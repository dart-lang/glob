// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import 'package:async/async.dart';
import 'package:path/path.dart' as p;
import 'package:pedantic/pedantic.dart';

import 'ast.dart';
import 'io.dart';
import 'utils.dart';

/// The errno for a file or directory not existing on Mac and Linux.
const _enoent = 2;

/// Another errno we see on Windows when trying to list a non-existent
/// directory.
const _enoentWin = 3;

/// A structure built from a glob that efficiently lists filesystem entities
/// that match that glob.
///
/// This structure is designed to list the minimal number of physical
/// directories necessary to find everything that matches the glob. For example,
/// for the glob `foo/{bar,baz}/*`, there's no need to list the working
/// directory or even `foo/`; only `foo/bar` and `foo/baz` should be listed.
///
/// This works by creating a tree of [_ListTreeNode]s, each of which corresponds
/// to a single of directory nesting in the source glob. Each node has child
/// nodes associated with globs ([_ListTreeNode.children]), as well as its own
/// glob ([_ListTreeNode._validator]) that indicates which entities within that
/// node's directory should be returned.
///
/// For example, the glob `foo/{*.dart,b*/*.txt}` creates the following tree:
///
///     .
///     '-- "foo" (validator: "*.dart")
///         '-- "b*" (validator: "*.txt"
///
/// If a node doesn't have a validator, we know we don't have to list it
/// explicitly.
///
/// Nodes can also be marked as "recursive", which means they need to be listed
/// recursively (usually to support `**`). In this case, they will have no
/// children; instead, their validator will just encompass the globs that would
/// otherwise be in their children. For example, the glob
/// `foo/{**.dart,bar/*.txt}` creates a recursive node for `foo` with the
/// validator `**.dart,bar/*.txt`.
///
/// If the glob contains multiple filesystem roots (e.g. `{C:/,D:/}*.dart`),
/// each root will have its own tree of nodes. Relative globs use `.` as their
/// root instead.
class ListTree {
  /// A map from filesystem roots to the list tree for those roots.
  ///
  /// A relative glob will use `.` as its root.
  final _trees = Map<String, _ListTreeNode>();

  /// Whether paths listed might overlap.
  ///
  /// If they do, we need to filter out overlapping paths.
  bool _canOverlap;

  ListTree(AstNode glob) {
    // The first step in constructing a tree from the glob is to simplify the
    // problem by eliminating options. [glob.flattenOptions] bubbles all options
    // (and certain ranges) up to the top level of the glob so we can deal with
    // them one at a time.
    var options = glob.flattenOptions();

    for (var option in options.options) {
      // Since each option doesn't include its own options, we can safely split
      // it into path components.
      var components = option.split(p.context);
      var firstNode = components.first.nodes.first;
      var root = '.';

      // Determine the root for this option, if it's absolute. If it's not, the
      // root's just ".".
      if (firstNode is LiteralNode) {
        var text = firstNode.text;
        if (Platform.isWindows) text.replaceAll("/", "\\");
        if (p.isAbsolute(text)) {
          // If the path is absolute, the root should be the only thing in the
          // first component.
          assert(components.first.nodes.length == 1);
          root = firstNode.text;
          components.removeAt(0);
        }
      }

      _addGlob(root, components);
    }

    _canOverlap = _computeCanOverlap();
  }

