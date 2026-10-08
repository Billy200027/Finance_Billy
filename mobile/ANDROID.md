# Finance Billy — APK de prueba

La APK abre la web publicada dentro de Android WebView, sin barra de direcciones. Requiere Android 8 o posterior, Android System WebView actualizado y conexión a internet. Usa la misma cuenta y la misma base de datos de la web. No incorpora contraseñas ni claves privadas.

## Instalar en el teléfono

1. Descarga `Finance-Billy-prueba.apk` en tu Android.
2. Abre el archivo desde Descargas.
3. Si Android lo solicita, permite a esa aplicación instalar este archivo y vuelve a la instalación. No necesitas desactivar Play Protect.
4. Instala y abre **Finance Billy**.
5. Inicia sesión con tu cuenta habitual. Al cerrar y reabrir el proceso puede pedirte entrar de nuevo.
6. Comprueba el registro, el teclado, Noticias, selección/copia de cuentas, subida de un JPG/PNG de hasta 5 MB y revisión desde tu cuenta administradora.

La firma de esta primera APK es de depuración: úsala para pruebas. No es una versión de producción ni una publicación en Google Play. Cada compilación en un runner nuevo puede usar otra firma; Android podría exigir desinstalar la prueba anterior. Desinstalar no borra tus registros de Supabase. Para distribuir futuras versiones actualizables se debe generar y conservar una clave de firma privada propia; nunca subirla al repositorio.

## Qué incluye

- Icono propio con las letras `fb.` y el color vino #6F1D36.
- Ventana sin dirección del navegador; barras del sistema y teclado adaptados.
- Selector de documentos de Android para imágenes de comprobantes. No pide acceso general a fotos, cámara ni contactos.
- JPG/PNG con firma de archivo validada y tamaño máximo 5 MB, además de las validaciones del servidor.
- Exportación JSON mediante el selector **Guardar archivo** de Android. No requiere acceso general al almacenamiento.
- Navegación externa fuera de la aplicación, HTTPS obligatorio y copias de seguridad Android desactivadas.
- Botones/menús sin selección accidental; noticias, tablas e información bancaria copiables. Esto es presentación, no protección contra capturas o extracción de datos.

Las mejoras de la web se reflejan al abrir la APK o pulsar Actualizar. Un cambio del código nativo necesita otra compilación. Incluye notificaciones push opcionales con Firebase Cloud Messaging. No ofrece funcionamiento financiero sin conexión ni captura directa desde la cámara.

## Activar notificaciones

1. Instala esta nueva APK, inicia sesión y pulsa **Notificaciones** junto a **Actualizar**.
2. Pulsa **Activar** y acepta el permiso de Android.
3. Noticias publicadas: aviso a miembros aprobados; solicitudes y comprobantes: solo administrador; préstamo aprobado: solo solicitante.
4. Al cerrar sesión se desconecta el dispositivo. Al cambiar de cuenta hay que activar nuevamente.

Necesita Google Play Services y conexión. Los avisos pueden demorarse aproximadamente un minuto más el tiempo de entrega de Android. Forzar la detención de la app puede impedir avisos hasta abrirla de nuevo. La recepción en un teléfono real aún debe probarse.

## Compilar sin Visual Studio Code

En GitHub abre el repositorio **Finance_Billy** → **Actions** → **Compilar APK de prueba** → **Run workflow**. Al terminar, descarga el artefacto **Finance-Billy-Android-prueba**, que incluye APK, proyecto Android y huella de firma. La compilación se ejecuta en GitHub; tu laptop solo necesita navegador. El workflow no modifica Supabase.

## Abrir el código en Windows (opcional)

1. Descarga y descomprime `Finance-Billy-Android-codigo.zip`.
2. Instala Android Studio desde https://developer.android.com/studio y completa su asistente estándar. No necesitas una extensión de VS Code.
3. En Android Studio elige **Open** y abre la carpeta `android-project` extraída.
4. Permite sincronizar Gradle y descargar el SDK 35 y Build Tools 35.0.0 cuando lo solicite.
5. En **Build** busca **Generate App Bundles or APKs** y selecciona una APK para pruebas. Los nombres exactos pueden variar con la versión de Android Studio.
6. Para una versión de distribución utiliza la opción de APK firmada y conserva tu archivo `.jks` y sus contraseñas en privado. La creación/entrada de esa clave te corresponde a ti.

GitHub utiliza Gradle 8.13, Android Gradle Plugin 8.13.2 y Java 17. `mobile/build_android.py` genera el proyecto a partir de código fuente auditable; el proyecto generado no contiene datos de los miembros. Se incluye también la licencia de Poppins para el monograma del icono.

## Verificación pendiente

Una compilación satisfactoria no sustituye una prueba en un teléfono. Antes de compartirla ampliamente, comprobar subida/cancelación de archivos, teclados, regreso a la app, sesiones, exportación JSON y aprobación de comprobantes. Las reglas financieras siguen en el backend previamente probado.
