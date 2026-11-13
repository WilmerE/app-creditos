# creditos

Aplicación offline para gestión de créditos y cobros.

Al crear una tarjeta se pueden seleccionar la fecha de inicio del crédito y la
fecha del primer pago. Las cuotas siguientes se programan semanalmente a partir
de esta última. El primer pago no puede preceder al inicio. Por defecto se
utilizan el próximo lunes y el sábado de esa semana.

En **Configuración empresarial**, accesible desde el inicio, se editan los datos
locales de la empresa y se eligen los campos adicionales visibles en el
encabezado de todas las tarjetas. Los datos se conservan en la base local.
La tabla de pagos muestra una marca cuando el abono cubre la cuota semanal o
liquida el saldo restante; los abonos parciales no se marcan como saldados.
Se pueden agregar filas manuales de seguimiento sin alterar el importe ni la
duración del plan. Solo se puede eliminar la última fila manual si nunca tuvo
datos registrados y permanece vacía. La fecha bajo RESTA corresponde al
`created_at` del primer abono registrado en esa fila; corregir el importe no
crea un nuevo recibo independiente, aunque sí queda un registro local del
cambio. Para pagos anteriores a esta función se
utiliza la fecha programada como estimación, identificada como tal.

La mora diaria se configura en **Configuración empresarial** como un entero
positivo, Q20 por defecto. Se guarda un día por tarjeta y día calendario
posterior al vencimiento de la cuota original pendiente más antigua; las filas
manuales no generan vencimientos. La actualización recupera los días
transcurridos desde la última revisión, incluso si la aplicación estuvo cerrada.
La mora generada permanece pendiente aunque se cubra la cuota que la originó.
La tarifa vigente se aplica a todos los días no pagados. La tarjeta desglosa
capital y mora y permite consultar las fechas pendientes tocando el banner.
RESTA muestra únicamente capital.

El importe de cada fila es acumulado. Su incremento se aplica primero a los
días de mora pendientes, del más antiguo al más reciente, y después al capital.
No se aceptan fracciones de un día de mora ni incrementos superiores a la
deuda total. Las correcciones dentro de 24 horas revierten primero capital y
después días completos de mora, en orden inverso, con el importe aplicado al
momento del cobro; las asignaciones y cambios se guardan para auditoría local.
No hay saldo a favor. Una tarjeta con mora pendiente no permite renovación.

La migración al esquema v9 conserva los pagos y la mora existentes. No genera
mora histórica anterior a la migración: empieza a contar desde el día
siguiente. No es necesario borrar la base. El seed incluye días pendientes
para tarjetas deudoras y sigue limitado a bases de negocio vacías.
El código generado de Drift no se versiona: tras obtener el proyecto o cambiar
el esquema, ejecute `dart run build_runner build` antes de compilar.

Las filas con `created_at` quedan bloqueadas para edición a partir de las 24
horas, también cuando esa fecha es estimada. El bloqueo se comprueba en la
interfaz y en el guardado local; no protege frente a cambios directos de SQLite
o del reloj del dispositivo y no sustituye un historial de auditoría.
El saldo RESTA se recalcula en el repositorio a partir de los abonos guardados;
un ajuste derivado de una fila posterior no cambia su fecha de modificación.

## Datos de prueba locales

En modo depuración, el menú del Dashboard > **Cargar datos de prueba** pide
confirmación e inserta 80 clientes ficticios y 200 tarjetas con su historial.
Solo funciona en una base sin clientes, teléfonos, tarjetas ni pagos; no borra
ni modifica datos existentes. Se ejecuta una sola vez por base de datos. No
utilice estos datos para cobros ni contacte los teléfonos de ejemplo. La opción
no aparece en compilaciones de producción.

## Sincronización con Supabase

Drift/SQLite sigue siendo la fuente local de los registros. Para iniciar la
aplicación se requiere una cuenta autenticada de Supabase. Cree
`supabase.local.json` en la raíz con `SUPABASE_URL` y `SUPABASE_API_KEY`
(la publishable/anon key; nunca use `service_role` en la app), y ejecute:

