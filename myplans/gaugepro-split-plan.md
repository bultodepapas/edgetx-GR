# Gauge Pro — Plan de división en dos widgets: dial (reloj) y barra

**Versión del documento:** 0.1 (borrador validado contra el árbol local, rama `feat/gauge-v2`)
**Estado:** Plan de senior dev; no se escribe código todavía
**Fecha:** 10 de agosto de 2026

---

# 1. Objetivo

Dividir el widget `WIDGETS/GaugePro/` en **dos widgets registrados e independientes**:

| Widget nuevo | Familia | Qué dibuja | Sustituye a |
|---|---|---|---|
| `GaugeDial` | `dial` | Instrumentos rotativos (Needle y Arc) | `Style = Needle` / `Style = Arc` / `Style = Auto` (zonas no-barra) |
| `GaugeBar` | `bar` | Instrumentos lineales (barras) | `Style = Bar` / `Style = Auto` (zonas muy anchas) |

Cada widget debe tener:
- **Su propio nombre y carpeta** en la SD (`/WIDGETS/<Nombre>/main.lua`), listado por separado en "Add widget".
- **Su propio conjunto de opciones** (el de dial no muestra opciones de barra ni viceversa).
- **Una sola fuente de verdad de código** — sin duplicar módulos (el repo ya eliminó un builder duplicado por exactamente esta razón; ver §2.4 y AUDIT.md P2-3).
- **Comportamiento actual intacto** dentro de cada familia: mismo dibujo, mismo modelo de datos, mismo rendimiento, mismas garantías.

---

# 2. Análisis del código actual

## 2.1 Anatomía del widget (hechos verificados leyendo el código)

Un solo widget, 17 módulos runtime + `main.lua` + `app.lua`:

| Módulo | Tamaño | Responsabilidad | Familia |
|---|---|---|---|
| `main.lua` | 15 KB | Registro, 44 opciones (`DEFS`), builder inline, guard de compatibilidad, memoiza `app.lua` | — |
| `app.lua` | 16 KB | Ciclo de vida: `create/update/refresh`, `configure`, `apply`, `painter()` | — |
| `theme.lua` | 27 KB | Tipografía, colores, `px()` (LCD_SCALE), opacidades, medidas | compartido |
| `geometry.lua` | 6 KB | `normalize`, `valueToAngle`, `linePoints(Into)`, `makeAxis`, `axisSpan` | compartido |
| `format.lua` | 3 KB | `display`, `widestSample`, `hms` | compartido |
| `options.lua` | 5 KB | `parse` del wire format (1-based, slots posicionales) | compartido |
| `ranges.lua` | 5 KB | `build`, `saneThresholds`, `determineState`, `deadband` | compartido |
| `presets.lua` | 10 KB | Presets de sensores, batería, celdas | compartido |
| `smoothing.lua` | 2 KB | `tau`, `step` (amortiguación independiente de framerate) | compartido |
| `telemetry.lua` | 18 KB | Resolución de fuente, historial min/max, staleness | compartido |
| `alerts.lua` | 4 KB | Alertas por transición de estado | compartido |
| `layout.lua` | 65 KB | `classify`, `pickStyle`, **`dialLayout`** (líneas 314-892), **`barLayout` + `applyBarVisual`** (896-1272), `signature`, y los helpers compartidos de colocación de texto (`placeValue`, `pickValueFont`, `stackTextRows`, `chipOverhang`, `chordAt`/`clipToChord`) | **ambas** |
| `renderer.lua` | 47 KB | **Renderizador de dial** (`buildTrack`, `buildTicks`, `buildNeedle`, `build`, `applyColors`, `updateArc`, `updateHistory`) **+ helpers LVGL compartidos usados por la barra**: `setProp`, `flush`, `label`, `updateChip`, `anchorUnit`, `updateSourceLabels`, `updatePulse`, `resolveColor`, `valueColor`, `applyStateInk`, `stateText`, `stateKey`, constantes `COLOR_*` | **ambas** |
| `bar_style.lua` | 20 KB | Resolución de apariencia de barra (presets → override → compacto), paletas | barra |
| `bar_faces.lua` | 64 KB | Registro de caras de barra (continuous, blocks, hex, ticks, steps, dual-rail); `select`, `estimateObjects`, techo 40 objetos | barra |
| `bar.lua` | 20 KB | Driver del renderizador de barra (`build`/`update`, marks, chip, pulse) | barra |
| `motion.lua` | 16 KB | Lenguaje de movimiento Phase 6 (off/essential/refined/expressive) | **solo barra** (verificado: `Motion.` solo aparece en `bar.lua:255,347`) |

