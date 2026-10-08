# Notificaciones de Finance Billy

Estado al 8 de octubre de 2026: servidor desplegado y validado; integración
Android escrita, pendiente de google-services.json, compilación y prueba en teléfono.
La APK anterior continúa funcionando, pero no incorpora Firebase Messaging.

## Destinatarios

| Evento | Destinatario |
| --- | --- |
| Publicar una noticia | Miembros aprobados con avisos activados |
| Nueva solicitud | Administrador con avisos activados |
| Nuevo comprobante | Administrador con avisos activados |
| Aprobar una solicitud | Solicitante con avisos activados |

Editar una noticia ya publicada no repite el aviso. Publicar un borrador sí lo genera.
El estado de aprobación es APROBADA_PENDIENTE_DESEMBOLSO: el aviso no afirma que se haya transferido dinero.

## Uso en la nueva APK

1. Entrar con la cuenta aprobada.
2. Presionar **Notificaciones**, junto a Actualizar.
3. Presionar **Activar o reintentar** y permitir las notificaciones en Android.
4. Para detenerlas en ese teléfono, usar **Desactivar**.

Los avisos abren Noticias, Solicitudes, Comprobantes o Préstamos según el evento.
El inicio de sesión y las autorizaciones siguen siendo necesarios para consultar datos.
La opción se muestra solo en la APK que incorpora el puente nativo; no se promete
push para navegadores o para la APK anterior.

## Único archivo de configuración pendiente

En Firebase Console, abrir el proyecto **Finance Billy Notificaciones**.
Ir a **Configuración del proyecto → General → Tus apps → Finance Billy Android**
y descargar **google-services.json**. El paquete debe ser com.billy.finance.
Colocarlo en mobile/google-services.json. Este es el archivo del cliente Android;
el JSON privado de la cuenta de servicio permanece en Supabase y nunca se copia al repositorio.

Después ejecutar el flujo **Compilar APK de prueba** en la rama que contiene la
integración Android. Solo entregar el APK si assembleDebug y lintDebug terminan correctamente.
La firma de prueba de la versión anterior puede exigir desinstalarla antes de instalar
la nueva. Los registros de la comunidad se conservan en Supabase, pero habrá que iniciar sesión otra vez.

## Servidor y privacidad

FCM_SERVICE_ACCOUNT_JSON y FINANCE_PUSH_WORKER_KEY son secretos de Supabase.
finance_push_worker_key es la copia protegida en Vault que utiliza Cron.
Las funciones RPC de dispositivos y entregas son accesibles exclusivamente por service_role.
La API valida usuario y sesión antes de vincular un teléfono. No acepta roles ni
destinatarios elegidos por el cliente. No utiliza temas públicos para dirigir avisos.

La cola se crea en la misma transacción de la operación; una operación fallida
no genera avisos. Cron procesa hasta 50 entregas por minuto, con reintentos.
El envío no es instantáneo: normalmente se inicia en el siguiente ciclo de un minuto,
además del tiempo de entrega de Google y la conexión del teléfono.

Cerrar sesión elimina la vinculación, desactiva la recepción local y cancela
avisos visibles. Cambiar de cuenta cambia el identificador privado de vinculación;
los avisos de una cuenta anterior no se muestran. Sesiones revocadas, usuarios
bloqueados y cuentas con cambio obligatorio de contraseña se excluyen del envío.
Los mensajes usan texto genérico, sin montos, nombres, cédulas, cuentas ni imágenes.
Android muestra una versión privada en la pantalla bloqueada y descarta duplicados.

FCM requiere servicios de Google Play. Sin permiso, sin conexión o con la app
forzada a detenerse, Android puede impedir o retrasar los avisos. No son garantía
de entrega ni sustituyen consultar los registros de la aplicación.

## Verificación realizada

- Google aceptó una solicitud FCM validate_only: autorización válida, sin envío real.
- Cron invocó finance-push correctamente (HTTP 200), con cola vacía.
- Prueba SQL transaccional: noticias, ausencia de repetición por edición, solicitudes
  y comprobantes solo para administrador, aprobaciones privadas, cambio de cuenta,
  revocación, exclusión de entregas arrendadas, desactivación y permisos RPC: PASS.
- Las pruebas se revirtieron; no dejaron usuarios, préstamos ni comprobantes ficticios.
- Siete pruebas existentes de reglas y fechas: PASS. Sintaxis JavaScript: PASS.
- Pendiente: compilación Android, lint y recepción real en dispositivo.

Las tablas privadas tienen RLS sin políticas públicas de forma intencional.
pg_net no es una extensión reubicable: su aviso de instalación en public no se
resuelve con ALTER EXTENSION SET SCHEMA. No se han ampliado permisos de usuarios
anon/authenticated a las tablas financieras ni a las funciones push.
