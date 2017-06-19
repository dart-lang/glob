// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:glob/glob.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group("Glob.quote()", () {
    test("quotes all active characters", () {
      expect(Glob.quote("*{[?\\}],-"), equals(r"\*\{\[\?\\\}\]\,\-"));
    });

    test("doesn't quote inactive characters", () {
      expect(Glob.quote("abc~`_+="), equals("abc~`_+="));
    });
  });

  group('Glob.union()', () {
    test('returns the union of both globs', () {
      var globA = new Glob('a*');
      var globB = new Glob('b*');
      var result = globA.union(globB);
      expect(result.matches('anteater'), isTrue);
      expect(result.matches('baterang'), isTrue);
      expect(result.matches('caboose'), isFalse);
    });

    test('throws for invalid configuration', () {
      var globA = new Glob('a*', caseSensitive: true);
      var globB = new Glob('b*', caseSensitive: false);
      expect(() => globA.union(globB), throwsUnsupportedError);

      globA = new Glob('a*', context: p.windows);
      globB = new Glob('b*', context: p.url);
      expect(() => globA.union(globB), throwsUnsupportedError);
    });
  });

  group("Glob.matches()", () {
    test("returns whether the path matches the glob", () {
      var glob = new Glob("foo*");
      expect(glob.matches("foobar"), isTrue);
      expect(glob.matches("baz"), isFalse);
    });

    test("only matches the entire path", () {
      var glob = new Glob("foo");
      expect(glob.matches("foo/bar"), isFalse);
      expect(glob.matches("bar/foo"), isFalse);
    });
  });

  group("Glob.matchAsPrefix()", () {
    test("returns a match if the path matches the glob", () {
      var glob = new Glob("foo*");
      expect(glob.matchAsPrefix("foobar"), new isInstanceOf<Match>());
      expect(glob.matchAsPrefix("baz"), isNull);
    });

    test("returns null for start > 0", () {
      var glob = new Glob("*");
      expect(glob.matchAsPrefix("foobar", 1), isNull);
    });
  });

  group("Glob.allMatches()", () {
    test("returns a single match if the path matches the glob", () {
      var matches = new Glob("foo*").allMatches("foobar");
      expect(matches, hasLength(1));
      expect(matches.first, new isInstanceOf<Match>());
    });

    test("returns an empty list if the path doesn't match the glob", () {
      expect(new Glob("foo*").allMatches("baz"), isEmpty);
    });

    test("returns no matches for start > 0", () {
      var glob = new Glob("*");
      expect(glob.allMatches("foobar", 1), isEmpty);
    });
  });

  group("GlobMatch", () {
    var glob = new Glob("foo*");
    var match = glob.matchAsPrefix("foobar");

    test("returns the string as input", () {
      expect(match.input, equals("foobar"));
    });

    test("returns the glob as the pattern", () {
      expect(match.pattern, equals(glob));
    });

    test("returns the span of the string for start and end", () {
      expect(match.start, equals(0));
      expect(match.end, equals("foobar".length));
    });

    test("has a single group that contains the whole string", () {
      expect(match.groupCount, equals(0));
      expect(match[0], equals("foobar"));
      expect(match.group(0), equals("foobar"));
      expect(match.groups([0]), equals(["foobar"]));
    });

    test("throws a range error for an invalid group", () {
      expect(() => match[1], throwsRangeError);
      expect(() => match[-1], throwsRangeError);
      expect(() => match.group(1), throwsRangeError);
      expect(() => match.groups([1]), throwsRangeError);
    });
  });

  test("globs are case-sensitive by default for Posix and URL contexts", () {
    expect("foo", contains(new Glob("foo", context: p.posix)));
    expect("FOO", isNot(contains(new Glob("foo", context: p.posix))));
    expect("foo", isNot(contains(new Glob("FOO", context: p.posix))));

    expect("foo", contains(new Glob("foo", context: p.url)));
    expect("FOO", isNot(contains(new Glob("foo", context: p.url))));
    expect("foo", isNot(contains(new Glob("FOO", context: p.url))));
  });

  test("globs are case-insensitive by default for Windows contexts", () {
    expect("foo", contains(new Glob("foo", context: p.windows)));
    expect("FOO", contains(new Glob("foo", context: p.windows)));
    expect("foo", contains(new Glob("FOO", context: p.windows)));
  });
}
