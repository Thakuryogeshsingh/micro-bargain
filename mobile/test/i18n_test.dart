import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:micro_bargain/core/i18n/i18n.dart';

final _placeholder = RegExp(r'\{\d+\}');

Set<String> _placeholders(String text) => _placeholder.allMatches(text).map((m) => m.group(0)!).toSet();

void main() {
  final keys = (jsonDecode(File('assets/i18n/_keys.json').readAsStringSync()) as List).cast<String>();

  test('tr fills placeholders and falls back to the Hindi key', () {
    expect(tr('{0} कैसी लगी?', ['Gupta Fruits']), 'Gupta Fruits कैसी लगी?');
    expect(tr('कोई अनजान टेक्स्ट'), 'कोई अनजान टेक्स्ट');
  });

  for (final language in languages.where((l) => l.code != 'hi')) {
    test('${language.englishName} catalogue covers every text with the same placeholders', () {
      final file = File('assets/i18n/${language.code}.json');
      expect(file.existsSync(), isTrue, reason: 'missing ${file.path}');
      final catalogue = (jsonDecode(file.readAsStringSync()) as Map).cast<String, String>();
      final missing = keys.where((k) => (catalogue[k] ?? '').trim().isEmpty).toList();
      expect(missing, isEmpty, reason: 'untranslated: ${missing.take(5)}');
      final broken = keys.where((k) => !_placeholders(catalogue[k]!).containsAll(_placeholders(k))).toList();
      expect(broken, isEmpty, reason: 'placeholders lost: ${broken.take(5)}');
    });
  }
}
