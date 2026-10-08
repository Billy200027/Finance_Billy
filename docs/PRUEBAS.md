# Verificación — 8 de octubre de 2026 UTC

## Cinco ciclos de pruebas

1. Lógica de importes/calendarios + batería transaccional: detectó respuesta nula en registro de idempotencia; corregida y repetida, PASS.
2. Batería completa después de añadir revocación de sesiones y aislamiento de roles: PASS. Siete pruebas de lógica: PASS.
3. Batería ampliada con noticias en borrador, contratos frente a cambios de tasa, comprobantes ajenos y dos cuotas vencidas: PASS. Lógica: PASS.
4. Batería completa tras limitar el reset a miembros de Finance Billy: PASS. Acceso real de administrador y consulta de estado: PASS. Lógica: PASS.
5. Batería completa: detectó orden no determinista de eventos con el mismo timestamp; se añadió una secuencia de inserción y se repitió toda la batería, PASS. Sintaxis y siete pruebas de lógica, PASS. No hay datos ficticios persistentes.

## Evidencia ejecutable

- `tests/domain.test.js`: 7 casos; el caso de centavos recorre 3.088 combinaciones de monto/plazo (193 montos × 16 plazos).
- `tests/integration.sql`: pruebas reales de PostgreSQL dentro de BEGIN/ROLLBACK. No se transfirió dinero ni se enviaron correos.
- Se comprobó por HTTP real: login por cédula del administrador, rol ADMIN, estado APROBADA, consulta de estado y catálogo público de bancos.

Casos de integración: registro, duplicación, aprobación, privacidad del pendiente, permisos de administrador, RLS, RPC inaccesible para cliente, activación, doble aprobación, compra de puntos, límite de 168 h, snapshot, una solicitud, FIFO, desembolso, centavos, calendario, pagos complementarios, fecha efectiva, conciliación de aprobación tardía, liquidación lunes/martes, noticias privadas, configuración no retroactiva, recibo ajeno, penalizaciones independientes, conciliación repetida, piso 0, recuperación sin deuda oculta y mantenimiento.

## Pendientes explícitos

- QA visual y flujo completo por navegador: no probado todavía.
- Registro y cambio de clave de un miembro real por HTTP: no probado; la prueba que iba a crear cuentas persistentes fue bloqueada y se sustituyó por pruebas transaccionales reversibles. No se creó esa cuenta de prueba.
- Carga/concurrencia masiva: no probada. Escrituras serializadas en transacciones con advisory lock e idempotencia.
- Restauración completa de backups externos y SMTP: no probados/configurados.
- Revisión Supabase: tablas nuevas privadas con RLS sin políticas públicas (información intencional del analizador). Permisos de anon y authenticated retirados en las cuatro tablas antiguas; el analizador ya no reporta acceso público a ellas. Protección contra contraseñas filtradas desactivada en la configuración preexistente de Auth; evaluar al configurar la cuenta/plataforma.
