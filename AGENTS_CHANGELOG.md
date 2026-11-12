# Bitácora de Agentes y Contexto de Cambios (AGENTS_CHANGELOG.md)

## [Equipo A / Agente UI] - 2026-11-04
- **Módulo modificado:** `features/cobros_tarjetas/presentation/widgets`
- **Cambios realizados:** Tarjeta digital con historial en dos tablas, celdas editables y auto-guardado por debounce/foco. Layout responsive: ancho máximo 960 px centrado, una sola tabla bajo 600 px y métricas táctiles (fuentes/alturas mayores) en Android/iOS.
- **Pendientes para el Equipo B:** Conectar `PaymentLocalDataSource` al repositorio/BLoC de cobros.
- **Contexto técnico / Breaking Changes:** El widget requiere `onAutoSave` y las cuotas se representan con `PaymentInstallment`.

## [Equipo B / Agente Data&Sync] - 2026-11-04
- **Módulo modificado:** `core/database`
- **Cambios realizados:** Tabla Drift de pagos con guardado por lote, stream reactivo y unicidad de boleta.
- **Pendientes para el Equipo A:** Consumir `PaymentLocalDataSource` desde el repositorio/BLoC.
- **Contexto técnico / Breaking Changes:** Migraciones de esquema v1→v2→v3; pagos asociados a `cardId`. Ejecutar `dart run build_runner build` tras cambios Drift y no versionar `*.g.dart`.

## [Equipo A / Agente UI] - 2026-11-04
- **Módulo modificado:** `features/clientes/presentation`
- **Cambios realizados:** `ClientBloc`, listado con búsqueda (nombre/DPI/alias), formulario crear/editar con teléfonos múltiples y `ClientPhotoPicker` (cámara solo si la plataforma la soporta; galería/archivo en desktop). Acciones: editar, crear tarjeta (callback `onCreateCard`), llamar y WhatsApp.
- **Pendientes para el Equipo B:** Contar tarjetas activas por cliente (`Client.activeCardsCount` es 0 hasta que exista la tabla de tarjetas) y conectar `ClientRemoteDataSource` al sync.
- **Contexto técnico / Breaking Changes:** Nuevos paquetes `image_picker`, `url_launcher`, `uuid`. macOS: entitlements `network.client` y `files.user-selected.read-only`.

## [Equipo B / Agente Data&Sync] - 2026-11-04
- **Módulo modificado:** `core/database`, `features/clientes/data`
- **Cambios realizados:** Tablas `clients` (UUID, soft delete) y `client_phones`; esquema v4. `ClientLocalDataSource` (stream, búsqueda, insert/update transaccional), `ClientPhotoStorage` (fotos en `<documentos>/client_photos`) y `ClientRemoteDataSource` (Supabase, sin registrar en DI ni sincronizar fotos).
- **Pendientes para el Equipo A:** Ninguno.
- **Contexto técnico / Breaking Changes:** Migración v3→v4 crea ambas tablas. `AppDatabase.forTesting` para pruebas en memoria.

## [Equipo A / Agente UI] - 2026-11-04
- **Módulo modificado:** `features/cobros_tarjetas/presentation`
- **Cambios realizados:** `CardCreationScreen` + `CardCreationCubit`: cliente (o preseleccionado), montos rápidos/personalizado, plan alterno 4x320 / 7x210 para Q1,000, vista previa FECHA/ABONO/RESTA, color de historial y guardado bloqueado por el candado. El menú «Crear tarjeta digital» de Clientes abre esta pantalla (cableado en `app.dart`).
- **Pendientes para el Equipo B:** Abrir `TarjetaDigitalWidget` con el `cardId` devuelto al crear; contar tarjetas activas en `Client.activeCardsCount`.
- **Contexto técnico / Breaking Changes:** La pantalla hace `pop(cardId)` al guardar.

## [Equipo B / Agente Data&Sync] - 2026-11-04
- **Módulo modificado:** `core/database`, `features/cobros_tarjetas/{domain,data}`
- **Cambios realizados:** Tabla `cards` (esquema v5, FK a `clients`), `PaymentPlanCalculator` (puro), `CreditCardCreation` (candado: pendiente = cuotas*monto - SUM(abonos) de tarjetas Activa/Deudor/Renovación debe ser Q0), `CreditCardRepository` y datasource local. Crear tarjeta es transaccional (tarjeta + cuotas) y marca como `paid` las tarjetas liquidadas; si hay tarjetas previas la nueva queda en `renewal` con cuotas `isRenewal`.
- **Pendientes para el Equipo A:** Ninguno.
- **Contexto técnico / Breaking Changes:** Migración v4→v5 crea `cards`. Primer cobro: sábado de la semana del siguiente lunes, luego semanal. Montos >Q2,000 requieren múltiplos de Q250 (semanas = monto/1000*4).

