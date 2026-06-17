import 'package:flutter/services.dart';

// Custom text input formatter to format integer amounts as CLP ($ 15.000)
class CLPFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digits = newValue.text.replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) {
      return TextEditingValue.empty;
    }

    final value = int.tryParse(digits) ?? 0;
    if (value > 999999999) {
      return oldValue;
    }

    // Format value with thousands separator (.)
    final buffer = StringBuffer();
    final str = value.toString();
    for (int i = 0; i < str.length; i++) {
      if (i > 0 && (str.length - i) % 3 == 0) {
        buffer.write('.');
      }
      buffer.write(str[i]);
    }

    final formattedText = buffer.toString();

    return TextEditingValue(
      text: formattedText,
      selection: TextSelection.collapsed(offset: formattedText.length),
    );
  }
}
