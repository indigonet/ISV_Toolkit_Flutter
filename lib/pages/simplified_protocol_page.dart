import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/localization.dart';
import '../services/terminal_sdk_service.dart';
import '../widgets/console_logs_view.dart';
import '../core/clp_formatter.dart';

class SimplifiedCommandMeta {
  final int code;
  final String labelKey;
  final IconData icon;
  final String descriptionKey;

  const SimplifiedCommandMeta({
    required this.code,
    required this.labelKey,
    required this.icon,
    required this.descriptionKey,
  });
}

class SimplifiedProtocolPage extends StatefulWidget {
  final AppLocale loc;
  final bool isDarkMode;

  const SimplifiedProtocolPage({
    super.key,
    required this.loc,
    required this.isDarkMode,
  });

  @override
  State<SimplifiedProtocolPage> createState() => _SimplifiedProtocolPageState();
}

class _SimplifiedProtocolPageState extends State<SimplifiedProtocolPage> {
  final TerminalSDKService _terminalSdk = TerminalSDKService();

  static const List<SimplifiedCommandMeta> _commands = [
    SimplifiedCommandMeta(
      code: 100,
      labelKey: 'Venta',
      icon: Icons.shopping_cart_outlined,
      descriptionKey: 'Realizar una venta cobrando al cliente',
    ),
    SimplifiedCommandMeta(
      code: 102,
      labelKey: 'Anulación',
      icon: Icons.replay_outlined,
      descriptionKey:
          'Anular una venta del lote actual usando su ID de operación',
    ),
    SimplifiedCommandMeta(
      code: 108,
      labelKey: 'Devolución',
      icon: Icons.keyboard_return_outlined,
      descriptionKey: 'Devolver fondos usando código de autorización',
    ),
    SimplifiedCommandMeta(
      code: 103,
      labelKey: 'Cierre',
      icon: Icons.lock_outline,
      descriptionKey: 'Cerrar el lote actual de transacciones',
    ),
    SimplifiedCommandMeta(
      code: 109,
      labelKey: 'Duplicado',
      icon: Icons.copy_all_outlined,
      descriptionKey: 'Imprimir duplicado usando ID de operación',
    ),
    SimplifiedCommandMeta(
      code: 105,
      labelKey: 'Detalles',
      icon: Icons.info_outline,
      descriptionKey: 'Obtener detalle de ventas del lote',
    ),
  ];

  late SimplifiedCommandMeta _activeCommand = _commands.first;
  final _formKeyTransaction = GlobalKey<FormState>();
  final FocusNode _amountFocusNode = FocusNode();

  final TextEditingController _amountController = TextEditingController(
    text: '15.000',
  );
  final TextEditingController _ticketNumberController = TextEditingController();
  final TextEditingController _employeeIdController = TextEditingController(
    text: '1',
  );
  final TextEditingController _operationIdController = TextEditingController();
  final TextEditingController _authCodeController = TextEditingController();

  int _saleType = 1; // default 1 (Compra Afecta)
  bool _printOnPos = true;
  bool _isExecuting = false;