## 2.2 El despacho actual dial ↔ bar

La elección de familia vive en `layout.pickStyle` (`layout.lua:163-167`):

```lua
if cfg.style == M.STYLE_BAR then return "bar" end
if cfg.style == M.STYLE_AUTO and (w / h) > 2.6 then return "bar" end
return "dial"
```

- La opción `Style` (posición 7 del contrato, `main.lua:87-88`) tiene opciones `{ Auto, Needle, Arc, Bar }`.
- `app.lua:92-96` (`painter`) elige renderizador por `widget.layout.style`; `configure()` resuelve `barVisual` solo si `L.style == "bar"` (`app.lua:228-233`); `refresh()` solo refresca paleta de barra si el estilo es barra (`app.lua:371-373`).
- `layout.calculate` (`layout.lua:1276-1287`) despacha a `dialLayout` o `barLayout`.

Consecuencia clave: **todo el código condicional por familia ya existe y está bien aislado**. El split no requiere reescribir renderizadores; requiere (a) fijar la familia por widget y (b) recortar opciones.

## 2.3 El contrato de opciones (restricción dura)

Documentado en `options.lua:1-34` y verificado contra el firmware:

1. **Los slots son POSICIONALES y solo se pueden APPEND** (`options.lua:21-24`). Insertar/reordenar reinterpreta datos de modelos guardados.
2. **CHOICE son enteros 1-based**, nunca strings (`options.lua:16-19`).
3. **Capacidad**: 2.11 → 10 slots; 2.12+ → 50 (`options.lua:39-52`). "Los primeros diez deben importar".
4. **44 opciones** hoy (`smoke_test.lua:164`, golden list). `Style` está en la posición 7.

Implicación: los dos widgets nuevos son **widgets nuevos, sin modelos heredados**, por lo que sus posiciones de slot las decidimos nosotros desde cero. La restricción de "frozen slots" NO los ata al orden actual de GaugePro — solo nos obliga a que los primeros diez de cada widget importen en 2.11.

## 2.4 Principios de diseño del proyecto que el plan debe respetar

- **Una sola fuente de verdad, sin duplicación.** Tanda 6 F-14/6.1 borró el builder duplicado de `options.lua` y dejó UN builder inline en `main.lua` porque "los dos solo pueden divergir" (ver `options.lua:54-59` y `main.lua:211-217`). Duplicar ~10 módulos compartidos en dos carpetas sería exactamente el defecto que el proyecto eliminó.
- **Coste de boot:** `main.lua` se ejecuta en el arranque para **todo widget de la tarjeta, usado o no** (`main.lua:7-9`). Todo lo que se mueva a un segundo archivo leído en boot cuesta una lectura más.
- **Memorización por path:** `app.lua` memoiza los módulos por path (`MODS_BY_PATH`, `app.lua:39-40`) y `main.lua` memoiza `app.lua` por radio (`main.lua:254-268`). Cuatro instancias = 16 chunks en vez de 64 (AUDIT.md P2-3).
- **Una instancia comparte la tabla de módulos:** los módulos son puros; todo el estado por-widget vive en la tabla `widget`. Dos tipos de widget distintos pueden cargar el mismo path con DEFS distintos sin colisión, porque cada ejecución del chunk `app.lua` captura su propio `DEFS` y su propio `MODS_BY_PATH`.

