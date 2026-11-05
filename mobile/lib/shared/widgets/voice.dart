import 'dart:async';

import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../../core/i18n/i18n.dart';
import '../../core/theme/app_theme.dart';
import 'common.dart';

final _speech = SpeechToText();

/// Opens a "speak now" sheet and returns what was said (Hindi), or null.
Future<String?> listenOnce(BuildContext context, {String hint = ''}) async {
  final ready = await _speech.initialize();
  if (!context.mounted) return null;
  if (!ready) {
    showMessage(context, tr('इस फ़ोन पर आवाज़ से खोज उपलब्ध नहीं है'));
    return null;
  }
  return showModalBottomSheet<String>(
    context: context,
    builder: (_) => _ListenSheet(hint: hint),
  );
}

class _ListenSheet extends StatefulWidget {
  const _ListenSheet({required this.hint});

  final String hint;

  @override
  State<_ListenSheet> createState() => _ListenSheetState();
}

class _ListenSheetState extends State<_ListenSheet> with SingleTickerProviderStateMixin {
  late final AnimationController _pulse =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 700), lowerBound: 0.9, upperBound: 1.2)
        ..repeat(reverse: true);
  String _words = '';
  bool _done = false;

  @override
  void initState() {
    super.initState();
    _speech.listen(
      listenOptions: SpeechListenOptions(
        partialResults: true,
        localeId: 'hi_IN',
        listenFor: const Duration(seconds: 12),
        pauseFor: const Duration(seconds: 3),
      ),
      onResult: (SpeechRecognitionResult result) {
        if (!mounted) return;
        setState(() => _words = result.recognizedWords);
        if (result.finalResult && !_done) {
          _done = true;
          Future.delayed(const Duration(milliseconds: 400), () {
            if (mounted) Navigator.pop(context, _words.trim().isEmpty ? null : _words.trim());
          });
        }
      },
    );
  }

  @override
  void dispose() {
    _speech.stop();
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 28),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ScaleTransition(
            scale: _pulse,
            child: Container(
              width: 90,
              height: 90,
              decoration: BoxDecoration(gradient: AppTheme.heroGradient, shape: BoxShape.circle),
              child: const Icon(Icons.mic_rounded, color: Colors.white, size: 46),
            ),
          ),
          const SizedBox(height: 16),
          Text(tr('बोलिए…'), style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppTheme.ink)),
          const SizedBox(height: 8),
          Text(
            _words.isEmpty ? widget.hint : _words,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 16, color: _words.isEmpty ? AppTheme.muted : AppTheme.ink),
          ),
          const SizedBox(height: 16),
          TextButton(
            onPressed: () => Navigator.pop(context, _words.trim().isEmpty ? null : _words.trim()),
            child: Text(_words.isEmpty ? tr('रद्द') : tr('ठीक है')),
          ),
        ]),
      ),
    );
  }
}

// ---------- understanding "2 किलो टमाटर 20 रुपये" ----------

const _numberWords = {
  'आधा': 0.5, 'डेढ़': 1.5, 'ढाई': 2.5, 'एक': 1, 'दो': 2, 'तीन': 3, 'चार': 4, 'पांच': 5, 'पाँच': 5, 'छह': 6, 'छः': 6,
  'सात': 7, 'आठ': 8, 'नौ': 9, 'दस': 10, 'ग्यारह': 11, 'बारह': 12, 'पंद्रह': 15, 'बीस': 20, 'पच्चीस': 25, 'तीस': 30,
  'चालीस': 40, 'पचास': 50, 'साठ': 60, 'सत्तर': 70, 'अस्सी': 80, 'नब्बे': 90, 'सौ': 100,
};

const _unitWords = {
  'किलो': 'kg', 'केजी': 'kg', 'kg': 'kg', 'kilo': 'kg', 'ग्राम': 'g', 'लीटर': 'litre', 'litre': 'litre',
  'दर्जन': 'dozen', 'dozen': 'dozen', 'पीस': 'piece', 'piece': 'piece', 'पैकेट': 'packet', 'packet': 'packet', 'डिब्बा': 'box',
};

const _priceWords = ['रुपये', 'रुपए', 'रुपया', 'रूपये', 'rupees', 'rupaye', 'rs', '₹'];

/// What a merchant said about a new deal.
class SpokenDeal {
  SpokenDeal({this.quantity, this.unit, this.price, this.productText = ''});

  final double? quantity;
  final String? unit;
  final double? price;
  final String productText;
}

double? _number(String token) {
  final cleaned = token.replaceAll('₹', '').replaceAll(',', '');
  return double.tryParse(cleaned) ?? _numberWords[cleaned]?.toDouble();
}

/// Reads quantity (number before a unit word), price (number next to "rupees"/₹) and the remaining words as the product.
SpokenDeal parseSpokenDeal(String text) {
  final tokens = text.toLowerCase().replaceAll(RegExp(r'[,.!?]'), ' ').split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();
  double? quantity, price;
  String? unit;
  final used = <int>{};
  for (var i = 0; i < tokens.length; i++) {
    final value = _number(tokens[i]);
    if (value == null) continue;
    final next = i + 1 < tokens.length ? tokens[i + 1] : '';
    final prev = i > 0 ? tokens[i - 1] : '';
    if (_unitWords.containsKey(next) && quantity == null) {
      quantity = value;
      unit = _unitWords[next];
      used.addAll([i, i + 1]);
    } else if (_priceWords.contains(next) || _priceWords.contains(prev) || tokens[i].startsWith('₹')) {
      price = value;
      used.add(i);
      if (_priceWords.contains(next)) used.add(i + 1);
      if (_priceWords.contains(prev)) used.add(i - 1);
    } else if (price == null && quantity != null) {
      price = value; // "2 किलो टमाटर 20" -> the second number is the price
      used.add(i);
    }
  }
  const filler = {'में', 'का', 'की', 'के', 'वाला', 'वाली', 'डील', 'प्रति', 'per', 'बेचना', 'है'};
  final productText = [
    for (var i = 0; i < tokens.length; i++)
      if (!used.contains(i) && !filler.contains(tokens[i]) && !_priceWords.contains(tokens[i])) tokens[i],
  ].join(' ');
  return SpokenDeal(quantity: quantity, unit: unit, price: price, productText: productText);
}
