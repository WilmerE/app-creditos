# Bitácora de Agentes y Contexto de Cambios (AGENTS_CHANGELOG.md)

## [Equipo A / Agente UI] - 2026-11-04
- **Módulo modificado:** `features/cobros_tarjetas/presentation`
- **Cambios realizados:** Sin cambios todavía.
- **Pendientes para el Equipo B:** Acordar contratos de estados y eventos del BLoC para la tabla editable.
- **Contexto técnico / Breaking Changes:** Mantener la presentación independiente de Drift y Supabase.

## [Equipo B / Agente Data&Sync] - 2026-11-04
- **Módulo modificado:** `core/database`
- **Cambios realizados:** Esqueleto de Drift con metadatos de sincronización local.
- **Pendientes para el Equipo A:** Coordinar contratos de repositorio y comportamiento reactivo de la tabla editable.
- **Contexto técnico / Breaking Changes:** Ejecutar `dart run build_runner build` para generar los archivos de Drift e inyección; nunca versionar archivos `*.g.dart`.

---
