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

---
