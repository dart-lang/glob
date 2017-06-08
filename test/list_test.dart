// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@TestOn('vm')
import 'dart:async';
import 'dart:io';

import 'package:glob/glob.dart';
import 'package:glob/src/utils.dart';
import 'package:path/path.dart' as p;
import 'package:scheduled_test/descriptor.dart' as d;
import 'package:scheduled_test/scheduled_test.dart';
import 'package:test/test.dart' show TestOn;

String sandbox;

void main() {
  setUp(() {
    scheduleSandbox();

    d.dir("foo", [
      d.file("bar"),
      d.dir("baz", [d.file("bang"), d.file("qux")])
    ]).create();
  });

  group("list()", () {
    test("fails if the context doesn't match the system context", () {
      expect(new Glob("*", context: p.url).list, throwsStateError);
    });

    test("reports exceptions for non-existent case-sensitive directories", () {
      schedule(() {
        expect(new Glob("non/existent/**", caseSensitive: true).list().toList(),
            throwsA(new isInstanceOf<FileSystemException>()));
      });
    });

    test("reports exceptions for non-existent case-insensitive directories",
        () {
      schedule(() {
        expect(
            new Glob("non/existent/**", caseSensitive: false).list().toList(),
            throwsA(new isInstanceOf<FileSystemException>()));
      });
    });
  });

  group("listSync()", () {
    test("fails if the context doesn't match the system context", () {
      expect(new Glob("*", context: p.url).listSync, throwsStateError);
    });

    test("reports exceptions for non-existent case-sensitive directories", () {
      schedule(() {
        expect(new Glob("non/existent/**", caseSensitive: true).listSync,
            throwsA(new isInstanceOf<FileSystemException>()));
      });
    });

    test("reports exceptions for non-existent case-insensitive directories",
        () {
      schedule(() {
        expect(new Glob("non/existent/**", caseSensitive: false).listSync,
            throwsA(new isInstanceOf<FileSystemException>()));
      });
    });
  });

  group("when case-sensitive", () {
    test("lists literals case-sensitively", () {
      schedule(() {
        expect(new Glob("foo/BAZ/qux", caseSensitive: true).listSync,
            throwsA(new isInstanceOf<FileSystemException>()));
      });
    });

    test("lists ranges case-sensitively", () {
      schedule(() {
        expect(new Glob("foo/[BX][A-Z]z/qux", caseSensitive: true).listSync,
            throwsA(new isInstanceOf<FileSystemException>()));
      });
    });

    test("options preserve case-sensitivity", () {
      schedule(() {
        expect(new Glob("foo/{BAZ,ZAP}/qux", caseSensitive: true).listSync,
            throwsA(new isInstanceOf<FileSystemException>()));
      });
    });
  });

  syncAndAsync((list) {
    group("literals", () {
      test("lists a single literal", () {
        expect(list("foo/baz/qux"),
            completion(equals([p.join("foo", "baz", "qux")])));
      });

      test("lists a non-matching literal", () {
        expect(list("foo/baz/nothing"), completion(isEmpty));
      });
    });

    group("star", () {
      test("lists within filenames but not across directories", () {
        expect(
            list("foo/b*"),
            completion(
                unorderedEquals([p.join("foo", "bar"), p.join("foo", "baz")])));
      });

      test("lists the empy string", () {
        expect(list("foo/bar*"), completion(equals([p.join("foo", "bar")])));
      });
    });

    group("double star", () {
      test("lists within filenames", () {
        expect(
            list("foo/baz/**"),
            completion(unorderedEquals(
                [p.join("foo", "baz", "qux"), p.join("foo", "baz", "bang")])));
      });

      test("lists the empty string", () {
        expect(list("foo/bar**"), completion(equals([p.join("foo", "bar")])));
      });

      test("lists recursively", () {
        expect(
            list("foo/**"),
            completion(unorderedEquals([
              p.join("foo", "bar"),
              p.join("foo", "baz"),
              p.join("foo", "baz", "qux"),
              p.join("foo", "baz", "bang")
            ])));
      });

      test("combines with literals", () {
        expect(
            list("foo/ba**"),
            completion(unorderedEquals([
              p.join("foo", "bar"),
              p.join("foo", "baz"),
              p.join("foo", "baz", "qux"),
              p.join("foo", "baz", "bang")
            ])));
      });

      test("lists recursively in the middle of a glob", () {
        d.dir("deep", [
          d.dir("a", [
            d.dir("b", [
              d.dir("c", [d.file("d"), d.file("long-file")]),
              d.dir("long-dir", [d.file("x")])
            ])
          ])
        ]).create();

        expect(
            list("deep/**/?/?"),
            completion(unorderedEquals([
              p.join("deep", "a", "b", "c"),
              p.join("deep", "a", "b", "c", "d")
            ])));
      });
    });

    group("any char", () {
      test("matches a character", () {
        expect(
            list("foo/ba?"),
            completion(
                unorderedEquals([p.join("foo", "bar"), p.join("foo", "baz")])));
      });

      test("doesn't match a separator", () {
        expect(list("foo?bar"), completion(isEmpty));
      });
    });

    group("range", () {
      test("matches a range of characters", () {
        expect(
            list("foo/ba[a-z]"),
            completion(
                unorderedEquals([p.join("foo", "bar"), p.join("foo", "baz")])));
      });

      test("matches a specific list of characters", () {
        expect(
            list("foo/ba[rz]"),
            completion(
                unorderedEquals([p.join("foo", "bar"), p.join("foo", "baz")])));
      });

      test("doesn't match outside its range", () {
        expect(list("foo/ba[a-x]"),
            completion(unorderedEquals([p.join("foo", "bar")])));
      });

      test("doesn't match outside its specific list", () {
        expect(list("foo/ba[rx]"),
            completion(unorderedEquals([p.join("foo", "bar")])));
      });
    });

    test("the same file shouldn't be non-recursively listed multiple times",
        () {
      d.dir("multi", [
        d.dir("start-end", [d.file("file")])
      ]).create();

      expect(list("multi/{start-*/f*,*-end/*e}"),
          completion(equals([p.join("multi", "start-end", "file")])));
    });

    test("the same file shouldn't be recursively listed multiple times", () {
      d.dir("multi", [
        d.dir("a", [
          d.dir("b", [
            d.file("file"),
            d.dir("c", [d.file("file")])
          ]),
          d.dir("x", [
            d.dir("y", [d.file("file")])
          ])
        ])
      ]).create();

      expect(
          list("multi/{*/*/*/file,a/**/file}"),
          completion(unorderedEquals([
            p.join("multi", "a", "b", "file"),
            p.join("multi", "a", "b", "c", "file"),
            p.join("multi", "a", "x", "y", "file")
          ])));
    });

    group("with symlinks", () {
      setUp(() {
        schedule(() {
          return new Link(p.join(sandbox, "dir", "link"))
              .create(p.join(sandbox, "foo", "baz"), recursive: true);
        }, "symlink foo/baz to dir/link");
      });

      test("follows symlinks by default", () {
        expect(
            list("dir/**"),
            completion(unorderedEquals([
              p.join("dir", "link"),
              p.join("dir", "link", "bang"),
              p.join("dir", "link", "qux")
            ])));
      });

      test("doesn't follow symlinks with followLinks: false", () {
        expect(list("dir/**", followLinks: false),
            completion(equals([p.join("dir", "link")])));
      });

      test("shouldn't crash on broken symlinks", () {
        schedule(() {
          return new Directory(p.join(sandbox, "foo")).delete(recursive: true);
        });

        expect(list("dir/**"), completion(equals([p.join("dir", "link")])));
      });
    });

    test("always lists recursively with recursive: true", () {
      expect(
          list("foo", recursive: true),
          completion(unorderedEquals([
            "foo",
            p.join("foo", "bar"),
            p.join("foo", "baz"),
            p.join("foo", "baz", "qux"),
            p.join("foo", "baz", "bang")
          ])));
    });

    test("lists an absolute glob", () {
      expect(schedule(() {
        var pattern =
            separatorToForwardSlash(p.absolute(p.join(sandbox, 'foo/baz/**')));

        return list(pattern);
      }),
          completion(unorderedEquals(
              [p.join("foo", "baz", "bang"), p.join("foo", "baz", "qux")])));
    });

    // Regression test for #4.
    test("lists an absolute case-insensitive glob", () {
      expect(schedule(() {
        var pattern =
            separatorToForwardSlash(p.absolute(p.join(sandbox, 'foo/Baz/**')));

        return list(pattern, caseSensitive: false);
      }),
          completion(unorderedEquals(
              [p.join("foo", "baz", "bang"), p.join("foo", "baz", "qux")])));
    }, skip: "Broken by sdk#28015.");

    test("lists a subdirectory that sometimes exists", () {
      d.dir("top", [
        d.dir("dir1", [
          d.dir("subdir", [d.file("file")])
        ]),
        d.dir("dir2", [])
      ]).create();

      expect(list("top/*/subdir/**"),
          completion(equals([p.join("top", "dir1", "subdir", "file")])));
    });

    group("when case-insensitive", () {
      test("lists literals case-insensitively", () {
        expect(list("foo/baz/qux", caseSensitive: false),
            completion(equals([p.join("foo", "baz", "qux")])));
        expect(list("foo/BAZ/qux", caseSensitive: false),
            completion(equals([p.join("foo", "baz", "qux")])));
      });

      test("lists ranges case-insensitively", () {
        expect(list("foo/[bx][a-z]z/qux", caseSensitive: false),
            completion(equals([p.join("foo", "baz", "qux")])));
        expect(list("foo/[BX][A-Z]z/qux", caseSensitive: false),
            completion(equals([p.join("foo", "baz", "qux")])));
      });

      test("options preserve case-insensitivity", () {
        // expect(list("foo/{bar,baz}/qux", caseSensitive: false),
        //     completion(equals([p.join("foo", "baz", "qux")])));
        expect(list("foo/{BAR,BAZ}/qux", caseSensitive: false),
            completion(equals([p.join("foo", "baz", "qux")])));
      });
    });
  });
}