## 2.5 Los dos conjuntos de opciones hoy (`main.lua:73-209`)

Posiciones actuales (monolito):
- **1-10 (core 211):** Source, Min, Max, Warn, Crit, HighGood, **Style**, ColorMode, Precision, ShowMinMax
- **11-24 (212):** Accent, Label, Suffix, Scale, Sweep, Damping, Cells, Battery, Alerts, AlertSw, Delay, Vibrate, ResetSw, ShowChip
- **25-39 (212, barra Phase 1):** BarPreset, BarFace, BarDir, BarOrigin, BarSize, BarEnds, Segments, SegGap, Palette, WarnClr, CritClr, TrackClr, Surface, PanelClr, Contrast
- **40-44 (212, barra Phase 5):** Motion, BarHead, ScaleMarks, ValuePos, LabelPos

Única opción **solo-dial**: `Sweep`. Única opción **inherente al monolito**: `Style` (se elimina en ambos).

---

# 3. Estado objetivo

## 3.1 Arquitectura recomendada: "motor compartido + dos frentes delgados"

```
Repo (fuente única)
WIDGETS/
├── GaugePro/            ← MONOLITO SIN TOCAR (referencia, suite de tests, motor)
│   ├── main.lua  app.lua  + los 15 módulos
│   ├── tests/  dev/  docs/  ...
├── GaugeDial/           ← NUEVO (solo main.lua, ~150 líneas)
│   └── main.lua          name="GaugeDial", DEFS dial (23), family="dial"
└── GaugeBar/            ← NUEVO (solo main.lua, ~180 líneas)
    └── main.lua          name="GaugeBar", DEFS bar (42), family="bar"

SD (salida de sync-sd.ps1)
/WIDGETS/GaugeDial/main.lua      → loadScript /SCRIPTS/TOOLS/GaugeCore/app.lua
/WIDGETS/GaugeBar/main.lua       → loadScript /SCRIPTS/TOOLS/GaugeCore/app.lua
/SCRIPTS/TOOLS/GaugeCore/*.lua   → los 17 archivos runtime (sin main.lua; no se registra)
```

- En la SD el radio ve **exactamente dos widgets**: `GaugeDial` y `GaugeBar`. `/SCRIPTS/TOOLS/GaugeCore/` no es escaneado como widget (el escaneo de `/WIDGETS` carga solo carpetas con `main.lua`; `SCRIPTS/TOOLS` es el hogar canónico de librerías Lua).
- Cada `main.lua` de frente pasa su `DEFS` (con la clave extra `family`) a `app.lua` del core. El chunk de `app.lua` captura ese `DEFS`; cada widget tiene su propio `MODS_BY_PATH`. Sin colisión (ver §2.4).
- **Cero duplicación de lógica**: un solo juego de módulos, un solo builder, un solo renderizador por familia.

### 3.1.1 Alternativas consideradas (decisión D1)

| Opción | Descripción | Pro | Contra | Veredicto |
|---|---|---|---|---|
| **A. Dos carpetas autocontenidas** | Cada widget lleva copia de los módulos compartidos | Instalación de una sola carpeta; sin dependencia runtime | Duplicación → deriva (contra F-14/6.1); ~2× espacio SD; requiere paso de sync para no divergir | No |
| **B. Motor + frentes (recomendada)** | Core en `/SCRIPTS/TOOLS/GaugeCore/`, dos frentes en `/WIDGETS/` | Una sola fuente; sin deriva; instalación de "suite" | Instalar un widget requiere la carpeta core (installación de 3 carpetas) | **Sí** |
| **C. Monolito como tercer widget** | Los frentes cargan de `/WIDGETS/GaugePro/` | Migración trivial; cero movimiento de archivos | El radio muestra 3 widgets; el core vive en una carpeta que parece widget | Solo transitorio |