  // COM port list vars
  List<String> _availableComPorts = [];
  bool _isLoadingPorts = false;
  bool _isCustomPort = false;
  final TextEditingController _comPortController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _comPortController.text = _terminalSdk.comPort;
    _generateRandomTicketNumber();
    _loadAvailablePorts();
  }

  @override
  void dispose() {
    _amountController.dispose();
    _ticketNumberController.dispose();
    _employeeIdController.dispose();
    _operationIdController.dispose();
    _authCodeController.dispose();
    _comPortController.dispose();
    _amountFocusNode.dispose();
    super.dispose();
  }

  void _generateRandomTicketNumber() {
    final rand = DateTime.now().millisecondsSinceEpoch % 100000;
    _ticketNumberController.text = rand.toString();
  }

  Future<void> _loadAvailablePorts() async {
    if (_isLoadingPorts) return;
    setState(() {
      _isLoadingPorts = true;
    });
    _terminalSdk.log('Scanning available COM ports...', level: 'DEBUG');

    List<String> ports = [];
    try {
      if (Platform.isWindows) {
        final result = await Process.run('reg', [
          'query',
          r'HKLM\HARDWARE\DEVICEMAP\SERIALCOMM',
        ]);
        if (result.exitCode == 0) {
          final lines = result.stdout.toString().split('\n');
          for (var line in lines) {
            line = line.trim();
            if (line.isEmpty) continue;
            final parts = line.split(RegExp(r'\s+'));
            if (parts.length >= 3) {
              final port = parts.last;
              if (port.startsWith('COM')) {
                ports.add(port);
              }
            }
          }
        }
      }
    } catch (e) {
      _terminalSdk.log('Error scanning COM ports: $e', level: 'ERROR');
    }

    // Sort numerically
    ports.sort((a, b) {
      final numA = int.tryParse(a.replaceAll(RegExp(r'\D'), '')) ?? 0;
      final numB = int.tryParse(b.replaceAll(RegExp(r'\D'), '')) ?? 0;
      return numA.compareTo(numB);
    });

    ports = ports.toSet().toList(); // Ensure unique values

    if (mounted) {
      setState(() {
        _availableComPorts = ports;
        _isLoadingPorts = false;
        if (ports.isNotEmpty && !ports.contains(_terminalSdk.comPort)) {
          _terminalSdk.comPort = ports.first;
          _comPortController.text = ports.first;
        }
      });
    }

    _terminalSdk.log('Port scan complete. Found: $ports', level: 'DEBUG');
  }

  void _handleConnect() async {
    final success = await _terminalSdk.connect();
    if (mounted) {
      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${widget.loc.t('Terminal conectado en')} ${_terminalSdk.comPort}',
            ),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${widget.loc.t('Error al conectar en')} ${_terminalSdk.comPort}',
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _autocompleteOperationId() {
    if (_terminalSdk.lastSuccessfulTransactionId != null) {
      setState(() {
        _operationIdController.text = _terminalSdk.lastSuccessfulTransactionId!;
      });
      _terminalSdk.log(
        'Autocompleted operation ID: ${_terminalSdk.lastSuccessfulTransactionId}',
        level: 'DEBUG',
      );
    }
  }

  String _formatBool(bool value, int commandCode) {
    if (commandCode == 100) {
      return value ? 'true' : 'false';
    }
    return value ? 'True' : 'False';
  }

  void _handleSendTransaction() async {
    if (!_formKeyTransaction.currentState!.validate()) return;

    if (_terminalSdk.connectionState.value !=
        TerminalConnectionState.connected) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(widget.loc.t('Debe conectar el puerto COM primero.')),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() => _isExecuting = true);

    String content = '';
    final code = _activeCommand.code;

    if (code == 100) {
      // Venta
      final amountClean = _amountController.text.replaceAll(RegExp(r'\D'), '');
      final amount = double.tryParse(amountClean) ?? 150;
      final String ticket = _ticketNumberController.text.trim();
      final int seller = int.tryParse(_employeeIdController.text.trim()) ?? 1;

      content =
          '100|${amount.toInt()}|$ticket|${_formatBool(_printOnPos, 100)}|$_saleType|$seller|';
    } else if (code == 102) {
      // Anulación
      final String opId = _operationIdController.text.trim();
      content = '102|$opId|${_formatBool(_printOnPos, 102)}|';
    } else if (code == 108) {
      // Devolución
      final String authCode = _authCodeController.text.trim();
      final amountClean = _amountController.text.replaceAll(RegExp(r'\D'), '');
      final amount = double.tryParse(amountClean) ?? 150;

      content =
          '108|$authCode|${amount.toInt()}|${_formatBool(_printOnPos, 108)}|';
    } else if (code == 103) {
      // Cierre
      content = '103|';
    } else if (code == 109) {
      // Duplicado
      final String opId = _operationIdController.text.trim();
      content = '109|$opId|${_formatBool(_printOnPos, 109)}|';
    } else if (code == 105) {
      // Detalles
      content = '105|${_formatBool(_printOnPos, 105)}|';
    }

    _terminalSdk.log(
      'Ejecutando comando simplificado (${_activeCommand.labelKey}): $content',
      level: 'INFO',
    );

    final response = await _terminalSdk.sendSimplifiedCommand(content);
    _terminalSdk.log('Simplified Protocol Request: $content', level: 'TX');
    _terminalSdk.log(
      'Simplified Protocol Response: ${jsonEncode(response)}',
      level: 'RX',
    );

    if (mounted) {
      setState(() => _isExecuting = false);

      final respCode = response['ResponseCode']?.toString() ?? '99';
      final respMsg = response['ResponseMessage']?.toString() ?? 'Error';

      if (respCode == '0') {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${widget.loc.t('Éxito')}: $respMsg'),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${widget.loc.t('Comando rechazado/fallido')} (${widget.loc.t('Código')}: $respCode)',
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDarkMode;
    final primaryColor = isDark ? Colors.cyanAccent : Colors.blueAccent;
    final cardBgColor = isDark ? const Color(0xFF1E293B) : Colors.white;
    final borderColor = isDark ? const Color(0xFF334155) : Colors.black12;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 1. LEFT COLUMN (Flex 3): Connection (Fixed layout, no scroll)
        Expanded(
          flex: 3,
          child: Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildHeader(primaryColor),
                const SizedBox(height: 16),
                _buildConnectionConfigCard(
                  cardBgColor,
                  borderColor,
                  primaryColor,
                ),
              ],
            ),
          ),
        ),

        // 2. CENTER COLUMN (Flex 4): Venta simplified request form
        Expanded(
          flex: 4,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: SingleChildScrollView(
              child: _buildTransactionFormCard(
                cardBgColor,
                borderColor,
                primaryColor,
              ),
            ),
          ),
        ),

        // 3. RIGHT COLUMN (Flex 4): Event log console
        Expanded(
          flex: 4,
          child: Padding(
            padding: const EdgeInsets.only(left: 12),
            child: ConsoleLogsView(
              terminalSdk: _terminalSdk,
              isDarkMode: isDark,
              cardBgColor: cardBgColor,
              borderColor: borderColor,
              primaryColor: primaryColor,
              loc: widget.loc,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildHeader(Color primary) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.point_of_sale, color: primary, size: 22),
            const SizedBox(width: 8),
            Text(
              widget.loc.t('Protocolo Simplificado'),
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          widget.loc.t('Comunicación simplificada con el terminal POS'),
          style: TextStyle(
            fontSize: 12,
            color: widget.isDarkMode ? Colors.white60 : Colors.black54,
          ),
        ),
      ],
    );
  }

  Widget _buildConnectionConfigCard(Color bg, Color border, Color primary) {
    return Card(
      color: bg,
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: border, width: 1),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.settings_input_hdmi, color: primary, size: 16),
                const SizedBox(width: 8),
                Text(
                  widget.loc.t('CONEXIÓN PUERTO SERIAL'),
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Text(
                  '${widget.loc.t('Estado')}:',
                  style: TextStyle(
                    fontSize: 11,
                    color: widget.isDarkMode ? Colors.white60 : Colors.black54,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: ValueListenableBuilder<TerminalConnectionState>(
                      valueListenable: _terminalSdk.connectionState,
                      builder: (context, connState, _) {
                        return _buildConnectionStateLED(connState);
                      },
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _buildComPortSelector(border),
            const SizedBox(height: 16),
            ValueListenableBuilder<TerminalConnectionState>(
              valueListenable: _terminalSdk.connectionState,
              builder: (context, connState, _) {
                final isConnected =
                    connState == TerminalConnectionState.connected;
                final isConnecting =
                    connState == TerminalConnectionState.connecting;

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (isConnected) ...[
                      SizedBox(
                        height: 42,
                        child: OutlinedButton.icon(
                          onPressed: () => _terminalSdk.disconnect(),
                          icon: const Icon(Icons.flash_off, size: 14),
                          label: Text(
                            widget.loc.t('Desconectar'),
                            style: const TextStyle(fontSize: 12),
                          ),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.redAccent,
                            side: const BorderSide(color: Colors.redAccent),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                        ),
                      ),
                    ] else ...[
                      SizedBox(
                        height: 42,
                        child: ElevatedButton.icon(
                          onPressed: isConnecting ? null : _handleConnect,
                          icon: isConnecting
                              ? const SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.flash_on, size: 14),
                          label: Text(
                            widget.loc.t('Conectar'),
                            style: const TextStyle(fontSize: 12),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: primary,
                            foregroundColor: widget.isDarkMode
                                ? Colors.black
                                : Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                );
              },
            ),
            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.download_for_offline_outlined,
                  size: 14,
                  color: widget.isDarkMode ? Colors.white54 : Colors.black54,
                ),
                const SizedBox(width: 6),
                InkWell(
                  onTap: () => _launchUrl(
                    'https://drive.google.com/file/d/10f5CYWE6Uy6M1BD7Fn6jMSUfYA3nglOL/view?usp=sharing',
                  ),
                  child: Text(
                    widget.loc.t('Descargar APK "Getnet PS"'),
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      decoration: TextDecoration.underline,
                      color: primary,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildComPortSelector(Color border) {
    final displayPorts = List<String>.from(_availableComPorts);
    if (_terminalSdk.comPort.isNotEmpty && !displayPorts.contains(_terminalSdk.comPort)) {
      displayPorts.insert(0, _terminalSdk.comPort);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.loc.t('Puerto COM'),
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.3,
          ),
        ),
        const SizedBox(height: 6),
        if (!_isCustomPort)
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 42,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: widget.isDarkMode
                          ? const Color(0xFF1E293B)
                          : Colors.white,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: border),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: _terminalSdk.comPort,
                        isExpanded: true,
                        icon: const Icon(Icons.keyboard_arrow_down, size: 18),
                        dropdownColor: widget.isDarkMode
                            ? const Color(0xFF1E293B)
                            : Colors.white,
                        style: TextStyle(
                          fontSize: 12,
                          color: widget.isDarkMode
                              ? Colors.white
                              : Colors.black87,
                        ),
                        items: [
                          ...displayPorts.map(
                            (port) => DropdownMenuItem(
                              value: port,
                              child: Row(
                                children: [
                                  const Icon(
                                    Icons.usb,
                                    size: 14,
                                    color: Colors.grey,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(port),
                                ],
                              ),
                            ),
                          ),
                          DropdownMenuItem(
                            value: '__custom__',
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.settings,
                                  size: 14,
                                  color: Colors.grey,
                                ),
                                const SizedBox(width: 8),
                                Text(widget.loc.t('Otro...')),
                              ],
                            ),
                          ),
                        ],
                        onChanged: (val) {
                          if (val == '__custom__') {
                            setState(() {
                              _isCustomPort = true;
                              _comPortController.text = _terminalSdk.comPort;
                            });
                          } else if (val != null) {
                            setState(() {
                              _terminalSdk.comPort = val;
                              _comPortController.text = val;
                            });
                          }
                        },
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 42,
                height: 42,
                child: OutlinedButton(
                  onPressed: _isLoadingPorts ? null : _loadAvailablePorts,
                  style: OutlinedButton.styleFrom(
                    padding: EdgeInsets.zero,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    side: BorderSide(color: border),
                    backgroundColor: widget.isDarkMode
                        ? const Color(0xFF1E293B)
                        : Colors.white,
                  ),
                  child: _isLoadingPorts
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 1.5),
                        )
                      : const Icon(Icons.refresh, size: 18),
                ),
              ),
            ],
          )
        else
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 42,
                  child: TextFormField(
                    controller: _comPortController,
                    style: const TextStyle(fontSize: 12),
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.usb, size: 14),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      hintText: 'e.g. COM3',
                      suffixIcon: displayPorts.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.list, size: 16),
                              onPressed: () {
                                setState(() {
                                  _isCustomPort = false;
                                  if (!displayPorts.contains(
                                    _terminalSdk.comPort,
                                  )) {
                                    _terminalSdk.comPort =
                                        displayPorts.first;
                                    _comPortController.text =
                                        displayPorts.first;
                                  }
                                });
                              },
                              tooltip: widget.loc.t('Mostrar lista'),
                            )
                          : null,
                    ),
                    onChanged: (val) => _terminalSdk.comPort = val.trim(),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 42,
                height: 42,
                child: OutlinedButton(
                  onPressed: _isLoadingPorts ? null : _loadAvailablePorts,
                  style: OutlinedButton.styleFrom(
                    padding: EdgeInsets.zero,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    side: BorderSide(color: border),
                    backgroundColor: widget.isDarkMode
                        ? const Color(0xFF1E293B)
                        : Colors.white,
                  ),
                  child: _isLoadingPorts
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 1.5),
                        )
                      : const Icon(Icons.refresh, size: 18),
                ),
              ),
            ],
          ),
      ],
    );
  }

  Future<void> _launchUrl(String url) async {
    try {
      await Process.run('cmd', ['/c', 'start', '', url]);
    } catch (_) {
      try {
        await Process.run('powershell', [
          '-Command',
          'Start-Process',
          '"$url"',
        ]);
      } catch (_) {}
    }
  }

  Widget _buildTransactionFormCard(Color bg, Color border, Color primary) {
    return Card(
      color: bg,
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: border, width: 1),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKeyTransaction,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(Icons.send_outlined, color: primary, size: 16),
                  const SizedBox(width: 8),
                  Text(
                    widget.loc.t('ENVIAR COMANDO (ISO8583)'),
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _buildDropdownField<SimplifiedCommandMeta>(
                label: widget.loc.t('Comando a enviar'),
                value: _activeCommand,
                icon: Icons.tune,
                items: _commands.map((cmd) {
                  return DropdownMenuItem<SimplifiedCommandMeta>(
                    value: cmd,
                    child: Row(
                      children: [
                        Icon(cmd.icon, size: 16, color: primary),
                        const SizedBox(width: 8),
                        Text(widget.loc.t(cmd.labelKey)),
                      ],
                    ),
                  );
                }).toList(),
                onChanged: (val) {
                  if (val != null) {
                    setState(() {
                      _activeCommand = val;
                    });
                  }
                },
              ),
              const SizedBox(height: 6),
              Text(
                widget.loc.t(_activeCommand.descriptionKey),
                style: TextStyle(
                  fontSize: 10,
                  color: widget.isDarkMode ? Colors.white54 : Colors.black54,
                ),
              ),
              const SizedBox(height: 16),

              if (_activeCommand.code == 100) ...[
                // Venta: Monto & Ticket Number Row
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: _buildFormField(
                        label: widget.loc.t('Monto'),
                        controller: _amountController,
                        icon: Icons.attach_money,
                        focusNode: _amountFocusNode,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: false,
                        ),
                        inputFormatters: [CLPFormatter()],
                        validator: (val) {
                          if (val == null || val.isEmpty) {
                            return widget.loc.t('Monto inválido');
                          }
                          final cleanStr = val.replaceAll(RegExp(r'\D'), '');
                          final d = double.tryParse(cleanStr) ?? 0;
                          if (d <= 0) {
                            return widget.loc.t('Monto no puede ser 0');
                          }
                          if (d > 999999999) {
                            return widget.loc.t('Monto fuera de rango');
                          }
                          return null;
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildFormField(
                        label: widget.loc.t('Número de Ticket'),
                        controller: _ticketNumberController,
                        icon: Icons.tag,
                        keyboardType: TextInputType.number,
                        maxLength: 10,
                        suffixIcon: IconButton(
                          icon: const Icon(Icons.refresh, size: 16),
                          onPressed: _generateRandomTicketNumber,
                        ),
                        validator: (val) {
                          if (val == null || val.trim().isEmpty) {
                            return widget.loc.t('Requerido');
                          }
                          if (val.trim().length > 10) {
                            return widget.loc.t('Máximo 10 caracteres');
                          }
                          return null;
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                // Venta: Tipo de Venta & Employee ID Row
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: _buildDropdownField<int>(
                        label: widget.loc.t('Tipo de Venta'),
                        value: _saleType,
                        icon: Icons.payment,
                        items: [
                          DropdownMenuItem(
                            value: 0,
                            child: Text(widget.loc.t('Compra (0)')),
                          ),
                          DropdownMenuItem(
                            value: 1,
                            child: Text(widget.loc.t('Compra Afecta (1)')),
                          ),
                          DropdownMenuItem(
                            value: 2,
                            child: Text(widget.loc.t('Factura Afecta (2)')),
                          ),
                          DropdownMenuItem(
                            value: 3,
                            child: Text(widget.loc.t('Compra Exenta (3)')),
                          ),
                          DropdownMenuItem(
                            value: 4,
                            child: Text(widget.loc.t('Factura Exenta (4)')),
                          ),
                        ],
                        onChanged: (val) {
                          if (val != null) {
                            setState(() => _saleType = val);
                          }
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildFormField(
                        label: widget.loc.t('ID de Vendedor'),
                        controller: _employeeIdController,
                        icon: Icons.person_outline,
                        keyboardType: TextInputType.number,
                        maxLength: 4,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        validator: (val) {
                          if (val == null || val.trim().isEmpty) {
                            return widget.loc.t('Requerido');
                          }
                          final n = int.tryParse(val.trim());
                          if (n == null || n <= 0) {
                            return widget.loc.t('ID inválido');
                          }
                          if (n > 9999) {
                            return widget.loc.t('Máx. 9999');
                          }
                          return null;
                        },
                      ),
                    ),
                  ],
                ),
              ] else if (_activeCommand.code == 102 ||
                  _activeCommand.code == 109) ...[
                // Anulación (102) & Duplicado (109): ID de Operación
                _buildFormField(
                  label: widget.loc.t('N° de Comprobante'),
                  controller: _operationIdController,
                  icon: Icons.receipt_long_outlined,
                  keyboardType: TextInputType.number,
                  maxLength: 8,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  suffixIcon: _terminalSdk.lastSuccessfulTransactionId != null
                      ? IconButton(
                          icon: const Icon(Icons.auto_awesome, size: 16),
                          onPressed: _autocompleteOperationId,
                          tooltip: widget.loc.t('Usar última venta'),
                        )
                      : null,
                  validator: (val) {
                    if (val == null || val.trim().isEmpty) {
                      return widget.loc.t('Requerido');
                    }
                    return null;
                  },
                ),
              ] else if (_activeCommand.code == 108) ...[
                // Devolución (108): Código de Autorización & Monto
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: _buildFormField(
                        label: widget.loc.t('Código de Autorización'),
                        controller: _authCodeController,
                        icon: Icons.lock_outline,
                        maxLength: 12,
                        validator: (val) {
                          if (val == null || val.trim().isEmpty) {
                            return widget.loc.t('Requerido');
                          }
                          return null;
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildFormField(
                        label: widget.loc.t('Monto'),
                        controller: _amountController,
                        icon: Icons.attach_money,
                        focusNode: _amountFocusNode,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: false,
                        ),
                        inputFormatters: [CLPFormatter()],
                        validator: (val) {
                          if (val == null || val.isEmpty) {
                            return widget.loc.t('Monto inválido');
                          }
                          final cleanStr = val.replaceAll(RegExp(r'\D'), '');
                          final d = double.tryParse(cleanStr) ?? 0;
                          if (d < 150 || d > 999999999) {
                            return widget.loc.t('Monto fuera de rango');
                          }
                          return null;
                        },
                      ),
                    ),
                  ],
                ),
              ],

              if (_activeCommand.code != 103) ...[
                const SizedBox(height: 16),
                _buildSectionHeader(widget.loc.t('OPCIONES DE IMPRESIÓN')),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.loc.t('Imprimir en POS'),
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            widget.loc.t(
                              'Imprimir comprobante físico directamente en el terminal',
                            ),
                            style: TextStyle(
                              fontSize: 10,
                              color: widget.isDarkMode
                                  ? Colors.white54
                                  : Colors.black54,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Switch(
                      value: _printOnPos,
                      onChanged: (val) => setState(() => _printOnPos = val),
                      activeThumbColor: primary,
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 20),
              SizedBox(
                height: 46,
                child: ElevatedButton.icon(
                  onPressed: _isExecuting ? null : _handleSendTransaction,
                  icon: _isExecuting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.send_outlined, size: 16),
                  label: Text(
                    widget.loc.t('Enviar Comando Simplificado'),
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primary,
                    foregroundColor: widget.isDarkMode
                        ? Colors.black
                        : Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: widget.isDarkMode ? const Color(0xFF334155) : Colors.black12,
          ),
        ),
      ),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.bold,
          color: Colors.grey,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Widget _buildFormField({
    required String label,
    required TextEditingController controller,
    required IconData icon,
    TextInputType keyboardType = TextInputType.text,
    List<TextInputFormatter>? inputFormatters,
    FormFieldValidator<String>? validator,
    int? maxLength,
    FocusNode? focusNode,
    Widget? suffixIcon,
  }) {
    final formatters = <TextInputFormatter>[
      if (inputFormatters != null) ...inputFormatters,
      if (maxLength != null) LengthLimitingTextInputFormatter(maxLength),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.3,
          ),
        ),
        const SizedBox(height: 6),
        TextFormField(
          controller: controller,
          keyboardType: keyboardType,
          inputFormatters: formatters,
          validator: validator,
          focusNode: focusNode,
          style: const TextStyle(fontSize: 12),
          decoration: InputDecoration(
            prefixIcon: Icon(icon, size: 16),
            suffixIcon: suffixIcon,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 10,
            ),
            filled: true,
            fillColor: widget.isDarkMode
                ? const Color(0xFF1E293B)
                : Colors.white,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(
                color: widget.isDarkMode
                    ? const Color(0xFF334155)
                    : Colors.black12,
              ),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(
                color: widget.isDarkMode
                    ? const Color(0xFF334155)
                    : Colors.black12,
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(
                color: widget.isDarkMode
                    ? Colors.cyanAccent
                    : Colors.blueAccent,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDropdownField<T>({
    required String label,
    required T value,
    required List<DropdownMenuItem<T>> items,
    required ValueChanged<T?> onChanged,
    required IconData icon,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.3,
          ),
        ),
        const SizedBox(height: 6),
        DropdownButtonFormField<T>(
          initialValue: value,
          isExpanded: true,
          items: items.map((item) {
            final child = item.child;
            Widget newChild = child;
            if (child is Text) {
              newChild = Text(
                child.data ?? '',
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
                style: child.style,
              );
            }
            return DropdownMenuItem<T>(
              key: item.key,
              value: item.value,
              onTap: item.onTap,
              enabled: item.enabled,
              alignment: item.alignment,
              child: newChild,
            );
          }).toList(),
          onChanged: onChanged,
          style: TextStyle(
            fontSize: 12,
            color: widget.isDarkMode ? Colors.white : Colors.black87,
          ),
          decoration: InputDecoration(
            prefixIcon: Icon(icon, size: 16),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 10,
            ),
            filled: true,
            fillColor: widget.isDarkMode
                ? const Color(0xFF1E293B)
                : Colors.white,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(
                color: widget.isDarkMode
                    ? const Color(0xFF334155)
                    : Colors.black12,
              ),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(
                color: widget.isDarkMode
                    ? const Color(0xFF334155)
                    : Colors.black12,
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(
                color: widget.isDarkMode
                    ? Colors.cyanAccent
                    : Colors.blueAccent,
              ),
            ),
          ),
          dropdownColor: widget.isDarkMode
              ? const Color(0xFF1E293B)
              : Colors.white,
        ),
      ],
    );
  }

  Widget _buildConnectionStateLED(TerminalConnectionState connState) {
    Color ledColor = Colors.redAccent;
    String statusText = widget.loc.t('Desconectado');
    List<BoxShadow> glow = [];

    if (connState == TerminalConnectionState.connecting) {
      ledColor = Colors.amber;
      statusText = widget.loc.t('Conectando...');
      glow = [
        BoxShadow(
          color: Colors.amber.withValues(alpha: 0.5),
          blurRadius: 8,
          spreadRadius: 2,
        ),
      ];
    } else if (connState == TerminalConnectionState.connected) {
      ledColor = const Color(0xFF10B981); // Emerald Green
      statusText = widget.loc.t('Conectado');
      glow = [
        BoxShadow(
          color: const Color(0xFF10B981).withValues(alpha: 0.6),
          blurRadius: 10,
          spreadRadius: 3,
        ),
      ];
    } else {
      glow = [
        BoxShadow(
          color: Colors.redAccent.withValues(alpha: 0.4),
          blurRadius: 8,
          spreadRadius: 2,
        ),
      ];
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: ledColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: ledColor.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: ledColor,
              shape: BoxShape.circle,
              boxShadow: glow,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            statusText,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: ledColor,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }
}
