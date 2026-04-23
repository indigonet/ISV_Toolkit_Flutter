import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

class SDKService {
  // Paths
  late String adbPath;
  late String aaptPath;
  late String apksignerPath;
  late String keytoolPath;
  late String jarsignerPath;
  late String flutterPath;

  // Connection tracking
  final ValueNotifier<String> adbStatusNotifier = ValueNotifier("Disconnected");
  String? currentSerial;
  final ValueNotifier<int> refreshTick = ValueNotifier(0);

  SDKService() {
    _initDefaultPaths();
    _detectBundledTools();
  }

  void _initDefaultPaths() {
    adbPath =
        r'C:\Users\Matias iOne\AppData\Local\Android\Sdk\platform-tools\adb.exe';
    aaptPath =
        r'C:\Users\Matias iOne\AppData\Local\Android\Sdk\build-tools\35.0.0\aapt.exe';
    apksignerPath =
        r'C:\Users\Matias iOne\AppData\Local\Android\Sdk\build-tools\35.0.0\apksigner.bat';
    keytoolPath = r'C:\Program Files\Java\jdk-17\bin\keytool.exe';
    jarsignerPath = r'C:\Program Files\Java\jdk-17\bin\jarsigner.exe';
    flutterPath =
        r'C:\Users\Matias iOne\Documents\flutter\flutter\bin\flutter.bat';
  }

  void _detectBundledTools() {
    try {
      final String exePath = Platform.resolvedExecutable;
      final String appDir = File(exePath).parent.path;
      final String bundledBin = p.join(appDir, 'bin');

      if (Directory(bundledBin).existsSync()) {
        final adb = p.join(bundledBin, 'adb.exe');
        if (File(adb).existsSync()) adbPath = adb;

        final aapt = p.join(bundledBin, 'aapt.exe');
        if (File(aapt).existsSync()) aaptPath = aapt;

        // For apksigner, we might bundle the jar or the bat
        final apksignerBat = p.join(bundledBin, 'apksigner.bat');
        if (File(apksignerBat).existsSync()) {
          apksignerPath = apksignerBat;
        } else {
          final apksignerJar = p.join(bundledBin, 'apksigner.jar');
          if (File(apksignerJar).existsSync()) apksignerPath = apksignerJar;
        }

        final kt = p.join(bundledBin, 'keytool.exe');
        if (File(kt).existsSync()) keytoolPath = kt;

        final js = p.join(bundledBin, 'jarsigner.exe');
        if (File(js).existsSync()) jarsignerPath = js;
      }
    } catch (e) {
      debugPrint('Error detecting bundled tools: $e');
    }
  }

  Process? _activeProcess;
  bool isSearchingTools = false;

  // Stream for logging if needed
  final _logController = StreamController<String>.broadcast();
  Stream<String> get logs => _logController.stream;

  void log(String line) {
    debugPrint(line);
    _logController.add(line);
  }

  Future<int> runCommand(
    String exec,
    List<String> args, {
    String? workDir,
    bool stream = true,
  }) async {
    log('🚀 Executing: ${p.basename(exec)} ${args.join(' ')}');
    try {
      bool useShell =
          exec.toLowerCase().endsWith('.bat') ||
          exec.toLowerCase().endsWith('.cmd');
      final proc = await Process.start(
        exec,
        args,
        workingDirectory: workDir,
        runInShell: useShell,
      );
      _activeProcess = proc;
      const decoder = Utf8Decoder(allowMalformed: true);
      proc.stdout.transform(decoder).transform(const LineSplitter()).listen((
        line,
      ) {
        if (stream) log(line);
      });
      proc.stderr.transform(decoder).transform(const LineSplitter()).listen((
        line,
      ) {
        if (stream) log('ERR: $line');
      });
      final code = await proc.exitCode;
      log('🏁 Finished with code $code');
      if (_activeProcess == proc) _activeProcess = null;
      return code;
    } catch (e) {
      log('CRITICAL ERROR: $e');
      return -1;
    }
  }

  void stopProcess() {
    _activeProcess?.kill();
    _activeProcess = null;
  }

  void autoDetectSDK(String root) {
    adbPath = p.join(root, 'platform-tools', 'adb.exe');
    final btDir = Directory(p.join(root, 'build-tools'));
    if (btDir.existsSync()) {
      final versions = btDir.listSync().whereType<Directory>().toList();
      if (versions.isNotEmpty) {
        versions.sort(
          (a, b) => p.basename(b.path).compareTo(p.basename(a.path)),
        );
        String latest = versions.first.path;
        aaptPath = p.join(latest, 'aapt.exe');
        apksignerPath = p.join(latest, 'apksigner.bat');
      }
    }
    log('SDK Auto-detected in $root');
  }

