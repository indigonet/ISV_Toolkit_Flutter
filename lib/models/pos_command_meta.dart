import 'package:flutter/material.dart';

class POSCommandMeta {
  final int code;
  final String labelKey;
  final IconData icon;
  final String descriptionKey;
  final bool isAdvanced;

  const POSCommandMeta({
    required this.code,
    required this.labelKey,
    required this.icon,
    required this.descriptionKey,
    this.isAdvanced = false,
  });
}
