// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:glob/glob.dart';
import 'package:glob/src/utils.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

const RAW_ASCII_WITHOUT_SLASH = "\t\n\r !\"#\$%&'()*+`-.0123456789:;<=>?@ABCDEF"
    "GHIJKLMNOPQRSTUVWXYZ[]^_`abcdefghijklmnopqrstuvwxyz{|}~";

// URL-encode the path for a URL context.
final asciiWithoutSlash = p.style == p.Style.url
    ? Uri.encodeFull(RAW_ASCII_WITHOUT_SLASH)
    : RAW_ASCII_WITHOUT_SLASH;

void main() {
  test("literals match exactly", () {
    expect("foo", contains(new Glob("foo")));
    expect("foo/bar", contains(new Glob("foo/bar")));
    expect("foo*", contains(new Glob(r"foo\*")));
  });

  test("backslashes match nothing on Windows", () {
    expect(
        r"foo\bar", isNot(contains(new Glob(r"foo\\bar", context: p.windows))));
  });

  group("star", () {
    test("matches non-separator characters", () {
      var glob = new Glob("*");
      expect(asciiWithoutSlash, contains(glob));
    });

    test("matches the empty string", () {
      expect("foo", contains(new Glob("foo*")));
      expect("", contains(new Glob("*")));
    });

    test("doesn't match separators", () {
      var glob = new Glob("*");
      expect("foo/bar", isNot(contains(glob)));
    });
  });

  group("double star", () {
    test("matches non-separator characters", () {
      var glob = new Glob("**");
      expect(asciiWithoutSlash, contains(glob));
    });

    test("matches the empty string", () {
      var glob = new Glob("foo**");
      expect("foo", contains(glob));
    });

    test("matches any level of nesting", () {
      var glob = new Glob("**");
      expect("a", contains(glob));
      expect("a/b/c/d/e/f", contains(glob));
    });

    test("doesn't match unresolved dot dots", () {
      expect("../foo/bar", isNot(contains(new Glob("**"))));
    });

    test("matches entities containing dot dots", () {
      expect("..foo/bar", contains(new Glob("**")));
      expect("foo../bar", contains(new Glob("**")));
      expect("foo/..bar", contains(new Glob("**")));
      expect("foo/bar..", contains(new Glob("**")));
    });
  });

  group("any char", () {
    test("matches any non-separator character", () {
      var glob = new Glob("foo?");
      for (var char in RAW_ASCII_WITHOUT_SLASH.split('')) {
        if (p.style == p.Style.url) char = Uri.encodeFull(char);
        expect("foo$char", contains(glob));
      }
    });

    test("doesn't match a separator", () {
      expect("foo/bar", isNot(contains(new Glob("foo?bar"))));
    });
  });

  group("range", () {
    test("can match individual characters", () {
      var glob = new Glob("foo[a<.*]");
      expect("fooa", contains(glob));
      expect("foo<", contains(glob));
      expect("foo.", contains(glob));
      expect("foo*", contains(glob));
      expect("foob", isNot(contains(glob)));
      expect("foo>", isNot(contains(glob)));
    });

    test("can match a range of characters", () {
      var glob = new Glob("foo[a-z]");
      expect("fooa", contains(glob));
      expect("foon", contains(glob));
      expect("fooz", contains(glob));
      expect("foo`", isNot(contains(glob)));
      expect("foo{", isNot(contains(glob)));
    });

    test("can match multiple ranges of characters", () {
      var glob = new Glob("foo[a-zA-Z]");
      expect("fooa", contains(glob));
      expect("foon", contains(glob));
      expect("fooz", contains(glob));
      expect("fooA", contains(glob));
      expect("fooN", contains(glob));
      expect("fooZ", contains(glob));
      expect("foo?", isNot(contains(glob)));
      expect("foo{", isNot(contains(glob)));
    });

    test("can match individual characters and ranges of characters", () {
      var glob = new Glob("foo[a-z_A-Z]");
      expect("fooa", contains(glob));
      expect("foon", contains(glob));
      expect("fooz", contains(glob));
      expect("fooA", contains(glob));
      expect("fooN", contains(glob));
      expect("fooZ", contains(glob));
      expect("foo_", contains(glob));
      expect("foo?", isNot(contains(glob)));
      expect("foo{", isNot(contains(glob)));
    });

    test("can be negated", () {
      var glob = new Glob("foo[^a<.*]");
      expect("fooa", isNot(contains(glob)));
      expect("foo<", isNot(contains(glob)));
      expect("foo.", isNot(contains(glob)));
      expect("foo*", isNot(contains(glob)));
      expect("foob", contains(glob));
      expect("foo>", contains(glob));
    });

    test("never matches separators", () {
      // "\t-~" contains "/".
      expect("foo/bar", isNot(contains(new Glob("foo[\t-~]bar"))));
      expect("foo/bar", isNot(contains(new Glob("foo[^a]bar"))));
    });

    test("allows dangling -", () {
      expect("-", contains(new Glob(r"[-]")));

      var glob = new Glob(r"[a-]");
      expect("-", contains(glob));
      expect("a", contains(glob));

      glob = new Glob(r"[-b]");
      expect("-", contains(glob));
      expect("b", contains(glob));
    });

    test("allows multiple -s", () {
      expect("-", contains(new Glob(r"[--]")));
      expect("-", contains(new Glob(r"[---]")));

      var glob = new Glob(r"[--a]");
      expect("-", contains(glob));
      expect("a", contains(glob));
    });

    test("allows negated /", () {
      expect("foo-bar", contains(new Glob("foo[^/]bar")));
    });

    test("doesn't choke on RegExp-active characters", () {
      var glob = new Glob(r"foo[\]].*");
      expect("foobar", isNot(contains(glob)));
      expect("foo].*", contains(glob));
    });
  });

  group("options", () {
    test("match if any of the options match", () {
      var glob = new Glob("foo/{bar,baz,bang}");
      expect("foo/bar", contains(glob));
      expect("foo/baz", contains(glob));
      expect("foo/bang", contains(glob));
      expect("foo/qux", isNot(contains(glob)));
    });

    test("can contain nested operators", () {
      var glob = new Glob("foo/{ba?,*az,ban{g,f}}");
      expect("foo/bar", contains(glob));
      expect("foo/baz", contains(glob));
      expect("foo/bang", contains(glob));
      expect("foo/qux", isNot(contains(glob)));
    });

    test("can conditionally match separators", () {
      var glob = new Glob("foo/{bar,baz/bang}");
      expect("foo/bar", contains(glob));
      expect("foo/baz/bang", contains(glob));
      expect("foo/baz", isNot(contains(glob)));
      expect("foo/bar/bang", isNot(contains(glob)));
    });
  });

  group("normalization", () {
    test("extra slashes are ignored", () {
      expect("foo//bar", contains(new Glob("foo/bar")));
      expect("foo/", contains(new Glob("*")));
    });

    test("dot directories are ignored", () {
      expect("foo/./bar", contains(new Glob("foo/bar")));
      expect("foo/.", contains(new Glob("foo")));
    });

    test("dot dot directories are resolved", () {
      expect("foo/../bar", contains(new Glob("bar")));
      expect("../foo/bar", contains(new Glob("../foo/bar")));
      expect("foo/../../bar", contains(new Glob("../bar")));
    });

    test("Windows separators are converted in a Windows context", () {
      expect(r"foo\bar", contains(new Glob("foo/bar", context: p.windows)));
      expect(r"foo\bar/baz",
          contains(new Glob("foo/bar/baz", context: p.windows)));
    });
  });

  test("an absolute path can be matched by a relative glob", () {
    var path = p.absolute('foo/bar');
    expect(path, contains(new Glob("foo/bar")));
  });

  test("a relative path can be matched by an absolute glob", () {
    var pattern = separatorToForwardSlash(p.absolute('foo/bar'));
    expect('foo/bar', contains(new Glob(pattern)));
  }, testOn: 'vm');

  group("with recursive: true", () {
    var glob = new Glob("foo/bar", recursive: true);

    test("still matches basic files", () {
      expect("foo/bar", contains(glob));
    });

    test("matches subfiles", () {
      expect("foo/bar/baz", contains(glob));
      expect("foo/bar/baz/bang", contains(glob));
    });

    test("doesn't match suffixes", () {
      expect("foo/barbaz", isNot(contains(glob)));
      expect("foo/barbaz/bang", isNot(contains(glob)));
    });
  });

  test("absolute POSIX paths", () {
    expect("/foo/bar", contains(new Glob("/foo/bar", context: p.posix)));
    expect("/foo/bar", isNot(contains(new Glob("**", context: p.posix))));
    expect("/foo/bar", contains(new Glob("/**", context: p.posix)));
  });

  test("absolute Windows paths", () {
    expect(r"C:\foo\bar", contains(new Glob("C:/foo/bar", context: p.windows)));
    expect(r"C:\foo\bar", isNot(contains(new Glob("**", context: p.windows))));
    expect(r"C:\foo\bar", contains(new Glob("C:/**", context: p.windows)));

    expect(r"\\foo\bar\baz",
        contains(new Glob("//foo/bar/baz", context: p.windows)));
    expect(
        r"\\foo\bar\baz", isNot(contains(new Glob("**", context: p.windows))));
    expect(r"\\foo\bar\baz", contains(new Glob("//**", context: p.windows)));
    expect(
        r"\\foo\bar\baz", contains(new Glob("//foo/**", context: p.windows)));
  });

  test("absolute URL paths", () {
    expect(r"http://foo.com/bar",
        contains(new Glob("http://foo.com/bar", context: p.url)));
    expect(
        r"http://foo.com/bar", isNot(contains(new Glob("**", context: p.url))));
    expect(
        r"http://foo.com/bar", contains(new Glob("http://**", context: p.url)));
    expect(r"http://foo.com/bar",
        contains(new Glob("http://foo.com/**", context: p.url)));

    expect("/foo/bar", contains(new Glob("/foo/bar", context: p.url)));
    expect("/foo/bar", isNot(contains(new Glob("**", context: p.url))));
    expect("/foo/bar", contains(new Glob("/**", context: p.url)));
  });

  group("when case-sensitive", () {
    test("literals match case-sensitively", () {
      expect("foo", contains(new Glob("foo", caseSensitive: true)));
      expect("FOO", isNot(contains(new Glob("foo", caseSensitive: true))));
      expect("foo", isNot(contains(new Glob("FOO", caseSensitive: true))));
    });

    test("ranges match case-sensitively", () {
      expect("foo", contains(new Glob("[fx][a-z]o", caseSensitive: true)));
      expect(
          "FOO", isNot(contains(new Glob("[fx][a-z]o", caseSensitive: true))));
      expect(
          "foo", isNot(contains(new Glob("[FX][A-Z]O", caseSensitive: true))));
    });

    test("sequences preserve case-sensitivity", () {
      expect("foo/bar", contains(new Glob("foo/bar", caseSensitive: true)));
      expect(
          "FOO/BAR", isNot(contains(new Glob("foo/bar", caseSensitive: true))));
      expect(
          "foo/bar", isNot(contains(new Glob("FOO/BAR", caseSensitive: true))));
    });

    test("options preserve case-sensitivity", () {
      expect("foo", contains(new Glob("{foo,bar}", caseSensitive: true)));
      expect(
          "FOO", isNot(contains(new Glob("{foo,bar}", caseSensitive: true))));
      expect(
          "foo", isNot(contains(new Glob("{FOO,BAR}", caseSensitive: true))));
    });
  });

  group("when case-insensitive", () {
    test("literals match case-insensitively", () {
      expect("foo", contains(new Glob("foo", caseSensitive: false)));
      expect("FOO", contains(new Glob("foo", caseSensitive: false)));
      expect("foo", contains(new Glob("FOO", caseSensitive: false)));
    });

    test("ranges match case-insensitively", () {
      expect("foo", contains(new Glob("[fx][a-z]o", caseSensitive: false)));
      expect("FOO", contains(new Glob("[fx][a-z]o", caseSensitive: false)));
      expect("foo", contains(new Glob("[FX][A-Z]O", caseSensitive: false)));
    });

    test("sequences preserve case-insensitivity", () {
      expect("foo/bar", contains(new Glob("foo/bar", caseSensitive: false)));
      expect("FOO/BAR", contains(new Glob("foo/bar", caseSensitive: false)));
      expect("foo/bar", contains(new Glob("FOO/BAR", caseSensitive: false)));
    });

    test("options preserve case-insensitivity", () {
      expect("foo", contains(new Glob("{foo,bar}", caseSensitive: false)));
      expect("FOO", contains(new Glob("{foo,bar}", caseSensitive: false)));
      expect("foo", contains(new Glob("{FOO,BAR}", caseSensitive: false)));
    });
  });
}