## [Equipo A / Agente UI] - 2026-11-04
- **Módulo modificado:** `features/cobros_tarjetas/presentation`, `features/clientes/presentation`
- **Cambios realizados:** `CardDetailCubit`/`CardDetailState` y `CardDetailScreen`: cargan tarjeta y cliente desde Drift, se suscriben al stream de cuotas y conectan `TarjetaDigitalWidget.onAutoSave` con la persistencia (sin botón de guardar; el debounce/foco sigue en el widget). Navegación: tras crear una tarjeta se abre su detalle; nuevo menú «Ver tarjetas» en Clientes (`card_navigation.dart`: `createCardFor`, `openClientCards`).
- **Pendientes para el Equipo B:** `Client.activeCardsCount` sigue en 0 (ahora ya existe la tabla `cards`).
- **Contexto técnico / Breaking Changes:** `ClientListScreen` recibe `onOpenCards`. El stream reescribe las filas con los valores de la BD; las celdas con foco no se sobrescriben.

## [Equipo B / Agente Data&Sync] - 2026-11-04
- **Módulo modificado:** `features/cobros_tarjetas/{domain,data}`
- **Cambios realizados:** `PaymentLocalDataSource.watchPayments` renombrado a `watchInstallmentsByCard`; nuevos `updateInstallment(s)` (transacción, solo columnas editables, boleta normalizada, error si la cuota no existe o la boleta se repite). `CreditCardRepository` suma `getCard`, `cardsForClient`, `watchInstallments` y `saveInstallments`.
- **Pendientes para el Equipo A:** Ninguno.
- **Contexto técnico / Breaking Changes:** `CreditCardRepositoryImpl` ahora recibe también `PaymentLocalDataSource`. Sin cambios de esquema.

---

## [Arquitecto / Emisión de créditos] - 2026-11-04
- **Módulo modificado:** `features/cobros_tarjetas` (cubit, pantalla, use cases, repositorio) y `core/database/transaction_runner.dart`.
- **Cambios realizados:** `CardCreationScreen` con selector Cliente Existente / Cliente Nuevo. Existente: buscador + filtro (Todos / Sin tarjeta activa / Con tarjeta activa) con candado Q0.00. Nuevo: formulario rápido y `CreateCardWithNewClient` crea cliente y tarjeta en una sola transacción Drift. Devuelve `cardId` al cerrar.
- **Pendientes:** Abrir `CardCreationScreen()` sin cliente desde el home (hoy `createCardFor` siempre pasa un cliente).

## [Tarjetas y configuración empresarial] - 2026-11-05
- **Módulos modificados:** `features/cobros_tarjetas`, `features/enterprise` y `core/database`.
- **Cambios realizados:** Tabla única de pagos con marca de cuota saldada; fechas de inicio y primer pago configurables; encabezado empresarial editable con campos opcionales persistidos localmente.
- **Pendientes:** Ninguno.

## [Datos de prueba / Drift] - 2026-11-05
- **Módulos modificados:** `core/database` y pantalla de inicio.
- **Cambios realizados:** `DatabaseSeed` inserta transaccionalmente 80 clientes ficticios y 200 tarjetas con cuotas; acceso manual solo en depuración, con confirmación y protección de datos existentes.
- **Pendientes:** Ninguno.
- **Contexto técnico:** Migración de esquema v5→v6; ejecutar `dart run build_runner build` tras actualizar. El saldo mostrado es el saldo total del crédito, por lo que la marca utiliza la cuota semanal o la liquidación del crédito.

## [Tarjetas / encabezado empresarial] - 2026-11-05
- **Módulo modificado:** `features/cobros_tarjetas/presentation/widgets`.
- **Cambios realizados:** Cuenta bancaria resaltada con fondo tenue, bordes redondeados y texto en negrita; separación visual entre datos empresariales y del cliente.
- **Pendientes:** Ninguno.

## [Dashboard de cobros] - 2026-11-05
- **Módulos modificados:** `features/dashboard` y pantalla de inicio.
- **Cambios realizados:** Panel reactivo Drift con filtros por estado, caja estimada, navegación a tarjeta y cambios de estado validados transaccionalmente.
- **Pendientes:** Para una caja exacta se necesita un historial de movimientos de abono con fecha e importe.
- **Contexto técnico:** Los estados existentes son manuales; la cifra abonada diaria se aproxima a partir de las últimas ediciones, no es un dato contable.

