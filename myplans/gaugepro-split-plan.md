# Gauge Pro — Plan corregido para dividir dial y barra

**Versión:** 0.5 (plan ejecutado, nombres Pro y documentación consolidados sobre `feat/gauge-v2`)
**Fecha:** 11 de agosto de 2026
**Estado:** fases 0–4 implementadas; fase 5 queda deliberadamente post-release
**Guía normativa:** [`WIDGETS/GaugePro/DEVELOPMENT_GUIDE.md`](../WIDGETS/GaugePro/DEVELOPMENT_GUIDE.md)

---

## 1. Veredicto

La división es conveniente: `GaugePro` ya contiene dos productos distintos, con geometría,
opciones y expectativas de zona diferentes. La frontera técnica también existe (`layout.style`,
`painter()`, `bar_style`, `bar_faces`, `bar`), por lo que no hay que reescribir el motor visual.

El borrador 0.1, sin embargo, no era implementable de forma segura. Esta revisión corrige seis
problemas:

1. **Pérdida de Needle/Arc.** El borrador eliminaba `Style` de `GaugeDialPro`, pero
   `dialLayout()` decide la aguja con `cfg.style`. El resultado habría sido un dial siempre en
   modo Arc. `GaugeDialPro` conserva un selector propio `DialStyle = Auto | Needle | Arc`.
2. **Ruta de core incorrecta.** EdgeTX siempre llama `create(zone, options, widgetPath)` y el
   tercer argumento será `/WIDGETS/GaugeDialPro/` o `/WIDGETS/GaugeBarPro/`. No puede reutilizarse como
   override del core. Los frentes deben ignorarlo para cargar módulos y usar un `CORE_PATH`
   explícito.
3. **Caché no compartida entre tipos.** Cada `main.lua` ejecuta su propio chunk de `app.lua`; por
   tanto cada frente obtiene su propio `MODS_BY_PATH`. Se conserva la compartición entre
   instancias del mismo tipo, pero un Dial + un Bar no comparten automáticamente módulos en RAM.
   El coste mixto debe medirse y la separación de módulos por familia es puerta obligatoria de
   release, no refactor opcional.
4. **Fases imposibles.** El borrador hacía que los frentes buscaran
   `/SCRIPTS/TOOLS/GaugeCore/` antes de que deploy creara esa carpeta. El empaquetado del core se
   mueve a la misma fase que introduce los frentes.
5. **Baseline desactualizado y rojo.** La suite actual tiene 70 unit tests y 200 lifecycle tests,
   no 36 + 46. En este HEAD: unit `70/70`; lifecycle `200 pass / 1 fail`; luacheck `1 warning / 0
   errors`. No se inicia el split hasta resolver el fallo de anatomía de Precision Rail
   (`expected 16, got 14`).
6. **Test de builder no realizable.** El builder es local y no acepta un `DEFS` arbitrario. Se
   reemplaza aquel test por contratos observables sobre `mod.options`, `mod.defs`, capacidades
   2.11/2.12 y, si se duplican bloques de bootstrap, una comprobación estática de identidad.

---

## 2. Objetivo y no objetivos

Crear dos widgets registrados e independientes:

| Widget | Familia fija | Caras |
|---|---|---|
| `GaugeDialPro` | `dial` | Auto, Needle, Arc |
| `GaugeBarPro` | `bar` | Continuous, Blocks, Hex, Ticks, Steps, Dual rail mediante presets/overrides |

Cada widget tendrá nombre, carpeta y opciones propios. Compartirán una sola fuente de runtime.
No se duplicarán renderizadores ni lógica de telemetría en el repositorio.

Por el límite EdgeTX de 10 caracteres, los nombres visibles serán `Gauge Dial Pro` y
`Gauge Bar Pro`, las factories usarán los IDs `DialPro` y `BarPro`, y las carpetas conservarán
los nombres descriptivos `GaugeDialPro` y `GaugeBarPro`.

No son objetivos de este cambio:

