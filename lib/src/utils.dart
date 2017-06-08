// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:path/path.dart' as p;

/// A range from [min] to [max], inclusive.
class Range {
  /// The minimum value included by the range.
  final int min;

  /// The maximum value included by the range.
  final int max;

  /// Whether this range covers only a single number.
  bool get isSingleton => min == max;

  Range(this.min, this.max);

  /// Returns a range that covers only [value].
  Range.singleton(int value) : this(value, value);

  /// Whether [this] contains [value].
  bool contains(int value) => value >= min && value <= max;

  bool operator ==(Object other) =>
      other is Range && other.min == min && other.max == max;

  int get hashCode => 3 * min + 7 * max;
}

/// An implementation of [Match] constructed by [Glob]s.
class GlobMatch implements Match {
  final String input;
  final Pattern pattern;
  final int start = 0;

  int get end => input.length;
  int get groupCount => 0;

  GlobMatch(this.input, this.pattern);

  String operator [](int group) => this.group(group);

  String group(int group) {
    if (group != 0) throw new RangeError.range(group, 0, 0);
    return input;
  }

  List<String> groups(List<int> groupIndices) =>
      groupIndices.map((index) => group(index)).toList();
}

final _quote = new RegExp(r"[+*?{}|[\]\\().^$-]");

/// Returns [contents] with characters that are meaningful in regular
/// expressions backslash-escaped.
String regExpQuote(String contents) =>
    contents.replaceAllMapped(_quote, (char) => "\\${char[0]}");

/// Returns [path] with all its separators replaced with forward slashes.
///
/// This is useful when converting from Windows paths to globs.
String separatorToForwardSlash(String path) {
  if (p.style != p.Style.windows) return path;
  return path.replaceAll('\\', '/');
}

/// Returns [path] which follows [context] converted to the POSIX format that
/// globs match against.
String toPosixPath(p.Context context, String path) {
  if (context.style == p.Style.windows) return path.replaceAll('\\', '/');
  if (context.style == p.Style.url) return Uri.decodeFull(path);
  return path;
}
