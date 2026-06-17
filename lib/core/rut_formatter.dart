import 'package:flutter/services.dart';

class RutFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final text = newValue.text;
    
    // Strip everything except digits and K/k
    final cleanText = text.replaceAll(RegExp(r'[^0-9kK]'), '');
    
    if (cleanText.isEmpty) {
      return const TextEditingValue(
        text: '',
        selection: TextSelection.collapsed(offset: 0),
      );
    }
    
    // Determine body and verification digit (DV)
    String body = '';
    String dv = '';
    if (cleanText.length > 1) {
      body = cleanText.substring(0, cleanText.length - 1);
      dv = cleanText.substring(cleanText.length - 1).toUpperCase();
    } else {
      body = cleanText;
    }
    
    // Limit body to 8 digits (which yields max RUT body 99.999.999)
    if (body.length > 8) {
      body = body.substring(0, 8);
    }
    
    // Format body with dots (e.g. 12.345.678)
    String formattedBody = '';
    int count = 0;
    for (int i = body.length - 1; i >= 0; i--) {
      formattedBody = body[i] + formattedBody;
      count++;
      if (count == 3 && i > 0) {
        formattedBody = '.$formattedBody';
        count = 0;
      }
    }
    
    String formatted = formattedBody;
    if (dv.isNotEmpty) {
      formatted = '$formatted-$dv';
    }
    
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}

bool isValidRut(String rut) {
  // Strip all formatting
  final clean = rut.replaceAll(RegExp(r'[^0-9kK]'), '');
  if (clean.length < 2) return false;
  
  final body = clean.substring(0, clean.length - 1);
  final dv = clean.substring(clean.length - 1).toUpperCase();
  
  // Modulo 11 check calculation
  int sum = 0;
  int multiplier = 2;
  for (int i = body.length - 1; i >= 0; i--) {
    final digit = int.tryParse(body[i]);
    if (digit == null) return false;
    sum += digit * multiplier;
    multiplier = multiplier == 7 ? 2 : multiplier + 1;
  }
  
  final remainder = sum % 11;
  final result = 11 - remainder;
  
  String expectedDv;
  if (result == 11) {
    expectedDv = '0';
  } else if (result == 10) {
    expectedDv = 'K';
  } else {
    expectedDv = result.toString();
  }
  
  return dv == expectedDv;
}
