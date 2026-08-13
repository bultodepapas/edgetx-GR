# Resultado técnico y visual — fase 3

**Fecha:** 2026-08-12

**Alcance:** jerarquía de track/arco, límites Threshold y silueta Needle

**Estado:** completada; fases 4–5 cerradas posteriormente

**Plan origen:** [DESIGN-FEEDBACK-PLAN-2026-08-12.md](DESIGN-FEEDBACK-PLAN-2026-08-12.md)

## Resultado ejecutivo

Needle y Arc ya expresan dos jerarquías coherentes. En Needle, la aguja es la
indicación primaria y el arco activo queda como una señal secundaria de
posición con 60–64% del grosor del track. En Arc, el arco sigue siendo la
geometría primaria y conserva el 100% del track.

Los límites `Threshold` dejaron de parecer ticks ordinarios: cada límite
interior sigue siendo una sola línea retenida en su ángulo exacto, cruza todo
el track, sobresale 2 px hacia los ticks y usa un trazo un nivel más grueso.
No se añadieron labels, triángulos, canvas ni objetos decorativos.

La aguja conserva tres `lvgl.line`, sus buffers y wrappers persistentes y el
`lvgl.set` directo. El base/mid/tip pasa aproximadamente por 30%/66%/100% del
alcance, con anchos 6/4/2 px en la referencia 400×160. El hub se redujo de 5 a
4 px donde la escala física lo permite.

## Evidencia visual nativa

Los PNG son recortes nativos exactos de 400×160. El before es la salida cerrada
de fase 2; el after fue capturado con el simulador EdgeTX después de fase 3.

| Estado | Before | After |
|---|---|---|
| NORMAL | [PNG](phase03/before/dial-wide-tx-voltage.png) | [PNG](phase03/after/dial-wide-tx-voltage.png) |
| WARN | [PNG](phase03/before/dial-wide-tx-warn.png) | [PNG](phase03/after/dial-wide-tx-warn.png) |
| CRIT | [PNG](phase03/before/dial-wide-tx-crit.png) | [PNG](phase03/after/dial-wide-tx-crit.png) |
| NO DATA | [PNG](phase03/before/dial-wide-tx-nodata.png) | [PNG](phase03/after/dial-wide-tx-nodata.png) |
| Min/max text | [PNG](phase03/before/dial-wide-tx-history.png) | [PNG](phase03/after/dial-wide-tx-history.png) |

Control de no regresión visual de Arc:
[PNG](phase03/after/dial-wide-arc-control.png).

Inspección visual:

- El track neutro vuelve a leerse como escala completa; el arco activo Needle
  ya no forma una segunda banda pesada.
- El límite exacto sobresale del track y se diferencia de los ticks azules sin
  depender únicamente del color.
- La aguja conserva alcance completo, pero la transición base/mid/tip y el hub
  se perciben más limpios.
- Arc conserva su peso completo y no hereda el adelgazamiento de Needle.
- No aparecen clipping, costuras, puntos negativos, solapes ni cambios en la
  composición de valor, unidad, cabecera o footer.
- La variación de tono del badge CRIT entre capturas pertenece a su animación;
  fase 3 no modifica estado, color ni movimiento del badge.

## Métricas geométricas

Medidas reproducibles en Dial 400×160:

| `LCD_SCALE` | Track | Arco Needle | Ratio | Tick | Threshold | Labio | Hub |
|---:|---:|---:|---:|---:|---:|---:|---:|
| 0.800 | 10 px | 6 px | 60.0% | 2 px | 3 px | 2 px | 5 px |
| 1.000 | 11 px | 7 px | 63.6% | 2 px | 3 px | 2 px | 4 px |
| 1.375 | 11 px | 7 px | 63.6% | 3 px | 4 px | 2 px | 4 px |

Arc conserva 10/11/11 px respectivamente: exactamente el grosor del track.
Las marcas se calculan desde `trackThickness`, no desde el arco fino.

## Recursos y regresión

| Gate | Resultado |
|---|---:|
| Pruebas puras | 72/72 |
| Smoke/geométricas | 219/219 |
| Contratos split | 17/17 |
| `luacheck` de archivos afectados | 0 warnings / 0 errors |
| Colisiones, incluida 400×160 | todas limpias |
| Objetos Dial 400×160 | 24; con historial 26, sin incremento |
| Dial Needle estable | 14 B/frame |
| Dial Arc estable | 13 B/frame |
| Needle ordinario | 1488 instrucciones/frame |
| Peor callback medido | 9400/20000 instrucciones |
| Bar motion, 48 casos | PASS |
| Capturas nativas | 5 before/after + 1 control Arc, PASS |

No se añadió ninguna tabla por frame. El movimiento reutiliza los tres buffers
de puntos, sus tres wrappers y los cuatro objetos de aguja/hub.

## Archivos funcionales modificados

- `theme.lua`: ratios semánticos de arco Needle, labio Threshold, taper y hub.
- `dial_layout.lua`: resolución separada de track/arco, geometría de límites y
  proporciones de aguja.
- `dial_renderer.lua`: límites construidos desde la geometría del track.
- `tests/smoke_test.lua`: contratos en las tres escalas, control Arc, ángulos
  exactos y retención de objetos.

## Decisión de cierre

Fase 3 queda cerrada. La presentación conservadora del nombre y la aceptación
integral se completaron posteriormente sin cambiar el identificador interno de
telemetría; véase
[PHASE-04-05-RESULTS-2026-08-12.md](PHASE-04-05-RESULTS-2026-08-12.md).
