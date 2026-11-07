import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yue/theme/tokens.dart';

/// Holds the app to the same scales as Eclipse.
void main() {
  final files = Directory('lib').listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart')).toList();

  List<String> offenders(RegExp pattern, bool Function(String) allowed) {
    final found = <String>[];
    for (final f in files) {
      final lines = f.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        if (lines[i].trimLeft().startsWith('//')) continue;
        for (final m in pattern.allMatches(lines[i])) {
          if (!allowed(m.group(1)!)) found.add('${f.path}:${i + 1}  ${m.group(0)}');
        }
      }
    }
    return found;
  }

  test('corner radii are on the scale', () {
    expect(offenders(RegExp(r'Radius\.circular\(([0-9.]+)\)'), (v) => Scale.radii.contains(double.parse(v))), isEmpty);
  });

  test('font sizes are on the scale', () {
    expect(offenders(RegExp(r'fontSize: ([0-9.]+)'), (v) => Scale.fontSizes.contains(double.parse(v))), isEmpty);
    expect(offenders(RegExp(r'(?:zhStyle|displayStyle)\(([0-9.]+)'), (v) => Scale.fontSizes.contains(double.parse(v))), isEmpty);
  });

  test('widgets that ease their own colours stand still during a theme change', () {
    final animated = RegExp(r'Animated(?:Container|DefaultTextStyle)\(');
    final bad = <String>[];
    for (final f in files) {
      final code = f.readAsLinesSync().where((line) => !line.trimLeft().startsWith('//')).join('\n');
      for (final m in animated.allMatches(code)) {
        final duration = RegExp(r'duration: ([^\n]*)').firstMatch(code.substring(m.end));
        if (!(duration?.group(1)?.startsWith('context.themed(') ?? false)) bad.add('${f.path}  ${m.group(0)}');
      }
    }
    expect(bad, isEmpty);
  });

  test('no emojis anywhere in the interface', () {
    final emoji = RegExp(r'[\u{1F300}-\u{1FAFF}\u{2600}-\u{27BF}]', unicode: true);
    final bad = [for (final f in files) if (emoji.hasMatch(f.readAsStringSync())) f.path];
    expect(bad, isEmpty);
  });
}