typedef Future<List<String>> ListFn(String glob,
    {bool recursive, bool followLinks, bool caseSensitive});

/// Runs [callback] in two groups with two values of [listFn]: one that uses
/// [Glob.list], one that uses [Glob.listSync].
void syncAndAsync(callback(ListFn listFn)) {
  group("async", () {
    callback((pattern, {recursive: false, followLinks: true, caseSensitive}) {
      return schedule(() {
        var glob = new Glob(pattern,
            recursive: recursive, caseSensitive: caseSensitive);

        return glob
            .list(root: sandbox, followLinks: followLinks)
            .map((entity) => p.relative(entity.path, from: sandbox))
            .toList();
      }, 'listing $pattern');
    });
  });

  group("sync", () {
    callback((pattern, {recursive: false, followLinks: true, caseSensitive}) {
      return schedule(() {
        var glob = new Glob(pattern,
            recursive: recursive, caseSensitive: caseSensitive);

        return glob
            .listSync(root: sandbox, followLinks: followLinks)
            .map((entity) => p.relative(entity.path, from: sandbox))
            .toList();
      }, 'listing $pattern');
    });
  });
}

void scheduleSandbox() {
  schedule(() {
    return Directory.systemTemp.createTemp('glob_').then((dir) {
      sandbox = dir.path;
      d.defaultRoot = sandbox;
    });
  }, 'creating sandbox');

  currentSchedule.onComplete.schedule(() {
    d.defaultRoot = null;
    if (sandbox == null) return null;
    var oldSandbox = sandbox;
    sandbox = null;
    return new Directory(oldSandbox).delete(recursive: true);
  });
}