## [Estados de tarjetas y caja diaria] - 2026-11-08
- **Módulos modificados:** `features/cobros_tarjetas`, `features/dashboard` y `core/database`.
- **Cambios realizados:** El saldo cero pone tarjetas abiertas en renovación; los pagos actualizan el estado según cuotas vencidas y saldo; emitir una tarjeta liquida las renovaciones anteriores y deja la nueva activa. La bandeja del dashboard excluye saldos pendientes. La caja diaria usa `updated_at` para abonos editados hoy.
- **Pendientes:** Ninguno.
- **Contexto técnico:** El abono diario sigue siendo una aproximación porque no existe historial de movimientos de caja.

## [Filas manuales y recepción de pagos] - 2026-11-08
- **Módulos modificados:** `core/database`, `features/cobros_tarjetas` y `features/dashboard`.
- **Cambios realizados:** Filas manuales vacías ordenadas al final, eliminación transaccional solo de la última fila sin datos y fecha de primera recepción en `payments.created_at`. Las filas manuales no alteran la proyección del plan.
- **Pendientes:** Ninguno.
- **Contexto técnico:** Migración v6→v7; las fechas de abonos anteriores se estiman con la fecha programada y se identifican como estimadas. No se conserva historial de cambios de importe.

## [Mora informativa de tarjetas] - 2026-11-08
- **Módulos modificados:** `features/cobros_tarjetas` (entidad, Cubit y detalle).
- **Cambios realizados:** Cálculo de Q20 diarios desde la cuota original pendiente más antigua, banner y desglose de capital y mora; actualización automática al cambiar el día.
- **Pendientes:** Ninguno.
- **Contexto técnico:** La mora es informativa y desaparece al saldar la cuota; no modifica el capital ni se registra como pago. Las filas manuales no generan vencimientos.

## [Preparación de mora persistente y bloqueo de edición]
- **Módulos modificados:** `core/database`, `features/enterprise` y `features/cobros_tarjetas`.
- **Cambios realizados:** Esquema v8 con tabla `mora` y tarifa empresarial; bloqueo local de edición de abonos a las 24 horas desde `created_at`, incluidas fechas estimadas.
- **Pendientes:** Generación y cobro persistente de mora, prioridad de pagos, límites de abono, detalle de atrasos, seed y auditoría de correcciones. La tarifa aún no está disponible en la interfaz ni afecta el cálculo informativo anterior.
- **Contexto técnico:** No se eliminó la base existente. El bloqueo local no impide manipular directamente SQLite o el reloj del dispositivo.

## [Validaciones locales de tarjetas y saldos]
- **Cambios realizados:** El repositorio recalcula los saldos RESTA en lugar de aceptar el saldo enviado por la interfaz, rechaza importes negativos o no finitos y comprueba la deuda de capital nuevamente al crear una tarjeta dentro de la transacción.
- **Pendientes:** La comprobación de renovación todavía no incluye la mora persistente; la prioridad de cobro y el límite de deuda total siguen sin implementarse.

## [Mora persistente y prioridad de cobro]
- **Módulos modificados:** base Drift, cobros y tarjetas, configuración empresarial, dashboard y datos de prueba.
- **Cambios realizados:** Esquema v9 con control de días, asignaciones reversibles y registro de cambios; generación idempotente desde la última revisión; tarifa configurable; pago de días completos de mora antes del capital; límite de deuda; detalle de fechas; renovación bloqueada por mora; seed con atrasos.
- **Contexto técnico:** La migración no genera atrasos anteriores a ella. Los pagos anteriores se consideran capital. La tarifa vigente afecta días pendientes, mientras que las reversiones usan el importe originalmente aplicado. La caja diaria sigue siendo una estimación; el bloqueo y la auditoría locales no evitan manipulación directa de SQLite o del reloj.

## [Clientes: ubicacion, fotografia y recepcion] - 2026-11-08
- **Modulos modificados:** `core/database`, `features/clientes`, `features/cobros_tarjetas` y `windows/flutter`.
- **Cambios realizados:** Selector de Google Maps para clientes en Windows mediante WebView2; permite elegir o arrastrar un pin y guardar latitud y longitud localmente. Migracion Drift v9->v10 con coordenadas opcionales en `clients`. La foto de cliente admite recorte circular, zoom y desplazamiento. Filas manuales nacen con la fecha actual, ofrecen selector de calendario y rechazan fechas pasadas. Los abonos con mora aceptan desde un dia completo, aplican primero los dias pendientes mas antiguos y destinan el remanente al capital.
- **Contexto tecnico:** La clave se inyecta al compilar desde `google_maps.local.json` mediante `--dart-define-from-file`; el archivo se excluye de Git. El mapa requiere conexion, Maps JavaScript API habilitada y WebView2 Runtime en Windows. Coordenadas nulas conservan compatibilidad con clientes existentes; la migracion no requiere seed.

