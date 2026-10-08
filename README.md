# Finance Billy 3.1 — sin planes

Aplicación administrativa para miembros, préstamos, cuotas, comprobantes, puntos y días activos. Interfaz en español, color principal vino `#6F1D36`, Poppins local y navegación adaptable a móvil.

No tiene planes, aportaciones, retornos ni pasarela de pagos. Las operaciones monetarias suceden fuera de la web. El administrador verifica evidencia y registra resultados.

## Estado de esta entrega

- Base de datos desplegada en el esquema privado `finance_billy` de Supabase.
- Función `finance-api` desplegada y autenticación del administrador comprobada.
- Cinco ciclos de pruebas de lógica y base de datos, con corrección de defectos; datos ficticios revertidos en cada batería.
- Publicación en GitHub Pages en preparación. Los permisos de las cuatro tablas antiguas se cerraron, conservando sus datos.
- Verificación visual móvil/escritorio y registro completo por la interfaz PENDIENTES hasta disponer de una URL de revisión.
- Avisos automáticos por correo NO configurados: falta remitente y autorización de un servicio de correo. El panel muestra comprobantes pendientes y la operativa no depende del correo.

## Arquitectura

Interfaz estática → Edge Function → Supabase Auth, PostgreSQL y Storage privado.

Solo la clave publicable aparece en `config.js`. La clave `service_role` proviene del entorno privado de Supabase y nunca se entrega al navegador. La función de servidor verifica el usuario, sesión vigente, estado de aprobación, rol y pertenencia de cada recurso. Las tablas están en un esquema privado, con RLS y sin permisos para `anon` o `authenticated`. Los RPC públicos solo permiten ejecución de `service_role`.

El acceso usa cédula + contraseña. Supabase Auth utiliza internamente una dirección derivada con SHA-256 para identificar la cuenta; esta dirección no es el correo de contacto ni un medio de recuperación. Las contraseñas las gestiona Auth mediante bcrypt. La contraseña del administrador no se incluye en este repositorio.

## Desarrollo

```sh
npm run check
npm test
npm run serve
```

Abrir `http://localhost:8080`. No necesita compilación ni dependencias de Node. En GitHub Pages utilizar rama `main`, carpeta raíz y `.nojekyll`.

## Backend

`supabase/schema.sql` documenta la instalación inicial del esquema en una base nueva. No ejecutar de nuevo sobre el esquema instalado. Antes de modificaciones realizar migración incremental y copia de seguridad. `supabase/functions/finance-api/index.ts` es la función desplegada; requiere los secretos de entorno proporcionados por Supabase `SUPABASE_URL` y `SUPABASE_SERVICE_ROLE_KEY`.

La función tiene `verify_jwt=false` porque registro y acceso son públicos. Todas las rutas privadas autentican la sesión explícitamente, verifican su existencia en `auth.sessions` y validan autorización en la base. No hay endpoint de instalación ni de creación pública de administradores.

## Reglas

- Aprobación inicial: 100 puntos y 0 días. Activación verificada de $1: 100 días acumulativos. Compra verificada de $3: 20 puntos, cada 168 horas.
- Días restantes: techo de las horas restantes dividido entre 24; nunca negativos. Inactividad conciliada por días de calendario de Ecuador, al completarse un día sin cobertura de activación. Las penalizaciones no generan deuda oculta de puntos.
- Préstamos: mínimo $40, múltiplos de $5, máximo `5 × floor(puntos / 5)`, 5–20 semanas, interés flat semanal 1.15 %. Una solicitud en espera o un préstamo activo por miembro.
- Solicitudes domingo a viernes. FIFO estricto; los snapshots de las condiciones no cambian.
- Primer sábado al menos siete días después del desembolso; siguientes cada siete días. Redondeo a centavos y ajuste de última cuota.
- Comprobantes JPG/PNG hasta 5 MB; archivos privados y enlaces temporales de 60 segundos. Pagos parciales, importes exactos y FIFO de cuotas. Sobrepagos se rechazan.
- Puntos por cumplimiento: sábado +2, domingo +1, lunes 0; desde martes −1 por día, por obligación. La fecha efectiva procede del último complemento verificado, no de la fecha de aprobación.
- Liquidación total: principal restante, interés exigible y una semana adicional de martes a viernes cuando no existe cuota exigible impaga. No se cobran intereses futuros ni se permite liquidación parcial con descuento.
- Mantenimiento permite lectura; bloquea cambios de miembros. Configuración futura, noticias manuales y auditoría administrativa.

## Uso del administrador

1. En Miembros, aprobar/rechazar nuevos registros y consultar sus cuentas.
2. En Comprobantes, comparar la imagen con el movimiento externo y registrar el importe realmente verificado.
3. En Solicitudes, resolver en orden FIFO y confirmar desembolso solo tras transferir externamente.
4. En Préstamos, consultar cuotas y corregir excepcionalmente fecha efectiva con motivo.
5. En Noticias, escribir contenido manual; borradores no visibles a miembros.
6. En Configuración, cambiar parámetros para futuras operaciones, activar mantenimiento y exportar registros.
7. En Auditoría, revisar acciones. La clave temporal revoca sesiones anteriores y obliga al miembro a cambiarla.

## Respaldo y recuperación

La exportación JSON del panel es una copia administrativa de registros, no un respaldo completo de Auth, archivos o de todos los hechos internos. Mantener también respaldo PostgreSQL de `finance_billy` y `auth`, y copia independiente del bucket `finance-billy`. Usar las herramientas de backup del plan contratado o exportación con Supabase CLI / pg_dump. No asumir que el plan gratuito incluye recuperación automática. Restaurar primero en un entorno aislado y comprobar usuarios, puntos, préstamos, cuotas y archivos antes de reemplazar producción. La restauración completa de un backup externo NO se ha probado en esta entrega; las pruebas sí verifican reversión transaccional.

## Límites

Concilia períodos omitidos antes de consultar o modificar datos; no requiere que una tarea nocturna haya corrido. Las consultas de estado devuelven el historial del miembro, o el conjunto de registros al administrador; para un volumen elevado habrá que incorporar paginación y probar capacidad. No se ha realizado una prueba de carga de cientos de usuarios. Los datos del proyecto anterior se mantienen; sus tablas ya no permiten acceso a los roles anon ni authenticated.