- rediseñar las caras actuales;
- cambiar thresholds, smoothing, alertas, historial o semántica de colores;
- migrar automáticamente datos del modelo en la radio;
- introducir una caché global Lua sin demostrar antes que hace falta;
- retirar `GaugePro` antes de que exista una ruta de transición documentada.

---

## 3. Hechos del código actual

### 3.1 Inventario baseline

Antes del split había **17 archivos Lua de producción en total**: `main.lua`, `app.lua` y 15
módulos cargados por `app.lua`. El payload nuevo contiene 19 archivos en GaugeCore y un
`main.lua` por frente; la diferencia corresponde a la extracción física de layouts/UI.

El módulo `app.lua` carga hoy siempre:

```text
theme geometry format options ranges presets smoothing motion telemetry
layout renderer bar_style bar_faces bar alerts
```

Aunque `motion`, `bar_style`, `bar_faces` y `bar` solo sirven a barras, un dial también paga su
carga. A la inversa, una barra carga todo el layout y renderer de dial.

### 3.2 Despacho existente

`layout.pickStyle(cfg, w, h)` devuelve `bar` cuando:

- `Style = Bar`; o
- `Style = Auto` y `w / h > 2.6`.

`app.painter()` elige `bar` o `renderer` mediante `widget.layout.style`. La apariencia de barra
solo se resuelve cuando el layout es `bar`. Esta frontera se conserva.

### 3.3 Invariante que obliga a conservar DialStyle

La familia y la cara de dial no son la misma decisión:

```lua
-- familia
L.style = "dial" -- frente GaugeDialPro

-- cara dentro de la familia
L.showNeedle = (cfg.style == STYLE_NEEDLE)
  or (cfg.style == STYLE_AUTO and mode ~= "micro")
```

Fijar la familia a `dial` elimina únicamente el salto automático a barra. No puede eliminar el
selector Auto/Needle/Arc.

### 3.4 Contrato de opciones

- Los slots son posicionales.
- CHOICE usa enteros 1-based.
- EdgeTX 2.11 declara 10 opciones; 2.12+ admite hasta 50.
- Los widgets nuevos no heredan slots de `GaugePro`, pero una vez publicados sus propios slots
  quedan congelados y solo se podrá append.
- Los defaults de opciones no declaradas en 2.11 siguen llegando a runtime porque
  `options.parse()` recorre el `DEFS` completo.

### 3.5 Contrato real de `create()`

El firmware llama a cada widget con tres argumentos:

```text
create(zone, storedOptions, /WIDGETS/<carpeta-del-frente>/)
```

Ese tercer argumento describe el frente, no el core. El diseño debe separar los conceptos
`widgetPath` y `corePath`.

---

## 4. Decisiones de arquitectura

### D1 — Motor compartido + dos frentes delgados

Distribución nueva:

```text
/WIDGETS/GaugeDialPro/main.lua
/WIDGETS/GaugeBarPro/main.lua
/SCRIPTS/TOOLS/GaugeCore/app.lua
/SCRIPTS/TOOLS/GaugeCore/<módulos>.lua
```

`GaugeCore` está fuera de `/WIDGETS`; el scanner del firmware solo recorre un nivel bajo
`WIDGETS_PATH` y carga las carpetas que contienen `main.lua`. Por ello el paquete nuevo registra
exactamente dos widgets.

Durante la transición puede existir además `/WIDGETS/GaugePro/`; en ese paquete la radio mostrará
tres widgets. No debe afirmarse “exactamente dos” para el paquete de transición.

### D2 — Una fuente en repo; dos layouts de deploy

Durante el PR de split, los módulos canónicos pueden permanecer en `WIDGETS/GaugePro/` para evitar
un `git mv` masivo de tests, docs y herramientas. `sync-sd.ps1` los copia al destino
`/SCRIPTS/TOOLS/GaugeCore/` mediante una lista/manifest explícita.

Esto es una sola fuente en el repositorio aunque durante la transición pueda haber dos copias en
la SD (core + legacy). Mover físicamente la fuente a `SCRIPTS/TOOLS/GaugeCore/` será un cleanup
posterior, separado del cambio funcional.

