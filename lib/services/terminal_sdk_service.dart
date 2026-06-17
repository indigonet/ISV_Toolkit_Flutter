import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:isolate';
import 'package:flutter/foundation.dart';
import 'package:crypto/crypto.dart';
import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

enum TerminalConnectionState { disconnected, connecting, connected }

class TerminalSDKService {
  static final TerminalSDKService _instance = TerminalSDKService._internal();
  factory TerminalSDKService() => _instance;
  TerminalSDKService._internal();

  // Connection Settings
  String comPort = 'COM3';
  int timeoutSeconds = 60;

  // State Notifiers
  final ValueNotifier<TerminalConnectionState> connectionState =
      ValueNotifier(TerminalConnectionState.disconnected);
  final ValueNotifier<Map<String, dynamic>?> lastResponse = ValueNotifier(null);

  // Last Successful Transaction ID (for void autocomplete)
  String? lastSuccessfulTransactionId;

  // Isolate-based connection handles
  Isolate? _serialIsolate;
  SendPort? _isolateSendPort;
  ReceivePort? _receivePort;
  Completer<Map<String, dynamic>>? _transactionCompleter;

  // Logs stream
  final StreamController<String> _logController = StreamController<String>.broadcast();
  Stream<String> get logs => _logController.stream;
  final List<String> recentLogs = [];

  // Helper to generate the signature of JsonSerialized payload
  String _signMessage(String jsonSerialized) {
    final bytes = utf8.encode(jsonSerialized);
    final digest = sha256.convert(bytes);
    return digest.toString().toUpperCase();
  }

  // Wrap payload in Getnet Envelope: {"JsonSerialized": "...", "Sign": "..."}
  String _envelopeMessage(Map<String, dynamic> data) {
    final jsonSerialized = jsonEncode(data);
    final sign = _signMessage(jsonSerialized);
    return jsonEncode({
      'JsonSerialized': jsonSerialized,
      'Sign': sign,
    });
  }

  void log(String message, {String level = 'INFO'}) {
    final timestamp = DateTime.now().toIso8601String().substring(11, 19);
    final logLine = '[$timestamp] [$level] $message';
    recentLogs.add(logLine);
    // Keep last 500 logs
    if (recentLogs.length > 500) {
      recentLogs.removeAt(0);
    }
    _logController.add(logLine);
    debugPrint(logLine);
  }

  void clearLogs() {
    recentLogs.clear();
    _logController.add('--- LOGS LIMPIADOS ---');
  }