## 3.2 Nombres y registro

| | `GaugeDial` | `GaugeBar` |
|---|---|---|
| `name` (≤ 10, `smoke_test.lua:135`) | `"GaugeDial"` (9) ✓ | `"GaugeBar"` (8) ✓ |
| `translate(name)` | `"Gauge Dial"` | `"Gauge Bar"` |
| Carpeta SD | `/WIDGETS/GaugeDial/` | `/WIDGETS/GaugeBar/` |
| `family` | `"dial"` | `"bar"` |
| Opciones | 23 (core 10 en 2.11) | 42 (core 10 en 2.11) |
| `pickStyle` | siempre `dial` | siempre `bar` |

---

# 4. Opciones por widget

## 4.1 Conjunto compartido (ambos, posiciones 1-9 idénticas para permitir un prefijo común en código y un test de identidad)

| # | Key | Tipo | Default | Opciones |
|---|---|---|---|---|
| 1 | `Source` | SOURCE | RSSI | — |
| 2 | `Min` | VALUE | 0 | -10000..10000 |
| 3 | `Max` | VALUE | 100 | -10000..10000 |
| 4 | `Warn` | VALUE | 55 | -10000..10000 |
| 5 | `Crit` | VALUE | 35 | -10000..10000 |
| 6 | `HighGood` | BOOL | 1 | — |
| 7 | `ColorMode` | CHOICE | 3 | Static, Threshold, Rail, Gradient, Sections |
| 8 | `Precision` | CHOICE | 1 | Auto, 0, 1, 2 |
| 9 | `ShowMinMax` | CHOICE | 2 | Off, Markers, Markers + text |

## 4.2 GaugeDial (23 opciones)

- **Posiciones 1-9:** el conjunto compartido de §4.1.
- **Posición 10 (since 211, core 2.11):** `Sweep` — CHOICE `{ "270 deg", "180 deg", "360 deg" }`, default 1. *(Es la única opción exclusiva de dial; se promueve a core porque en un widget de dial es la decisión de forma más importante después de las 9 compartidas.)*
- **Posiciones 11-23 (since 212):** `Accent`, `Label`, `Suffix`, `Scale`, `Damping`, `Cells`, `Battery`, `Alerts`, `AlertSw`, `Delay`, `Vibrate`, `ResetSw`, `ShowChip` (mismos tipos/defaults que el monolito, `main.lua:110-139`).

**Se eliminan:** `Style` (implícita) y las 20 opciones de barra.

## 4.3 GaugeBar (42 opciones)

- **Posiciones 1-9:** el conjunto compartido de §4.1.
- **Posición 10 (since 211):** `BarPreset` — CHOICE `{ Auto, Classic, Theme, Hex, Blocks, Ticks, RC center, Minimal, Bold data }`, default 2. *(Promovida a core: en un widget de barra, el preset es la decisión de forma más importante; sin ella, 2.11 quedaría con solo 9 opciones.)*
- **Posiciones 11-29 (since 212):** `BarFace`, `BarDir`, `BarOrigin`, `BarSize`, `BarEnds`, `Segments`, `SegGap`, `Palette`, `WarnClr`, `CritClr`, `TrackClr`, `Surface`, `PanelClr`, `Contrast`, `Motion`, `BarHead`, `ScaleMarks`, `ValuePos`, `LabelPos` (las 20 de barra menos `BarPreset`; tipos/defaults iguales que `main.lua:145-208`).
- **Posiciones 30-42 (since 212):** `Accent`, `Label`, `Suffix`, `Scale`, `Damping`, `Cells`, `Battery`, `Alerts`, `AlertSw`, `Delay`, `Vibrate`, `ResetSw`, `ShowChip`.

**Se eliminan:** `Style` (implícita) y `Sweep` (irrelevante en una barra).