### D3 — SPEC explícito, no propiedades escondidas en DEFS

Cada frente pasa una especificación al factory de `app.lua`:

```lua
local SPEC = {
  name = "DialPro",         -- o BarPro; máximo 10 caracteres en EdgeTX
  family = "dial",          -- o bar
  coreApi = 1,
  defs = DEFS,
}

local app = appChunk(SPEC)
```

`app.lua` valida `name`, `family`, `coreApi` y `defs`. No se añade `DEFS.family` a una tabla que
conceptualmente es un array.

### D4 — La ruta de producción nunca proviene del tercer argumento

Patrón obligatorio del frente:

```lua
local CORE_PATH = "/SCRIPTS/TOOLS/GaugeCore/"

local function create(zone, opts, _widgetPath)
  -- cargar app.lua y sus módulos exclusivamente desde CORE_PATH
end
```

Para tests, el chunk de `main.lua` puede recibir una configuración solo al ejecutarse (por
ejemplo `chunk({ corePath = widgetDir })`). No se usa el tercer argumento de `create()` como
inyección. Un test específico debe pasar `/WIDGETS/GaugeDialPro/` como tercer argumento y demostrar
que todos los `loadScript` apuntan al core.

### D5 — ABI/versionado del core

Los frentes declaran `coreApi = 1`; `app.lua` expone el mismo número. Si falta el core o no
coincide la versión, el error debe nombrar el frente, la ruta y las versiones esperada/encontrada.
Esto convierte una instalación parcial o mezcla de releases en un diagnóstico, no en un fallo
opaco.

El core se carga en primer uso, no durante el registro, para que un core ausente no impida que el
widget aparezca en “Add widget”. El guard `lvgl == nil` también se conserva por frente.

### D6 — Sin caché global en la primera implementación

Cada `main.lua` memoiza un `sharedApp`; todas las instancias del mismo tipo comparten app y módulos.
Dial y Bar mantienen caches separadas. Es un coste fijo por familia usada, no por instancia.

No se escribe en `_G` para compartir módulos entre tipos. Si la prueba de memoria mixta no pasa,
se presenta una decisión arquitectónica aparte: caché global versionada y namespaced, o aceptar
un presupuesto explícito. No se oculta la duplicación bajo la afirmación de que el path la evita.

---

## 5. Opciones definitivas

### 5.1 Prefijo común, slots 1–9

| # | Key | Field | Tipo | Default |
|---:|---|---|---|---|
| 1 | Source | source | SOURCE | RSSI |
| 2 | Min | min | VALUE | 0 |
| 3 | Max | max | VALUE | 100 |
| 4 | Warn | warn | VALUE | 55 |
| 5 | Crit | crit | VALUE | 35 |
| 6 | HighGood | highGood | BOOL | 1 |
| 7 | ColorMode | colorMode | CHOICE | Rail (3) |
| 8 | Precision | precision | CHOICE | Auto (1) |
| 9 | ShowMinMax | showMinMax | CHOICE | Markers (2) |

Este prefijo es byte-equivalente en ambos frentes y queda congelado.

### 5.2 GaugeDialPro — 24 opciones

- **Slot 10 / since 211:** `DialStyle`, field `style`, CHOICE
  `{ Auto, Needle, Arc }`, default Auto.
- **Slot 11 / since 212:** `Sweep`, CHOICE `{ 270 deg, 180 deg, 360 deg }`.
- **Slots 12–24 / since 212:** `Accent`, `Label`, `Suffix`, `Scale`, `Damping`,
  `Cells`, `Battery`, `Alerts`, `AlertSw`, `Delay`, `Vibrate`, `ResetSw`, `ShowChip`.

`DialStyle` cabe en el límite de 10 caracteres y mantiene exactamente la semántica que usa
`dialLayout`. Se elimina únicamente la alternativa Bar.

### 5.3 GaugeBarPro — 42 opciones