  /// Add the glob represented by [components] to the tree under [root].
  void _addGlob(String root, List<SequenceNode> components) {
    // The first [parent] represents the root directory itself. It may be null
    // here if this is the first option with this particular [root]. If so,
    // we'll create it below.
    //
    // As we iterate through [components], [parent] will be set to
    // progressively more nested nodes.
    var parent = _trees[root];
    for (var i = 0; i < components.length; i++) {
      var component = components[i];
      var recursive = component.nodes.any((node) => node is DoubleStarNode);
      var complete = i == components.length - 1;

      // If the parent node for this level of nesting already exists, the new
      // option will be added to it as additional validator options and/or
      // additional children.
      //
      // If the parent doesn't exist, we'll create it in one of the else
      // clauses below.
      if (parent != null) {
        if (parent.isRecursive || recursive) {
          // If [component] is recursive, mark [parent] as recursive. This
          // will cause all of its children to be folded into its validator.
          // If [parent] was already recursive, this is a no-op.
          parent.makeRecursive();

          // Add [component] and everything nested beneath it as an option to
          // [parent]. Since [parent] is recursive, it will recursively list
          // everything beneath it and filter them with one big glob.
          parent.addOption(_join(components.sublist(i)));
          return;
        } else if (complete) {
          // If [component] is the last component, add it to [parent]'s
          // validator but not to its children.
          parent.addOption(component);
        } else {
          // On the other hand if there are more components, add [component]
          // to [parent]'s children and not its validator. Since we process
          // each option's components separately, the same component is never
          // both a validator and a child.
          if (!parent.children.containsKey(component)) {
            parent.children[component] = _ListTreeNode();
          }
          parent = parent.children[component];
        }
      } else if (recursive) {
        _trees[root] = _ListTreeNode.recursive(_join(components.sublist(i)));
        return;
      } else if (complete) {
        _trees[root] = _ListTreeNode()..addOption(component);
      } else {
        _trees[root] = _ListTreeNode();
        _trees[root].children[component] = _ListTreeNode();
        parent = _trees[root].children[component];
      }
    }
  }

  /// Computes the value for [_canOverlap].
  bool _computeCanOverlap() {
    // If this can list a relative path and an absolute path, the former may be
    // contained within the latter.
    if (_trees.length > 1 && _trees.containsKey('.')) return true;

    // Otherwise, this can only overlap if the tree beneath any given root could
    // overlap internally.
    return _trees.values.any((node) => node.canOverlap);
  }

  /// List all entities that match this glob beneath [root].
  Stream<FileSystemEntity> list({String root, bool followLinks = true}) {
    if (root == null) root = '.';
    var group = StreamGroup<FileSystemEntity>();
    for (var rootDir in _trees.keys) {
      var dir = rootDir == '.' ? root : rootDir;
      group.add(_trees[rootDir].list(dir, followLinks: followLinks));
    }
    group.close();

    if (!_canOverlap) return group.stream;

    // TODO(nweiz): Rather than filtering here, avoid double-listing directories
    // in the first place.
    var seen = Set();
    return group.stream.where((entity) {
      if (seen.contains(entity.path)) return false;
      seen.add(entity.path);
      return true;
    });
  }

  /// Synchronosuly list all entities that match this glob beneath [root].
  List<FileSystemEntity> listSync({String root, bool followLinks = true}) {
    if (root == null) root = '.';

    var result = _trees.keys.expand((rootDir) {
      var dir = rootDir == '.' ? root : rootDir;
      return _trees[rootDir].listSync(dir, followLinks: followLinks);
    });

    if (!_canOverlap) return result.toList();

    // TODO(nweiz): Rather than filtering here, avoid double-listing directories
    // in the first place.
    var seen = Set<String>();
    return result.where((entity) {
      if (seen.contains(entity.path)) return false;
      seen.add(entity.path);
      return true;
    }).toList();
  }
}

/// A single node in a [ListTree].
class _ListTreeNode {
  /// This node's child nodes, by their corresponding globs.
  ///
  /// Each child node will only be listed on directories that match its glob.
  ///
  /// This may be `null`, indicating that this node should be listed
  /// recursively.
  Map<SequenceNode, _ListTreeNode> children;

  /// This node's validator.
  ///
  /// This determines which entities will ultimately be emitted when [list] is
  /// called.
  OptionsNode _validator;

  /// Whether this node is recursive.
  ///
  /// A recursive node has no children and is listed recursively.
  bool get isRecursive => children == null;

  bool get _caseSensitive {
    if (_validator != null) return _validator.caseSensitive;
    if (children == null) return true;
    if (children.isEmpty) return true;
    return children.keys.first.caseSensitive;
  }

  /// Whether this node doesn't itself need to be listed.
  ///
  /// If a node has no validator and all of its children are literal filenames,
  /// there's no need to list its contents. We can just directly traverse into
  /// its children.
  bool get _isIntermediate {
    if (_validator != null) return false;
    return children.keys.every((sequence) =>
        sequence.nodes.length == 1 && sequence.nodes.first is LiteralNode);
  }

