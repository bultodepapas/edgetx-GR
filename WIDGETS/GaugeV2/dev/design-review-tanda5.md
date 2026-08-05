# GaugeV2 — Respuesta al 2.º informe del diseñador (modo-Rail-crit)

**Revisor:** diseñador gráfico (2.º informe, 5 de agosto de 2026, medidas sobre la
captura `mode-Rail-crit-v2.svg` a 300×240).
**Preparado por:** desarrollo de GaugeV2.
**Decisión del propietario del repo (de adopción):** el diseño general se **mantiene**.
Es pulido, no rediseño. Se adoptan las correcciones de la aguja, los solapamientos
("cosas encima") y los errores de detalle que siguen vigentes; todo lo que hoy funciona
se conserva y se blinda con tests.

> **Método.** Cada hallazgo se contrastó contra el **árbol de objetos real** del código
> actual (sonda sobre `tests/mock_env.lua` en la zona canónica 200×160, `ColorMode = Rail`,
> valor 22, 40 frames) y contra `dev/collide.lua` (12 zonas + extremos + 3 barridos,
> limpio). Las medidas de este doc son de esa sonda, no estimaciones sobre la imagen.
>
> **STATUS (2026-08-05): P0 implementado.** P0-1 (cola eliminada) y P0-2 (holgura de
> valor: región 7 px más abajo + STDSIZE 16 px incorporado a la rampa para degradar la
> fuente suavemente, AUDIT P3-4) están en el código, con test de regresión propio
> (*P0-2: the value cell clears the hub and the needle at critical angles*). Verificado:
> suites 38/38 + 89/89, `dev/collide.lua` limpio (18/18). En la base 200×160 el valor
> pasa de 24 px a 16 px y de y 71 a y 82 (5 px libres bajo el pivote); la aguja a 194°
> queda a 11 px de la celda (antes cruzaba su esquina).
>
> **Renders para inspección** (en `dev/shots/`, gitignored): `mode-Rail-crit.png` es la
> **v5** (código actual), con copia versionada `mode-Rail-crit-v5.*`; `mode-Rail-crit-v1.*`
> a `-v4.*` se conservan como trazabilidad. Las variaciones de posición son
> `mode-Rail-pos1` (valor 0, aguja en el cap inicial), `mode-Rail-pos2` (valor 50, aguja
> arriba) y `mode-Rail-pos3` (valor 100, aguja en el cap final).
>
> **STATUS (2026-08-05, adenda): P0-4 y P1-5 implementados.** P0-4 (la aguja ya no
> atraviesa el chip WARN/CRIT: `geometry.lua` gana `rayBoxEntry` — intersección
> rayo/caja por el método de slabs — y `renderer.lua.updateArc` recorta
> `needleOuter/needleBodyOuter/needleTipInner` al radio de entrada del pill menos 2 px
> cuando el chip está visible y el ángulo actual lo cruzaría; `frame.chipBox` guarda el
> footprint real del pill, calculado en `updateChip`, del que `L.chipOff` es la pieza que
> faltaba — `bar.lua` la necesitaba también y no la tenía, causaba `FAIL ... attempt to
> perform arithmetic on a nil value (field 'chipOff')` en 3 tests hasta corregirlo).
> Confirmado en `mode-Rail-pos2.png` (valor 50): antes el tallo cruzaba el pill de lado a
> lado; ahora se detiene ~2 px antes del borde inferior del chip. Test de regresión propio
> (*P0-4: the needle stops short of the state chip instead of crossing it*). P1-5 (alcance
> acotado, decisión del propietario 05 ago 2026): `nameBox` ya no se ancla al fondo fijo
> del dial — sube hacia `minMaxBox`/`valueBox` con un límite inferior en la posición
> antigua, así que nunca queda peor que antes; el hueco entre `22 dB` y `RSSI` se redujo
> visiblemente (confirmado por comparación directa antes/después). **No se tocó el tamaño
> de fuente del valor** (RAMP/`valueDrop`): el ancho disponible en esa Y está gobernado por
> el chord del dial, no por la altura de la región, y agrandar la fuente exige mover el
> valor más cerca del centro — justo lo que P0-2 revirtió para separarlo del pivote/aguja.
> Tocar eso reabre el test con nombre propio de P0-2, así que se deja como decisión
> explícita pendiente (ver P1-5 en el plan) en vez de forzarlo en esta pasada. Verificado:
> suites 38/38 + 90/90 (+1 test nuevo), `dev/collide.lua` limpio (18/18).
>
> **STATUS (2026-08-05, 2.ª adenda): P1-1 y P1-3 implementados.** P1-1: la tinta del
> valor pasa a `align = CENTER` en su caja reservada (`layout.placeValue`) y la unidad se
> re-ancla a la tinta REAL en cada cambio de `valueStr` (`renderer.anchorUnit`, compartida
> con `bar.lua`) — con la tinta centrada en una caja de ancho fijo, su propio centro es
> siempre la mitad de la caja sin importar cuántos dígitos tenga, así que el grupo visible
> queda en el mismo centro que el grupo reservado para cualquier valor, no solo para la
> muestra más ancha. Confirmado en `mode-Rail-crit.png`: `22 dB` se desplazó a la
> izquierda, visiblemente más cerca del pivote. P1-3: la banda pasiva se rebaja a
> `opacity.railBandCrit = 160` únicamente mientras `colorKey == "critical"` (WARN conserva
> 200, porque ahí el ámbar es el estado activo); medido en píxel sobre el render, la banda
> ámbar pasa de (181,144,57) a (149,121,51), casi exacto a la predicción de la fórmula de
> blend 200→160. Los dos con test de regresión propio. Verificado: suites 38/38 + 92/92
> (+2 tests nuevos), `dev/collide.lua` limpio (18/18). P1-2 queda cubierto por P1-5 (mismo
> cambio de `nameBox`), así que se marca resuelto sin código adicional.

---

