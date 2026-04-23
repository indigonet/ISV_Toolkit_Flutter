import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:window_manager/window_manager.dart';
import 'package:path/path.dart' as p;

import '../core/localization.dart';
import '../services/sdk_service.dart';

class SigningDialog extends StatefulWidget {
  final AppLocale loc;
  final bool isDarkMode;
  final SDKService sdk;
  final String? initialApkPath;
  final bool isDialog;
  final bool showOnlySign;

  const SigningDialog({
    super.key,
    required this.loc,
    required this.isDarkMode,
    required this.sdk,
    this.initialApkPath,
    this.isDialog = true,
    this.showOnlySign = false,
  });

  @override
  State<SigningDialog> createState() => _SigningDialogState();
}

class _SigningDialogState extends State<SigningDialog>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // Sign State
  String? _apkPath;
  String? _jksPath;
  // Create JKS State (Almacén)
  final TextEditingController _newFileNameController = TextEditingController(
    text: "mi_firma_isv",
  );
  final TextEditingController _createPassController = TextEditingController(
    text: "",
  );
  final TextEditingController _confirmPassController = TextEditingController(
    text: "",
  );

  // Create JKS State (Propietario)
  final TextEditingController _cnController = TextEditingController(
    text: "Juan Pérez",
  );
  final TextEditingController _ouController = TextEditingController(
    text: "Desarrollo",
  );
  final TextEditingController _oController = TextEditingController(
    text: "Empresa S.A.",
  );
  final TextEditingController _lController = TextEditingController(
    text: "Santiago",
  );
  final String _defaultAlias = "key0";
  final TextEditingController _aliasController = TextEditingController(
    text: "",
  );
  final TextEditingController _stController = TextEditingController(text: "RM");
  final TextEditingController _cController = TextEditingController(text: "CL");

  bool _isProcessing = false;
  bool _obscureSignPass = true;
  bool _obscureCreatePass = true;
  bool _obscureConfirmPass = true;
  String _statusMessage = "";

  @override
  void initState() {
    super.initState();
    _statusMessage = widget.loc.ready;
    _tabController = TabController(
      length: widget.showOnlySign ? 1 : 2,
      vsync: this,
    );
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        setState(() {});
      }
    });
    _apkPath = widget.initialApkPath;
  }

  @override
  void dispose() {
    _tabController.dispose();
    _newFileNameController.dispose();
    _createPassController.dispose();
    _confirmPassController.dispose();
    _cnController.dispose();
    _ouController.dispose();
    _oController.dispose();
    _lController.dispose();
    _stController.dispose();
    _aliasController.dispose();
    _cController.dispose();
    super.dispose();
  }

  void _pickApk() async {
    try { await windowManager.focus(); } catch(_) {}
    FilePickerResult? result = await FilePicker.platform.pickFiles(

      type: FileType.custom,
      allowedExtensions: ['apk'],
    );
    if (result != null) {
      setState(() => _apkPath = result.files.single.path);
    }
  }

  void _pickJks() async {
    try { await windowManager.focus(); } catch(_) {}
    FilePickerResult? result = await FilePicker.platform.pickFiles(

      type: FileType.custom,
      allowedExtensions: ['jks', 'keystore'],
    );
    if (result != null) {
      setState(() => _jksPath = result.files.single.path);
    }
  }

  void _createJKS() async {
    if (_createPassController.text.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              widget.loc.t(
                'Por favor, ingresa una contraseña para el almacén.',
              ),
            ),
          ),
        );
      }
      return;
    }

    if (_createPassController.text != _confirmPassController.text) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(widget.loc.t('Las contraseñas no coinciden.')),
          ),
        );
      }
      return;
    }

    try { await windowManager.focus(); } catch(_) {}
    String? path = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Seleccionar carpeta de destino',
    );

    if (path == null) {
      return;
    }

    setState(() {
      _isProcessing = true;
      _statusMessage = "Generando almacén de claves (JKS)...";
    });

    String aliasValue = _aliasController.text.isNotEmpty
        ? _aliasController.text
        : _defaultAlias;
    String pass = _createPassController.text;
    String cn = _cnController.text.isNotEmpty ? "CN=${_cnController.text}" : "";
    String ou = _ouController.text.isNotEmpty ? "OU=${_ouController.text}" : "";
    String o = _oController.text.isNotEmpty ? "O=${_oController.text}" : "";
    String l = _lController.text.isNotEmpty ? "L=${_lController.text}" : "";
    String st = _stController.text.isNotEmpty ? "ST=${_stController.text}" : "";
    String c = _cController.text.isNotEmpty ? "C=${_cController.text}" : "";

    List<String> dnameParts = [
      cn,
      ou,
      o,
      l,
      st,
      c,
    ].where((p) => p.isNotEmpty).toList();
    String dname = dnameParts.join(', ');
    if (dname.isEmpty) {
      dname = "CN=Unknown";
    }

    String fileName = _newFileNameController.text;
    if (!fileName.endsWith('.jks')) {
      fileName += '.jks';
    }
    String outJks = p.join(path, fileName);

    try {
      int code = await widget.sdk.runCommand(widget.sdk.keytoolPath, [
        '-genkey',
        '-v',
        '-keystore',
        outJks,
        '-alias',
        aliasValue,
        '-keyalg',
        'RSA',
        '-keysize',
        '2048',
        '-validity',
        '10000',
        '-storepass',
        pass,
        '-keypass',
        pass,
        '-dname',
        dname,
      ]);

      if (code == 0) {
        setState(() => _statusMessage = widget.loc.t("JKS creado con éxito"));
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(widget.loc.t('JKS guardado en: $outJks')),
              backgroundColor: Colors.green,
            ),
          );
          // Pre-fill the signing tab
          _jksPath = outJks;
          _createPassController.text = pass;
          _tabController.animateTo(0); // Switch to signing tab
        }
      } else {
        setState(() => _statusMessage = "${widget.loc.error} al crear JKS");
      }
    } catch (e) {
      setState(() => _statusMessage = "Error: $e");
    } finally {
      setState(() => _isProcessing = false);
    }
  }

  void _signApk() async {
    if (_apkPath == null ||
        _jksPath == null ||
        _createPassController.text.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(widget.loc.missingData)));
      return;
    }

    try { await windowManager.focus(); } catch(_) {}
    String? outputDir = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Seleccionar carpeta para guardar APK',
    );

    if (outputDir == null) {
      return;
    }

    setState(() {
      _isProcessing = true;
      _statusMessage = "Firmando aplicación...";
    });

    String? aliasValue = _aliasController.text.trim();
    if (aliasValue.isEmpty) {
      setState(() => _statusMessage = "Detectando alias...");
      aliasValue = await widget.sdk.getKeystoreAlias(
        _jksPath!,
        _createPassController.text,
      );
      if (aliasValue == null) {
        widget.sdk.log(
          "⚠️ No se pudo detectar el alias. Usando predeterminado: $_defaultAlias",
        );
        aliasValue = _defaultAlias;
      } else {
        widget.sdk.log("🔍 Alias detectado automáticamente: $aliasValue");
        _aliasController.text = aliasValue;
      }
    }

    String baseName = p.basenameWithoutExtension(_apkPath!);
    String outApk = p.join(outputDir, '${baseName}_signed.apk');

    try {
      String apksignerJar = '';
      if (widget.sdk.apksignerPath.endsWith('.jar')) {
        apksignerJar = widget.sdk.apksignerPath;
      } else {
        final String apksignerDir = File(widget.sdk.apksignerPath).parent.path;
        apksignerJar = p.join(apksignerDir, 'lib', 'apksigner.jar');
      }

      String javaExe = widget.sdk.jarsignerPath.replaceAll(
        'jarsigner.exe',
        'java.exe',
      );

      // Safety check if java.exe is not in the same bin as jarsigner
      if (!File(javaExe).existsSync()) {
        javaExe = 'java';
      }

      ProcessResult res;
      if (File(apksignerJar).existsSync() && File(javaExe).existsSync()) {
        res = await Process.run(javaExe, [
          '-jar',
          apksignerJar,
          'sign',
          '--ks',
          _jksPath!,
          '--ks-pass',
          'pass:${_createPassController.text}',
          '--ks-key-alias',
          aliasValue,
          '--key-pass',
          'pass:${_createPassController.text}',
          '--out',
          outApk,
          _apkPath!,
        ]);
      } else {
        res = await Process.run('cmd', [
          '/S',
          '/C',
          '"${widget.sdk.apksignerPath}" sign --ks "$_jksPath" --ks-pass "pass:${_createPassController.text}" --ks-key-alias "$aliasValue" --key-pass "pass:${_createPassController.text}" --out "$outApk" "$_apkPath"',
        ], runInShell: true);
      }

      final String rawOut = res.stdout.toString();
      final String rawErr = res.stderr.toString();
      widget.sdk.log('✍️ apksigner exit code: ${res.exitCode}');
      if (rawOut.isNotEmpty) widget.sdk.log('✍️ apksigner stdout: $rawOut');
      if (rawErr.isNotEmpty) widget.sdk.log('✍️ apksigner stderr: $rawErr');

      if (res.exitCode == 0) {
        setState(() => _statusMessage = "Firma exitosa");
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('${widget.loc.apkSaved} $outApk'),
              backgroundColor: Colors.green,
            ),
          );
          if (widget.isDialog) {
            Navigator.pop(context);
          }
        }
      } else {
        setState(() => _statusMessage = "Error al firmar");
        if (mounted) {
          final errorMsg = rawErr.isNotEmpty ? rawErr : rawOut;
          showDialog(
            context: context,
            builder: (context) => AlertDialog(
              title: Text(widget.loc.signError),
              content: SelectableText(
                errorMsg.length > 500
                    ? '${errorMsg.substring(0, 500)}...'
                    : errorMsg,
                style: const TextStyle(fontFamily: 'Consolas', fontSize: 12),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(widget.loc.t('CERRAR')),
                ),
              ],
            ),
          );
        }
      }
    } catch (e) {
      widget.sdk.log('Error crítico en firma: $e');
      setState(() => _statusMessage = "Error: $e");
    } finally {
      setState(() => _isProcessing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isD = widget.isDarkMode;

    Widget content = Container(
      width: widget.isDialog ? 850 : double.infinity,
      height: widget.isDialog ? 640 : null,
      constraints: widget.isDialog
          ? null
          : const BoxConstraints(minHeight: 500),
      padding: const EdgeInsets.all(20),
      decoration: widget.isDialog
          ? null
          : BoxDecoration(
              color: isD ? Colors.white.withValues(alpha: 0.02) : Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isD
                    ? Colors.white10
                    : Colors.blueGrey.withValues(alpha: 0.1),
              ),
              boxShadow: isD
                  ? []
                  : [
                      BoxShadow(
                        color: Colors.blueAccent.withValues(alpha: 0.02),
                        blurRadius: 20,
                        offset: const Offset(0, 10),
                      ),
                    ],
            ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!widget.isDialog && !widget.showOnlySign) ...[
            Text(
              widget.loc.signingManagement.toUpperCase(),
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: isD ? Colors.cyanAccent : Colors.blueAccent,
              ),
            ),
            const SizedBox(height: 12),
          ],
          if (!widget.showOnlySign) ...[
            TabBar(
              controller: _tabController,
              labelColor: isD ? Colors.cyanAccent : Colors.blueAccent,
              unselectedLabelColor: Colors.grey,
              indicatorColor: isD ? Colors.cyanAccent : Colors.blueAccent,
              isScrollable: false,
              tabs: [
                Tab(
                  text: widget.loc.signApk,
                  icon: const Icon(Icons.app_registration, size: 18),
                ),
                Tab(
                  text: widget.loc.newJks,
                  icon: const Icon(Icons.add_moderator, size: 18),
                ),
              ],
            ),
            const SizedBox(height: 16),
          ] else
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Row(
                children: [
                  Icon(
                    Icons.vpn_key_outlined,
                    color: isD ? Colors.cyanAccent : Colors.blueAccent,
                  ),
                  const SizedBox(width: 10),
                  Text(
                    widget.loc.signingApp,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),

          Expanded(
            child: TabBarView(
              controller: _tabController,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                _buildSignTab(isD),
                if (!widget.showOnlySign) _buildCreateJksTab(isD),
              ],
            ),
          ),
          const SizedBox(height: 16),
          if (_isProcessing || _statusMessage != widget.loc.ready) ...[
            Center(
              child: Text(
                _statusMessage,
                style: TextStyle(
                  color: isD ? Colors.white54 : Colors.grey[700],
                  fontSize: 12,
                ),
              ),
            ),
            const SizedBox(height: 8),
          ],
          LinearProgressIndicator(
            value: _isProcessing ? null : 0,
            minHeight: 2,
            backgroundColor: Colors.grey.withValues(alpha: 0.2),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              if (widget.isDialog)
                OutlinedButton(
                  onPressed: () => Navigator.pop(context),
                  style: OutlinedButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 12,
                    ),
                  ),
                  child: Text(
                    widget.loc.cancel,
                    style: TextStyle(
                      color: isD ? Colors.white70 : Colors.black87,
                    ),
                  ),
                )
              else
                const SizedBox(),
              ElevatedButton(
                onPressed: _isProcessing
                    ? null
                    : () {
                        if (_tabController.index == 0) {
                          _signApk();
                        } else {
                          _createJKS();
                        }
                      },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blueAccent,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 32,
                    vertical: 12,
                  ),
                ),
                child: Text(
                  (widget.showOnlySign || _tabController.index == 0)
                      ? widget.loc.sign
                      : widget.loc.generateJks,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        ],
      ),
    );

    if (widget.isDialog) {
      return Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        backgroundColor: isD ? const Color(0xFF1E1E1E) : Colors.white,
        child: content,
      );
    }

    return content;
  }

  Widget _buildSignTab(bool isD) {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      child: Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isD
                    ? Colors.white.withValues(alpha: 0.03)
                    : Colors.blueGrey[50],
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isD
                      ? Colors.white10
                      : Colors.blueGrey.withValues(alpha: 0.1),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.blueAccent.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.layers_outlined,
                      size: 20,
                      color: isD ? Colors.cyanAccent : Colors.blueAccent,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.loc.apkSelectedTitle,
                          style: TextStyle(
                            fontSize: 10,
                            color: Colors.grey,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          _apkPath != null
                              ? p.basename(_apkPath!)
                              : widget.loc.selectApkHint,
                          style: TextStyle(
                            color: isD ? Colors.white : Colors.blueGrey[900],
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                  ElevatedButton(
                    onPressed: _pickApk,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blueAccent,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                    ),
                    child: Text(
                      widget.loc.browse,
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Icon(
                  Icons.vpn_key_outlined,
                  size: 14,
                  color: isD ? Colors.cyanAccent : Colors.blueAccent,
                ),
                const SizedBox(width: 8),
                Text(
                  widget.loc.signingCredentials,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
            const Divider(height: 24),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.loc.pickJks,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 11,
                        ),
                      ),
                      const SizedBox(height: 6),
                      InkWell(
                        onTap: _pickJks,
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          height: 42,
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                          decoration: BoxDecoration(
                            color: isD
                                ? Colors.white.withValues(alpha: 0.05)
                                : Colors.blueGrey.withValues(alpha: 0.02),
                            border: Border.all(
                              color: isD
                                  ? Colors.white10
                                  : Colors.blueGrey.withValues(alpha: 0.1),
                            ),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.folder_open,
                                size: 16,
                                color: isD
                                    ? Colors.cyanAccent
                                    : Colors.blueAccent,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  _jksPath != null
                                      ? p.basename(_jksPath!)
                                      : widget.loc.selectJksHint,
                                  style: TextStyle(
                                    color: _jksPath != null
                                        ? (isD ? Colors.white : Colors.black)
                                        : Colors.grey,
                                    fontSize: 12,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _buildFieldLayout(
                    widget.loc.aliasLabel,
                    _aliasController,
                    icon: Icons.vpn_key_outlined,
                    hint: 'Auto-detectar (ej: key0)',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _buildFieldLayout(
                    widget.loc.passwordLabel,
                    _createPassController,
                    isPassword: true,
                    icon: Icons.lock_outline,
                    hint: '******',
                    isObscured: _obscureSignPass,
                    onToggle: () =>
                        setState(() => _obscureSignPass = !_obscureSignPass),
                  ),
                ),
                const SizedBox(width: 16),
                const Expanded(child: SizedBox()), // Spacer
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFieldLayout(
    String label,
    TextEditingController controller, {
    bool isPassword = false,
    String? hint,
    bool isObscured = false,
    VoidCallback? onToggle,
    IconData? icon,
  }) {
    final isD = widget.isDarkMode;
    final color = isD ? Colors.cyanAccent : Colors.blueAccent;

    return Padding(
      padding: const EdgeInsets.only(bottom: 6.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (icon != null) ...[
                Icon(icon, size: 12, color: color.withValues(alpha: 0.7)),
                const SizedBox(width: 4),
              ],
              Text(
                label,
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 11,
                  color: isD ? Colors.white70 : Colors.black87,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          SizedBox(
            height: 38,
            child: TextField(
              controller: controller,
              obscureText: isPassword && isObscured,
              style: TextStyle(
                fontSize: 12,
                color: isD ? Colors.white : Colors.black87,
              ),
              decoration: InputDecoration(
                filled: true,
                fillColor: isD
                    ? Colors.white.withValues(alpha: 0.05)
                    : Colors.blueGrey.withValues(alpha: 0.02),
                hintText: hint,
                hintStyle: const TextStyle(fontSize: 12, color: Colors.grey),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(
                    color: isD
                        ? Colors.white10
                        : Colors.blueGrey.withValues(alpha: 0.1),
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(
                    color: color.withValues(alpha: 0.5),
                    width: 1.5,
                  ),
                ),
                suffixIcon: isPassword
                    ? IconButton(
                        icon: Icon(
                          isObscured ? Icons.visibility_off : Icons.visibility,
                          size: 16,
                          color: isD
                              ? (isObscured
                                    ? Colors.white38
                                    : Colors.cyanAccent)
                              : (isObscured ? Colors.grey : Colors.blueAccent),
                        ),
                        onPressed: onToggle,
                        splashRadius: 16,
                      )
                    : null,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCreateJksTab(bool isD) {
    return Column(
      children: [
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // COLUMNA ALMACEN
              Expanded(
                child: _buildCreationCard(
                  isD,
                  title: widget.loc.creationCardTitle,
                  icon: Icons.account_balance_wallet_outlined,
                  children: [
                    _buildFieldLayout(
                      widget.loc.jksFileLabel,
                      _newFileNameController,
                      icon: Icons.insert_drive_file_outlined,
                      hint: 'mi_firma_isv',
                    ),
                    const SizedBox(height: 4),
                    _buildFieldLayout(
                      widget.loc.aliasLabel,
                      _aliasController,
                      icon: Icons.vpn_key_outlined,
                      hint: widget.loc.aliasHint,
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: _buildFieldLayout(
                            widget.loc.password,
                            _createPassController,
                            isPassword: true,
                            hint: widget.loc.min6Chars,
                            icon: Icons.password_outlined,
                            isObscured: _obscureCreatePass,
                            onToggle: () => setState(
                              () => _obscureCreatePass = !_obscureCreatePass,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _buildFieldLayout(
                            widget.loc.confirmPassword,
                            _confirmPassController,
                            isPassword: true,
                            hint: widget.loc.repeatPassword,
                            icon: Icons.check_circle_outline,
                            isObscured: _obscureConfirmPass,
                            onToggle: () => setState(
                              () => _obscureConfirmPass = !_obscureConfirmPass,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 20),
              // COLUMNA PROPIETARIO
              Expanded(
                child: _buildCreationCard(
                  isD,
                  title: widget.loc.ownerDetails,
                  icon: Icons.assignment_ind_outlined,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: _buildFieldLayout(
                            widget.loc.fullName,
                            _cnController,
                            icon: Icons.badge_outlined,
                          ),
                        ),
                      ],
                    ),
                    Row(
                      children: [
                        Expanded(
                          child: _buildFieldLayout(
                            widget.loc.company,
                            _oController,
                            icon: Icons.business_outlined,
                          ),
                        ),
                      ],
                    ),
                    Row(
                      children: [
                        Expanded(
                          child: _buildFieldLayout(
                            widget.loc.city,
                            _lController,
                            icon: Icons.location_city_outlined,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _buildFieldLayout(
                            widget.loc.countryCode,
                            _cController,
                            icon: Icons.flag_outlined,
                          ),
                        ),
                      ],
                    ),
                    const Spacer(),
                    Text(
                      widget.loc.certFieldsNote,
                      style: TextStyle(
                        fontSize: 10,
                        color: Colors.grey.withValues(alpha: 0.6),
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCreationCard(
    bool isD, {
    required String title,
    required IconData icon,
    required List<Widget> children,
  }) {
    final color = isD ? Colors.cyanAccent : Colors.blueAccent;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isD ? Colors.white.withValues(alpha: 0.02) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isD ? Colors.white10 : Colors.blueGrey.withValues(alpha: 0.1),
        ),
        boxShadow: isD
            ? []
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.02),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 8),
              Text(
                title,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  color: color,
                  letterSpacing: 1.1,
                ),
              ),
            ],
          ),
          const Divider(height: 12),
          Expanded(
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              child: Column(children: children),
            ),
          ),
        ],
      ),
    );
  }
}