## 4.4 Notas

- `Scale` ("Scale ends") **sí es compartida**: los tests de barra la usan (`smoke_test.lua:468`, `Scale = "Manual"`).
- El orden del conjunto compartido 212 puede diferir entre widgets (en dial ocupa 11-23, en barra 30-42); lo que se fija por test es el **conjunto** (key+tipo+default+choices), no la posición, para cada widget (ver §7.3).
- El `builder` de opciones se mantiene **inline en cada `main.lua`** (igual que el monolito) para preservar el coste de boot de 1 lectura por widget. La deriva entre los tres builders se impide con un test de identidad (§7.3, T2).

---

# 5. Cambios de código por módulo

## 5.1 Fase 1 — Parametrización de familia (mínima y quirúrgica)

| Archivo | Cambio |
|---|---|
| `layout.lua:163-167` | `pickStyle(cfg, w, h, family)`: `if family == "bar" then return "bar" end if family == "dial" then return "dial" end` + heurística actual como fallback (familia nula = monolito intacto). |
| `layout.lua:1276-1287` | `calculate(widget, cfg)` pasa `widget.family` a `pickStyle`. |
| `app.lua:68-89` | `M.create` lee `DEFS.family` (clave extra, ignorada por `options.parse` que itera `1..#defs`) y la estampa en `widget.family`. |
| `app.lua` | Sin más cambios en esta fase: `painter()`, los `if L.style == "bar"` de `configure()`/`refresh()` y `bar_style.refreshPalette` ya despachan correctamente porque `L.style` quedará forzado por `pickStyle`. |

**Comportamiento del monolito:** `family` es nil → heurística actual idéntica. Los 36 unit + 46 lifecycle tests deben seguir pasando **sin modificaciones**.

**Nota de comportamiento deliberada:** el widget `GaugeDial` **pierde el fallback automático a barra** en zonas `w/h > 2.6`. En su lugar dibuja siempre dial; la orientación horizontal existente (`dialLayout`, `layout.lua:356-372`) ya lo maneja (dial a la izquierda, columna de texto a la derecha). Esto es el punto del split y debe documentarse.

## 5.2 Fase 2 — Los dos frentes

### `WIDGETS/GaugeDial/main.lua` (nuevo)
Estructura idéntica al monolito `main.lua` pero:
- `local NAME = "GaugeDial"`, `local CORE_PATH = "/SCRIPTS/TOOLS/GaugeCore/"`
- `DEFS` = 23 opciones de §4.2 + `DEFS.family = "dial"`.
- `create(zone, opts, path)` carga `CORE_PATH .. "app.lua"` (el parámetro `path` solo sirve para los tests; por defecto `CORE_PATH`).
- Guard de compatibilidad `if lvgl == nil` idéntico.
- `translate` con labels de sus 23 opciones + `"Gauge Dial"`.

### `WIDGETS/GaugeBar/main.lua` (nuevo)
Igual con `NAME = "GaugeBar"`, `DEFS` de 42 opciones de §4.3 + `family = "bar"`, label `"Gauge Bar"`.

### 5.2.1 La memoización `sharedApp` y el path del core
- Cada frente memoiza su propio `sharedApp = chunk(DEFS)` (patrón `main.lua:254-268`).
- `widget.app` se asigna igual; `update/refresh` delegan igual.
- `app.lua` recibe el path del core en `create` y lo usa para `loadModules` → los módulos se cargan desde `/SCRIPTS/TOOLS/GaugeCore/`. **No se pasa el path del frente** (allí no hay módulos).

## 5.3 Fase 3 — Refactor arquitectónico (recomendado, opcional en el tiempo)

Objetivos: cortar carga muerta (el widget de barra no necesita `dialLayout` ni el driver de dial; el de dial no necesita `bar_style/bar_faces/bar/motion`), y nombres honestos.