## 0. Veredicto del propietario

- El rediseño propuesto en §4/§5 del informe **no se adopta** (nueva base 300×240 con
  letterboxing, aguja como triángulo, reescritura de la gramática de estados). No aporta
  y arriesga lo que ya funciona.
- Se adopta como **plan de pulido**: aguja limpia (punta definida, sin cola/gancho),
  cero solapamientos en la zona central (valor / aguja / pivote), centrado óptico del
  bloque valor+unidad, y los errores de detalle vigentes (jerarquía de color en CRIT,
  etiqueta de fuente, robustez de dígitos).
- Prioridad absoluta: **que lo que está funcione perfectamente** — ninguna corrección
  puede romper las suites (38 unit / 88 smoke), el audit de colisiones ni los renders.

---

## 1. Realidad del repo: cómo se mide este widget

El informe mide una captura de **300×240 px**. Esa captura es **exactamente 1.5×** la zona
de referencia con la que trabaja el widget y las herramientas de `dev/`:

- `dev/shots.lua`, `dev/audit-preview.lua` y `dev/collide.lua` renderizan la zona
  **200×160** (`dev/shots.lua:264-275`, `dev/collide.lua:170-174`).
- Los centros lo confirman: el informe dice C ≈ (150,108); el árbol real mide **C = (99,73)**
  en base 200×160 → (148.5, 109.5) a 1.5×. La proporción es exacta.

Además, en la radio real no existe un lienzo fijo: EdgeTX entrega `zone.w/zone.h` en
píxeles reales (320, 480, 800 px de ancho) y `theme.px()` escala con `LCD_SCALE`
(0.8 / 1.0 / 1.375, `theme.lua:88-90`). Toda la geometría se recalcula por zona
(`layout.calculate`, `layout.lua:540-551`). Por tanto:

> **Las medidas absolutas de este doc son para la base canónica 200×160** (la zona que
> produce la captura del informe y la que ejercitan las herramientas `dev/`). En otras
> zonas se conserva la **proporción**, no el píxel: el mismo código recalcula el layout.
> Para convertir una medida del informe (300×240) a la base: **÷ 1.5**.

### Restricciones inmutables del repo

1. **La aguja es familia `lvgl.line`, nunca `lvgl.triangle`** (AUDIT.md P2-1): el
   `refresh()` del triángulo libera y reconstruye el canvas en cada cambio de ángulo
   (~24 KB de churn de heap por frame con damping). La punta se logra con dos líneas.
2. **El texto se pinta sobre la geometría** (contrato de legibilidad): el z-order no se usa
   como parche; los solapamientos se corrigen en geometría.
3. **Los colores son roles de tema**, no literales (excepto RED, que el firmware no expone).

### Medidas del árbol real (sonda, base 200×160, Rail, valor 22)

| Elemento | Medido hoy |
|---|---|
| Centro del dial | (99, 73) |
| Pista (track) | r = 52, grosor 11, opacidad 90 (35 %) |
| Rail (bandas) | radio 61, grosor 3, gap 1 px, opacidad 200 |
| Ticks | 2 px, de r 63 a r 67 (5 mayores; menores en `large`) |
| Aguja cuerpo | 6 px, (91,71) → (72,66) |
| Aguja punta | 2 px, (73,66) → (54,62) |
| **Cola** | **4 px, (107,75) → (108,75) — muñón de 1 px a la derecha del pivote** |
| Pivote | círculo sólido r 4 en (99,73) |
| Tinta del valor `22` | ≈ (88..114, 71..95), fuente 24 px |
| Unidad `dB` | (120..134, 81..94) — alineada a la línea base |
| Caja de valor reservada | (62,71,52,24) — ancho de muestra `-100` |
| Bloque visible `22 dB` | ≈ (88..134) → **centro 111, +12 px respecto al dial** |
| Chip `CRIT` | pill 19 px de alto, pad lateral 7, texto centrado, borde 1 px; ancho ≈ 42 px con `T.textWidth` |
| Etiqueta `RSSI` | (0,130,200,11) — debajo del hueco inferior del anillo |
| Fila min/max | (69,97,61,11) |

---

## 2. Conversión de las especificaciones del informe (§4) a la base

| Parámetro (informe, 300×240) | Base 200×160 (÷1.5) | Código hoy | Veredicto |
|---|---|---|---|
| Centro C ≈ (150, 108) | (100, 72) | (99, 73) | ✅ coincide |
| Rail principal radio 78–82 / grosor 13–15 | 52–54.7 / 8.7–10 | pista 52 / 11 | ✅ dentro del rango (es la pista; el rail es overlay de 3 px) |
| Zona crítica: overlay igual espesor o 4–6 px más fino | 2.7–4 px | banda a radio 61, grosor 3, gap 1 | ✅ ya es overlay concéntrico (P-E, Tanda 4) |
| Aguja: largo hasta r−8 | r−5.3 | needleOuter 46 = r−6 | ✅ |
| Aguja: base total 7–9 | 4.7–6 | cuerpo 6 | ✅ |
| Aguja: punta 1–2 | 0.7–1.3 | punta 2 (mínimo legible) | ✅ (mín. 2 px es la cota física) |
| Aguja: **sin cola/gancho** | — | **colas: `ui.tail`, muñón de 4 px** | ❌ **se adopta eliminarla** |
| Hub 5–6 px | 3.3–4 | r 4 | ✅ |
| Chip ≈ 62×28 | 41×18.7 | `CRIT` + 2×7 ≈ 42×19 | ✅ |
| Valor: 10–14 px más abajo, 6 px libres del hub | 6.7–9.3 / 4 | tinta top 71 **dentro** del pivote (69..77): sin aire, solape de celda ~6 px | ❌ **se adopta (acotado)** |
| Unidad: gap 5–7, tercio inferior | 3.3–4.7 | gap 6, línea base | ✅ gap; ⚠️ alineación (opcional) |
| RSSI: subir 4–8 | 2.7–5.3 | nameBox y 130 | ⚠️ **se adopta como pulido** |
| Ticks: misma función polar | — | `buildTicks` + `tickInner/tickOuter` | ✅ ya uniforme |
| Paleta CRIT: 1 rojo + 1 rojo atenuado + neutro; ámbar solo pasivo | — | rojo arco/texto, banda a 200, ámbar a 200 | ⚠️ **pulido: rebajar banda pasiva** |