- **Slot 10 / since 211:** `BarPreset`, default Classic (2).
- **Slots 11–23 / since 212:** `Accent`, `Label`, `Suffix`, `Scale`, `Damping`,
  `Cells`, `Battery`, `Alerts`, `AlertSw`, `Delay`, `Vibrate`, `ResetSw`, `ShowChip`.
- **Slots 24–42 / since 212:** `BarFace`, `BarDir`, `BarOrigin`, `BarSize`,
  `BarEnds`, `Segments`, `SegGap`, `Palette`, `WarnClr`, `CritClr`, `TrackClr`, `Surface`,
  `PanelClr`, `Contrast`, `Motion`, `BarHead`, `ScaleMarks`, `ValuePos`, `LabelPos`.

Este orden deja primero la configuración general y después la personalización avanzada. Como el
widget es nuevo, no hay contrato anterior que obligue a conservar el orden 0.1.

### 5.4 Reglas de UI

- `GaugeDialPro` no muestra opciones `Bar*`, `Motion`, paleta/surface ni posiciones lineales.
- `GaugeBarPro` no muestra `DialStyle` ni `Sweep`.
- Ninguno muestra el selector de familia `Style = ... Bar` del monolito.
- En 2.11 ambos declaran exactamente 10 opciones significativas.

---

## 6. Cambios técnicos

### 6.1 Parametrización mínima

1. `app.lua` recibe `SPEC`, guarda `widget.family` y usa `SPEC.name` en errores.
2. `layout.pickStyle(cfg, w, h, family)`:

   ```lua
   if family == "dial" then return "dial" end
   if family == "bar" then return "bar" end
   -- fallback legacy actual
   ```

3. `layout.calculate()` pasa `widget.family`.
4. `GaugePro` legacy pasa `family = nil`; su heurística y sus 44 slots quedan intactos.

### 6.2 Frentes

Cada frente contiene únicamente:

- guard de compatibilidad;
- `NAME`, `CORE_PATH`, `SPEC` y `DEFS`;
- builder inline de opciones y traducciones;
- memoización `sharedApp`;
- delegación de `create/update/refresh`.

El pequeño bootstrap se duplica deliberadamente para que el widget pueda registrarse sin core y
para no añadir lecturas SD al arranque. Su comportamiento se congela mediante tests observables y
una sección marcada idéntica en ambos archivos. No se presenta esa duplicación como “imposible de
derivar”. Si la sección deja de ser trivial, se genera desde una plantilla en vez de crecer en
paralelo.

### 6.3 Separación de carga por familia — obligatoria antes de release

Extraer:

- `ui_core.lua`: batching de propiedades, labels, chip, pulso, colores y source labels usados por
  ambos renderizadores;
- `layout_common.lua`: clasificación, tipografía/colocación compartida y firma estructural;
- `dial_layout.lua` y `bar_layout.lua`;
- renombrar conceptualmente `renderer.lua` a renderer de dial y `bar.lua` a renderer de barra
  (el rename físico puede hacerse en el mismo commit si no mezcla cambios funcionales).

Listas objetivo:

```text
common: theme geometry format options ranges presets smoothing telemetry alerts
        layout_common ui_core
dial:   dial_layout dial_renderer
bar:    motion bar_layout bar_style bar_faces bar_renderer
legacy: common + dial + bar
```

`loadModules(corePath, family)` carga solo `common + family`. Los `setup()` también se ejecutan
solo para módulos presentes. El frontend Dial no debe tener keys `bar`, `bar_style`, `bar_faces`
o `motion`; el frontend Bar no debe cargar `dial_renderer` ni `dial_layout`.

### 6.4 Deploy seguro

`sync-sd.ps1` debe trabajar con tres targets resueltos y validados por separado:

```text
<SD>/SCRIPTS/TOOLS/GaugeCore
<SD>/WIDGETS/GaugeDialPro
<SD>/WIDGETS/GaugeBarPro
```

Requisitos:

- manifest explícito por target;
- borrar únicamente `*.luac` obsoletos dentro de esos targets exactos;
- detectar archivos runtime antiguos que ya no estén en el manifest y reportarlos; no borrar
  carpetas amplias;
