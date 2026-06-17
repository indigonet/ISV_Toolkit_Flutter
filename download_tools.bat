@echo off
setlocal

echo --- PREPARANDO HERRAMIENTAS PARA ISV TOOLKIT ---
echo.

set "RESOURCES_DIR=%~dp0resources"
set "BIN_DIR=%RESOURCES_DIR%\bin"
set "PLATFORM_TOOLS_DIR=%BIN_DIR%\platform-tools"
set "JDK_DIR=%BIN_DIR%\jdk"

if not exist "%BIN_DIR%" mkdir "%BIN_DIR%"

:: --- 1. ANDROID PLATFORM TOOLS ---
echo [1/2] Verificando Android Platform Tools...
if exist "%PLATFORM_TOOLS_DIR%\adb.exe" goto :adb_exists
if exist "%BIN_DIR%\adb.exe" goto :adb_exists_direct

echo [!] Platform Tools no encontradas. Descargando...
set "PT_URL=https://dl.google.com/android/repository/platform-tools-latest-windows.zip"
powershell -Command "Invoke-WebRequest -Uri '%PT_URL%' -OutFile '%TEMP%\pt.zip'"
echo Extrayendo Platform Tools...
powershell -Command "Expand-Archive -Path '%TEMP%\pt.zip' -DestinationPath '%BIN_DIR%' -Force"
del "%TEMP%\pt.zip"
goto :adb_done

:adb_exists
echo [INFO] Platform Tools ya presentes en: %PLATFORM_TOOLS_DIR%
echo Saltando descarga.
goto :adb_done

:adb_exists_direct
echo [INFO] ADB ya presente en: %BIN_DIR%
echo Saltando descarga.
goto :adb_done

:adb_done
echo.

:: --- 2. JDK 11 ---
echo [2/2] Verificando JDK 11...
if exist "%JDK_DIR%\bin\java.exe" goto :jdk_exists

echo [!] JDK 11 no encontrado. Descargando Microsoft OpenJDK 11 Portable...
set "JDK_URL=https://aka.ms/download-jdk/microsoft-jdk-11.0.22-windows-x64.zip"
powershell -Command "Invoke-WebRequest -Uri '%JDK_URL%' -OutFile '%TEMP%\jdk.zip'"
echo Extrayendo JDK...
if exist "%JDK_DIR%" rd /s /q "%JDK_DIR%"
powershell -Command "Expand-Archive -Path '%TEMP%\jdk.zip' -DestinationPath '%BIN_DIR%\jdk_tmp' -Force"
for /d %%i in ("%BIN_DIR%\jdk_tmp\jdk-*") do move "%%i" "%JDK_DIR%"
rd /s /q "%BIN_DIR%\jdk_tmp"
del "%TEMP%\jdk.zip"
goto :jdk_done

:jdk_exists
echo [INFO] JDK 11 ya presente en: %JDK_DIR%
echo Saltando descarga.
goto :jdk_done

:jdk_done
echo.
echo --- PROCESO COMPLETADO ---
echo Ubicacion de herramientas: %BIN_DIR%
echo.
pause
