# Resultado técnico y visual — fase 2

**Fecha:** 2026-08-12

**Alcance:** jerarquía de valor y unidad en DialPro horizontal normal/large

**Estado:** completada y aprobada para continuar con fase 3

**Plan origen:** [DESIGN-FEEDBACK-PLAN-2026-08-12.md](DESIGN-FEEDBACK-PLAN-2026-08-12.md)

## Resultado ejecutivo

La unidad ya no compite con el valor en DialPro 400×160. El valor conserva el
primer nivel visual; la unidad selecciona el font disponible más cercano al
40% de su altura, nunca supera 50%, respeta un suelo legible `XS` y usa el gap
`sm`. La política existe solo en el Dial horizontal `normal/large`.

`placeValue` y `pickValueFont` conservan sus defaults cuando no reciben una
política. BarPro no la pasa y mantiene tanto su tipografía como sus cajas de
referencia. `L.unitGap` es ahora la única fuente del gap resuelto para layout y
para el reanclaje vivo de `ui_core.anchorUnit`.

## Evidencia visual nativa

Los PNG son recortes nativos exactos de 400×160. El before es la salida
aprobada de fase 1; el after se capturó de nuevo con el simulador EdgeTX tras
implementar fase 2.

| Estado | Before | After |
|---|---|---|
| NORMAL | [PNG](phase02/before/dial-wide-tx-voltage.png) | [PNG](phase02/after/dial-wide-tx-voltage.png) |
| WARN | [PNG](phase02/before/dial-wide-tx-warn.png) | [PNG](phase02/after/dial-wide-tx-warn.png) |
| CRIT | [PNG](phase02/before/dial-wide-tx-crit.png) | [PNG](phase02/after/dial-wide-tx-crit.png) |
| NO DATA | [PNG](phase02/before/dial-wide-tx-nodata.png) | [PNG](phase02/after/dial-wide-tx-nodata.png) |
| Min/max text | [PNG](phase02/before/dial-wide-tx-history.png) | [PNG](phase02/after/dial-wide-tx-history.png) |

Inspección visual:

- La `V` queda inequívocamente asociada al número y deja de funcionar como un
  segundo valor dominante.
- El valor, la cabecera, el badge, el dial y el footer no cambian de posición.
- NORMAL, WARN, CRIT, NO DATA e historial conservan el mismo centro óptico.
- No hay clipping, wrapping, colisiones ni pérdida de contraste observables.
- La variación de tono del badge CRIT entre capturas corresponde a la fase de
  su animación retenida; la fase 2 no modifica color, estado ni movimiento.

## Métricas de la política

Medidas reproducibles del mock sobre la zona 400×160:

| `LCD_SCALE` | Valor | Valor/zona | Unidad | Unidad/valor | Gap `sm` |
|---:|---:|---:|---:|---:|---:|
| 0.800 | 54 px | 33.8% | 23 px | 42.6% | 3 px |
| 1.000 | 69 px | 43.1% | 29 px | 42.0% | 4 px |
| 1.375 | 71 px | 44.4% | 27 px | 38.0% | 6 px |

En escala 0.8, `XXL` mide 54 px y es el mayor font que expone el firmware: no
existe un escalón intermedio para alcanzar el suelo ideal de 35% (56 px). Se
acepta 33.8% como límite honesto de la rampa discreta; la unidad sí permanece
dentro de su objetivo y de su máximo.

La secuencia `--`, `9.9`, `10.0`, `-8.8` conserva el centro del grupo sin
desplazamiento medible en el mock y mantiene en cada refresh el gap resuelto.

## No regresión de BarPro

La referencia BarPro 300×70 permanece exacta con `LCD_SCALE=1`:

| Caja | Geometría |
|---|---:|
| Valor | `127,5,33,12` |
| Unidad | `166,4,6,12` |
| Gap | `md = 6 px` |

BarPro mantiene 17 objetos retenidos en la escena de referencia y no recibe
ningún objeto, opción ni ruta tipográfica nueva.

## Gates ejecutados

| Gate | Resultado |
|---|---:|
| Pruebas puras | 72/72 |
| Smoke/geométricas | 216/216 |
| Contratos split | 17/17 |
| `luacheck` de archivos afectados | 0 warnings / 0 errors |
| Colisiones, incluida 400×160 | todas limpias |
| Objetos Dial 400×160 | 24; con historial 26, sin incremento |
| Dial estable | 13–14 B/frame |
| Dial Needle ordinario | 1488 instrucciones/frame |
| Peor callback medido | 9400/20000 instrucciones |
| Motion Bar, 48 casos | PASS |
| Capturas nativas focalizadas | 5/5 PASS |

## Archivos funcionales modificados

- `layout_common.lua`: política opcional, selección por ratio y `L.unitGap`.
- `dial_layout.lua`: política limitada al horizontal normal/large.
- `ui_core.lua`: reanclaje vivo con el gap resuelto.
- `tests/smoke_test.lua`: tres contratos de fase 2, incluida la geometría
  exacta de BarPro.

## Decisión de cierre

Fase 2 queda cerrada. Track, arco, marcas de umbral y silueta de aguja fueron
resueltos posteriormente en
[fase 3](PHASE-03-RESULTS-2026-08-12.md), sin reabrir la composición ni la
política tipográfica ya verificadas.
