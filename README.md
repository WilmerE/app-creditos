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

## Datos de prueba locales

En modo depuración, el botón **Cargar datos de prueba** del inicio pide
confirmación e inserta 80 clientes ficticios y 200 tarjetas con su historial.
Solo funciona en una base sin clientes, teléfonos, tarjetas ni pagos; no borra
ni modifica datos existentes. Se ejecuta una sola vez por base de datos. No
utilice estos datos para cobros ni contacte los teléfonos de ejemplo. La opción
no aparece en compilaciones de producción.

## Dashboard de cobros

El botón **Dashboard** muestra tarjetas por estado guardado y permite filtrar
su listado o abrir cada tarjeta. Los abonos no cambian el estado automáticamente.
El cambio manual a pagada exige saldo cero y no se puede abrir una tarjeta si el
cliente tiene otra tarjeta abierta con deuda. Las tarjetas archivadas y los
clientes eliminados no se incluyen.

La caja proyectada suma el importe pactado de las cuotas programadas para hoy.
**Abonado estimado** suma el importe acumulado de las cuotas cuya última
modificación fue hoy. Es solo una aproximación: una edición puede no ser un
abono y puede actualizar cuotas posteriores; no hay historial de transacciones
que permita determinar lo realmente cobrado ese día. El filtro de caja incluye
tarjetas con cuotas programadas hoy o con importes positivos editados hoy.
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
