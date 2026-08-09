# GaugePro — auditoría de código (post 1.1)

**Fecha:** 2026-08-05 · **Rama:** `feat/gauge-v2` · **HEAD:** `78e1ecef7`
**Alcance:** únicamente `WIDGETS/GaugePro/` (14 módulos runtime, harness de test, docs y `dev/`).
**Método:** lectura completa del código; contrastación de cada supuesto contra el firmware de
este mismo repo (`radio/src/lua/`, `radio/src/gui/colorlcd/`, `radio/src/thirdparty/lvgl/`);
ejecución de la suite existente y de sondas dirigidas sobre el mock; y **renderizado visual** del
árbol de objetos real en ~70 combinaciones de zona, valor y opción (§7).

**Estado de la suite al auditar:** `run_tests.lua` 36/36 · `smoke_test.lua` 46/46 — todo verde.
Ninguno de los defectos de abajo es una regresión: son huecos de cobertura. Las sondas que los
demuestran están en el apéndice §9; el análisis gráfico, en §7.

---

## Estado de la corrección (2026-08-05)

Cada hallazgo corregido lleva el marcador **✅ CORREGIDO** en su propio encabezado, con una nota
de qué cambió y qué test lo verifica. Progreso por tanda (ver §9 para el orden completo):

- **Tanda 1** (P0-1, P0-2, P0-5, P0-6, P0-4) — ✅ completa.
- **Tanda 2** (P0-3, P0-7, P1-8, P1-9, P1-6, P1-7) — ✅ completa.
- **Tanda 3** (visual) — ✅ **completa**. Todos los hallazgos gráficos (§7) y de
  comportamiento visual (§2) están corregidos: G-2, G-12, G-3, G-4, P1-5, P1-1, G-6, G-7, G-8,
  G-9, P1-2, P1-3, P1-4, G-10, P1-10, P1-11, G-13, G-11. **G-1** y **G-10** verificados
  resueltos como efecto de otras correcciones (ver sus notas). `dev/collide.lua` no reporta
  ninguna colisión en la matriz de 12 zonas, en los extremos de valor ni en los barridos de
  270°/180°/360°.
- **Tanda 4** (rendimiento) — ✅ **completa**. P2-1 (aguja de líneas, sin
  reasignación de lienzo por frame), P2-3 (app + tabla de módulos compartidos:
  13 `loadScript` la primera instancia, 0 las siguientes), P2-2 (escrituras
  agrupadas por objeto y frame: 14 → 10 `lvgl.set` en una transición), P2-4
  (precisión de sensor cacheada por nombre).
- **Tanda 5** (higiene: P3-1 a P3-8) — pendiente.

**Plan de reparación del análisis gráfico (`dev/design-review-response.md`) — ✅ implementado**
(2026-08-05): P0 (aguja afilada en dos líneas + pivote sólido + holgura de valor + badge con
padding/centrado vertical/borde), P1 (ticks ≥ 2 px y rol más claro, rails de referencia a
opacidad 200 con separación de banda, unidad un paso por debajo del valor, compensación óptica
de 1 px), P2 (pista neutra al ~35 %, nombre en la fuente más pequeña). Verificado con
`dev/collide.lua` limpio en la matriz completa y en los tres barridos; suite de regresión ampliada
con 9 tests nuevos (P-A, P-B dial+bar, P-C, P-D, P-E, P2-9, P2-10).

`run_tests.lua` 38/38 · `smoke_test.lua` 88/88 tras las Tandas 3 y 4 y el plan del análisis
gráfico (51 tests nuevos, todos de regresión sobre hallazgos concretos de este informe).

---

## 0. Veredicto

La arquitectura es sólida y por encima de la media del ecosistema: contrato de opciones
verificado contra el firmware, objetos LVGL retenidos con caché de propiedades, histéresis real,
modelo de disponibilidad honesto, y un mock que impone las *allow-lists* de propiedades del C++.
Eso es trabajo serio.

Lo que falla es el **eje "reconfiguración en caliente"**. El widget construye el árbol una vez y
lo actualiza por deltas —correcto— pero la firma que decide *cuándo* reconstruir no incluye el
rango ni el texto del nombre. Todo lo que se deriva del rango en tiempo de construcción
(secciones, rail, marcas de barra, etiquetas de escala) se queda congelado con valores viejos en
cuanto el rango cambia sin cambiar el ancho de la cadena. Ese único fallo de diseño genera 3 de
los 7 defectos P0.

El segundo problema es de **API**: las dos opciones de tipo `SWITCH` se leen con `getValue()`,
que en el firmware espera un `MIXSRC` y no un `swsrc_t`. Interruptor de alerta e interruptor de
reset no funcionan en radio real, y ningún test lo detecta porque el mock hace `getValue` y
`getSourceValue` intercambiables.

El tercer problema sólo aparece al **mirar** el widget, y es el más extenso: §7 documenta 13
defectos gráficos —colisiones de texto sistemáticas, dos modos de color que no se ven, y una
configuración por defecto (`Cels`, `RxBt` 4S) que produce un dial rojo permanente con las
etiquetas de escala equivocadas.

**Recuento:** 7 P0 · 11 P1 · 4 P2 (rendimiento/recursos) · 8 P3 (diseño/mantenibilidad)
· 13 G (gráficos, §7).

---

## 1. P0 — defectos de corrección

### P0-1 · Las opciones `SWITCH` se leen con la API equivocada ✅ CORREGIDO

> **Corregido.** `alerts.lua` y `app.lua` ahora leen con `getSwitchValue()`. Mock
> ampliado con un `getSwitchValue` distinto de `getValue` (`mock.setSwitch`),
> para que un futuro uso de la API equivocada vuelva a fallar en test.
> Verificado por `smoke_test.lua`: *"P0-1: switch options are read with
> getSwitchValue, not getValue"* y *"P0-1: a switch mis-read as a value does
> not silence alerts"*.

`alerts.lua:26-31` · `app.lua:206-215`

```lua
local ok, value = pcall(getValue, id)      -- alerts.lua:29
local ok, value = pcall(getValue, sw)      -- app.lua:209
```

Una opción `SWITCH` se almacena como `swsrc_t` con signo
(`widget.h` `WidgetOption::Switch` → `widgetData->getSignedValue(i)`,
`lua_widget_factory.cpp:155-172`), y el rango incluye **valores negativos**
(`SWSRC_FIRST = -SWSRC_LAST`, `dataconstants.h:464`).
`luaGetValue` (`api_general.cpp:707-724`) interpreta un entero como identificador
**`MIXSRC`**, un espacio de numeración distinto. El resultado es el valor de una fuente
arbitraria (un stick, un trim, un canal) o `nil`.

La API correcta existe desde 2.6: `getSwitchValue(switchIndex)` → `boolean`
(`api_general.cpp:2690`, registrada en `:3190`).

Consecuencia: **el interruptor de alerta y el de reset no hacen lo que dicen en hardware real.**
Peor en el de alerta: `switchActive()` devuelve `true` cuando el `pcall` falla, así que un
interruptor mal leído *arma* las alertas en lugar de silenciarlas.

Corrección:

```lua
local function switchOn(id, onError)
  if not id or id == 0 then return true end
  if type(getSwitchValue) ~= "function" then return onError end
  local ok, v = pcall(getSwitchValue, id)
  if not ok then return onError end
  return v == true
end
```

Nótese la asimetría deliberada: para la alerta `onError = true` (seguir armado), para el reset
`onError = false` (no disparar un reset fantasma).

---

### P0-2 · Un cambio de rango no reconstruye lo que depende del rango ✅ CORREGIDO

> **Corregido.** `widget.rangeSig` se concatena ahora a la firma de layout en
> `app.lua`, así que cualquier cambio de rango fuerza una reconstrucción
> completa (secciones, rails, marcas de barra, etiquetas de escala).
> Verificado por `smoke_test.lua`: *"P0-2: the cell latch rebuilds sections,
> rails and scale labels"*.

`app.lua:148-167` · `layout.lua:341-350`

`layout.signature()` incluye estilo, modo, orientación, flags de visibilidad, `colorMode`,
`sweep`, fuente tipográfica, radio y tamaño de zona — pero **no el rango**. `configure()` calcula
`rangeSig` (`app.lua:148`) y lo usa sólo para resetear historial y suavizado; nunca fuerza una
reconstrucción.

Se construyen a partir de `cfg.min/max/ranges` **una sola vez, en `build()`**:

| Objeto | Fichero |
|---|---|
| arcos de sección (`ColorMode = Sections`) | `renderer.lua:80-95` |
| arcos de rail (`ColorMode = Rail`) | `renderer.lua:109-127` |
| marcas de umbral de la barra | `bar.lua:48-57` |
| etiquetas de extremo de escala | `renderer.lua:257-262` |

Evidencia (sonda 1): fuente `RxBt`, `ColorMode = Sections`. Antes del enganche de celdas la
escala es 0–8.4 V y las secciones están en `135→248 / 248→254 / 254→405`. Tras la primera lectura
de 16.4 V la escala pasa a 13.2–16.8 V y **las secciones siguen exactamente en los mismos
ángulos**. La etiqueta de escala máxima sigue diciendo `8.40` sobre un dial de 13.2–16.8.

No es un caso exótico de baterías: dispara con cualquier edición de `Maximum` que no cambie el
ancho de la cadena más larga (100 → 200 lo reproduce, sonda 3b).

