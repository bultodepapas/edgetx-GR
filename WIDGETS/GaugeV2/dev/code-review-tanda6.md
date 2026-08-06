# GaugeV2 — Tanda 6: barrido de funcionamiento, robustez y rendimiento

**Alcance**: sólo `WIDGETS/GaugeV2/`. Revisión de código, no de diseño visual
(la parte gráfica quedó cerrada en Tanda 5 y el audit geométrico está limpio).

**Estado de partida (medido, no asumido)**

| Comprobación | Resultado |
|---|---|
| `tests/run_tests.lua` | 38 pass / 0 fail |
| `tests/smoke_test.lua` | 96 pass / 0 fail |
| `dev/collide.lua` (18 escenarios) | **0 colisiones** — todo limpio |

Es decir: **ninguno de los 17 defectos de abajo lo detecta la suite actual**.
Eso es, en sí mismo, el hallazgo estructural de esta tanda.

Toda la evidencia se obtuvo con sondas headless sobre `tests/mock_env.lua`
(mismo intérprete Lua 5.3 que embebe EdgeTX) y contrastada contra el firmware
de este mismo repositorio (`radio/src/lua/lua_widget.cpp`).

---

## 1. Resumen ejecutivo

| # | Severidad | Defecto | Efecto observable |
|---|---|---|---|
| F-1 | **P0** | `L.chipOff` se pierde en el segundo `update()` | **El firmware desactiva el widget de forma permanente** |
| F-2 | **P1** | Battery % sobre fuente `Cels` divide dos veces por el nº de celdas | Marca **0 %** con la configuración por defecto |
| F-3 | **P1** | `saneThresholds` rompe la escala descendente | Bandas warn/crit invertidas |
| F-4 | **P1** | El memo de `theme.textWidth` crece sin límite | Fuga de heap Lua proporcional al tiempo de vuelo |
| F-5 | **P1** | Cambiar «Accent colour» no repinta nada | La opción parece rota |
| F-6 | **P1** | `sensorCache` global sobrevive al cambio de modelo | `model.resetSensor()` borra **otro** sensor |
| F-7 | P2 | El retardo de arranque de alertas no se re-arma | Alarma falsa tras un brownout |
| F-8 | P2 | El *ghost* nunca se muestra con «Min/max = Off» | Objeto LVGL muerto + función perdida |
| F-9 | P2 | La resolución de fuente es un *latch* irreversible | Sin unidad / sin preset para siempre |
| F-10 | P2 | `theme.RAMP` revienta si falta una constante de fuente | Crash en firmware sin `XXLSIZE` |
| F-11 | P2 | La aguja cuesta 3 `lvgl.set` y ~12 tablas por frame | **+169 % de basura/frame** frente a modo Arc |
| F-12 | P3 | `widget.autoCells` queda obsoleto al salir de Auto | Latcheo de celdas innecesario |
| F-13 | P3 | Código muerto (6 símbolos) | Mantenimiento |
| F-14 | P3 | `main.lua` duplica `options.build()` | Riesgo de divergencia |
| F-15 | P3 | `bar.lua` duplica 3 funciones de `renderer.lua` | Riesgo de divergencia |
| F-16 | P3 | La tabla de objetos de `DOCS.md` §5 está obsoleta | Documentación falsa en 3 filas |
| F-17 | P3 | Ausencia total de cobertura para F-1…F-11 | El hueco que permitió todo lo anterior |

---

## 2. P0 — El widget se autodestruye

### F-1 · `L.chipOff` desaparece en el segundo `update()`