---

## 3. Análisis hallazgo por hallazgo

### P0 — lo más grave del informe

**3.1 Aguja y `22` se superponen — vigente (acotado), se adopta.**
En el árbol real, en el ángulo crítico (194°) la banda del cuerpo (6 px, de (91,71) a
(72,66)) pasa **por debajo de la esquina superior-izquierda de la tinta** del valor
(88..114, 71..95), y el rango vertical del pivote (69..77) se solapa con la parte superior
de la celda de la tinta. El texto se pinta encima, así que la lectura es posible — pero el
efecto visual de "menos rojo" que describió el informe es exactamente la banda del cuerpo
asomando a la izquierda de los dígitos. `dev/collide.lua` no lo detecta **por diseño**:
excluye la aguja del audit (`dev/collide.lua:74-77`), porque la aguja barre bajo el texto
por contrato. **Decisión:** corregir la geometría, no el z-order (ver P0-1/P0-2 del plan).

**3.2 Aguja deformada / sin punta / cola — vigente en la cola, se adopta.**
La punta afilada (2 px) y el cuerpo de base constante (6 px) ya existen desde la Tanda 4.
Lo que sigue visible es la **cola**: un muñón de 1 px de largo y 4 px de grosor a la
derecha del pivote (107,75)→(108,75), resto del contrapeso de la era de triángulos.
Es el "gancho" del informe. **Decisión:** eliminar `ui.tail` (P0-1 del plan); además
ahorra un objeto y su escritura `pts` por frame.

**3.3 Rail crítico se fusiona con la aguja — mitigado, pulido menor.**
La banda roja (radio 61, grosor 3, opacidad 200) y la aguja roja (cuerpo 6 + punta 2)
coinciden angularmente en crítico. Ya están separadas en radio (gap 1 px) y en opacidad
(200 vs 255), y la Tanda 4 dejó la banda como referencia pasiva (P-E). **Decisión:**
mantener la semántica (banda = zona fija, arco = estado) y rebajar ligeramente la banda
pasiva en CRIT (P1-3 del plan) para que la aguja domine sin ambigüedad.

### P1 — composición

**3.4 Bloque `22 dB` descentrado — VIGENTE y medible, se adopta (con matiz).**
El grupo **reservado** (caja de muestra + gap + unidad) está centrado: caja (62..114) +
unidad (120..134) → centro 98 ≈ dial 99. **Pero la tinta visible no:** la caja se reserva
con la muestra más ancha posible (`-100`, 52 px, `layout.lua:321-322`) y la tinta del
valor se ancla a la **derecha** de la caja (`L.valueAlign = RIGHT`, `layout.lua:159`) para
mantener la unidad pegada. Con un valor de 2 dígitos quedan ~26 px de reserva vacía a la
izquierda y el bloque visible `22 dB` (≈88..134) queda **+12 px a la derecha** del centro.
La compensación óptica de 1 px de la Tanda 4 ajusta el grupo reservado, no la tinta.
**Decisión:** centrar la tinta en su caja y re-anclar la unidad a la tinta en cada cambio
de valor (P1-1 del plan), con el tradeoff documentado: el dígito de las unidades se mueve
**dentro** de la caja reservada (los vecinos no se mueven; la cuerda G-6 no cambia).