1. **Extraer `uicore.lua`** de `renderer.lua`: los helpers compartidos que la barra ya consume (`renderer.lua` → `setProp:47`, `flush:93`, `label:305`, `updateChip:619`, `anchorUnit:736`, `updateSourceLabels:1025`, `updatePulse:955`, `resolveColor:472`, `valueColor:497`, `applyStateInk:507`, `stateText:581`, `stateKey:605`, `COLOR_*:38`). `bar.lua` pasa a depender de `uicore` en vez de `renderer`. Sin cambio de comportamiento (la asignación `M.updateSourceLabels = R.updateSourceLabels` en `bar.lua:26` simplemente apunta a `uicore`).
2. **Dividir `layout.lua`** en: `layout.lua` (común: `classify`, `placeValue`, `pickValueFont`, `stackTextRows`, `chipOverhang`, `chordAt`/`clipToChord`, `signature`), `dial_layout.lua` (`dialLayout`), `bar_layout.lua` (`barLayout`, `applyBarVisual`).
3. **`app.lua.MODULES` dependiente de familia:**
   - dial: `theme, geometry, format, options, ranges, presets, smoothing, telemetry, layout, dial_layout, uicore, renderer(dial), alerts`
   - bar: `theme, geometry, format, options, ranges, presets, smoothing, motion, telemetry, layout, bar_layout, uicore, bar_style, bar_faces, bar, alerts`
4. **Simplificar `app.lua`:** `painter()` deja de despachar (familia fija); los `if L.style == "bar"` de `configure()`/`refresh()` se vuelven incondicionales según familia.
5. **Mover los módulos al core** (`git mv WIDGETS/GaugePro/*.lua` → `WIDGETS/GaugeCore/` o directamente la ruta SD `/SCRIPTS/TOOLS/GaugeCore/` en el árbol de deploy) y actualizar los `dofile`/`loadfile` de los tests y `dev/`.

**Riesgo de la Fase 3:** churn grande sobre archivos con tests y docs. Se hace solo después de que las Fases 1-2 estén verdes y congeladas.

## 5.4 Fase 4 — Deploy y tooling

