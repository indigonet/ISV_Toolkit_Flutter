import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:archive/archive_io.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import '../core/localization.dart';
import '../services/sdk_service.dart';
import '../widgets/panel_button.dart';
import '../widgets/signing_dialog.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:window_manager/window_manager.dart';

class AnalysisPage extends StatefulWidget {
  final AppLocale loc;
  final bool isDarkMode;
  final SDKService sdk;
  final String adbStatus;

  const AnalysisPage({
    super.key,
    required this.loc,
    required this.isDarkMode,
    required this.sdk,
    required this.adbStatus,
  });

  @override
  State<AnalysisPage> createState() => _AnalysisPageState();
}

class _AnalysisPageState extends State<AnalysisPage> {
  bool _isAnalyzing = false;
  Uint8List? _apkIconBytes;
  final Map<String, String> _apkData = {};
  String? _apkPath;
  String _installStatus = "unknown";
  String? _installedVersion;
  bool _isInstalling = false;
  bool _isUninstalling = false;
  bool _isExtractedFromDevice = false;

  String _rawAapt = "";
  String _rawApksigner = "";
  String _rawJarsigner = "";
  bool _isDragging = false;

  final TextEditingController _packageNameController = TextEditingController();

  @override
  void initState() {
    super.initState();
    widget.sdk.refreshTick.addListener(_checkInstallationStatus);
  }

  @override
  void dispose() {
    widget.sdk.refreshTick.removeListener(_checkInstallationStatus);
    _packageNameController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(AnalysisPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.adbStatus != widget.adbStatus) {
      _checkInstallationStatus();
    }
  }

  void _analyzeAPK({String? manualPath, bool extractedFromDevice = false}) async {
    _isExtractedFromDevice = extractedFromDevice;
    String path;
    String fileName;

    if (manualPath != null) {
      path = manualPath;
      fileName = p.basename(path);
    } else {
      // Forzar foco a la ventana actual para que el diálogo se abra en el mismo monitor
      try {
        await windowManager.focus();
      } catch (_) {}

      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['apk'],
      );
      if (result == null) return;
      path = result.files.single.path!;
      fileName = result.files.single.name;
    }

    setState(() {
      _isAnalyzing = true;
      _apkIconBytes = null;
      _apkData.clear();
      _rawAapt = "";
      _rawApksigner = "";
      _rawJarsigner = "";
    });

    double fileSizeMB = File(path).lengthSync() / (1024 * 1024);

    String appLabel = "Unknown",
        packageName = "Unknown",
        verName = "N/A",
        verCode = "N/A",
        minSdk = "N/A",
        targetSdk = "N/A",
        nativeCode = "N/A",
        modo = "Unknown",
        iconPath = "";
    List<String> schemes = [];
    String certDN = "N/A", sha256 = "N/A";

