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
  final ValueNotifier<List<String>> connectedDevices = ValueNotifier([]);
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
        // 1. Detect ADB (Platform Tools)
        final adbDirect = p.join(bundledBin, 'adb.exe');
        final adbInFolder = p.join(bundledBin, 'platform-tools', 'adb.exe');

        if (File(adbInFolder).existsSync()) {
          adbPath = adbInFolder;
        } else if (File(adbDirect).existsSync()) {
          adbPath = adbDirect;
        }

        // 2. Detect AAPT/Apksigner (Build Tools)
        final aaptDirect = p.join(bundledBin, 'aapt.exe');
        if (File(aaptDirect).existsSync()) aaptPath = aaptDirect;

        final apksignerBat = p.join(bundledBin, 'apksigner.bat');
        if (File(apksignerBat).existsSync()) {
          apksignerPath = apksignerBat;
        } else {
          final apksignerJar = p.join(bundledBin, 'apksigner.jar');
          if (File(apksignerJar).existsSync()) apksignerPath = apksignerJar;
        }

        // 3. Detect Java (JDK)
        // Check for bundled JDK folder first
        final bundledJdkBin = p.join(bundledBin, 'jdk', 'bin');
        final kt = p.join(bundledJdkBin, 'keytool.exe');
        final js = p.join(bundledJdkBin, 'jarsigner.exe');

        if (File(kt).existsSync() && File(js).existsSync()) {
          keytoolPath = kt;
          jarsignerPath = js;
        } else {
          // Fallback to direct bin tools if present
          final ktDirect = p.join(bundledBin, 'keytool.exe');
          final jsDirect = p.join(bundledBin, 'jarsigner.exe');
          if (File(ktDirect).existsSync()) keytoolPath = ktDirect;
          if (File(jsDirect).existsSync()) jarsignerPath = jsDirect;
        }
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
      List<String> finalArgs = args;
      if (p.basename(exec).toLowerCase() == 'adb.exe' &&
          currentSerial != null) {
        // Check if -s is already present
        if (!args.contains('-s')) {
          finalArgs = ['-s', currentSerial!, ...args];
        }
      }

      bool useShell =
          exec.toLowerCase().endsWith('.bat') ||
          exec.toLowerCase().endsWith('.cmd');
      final proc = await Process.start(
        exec,
        finalArgs,
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
      p.join(
        Platform.environment['USERPROFILE'] ?? '',
        'AppData',
        'Local',
        'Android',
        'Sdk',
      ),
      r'C:\Android\Sdk',
      r'D:\Android\Sdk',
      r'C:\Program Files (x86)\Android\android-sdk',
      Platform.environment['ANDROID_HOME'] ?? '',
      Platform.environment['ANDROID_SDK_ROOT'] ?? '',
    ];

    // Check for common Android Studio install paths to find bundled SDKs
    List<String> studioPaths = [
      r'C:\Program Files\Android\Android Studio',
      r'C:\Program Files (x86)\Android\Android Studio',
    ];

    for (var studio in studioPaths) {
      if (Directory(studio).existsSync()) {
        final jbr = p.join(studio, 'jbr', 'bin');
        if (File(p.join(jbr, 'jarsigner.exe')).existsSync()) {
          keytoolPath = p.join(jbr, 'keytool.exe');
          jarsignerPath = p.join(jbr, 'jarsigner.exe');
        }
      }
    }

    for (var root in suspectedRoots) {
      if (root.isNotEmpty && Directory(root).existsSync()) {
        autoDetectSDK(root);
        // If we found adb, don't break yet, keep looking for better tools in other roots?
        // Actually, let's keep the first valid one but try to find Build Tools.
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
    if (!File(jarsignerPath).existsSync() || jarsignerPath.contains('jdk-17')) {
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
      if (!File(adbPath).existsSync()) {
        adbStatusNotifier.value = disconnectedLoc;
        connectedDevices.value = [];
        return disconnectedLoc;
      }

      final res = await Process.run(adbPath, [
        'devices',
      ]).timeout(const Duration(seconds: 3));
      final output = res.stdout.toString();
      final lines = output.split('\n');

      List<String> devices = [];
      for (var line in lines) {
        if (line.contains('\tdevice')) {
          final serial = line.split('\t')[0].trim();
          devices.add(serial);
        }
      }

      connectedDevices.value = devices;

      String newStatus = disconnectedLoc;
      if (devices.isNotEmpty) {
        // If currentSerial is not in the list, or null, pick the first one
        if (currentSerial == null || !devices.contains(currentSerial)) {
          currentSerial = devices.first;
        }
        newStatus = "$connectedLoc: $currentSerial";
      } else {
        currentSerial = null;
      }

      adbStatusNotifier.value = newStatus;
      refreshTick.value++; // Force notification even if status string is same
      return newStatus;
    } catch (e) {
      adbStatusNotifier.value = disconnectedLoc;
      connectedDevices.value = [];
      refreshTick.value++;
      return disconnectedLoc;
    }
  }

  void selectDevice(String serial) {
    if (connectedDevices.value.contains(serial)) {
      currentSerial = serial;
      // We don't have the loc here, so we just update the serial and force a refresh
      // The DashboardPage will call getAdbDevices again or we can update the status manually if we had the locs
      // For now, let's just trigger a refresh tick.
      refreshTick.value++;
    }
  }

  List<String> adbArgs(List<String> args) {
    if (currentSerial != null) {
      return ['-s', currentSerial!, ...args];
    }
    return args;
  }

  Future<ProcessResult> runAdb(
    List<String> args, {
    bool runInShell = false,
  }) async {
    return await Process.run(adbPath, adbArgs(args), runInShell: runInShell);
  }

  Future<List<String>> getPackages() async {
    try {
      final res = await runAdb(['shell', 'pm', 'list', 'packages']);
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

  /// Returns a map of package names to app labels using a fast dumpsys trick
  Future<Map<String, String>> getPackagesWithNames() async {
    Map<String, String> results = {};
    try {
      // This command extracts both the package block and the application-label in one pass
      // We also look for other potential label indicators
      final res = await runAdb([
        'shell',
        'dumpsys package | grep -E "Package \\[[^]]+\\]|application-label:|label:|Label:"',
      ], runInShell: true);

      if (res.exitCode == 0) {
        final lines = res.stdout.toString().split('\n');
        String? currentPkg;

        final pkgRegex = RegExp(r"Package \[([^\]]+)\]");
        // Matches application-label:'Name' or label=Name or Label: Name
        final labelRegex = RegExp(
          r"(?:application-label|label|Label)[:=]\s*'?([^']*)'?",
        );

        for (var line in lines) {
          final pkgMatch = pkgRegex.firstMatch(line);
          if (pkgMatch != null) {
            currentPkg = pkgMatch.group(1);
            continue;
          }

          if (currentPkg != null) {
            final labelMatch = labelRegex.firstMatch(line);
            if (labelMatch != null) {
              final label = labelMatch.group(1)!.trim();
              if (label.isNotEmpty && label != "null") {
                results[currentPkg] = label;
                currentPkg = null; // Found it, move to next package
              }
            }
          }
        }
      }
    } catch (e) {
      log("Error getting package names: $e");
    }

    // Fallback: merge with pm list packages to ensure we have all packages (even without labels)
    try {
      final all = await getPackages();
      for (var p in all) {
        if (!results.containsKey(p)) {
          results[p] = p; // Fallback to package name if label not found
        }
      }
    } catch (_) {}

    return results;
  }

  Future<Process?> startLogcat({
    String? packageName,
    String level = "V",
  }) async {
    List<String> args = adbArgs(['logcat', '-v', 'threadtime', '*:$level']);

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
