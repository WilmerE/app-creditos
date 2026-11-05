# Guía de entorno para Windows (Equipo B)

Proyecto: **creditos** (Flutter, offline-first con Drift/SQLite).
Versión de referencia: Flutter 3.47.9 (canal `stable`, Dart ^3.13.7).

## 1. Requisitos

| Herramienta | Para qué | Notas |
|---|---|---|
| Windows 10/11 64 bits | — | — |
| Git for Windows | Control de versiones | https://git-scm.com/download/win |
| Flutter SDK 3.47.x (stable) | Framework | Incluye Dart |
| Visual Studio 2022 (Community) | Compilar app de escritorio Windows | Carga de trabajo **"Desarrollo para el escritorio con C++"** (incluye CMake y Windows SDK) |
| VS Code (o Android Studio) | IDE | Extensiones: *Flutter* y *Dart* |
| Android Studio (opcional) | Compilar/emular Android | Instalar Android SDK + cmdline-tools |

> Visual Studio Code **no** sustituye a Visual Studio 2022: sin la carga de C++ no compila el target Windows.

## 2. Instalación

1. **Git**: instalar con opciones por defecto.
2. **Flutter SDK**:
   - Descargar de https://docs.flutter.dev/get-started/install/windows.
   - Extraer en una ruta **sin espacios ni permisos especiales**, p. ej. `C:\src\flutter` (no `C:\Program Files`).
   - Agregar `C:\src\flutter\bin` a la variable `Path` del usuario.
   - O con Git: `git clone https://github.com/flutter/flutter.git -b stable C:\src\flutter`.
3. **Visual Studio 2022**: instalar la carga *Desarrollo para el escritorio con C++*.
4. **Modo desarrollador** (necesario para symlinks de plugins):
   ```powershell
   start ms-settings:developers
   ```
   Activar "Modo para desarrolladores".
5. Abrir una terminal nueva y verificar:
   ```powershell
   flutter --version
   flutter doctor -v
   ```
   Debe aparecer ✓ en *Flutter*, *Windows Version* y *Visual Studio*. Si instalas Android, acepta licencias:
   ```powershell
   flutter doctor --android-licenses
   ```

## 3. Clonar y preparar el proyecto

```powershell
git clone https://github.com/WilmerE/app-creditos.git
cd app-creditos
flutter pub get
```

### Generar código (obligatorio)

Los archivos `*.g.dart` (Drift) están en `.gitignore`, por lo que **no vienen en el repositorio**. Hay que generarlos tras clonar y cada vez que cambien tablas de Drift o clases `@injectable`:

```powershell
dart run build_runner build --delete-conflicting-outputs
```

Modo continuo mientras se desarrolla:

```powershell
dart run build_runner watch --delete-conflicting-outputs
```

> `lib/injection_container.config.dart` sí está versionado; si hay conflictos de merge, resuélvelos regenerándolo con el comando anterior.

## 4. Ejecutar y probar

```powershell
flutter run -d windows        # app de escritorio
flutter run -d chrome         # opcional (web no es el target principal)
flutter analyze               # debe terminar sin issues
flutter test                  # toda la suite debe pasar
dart format lib test          # formato antes de commitear
```

La base de datos local (SQLite) se crea automáticamente en el directorio de documentos de la aplicación; `sqlite3_flutter_libs` empaqueta la librería, no hace falta instalar SQLite.

## 5. Notas por funcionalidad

- **Selector de foto de cliente** (`image_picker`): en Windows solo ofrece galería/archivo; la cámara está disponible únicamente en Android/iOS.
- **Supabase** (`supabase_flutter`): la sincronización remota no es necesaria para trabajar en local. No se versionan credenciales; si se requieren, el líder del equipo las entrega por canal seguro y **nunca** se commitean.
- **Moneda**: todos los montos se muestran con punto decimal vía `CurrencyFormatter.formatGtq` (ej. `Q1,000.00`). No formatear importes manualmente.

## 6. Flujo de trabajo en equipo

- Antes de empezar, leer `AGENTS_CHANGELOG.md` y, al terminar, añadir una entrada con módulo modificado, cambios y pendientes.
- Arquitectura: Clean Architecture por feature (`data` / `domain` / `presentation`) bajo `lib/features/`.
- Terminar los archivos de texto con LF o dejar que Git convierta (`git config --global core.autocrlf true`).

## 7. Problemas frecuentes

| Síntoma | Solución |
|---|---|
| `flutter` no se reconoce | Reabrir la terminal; revisar que `...\flutter\bin` está en `Path`. |
| `Visual Studio not installed` / falta `CMake` | Instalar la carga de trabajo C++ de escritorio y volver a ejecutar `flutter doctor`. |
| `Building with plugins requires symlink support` | Activar el Modo desarrollador (paso 2.4). |
| Errores `app_database.g.dart not found` / `_$AppDatabase` | Ejecutar `dart run build_runner build --delete-conflicting-outputs`. |
| `GetIt: Object not registered` | Regenerar la inyección con build_runner. |
| Versión de Dart/SDK incompatible con `pubspec.yaml` | `flutter upgrade` o `flutter channel stable`; comparar con `flutter --version`. |
| Error al compilar por caché corrupta | `flutter clean`, `flutter pub get` y volver a generar código. |
| Antivirus bloquea la compilación | Excluir la carpeta del SDK y del proyecto en Windows Defender. |
| Rutas largas en Git/CMake | `git config --system core.longpaths true` y clonar en una ruta corta (p. ej. `C:\dev`). |

## 8. Checklist final

- [ ] `flutter doctor -v` sin errores en Flutter, Windows y Visual Studio
- [ ] `flutter pub get` correcto
- [ ] `build_runner` ejecutado sin errores
- [ ] `flutter analyze` limpio
- [ ] `flutter test` en verde
- [ ] `flutter run -d windows` abre la app