  Future<bool> connect() async {
    disconnect(); // Close existing first
    connectionState.value = TerminalConnectionState.connecting;
    
    final completer = Completer<bool>();
    _receivePort = ReceivePort();
    
    _receivePort!.listen((message) {
      if (message is SendPort) {
        _isolateSendPort = message;
        // Send connect command to background isolate
        _isolateSendPort!.send({
          'command': 'connect',
          'comPort': comPort,
        });
      } else if (message is Map<String, dynamic>) {
        final type = message['type'] as String;
        if (type == 'status') {
          final stateIndex = message['state'] as int;
          final state = TerminalConnectionState.values[stateIndex];
          connectionState.value = state;
          
          if (!completer.isCompleted) {
            if (state == TerminalConnectionState.connected) {
              completer.complete(true);
              // Execute a quick Poll after connecting to verify real terminal responsiveness
              unawaited(executePoll());
            } else if (state == TerminalConnectionState.disconnected) {
              completer.complete(false);
            }
          }
        } else if (type == 'log') {
          final msg = message['message'] as String;
          final lvl = message['level'] as String;
          log(msg, level: lvl);
        } else if (type == 'rx') {
          final envelope = message['envelope'] as Map<String, dynamic>;
          _handleIncomingPOSMessage(envelope);
        }
      }
    });

    try {
      _serialIsolate = await Isolate.spawn(_serialIsolateEntryPoint, _receivePort!.sendPort);
      // Wait for connect completion or timeout
      return await completer.future.timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          log('Connection attempt timed-out (10s limit).', level: 'ERROR');
          disconnect();
          return false;
        },
      );
    } catch (e) {
      log('Failed to spawn serial background thread: $e', level: 'ERROR');
      disconnect();
      return false;
    }
  }

  void disconnect() {
    if (_isolateSendPort != null) {
      try {
        _isolateSendPort!.send({'command': 'disconnect'});
      } catch (_) {}
    }
    _receivePort?.close();
    _serialIsolate?.kill(priority: Isolate.beforeNextEvent);

    _serialIsolate = null;
    _isolateSendPort = null;
    _receivePort = null;
    _transactionCompleter = null;
    connectionState.value = TerminalConnectionState.disconnected;
  }

  void _handleIncomingPOSMessage(Map<String, dynamic> envelope) {
    if (envelope['Protocol'] == 'simplified') {
      final String raw = envelope['Raw'] as String;
      final int lrc = envelope['LRC'] as int;
      log('Simplified Protocol Received: $raw (LRC: 0x${lrc.toRadixString(16).padLeft(2, '0').toUpperCase()})', level: 'RX');

      final responseData = _parseSimplifiedResponse(raw, lrc);
      lastResponse.value = responseData;

      if (responseData['ResponseCode'] == '0') {
        log('Operation Approved (Simplified)', level: 'SUCCESS');
      } else {
        log('Operation Failed/Rejected (Code: ${responseData['ResponseCode']}) (Simplified)', level: 'ERROR');
      }

      if (_transactionCompleter != null && !_transactionCompleter!.isCompleted) {
        _transactionCompleter!.complete(responseData);
      }
      return;
    }

    // Log the raw message envelope
    log('Message Received (RX Envelope): ${jsonEncode(envelope)}', level: 'RX');

    try {
      // Check for confirmation {"Received": true}
      if (envelope.containsKey('Received') && envelope['Received'] == true) {
        log('POS confirmed receipt of last request (Received: true)', level: 'DEBUG');
        return;
      }

      // POS messages must be acknowledged with {"Received": true}
      _sendAcknowledgement();

      if (envelope.containsKey('JsonSerialized')) {
        final jsonStr = envelope['JsonSerialized'] as String;
        final innerData = jsonDecode(jsonStr) as Map<String, dynamic>;
        
        log('Parsed RX Inner Data: $innerData', level: 'RX');

        // Check if this is an intermediate state message
        if (innerData.containsKey('Message')) {
          final String statusMessage = innerData['Message'] ?? '';
          log('POS Status Message: $statusMessage', level: 'INFO');
        } 
        // Check if this is a final transaction response (FunctionCode & ResponseCode exist)
        else if (innerData.containsKey('ResponseCode') && innerData.containsKey('FunctionCode')) {
          final int responseCode = int.tryParse(innerData['ResponseCode'].toString()) ?? -1;
          final String responseMsg = innerData['ResponseMessage'] ?? 'Rechazada';
          
          lastResponse.value = innerData;
          
          if (responseCode == 0) {
            if (innerData.containsKey('TransactionId')) {
              lastSuccessfulTransactionId = innerData['TransactionId'];
            }
            log('Operation Approved: $responseMsg', level: 'SUCCESS');
          } else {
            log('Operation Rejected (Code: $responseCode): $responseMsg', level: 'ERROR');
          }
          
          // Resolve waiting transaction
          if (_transactionCompleter != null && !_transactionCompleter!.isCompleted) {
            _transactionCompleter!.complete(innerData);
          }
        }
      }
    } catch (e) {
      log('Error decoding POS message: $e', level: 'ERROR');
    }
  }

  Map<String, dynamic> _parseSimplifiedResponse(String raw, int lrc) {
    final parts = raw.split('|');
    final commandCode = parts.isNotEmpty ? int.tryParse(parts[0]) : null;
    
    final Map<String, dynamic> responseData = {
      'Protocol': 'simplified',
      'Command': commandCode,
      'ResponseCode': parts.length > 1 ? parts[1] : '99',
      'ResponseMessage': parts.length > 2 ? parts[2] : 'Rechazada',
      'RawText': raw,
      'LRC': lrc,
    };

    if (commandCode == 100 || commandCode == 109) {
      // Venta / Duplicado
      if (parts.length >= 22) {
        responseData['CommerceCode'] = parts[3];
        responseData['TerminalId'] = parts[4];
        responseData['TicketNumber'] = parts[5];
        responseData['AuthorizationCode'] = parts[6];
        responseData['Amount'] = parts[7];
        responseData['SharesNumber'] = parts[8];
        responseData['SharesAmount'] = parts[9];
        responseData['Last4Digits'] = parts[10];
        responseData['OperationId'] = parts[11];
        responseData['CardType'] = parts[12];
        responseData['AccountingDate'] = parts[13];
        responseData['AccountNumber'] = parts[14];
        responseData['CardBrand'] = parts[15];
        responseData['RealDate'] = parts[16];
        responseData['EmployeeId'] = parts[17];
        responseData['Tip'] = parts[18];
        responseData['SaleType'] = parts[19];
        responseData['PosMode'] = parts[20];
        responseData['Cashback'] = parts[21];
        if (responseData['ResponseCode'] == '0' && responseData['OperationId'] != null) {
          lastSuccessfulTransactionId = responseData['OperationId'].toString();
        }
      } else {
        responseData['Amount'] = parts.length > 2 ? parts[2] : null;
        responseData['TicketNumber'] = parts.length > 3 ? parts[3] : null;
        responseData['AuthorizationCode'] = parts.length > 4 ? parts[4] : null;
      }
    } else if (commandCode == 102) {
      // Anulación
      if (parts.length >= 8) {
        responseData['CommerceCode'] = parts[3];
        responseData['TerminalId'] = parts[4];
        responseData['AuthorizationCode'] = parts[5];
        responseData['OperationId'] = parts[6];
        responseData['Success'] = parts[7];
      }
    } else if (commandCode == 103) {
      // Cierre
      if (parts.length >= 5) {
        responseData['CommerceCode'] = parts[3];
        if (parts.length == 5) {
          responseData['Success'] = parts[4];
        } else {
          responseData['TerminalId'] = parts[4];
          responseData['Success'] = parts[5];
        }
      }
    } else if (commandCode == 105) {
      // Detalle de Ventas
      try {
        final int firstPipe = raw.indexOf('|');
        final int secondPipe = raw.indexOf('|', firstPipe + 1);
        final int thirdPipe = raw.indexOf('|', secondPipe + 1);
        if (firstPipe != -1 && secondPipe != -1 && thirdPipe != -1) {
          responseData['ResponseCode'] = raw.substring(firstPipe + 1, secondPipe);
          responseData['ResponseMessage'] = raw.substring(secondPipe + 1, thirdPipe);
          responseData['SaleDetails'] = raw.substring(thirdPipe + 1);
        }
      } catch (e) {
        log('Error parsing simplified sale details: $e', level: 'ERROR');
      }
    } else if (commandCode == 108) {
      // Devolución
      if (parts.length >= 9) {
        responseData['CommerceCode'] = parts[3];
        responseData['TerminalId'] = parts[4];
        responseData['AuthorizationCode'] = parts[5];
        responseData['OperationId'] = parts[6];
        responseData['Success'] = parts[7];
        responseData['DateTime'] = parts[8];
      }
    }

    return responseData;
  }

  void _sendAcknowledgement() {
    if (_isolateSendPort == null) return;
    
    final ackStr = jsonEncode({'Received': true});
    log('Sending confirmation to POS (Received: true)', level: 'TX');
    
    try {
      _isolateSendPort!.send({
        'command': 'write',
        'data': ackStr,
      });
    } catch (e) {
      log('Failed to dispatch confirmation: $e', level: 'ERROR');
    }
  }

  // POLL Command (106)
  Future<Map<String, dynamic>> executePoll() async {
    lastResponse.value = null;
    if (connectionState.value != TerminalConnectionState.connected) {
      log('Cannot execute POLL: Terminal is disconnected', level: 'ERROR');
      return {'ResponseCode': -1, 'ResponseMessage': 'Disconnected'};
    }

    log('Despatching Command 106 [POLL]...', level: 'TX');

    return await _sendSerialCommand({
      'Command': 106,
      'DateTime': DateTime.now().toIso8601String().replaceAll('T', ' ').substring(0, 19),
    });
  }

  // SALE Command (100)
  Future<Map<String, dynamic>> executeSale({
    required double amount,
    required String ticketNumber,
    bool printOnPos = false,
    required int saleType,
    bool sendMessage = false,
    int employeeId = 1,
  }) async {
    lastResponse.value = null;
    if (connectionState.value != TerminalConnectionState.connected) {
      log('Cannot execute SALE: Terminal is disconnected', level: 'ERROR');
      return {'ResponseCode': -1, 'ResponseMessage': 'Disconnected'};
    }

    log('Despatching Command 100 [SALE]...', level: 'TX');

    final data = {
      'Command': 100,
      'Amount': amount.toInt(),
      'TicketNumber': ticketNumber,
      'PrintOnPos': printOnPos,
      'SaleType': saleType,
      'SendMessage': sendMessage,
      'EmployeeId': employeeId,
      'DateTime': DateTime.now().toIso8601String().replaceAll('T', ' ').substring(0, 19),
    };

    return await _sendSerialCommand(data);
  }

  // REFUND / VOID Command (102)
  Future<Map<String, dynamic>> executeVoid({
    required String transactionId,
    bool printOnPos = false,
  }) async {
    lastResponse.value = null;
    if (connectionState.value != TerminalConnectionState.connected) {
      log('Cannot execute REFUND: Terminal is disconnected', level: 'ERROR');
      return {'ResponseCode': -1, 'ResponseMessage': 'Disconnected'};
    }

    log('Despatching Command 102 [REFUND] for ID: $transactionId...', level: 'TX');

    final data = {
      'Command': 102,
      'OperationId': transactionId,
      'PrintOnPos': printOnPos,
      'DateTime': DateTime.now().toIso8601String().replaceAll('T', ' ').substring(0, 19),
    };

    return await _sendSerialCommand(data);
  }

  // Execute custom map commands (for dynamic support of all 18+ POS commands)
  Future<Map<String, dynamic>> executeCustomCommand(Map<String, dynamic> data) async {
    lastResponse.value = null;
    if (connectionState.value != TerminalConnectionState.connected) {
      final cmd = data['Command'] ?? 'UNKNOWN';
      log('Cannot execute command $cmd: Terminal is disconnected', level: 'ERROR');
      return {'ResponseCode': -1, 'ResponseMessage': 'Disconnected'};
    }
    final cmd = data['Command'] ?? 'UNKNOWN';
    log('Despatching Command $cmd...', level: 'TX');
    return await _sendSerialCommand(data);
  }

  // Helper to send Getnet format through Serial COM via Isolate and await signed response
  Future<Map<String, dynamic>> _sendSerialCommand(Map<String, dynamic> data) async {
    if (_isolateSendPort == null) {
      log('COM port background thread is not active. Operation aborted.', level: 'ERROR');
      return {'ResponseCode': -1, 'ResponseMessage': 'COM port not connected'};
    }

    final envelopeStr = _envelopeMessage(data);
    log('Sending Message (TX Envelope): $envelopeStr', level: 'TX');
    
    _transactionCompleter = Completer<Map<String, dynamic>>();
    
    try {
      _isolateSendPort!.send({
        'command': 'write',
        'data': envelopeStr,
      });

      final response = await _transactionCompleter!.future.timeout(
        Duration(seconds: timeoutSeconds),
      );
      
      return response;
    } on TimeoutException {
      log('POS response timeout after $timeoutSeconds seconds.', level: 'ERROR');
      _transactionCompleter = null;
      return {
        'ResponseCode': 99,
        'ResponseMessage': 'TIMEOUT ERROR',
      };
    } catch (e) {
      log('Exception during serial exchange: $e', level: 'ERROR');
      _transactionCompleter = null;
      return {
        'ResponseCode': -1,
        'ResponseMessage': e.toString(),
      };
    }
  }

  // Send Simplified Protocol Command
  Future<Map<String, dynamic>> sendSimplifiedCommand(String content) async {
    if (_isolateSendPort == null) {
      log('COM port background thread is not active. Operation aborted.', level: 'ERROR');
      return {'ResponseCode': -1, 'ResponseMessage': 'COM port not connected'};
    }

    final contentBytes = utf8.encode(content);
    // STX (0x02) + Content + ETX (0x03)
    final List<int> packet = [];
    packet.add(0x02);
    packet.addAll(contentBytes);
    packet.add(0x03);

    // Calculate LRC (XOR of content + ETX, omitting STX)
    int lrc = 0;
    for (int i = 1; i < packet.length; i++) {
      lrc ^= packet[i];
    }
    packet.add(lrc);

    final hexStr = packet.map((b) => '0x${b.toRadixString(16).padLeft(2, '0').toUpperCase()}').join(' ');
    log('Sending Simplified Request (Hex): $hexStr', level: 'TX');
    log('Sending Simplified Request (ASCII): <STX>$content<ETX><0x${lrc.toRadixString(16).padLeft(2, '0').toUpperCase()}>', level: 'TX');

    _transactionCompleter = Completer<Map<String, dynamic>>();

    try {
      _isolateSendPort!.send({
        'command': 'write',
        'data': packet,
      });

      final response = await _transactionCompleter!.future.timeout(
        Duration(seconds: timeoutSeconds),
      );

      return response;
    } on TimeoutException {
      log('POS response timeout after $timeoutSeconds seconds.', level: 'ERROR');
      _transactionCompleter = null;
      return {
        'ResponseCode': 99,
        'ResponseMessage': 'TIMEOUT ERROR',
      };
    } catch (e) {
      log('Exception during serial exchange: $e', level: 'ERROR');
      _transactionCompleter = null;
      return {
        'ResponseCode': -1,
        'ResponseMessage': e.toString(),
      };
    }
  }
}