## [Ubicacion actual al elegir cliente] - 2026-11-08
- **Modulos modificados:** `features/clientes`, configuracion Android y permisos de macOS.
- **Cambios realizados:** El selector de mapa permite solicitar la ubicación actual de forma explícita, recentrar el mapa y colocar el pin; muestra progreso y mensajes cuando los servicios o permisos no están disponibles. Se declararon permisos de ubicación en primer plano para Android y permiso con uso mientras se utiliza la app en macOS.
- **Contexto tecnico:** La ubicación se obtiene con `geolocator` y requiere permiso del usuario y servicios de ubicación activos. No requiere habilitar una API adicional en Google Cloud; la clave de Maps sigue siendo necesaria para cargar el mapa. El selector de Google Maps existente continúa limitado a Windows.

## [Busqueda en listas del dashboard] - 2026-11-08
- **Modulos modificados:** `features/dashboard/presentation`.
- **Cambios realizados:** Se agregó un campo de búsqueda instantánea sobre la lista de tarjetas del dashboard; filtra por nombre de cliente o referencia/alias, ignora mayúsculas y acentos, y permite limpiar la búsqueda.
- **Contexto tecnico:** El filtrado se aplica a las tarjetas visibles del filtro actual y no altera los datos ni el estado financiero.

## [Transicion de tarjetas en renovacion] - 2026-11-08
- **Modulos modificados:** `features/dashboard`.
- **Cambios realizados:** El menú de una tarjeta en renovación solo ofrece pasarla a pagada. El repositorio también rechaza cualquier otro cambio manual de estado cuando la deuda total ya es cero.
- **Contexto tecnico:** Se mantiene la validación transaccional de saldo antes de permitir el estado pagado; la renovación sigue siendo resultado de haber liquidado el saldo.

## [Desactivacion de tarjetas deudoras] - 2026-11-08
- **Modulos modificados:** `features/cobros_tarjetas`, `features/dashboard` y creación de tarjetas.
- **Cambios realizados:** Se agregó el estado `deactivated`. Una tarjeta deudora solo permite desactivarse; una desactivada solo permite reactivarse; renovación solo permite pasar a pagada. Las desactivadas tienen una bandeja propia y quedan fuera de los totales y filas de caja del dashboard. La creación de tarjeta se bloquea si el cliente conserva una tarjeta en estado deudor o desactivada, incluso si su saldo figura en cero.
- **Contexto tecnico:** No se cambió el esquema Drift: el estado se conserva en el campo textual existente. La mora de tarjetas desactivadas sigue acumulándose y su deuda permanece visible; la desactivación solo las excluye de las métricas de caja.

## [Cobros programados para hoy] - 2026-11-08
- **Modulos modificados:** `features/dashboard`.
- **Cambios realizados:** Se agregó el acceso del dashboard a cuotas con vencimiento hoy y grupos de Pendientes/Pagados; esta sección aparece primero y abre seleccionada por defecto. Los abonos parciales permanecen en Pendientes y muestran abonado a capital y resto de la cuota; las cuotas manuales no se incluyen.
- **Contexto tecnico:** La clasificación compara el capital aplicado a la cuota (`amountPaid - moraPaid`) con el importe semanal. Se filtra por fecha calendario local programada; la mora/deuda no se cambia por estar pendiente en el mismo día del vencimiento.
- **Actualización:** En el grupo Pendientes se agregaron acciones para llamar y abrir el chat de WhatsApp usando el teléfono principal del cliente; sin teléfono registrado, las acciones quedan deshabilitadas.