| Archivo | Cambio |
|---|---|
| `dev/sync-sd.ps1` | Tres destinos: módulos runtime → `$Dest\SCRIPTS\TOOLS\GaugeCore\`; `main.lua` de cada frente → `$Dest\WIDGETS\GaugeDial\` y `$Dest\WIDGETS\GaugeBar\`. Mantener la validación de path seguro existente. |
| `dev/gallery.lua`, `dev/collage.lua`, `dev/scenes.lua` | Parametrizar por widget/familia: las galerías "every option" deben reflejar el conjunto de opciones de cada widget (hoy producen el collage del monolito de 222 escenas). |
| `dev/zone_atlas.lua`, `dev/shots.lua` | Revisar: el atlas de zonas y las capturas son válidos para ambas familias; solo hay que dirigirlos al widget correcto por escenario. |
| `dev/boot_cost.lua` | Añadir medición del coste de boot de los dos frentes (contrato nuevo: 1 lectura por frente). |
| `README.md`, `DOCS.md` | Instrucciones de instalación de la suite (3 carpetas), tabla de migración §6, sección por widget. |

---

# 6. Migración y compatibilidad

- **Modelos existentes con `GaugePro`:** siguen funcionando mientras el monolito se siga distribuyendo. El plan recomienda **distribuir el monolito durante una fase de transición** y retirarlo del material de marketing al cerrar la Fase 4 (no del repo: sigue siendo la referencia de tests y el motor).
- **No existe migración automática de config**: las opciones guardadas en el modelo van por posición de slot del widget `GaugePro`; los widgets nuevos tienen slots nuevos. El usuario debe quitar `GaugePro`, añadir `GaugeDial`/`GaugeBar` y reconfigurar. Se documenta una **tabla de mapeo** (manual):
  - `Style = Needle|Arc|Auto` (zona no-barra) → `GaugeDial`; conserva Source/Min/Max/Warn/Crit/HighGood/ColorMode/Precision/ShowMinMax/Sweep/etc.
  - `Style = Bar` (o `Auto` en zona muy ancha) → `GaugeBar`; conserva las mismas 9 compartidas + opciones de barra.
- **Compatibilidad 2.11:** cada widget nuevo declara exactamente 10 opciones en 2.11 (su slot 10 de familia + las 9 compartidas). El resto queda `since 212`. Hay que verificar que la promoción de `Sweep`/`BarPreset` a `since 211` no choca con el firmware 2.11 (CHOICE existe; riesgo bajo — ver Riesgos R3).

---

# 7. Estrategia de tests

## 7.1 Suite existente (no se toca)
- `tests/run_tests.lua` (36 unit): no carga `layout.lua` → la firma nueva de `pickStyle` no la afecta.
- `tests/smoke_test.lua` (46 lifecycle) contra el monolito: el cambio de Fase 1 es nil-safe → debe pasar **sin modificación** (puerta de Fase 1).

## 7.2 Nuevos tests de los frentes (`tests/widgets_test.lua`)
Reutiliza `mock_env.lua`. Patrón `newWidget` actualizado para pasar el path del core en `create`.

| # | Test | Qué pina |
|---|---|---|
| W1 | `#mod.name <= 10`, sin espacios, y `translate` cubre todas las opciones + el widget | Contrato de registro de ambos frentes |
| W2 | `GaugeDial` declara 23 opciones; `GaugeBar` declara 42; cada uno exactamente 10 en `capacity=10` (2.11) | Conteo y contrato 2.11/2.12 |
| W3 | **Identidad del prefijo compartido**: posiciones 1-9 idénticas (key+type+default+choices) en ambos `mod.defs` | Antideriva del conjunto compartido |
| W4 | **Identidad del builder**: los builders de los tres widgets (monolito + 2 frentes) producen salidas estructuralmente iguales para un mismo `DEFS` de prueba | El builder inline no deriva entre copias |
| W5 | Forzado de familia: `GaugeDial` en `{400,80}` → `widget.layout.style == "dial"`; `GaugeBar` en `{200,160}` → `"bar"` | `pickStyle` por familia |
| W6 | `GaugeDial` ignora opciones de barra: `cfg.barPreset` ausente, `widget.barVisual == nil`, `configure()` no resuelve paleta | Sin contaminación cruzada |
| W7 | `GaugeBar` ignora `Sweep`: opción ausente, `L.sweep` nulo | Ídem |
| W8 | Smoke de vida: cada frente crea/actualiza/refresca sobre una fuente real (RSSI) sin errores; objeto churn = 0 | Rendimiento y estabilidad por familia |
| W9 | `GaugeBar` con solo las 10 opciones de 2.11 renderiza la Classic Rail por defecto | Comportamiento 2.11 |
| W10 | `GaugeDial` respeta `Sweep` (270/180/360 → `L.sweep`/`L.startAngle` correctos) | Opción exclusiva de dial |

## 7.3 Regresión cruzada
- El conjunto de opciones 212 de cada widget se fija con una golden list por widget (mismo estilo que `smoke_test.lua:160-168`).
- `dev/collage.lua` regenera las hojas de opciones por familia y se comparan contra las PNG/SVG versionadas.

---

# 8. Fases y puertas de verificación