    try {
      // 1. AAPT Badging
      try {
        if (File(widget.sdk.aaptPath).existsSync()) {
          final aaptRes = await Process.run(widget.sdk.aaptPath, [
            'dump',
            'badging',
            path,
          ]);
          _rawAapt = aaptRes.stdout.toString() + aaptRes.stderr.toString();
          final aaptOut = _rawAapt;

          final pkgMatch = RegExp(
            r"package: name='([^']*)' versionCode='([^']*)' versionName='([^']*)'",
          ).firstMatch(aaptOut);
          if (pkgMatch != null) {
            packageName = pkgMatch.group(1)!;
            verCode = pkgMatch.group(2)!;
            verName = pkgMatch.group(3)!;
          }
          final labelMatch = RegExp(
            r"application-label:'([^']*)'",
          ).firstMatch(aaptOut);
          if (labelMatch != null) appLabel = labelMatch.group(1)!;

          final sdkMatch = RegExp(r"sdkVersion:'([^']*)'").firstMatch(aaptOut);
          if (sdkMatch != null) minSdk = sdkMatch.group(1)!;

          final targetMatch = RegExp(
            r"targetSdkVersion:'([^']*)'",
          ).firstMatch(aaptOut);
          if (targetMatch != null) targetSdk = targetMatch.group(1)!;

          final nativeMatch = RegExp(r"native-code: (.*)").firstMatch(aaptOut);
          if (nativeMatch != null) {
            nativeCode = nativeMatch.group(1)!.replaceAll("'", "").trim();
          }

          // FALLBACK: If aapt doesn't report native-code, scan the APK zip for lib/ folders
          if (nativeCode == "N/A" || nativeCode.isEmpty) {
            try {
              final bytes = await File(path).readAsBytes();
              final archive = ZipDecoder().decodeBytes(bytes);
              Set<String> archs = {};
              for (final file in archive) {
                if (file.name.startsWith('lib/')) {
                  final parts = file.name.split('/');
                  if (parts.length > 2) {
                    archs.add(parts[1]);
                  }
                }
              }
              if (archs.isNotEmpty) {
                nativeCode = archs.join(' ');
              } else {
                nativeCode = "N/A";
              }
            } catch (_) {}
          }

          // Extract the highest-density rasterized icon from AAPT output if available
          final iconMatches = RegExp(
            r"icon-(\d+)[:=]?\s*'([^']*)'",
          ).allMatches(aaptOut);
          String? bestRasterIconPath;
          int highestDensity = -1;
          for (final match in iconMatches) {
            final densityStr = match.group(1);
            final path = match.group(2);
            if (densityStr != null &&
                path != null &&
                !path.toLowerCase().endsWith('.xml')) {
              final density = int.tryParse(densityStr) ?? 0;
              if (density > highestDensity) {
                highestDensity = density;
                bestRasterIconPath = path;
              }
            }
          }

          if (bestRasterIconPath != null) {
            iconPath = bestRasterIconPath;
          } else {
            final iconMatch =
                RegExp(r"icon-\d+[:=]?\s*'([^']*)'").firstMatch(aaptOut) ??
                RegExp(r"icon[:=]?\s*'([^']*)'").firstMatch(aaptOut);
            iconPath = iconMatch?.group(1) ?? "";
          }

          bool isDebug = aaptOut.contains("application-debuggable");
          modo = isDebug ? "Debug" : "Release";
        } else {
          widget.sdk.log("⚠️ aapt no encontrado en: ${widget.sdk.aaptPath}");
        }
      } catch (e) {
        widget.sdk.log("Error running aapt: $e");
      }

      // 2. Apksigner
      try {
        if (File(widget.sdk.apksignerPath).existsSync()) {
          // cmd.exe /c strips quotes unexpectedly if there are multiple quotes in the command string,
          // breaking the tool execution on Windows if the SDK path has spaces.
          // Solution: bypass apksigner.bat entirely by directly invoking its underlying jar with java.exe.

          String apksignerJar = '';
          if (widget.sdk.apksignerPath.endsWith('.jar')) {
            apksignerJar = widget.sdk.apksignerPath;
          } else {
            final String apksignerDir = File(
              widget.sdk.apksignerPath,
            ).parent.path;
            apksignerJar = p.join(apksignerDir, 'lib', 'apksigner.jar');
          }

          String javaExe = widget.sdk.jarsignerPath.replaceAll(
            'jarsigner.exe',
            'java.exe',
          );

          if (!File(javaExe).existsSync()) {
            javaExe = 'java';
          }

          ProcessResult signRes;
          if (File(apksignerJar).existsSync() && File(javaExe).existsSync()) {
            signRes = await Process.run(javaExe, [
              '-jar',
              apksignerJar,
              'verify',
              '--verbose',
              '--print-certs',
              path,
            ], runInShell: false);
          } else {
            // Fallback: Run the apksigner.bat or .jar directly via shell
            // Process.run with runInShell: true handles quotes for paths with spaces automatically on Windows
            signRes = await Process.run(widget.sdk.apksignerPath, [
              'verify',
              '--verbose',
              '--print-certs',
              path,
            ], runInShell: true);
          }

          final String rawOutput = signRes.stdout.toString();
          final String rawError = signRes.stderr.toString();
          widget.sdk.log('🔑 apksigner exit code: ${signRes.exitCode}');

          _rawApksigner =
              "=== APKSIGNER VERIFY ===\n══════════════════════════════════════════════════\n$rawOutput${rawError.isNotEmpty ? '\n--- STDERR ---\n$rawError' : ''}";
          final signOut = rawOutput + rawError;

          if (signOut.contains("v1 scheme (JAR signing): true")) {
            schemes.add("v1");
          }
          if (signOut.contains("v2 scheme (APK Signature Scheme v2): true")) {
            schemes.add("v2");
          }
          if (signOut.contains("v3 scheme (APK Signature Scheme v3): true")) {
            schemes.add("v3");
          }

          // More flexible regex to catch Signer #1, #2, etc. and different capitalization
          final dnMatch = RegExp(
            r"Signer #\d+ certificate DN: (.*)",
            caseSensitive: false,
          ).firstMatch(signOut);
          if (dnMatch != null) {
            certDN = dnMatch.group(1)?.trim() ?? certDN;
          }

          final shaMatch = RegExp(
            r"Signer #\d+ certificate SHA-256 digest: (.*)",
            caseSensitive: false,
          ).firstMatch(signOut);
          if (shaMatch != null) {
            String rawSha = shaMatch.group(1)?.trim() ?? sha256;
            sha256 = rawSha
                .replaceAll(':', '')
                .replaceAll(' ', '')
                .toLowerCase();
          }

          // EXTRA FALLBACK: Scan entire output for any 64-char hex string (SHA-256)
          if (sha256 == "N/A" || sha256.length < 64) {
            final hexRegex = RegExp(r"([0-9a-fA-F]{2}[: ]?){31}[0-9a-fA-F]{2}");
            final hexMatch = hexRegex.firstMatch(signOut);
            if (hexMatch != null) {
              sha256 = hexMatch
                  .group(0)!
                  .replaceAll(':', '')
                  .replaceAll(' ', '')
                  .toLowerCase();
            }
          }
        } else {
          widget.sdk.log(
            "⚠️ apksigner no encontrado en: ${widget.sdk.apksignerPath}",
          );
        }
      } catch (e) {
        widget.sdk.log("Error running apksigner: $e");
      }

      // 3. Jarsigner & Fallback Extraction
      try {
        if (File(widget.sdk.jarsignerPath).existsSync()) {
          final jarRes = await Process.run(widget.sdk.jarsignerPath, [
            '-verify',
            '-verbose',
            '-certs',
            path,
          ]);
          _rawJarsigner = jarRes.stdout.toString() + jarRes.stderr.toString();

          // FALLBACK: If apksigner failed or didn't provide cert info, try parsing jarsigner
          if (certDN == "N/A" || sha256 == "N/A") {
            final signOutJar = _rawJarsigner;

            // Jarsigner DN parsing (typically follows "X.509, ")
            final dnMatchJar = RegExp(
              r"X\.509, (CN=[^,\]\n]*)",
              caseSensitive: false,
            ).firstMatch(signOutJar);
            if (certDN == "N/A" && dnMatchJar != null) {
              certDN = dnMatchJar.group(1)?.trim() ?? certDN;
            }

            // Jarsigner SHA-256 parsing (usually inside brackets [SHA-256: ...])
            // Matches [SHA-256: 3D:8A:...] or similar formats
            final shaMatchJar = RegExp(
              r"SHA-?256:?\s*([0-9A-Fa-f: ]{64,})",
              caseSensitive: false,
            ).firstMatch(signOutJar);

            if (sha256 == "N/A" && shaMatchJar != null) {
              // Normalize: remove colons and spaces to match standard hash format
              String rawSha = shaMatchJar.group(1) ?? "";
              sha256 = rawSha
                  .replaceAll(':', '')
                  .replaceAll(' ', '')
                  .toLowerCase()
                  .trim();
            }
          }
        } else {
          widget.sdk.log(
            "⚠️ jarsigner no encontrado en: ${widget.sdk.jarsignerPath}",
          );
        }
      } catch (e) {
        widget.sdk.log("Error running jarsigner: $e");
      }

      // 4. Keytool fallback (Most robust for cert info if other tools fail)
      if (sha256 == "N/A" || certDN == "N/A") {
        try {
          if (File(widget.sdk.keytoolPath).existsSync()) {
            final keyRes = await Process.run(widget.sdk.keytoolPath, [
              '-printcert',
              '-jarfile',
              path,
            ]);
            final keyOut = keyRes.stdout.toString() + keyRes.stderr.toString();

            if (certDN == "N/A") {
              final dnMatch = RegExp(
                r"Propietario: (.*)|Owner: (.*)",
                caseSensitive: false,
              ).firstMatch(keyOut);
              if (dnMatch != null) {
                certDN = (dnMatch.group(1) ?? dnMatch.group(2) ?? certDN)
                    .trim();
              }
            }

            if (sha256 == "N/A") {
              final shaMatch = RegExp(
                r"SHA256:?\s*([0-9A-Fa-f: ]{64,})",
                caseSensitive: false,
              ).firstMatch(keyOut);
              if (shaMatch != null) {
                sha256 = shaMatch
                    .group(1)!
                    .replaceAll(':', '')
                    .replaceAll(' ', '')
                    .toLowerCase()
                    .trim();
              }
            }
          }
        } catch (e) {
          widget.sdk.log("Error running keytool fallback: $e");
        }
      }

      try {
        // Optimization: Extract icon in background to avoid freezing UI
        final iconBytes = await compute(_extractIconInBackground, {
          'apkPath': path,
          'iconPath': iconPath,
        });
        if (iconBytes != null) {
          _apkIconBytes = iconBytes;
        }
      } catch (e) {
        widget.sdk.log("⚠️ Icon extract failed: $e");
      }

      setState(() {
        _apkPath = path;
        _apkData['Archivo'] = fileName;
        _apkData['Aplicación'] = appLabel;
        _apkData['Paquete'] = packageName;
        _apkData['Version Name'] = verName;
        _apkData['Version Code'] = verCode;
        _apkData['Min SDK'] = minSdk;
        _apkData['Target SDK'] = targetSdk;
        _apkData['Arquitectura'] = nativeCode;
        _apkData['Tamaño'] = "${fileSizeMB.toStringAsFixed(1)} MB";
        _apkData['Modo'] = modo;
        _apkData['Firma'] = schemes.isEmpty ? 'Unsigned' : schemes.join(', ');
        _apkData['Certificado'] = certDN;
        _apkData['SHA-256'] = sha256;
        _isAnalyzing = false;
        _packageNameController.text = packageName;
      });
      _checkInstallationStatus();
    } catch (e) {
      setState(() => _isAnalyzing = false);
      widget.sdk.log('Analysis error: $e');
    }
  }

  void _installCurrentApk() async {
    if (_apkPath == null) return;
    if (!mounted) return;

    setState(() => _isInstalling = true);
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.install_mobile, color: Colors.white),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                '${widget.loc.t("Instalando APK en el dispositivo")}...',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(width: 16),
            SizedBox(
              width: 120,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: const LinearProgressIndicator(
                  backgroundColor: Colors.white24,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  minHeight: 5,
                ),
              ),
            ),
          ],
        ),
        backgroundColor: Colors.green[700],
        duration: const Duration(days: 365), // Keep open
        behavior: SnackBarBehavior.fixed,
      ),
    );

    int code = await widget.sdk.runCommand(widget.sdk.adbPath, [
      'install',
      '-r',
      '-t',
      '-d',
      '-g',
      _apkPath!,
    ]);

    if (!mounted) return;
    setState(() => _isInstalling = false);

    // Refresh status in background — guarded internally
    unawaited(_checkInstallationStatus());

    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          code == 0
              ? widget.loc.t('Instalación completada')
              : '${widget.loc.t('Error en la instalación')} ($code)',
        ),
        backgroundColor: code == 0 ? Colors.green : Colors.red,
        behavior: SnackBarBehavior.fixed,
      ),
    );
  }

  void _uninstallPackage() async {
    final pkg = _packageNameController.text.trim();
    if (pkg.isEmpty) return;
    if (!mounted) return;

    setState(() => _isUninstalling = true);
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.delete_sweep, color: Colors.white),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                '${widget.loc.t("Desinstalando aplicación")}...',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(width: 16),
            SizedBox(
              width: 120,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: const LinearProgressIndicator(
                  backgroundColor: Colors.white24,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  minHeight: 5,
                ),
              ),
            ),
          ],
        ),
        backgroundColor: Colors.orange[800],
        duration: const Duration(days: 365),
        behavior: SnackBarBehavior.fixed,
      ),
    );

    int code = await widget.sdk.runCommand(widget.sdk.adbPath, [
      'uninstall',
      pkg,
    ]);

    if (!mounted) return;
    setState(() => _isUninstalling = false);

    unawaited(_checkInstallationStatus());

    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          code == 0
              ? widget.loc.t('Desinstalado con éxito')
              : '${widget.loc.t('Error al desinstalar')} ($code)',
        ),
        backgroundColor: code == 0 ? Colors.green : Colors.red,
        behavior: SnackBarBehavior.fixed,
      ),
    );
  }

  void _showUninstallByPackageDialog() async {
    final isD = widget.isDarkMode;

    // Show dialog immediately with loading state
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) => _UninstallPackageDialog(
        sdk: widget.sdk,
        isDark: isD,
        loc: widget.loc,
        onUninstalled: () {
          _checkInstallationStatus();
        },
      ),
    );
  }

  void _showExtractPackageDialog() async {
    final isD = widget.isDarkMode;
    final isDeviceConnected = !widget.adbStatus.contains(
      widget.loc.statusDisconnected,
    );

    if (!isDeviceConnected) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(widget.loc.t("No hay ningún dispositivo conectado por ADB")),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) => _ExtractPackageDialog(
        sdk: widget.sdk,
        isDark: isD,
        loc: widget.loc,
        onExtracted: (localPath) {
          _analyzeAPK(manualPath: localPath, extractedFromDevice: true);
        },
      ),
    );
  }

  Future<void> _checkInstallationStatus() async {
    if (!mounted) return;
    final pkg = _packageNameController.text.trim();
    if (pkg.isEmpty ||
        widget.adbStatus.contains(widget.loc.statusDisconnected)) {
      if (mounted) setState(() => _installStatus = 'unknown');
      return;
    }

    try {
      final res = await widget.sdk.runAdb(['shell', 'dumpsys', 'package', pkg]);
      if (!mounted) return;

      final String out = res.stdout.toString() + res.stderr.toString();
      final verMatch = RegExp(r'versionName=([^\s]*)').firstMatch(out);

      if (verMatch == null) {
        setState(() => _installStatus = 'notInstalled');
        return;
      }

      _installedVersion = verMatch.group(1);

      final currentApkVer = _apkData['Version Name'] ?? '';
      if (_installedVersion != null &&
          _installedVersion != currentApkVer &&
          currentApkVer.isNotEmpty) {
        setState(() => _installStatus = 'update');
      } else {
        setState(() => _installStatus = 'installed');
      }
    } catch (_) {
      if (mounted) setState(() => _installStatus = 'unknown');
    }
  }

  void _showCommandsDialog() {
    showDialog(
      context: context,
      builder: (context) => _CommandsDialog(
        loc: widget.loc,
        isDark: widget.isDarkMode,
        rawAapt: _rawAapt,
        rawApksigner: _rawApksigner,
        rawJarsigner: _rawJarsigner,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDarkMode;
    final accentColor = isDark ? Colors.cyanAccent : Colors.blueAccent;

    return DropTarget(
      onDragDone: (detail) {
        if (detail.files.isNotEmpty) {
          final file = detail.files.first;
          if (file.name.toLowerCase().endsWith('.apk')) {
            _analyzeAPK(manualPath: file.path);
          }
        }
      },
      onDragEntered: (detail) => setState(() => _isDragging = true),
      onDragExited: (detail) => setState(() => _isDragging = false),
      child: Stack(
        children: [
          SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      widget.loc.analyzeApk,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: accentColor,
                      ),
                    ),
                    if (_apkData.isNotEmpty)
                      Row(
                        children: [
                          if (_isExtractedFromDevice) ...[
                            _CircularActionIcon(
                              icon: Icons.download_for_offline_outlined,
                              tooltip: widget.loc.t("Guardar APK extraída en el PC"),
                              onTap: () async {
                                final label = _apkData['Aplicación'] ?? 'App';
                                final sanitizedName = label.replaceAll(RegExp(r'[\\/:*?"<>| ]'), '_');
                                final String? outputPath = await FilePicker.platform.saveFile(
                                  dialogTitle: widget.loc.t('Guardar APK Extraída'),
                                  fileName: '$sanitizedName.apk',
                                  type: FileType.custom,
                                  allowedExtensions: ['apk'],
                                );
                                if (outputPath != null && _apkPath != null) {
                                  try {
                                    await File(_apkPath!).copy(outputPath);
                                    if (context.mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(
                                          content: Text('${widget.loc.t("APK guardada en")} $outputPath'),
                                          backgroundColor: Colors.green,
                                        ),
                                      );
                                    }
                                  } catch (e) {
                                    if (context.mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(
                                          content: Text('${widget.loc.t("Error al guardar")}: $e'),
                                          backgroundColor: Colors.redAccent,
                                        ),
                                      );
                                    }
                                  }
                                }
                              },
                              isDark: isDark,
                              color: Colors.greenAccent,
                            ),
                            const SizedBox(width: 8),
                          ],
                          _CircularActionIcon(
                            icon: Icons.terminal,
                            tooltip: widget.loc.viewCommands,
                            onTap: _showCommandsDialog,
                            isDark: isDark,
                          ),
                          const SizedBox(width: 8),
                          _CircularActionIcon(
                            icon: Icons.developer_mode,
                            tooltip: widget.loc.t("Extraer APK del Dispositivo"),
                            onTap: _isAnalyzing ? null : _showExtractPackageDialog,
                            isDark: isDark,
                            color: accentColor,
                          ),
                          const SizedBox(width: 8),
                          _CircularActionIcon(
                            icon: Icons.file_upload_outlined,
                            tooltip: widget.loc.analyzeAnotherApk,
                            onTap: _isAnalyzing ? null : _analyzeAPK,
                            isDark: isDark,
                            color: accentColor,
                          ),
                        ],
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                if (_isAnalyzing)
                  Center(
                    child: Column(
                      children: [
                        const SizedBox(height: 30),
                        const CircularProgressIndicator(),
                        const SizedBox(height: 12),
                        Text(widget.loc.analyzing),
                      ],
                    ),
                  )
                else if (_apkData.isEmpty)
                  _buildEmptyState()
                else
                  _buildAnalysisResult(),
              ],
            ),
          ),
          if (_isDragging)
            Positioned.fill(
              child: Container(
                color: accentColor.withValues(alpha: 0.1),
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 32,
                      vertical: 24,
                    ),
                    decoration: BoxDecoration(
                      color: isDark ? Colors.black87 : Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: accentColor, width: 2),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.2),
                          blurRadius: 20,
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.file_download_outlined,
                          size: 48,
                          color: accentColor,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          widget.loc.t("Suelta el APK aquí"),
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    final isDark = widget.isDarkMode;
    final color = isDark ? Colors.cyanAccent : Colors.blueAccent;
    final isDeviceConnected = !widget.adbStatus.contains(
      widget.loc.statusDisconnected,
    );

    return Column(
      children: [
        const SizedBox(height: 20),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Card 1: Local APK
            Expanded(
              child: InkWell(
                onTap: _analyzeAPK,
                borderRadius: BorderRadius.circular(20),
                child: Container(
                  height: 220,
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: isDark ? Colors.white.withValues(alpha: 0.03) : Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: color.withValues(alpha: 0.2),
                      width: 2,
                    ),
                    boxShadow: isDark
                        ? []
                        : [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.03),
                              blurRadius: 20,
                              offset: const Offset(0, 10),
                            ),
                          ],
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.1),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(Icons.file_upload_outlined, size: 36, color: color),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        widget.loc.selectApk,
                        style: TextStyle(
                          color: isDark ? Colors.white : Colors.black87,
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        widget.loc.analysisInitialDesc,
                        style: TextStyle(
                          color: isDark ? Colors.white38 : Colors.black38,
                          fontSize: 11,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 20),
            // Card 2: Device APK Extraction
            Expanded(
              child: InkWell(
                onTap: _showExtractPackageDialog,
                borderRadius: BorderRadius.circular(20),
                child: Container(
                  height: 220,
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: isDark ? Colors.white.withValues(alpha: 0.03) : Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: isDeviceConnected
                          ? color.withValues(alpha: 0.2)
                          : (isDark ? Colors.white10 : Colors.black12),
                      width: 2,
                    ),
                    boxShadow: isDark
                        ? []
                        : [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.03),
                              blurRadius: 20,
                              offset: const Offset(0, 10),
                            ),
                          ],
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: isDeviceConnected
                              ? color.withValues(alpha: 0.1)
                              : (isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.05)),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.developer_mode,
                          size: 36,
                          color: isDeviceConnected ? color : (isDark ? Colors.white24 : Colors.black26),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        widget.loc.t("Extraer APK del Dispositivo"),
                        style: TextStyle(
                          color: isDeviceConnected
                              ? (isDark ? Colors.white : Colors.black87)
                              : (isDark ? Colors.white38 : Colors.black38),
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        isDeviceConnected
                            ? widget.loc.t("Extrae y analiza un paquete instalado en el POS conectado por ADB.")
                            : widget.loc.t("Conecta un dispositivo por ADB para habilitar esta opción."),
                        style: TextStyle(
                          color: isDark ? Colors.white38 : Colors.black38,
                          fontSize: 11,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildAnalysisResult() {
    final isDark = widget.isDarkMode;

    String firmaStatus = "Unsigned";
    bool isFirmaValid = false;
    String apkFirma = _apkData['Firma'] ?? '';
    if (apkFirma.isNotEmpty && apkFirma != 'Unsigned' && apkFirma != 'N/A') {
      isFirmaValid = true;
      if (apkFirma == 'v2') {
        firmaStatus = widget.loc.validAndroid;
      } else {
        firmaStatus = widget.loc.validMaxStore;
      }
    } else {
      firmaStatus = widget.loc.invalidUnsigned;
    }

    String jarsignerStatusText = widget.loc.t("Desconocido");
    Color jarsignerStatusColor = Colors.orangeAccent;

    if (_rawJarsigner.isNotEmpty) {
      final lower = _rawJarsigner.toLowerCase();
      if (lower.contains("jar is unsigned") ||
          lower.contains("no está firmado")) {
        jarsignerStatusText = widget.loc.t("Sin Firmar (Unsigned)");
        jarsignerStatusColor = Colors.redAccent;
      } else if (lower.contains(">>> signer") || lower.contains("firmante")) {
        jarsignerStatusText = widget.loc.t("Firma Completa");
        jarsignerStatusColor = Colors.green;
      } else {
        jarsignerStatusText = widget.loc.t("Sin Firmar (Unsigned)");
        jarsignerStatusColor = Colors.redAccent;
      }
    }
    final bool isProductiveOrEncrypted =
        _apkData['Paquete'] == 'Unknown' ||
        _apkData['Aplicación'] == 'Unknown';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (isProductiveOrEncrypted)
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.orangeAccent.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: Colors.orangeAccent.withValues(alpha: 0.3),
              ),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.warning_amber_rounded,
                  color: Colors.orangeAccent,
                  size: 24,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    widget.loc.t(
                      "Esta APK podría estar encriptada o firmada por un POS productivo, impidiendo la lectura de sus metadatos estándar.",
                    ),
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Colors.orangeAccent,
                    ),
                  ),
                ),
              ],
            ),
          ),
        // Header Card
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: isDark ? Colors.white.withValues(alpha: 0.03) : Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isDark
                  ? Colors.white10
                  : Colors.blue.withValues(alpha: 0.1),
            ),
            boxShadow: isDark
                ? []
                : [
                    BoxShadow(
                      color: Colors.blueAccent.withValues(alpha: 0.05),
                      blurRadius: 15,
                      offset: const Offset(0, 5),
                    ),
                  ],
          ),
          child: Row(
            children: [
              Tooltip(
                message: _apkIconBytes != null
                    ? widget.loc.t("Ver icono ampliado y opciones")
                    : widget.loc.noIcon,
                child: InkWell(
                  onTap: _apkIconBytes != null
                      ? () {
                          showDialog(
                            context: context,
                            builder: (context) => _ApkIconDialog(
                              iconBytes: _apkIconBytes!,
                              appName: _apkData['Aplicación'] ?? 'App',
                              isDark: isDark,
                              loc: widget.loc,
                              sdk: widget.sdk,
                            ),
                          );
                        }
                      : null,
                  borderRadius: BorderRadius.circular(14),
                  child: Container(
                    width: 75,
                    height: 75,
                    decoration: BoxDecoration(
                      color: isDark ? Colors.black45 : Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.1),
                          blurRadius: 8,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: _apkIconBytes != null
                        ? Padding(
                            padding: const EdgeInsets.all(10),
                            child: Image.memory(_apkIconBytes!),
                          )
                        : Icon(
                            Icons.image_not_supported_outlined,
                            size: 32,
                            color: isDark
                                ? Colors.white24
                                : Colors.blueGrey[200],
                          ),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Tooltip(
                      message: widget.loc.copyName,
                      child: InkWell(
                        onTap: () {
                          Clipboard.setData(
                            ClipboardData(text: _apkData['Aplicación'] ?? ''),
                          );
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                '${widget.loc.copied}: ${_apkData['Aplicación']}',
                              ),
                              duration: const Duration(seconds: 1),
                            ),
                          );
                        },
                        child: Text(
                          _apkData['Aplicación'] ?? '',
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.5,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Tooltip(
                      message: widget.loc.copyPackage,
                      child: InkWell(
                        onTap: () {
                          Clipboard.setData(
                            ClipboardData(text: _apkData['Paquete'] ?? ''),
                          );
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                '${widget.loc.copied}: ${_apkData['Paquete']}',
                              ),
                              duration: const Duration(seconds: 1),
                            ),
                          );
                        },
                        child: Text(
                          _apkData['Paquete'] ?? '',
                          style: TextStyle(
                            fontSize: 12,
                            color: isDark
                                ? Colors.cyanAccent
                                : Colors.blueAccent,
                            fontWeight: FontWeight.w500,
                            fontFamily: 'Consolas',
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _buildStatusBadge(
                          'v${_apkData['Version Name']} (${_apkData['Version Code']})',
                          Icons.tag,
                        ),
                        _buildStatusBadge(
                          _apkData['Tamaño'] ?? '',
                          Icons.storage,
                        ),
                        _buildStatusBadge(
                          _apkData['Modo'] ?? '',
                          Icons.bolt,
                          color: _apkData['Modo'] == 'Debug'
                              ? Colors.orangeAccent
                              : Colors.greenAccent,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              _buildCompactInstallActions(),
            ],
          ),
        ),

        const SizedBox(height: 8),

        // Titles Row for Detailed Info
        Row(
          children: [
            Expanded(
              flex: 3,
              child: _buildBlockTitle(
                widget.loc.t("ESPECIFICACIONES"),
                Icons.settings_suggest_outlined,
              ),
            ),
            const SizedBox(width: 20),
            Expanded(
              flex: 4,
              child: _buildBlockTitle(
                widget.loc.t("VERIFICACIÓN DE SEGURIDAD"),
                Icons.security_outlined,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        // Cards Row with IntrinsicHeight
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                flex: 3,
                child: _buildBlockCard([
                  _infoRow(
                    widget.loc.t("Version Name"),
                    _apkData['Version Name'] ?? 'N/A',
                  ),
                  _infoRow(
                    widget.loc.t("Version Code"),
                    _apkData['Version Code'] ?? 'N/A',
                  ),
                  _infoRow(
                    widget.loc.t("Min SDK"),
                    "API ${_apkData['Min SDK'] ?? 'N/A'}",
                  ),
                  _infoRow(
                    widget.loc.t("Target SDK"),
                    "API ${_apkData['Target SDK'] ?? 'N/A'}",
                  ),
                  _infoRow(
                    widget.loc.architecture,
                    _apkData['Arquitectura'] ?? 'N/A',
                  ),
                  _infoRow(widget.loc.filename, _apkData['Archivo'] ?? 'N/A'),
                ]),
              ),
              const SizedBox(width: 20),
              Expanded(
                flex: 4,
                child: _buildBlockCard([
                  _infoRow(widget.loc.schemes, _apkData['Firma'] ?? 'N/A'),
                  _infoRow(
                    widget.loc.signature,
                    firmaStatus,
                    isSuccess: isFirmaValid,
                  ),
                  _infoRow(
                    widget.loc.certificate,
                    _apkData['Certificado'] ?? 'N/A',
                  ),
                  _infoRow(
                    widget.loc.sha256,
                    _apkData['SHA-256'] ?? 'N/A',
                    isCode: true,
                  ),
                  _infoRow(
                    widget.loc.t("Verificación Jarsigner"),
                    jarsignerStatusText,
                    customColor: jarsignerStatusColor,
                  ),
                ]),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildStatusBadge(String text, IconData icon, {Color? color}) {
    final isDark = widget.isDarkMode;
    final primary = color ?? (isDark ? Colors.cyanAccent : Colors.blueAccent);
    final isCopyable =
        text.contains('.') ||
        text.contains(RegExp(r'\d')); // Simplified check for version/size

    Widget badge = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: primary.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: primary.withValues(alpha: 0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: primary),
          const SizedBox(width: 6),
          Text(
            text,
            style: TextStyle(
              fontSize: 11,
              color: primary,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );

    if (isCopyable) {
      return Tooltip(
        message: widget.loc.clickToCopy,
        child: InkWell(
          onTap: () {
            // Strip the decorative 'v' prefix if copying version
            final cleanText = text.replaceFirst(RegExp(r'^v'), '').trim();
            Clipboard.setData(ClipboardData(text: cleanText));
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Copiado: $cleanText'),
                duration: const Duration(seconds: 1),
              ),
            );
          },
          borderRadius: BorderRadius.circular(8),
          child: badge,
        ),
      );
    }

    return badge;
  }

  Widget _buildBlockTitle(String title, IconData icon) {
    final isDark = widget.isDarkMode;
    return Row(
      children: [
        Icon(
          icon,
          size: 18,
          color: isDark
              ? Colors.cyanAccent.withValues(alpha: 0.7)
              : Colors.blueAccent,
        ),
        const SizedBox(width: 8),
        Text(
          title,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w900,
            color: isDark ? Colors.white38 : Colors.blueGrey[800],
            letterSpacing: 1.0,
          ),
        ),
      ],
    );
  }

  Widget _buildBlockCard(List<Widget> children) {
    final isDark = widget.isDarkMode;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: isDark ? Colors.black12 : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.05)
              : Colors.blue.withValues(alpha: 0.08),
        ),
        boxShadow: isDark
            ? []
            : [
                BoxShadow(
                  color: Colors.blueAccent.withValues(alpha: 0.03),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
              ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }
  Widget _infoRow(
    String label,
    String value, {
    bool isCode = false,
    bool isSuccess = false,
    Color? customColor,
  }) {
    final isDark = widget.isDarkMode;
    final displayColor =
        customColor ??
        (isSuccess
            ? Colors.green
            : (isDark ? Colors.white : Colors.blueGrey[900]!));
    final bool isFilename = label == widget.loc.filename || label == widget.loc.t("Archivo");

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: isDark ? Colors.white38 : Colors.blueGrey[400],
              ),
            ),
          ),
          Expanded(
            child: isFilename
                ? Tooltip(
                    message: value,
                    child: Text(
                      value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        fontFamily: isCode ? 'Consolas' : null,
                        fontWeight: FontWeight.w600,
                        color: displayColor,
                      ),
                    ),
                  )
                : SelectableText(
                    value,
                    maxLines: (label == "SHA-256" || label == "Certificado")
                        ? null
                        : 1,
                    style: TextStyle(
                      fontSize: 14,
                      fontFamily: isCode ? 'Consolas' : null,
                      fontWeight: FontWeight.w600,
                      color: displayColor,
                    ),
                  ),
          ),
        ],
      ),
    );
  }
  Widget _buildCompactInstallActions() {
    final isD = widget.isDarkMode;
    final isDeviceConnected = !widget.adbStatus.contains(
      widget.loc.statusDisconnected,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (isDeviceConnected)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.info_outline,
                size: 14,
                color: isD ? Colors.cyanAccent : Colors.blueGrey[400],
              ),
              const SizedBox(width: 6),
              Text(
                _installStatus == "installed"
                    ? '${widget.loc.t("Instalada")} (v$_installedVersion)'
                    : _installStatus == "update"
                    ? '${widget.loc.t("Instalada")} v$_installedVersion'
                    : widget.loc.t("No instalada"),
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: isD ? Colors.white70 : Colors.blueGrey[600],
                ),
              ),
            ],
          ),
        if (isDeviceConnected) const SizedBox(height: 12),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isDeviceConnected) ...[
              // ── INSTALAR / ACTUALIZAR: visible siempre ──
              if (_installStatus == "update")
                PanelBtnCompact(
                  onPressed: _isInstalling ? null : _installCurrentApk,
                  label: _isInstalling
                      ? widget.loc.t("ACTUALIZANDO...")
                      : widget.loc.t("ACTUALIZAR"),
                  icon: _isInstalling ? Icons.sync : Icons.system_update,
                  color: Colors.orangeAccent,
                  tooltip: widget.loc.updateTooltip,
                )
              else
                PanelBtnCompact(
                  // Activo cuando la app NO está instalada o el estado es desconocido
                  onPressed:
                      ((_installStatus == "notInstalled" ||
                              _installStatus == "unknown") &&
                          !_isInstalling)
                      ? _installCurrentApk
                      : null,
                  label: _isInstalling
                      ? widget.loc.t("INSTALANDO...")
                      : widget.loc.t("INSTALAR"),
                  icon: _isInstalling ? Icons.sync : Icons.download,
                  color: Colors.black,
                  isHighContrast: true,
                  tooltip:
                      (_installStatus == "notInstalled" ||
                          _installStatus == "unknown")
                      ? widget.loc.installApkTooltip
                      : widget.loc.appAlreadyInstalled,
                ),
              const SizedBox(width: 8),
              // ── DESINSTALAR: split button (APK actual + cualquier app) ──
              _SplitUninstallButton(
                isUninstalling: _isUninstalling,
                canUninstall:
                    (_installStatus == "installed" ||
                        _installStatus == "update") &&
                    !_isUninstalling,
                onUninstall: _uninstallPackage,
                onUninstallAny: _showUninstallByPackageDialog,
                loc: widget.loc,
              ),
              const SizedBox(width: 8),
            ],
            PanelBtnCompact(
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (context) => SigningDialog(
                    loc: widget.loc,
                    isDarkMode: widget.isDarkMode,
                    sdk: widget.sdk,
                    initialApkPath: _apkPath,
                    showOnlySign: true,
                  ),
                );
              },
              label: widget.loc.t("FIRMAR"),
              icon: Icons.vpn_key_outlined,
              color: Colors.blueAccent,
              tooltip: widget.loc.signTooltip,
              isHighContrast: true,
            ),
          ],
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Split button: DESINSTALAR (APK actual) + botón flecha → desinstalar cualquier app
// ─────────────────────────────────────────────────────────────────────────────
class _SplitUninstallButton extends StatelessWidget {
  final bool isUninstalling;
  final bool canUninstall;
  final VoidCallback onUninstall;
  final VoidCallback onUninstallAny;
  final AppLocale loc;

