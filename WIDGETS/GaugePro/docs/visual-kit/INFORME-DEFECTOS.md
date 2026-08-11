# Gauge Pro — Informe de defectos detectados por análisis visual

Análisis de la tanda de capturas `docs/visual-kit/screenshots/` (262 PNG,
generadas originalmente 2026-08-10 16:52 por `tools/gaugepro-visual-kit/run.py
all`). Regeneradas 2026-08-10 21:10 tras aplicar los fixes de [F-01](#f-01) y
[H-01](#h-01) — `RUN_SUMMARY.md`/`CATALOG.md` reflejan esa segunda corrida.

**Estado del documento:** vivo. Cada hallazgo se añade cuando está *confirmado*
con medición sobre píxel, no cuando se sospecha. Si aparece información nueva
que contradice o matiza un hallazgo previo, se edita ese hallazgo (con nota de
revisión), no se añade uno nuevo.

Clasificación:

| Prefijo | Significado |
|---|---|
| **W-nn** | Defecto real del widget (se ve igual en la radio) |
| **F-nn** | Defecto en el binding LVGL / firmware que el widget destapa |
| **H-nn** | Defecto del arnés de captura (emulador / `tools/gaugepro-visual-kit`) |

---

## Resumen ejecutivo

| ID | Sev | Título | Impacto |
|---|---|---|---|
| [F-01](#f-01) | **P0 — RESUELTO** | Cualquier `lvgl.set()` sobre un arco/círculo ya construido lo desplaza (defecto del binding LVGL, no de Gauge Pro) | Corregido en `renderer.lua` reenviando el centro en cada `lvgl.set`; verificado en 9 configuraciones reales |
| [H-01](#h-01) | **P0 — RESUELTO** | El arnés ignoraba el `zone` declarado por cada caso: 210 de 222 casos se renderizaban a pantalla completa | Corregido: routing por zona real + columna "Zone (real)" en CATALOG.md + `verify_dupes.py` conectado (degrada a WARN); verificado contra el simulador real |
| [W-01](#w-01) | **P1** | Los ticks de escala se dibujan a un radio muy superior al del anillo, en un hueco vacío | Ticks "flotando" desconectados del dial; en zonas reales se salen de la zona y pisan al widget vecino |
| [W-02](#w-02) | **P1** | El píldora de estado (WARN/CRIT) se recorta contra el borde inferior de la zona | Badge cortado por la mitad en layouts anchos |
| [W-03](#w-03) | **P1** | La cara `continuous` pinta el track inactivo a opacidad plena (las caras segmentadas no) | El tramo vacío compite (o gana) al tramo lleno; en CRIT el vacío es lo más brillante de la barra |
| [W-06](#w-06) | **P1** | `BarOrigin = Zero` sólo dibuja la marca de cero: el relleno sigue naciendo en el extremo bajo de la escala | La opción parece funcionar (aparece la marca) pero no cambia lo que mide la barra, en 4 de las 5 caras |
| [W-04](#w-04) | **P2** | La aguja no arranca en el pivote y sobresale del anillo | Hueco visible entre el buje y la base de la aguja; punta fuera de la banda |
| [H-02](#h-02) | **P2 — parcialmente resuelto** | `layouts.nearest_zone()` calculaba sobre 480×272 mientras el simulador es 800×480 | El fix de H-01 corrigió el tamaño de pantalla en el único sitio que lo usaba; sigue abierto revisar la lista de objetivos de `zonas` (ver nota en H-02) |
| [W-05](#w-05) | **P3** | El modo Static pinta con el verde de acento, el mismo RGB que la banda "normal" | La barra dice "todo bien" mientras la píldora dice WARN |
| [H-03](#h-03) | **P3** | Colisión de numeración, tema `stock` redundante y casos que fijan el valor por defecto | `017` duplicado; 16 capturas `__stock` idénticas a la base; `br-medium` ≡ `br-end-round` ≡ `br-normal` |

---

## F-01 — Todos los arcos del dial salvo el track se dibujan con el centro desplazado — RESUELTO {#f-01}

**Severidad: P0 (bloqueante).** Era la causa raíz de la mayoría de duplicados
de la tanda y de que el dial no mostrara progreso.

**Estado: corregido en `renderer.lua` (`M.flush`/`markRoundCenter`) y verificado
contra el binario real del simulador (`build/simu/simu.exe`), no sólo contra el
mock.** La sección de abajo queda como registro histórico del diagnóstico
(incluida la hipótesis inicial, que la reproducción in-simulador **descartó**);
la causa raíz confirmada y el fix aplicado están en
[Causa raíz confirmada (revisión)](#f-01-revision).

### Evidencia

Ajuste de círculo por mínimos cuadrados sobre la línea media de cada trazo
(script en el [anexo](#anexo-a--cómo-reproducir-las-medidas)).

`026_dial_op-sweep360.png` (zona 800×480, `L.cx,L.cy = 240,240`):

| Objeto | Centro ajustado | Radio dibujado | Desplazamiento vs (240,240) |
|---|---|---|---|
| `ui.track` (fondo) | **(239.5, 239.2)** | 198.5 | (0.5, 0.8) — correcto |
| `ui.valueArc` (naranja, estado WARN) | **(35.0, 33.1)** | 196.1 | **(−205, −206)** |

El parámetro `radius` del arco de valor es `R = 196.1 + espesor/2 ≈ 205`.
El desplazamiento medido **coincide exactamente con −R en ambos ejes**.

`013_color_color-sections-ok.png` (misma zona), banda verde de `ui.sections`:

* centro ajustado **(22.8, 20.5)**, radio 213.8, residuo ±3.6 px
* desplazamiento (−217.2, −219.5) ≈ **−`L.railRadius`**

`L05_layout2p3_dial_vs_bar.png`, zona 400×240, centro del dial medido sobre el
track en (116.5, 119.6): banda de sección ajustada en (28.6, 25.8) → mismo
patrón con un radio distinto.

Tres radios distintos, tres desplazamientos distintos, todos iguales a `−R`.
No es una constante: **es el propio radio del objeto restado dos veces.**

### Consecuencias visibles (todas confirmadas)

1. **El dial no dibuja arco de valor.** Muestreando la banda del track cada 15°
   en `001` (valor al 79.5 %) y en `003` (valor al 19.5 %), los 19 puntos
   devuelven exactamente el mismo RGB `(156,186,214)` en ambos casos: la banda
   es uniforme en los 270°. El único indicador de valor que queda en el dial es
   la aguja.
2. **Con barrido de 270° el arco de valor cae entero fuera de pantalla.** Con
   centro en (35,33) y r≈196, los ángulos 135°→349° dan puntos con x<0 o y<0.
   Sólo asoma el **casquete redondeado del extremo**: es la mancha verde
   recortada contra el borde superior que aparece en *todas* las capturas de
   dial (`001`: tinta en la fila y=0, columnas 220–236, RGB `(57,158,115)`).
   En `003` (crítico, ángulo 187.6°) el casquete cae fuera y no se ve nada.
   En `026` (barrido 360°) el arco da la vuelta y sí entra en pantalla: es el
   arco naranja suelto de la esquina superior izquierda.
3. **`ColorMode` no tiene ningún efecto en el dial.** Static / Threshold / Rail
   / Gradient sólo se diferencian por el color del arco de valor y por las
   bandas — y ninguno de esos objetos se pinta donde debe. Resultado:
   `001`, `005`, `007`, `009`, `011` (+ sus gemelas `__stock`) son
   **byte-idénticas**; ídem el grupo crítico `003/006/008/010/012`.
4. **Rail no dibuja nada.** Sólo crea bandas para roles ≠ `normal`
   ([renderer.lua:194](../../renderer.lua#L194)); desplazadas, ambas quedan
   completamente fuera de pantalla. Por eso `009`/`010` son idénticas a las
   Static.
5. **Sections sólo deja ver la banda `normal`.** Las bandas crit/warn quedan a
   la izquierda del centro desplazado, fuera de la zona.

### Análisis del código

El widget construye todos los arcos igual, pasando el **centro** en `x`/`y`:

* track — [renderer.lua:144-151](../../renderer.lua#L144) — `radius = L.radius` → **correcto**
* sections — [renderer.lua:167-173](../../renderer.lua#L167) — `radius = L.railRadius` → desplazado
* rails — [renderer.lua:198-204](../../renderer.lua#L198) — `radius = L.railRadius` → desplazado
* ghost — [renderer.lua:320-327](../../renderer.lua#L320) — `radius = L.radius` → desplazado
* valueArc — [renderer.lua:331-337](../../renderer.lua#L331) — `radius = L.radius` → desplazado

Es decir: **el único arco correcto es el primero que se crea**, y el error no
depende del valor del radio.

En el binding, `LvglWidgetRoundObject` guarda `x,y` como **esquina** y
convierte desde/hacia centro en cada operación
([lua_lvgl_widget.cpp:1791-1806](../../../../radio/src/lua/lua_lvgl_widget.cpp#L1791)):

```cpp
void LvglWidgetRoundObject::setPos(coord_t x, coord_t y)
{ LvglWidgetObject::setPos(x - radius.coord, y - radius.coord); }   // centro -> esquina

void LvglWidgetRoundObject::setRadius(coord_t r)
{ x += radius.coord; y += radius.coord;                             // esquina -> centro
  radius.coord = r; w = h = r * 2;
  setPos(x, y); setSize(w, h); }                                    // centro -> esquina
```

y `LvglWidgetArc::build()`
([lua_lvgl_widget.cpp:1958](../../../../radio/src/lua/lua_lvgl_widget.cpp#L1958))
asume que `x,y` **todavía están en centro** al entrar:

```cpp
setPos(x, y);              // resta radius UNA vez
setRadius(radius.coord);   // suma radius, vuelve a restar -> idempotente
window = new Window(parent, {x, y, w, h}, lv_arc_create);
```

Esa secuencia es idempotente **sólo si `x,y` valen el centro al entrar**. Si el
objeto pasa por `setPos()`/`build()` una segunda vez, la resta del radio se
aplica dos veces y el resultado **se estabiliza** en `centro − 2R` — que es
justo lo medido (el objeto se dibuja centrado en `centro − R`, su esquina).
El desplazamiento medido es exactamente igual a `R`, no acumulativo entre
frames (el arco de valor recibe un `lvgl.set{endAngle}` por frame y no deriva),
lo que encaja con **una única** resta extra en la vida del objeto.

> **Pendiente de cerrar (histórico):** la hipótesis de arriba ("doble resta de
> esquina dentro de `build()`") quedó descartada al reproducirla — ver la
> revisión inmediatamente abajo. Se deja el análisis original sin borrar
> porque documenta el camino de descarte, pero **no describe el mecanismo
> real**.

---

## F-01 — Causa raíz confirmada (revisión tras repro en simulador real) {#f-01-revision}

El análisis original de arriba asumía que el desplazamiento se originaba
DENTRO de `LvglWidgetArc::build()` (una doble conversión centro↔esquina). Un
repro aislado contra el binario real (`build/simu/simu.exe`, no el mock)
**descarta esa hipótesis** y, con ella, la corrección que se había propuesto
(reafirmar la esquina `x=cx-radius` tras construir el arco): esa corrección
se probó explícitamente y **no cambia nada** — el arco cae exactamente en el
mismo sitio, roto, con o sin ella.

### Método

Widget Lua mínimo (`WIDGETS/<nombre>/main.lua`), sin ninguna dependencia de
Gauge Pro, que crea un arco de fondo (nunca tocado después) y un segundo arco
al mismo `x,y,radius`, sondeado de formas distintas: construido y dejado en
paz; construido degenerado y actualizado un frame después; actualizado con
sólo un cambio de color (sin tocar ángulo ni x/y); corregido con `lvgl.set`
justo tras construirse. Cada variante se botó en `simu.exe` de verdad (vía
`tools/gaugepro-visual-kit`'s `SimuDriver`, el mismo driver que genera esta
tanda) y se capturó por separado, con marcadores de referencia (un rectángulo
negro en el centro exacto pedido) para no depender de ajustar círculos a ojo.

### Resultado

* Un arco construido **una sola vez**, con el span final ya correcto en el
  propio `lvgl.arc{...}` inicial, **siempre queda bien colocado** — sea cual
  sea su radio (probado de 12 a 190 px).
* El **primer** `lvgl.set()` que se le hace a ese mismo arco después de
  construido — **cualquiera**, aunque sólo cambie `color` u `opacity` y no
  toque `endAngle` ni `x`/`y` — lo saca de sitio. Confirmado con un
  rectángulo de control (mismo patrón "construir, luego `lvgl.set` con sólo
  color"): el rectángulo **no se mueve**. El defecto es específico de
  `LvglWidgetRoundObject` (arcos y círculos), no general a `lvgl.set`.
* Reafirmar `x = cx - radius, y = cy - radius` (la corrección "de esquina"
  que proponía la versión original de este hallazgo) en ese mismo `lvgl.set`
  **no corrige nada**: el arco cae exactamente en el mismo sitio roto que sin
  la corrección.
* Reafirmar en cambio `x = cx, y = cy` — el **centro sin convertir**, tal
  cual se le pasa a `lvgl.arc{}` la primera vez — **sí corrige la posición**,
  de forma reproducible, en cada variante probada (color-solo, ángulo-solo,
  degenerado-y-actualizado-después, corrección-doble). Probado también con
  cuatro actualizaciones sucesivas al radio real del dial (190 px): la
  posición se mantiene correcta en las cuatro, siempre que **cada** llamada a
  `lvgl.set` (no sólo la primera) incluya `x,y`.
* Esto encaja con el único caso del propio Gauge Pro que YA funcionaba sin
  tocar nada: `ui.pivotRing` (un círculo) y la cabeza "Dot" de la barra
  (`bar_faces.lua`) — esta última mueve su círculo con `lvgl.set(ui.head,
  {x = position})`, y `position` ya es la coordenada CENTRO sin convertir, no
  una esquina. Coincidencia, no diseño deliberado, pero confirma el patrón.

El mecanismo exacto dentro de `LvglWidgetRoundObject::refresh()` /
`lv_arc_set_*` que hace que reenviar el centro sin convertir sea lo que
corrige la posición no se terminó de rastrear dentro de LVGL en sí (harían
falta las fuentes de LVGL, no sólo el wrapper de EdgeTX) — pero el
comportamiho es determinista, reproducible en un repro que no toca ni una
línea de Gauge Pro, y **verificado además contra el widget real** (ver
Remediación aplicada). El comportamiento es un defecto del binding/LVGL sobre
el que Gauge Pro no tiene control; lo único accionable desde Lua es no dejar
que un arco reciba nunca un `lvgl.set()` sin su centro dentro.

### Remediación aplicada

`renderer.lua`: cada arco/círculo del dial que se actualiza después de
construido (`ui.sections[i]`, `ui.rails[i]`, `ui.ghost`, `ui.valueArc`; NO
`ui.track`, que nunca se toca tras `build()` y por eso no lo necesita) se
registra en `widget.ui.roundCenters` en el momento de crearse
(`markRoundCenter`). `M.flush()` — el único sitio del archivo donde se llama
`lvgl.set` sobre estos objetos, dado que todas las actualizaciones pasan por
`setProp`/`flush`, nunca por un `lvgl.set` suelto — inyecta `x = L.cx, y =
L.cy` en la tabla de propiedades ya pendiente de cualquier objeto registrado,
justo antes de enviarla:

```lua
-- renderer.lua (M.flush)
local round, L = widget.ui.roundCenters, widget.layout
for i = 1, count do
  local obj = list[i]
  local t = dirty[obj]
  if round and round[obj] then
    t.x, t.y = L.cx, L.cy
  end
  lvgl.set(obj, t)
  ...
```

Por qué en `widget.ui` y no en `widget.frame` (donde vivía la primera versión
de este registro, y no funcionaba): `M.build()` **reemplaza** `widget.frame`
entero al final de la construcción (una tabla nueva de estado de animación
por-frame), después de que todos los arcos ya se hubieran registrado — así
que el registro se perdía antes de que corriera el primer `flush()` real.
`widget.ui` es el árbol de objetos retenidos y sólo se le añaden campos
durante `M.build()`, nunca se reemplaza — es el sitio correcto para "qué
objetos retenidos necesitan este tratamiento".

Por qué en `flush()` y no en cada punto de llamada (`applyColors`,
`updateArc`, `updateHistory`): porque el defecto se dispara con
**cualquier** propiedad, no sólo con el ángulo — parchear sólo `updateArc`
habría dejado roto `applyColors` (que sólo toca color/opacidad en
`ui.sections`/`ui.rails`/`ui.valueArc`). Centralizarlo en `flush()` cubre las
tres rutas de una vez y no depende de que cada futura ruta de actualización
se acuerde de incluirlo.

### Verificación

Contra el widget real (no el repro aislado), con las cuatro combinaciones que
antes fallaban de forma distinta — Rail/Threshold/Gradient/Sections, en
normal/warn/crítico, barrido 270°/360°, con marcadores min/max, needle y bar
style — el arco de valor y las bandas de referencia quedan concéntricos con
el track en las nueve configuraciones probadas. El estilo `bar` (que no pasa
por este código) se confirmó sin regresión.

**Actualización — confirmado en la corrida oficial completa.** Tras aplicar
también el fix de [H-01](#h-01), se regeneró la tanda entera (262 capturas,
`python run.py` vía `cmd_capture`/`cmd_report` reales, contra el `sdcard` del
repo) y **todas las capturas de dial publicadas en `screenshots/` muestran
ahora el arco de valor y las bandas concéntricas con el track** — no sólo las
nueve configuraciones de la verificación aislada. `001_estado_st-normal.png`
y `013_color_color-sections-ok.png` (las dos capturas que usé como ejemplo
del defecto en la primera versión de este hallazgo) son la comprobación más
directa: compárense contra su descripción original más arriba.

### Trabajo pendiente

* **Portar el repro aislado al repo** como
  `WIDGETS/GaugePro/dev/repro_arc_offset.lua` + un runner en
  `tools/gaugepro-visual-kit/`, para que la próxima regresión de este tipo
  (en Gauge Pro o en cualquier otro widget LVGL de este repo) se detecte sin
  repetir la investigación desde cero.
* **Aserción geométrica en el arnés** (seguía pendiente, ver Paso 3 del
  análisis original): el arnés debe verificar que hay tinta de acento sobre
  la banda del track proporcional al valor, no sólo capturar el PNG y marcar
  PASS. Con el fix aplicado esto ya se cumple, pero nada en el arnés lo
  hubiera cazado si se rompe de nuevo.
* **Reporte upstream a EdgeTX**, con el repro aislado como adjunto: un
  `lvgl.set()` sobre un arco o círculo ya construido lo desplaza, y el
  desplazamiento sólo se corrige reenviando el centro sin convertir en la
  misma llamada. El mock de pruebas de este repo (`tests/mock_env.lua`) no
  modela ninguna semántica de conversión centro/esquina para objetos
  redondos, así que la suite headless existente no habría cazado esto ni
  puede servir de regresión contra el binding real — sólo una corrida contra
  el simulador real (como la de esta verificación) lo hace.

---

## H-01 — El arnés ignora el `zone` declarado por cada caso — RESUELTO {#h-01}

**Severidad: P0 para la validez de la tanda.**

**Estado: corregido en `tools/gaugepro-visual-kit/{catalog.py,layouts.py,
run.py,report.py,verify_dupes.py}`, verificado contra el binario real del
simulador (no sólo lógica Python).** Las tres remediaciones que proponía este
hallazgo están aplicadas (routing por zona real, columna "Zone (real)" en
`CATALOG.md`, y `verify_dupes.py` conectado a `cmd_report()`). El análisis y
el diagnóstico originales de abajo quedan como registro; el resultado de la
verificación — incluida una precisión importante sobre qué duplicados
desaparecen y cuáles no — está en
[Verificación (revisión)](#h-01-verificacion) al final de la sección.

`scenes.json` declara un `zone` (ancho×alto para el que el escenario fue
diseñado) en **210 de los 222 casos**. Pero
[catalog.py:169-173](../../../../tools/gaugepro-visual-kit/catalog.py#L169)
sólo lo honra cuando `section == "zonas"`:

```python
if case["section"] == "zonas" and case.get("zone"):
    layout_id, zone_index, _rect = layouts.nearest_zone(target_w, target_h)
    ...
else:
    out.append(Track1Screen(case, overrides))   # Layout1x1 => 800x480
```

Los otros 210 casos se renderizan **a pantalla completa (800×480)**, tamaño que
no aparece en ninguna radio real como zona de widget salvo el layout 1×1.

### Consecuencias

* **Los casos cuyo objeto de prueba *es* el tamaño no prueban nada.**
  `br-narrow` (300×44), `br-short` (160×44), `br-nochip` (300×70) y `br-crit`
  (300×70) se renderizan los cuatro a 800×480 → **cuatro PNG byte-idénticos**
  (`062`, `063`, `064`, `066`). Igual con `060`/`069`/`072`/`090`
  (`br-normal`, `br-medium`, `br-end-round`, `br-tall`).
* **`tx-prec2-micro` declara 60×60** y se renderiza a 800×480: el modo `micro`
  de [layout.lua:448](../../layout.lua#L448) y los recortes de contención de
  [layout.lua:472-500](../../layout.lua#L472) — el código que existe
  explícitamente para evitar coordenadas negativas que *revientan* el widget en
  la radio — **no se ejercitan ni una sola vez en toda la tanda**.
* Los `f4-*-compact` (160×44) y `f4-*-dense` (480×110) tampoco ven su tamaño.
* En total, **24 PNG son byte-idénticos a los de otro caso** y los 24 figuran
  como PASS en `CATALOG.md` / `RUN_SUMMARY.md` (`262 pass, 0 warn, 0 fail`).

### Remediación propuesta (las tres, aplicadas)

1. **Honrar `zone` en todos los casos**, no sólo en `zonas`:

   ```python
   # catalog.py, build_track1_screens
   zone = case.get("zone")
   if zone:
       layout_id, zone_index, _rect = layouts.nearest_zone(
           zone[0], zone[1], SCREEN_W, SCREEN_H)
       out.append(Track1Screen(case, overrides,
                               layout_id=layout_id, zone_index=zone_index))
   else:
       out.append(Track1Screen(case, overrides))
   ```

   (con `SCREEN_W/H` reales — ver [H-02](#h-02)).

2. **Registrar en el catálogo la zona efectiva**, no la pedida: añadir columna
   `Zone (real)` con `LayoutId/zone → WxH px`. Hoy `CATALOG.md` no dice en qué
   tamaño se pintó nada, que es exactamente el dato que faltaba para detectar
   este fallo leyendo el informe.

3. **Integrar `verify_dupes.py` en `cmd_report()`**: ya existe y hace justo la
   comprobación (`tools/gaugepro-visual-kit/verify_dupes.py`) pero **no está
   conectado**. Un grupo de duplicados entre casos con overrides distintos debe
   degradar el estado a `WARN` en `RUN_SUMMARY.md`, no quedarse en PASS.

---

## H-01 — Verificación (revisión tras corrida real) {#h-01-verificacion}

### Cambios aplicados

* **`catalog.py`** — `SCREEN_W, SCREEN_H` pasa de `480, 272` (el valor
  incorrecto que también describe [H-02](#h-02)) a `800, 480`, el tamaño real
  del simulador. `build_track1_screens` ya no restringe el enrutado por zona
  a `section == "zonas"`: **cualquier** caso con `zone` en `scenes.json` pasa
  por `layouts.nearest_zone(w, h, SCREEN_W, SCREEN_H)`, y el rectángulo real
  devuelto (`(x, y, w, h)`) se guarda en el nuevo campo
  `Track1Screen.real_rect`.
* **`run.py`** — `_run_track1` y `_run_theme_subset` propagan
  `layout=s.layout_id, zone_index=s.zone_index, zone_rect=s.real_rect` a cada
  fila del `runlog`. `_run_theme_subset` tenía su **propio** bug de la misma
  familia — construía sus escenas con `Screen("Layout1x1", [(0, ...)])`
  a fuego, ignorando `s.layout_id`/`s.zone_index` incluso para los casos de
  `estado`/`color` que sí declaran zona — corregido al mismo patrón que
  Track 1.
* **`report.py`** — nueva columna "Zone (real)" en `CATALOG.md`
  (`_fmt_zone`), y `flag_cross_case_duplicates(rows, shots_dir)`: agrupa las
  capturas por hash SHA-1 y degrada a `WARN` cualquier fila `PASS` cuyo grupo
  de duplicados contenga **más de un `name` de caso distinto** (un duplicado
  entre capturas del mismo caso bajo temas distintos, H-03, se deja como
  está — es lo esperado). `run.py cmd_report()` la invoca antes de escribir
  los tres artefactos, así que tanto `CATALOG.md` como los conteos de
  `RUN_SUMMARY.md` reflejan la degradación.
* **`verify_dupes.py`** — refactorizado para exponer
  `find_duplicate_groups(shots_dir)` como función reutilizable (antes sólo
  tenía un `main()` de CLI); `report.py` la importa.

### Verificación contra el simulador real

`build_track1_screens` sobre el `scenes.json`/`defs.json` reales: los 206
casos no-skipped que declaran zona (eran 210 sobre 222 totales; los otros 4
están en `SKIPPED_CASES`) pasan ahora por `nearest_zone` con el tamaño de
pantalla correcto — cero casos caen ya en el fallback fullscreen sin zona
declarada.

Corrida real (vía `SimuDriver`, el mismo driver que usa `run.py`) de diez
casos que antes eran duplicados byte-idénticos, incluyendo los que cita el
hallazgo original:

| Caso | Zona pedida | Zona real asignada | Resultado |
|---|---|---|---|
| `br-tall` | 100×220 | `Layout2P1 z1` → 400×240 | **distinto** de los demás (antes idéntico a `br-normal`) |
| `tx-prec2-micro` | 60×60 | `Layout1P4 z1` → 400×120 | **distinto** de todos (antes idéntico al resto a 800×480) |
| `f4-ticks-compact` | 160×44 | `Layout1P4 z1` → 400×120 | **distinto** de todos |
| `br-narrow` / `br-short` / `br-crit` | 300×44 / 160×44 / 300×70 | los tres → `Layout1P4 z1` (400×120) | **siguen idénticos entre sí** |
| `br-normal` / `br-medium` / `br-end-round` | 300×70 / 320×90 / 320×90 | los tres → `Layout1P4 z1` (400×120) | **siguen idénticos entre sí** |

El primer grupo de "siguen idénticos" **no es un fallo del enrutado**: los
tres casos comparten exactamente el mismo Min/Max/Warn/Crit (fueron
diseñados para probar un mismo valor crítico a tres anchos distintos) y
**no existe ninguna zona real más pequeña que 400×120 a 800×480** — el
catálogo `ZMAP` de EdgeTX no baja de ahí a esta resolución. Es la limitación
que ya describe [H-02](#h-02) ("ningún caso baja de 400×120"), no algo que el
enrutado de H-01 pueda resolver por sí solo: el enrutado ahora es *correcto*
(manda cada caso a la zona real más cercana), sólo que la zona real más
cercana sigue siendo la misma para varios objetivos pequeños distintos.

El segundo grupo ("br-normal/br-medium/br-end-round") es el hallazgo ya
catalogado en [H-03](#h-03) punto 3 (casos cuyo único override es el propio
valor por defecto de la opción) — confirmado sin cambios, no relacionado con
la zona.

**Con `flag_cross_case_duplicates` conectado**, estos dos grupos residuales
pasan a `WARN` en vez de `PASS` silencioso, con la razón anotada en
`RUN_SUMMARY.md` — exactamente el comportamiento que pedía la remediación #3.

### Actualización — corrida oficial completa (262 capturas)

Se regeneró la tanda entera contra el `sdcard` real del repo (no el scratch
de 10 casos de arriba): `python run.py` vía `cmd_capture`/`cmd_report`
reales — 206 Track 1 + 8 Track 2 + 48 temas, 262 capturas, 0 FAIL. Confirma
lo de arriba a escala completa: `br-normal.png` ahora se ve como un widget
compacto en la esquina superior derecha de un lienzo de 800×480 (zona real
`Layout1P4 z1`, 400×120 px), no a pantalla completa, y `CATALOG.md` lo dice
explícitamente en su columna "Zone (real)".

**Hallazgo nuevo, no anticipado, al conectar `verify_dupes.py` de verdad:**
la corrida completa marca **70 filas en `WARN`** (`RUN_SUMMARY.md`), muy por
encima de los ~7 duplicados que cita el análisis original de arriba. Revisar
esa lista entera muestra que la enorme mayoría **no es el bug de H-01** —
H-01 está resuelto, el enrutado es correcto — sino tres causas ya conocidas
o esperables que la comprobación, tal como se especificó, no distingue entre
sí:

1. **Colapso de zona real** ([H-02](#h-02), como ya se documentó arriba):
   varios objetivos pequeños distintos siguen cayendo en la misma zona real
   más cercana (`Layout1P4 z1`, 400×120) porque no existe nada más pequeño en
   el catálogo `ZMAP` a 800×480.
2. **Opciones que fijan su propio valor por defecto** ([H-03](#h-03) punto
   3): ya documentado, sin cambios.
3. **Coincidencia genuina de píxeles por diseño del propio caso de prueba,
   categoría no anticipada al escribir la remediación original.** Ejemplo:
   `color-static-ok`, `color-threshold-ok` y `color-gradient-ok` comparten el
   mismo Min/Max/Warn/Crit y el mismo valor "cómodamente normal" — y para ese
   valor, Static (acento fijo), Threshold (color por estado, que en "normal"
   también resuelve a acento) y Gradient (rampa que en el extremo "normal"
   converge al mismo acento) **producen el mismo verde por diseño**: la
   diferencia entre esos tres modos sólo se manifiesta en warn/crítico, que
   es precisamente lo que esos tres casos "-ok" no ejercitan. Lo mismo con
   los trillizos `pal-preset-auto`/`f4-preset-hex`/`f4-auto-rssi` y
   `f5-auto-ch1`/`f5-auto-thr` (los tres resuelven al mismo preset "Auto"
   desde entradas distintas — coincidir es el punto de la prueba, no un
   fallo). Esto no es un defecto del arnés ni del widget: es que la
   comprobación byte-a-byte, aplicada sin distinguir *por qué* dos casos
   coinciden, no puede diferenciar "el enrutado rompió el caso" de "el caso
   coincide con otro a propósito".

La remediación #3 tal como estaba escrita ("un grupo de duplicados entre
casos con overrides distintos debe degradar a WARN") es *correcta* — el
código hace exactamente eso — pero la especificación resultó más ruidosa de
lo que parecía sobre el papel una vez se corrió contra la tanda real. No se
ajustó el heurístico en esta pasada (habría requerido codificar qué pares de
overrides "no deberían importar" caso por caso, un riesgo de sobre-ingeniería
mayor que el problema que resuelve) — se deja documentado aquí para que la
próxima persona que lea 70 warnings en `RUN_SUMMARY.md` sepa que la mayoría
son ruido esperado y no repita esta misma investigación.

### Trabajo pendiente

* Los duplicados residuales de la categoría 1 (colapso de zona) no se
  resuelven solos con H-01; requieren [H-02](#h-02) (una lista de tamaños
  objetivo para `zonas` que sean alcanzables a 800×480).
* Si el volumen de `WARN` en `RUN_SUMMARY.md` resulta molesto en la práctica,
  la mejora más barata es dejar de listar como sospechosos los grupos cuyos
  `overrides` sólo difieren en `ColorMode` cuando el caso es de la familia
  "-ok" (no ejercita warn/crítico) — cubre la categoría 3 completa sin tocar
  la lógica de detección de duplicados en sí.

---

## W-01 — Los ticks de escala se dibujan muy por fuera del anillo {#w-01}

**Severidad: P1.**

### Evidencia

`001_estado_st-normal.png`, centro (240,240):

| Elemento | Radio medido |
|---|---|
| Banda del track (borde interior→exterior) | 185 → 211 |
| Ticks mayores (7, a 45° exactos: 135…405) | **226 → 230** |
| Ticks menores (6, en las bisectrices) | 225 → 227 |
| Casquete del arco de valor mal ubicado | 233 → 240 (recortado) |

Los ángulos son correctos (7 ticks equiespaciados en el barrido de 270°, con
sus 6 menores intercalados). El problema es **radial**: hay **15 px de vacío**
entre el borde exterior del anillo y el primer tick, porque
[layout.lua:502-505](../../layout.lua#L502) reserva el hueco de la banda de
rail *siempre*, se dibuje o no:

```lua
L.railRadius = L.radius + floor(L.trackThickness / 2) + L.railThickness + L.railGap
L.tickInner  = L.railRadius + tickGap
```

En `ColorMode` Static / Threshold / Gradient **nunca hay banda de rail**, así
que ese anillo reservado queda vacío y los ticks parecen suspendidos en el
aire, sin relación visual con la escala que anotan.

En zonas reales el efecto es peor: en `L05_layout2p3_dial_vs_bar.png` el dial
inferior izquierdo tiene los ticks a r≈101…119 con el borde exterior del anillo
en r≈90 — y el tick superior cae en **y=247**, dentro de los 240 px de la zona
de arriba: **pisa el widget vecino**.

### Remediación propuesta

En [layout.lua:502-505](../../layout.lua#L502), reservar el anillo de rail sólo
cuando se va a usar, y acercar los ticks al anillo:

```lua
-- El hueco de la banda de rail sólo existe si hay banda que dibujar; en los
-- modos sin banda los ticks se pegan al anillo en lugar de quedar flotando a
-- 15 px de él (INFORME-DEFECTOS.md W-01).
local hasBand = (cfg.colorMode == M.COLOR_RAIL)
             or (cfg.colorMode == M.COLOR_SECTIONS)
L.railRadius = L.radius + floor(L.trackThickness / 2)
             + (hasBand and (L.railThickness + L.railGap) or 0)
L.tickInner  = L.railRadius + tickGap
```

Ojo: `outerReserve` ([layout.lua:462](../../layout.lua#L462)) usa el mismo
presupuesto para *elegir* el radio, así que debe consultar el mismo `hasBand`;
si no, el dial se encoge para reservar sitio que ya no usa. Conviene extraer
`hasBand` **antes** del cálculo de `outerReserve` y usarlo en los dos sitios.

Verificación: los ticks deben quedar en `[radius + trackThickness/2 + gap,
+ tickLength]` y `L.tickOuter <= edgeReach` debe seguir cumpliéndose (la
aserción de contención de [layout.lua:492](../../layout.lua#L492) ya existe).

---

## W-02 — La píldora de estado se recorta contra el borde de la zona {#w-02}

**Severidad: P1.**

### Evidencia

Barrido de tinta en la última fila de píxeles de cada captura:

* `164_ejes5_f5-dual-h-neg.png` → tinta en `y = 479`, columnas **745–783**,
  RGB `(156,162,165)` = `chipEdge` (rol `label`). La píldora **CRIT** está
  cortada por abajo.
* `L05_layout2p3_dial_vs_bar.png` → idéntico, columnas 745–783.
* `124_ejes5_f5-v-continuous-static.png` → la píldora **WARN** queda pegada a
  la esquina inferior derecha, a media pantalla de la barra que califica.

El borde del chip se construye en
[renderer.lua:392-398](../../renderer.lua#L392) expandiendo la caja de estado
en `L.chipOutline` **hacia fuera en las cuatro direcciones**:

```lua
ui.chipEdge = lvgl.rectangle{
  x = L.stateBox.x - edge, y = L.stateBox.y - L.chipOff - edge,
  w = L.stateBox.w + edge * 2, h = L.chipHeight + edge * 2, ...
}
```

Si `L.stateBox` ya está pegada al borde inferior de la zona, el `- edge` /
`+ edge * 2` la saca fuera. El comentario del propio código
([renderer.lua:381-384](../../renderer.lua#L381)) menciona que *"un campo
escrito por el renderer se perdía y el chip acababa fuera de su zona"* — el
síntoma sigue presente por otra vía.

### Remediación propuesta

Que la caja de estado **reserve su propio outline** en layout, en vez de que el
renderer lo añada por fuera. En el sitio donde se coloca `L.stateBox`:

```lua
-- El outline del chip se pinta por FUERA de stateBox (renderer.buildChip), así
-- que la zona debe reservarlo aquí: colocar la caja pegada al borde deja el
-- borde de 1 px (y el chipOff vertical) fuera del recorte (W-02).
local pad = L.chipOutline + L.chipOff
L.stateBox.x = clamp(L.stateBox.x, pad, w - L.stateBox.w - pad)
L.stateBox.y = clamp(L.stateBox.y, pad, h - L.chipHeight - pad)
```

Complementario (recomendado): en zonas anchas y bajas, anclar el chip **al lado
del valor**, no a la esquina de la zona. En `124` el badge WARN está a 500 px de
la barra vertical que describe; leído en la radio no se asocia con nada.

---

## W-03 — La cara `continuous` pinta el track inactivo a opacidad plena {#w-03}

**Severidad: P1.** El defecto está **acotado a la cara `continuous`**: las cuatro
caras segmentadas lo hacen bien.

### Evidencia

Corte transversal completo de la barra en `060_barra_br-normal.png`
(valor 79.5 %, cara `continuous` por defecto). Filas 412–437, columnas
seleccionadas:

| Fila | x = 100 (tramo lleno) | x = 700 (tramo vacío) | Qué es |
|---|---|---|---|
| 418 | `#105d9c` | `#105d9c` | borde superior |
| 419–430 | `#21925a` verde de acento | **`#105d9c`** | cuerpo (relleno / track) |
| 431 | `#105d9c` | `#105d9c` | separador |
| 432–435 | `#c61021` rojo / `#a55d21` ámbar | **`#105d9c`** | tira de bandas de referencia |
| 436 | `#105d9c` | `#105d9c` | borde inferior |

`#105d9c` = `(16,93,156)` = `T.color.rail` **a opacidad 255**. Que es opacidad
plena está comprobado por partida doble:

* es el mismo RGB exacto que el buje del dial, dibujado `filled = 1` sin
  opacidad ([renderer.lua:299-302](../../renderer.lua#L299));
* las bandas de referencia encima suyo salen `#c61021`, que es exactamente
  `crit` (#ff0000) mezclado a `railBand` (200/255) **sobre un fondo `#105d9c`
  opaco** — con un track translúcido el resultado habría sido `#fa1422`.

Comparación entre caras (histograma del color del segmento inactivo):

| Captura | Cara | Track inactivo | α efectivo |
|---|---|---|---|
| `060`, `078`, `124` | `continuous` | **`(16,93,156)`** | **255** ✗ |
| `113` | `blocks` | `(173,199,222)` | ~69 ✓ |
| `097` | `hex` | `(173,199,222)` | ~69 ✓ |
| `001` (dial) | — | `(156,186,214)` | 90 = `T.opacity.rail` ✓ |

El diseño pide `T.opacity.rail = 90` (~35 %,
[theme.lua:158](../../theme.lua#L158)) y así se construye:
[bar_faces.lua:278](../../bar_faces.lua#L278) pasa `T.opacity.rail` a `shape()`,
que lo reenvía tal cual a `lvgl.rectangle`
([bar_faces.lua:186-189](../../bar_faces.lua#L186)). La ruta de repintado
([bar_faces.lua:787-791](../../bar_faces.lua#L787)) lo recalcula, pero su máximo
es 150:

```lua
local trackOpacity = (assist == "strong") and T.opacity.railBand
  or assisted and min(T.opacity.full, T.opacity.rail + 60) or T.opacity.rail
```

**Ningún camino del código pide 255.** Queda por identificar qué primitiva lo
pinta; el hecho medido está cerrado, el mecanismo no.

Efecto agravado en estado crítico: en `164_ejes5_f5-dual-h-neg.png` el relleno
es rojo oscuro y el **vacío** azul brillante — lo más luminoso de la barra es la
parte que no significa nada.

### Remediación propuesta

1. **Instrumentar y acotar** — `dev/audit-preview.lua` ya vuelca el árbol de
   objetos. Volcar, para un build de cara `continuous`, cada primitiva con
   `color == T.color.rail` y su opacidad. Que las caras segmentadas usen el
   mismo `shape()` y salgan bien apunta a `continuousBuild()`
   ([bar_faces.lua:250](../../bar_faces.lua#L250)) y no a `shape()` en sí:
   sospechosos por orden, el `casing` de
   [bar_faces.lua:274-277](../../bar_faces.lua#L274) (se dibuja sobre `barOuter`,
   que envuelve al track) y el `ui.panel` de
   [bar_faces.lua:261-268](../../bar_faces.lua#L261) (`T.opacity.full`).
2. **Blindar el invariante en el arnés headless**, que es donde se debió cazar:
   aserción en `tests/` de que ninguna primitiva del track de barra supera
   `T.opacity.rail + 60`. Una regla de una línea sobre el árbol del mock que
   cubre las cinco caras de golpe.
3. **Unificar el tono de "inactivo".** Hoy conviven tres valores (90 en el dial,
   ~69 en las caras segmentadas, 255 en `continuous`) para el mismo rol
   semántico. Debe salir de un único sitio y no recalcularse por cara.

---

## W-06 — `BarOrigin = Zero` no mueve el origen del relleno {#w-06}

**Severidad: P1.** La opción *parece* funcionar —aparece la marca de cero— pero
no cambia lo que la barra representa. Es el peor tipo de fallo de opción: no se
nota hasta que alguien confía en la lectura.

### Evidencia

Todos los casos "positive" comparten escala **min = −9, max = 11**, así que el
cero cae en el 45 % → **x = 361** sobre el eje de 8…790. Valor 7.9 → **x = 670**.
Con `BarOrigin = Zero` el relleno debería ocupar **361 → 670**; el tramo 8…361
debería quedar en color de track.

Muestreo del cuerpo de la barra (fila central), a la izquierda y a la derecha
del cero:

| Captura | Cara | x=30 | x=120 | x=220 | x=320 | x=420 | x=620 | ¿Honra el cero? |
|---|---|---|---|---|---|---|---|---|
| `150` | continuous | `#ff0000` | `#ff0000` | `#d65100` | `#21925a` | `#21925a` | `#21925a` | **no** |
| `153` | blocks | `#ff0000` | `#ff0000` | `#ce6100` | (hueco) | `#21925a` | `#21925a` | **no** |
| `156` | hex | `#ff0000` | `#ff0000` | `#ce6100` | `#21925a` | `#21925a` | `#a5cfc6` | **no** |
| `166` | dual-rail | rojo **pálido** | rojo pálido | rojo pálido | rojo pálido | `#21925a` | `#21925a` | **sí** |

En `150`/`153`/`156` el tramo a la izquierda del cero está a **saturación
plena** — es relleno, no track (el track vacío de esas mismas capturas mide
`#a5cfc6` / `#105d9c`). En `166` el mismo tramo está en el tono pálido del rail
y el verde saturado arranca justo en la marca de cero.

La marca de cero **sí** se dibuja en las cuatro caras
([bar.lua:181](../../bar.lua#L181), `axis.originCoord`): visible como tick a
x = 360–362 en `150` y `153`. De ahí que el defecto pase desapercibido.

Los casos "negative" (`149`, `152`, …) usan min = 4, max = 24, donde el cero cae
**fuera** de la escala: ahí `originClamped` degrada correctamente a extremo bajo
([bar_style.lua:402-404](../../bar_style.lua#L402)) y el render es el esperado.
No prueban nada sobre la opción.

### Análisis del código

La cadena de configuración es correcta y está verificada:

* `BarOrigin` es un CHOICE de 3 opciones (`Auto`, `Scale low`, `Zero`) →
  `cfg.barOrigin = 3` para `Zero`;
* `ORIGIN = { [2] = "scale-low", [3] = "zero" }`
  ([bar_style.lua:115](../../bar_style.lua#L115)) → `visual.origin = "zero"` ✓;
* `G.makeAxis(..., visual.origin)` ([layout.lua:1267](../../layout.lua#L1267))
  → `wantsZero = true` → `axis.originT = zeroT = 0.45`
  ([geometry.lua:96](../../geometry.lua#L96));
* y **`tests/smoke_test.lua:387` ya afirma exactamente ese `originT`**.

Es decir: **el eje está bien y está probado; lo que no usa el eje es el
relleno.** Los consumidores existen —
[bar_faces.lua:1107-1150](../../bar_faces.lua#L1107) tiene la rama
`axis.originT ~= 0` para celdas, y
[bar_faces.lua:1198](../../bar_faces.lua#L1198) llama a `G.axisOriginSpan` —
pero el resultado en pantalla dice que no gobiernan el tramo pintado en
`continuous` / `blocks` / `hex`. Sospechoso principal: los tramos de gradiente
de [bar_faces.lua:298-300](../../bar_faces.lua#L298), construidos sobre
`G.axisSpan(active, t1, t2)` con `t1,t2` recorriendo **0…1**, sin consultar
`originT`.

### Remediación propuesta

1. **Test que falle hoy** (antes de tocar nada). El test actual comprueba el
   eje; falta comprobar el consumidor. Sobre el mock, con
   `min=-9, max=11, BarOrigin=Zero, value=7.9`, afirmar que **ninguna** primitiva
   de relleno empieza antes de `G.axisPoint(axis, axis.originT)`. Repetirlo
   parametrizado para las cinco caras: es el mismo aserto cinco veces y es lo
   que habría cazado esto.
2. **Un único punto de verdad para el tramo lleno.** Que todas las caras
   obtengan su intervalo de `G.axisOriginSpan(axis, normalized)` —que ya existe y
   ya hace lo correcto en ambos sentidos del signo— en lugar de que cada cara
   derive su propio `from/to`. `dual-rail` es la prueba de que la función
   funciona; el problema es que sólo ella la usa de verdad.
3. **Fallar visible en vez de fallar callado.** Si una cara no soporta el origen
   en cero, debe registrarlo en `visual.downgrades` (el mecanismo ya existe,
   `bar_style.lua:395`) y no limitarse a ignorar la opción.

---

## W-05 — El modo Static pinta con el verde que significa "normal" {#w-05}

**Severidad: P3 (riesgo de diseño, no fallo de render).**

`097_caras4_f4-hex-static` y `102_caras4_f4-ticks-static` muestran el relleno en
`(33,146,90)` mientras la píldora dice **WARN**. No es un fallo: en modo Static
`resolveColor()` devuelve el acento
([renderer.lua:473](../../renderer.lua#L473)) y el acento es
`lcd.RGB(0x20,0x90,0x58)` ([theme.lua:117](../../theme.lua#L117)) — verde.

El problema es semántico: **ese mismo verde es el que `stateColor("normal")`
usa para decir "todo bien"** (la función devuelve el acento para el rol
`normal`, [theme.lua:288](../../theme.lua#L288)). En Static, entonces, la barra
pinta literalmente el color "OK" durante un WARN o un CRIT, y sólo la píldora
—mucho más pequeña— contradice esa lectura. En una radio, mirando de reojo en
vuelo, gana la barra.

### Remediación propuesta

Elegir una de las dos, no ambas:

* **(a)** Que Static use un rol **neutro** (`T.color.label` / SECONDARY1) en vez
  del acento, de modo que "sin semántica de color" se vea como *sin* semántica.
* **(b)** Documentar explícitamente en la ayuda de la opción que Static ignora el
  estado, y mantener el acento — pero entonces el acento por defecto no debería
  coincidir con el color del rol `normal`.

Recomiendo (a): es un cambio de una línea en `resolveColor()` y elimina la
ambigüedad sin tocar la paleta.

---

## W-04 — La aguja no arranca en el pivote y sobresale del anillo {#w-04}

**Severidad: P2 (cosmético, pero visible en todas las capturas de dial).**

### Evidencia

Análisis de componentes conexas en `001_estado_st-normal.png`: el buje
(`ui.pivotRing`, disco de 24×24 px en (239.5, 239.5)) sale como **componente
separada** de la aguja — es decir, **no se tocan**. Ampliando la zona se ve un
hueco limpio de ~8 px entre el disco azul y la base negra de la aguja.

Causa: [layout.lua:535](../../layout.lua#L535) y
[layout.lua:558](../../layout.lua#L558) fijan los dos radios de forma
independiente:

```lua
L.needleInner = clamp(floor(L.radius * 0.16), T.px(3), T.px(20))   -- 0.16·R
L.pivotRadius = clamp(floor(L.radius * T.ratio.pivotRadius), T.px(3), T.px(9))
```

Con `R ≈ 205`: `needleInner = 20·px` mientras `pivotRadius` está topado en
`T.px(9)`. El tope del buje y el arranque de la aguja divergen en cuanto el
dial crece — el comentario del renderer dice que el buje *"se crea después de la
aguja para tapar el extremo interior de la pala"*
([renderer.lua:294-298](../../renderer.lua#L294)), pero con esos números no lo
alcanza.

En el otro extremo, la punta cruza la banda del track y asoma por fuera
(visible en `001`, `019`, `205`), con un fragmento azul claro que sobresale del
negro — es el `ui.needleTip` pintado más allá de `L.needleOuter`.

### Remediación propuesta

Atar el arranque de la aguja al buje en lugar de a una fracción del radio:

```lua
L.pivotRadius = clamp(floor(L.radius * T.ratio.pivotRadius), T.px(3), T.px(9))
-- La pala arranca DENTRO del buje: el buje se dibuja después y tapa la unión,
-- pero sólo si hay solape. Atarlo a una fracción independiente del radio los
-- separa en cuanto el dial crece (INFORME-DEFECTOS.md W-04).
L.needleInner = max(1, L.pivotRadius - T.px(1))
```

(mover el cálculo de `pivotRadius` **antes** del bloque de la aguja; hoy está
después y el comentario de [layout.lua:569](../../layout.lua#L569) lo señala
como dependencia de orden).

Para la punta, `L.needleOuter` ya se calcula como
`L.radius - trackThickness/2 - px(1)`, que es el **borde interior** de la banda:
el desbordamiento sugiere que el segmento de punta se dibuja con `rounded = 1`
y su casquete añade `needleTipThickness/2` por delante. Restar ese casquete:

```lua
L.needleOuter = L.radius - floor(L.trackThickness / 2) - T.px(1)
              - floor(L.needleTipThickness / 2)   -- el cap redondo sobresale
```

---

## H-02 — `nearest_zone()` calcula sobre 480×272 y el simulador es 800×480 {#h-02}

**Severidad: P2 — parcialmente resuelto como efecto colateral de [H-01](#h-01-verificacion).**
El fix de H-01 cambió `catalog.py`'s `SCREEN_W, SCREEN_H` de `480, 272` a
`800, 480` y lo pasa explícitamente a **todas** las llamadas a
`layouts.nearest_zone()`, incluida la de la sección `zonas` (que antes de
H-01 era la única que llamaba a esta función, y lo hacía sin pasar el
tamaño, cayendo en el default incorrecto de `layouts.py`). Eso corrige el
bug técnico que describe esta sección. Lo que **sigue sin resolver** es la
observación de fondo: a 800×480 el catálogo `ZMAP` de EdgeTX no tiene
ninguna zona real por debajo de 400×120, así que los objetivos pequeños de
la sección `zonas` (60×60 … 128×96) y de varios casos de `barra`/`caras4`
siguen sin ser alcanzables — confirmado en la verificación de H-01. Los
puntos 1 y 2 de la remediación de abajo están aplicados; el punto 3 (revisar
la lista de objetivos de `zonas`) sigue abierto.

[layouts.py:83](../../../../tools/gaugepro-visual-kit/layouts.py#L83) declara
`def nearest_zone(target_w, target_h, screen_w=480, screen_h=272)` y
[catalog.py:171](../../../../tools/gaugepro-visual-kit/catalog.py#L171) lo llama
**sin pasar el tamaño real**. Las capturas son de 800×480.

Zona pedida vs zona realmente renderizada:

| Caso | Pedido | Layout elegido | Real a 800×480 |
|---|---|---|---|
| `zone-60x60` | 60×60 | Layout1P4 z1 | **400×120** |
| `zone-80x60` | 80×60 | Layout1P4 z1 | **400×120** (idéntica) |
| `zone-100x100` | 100×100 | Layout1P3 z1 | 400×160 |
| `zone-128x96` | 128×96 | Layout1P3 z1 | 400×160 (idéntica) |
| `zone-160x160` / `200x160` / `300x150` | — | Layout2P1 z1 | 400×240 (las tres iguales) |
| `zone-200x200` / `260x220` / `120x220` | — | Layout4P2B z4 | 400×360 (las tres iguales) |
| `zone-100x260` | 100×260 | Layout1P3 z0 | 400×480 |
| `zone-480x272` | 480×272 | Layout1x1 z0 | **800×480** |

Los 12 casos colapsan en **6 zonas distintas** — que es exactamente el patrón de
duplicados observado (`199/200/203` idénticas, `201/202/204` idénticas).

Además, ninguna zona baja de 400×120: la sección `zonas`, cuyo propósito
declarado es *"el mismo widget a distintos tamaños de zona reales"*, **no cubre
ningún tamaño pequeño**. Sobre una pantalla de 800×480 el `ZMAP` de EdgeTX no
produce zonas menores; los objetivos de 60×60 a 128×96 son inalcanzables por
construcción.

### Remediación propuesta

1. Pasar el tamaño real: detectarlo del primer PNG capturado o declararlo como
   constante del arnés (`SCREEN_W, SCREEN_H = 800, 480`) y propagarlo a
   `nearest_zone()` y `pixel_rect()`.
2. **Fallar ruidosamente cuando el objetivo es inalcanzable.** `nearest_zone()`
   devuelve siempre *algo*; debe devolver también la distancia y el arnés debe
   marcar `WARN` si la zona elegida difiere del objetivo en más de, digamos, el
   50 % en cualquier eje. Un `zone-60x60` que se pinta a 400×120 no puede
   reportarse como PASS.
3. Revisar la lista de objetivos de la sección `zonas` para que sea el conjunto
   de zonas **realmente existentes** en la pantalla de destino, en vez de una
   lista de tamaños inventados. Los tamaños pequeños de verdad (micro/compact)
   sólo se pueden ejercitar en radios de 480×272 → merecen una corrida aparte
   con un simulador de esa clase.

---

## H-03 — Numeración, tema `stock` y casos que fijan el valor por defecto {#h-03}

**Severidad: P3 (higiene del informe).**

1. `_run_theme_subset()` arranca en `seq_start=1`
   ([run.py:369](../../../../tools/gaugepro-visual-kit/run.py#L369) para
   `--themes-only`), así que la pista de temas reutiliza índices de la pista 1:
   conviven `017_escala_sc-20000.png` y
   `017_estado_st-normal__gaugeprolab-light.png` en el mismo directorio, y
   `CATALOG.md` lista dos filas con `#017` en secciones distintas. Ordenar el
   directorio por nombre deja de reflejar el orden de captura.
   *Fix:* prefijo por pista (`T1-017`, `TH-017`, `L-01`) o contador global.

2. Las 16 capturas `__stock` son **byte-idénticas** a las de la corrida base
   (`001` ≡ `001__stock`, etc.): el tema base ya *es* `EdgeTX Default`. La
   comparación de temas no aporta información y consume ~6 % de la tanda.
   *Fix:* omitir el sufijo `stock` y reutilizar la captura base como referencia
   en `CATALOG.md`, o sustituirlo por un tercer tema que sí difiera.

3. **Casos cuyo único override es el valor por defecto.** `069 br-medium`
   (`BarSize=Medium`) y `072 br-end-round` (`BarEnds=Round`) son byte-idénticos
   a `060 br-normal`: ambos fijan la opción a su propio valor por defecto, así
   que no prueban que la opción haga nada. Contrasta con `068/070/071`
   (Thin/Thick/Maximum) y `073/074` (Square/Chamfer), que sí difieren.
   *Fix:* el generador conoce los `defs` — debe marcar como `WARN` (o descartar)
   todo caso cuyo conjunto de overrides sea un subconjunto de los valores por
   defecto. Es la misma comprobación que hace falta para
   [H-01](#h-01) y se puede escribir una vez.

   **Nota:** esto explica *sólo* los duplicados de esta clase. Los grupos
   grandes de duplicados (13 y 11 ficheros) son [F-01](#f-01); los de la sección
   `barra` y `zonas` son [H-01](#h-01)/[H-02](#h-02).

---

## Anexo A — cómo reproducir las medidas

Todas las cifras de este informe salen de tres scripts sobre los PNG
(Python + Pillow, sin dependencias del firmware):

* **ajuste de círculo por línea media** — para cada fila `y`, tomar el punto
  medio de cada tramo contiguo del color buscado y ajustar un círculo
  algebraico. Con residuos < ±4 px sobre un trazo de 5 px, el centro es fiable.
* **componentes conexas** — segmentar todo lo que no es fondo y reportar
  centroide, radio y ángulo respecto al centro del dial. Sirve para ver qué
  toca qué (así se detectó que el buje **no** toca la aguja, W-04).
* **muestreo polar** — leer el RGB a lo largo del radio medio de la banda cada
  15° del barrido. Así se demostró que el arco de valor no existe (F-01).

Recomendación: portarlos a `tools/gaugepro-visual-kit/inspect.py` para que las
próximas tandas se puedan auditar con aserciones y no sólo con el ojo.

## Anexo B — comprobado y sin hallazgo

Cosas que sí se revisaron y **salen bien**; se listan para que la próxima pasada
no las vuelva a mirar:

* **Cara `ticks`** (`102`): el ritmo de marcas es regular a 29 px; las dos
  irregularidades aparentes son las marcas de umbral exactas (crit en x=281,
  warn en x=438, coincidiendo con 35 % y 55 % de la escala) y la supresión de la
  marca de rejilla que caería a 13 px de ellas. Es evitación de colisión
  deliberada y funciona.
* **Recorte fuera de escala** (`023 sc-outofrange`, escala −292…−272, valor 7.9):
  la aguja se clava correctamente en el tope del barrido (405°). El único reparo
  es que el texto muestra `7.9` junto a una escala que no lo contiene, sin
  ninguna marca de "fuera de rango" — mejora, no defecto.
* **Variantes de opción que sí se distinguen**: `BarSize` (068/070/071),
  `BarEnds` (073/074), `BarHead` (174–178), `ScaleMarks` (179–182), `ValuePos`
  (183–186), `LabelPos` (187–190) y `Contrast` (057/058/059) producen las 24
  imágenes distintas esperadas. Ninguna de esas opciones está muerta.

## Anexo C — pendiente de analizar

Secciones de la tanda todavía sin revisar en detalle, por orden de riesgo:

* `ejes5` caras `ticks` y `steps` con origen en cero (`158`–`163`): las otras
  tres caras están medidas en [W-06](#w-06); estas dos no, por tener muy poca
  tinta para el muestreo automático. Conviene confirmarlas a mano.
* `caras4` modos de color por cara (092–111, 20 capturas): sólo se revisaron
  `hex-static`, `hex-gradient`, `ticks-static` y `blocks-dense`.
* `paleta` (15): colores personalizados; sólo se miró `pal-mono-off`.
* Temas `GaugeProLab Light/Dark` más allá de los dos casos ya mirados.
* Layouts `L01`–`L04`, `L06`, `L07` (los de pantalla completa).