  /// Returns whether listing this node might return overlapping results.
  bool get canOverlap {
    // A recusive node can never overlap with itself, because it will only ever
    // involve a single call to [Directory.list] that's then filtered with
    // [_validator].
    if (isRecursive) return false;

    // If there's more than one child node and at least one of the children is
    // dynamic (that is, matches more than just a literal string), there may be
    // overlap.
    if (children.length > 1) {
      // Case-insensitivity means that even literals may match multiple entries.
      if (!_caseSensitive) return true;

      if (children.keys.any((sequence) =>
          sequence.nodes.length > 1 || sequence.nodes.single is! LiteralNode)) {
        return true;
      }
    }

    return children.values.any((node) => node.canOverlap);
  }

  /// Creates a node with no children and no validator.
  _ListTreeNode()
      : children = Map<SequenceNode, _ListTreeNode>(),
        _validator = null;

  /// Creates a recursive node the given [validator].
  _ListTreeNode.recursive(SequenceNode validator)
      : children = null,
        _validator =
            OptionsNode([validator], caseSensitive: validator.caseSensitive);

  /// Transforms this into recursive node, folding all its children into its
  /// validator.
  void makeRecursive() {
    if (isRecursive) return;
    _validator = OptionsNode(children.keys.map((sequence) {
      var child = children[sequence];
      child.makeRecursive();
      return _join([sequence, child._validator]);
    }), caseSensitive: _caseSensitive);
    children = null;
  }

  /// Adds [validator] to this node's existing validator.
  void addOption(SequenceNode validator) {
    if (_validator == null) {
      _validator =
          OptionsNode([validator], caseSensitive: validator.caseSensitive);
    } else {
      _validator.options.add(validator);
    }
  }

  /// Lists all entities within [dir] matching this node or its children.
  ///
  /// This may return duplicate entities. These will be filtered out in
  /// [ListTree.list].
  Stream<FileSystemEntity> list(String dir, {bool followLinks = true}) {
    if (isRecursive) {
      return Directory(dir)
          .list(recursive: true, followLinks: followLinks)
          .where((entity) => _matches(p.relative(entity.path, from: dir)));
    }

    // Don't spawn extra [Directory.list] calls when we already know exactly
    // which subdirectories we're interested in.
    if (_isIntermediate && _caseSensitive) {
      var resultGroup = StreamGroup<FileSystemEntity>();
      children.forEach((sequence, child) {
        resultGroup.add(child.list(
            p.join(dir, (sequence.nodes.single as LiteralNode).text),
            followLinks: followLinks));
      });
      resultGroup.close();
      return resultGroup.stream;
    }

    return StreamCompleter.fromFuture(() async {
      var entities =
          await Directory(dir).list(followLinks: followLinks).toList();
      await _validateIntermediateChildrenAsync(dir, entities);

      var resultGroup = StreamGroup<FileSystemEntity>();
      var resultController = StreamController<FileSystemEntity>(sync: true);
      unawaited(resultGroup.add(resultController.stream));
      for (var entity in entities) {
        var basename = p.relative(entity.path, from: dir);
        if (_matches(basename)) resultController.add(entity);

        children.forEach((sequence, child) {
          if (entity is! Directory) return;
          if (!sequence.matches(basename)) return;
          var stream = child
              .list(p.join(dir, basename), followLinks: followLinks)
              .handleError((_) {}, test: (error) {
            // Ignore errors from directories not existing. We do this here so
            // that we only ignore warnings below wild cards. For example, the
            // glob "foo/bar/*/baz" should fail if "foo/bar" doesn't exist but
            // succeed if "foo/bar/qux/baz" doesn't exist.
            return error is FileSystemException &&
                (error.osError.errorCode == _enoent ||
                    error.osError.errorCode == _enoentWin);
          });
          resultGroup.add(stream);
        });
      }
      unawaited(resultController.close());
      unawaited(resultGroup.close());
      return resultGroup.stream;
    }());
  }