  const _SplitUninstallButton({
    required this.isUninstalling,
    required this.canUninstall,
    required this.onUninstall,
    required this.onUninstallAny,
    required this.loc,
  });

  @override
  Widget build(BuildContext context) {
    const color = Colors.redAccent;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Botón principal: desinstala el APK analizado
        SizedBox(
          height: 38,
          child: Tooltip(
            message: canUninstall
                ? loc.uninstallApkTooltip
                : loc.appNotInstalled,
            child: ElevatedButton.icon(
              onPressed: canUninstall ? onUninstall : null,
              icon: isUninstalling
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.delete_outline, size: 16),
              label: Text(
                isUninstalling
                    ? loc.t('DESINSTALANDO...')
                    : loc.t('DESINSTALAR'),
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: canUninstall ? color : Colors.grey[700],
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                shape: const RoundedRectangleBorder(
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(8),
                    bottomLeft: Radius.circular(8),
                  ),
                ),
                elevation: 0,
              ),
            ),
          ),
        ),
        // Separador visual
        Container(width: 1, height: 38, color: Colors.white24),
        // Botón flecha: abre el diálogo de desinstalar cualquier app
        SizedBox(
          height: 38,
          width: 36,
          child: Tooltip(
            message: loc.uninstallAnyAppTooltip,
            child: ElevatedButton(
              onPressed: onUninstallAny,
              style: ElevatedButton.styleFrom(
                backgroundColor: color,
                foregroundColor: Colors.white,
                padding: EdgeInsets.zero,
                shape: const RoundedRectangleBorder(
                  borderRadius: BorderRadius.only(
                    topRight: Radius.circular(10),
                    bottomRight: Radius.circular(10),
                  ),
                ),
                elevation: 0,
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Icon(Icons.keyboard_arrow_down, size: 18),
            ),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Diálogo: Desinstalar cualquier app del dispositivo con buscador
// ─────────────────────────────────────────────────────────────────────────────
class _UninstallPackageDialog extends StatefulWidget {
  final SDKService sdk;
  final bool isDark;
  final AppLocale loc;
  final VoidCallback? onUninstalled;

  const _UninstallPackageDialog({
    required this.sdk,
    required this.isDark,
    required this.loc,
    this.onUninstalled,
  });

  @override
  State<_UninstallPackageDialog> createState() =>
      _UninstallPackageDialogState();
}

class _UninstallPackageDialogState extends State<_UninstallPackageDialog> {
  final TextEditingController _filterCtrl = TextEditingController();
  Map<String, String> _allPackageMap = {};
  List<String> _allPackages = [];
  List<String> _filtered = [];
  String? _selected;
  bool _isLoading = true;
  bool _isUninstalling = false;
  String? _statusMessage;
  bool _statusOk = false;

  @override
  void initState() {
    super.initState();
    _filterCtrl.addListener(_applyFilter);
    _loadPackages();
  }

  @override
  void dispose() {
    _filterCtrl.removeListener(_applyFilter);
    _filterCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadPackages() async {
    setState(() => _isLoading = true);
    final map = await widget.sdk.getPackagesWithNames();
    final list = map.keys.toList();

    // Sort by App Label (value), case-insensitive
    list.sort((a, b) {
      final labelA = map[a]?.toLowerCase() ?? a.toLowerCase();
      final labelB = map[b]?.toLowerCase() ?? b.toLowerCase();
      return labelA.compareTo(labelB);
    });

    if (mounted) {
      setState(() {
        _allPackageMap = map;
        _allPackages = list;
        _filtered = list;
        _isLoading = false;
      });
    }
  }

  void _applyFilter() {
    final q = _filterCtrl.text.toLowerCase().trim();
    setState(() {
      _filtered = q.isEmpty
          ? _allPackages
          : _allPackages.where((p) {
              final label = _allPackageMap[p]?.toLowerCase() ?? '';
              final pkg = p.toLowerCase();
              return label.contains(q) || pkg.contains(q);
            }).toList();
      // Deselect if no longer visible
      if (_selected != null && !_filtered.contains(_selected)) {
        _selected = null;
      }
    });
  }

  Future<void> _doUninstall() async {
    if (_selected == null) return;
    final pkg = _selected!;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: widget.isDark ? const Color(0xFF1E293B) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(
              Icons.warning_amber_rounded,
              color: Colors.orangeAccent,
              size: 22,
            ),
            const SizedBox(width: 8),
            Text(
              widget.loc.t('Confirmar desinstalación'),
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        content: RichText(
          text: TextSpan(
            style: TextStyle(
              fontSize: 13,
              color: widget.isDark ? Colors.white70 : Colors.black87,
            ),
            children: [
              TextSpan(text: '${widget.loc.t('¿Desinstalar')} '),
              TextSpan(
                text: _allPackageMap[pkg] ?? pkg,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.redAccent,
                ),
              ),
              TextSpan(
                text: '\n($pkg)',
                style: TextStyle(
                  fontSize: 10,
                  fontFamily: 'Consolas',
                  color: widget.isDark ? Colors.white38 : Colors.black38,
                ),
              ),
              TextSpan(text: ' ${widget.loc.t('del dispositivo?')}'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(widget.loc.t('CANCELAR')),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: Text(widget.loc.t('DESINSTALAR')),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() {
      _isUninstalling = true;
      _statusMessage = null;
    });

    final code = await widget.sdk.runCommand(widget.sdk.adbPath, [
      'uninstall',
      pkg,
    ]);

    if (!mounted) return;

    final success = code == 0;
    final label = _allPackageMap[pkg] ?? pkg;
    setState(() {
      _isUninstalling = false;
      _statusOk = success;
      _statusMessage = success
          ? '✅ ${widget.loc.t("Desinstalado con éxito")}: $label'
          : '❌ ${widget.loc.t("Error al desinstalar")} (código $code)';
    });

    if (success) {
      // Remove from local list
      setState(() {
        _allPackageMap.remove(pkg);
        _allPackages.remove(pkg);
        _filtered.remove(pkg);
        _selected = null;
      });
      widget.onUninstalled?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isD = widget.isDark;
    final bg = isD ? const Color(0xFF1E293B) : Colors.white;
    final cardBg = isD ? const Color(0xFF0F172A) : const Color(0xFFF5F7FA);
    final borderColor = isD
        ? Colors.white.withValues(alpha: 0.08)
        : Colors.blueGrey.withValues(alpha: 0.15);
    final textColor = isD ? Colors.white : Colors.black87;

    return Dialog(
      backgroundColor: bg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        width: 520,
        constraints: const BoxConstraints(maxHeight: 620),
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header ──
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.redAccent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.delete_sweep_outlined,
                    color: Colors.redAccent,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.loc.t('Desinstalar app del dispositivo'),
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: textColor,
                        ),
                      ),
                      Text(
                        _isLoading
                            ? widget.loc.t('Cargando paquetes...')
                            : '${_allPackages.length} ${widget.loc.t("paquetes instalados")}',
                        style: TextStyle(
                          fontSize: 11,
                          color: isD ? Colors.white38 : Colors.blueGrey[400],
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: Icon(
                    Icons.close,
                    color: isD ? Colors.white38 : Colors.black38,
                  ),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // ── Buscador ──
            TextField(
              controller: _filterCtrl,
              autofocus: true,
              style: TextStyle(fontSize: 13, color: textColor),
              decoration: InputDecoration(
                hintText: widget.loc.t('Buscar por nombre o paquete...'),
                hintStyle: TextStyle(
                  fontSize: 12,
                  color: isD ? Colors.white30 : Colors.blueGrey[300],
                ),
                prefixIcon: const Icon(Icons.search, size: 18),
                suffixIcon: _filterCtrl.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 16),
                        onPressed: () => _filterCtrl.clear(),
                      )
                    : null,
                filled: true,
                fillColor: cardBg,
                contentPadding: const EdgeInsets.symmetric(
                  vertical: 10,
                  horizontal: 14,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: borderColor),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: borderColor),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: Colors.redAccent),
                ),
              ),
            ),
            const SizedBox(height: 12),

            // ── Lista de paquetes ──
            Expanded(
              child: _isLoading
                  ? const Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircularProgressIndicator(color: Colors.redAccent),
                          SizedBox(height: 12),
                          Text(
                            'Cargando paquetes instalados...',
                            style: TextStyle(fontSize: 12),
                          ),
                        ],
                      ),
                    )
                  : _filtered.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.search_off,
                            size: 36,
                            color: isD ? Colors.white24 : Colors.blueGrey[200],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            widget.loc.t('No se encontraron paquetes'),
                            style: TextStyle(
                              fontSize: 13,
                              color: isD
                                  ? Colors.white38
                                  : Colors.blueGrey[400],
                            ),
                          ),
                        ],
                      ),
                    )
                  : Container(
                      decoration: BoxDecoration(
                        color: cardBg,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: borderColor),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: ListView.separated(
                          itemCount: _filtered.length,
                          separatorBuilder: (_, _) =>
                              Divider(height: 1, color: borderColor),
                          itemBuilder: (ctx, i) {
                            final pkg = _filtered[i];
                            final isSelected = pkg == _selected;
                            return InkWell(
                              onTap: () => setState(() => _selected = pkg),
                              borderRadius: i == 0
                                  ? const BorderRadius.only(
                                      topLeft: Radius.circular(12),
                                      topRight: Radius.circular(12),
                                    )
                                  : i == _filtered.length - 1
                                  ? const BorderRadius.only(
                                      bottomLeft: Radius.circular(12),
                                      bottomRight: Radius.circular(12),
                                    )
                                  : BorderRadius.zero,
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 150),
                                color: isSelected
                                    ? Colors.redAccent.withValues(alpha: 0.15)
                                    : Colors.transparent,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 10,
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      isSelected
                                          ? Icons.radio_button_checked
                                          : Icons.radio_button_off,
                                      size: 16,
                                      color: isSelected
                                          ? Colors.redAccent
                                          : (isD
                                                ? Colors.white24
                                                : Colors.blueGrey[300]),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            _allPackageMap[pkg] ?? pkg,
                                            style: TextStyle(
                                              fontSize: 13,
                                              fontWeight: isSelected
                                                  ? FontWeight.bold
                                                  : FontWeight.w500,
                                              color: isSelected
                                                  ? Colors.redAccent
                                                  : textColor,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            pkg,
                                            style: TextStyle(
                                              fontSize: 10,
                                              fontFamily: 'Consolas',
                                              color: isSelected
                                                  ? Colors.redAccent.withValues(alpha: 0.7)
                                                  : (isD ? Colors.white38 : Colors.black38),
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
            ),

            // ── Status message ──
            if (_statusMessage != null) ...[
              const SizedBox(height: 10),
              AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: _statusOk
                      ? Colors.green.withValues(alpha: 0.12)
                      : Colors.redAccent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: _statusOk
                        ? Colors.green.withValues(alpha: 0.3)
                        : Colors.redAccent.withValues(alpha: 0.3),
                  ),
                ),
                child: Text(
                  _statusMessage!,
                  style: TextStyle(
                    fontSize: 12,
                    color: _statusOk ? Colors.greenAccent : Colors.redAccent,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],

            // ── Footer buttons ──
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Reload button
                TextButton.icon(
                  onPressed: _isLoading ? null : _loadPackages,
                  icon: const Icon(Icons.refresh, size: 16),
                  label: Text(
                    widget.loc.t('Recargar'),
                    style: const TextStyle(fontSize: 12),
                  ),
                  style: TextButton.styleFrom(
                    foregroundColor: isD
                        ? Colors.white54
                        : Colors.blueGrey[400],
                  ),
                ),
                Row(
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: Text(widget.loc.t('CERRAR')),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton.icon(
                      onPressed: (_selected != null && !_isUninstalling)
                          ? _doUninstall
                          : null,
                      icon: _isUninstalling
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.delete_outline, size: 16),
                      label: Text(
                        _isUninstalling
                            ? widget.loc.t('DESINSTALANDO...')
                            : widget.loc.t('DESINSTALAR'),
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _selected != null
                            ? Colors.redAccent
                            : Colors.grey[700],
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        elevation: 0,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Static function to run in a separate isolate for icon extraction

Future<Uint8List?> _extractIconInBackground(Map<String, String> params) async {
  final path = params['apkPath']!;
  final iconPath = params['iconPath']!;

  try {
    final bytes = await File(path).readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes);

    // 1. Intento exacto de AAPT si está soportado (PNG/WEBP/JPG)
    if (iconPath.isNotEmpty && !iconPath.toLowerCase().endsWith('.xml')) {
      for (final file in archive) {
        if (file.name == iconPath) {
          return file.content;
        }
      }
    }

    // 2. Si AAPT devolvió la ruta de un XML vectorizado (Adaptive Icon),
    // deducimos su nombre original (ej: "ic_launcher") para buscar su rasterización.
    String baseIconName = 'ic_launcher';
    if (iconPath.isNotEmpty) {
      final parts = iconPath.split('/');
      final fileName = parts.last;
      baseIconName = fileName.split('.').first.toLowerCase();
    }

    // 3. Búsqueda exhaustiva del icono en formato renderizable (PNG/WEBP/JPG)
    ArchiveFile? bestCandidate;
    int maxScore = -1;
    int maxSize = 0;

    for (final file in archive) {
      final name = file.name.toLowerCase();

      // Filtrar solo formatos renderizables por Image.memory()
      if (!name.endsWith('.png') &&
          !name.endsWith('.jpg') &&
          !name.endsWith('.webp')) {
        continue;
      }

      // Evitar iconos de librerías del sistema, que siempre son pequeños, y otros elementos no deseados
      if (name.contains('androidx') ||
          name.contains('notification') ||
          name.contains('material_') ||
          name.contains('common_') ||
          name.contains('google_') ||
          name.contains('splash') ||
          name.contains('background') ||
          name.contains('bg_')) {
        continue;
      }

      // Asegurar que está dentro de res/mipmap o res/drawable
      if (!name.contains('res/mipmap') && !name.contains('res/drawable')) {
        continue;
      }

      final nameWithoutExt = p.basenameWithoutExtension(name);

      // Calcular puntuación de relevancia del icono. Queremos preferir los iconos pre-renderizados
      // completos (legacy/round) sobre las capas individuales de iconos adaptativos (foreground).
      int score = 0;
      if (nameWithoutExt == baseIconName) {
        score = 100;
      } else if (nameWithoutExt == '${baseIconName}_round' ||
          nameWithoutExt == 'ic_launcher_round') {
        score = 100;
      } else if (nameWithoutExt == 'ic_launcher' ||
          nameWithoutExt == 'app_icon' ||
          nameWithoutExt == 'launcher_icon') {
        score = 100;
      } else if (nameWithoutExt == '${baseIconName}_foreground' ||
          nameWithoutExt == 'ic_launcher_foreground') {
        score = 50;
      } else if (baseIconName.isNotEmpty &&
          nameWithoutExt.startsWith('${baseIconName}_')) {
        score = 40;
      }

      if (score > 0) {
        // Seleccionamos por mayor puntuación, o por mayor tamaño en caso de empate
        if (score > maxScore) {
          maxScore = score;
          maxSize = file.size;
          bestCandidate = file;
        } else if (score == maxScore && file.size > maxSize) {
          maxSize = file.size;
          bestCandidate = file;
        }
      }
    }

    // 4. Último Recurso (Estilo Ostorlab Extremo): Si todos los heurísticos anteriores fallaron,
    // o el nombre base era muy raro, simplemente extraemos la imagen PNG/WEBP/JPG más pesada
    // que se halle en `res/mipmap` o `res/drawable` y que contenga "icon" o "logo" en el nombre del archivo,
    // ignorando nombres oficiales.
    if (bestCandidate == null) {
      maxSize = 0;
      for (final file in archive) {
        final name = file.name.toLowerCase();
        final filename = p.basename(name);

        if (!name.endsWith('.png') &&
            !name.endsWith('.jpg') &&
            !name.endsWith('.webp')) {
          continue;
        }
        if (name.contains('androidx') ||
            name.contains('notification') ||
            name.contains('splash') ||
            name.contains('background') ||
            name.contains('bg_')) {
          continue;
        }
        if (!name.contains('res/mipmap') && !name.contains('res/drawable')) {
          continue;
        }

        if (filename.contains('icon') || filename.contains('logo')) {
          if (file.size > maxSize) {
            maxSize = file.size;
            bestCandidate = file;
          }
        }
      }
    }

    // 5. Nivel Dios (Falla Total Absoluta): Escanear todas las imágenes PNG/WEBP sin importar su ruta.
    // Ignoraremos filtros de carpetas y barreremos el ZIP entero buscando la imagen PNG más pesada
    // que no parezca un elemento de interfaz o background.
    if (bestCandidate == null) {
      maxSize = 0;
      for (final file in archive) {
        final name = file.name.toLowerCase();

        if (!name.endsWith('.png') && !name.endsWith('.webp')) {
          continue;
        }
        if (name.contains('androidx') ||
            name.contains('splash') ||
            name.contains('background') ||
            name.contains('bg_') ||
            name.contains('nav_') ||
            name.contains('btn_')) {
          continue;
        }

        if (file.size > maxSize) {
          maxSize = file.size;
          bestCandidate = file;
        }
      }
    }

    return bestCandidate?.content;
  } catch (_) {}
  return null;
}

// ---------------------------------------------------------------------------
// Optimized Commands Dialog — uses ListView.builder for lazy rendering so
// that large outputs (e.g. jarsigner with thousands of lines) open instantly.
// Lines are split once per tab in initState and cached in lists.
// ---------------------------------------------------------------------------
class _CommandsDialog extends StatefulWidget {
  final AppLocale loc;
  final bool isDark;
  final String rawAapt;
  final String rawApksigner;
  final String rawJarsigner;

  const _CommandsDialog({
    required this.loc,
    required this.isDark,
    required this.rawAapt,
    required this.rawApksigner,
    required this.rawJarsigner,
  });

  @override
  State<_CommandsDialog> createState() => _CommandsDialogState();
}

class _CommandsDialogState extends State<_CommandsDialog> {
  static const _tabs = ['AAPT', 'APKSIGNER', 'JARSIGNER'];

  int _selectedIndex = 0;

  /// Pre-split lines for each tab — populated once in initState.
  late final List<List<String>> _lines;

  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    // Split each raw output into lines once. Empty output → single placeholder.
    _lines = [
      _splitLines(widget.rawAapt),
      _splitLines(widget.rawApksigner),
      _splitLines(widget.rawJarsigner),
    ];
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  List<String> _splitLines(String raw) {
    if (raw.trim().isEmpty) return ['No hay datos disponibles'];
    return raw.split('\n');
  }

  void _copyCurrentTab() {
    final text = _lines[_selectedIndex].join('\n');
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Copiado al portapapeles'),
        duration: Duration(seconds: 1),
      ),
    );
  }

  void _selectTab(int index) {
    if (_selectedIndex == index) return;
    setState(() {
      _selectedIndex = index;
      // Jump to top instantly when switching tabs
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(0);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;
    final bgColor = isDark
        ? Colors.white.withValues(alpha: 0.04)
        : Colors.black.withValues(alpha: 0.04);
    final lines = _lines[_selectedIndex];

    return AlertDialog(
      title: Text(widget.loc.t('Comandos de Análisis')),
      content: SizedBox(
        width: 820,
        height: 520,
        child: Column(
          children: [
            // Tab selector
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(_tabs.length, (i) {
                final isActive = _selectedIndex == i;
                final lineCount = _lines[i].length;
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: ChoiceChip(
                    label: Text(
                      '${_tabs[i]} ($lineCount)',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: isActive
                            ? FontWeight.bold
                            : FontWeight.normal,
                      ),
                    ),
                    selected: isActive,
                    onSelected: (_) => _selectTab(i),
                  ),
                );
              }),
            ),
            const SizedBox(height: 8),
            // Lazy-rendered line list
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: bgColor,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Scrollbar(
                  controller: _scrollController,
                  thumbVisibility: true,
                  child: ListView.builder(
                    controller: _scrollController,
                    itemCount: lines.length,
                    // Each line item is lightweight: a simple Text widget.
                    itemBuilder: (context, index) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 0,
                        ),
                        child: SelectableText(
                          lines[index],
                          style: TextStyle(
                            fontFamily: 'Consolas',
                            fontSize: 11,
                            height: 1.45,
                            color: isDark ? Colors.white70 : Colors.black87,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton.icon(
          onPressed: _copyCurrentTab,
          icon: const Icon(Icons.copy, size: 14),
          label: Text(widget.loc.t('COPIAR TODO')),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(widget.loc.t('CERRAR')),
        ),
      ],
    );
  }
}

class _CircularActionIcon extends StatefulWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;
  final bool isDark;
  final Color? color;

  const _CircularActionIcon({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    required this.isDark,
    this.color,
  });

  @override
  State<_CircularActionIcon> createState() => _CircularActionIconState();
}

class _CircularActionIconState extends State<_CircularActionIcon> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final bool isEnabled = widget.onTap != null;
    final Color iconColor =
        widget.color ??
        (widget.isDark ? Colors.blueGrey[300]! : Colors.blueGrey);

    return Tooltip(
      message: widget.tooltip,
      child: MouseRegion(
        onEnter: (_) => isEnabled ? setState(() => _isHovered = true) : null,
        onExit: (_) => isEnabled ? setState(() => _isHovered = false) : null,
        child: InkWell(
          onTap: widget.onTap,
          borderRadius: BorderRadius.circular(20),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _isHovered && isEnabled
                  ? (widget.isDark
                        ? Colors.white.withValues(alpha: 0.08)
                        : Colors.black.withValues(alpha: 0.05))
                  : Colors.transparent,
            ),
            child: Icon(
              widget.icon,
              size: 20,
              color: isEnabled ? iconColor : Colors.grey.withValues(alpha: 0.5),
            ),
          ),
        ),
      ),
    );
  }
}

class _ExtractPackageDialog extends StatefulWidget {
  final SDKService sdk;
  final bool isDark;
  final AppLocale loc;
  final Function(String) onExtracted;

  const _ExtractPackageDialog({
    required this.sdk,
    required this.isDark,
    required this.loc,
    required this.onExtracted,
  });

  @override
  State<_ExtractPackageDialog> createState() => _ExtractPackageDialogState();
}

class _ExtractPackageDialogState extends State<_ExtractPackageDialog> {
  final TextEditingController _filterCtrl = TextEditingController();
  Map<String, String> _allPackageMap = {};
  List<String> _allPackages = [];
  List<String> _filtered = [];
  String? _selected;
  bool _isLoading = true;
  bool _isExtracting = false;
  String? _statusMessage;
  bool _statusOk = false;

  @override
  void initState() {
    super.initState();
    _filterCtrl.addListener(_applyFilter);
    _loadPackages();
  }

  @override
  void dispose() {
    _filterCtrl.removeListener(_applyFilter);
    _filterCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadPackages() async {
    setState(() => _isLoading = true);
    final map = await widget.sdk.getPackagesWithNames();
    final list = map.keys.toList();

    // Sort by App Label (value), case-insensitive
    list.sort((a, b) {
      final labelA = map[a]?.toLowerCase() ?? a.toLowerCase();
      final labelB = map[b]?.toLowerCase() ?? b.toLowerCase();
      return labelA.compareTo(labelB);
    });

    if (mounted) {
      setState(() {
        _allPackageMap = map;
        _allPackages = list;
        _filtered = list;
        _isLoading = false;
      });
    }
  }

  void _applyFilter() {
    final q = _filterCtrl.text.toLowerCase().trim();
    setState(() {
      _filtered = q.isEmpty
          ? _allPackages
          : _allPackages.where((p) {
              final label = _allPackageMap[p]?.toLowerCase() ?? '';
              final pkg = p.toLowerCase();
              return label.contains(q) || pkg.contains(q);
            }).toList();
      // Deselect if no longer visible
      if (_selected != null && !_filtered.contains(_selected)) {
        _selected = null;
      }
    });
  }

  Future<void> _doExtract({bool onlyDownload = false}) async {
    if (_selected == null) return;
    final pkg = _selected!;

    String? outputPath;
    if (onlyDownload) {
      final label = _allPackageMap[pkg] ?? pkg;
      final sanitizedName = label.replaceAll(RegExp(r'[\\/:*?"<>| ]'), '_');
      outputPath = await FilePicker.platform.saveFile(
        dialogTitle: widget.loc.t('Guardar APK Extraída'),
        fileName: '$sanitizedName.apk',
        type: FileType.custom,
        allowedExtensions: ['apk'],
      );
      if (outputPath == null) return;
    }

    setState(() {
      _isExtracting = true;
      _statusMessage = widget.loc.t("Obteniendo ruta del paquete...");
      _statusOk = true;
    });

    try {
      // 1. Get path on device
      final pathRes = await widget.sdk.runAdb(['shell', 'pm', 'path', pkg]);
      if (pathRes.exitCode != 0) {
        throw Exception("Failed to find path for package $pkg");
      }

      final outLines = pathRes.stdout.toString().split('\n');
      String? remotePath;
      for (var line in outLines) {
        if (line.startsWith('package:')) {
          remotePath = line.replaceFirst('package:', '').trim();
          break;
        }
      }

      if (remotePath == null || remotePath.isEmpty) {
        throw Exception("Could not parse package path on device");
      }

      setState(() {
        _statusMessage = widget.loc.t("Extrayendo archivo APK...");
      });

      // 2. Prepare local path
      String localPath;
      if (onlyDownload) {
        localPath = outputPath!;
      } else {
        final tempDir = Directory.systemTemp;
        final localFolder = Directory(p.join(tempDir.path, 'isv_extracted'));
        if (!localFolder.existsSync()) {
          localFolder.createSync(recursive: true);
        }
        localPath = p.join(localFolder.path, '$pkg.apk');
      }

      // 3. Pull file
      final pullRes = await widget.sdk.runAdb(['pull', remotePath, localPath]);
      if (pullRes.exitCode != 0) {
        throw Exception("Failed to pull APK from device (exit code ${pullRes.exitCode})");
      }

      if (mounted) {
        if (onlyDownload) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('${widget.loc.t("APK guardada en")} $localPath'),
              duration: const Duration(seconds: 3),
              backgroundColor: Colors.green,
            ),
          );
          Navigator.pop(context);
        } else {
          widget.onExtracted(localPath);
          Navigator.pop(context);
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isExtracting = false;
          _statusOk = false;
          _statusMessage = '❌ ${widget.loc.t("Error al extraer")}: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isD = widget.isDark;
    final bg = isD ? const Color(0xFF1E293B) : Colors.white;
    final cardBg = isD ? const Color(0xFF0F172A) : const Color(0xFFF5F7FA);
    final borderColor = isD
        ? Colors.white.withValues(alpha: 0.08)
        : Colors.blueGrey.withValues(alpha: 0.15);
    final textColor = isD ? Colors.white : Colors.black87;
    final primaryColor = isD ? Colors.cyanAccent : Colors.blueAccent;
    return Dialog(
      backgroundColor: bg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        width: 520,
        constraints: const BoxConstraints(maxHeight: 620),
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header ──
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: primaryColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    Icons.developer_mode_outlined,
                    color: primaryColor,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.loc.t('Extraer APK del dispositivo'),
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: textColor,
                        ),
                      ),
                      Text(
                        _isLoading
                            ? widget.loc.t('Cargando paquetes...')
                            : '${_allPackages.length} ${widget.loc.t("paquetes instalados")}',
                        style: TextStyle(
                          fontSize: 11,
                          color: isD ? Colors.white38 : Colors.blueGrey[400],
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: Icon(
                    Icons.close,
                    color: isD ? Colors.white38 : Colors.black38,
                  ),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // ── Buscador ──
            TextField(
              controller: _filterCtrl,
              autofocus: true,
              style: TextStyle(fontSize: 13, color: textColor),
              decoration: InputDecoration(
                hintText: widget.loc.t('Buscar por nombre o paquete...'),
                hintStyle: TextStyle(
                  fontSize: 12,
                  color: isD ? Colors.white30 : Colors.blueGrey[300],
                ),
                prefixIcon: const Icon(Icons.search, size: 18),
                suffixIcon: _filterCtrl.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 16),
                        onPressed: () => _filterCtrl.clear(),
                      )
                    : null,
                filled: true,
                fillColor: cardBg,
                contentPadding: const EdgeInsets.symmetric(
                  vertical: 10,
                  horizontal: 14,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: borderColor),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: borderColor),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: primaryColor),
                ),
              ),
            ),
            const SizedBox(height: 12),

            // ── Lista de paquetes ──
            Expanded(
              child: _isLoading
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircularProgressIndicator(color: primaryColor),
                          const SizedBox(height: 12),
                          const Text(
                            'Cargando paquetes instalados...',
                            style: TextStyle(fontSize: 12),
                          ),
                        ],
                      ),
                    )
                  : _filtered.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.search_off,
                            size: 36,
                            color: isD ? Colors.white24 : Colors.blueGrey[200],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            widget.loc.t('No se encontraron paquetes'),
                            style: TextStyle(
                              fontSize: 13,
                              color: isD
                                  ? Colors.white38
                                  : Colors.blueGrey[400],
                            ),
                          ),
                        ],
                      ),
                    )
                  : Container(
                      decoration: BoxDecoration(
                        color: cardBg,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: borderColor),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: ListView.separated(
                          itemCount: _filtered.length,
                          separatorBuilder: (_, _) =>
                              Divider(height: 1, color: borderColor),
                          itemBuilder: (ctx, i) {
                            final pkg = _filtered[i];
                            final isSelected = pkg == _selected;
                            return InkWell(
                              onTap: () => setState(() => _selected = pkg),
                              borderRadius: i == 0
                                  ? const BorderRadius.only(
                                      topLeft: Radius.circular(12),
                                      topRight: Radius.circular(12),
                                    )
                                  : i == _filtered.length - 1
                                  ? const BorderRadius.only(
                                      bottomLeft: Radius.circular(12),
                                      bottomRight: Radius.circular(12),
                                    )
                                  : BorderRadius.zero,
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 150),
                                color: isSelected
                                    ? primaryColor.withValues(alpha: 0.15)
                                    : Colors.transparent,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 10,
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      isSelected
                                          ? Icons.radio_button_checked
                                          : Icons.radio_button_off,
                                      size: 16,
                                      color: isSelected
                                          ? primaryColor
                                          : (isD
                                                ? Colors.white24
                                                : Colors.blueGrey[300]),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            _allPackageMap[pkg] ?? pkg,
                                            style: TextStyle(
                                              fontSize: 13,
                                              fontWeight: isSelected
                                                  ? FontWeight.bold
                                                  : FontWeight.w500,
                                              color: isSelected
                                                  ? primaryColor
                                                  : textColor,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            pkg,
                                            style: TextStyle(
                                              fontSize: 10,
                                              fontFamily: 'Consolas',
                                              color: isSelected
                                                  ? primaryColor.withValues(alpha: 0.7)
                                                  : (isD ? Colors.white38 : Colors.black38),
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
            ),

            // ── Status message ──
            if (_statusMessage != null) ...[
              const SizedBox(height: 10),
              AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: _statusOk
                      ? primaryColor.withValues(alpha: 0.12)
                      : Colors.redAccent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: _statusOk
                        ? primaryColor.withValues(alpha: 0.3)
                        : Colors.redAccent.withValues(alpha: 0.3),
                  ),
                ),
                child: Text(
                  _statusMessage!,
                  style: TextStyle(
                    fontSize: 12,
                    color: _statusOk ? primaryColor : Colors.redAccent,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],

            // ── Footer buttons ──
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Reload button
                TextButton.icon(
                  onPressed: _isLoading ? null : _loadPackages,
                  icon: const Icon(Icons.refresh, size: 16),
                  label: Text(
                    widget.loc.t('Recargar'),
                    style: const TextStyle(fontSize: 12),
                  ),
                  style: TextButton.styleFrom(
                    foregroundColor: isD
                        ? Colors.white54
                        : Colors.blueGrey[400],
                  ),
                ),
                Row(
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: Text(widget.loc.t('CERRAR')),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton.icon(
                      onPressed: (_selected != null && !_isExtracting)
                          ? _doExtract
                          : null,
                      icon: _isExtracting
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.download, size: 16),
                      label: Text(
                        _isExtracting
                            ? widget.loc.t('EXTRAYENDO...')
                            : widget.loc.t('EXTRAER Y ANALIZAR'),
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _selected != null
                            ? primaryColor
                            : (isD ? const Color(0xFF334155) : Colors.grey[300]),
                        foregroundColor: _selected != null
                            ? (isD && primaryColor == Colors.cyanAccent ? Colors.black : Colors.white)
                            : (isD ? Colors.white30 : Colors.black38),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        elevation: 0,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ApkIconDialog extends StatefulWidget {
  final Uint8List iconBytes;
  final String appName;
  final bool isDark;
  final AppLocale loc;
  final SDKService sdk;

  const _ApkIconDialog({
    required this.iconBytes,
    required this.appName,
    required this.isDark,
    required this.loc,
    required this.sdk,
  });

  @override
  State<_ApkIconDialog> createState() => _ApkIconDialogState();
}

class _ApkIconDialogState extends State<_ApkIconDialog> {
  bool _isSaving = false;
  bool _isCopying = false;

  Future<void> _copyIcon() async {
    setState(() => _isCopying = true);
    try {
      final ui.Codec codec = await ui.instantiateImageCodec(widget.iconBytes);
      final ui.FrameInfo frameInfo = await codec.getNextFrame();
      final ui.Image image = frameInfo.image;
      final ByteData? byteData = await image.toByteData(
        format: ui.ImageByteFormat.png,
      );
      if (byteData == null) {
        throw Exception("Could not convert to PNG");
      }
      final Uint8List standardPngBytes = byteData.buffer.asUint8List();

      final tempDir = Directory.systemTemp;
      final tempFile = File(
        p.join(tempDir.path, 'isv_apk_icon.png'),
      );
      await tempFile.writeAsBytes(standardPngBytes);

      final String psCommand =
          "Add-Type -AssemblyName System.Windows.Forms, System.Drawing; "
          "\$do = New-Object System.Windows.Forms.DataObject; "
          "\$paths = New-Object System.Collections.Specialized.StringCollection; "
          "\$paths.Add('${tempFile.path}'); "
          "\$do.SetFileDropList(\$paths); "
          "\$img = [System.Drawing.Image]::FromFile('${tempFile.path}'); "
          "\$do.SetImage(\$img); "
          "\$img.Dispose(); "
          "[System.Windows.Forms.Clipboard]::SetDataObject(\$do, \$true);";

      await Process.run('powershell', [
        '-ExecutionPolicy',
        'Bypass',
        '-Command',
        psCommand,
      ]);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(widget.loc.iconCopied),
            duration: const Duration(seconds: 2),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      widget.sdk.log("Error copying icon: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(widget.loc.iconCriticalError),
            duration: const Duration(seconds: 2),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isCopying = false);
    }
  }

  Future<void> _saveIcon() async {
    setState(() => _isSaving = true);
    try {
      final sanitizedName = widget.appName.replaceAll(RegExp(r'[\\/:*?"<>| ]'), '_');
      final String? outputPath = await FilePicker.platform.saveFile(
        dialogTitle: widget.loc.t('Guardar Icono de Aplicación'),
        fileName: '${sanitizedName}_icon.png',
        type: FileType.custom,
        allowedExtensions: ['png'],
      );

      if (outputPath == null) {
        setState(() => _isSaving = false);
        return;
      }

      final ui.Codec codec = await ui.instantiateImageCodec(widget.iconBytes);
      final ui.FrameInfo frameInfo = await codec.getNextFrame();
      final ui.Image image = frameInfo.image;
      final ByteData? byteData = await image.toByteData(
        format: ui.ImageByteFormat.png,
      );
      if (byteData == null) {
        throw Exception("Could not convert to PNG");
      }
      final Uint8List standardPngBytes = byteData.buffer.asUint8List();

      final file = File(outputPath);
      await file.writeAsBytes(standardPngBytes);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${widget.loc.t("Icono guardado en")} $outputPath'),
            duration: const Duration(seconds: 3),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      widget.sdk.log("Error saving icon: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(widget.loc.t('Error al guardar el archivo')),
            duration: const Duration(seconds: 2),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isD = widget.isDark;
    final bg = isD ? const Color(0xFF1E293B) : Colors.white;
    final textColor = isD ? Colors.white : Colors.black87;

    return Dialog(
      backgroundColor: bg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: SizedBox(
        width: 340,
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      widget.appName,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: textColor,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    icon: Icon(
                      Icons.close,
                      color: isD ? Colors.white38 : Colors.black38,
                    ),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Container(
                width: 160,
                height: 160,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isD ? Colors.black26 : Colors.grey[100],
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: isD ? Colors.white10 : Colors.black12,
                  ),
                ),
                child: Image.memory(widget.iconBytes),
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ElevatedButton.icon(
                    onPressed: _isCopying ? null : _copyIcon,
                    icon: _isCopying
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.copy, size: 16),
                    label: Text(widget.loc.t('Copiar Icono')),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isD ? Colors.white10 : Colors.grey[200],
                      foregroundColor: textColor,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    ),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton.icon(
                    onPressed: _isSaving ? null : _saveIcon,
                    icon: _isSaving
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.save, size: 16),
                    label: Text(widget.loc.t('Guardar en PC')),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isD ? Colors.cyanAccent : Colors.blueAccent,
                      foregroundColor: isD ? Colors.black : Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
