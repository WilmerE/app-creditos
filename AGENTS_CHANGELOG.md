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

---
