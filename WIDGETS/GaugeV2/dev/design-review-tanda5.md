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
> **v3** (código actual), con copia versionada `mode-Rail-crit-v3.*`; `mode-Rail-crit-v1.*`
> y `-v2.*` se conservan como trazabilidad. Las variaciones de posición son
> `mode-Rail-pos1` (valor 0, aguja en el cap inicial), `mode-Rail-pos2` (valor 50, aguja
> arriba) y `mode-Rail-pos3` (valor 100, aguja en el cap final).

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

### P1 — composición y jerarquía

| # | Cambio | Ficheros | Estado |
|---|---|---|---|
| P1-1 | **Centrar la tinta visible** del valor en su caja (align CENTER) y re-anclar la unidad a la tinta en cada cambio de valor (guardado por `valueStr`). Bloque visible centrado ±2 px para cualquier ancho; vecinos y cuerda intactos; el dígito de unidades se mueve dentro de la caja reservada | `layout.lua:159` (valueAlign), `renderer.lua` updateText (+ bar.lua) | pendiente |
| P1-2 | **RSSI más cerca**: subir ~3–5 px en la base o recortar el vacío inferior; margen inferior seguro y `collide.lua` limpio | `layout.lua:349` (nameBox balanced) | pendiente |
| P1-3 | **Jerarquía en CRIT**: rebajar la banda de referencia pasiva en estado crítico (`opacity.railBand` 200 → ~160, o un umbral por estado) para que el ámbar y el rojo de la banda no compitan con el rojo del estado | `theme.lua:63`, `renderer.lua:168` | pendiente (recomendado) |
| P1-4 | Chip `CRIT`: sin cambios funcionales; **test de regresión** que fija padding/centrado/borde (ya métrico) | `tests/smoke_test.lua` | pendiente |

### P2 — verificación y robustez

| # | Cambio | Ficheros | Estado |
|---|---|---|---|
| P2-1 | Ticks: test que fija radio/longitud/espesor uniformes (función polar única) | `tests/` | pendiente |
| P2-2 | Unidad: test para dB / dBm / `%` / vacío (ya de la fuente, no hard-coded) | `tests/` | pendiente |
| P2-3 | Robustez: casos `7`, `100`, `-92`, `---` (sin datos) y out-of-scale en la matriz de verificación | `dev/collide.lua` / `tests/` | pendiente |
| P2-4 | Z-order: pintar el chip antes de los textos de valor (orden 4.1 del informe) — sin efecto visual hoy, elimina el riesgo de que el pill tape texto si alguna vez se solapan | `renderer.lua` build | opcional, bajo riesgo |

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
- Suites `run_tests.lua` (38) y `smoke_test.lua` (88) verdes; tests de regresión de este
  plan añadidos (P1-4, P2-1, P2-2, P2-3, P0-1 sin cola, P0-2 holgura).
- Regenerar `dev/shots/*.svg|png` (incl. `mode-Rail-crit`) y `dev/audit-preview.html` para
  re-revisión del mismo frame.

## 7. Criterios de aceptación (base 200×160)

- ☐ La tinta del valor no toca pivote, banda de aguja, chip ni rail en 1–4 caracteres,
  negativos, fuera de escala y sin datos (probe + `collide.lua`).
- ☐ El bloque visible valor+unidad queda centrado ±2 px respecto al centro del dial en la
  referencia 200×160, para valores de 1 y de 4 caracteres.
- ☐ La aguja tiene punta definida (2 px) y base constante (6 px) en todos los ángulos, y
  **no tiene cola**.
- ☐ En coincidencia angular, la zona crítica y la aguja se distinguen (banda pasiva < 255).
- ☐ `CRIT` centrado por métricas y fijado por test.
- ☐ Ticks idénticos en radio, longitud y espesor (test).
- ☐ Gramática cromática única por estado: normal / warn / crit / no-data / error,
  documentada (bandas = referencia pasiva; arco + texto = estado activo).
- ☐ La unidad viene de la fuente (dB/dBm/`%`/vacío), nunca hard-coded (test).
- ☐ Matriz de verificación en 200×160, 480×272, 800×480 y zona compacta real
  (`dev/collide.lua`).
- ☐ Suites verdes (38/38, 88/88) y renders regenerados para revisión.
