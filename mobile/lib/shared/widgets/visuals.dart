import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

/// Emoji for a product name (Hindi or English words), used when a product has no photo.
const _productEmoji = [
  (['सेब', 'apple'], '🍎'),
  (['केला', 'banana'], '🍌'),
  (['अनार', 'pomegranate'], '🫐'),
  (['पपीता', 'papaya'], '🥭'),
  (['आम', 'mango'], '🥭'),
  (['मौसमी', 'संतरा', 'orange'], '🍊'),
  (['अंगूर', 'grape'], '🍇'),
  (['तरबूज़', 'तरबूज', 'watermelon'], '🍉'),
  (['स्ट्रॉबेरी', 'strawberry'], '🍓'),
  (['नींबू', 'lemon'], '🍋'),
  (['टमाटर', 'tomato'], '🍅'),
  (['आलू', 'potato'], '🥔'),
  (['प्याज़', 'प्याज', 'onion'], '🧅'),
  (['पालक', 'साग', 'spinach'], '🥬'),
  (['भिंडी', 'okra'], '🫛'),
  (['गाजर', 'carrot'], '🥕'),
  (['मिर्च', 'chilli'], '🌶️'),
  (['गोभी', 'cabbage', 'cauliflower'], '🥦'),
  (['खीरा', 'cucumber'], '🥒'),
  (['मक्का', 'corn'], '🌽'),
  (['दूध', 'milk'], '🥛'),
  (['पनीर', 'cheese', 'paneer'], '🧀'),
  (['दही', 'curd', 'yogurt'], '🥣'),
  (['मक्खन', 'घी', 'butter', 'ghee'], '🧈'),
  (['अंडा', 'egg'], '🥚'),
  (['आटा', 'flour'], '🌾'),
  (['चावल', 'rice'], '🍚'),
  (['दाल', 'dal'], '🫘'),
  (['तेल', 'oil'], '🫙'),
  (['चीनी', 'sugar'], '🍬'),
  (['ब्रेड', 'bread'], '🍞'),
  (['केक', 'cake'], '🎂'),
  (['बिस्कुट', 'कुकीज़', 'biscuit', 'cookie'], '🍪'),
  (['नमकीन', 'chips', 'snack'], '🥨'),
  (['जूस', 'juice'], '🧃'),
  (['चाय', 'tea'], '🍵'),
  (['चिकन', 'chicken'], '🍗'),
  (['मछली', 'fish'], '🐟'),
];

/// Category (English name from the API) -> fallback emoji and pastel colour.
const _categoryLook = {
  'Fruits': ('🍎', Color(0xFFFFE4E1)),
  'Vegetables': ('🥬', Color(0xFFE3F5DF)),
  'Grocery': ('🛒', Color(0xFFFFF1D6)),
  'Dairy Products': ('🥛', Color(0xFFE6F0FF)),
  'Bakery': ('🍞', Color(0xFFFDEBD8)),
  'Snacks': ('🥨', Color(0xFFFFF3C4)),
  'Beverages': ('🥤', Color(0xFFDDF4F7)),
  'Meat and Seafood': ('🍗', Color(0xFFFCE1E4)),
  'Household Essentials': ('🧴', Color(0xFFEDE7FB)),
  'Other Local Products': ('🛍️', Color(0xFFF2EEE6)),
};

const _pastels = [
  Color(0xFFFFE4E1), Color(0xFFE3F5DF), Color(0xFFFFF1D6), Color(0xFFE6F0FF),
  Color(0xFFFDEBD8), Color(0xFFEDE7FB), Color(0xFFDDF4F7), Color(0xFFFFF3C4),
];

/// (emoji, pastel background) for a product; stable for the same name.
(String, Color) productLook(String name, [String category = '']) {
  final lower = name.toLowerCase();
  String? emoji;
  for (final (words, e) in _productEmoji) {
    if (words.any((w) => lower.contains(w))) {
      emoji = e;
      break;
    }
  }
  final fallback = _categoryLook[category];
  final color = fallback?.$2 ?? _pastels[name.hashCode.abs() % _pastels.length];
  return (emoji ?? fallback?.$1 ?? '🛍️', AppTheme.dark ? Color.lerp(color, const Color(0xFF1A201E), 0.82)! : color);
}

/// Big emoji on a soft colour, standing in for a product photo.
class ProductArt extends StatelessWidget {
  const ProductArt({super.key, required this.name, this.category = '', this.size = 88});

  final String name;
  final String category;
  final double size;

  @override
  Widget build(BuildContext context) {
    final (emoji, color) = productLook(name, category);
    return Container(
      width: size,
      height: size,
      color: color,
      alignment: Alignment.center,
      child: LayoutBuilder(
        builder: (_, box) => Text(emoji, style: TextStyle(fontSize: (box.maxHeight.isFinite ? box.maxHeight : 160) * 0.45)),
      ),
    );
  }
}