```powershell
flutter run -d windows --dart-define-from-file=supabase.local.json
```

Para Android, use el mismo argumento con `-d <id_del_dispositivo>`. En el
primer inicio, la pantalla de acceso permite iniciar sesión, crear cuenta o
recuperar la contraseña por código. Después de autenticarse, la app abre el
Dashboard directamente. Los dispositivos sincronizan los registros de esa cuenta por `updated_at`; en
conflictos gana la versión con la marca más reciente. El proceso se intenta al
iniciar sesión, al abrir la app y cada dos minutos. Las fotos continúan en el
dispositivo; los registros de clientes conservan su ruta local de foto sin
subirla.

Antes de usar una instancia nueva, aplique
`supabase/migrations/20261110000000_local_first_sync.sql` en el SQL Editor de
Supabase. La migración crea las tablas espejo y limita lectura y escritura a
filas del usuario autenticado mediante RLS. Las cuentas y el esquema del
proyecto de Supabase deben estar habilitados para Auth por correo y contraseña.

### Sesión y trabajo offline

La sesión de Supabase se guarda en el almacén seguro del sistema operativo.
Al iniciar la actualización, la aplicación migra automáticamente una sesión
existente desde las preferencias locales. Una sesión local ya guardada permite
abrir el Dashboard sin conexión y trabajar con Drift. Si no existe sesión (por
ejemplo, en el primer inicio), se necesita conexión para iniciar sesión; sin
ella, el Dashboard permanece bloqueado. La sincronización se dispara al volver
la conectividad, al reanudar la app, al iniciar sesión, al cambiar datos y cada
dos minutos. El menú del Dashboard permite cerrar sesión y advierte si no se
puede confirmar que los cambios estén sincronizados. Los datos locales quedan
vinculados a la primera cuenta y se bloquean para otras cuentas para evitar
mezclas. El estado de conectividad es aproximado: cada petición remota se
protege ante fallos de red. La plantilla de correo de Supabase debe incluir el
código OTP para confirmar el registro y recuperar la contraseña desde la app.
Para que Supabase envíe un código y no un enlace, en **Authentication > Email
Templates > Confirm signup** cambia el asunto y reemplaza `{{ .ConfirmationURL }}`
por `{{ .Token }}` en el cuerpo. En **Authentication > Sign In / Providers >
Email**, configura **Email OTP expiration** en `3600` segundos; la app muestra
la cuenta regresiva con ese plazo. Usa también `{{ .Token }}` en **Reset
Password** para completar la recuperación dentro de la app. El botón de reenvío
respeta el intervalo de 60 segundos de Supabase.

## Dashboard de cobros

El botón **Dashboard** muestra tarjetas por estado y permite filtrar su listado
o abrir cada tarjeta. Al liquidar el saldo, la tarjeta pasa a **En renovación**;
si vuelve a tener saldo pendiente, permanece o vuelve a **Activa / Deudor** según
si tiene cuotas vencidas. Una tarjeta con deuda no puede marcarse como pagada ni
en renovación. Al emitir una nueva tarjeta, la anterior liquidada pasa a
**Pagada** y la nueva queda **Activa**. No se puede abrir una tarjeta si el
cliente tiene otra tarjeta abierta con deuda. Las tarjetas archivadas y los
clientes eliminados no se incluyen.

La caja proyectada suma el importe pactado de las cuotas programadas para hoy.
**Abonado estimado** suma el importe acumulado de las cuotas cuya última
modificación (`updated_at`) fue hoy, no las cuotas cuya fecha programada es hoy.
Es solo una aproximación: una edición puede no ser un abono; no hay historial
completo de recibos históricos que permita determinar lo realmente cobrado ese
día. El filtro de caja incluye tarjetas con cuotas
programadas hoy o con importes positivos editados hoy.
Las cuotas restantes se calculan dividiendo el saldo pendiente entre el importe
semanal y redondeando hacia arriba.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.
