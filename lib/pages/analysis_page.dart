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

  void _analyzeAPK({String? manualPath}) async {
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

          final iconMatch =
              RegExp(r"icon-\d+='([^']*)'").firstMatch(aaptOut) ??
              RegExp(r"icon='([^']*)'").firstMatch(aaptOut);
          iconPath = iconMatch?.group(1) ?? "";

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
            // Fallback (might still fail with spaces due to Windows cmd.exe quirky quote stripping)
            signRes = await Process.run('cmd', [
              '/S',
              '/C',
              '"${widget.sdk.apksignerPath}" verify --verbose --print-certs "$path"',
            ], runInShell: true);
          }

          final String rawOutput = signRes.stdout.toString();
          final String rawError = signRes.stderr.toString();
          widget.sdk.log('🔑 apksigner exit code: ${signRes.exitCode}');
          widget.sdk.log('🔑 apksigner stdout: $rawOutput');
          widget.sdk.log('🔑 apksigner stderr: $rawError');

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
          final dnMatch = RegExp(
            r"Signer #1 certificate DN: (.*)",
          ).firstMatch(signOut);
          if (dnMatch != null) {
            certDN = dnMatch.group(1)?.trim() ?? certDN;
          }
          final shaMatch = RegExp(
            r"Signer #1 certificate SHA-256 digest: (.*)",
          ).firstMatch(signOut);
          if (shaMatch != null) sha256 = shaMatch.group(1)?.trim() ?? sha256;
        } else {
          widget.sdk.log(
            "⚠️ apksigner no encontrado en: ${widget.sdk.apksignerPath}",
          );
        }
      } catch (e) {
        widget.sdk.log("Error running apksigner: $e");
      }

      // 3. Jarsigner
      try {
        if (File(widget.sdk.jarsignerPath).existsSync()) {
          final jarRes = await Process.run(widget.sdk.jarsignerPath, [
            '-verify',
            '-verbose',
            '-certs',
            path,
          ]);
          _rawJarsigner = jarRes.stdout.toString() + jarRes.stderr.toString();
        } else {
          widget.sdk.log(
            "⚠️ jarsigner no encontrado en: ${widget.sdk.jarsignerPath}",
          );
        }
      } catch (e) {
        widget.sdk.log("Error running jarsigner: $e");
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
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('⏳ Iniciando instalación...'),
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: 2),
      ),
    );

    int code = await widget.sdk.runCommand(widget.sdk.adbPath, [
      'install',
      '-t',
      '-r',
      _apkPath!,
    ]);

    if (!mounted) return;
    setState(() => _isInstalling = false);

    // Refresh status in background — guarded internally
    unawaited(_checkInstallationStatus());

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          code == 0
              ? 'Instalación completada'
              : 'Error en la instalación ($code)',
        ),
        backgroundColor: code == 0 ? Colors.green : Colors.red,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _uninstallPackage() async {
    final pkg = _packageNameController.text.trim();
    if (pkg.isEmpty) return;
    if (!mounted) return;

    setState(() => _isUninstalling = true);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('⏳ Desinstalando aplicación...'),
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: 2),
      ),
    );

    int code = await widget.sdk.runCommand(widget.sdk.adbPath, [
      'uninstall',
      pkg,
    ]);

    if (!mounted) return;
    setState(() => _isUninstalling = false);

    unawaited(_checkInstallationStatus());

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          code == 0 ? 'Desinstalado con éxito' : 'Error al desinstalar ($code)',
        ),
        backgroundColor: code == 0 ? Colors.green : Colors.red,
        behavior: SnackBarBehavior.floating,
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
      final res = await Process.run(widget.sdk.adbPath, [
        'shell',
        'dumpsys',
        'package',
        pkg,
      ]);
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
    String currentOutput = _rawAapt;
    String selected = "AAPT";

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          if (selected == "AAPT") currentOutput = _rawAapt;
          if (selected == "APKSIGNER") currentOutput = _rawApksigner;
          if (selected == "JARSIGNER") currentOutput = _rawJarsigner;

          return AlertDialog(
            title: Text(widget.loc.t("Comandos de Análisis")),
            content: SizedBox(
              width: 800,
              height: 500,
              child: Column(
                children: [
                  RadioGroup<String>(
                    groupValue: selected,
                    onChanged: (val) {
                      setDialogState(() => selected = val!);
                    },
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _radioOption("AAPT"),
                        _radioOption("APKSIGNER"),
                        _radioOption("JARSIGNER"),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: SingleChildScrollView(
                        child: SelectableText(
                          currentOutput.isEmpty
                              ? "No hay datos disponibles"
                              : currentOutput,
                          style: const TextStyle(
                            fontFamily: 'Consolas',
                            fontSize: 11,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(widget.loc.t("CERRAR")),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _radioOption(String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Radio<String>(value: label),
        Text(label, style: const TextStyle(fontSize: 12)),
        const SizedBox(width: 8),
      ],
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
                          _CircularActionIcon(
                            icon: Icons.terminal,
                            tooltip: widget.loc.viewCommands,
                            onTap: _showCommandsDialog,
                            isDark: isDark,
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

    return Center(
      child: InkWell(
        onTap: _analyzeAPK,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          width: double.infinity,
          height: 220,
          decoration: BoxDecoration(
            color: isDark ? Colors.white.withValues(alpha: 0.03) : Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: color.withValues(alpha: 0.2),
              width: 2,
              style: BorderStyle
                  .solid, // Could use a custom dash painter for better look
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
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.file_upload_outlined, size: 40, color: color),
              ),
              const SizedBox(height: 16),
              Text(
                widget.loc.selectApk,
                style: TextStyle(
                  color: isDark ? Colors.white : Colors.black87,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                widget.loc.analysisInitialDesc,
                style: TextStyle(
                  color: isDark ? Colors.white38 : Colors.black38,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ),
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header Card
        Container(
          padding: const EdgeInsets.all(20),
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
                    ? widget.loc.copyIcon
                    : widget.loc.noIcon,
                child: InkWell(
                      onTap: _apkIconBytes != null
                          ? () async {
                              try {
                                // 1. Convertir la imagen a un PNG estándar usando el motor de Flutter
                                // Esto soluciona los problemas de PNGs optimizados de Android y WebP
                                final ui.Codec codec = await ui.instantiateImageCodec(_apkIconBytes!);
                                final ui.FrameInfo frameInfo = await codec.getNextFrame();
                                final ui.Image image = frameInfo.image;
                                final ByteData? byteData = await image.toByteData(format: ui.ImageByteFormat.png);
                                if (byteData == null) throw Exception("Could not convert to PNG");
                                final Uint8List standardPngBytes = byteData.buffer.asUint8List();

                                // 2. Guardar el PNG "limpio" en un archivo temporal
                                final tempDir = Directory.systemTemp;
                                final tempFile = File(p.join(tempDir.path, 'isv_apk_icon.png'));
                                await tempFile.writeAsBytes(standardPngBytes);

                                // 3. Copiar al portapapeles (Archivo + Imagen)
                                // Ahora que es un PNG estándar, PowerShell no fallará con OutOfMemory
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
                                  '-ExecutionPolicy', 'Bypass', '-Command', psCommand,
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
                              }
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
                              content: Text('${widget.loc.copied}: ${_apkData['Paquete']}'),
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

        const SizedBox(height: 14),

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
        const SizedBox(height: 12),
        // Cards Row with IntrinsicHeight
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                flex: 3,
                child: _buildBlockCard([
                  _infoRow(widget.loc.t("Version Name"), _apkData['Version Name'] ?? 'N/A'),
                  _infoRow(widget.loc.t("Version Code"), _apkData['Version Code'] ?? 'N/A'),
                  _infoRow(widget.loc.t("Min SDK"), "API ${_apkData['Min SDK'] ?? 'N/A'}"),
                  _infoRow(
                    widget.loc.t("Target SDK"),
                    "API ${_apkData['Target SDK'] ?? 'N/A'}",
                  ),
                  _infoRow(widget.loc.architecture, _apkData['Arquitectura'] ?? 'N/A'),
                  _infoRow(widget.loc.filename, _apkData['Archivo'] ?? 'N/A'),
                ]),
              ),
              const SizedBox(width: 20),
              Expanded(
                flex: 4,
                child: _buildBlockCard([
                  _infoRow(widget.loc.schemes, _apkData['Firma'] ?? 'N/A'),
                  _infoRow(widget.loc.signature, firmaStatus, isSuccess: isFirmaValid),
                  _infoRow(widget.loc.certificate, _apkData['Certificado'] ?? 'N/A'),
                  _infoRow(
                    widget.loc.sha256,
                    _apkData['SHA-256'] ?? 'N/A',
                    isCode: true,
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
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
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
  }) {
    final isDark = widget.isDarkMode;
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
            child: SelectableText(
              value,
              maxLines: (label == "SHA-256" || label == "Certificado")
                  ? null
                  : 1,
              style: TextStyle(
                fontSize: 14,
                fontFamily: isCode ? 'Consolas' : null,
                fontWeight: FontWeight.w600,
                color: isSuccess
                    ? Colors.green
                    : (isDark ? Colors.white : Colors.blueGrey[900]),
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
              // ── DESINSTALAR: visible siempre; deshabilitado si no instalada ──
              PanelBtnCompact(
                onPressed:
                    ((_installStatus == "installed" ||
                            _installStatus == "update") &&
                        !_isUninstalling)
                    ? _uninstallPackage
                    : null,
                label: _isUninstalling
                    ? widget.loc.t("DESINSTALANDO...")
                    : widget.loc.t("DESINSTALAR"),
                icon: _isUninstalling ? Icons.sync : Icons.delete_outline,
                color: Colors.redAccent,
                tooltip:
                    (_installStatus == "installed" ||
                        _installStatus == "update")
                    ? widget.loc.uninstallApkTooltip
                    : widget.loc.appNotInstalled,
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

    // 3. Búsqueda exhaustiva del icono en formato renderizable (PNG)
    ArchiveFile? bestCandidate;
    int maxSize = 0;

    for (final file in archive) {
      final name = file.name.toLowerCase();

      // Filtrar solo formatos renderizables por Image.memory()
      if (!name.endsWith('.png') &&
          !name.endsWith('.jpg') &&
          !name.endsWith('.webp')) {
        continue;
      }

      // Evitar iconos de librerías del sistema, que siempre son pequeños
      if (name.contains('androidx') ||
          name.contains('notification') ||
          name.contains('material_') ||
          name.contains('common_')) {
        continue;
      }

      // Prioridad a: el nombre base que nos entregó AAPT, o estándares de Android
      if (name.contains(baseIconName) ||
          name.contains('ic_launcher') ||
          name.contains('app_icon') ||
          name.contains('mipmap/ic_') ||
          name.contains('drawable/ic_')) {
        // Seleccionamos el archivo de mayor peso (resolución más alta)
        if (file.size > maxSize) {
          maxSize = file.size;
          bestCandidate = file;
        }
      }
    }

    // 4. Último Recurso (Estilo Ostorlab Extremo): Si todos los heurísticos anteriores fallaron,
    // o el nombre base era muy raro, simplemente extraemos la imagen PNG/WEBP/JPG más pesada
    // que se halle en `res/mipmap` o `res/drawable` o que contenga "icon"|"logo",
    // ignorando nombres oficiales.
    if (bestCandidate == null) {
      for (final file in archive) {
        final name = file.name.toLowerCase();

        if (!name.endsWith('.png') &&
            !name.endsWith('.jpg') &&
            !name.endsWith('.webp')) {
          continue;
        }
        if (name.contains('androidx') ||
            name.contains('notification') ||
            name.contains('splash') ||
            name.contains('background')) {
          continue;
        }

        if (name.contains('res/mipmap') ||
            name.contains('res/drawable') ||
            name.contains('icon') ||
            name.contains('logo')) {
          if (file.size > maxSize) {
            maxSize = file.size;
            bestCandidate = file;
          }
        }
      }
    }

    // 5. Nivel Dios (Falla Total Absoluta): Escanear todas las imágenes PNG sin importar su ruta.
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

    if (bestCandidate != null) {
      return bestCandidate.content;
    }
  } catch (_) {}
  return null;
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
    final Color iconColor = widget.color ?? 
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

