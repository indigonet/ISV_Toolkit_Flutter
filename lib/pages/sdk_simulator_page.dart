import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:crypto/crypto.dart';
import '../core/localization.dart';
import '../services/terminal_sdk_service.dart';
import '../models/pos_command_meta.dart';
import '../core/clp_formatter.dart';
import '../core/rut_formatter.dart';
import '../widgets/console_logs_view.dart';

class SDKSimulatorPage extends StatefulWidget {
  final AppLocale loc;
  final bool isDarkMode;

  const SDKSimulatorPage({
    super.key,
    required this.loc,
    required this.isDarkMode,
  });

  @override
  State<SDKSimulatorPage> createState() => _SDKSimulatorPageState();
}

class _SDKSimulatorPageState extends State<SDKSimulatorPage> {
  final TerminalSDKService _terminalSdk = TerminalSDKService();

  final _formKeyCommand = GlobalKey<FormState>();
  final FocusNode _amountFocusNode = FocusNode();

  final TextEditingController _amountController = TextEditingController(
    text: '\$ 15.000',
  );
  final TextEditingController _ticketNumberController = TextEditingController();
  final TextEditingController _employeeIdController = TextEditingController(
    text: '1',
  );
  final TextEditingController _voidTxIdController = TextEditingController();
  final TextEditingController _comPortController = TextEditingController();
  final TextEditingController _paramKeyController = TextEditingController();
  final TextEditingController _paramValueController = TextEditingController();
  final TextEditingController _authCodeController = TextEditingController();
  final TextEditingController _commerceIdController = TextEditingController(
    text: '1234567',
  );
  final TextEditingController _rutCommerceController = TextEditingController(
    text: '12.345.678-5',
  );
  final TextEditingController _allowedCardsController = TextEditingController(
    text: '12345678, 12345679, 12345670',
  );
  final TextEditingController _hostRrnController = TextEditingController(
    text: '433413000062',
  );
  final TextEditingController _originalMtiController = TextEditingController(
    text: '0200',
  );
  final TextEditingController _originalDe11Controller = TextEditingController(
    text: '621234',
  );
  final TextEditingController _originalDe12Controller = TextEditingController(
    text: '131340',
  );
  final TextEditingController _originalDe13Controller = TextEditingController(
    text: '1129',
  );

  int _saleType = 1; // 0 = Compra, 1 = Compra Afecta, etc.
  bool _sendMessage = false;
  bool _isExecuting = false;
  bool _isPolling = false;
  bool _printOnPos = true;
  int _selectedCategoryIndex = 0; // 0 = Comandos, 1 = Reportes, 2 = Config.
  POSCommandMeta? _activeCommand;
  int _jsonInspectorView = 0; // 0 for Caja Inner JSON, 1 for Signed Envelope
  int _consoleActiveTab = 0; // 0 = Logs, 1 = Request, 2 = Response
  Map<String, dynamic>? _lastRequest;

  List<String> _availableComPorts = [];
  bool _isLoadingPorts = false;
  bool _isCustomPort = false;
  final ScrollController _horizontalScrollController = ScrollController();

  static const List<POSCommandMeta> _financialCommands = [
    POSCommandMeta(
      code: 100,
      labelKey: 'Venta',
      icon: Icons.shopping_cart_outlined,
      descriptionKey: 'Realizar una venta cobrando al cliente',
      isAdvanced: false,
    ),
    POSCommandMeta(
      code: 102,
      labelKey: 'Anulación',
      icon: Icons.replay_outlined,
      descriptionKey: 'Anular una venta del lote actual usando su ID',
      isAdvanced: false,
    ),
    POSCommandMeta(
      code: 108,
      labelKey: 'Reembolso / Devolución',
      icon: Icons.keyboard_return_outlined,
      descriptionKey:
          'Devolver fondos al cliente usando código de autorización',
      isAdvanced: false,
    ),
    POSCommandMeta(
      code: 103,
      labelKey: 'Cierre',
      icon: Icons.lock_outline,
      descriptionKey: 'Cerrar el lote actual de transacciones',
      isAdvanced: false,
    ),
    POSCommandMeta(
      code: 109,
      labelKey: 'Duplicado',
      icon: Icons.copy_all_outlined,
      descriptionKey: 'Imprimir duplicado de una transacción usando su ID',
      isAdvanced: false,
    ),
    POSCommandMeta(
      code: 116,
      labelKey: 'Cancelar venta',
      icon: Icons.cancel_outlined,
      descriptionKey: 'Cancelar transacción en curso en el POS',
      isAdvanced: false,
    ),
  ];

  static const List<POSCommandMeta> _queryCommands = [
    POSCommandMeta(
      code: 106,
      labelKey: 'Consulta',
      icon: Icons.wifi_tethering,
      descriptionKey: 'Verificar conectividad del POS',
      isAdvanced: false,
    ),
    POSCommandMeta(
      code: 101,
      labelKey: 'Último comprobante',
      icon: Icons.receipt_long_outlined,
      descriptionKey: 'Consultar detalles del último voucher emitido',
      isAdvanced: false,
    ),
    POSCommandMeta(
      code: 105,
      labelKey: 'Detalles',
      icon: Icons.info_outline,
      descriptionKey: 'Listar detalles de transacciones del lote',
      isAdvanced: false,
    ),
    POSCommandMeta(
      code: 104,
      labelKey: 'Totales',
      icon: Icons.functions,
      descriptionKey: 'Obtener totales del lote de transacciones',
      isAdvanced: false,
    ),
    POSCommandMeta(
      code: 110,
      labelKey: 'Ventas por vendedor',
      icon: Icons.badge_outlined,
      descriptionKey: 'Consultar ventas acumuladas por ID de vendedor',
      isAdvanced: true,
    ),
    POSCommandMeta(
      code: 111,
      labelKey: 'Informe de propinas',
      icon: Icons.monetization_on_outlined,
      descriptionKey: 'Consultar reporte de propinas acumuladas',
      isAdvanced: true,
    ),
    POSCommandMeta(
      code: 115,
      labelKey: 'Informe SIM',
      icon: Icons.sim_card_outlined,
      descriptionKey: 'Obtener información de la tarjeta SIM del POS',
      isAdvanced: true,
    ),
    POSCommandMeta(
      code: 107,
      labelKey: 'Modo normal',
      icon: Icons.play_arrow_outlined,
      descriptionKey: 'Establecer terminal en modo normal de operación',
      isAdvanced: false,
    ),
    POSCommandMeta(
      code: 113,
      labelKey: 'Venta predeterminada',
      icon: Icons.settings_suggest_outlined,
      descriptionKey: 'Configurar tipo de venta predeterminada',
      isAdvanced: false,
    ),
    POSCommandMeta(
      code: 114,
      labelKey: 'Parámetros',
      icon: Icons.tune_outlined,
      descriptionKey: 'Obtener reporte de configuración de parámetros',
      isAdvanced: false,
    ),
  ];