Corrección mínima: concatenar `widget.rangeSig` a la firma en `app.lua:158`. Correcta y barata;
el coste es una reconstrucción completa por cambio de rango, que ocurre como mucho una vez por
vuelo (el enganche de celdas) o al editar opciones.

---

### P0-3 · Las escalas descendentes pierden bandas, rails y marcas ✅ CORREGIDO

> **Corregido.** `renderer.lua` ordena el span de cada banda con un nuevo
> helper `bandSpan()` (`min`/`max` de los dos ángulos) en vez de asumir
> `a2 > a1`; `bar.lua` compara la posición normalizada en vez del valor
> crudo contra `cfg.min/max`. Verificado por `smoke_test.lua`: *"P0-3: a
> descending scale still draws sections, rails and bar marks"*.

`renderer.lua:86` · `renderer.lua:116` · `bar.lua:52`

`geometry.normalize` refleja los rangos invertidos en lugar de intercambiarlos —comportamiento
deliberado y documentado (`geometry.lua:29-36`, `IMPROVEMENT_PLAN.md §6.4`: *"Descending scales
(rate of climb, temperature margin) then work"*). Pero los constructores asumen que el mapeo
valor→ángulo es monótono creciente:

```lua
if a2 > a1 then ... end                                  -- renderer.lua:86, :116
if r.role ~= "normal" and r.to > cfg.min and r.to < cfg.max then   -- bar.lua:52
```

Con `Min = 100, Max = 0` el mapeo se invierte: `angleOf(banda.from) > angleOf(banda.to)` para
todas las bandas, y `r.to > 100 and r.to < 0` nunca es cierto.

Evidencia (sonda extra): con `Min=100 / Max=0` → **0 secciones, 0 rails, 0 marcas**.
Con `Min=0 / Max=100` → 3 secciones, 2 marcas. El arco de valor y la aguja sí se dibujan
correctamente, así que el usuario ve un dial que funciona pero sin ninguna referencia de umbral.

Corrección: comparar por `math.min/max` de los dos ángulos y construir cuando difieran; en la
barra, decidir con la posición normalizada (`G.normalize(r.to, cfg.min, cfg.max)` estrictamente
entre 0 y 1) en vez de con el valor crudo.

---

### P0-4 · `Sweep = 360°` no dibuja el anillo de pista ✅ CORREGIDO

> **Corregido.** `buildTrack()` recorta `endA` igual que `angleOf()`
> (`- 1` cuando `sweep >= 360`). Verificado por `smoke_test.lua`: *"P0-4: a
> 360 degree sweep still draws the background track"*.

`renderer.lua:77-104`

```lua
local endA = L.startAngle + L.sweep      -- 270 + 360 = 630
```

`angleOf()` sí protege el arco de valor (`renderer.lua:68`, `- 1` cuando `sweep >= 360`), pero
`buildTrack` no aplica la misma protección al arco de pista. En el firmware,
`lv_arc_set_bg_end_angle` hace `if (end > 360) end -= 360` **una sola vez**
(`lvgl/src/widgets/lv_arc.c:168`), así que 630 → 270, idéntico a `bgStartAngle`. Y
`lv_draw_arc` retorna inmediatamente con `if (start_angle == end_angle) return;`
(`lvgl/src/draw/sw/lv_draw_sw_arc.c:66`).

Evidencia (sonda 7):

```text
270 deg  start=135 end=405 -> LVGL bg 135..45
180 deg  start=180 end=360 -> LVGL bg 180..360
360 deg  start=270 end=630 -> LVGL bg 270..270   <-- LONGITUD CERO (no se dibuja)
```

Contradice directamente `DOCS.md §5.5` (*"A full ring clamps its end angle to `start + 359` so it
can never close onto its own start (which would render nothing)"*) — el recorte existe para el
indicador pero no para el fondo.

Corrección: `local endA = L.startAngle + L.sweep - ((L.sweep >= 360) and 1 or 0)`.

---

### P0-5 · `cellsApplied` no se limpia al cambiar de fuente ✅ CORREGIDO

> **Corregido.** `widget.cellsApplied = nil` añadido al bloque de reset por
> cambio de fuente. Verificado por `smoke_test.lua`: *"P0-5: cellsApplied
> resets on a source change"*.

`app.lua:225-229` · `app.lua:186-196`

El bloque de reset por cambio de fuente limpia `lastValue`, `state`, `src.cells`, historial,
suavizado y alertas — pero no `widget.cellsApplied`. Como el enganche de celdas está guardado por
`not widget.cellsApplied`, **la segunda fuente de batería del ciclo de vida del widget nunca
recalcula su escala**.

Evidencia (sonda 2): `RxBt` @16.4 V → `cellsApplied = true`, escala 13.2–16.8. Cambio a `Cels`
→ `cellsApplied` sigue `true`, `src.cells = 3` detectado, y `configure()` no se vuelve a ejecutar.

Corrección: añadir `widget.cellsApplied = nil` al bloque de `app.lua:187-196`.

---

### P0-6 · Editar «Name override» no cambia el texto en pantalla ✅ CORREGIDO

> **Corregido.** `updateSourceLabels()` se llama ahora siempre que no hubo
> reconstrucción (no sólo en `sourceChanged`); `setProp` no hace nada cuando
> el texto no cambió, así que la llamada es gratis en el caso común.
> Verificado por `smoke_test.lua`: *"P0-6: editing the Name override updates
> the label without a rebuild"*.

`app.lua:158` · `app.lua:200-202`

```lua
local sig = m.layout.signature(L, cfg) .. ":" .. widget.unitText
```

La firma incorpora `unitText` pero no `nameText`. `updateSourceLabels()` —lo único que reescribe
la etiqueta de nombre— sólo se invoca cuando cambia el id de la fuente (`widget.sourceChanged`).

Evidencia (sonda 3): tras poner `Label = "LINK"`, `widget.nameText == "LINK"` pero el objeto
etiqueta sigue mostrando `"RSSI"`.

Asimétrico e incoherente: `Suffix` sí funciona (por estar en la firma), pero lo hace por la vía
cara —reconstrucción completa del árbol— cuando bastaba un `setProp`.

Corrección: llamar siempre a `updateSourceLabels()` en `M.update` cuando no hubo reconstrucción,
o mantener un `textSig` propio para nombre/unidad/escala y actualizar por deltas.

---

### P0-7 · El historial mezcla unidades en modo batería y en `Cells = Total/Average` ✅ CORREGIDO

> **Corregido.** Nuevo `telemetry.historyTrustworthy(cfg, wasCells)`: los
> hermanos del sensor sólo se usan cuando el valor mostrado es el crudo del
> sensor; en el resto de casos cae al tracker interno (que sí sigue el valor
> mostrado). `app.lua` añade `historySig` (batería + modo de celdas) para
> resetear el historial también en un cambio de modo que no toque
> min/max. De paso se corrigieron P1-8 y P1-9 (mismo área): el interruptor de
> reset ahora llama a `model.resetSensor()` para sensores de telemetría
> reales, y `readHistorySiblings()` sólo cuenta como éxito si al menos una
> lectura fue numérica. Verificado por `smoke_test.lua`: *"P0-7: battery
> percent history…"*, *"P0-7: Cells=Total history…"*, *"P1-8: the reset
> switch resets a real telemetry sensor…"*, *"P1-9: the fallback tracker
> still runs…"*.

`telemetry.lua:175-183`

`readHistorySiblings()` lee `<sensor>-` / `<sensor>+` en crudo y lo escribe en `widget.history`,
sin considerar que `M.refresh` puede haber transformado el valor mostrado después. Las dos
transformaciones que rompen la equivalencia:

- **`Battery = Li-Po/Li-Ion`** (`telemetry.lua:250-260`): el valor pasa a porcentaje 0–100, el
  historial sigue en voltios.
- **`Cells = Total` o `Average`** (`telemetry.lua:222-231`): el valor es el total/media del pack,
  pero `Cels-`/`Cels+` son *por celda* — lo dice la propia documentación del firmware
  (`api_general.cpp:773-775`: *"a `Cels+` or `Cels-` will return a single value - the maximum or
  minimum Cels value"*).

Evidencia (sonda 8): dial 0–100 %, valor `95`, y texto `min 15 / max 17` derivado de
14.8 V / 16.8 V. Los marcadores del dial se dibujan al 15 % y al 17 %.

Corrección: usar los hermanos sólo cuando el valor mostrado sea el valor crudo del sensor
—es decir, `cfg.battery == BATTERY_OFF` y (no es tabla de celdas o `cfg.cells == CELLS_LOWEST`)—
y caer al tracker interno en el resto de casos.

---

## 2. P1 — defectos de comportamiento y visuales

### P1-1 · El pulso crítico deja el arco a opacidad plena al perder el enlace ✅ CORREGIDO

> **Corregido.** En la rama de salida de `renderer.updatePulse()`, la opacidad
> restaurada es ahora la que pide la clave nueva (`muted` → 120, el resto →
> 255) en lugar de `full` siempre. Un gauge atenuado por pérdida de enlace ya
> no vuelve a opacidad plena al cortarse el pulso en el valle. Verificado por
> `smoke_test.lua`: *"P1-1: losing the link mid-pulse leaves the gauge muted,
> not at full"*.

`renderer.lua:484-499`

`applyColors()` fija `opacity = T.opacity.muted` (120) cuando la clave es `"muted"`, y a
continuación `updatePulse()` —en el mismo frame— ve `key ~= "critical"` con `frame.pulse == true`
y lo sobrescribe con `T.opacity.full` (255).

Evidencia (sonda 5): tras perder el enlace estando en el valle del pulso,
`colorKey = "muted"` pero `opacity = 255` en lugar de 120. El estado queda pegado hasta el
siguiente cambio de color.

Corrección: en la rama de salida del pulso, restaurar la opacidad que corresponde a `key`, no
`full`; o mover el pulso *después* del cálculo de opacidad base y hacerlo relativo.

---

### P1-2 · En barra corta el texto de estado se construye con altura 0 ✅ CORREGIDO

> **Corregido.** La fila inferior de la barra se dimensiona ahora con la
> **fuente de estado** (`stateH`), no con `nameH`. El presupuesto vertical
> reserva la fila de estado ANTES que la caja del valor, recorta la barra a su
> mínimo antes de ceder, y sólo elimina la fila cuando la zona no admite ni el
> valor en su fuente más pequeña (XXS) — por debajo de ~44 px de alto, donde
> es físicamente imposible. En las zonas del informe (300 px de ancho,
> h = 44…60) `stateBox.h` es 13 px y `STALE`/`NO LINK`/`WARN`/`CRIT` se ven.
> Verificado por `smoke_test.lua`: *"P1-2: a short bar keeps a real-height
> state row"* (matriz h ∈ {40,44,46,50,55,60} sin cajas degeneradas, y CRIT
> visible en una barra de 44 px).

`layout.lua:294-322`

`nameH` es 0 cuando `showName` es falso, y `L.stateBox` toma su altura de `nameH`
(`layout.lua:314-315`). Cuando la ruta de emergencia de `layout.lua:301-305` desactiva el nombre,
la caja de estado queda con `h = 0` aunque `showState` siga siendo `true`.

Evidencia (sonda 6), zona de 300 px de ancho:

```text
h= 44  showName=false showState=true  stateBox.h=0
h= 46  showName=false showState=true  stateBox.h=0
h= 50  showName=false showState=true  stateBox.h=0
h= 60  showName=true  showState=true  stateBox.h=13
```

Es decir: en cualquier barra de menos de ~55 px de alto, `STALE`, `NO LINK`, `WARN` y `CRIT`
**no se ven**. Justo las zonas donde más importa.

Corrección: derivar `stateBox.h` de `T.fontHeight(L.stateFont)` y condicionar `showState` a que
haya sitio real, no a `nameH`.

---

### P1-3 · Un temporizador transcurrido desborda la caja de valor ✅ CORREGIDO

> **Corregido.** `widestSample()` reserva ahora la anchura **con signo**
> (`"-00:00:00"`, 9 caracteres) en la rama de timer, de modo que `"-00:01:05"`
> cabe sin saltar de línea. Además, el fallback de `pickValueFont()` ya no
> devuelve un ancho de muestra mayor que la región (recortada a la cuerda,
> G-6) cuando ningún cuerpo cabe: el cuadro nunca asoma fuera del anillo.
> Verificado por `run_tests.lua` (*"widest sample covers the scale plus one
> character of slack"*) y `smoke_test.lua`: *"P1-3: an elapsed timer fits its
> value box"*.

`format.lua:45-52`

`widestSample()` devuelve `"00:00:00"` (8 caracteres) para fuentes tipo timer, pero `hms()`
antepone el signo para los transcurridos: `"-00:01:05"` son 9. La caja se reserva con el ancho de
la muestra y `etx_label_create` usa `LV_LABEL_LONG_WRAP` con altura fija, así que el sobrante
salta de línea y se recorta.

Evidencia (sonda 4): caja de 140 px, cadena que necesita ~158 px.

Es el mismo comportamiento —temporizador transcurrido en negativo— que el widget oficial Value y
que `renderer.colorKey` ya trata como `warning` (`renderer.lua:283-285`). El muestreo no se
enteró.

Corrección: `return "-00:00:00"` en la rama de timer.

---

### P1-4 · Cualquier valor fuera de escala desborda igual ✅ CORREGIDO

> **Corregido.** El valor no se recorta a la escala (correcto: un instrumento
> debe decir la verdad), así que la muestra reservada añade **un carácter de
> margen** —el signo `-` delante del texto más ancho del rango—. La caja
> resultante contiene cualquier valor que sea, a lo sumo, un carácter más
> ancho que los extremos de la escala (el caso medido: `1500` en una escala
> 0–100). Verificado por `smoke_test.lua`: *"P1-4: an out-of-scale value fits
> its value box"*. Límite conocido y aceptado: una excursión doble (signo
> opuesto **y** un dígito más, p. ej. `-1500` en una escala 0–100) sigue
> superando el margen.

`format.lua:45-52` (mismo mecanismo)

La caja se dimensiona con `min`/`max`, pero el valor mostrado no está recortado a la escala
(correcto: un instrumento debe decir la verdad). Evidencia (sonda 8h): escala 0–100, valor
1500 → texto de 105 px en una caja de 79 px.

Corrección: reservar con un margen (p. ej. un carácter extra), o `lv_label_set_long_mode` no está
expuesto, así que la vía práctica es sobredimensionar la muestra.

---

### P1-5 · El modo Gradiente queda rojo permanente si `Warning == Critical` ✅ CORREGIDO

> **Corregido.** En `renderer.colorKey`, cuando `lo == hi` (umbrales iguales =
> acantilado deliberado) la rampa de gradiente cae a `data.state` en lugar de
> normalizar sobre un tramo de longitud cero, que `geometry.normalize` resolvía
> a 0 —rojo— para cualquier valor. La barra hereda la corrección (usa el mismo
> `colorKey`). Verificado por `smoke_test.lua`: *"P1-5: gradient with Warn ==
> Crit follows the state, not the red end"*.

`renderer.lua:287-297`

```lua
local lo, hi = cfg.crit, cfg.warn
local t = G.normalize(data.displayValue, lo, hi)
```

`geometry.normalize` devuelve 0 cuando `maximum == minimum` (`geometry.lua:33`). Con los dos
umbrales iguales, `t` es siempre 0 → `grad0` → rojo, para cualquier valor.

Evidencia (sonda 12): valores 10, 50 y 90 sobre una escala 0–100 con `Warn = Crit = 50`
producen los tres `colorKey = grad0`.

---

### P1-6 · `packRange` ignora el modo de lectura de celdas ✅ CORREGIDO

> **Corregido.** El preset `Cell/Cells/Cels/Cel#` lleva ahora `cellsTable =
> true`; `app.lua` sólo aplica `packRange` cuando la fuente no es una tabla
> de celdas o `cfg.cells == CELLS_TOTAL`. `Lowest`/`Average` se quedan en la
> escala de una celda. Verificado por `smoke_test.lua`: *"P1-6: only
> Cells=Total switches a Cels source to the pack-range scale"*.

`app.lua:110-117`

Cuando el preset es de batería y `src.cells > 1`, la escala pasa a rango de **pack**
(`presets.packRange`). Pero el valor mostrado depende de `cfg.cells`, que la rama no consulta.

Evidencia (sonda A), sensor `Cels` con `{4.10, 4.05, 4.00, 3.95}`:

```text
Cells=Lowest   valor=4     escala=13.2..16.8
Cells=Average  valor=4     escala=13.2..16.8
Cells=Total    valor=16    escala=13.2..16.8
```

`Lowest` es el valor **por defecto** de la opción. La configuración por defecto sobre el sensor
de celdas más común deja la aguja clavada en el mínimo.

Corrección: aplicar `packRange` sólo si `cfg.cells == CELLS_TOTAL`, o si la fuente no es una tabla
de celdas (sensor de voltaje de pack tipo `RxBt`/`VFAS`).

---

### P1-7 · El fallback por unidad convierte cualquier sensor de voltios en batería ✅ CORREGIDO

> **Corregido.** `presets.find()` devuelve una copia sin `battery`/
> `cellsTable` cuando la coincidencia viene sólo de la unidad; la
> coincidencia exacta por nombre conserva los flags. Verificado por
> `run_tests.lua`: *"P1-7: an unknown voltage sensor does not inherit
> battery detection"*.

`presets.lua:126-147`

Si el nombre no casa, se busca por unidad y el primer preset con `units = {1}` es `RxBt`, que
lleva `battery = true`. Cualquier sensor en voltios sin nombre conocido hereda detección de
celdas y rango de pack.

Evidencia (sonda 11): un sensor `VBEC` de 5 V → preset 0–8.4 con `battery = true` →
`cellCount(5.0) = 2` → escala 6.6–8.4 V. El BEC queda permanentemente por debajo del mínimo, en
crítico.

Corrección: no propagar `battery` en la coincidencia por unidad (sólo en la coincidencia exacta
por nombre), que es donde el conocimiento del sensor es real.

---

### P1-8 · El interruptor de reset no hace nada en sensores de telemetría ✅ CORREGIDO

> **Corregido junto con P0-7.** `checkResetSwitch()` en `app.lua` llama a
> `model.resetSensor(widget.source.sensorIndex)` cuando la fuente es un
> sensor de telemetría real, antes de limpiar el tracker local. `telemetry.
> resolveSource` ahora también resuelve `sensorIndex` (índice de
> `model.getSensor`, distinto del id `MIXSRC`). Verificado por
> `smoke_test.lua`: *"P1-8: the reset switch resets a real telemetry sensor
> at the radio"*.

`telemetry.lua:272-282` · `app.lua:206-215`

`resetHistory()` pone `h.min/h.max` a `nil`, pero en el mismo frame `M.refresh` llama a
`readHistorySiblings()`, que los rellena otra vez desde los valores que la radio sigue guardando.
Para cualquier sensor de telemetría con hermanos `-`/`+` —el caso normal— el interruptor es un
no-op. El test que lo cubre (`smoke_test.lua:548`) usa una fuente de stick, sin hermanos.

Contradice `DOCS.md §4.7` (*"is cleared by a source change, a range change or the Reset switch"*).

El firmware sí expone la herramienta correcta: **`model.resetSensor(sensor)`**
(`api_model.cpp:1869`, registrada en `:2001`).

Corrección: cuando `s.minId` existe, resolver el índice de sensor y llamar a `model.resetSensor`;
si no, limpiar el tracker interno. Alternativa honesta: documentar que el reset sólo aplica a
fuentes locales.

*(Este defecto es además la causa de que P0-1 no se note en pruebas: aunque el interruptor se
leyera bien, el reset seguiría sin efecto visible en telemetría.)*

---

### P1-9 · El tracker de reserva nunca arranca si los hermanos existen pero no tienen datos ✅ CORREGIDO

> **Corregido junto con P0-7.** `readHistorySiblings()` ahora sólo devuelve
> `true` si al menos una de las dos lecturas fue numérica (`gotAny`).
> Verificado por `smoke_test.lua`: *"P1-9: the fallback tracker still runs
> while siblings resolve but read nil"*.

`telemetry.lua:176-183`

```lua
if not s.minId and not s.maxId then return false end
...
return true
```

Devuelve `true` en cuanto los ids resuelven, aunque ambas lecturas hayan sido `nil`. El fallback
(`trackHistory`) queda desactivado permanentemente.

Evidencia (sonda J): sensor `RSSI` con `RSSI-`/`RSSI+` declarados pero sin valor; tras 5
refrescos con datos válidos, `history.min = nil`, `history.max = nil`, marcadores invisibles.

Corrección: devolver `true` sólo si al menos una de las dos lecturas fue numérica.

---

### P1-10 · La barra no tiene pulso crítico ni chip de estado ✅ CORREGIDO

> **Corregido.** La barra construye ahora el mismo chip de estado que el dial
> (`renderer.updateChip`, extraído del dial y compartido por ambos renderizadores:
> el chip abraza el texto con `chipPad`/`chipHeight`, que ya no son campos
> muertos) y pulsa el relleno a ~1 Hz en crítico, con la misma regla de salida
> del pulso que el dial (P1-1): perder el enlace en el valle deja la barra
> atenuada, no a opacidad plena. El mismo widget comunica la criticidad igual
> en zonas de dial y de barra. Verificado por `smoke_test.lua`: *"P1-10: the
> bar chips and pulses its state like the dial"*.

`bar.lua` · `layout.lua:319-320`

`renderer.updatePulse` no tiene equivalente en `bar.lua`, y `layout.barLayout` calcula
`L.chipPad` y `L.chipHeight` que la barra nunca usa. El resultado es que el mismo widget, con la
misma criticidad, comunica distinto según la forma de la zona. Los campos muertos sugieren que la
paridad se pretendía y se quedó a medias.

---

### P1-11 · Las marcas de umbral de la barra pierden el límite de aviso cuando «bajo es bueno» ✅ CORREGIDO

> **Corregido.** La condición de marcas ya no exige `role ~= "normal"`: marca
> el `to` de **toda** banda cuyo extremo caiga estrictamente dentro de la
> escala (`t > 0 and t < 1`, ya normalizado — descendente incluido). Con
> `highGood = false` el límite de aviso es el `to` de la banda normal, que
> ahora sí se marca: el sensor de temperatura (0/70/90/120) dibuja **2**
> marcas, tantas como rails dibuja el dial del mismo sensor. Verificado por
> `smoke_test.lua`: *"P1-11: low-is-good bars mark the warning boundary
> too"*.

`bar.lua:52`

La condición itera bandas y marca `r.to` de las no-normales. Con `highGood = false` el orden es
`normal → warning → critical`, así que el límite de aviso es el `to` de la banda **normal** y no
se marca; y el `to` de la crítica coincide con `cfg.max`, que la condición excluye.

Evidencia (sonda B), sensor de temperatura (0/70/90/120): la barra dibuja **1** marca, el dial
del mismo sensor dibuja **2** rails (sonda C).

---

## 3. P2 — rendimiento y recursos

### P2-1 · Cada frame de aguja destruye y reasigna dos lienzos LVGL ✅ CORREGIDO

> **Corregido.** La aguja y el contrapeso son ahora **líneas** (`lvgl.line`), no
> triángulos. `LvglWidgetLine::refresh()` sólo reescribe los puntos de la línea
> (`lv_line_set_points`) — sin `malloc`, sin borrar el objeto — mientras que
> `LvglWidgetTriangle::refresh()` liberaba el lienzo, borraba el objeto y
> rehacía `malloc(w*h+4)` en cada cambio de ángulo. La opción 1 del informe:
> se pierde el afilado, se elimina por completo el churn de heap (el único
> hallazgo con riesgo de estabilidad). Verificado por `smoke_test.lua`:
> *"style choice controls the needle"* (el objeto es `line`, no `triangle`).

`renderer.lua:425-430`

```lua
lvgl.set(ui.needle, { pts = G.trianglePoints(...) })
lvgl.set(ui.tail,   { pts = G.trianglePoints(...) })
```

`lvgl.set` → `LvglWidgetObjectBase::update()` → `getParams` + `refresh()`
(`lua_lvgl_widget.cpp:763-767`). Y `LvglWidgetTriangle::refresh()` es
(`lua_lvgl_widget.cpp:1430-1443`):

```cpp
if (mask) { free(mask); mask = nullptr; }
if (lvobj) { lv_obj_del(lvobj); lvobj = nullptr; }   // "May render incorrectly when trying to reuse previous canvas"
color.forceUpdate();
build(nullptr);                                       // malloc(w*h + 4) + rasterizado + lv_canvas_create
```

Con amortiguación activa (`Damping = 4` por defecto) el valor suavizado cambia casi todos los
frames, así que el ángulo cambia casi todos los frames. Medido (sonda E): **46 escrituras sobre
triángulos en 20 frames**, es decir ~2.3 ciclos completos free/`lv_obj_del`/`malloc` por frame.
En una zona de 200×200 el bounding box de la aguja ronda 110×110 → ~12 KB por triángulo, ~24 KB
de churn de heap por frame, en el asignador de una STM32. Es el patrón que produce los fallos de
memoria clásicos de los widgets Lua.

Efectos laterales no evidentes: `lv_obj_del` + recreación **reinicia el flag `LV_OBJ_FLAG_HIDDEN`**
(el objeto reaparece si estaba oculto) y **cambia el z-order** (el objeto recreado pasa al final
de la lista de hijos). Hoy no se manifiesta porque `updateArc` retorna antes de escribir cuando
los datos no son válidos y porque `needleInner > pivotRadius`; es una dependencia frágil y no
documentada.

Correcciones posibles, de menor a mayor coste de rediseño:

1. Sustituir la aguja triangular por `lvgl.line` con `thickness`.
   `LvglWidgetLine::refresh()` (`lua_lvgl_widget.cpp:1140-1145`) sólo rehace `lv_line_set_points`:
   **sin `malloc`, sin borrar el objeto**. Se pierde el afilado, se gana un orden de magnitud.
2. Mantener el triángulo sólo en modo `large` y usar línea en el resto.
3. Cuantizar el ángulo de la aguja (p. ej. 2°) por debajo de modo `large`.

La forma `pts = function` **no** ayuda: `callRefs` hashea el resultado y llama al mismo
`refresh()` cuando cambia (`lua_lvgl_widget.cpp:1195-1210`).

---

### P2-2 · Una escritura de propiedad = un `refresh()` completo del objeto en C++ ✅ CORREGIDO

> **Corregido.** `setProp()` encola ahora las claves sucias por objeto y un
> `flush()` al final de cada entrada pública del frame (el `update` del
> renderizador y el de la barra, y `updateSourceLabels`, que corre desde
> `app.update`) emite **un** `lvgl.set` por objeto. La transición
> normal → crítico pasa de 14 a **10** `lvgl.set` (la aguja añade 2 directos
> por `pts`, que no pueden pasar por la caché porque las tablas se comparan
> por referencia). La caché sigue filtrando claves sin cambio y se actualiza
> de inmediato, así que las lecturas del mismo frame ven el valor nuevo.
> Verificado por `smoke_test.lua`: *"P2-2: a state transition batches one
> lvgl.set per object"* (color+opacidad+ángulo del arco salen en una sola
> llamada).

`renderer.lua:45-58`

`setProp` escribe **una** clave por llamada a `lvgl.set`. Cada llamada dispara
`getParams` + `refresh()`, y para un arco `refresh()` reaplica ángulos, colores, radio, posición
y tamaño (`lua_lvgl_widget.h:653-662` + `LvglWidgetRoundObject::refresh`).

Medido (sonda F): **14 llamadas a `lvgl.set` en una sola transición de estado** (normal →
crítico), sobre 6 objetos distintos. Agrupando las claves sucias por objeto en una única tabla se
bajaría a ~6, con la misma semántica de caché.

Corrección: acumular en `scratch` por objeto y hacer un único `lvgl.set` al final del frame
(`flush`), en vez de emitir por propiedad.

---

### P2-3 · Cada instancia del widget carga 13 chunks propios ✅ CORREGIDO

> **Corregido.** `main.lua` memoiza ahora el resultado de cargar `app.lua`
> (un upvalue compartido por todas las instancias, que es exactamente cómo el
> firmware ejecuta `main.lua` una sola vez) y `app.lua` memoiza la **tabla de
> módulos** por ruta. La primera instancia carga los 13 chunks; la segunda
> carga **0**, y comparten los módulos —incluidas las cachés de métricas de
> `theme`, que ahora memoizan entre instancias. Los `setup()` siguen siendo
> idempotentes y toda la estado por widget vive en `widget`. Verificado por
> `smoke_test.lua`: *"P2-3: the module table is shared between instances"*.

`main.lua:131-141` · `app.lua:23-41,60-63`

Medido (sonda 9): **13 llamadas a `loadScript` por instancia** (`app.lua` + 12 módulos). El
firmware carga `main.lua` una sola vez y comparte sus upvalues entre todas las instancias
(`luaLoadWidgetCallback`, `widgets.cpp:100`), así que la duplicación es evitable por completo.

Cuatro GaugePro en una pantalla = 52 chunks, 52 tablas de módulo y cuatro copias independientes de
`theme.widthCache`/`heightCache` (que además deja de memoizar entre instancias).

Corrección: memoizar `app` y la tabla de módulos en un upvalue de `main.lua`. Es seguro:
`layout.setup()`, `renderer.setup()` y `bar.setup()` son idempotentes y sólo guardan referencias a
los mismos módulos.

---

### P2-4 · `sensorPrecision` recorre 60 sensores creando 60 tablas Lua ✅ CORREGIDO

> **Corregido.** `findSensor()` memoiza en una tabla de módulo cada acierto
> `nombre → {prec, índice}`, así que el barrido de 60 sensores ocurre una vez
> por nombre de sensor por modelo, no en cada resolución de fuente. Como los
> módulos ahora se comparten entre instancias (P2-3), la caché también. Sólo
> se cachean los **aciertos**: un sensor aún no conectado se vuelve a
> escanear cuando aparece, así que nunca se cachea un fallo. Verificado por
> `smoke_test.lua`: *"P2-4: a second source resolution does not rescan the
> sensor table"*.

`telemetry.lua:82-92`

Medido (sonda I): **60 llamadas a `model.getSensor` por resolución de fuente**. Cada una
construye una tabla nueva con 5–6 campos (`api_model.cpp:1834-1856`). Ocurre en cada `update()`
con fuente nueva, y `update()` también se dispara al redimensionar la zona
(`lua_widget.cpp:425-444`).

Está dentro del presupuesto (20 000 instrucciones VM por llamada,
`widgets.cpp:37` + `luaHook`), pero es gasto gratuito. Memoizar `nombre → prec` en una tabla de
módulo lo reduce a una pasada por modelo.

---

## 4. P3 — diseño, mantenibilidad y fidelidad de tests

### P3-1 · `main.lua` y `options.lua` implementan dos veces el mismo contrato

`main.lua:110-129` (build + translate inline) vs `options.lua:57-86` (`M.build`, `M.translator`).

**El firmware sólo ejecuta la copia de `main.lua`. La suite sólo prueba la de `options.lua`.**
`run_tests.lua:247-259` valida `options.build`, que en producción no se llama nunca. Las dos
copias pueden divergir sin que nada lo detecte. El comentario de `main.lua:98-99` justifica la
duplicación por coste de arranque, lo cual es razonable — pero entonces el test debe apuntar a la
copia real (`mod.options`, como sí hace `smoke_test.lua:114-130`) y `options.build` debería
eliminarse o quedar marcado como referencia no ejecutada.

---

### P3-2 · `Minimum/Maximum/Warning/Critical` son enteros

`main.lua:46-53` (`type = VALUE` → `WidgetOption::Integer` → `NumberEdit`)

El usuario no puede escribir `4.2`. Con `Scale = Manual` —el modo que el propio `DOCS.md §4.2`
propone para «hacer explícita la relación»— es imposible configurar a mano cualquier escala de
voltaje, que es justo el terreno donde el widget presume de presets. La restricción viene del
firmware, no del widget, pero el diseño la ignora.

Opciones: almacenar en centésimas y dividir al leer (rompe el contrato posicional si se cambia el
tipo — habría que **añadir** opciones nuevas, nunca reinterpretar las existentes), o exponer un
`CHOICE` de rangos predefinidos por química.

---

### P3-3 · Las métricas de fuente del mock no reproducen el orden real

`tests/mock_env.lua:167-179`

```lua
if flags >= 0x600 then h = 48    -- XXLSIZE(0x600) y XLSIZE(0x700) reciben lo mismo
```

Orden real (`gui/colorlcd/fonts.h`, `FontIndex`):
`XXS(0x200) < XS(0x300) < STD(0x000) < L(0x400) < XL(0x500) < LXL(0x700) < XXL(0x600)`.
El `XLSIZE` de Lua es `FONT_LXL` — *"Halfway between XL and XXL"*.

El orden de `theme.RAMP` es **correcto** para hardware real; el problema es que el mock da a sus
dos candidatos superiores la misma altura (48/48, sonda 13), así que el buscador de ajuste
automático nunca los distingue en test. Cualquier bug de selección entre XXL y XL es invisible.

---

### P3-4 · `theme.RAMP` salta `STDSIZE` y `pickValueFont` degrada en silencio

`theme.lua:41-43` · `layout.lua:75-95`

La rampa va `MIDSIZE(24) → SMLSIZE(13)`, un salto de casi 2× con `STDSIZE(16)` disponible y
declarado (`theme.FONTS.S`) pero fuera de la rampa. Además, si `cap` no pertenece a la rampa,
`started` nunca se activa y la función cae al **más pequeño** de todos en vez de al tope pedido.
Hoy los tres `cap` usados están en la rampa; es una trampa esperando a la próxima edición.

---

### P3-5 · Código y tokens muertos

| Elemento | Fichero |
|---|---|
| `ratio.unitToValue` (nunca leído; el tamaño de unidad sale de `smallerFont(font, 2)`) | `theme.lua:69` |
| `M.fitFont` (sustituido por `pickValueFont`) | `theme.lua:116-121` |
| `FONTS.S` | `theme.lua:34` |
| `L.chipPad` / `L.chipHeight` en modo barra | `layout.lua:319-320` |
| `history.fromSensor` (se escribe, nunca se lee) | `telemetry.lua:281` |
| `options.M.present` | `options.lua:142-145` |
| `options.M.build` / `M.translator` / `M.capacity` (ver P3-1) | `options.lua:43-86` |
| `M.tickPoints` (alias de `linePoints`, sin uso) | `geometry.lua:54` |

---

### P3-6 · `bar.lua` reimplementa la resolución de color

`bar.lua:154-172` duplica la lógica de `renderer.resolveColor` (`renderer.lua:301-308`), que es
local y no está exportada. La deriva ya es visible: la barra no tiene pulso (P1-10). Exportar
`resolveColor` y consumirlo desde ambos renderizadores.

---

### P3-7 · `cleanName` destruye nombres UTF-8 legítimos

`telemetry.lua:47-54`

El bucle elimina **todos** los bytes iniciales `> 127`, no sólo el carácter inválido conocido de
ciertas versiones de firmware. Un sensor con nombre acentuado o no latino pierde su primer
carácter (o más). Acotar a un solo byte, o comprobar contra el patrón concreto que se pretende
limpiar.

---

### P3-8 · `dev/sync-sd.ps1` no limpia los `.luac` obsoletos

`dev/sync-sd.ps1:16-30`

`loadScript(..., "bt")` hace que el firmware **compile cada módulo a `.luac` en la SD** en el
primer arranque y luego prefiera el binario cuando su fecha sea igual o posterior a la del
fuente (`interface.cpp:481-500`). `Copy-Item` conserva `LastWriteTime` del origen, así que
desplegar una revisión con fecha anterior a la del `.luac` existente hace que **la radio siga
ejecutando el código viejo**, sin ningún aviso.

Corrección: `Remove-Item (Join-Path $target '*.luac') -Force -ErrorAction SilentlyContinue` antes
de copiar. Añadir también `*.luac` al `.gitignore`.

---

## 5. Deriva de documentación

| `DOCS.md` | Realidad |
|---|---|
| §4.7 «cleared by … the Reset switch» | No para sensores de telemetría (P1-8). |
| §4.8 «rebuilt once, to `cells × [3.0 … 4.2] V`» | `packRange` usa `chem.empty = 3.3` → 4S = **13.2**–16.8 V, no 12.0 (`presets.lua:157,204-206`). |
| §5.5 «A full ring clamps its end angle to `start + 359`» | Sólo el arco de valor; la pista no (P0-4). |
| §5.4 «Per-frame writes: … needle/tail `pts`» | Cierto, pero omite que en firmware cada una destruye y reasigna el lienzo (P2-1). |

---

## 6. Lo que está bien y no hay que tocar

Merece decirse explícitamente, porque es la parte cara de acertar:

- **El contrato de opciones.** 1-based, posicional, tipado, con capacidad por versión — todo
  verificado línea a línea contra `widget_settings.cpp:193-201`, `widget.cpp:76-86` y
  `lua_widget_factory.cpp:291`. La tabla de nombres como default de `SOURCE` es idiomática
  (`lua_widget_factory.cpp:175-192`, «find first available»). El guardado de compatibilidad de
  `main.lua:27-37` es el patrón correcto.
- **El mock que impone las allow-lists del C++.** `tests/mock_env.lua:33-52` reproduce las cadenas
  de `parseParam` reales, incluido que `lvgl.triangle` sólo acepte `pts`, que `dashGap`/`dashWidth`
  vivan en `LvglWidgetLineBase` y no en `LvglWidgetLine`, y que no exista metatabla de strings.
  Eso es fidelidad poco común y ha evitado bugs reales.
- **Histéresis y modelo de disponibilidad.** `ranges.determineState` degrada al instante y mejora
  con banda muerta; el test de rampa ruidosa (`run_tests.lua:157-169`) es el correcto.
- **Peso de arranque.** `main.lua` sólo declara y carga `app.lua` bajo demanda; el coste por
  radio que no usa el widget es un fichero.
- **Independencia del frame rate en el suavizado**, con la conversión explícita de ticks de 10 ms
  a milisegundos (`smoothing.lua:46`).
- **`lcd.sizeText` y `lcd.RGB` son seguros fuera del ciclo de dibujo** —no comprueban
  `luaLcdAllowed`/`luaLcdBuffer` (`api_colorlcd.cpp:262-269`, `:1000-1016`)—, así que llamarlos
  desde `update()` con `dc == nullptr` es correcto. Lo verifiqué porque era un fallo plausible; no
  lo es.

---

## 7. Análisis gráfico

### 7.0 Cómo se generó, y por qué la previsualización existente engaña

`dev/preview.lua` renderiza el árbol de objetos LVGL real a SVG. Es una herramienta excelente,
pero **dibuja los ángulos que el widget pidió, no los que LVGL dibuja**, y no modela el recorte
de las etiquetas. Por eso el anillo ausente en `Sweep = 360°` (P0-4) y todos los desbordes de
texto llevaban meses siendo invisibles en la revisión visual.

Para esta auditoría se añadieron dos herramientas junto a ella:

| Herramienta | Qué añade |
|---|---|
| `dev/audit-preview.lua` | Normaliza los ángulos como `lv_arc_set_*_angle` (`-= 360` **una sola vez**), descarta los arcos de longitud cero como `lv_draw_arc`, y emula `LV_LABEL_LONG_WRAP` (ajuste al ancho + recorte a la altura), marcando en rojo toda etiqueta que desborda. ~70 casos. |
| `dev/collide.lua` | Prueba geométrica del árbol real: solapes etiqueta/etiqueta, etiqueta/anillo y etiqueta/marca, más cajas degeneradas. Es la comprobación que falta en la suite: los tests de layout sólo verifican que los objetos estén **dentro de la zona**, nunca que no se pisen entre sí. |

```sh
lua5.3 dev/audit-preview.lua ./          # -> dev/audit-preview.html
lua5.3 dev/collide.lua       ./          # -> informe de colisiones
```

---

### 7.1 Defectos que hacen el widget engañoso

#### G-1 · `Cels` y `RxBt` por defecto: dial rojo permanente y escala equivocada ✅ CORREGIDO

> **Verificado resuelto por P0-2 + P1-6.** Sus dos causas ya están corregidas:
> P0-2 reconstruye las secciones/etiquetas al cambiar el rango y P1-6 mantiene
> `Cels`/`RxBt` en la escala correcta según `Cells`. La sonda confirma que
> `RxBt` 16.4 V dimensiona la caja del valor para `16.40` (132 px de caja,
> 132 px de texto) y que `Cels` por defecto queda en `normal` con la escala de
> celda única.

**El caso más grave de todo el informe, y es la configuración por defecto del sensor de baterías.**

Fuente `Cels`, todas las opciones por defecto (`Cells = Lowest`, `Scale = Auto`), celdas
`{4.10, 4.05, 4.00, 3.95}`:

| Lo que se ve | Lo que debería verse |
|---|---|
| Valor `3.95 V` (correcto) | `3.95 V` |
| Etiquetas de escala `3.00` … `4.20` | `13.20` … `16.80` |
| Chip **CRIT**, anillo entero rojo | Normal (3.95 V está sobre el aviso de 3.7) |

Es la superposición de dos defectos: **P1-6** cambia la escala efectiva a rango de pack
(13.2–16.8 V) sin mirar que `Cells = Lowest` muestra un valor **por celda**, de modo que 3.95 cae
muy por debajo del mínimo y el estado es crítico para siempre; y **P0-2** deja las etiquetas de
escala congeladas en los valores previos al enganche de celdas.

Con `Cells = Total` el valor (16.10 V) sí encaja en la escala, pero entonces se manifiesta la
tercera consecuencia de P0-2: la caja del valor se dimensionó con la muestra anterior (`4.20`,
4 caracteres) y el texto real (`16.10`, 5 caracteres) **se recorta a `16.`**.

El mismo patrón con `RxBt` a 16.4 V: etiquetas `0.00` … `8.40` sobre un dial de 13.2–16.8 V,
arco pegado al fondo de escala y valor recortado a `16.`.

#### G-2 · El modo `Sections` es invisible ✅ CORREGIDO

> **Corregido.** Las secciones se dibujan ahora en `L.railRadius` (el mismo
> radio que Rail) con `bgOpacity = 255`, en vez de compartir el radio y
> grosor del arco de valor a 64/255 (25 %). `buildTrack()` construye
> siempre un `ui.track` de fondo, y añade las bandas de Sections como un
> anillo exterior encima. Verificado por `smoke_test.lua`: *"G-2: Sections
> bands sit outside the value arc, at full opacity"*.

Medido sobre el árbol real (sonda A del apéndice), **antes** de la corrección:

```text
section 1..3   r=68  th=12  bgOpacity=64   opacity=0     <- creadas #1..#3
valueArc       r=68  th=12  bgOpacity=0    opacity=255   <- creado #18, pinta encima
rail (Rail)    r=78  th=4   bgOpacity=255                <- otro radio, opaco: sí se ve
```

Dos causas acumuladas:

1. las bandas usaban **el mismo radio y el mismo grosor** que el arco de valor, que se crea
   después y las tapaba por completo por debajo del valor actual;
2. lo poco que asomaba por encima del valor se dibujaba al **25 % de opacidad**
   (`T.opacity.rail = 64`), sobre fondo oscuro casi imperceptible.

A valor 78 sobre 100, `Sections` era **pixel a pixel idéntico** a `Static`. El modo `Rail` no
tenía este problema: radio distinto (78 vs 68) y opacidad 255 — el modelo que ahora sigue
`Sections` también.

#### G-3 · Un temporizador transcurrido dice `CRIT` en color de aviso ✅ CORREGIDO

> **Corregido.** `renderer.stateText()` trata ahora el temporizador transcurrido
> como `warning` —la misma clasificación que `colorKey()`— en vez de leer el
> `data.state` crudo, que es `critical` porque un valor negativo cae por debajo
> del mínimo de la escala. El chip dice `WARN` en ámbar, coherente con el arco.
> La barra hereda la corrección (`bar.lua` usa `renderer.stateText`).
> Verificado por `smoke_test.lua`: *"G-3: an elapsed timer says WARN, not CRIT
> in warning colour"*. Sigue pendiente la nota de diseño: un timer sobre la
> escala 0–100 por defecto sigue siendo un dial sin sentido (aguja clavada).

```text
data.state = critical   colorKey = warning   chip = "CRIT"
stateLabel color = 16385 (COLOR_THEME_WARNING)
```

`colorKey` trata el timer transcurrido como `warning` (`renderer.lua:283-285`), pero `stateText`
lo lee de `data.state`, que es `critical` porque un valor negativo cae por debajo del mínimo de
la escala. La palabra **CRIT dibujada en ámbar** es lo peor de los dos mundos.

Además, un timer sobre la escala por defecto 0–100 es un dial sin sentido: el valor está en
segundos, así que la aguja vive clavada en un extremo. El texto es correcto; el instrumento no.

#### G-4 · Una escala manual con rango negativo queda toda en crítico ✅ CORREGIDO

> **Corregido.** `ranges.saneThresholds()` detecta cuando **ambos** umbrales
> caen fuera de `[min, max]` por el mismo lado —el `clamp` de `build()` los
> colapsaba sobre el mismo extremo y la banda crítica pasaba a ser toda la
> escala— y los deriva al 35 % / 55 % del tramo (espejado para `High is good =
> false`), las proporciones que usan los presets. Se aplica en
> `app.configure()` sobre los umbrales efectivos, así que `cfg.warn/crit`,
> bandas, estado, rail, secciones y el modo Gradiente comparten los mismos
> valores derivados. Un par igual **dentro** del rango se deja intacto (un
> acantilado deliberado). Verificado por `run_tests.lua`: *"G-4: both
> thresholds out of range derive at the presets' proportions"* y
> `smoke_test.lua`: *"G-4: out-of-range thresholds do not leave the dial born
> critical"*.

`Min = -120, Max = 0` (el caso RSSI en dBm, que los propios presets definen) con los umbrales por
defecto 55/35: `ranges.build` recorta ambos a 0, la banda crítica pasa a ser `-120..0` —toda la
escala— y las bandas de aviso y normal quedan de ancho cero. **El dial nace permanentemente
rojo** y no hay forma de notarlo salvo mirándolo.

#### G-5 · `Static` no da ninguna pista de color en crítico

En `ColorMode = Static` el arco y el número siguen en color de acento aunque el estado sea
crítico; el único aviso es el chip `CRIT`, de 13 px. Es coherente con el nombre del modo, pero
significa que un usuario que eligió "un color fijo" pierde toda la señalización de umbral.
Merece al menos que el chip use el color de estado.

---

### 7.2 Colisiones de texto (medidas, no estimadas)

`dev/collide.lua` sobre la matriz de zonas, valor 78, `ShowMinMax = "Markers + text"`:

```text
 60x60    LABEL/RING   "78" cruza un arco (r=15, th=4)
 80x60    LABEL/RING   "78" cruza un arco (r=15, th=4)
100x100   LABEL/RING   "dB" cruza un arco (r=34, th=7)
128x96    LABEL/RING   "dB" cruza un arco (r=32, th=6)
160x160   LABEL/RING   "dB" cruza un arco (r=51, th=11)
200x160   LABEL/RING   "dB" cruza un arco (r=51, th=11)
200x200   LABEL/LABEL  "min 31" x "0"    solape 6x8 px
          LABEL/LABEL  "max 92" x "100"  solape 18x8 px
          LABEL/RING   "dB", "min 31" cruzan arcos
          LABEL/TICK   "min 31", "max 92", "100", "dB" cruzados por marcas
260x220   LABEL/LABEL  "min 31" x "0"    solape 6x5 px
          LABEL/LABEL  "max 92" x "100"  solape 18x5 px
          LABEL/RING   "dB", "min 31", "max 92" cruzan arcos
480x272   LABEL/TICK   "100" cruzado por una marca
```

#### G-6 · La unidad cruza el anillo en 6 de 12 zonas ✅ CORREGIDO

> **Corregido.** La región del valor en modo balanceado se recorta ahora a la
> **cuerda** del círculo en el borde inferior de la banda (no al ancho de la
> caja del dial), con 1 px de margen para el redondeo, y la banda sube un poco
> (micro centrada en el círculo, compacta al 50 %, normal/large al 45 %). De
> paso: `placeValue()` no cuenta la unidad dos veces (el hueco ya venía en
> `uw`), y una unidad que no se dibuja (micro) ya no reserva ancho. El árbol
> real ya no muestra ninguna colisión valor/unidad vs anillo en la matriz de
> 12 zonas, ni en extremos de valor ni en los barridos (verificado con
> `dev/collide.lua`). Verificado por `smoke_test.lua`: *"G-6: the value and
> unit stay inside the ring in balanced zones"*.

`placeValue` (`layout.lua:106-122`) centra el grupo *valor + unidad* en una región tan ancha como
la caja del dial. Pero a la altura donde se dibuja (52–82 % de la caja) el hueco interior del
círculo es una **cuerda**, más estrecha que `dial.w`. La unidad, que va a la derecha del número,
cae sistemáticamente sobre el anillo.

Empeora con el ancho de la cadena: `5400`, `78.00` y `5400.00` cruzan el anillo por ambos lados,
y `78.00` en zona micro queda con el `7` partido por el arco.

#### G-7 · `min/max` choca con las etiquetas de escala en todas las zonas grandes ✅ CORREGIDO

> **Corregido.** La fila `min/max` (que cuelga bajo el valor, dentro del
> círculo) se recorta ahora a la **cuerda** del anillo a su profundidad con el
> mismo `clipToChord()` que usa el valor (G-6). Con la banda del valor más
> arriba (G-6) el solape `LABEL/LABEL` con las etiquetas de escala ya no se
> produce, y el recorte elimina además el cruce con el anillo y con las marcas
> de historial que apuntan a la misma banda inferior. `dev/collide.lua` ya no
> reporta ninguna colisión `LABEL/LABEL` ni `LABEL/RING` en la matriz de
> zonas. Verificado por `smoke_test.lua`: *"G-7: the min/max row stays inside
> the ring and off the scale labels"*.

18 px de solape horizontal en 200×200 y 260×220. Es precisamente la combinación que la
documentación promociona (`large` + `Markers + text`): `L.minMaxBox` y las etiquetas de extremo
se disputan la misma banda inferior sin ninguna comprobación entre ellas.

#### G-8 · La etiqueta de escala superior siempre la cruza su propia marca ✅ CORREGIDO

> **Corregido.** Cada etiqueta de escala se empuja ahora hacia fuera a lo
> largo de su radio hasta que la **esquina más cercana** al centro queda a
> `tickOuter + px(sm)`. Al quedar todo el cuadro a distancia ≥ ese radio, la
> marca (que termina dentro de `tickOuter`) no puede tocarlo, en cualquier
> ángulo del arco. `dev/collide.lua` ya no reporta `"100"` cruzado por su
> marca en la matriz de zonas ni en los barridos de 270°. Verificado por
> `smoke_test.lua`: *"G-8: the scale end labels sit clear of their end
> ticks"*.

En todas las zonas `large`, incluida pantalla completa. La caja de la etiqueta se **centra** en un
punto a `tickOuter + px(sm)` (`layout.lua:262-269`), así que su mitad interior retrocede sobre la
marca. Visualmente `100` se lee como `f00`.

#### G-9 · La caja de las etiquetas de escala es de ancho fijo ✅ CORREGIDO

> **Corregido.** Cada caja se dimensiona ahora con `T.textWidth` de su propio
> texto (`"20000.00"` → 48 px en lugar de 30), medida exacta de lo que el
> renderizador va a imprimir con la misma fuente. Sin recorte ni salto de
> línea. Verificado por `smoke_test.lua`: *"G-9: scale labels size their box
> to the text, not a fixed width"*.

`local sw = T.px(30)` (`layout.lua:267`), independientemente de la cadena. Con `Max = 20000` y dos
decimales, `20000.00` (48 px) se recorta a `2000`. Debe medirse con `T.textWidth`.

#### G-10 · En `Sweep = 360°` el nombre se dibuja sobre el anillo ✅ CORREGIDO

> **Verificado resuelto por G-6.** La corrección G-6 subió la banda del valor
> dentro del círculo (45 % de la caja en normal/large), y el nombre cuelga
> ahora justo debajo de ella, dentro del radio interior: ni el nombre ni el
> valor cruzan el anillo, y no se superponen entre sí (2 px de separación).
> Comprobado con la comprobación etiqueta-vs-arco de `dev/collide.lua` en
> 360° sobre las tres zonas `large` (200×200, 260×220, 480×272): limpio en
> todas. Verificado por `smoke_test.lua`: *"G-10: at 360 degrees the name
> stays inside the ring and off the value"*.

`LABEL/RING "RSSI" cruza un arco (r=68, th=12)`. La rama de 360° mete el nombre bajo el valor,
dentro del círculo (`layout.lua:242-247`), y a ese radio el anillo pasa justo por ahí. En la
captura el nombre y el valor se leen como una sola mancha.

#### G-11 · En `Sweep = 180°` ambas etiquetas de escala las cruzan las marcas ✅ CORREGIDO

> **Corregido.** La corrección G-8/G-9 ya había apartado la etiqueta inferior
> de su marca; la superior seguía cruzándola cuando el borde de la zona
> (200×200, arco de 180° que termina a las 3 en punto) obligaba al recorte a
> devolver el cuadro sobre la marca. Ahora, si tras el recorte a la zona el
> cuadro sigue intersectando la marca de extremo, la etiqueta se **desliza por
> la tangente** (perpendicular al radio) hasta despejarla, en la dirección que
> quepa en la zona. `dev/collide.lua` ya no reporta ninguna colisión en 180°
> (ni en 200×200 ni en 480×272). Verificado por `smoke_test.lua`: *"G-11: at
> 180 degrees both scale labels clear their end ticks"*.

Los extremos del arco caen a las 9 y a las 3 en punto, exactamente donde están las marcas
extremas.

---

### 7.3 Superposiciones y aprovechamiento del espacio

#### G-12 · En la barra, las marcas de umbral quedan **bajo** el relleno ✅ CORREGIDO

> **Corregido.** `bar.build()` crea ahora `ui.fill` antes que `ui.marks`, así
> que las marcas pintan encima del relleno en vez de debajo. Verificado por
> `smoke_test.lua`: *"G-12: bar threshold marks paint on top of the fill,
> not under it"*.

Orden de creación medido (`bar.build`), **antes** de la corrección: `marks = #2,#3` → `fill = #4`
→ `ghost = #5` → `minMark = #6`. Con valor 78 sobre 100 el relleno ocupaba `x = 4..232` y las dos
marcas estaban en `x = 106` y `x = 165`: **ambas tapadas**.

Era el mismo error de capas que G-2, con el mismo efecto perverso: las referencias de umbral
desaparecían justo cuando el valor se acercaba a ellas.

#### G-13 · Las orientaciones vertical y horizontal desperdician el 70 % de la zona ✅ CORREGIDO

> **Corregido (horizontal; vertical verificado como límite geométrico).** La
> rama horizontal ya no capa el dial a `min(w*0.5, h)`: el dial crece hasta la
> **altura completa** de la zona y la columna de texto se queda sólo con el
> ancho que necesita (suelo `max(px(120), 0.28·w)`, y el `max()` con la regla
> anterior garantiza que ningún dial pequeño pierda tamaño). En 480×272 el
> anillo pasa de ~210 a **234 px** (27 % → 32 % del área), el máximo geométrico
> para un dial redondo en esa zona. En vertical (100×260, 120×220) el dial ya
> estaba limitado por la anchura de la zona: el 18 % es inherente a un redondo
> en un rectángulo 2.6:1 y no mejora sin deformar el instrumento. Verificado
> por `smoke_test.lua`: *"G-13: a wide horizontal zone grows the dial to the
> full height"*.

Diámetro del anillo frente a la zona, medido:

```text
zona      modo      orientación  Ø anillo   % del lado corto   % del área
 60x60    micro     balanced        38          63 %              32 %
100x100   compact   balanced        78          78 %              48 %
200x200   large     balanced       156          78 %              48 %
300x150   normal    horizontal     126          84 %              28 %
120x220   normal    vertical        96          80 %              27 %
100x260   compact   vertical        78          78 %              18 %
480x272   large     horizontal     210          77 %              27 %
```

En `100x260` el instrumento ocupa el **18 %** del área: un dial de 78 px de diámetro en una zona
de 26 000 px². La causa es que las ramas vertical y horizontal reservan una caja cuadrada para el
dial y dejan el resto a un bloque de texto que no lo necesita. En `Sweep = 180°` es aún peor: el
arco sólo usa la mitad superior de una caja cuadrada, así que la mitad inferior queda vacía por
construcción.

---

### 7.4 Lo que el renderizado confirma que **sí** funciona

Conviene decirlo, porque es la mayoría de lo que se ve:

- **El ajuste automático de fuente es sólido.** `78` → `780` → `5400` → `78.00` → `5400.00`: la
  rampa reduce el cuerpo y el número siempre cabe a lo ancho. El problema no es el ajuste, es la
  región contra la que ajusta (G-6).
- **La caja de valor fija cumple su promesa**: las cifras no bailan al cambiar el valor.
- **Las transiciones de banda son limpias** en el barrido 0→100: rojo+CRIT hasta 34, ámbar+WARN
  de 36 a 54, acento sin chip a partir de 56.
- **Los estados de disponibilidad se distinguen bien**: `STALE`, `NO LINK` y `NO SOURCE` tienen
  chip propio y el gauge se atenúa, conservando el último valor conocido.
- **El modo `Rail`** es el mejor de los cinco: radio propio, opacidad plena, no compite con el
  arco de valor. Es el modelo que `Sections` debería seguir.
- **La barra** en zonas anchas es legible y honesta; con altura suficiente (≥ 60 px) muestra
  nombre y estado correctamente.

---

## 8. Orden de trabajo propuesto

**Tanda 1 — corrección (rompe funcionalidad prometida hoy)**
P0-1 (interruptores) · P0-2 (firma de rango) · P0-5 (`cellsApplied`) · P0-6 (nombre) ·
P0-4 (anillo 360°). Las cinco son cambios de pocas líneas.

**Tanda 2 — corrección con decisión de diseño**
P0-3 (escalas descendentes) · P0-7 y P1-8/P1-9 (semántica de historial, junto con
`model.resetSensor`) · P1-6 y P1-7 (baterías: `packRange` vs modo de celdas, y no heredar
`battery` por unidad).

**Tanda 3 — visual: engaño primero, estética después**
Lo que hace mentir al instrumento: G-1 (`Cels`/`RxBt` rojo permanente — se resuelve casi entero
con P0-2 + P1-6) · G-2 (capas y opacidad de `Sections`) · G-12 (capas de las marcas de la barra;
crear el relleno antes) · G-3 (CRIT en ámbar del timer) · G-4 (umbrales fuera de rango) ·
P1-5 (gradiente degenerado) · P1-1 (pulso).
Después la legibilidad: G-6 (región de valor = cuerda, no ancho de caja) · G-7 (banda inferior
compartida) · G-8/G-9 (etiquetas de escala: centrado sobre la marca y ancho fijo de 30 px) ·
P1-2 (barra corta) · P1-3/P1-4 (desbordes de texto) · G-10 (nombre sobre el anillo en 360°) ·
P1-10/P1-11 (paridad de la barra).
Por último, aprovechamiento: G-13 (vertical/horizontal usan el 18–28 % de la zona) y G-11.

**Tanda 4 — rendimiento**
P2-1 (aguja: es el único con riesgo de estabilidad, no sólo de fluidez) · P2-3 (módulos
compartidos) · P2-2 (agrupar escrituras) · P2-4 (caché de precisión).

**Tanda 5 — higiene**
P3-1 (una sola implementación del contrato + test sobre la real) · P3-3 (métricas del mock) ·
P3-5/P3-6 (código muerto y duplicado) · P3-8 (`.luac` obsoletos) · §5 (docs).

Cobertura que falta y que habría detectado casi todo lo anterior:

1. Un test que cambie el rango en caliente y compare los ángulos de sección/rail **antes y
   después** (P0-2).
2. Una matriz de zonas para la barra con `h ∈ {40, 45, 50, 55, 60}` verificando que toda caja
   visible tiene altura > 0 (P1-2).
3. Un `getSwitchValue` en el mock, distinto de `getValue`, para que el uso de la API equivocada
   falle (P0-1).
4. Escenarios de batería que afirmen que la unidad del historial coincide con la del valor
   mostrado (P0-7).
5. Un test de escala descendente (`Min > Max`) que exija ≥ 1 sección y ≥ 1 marca (P0-3).
6. **`dev/collide.lua` como test**: hoy es un informe. Convertirlo en aserciones sobre la matriz
   de zonas cerraría de golpe G-6 a G-11, que son la mitad de los defectos gráficos y ninguno
   detectable con los tests actuales (que sólo comprueban que los objetos estén dentro de la
   zona, no que no se pisen).
7. Una aserción de capas: para cada modo de color, que ningún objeto de referencia (sección,
   rail, marca de umbral) quede tapado por el arco/relleno de valor (G-2, G-12).

---

## 9. Apéndice — reproducción

Herramientas añadidas junto a `dev/preview.lua` (ver §7.0 para por qué hacen falta):

```sh
lua5.3 dev/audit-preview.lua ./     # -> dev/audit-preview.html, ~70 casos
lua5.3 dev/collide.lua       ./     # -> informe de colisiones geométricas
```

Las sondas de comportamiento usadas en §1–§4 están en el scratchpad de la sesión
(`audit_probe.lua`, `audit_probe2.lua`, `p3.lua`, `p4.lua`) y se ejecutan igual que la suite:

```sh
lua5.3 audit_probe.lua  <ruta-a-WIDGETS/GaugePro/>
lua5.3 audit_probe2.lua <ruta-a-WIDGETS/GaugePro/>
```

Referencias de firmware citadas (todas de este repositorio, `radio/src/`):

| Afirmación | Fuente |
|---|---|
| Opciones a Lua como enteros; String/File como cadena | `lua/lua_widget.cpp:331-360` |
| `CHOICE` almacenado 1-based | `gui/colorlcd/mainview/widget_settings.cpp:193-201` |
| Slots posicionales y tipados; `setDefault` sólo al cambiar el tipo | `gui/colorlcd/mainview/widget.cpp:76-86` |
| Truncado a `MAX_WIDGET_OPTIONS` | `lua/lua_widget_factory.cpp:291`, `datastructs_screen.h:92` |
| Tabla de nombres como default de `SOURCE` | `lua/lua_widget_factory.cpp:175-192` |
| `getValue` interpreta el entero como `MIXSRC` | `lua/api_general.cpp:707-724` |
| `getSwitchValue` es la API de switches | `lua/api_general.cpp:2690`, `:3190` |
| `model.resetSensor` existe | `lua/api_model.cpp:1869`, `:2001` |
| `Cels+`/`Cels-` son por celda | `lua/api_general.cpp:773-775` |
| `lvgl.set` = `getParams` + `refresh()` | `lua/lua_lvgl_widget.cpp:763-767` |
| `Triangle::refresh` borra y reconstruye el lienzo | `lua/lua_lvgl_widget.cpp:1429-1442` |
| `Line::refresh` no asigna memoria | `lua/lua_lvgl_widget.cpp:1141-1146` |
| Ángulos de arco: `-= 360` una sola vez | `thirdparty/lvgl/src/widgets/lv_arc.c:93,116,146,168` |
| Arco de longitud cero no se dibuja | `thirdparty/lvgl/src/draw/sw/lv_draw_sw_arc.c:66` |
| Orden real de fuentes (`LXL` entre `XL` y `XXL`) | `gui/colorlcd/fonts.h:25-38` |
| Presupuesto de 20 000 instrucciones por llamada | `lua/widgets.cpp:37,85-98` |
| `lcd.sizeText` / `lcd.RGB` no requieren buffer LCD | `lua/api_colorlcd.cpp:262-269`, `:1000-1016` |
| `loadScript` compila a `.luac` y prefiere el binario | `lua/interface.cpp:441-500` |
