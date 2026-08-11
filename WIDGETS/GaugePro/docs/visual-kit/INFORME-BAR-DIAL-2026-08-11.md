# Gauge Bar Pro + Gauge Dial Pro — informe de análisis visual y revisión de código

> **Estado: los catorce hallazgos están corregidos y verificados.** El análisis
> original se conserva íntegro más abajo, porque el diagnóstico es la parte que
> no se puede reconstruir después. Lo que se hizo, y la evidencia de que
> funciona, está en [§0 Reparaciones](#0-reparaciones-aplicadas).
>
> El hallazgo raíz resultó **no ser del widget**: EdgeTX compila Lua con
> `LUA_FLOORN2I 1`, de modo que en la radio `0.45 == 0` es **verdadero**. Ver
> [R-0](#r-0).

**Fecha:** 11 de agosto de 2026
**Rama:** `feat/gauge-v2` — árbol limpio en `488d6cf82`
**Alcance:** el estilo **Bar** (`GaugeBarPro`) y el estilo **Dial / reloj** (`GaugeDialPro`),
en sus opciones, caras, modos de color, paletas, orígenes, tamaños y estados.
**Documento hermano:** [`INFORME-DEFECTOS.md`](INFORME-DEFECTOS.md) (histórico pre-split).
Este informe **no lo sustituye**: reverifica sus puntos abiertos contra el código
actual y añade hallazgos nuevos.

---

## 0. Reparaciones aplicadas {#0-reparaciones-aplicadas}

| ID | Corrección | Fichero(s) | Prueba que lo fija |
|---|---|---|---|
| [R-0](#r-0) | **Causa raíz de B-1**: `float == entero` se trunca en la radio. Eliminada esa comparación de todo el runtime | `geometry.lua`, `bar_faces.lua`, `ranges.lua` | `N-01`, `N-02`, `N-03` |
| B-1 | `BarOrigin = Zero` mueve el origen del relleno en las cinco caras | (consecuencia de R-0) | `N-02` + captura nativa |
| B-2 | El guardián de contraste mide contra la **superficie**, y `palette = theme` rechaza un rol ilegible en vez de adoptarlo a ciegas | `bar_style.lua` | `Theme Adaptive adopts a theme role only when it is readable` |
| B-3 | Los dos carriles de Dual Rail son pista, no colores de estado | `bar_faces.lua` | catálogo + captura nativa |
| B-4 | `Surface = Theme panel` se dibuja como borde real cuando su color coincide con el fondo; **y una sola implementación de panel para todas las caras** | `bar_faces.lua` | `Phase 2: surfaces ground the widget…` |
| B-5 | El pulso crítico modula la cabeza / la píldora, nunca el dato | `bar_faces.lua`, `bar.lua`, `dial_renderer.lua` | `Phase 6: Refined critical pulse…`, `P1-1`, `P1-10` |
| B-6 | La cara Steps tiene suelo de altura, cediendo sólo si el raíl no da un píxel por escalón | `bar_faces.lua` | `Phase 4: Stepped Signal grows upward…` |
| B-7 | Static siempre anuncia su estado con la píldora | (ya era el comportamiento; ahora está fijado) | `P-1b` |
| P-1 | `ShowMinMax = "Markers + text"` pinta texto en **ambas** familias | `bar_layout.lua`, `bar.lua`, `dial_layout.lua` | `P-1` |
| P-2 | `Gradient` es espacial en las dos familias, con una sola regla compartida | `ui_core.lua`, `dial_renderer.lua`, `bar_faces.lua` | `P-2`, `gradient mode paints the SCALE…` |
| D-1 | Threshold dibuja sus marcas exactas también en el dial | `dial_renderer.lua` | `D-1` |
| D-2 | La aguja arranca dentro del buje | `dial_layout.lua` | catálogo (`st-normal`: pala r=8 → r=3) |
| D-3 | El marcador de "sin lectura" es `--`, no un guion suelto | `format.lua` | `number formatting honours precision` |
| H-1 | El emisor SVG usa `lengthAdjust="spacing"`: mantiene el ancho honesto sin deformar glifos | `dev/svgkit.lua` | inspección a 2× y 6× |
| H-2 | `verify_dupes.py` clasifica cada duplicado y `report.py` sólo avisa de los inexplicados | `verify_dupes.py`, `report.py` | 48 WARN → 0 |

Puertas después de las reparaciones:

```
run_tests.lua       70/70    PASS
smoke_test.lua     208/208   PASS   (+7 tests nuevos)
widgets_test.lua    17/17    PASS
luacheck                     0 warnings / 0 errors en los 20 módulos runtime
dev/collide.lua              all cases clean
dev/gallery.lua              223 escenas, 0 fallidas, 0 avisos de render
visual-kit (firmware real)   262 capturas, 262 PASS, 0 WARN, 0 FAIL
verify_dupes.py              0 grupos duplicados sin explicar
```

### R-0 — La radio evalúa `0.45 == 0` como verdadero {#r-0}

**Esto no era un defecto del widget.** Es la causa raíz de B-1 y de la mitad de
sus síntomas, y afecta a **cualquier script Lua de este firmware**.

`radio/src/thirdparty/Lua/src/luaconf.h:164` define `LUA_FLOORN2I 1`, con este
comentario de EdgeTX:

> *We need to force floats to be converted to integers, even if not integral in
> nature. It allows most Edgetx API functions to accept unrounded floats when
> integers are required.*

El efecto buscado es ese. El no buscado es que `luaV_equalobj`
(`lvm.c:404`) usa **el mismo** macro `tointeger` para comparar un float con un
entero, así que el float se **suelifica** antes de comparar.

Medido en el simulador real, instrumentando el widget y leyendo `simu.log`:

```
GPDBG4 o=0.45 mt=float  o==0:true  o==0.0:false  o>0:true
                                   lit 0.45==0:true  1/2=0.5  3%2=1
```

- `x == <entero>` con `x` fraccionario → **falso positivo**.
- `x == <float>` → correcto (`luai_numeq`).
- `<`, `<=`, `>`, `>=` → correctos (la conversión va int→float, que es exacta).
- Las claves de tabla no se ven afectadas (`luaH_get` fija el modo 0).

Consecuencias que estaban vivas en el widget:

| Comparación | Dónde | Qué provocaba |
|---|---|---|
| `axis.originT == 0` | `bar_faces` ×4 | `BarOrigin = Zero` tomaba siempre la rama de prefijo: **B-1** |
| `fraction == 0` | `paintCell` | toda celda **parcial** se pintaba como fantasma |
| `cell.fraction == fraction` | `setCellFraction` | el repintado de una celda parcial se saltaba |
| `span == 0` | `ranges.deadband` | una escala de 0.5 V perdía su histéresis |

Corregido usando desigualdades y un booleano resuelto una vez
(`axis.prefixOrigin`), con el mecanismo documentado en `geometry.isZero`. La
guarda `N-03` escanea los módulos de runtime y falla si vuelve a aparecer una
de estas comparaciones: reintroducida a mano, la detecta
(`bar_faces.lua:760 if axis.originT == 0 then`).

**No se ha tocado `luaconf.h`.** Cambiar `LUA_FLOORN2I` alteraría la semántica
numérica de todos los scripts del fork; es una decisión del propietario del
firmware, no de este widget. Queda anotado aquí como defecto de plataforma con
la evidencia para decidirlo.

### Verificación sobre el firmware real {#verificacion}

Tanda completa nueva, con todas las capturas regeneradas (Track 1, Track 2 y el
subconjunto de temas): **262 pantallas, 262 PASS, 0 WARN, 0 FAIL**, frente a
166 PASS / 48 WARN antes.

Los 48 avisos eran duplicados byte-idénticos sin triar. Ahora `verify_dupes.py`
clasifica cada grupo y `report.py` sólo degrada a WARN los que **no** tienen
explicación: quedan **0 grupos inexplicados**. Los 12 que persisten están
justificados uno a uno y se imprimen con su motivo — todos son "esta opción ES
el valor por defecto, así que estos casos repiten el mismo render" o la
limitación conocida de `TX_VOLTAGE` documentada en el README del kit.

Medidas de píxel sobre las capturas nativas, mismo método que el análisis:

| Qué | Antes | Después |
|---|---|---|
| Relleno del preset Minimal (`087`) | `#ffdf00` — **1.14:1** claro / 9.93 oscuro | `#21925a` — **3.40:1** claro / **3.35:1** oscuro |
| Relleno en CRIT (`062`) | `#bd3c4a` (translúcido, 2.46:1 sobre oscuro) | `#ff0000` a opacidad plena |
| Carril negativo de Dual Rail (`166`) | `#ef5d63` en todo su largo | `#6396bd` — pista |
| Origen cero, relleno (`150`) | `407…730` (nace en el extremo bajo) | `583…730` (nace en la marca de cero, `580`) |
| Primer escalón activo de Steps (`f4-steps-static`) | 2 px verde junto a 15 px de pista | escalón sólido, legible |

Y mirando los píxeles, ampliados y recortados a la zona:

| Hoja | Qué confirma |
|---|---|
| [`despues-dial-estado-color.png`](analisis-2026-08-11/despues-dial-estado-color.png) | Static / Threshold / Gradient **ya no son la misma imagen**: Threshold marca sus dos umbrales exactos, Gradient pinta la rampa espacial rojo→naranja→verde. La aguja arranca en el buje. `NO SOURCE` muestra `--`. El pulso apaga la píldora, no el arco |
| [`despues-bar-origen-zero.png`](analisis-2026-08-11/despues-bar-origen-zero.png) | `BarOrigin = Zero` nace en la marca de cero en las **cinco** caras, con celda parcial en los dos bordes |
| [`despues-bar-dual-rail.png`](analisis-2026-08-11/despues-bar-dual-rail.png) | Los dos carriles son pista neutra; el relleno crece desde el cero hacia el valor |
| [`despues-bar-estilos.png`](analisis-2026-08-11/despues-bar-estilos.png) | Minimal en verde calibrado, CRIT en rojo pleno, `Theme panel` distinguible de `Transparent` |
| [`despues-dial-minmax-text.png`](analisis-2026-08-11/despues-dial-minmax-text.png) · [`despues-bar-minmax-text.png`](analisis-2026-08-11/despues-bar-minmax-text.png) | `Markers + text` escribe `min`/`max` en **ambas** familias |
| [`despues-bar-steps.png`](analisis-2026-08-11/despues-bar-steps.png) | Los escalones activos son barras sólidas, no pelos |

El catálogo ganó una escena, `br-minmax-text`: no había **ninguna** caso de
barra que ejerciera `ShowMinMax`, que es parte de por qué la tercera opción
pudo estar cableada a `false` en esa familia sin que nadie lo viera.

---

## 1. Método y base de evidencia

Tres fuentes independientes, cruzadas entre sí en cada hallazgo:

| Fuente | Qué es | Qué prueba |
|---|---|---|
| **Suites Lua** (`tests/run_tests.lua`, `smoke_test.lua`, `widgets_test.lua`, `luacheck`, `dev/collide.lua`) | lógica pura sobre `tests/mock_env.lua` | contratos, estados, geometría, colisiones |
| **Catálogo SVG** (`dev/shots.lua` + `dev/gallery.lua`) | el árbol de objetos LVGL real que pide el widget, emitido como SVG | qué objeto, con qué color, opacidad y coordenada exacta |
| **Emulador de radio** (`tools/gaugepro-visual-kit` sobre `build/simu/simu.exe`, `--pipe`) | **firmware real**: LVGL real, binding Lua real, fuentes y temas reales | los píxeles que ve el usuario |

Ejecutado en esta sesión:

- 228 SVG × 3 temas (`stock`, `dark`, `highcontrast`) + hoja de galería completa — **0 fallos, 0 avisos de render**.
- Rasterizado con Playwright y **mirado**, ampliado, recortado **a la zona real de cada widget**
  (el simulador es 800×480 y cada caso vive en una zona de layout concreta; sin recortar,
  la composición se juzga mal).
- Relectura de las 214 capturas de firmware real de `docs/visual-kit/screenshots/`
  (generadas 2026-08-11 08:36, **posteriores a todos los fuentes** del widget: siguen vigentes).
- Medición de píxel sobre las capturas nativas (RLE de scanlines, bounding boxes,
  histogramas y ratios de contraste WCAG) — todos los números de este informe salen de ahí.
- Revisión de `bar.lua`, `bar_faces.lua`, `bar_layout.lua`, `bar_style.lua`,
  `dial_layout.lua`, `dial_renderer.lua`, `geometry.lua`, `ui_core.lua`, `theme.lua`.

### 1.1 Línea base: todo verde antes de empezar

```
run_tests.lua      70/70    PASS
smoke_test.lua    201/201   PASS
widgets_test.lua   17/17    PASS
luacheck                    0 errores (34 warnings, todos en output/ generado y 1 en tests/)
dev/collide.lua             collision audit: all cases clean
dev/gallery.lua             222 escenas, 0 fallidas, avisos de render: ninguno
```

**Ninguno de los hallazgos P1 de este informe es visible desde esas puertas.**
Ese es, en sí mismo, el resultado más importante: 288 tests en verde y una galería
limpia conviven con una opción inerte, tres presets ilegibles y una cara que pinta
el carril inactivo como si estuviera lleno.

### 1.2 Evidencia gráfica adjunta

| Hoja | Contenido |
|---|---|
| [`analisis-2026-08-11/dial-estado-color.png`](analisis-2026-08-11/dial-estado-color.png) | Dial: 14 zonas, estados y los 5 ColorMode |
| [`analisis-2026-08-11/dial-escala-opciones.png`](analisis-2026-08-11/dial-escala-opciones.png) | Dial: escalas, sweeps, estilos, min/max, aguja |
| [`analisis-2026-08-11/bar-estilos.png`](analisis-2026-08-11/bar-estilos.png) | Bar: 32 zonas, tamaños, extremos, superficies, ColorMode, presets |
| [`analisis-2026-08-11/bar-caras.png`](analisis-2026-08-11/bar-caras.png) | Bar: Blocks / Hex / Ticks / Steps × 5 ColorMode |
| [`analisis-2026-08-11/bar-origen-zero.png`](analisis-2026-08-11/bar-origen-zero.png) | Bar: `BarOrigin = Zero` en las 5 caras |
| [`analisis-2026-08-11/bar-dual-rail.png`](analisis-2026-08-11/bar-dual-rail.png) | Bar: Dual Rail horizontal y vertical |

---

## 2. Resumen ejecutivo

| ID | Sev | Familia | Título | Procedencia |
|---|---|---|---|---|
| [B-1](#b-1) | **P1 — RESUELTO** | Bar | `BarOrigin = Zero` no mueve el origen del relleno **en el firmware real** (sí en el mock) | reabre W-06 |
| [B-2](#b-2) | **P1 — RESUELTO** | Bar | Tres presets pintan el dato en `#ffde00` a **1.14:1** sobre el fondo | nuevo |
| [B-3](#b-3) | **P1 — RESUELTO** | Bar | Dual Rail pinta el carril del signo contrario **lleno** y en rojo crítico | nuevo |
| [P-1](#p-1) | **P1 — RESUELTO** | Paridad | `ShowMinMax = "Markers + text"` no muestra texto: en Bar **nunca**, en Dial casi nunca | nuevo |
| [P-2](#p-2) | **P1 — RESUELTO** | Paridad | `ColorMode = Gradient` significa cosas distintas en Dial y en Bar | nuevo |
| [B-4](#b-4) | **P2 — RESUELTO** | Bar | `Surface = Theme panel` es un no-op que cuesta un objeto LVGL | nuevo |
| [B-5](#b-5) | **P2 — RESUELTO** | Bar | El pulso de crítico deja el relleno en `#bd3c4a`, fuera de la ventana de luminancia | nuevo |
| [B-6](#b-6) | **P2 — RESUELTO** | Bar | La cara `Steps` dibuja los escalones bajos como pelos de 1 px | nuevo |
| [D-1](#d-1) | **P2 — RESUELTO** | Dial | Static / Threshold / Gradient son **byte-idénticos** en estado normal | nuevo |
| [D-2](#d-2) | **P2 — RESUELTO** | Dial | La aguja no arranca en el buje: hueco fijo de 0.07·R | reabre W-04 (mitad: el hueco sí, el desborde no) |
| [B-7](#b-7) | **P3 — RESUELTO** | Bar | `ColorMode = Static` pinta con el verde que significa "normal" | reabre W-05 |
| [D-3](#d-3) | **P3 — RESUELTO** | Dial | El marcador de valor de `NO SOURCE` se lee como una barra gris suelta | nuevo |
| [H-1](#h-1) | **P2 — RESUELTO** | Utillaje | El emisor SVG usa `textLength` + `lengthAdjust`: el texto se rompe al rasterizar | nuevo |
| [H-2](#h-2) | **P2 — RESUELTO** | Utillaje | 48 capturas byte-idénticas; el aviso no distingue "opción sin efecto" de "colapso del arnés" | amplía H-03 |

---

## 3. Hallazgos del estilo BAR

### B-1 — `BarOrigin = Zero` dibuja la marca de cero pero el relleno sigue naciendo en el extremo bajo {#b-1}

**Severidad: P1.** La opción parece funcionar (aparece la marca) y miente sobre lo que mide la barra.

> **RESUELTO** — ver [§0](#0-reparaciones-aplicadas) y la [verificación](#verificacion).

#### Evidencia — firmware real

`153_ejes5_f5-zero-h-blocks-positive.png` (`BarFace=Blocks, BarOrigin=Zero,
ColorMode=Sections, Min=-9, Max=11`, valor 7.9). La barra ocupa x = 408…792 (384 px).
RLE de la fila 61:

| x | ancho | color | lectura |
|---:|---:|---|---|
| 408 | 33 | `#ff0000` | bloque 1 — **activo** |
| 447 | 32 | `#ff0000` | bloque 2 — **activo** |
| 486 | 32 | `#ce6100` | bloque 3 — **activo** |
| 524…711 | — | `#21925a` | bloques 4…8 — **activos** |
| **580** | **3** | **`#105d9c`** | **marca de cero**, altura completa 55…79 con voladizo |
| 717 | 14 | `#a5cfc6` | bloque 9 — fantasma |
| 731 | 4 | `#000000` | cabeza (valor) |
| 755 | 37 | `#a5cfc6` | bloque 10 — fantasma |

`zeroT = normalize(0, -9, 11) = 0.45` → x = 408 + 0.45·384 = **581**. La marca está
exactamente ahí, a altura completa y en `palette.label`: es `ui.zeroMark`
([`bar.lua:180-186`](../../bar.lua#L180)), que **sólo se crea si `visual.origin == "zero"`**.
Es decir: en la radio el origen ES "zero" y aun así los bloques 1…8 están activos
desde el extremo izquierdo, sin parcial en ninguno de los dos bordes.

Ese patrón —prefijo completo, sin parciales— es exactamente el que produce la rama
`axis.originT == 0` de [`bar_faces.lua:1119`](../../bar_faces.lua#L1119).

Se repite en las cinco caras (ver [`bar-origen-zero.png`](analisis-2026-08-11/bar-origen-zero.png)):
`150` continuous (relleno degradado desde x=407 cruzando la marca de cero en 580),
`153` blocks, `156` hex, `159` ticks, `162` steps.

#### Evidencia — arnés Lua: **correcto**

Reproduciendo la misma configuración contra `tests/mock_env.lua`:

```
axis: originT=0.4500 zeroT=0.4500 origin=zero clamped=false
cell  1..4   fraction=0     opa=82     <- fantasma
cell  5      fraction=0.5   opa=169    <- parcial en el borde CERO
cell  6..8   fraction=1.0   opa=255    <- activo
cell  9      fraction=0.45  opa=160    <- parcial en el borde CABEZA
cell 10      fraction=0     opa=82     <- fantasma
```

La lógica del widget es correcta: `G.makeAxis` ([`geometry.lua:87-112`](../../geometry.lua#L87))
calcula `originT = zeroT`, y `continuousUpdate` ([`bar_faces.lua:736-740`](../../bar_faces.lua#L736))
y `updatePartialCells` ([`bar_faces.lua:1146`](../../bar_faces.lua#L1146)) abren el tramo
desde el origen.

#### Diagnóstico

**Los dos entornos discrepan.** En el firmware real coexisten dos hechos que no pueden
ser ciertos a la vez con un único `axis`:

1. `visual.origin == "zero"` (la marca existe y está en `axis.originCoord`);
2. el actualizador de celdas tomó la rama `axis.originT == 0`.

Hipótesis a descartar por orden de coste, **con instrumentación en la radio**, no por lectura:

1. **Dos objetos `axis` distintos**: `L.axis` en el momento del build (marca) frente al
   `widget.layout.axis` del refresh (celdas). `bar_layout.calculate` reconstruye `L.axis`
   y `L.activeAxis` en cada pasada ([`bar_layout.lua:389-392`](../../bar_layout.lua#L389));
   si una pasada posterior llega con `visual.origin` distinto, la marca retenida se queda
   donde estaba y el relleno cambia de modelo.
2. **`cfg.min`/`cfg.max` distintos entre build y refresh** (resolución tardía de preset o
   de fuente — el mismo patrón que `F-9b` en `smoke_test`): `zeroT` colapsaría a 0.
3. Codificación de la opción en el arnés (`tools/gaugepro-visual-kit/defs.py`). **Poco
   probable**: si `barOrigin` no llegara como 3, la marca de cero no se dibujaría.

#### Remediación propuesta

1. Añadir al harness de tests un caso que **compare `visual.origin` con `L.axis.originT`**
   y falle si `origin == "zero" and originT == 0 and zeroInside`. Hoy nada liga esas dos
   verdades.
2. Instrumentar `bar_layout.barLayout` para volcar `visual.origin`, `cfg.min`, `cfg.max`,
   `axis.originT` en `simu.log` y capturar el caso 153 con el emulador.
3. Consumir un **único** descriptor de origen: que `bar.lua` dibuje `zeroMark` desde
   `axis.originT`/`axis.originCoord` y no desde `visual.origin`, de modo que marca y
   relleno no puedan divergir aunque el layout se recalcule.

---

### B-2 — Tres presets pintan el dato en el amarillo del tema: 1.14:1 sobre el fondo {#b-2}

**Severidad: P1.** No es un color mal elegido: es **la reintroducción, por otra puerta,

> **RESUELTO** — ver [§0](#0-reparaciones-aplicadas) y la [verificación](#verificacion).
de un defecto que este mismo repositorio ya diagnosticó, arregló y documentó**.

[`theme.lua:95-99`](../../theme.lua#L95), sobre por qué los colores de estado dejaron de
ser roles de tema:

> *This used to be `COLOR_THEME_ACTIVE`, which is `#ffde00` on the stock theme and scores
> **1.13:1** against the stock screen background — the normal state, arc and value alike,
> was effectively invisible on a stock radio. It measured 9.87:1 on a dark theme, which is
> why every render in this repo looked right for four review rounds.*

`bar_style.lua` vuelve a coger exactamente ese rol para el estado normal de tres presets.

#### Evidencia

`087_barra_br-preset-minimal.png`, RLE de la fila del relleno:

```
409 +132  #ffdf00     <- relleno activo
541 +3    #ff0000     <- marca crit
544 +74   #ffdf00
618 +3    #e70000
621 +91   #ffdf00
713 +3    #000000     <- cabeza
716 +75   #9cbad6     <- pista
```

`122_caras4_f4-preset-ticks.png`: los 20 ticks activos, todos `#ffdf00`.

Contrastes WCAG medidos contra el fondo real de la zona (`#e7eff7`) y contra un tema
oscuro (`#303030`):

| Color | vs `#e7eff7` | vs `#303030` | Luminancia | Ventana `[0.189, 0.247]` |
|---|---:|---:|---:|---|
| `#ffdf00` | **1.14** | 9.93 | 0.740 | **fuera** |
| `#21925a` (normal clásico) | 3.40 | 3.35 | 0.216 | dentro |
| `#ce6100` (warn) | 3.39 | 3.35 | 0.217 | dentro |
| `#ff0000` (crit) | 3.44 | 3.30 | 0.213 | dentro |

#### Análisis del código

[`bar_style.lua:256-257`](../../bar_style.lua#L256):

```lua
if mode == "theme" then
  normalSource, warningSource = COLOR_THEME_ACTIVE, COLOR_THEME_WARNING
```

`COLOR_THEME_ACTIVE` es `#ffde00` en el tema stock de EdgeTX. Lo usan **tres de los
nueve presets** ([`bar_style.lua:40-96`](../../bar_style.lua#L40)):

| Preset | `palette` | `surface` | `thickness` | `contrast` |
|---|---|---|---|---|
| `[3] theme-clean` | `theme` | `theme-panel` | thin | auto |
| `[6] signal-ticks` | `theme` | transparent | medium | auto |
| `[8] minimal-line` | `theme` | transparent | **thin** | **off** |

`minimal-line` es el peor caso posible: el color de menor contraste, sobre el fondo
desnudo, con el trazo más fino **y con el canal de asistencia desactivado por diseño**.

La causa estructural está en el guardián: [`bar_style.lua:309-311`](../../bar_style.lua#L309)

```lua
local nt = T.contrastRatio(normal, track)
local wt = T.contrastRatio(warning, track)
local ct = T.contrastRatio(critical, track)
```

**Sólo se mide contra la pista.** Cuando la superficie es transparente y el trazo es
fino, el dato no se apoya en la pista sino en el fondo de la pantalla, y ese contraste
no se evalúa nunca.

#### Remediación propuesta

1. Añadir `normalSurfaceContrast` / `warningSurfaceContrast` / `criticalSurfaceContrast`
   contra `palette.panel` **y** contra el fondo del tema, y meterlos en `basicNeed`.
2. Con `palette == "theme"`, no adoptar `COLOR_THEME_ACTIVE` a ciegas: si su contraste
   contra la superficie efectiva baja de 3:1, degradar al `T.color.accent` calibrado y
   registrar el downgrade (ya existe el mecanismo `visual.downgrades`).
3. `contrast = "off"` debe seguir permitiendo la degradación de color: hoy apaga tanto el
   canal redundante como cualquier corrección.

---

### B-3 — Dual Rail pinta el carril del signo contrario a longitud completa y en rojo crítico {#b-3}

**Severidad: P1** (riesgo de lectura invertida en la cara pensada precisamente para

> **RESUELTO** — ver [§0](#0-reparaciones-aplicadas) y la [verificación](#verificacion).
mandos bidireccionales).

#### Evidencia

`166_ejes5_f5-dual-h-pos.png` (`Min=-9, Max=11`, valor **positivo** 7.9):

| x | ancho | color | qué es |
|---:|---:|---|---|
| 408 | **172** | `#ef5d63` | **todo el carril negativo, saturado** |
| 580 | 3 | `#105d9c` | cero |
| 583…730 | 148 | `#21925a` | relleno positivo (correcto: nace en cero) |
| 731 | 4 | `#000000` | cabeza |
| 735 | 57 | `#6bb694` | pista positiva inactiva (verde al 59 %) |

El lado positivo **sí** distingue activo (`#21925a` opaco) de inactivo (`#6bb694`).
El lado negativo no distingue nada: es una barra roja llena, permanentemente. Lo mismo
en vertical (`169 f5-dual-v-pos`: mitad inferior salmón completa) y en `172`, `173`.

#### Análisis del código

[`bar_faces.lua:1527-1541`](../../bar_faces.lua#L1527):

```lua
for i = 1, 2 do
  local fromT, toT = (i == 1) and 0 or axis.originT, ...
  local endpoint = (i == 1) and widget.config.min or widget.config.max
  local negative = endpoint < 0
  local track = lvgl.rectangle{
    ...
    color = negative and palette.critical or palette.normal,
    opacity = T.opacity.rail, ...
```

Dos decisiones se suman:

1. **El carril negativo toma `palette.critical`.** Semánticamente eso dice "negativo =
   crítico". Para el preset `rc-center` (un stick centrado) es falso: −50 % de alerón no
   es un estado crítico.
2. **La opacidad sube con la asistencia.** `dualPalette`
   ([`bar_faces.lua:1558-1559`](../../bar_faces.lua#L1558)) hace
   `trackOpacity = rail + 60` cuando `assist == "needed"` y `railBand` (200) cuando es
   `"strong"`. Medido: 59 % — a esa opacidad un rojo saturado sobre fondo claro deja de
   leerse como pista y se lee como relleno.

#### Remediación propuesta

- Los dos carriles inactivos deben usar `palette.track`, no colores de estado; el signo
  se comunica con la **posición respecto al cero**, que ya está dibujada.
- Si se quiere teñir los carriles, hacerlo con la mezcla hacia el fondo que ya usa el
  lado positivo (`#6bb694` = normal al 62 %) y aplicar la **misma** regla a ambos lados,
  para que la asimetría activo/inactivo exista en los dos.
- El tope de opacidad de un carril inactivo no debería superar el del relleno activo
  menos un escalón, sea cual sea el nivel de asistencia.

---

### B-4 — `Surface = Theme panel` es un no-op que cuesta un objeto LVGL {#b-4}

**Severidad: P2.**

> **RESUELTO** — ver [§0](#0-reparaciones-aplicadas) y la [verificación](#verificacion).

`075_barra_br-surface-clear.png` y `076_barra_br-surface-theme.png` tienen **histogramas
de color idénticos** (`#e7eff7` 373654 px, `#ce6100` 3642, `#6396bd` 3554, …). También
`114 f4-hex-rich`, que declara `Surface=Theme panel`, es indistinguible de su equivalente
transparente.

Causa, en dos líneas:

- [`bar_faces.lua:909-917`](../../bar_faces.lua#L909) — `buildPanel` **sí** crea el
  rectángulo cuando la superficie no es transparente, opaco y a zona completa.
- [`bar_style.lua:269-270`](../../bar_style.lua#L269) — su color es
  `COLOR_THEME_SECONDARY3`, que en el tema stock (`#e4eef2`) es **el mismo color con el
  que la radio pinta el fondo de pantalla**.

Resultado: un objeto LVGL más, un relleno de zona completa por frame, y cero píxeles de
diferencia. La opción sólo es visible con `Surface = Custom colors` (`077`, aubergine).

**Remediación:** o el panel se separa del fondo (por ejemplo mezclando SECONDARY3 hacia
PRIMARY3 un escalón, o añadiendo el borde `SECONDARY1` que ya está en la paleta), o
`theme-panel` se resuelve a `transparent` cuando `panel == fondo` y no se construye el
objeto. Lo segundo es gratis y honesto; lo primero requiere decisión de diseño.

---

### B-5 — El pulso de crítico deja el relleno en `#bd3c4a`, fuera de la ventana de luminancia {#b-5}

**Severidad: P2.**

> **RESUELTO** — ver [§0](#0-reparaciones-aplicadas) y la [verificación](#verificacion).

Medido en `071_barra_br-maximum.png` y `062_barra_br-crit.png`: el relleno en estado
CRIT es `#bd3c4a`, mientras la píldora y el valor son `#ff0000`. El árbol de objetos lo
confirma — `br-crit.svg`:

```
<rect ... fill="#ff0000" fill-opacity="0.80"/>   <- relleno CRIT
<rect ... fill="#21925a" fill-opacity="1.00"/>   <- relleno normal (br-normal.svg)
```

Es el pulso crítico (`R.updatePulse` → `T.opacity.pulse = 150`,
[`theme.lua:172`](../../theme.lua#L172)) capturado a media fase. Dos consecuencias:

1. **El estado más urgente es, la mitad del tiempo, el elemento menos presente de la
   pantalla.** El verde de "todo bien" se dibuja al 100 %; el rojo de "crítico" oscila
   entre el 59 % y el 100 %.
2. `#bd3c4a` tiene luminancia 0.145 y **2.46:1 contra un fondo oscuro** — fuera de la
   ventana `[0.189, 0.247]` que el propio contrato de color del widget exige a cualquier
   color fijo. La ventana se verifica sobre el color nominal, no sobre el color
   compuesto que realmente se pinta.

**Remediación:** pulsar sobre un canal que no degrade la señal (grosor de la cabeza,
la píldora, un halo) o acotar el suelo del pulso a una opacidad cuyo color compuesto
siga dentro de la ventana. Y medir la ventana **después** de aplicar opacidad, no antes.

---

### B-6 — La cara `Steps` dibuja los escalones bajos como pelos de 1 px {#b-6}

**Severidad: P2.** Visible en `107`…`111`, `118`, `119`, `161`, `162`

> **RESUELTO** — ver [§0](#0-reparaciones-aplicadas) y la [verificación](#verificacion).
(ver [`bar-caras.png`](analisis-2026-08-11/bar-caras.png)).

Altura de columna medida en `107_caras4_f4-steps-static.png` (barra x = 408…792,
cabeza en x = 560):

| x | altura | color | estado |
|---:|---:|---|---|
| 448, 464 | **2 px** | `#21925a` | **activo** |
| 488…512 | **4 px** | `#21925a` | **activo** |
| 528…552 | 6 px | `#adcbde` | inactivo |
| 640…664 | 11 px | `#adc7de` | inactivo |
| 680…704 | 13 px | `#adc7de` | inactivo |
| 720 | 15 px | `#adc7de` | inactivo |

La escalera crece de izquierda a derecha por diseño (metáfora de barras de señal), pero
el efecto combinado es que **la parte que lleva el dato es la más fina del widget y la
parte sin dato es la más gruesa**: 2 px de verde activo frente a 15 px de azul inactivo.
A tamaño real los primeros escalones no se ven.

**Remediación:** suelo de altura para el escalón (`max(T.px(3), …)`) igual que
`blocksBuild` usa `minCell = T.px(3)` ([`bar_faces.lua:1332`](../../bar_faces.lua#L1332)),
y recorte del número de escalones cuando ese suelo no cabe, en vez de degradar la altura.

---

### B-7 — `ColorMode = Static` pinta con el verde que significa "normal" (W-05, abierto) {#b-7}

**Severidad: P3.** Confirmado en `078_barra_br-mode-static.png`: relleno `#21925a`

> **RESUELTO** — ver [§0](#0-reparaciones-aplicadas) y la [verificación](#verificacion).
(exactamente el color del estado normal) con la píldora **WARN** visible al lado.

Causa en [`ui_core.lua`](../../ui_core.lua) `resolveColor`: `if key == "static" then
return widget.accent or T.color.accent end`, y `T.color.accent` es el mismo verde que
`stateColor("normal")`. La barra dice "todo bien" mientras la píldora dice lo contrario.

**Remediación:** que el acento por defecto de Static no coincida con el verde semántico
(por ejemplo el azul `SECONDARY1`, ya calibrado), o documentar Static como "sin
semántica de color" y obligar a que la píldora esté siempre visible en ese modo.

---

## 4. Hallazgos del estilo DIAL / reloj

### D-1 — Static, Threshold y Gradient son byte-idénticos en estado normal {#d-1}

**Severidad: P2.**

> **RESUELTO** — ver [§0](#0-reparaciones-aplicadas) y la [verificación](#verificacion).

`RUN_SUMMARY.md` lo dice sin ambigüedad: `005_color_color-static-ok.png`,
`007_color_color-threshold-ok.png` y `011_color_color-gradient-ok.png` son
**byte-idénticas**. Lo mismo `001` ≡ `009` (rail) ≡ `027`.

En la hoja [`dial-estado-color.png`](analisis-2026-08-11/dial-estado-color.png) se ve:
tres modos de color distintos producen exactamente el mismo arco verde liso. Sólo Rail y
Sections añaden algo (las bandas exteriores). En estado crítico sí se separan
(`006` verde estático, `008` rojo, `012` rojo puro, `014` con bandas).

Consecuencia práctica: un usuario que cambia `ColorMode` en el dial y está en estado
normal —el 95 % del tiempo de vuelo— no ve ninguna diferencia y concluye que la opción
está rota.

**Remediación:** el modo `Threshold` debería dibujar en el dial las marcas exactas de
umbral que **sí** dibuja la barra (`br-mode-threshold`); es su significado declarado
("Threshold / exact marks"). Sin eso, `Threshold` ≡ `Static` en el dial por construcción.

---

### P-2 — `ColorMode = Gradient` significa cosas distintas en Dial y en Bar {#p-2}

**Severidad: P1 de paridad** (`DEVELOPMENT_GUIDE.md` §5: *"Mismo significado de

> **RESUELTO** — ver [§0](#0-reparaciones-aplicadas) y la [verificación](#verificacion).
ColorMode | obligatorio; representación radial | obligatorio; representación lineal"*).

- **Bar**: gradiente **espacial**. `bar_faces.lua` construye N slices a lo largo del eje,
  cada una con el color de la severidad de *esa posición* de la escala. Se ve la escala
  entera coloreada (`085 br-gradient-large`: rojo → naranja → verde).
- **Dial**: gradiente **temporal**. [`ui_core.lua:139-153`](../../ui_core.lua#L139)
  devuelve **una sola clave** `"grad"..floor(t*20)` calculada con el *valor actual*
  entre `crit` y `warn`, y el arco entero se pinta de ese color.

No son dos representaciones del mismo concepto: son dos conceptos. En el dial el color
responde a "cuán cerca del umbral estoy"; en la barra, a "qué severidad tiene cada punto
de la escala". Un usuario con un dial y una barra en la misma pantalla ve dos reglas.

**Remediación:** decidir cuál es el significado canónico y adaptarlo a la otra familia
(el arco radial admite slices igual que el eje lineal), o —si se acepta la asimetría—
documentarla explícitamente y separarla en dos opciones con nombres distintos, como
exige la §12 del guía de desarrollo para toda excepción.

---

### P-1 — `ShowMinMax = "Markers + text"` no muestra texto {#p-1}

**Severidad: P1 de paridad.** Es una opción de los **slots compartidos 1–9**, que deben

> **RESUELTO** — ver [§0](#0-reparaciones-aplicadas) y la [verificación](#verificacion).
ser idénticos en key, tipo, default y **semántica** en ambas familias.

#### Bar: nunca, en ningún tamaño

[`bar_layout.lua:31-32`](../../bar_layout.lua#L31):

```lua
L.showMarkers    = (cfg.showMinMax or 1) > 1
L.showMinMaxText = false          -- <-- constante
```

La tercera opción del CHOICE es, en `GaugeBarPro`, indistinguible de la segunda. Siempre.

#### Dial: sólo con `mode == "large"`

[`dial_layout.lua:40-41`](../../dial_layout.lua#L40):

```lua
L.showMarkers    = (cfg.showMinMax or 1) > 1 and mode ~= "micro"
L.showMinMaxText = (cfg.showMinMax or 1) > 2 and mode == "large"
```

`mode == "large"` exige `min(w,h) >= 180 * LCD_SCALE`
([`layout_common.lua:146-153`](../../layout_common.lua#L146)). En una radio 800×480 eso
son ~300 px de lado corto: la zona de media pantalla 400×240 —la más usada— **no
califica**. Verificado en las dos fuentes:

- SVG: `op-mm-off` = 47 objetos, `op-mm-mark` = 49, `op-mm-text` = **49 y byte-idéntico a
  `op-mm-mark`**; los dos objetos extra son las dos marcas radiales, ningún texto.
- Firmware real: `031_dial_op-mm-mark.png` ≡ `032_dial_op-mm-text.png`, byte-idénticas.

**Remediación:** implementar el texto en la barra (tiene sitio de sobra en horizontal:
`br-large`, 480×160, deja media zona vacía) o retirar la tercera opción de ambos
contratos. Lo que no puede quedarse es un CHOICE de tres valores con dos comportamientos
en una familia y dos-y-medio en la otra. **Ojo:** las opciones publicadas están
congeladas y son append-only; retirar la opción no es viable sin romper modelos
guardados, así que el camino correcto es implementarla.

---

### D-2 — La aguja no arranca en el buje: hueco fijo de 0.07·R (W-04, parcialmente abierto) {#d-2}

**Severidad: P2.**

> **RESUELTO** — ver [§0](#0-reparaciones-aplicadas) y la [verificación](#verificacion).

```lua
L.pivotRadius = clamp(floor(L.radius * T.ratio.pivotRadius), ...)  -- ratio 0.09
L.needleInner = clamp(floor(L.radius * 0.16), T.px(3), T.px(20))
```

[`dial_layout.lua:247`](../../dial_layout.lua#L247) y
[`dial_layout.lua:270`](../../dial_layout.lua#L270), con
[`theme.lua:182,198`](../../theme.lua#L182). El buje termina en 0.09·R y la pala empieza
en 0.16·R: **siempre** hay un hueco de 0.07·R entre ambos. En una zona 200×160 (R = 51)
son 4 px, perfectamente visibles en `001`, `005`, `007`, `027`.

**Corrección respecto al informe anterior:** la otra mitad de W-04 ("la punta sobresale
del anillo") **no se reproduce**. `L.needleOuter = L.radius - trackThickness/2 - px(1)`
deja la punta dentro del borde interior de la pista (medido en `st-normal.svg`: pala
r = 8…45, pista r = 45.5…56.5). Lo que el ojo lee como "la aguja atraviesa el anillo"
son las **marcas radiales de min/max**, que por diseño van de `markInner`
(dentro de la pista) a `markOuter` (fuera del rail),
[`dial_layout.lua:226-227`](../../dial_layout.lua#L226). Cruzan la banda entera y a
tamaño pequeño se confunden con la aguja.

**Remediación:** `needleInner = pivotRadius` (o `pivotRadius - 1` para solapar un píxel),
y estudiar acortar `markOuter` para que la marca de historial no cruce toda la pista.

---

### D-3 — El marcador de valor de `NO SOURCE` se lee como una barra gris suelta {#d-3}

**Severidad: P3.** En `004_estado_st-nosource.png` el hueco del valor se rellena con un

> **RESUELTO** — ver [§0](#0-reparaciones-aplicadas) y la [verificación](#verificacion).
guion a cuerpo 29 px, que en el firmware real se pinta como un rectángulo gris macizo
flotando encima de la píldora `NO SOURCE`, desalineado con ella. Se lee como un artefacto
de render, no como "sin dato".

**Remediación:** usar `--` o el guion largo, alinearlo con la caja de valor y llevarlo al
mismo color apagado de la píldora.

---

## 5. Hallazgos del utillaje

### H-1 — El emisor SVG usa `textLength` + `lengthAdjust`: el texto se rompe al rasterizar {#h-1}

**Severidad: P2 para la validez de cualquier revisión visual futura.**

> **RESUELTO** — ver [§0](#0-reparaciones-aplicadas) y la [verificación](#verificacion).

`dev/svgkit.lua` emite cada etiqueta con el ancho medido de la fuente EdgeTX:

```xml
<text ... textLength="46.0" lengthAdjust="spacingAndGlyphs">STALE</text>
```

Chromium aplica ese ajuste de forma inconsistente según el zoom: a 2× el catálogo mostró
`NO DA`, `NO LIN`, `STAL` y una píldora **vacía** en `st-nosource`; a 4× las mismas
escenas leen `NO DATA`, `NO LINK`, `STALE` correctamente, pero `st-normal` degenera en
`/8 D` y `RSSI` se vuelve ilegible.

**Ningún defecto de widget se esconde detrás de esto** —lo verifiqué escena por escena—
pero es una trampa activa: cuatro "recortes de texto" aparentes resultaron ser artefactos
del rasterizador. Sin el A/B se habrían reportado como defectos.

**Remediación:** emitir `textLength` sólo cuando el SVG se use para medir, y no para
mirar; o añadir a `shots.lua` un modo `--no-textlength`. Mientras tanto: **cualquier
sospecha sobre texto en un SVG del catálogo se confirma contra la captura nativa, no
contra el SVG.**

### H-2 — 48 capturas byte-idénticas, sin distinguir causa {#h-2}

`verify_dupes.py` marca 48 avisos, y ahí conviven tres cosas distintas:

1. **Defectos reales** — `op-mm-mark` ≡ `op-mm-text` ([P-1](#p-1)),
   `br-surface-clear` ≡ `br-surface-theme` ([B-4](#b-4)),
   `static` ≡ `threshold` ≡ `gradient` en el dial ([D-1](#d-1)).
2. **Identidad legítima** — `br-medium` ≡ `br-end-round` ≡ `br-normal` (son los valores
   por defecto), `br-nochip` ≡ `br-crit` (por diseño: CRIT sigue visible sin chip).
3. **Colapso del arnés** — las cuatro `zone-60x60`…`zone-128x96` idénticas, y
   `sc-preset` ≡ `sc-lowgood` (todo el catálogo usa `TX_VOLTAGE` remapeado, así que las
   escenas que se distinguían por *fuente* dejan de distinguirse).

**Remediación:** clasificar cada par en el propio `verify_dupes.py` con una lista de
identidades esperadas; lo que quede sin justificar es señal, no ruido. Hoy 48 avisos sin
triaje equivalen a 0 avisos.

---

## 6. Comprobado y sin hallazgo

- **Contención en zona**: ningún objeto pintado fuera de la zona en las 222 escenas del
  catálogo ni en las 214 capturas nativas (`R-4`, `dev/collide.lua` limpio).
- **Sweeps 270/180/360**: los tres correctos, incluido el cierre del anillo a 359°.
- **`HighGood` On/Off**: invierte las bandas de sección correctamente (`019` vs `020`).
- **Precisión 0/1/2**: `7.9` / `7.90` correctos, ancho de caja reservado.
- **Escala descendente y `warn == crit`**: sin oscilación ni división por cero
  (`021`, `022`).
- **Estados de ausencia** (`NO DATA`, `NO LINK`, `STALE`): geometría, apagado del dato y
  píldora correctos; el texto se lee entero en el firmware real.
- **Colores de estado calibrados** (`#21925a`, `#ce6100`, `#ff0000`): los tres dentro de
  la ventana `[0.189, 0.247]` y ≥ 3.3:1 contra fondo claro **y** oscuro. El contrato de
  color se cumple donde se aplica; los fallos de este informe son colores que **esquivan**
  ese contrato (tema, pulso, carril dual).
- **Reutilización de objetos**: 200 frames estables sin churn en ambas familias
  (`widgets_test`).

---

## 7. Cómo reproducir

```sh
cd WIDGETS/GaugePro
export PATH="$HOME/scoop/shims:$PATH"

# 1. Línea base
lua53 tests/run_tests.lua && lua53 tests/smoke_test.lua && lua53 tests/widgets_test.lua
luacheck . && lua53 dev/collide.lua ./

# 2. Catálogo SVG (árbol de objetos exacto)
lua53 dev/shots.lua ./ <out>/stock --theme stock
lua53 dev/gallery.lua ./ --out <out>/gallery --theme both

# 3. Firmware real (requiere simu con -DWIDGET_STUDIO=ON)
cd ../../tools/gaugepro-visual-kit && python run.py all
```

Rasterizar los SVG con Playwright (no hay cairosvg) y **recortar cada captura nativa a la
zona real del widget** antes de juzgar composición: el simulador es 800×480 y, por
ejemplo, el caso `001` vive en `Layout1P3 z1` = `(400,0,400,160)`. La columna
"Zone (real)" de `CATALOG.md` da la zona de cada caso; `tools/gaugepro-visual-kit/layouts.py`
da la geometría.

Las medidas de píxel de este informe se hicieron cargando el PNG en un `<canvas>` y
haciendo RLE de la scanline con más píxeles no-fondo de la zona.

---

## 8. Orden de ataque recomendado — ejecutado

El plan original se ejecutó en este orden, y cada punto está cerrado y
verificado en [§0](#0-reparaciones-aplicadas):

1. **[B-1]** instrumentar y cerrar el origen cero. La instrumentación en el
   simulador real encontró algo mayor de lo previsto: la causa no estaba en el
   widget sino en la aritmética del firmware ([R-0](#r-0)).
2. **[B-2]** guardián de contraste contra la superficie — cerró de golpe los
   tres presets y protege cualquier tema futuro.
3. **[P-1]** texto min/max en la barra.
4. **[B-3]** carriles inactivos en color de pista.
5. **[P-2]** semántica de Gradient unificada en el core, consumida por las dos
   familias.
6. **[B-4]**, **[B-5]**, **[B-6]**, **[D-1]**, **[D-2]**, **[D-3]**.
7. **[H-1]**, **[H-2]** — el utillaje ya no inventa recortes de texto ni ahoga
   la señal en 48 avisos sin triar.

## 9. Lo que queda para el propietario

Nada de esto es trabajo pendiente del widget; son decisiones que no me
corresponde tomar:

1. **`LUA_FLOORN2I 1` en `radio/src/thirdparty/Lua/src/luaconf.h:164`.** El
   widget ya no depende de esa comparación, pero el resto de scripts Lua del
   fork sí puede. Cambiarlo altera la semántica numérica de todo el firmware;
   la evidencia para decidirlo está en [R-0](#r-0).
2. **`ColorMode = Static`** conserva el verde de acento por defecto, que es
   también el color semántico de "normal". La contradicción está mitigada
   (la píldora siempre anuncia el estado, fijado por el test `P-1b`), pero si
   se prefiere un acento neutro por defecto es un cambio de una línea con
   impacto visible en modelos ya guardados.
3. **Cobertura de fuentes en el emulador.** Las 16 escenas saltadas y los
   grupos de capturas idénticas que quedan se deben todos a que el arnés
   inyecta `TX_VOLTAGE` en lugar de sensores reales (limitación documentada en
   el README del kit). Resolverlo daría cobertura real a CELLS, staleness y
   pérdida de enlace.