  static const List<POSCommandMeta> _mcCommands = [
    POSCommandMeta(
      code: 120,
      labelKey: 'Venta MC',
      icon: Icons.store_outlined,
      descriptionKey: 'Realizar venta asignada a un comercio específico',
      isAdvanced: true,
    ),
    POSCommandMeta(
      code: 122,
      labelKey: 'Anulación MC',
      icon: Icons.storefront_outlined,
      descriptionKey: 'Anular venta de un comercio específico',
      isAdvanced: true,
    ),
    POSCommandMeta(
      code: 123,
      labelKey: 'Devolución MC',
      icon: Icons.assignment_return_outlined,
      descriptionKey: 'Devolver fondos de un comercio específico',
      isAdvanced: true,
    ),
    POSCommandMeta(
      code: 124,
      labelKey: 'Datos principales del POS',
      icon: Icons.perm_device_info_outlined,
      descriptionKey: 'Obtener datos principales del terminal POS',
      isAdvanced: true,
    ),
  ];

  List<POSCommandMeta> get _currentCategoryCommands {
    switch (_selectedCategoryIndex) {
      case 0:
        return _financialCommands;
      case 1:
        return _queryCommands;
      case 2:
        return _mcCommands;
      default:
        return _financialCommands;
    }
  }

  void _changeCategory(int index) {
    setState(() {
      _selectedCategoryIndex = index;
    });
  }

  @override
  void initState() {
    super.initState();
    _comPortController.text = _terminalSdk.comPort;
    _generateRandomTicketNumber();
    _activeCommand = _financialCommands.first;

    // Real-time JSON preview: rebuild on any form field change
    for (final ctrl in [
      _amountController,
      _ticketNumberController,
      _employeeIdController,
      _voidTxIdController,
      _authCodeController,
      _rutCommerceController,
      _allowedCardsController,
      _hostRrnController,
      _originalMtiController,
      _originalDe11Controller,
      _originalDe12Controller,
      _originalDe13Controller,
    ]) {
      ctrl.addListener(() {
        if (mounted) setState(() {});
      });
    }

    // Load available COM ports on startup
    _loadAvailablePorts();
  }

  @override
  void dispose() {
    _amountFocusNode.dispose();
    _amountController.dispose();
    _ticketNumberController.dispose();
    _employeeIdController.dispose();
    _voidTxIdController.dispose();
    _comPortController.dispose();
    _paramKeyController.dispose();
    _paramValueController.dispose();
    _authCodeController.dispose();
    _commerceIdController.dispose();
    _rutCommerceController.dispose();
    _allowedCardsController.dispose();
    _hostRrnController.dispose();
    _originalMtiController.dispose();
    _originalDe11Controller.dispose();
    _originalDe12Controller.dispose();
    _originalDe13Controller.dispose();
    _horizontalScrollController.dispose();
    super.dispose();
  }

  void _generateRandomTicketNumber() {
    final rand = 10000 + (DateTime.now().microsecondsSinceEpoch % 90000);
    _ticketNumberController.text = '$rand';
  }

  bool _supportsPrintOnPos(int code) {
    return const [
      100,
      101,
      102,
      103,
      104,
      105,
      108,
      109,
      110,
      111,
      114,
      115,
      120,
      122,
      123,
    ].contains(code);
  }

  void _autocompleteVoidId() {
    if (_terminalSdk.lastSuccessfulTransactionId != null) {
      setState(() {
        _voidTxIdController.text = _terminalSdk.lastSuccessfulTransactionId!;
      });
      _terminalSdk.log(
        'Autocompleted void ID: ${_terminalSdk.lastSuccessfulTransactionId}',
        level: 'DEBUG',
      );
    }
  }

  Future<void> _loadAvailablePorts() async {
    if (_isLoadingPorts) return;
    setState(() {
      _isLoadingPorts = true;
    });

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
  }