| Fase | Alcance | Puerta |
|---|---|---|
| 0 | Este documento; decisión D1 (arquitectura), nombres, conjuntos de opciones, política de transición | Plan revisado (grill) |
| 1 | `pickStyle(family)` + `widget.family` en `app.lua`/`layout.lua` | 36 unit + 46 lifecycle verdes **sin tocar**; monolito idéntico |
| 2 | `WIDGETS/GaugeDial/main.lua`, `WIDGETS/GaugeBar/main.lua`, `tests/widgets_test.lua` (W1-W10) | Todos los W1-W10 verdes; instalación manual en simu: 2 widgets listados, opciones correctas |
| 3 | `uicore.lua`, split de `layout.lua`, `MODULES` por familia, `git mv` al core | Suite completa verde con el monolito ahora "referencia"; `boot_cost` por frente ≤ contrato; sin churn de objetos |
| 4 | `sync-sd.ps1`, galerías por familia, `boot_cost`, README/DOCS | Deploy simu: 3 carpetas → 2 widgets; galerías por familia regeneradas |
| 5 | Transición: retirar el monolito del material de distribución; tabla de migración publicada | Revisión final y README definitivo |

**Orden de commits sugerido (conventional, estilo del repo):** `feat(widget): family parameter for dial/bar split` → `feat(widget): add GaugeDial front` → `feat(widget): add GaugeBar front` → `test(widget): widget split contract suite` → `refactor(widget): extract uicore and split layouts` → `chore(widget): deploy both widgets via sync-sd`.

---

# 9. Riesgos y mitigaciones

| # | Riesgo | Severidad | Mitigación |
|---|---|---|---|
| R1 | Deriva entre las 3 copias del builder de opciones y/o los 3 conjuntos de DEFS | Media | Test W3 (identidad del prefijo 1-9) y W4 (identidad del builder); golden lists por widget |
| R2 | El widget `GaugeDial` pierde el fallback a barra en zonas muy anchas (comportamiento visible) | Media | Decisión deliberada y documentada; la orientación horizontal de `dialLayout` ya la cubre; verificar en simu en 480×272 y 800×480 |
| R3 | Promover `Sweep`/`BarPreset` a `since 211` en los widgets nuevos | Baja | Los widgets son nuevos (sin datos guardados); confirmar en 2.11 que CHOICE en slot 10 se declara y funciona |
| R4 | El frente carga `app.lua` y 15 módulos desde `/SCRIPTS/TOOLS/GaugeCore/`; si el usuario instala solo una carpeta, falla | Media | Instalación de suite en 3 carpetas, documentada; `sync-sd.ps1` la hace de un solo comando; mensaje de error claro en `main.lua` si falta el core |
| R5 | Coste de boot: cada frente sigue costando 1 lectura (main.lua inline builder) | Baja | Diseñado así; `dev/boot_cost.lua` mide y fija el contrato por frente |
| R6 | Churn de la Fase 3 rompe tests/docs que referencian `renderer.lua`/`layout.lua` | Media | Fase 3 solo después de Fases 1-2 congeladas; `git mv` + actualización mecánica de paths; el monolito queda como referencia |
| R7 | `GaugePro` (monolito) y los dos nuevos coexistiendo confunden ("¿cuál instalo?") | Baja | Política de transición explícita (§6); README jerarquiza los dos nuevos |

---

# 10. Preguntas abiertas

1. **¿Nombres finales?** Propuesta `GaugeDial`/`GaugeBar`. Alternativas: `GaugeClock`/`GaugeBar`, `GaugeNeedle`/`GaugeBar`, o nombres en español (`Reloj`/`Barra`) — los 10 caracteres lo permiten.
2. **¿El monolito `GaugePro` se retira de la distribución o permanece como tercer widget "todo-en-uno"?** El plan recomienda retirarlo de la distribución (no del repo) tras la transición.
3. **¿Slot 10 de cada widget?** `Sweep` (dial) y `BarPreset` (barra). Alternativa: dejar el slot 10 vacío y que 2.11 tenga solo 9 opciones.
4. **¿Fase 3 (refactor arquitectónico) en el mismo PR o en uno posterior?** El plan la separa; puede aplazarse sin bloquear el valor del split.
5. **¿La opción `Style` debe conservarse en algún widget como override por zona?** Recomendación: no — cada widget ES su familia; conservarla reintroduce la confusión que el split elimina.
