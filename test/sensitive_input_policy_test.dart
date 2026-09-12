import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:flutter_test/flutter_test.dart';

class _InputPolicy extends RecursiveAstVisitor<void> {
  final String path;
  int fields = 0;

  _InputPolicy(this.path);

  String? _constructor(AstNode node) => switch (node) {
    InstanceCreationExpression() => node.constructorName.type.toSource(),
    MethodInvocation() => node.methodName.name,
    _ => null,
  };

  void _check(String name, AstNode node, ArgumentList arguments) {
    if (name == 'TextField' || name == 'TextFormField') {
      fields++;
      final named = {
        for (final argument in arguments.arguments.whereType<NamedArgument>())
          argument.name.lexeme: argument.argumentExpression.toSource(),
      };
      expect(named['enableIMEPersonalizedLearning'], 'false', reason: '$path: IME learning must be disabled');
      if (named['enableInteractiveSelection'] == 'false') return;

      var parent = node.parent;
      while (parent != null && _constructor(parent) != 'SensitiveTextEditing') {
        parent = parent.parent;
      }
      expect(parent, isNotNull, reason: '$path: keyboard copying must use SensitiveTextEditing');
      expect(named['contextMenuBuilder'], 'menuBuilder', reason: '$path: menu copying must use the protected builder');
    }
  }

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    _check(node.constructorName.type.toSource(), node, node.argumentList);
    super.visitInstanceCreationExpression(node);
  }

  @override
  void visitMethodInvocation(MethodInvocation node) {
    _check(node.methodName.name, node, node.argumentList);
    super.visitMethodInvocation(node);
  }
}

void main() {
  test('every application text input enforces sensitive copy and IME policy', () {
    var fields = 0;
    final files = Directory('lib').listSync(recursive: true).whereType<File>();
    for (final file in files) {
      if (file.path.endsWith('.dart') && file.path.endsWith('.g.dart') == false) {
        final visitor = _InputPolicy(file.path);
        parseString(content: file.readAsStringSync()).unit.accept(visitor);
        fields += visitor.fields;
      }
    }
    expect(fields, greaterThan(0));
  });
}