  void _handlePoll() async {
    if (connectionStateValue != TerminalConnectionState.connected) return;

    setState(() => _isPolling = true);
    _terminalSdk.log('Ping test triggered (POLL)', level: 'INFO');

    final response = await _terminalSdk.executePoll();

    setState(() => _isPolling = false);

    if (mounted) {
      final code = response['ResponseCode'] ?? -1;
      final msg = response['ResponseMessage'] ?? 'Error';

      if (!msg.toString().toLowerCase().contains('timeout')) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              code == 0
                  ? widget.loc.t('Ping de conexión exitoso')
                  : '${widget.loc.t('Error al ejecutar POLL')}: $msg',
            ),
            backgroundColor: code == 0 ? Colors.green : Colors.red,
          ),
        );
      }
    }
  }

  String _formatCurrentDateTime() {
    final now = DateTime.now();
    final day = now.day.toString().padLeft(2, '0');
    final month = now.month.toString().padLeft(2, '0');
    final year = now.year.toString();
    final hour = now.hour.toString().padLeft(2, '0');
    final minute = now.minute.toString().padLeft(2, '0');
    final second = now.second.toString().padLeft(2, '0');
    return '$day-$month-$year $hour:$minute:$second';
  }

  /// Builds the current request payload from form field values without sending.
  /// Used for real-time JSON preview in the Request tab.
  Map<String, dynamic> _buildRequestPreview(int code) {
    final cleanAmountStr = _amountController.text.replaceAll(RegExp(r'\D'), '');
    final amount = int.tryParse(cleanAmountStr) ?? 0;
    final empId = int.tryParse(_employeeIdController.text) ?? 1;

    final Map<String, dynamic> data = {
      'Command': code,
      'DateTime': _formatCurrentDateTime(),
    };

    switch (code) {
      case 100:
        data.addAll({
          'Amount': amount,
          'TicketNumber': _ticketNumberController.text.trim(),
          'PrintOnPos': _printOnPos,
          'SaleType': _saleType,
          'SendMessage': _sendMessage,
          'EmployeeId': empId,
        });
        break;
      case 102:
        data.addAll({
          'OperationId': int.tryParse(_voidTxIdController.text.trim()) ?? 0,
          'PrintOnPos': _printOnPos,
        });
        break;
      case 108:
        data.addAll({
          'Amount': amount,
          'AuthorizationCode': _authCodeController.text.trim(),
          'PrintOnPos': _printOnPos,
        });
        break;
      case 109:
        data.addAll({
          'OperationId': int.tryParse(_voidTxIdController.text.trim()) ?? 0,
          'PrintOnPos': _printOnPos,
        });
        break;
      case 110:
      case 111:
        data.addAll({'EmployeeId': empId, 'PrintOnPos': _printOnPos});
        break;
      case 113:
        data.addAll({'SaleType': _saleType});
        break;
      case 120:
        final cards = _allowedCardsController.text
            .split(',')
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty)
            .toList();
        data.addAll({
          'Amount': amount,
          'PrintOnPos': _printOnPos,
          'SaleType': _saleType,
          'SendMessage': _sendMessage,
          'RestrictedCards': null,
          'AllowedCards': cards.isEmpty ? [] : cards,
          'RutCommerceSon': _rutCommerceController.text.trim(),
          'CommerceData': null,
          'CommerceParams': null,
          'PlaceCardToPayTimeout': 20,
          'PaymentResultTimeout': 3,
        });
        break;
      case 122:
        data.addAll({
          'Amount': amount,
          'OperationId': int.tryParse(_voidTxIdController.text.trim()) ?? 0,
          'PrintOnPos': _printOnPos,
          'RutCommerceSon': _rutCommerceController.text.trim(),
          'HostRRN': _hostRrnController.text.trim(),
          'SaleType': _saleType,
          'CommerceData': null,
          'OriginalData': {
            'Mti': _originalMtiController.text.trim(),
            'DE11': _originalDe11Controller.text.trim(),
            'DE12': _originalDe12Controller.text.trim(),
            'DE13': _originalDe13Controller.text.trim(),
          },
          'PlaceCardToPayTimeout': 20,
          'PaymentResultTimeout': 3,
        });
        break;
      case 123:
        data.addAll({
          'Amount': amount,
          'AuthorizationCode': _authCodeController.text.trim(),
          'PrintOnPos': _printOnPos,
          'RutCommerceSon': _rutCommerceController.text.trim(),
          'CommerceData': null,
          'PlaceCardToPayTimeout': 20,
          'PaymentResultTimeout': 3,
        });
        break;
      default:
        if (_supportsPrintOnPos(code)) {
          data.addAll({'PrintOnPos': _printOnPos});
        }
        break;
    }

    return data;
  }

  void _handleExecuteCommand(int code) async {
    if (!_formKeyCommand.currentState!.validate()) return;

    setState(() => _isExecuting = true);

    Map<String, dynamic> requestData = {
      'Command': code,
      'DateTime': _formatCurrentDateTime(),
    };

    // Clean amount formatted string to raw numeric integer
    final cleanAmountStr = _amountController.text.replaceAll(RegExp(r'\D'), '');
    final amount = int.tryParse(cleanAmountStr) ?? 0;

    final empId = int.tryParse(_employeeIdController.text) ?? 1;

    switch (code) {
      case 100: // Sale (Venta)
        requestData.addAll({
          'Amount': amount,
          'TicketNumber': _ticketNumberController.text.trim(),
          'PrintOnPos': _printOnPos,
          'SaleType': _saleType,
          'SendMessage': _sendMessage,
          'EmployeeId': empId,
        });
        break;
      case 102: // Cancellation (Anulación)
        requestData.addAll({
          'OperationId': int.tryParse(_voidTxIdController.text.trim()) ?? 0,
          'PrintOnPos': _printOnPos,
        });
        break;
      case 108: // Refund (Reembolso / Devolución)
        requestData.addAll({
          'Amount': amount,
          'AuthorizationCode': _authCodeController.text.trim(),
          'PrintOnPos': _printOnPos,
        });
        break;
      case 109: // Duplicate (Duplicado)
        requestData.addAll({
          'OperationId': int.tryParse(_voidTxIdController.text.trim()) ?? 0,
          'PrintOnPos': _printOnPos,
        });
        break;
      case 110: // Seller Sales (Ventas por vendedor)
      case 111: // Tips Report (Informe de propinas)
        requestData.addAll({'EmployeeId': empId, 'PrintOnPos': _printOnPos});
        break;
      case 113: // Default Sale (Venta predeterminada)
        requestData.addAll({'SaleType': _saleType});
        break;
      case 120: // Venta MC
        List<String> allowedCards = _allowedCardsController.text
            .split(',')
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty)
            .toList();
        requestData.addAll({
          'Amount': amount,
          'PrintOnPos': _printOnPos,
          'SaleType': _saleType,
          'SendMessage': _sendMessage,
          'RestrictedCards': null,
          'AllowedCards': allowedCards.isEmpty ? [] : allowedCards,
          'RutCommerceSon': _rutCommerceController.text.trim(),
          'CommerceData': null,
          'CommerceParams': null,
          'PlaceCardToPayTimeout': 20,
          'PaymentResultTimeout': 3,
        });
        break;
      case 122: // Anulación MC
        requestData.addAll({
          'Amount': amount,
          'OperationId': int.tryParse(_voidTxIdController.text.trim()) ?? 0,
          'PrintOnPos': _printOnPos,
          'RutCommerceSon': _rutCommerceController.text.trim(),
          'HostRRN': _hostRrnController.text.trim(),
          'SaleType': _saleType,
          'CommerceData': null,
          'OriginalData': {
            'Mti': _originalMtiController.text.trim(),
            'DE11': _originalDe11Controller.text.trim(),
            'DE12': _originalDe12Controller.text.trim(),
            'DE13': _originalDe13Controller.text.trim(),
          },
          'PlaceCardToPayTimeout': 20,
          'PaymentResultTimeout': 3,
        });
        break;
      case 123: // Devolución MC
        requestData.addAll({
          'Amount': amount,
          'AuthorizationCode': _authCodeController.text.trim(),
          'PrintOnPos': _printOnPos,
          'RutCommerceSon': _rutCommerceController.text.trim(),
          'CommerceData': null,
          'PlaceCardToPayTimeout': 20,
          'PaymentResultTimeout': 3,
        });
        break;
      default:
        // Direct commands (106, 101, 103, 104, 105, 107, 114, 115, 116, 124) do not need custom params
        if (_supportsPrintOnPos(code)) {
          requestData.addAll({'PrintOnPos': _printOnPos});
        }
        break;
    }

    _terminalSdk.timeoutSeconds = 60; // Timeout hardcoded to 60s

    setState(() {
      _lastRequest = requestData;
      _consoleActiveTab = 1; // Focus Request tab
    });

    final response = await _terminalSdk.executeCustomCommand(requestData);

    setState(() {
      _isExecuting = false;
      _consoleActiveTab = 2; // Focus Response tab
      if (code == 100 || code == 120) {
        _generateRandomTicketNumber();
      }
    });

    if (mounted) {
      final responseCode = response['ResponseCode'] ?? -1;
      final responseMsg = response['ResponseMessage'] ?? widget.loc.t('Error');

      if (!responseMsg.toString().toLowerCase().contains('timeout')) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              responseCode == 0
                  ? '${widget.loc.t('Comando ejecutado con éxito')}: $responseMsg'
                  : '${widget.loc.t('Error al ejecutar')}: $responseMsg',
            ),
            backgroundColor: responseCode == 0 ? Colors.green : Colors.red,
          ),
        );
      }
    }
  }

  void _handleCancelActiveCommand() async {
    _terminalSdk.log(
      'Manual cancellation requested by user. Sending command 116 (Cancel Sale)...',
      level: 'WARN',
    );

    final cancelRequest = {
      'Command': 116,
      'DateTime': _formatCurrentDateTime(),
    };

    // Set UI state to show cancel command is being sent in Request console
    setState(() {
      _lastRequest = cancelRequest;
      _consoleActiveTab =
          1; // Focus Request tab to show the cancellation command
    });

    // Execute command 116 via SDK
    final response = await _terminalSdk.executeCustomCommand(cancelRequest);

    setState(() {
      _isExecuting = false;
      _consoleActiveTab =
          2; // Focus Response tab to show the cancellation response
    });

    if (mounted) {
      final responseCode = response['ResponseCode'] ?? -1;
      final responseMsg = response['ResponseMessage'] ?? widget.loc.t('Error');

      if (!responseMsg.toString().toLowerCase().contains('timeout')) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              responseCode == 0
                  ? '${widget.loc.t('Venta cancelada con éxito')}: $responseMsg'
                  : '${widget.loc.t('Error al cancelar')}: $responseMsg',
            ),
            backgroundColor: responseCode == 0 ? Colors.green : Colors.red,
          ),
        );
      }
    }
  }

  TerminalConnectionState get connectionStateValue =>
      _terminalSdk.connectionState.value;

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDarkMode;
    final primaryColor = isDark ? Colors.cyanAccent : Colors.blueAccent;
    final cardBgColor = isDark ? const Color(0xFF1E293B) : Colors.white;
    final borderColor = isDark ? const Color(0xFF334155) : Colors.black12;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 1. LEFT SIDEBAR (Flex 3): Connection Config + Command Selector (Fixed, no global sidebar scroll)
        Expanded(
          flex: 3,
          child: Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildConnectionConfigCard(
                  cardBgColor,
                  borderColor,
                  primaryColor,
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: _buildCommandSelectorCard(
                    cardBgColor,
                    borderColor,
                    primaryColor,
                  ),
                ),
              ],
            ),
          ),
        ),

        // 2. CENTER PANEL (Flex 4): Configuration Form of selected command
        Expanded(
          flex: 4,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: SingleChildScrollView(
              child: _buildActiveCommandFormCard(
                cardBgColor,
                borderColor,
                primaryColor,
              ),
            ),
          ),
        ),

        // 3. RIGHT PANEL (Flex 5): Unified Developer Console
        Expanded(
          flex: 5,
          child: Padding(
            padding: const EdgeInsets.only(left: 12),
            child: _buildUnifiedConsoleCard(
              cardBgColor,
              borderColor,
              primaryColor,
            ),
          ),
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
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.05),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        ),
                      ],
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
                Icon(Icons.settings_ethernet, color: primary, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    widget.loc.t('Configuración del Terminal'),
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                    overflow: TextOverflow.ellipsis,
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
                        width: double.infinity,
                        height: 42,
                        child: OutlinedButton.icon(
                          onPressed: _isPolling ? null : _handlePoll,
                          icon: _isPolling
                              ? const SizedBox(
                                  width: 12,
                                  height: 12,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 1.5,
                                  ),
                                )
                              : const Icon(Icons.wifi_tethering, size: 14),
                          label: Text(
                            widget.loc.t('Test conexión (POLL)'),
                            style: const TextStyle(fontSize: 12),
                          ),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: primary,
                            side: BorderSide(color: primary),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
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
                        width: double.infinity,
                        height: 42,
                        child: ElevatedButton.icon(
                          onPressed: isConnecting
                              ? null
                              : () => _terminalSdk.connect(),
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
          ],
        ),
      ),
    );
  }

  Widget _buildCommandSelectorCard(Color bg, Color border, Color primary) {
    final commands = _currentCategoryCommands;

    return Card(
      color: bg,
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: border, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Category selector tabs
          Container(
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: border)),
            ),
            child: Row(
              children: [
                _buildCategoryTabButton(
                  0,
                  Icons.payment,
                  widget.loc.t('Comandos'),
                  primary,
                ),
                _buildCategoryTabButton(
                  1,
                  Icons.query_stats,
                  widget.loc.t('Reportes'),
                  primary,
                ),
                _buildCategoryTabButton(
                  2,
                  Icons.store_outlined,
                  widget.loc.t('MC'),
                  primary,
                ),
              ],
            ),
          ),

          // Vertical command list (Independent scroll)
          Expanded(
            child: ListView.separated(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.all(8),
              itemCount: commands.length,
              separatorBuilder: (context, index) => const SizedBox(height: 4),
              itemBuilder: (context, index) {
                final cmd = commands[index];
                final isSelected = _activeCommand?.code == cmd.code;

                return Material(
                  color: isSelected
                      ? primary.withValues(alpha: 0.12)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                  child: InkWell(
                    onTap: () {
                      setState(() {
                        _activeCommand = cmd;
                        _consoleActiveTab = 1; // Auto focus Request tab
                      });
                    },
                    borderRadius: BorderRadius.circular(10),
                    hoverColor: primary.withValues(alpha: 0.05),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: isSelected ? primary : Colors.transparent,
                          width: 1.0,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            cmd.icon,
                            size: 16,
                            color: isSelected
                                ? primary
                                : (widget.isDarkMode
                                      ? Colors.white60
                                      : Colors.black54),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              widget.loc.t(cmd.labelKey),
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: isSelected
                                    ? FontWeight.bold
                                    : FontWeight.w500,
                                color: isSelected
                                    ? primary
                                    : (widget.isDarkMode
                                          ? Colors.white
                                          : Colors.black87),
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? primary.withValues(alpha: 0.2)
                                  : (widget.isDarkMode
                                        ? const Color(0xFF334155)
                                        : Colors.grey.shade200),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              '${cmd.code}',
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                                color: isSelected
                                    ? primary
                                    : (widget.isDarkMode
                                          ? Colors.white70
                                          : Colors.black54),
                                fontFamily: 'monospace',
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryTabButton(
    int index,
    IconData icon,
    String label,
    Color primary,
  ) {
    final isSelected = _selectedCategoryIndex == index;
    final flex = (index == 2) ? 2 : 4;
    final borderRadius = index == 0
        ? const BorderRadius.only(topLeft: Radius.circular(15))
        : (index == 2
              ? const BorderRadius.only(topRight: Radius.circular(15))
              : BorderRadius.zero);

    return Expanded(
      flex: flex,
      child: InkWell(
        onTap: () => _changeCategory(index),
        borderRadius: borderRadius,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            borderRadius: borderRadius,
            border: Border(
              bottom: BorderSide(
                color: isSelected ? primary : Colors.transparent,
                width: 2.5,
              ),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: isSelected ? 15 : 13,
                color: isSelected
                    ? primary
                    : (widget.isDarkMode ? Colors.white38 : Colors.black38),
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  style: TextStyle(
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                    fontSize: isSelected ? 12 : 10,
                    color: isSelected
                        ? primary
                        : (widget.isDarkMode ? Colors.white38 : Colors.black38),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _getCategoryName(int catIndex) {
    switch (catIndex) {
      case 0:
        return 'COMANDOS';
      case 1:
        return 'REPORTES';
      case 2:
        return 'MC';
      default:
        return 'COMANDOS';
    }
  }

  Widget _buildActiveCommandFormCard(Color bg, Color border, Color primary) {
    if (_activeCommand == null) return const SizedBox.shrink();
    final cmd = _activeCommand!;

    return Card(
      color: bg,
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: border, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              children: [
                Icon(cmd.icon, color: primary, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'SDK SIMULATOR / ${_getCategoryName(_selectedCategoryIndex)}',
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                          color: widget.isDarkMode
                              ? Colors.white38
                              : Colors.black38,
                          letterSpacing: 1.0,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Configuración de ${widget.loc.t(cmd.labelKey)}',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: widget.isDarkMode
                              ? Colors.white
                              : Colors.black87,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: primary.withValues(alpha: 0.3)),
                  ),
                  child: Text(
                    'CMD_${cmd.code}',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: primary,
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),

          // Form Content
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Form(
              key: _formKeyCommand,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (cmd.code == 100) ...[
                    _buildVentaForm(border, primary),
                  ] else if (cmd.code == 102 || cmd.code == 109) ...[
                    _buildAnulacionDuplicadoForm(cmd, primary),
                  ] else if (cmd.code == 108) ...[
                    _buildReembolsoForm(primary),
                  ] else if (cmd.code == 110 || cmd.code == 111) ...[
                    _buildVendedorPropinasForm(cmd, primary),
                  ] else if (cmd.code == 113) ...[
                    _buildVentaPredeterminadaForm(border),
                  ] else if (cmd.code == 120) ...[
                    _buildVentaMCForm(border, primary),
                  ] else if (cmd.code == 122) ...[
                    _buildAnulacionMCForm(border, primary),
                  ] else if (cmd.code == 123) ...[
                    _buildDevolucionMCForm(border, primary),
                  ] else ...[
                    // Comandos sin parámetros directos (Poll, LastVoucher, Details, Totals, SetNormalMode, Params, SIM Report, etc.)
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: widget.isDarkMode
                            ? Colors.black12
                            : Colors.grey.shade50,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: border),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.info_outline, color: primary, size: 20),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              widget.loc.t(
                                'Este comando se enviará directamente al POS sin parámetros adicionales.',
                              ),
                              style: TextStyle(
                                fontSize: 12,
                                color: widget.isDarkMode
                                    ? Colors.white70
                                    : Colors.black87,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  if (_supportsPrintOnPos(cmd.code)) ...[
                    const SizedBox(height: 16),
                    _buildSectionHeader(widget.loc.t('OPCIONES DE IMPRESIÓN')),
                    const SizedBox(height: 8),
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

                  const SizedBox(height: 24),
                  ValueListenableBuilder<TerminalConnectionState>(
                    valueListenable: _terminalSdk.connectionState,
                    builder: (context, connState, _) {
                      final isConnected =
                          connState == TerminalConnectionState.connected;

                      // Dynamic colors based on command type
                      List<Color> gradientColors;
                      if (cmd.code == 100 || cmd.code == 104) {
                        gradientColors = widget.isDarkMode
                            ? [
                                const Color(0xFF06B6D4),
                                const Color(0xFF3B82F6),
                              ] // Cyan to Blue
                            : [
                                const Color(0xFF0EA5E9),
                                const Color(0xFF2563EB),
                              ];
                      } else if (cmd.code == 102 || cmd.code == 103) {
                        gradientColors = [
                          const Color(0xFFEC4899),
                          const Color(0xFFEF4444),
                        ]; // Pink to Red
                      } else {
                        gradientColors = widget.isDarkMode
                            ? [
                                const Color(0xFF10B981),
                                const Color(0xFF059669),
                              ] // Emerald to Green
                            : [
                                const Color(0xFF34D399),
                                const Color(0xFF059669),
                              ];
                      }

                      return Row(
                        children: [
                          Expanded(
                            child: _buildGradientButton(
                              label: widget.loc.t('Enviar Comando'),
                              onPressed: (isConnected && !_isExecuting)
                                  ? () => _handleExecuteCommand(cmd.code)
                                  : null,
                              gradientColors: gradientColors,
                              isLoading: _isExecuting,
                            ),
                          ),
                          if (_isExecuting) ...[
                            const SizedBox(width: 12),
                            OutlinedButton.icon(
                              onPressed: _handleCancelActiveCommand,
                              icon: const Icon(
                                Icons.cancel_outlined,
                                color: Colors.redAccent,
                                size: 16,
                              ),
                              label: Text(
                                widget.loc.cancel,
                                style: const TextStyle(
                                  color: Colors.redAccent,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                ),
                              ),
                              style: OutlinedButton.styleFrom(
                                side: const BorderSide(
                                  color: Colors.redAccent,
                                  width: 1.5,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                padding: const EdgeInsets.symmetric(
                                  vertical: 16,
                                  horizontal: 16,
                                ),
                              ),
                            ),
                          ],
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Text(
      title,
      style: TextStyle(
        fontSize: 10,
        fontWeight: FontWeight.bold,
        color: widget.isDarkMode ? Colors.white38 : Colors.black38,
        letterSpacing: 1.0,
      ),
    );
  }

  Widget _buildFormField({
    required String label,
    required TextEditingController controller,
    required IconData icon,
    TextInputType keyboardType = TextInputType.text,
    List<TextInputFormatter>? inputFormatters,
    String? Function(String?)? validator,
    int? maxLength,
    Widget? suffixIcon,
    FocusNode? focusNode,
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
        TextFormField(
          controller: controller,
          keyboardType: keyboardType,
          inputFormatters: inputFormatters,
          validator: validator,
          maxLength: maxLength,
          focusNode: focusNode,
          style: const TextStyle(fontSize: 12),
          buildCounter:
              (
                context, {
                required currentLength,
                required isFocused,
                maxLength,
              }) => null,
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
            counterText: "",
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

  Widget _buildVentaForm(Color border, Color primary) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildSectionHeader(widget.loc.t('VALORES DE TRANSACCIÓN')),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              flex: 5,
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
              flex: 5,
              child: _buildFormField(
                label: widget.loc.t('Número de Ticket'),
                controller: _ticketNumberController,
                icon: Icons.tag,
                maxLength: 24,
                suffixIcon: IconButton(
                  onPressed: _generateRandomTicketNumber,
                  icon: const Icon(Icons.refresh, size: 16),
                  tooltip: 'Generar Ticket',
                ),
                validator: (val) {
                  if (val == null || val.trim().isEmpty) {
                    return widget.loc.t('Requerido');
                  }
                  if (val.trim().length > 24) {
                    return widget.loc.t('Máximo 24 caracteres');
                  }
                  return null;
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Row(
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
                  DropdownMenuItem(
                    value: 5,
                    child: Text(widget.loc.t('Venta Afecta (5)')),
                  ),
                  DropdownMenuItem(
                    value: 6,
                    child: Text(widget.loc.t('Venta Exenta (6)')),
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
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                validator: (val) {
                  if (val == null || val.trim().isEmpty) {
                    return widget.loc.t('Requerido');
                  }
                  final n = int.tryParse(val.trim());
                  if (n == null || n <= 0) return widget.loc.t('ID inválido');
                  if (n > 9999) return widget.loc.t('Máx. 9999');
                  return null;
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _buildSectionHeader(widget.loc.t('OPCIONES AVANZADAS')),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: Text(
                widget.loc.t('Mensajes Intermedios'),
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            Switch(
              value: _sendMessage,
              onChanged: (val) => setState(() => _sendMessage = val),
              activeThumbColor: primary,
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildAnulacionDuplicadoForm(POSCommandMeta cmd, Color primary) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildSectionHeader(widget.loc.t('VALORES DE TRANSACCIÓN')),
        const SizedBox(height: 12),
        _buildFormField(
          label: widget.loc.t(
            cmd.code == 102
                ? 'N° de Comprobante'
                : 'ID de Transacción a Duplicar',
          ),
          controller: _voidTxIdController,
          icon: Icons.history,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          suffixIcon: _terminalSdk.lastSuccessfulTransactionId != null
              ? TextButton.icon(
                  onPressed: _autocompleteVoidId,
                  icon: const Icon(Icons.auto_awesome, size: 14),
                  label: Text(
                    widget.loc.t('Última venta'),
                    style: const TextStyle(fontSize: 10),
                  ),
                )
              : null,
          validator: (val) {
            if (val == null || val.trim().isEmpty) {
              return widget.loc.t('Ingresa el ID de la transacción');
            }
            final n = int.tryParse(val.trim());
            if (n == null || n <= 0) {
              return widget.loc.t('El ID debe ser mayor a 0');
            }
            return null;
          },
        ),
      ],
    );
  }

  Widget _buildReembolsoForm(Color primary) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildSectionHeader(widget.loc.t('VALORES DE TRANSACCIÓN')),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              flex: 5,
              child: _buildFormField(
                label: widget.loc.t('Monto Devolución'),
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
              flex: 5,
              child: _buildFormField(
                label: widget.loc.t('Código de Autorización'),
                controller: _authCodeController,
                icon: Icons.vpn_key_outlined,
                validator: (val) {
                  if (val == null || val.trim().isEmpty) {
                    return widget.loc.t('Requerido');
                  }
                  if (val.trim().length < 4) {
                    return widget.loc.t('Mínimo 4 caracteres');
                  }
                  if (val.trim().length > 20) {
                    return widget.loc.t('Máximo 20 caracteres');
                  }
                  return null;
                },
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildVendedorPropinasForm(POSCommandMeta cmd, Color primary) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildSectionHeader(widget.loc.t('FILTRO DE BÚSQUEDA')),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _buildFormField(
                label: widget.loc.t('ID de Vendedor'),
                controller: _employeeIdController,
                icon: Icons.badge_outlined,
                keyboardType: TextInputType.number,
                maxLength: 4,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                validator: (val) {
                  if (val == null || val.trim().isEmpty) {
                    return widget.loc.t('Requerido');
                  }
                  final n = int.tryParse(val.trim());
                  if (n == null || n <= 0) return widget.loc.t('ID inválido');
                  if (n > 9999) return widget.loc.t('Máx. 9999');
                  return null;
                },
              ),
            ),
            const Spacer(),
          ],
        ),
      ],
    );
  }

  Widget _buildVentaPredeterminadaForm(Color border) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildSectionHeader(widget.loc.t('CONFIGURACIÓN DEL TERMINAL')),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _buildDropdownField<int>(
                label: widget.loc.t('Tipo de Venta Predeterminada'),
                value: _saleType,
                icon: Icons.settings_suggest_outlined,
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
                  DropdownMenuItem(
                    value: 5,
                    child: Text(widget.loc.t('Venta Afecta (5)')),
                  ),
                  DropdownMenuItem(
                    value: 6,
                    child: Text(widget.loc.t('Venta Exenta (6)')),
                  ),
                ],
                onChanged: (val) {
                  if (val != null) {
                    setState(() => _saleType = val);
                  }
                },
              ),
            ),
            const Spacer(),
          ],
        ),
      ],
    );
  }

  Widget _buildVentaMCForm(Color border, Color primary) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildSectionHeader(widget.loc.t('VALORES DE TRANSACCIÓN')),
        const SizedBox(height: 12),
        Row(
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
                label: widget.loc.t('RUT Comercio Hijo'),
                controller: _rutCommerceController,
                icon: Icons.store_outlined,
                inputFormatters: [RutFormatter()],
                validator: (val) {
                  if (val == null || val.trim().isEmpty) {
                    return widget.loc.t('Requerido');
                  }
                  if (!isValidRut(val)) {
                    return widget.loc.t('RUT inválido');
                  }
                  return null;
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Row(
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
                  DropdownMenuItem(
                    value: 5,
                    child: Text(widget.loc.t('Venta Afecta (5)')),
                  ),
                  DropdownMenuItem(
                    value: 6,
                    child: Text(widget.loc.t('Venta Exenta (6)')),
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
                label: widget.loc.t('Tarjetas Permitidas (separadas por coma)'),
                controller: _allowedCardsController,
                icon: Icons.credit_card,
                validator: (val) {
                  if (val == null || val.trim().isEmpty) return null;
                  final cards = val
                      .split(',')
                      .map((s) => s.trim())
                      .where((s) => s.isNotEmpty)
                      .toList();
                  for (final card in cards) {
                    if (!RegExp(r'^\d{6,19}$').hasMatch(card)) {
                      return widget.loc.t('Cada tarjeta: 6-19 dígitos');
                    }
                  }
                  return null;
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _buildSectionHeader(widget.loc.t('OPCIONES AVANZADAS')),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: Text(
                widget.loc.t('Mensajes Intermedios'),
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            Switch(
              value: _sendMessage,
              onChanged: (val) => setState(() => _sendMessage = val),
              activeThumbColor: primary,
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildAnulacionMCForm(Color border, Color primary) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildSectionHeader(widget.loc.t('VALORES DE TRANSACCIÓN')),
        const SizedBox(height: 12),
        Row(
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
                label: widget.loc.t('N° de Comprobante'),
                controller: _voidTxIdController,
                icon: Icons.history,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                validator: (val) {
                  if (val == null || val.trim().isEmpty) {
                    return widget.loc.t('Requerido');
                  }
                  final n = int.tryParse(val.trim());
                  if (n == null || n <= 0) {
                    return widget.loc.t('El ID debe ser mayor a 0');
                  }
                  return null;
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: _buildFormField(
                label: widget.loc.t('RUT Comercio Hijo'),
                controller: _rutCommerceController,
                icon: Icons.store_outlined,
                inputFormatters: [RutFormatter()],
                validator: (val) {
                  if (val == null || val.trim().isEmpty) {
                    return widget.loc.t('Requerido');
                  }
                  if (!isValidRut(val)) {
                    return widget.loc.t('RUT inválido');
                  }
                  return null;
                },
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildFormField(
                label: widget.loc.t('Host RRN'),
                controller: _hostRrnController,
                icon: Icons.dns_outlined,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                maxLength: 12,
                validator: (val) {
                  if (val == null || val.trim().isEmpty) {
                    return widget.loc.t('Requerido');
                  }
                  if (!RegExp(r'^\d{6,12}$').hasMatch(val.trim())) {
                    return widget.loc.t('6 a 12 dígitos');
                  }
                  return null;
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Row(
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
                  DropdownMenuItem(
                    value: 5,
                    child: Text(widget.loc.t('Venta Afecta (5)')),
                  ),
                  DropdownMenuItem(
                    value: 6,
                    child: Text(widget.loc.t('Venta Exenta (6)')),
                  ),
                ],
                onChanged: (val) {
                  if (val != null) {
                    setState(() => _saleType = val);
                  }
                },
              ),
            ),
            const Spacer(),
          ],
        ),
        const SizedBox(height: 16),
        _buildSectionHeader(
          widget.loc.t('DATOS DE VENTA ORIGINAL (ORIGINALDATA)'),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _buildFormField(
                label: widget.loc.t('MTI Original'),
                controller: _originalMtiController,
                icon: Icons.tag,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                maxLength: 4,
                validator: (val) {
                  if (val == null || val.trim().isEmpty) {
                    return widget.loc.t('Requerido');
                  }
                  if (!RegExp(r'^\d{4}$').hasMatch(val.trim())) {
                    return widget.loc.t('4 dígitos (ej. 0200)');
                  }
                  return null;
                },
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildFormField(
                label: widget.loc.t('DE11 / STAN Original'),
                controller: _originalDe11Controller,
                icon: Icons.pin_outlined,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                maxLength: 6,
                validator: (val) {
                  if (val == null || val.trim().isEmpty) {
                    return widget.loc.t('Requerido');
                  }
                  if (!RegExp(r'^\d{1,6}$').hasMatch(val.trim())) {
                    return widget.loc.t('Máx. 6 dígitos');
                  }
                  return null;
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _buildFormField(
                label: widget.loc.t('DE12 / Hora Original (HHMMSS)'),
                controller: _originalDe12Controller,
                icon: Icons.access_time,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                maxLength: 6,
                validator: (val) {
                  if (val == null || val.trim().isEmpty) {
                    return widget.loc.t('Requerido');
                  }
                  if (!RegExp(r'^\d{6}$').hasMatch(val.trim())) {
                    return widget.loc.t('6 dígitos HHMMSS');
                  }
                  return null;
                },
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildFormField(
                label: widget.loc.t('DE13 / Fecha Original (MMDD)'),
                controller: _originalDe13Controller,
                icon: Icons.calendar_today_outlined,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                maxLength: 4,
                validator: (val) {
                  if (val == null || val.trim().isEmpty) {
                    return widget.loc.t('Requerido');
                  }
                  if (!RegExp(r'^\d{4}$').hasMatch(val.trim())) {
                    return widget.loc.t('4 dígitos MMDD');
                  }
                  return null;
                },
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildDevolucionMCForm(Color border, Color primary) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildSectionHeader(widget.loc.t('VALORES DE TRANSACCIÓN')),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _buildFormField(
                label: widget.loc.t('Monto Devolución'),
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
                label: widget.loc.t('Código de Autorización'),
                controller: _authCodeController,
                icon: Icons.vpn_key_outlined,
                validator: (val) {
                  if (val == null || val.trim().isEmpty) {
                    return widget.loc.t('Requerido');
                  }
                  if (val.trim().length < 4) {
                    return widget.loc.t('Mínimo 4 caracteres');
                  }
                  if (val.trim().length > 20) {
                    return widget.loc.t('Máximo 20 caracteres');
                  }
                  return null;
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: _buildFormField(
                label: widget.loc.t('RUT Comercio Hijo'),
                controller: _rutCommerceController,
                icon: Icons.store_outlined,
                inputFormatters: [RutFormatter()],
                validator: (val) {
                  if (val == null || val.trim().isEmpty) {
                    return widget.loc.t('Requerido');
                  }
                  if (!isValidRut(val)) {
                    return widget.loc.t('RUT inválido');
                  }
                  return null;
                },
              ),
            ),
            const Spacer(),
          ],
        ),
      ],
    );
  }

  Widget _buildGradientButton({
    required String label,
    required VoidCallback? onPressed,
    required List<Color> gradientColors,
    bool isLoading = false,
  }) {
    final isDisabled = onPressed == null;
    return Container(
      decoration: BoxDecoration(
        gradient: isDisabled
            ? null
            : LinearGradient(
                colors: gradientColors,
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
        color: isDisabled ? Colors.grey.withValues(alpha: 0.15) : null,
        borderRadius: BorderRadius.circular(10),
        boxShadow: isDisabled
            ? null
            : [
                BoxShadow(
                  color: gradientColors.first.withValues(alpha: 0.3),
                  blurRadius: 8,
                  offset: const Offset(0, 4),
                ),
              ],
      ),
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent,
          shadowColor: Colors.transparent,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
        child: isLoading
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation(Colors.white),
                ),
              )
            : Text(
                label,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  color: Colors.white,
                  letterSpacing: 0.5,
                ),
              ),
      ),
    );
  }

  Widget _buildUnifiedConsoleCard(Color bg, Color border, Color primary) {
    return Card(
      color: bg,
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: border, width: 1),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Console Header & Tab selection
            Row(
              children: [
                Icon(
                  _consoleActiveTab == 0
                      ? Icons.terminal
                      : (_consoleActiveTab == 1
                            ? Icons.arrow_outward
                            : Icons.subdirectory_arrow_left),
                  color: primary,
                  size: 16,
                ),
                const SizedBox(width: 8),
                Text(
                  _consoleActiveTab == 0
                      ? widget.loc.t('Consola de Logs')
                      : (_consoleActiveTab == 1
                            ? widget.loc.t('Petición (Request)')
                            : widget.loc.t('Respuesta (Response)')),
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),

            // Console Tabs Buttons
            Row(
              children: [
                _buildConsoleTabButton(0, widget.loc.t('Logs'), primary),
                const SizedBox(width: 6),
                _buildConsoleTabButton(
                  1,
                  widget.loc.t('Request (Caja)'),
                  primary,
                ),
                const SizedBox(width: 6),
                _buildConsoleTabButton(
                  2,
                  widget.loc.t('Response (POS)'),
                  primary,
                ),
              ],
            ),
            const SizedBox(height: 10),

            // Console Content Area
            Expanded(child: _buildConsoleTabContent(border, primary)),
          ],
        ),
      ),
    );
  }

  Widget _buildConsoleTabButton(int index, String label, Color primary) {
    final isSelected = _consoleActiveTab == index;
    return InkWell(
      onTap: () => setState(() => _consoleActiveTab = index),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected
              ? primary.withValues(alpha: 0.15)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected
                ? primary.withValues(alpha: 0.3)
                : (widget.isDarkMode
                      ? const Color(0xFF334155)
                      : Colors.black12),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 10,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            color: isSelected
                ? primary
                : (widget.isDarkMode ? Colors.white70 : Colors.black87),
          ),
        ),
      ),
    );
  }

  Widget _buildConsoleTabContent(Color border, Color primary) {
    switch (_consoleActiveTab) {
      case 0: // Logs (Event console)
        return ConsoleLogsView(
          terminalSdk: _terminalSdk,
          isDarkMode: widget.isDarkMode,
          cardBgColor: widget.isDarkMode
              ? const Color(0xFF0F172A)
              : Colors.white,
          borderColor: border,
          primaryColor: primary,
          loc: widget.loc,
          embedMode: true,
        );
      case 1: // Request payload - live preview from current form values
        final code = _activeCommand?.code ?? 100;
        final previewData = _isExecuting
            ? (_lastRequest ?? _buildRequestPreview(code))
            : _buildRequestPreview(code);
        final jsonRequest = const JsonEncoder.withIndent(
          '  ',
        ).convert(previewData);
        return _buildJsonViewer(jsonRequest, border, primary);
      case 2: // Response payload
        return ValueListenableBuilder<Map<String, dynamic>?>(
          valueListenable: _terminalSdk.lastResponse,
          builder: (context, response, _) {
            if (response == null) {
              return Center(
                child: Text(
                  widget.loc.t('Esperando transacción...'),
                  style: TextStyle(
                    fontSize: 11,
                    color: widget.isDarkMode ? Colors.white38 : Colors.black38,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              );
            }

            // Construct data to show (Caja Inner vs Signed Envelope)
            String jsonToShow;
            if (_jsonInspectorView == 0) {
              jsonToShow = const JsonEncoder.withIndent('  ').convert(response);
            } else {
              final jsonSerialized = jsonEncode(response);
              final digestBytes = utf8.encode(jsonSerialized);
              final signStr = sha256
                  .convert(digestBytes)
                  .toString()
                  .toUpperCase();
              final envelope = {
                'JsonSerialized': jsonSerialized,
                'Sign': signStr,
              };
              jsonToShow = const JsonEncoder.withIndent('  ').convert(envelope);
            }

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Dual Inspector Tabs inside Response view
                Row(
                  children: [
                    _buildInspectorTab(
                      0,
                      widget.loc.t('JSON de Caja'),
                      primary,
                    ),
                    const SizedBox(width: 8),
                    _buildInspectorTab(
                      1,
                      widget.loc.t('Sobre Getnet (Envelope)'),
                      primary,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Expanded(child: _buildJsonViewer(jsonToShow, border, primary)),
              ],
            );
          },
        );
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildJsonViewer(String jsonText, Color border, Color primary) {
    return Stack(
      children: [
        Container(
          width: double.infinity,
          height: double.infinity,
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: const Color(0xFF0F172A),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: border),
          ),
          child: SingleChildScrollView(
            child: SelectableText(
              jsonText,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 10.0,
                color: Colors.white,
                height: 1.3,
              ),
            ),
          ),
        ),
        Positioned(
          top: 8,
          right: 8,
          child: IconButton(
            icon: const Icon(Icons.copy, size: 14),
            color: primary,
            tooltip: widget.loc.t('Copiar JSON'),
            style: IconButton.styleFrom(
              backgroundColor: widget.isDarkMode
                  ? Colors.black54
                  : Colors.white70,
            ),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: jsonText));
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    widget.loc.t('Respuesta copiada al portapapeles'),
                  ),
                  duration: const Duration(seconds: 2),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildInspectorTab(int index, String label, Color primary) {
    final isSelected = _jsonInspectorView == index;
    return InkWell(
      onTap: () => setState(() => _jsonInspectorView = index),
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: isSelected
              ? primary.withValues(alpha: 0.15)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected
                ? primary.withValues(alpha: 0.3)
                : Colors.transparent,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 9,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            color: isSelected
                ? primary
                : (widget.isDarkMode ? Colors.white54 : Colors.black54),
          ),
        ),
      ),
    );
  }
}
