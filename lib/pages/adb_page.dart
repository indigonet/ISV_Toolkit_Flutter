import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:window_manager/window_manager.dart';
import '../core/localization.dart';

import '../services/sdk_service.dart';

class AdbPage extends StatefulWidget {
  final AppLocale loc;
  final bool isDarkMode;
  final String adbStatus;
  final SDKService sdk;

  const AdbPage({
    super.key,
    required this.loc,
    required this.isDarkMode,
    required this.adbStatus,
    required this.sdk,
  });

  @override
  State<AdbPage> createState() => _AdbPageState();
}

class _AdbPageState extends State<AdbPage> {
  final List<String> _logs = [];
  final ScrollController _scrollController = ScrollController();
  bool _isLogcatRunning = false;
  String? _selectedPackage;
  List<String> _packages = [];
  String _selectedLevel = "D"; // Default to Debug
  bool _autoScroll = true;
  StreamSubscription? _logSubscription;
  Process? _logcatProcess;

  // Search
  final TextEditingController _searchController = TextEditingController();
  List<int> _searchMatches = [];
  int _currentSearchIndex = -1;

  // Buffer for logs to avoid excessive UI updates
  final List<String> _logBuffer = [];
  Timer? _logUpdateTimer;

  final TextEditingController _packageSearchController =
      TextEditingController();

  String? _currentPid;
  Timer? _pidPollTimer;

  // Stats
  int _debugCount = 0;
  int _warnCount = 0;
  int _errorCount = 0;

  void _runSearch(String value) {
    if (value.length < 3) {
      setState(() {
        _searchMatches = [];
        _currentSearchIndex = -1;
      });
      return;
    }

    final List<int> matches = [];
    for (int i = 0; i < _logs.length; i++) {
      if (_logs[i].toLowerCase().contains(value.toLowerCase())) {
        matches.add(i);
      }
    }

    setState(() {
      _searchMatches = matches;
      _currentSearchIndex = matches.isNotEmpty ? 0 : -1;
    });

    if (_searchMatches.isNotEmpty) {
      _scrollToMatch(_searchMatches[0]);
    }
  }

  void _nextMatch() {
    if (_searchMatches.isEmpty) return;
    setState(() {
      _currentSearchIndex = (_currentSearchIndex + 1) % _searchMatches.length;
    });
    _scrollToMatch(_searchMatches[_currentSearchIndex]);
  }

  void _prevMatch() {
    if (_searchMatches.isEmpty) return;
    setState(() {
      _currentSearchIndex =
          (_currentSearchIndex - 1 + _searchMatches.length) %
          _searchMatches.length;
    });
    _scrollToMatch(_searchMatches[_currentSearchIndex]);
  }