- copiar primero core, luego frentes;
- ejecutar una verificación post-copy de existencia y `coreApi`;
- modo `-IncludeLegacy` para el paquete de transición;
- nunca borrar `WIDGETS/GaugePro` automáticamente. Su retirada es una acción explícita después de
  migrar los modelos.

Paquetes documentados:

| Paquete | Contenido | Widgets visibles |
|---|---|---:|
| nuevo, SD limpia | Core + Dial + Bar | 2 |
| nuevo sobre SD con GaugePro previo | Core + Dial + Bar; legacy conservado con advertencia | 3 |
| transición | Core + Dial + Bar + GaugePro legacy | 3 |

### 6.5 Guardrails obligatorios de desarrollo

La guía [`DEVELOPMENT_GUIDE.md`](../WIDGETS/GaugePro/DEVELOPMENT_GUIDE.md) forma parte del contrato
de este plan. No es documentación informativa: sus checks son puertas de revisión.

Reglas resumidas:

1. **Shared-first.** Telemetría, escalas, thresholds, estados, color, formato, smoothing,
   historial, alertas, badges, accesibilidad y optimizaciones LVGL se implementan una vez en core.
2. **Paridad por defecto.** Si una mejora de una familia es aplicable a la otra, se lleva al core
   o se implementan ambos adaptadores en el mismo cambio. “Copiar después” no es aceptable.
3. **Separación de geometría, no de semántica.** Dial y Bar pueden dibujar distinto; deben dar la
   misma lectura, estado, unidad, historial, alertas y significado de ColorMode.
4. **Dependencias unidireccionales.** Familias → core; nunca Dial → Bar, Bar → Dial o core → una
   familia. Solo `app.lua` compone la familia elegida.
5. **Frentes delgados.** `main.lua` registra opciones y delega; no contiene lógica de producto ni
   de render.
6. **Opciones protegidas.** Prefijo común 1–9 idéntico; slots publicados append-only; CHOICE
   1-based; toda opción común se cambia en ambos frentes.
7. **Pruebas simétricas.** Una regla compartida modificada exige evidencia contra Dial y Bar.
8. **Recursos mixtos.** Un cambio de core se mide en Dial, Bar y Dial + Bar; probar una sola
   familia no basta.
9. **Excepciones explícitas.** Toda asimetría aplicable requiere evidencia, test, alcance temporal
   y aprobación del propietario.

Cada PR debe completar el checklist de la guía y declarar una de estas salidas para la otra
familia: `shared automatically`, `implemented in both`, o `not applicable` con justificación.

---

## 7. Migración

No hay migración automática segura en runtime: el modelo identifica un widget por factory y
guarda opciones posicionales. Cambiar el nombre crea otra factory.

Tabla manual:

| GaugePro actual | Destino | Ajuste |
|---|---|---|
| Style = Needle | GaugeDialPro | DialStyle = Needle |
| Style = Arc | GaugeDialPro | DialStyle = Arc |
| Style = Auto en zona no ancha | GaugeDialPro | DialStyle = Auto |
| Style = Bar | GaugeBarPro | BarPreset y overrides equivalentes |
| Style = Auto con `w/h > 2.6` | GaugeBarPro | BarPreset = Classic/Auto según decisión visual |

Flujo recomendado:

1. instalar el paquete de transición;
2. añadir el widget nuevo al lado del legacy y copiar la configuración;
3. comparar lectura, estado, alertas e historial;
4. quitar la instancia legacy del modelo;
5. solo cuando ningún modelo la use, retirar la carpeta `GaugePro` de la SD.

La configuración antigua no se pierde mientras se conserve el legacy. No renombrar directamente
la carpeta existente: eso dejaría referencias de modelos sin factory.

---

## 8. Estrategia de verificación

### 8.1 Puerta cero: baseline

Antes del primer cambio:

- resolver el fallo actual `Precision Rail visible-object anatomy: expected 16, got 14`;
- `tests/run_tests.lua`: 70/70;
- `tests/smoke_test.lua`: 201/201 después de corregir/ratificar el caso rojo actual;
- `luacheck`: 0 errores y no aumentar el warning conocido de `motion.lua`;
- guardar manifiestos visuales, census, instrucciones y allocations actuales.

