@echo off
set "FLUTTER_BIN=C:\Users\Matias iOne\Documents\flutter\flutter\bin\flutter.bat"
echo --- COMPILANDO ISV TOOLKIT PRO (MODO RELEASE) ---
"%FLUTTER_BIN%" build windows --release
echo.
echo --- APLICANDO DESBLOQUEO DE SEGURIDAD ---
powershell -Command "Unblock-File -Path build\windows\x64\runner\Release\isv_toolkit.exe"
echo.

echo --- GENERANDO INSTALADOR (INNO SETUP) ---
set "ISCC=%ProgramFiles(x86)%\Inno Setup 6\ISCC.exe"
if not exist "%ISCC%" set "ISCC=%ProgramFiles%\Inno Setup 6\ISCC.exe"

if exist "%ISCC%" (
    "%ISCC%" windows\installer\isv_toolkit.iss
    echo.
    echo --- INSTALADOR GENERADO EN build\installer ---
    explorer build\installer
) else (
    echo [ADVERTENCIA] Inno Setup no encontrado. Instala Inno Setup 6 para generar el .exe unico.
    echo Descargalo en: https://jrsoftware.org/isdl.php
    echo.
    echo --- ABRIENDO CARPETA DEL COMPILADO ---
    explorer build\windows\x64\runner\Release
)
pause
