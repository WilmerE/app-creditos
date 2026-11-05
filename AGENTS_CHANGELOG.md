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