No se “arregla” el test cambiando 16 por 14 sin decidir si el casing nuevo eliminó objetos
correctamente o si faltan dos objetos visibles.

### 8.2 Contratos nuevos de frentes

1. IDs internos `DialPro`/`BarPro` y keys `<= 10`; nombres visibles terminados en `Pro` y
   traducciones completas;
2. Dial 24 opciones, Bar 42; ambos exactamente 10 en 2.11;
3. slots 1–9 idénticos y golden list completa por frente;
4. defaults/choices 1-based y mismos tipos/rangos que el monolito;
5. `GaugeDialPro` forzado a dial incluso en `400x80`;
6. `GaugeBarPro` forzado a bar incluso en `200x160`;
7. `DialStyle` Auto/Needle/Arc produce la anatomía correcta;
8. Bar no tiene `cfg.sweep`; Dial no tiene `cfg.barPreset`;
9. el tercer argumento `/WIDGETS/<front>/` jamás se usa para cargar core;
10. core ausente y `coreApi` incompatible producen errores diagnósticos;
11. dos instancias del mismo frente comparten `sharedApp` y tabla de módulos;
12. create/update/refresh, resize, source change, alertas y 200 frames sin object churn.

### 8.3 Paridad visual y funcional

Comparar escenas equivalentes contra el monolito:

- Needle/Arc: 180/270/360, micro/compact/normal/large, horizontal/vertical;
- Bar: las seis caras, ambos ejes, escalas ascendentes/descendentes/cero, cinco ColorMode;
- NO SOURCE, NO DATA, STALE, NO LINK, WARN, CRIT;
- batería, Cells, timers, min/max, reconnect y reset;
- temas stock, dark y high-contrast.

Las imágenes deben ser pixel-equivalentes salvo texto del nombre del widget o una diferencia
aprobada y documentada.

### 8.4 Presupuesto de recursos

Extender `boot_cost.lua`/probes para medir, con GC controlado:

- boot de ambos `main.lua`, usados o no;
- primer `create` de Dial y de Bar;
- un Dial + un Bar;
- cuatro instancias de Dial; cuatro de Bar;
- paquete de transición con legacy.

Gates:

- una segunda instancia del mismo frente no vuelve a cargar chunks;
- Dial no carga módulos de Bar y viceversa;
- ninguna callback supera los contratos actuales: ordinary `< 2000`, transition `< 6000`,
  structural `< 10000` instrucciones;
- allocations steady-state no empeoran frente a los valores actuales (dial 13–14 B/frame; barras
  ordinarias ~32–35 B/frame en los probes existentes);
- el delta de RAM de un Dial + un Bar queda documentado y aprobado en radio objetivo. Si la
  duplicación de common no cabe, el release se bloquea hasta decidir una caché compartida.

### 8.5 Simulador/radio

- instalación nueva muestra exactamente **Gauge Dial Pro** y **Gauge Bar Pro**
  (`DialPro`/`BarPro` internamente);
- instalación de transición muestra también `GaugePro`;
- settings correctos en 2.11 y 2.12+;
- reinicio en frío, cambio de tema, resize y cuatro widgets simultáneos;
- instalación incompleta muestra un error accionable y no desaparece silenciosamente.

---

## 9. Fases y commits

| Fase | Alcance | Estado |
|---|---|---|
| 0 | Resolver baseline rojo; congelar contratos y guía normativa | completada |
| 1 | Introducir `SPEC`, `coreApi`, `family` y dispatch fijo | completada; legacy 201/201 |
| 2 | Añadir GaugeDialPro/GaugeBarPro, contratos y sync | completada; split 17/17 |
| 3 | Extraer `ui_core`, layouts/renderers y carga selectiva | completada; gates de recursos verdes |
| 4 | README/DOCS, paquetes nuevo/transición y migración | completada; post-copy verificado |
| 5 | Tras una release de transición, dejar de distribuir legacy por defecto | pendiente por diseño; requiere confirmar modelos migrados |

