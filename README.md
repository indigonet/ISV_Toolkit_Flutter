# ISV Toolkit 🚀

Una potente suite de herramientas desarrollada en **Flutter** para desarrolladores e integradores de terminales POS y aplicaciones Android. Permite analizar APKs, firmarlas, simular protocolos seriales y depurar dispositivos POS mediante una interfaz moderna, premium y responsiva (soporte completo de modo oscuro/claro y multi-idioma).

---

## ✨ Características Principales

### 📦 1. Analizador de APKs (APK Analyzer)
* **Drag & Drop:** Simplemente arrastra tu archivo APK dentro de la interfaz para comenzar el análisis.
* **Especificaciones Técnicas:** Inspecciona el nombre de la versión, código de la versión, Min SDK, Target SDK, arquitectura soportada y nombre del paquete.
* **Verificación de Seguridad y Firma:** Revisa esquemas de firmas de Android (V2, Jarsigner) y hashes SHA-256.
* **Extractor de Icono:** Copia el icono de la aplicación directamente al portapapeles del sistema (formato PNG estándar) a través de un simple clic.
* **Instalación/Desinstalación Rápida:** Instala, actualiza o desinstala APKs en dispositivos conectados por ADB directamente desde la interfaz.

### 🔑 2. Suite de Firma de APKs (APK Signer Suite)
* Asistente interactivo para firmar aplicaciones de forma rápida utilizando herramientas nativas de Android (`apksigner`, `jarsigner`, `keytool`).

### 🪵 3. Visor de Logs ADB (Logcat Suite)
* **Monitoreo en Tiempo Real:** Visualiza la salida del Logcat del terminal POS conectado.
* **Badge de Conexión ADB:** Detección automática de dispositivos, selección rápida de puerto ADB y visualización de estado en tiempo real.

### 💳 4. Simulador de SDK POS
* Entorno interactivo para simular transacciones y flujos del SDK de terminales de pago.

### 🔌 5. Simulador de Protocolo Simplificado (ISO8583 Pipe-Separated)
* **Envío de Comandos:** Interfaz gráfica para parametrizar y enviar comandos (Venta, Anulación, Devolución, Cierre de Lote, Duplicado, Detalles) a través de puertos serie.
* **Conversor Hexadecimal a Texto:** Decodifica tramas hexadecimales reales recibidas (excluyendo STX/ETX/LRC de forma automática) y cópialas al portapapeles con un solo clic.
* **Conexión Serial COM:** Escaneo automático de puertos seriales activos en Windows, con opción de ingresar un puerto personalizado.
* **Consola Integrada:** Historial en vivo de eventos de transmisión (TX) y recepción (RX) con formatos legibles.

### ⚙️ 6. Ajustes y Utilidades
* **Multi-Idioma:** Soporte completo para Español, Inglés y Portugués.
* **Temas Dinámicos:** Selector entre modo oscuro (Dark Mode) y modo claro (Light Mode).
* **Control del POS:** Permite enviar comandos de reinicio a terminales de pago conectados por ADB.
* **Descarga directa:** Botón integrado para descargar actualizaciones y acceder al repositorio de GitHub de manera instantánea.

---

## 🛠️ Requisitos de Entorno

Para utilizar todas las funciones avanzadas de firmas y análisis, la suite requiere configurar las rutas de las siguientes herramientas de desarrollo (puedes auto-detectarlas o buscarlas manualmente desde el diálogo de ajustes):
* **ADB** (Android Debug Bridge)
* **AAPT** (Android Asset Packaging Tool)
* **Apksigner**
* **Keytool** (incluido en JDK)
* **Jarsigner** (incluido en JDK)

---

## 🚀 Instalación y Desarrollo

### Ejecutar en Modo Desarrollo
Para ejecutar la aplicación localmente, asegúrate de tener el entorno de Flutter configurado y ejecuta:

```bash
flutter pub get
flutter run -d windows
```

O utiliza los scripts automatizados incluidos en el proyecto:
* `run_debug.bat`: Levanta la aplicación en modo desarrollo.
* `download_tools.bat`: Descarga las herramientas del SDK necesarias.
* `build_release.bat`: Compila el empaquetado de producción de la aplicación.

---

## 📦 Tecnologías Utilizadas

* **Framework:** Flutter (Desktop Windows)
* **Lenguaje:** Dart
* **Integraciones del Sistema:** Win32 APIs, ADB y herramientas de CLI de Android.
* **Empaquetamiento:** Soporte de MSIX para la creación de instaladores nativos en Windows.