// Entry point for the background serial isolate
void _serialIsolateEntryPoint(SendPort mainSendPort) {
  final receivePort = ReceivePort();
  mainSendPort.send(receivePort.sendPort);

  int hComm = INVALID_HANDLE_VALUE;
  bool isListening = false;

  void sendLog(String message, String level) {
    mainSendPort.send({'type': 'log', 'message': message, 'level': level});
  }

  void sendStatus(TerminalConnectionState state) {
    mainSendPort.send({'type': 'status', 'state': state.index});
  }

  void sendRx(Map<String, dynamic> envelope) {
    mainSendPort.send({'type': 'rx', 'envelope': envelope});
  }

  // Background read polling loop
  Future<void> startReadLoop() async {
    isListening = true;
    final bufferSize = 4096;
    final buffer = calloc<Uint8>(bufferSize);
    final bytesRead = calloc<DWORD>();
    final List<int> accumulatedBytes = [];

    try {
      while (isListening && hComm != INVALID_HANDLE_VALUE) {
        await Future.delayed(const Duration(milliseconds: 20));

        final result = ReadFile(
          hComm,
          buffer,
          bufferSize,
          bytesRead,
          nullptr,
        );

        if (result == 0) {
          final err = GetLastError();
          if (err != ERROR_IO_PENDING) {
            sendLog('ReadFile error: $err. Disconnecting...', 'ERROR');
            break;
          }
          continue;
        }

        final int count = bytesRead.value;
        if (count > 0) {
          final rawBytes = buffer.asTypedList(count);
          accumulatedBytes.addAll(rawBytes);

          bool parsedSomething = true;
          while (parsedSomething && accumulatedBytes.isNotEmpty) {
            parsedSomething = false;

            int jsonStart = accumulatedBytes.indexOf(0x7B); // '{'
            int stxStart = accumulatedBytes.indexOf(0x02); // STX

            if (jsonStart != -1 && (stxStart == -1 || jsonStart < stxStart)) {
              int braceCount = 0;
              int endIdx = -1;
              for (int i = jsonStart; i < accumulatedBytes.length; i++) {
                if (accumulatedBytes[i] == 0x7B) {
                  braceCount++;
                } else if (accumulatedBytes[i] == 0x7D) {
                  braceCount--;
                  if (braceCount == 0) {
                    endIdx = i;
                    break;
                  }
                }
              }

              if (endIdx != -1) {
                final packetBytes = accumulatedBytes.sublist(jsonStart, endIdx + 1);
                final jsonStr = utf8.decode(packetBytes, allowMalformed: true);
                try {
                  final Map<String, dynamic> data = jsonDecode(jsonStr);
                  sendRx(data);
                } catch (_) {}
                accumulatedBytes.removeRange(0, endIdx + 1);
                parsedSomething = true;
              } else {
                if (jsonStart > 0) {
                  accumulatedBytes.removeRange(0, jsonStart);
                }
              }
            } else if (stxStart != -1) {
              int etxIndex = -1;
              for (int i = stxStart + 1; i < accumulatedBytes.length; i++) {
                if (accumulatedBytes[i] == 0x03) { // ETX
                  etxIndex = i;
                  break;
                }
              }

              if (etxIndex != -1 && accumulatedBytes.length > etxIndex + 1) {
                final contentBytes = accumulatedBytes.sublist(stxStart + 1, etxIndex);
                final lrc = accumulatedBytes[etxIndex + 1];
                final rawContent = utf8.decode(contentBytes, allowMalformed: true);

                sendRx({
                  'Protocol': 'simplified',
                  'Raw': rawContent,
                  'LRC': lrc,
                });

                accumulatedBytes.removeRange(0, etxIndex + 2);
                parsedSomething = true;
              } else {
                if (stxStart > 0) {
                  accumulatedBytes.removeRange(0, stxStart);
                }
              }
            } else {
              accumulatedBytes.clear();
            }
          }
        }
      }
    } catch (e) {
      sendLog('Exception in serial read loop: $e', 'ERROR');
    } finally {
      calloc.free(buffer);
      calloc.free(bytesRead);
      if (hComm != INVALID_HANDLE_VALUE) {
        CloseHandle(hComm);
        hComm = INVALID_HANDLE_VALUE;
      }
      isListening = false;
      sendStatus(TerminalConnectionState.disconnected);
    }
  }

  receivePort.listen((message) async {
    if (message is! Map) return;
    final command = message['command'] as String?;

    if (command == 'connect') {
      final comPort = message['comPort'] as String;
      sendStatus(TerminalConnectionState.connecting);

      final formattedPort = comPort.startsWith(r'\\.\') ? comPort : r'\\.\' + comPort;
      sendLog('Connecting to POS Terminal on serial port $formattedPort...', 'INFO');

      final portNamePtr = formattedPort.toNativeUtf16();
      hComm = CreateFile(
        portNamePtr,
        GENERIC_READ | GENERIC_WRITE,
        0,
        nullptr,
        OPEN_EXISTING,
        0,
        NULL,
      );

      if (hComm == INVALID_HANDLE_VALUE) {
        final err = GetLastError();
        calloc.free(portNamePtr);
        sendLog('Failed to open COM port $comPort. Error: $err', 'ERROR');
        sendStatus(TerminalConnectionState.disconnected);
        return;
      }
      calloc.free(portNamePtr);

      // Allocate buffer queue sizes for high throughput
      SetupComm(hComm, 4096, 4096);

      // Configure Port State (BaudRate, ByteSize, Parity, StopBits)
      final dcb = calloc<DCB>();
      dcb.ref.DCBlength = sizeOf<DCB>();
      if (GetCommState(hComm, dcb) == 0) {
        final err = GetLastError();
        sendLog('GetCommState failed. Error: $err', 'ERROR');
        CloseHandle(hComm);
        hComm = INVALID_HANDLE_VALUE;
        calloc.free(dcb);
        sendStatus(TerminalConnectionState.disconnected);
        return;
      }

      dcb.ref.BaudRate = 115200;
      dcb.ref.ByteSize = 8;
      dcb.ref.Parity = NOPARITY;
      dcb.ref.StopBits = ONESTOPBIT;
      dcb.ref.bitfield = 1; // Clear flow control flags inside the bitfield

      if (SetCommState(hComm, dcb) == 0) {
        final err = GetLastError();
        sendLog('SetCommState failed. Error: $err', 'ERROR');
        CloseHandle(hComm);
        hComm = INVALID_HANDLE_VALUE;
        calloc.free(dcb);
        sendStatus(TerminalConnectionState.disconnected);
        return;
      }
      calloc.free(dcb);

      // Configure Timeouts (Non-blocking reads)
      final timeouts = calloc<COMMTIMEOUTS>();
      const maxDword = 0xFFFFFFFF;
      timeouts.ref.ReadIntervalTimeout = maxDword;
      timeouts.ref.ReadTotalTimeoutMultiplier = 0;
      timeouts.ref.ReadTotalTimeoutConstant = 0;
      timeouts.ref.WriteTotalTimeoutMultiplier = 0;
      timeouts.ref.WriteTotalTimeoutConstant = 0;

      if (SetCommTimeouts(hComm, timeouts) == 0) {
        final err = GetLastError();
        sendLog('SetCommTimeouts failed. Error: $err', 'ERROR');
        CloseHandle(hComm);
        hComm = INVALID_HANDLE_VALUE;
        calloc.free(timeouts);
        sendStatus(TerminalConnectionState.disconnected);
        return;
      }
      calloc.free(timeouts);

      // Clean any stale Tx/Rx hardware buffers
      PurgeComm(hComm, PURGE_TXABORT | PURGE_RXABORT | PURGE_TXCLEAR | PURGE_RXCLEAR);

      sendStatus(TerminalConnectionState.connected);
      sendLog('Connected to POS Terminal on $comPort', 'SUCCESS');

      // Start background read polling loop
      startReadLoop();

    } else if (command == 'write') {
      if (hComm == INVALID_HANDLE_VALUE) {
        sendLog('Cannot write: COM port is not open.', 'ERROR');
        return;
      }
      final dynamic rawData = message['data'];

      try {
        final List<int> bytes = rawData is String ? utf8.encode(rawData) : List<int>.from(rawData);
        final buffer = calloc<Uint8>(bytes.length);
        buffer.asTypedList(bytes.length).setAll(0, bytes);
        final bytesWritten = calloc<DWORD>();

        final result = WriteFile(
          hComm,
          buffer,
          bytes.length,
          bytesWritten,
          nullptr,
        );

        final writtenCount = bytesWritten.value;
        calloc.free(buffer);
        calloc.free(bytesWritten);

        if (result == 0 || writtenCount != bytes.length) {
          final err = GetLastError();
          sendLog('WriteFile failed. Error: $err. Written: $writtenCount/${bytes.length}', 'ERROR');
        }
      } catch (e) {
        sendLog('Exception during WriteFile in isolate: $e', 'ERROR');
      }

    } else if (command == 'disconnect') {
      isListening = false;
      if (hComm != INVALID_HANDLE_VALUE) {
        CloseHandle(hComm);
        hComm = INVALID_HANDLE_VALUE;
      }
      sendStatus(TerminalConnectionState.disconnected);
      receivePort.close();
    }
  });
}
