import 'package:flutter/material.dart';
import '../core/localization.dart';
import '../services/sdk_service.dart';
import '../widgets/signing_dialog.dart';

class SigningPage extends StatelessWidget {
  final AppLocale loc;
  final bool isDarkMode;
  final SDKService sdk;

  const SigningPage({
    super.key,
    required this.loc,
    required this.isDarkMode,
    required this.sdk,
  });

  @override
  Widget build(BuildContext context) {
    return SigningDialog(
      loc: loc,
      isDarkMode: isDarkMode,
      sdk: sdk,
      isDialog: false,
    );
  }
}