**Mecánica.** `app.configure()` reemplaza `widget.layout` **siempre**
([app.lua:188-189](../app.lua#L188-L189)), pero sólo reconstruye el árbol si
la firma cambió ([app.lua:193-202](../app.lua#L193-L202)). `L.chipOff` se
calcula **únicamente dentro de `build()`**
([renderer.lua:314-315](../renderer.lua#L314-L315),
[bar.lua:102-103](../bar.lua#L102-L103)). Resultado: cualquier `update()` que
no cambie la firma deja `widget.layout.chipOff = nil`, y la siguiente
transición de texto de estado entra en
[renderer.lua:479](../renderer.lua#L479) → aritmética sobre `nil`.

**Evidencia (sonda A / J).** No hace falta ni cambiar una opción:

```
=== J  chipOff after update() with IDENTICAL options (no user edit at all)
  chipOff after build : 3
  chipOff after update: nil
  refresh into CRIT   : ok=false ./renderer.lua:479:
                        attempt to perform arithmetic on a nil value (field 'chipOff')
```

Idéntico en el renderer de barra:

```
=== A2  same path, bar style (300x60)
  style=bar  showState=true
  after update     : layout.chipOff = nil
  refresh into CRIT: ok=false ./renderer.lua:479: ...
```

**Disparadores reales, confirmados en el firmware de este repo:**

| Acción del usuario | Ruta |
|---|---|
| Abrir los ajustes del widget y salir (**incluso con Cancelar**) | `WidgetSettings::onCancel` → `widget->updateWithoutRefresh()` (`widget_settings.cpp:223`) |
| Entrar en pantalla completa sobre el widget | `Widget::setFullscreen` → `updateWithoutRefresh()` (`widget.cpp:254`) |
| Redimensionar / cambiar el layout de pantalla | `Widget::updateZoneRect(rect, true)` |

**Consecuencia, no cosmética.** `lua_widget.cpp:365` captura el error y llama a
`setErrorMessage()`, que traza literalmente `"Widget disabled"`
(`lua_widget.cpp:463`). A partir de ahí:

- `updateWithoutRefresh()` sale inmediatamente (`if (... || errorMessage) return;`, línea 333),
- `refresh()` pinta un cartel rojo de error en lugar del gauge (líneas 485-500),
- `background()` sale (línea 543),
- y **`errorMessage` sólo se libera en el destructor** (línea 271-272): el gauge
  queda muerto hasta recargar modelo o reiniciar la radio.

**Por qué la suite no lo ve.** El test que ejecuta exactamente esta secuencia
([smoke_test.lua:1477-1480](../tests/smoke_test.lua#L1477-L1480)) sólo comprueba
la firma; nunca fuerza una transición de estado después del segundo `update()`.

---

## 3. P1 — Salida incorrecta y recursos

### F-2 · Battery % sobre `Cels` devuelve 0 % con la configuración por defecto

`telemetry.refresh()` agrega la tabla de celdas y de paso fija el recuento real
(`src.cells = src.cells or count`, [telemetry.lua:268](../telemetry.lua#L268)).
Después, el bloque de batería vuelve a dividir por ese recuento
([telemetry.lua:288-298](../telemetry.lua#L288-L298)) — pero con `Lowest` o
`Average` el valor **ya es por celda**. Se divide dos veces.

**Evidencia (sonda C).** Pack 4S real a ~3.85 V/celda (≈ 55 %):

```
  Cells=Lowest   cells=4 perCell=0.960 ->  0 %   (expected ~55)
  Cells=Total    cells=4 perCell=3.850 -> 55 %   (expected ~55)
  Cells=Average  cells=4 perCell=0.962 ->  0 %   (expected ~55)
```

`Lowest` es el **valor por defecto** de la opción *Cell reading*
([main.lua:85-86](../main.lua#L85-L86)) y el que `DOCS.md` §4.8 recomienda
explícitamente («the cell that sags first is the one that matters»). O sea: la
combinación documentada como recomendada es justo la que da 0 %.

Ya existe el predicado correcto para decidirlo —
`presets`.`cellsTable` + `historyTrustworthy()` distinguen exactamente este caso
para el historial ([telemetry.lua:213-217](../telemetry.lua#L213-L217))— pero
no se aplica al cálculo de porcentaje.

### F-3 · `saneThresholds` corrompe la escala descendente

[ranges.lua:74-85](../ranges.lua#L74-L85) compara `wh < minimum` sin normalizar
el orden de `minimum`/`maximum`. Con `Min = 100, Max = 0` (escala descendente
legítima: `ranges.build` y `geometry.normalize` la soportan a propósito, P0-3)
el guardián se dispara sobre umbrales perfectamente válidos y los recalcula
con un `span` negativo.

**Evidencia (sonda B).**

```
  ascending  0..100 warn 55 crit 35 -> warn 55   crit 35      (ok)
  descending 100..0 warn 55 crit 35 -> warn 45.0 crit 65.0    (invertidos)

  bands actually built:          bands the user configured:
     critical 0 .. 45.0             critical 0 .. 35
     warning  45.0 .. 65.0          warning  35 .. 55
     normal   65.0 .. 100           normal   55 .. 100
```

**Efecto de extremo a extremo (sonda O):**

```
  cfg warn=45.0 crit=65.0   value=78 -> state=normal  (correcto por casualidad)
                            value=40 -> state=critical (debería ser warning)
```

Un valor en zona de aviso se pinta rojo, pulsa y **dispara la alerta acústica
de crítico**.

*Efecto colateral en la misma configuración*: el arco *ghost* de peak-hold va
siempre de `L.startAngle` a `angleOf(h.max)`
([renderer.lua:648-656](../renderer.lua#L648-L656)); en escala descendente el
pico se mapea de vuelta sobre `startAngle`, así que el ghost marca el tramo
**no recorrido** (sonda Y: historial 60…89, ghost 135°…165° = valores 100…89).

### F-4 · El memo de `theme.textWidth` crece sin límite

`theme.lua` documenta en su cabecera que la medición se memoriza porque «never
changes at runtime», y el comentario de la función es explícito:

> *«Only called from layout / build paths — never per frame»*
> ([theme.lua:137-138](../theme.lua#L137-L138))

Ese contrato se rompió al introducir `anchorUnit` (P1-1 de Tanda 5):
[renderer.lua:499](../renderer.lua#L499) llama a `T.textWidth(str, ...)` con la
**cadena del valor en vivo**, en cada cambio de texto — y `bar.lua:236` hace lo
mismo. Cada valor distinto añade una entrada permanente (y retiene su string).

**Evidencia (sonda U, leyendo el `widthCache` real vía `debug.getupvalue`):**

```
  Precision 0 (RSSI 0..100)  entries   7 ->  108 tras 2000 frames (+101)
  Precision 1 (voltaje)      entries   9 -> 1010 tras 2000 frames (+1001)
  Precision 2 (corriente)    entries  10 -> 2011 tras 2000 frames (+2001)
```

Con 2 decimales es **una entrada por frame** en el peor caso: crecimiento lineal
sin techo mientras el widget esté en pantalla. El caché es además de módulo,
compartido entre todas las instancias del gauge.

### F-5 · Cambiar «Accent colour» no repinta nada

`layout.signature()` ([layout.lua:592-601](../layout.lua#L592-L601)) no incluye
`cfg.accent`, así que un cambio de color no reconstruye el árbol; y el repintado
de colores está condicionado a un cambio de **clave semántica**
([renderer.lua:708-711](../renderer.lua#L708-L711),
[bar.lua:212-213](../bar.lua#L212-L213)), que no cambia al tocar el acento.

**Evidencia (sonda E), modo Sections:**

```
  before: valueArc=12291 normalSection=12291 accent=12291
  after : valueArc=12291 normalSection=12291 accent=8192   (RED=8192)
  tree rebuilt: false
```

`widget.accent` sí se actualiza; ningún objeto lo refleja. Afecta al arco de
valor, la etiqueta de valor, las bandas *Sections*, los raíles *Rail* y las
marcas de umbral de la barra. Se corrige sólo cuando algo ajeno fuerza la
reconstrucción.

### F-6 · `sensorCache` sobrevive al cambio de modelo

`sensorCache` es una tabla de módulo ([telemetry.lua:92](../telemetry.lua#L92))
que sólo cachea aciertos. Pero los módulos se comparten por ruta y persisten
durante toda la sesión de radio (`MODS_BY_PATH` en
[app.lua:38](../app.lua#L38), `sharedApp` en [main.lua:143](../main.lua#L143)):
sobreviven al cambio de modelo, mientras que el índice y la precisión de un
sensor son **datos de modelo**.

**Evidencia (sonda K):**

```
  model A: sensorIndex=2 prec=1
  model B: sensorIndex=2 prec=1   (verdad: índice 7, prec 2)
  -> model.resetSensor() borraría el índice 2
```

Dos consecuencias: precisión de formato equivocada, y —más grave— el
interruptor *Reset min/max* llama a `model.resetSensor()`
([app.lua:266](../app.lua#L266)) sobre el índice de otro modelo, es decir,
**resetea un sensor que no es el suyo**.

---

## 4. P2 — Comportamiento y rendimiento

### F-7 · El retardo de arranque de alertas no se re-arma tras un corte

`a.armedAt` se fija una sola vez ([alerts.lua:79-82](../alerts.lua#L79-L82)) y
sólo lo limpia `alerts.reset()`, que `app.update()` invoca **únicamente al
cambiar de fuente** ([app.lua:231](../app.lua#L231)). La pérdida de enlace pone
`a.state = nil` pero deja `armedAt` en el pasado.

**Evidencia (sonda X):**

```
  t=2s, dentro del retardo de 4 s : tones=0   (correcto)
  t=5s, retardo cumplido          : tones=2   (correcto)
  enlace caído 3 s                : tones=+0
  1er frame tras reconectar       : tones=+2  (con re-arme sería 0)
```

Esto contradice el motivo declarado de la función en `DOCS.md` §6.5 y en la
cabecera de `alerts.lua`: *«a model powering up reports nonsense for a second or
two»*. Un brownout es exactamente ese escenario, y es el único en que el retardo
no actúa.

### F-8 · El *ghost* nunca aparece con «Min/max = Off»

`updateHistory()` sale antes de tocar el ghost si no hay marcadores
([renderer.lua:620](../renderer.lua#L620)), pero `L.showGhost` sólo depende del
modo ([layout.lua:201](../layout.lua#L201)), así que el objeto se crea igual.

**Evidencia (sonda F):**

```
  ShowMinMax=Off      showGhost=true ghostObj=true visible=false
  ShowMinMax=Markers  showGhost=true ghostObj=true visible=true
```

`bar.lua` no tiene ese acoplamiento (su ghost funciona con marcadores
apagados), así que las dos implementaciones discrepan. `DOCS.md` §5 lista el
ghost como creado «≥ compact», sin mencionar la dependencia.

### F-9 · La resolución de fuente es un *latch* irreversible

[telemetry.lua:114](../telemetry.lua#L114) sale si `s.id == id and s.resolved`,
y `s.resolved = true` se fija incluso cuando `getFieldInfo()` falló
([telemetry.lua:126](../telemetry.lua#L126)). No hay reintento: ni por
`refresh()`, ni por un `update()` posterior.

**Evidencia (sonda G)** — el sensor aparece después del primer `update()`:

```
  boot   : name="" unit="" isTelemetry=false resolved=true
  later  : name="" unit="" isTelemetry=false min/max=0/100
  update : name="" unit="" min/max=0/100      <- ni con un update() explícito
```

Se pierden para siempre: nombre, unidad, precisión, preset de escala, los
sensores hermanos `-`/`+`, y la distinción «NO LINK» vs «NO DATA» (que depende
de `src.isTelemetry`, [telemetry.lua:250](../telemetry.lua#L250)).

### F-10 · `theme.RAMP` revienta si falta una constante de fuente

`M.RAMP` se construye con globales del firmware
([theme.lua:45-46](../theme.lua#L45-L46)). Si una falta, el constructor deja un
agujero y `#RAMP` sigue devolviendo 7.

**Evidencia (sonda N):**

```
  #RAMP con XXLSIZE=nil  : 7   (esperado 7)
  RAMP[1] = nil
  fitFont(RAMP,20) -> ok=false ./theme.lua:133: table index is nil
```

No es un fallo de degradación elegante: es un crash en la primera pasada de
layout, es decir, F-1 otra vez (widget desactivado).

### F-11 · Coste por frame de la aguja de 3 tramos

La aguja se dibuja con tres `lvgl.set` directos
([renderer.lua:601-606](../renderer.lua#L601-L606)) que saltan el batching de
`setProp`/`flush` (P2-2) porque `pts` es una tabla nueva cada vez.

**Evidencia (sondas L, V, W).** Reparto de escrituras en 20 frames de barrido:

```
  ghost           20 sets (1.00/frame)     needle          19 (0.95)
  maxMark         20 sets (1.00/frame)     valueLabel      14 (0.70)
  needleMid       19 sets (0.95/frame)     stateLabel       1 (0.05)
  needleTip       19 sets (0.95/frame)
  valueArc        19 sets (0.95/frame)     TOTAL          131 (6.55/frame)
```

Basura generada por frame (instrumentación del harness desactivada):

```
  dial 200x200 (aguja)    814 B/frame
  dial 200x200 (Arc)      303 B/frame      <- misma escena sin aguja
  bar  300x60             295 B/frame
```

```
  geometry.linePoints: 157 llamadas en 40 frames (3.92/frame)
  cada llamada asigna 3 tablas -> 11.8 tablas/frame sólo de pts
```

La aguja son **~511 B/frame** de los 814, es decir **+169 %** sobre la misma
escena sin ella. No es un defecto —es el precio de la decisión de diseño de
Tanda 5— pero es el objetivo de optimización más rentable que queda, y se puede
reducir sin tocar el aspecto visual (§6, Fase 5).

Contexto sano, para no sobreactuar: el árbol LVGL sigue siendo pequeño y el
arranque sigue siendo correcto.

```
  60x60 micro 8 obj   200x160 22   200x200 34   480x272 34   bar 12
  4 gauges -> 13 loadScript (1 app + 12 módulos)   <- memoización P2-3 intacta
```

---

## 5. P3 — Coherencia

- **F-12** `widget.autoCells` sólo se escribe dentro de la rama `auto`
  ([app.lua:121](../app.lua#L121)); al pasar a *Manual* conserva el valor
  anterior. Sonda H: `Auto → autoCells=true`, `Manual → autoCells=true`.
  Impacto bajo (latcheo innecesario), pero es estado mentiroso.
- **F-13 Código muerto**: `options.build()` y `options.translator()` (0 usos en
  runtime — `main.lua` los reimplementa), `options.present()`,
  `geometry.trianglePoints()` (prohibido por P2-1), `history.fromSensor`,
  `data.raw` / `data.perCell` (se escriben, nunca se leen).
- **F-14** `main.lua:117-136` duplica `options.build()`. Verificado idénticos
  **hoy** (sonda M: `inline=24  options.build=24  differences: 0`), pero es
  duplicación de la lógica más frágil del widget (contrato posicional de slots).
- **F-15** `bar.lua` reimplementa `resolveColor` (líneas 214-218 vs
  `renderer.lua:389-396`), `updatePulse` y `updateSourceLabels`.
- **F-16** `DOCS.md` §5 miente en 3 filas. Árbol real de un 200×200 (sonda Z):
  `arc 5, circle 1, label 8, line 18, rectangle 2`.

  | DOCS dice | Realidad |
  |---|---|
  | «Needle + counterweight **triangles** \| 2» | 3 `line` (`needle`/`needleMid`/`needleTip`), sin contrapeso, sin triángulos |
  | «Pivot ring + dot **circles** \| 2» | 1 `circle` (`pivotRing` sólido) |
  | «State chip + label \| 2 \| ≥ compact» | 3 objetos (`chipEdge` + `chip` + label), y ahora condicionado a `ShowChip` |

- **F-17** La brecha de cobertura: 134 tests verdes y ninguno toca las rutas de
  F-1…F-11. Faltan tres familias enteras: **ciclo de vida** (`update()`
  repetido), **configuraciones invertidas** (escala descendente) y
  **acotación de recursos** (crecimiento de cachés).

---

## 6. Plan de reparación

Orden por riesgo residual, no por comodidad. Cada fase deja la suite verde y el
audit de colisiones limpio antes de pasar a la siguiente.

### Fase 0 — Red de seguridad (bloqueante, antes de tocar código)

Los tests van **primero y en rojo**: F-1 existe justamente porque el test que
recorría esa secuencia no comprobaba el efecto.

- **0.1** `smoke_test`: `update()` repetido + transición de estado, dial y barra.
- **0.2** `run_tests`: `saneThresholds` con `min > max` (high-good y low-good).
- **0.3** `smoke_test`: Battery % sobre `Cels` en los tres modos de agregación.
- **0.4** `smoke_test`: acotación del `widthCache` tras N frames de valor variable.
- **0.5** `smoke_test`: cambio de `Accent` en caliente → color aplicado.
- **0.6** `run_tests`: `sensorCache` no cruza modelos.
- **Aceptación**: 6 tests nuevos, **todos en rojo** por el motivo esperado.

### Fase 1 — P0 (parche mínimo, envío inmediato)

- **1.1** Mover el cálculo de `chipOff` de `build()` a `layout.dialLayout()` /
  `layout.barLayout()`, junto a `chipPad`/`chipHeight`, que ya viven ahí
  ([layout.lua:486-487](../layout.lua#L486-L487),
  [layout.lua:570-571](../layout.lua#L570-L571)). Es su sitio natural: es
  geometría derivada, no estado de construcción.
- **1.2** `renderer.build`/`bar.build` pasan a **leer** `L.chipOff`; se elimina
  el cálculo duplicado en los dos ficheros.
- **1.3** Barrido de la misma clase de fallo: auditar todo campo de `L` escrito
  fuera de `layout.calculate()`. Es un patrón, no un caso aislado.
- **Aceptación**: 0.1 en verde; `grep` confirma que ningún `L.<campo> =` queda
  fuera de `layout.lua`.

### Fase 2 — P1 de corrección

- **2.1 (F-2)** En el bloque de batería, usar el valor por celda directo cuando
  la lectura ya es por celda: reutilizar el criterio `cellsTable` +
  `cfg.cells ~= CELLS_TOTAL` que ya emplea `historyTrustworthy()`. Extraer ese
  predicado a una función nombrada y usarlo en los dos sitios (una sola verdad).
- **2.2 (F-3)** Normalizar el orden de `minimum`/`maximum` al entrar en
  `saneThresholds()`, igual que hace `ranges.build()`. Corregir de paso la
  orientación del ghost (usar el extremo que corresponde al sentido de la
  escala, no `h.max` fijo).
- **2.3 (F-5)** Añadir `cfg.accent` a `layout.signature()`. Es la opción más
  barata y la correcta: el acento entra en objetos creados en `build()`
  (secciones, raíles, marcas), que no tienen ruta de actualización.
- **2.4 (F-6)** Clavar `sensorCache` al modelo activo: invalidarlo cuando cambie
  la identidad del modelo, o simplemente pasar a caché por widget. Dado que
  `resolveSource` ya sólo trabaja al cambiar la fuente, el caché global aporta
  poco frente al riesgo de resetear el sensor equivocado.
- **Aceptación**: 0.2, 0.3, 0.5, 0.6 en verde.

### Fase 3 — P1 de recursos

- **3.1 (F-4)** Restaurar el contrato de `theme.textWidth`. Preferencia:
  `anchorUnit` deja de medir la cadena viva y se ancla por **número de
  caracteres** contra el ancho ya medido de la muestra más ancha (los dígitos
  son de ancho fijo en las fuentes de EdgeTX; la muestra ya está medida en
  `placeValue`). Alternativa si hace falta exactitud: función de medición
  separada **sin memo**.
- **3.2** Reforzar el contrato con un test de acotación (0.4) para que no se
  vuelva a romper en silencio, y actualizar la cabecera de `theme.lua` para que
  diga la verdad sobre quién puede llamar a qué.
- **Aceptación**: 0.4 en verde; `widthCache` estable tras 2000 frames.

### Fase 4 — P2 de comportamiento

- **4.1 (F-7)** Re-armar `a.armedAt = nil` cuando los datos dejan de ser
  válidos, no sólo al cambiar de fuente.
- **4.2 (F-8)** Decidir y unificar la semántica del ghost entre dial y barra:
  o el ghost es independiente de los marcadores (mi recomendación: lo es en la
  barra, y `showGhost` ya se calcula por separado), o `showGhost` pasa a
  depender de `showMinMax` y el objeto deja de crearse. **No las dos cosas.**
- **4.3 (F-9)** Reintentar la resolución mientras no haya éxito: marcar
  `s.resolved` sólo cuando `getFieldInfo()` devolvió algo, con un contador de
  reintentos para no escanear en cada frame.
- **4.4 (F-10)** Filtrar `nil` al construir `M.RAMP`, y validar que quede al
  menos una fuente utilizable.
- **Aceptación**: tests nuevos para 4.1 y 4.3; audit de colisiones limpio.

### Fase 5 — Optimización (sin cambio visual)

Objetivo medible: bajar de **814 B/frame** a ≲ 400 B/frame en dial con aguja,
sin tocar la geometría de 3 tramos.

- **5.1** Buffers `pts` persistentes por objeto: mutar los números en sitio en
  lugar de reconstruir `{{x,y},{x,y}}`. Elimina ~9 de las ~12 tablas/frame.
- **5.2** Reutilizar también la tabla envoltorio `{pts = ...}` de `lvgl.set`.
- **5.3** Revisar si `ghost` y `maxMark` necesitan escribirse en cada frame
  (1.00 sets/frame cada uno): sólo cambian cuando el máximo histórico avanza.
- **5.4** Re-medir con la sonda V y registrar el resultado. **Si la mejora no
  llega, revertir**: el código actual es legible y correcto, y no vale la pena
  cambiarlo por una ganancia que no se pueda demostrar.
- **Aceptación**: sonda V muestra la reducción; suite y audit sin cambios.

### Fase 6 — Coherencia y documentación

- **6.1 (F-14)** `main.lua` pasa a usar `options.build()` / `options.translator()`
  — **midiendo antes** el coste de arranque, porque el comentario de
  [main.lua:105-106](../main.lua#L105-L106) dice que la duplicación es
  deliberada («boot costs exactly one file read per widget»). Si la medición
  confirma el motivo, la acción correcta es la inversa: **borrar** las funciones
  muertas de `options.lua` y anotar la duplicación como intencional.
- **6.2 (F-15)** Subir `resolveColor`, `updatePulse` y `updateSourceLabels` a
  helpers compartidos en `renderer.lua`, como ya se hizo con `updateChip`,
  `anchorUnit` y `label`.
- **6.3 (F-12, F-13)** Limpiar el estado obsoleto y los 6 símbolos muertos.
- **6.4 (F-16)** Corregir las 3 filas de `DOCS.md` §5 y documentar la semántica
  del ghost que se fije en 4.2.
- **Aceptación**: recuento de objetos de `DOCS.md` reproducible con la sonda Z.

---

## 7. Recomendación de secuenciación

**Fases 0 y 1 son urgentes y separables del resto**: F-1 desactiva el widget con
una acción tan corriente como abrir sus ajustes y salir. Merecen su propio
commit y su propio envío, sin esperar a las demás.

Fases 2-3 son el bloque de corrección real y deberían ir juntas. Fases 4-6 son
higiene y pueden planificarse con calma.

**Fase 5 es la única opcional**, y con criterio de reversión explícito: es
optimización sobre código que ya funciona.