  Future<void> autoSearchAllTools() async {
    isSearchingTools = true;
    log('🔍 Deep Searching for tools...');

    try {
      final whereAdb = await Process.run('where', [
        'adb',
      ]).timeout(const Duration(seconds: 2));
      if (whereAdb.exitCode == 0) {
        adbPath = whereAdb.stdout.toString().split('\r\n').first.trim();
        Directory platformTools = File(adbPath).parent;
        if (platformTools.path.endsWith('platform-tools')) {
          autoDetectSDK(platformTools.parent.path);
        }
      }
    } catch (_) {}

    List<String> suspectedRoots = [
      p.join(Platform.environment['LOCALAPPDATA'] ?? '', 'Android', 'Sdk'),
      r'C:\Android\Sdk',
      Platform.environment['ANDROID_HOME'] ?? '',
      Platform.environment['ANDROID_SDK_ROOT'] ?? '',
    ];

    for (var root in suspectedRoots) {
      if (root.isNotEmpty && Directory(root).existsSync()) {
        autoDetectSDK(root);
        break;
      }
    }

    try {
      final whereJava = await Process.run('where', [
        'java',
      ]).timeout(const Duration(seconds: 2));
      if (whereJava.exitCode == 0) {
        String javaExe = whereJava.stdout.toString().split('\r\n').first.trim();
        String javaBin = File(javaExe).parent.path;

        // Only accept it if jarsigner exists here
        if (File(p.join(javaBin, 'jarsigner.exe')).existsSync()) {
          keytoolPath = p.join(javaBin, 'keytool.exe');
          jarsignerPath = p.join(javaBin, 'jarsigner.exe');
        }
      }
    } catch (_) {}

    // 2. Try JAVA_HOME
    String? javaHome = Platform.environment['JAVA_HOME'];
    if (javaHome != null && javaHome.isNotEmpty) {
      String bin = p.join(javaHome, 'bin');
      if (File(p.join(bin, 'jarsigner.exe')).existsSync()) {
        keytoolPath = p.join(bin, 'keytool.exe');
        jarsignerPath = p.join(bin, 'jarsigner.exe');
      }
    }

    // 3. Try common Program Files paths if still not found or using default
    if (!File(jarsignerPath).existsSync()) {
      final javaRoot = Directory(r'C:\Program Files\Java');
      if (javaRoot.existsSync()) {
        final List<FileSystemEntity> entities = await javaRoot.list().toList();
        final dirs = entities.whereType<Directory>().toList();
        // Look for JDK folders
        dirs.sort(
          (a, b) => b.path.compareTo(a.path),
        ); // Simple sort to get latest
        for (var dir in dirs) {
          String bin = p.join(dir.path, 'bin');
          if (File(p.join(bin, 'jarsigner.exe')).existsSync()) {
            keytoolPath = p.join(bin, 'keytool.exe');
            jarsignerPath = p.join(bin, 'jarsigner.exe');
            break;
          }
        }
      }
    }

    isSearchingTools = false;
    log('Search complete. ADB: ${p.basename(adbPath)}');
  }

  Future<String> getAdbDevices(
    String connectedLoc,
    String disconnectedLoc,
    String errorLoc,
  ) async {
    try {
      final res = await Process.run(adbPath, [
        'devices',
      ]).timeout(const Duration(seconds: 3));
      final output = res.stdout.toString();
      final lines = output.split('\n');
      String newStatus = disconnectedLoc;

      for (var line in lines) {
        if (line.contains('\tdevice')) {
          final serial = line.split('\t')[0].trim();
          currentSerial = serial;
          newStatus = "$connectedLoc: $serial";
          break;
        }
      }

      if (newStatus == disconnectedLoc) {
        currentSerial = null;
      }

      adbStatusNotifier.value = newStatus;
      refreshTick.value++; // Force notification even if status string is same
      return newStatus;
    } catch (e) {
      adbStatusNotifier.value = errorLoc;
      refreshTick.value++;
      return errorLoc;
    }
  }

  Future<List<String>> getPackages() async {
    try {
      final res = await Process.run(adbPath, [
        'shell',
        'pm',
        'list',
        'packages',
      ]);
      if (res.exitCode == 0) {
        return res.stdout
            .toString()
            .split('\n')
            .where((s) => s.startsWith('package:'))
            .map((s) => s.replaceFirst('package:', '').trim())
            .toList();
      }
    } catch (_) {}
    return [];
  }

  Future<Process?> startLogcat({
    String? packageName,
    String level = "V",
  }) async {
    List<String> args = ['logcat', '-v', 'threadtime', '*:$level'];

    // El filtrado por PID nativo fue removido porque tiene dos fallas fatales:
    // 1. Falla si la app no ha sido abierta aún.
    // 2. Mata el logcat si la app se reinicia.
    // A partir de ahora, el filtrado se hace EN VIVO desde Dart (cliente) mediante polling de PID.
    debugPrint(
      "DEBUG LOGCAT: Requesting RAW unfiltered logcat. Filtering will be handled locally by AdbPage Dart polling.",
    );

    try {
      final proc = await Process.start(adbPath, args, runInShell: true);
      _activeProcess = proc;
      return proc;
    } catch (e) {
      log('Logcat Error: $e');
      return null;
    }
  }

  Future<int> reboot() async {
    List<String> args = [];
    if (currentSerial != null) {
      args.addAll(['-s', currentSerial!]);
    }
    args.add('reboot');
    return await runCommand(adbPath, args);
  }

  Future<String?> getKeystoreAlias(String jksPath, String password) async {
    try {
      final res = await Process.run(keytoolPath, [
        '-list',
        '-keystore',
        jksPath,
        '-storepass',
        password,
      ]);
      if (res.exitCode == 0) {
        final lines = res.stdout.toString().split('\n');
        for (var line in lines) {
          if (line.contains('PrivateKeyEntry') ||
              line.contains('entrada de clave privada')) {
            return line.split(',').first.trim();
          }
        }
      }
    } catch (_) {}
    return null;
  }
}
