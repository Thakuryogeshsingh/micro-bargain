import 'package:flutter_test/flutter_test.dart';
import 'package:micro_bargain/shared/widgets/voice.dart';

void main() {
  test('digits with unit and rupees', () {
    final d = parseSpokenDeal('2 किलो टमाटर 20 रुपये');
    expect(d.quantity, 2);
    expect(d.unit, 'kg');
    expect(d.price, 20);
    expect(d.productText, 'टमाटर');
  });

  test('Hindi number words and price without the word rupees', () {
    final d = parseSpokenDeal('पांच दर्जन केला चालीस');
    expect(d.quantity, 5);
    expect(d.unit, 'dozen');
    expect(d.price, 40);
    expect(d.productText, 'केला');
  });

  test('rupee sign and half kilo', () {
    final d = parseSpokenDeal('आधा किलो पनीर ₹150');
    expect(d.quantity, 0.5);
    expect(d.price, 150);
    expect(d.productText, 'पनीर');
  });
}