  void _scrollToMatch(int index) {
    if (!_scrollController.hasClients) return;
    
    _autoScroll = false;

    // Con itemExtent: 16.0, el cálculo es exacto:
    // (index * 16.0) + padding superior (8.0)
    // Restamos un poco de offset (32.0) para que la línea no quede pegada arriba, sino un poco más centrada
    final double targetOffset = (index * 16.0) + 8.0 - 32.0;
    
    _scrollController.animateTo(
      targetOffset.clamp(0.0, _scrollController.position.maxScrollExtent),
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  void initState() {
    super.initState();
    _loadPackages();
    widget.sdk.refreshTick.addListener(_loadPackages);
  }

  @override
  void didUpdateWidget(AdbPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.adbStatus != widget.adbStatus) {
      _loadPackages();
    }
  }

  @override
  void dispose() {
    widget.sdk.refreshTick.removeListener(_loadPackages);
    _stopLogcat();
    _logUpdateTimer?.cancel();
    _pidPollTimer?.cancel();
    _scrollController.dispose();
    _packageSearchController.dispose();
    super.dispose();
  }

  Future<void> _loadPackages() async {
    final list = await widget.sdk.getPackages();
    if (mounted) {
      setState(() {
        _packages = list;
        _packages.sort();
      });
    }
  }

  void _startLogcat() async {
    if (_isLogcatRunning) {
      _stopLogcat();
      return;
    }

    setState(() {
      _isLogcatRunning = true;
      _logs.add("--- INICIANDO LOGCAT ---");
    });

    _logcatProcess = await widget.sdk.startLogcat(
      packageName: _selectedPackage,
      level: _selectedLevel,
    );

    _currentPid = null;
    if (_selectedPackage != null && _selectedPackage!.isNotEmpty) {
      _startPidPolling();
    }

    if (_logcatProcess != null) {
      _logSubscription = _logcatProcess!.stdout
          .transform(const Utf8Decoder(allowMalformed: true))
          .transform(const LineSplitter())
          .listen((line) {
            bool shouldAdd = true;

            if (_selectedPackage != null && _selectedPackage!.isNotEmpty) {
              if (_currentPid != null) {
                // regex to match PID in threadtime format: MM-DD HH:MM:SS.ms  PID  TID V TAG: message
                // The PID is the first number after the timestamp.
                final match = RegExp(
                  r'^\d{2}-\d{2}\s\d{2}:\d{2}:\d{2}\.\d{3}\s+(\d+)\s+',
                ).firstMatch(line);
                if (match != null) {
                  final linePid = match.group(1);
                  if (linePid != _currentPid) {
                    shouldAdd = false;
                  }
                } else {
                  // If it doesn't match threadtime, it might be a header or something else.
                  // We can choose to keep it or drop it. Usually headers are kept.
                  if (line.startsWith('---------')) {
                    shouldAdd = true;
                  } else {
                    shouldAdd = false;
                  }
                }
              } else {
                // Package selected but PID not found yet (app not running)
                shouldAdd = false;
              }
            }

            if (shouldAdd) {
              _logBuffer.add(line);
              if (_logUpdateTimer == null || !_logUpdateTimer!.isActive) {
                _logUpdateTimer = Timer(const Duration(milliseconds: 100), () {
                  if (mounted && _logBuffer.isNotEmpty) {
                    setState(() {
                      final String searchTerm = _searchController.text.toLowerCase();
                      
                      
                      for (var logLine in _logBuffer) {
                        _logs.add(logLine);
                        
                        // Si hay búsqueda activa, registrar nuevas coincidencias
                        if (searchTerm.length >= 3 && logLine.toLowerCase().contains(searchTerm)) {
                          _searchMatches.add(_logs.length - 1);
                        }

                        if (logLine.contains(' D/')) _debugCount++;
                        if (logLine.contains(' W/')) _warnCount++;
                        if (logLine.contains(' E/')) _errorCount++;
                      }
                      
                      // Manejar el límite de 2000 líneas y DESPLAZAR índices de búsqueda
                      if (_logs.length > 2000) {
                        int removedCount = _logs.length - 2000;
                        _logs.removeRange(0, removedCount);
                        
                        // CRITICAL: Ajustar todos los índices de búsqueda existentes
                        if (_searchMatches.isNotEmpty) {
                          final List<int> newMatches = [];
                          int matchToKeepFocus = -1;
                          
                          for (int i = 0; i < _searchMatches.length; i++) {
                            int newIdx = _searchMatches[i] - removedCount;
                            if (newIdx >= 0) {
                              newMatches.add(newIdx);
                              // Si este era el índice que el usuario estaba mirando, intentar mantenerlo
                              if (i == _currentSearchIndex) {
                                matchToKeepFocus = newMatches.length - 1;
                              }
                            }
                          }
                          
                          _searchMatches = newMatches;
                          if (matchToKeepFocus != -1) {
                            _currentSearchIndex = matchToKeepFocus;
                          } else if (_searchMatches.isEmpty) {
                            _currentSearchIndex = -1;
                          } else {
                            // Si se borró el que estábamos viendo, ajustar al más cercano
                            _currentSearchIndex = _currentSearchIndex.clamp(-1, _searchMatches.length - 1);
                          }
                        }
                      }
                      
                      _logBuffer.clear();
                    });

                    if (_autoScroll) {
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (_scrollController.hasClients) {
                          _scrollController.jumpTo(
                            _scrollController.position.maxScrollExtent,
                          );
                        }
                      });
                    }
                  }
                });
              }
            }
          });
    }
  }

  void _stopLogcat() {
    _logSubscription?.cancel();
    _logcatProcess?.kill();
    _pidPollTimer?.cancel();
    setState(() {
      _isLogcatRunning = false;
      _logs.add("--- LOGCAT DETENIDO ---");
    });
  }

  void _startPidPolling() {
    _pidPollTimer?.cancel();
    _updatePid();
    _pidPollTimer = Timer.periodic(const Duration(seconds: 2), (timer) {
      if (!_isLogcatRunning) {
        timer.cancel();
        return;
      }
      _updatePid();
    });
  }

  void _updatePid() async {
    if (_selectedPackage == null || _selectedPackage!.isEmpty) return;

    try {
      final pidRes = await Process.run(widget.sdk.adbPath, [
        'shell',
        'pidof',
        '-s',
        _selectedPackage!,
      ]);
      String pid = pidRes.stdout.toString().trim();

      if (pidRes.exitCode != 0 || pid.isEmpty) {
        // Fallback ps -A
        final psRes = await Process.run(widget.sdk.adbPath, [
          'shell',
          'ps',
          '-A',
        ]);
        final lines = psRes.stdout.toString().split('\n');
        for (var l in lines) {
          if (l.contains(_selectedPackage!)) {
            final parts = l.trim().split(RegExp(r'\s+'));
            if (parts.length > 1) {
              pid = parts[1];
              break;
            }
          }
        }
      }

      if (pid != _currentPid) {
        setState(() {
          _currentPid = pid.isEmpty ? null : pid;
        });
        if (_currentPid != null) {
          debugPrint(
            "DEBUG LOGCAT: New PID found for $_selectedPackage: $_currentPid",
          );
        }
      }
    } catch (e) {
      debugPrint("DEBUG LOGCAT: Error polling PID: $e");
    }
  }

  void _clearLogs() {
    setState(() {
      _logs.clear();
      _logBuffer.clear();
      _debugCount = 0;
      _warnCount = 0;
      _errorCount = 0;
      _searchMatches.clear();
      _currentSearchIndex = -1;
    });
    // Forzar un pequeño log para confirmar que sigue vivo si es necesario,
    // pero el listener debería seguir funcionando.
  }

  Future<void> _saveLogs() async {
    if (_logs.isEmpty) {
      return;
    }

    final now = DateTime.now();
    final timestamp = "${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}_"
        "${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}${now.second.toString().padLeft(2, '0')}";
    
    // Preparar nombre de archivo sugerido
    String suggestedName = 'logcat_$timestamp.txt';
    if (_selectedPackage != null && _selectedPackage!.isNotEmpty) {
      suggestedName = 'logcat_${_selectedPackage}_$timestamp.txt';
    }
    
    try { await windowManager.focus(); } catch(_) {}

    String? path = await FilePicker.platform.saveFile(
      dialogTitle: widget.loc.saveLog,
      fileName: suggestedName,
      type: FileType.custom,
      allowedExtensions: ['txt'],
    );

    if (path != null) {
      final file = File(path);
      
      // Construir contenido con cabecera profesional
      final buffer = StringBuffer();
      buffer.writeln("==================================================");
      buffer.writeln("            LOGCAT DE ISV TOOLKIT               ");
      buffer.writeln("==================================================");
      buffer.writeln("FECHA: ${now.toString()}");
      buffer.writeln("PACKAGE FILTRADO: ${_selectedPackage ?? 'NINGUNO'}");
      buffer.writeln("--------------------------------------------------");
      buffer.writeln("");
      buffer.writeln(_logs.join('\n'));

      await file.writeAsString(buffer.toString());
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${widget.loc.t("Log guardado en")}: $path'),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  void _showStatsDialog() async {
    if (_selectedPackage == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            widget.loc.t('Selecciona una aplicación para ver estadísticas'),
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (context) {
        return _StatsDialog(
          packageName: _selectedPackage!,
          sdk: widget.sdk,
          isDark: widget.isDarkMode,
          loc: widget.loc,
        );
      },
    );
  }

  Color _getLogColor(String line) {
    final upper = line.toUpperCase();

    // ASSERT (Light Purple)
    if (line.contains(' A/') || upper.contains('ASSERT')) {
      return const Color(0xFFCE93D8);
    }

    // FATAL/CRASH/RUNTIME ERROR (Softer Red)
    if (upper.contains('FATAL') ||
        upper.contains('CRASH') ||
        upper.contains('EXCEPTION') ||
        line.contains(' E/AndroidRuntime')) {
      return const Color(0xFFEF9A9A);
    }

    // ERROR (Light Red)
    if (line.contains(' E/')) {
      return const Color(0xFFFFAB91);
    }

    // WARN (Light Yellow)
    if (line.contains(' W/') ||
        upper.contains('HTTP') ||
        upper.contains('-->') ||
        upper.contains('<--') ||
        upper.contains('RETROFIT') ||
        upper.contains('OKHTTP') ||
        upper.contains('POST ') ||
        upper.contains('GET ')) {
      return const Color(0xFFFFF59D);
    }

    // INFO (Light Green)
    if (line.contains(' I/')) {
      return const Color(0xFFA5D6A7);
    }

    // DEBUG (Light Blue)
    if (line.contains(' D/')) {
      return const Color(0xFF90CAF9);
    }

    // VERBOSE (Light Grey)
    if (line.contains(' V/')) {
      return const Color(0xFFEEEEEE);
    }

    // Default always light because the console is dark
    return Colors.white.withValues(alpha: 0.9);
  }

  Color? _getLogBgColor(String line) {
    final upper = line.toUpperCase();
    if (upper.contains('FATAL') ||
        upper.contains('CRASH') ||
        line.contains(' E/AndroidRuntime')) {
      return Colors.redAccent.withValues(
        alpha: 0.15,
      ); // Highlight crash background
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final isD = widget.isDarkMode;
    final color = isD ? Colors.cyanAccent : Colors.blueAccent;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.pets, color: color, size: 28),
            const SizedBox(width: 12),
            Text(
              widget.loc.t("LOGCAT MONITOR"),
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w900,
                color: isD ? Colors.white : Colors.black87,
                letterSpacing: 1.2,
              ),
            ),
            const Spacer(),
            Text(
              "",
              style: TextStyle(
                fontSize: 10,
                color: isD ? Colors.white38 : Colors.grey[600],
                fontFamily: 'Consolas',
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),

        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: isD ? const Color(0xFF1E1E1E) : Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isD
                  ? Colors.white.withValues(alpha: 0.1)
                  : Colors.blueGrey.withValues(alpha: 0.1),
            ),
            boxShadow: isD
                ? []
                : [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
          ),
          child: Column(
            children: [
              Row(
                children: [
                  const Icon(Icons.search, size: 16, color: Colors.grey),
                  const SizedBox(width: 8),
                  Text(
                    widget.loc.t('FILTRAR POR PACKAGE:'),
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: SizedBox(
                      height: 36,
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          return Autocomplete<String>(
                            optionsBuilder:
                                (TextEditingValue textEditingValue) {
                                  if (textEditingValue.text.isEmpty) {
                                    return _packages;
                                  }
                                  return _packages.where((String option) {
                                    return option.toLowerCase().contains(
                                      textEditingValue.text.toLowerCase(),
                                    );
                                  });
                                },
                            onSelected: (String selection) {
                              setState(() => _selectedPackage = selection);
                              if (_isLogcatRunning) {
                                _stopLogcat();
                                _startLogcat();
                              }
                            },
                            fieldViewBuilder:
                                (
                                  context,
                                  controller,
                                  focusNode,
                                  onFieldSubmitted,
                                ) {
                                  return TextField(
                                    controller: controller,
                                    focusNode: focusNode,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: isD
                                          ? Colors.white
                                          : Colors.black87,
                                    ),
                                    onTap: () {
                                      if (_packages.isEmpty) _loadPackages();
                                    },
                                    onChanged: (String val) {
                                      _selectedPackage = val.isEmpty
                                          ? null
                                          : val;
                                    },
                                    onSubmitted: (String val) {
                                      onFieldSubmitted(); // Default behavior
                                      setState(() {
                                        _selectedPackage = val.isEmpty
                                            ? null
                                            : val;
                                      });
                                      if (_isLogcatRunning) {
                                        _stopLogcat();
                                        _startLogcat();
                                      }
                                    },
                                    decoration: InputDecoration(
                                      hintText: widget.loc.t(
                                        'TODOS (Escribe para buscar)',
                                      ),
                                      hintStyle: const TextStyle(fontSize: 11),
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                            horizontal: 12,
                                          ),
                                      suffixIcon: IconButton(
                                        icon: const Icon(Icons.clear, size: 14),
                                        onPressed: () {
                                          controller.clear();
                                          setState(
                                            () => _selectedPackage = null,
                                          );
                                          if (_isLogcatRunning) {
                                            _stopLogcat();
                                            _startLogcat();
                                          }
                                        },
                                      ),
                                    ),
                                  );
                                },
                            optionsViewBuilder: (context, onSelected, options) {
                              return Align(
                                alignment: Alignment.topLeft,
                                child: Material(
                                  elevation: 4,
                                  borderRadius: BorderRadius.circular(8),
                                  color: isD
                                      ? const Color(0xFF1E1E1E)
                                      : Colors.white,
                                  child: Container(
                                    width: constraints.maxWidth,
                                    constraints: const BoxConstraints(
                                      maxHeight: 200,
                                    ),
                                    child: ListView.builder(
                                      padding: EdgeInsets.zero,
                                      shrinkWrap: true,
                                      itemCount: options.length,
                                      itemBuilder: (context, index) {
                                        final String option = options.elementAt(
                                          index,
                                        );
                                        return ListTile(
                                          title: Text(
                                            option,
                                            style: const TextStyle(
                                              fontSize: 11,
                                            ),
                                          ),
                                          onTap: () => onSelected(option),
                                          dense: true,
                                        );
                                      },
                                    ),
                                  ),
                                ),
                              );
                            },
                          );
                        },
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  _toolBtn(
                    Icons.analytics_outlined,
                    widget.loc.t("Estadísticas"),
                    _showStatsDialog,
                    isD,
                    color: Colors.blueAccent,
                    filled: true,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // NUEVA BARRA DE BÚSQUEDA (CTRL + F STYLE)
              Row(
                children: [
                  const Icon(
                    Icons.find_in_page,
                    size: 16,
                    color: Colors.cyanAccent,
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 350, // Limitar ancho para mejor UI
                    child: SizedBox(
                      height: 38,
                      child: TextField(
                        controller: _searchController,
                        onChanged: (v) {
                          // Pequeño delay opcional o limpiar rápido si está vacío
                          if (v.isEmpty) {
                            _runSearch('');
                          } else {
                            _runSearch(v);
                          }
                        },
                        style: TextStyle(
                          fontSize: 12,
                          color: isD ? Colors.white : Colors.black87,
                        ),
                        decoration: InputDecoration(
                          hintText: widget.loc.t('Buscar (mín. 3 letras)...'),
                          hintStyle: const TextStyle(fontSize: 11),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                          ),
                          filled: true,
                          fillColor: isD
                              ? Colors.white.withValues(alpha: 0.05)
                              : Colors.grey[100],
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide.none,
                          ),
                          suffixIcon: SizedBox(
                            width:
                                120, // Ancho fijo para el sufijo para evitar saltos
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                if (_searchMatches.isNotEmpty)
                                  Text(
                                    '${_currentSearchIndex + 1}/${_searchMatches.length}',
                                    style: const TextStyle(
                                      fontSize: 10,
                                      color: Colors.cyanAccent,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                IconButton(
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(),
                                  icon: const Icon(
                                    Icons.keyboard_arrow_up,
                                    size: 20,
                                  ),
                                  onPressed: _prevMatch,
                                ),
                                IconButton(
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(),
                                  icon: const Icon(
                                    Icons.keyboard_arrow_down,
                                    size: 20,
                                  ),
                                  onPressed: _nextMatch,
                                ),
                                IconButton(
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(),
                                  icon: const Icon(Icons.close, size: 16),
                                  onPressed: () {
                                    _searchController.clear();
                                    _runSearch('');
                                  },
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  const Text(
                    'NIVEL:',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Theme(
                    data: Theme.of(context).copyWith(
                      focusColor: Colors.transparent,
                      hoverColor: Colors.transparent,
                    ),
                    child: SizedBox(
                      width: 100,
                      height: 38,
                      child: DropdownButtonFormField<String>(
                        initialValue: _selectedLevel,
                        focusColor: Colors.transparent,
                        decoration: InputDecoration(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 10,
                          ),
                          filled: true,
                          fillColor: isD
                              ? Colors.white.withValues(alpha: 0.05)
                              : Colors.grey[100],
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide.none,
                          ),
                        ),
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: isD ? Colors.white : Colors.black87,
                        ),
                        dropdownColor: isD
                            ? const Color(0xFF1E1E1E)
                            : Colors.white,
                        items: const [
                          DropdownMenuItem(value: "V", child: Text('VERBOSE')),
                          DropdownMenuItem(value: "D", child: Text('DEBUG')),
                          DropdownMenuItem(value: "I", child: Text('INFO')),
                          DropdownMenuItem(value: "W", child: Text('WARN')),
                          DropdownMenuItem(value: "E", child: Text('ERROR')),
                        ],
                        onChanged: (val) =>
                            setState(() => _selectedLevel = val!),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    height: 38,
                    child: ElevatedButton.icon(
                      onPressed: _isLogcatRunning ? _stopLogcat : _startLogcat,
                      icon: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 300),
                        child: Icon(
                          _isLogcatRunning
                              ? Icons.stop_rounded
                              : Icons.play_arrow_rounded,
                          key: ValueKey(_isLogcatRunning),
                          size: 20,
                        ),
                      ),
                      label: Text(
                        _isLogcatRunning
                            ? widget.loc.t('DETENER')
                            : widget.loc.t('INICIAR STREAM'),
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 12,
                          letterSpacing: 0.5,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _isLogcatRunning
                            ? Colors.redAccent.withValues(alpha: 0.9)
                            : Colors.greenAccent.shade700,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        elevation: _isLogcatRunning ? 4 : 2,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  _outlineBtn(
                    Icons.delete_outline,
                    widget.loc.clearScreen,
                    _clearLogs,
                    isD,
                  ),
                  const Spacer(),
                      Row(
                        children: [
                          Checkbox(
                            value: _autoScroll,
                            onChanged: (v) => setState(() => _autoScroll = v!),
                            activeColor: color,
                            visualDensity: VisualDensity.compact,
                          ),
                          Text(widget.loc.autoScroll, style: const TextStyle(fontSize: 10)),
                        ],
                      ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    onPressed: _saveLogs,
                    icon: const Icon(Icons.save, size: 14),
                    label: Text(
                      widget.loc.saveLog,
                      style: const TextStyle(fontSize: 11),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blueAccent,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ],
              ),
              if (_packages.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8.0),
                  child: Row(
                    children: [
                      Icon(
                        Icons.check_circle_outline,
                        size: 12,
                        color: Colors.greenAccent,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        "${_packages.length} packages cargados - Escribe para filtrar",
                        style: TextStyle(
                          fontSize: 10,
                          color: Colors.greenAccent.withValues(alpha: 0.8),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),

        const SizedBox(height: 12),

        Expanded(
          child: Container(
            width: double.infinity,
            decoration: BoxDecoration(
              color: const Color(0xFF0D0D0D),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.white10),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SelectionArea(
                child: RepaintBoundary(
                    child: ListView.builder(
                      controller: _scrollController,
                      itemCount: _logs.length,
                      itemExtent: 16.0, // Altura fija para scroll perfecto
                      padding: const EdgeInsets.all(8),
                      itemBuilder: (context, index) {
                        final bool isCurrent = _currentSearchIndex != -1 &&
                                               _searchMatches.isNotEmpty &&
                                               _currentSearchIndex < _searchMatches.length &&
                                               _searchMatches[_currentSearchIndex] == index;

                        return Container(
                          height: 16.0,
                          alignment: Alignment.centerLeft,
                          color: isCurrent
                              ? Colors.blue.withValues(alpha: 0.4)
                              : _getLogBgColor(_logs[index]),
                          child: _buildHighlightedText(
                            _logs[index],
                            _searchController.text,
                            _getLogColor(_logs[index]),
                            isCurrent,
                          ),
                        );
                      },
                    ),
                ),
              ),
            ),
          ),
        ),

        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: isD ? Colors.black38 : Colors.grey[200],
            borderRadius: const BorderRadius.vertical(
              bottom: Radius.circular(8),
            ),
          ),
          child: Row(
            children: [
              _statText(Icons.list, 'Líneas: ${_logs.length}', isD),
              const SizedBox(width: 16),
              _statText(
                Icons.bug_report,
                'DEBUG: $_debugCount',
                isD,
                color: Colors.blueAccent,
              ),
              const SizedBox(width: 16),
              _statText(
                Icons.warning_amber,
                'WARN: $_warnCount',
                isD,
                color: Colors.orangeAccent,
              ),
              const SizedBox(width: 16),
              _statText(
                Icons.error_outline,
                'ERROR: $_errorCount',
                isD,
                color: Colors.redAccent,
              ),
              const Spacer(),
              const Icon(Icons.circle, size: 8, color: Colors.redAccent),
              const SizedBox(width: 6),
              Text(
                _isLogcatRunning
                    ? widget.loc.t('Monitoreo: ACTIVO')
                    : widget.loc.t('Monitoreo: INACTIVO'),
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: isD ? Colors.white54 : Colors.grey[700],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildHighlightedText(
    String text,
    String term,
    Color baseColor,
    bool isCurrentMatch,
  ) {
    final style = TextStyle(
      color: baseColor,
      fontFamily: 'Consolas',
      fontSize: 11,
      height: 1.1, // Ajustado para itemExtent 16
      letterSpacing: 0.2,
    );

    if (term.isEmpty || !text.toLowerCase().contains(term.toLowerCase())) {
      return Text(
        text,
        style: style,
        maxLines: 1,
        overflow: TextOverflow.clip,
      );
    }

    List<TextSpan> spans = [];
    int start = 0;
    int indexOfMatch;
    String lowText = text.toLowerCase();
    String lowTerm = term.toLowerCase();

    while ((indexOfMatch = lowText.indexOf(lowTerm, start)) != -1) {
      if (indexOfMatch > start) {
        spans.add(TextSpan(text: text.substring(start, indexOfMatch)));
      }

      spans.add(
        TextSpan(
          text: text.substring(indexOfMatch, indexOfMatch + term.length),
          style: TextStyle(
            backgroundColor: isCurrentMatch ? Colors.orange : Colors.yellow,
            color: Colors.black,
            fontWeight: FontWeight.bold,
          ),
        ),
      );

      start = indexOfMatch + term.length;
    }

    if (start < text.length) {
      spans.add(TextSpan(text: text.substring(start)));
    }

    return RichText(
      text: TextSpan(
        style: TextStyle(
          color: baseColor,
          fontFamily: 'Consolas',
          fontSize: 11,
          height: 1.3,
          letterSpacing: 0.2,
        ),
        children: spans,
      ),
    );
  }

  Widget _toolBtn(
    IconData icon,
    String label,
    VoidCallback? onTap,
    bool isD, {
    Color? color,
    bool filled = false,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: filled
              ? (color ?? Colors.blueAccent)
              : (isD ? Colors.white.withValues(alpha: 0.05) : Colors.grey[100]),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: filled
                ? Colors.transparent
                : (isD ? Colors.white10 : Colors.grey.shade300),
          ),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 14,
              color: filled
                  ? Colors.white
                  : (color ?? (isD ? Colors.white70 : Colors.black54)),
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                color: filled
                    ? Colors.white
                    : (isD ? Colors.white70 : Colors.black87),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _outlineBtn(
    IconData icon,
    String label,
    VoidCallback onTap,
    bool isD,
  ) {
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 14),
      label: Text(label, style: const TextStyle(fontSize: 11)),
      style: OutlinedButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        padding: const EdgeInsets.symmetric(horizontal: 12),
      ),
    );
  }

  Widget _statText(IconData icon, String text, bool isD, {Color? color}) {
    return Row(
      children: [
        Icon(icon, size: 12, color: color ?? Colors.grey),
        const SizedBox(width: 4),
        Text(
          text,
          style: const TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w500,
            color: Colors.grey,
          ),
        ),
      ],
    );
  }
}

class _StatsDialog extends StatefulWidget {
  final String packageName;
  final SDKService sdk;
  final AppLocale loc;
  final bool isDark;

  const _StatsDialog({
    required this.packageName,
    required this.sdk,
    required this.loc,
    required this.isDark,
  });

  @override
  State<_StatsDialog> createState() => _StatsDialogState();
}

class _StatsDialogState extends State<_StatsDialog> {
  late String _memInfo;
  late String _cpuInfo;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _memInfo = widget.loc.loading;
    _cpuInfo = widget.loc.loading;
    _fetchStats();
    _timer = Timer.periodic(const Duration(seconds: 3), (_) => _fetchStats());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _fetchStats() async {
    try {
      // Memory
      final memRes = await Process.run(widget.sdk.adbPath, [
        'shell',
        'dumpsys',
        'meminfo',
        widget.packageName,
      ]).timeout(const Duration(seconds: 4));
      String mem = widget.loc.unavailable;
      if (memRes.exitCode == 0) {
        final out = memRes.stdout.toString();
        final match =
            RegExp(r"TOTAL\s+PSS:\s+(\d+)").firstMatch(out) ??
            RegExp(r"TOTAL\s+(\d+)").firstMatch(out);
        if (match != null) {
          double mb = int.parse(match.group(1)!) / 1024;
          mem = "${mb.toStringAsFixed(1)} MB";
        }
      }

      // CPU
      // Using 'top' to find the package's CPU usage
      final cpuRes = await Process.run(widget.sdk.adbPath, [
        'shell',
        'top',
        '-n',
        '1',
        '-b',
      ]).timeout(const Duration(seconds: 4));
      String cpu = "0%";
      if (cpuRes.exitCode == 0) {
        final out = cpuRes.stdout.toString();
        final lines = out.split('\n');
        for (var line in lines) {
          if (line.contains(widget.packageName)) {
            // Typical top line on Android:
            // 11624  1000   0  5622M 166M  81M S 0.0   0.8   0:01.23 com.example.app
            // We search for a percentage (usually column 8 or 9)
            final parts = line.trim().split(RegExp(r'\s+'));
            if (parts.length >= 9) {
              for (var p in parts) {
                if (p.contains('.') && p.length <= 4) {
                  // Heuristic for %
                  cpu = "$p%";
                  break;
                }
              }
            }
          }
        }
      }

      if (mounted) {
        setState(() {
          _memInfo = mem;
          _cpuInfo = cpu;
        });
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: widget.isDark ? const Color(0xFF1A1A1A) : Colors.white,
      title: Row(
        children: [
          const Icon(Icons.analytics, color: Colors.blueAccent),
          const SizedBox(width: 8),
          const Text('Estadísticas en Vivo'),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.packageName,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: Colors.blueAccent,
            ),
          ),
          const Divider(height: 24),
          _statRow(
            'Memoria RAM (PSS)',
            _memInfo,
            Icons.memory,
            Colors.orangeAccent,
          ),
          const SizedBox(height: 16),
          _statRow(
            'Uso de CPU',
            _cpuInfo,
            Icons.shutter_speed,
            Colors.greenAccent,
          ),
          const SizedBox(height: 16),
          _statRow(
            'Consumo de Datos',
            'N/A',
            Icons.network_check,
            Colors.blueAccent,
          ),
          const SizedBox(height: 20),
          const Text(
            '* Los valores se actualizan cada 3 segundos',
            style: TextStyle(fontSize: 10, color: Colors.grey),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('CERRAR'),
        ),
      ],
    );
  }

  Widget _statRow(String label, String value, IconData icon, Color color) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, size: 18, color: color),
        ),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(fontSize: 11, color: Colors.grey),
            ),
            Text(
              value,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
            ),
          ],
        ),
      ],
    );
  }
}