  /// If this is a case-insensitive list, validates that all intermediate
  /// children (according to [_isIntermediate]) match at least one entity in
  /// [entities].
  ///
  /// This ensures that listing "foo/bar/*" fails on case-sensitive systems if
  /// "foo/bar" doesn't exist.
  Future _validateIntermediateChildrenAsync(
      String dir, List<FileSystemEntity> entities) async {
    if (_caseSensitive) return;

    for (var sequence in children.keys) {
      var child = children[sequence];
      if (!child._isIntermediate) continue;
      if (entities.any(
          (entity) => sequence.matches(p.relative(entity.path, from: dir)))) {
        continue;
      }

      // We know this will fail, we're just doing it to force dart:io to emit
      // the exception it would if we were listing case-sensitively.
      await child
          .list(p.join(dir, (sequence.nodes.single as LiteralNode).text))
          .toList();
    }
  }

  /// Synchronously lists all entities within [dir] matching this node or its
  /// children.
  ///
  /// This may return duplicate entities. These will be filtered out in
  /// [ListTree.listSync].
  Iterable<FileSystemEntity> listSync(String dir, {bool followLinks = true}) {
    if (isRecursive) {
      return Directory(dir)
          .listSync(recursive: true, followLinks: followLinks)
          .where((entity) => _matches(p.relative(entity.path, from: dir)));
    }

    // Don't spawn extra [Directory.listSync] calls when we already know exactly
    // which subdirectories we're interested in.
    if (_isIntermediate && _caseSensitive) {
      return children.keys.expand((sequence) {
        return children[sequence].listSync(
            p.join(dir, (sequence.nodes.single as LiteralNode).text),
            followLinks: followLinks);
      });
    }

    var entities = Directory(dir).listSync(followLinks: followLinks);
    _validateIntermediateChildrenSync(dir, entities);

    return entities.expand((entity) {
      var entities = <FileSystemEntity>[];
      var basename = p.relative(entity.path, from: dir);
      if (_matches(basename)) entities.add(entity);
      if (entity is! Directory) return entities;

      entities.addAll(children.keys
          .where((sequence) => sequence.matches(basename))
          .expand((sequence) {
        try {
          return children[sequence]
              .listSync(p.join(dir, basename), followLinks: followLinks)
              .toList();
        } on FileSystemException catch (error) {
          // Ignore errors from directories not existing. We do this here so
          // that we only ignore warnings below wild cards. For example, the
          // glob "foo/bar/*/baz" should fail if "foo/bar" doesn't exist but
          // succeed if "foo/bar/qux/baz" doesn't exist.
          if (error.osError.errorCode == _enoent ||
              error.osError.errorCode == _enoentWin) {
            return const [];
          } else {
            rethrow;
          }
        }
      }));

      return entities;
    });
  }

  /// If this is a case-insensitive list, validates that all intermediate
  /// children (according to [_isIntermediate]) match at least one entity in
  /// [entities].
  ///
  /// This ensures that listing "foo/bar/*" fails on case-sensitive systems if
  /// "foo/bar" doesn't exist.
  void _validateIntermediateChildrenSync(
      String dir, List<FileSystemEntity> entities) {
    if (_caseSensitive) return;

    children.forEach((sequence, child) {
      if (!child._isIntermediate) return;
      if (entities.any(
          (entity) => sequence.matches(p.relative(entity.path, from: dir)))) {
        return;
      }

      // If there are no [entities] that match [sequence], manually list the
      // directory to force `dart:io` to throw an error. This allows us to
      // ensure that listing "foo/bar/*" fails on case-sensitive systems if
      // "foo/bar" doesn't exist.
      child.listSync(p.join(dir, (sequence.nodes.single as LiteralNode).text));
    });
  }

  /// Returns whether the native [path] matches [_validator].
  bool _matches(String path) {
    if (_validator == null) return false;
    return _validator.matches(toPosixPath(p.context, path));
  }

  String toString() => "($_validator) $children";
}

/// Joins each [components] into a new glob where each component is separated by
/// a path separator.
SequenceNode _join(Iterable<AstNode> components) {
  var componentsList = components.toList();
  var first = componentsList.removeAt(0);
  var nodes = [first];
  for (var component in componentsList) {
    nodes.add(LiteralNode('/', caseSensitive: first.caseSensitive));
    nodes.add(component);
  }
  return SequenceNode(nodes, caseSensitive: first.caseSensitive);
}