La Fase 2 es un checkpoint funcional, no un artefacto publicable. La Fase 3 es obligatoria antes
de release.

Orden sugerido de commits:

```text
test(gaugepro): restore green split baseline
refactor(gaugepro): add frontend spec and fixed family dispatch
feat(gaugepro): add GaugeDialPro and GaugeBarPro fronts
test(gaugepro): pin split contracts and core path
refactor(gaugepro): load family-specific layouts and renderers
chore(gaugepro): deploy versioned shared core
docs(gaugepro): publish split migration guide
```

---

## 10. Riesgos residuales

| Riesgo | Severidad | Mitigación/gate |
|---|---|---|
| Core/frente de versiones distintas | Alta | `coreApi`, error diagnóstico, post-copy verify |
| RAM duplicada entre Dial y Bar | Alta | módulos selectivos + prueba mixta; caché global solo por decisión explícita |
| Instalación parcial | Alta | carga diferida, mensaje claro, manifest y paquetes |
| Pérdida de Needle/Arc | Alta | `DialStyle` slot 10 + tests de anatomía |
| Uso accidental de `widgetPath` como core | Alta | API separada + test con path real del firmware |
| Deriva del bootstrap duplicado | Media | bloque mínimo idéntico + test estático; template si crece |
| Ruptura de modelos legacy | Alta | paquete de transición; no auto-delete/rename |
| Churn al separar layout/renderer | Media | después de checkpoint funcional; commits mecánicos separados |
| Confusión entre Dial y “reloj de tiempo” | Baja | label `Gauge Dial Pro`, ID `DialPro`; evitar `GaugeClock` |
| Una mejora llega solo a una familia aunque sea compartible | Alta | regla shared-first, checklist y tests simétricos de `DEVELOPMENT_GUIDE.md` |

---

## 11. Decisiones recomendadas para cerrar

1. Usar labels **Gauge Dial Pro**/**Gauge Bar Pro**, IDs `DialPro`/`BarPro` y carpetas
   `GaugeDialPro`/`GaugeBarPro`.
2. Mantener `DialStyle` y eliminar solo el cambio de familia.
3. Slot 10: `DialStyle` para Dial, `BarPreset` para Bar; `Sweep` pasa al 11.
4. Distribuir una release de transición con legacy opcional.
5. Hacer obligatoria la separación de módulos y el gate de RAM antes de publicar.
6. No introducir caché global hasta medir el caso mixto en el hardware objetivo.

Con estas decisiones, el split deja de ser solo una separación de menús: se convierte en dos
widgets coherentes, instalables y verificables, sin perder caras de dial ni degradar silenciosamente
la memoria del transmisor.

---

## 12. Resultado de ejecución

- Suites: `70/70` unit, `201/201` lifecycle legacy y `17/17` contratos split.
- Carga selectiva observada: Dial 14 chunks; Bar 17. Dial no carga ningún módulo Bar y Bar no
  carga `dial_layout` ni `dial_renderer`.
- Callbacks del probe split: Dial update/build `~3800/~4800`; Bar `~7200/~4200` instrucciones;
  steady-state `~600/~800`; movimiento `~1800/~1600`. Todos pasan los guardrails.
- Auditoría completa: matriz de colisiones limpia; allocations conservan el baseline aprobado
  (Dial 13–14 B/frame, Bar 32–35 B/frame ordinario; cero `linePoints` por frame).
- RAM retenida del harness: Dial `~310 KB`, Bar `~531 KB`, estimado mixto `~841 KB`. Es una
  medición comparativa de Lua de escritorio, no una cifra de heap garantizada para cada radio.
- `sync-sd.ps1` verificó paquetes nuevo y de transición, orden core→frentes y `coreApi = 1`.
- La verificación visual y de memoria en radio o Companion real queda como gate manual de release;
  la instalación de archivos y los harnesses headless sí quedaron validados.
- El legacy no se elimina automáticamente; su retiro permanece como la fase 5 post-release.