**3.5 Chip `CRIT` descentrado — ya resuelto; solo documentar.**
El pill usa `chipPad` 7, `chipHeight = stateH+6` = 19 y texto centrado por
`chipOff = (chipHeight − stateH)/2` (`renderer.lua:307-321`); el ancho abraza el texto
medido con `T.textWidth` (`renderer.lua:441`). La propuesta del informe ("medir y centrar,
ajuste óptico ±1 px documentado") ya está implementada en métricas reales. **Decisión:**
no hay cambio funcional; se añade un test de regresión que fija el centrado.

**3.6 Ámbar compite con CRIT — vigente como jerarquía, pulido.**
En CRIT el arco y el texto son rojo pleno; la banda ámbar de referencia (radio 61,
opacidad 200) es el elemento de mayor luminancia de la corona. La semántica actual es
correcta (bandas = zonas fijas pasivas, arco = estado activo, decisión P-E de la Tanda 4),
pero el pulido de jerarquía pide que la banda pasiva baje un escalón. **Decisión:**
P1-3 del plan (rebajar la opacidad de las bandas de referencia en estado crítico).

**3.7 Ticks irregulares/ocultos — ya resuelto; verificación.**
Todos los ticks salen de la misma función polar con los mismos radios
(`layout.lua:280-281`, `renderer.lua:177-203`), 2 px y en el rol claro desde la Tanda 4
(P-C). La percepción del informe se debía a las bandas cercanas a los ticks, ya atenuadas.
**Decisión:** verificación con test; sin cambios de código.

### P2 — detalles

**3.8 RSSI desconectada — se adopta como pulido.**
La etiqueta está debajo del hueco inferior del anillo (nameBox y 130, anillo abierto por
abajo en 45°..135°), sin colisión (verificado con `collide.lua`). El informe la percibe
"como título de otro componente". **Decisión:** acercarla al instrumento (subir ~3–5 px en
la base o recortar el vacío), manteniendo el margen inferior y el audit limpio (P1-2).

**3.9 Unidad no hard-coded — ya satisfecho; verificación.**
La unidad **se lee de la fuente**: `telemetry.unitName` traduce el enum de la radio
(dB/dBm/%/V/mAh/…, `telemetry.lua:29-42`) y `app.lua:159-165` la resuelve en
`Suffix` → batería `%` → unidad del sensor. El `dB` de la captura viene del sensor RSSI
(unidad 17), no de una constante. **Decisión:** sin cambios; test de regresión para
dB/dBm/`%`/vacío.

**3.10 Robusto a 1–3 dígitos — ya satisfecho; ampliar tests.**
El layout es métrico y adaptativo (muestra con margen `widestSample`, `format.lua:45-59`;
auto-fit de fuente, `layout.lua:97-135`; recorte a la cuerda, `layout.lua:55-68`). Los
tests P1-3/P1-4 y la matriz de `collide.lua` cubren la base. **Decisión:** añadir casos
`7`, `100`, `-92` y `---` (sin datos) a la verificación.

**3.11 Código de color / jerarquía rota (2.1) — pulido ya cubierto en P1-3.**
La jerarquía valor → estado → escala es el diseño actual (texto sobre geometría, chip con
borde, bandas atenuadas). El "chip CRIT roba atención" es una opinión de diseño; el
propietario lo mantiene como punto de estado.

### P0 (reabierto) — hallazgos de una revisión visual adicional (Tanda 5, 05 ago 2026)

> Esta sub-sección no viene del informe del diseñador: sale de una inspección pixel a pixel
> de los renders reales (`dev/shots/mode-Rail-crit-v1/v2/v3.png` y
> `mode-Rail-pos1/2/3.png`), contrastada contra `layout.lua`, `renderer.lua`, `theme.lua`,
> `dev/shots.lua` y `tests/mock_env.lua`. Confirma P0-1 y P0-2 (comparando v2 vs v3: la cola
> desaparece, el hueco entre `22` y el pivote/cuerpo de la aguja es real y visible en el
> render) y encuentra dos colisiones aguja-elemento que ni el informe original ni
> `dev/collide.lua` cubren, porque ambos prueban ángulos donde no ocurren.

**3.12 La aguja atraviesa el chip de estado en ángulos "hacia arriba" — nuevo, P0.**
En `mode-Rail-pos2.png` (valor 50, aguja a 270°, estado WARN) el tallo de la aguja sale del
pivote y sube en línea recta, cruzando literalmente el relleno y el texto del pill `WARN`
antes de llegar al borde interior de la pista. Medido en el render (300×240): el pill ocupa
x 115–181 / y ≈54–86; la aguja lo atraviesa verticalmente por su centro (x≈148) en todo ese
rango de y. No es un artefacto del ángulo de prueba: `L.stateBox` se coloca en
`dial.y + floor(dial.h*0.26)` (`layout.lua:344`), centrado horizontalmente en todo el ancho
del dial, y `needleOuter` llega casi al borde interior de la pista
(`L.radius - trackThickness/2 - 1`, `layout.lua:304`) — el chip vive justo en la trayectoria
de cualquier aguja que apunte hacia arriba. Y "hacia arriba" no es un caso raro: con Sweep
270° (`{135,270}`, default de Rail) la aguja apunta a 270° en valor 50 (el punto medio); con
Sweep 180° (`{180,180}`) también pasa por 270° en valor 50; con Sweep 360° (`{270,360}`) la
aguja *empieza* apuntando a 270° en valor 0. En los tres presets hay un valor de escala en el
que la aguja cruza el chip, y el chip solo se muestra en WARN/CRIT/NO DATA/NO LINK/STALE
(`renderer.lua:405-420,431`) — justo los estados que más necesitan destacar.
`dev/collide.lua` no lo detecta: excluye la aguja de **todas** las colisiones de etiqueta,
chip incluido (`dev/collide.lua:69-76`, `sweep[w.ui.needle] = true` sin distinguir chip de
valor). Esa exclusión se justificó para el caso ya documentado en 3.1 (la aguja roza la
esquina del valor; el texto se pinta encima; legible) — pero un pill sólido de 66×30 px
bisecado por el tallo de la aguja no es "rozar una esquina", es partir el elemento en dos.
Aplicar la misma regla aquí es usar el z-order como parche, justo lo que la restricción 2 del
repo prohíbe. **Decisión:** tratarlo como P0 geométrico, no como exclusión de audit. Ver
P0-4 del plan.

**3.13 La aguja tapa la unidad en el cap final — nuevo, P0 → reconsiderado a P2.**
En `mode-Rail-pos3.png` (valor 100, aguja en el cap final, 45°) el cuerpo de la aguja queda
directamente encima de la `d` de `dB`: confirmado recortando y ampliando esa zona del
render — el cuerpo cubre casi por completo el trazo de la letra, dejando solo la `B`
legible. Es estructural, no accidental: el cap final del sweep 270° por defecto es 45°
(entre las 3 y las 6), exactamente el cuadrante donde vive la unidad (a la derecha del
valor). Cualquier valor cercano al máximo de la escala empuja la aguja hacia ese mismo
cuadrante. El informe y P0-2 solo corrigieron la holgura en el **ángulo crítico** (194°,
contra el **valor**); este es el mismo tipo de colisión contra la **unidad**, en el extremo
opuesto del barrido. **Reconsiderado el 05 ago 2026:** el propietario, viendo esta misma
familia de solapamiento en `value-78` (valor grande, aguja cerca), decide que proteger la
unidad geométricamente no vale la pena — prefiere el valor lo más grande posible y la
unidad pequeña o **desactivable** (quien configura el sensor ya sabe la unidad). Pasa de
P0-5 a **P2-5**, sustituido por la opción `ShowUnit`. Ver nota de alcance en P2-5 del plan
(cambia el contrato de opciones, no es un pulido puro).

**3.14 Centrado del chip — 3.5 se reabre con matiz (medido, no solo documentado).**
Aislando el pill del anillo del dial por continuidad de región (no solo por color, que
coincide entre pista y chip) en `mode-Rail-crit-v3.png`: el pill ocupa x 115–181 (66 px), el
texto `CRIT` ocupa x 127–173 (46 px) → margen izquierdo 12 px, margen derecho 8 px. No es
percepción óptica de las letras: el texto está 2 px a la derecha del centro real del pill,
con un reparto de aire 12:8 (50 % más a la izquierda). 3.5 se cerró como "ya resuelto"
citando la fórmula de centrado **vertical** (`chipOff`, `renderer.lua:303`), correcta — pero
esa fórmula no toca el eje horizontal, y el ancho del pill se calcula con `T.textWidth` →
`lcd.sizeText` (`theme.lua:111-123`), la métrica real de fuente **en el dispositivo**.
Contrastando en el código: **el desajuste medido es del pipeline de capturas, no del
widget.** `tests/mock_env.lua:168-179` stubea `lcd.sizeText` como `#texto * 0.55 * alto`
(monoespaciado), y `dev/shots.lua:89` usa la misma fórmula para maquetar el SVG — pero el
`<text>` real del SVG se dibuja con `font-family="DejaVu Sans, Verdana, sans-serif"`
(`dev/shots.lua:171`), una fuente proporcional. `CRIT` tiene una `I` angosta: la fórmula
monoespaciada sobreestima su ancho, así que la caja calculada no coincide con la tinta real
de DejaVu — de ahí el 12:8. En el radio real `lcd.sizeText` mide la fuente que de verdad se
dibuja, así que este desajuste concreto **no tiene por qué reproducirse en hardware**.
**Decisión:** no corregir el centrado a ciegas contra el screenshot (riesgo de sobre-corregir
un problema que es del renderer de `dev/`, no del widget); verificar primero contra una
captura de simulador/radio real, o mejorar `textW`/`sizeText` de `dev/` para que dejen de
mentir sobre el ancho de fuente antes de fiarse de una medida en píxeles de estas capturas.
Ver P1-4 revisado.

**3.15 Aire muerto entre el valor y `RSSI` — nuevo, P1 (detectado en revisión visual).**
En capturas balanced (`mode-Rail-crit`, base 200×160) queda un hueco vertical notable entre
la caja del valor y la etiqueta de nombre. Los dos elementos no se hablan entre sí:
`nameBox` se ancla al fondo del `dial` (`dial.y + dial.h - nameH`, `layout.lua:354`)
independientemente de dónde termine la tinta del valor, mientras que `valueRegion` reserva
una banda proporcional fija (`dial.h*0.26`, `layout.lua:251-252`) casi siempre más alta que
el texto que contiene. El hueco crece o encoge con el tamaño de zona sin que nadie lo
controle. Con ese aire disponible, subir el valor un escalón en la rampa (`STDSIZE`→`M`,
`theme.lua:45`) es viable en más zonas de las que hoy lo usan, y/o repartir mejor
`minMaxBox`/`nameBox` en ese tramo. **Decisión:** P1-5 del plan — no es solo estético: más
tamaño de fuente en el valor es la jerarquía visual correcta (es el dato más importante del
dial) y hoy se degrada antes de lo necesario porque `valueRegion` no usa el espacio que sí
tiene libre debajo.

### Correcciones al informe (metodología)

- Varias medidas describen la captura **v1** (pre-Tanda 4): pivote anillo+punto, aguja de
  6 px roma, badge de 4 px, ticks de 1 px. En `mode-Rail-crit-v2` (la referencia citada
  en §9 del informe) todo eso ya está corregido. Lo que sigue vigente en v2 es lo que este
  doc adopta: cruce sutil aguja-valor, muñón de cola, bloque visible desplazado, ámbar en
  CRIT y RSSI separada.
- El "díal inclinado" del muestreo de color (§3 del informe) es el bloque `22 dB`
  desplazado (3.4), no el arco: el arco es geométricamente simétrico y el grupo reservado
  está centrado.
- "RSSI + 22 dB" correcto para esta fuente: el widget no asume la unidad (3.9).

---

## 4. Plan de reparación (pulido)

### P0 — aguja y zona central (hacer primero)

| # | Cambio | Ficheros | Estado |
|---|---|---|---|
| P0-1 | **Eliminar la cola/gancho** (`ui.tail`): borrar su creación, su escritura `pts` por frame y su color; quitar `tailOuter` y `ratio.tailLength`. La aguja queda cuerpo + punta + pivote | `renderer.lua` (buildNeedle, applyColors, updateArc), `layout.lua`, `theme.lua`, `dev/collide.lua`, `DOCS.md`, `smoke_test.lua` | ✅ Done — la aguja es solo cuerpo + punta + pivote; test P-A actualizado (`w.ui.tail == nil`); -1 objeto por frame |
| P0-2 | **Holgura de valor**: bajar la región de valor ~5–9 px en la base (balanced normal) para dejar aire real entre la celda de tinta y el pivote/banda del cuerpo en ángulos críticos. La fila min/max no puede salir de su cuerda (G-7). Acompañado de `STDSIZE` en la rampa de fuentes (16 px) para que la degradación por la cuerda sea 24→16 y no 24→13 (AUDIT P3-4); la unidad no cambia (skip de STD en `smallerFont`) | `layout.lua` (valueRegion + `valueDrop = T.px(7)`), `theme.lua` (RAMP + smallerFont), `tests/smoke_test.lua` | ✅ Done — 200×160: valor 24→16 px, y 71→82, 5 px libres bajo el pivote; aguja a 194° a 11 px de la celda; 200×200/260×220 conservan su fuente; fila min/max dentro de su cuerda; collide 18/18 |
| P0-3 | Punta definida + hub sólido (ya ✅ Tanda 4) | — | ✅ mantener + test existente |
| P0-4 | **Aguja vs. chip de estado** (3.12): el chip WARN/CRIT/NO DATA/... vive en la trayectoria vertical de la aguja para algún valor de la escala, en los 3 presets de Sweep. Recorta el alcance de la aguja (`needleOuter`/`needleBodyOuter`/`needleTipInner`) al radio de entrada al pill (método de slabs, `G.rayBoxEntry`) menos 2 px, solo cuando el chip está visible y el ángulo actual lo cruzaría; el resto de ángulos no se toca | `geometry.lua` (`rayBoxEntry`), `renderer.lua` (`needleReach`, `updateArc`, `updateChip`→`frame.chipBox`, `L.chipOff`), `bar.lua` (`L.chipOff` que faltaba) | ✅ Done — confirmado en `mode-Rail-pos2.png` (valor 50): el tallo ya no cruza el pill, se detiene ~2 px antes de su borde; test de regresión propio; suites 38/38+90/90, collide 18/18. **`dev/collide.lua` sigue sin comprobarlo por sí solo** (la exclusión de la aguja en `dev/collide.lua:69-76` no distingue chip de valor) — pendiente extenderlo, ver §6 |

### P1 — composición y jerarquía

| # | Cambio | Ficheros | Estado |
|---|---|---|---|
| P1-1 | **Centrar la tinta visible** del valor en su caja (align CENTER) y re-anclar la unidad a la tinta en cada cambio de valor (guardado por `valueStr`). Bloque visible centrado ±2 px para cualquier ancho; vecinos y cuerda intactos; el dígito de unidades se mueve dentro de la caja reservada | `layout.lua` (`placeValue`, `valueAlign`), `renderer.lua` (`M.anchorUnit`, `updateText`), `bar.lua` (llama `R.anchorUnit`) | ✅ Done — probado con matemática, no solo visual: con la tinta centrada en una caja de ancho fijo, su propio centro es siempre `vw/2` sin importar el ancho real, así que anclar la unidad justo después de la tinta reproduce el centro del grupo RESERVADO de forma exacta, no aproximada. Confirmado en `mode-Rail-crit.png`: `22 dB` se movió a la izquierda, ya no a +12 px del centro. Test de regresión propio (1 vs 2 dígitos, ≤2 px); suites 38/38+92/92, collide 18/18 |
| P1-2 | **RSSI más cerca**: subir ~3–5 px en la base o recortar el vacío inferior; margen inferior seguro y `collide.lua` limpio | `layout.lua:349` (nameBox balanced) | ✅ Cubierto por P1-5 (mismo cambio: `nameBox` ya sube hacia el contenido real) |
| P1-3 | **Jerarquía en CRIT**: rebajar la banda de referencia pasiva en estado crítico (`opacity.railBand` 200 → ~160, o un umbral por estado) para que el ámbar y el rojo de la banda no compitan con el rojo del estado | `theme.lua:63` (`opacity.railBandCrit = 160`), `renderer.lua` (`applyColors`) | ✅ Done — solo se rebaja mientras `colorKey == "critical"`; WARN conserva la opacidad normal (ahí el ámbar SÍ es el estado activo). Medido en píxel: banda ámbar pasa de (181,144,57) a (149,121,51) en CRIT, coincide con la predicción 200→160 casi exacto. Test de regresión propio; suites 38/38+92/92, collide 18/18 |
| P1-4 | Chip `CRIT`: el padding horizontal medido (12 px izq. / 8 px der., 3.14) es casi seguro un artefacto de `dev/shots.lua`+`mock_env.lua` (ancho monoespaciado 0.55×alto vs. DejaVu proporcional real), no del widget (que usa `lcd.sizeText` real vía `T.textWidth`). **No tocar `updateChip` a ciegas contra el screenshot.** Primero: verificar en simulador/radio real o corregir `textW` de `dev/` para que mida como DejaVu; solo si el desajuste sobrevive esa verificación, ajustar el centrado. Test de regresión que fija padding/borde (ya métrico) sigue en pie | `dev/shots.lua:89`, `tests/mock_env.lua:168-179` (verificación); `tests/smoke_test.lua` (test) | pendiente — **verificar antes de "arreglar"** |
| P1-5 | **Aprovechar el aire muerto** (3.15 — pedido explícito del propietario 05 ago 2026): `nameBox` se ancla al fondo del dial sin enterarse de dónde termina `minMaxBox`/`valueBox`. Parte ✅: `nameBox` ahora sube hasta `minMaxBox.y + minMaxBox.h + xs`, con la posición vieja como suelo (nunca peor que antes) — confirmado por comparación directa antes/después en `mode-Rail-crit.png`, el hueco antes de `RSSI` se redujo visiblemente. Parte pendiente: **agrandar la fuente del valor** en sí. El ancho disponible en la Y del valor está gobernado por el *chord* del dial (`clipToChord`), no por la altura de la región — acercar el valor al centro ganaría chord para un tipo más grande, pero es exactamente lo que `valueDrop` (P0-2) alejó para separarlo del pivote/aguja, y ese trade-off tiene un test con nombre propio (*P0-2: the value cell clears the hub...*). El propietario ya aceptó que la aguja pase detrás de un valor más grande (ver 3.13/P2-5) — falta decidir cuánto de `valueDrop` se cede a cambio y actualizar ese test a propósito, no por accidente | `layout.lua` (`nameBox` ✅; `valueRegion`/`valueDrop` pendiente), `theme.lua` (RAMP, si se decide subir la fuente) | 🟡 parcial — dead space cerrado; tamaño de fuente pendiente de decisión explícita sobre `valueDrop` |

### P2 — verificación y robustez

| # | Cambio | Ficheros | Estado |
|---|---|---|---|
| P2-1 | Ticks: test que fija radio/longitud/espesor uniformes (función polar única) | `tests/` | pendiente |
| P2-2 | Unidad: test para dB / dBm / `%` / vacío (ya de la fuente, no hard-coded) | `tests/` | pendiente |
| P2-3 | Robustez: casos `7`, `100`, `-92`, `---` (sin datos) y out-of-scale en la matriz de verificación | `dev/collide.lua` / `tests/` | pendiente |
| P2-4 | Z-order: pintar el chip antes de los textos de valor (orden 4.1 del informe) — sin efecto visual hoy, elimina el riesgo de que el pill tape texto si alguna vez se solapan | `renderer.lua` build | opcional, bajo riesgo |
| P2-5 | **Aguja vs. unidad en el cap final** (3.13, nuevo) — *reconsiderado 05 ago 2026*: el propietario prioriza el tamaño del valor sobre proteger la unidad de la aguja (ver P1-5) y propone que la unidad sea pequeña y/o **opcional** (`ShowUnit`, on/off), ya que quien configura el sensor ya sabe la unidad. Baja de P0 a P2: no requiere blindaje geométrico si la unidad puede ocultarse. Añadir una opción nueva cambia el contrato declarado (`DOCS.md`, conteo de opciones — ver commit `2233ac34d`), así que **no entra sola en un "pulido"**: requiere decisión de alcance explícita antes de tocar `main.lua`/`DOCS.md` | `layout.lua` (showUnit ya existe internamente por modo; falta el toggle de usuario), `main.lua` (nueva opción), `DOCS.md` | pendiente — **bloqueado por decisión de alcance** |

### No se adopta (motivo)

| Propuesta del informe | Motivo |
|---|---|
| Aguja como triángulo (`drawFilledTriangle`, §5.3) | AUDIT.md P2-1: churn de heap por frame en la STM32. La punta ya se logra con dos líneas (P0-3) |
| Sistema base 300×240 con letterboxing (§5.1) | El widget ya escala por `zone.w/h` reales + `LCD_SCALE`; la base canónica de medidas es 200×160 y la captura es ×1.5. Cambiar el modelo no aporta y arriesga regresiones |
| Reescribir la gramática de estados por etapas (§6) | Normal / WARN / CRIT / NO DATA / ERR ya existen (chip + color + pulso); se refina, no se rehace |
| Rediseñar la zona crítica como overlay independiente | Ya es overlay concéntrico (radio 61, grosor 3 vs 11, gap 1) desde la Tanda 4 |
| Usar el z-order para ocultar malas composiciones | Contrario a la restricción 2: se corrige geometría |

---

## 5. Orden de dibujo (verificación)

El orden actual es ya el del informe (§4.1) con una salvedad: `pista/rails → ticks →
ghost → arco de valor → aguja (cuerpo, punta) → pivote → marcadores → textos → chip →
etiquetas de escala`. El chip se crea **después** de los textos de valor
(`renderer.lua:293-325`): no se solapan hoy, pero P2-4 los reordena para cumplir
estrictamente "chip antes que texto" y eliminar el riesgo. No se usa el z-order para
ocultar la aguja bajo el valor: la aguja se arregla en geometría (P0-1/P0-2).

## 6. Verificación tras cada cambio

- `dev/collide.lua` limpio en la matriz de 12 zonas + extremos + barridos (hoy: 18/18 ✅).
  **Sigue pendiente extender la matriz** para que el chip SE COMPRUEBE contra la aguja ahí
  también — la exclusión de `dev/collide.lua:69-76` sigue sin distinguir chip de valor; P0-4
  quedó cubierto por un test dedicado en `smoke_test.lua` en su lugar, no por el audit.
  Mantener la exclusión solo para la tinta del valor (contrato 3.1) el día que se toque.
- Barrido de valores 0/25/50/75/100 en los 3 presets de Sweep (270/180/360) con estado
  WARN/CRIT forzado, para encontrar el ángulo en que la aguja cruza `stateBox` en cada uno
  (P0-4) — el "value 78" fijo que usa hoy `dev/collide.lua:191` no lo habría encontrado.
- Suites `run_tests.lua` (38) y `smoke_test.lua` (92) verdes; tests de regresión de este
  plan añadidos (✅ P0-1 sin cola, ✅ P0-2 holgura, ✅ P0-4 aguja/chip, ✅ P1-1 centrado,
  ✅ P1-3 jerarquía CRIT; pendientes: P1-4, P2-1, P2-2, P2-3).
- Antes de tocar el centrado del chip (P1-4): confirmar en simulador/radio real que el
  desajuste 12:8 de 3.14 no es del `sizeText` monoespaciado de `dev/`. No usar solo el
  screenshot de `dev/shots.lua` como prueba.
- Regenerar `dev/shots/*.svg|png` (incl. `mode-Rail-crit` y `mode-Rail-pos1/2/3`) y
  `dev/audit-preview.html` para re-revisión del mismo frame.

## 7. Criterios de aceptación (base 200×160)

- ☐ La tinta del valor no toca pivote ni chip en 1–4 caracteres, negativos, fuera de escala
  y sin datos (probe + `collide.lua`). *Relajado por P1-5 (decisión explícita del
  propietario, 05 ago 2026): a mayor tamaño de valor, la banda de la aguja puede pasar por
  detrás de la tinta — el contrato "texto sobre geometría" (§1, restricción 2) sigue
  garantizando legibilidad; lo que no se permite es que dejen de ser identificables.*
- ☑ **La aguja no biseca el chip de estado** — P0-4 done, test de regresión propio
  (Sweep 270° verificado; 180°/360° comparten la misma `rayBoxEntry` así que quedan
  cubiertos por construcción, pero no tienen un caso de test dedicado todavía).
- ☑ El bloque visible valor+unidad queda centrado ±2 px respecto al centro del dial —
  P1-1 done, test de regresión propio (1 vs 2 dígitos, ≤2 px de diferencia).
- ☑ La aguja tiene punta definida (2 px) y base constante (6 px) en todos los ángulos, y
  **no tiene cola** — P0-1/P0-3, ya verificado en tandas previas.
- ☑ En coincidencia angular, la zona crítica y la aguja se distinguen (banda pasiva < 255)
  — P1-3 done: 200 fuera de CRIT, 160 en CRIT, test de regresión propio.
- ☐ `CRIT`/`WARN` centrado por métricas reales de fuente (verificado en dispositivo o con
  `sizeText` de `dev/` corregido, no con la captura tal cual — 3.14) y fijado por test.
- ☐ Ticks idénticos en radio, longitud y espesor (test).
- ☐ Gramática cromática única por estado: normal / warn / crit / no-data / error,
  documentada (bandas = referencia pasiva; arco + texto = estado activo).
- ☐ La unidad viene de la fuente (dB/dBm/`%`/vacío), nunca hard-coded (test).
- 🟡 El valor usa el aire disponible bajo el dial (P1-5): `nameBox` ya sube hacia el
  contenido real (done); un escalón más de fuente sigue pendiente de decidir cuánto
  `valueDrop` se cede.
- ☐ Matriz de verificación en 200×160, 480×272, 800×480 y zona compacta real
  (`dev/collide.lua`).
- ☑ Suites verdes (38/38, 92/92) y renders regenerados (`mode-Rail-crit.png` es ahora v5,
  `mode-Rail-pos1/2/3.png`) — 05 ago 2026.

> **Fuera de alcance de esta tanda (pendiente de decisión):** opción `ShowUnit` para
> ocultar la unidad (P2-5) — cambia el contrato de opciones declarado; no es un "pulido",
> es una feature nueva. Ver nota de alcance en P2-5. **No confundir con `ShowChip`**
> (§8 abajo), que es una opción distinta, ya implementada esta misma ronda, para el pill
> de estado — no para la unidad.

---

## 8. Adenda — mejoras del propietario, 3.ª ronda (05 ago 2026)

Tres pedidos explícitos del propietario a partir de la revisión visual de §0-§7, ninguno
originado en el informe del diseñador. Los dos primeros son geometría/tema (pulido, sin
tocar el contrato); el tercero SÍ cambia el contrato de opciones — a diferencia de
`ShowUnit`/P2-5, este se implementó porque el propietario lo pidió explícitamente
("analiza, planea y haz esos cambios"), no quedó pendiente de decisión.

**8.1 Verde por defecto en estado normal.**
`stateColor()` resolvía el estado "normal" a `accent or M.color.accent`, y `M.color.accent`
era `COLOR_THEME_PRIMARY1` (blanco). El primer intento — añadir un rol `M.color.normal`
verde y usarlo solo como fallback — no funcionó: la opción `Accent` (declarada en
`main.lua`, `since = 212`) **siempre** entrega un color real como su propio default
(`COLOR_THEME_PRIMARY1`), nunca `nil`, así que en cualquier radio 2.12+ `widget.accent`
nunca cae al fallback — el fallback era código muerto en la práctica. La causa raíz estaba
en el default de la opción, no en `stateColor`. Arreglo: `M.color.accent` pasa a
`COLOR_THEME_ACTIVE` (verde) y el default de `Accent` en `main.lua` pasa a
`COLOR_THEME_ACTIVE` también — mismo rol en los dos sitios, para que 2.11 (sin la opción,
`widget.accent = nil`) y 2.12+ (opción siempre presente) terminen en el mismo color.
Afecta también a Static (antes blanco, ahora verde por defecto) — coherente con "el color
por defecto de este gauge es verde", no solo los modos con estado. El Accent del usuario
sigue ganando si lo cambia. Test de regresión propio (normal = verde; Accent explícito
sigue ganando).

**8.2 Aguja de color fijo, nunca sigue el estado.**
`applyColors` pintaba la aguja con el mismo color que el arco/valor (`c`, dependiente de
`colorKey`) — antes de este cambio la aguja pasaba a blanco/verde en normal, ámbar en
WARN, rojo en CRIT. Nuevo rol `T.color.needle = COLOR_THEME_PRIMARY1`, fijado **una sola
vez** en `buildNeedle` (no en cada cambio de estado) y quitado de `applyColors` — la aguja
ya no se reescribe por color en absoluto, ahorra dos `setProp` por transición de estado
además de resolver el pedido. Con 8.1 puesto en verde, esto además evita que la aguja se
mimetice con el arco en estado normal. Confirmado visualmente: blanca en normal (verde),
WARN (ámbar) y CRIT (rojo) por igual. Test de regresión propio (color idéntico en los 3
estados).

**8.3 `ShowChip`: el pill de estado pasa a opcional — cambia el contrato.**
Nueva opción `{ key = "ShowChip", label = "State chip", type = BOOL, field = "showChip",
since = 212, default = 1 }`, añadida al **final** de `DEFS` en `main.lua` (append-only,
restricción del contrato — nunca insertar en medio, desplazaría los valores guardados de
modelos existentes). `layout.lua` combina el cálculo existente de `L.showState` (que ya
ocultaba el chip en modo `micro`/zonas de barra angostas) con `cfg.showChip ~= false` — el
chip solo se construye si el layout lo permite Y el usuario no lo desactivó; `~= false` en
vez de comprobar `nil` para que cualquier caller/test que nunca toque el campo siga viendo
el default declarado (on). No hizo falta tocar `renderer.lua`/`bar.lua`: como
`ui.chip`/`ui.stateLabel` ya solo se construyen `if L.showState`, apagar la opción los deja
sin construir por el mismo mecanismo que ya usa el modo micro — cero lógica nueva en el
renderer. Verificado con `ShowChip = false` en estado crítico: sin pill, sin texto de
estado, resto del dial intacto. Dos tests de regresión (apagado oculta todo; el default
sigue encendido).

**Verificación de la 3.ª ronda:** suites 38/38 + 96/96 (+4 tests nuevos: verde, aguja fija,
ShowChip on/off), `dev/collide.lua` limpio (18/18), contrato de opciones intacto (`2.11
declara exactamente diez`, `2.12 declara el set completo`, `translate cubre cada opción`).
Nuevo shot `dev/shots/mode-Rail-nochip.png` (Rail, crítico, chip apagado) para
trazabilidad visual del toggle.
