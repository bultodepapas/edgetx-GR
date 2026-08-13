# Resultado técnico y visual — fases 0 y 1

**Fecha:** 2026-08-12

**Alcance:** baseline de decisión y recomposición horizontal de DialPro

**Estado:** cerrado; fase 2 completada posteriormente

**Plan origen:** [DESIGN-FEEDBACK-PLAN-2026-08-12.md](DESIGN-FEEDBACK-PLAN-2026-08-12.md)

## Resultado ejecutivo

DialPro 400×160 ya se lee como un solo instrumento. El nombre y el estado comparten una cabecera estable, el valor ocupa un área principal explícita y el historial usa un footer que desaparece por completo cuando no se solicita o no cabe. WARN, CRIT y NO DATA no cambian la posición vertical del valor.

El cambio está limitado a `orientation == "horizontal"` en modos `normal/large`. Balanced, vertical, compact, micro y todo BarPro conservan sus rutas previas.

## Evidencia visual

Los PNG son recortes nativos exactos de 400×160, tomados desde la zona superior derecha de una pantalla EdgeTX 800×480.

| Estado | Before | After |
|---|---|---|
| NORMAL | [PNG](phase01/before/dial-wide-tx-voltage.png) | [PNG](phase01/after/dial-wide-tx-voltage.png) |
| WARN | [PNG](phase01/before/dial-wide-tx-warn.png) | [PNG](phase01/after/dial-wide-tx-warn.png) |
| CRIT | [PNG](phase01/before/dial-wide-tx-crit.png) | [PNG](phase01/after/dial-wide-tx-crit.png) |
| NO DATA | [PNG](phase01/before/dial-wide-tx-nodata.png) | [PNG](phase01/after/dial-wide-tx-nodata.png) |
| Min/max text | [PNG](phase01/before/dial-wide-tx-history.png) | [PNG](phase01/after/dial-wide-tx-history.png) |

Inspección visual:

- El título dejó de flotar bajo el badge y ahora pertenece inequívocamente al valor.
- WARN, CRIT y NO DATA usan la reserva derecha de la cabecera; no empujan el contenido.
- NORMAL permanece silencioso: la reserva existe, pero el badge retenido está oculto.
- El valor recupera el espacio de la antigua fila exclusiva de estado.
- El footer aparece solo con `Markers + text`; sin él, su altura y gap vuelven a `mainBox`.
- Los extremos 270° caben en la zona de referencia y siguen ocultos en 360°.
- No se añadieron card, fondo opaco, sombra ni decoración dependiente del tipo de sensor.

Quedaron visibles, de forma intencional, dos asuntos fuera de la fase 1: la unidad `V` aún competía con el valor y el arco activo Needle conservaba el grosor completo. La jerarquía de unidad ya fue resuelta y verificada en [fase 2](PHASE-02-RESULTS-2026-08-12.md); el peso de track/arco permanece asignado a la fase 3.

## Geometría before/after

Coordenadas relativas a la zona 400×160, con `LCD_SCALE=1` del mock reproducible:

| Elemento | Before NORMAL | After NORMAL |
|---|---:|---:|
| Header | implícito | `160,6,234,25` |
| Main | implícito | `160,35,234,119` |
| Footer | implícito | `160,154,234,0` |
| Value | `184,25,151,69` | `184,60,151,69` |
| Name | `160,123,234,12` | `160,12,131,12` |
| State reserve | `160,100,234,17` | `295,10,98,17` |
| Scale endpoints | ocultos | `8,136,19,12` y `132,136,19,12` |

Con min/max text, `mainBox` pasa a `160,35,234,103` y el footer a `160,142,234,12`. El valor queda en `y=52`; sin footer queda en `y=60`. Esta diferencia depende de la opción estructural, no del estado NORMAL/WARN/CRIT/NO DATA.

## Escenas de fase 0

`dev/scenes.lua` incorpora cinco casos al final del catálogo, sin cambiar la numeración de las escenas existentes:

- `dial-wide-tx-voltage`
- `dial-wide-tx-warn`
- `dial-wide-tx-crit`
- `dial-wide-tx-nodata`
- `dial-wide-tx-history`

El contrato Lua usa la fuente real `tx-voltage`, precisión automática de una decimal y el preset de `presets.lua`: 6.0–8.4 V, WARN 6.8 y CRIT 6.4. `color-threshold-ok` permanece intacta como prueba sintética `-8..12`.

El simulador nativo solo permite etiquetas de sensor telemétrico inyectado de hasta cuatro caracteres y las opciones `VALUE` persisten umbrales enteros. Por eso el arnés usa internamente `TxV` y una ventana portátil 6–9/WARN 7/CRIT 6 para posar estados, mientras `Label="TX VOLTAGE"` conserva la presentación. Esta adaptación pertenece exclusivamente al arnés; no altera el runtime ni el contrato exacto de las escenas Lua.

Limitación observada: el sibling mínimo dinámico de EdgeTX para el `TxV` inyectado conserva 7.9 en la captura nativa aunque se envíen pasos temporizados 6.5 → 8.2 → 7.9; el máximo sí registra 8.2. La escena Lua exacta verifica `min 6.5` y `max 8.2`. Por tanto, el PNG nativo de historial es evidencia de layout/footer, no evidencia semántica del mínimo del simulador. El comportamiento de historial del widget sigue cubierto por las suites Lua y queda anotado para el endurecimiento del arnés en fase 5.

## Recursos y regresión

| Gate | Resultado |
|---|---:|
| Pruebas puras | 72/72 |
| Smoke/geométricas | 213/213 |
| Contratos split | 17/17 |
| Colisiones, incluida 400×160 | todas limpias |
| Objetos 400×160 NORMAL | 22 → 24 retenidos |
| Objetos 400×160 con min/max text | 24 → 26 retenidos |
| Motivo del incremento | 2 labels de extremos ya soportadas |
| Dial estable | 13–14 B/frame |
| Dial Needle ordinario | 1500 instrucciones/frame |
| Peor callback medido | 9400/20000 instrucciones |
| Python del arnés | `py_compile` limpio |
| Visual-kit split check | 69 Dial + 152 Bar, PASS |

BarPro se verificó dentro de las suites y de los gates de faces, movimiento, instrucciones y census. No recibe la nueva geometría ni objetos adicionales.

## Archivos funcionales modificados

- `dial_layout.lua`: estructura horizontal, reserva estable de badge, footer por fit y endpoints por fit real.
- `dev/scenes.lua`: cinco escenas de decisión TX.
- `tests/smoke_test.lua`: contratos explícitos header/main/footer, estabilidad de estado y devolución del footer.
- `dev/collide.lua`: zona 400×160 añadida.
- `dev/census.lua`: census específico 400×160.
- `tools/gaugepro-visual-kit/catalog.py`, `probe_one.py` y `run.py`: soporte reproducible para las poses telemétricas de las nuevas escenas.

## Decisión de cierre

Fases 0 y 1 quedan cerradas. La política opcional de unidad se implementó después en la fase 2, manteniendo los defaults de `placeValue` para BarPro y para las demás familias de DialPro. La siguiente entrega funcional es la fase 3: track, umbrales y aguja.