## [Carpetas locales de capital] - 2026-11-08
- **Modulos modificados:** `core/database`, `features/capital_groups`, creación de tarjetas y dashboard.
- **Cambios realizados:** Drift v11 incorpora `capital_groups` y `cards.folder_id` opcional. Se agregó gestión local para crear, editar y eliminar grupos; al eliminar uno, sus tarjetas vuelven a Capital Principal. La creación permite asignar una tarjeta a una carpeta. El selector del dashboard filtra los conteos, cobros de hoy, caja y listas por la carpeta seleccionada; abre en Capital Principal.
- **Contexto tecnico:** Tarjetas anteriores y seed conservan `folder_id = NULL` y pertenecen a Capital Principal. No se consolida información entre carpetas ni se altera el cálculo de cobros, mora, bloqueo de edición o renovación.
- **Actualización:** En creación de tarjeta, el selector de capital se movió al inicio y ahora requiere selección explícita, incluyendo Capital Principal. Guardar permanece deshabilitado y muestra requisitos pendientes hasta que cliente, plan, fechas y capital estén completos.

## [Alertas operativas y seguimiento de cobros] - 2026-11-08
- **Módulos modificados:** `core/database`, `features/dashboard`, `features/cobros_tarjetas` y `features/enterprise`.
- **Cambios realizados:** Drift v12 incorpora alertas locales idempotentes y configuración de hora límite diaria (predeterminado 18:00) y minutos de aviso (60 por defecto). El dashboard genera alertas al registrar cada nuevo día persistente de mora, al pasar a Deudor, al liquidarse una tarjeta y al quedar lista para renovación; agrega una sección de seguimiento prioritario para tarjetas con 30+ días de mora. El cobro diario pendiente se señala cerca del límite y queda registrado como alerta durante la ventana configurada, incluso si la app se abre después del límite.
- **Contexto técnico:** Las alertas se vinculan a tarjeta y carpeta, se conservan localmente y usan claves únicas para no duplicarse al reabrir la app. La transición a Deudor se evalúa al abrir dashboard y al reconciliar pagos; la transición de renovación a pagada continúa realizándose al emitir la siguiente tarjeta. El horario es configurable en Configuración empresarial. No se ejecutaron pruebas automatizadas.
- **Actualización Android:** Se añadió `flutter_local_notifications` para enviar a la barra de notificaciones del sistema los eventos nuevos que la app persiste. Android 13+ solicita permiso al usuario; si se niega, las alertas internas siguen disponibles. Se conserva el canal local y la pantalla bloqueada oculta el contenido sensible. Tras instalar NDK 28.2.13676358 con Android CLI, `flutter run` compiló el APK; se instaló y abrió en el emulador API 37 y se comprobó que el permiso `POST_NOTIFICATIONS` quedó concedido. La primera instalación perdió conexión ADB porque el emulador se había cerrado; se reinició para completar la instalación. No se generó una alerta de negocio artificial para validar su contenido en la bandeja.

## [Autenticación offline-first y espejo Supabase] - 2026-11-11
- **Módulos modificados:** `core/auth`, `core/network`, `core/database`, `features/dashboard`, inicialización/DI, `pubspec.yaml`, Android y `supabase/migrations`.
- **Cambios realizados:** Supabase se configura con `SUPABASE_URL` y `SUPABASE_API_KEY` inyectadas por `--dart-define-from-file`. La sesión se guarda con `flutter_secure_storage` y las sesiones existentes en SharedPreferences se migran al primer acceso. Supabase no configurado, sin sesión o sin red no impide abrir la app ni operar Drift. El servicio sincroniza clientes, grupos de capital, tarjetas y pagos en ambas direcciones, usa `updated_at` para resolver conflictos (gana la fila más reciente), asocia los datos a la cuenta autenticada y respeta eliminaciones lógicas. Reintenta al recuperar conectividad, al reanudar la app, al iniciar sesión y cada dos minutos. El Dashboard muestra estado de sincronización; el login indica cómo continuar localmente si no hay red. Se agregaron políticas RLS para que cada cuenta acceda solo a sus filas.
- **Migración Drift:** Esquema v14 agrega metadatos/fechas de sincronización y eliminaciones lógicas. La actualización tolera columnas ya presentes en bases de desarrollo con `user_version` atrasada. Las columnas `updated_at` se agregan con default constante por la restricción de SQLite y se inicializan desde `created_at`; las nuevas tarjetas guardan su `updated_at` explícitamente.
- **Contexto técnico / Limitaciones:** La detección de conectividad es orientativa; las solicitudes remotas también manejan fallos y conservan Drift como fuente local. Las fotos permanecen en el dispositivo. Requiere aplicar `supabase/migrations/20261110000000_local_first_sync.sql` en el proyecto Supabase y configurar Auth. Se ejecutó `dart analyze` en los archivos modificados relevantes y pasó; no se ejecutaron pruebas automatizadas. La migración local requiere confirmación al ejecutar la app con una base existente.
