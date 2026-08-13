# Plan técnico — feedback visual de DialPro 400×160

**Fecha:** 2026-08-12
**Estado:** listo para implementación; este documento no modifica todavía el runtime
**Prioridad:** P1 visual, sin cambio del contrato de opciones
**Referencia:** [captura 010](screenshots/010_color_color-threshold-ok.png) · [catálogo](CATALOG.md) · [auditoría vigente](AUDIT-2026-08-12.md)

## 1. Decisión ejecutiva

El feedback del diseñador identifica correctamente cuatro problemas visibles:

1. En la variante horizontal, el dial y el bloque numérico no forman un solo instrumento.
2. El nombre de fuente queda flotando debajo del valor.
3. En modo `Threshold`, los ticks y los límites de alarma no tienen suficiente diferenciación visual.
4. En este tamaño, el arco activo y la unidad compiten demasiado con el valor principal.

La solución recomendada es una mejora focalizada del layout horizontal de DialPro y de su gramática visual. No se debe reconstruir la arquitectura: el widget ya es responsivo, usa objetos LVGL retenidos, calcula la geometría fuera del refresco ordinario, evita asignaciones por movimiento de aguja y ya implementa estados, umbrales, histéresis, precisión, min/max y ausencia de datos.

No se añadirán opciones ni se cambiará su orden. DialPro debe conservar sus 24 slots, BarPro sus 42 slots y EdgeTX 2.11 su contrato reducido de 10 slots.

## 2. Contexto que cambia la interpretación de la captura

La imagen completa mide 800×480, pero DialPro solo controla la zona superior derecha de **400×160** (`Layout1P3 z1`). El espacio vacío situado debajo no pertenece al widget y no puede utilizarse desde su Lua. Por tanto, la valoración de “espacio desaprovechado” solo es válida dentro del rectángulo 400×160, no respecto a toda la pantalla.

La escena 010 tampoco es un preset realista de batería. Es una escena contractual para demostrar `ColorMode=Threshold` y usa:

- `Min=-8`
- `Max=12`
- `Warn=3`
- `Crit=-1`
- valor nativo presentado: `7.9 V`

Esta combinación deliberadamente sintética sirve para separar los límites en la captura, pero no debe convertirse en la imagen de referencia de producto. Se conservará como prueba matemática y se añadirá una escena de presentación con escala TX realista.

## 3. Diagnóstico contra el código actual

| Feedback | Veredicto técnico | Decisión |
|---|---|---|
| Gauge y número desconectados | Válido. En horizontal, `dial_layout.lua` apila valor, estado, min/max y nombre en filas separadas; el nombre termina abajo. | Corregir con cabecera compartida y una sola columna informativa. |
| Falta una estructura header/main/footer | Válido para horizontal normal/large. | Adoptar sin crear un panel de fondo. |
| La escala no se entiende | Parcialmente válido. Los límites exactos existen, pero las marcas de `Threshold` se parecen demasiado a ticks normales y las etiquetas de extremos solo aparecen en modo `large`. | Diferenciar marcas y permitir extremos por ajuste geométrico real. |
| Arco verde demasiado dominante | Válido en estilo Needle: arco y aguja expresan posición a la vez. | Adelgazar únicamente el arco activo de Needle; Arc conserva su peso. |
| Aguja sin taper | No es exacto: ya está formada por tres líneas persistentes con taper. A 400×160 las transiciones se comprimen visualmente. | Ajustar proporciones y hub; mantener la arquitectura de tres líneas. |
| Añadir triángulo/outline/highlight | No compensa. El triángulo reconstruye canvas y produjo aproximadamente 24 KB/frame de churn en pruebas previas. Outline y highlight añaden objetos sin resolver el problema principal. | Rechazar; mejorar la silueta con las tres líneas existentes. |
| Unidad demasiado grande/separada | Válido en esta composición. Ya existe baseline y reserva estable, pero el tamaño y gap son globales. | Introducir una política opcional de unidad para Dial horizontal. |
| Alinear el número a la derecha para que no se mueva | El problema de movimiento ya está resuelto: se reserva el ancho de la muestra más larga y se reancla la unidad. El alineado visible centrado fue una decisión consciente. | Mantener estabilidad y centrado óptico; no imponer `RIGHT`. |
| `tx-voltage` parece un identificador interno | Válido. `Label` ya permite override, pero el valor por defecto sigue siendo crudo. | Alias conservador para fuentes internas conocidas; `Label` siempre gana. |
| Badge `NORMAL` permanente | Añade ruido y consume cabecera en el estado más común. | Estado normal silencioso; texto explícito para WARN/CRIT/NO DATA. |
| Min/max, thresholds, precisión y título configurables | Ya existen (`ShowMinMax`, `Min`, `Max`, `Warn`, `Crit`, `Precision`, `Label`). | No duplicar opciones. Mejorar su presentación. |
| Missing data, alertas e histéresis | Ya existen en `telemetry.lua`, `alerts.lua` y `ranges.lua`. | Mantener y ampliar pruebas visuales. |
| Tres layouts responsivos | Ya existe clasificación `micro/compact/normal/large` más orientación horizontal/balanced/vertical. | No sustituirla por tres cortes de aspect ratio menos precisos. |
| Precalcular trigonometría y evitar tablas por frame | Ya implementado para ticks, aguja e historial móvil. | Tratarlo como gate de no regresión. |
| Card, sombra y fondo propio | Riesgoso: el widget vive sobre temas e imágenes de fondo que no controla. | No añadir superficie por defecto a DialPro. |
| Icono de batería | DialPro acepta cualquier fuente numérica; un icono fijo mentiría para RSSI, temperatura, RPM o controles. | Rechazar en el widget genérico. |
| Flecha de tendencia/sparkline | Requiere ventana temporal, filtrado de ruido, nueva semántica y probablemente nuevos slots/objetos. | Diferir a un incremento independiente, preferiblemente fullscreen. |

## 4. Objetivo visual aprobado

Para una zona 400×160, el instrumento debe leerse así:

```text
┌──────────────────────── zona propia 400×160 ────────────────────────┐
│       DIAL                 TX VOLTAGE                    [WARN]      │
│                         ┌──────────────────────┐                    │
│  escala + aguja         │       7.9  V         │                    │
│  -8          12         └──────────────────────┘                    │
│                         min 7.2       max 8.1  (si está activado)   │
└─────────────────────────────────────────────────────────────────────┘
```

Reglas:

- Dial: 38–42% del ancho útil; información: 58–62%. El reparto actual ya está cerca y no necesita una reescritura.
- Cabecera de la columna informativa: nombre a la izquierda y badge a la derecha, en la misma fila.
- Área principal: valor y unidad como un grupo estable, con el valor como primer nivel jerárquico.
- Pie: min/max históricos solo cuando `ShowMinMax` lo solicite y haya ancho real.
- Extremos de escala pertenecen al dial; `min/max` históricos pertenecen al pie. No deben confundirse.
- En estado normal no se muestra un badge verde permanente. WARN y CRIT siguen usando texto, no solo color; los estados informativos de indisponibilidad respetan la opción existente `ShowChip` y, cuando esta está desactivada, conservan como mínimo el placeholder de valor.
- No se dibuja borde, card ni sombra por defecto.

## 5. Gramática visual por `ColorMode`

No se mezclarán los contratos de los modos:

| Modo | Significado que debe conservar |
|---|---|
| `Static` | Arco activo con el acento configurado; sin referencias de umbral. |
| `Threshold` | Track neutro, arco activo según estado y marcas exactas en `Warn`/`Crit`. No pinta zonas completas. |
| `Rail` | Banda exterior fina para las zonas warning/critical. |
| `Gradient` | Color espacial continuo sobre la escala. |
| `Sections` | Toda la escala dividida en bandas semánticas. |

La recomendación del diseñador de “zona verde/ámbar/roja” corresponde a `Sections` o `Rail`; aplicarla a `Threshold` haría dos opciones visualmente redundantes.

En Needle + Threshold se aplicará:

- track neutro con el grosor actual;
- arco activo al 55–70% del grosor del track;
- marcas Warn/Crit atravesando todo el track y sobresaliendo 1–2 px hacia fuera;
- marca de umbral al menos 1 px más gruesa que un tick normal, limitada por escala LCD;
- ticks mayores siempre en el rol neutro `tick`;
- aguja neutra y legible sobre normal/warning/critical;
- extremos numéricos solo cuando ambos quepan sin tocar ticks, arco o borde de zona.

En estilo Arc, `arcThickness` seguirá igual al track: adelgazarlo allí debilitaría el elemento que representa el valor.

## 6. Plan de implementación por fases

### Fase 0 — fijar baseline y escenas de decisión

**Archivos:** `dev/scenes.lua`, herramientas visuales existentes y documentación.

1. Conservar `color-threshold-ok` con `-8..12`; sigue siendo una prueba contractual.
2. Añadir una escena de producto `dial-wide-tx-voltage` en 400×160 con `6.0..8.4`, warning `7.2`, critical `6.8`, `7.9 V`, Needle, Threshold y una decimal.
3. Añadir variantes de esa escena para WARN, CRIT, NO DATA y `ShowMinMax=Markers + text`.
4. Guardar before/after del recorte exacto de la zona 400×160. La pantalla 800×480 solo sirve para verificar integración con EdgeTX.
5. Registrar baseline de cajas, objetos, instrucciones y B/frame antes de tocar layout.

**Salida:** evidencia que separa prueba de contrato y referencia estética.

### Fase 1 — recomponer el layout horizontal

**Archivo principal:** `dial_layout.lua`.

1. Limitar el cambio a `orientation == "horizontal"` y modos `normal/large`.
2. Crear geometría explícita `headerBox`, `mainBox` y `footerBox` dentro de `textRegion`.
3. Colocar `nameBox` y `stateBox` en la misma cabecera. El badge conserva su ancho ajustado al texto y se ancla a la derecha; el título recibe el ancho restante.
4. Centrar `valueBox + unitBox` dentro de `mainBox`, no respecto a toda la zona.
5. Mostrar el footer únicamente si min/max text cabe. Si no cabe, conservar los marcadores radiales y devolver el espacio al valor.
6. Eliminar la fila vacía exclusiva del estado normal; la cabecera ya reserva de forma segura el lugar para un badge de alarma.
7. Mantener intactas las rutas balanced, vertical, compact y micro.
8. Calcular etiquetas de extremos mediante un predicado de fit posterior a la geometría. Para sweep 360° permanecen ocultas porque ambos extremos coinciden.

**Criterio:** en 400×160 el nombre deja de estar bajo el hueco central y se percibe unido al valor; WARN/CRIT no produce salto vertical.

### Fase 2 — jerarquía de valor y unidad sin romper BarPro

**Archivos:** `layout_common.lua`, `ui_core.lua`, `dial_layout.lua`.

1. Extender `placeValue`/`pickValueFont` con una política opcional, manteniendo exactamente los defaults actuales.
2. La política de Dial horizontal normal/large usará:
   - el mínimo número de pasos de la rampa que deje la unidad en el font disponible más cercano al 40% del valor;
   - límite legible en `XS` y máximo práctico de 50% cuando la rampa discreta no permita alcanzar 35–45%;
   - objetivo ideal de altura 35–45% en la escena 400×160;
   - gap `sm` en vez de `md`.
3. Guardar el gap resuelto en `L.unitGap`; tanto layout como `anchorUnit` deben leer el mismo valor. No puede quedar un `md` hardcodeado en una ruta y `sm` en la otra.
4. Conservar la caja reservada por la muestra más ancha y el reanclaje dinámico de la unidad. Cambiar `9.9` a `10.0` no debe mover el centro óptico del grupo.
5. BarPro no pasa la política nueva y conserva su geometría y tipografía actuales.

### Fase 3 — clarificar track, umbrales y aguja

**Archivos:** `dial_layout.lua`, `dial_renderer.lua`, `theme.lua`.

1. Separar de verdad `L.trackThickness` y `L.arcThickness` en estilo Needle.
2. Hacer que `buildThresholdMarks` mida contra `trackThickness`, no contra el arco adelgazado, y añada el pequeño labio exterior.
3. Mantener una línea persistente por límite interior; no añadir labels de Warn/Crit ni objetos decorativos.
4. Ajustar `needleBodyReach`, `needleMidReach`, anchos relativos y `pivotRadius` para que el taper sea perceptible a 400×160.
5. Reducir el hub como máximo 1 px escalado si la comparación A/B confirma que sigue cubriendo la unión de los tres segmentos.
6. Mantener tres `lvgl.line`, buffers persistentes, wrappers persistentes y `lvgl.set` directo. No usar triángulos ni pasar puntos móviles por `setProp`.
7. Expresar cualquier nuevo ratio/opacity en tokens semánticos de `theme.lua`; no introducir RGB literales en el renderer.

### Fase 4 — nombre de fuente presentable

**Archivos:** `app.lua` y, si se extrae un helper puro, sus pruebas.

1. Mantener precedencia: `Label` no vacío > alias conocido > nombre de fuente original.
2. Añadir únicamente aliases seguros de identificadores internos conocidos; primer caso: `tx-voltage`/`TX_VOLTAGE` → `TX VOLTAGE`.
3. No modificar el identificador usado para lectura de telemetría, presets o persistencia.
4. No convertir arbitrariamente a mayúsculas nombres personalizados o sensores de terceros.
5. Aplicar la misma regla de presentación en DialPro y BarPro para que una misma fuente no tenga dos nombres visibles.

### Fase 5 — pruebas y verificación visual

**Archivos:** `tests/run_tests.lua`, `tests/smoke_test.lua`, `dev/collide.lua`, `dev/census.lua`, `dev/instructions.lua`, `dev/measure_frames.lua`, `dev/scenes.lua`.

Añadir asserts para:

- cabecera, main y footer sin intersección en 400×160;
- nombre y badge compartiendo baseline/cabecera;
- NORMAL sin badge visible y WARN/CRIT/NO DATA sin relayout;
- ratio y gap de unidad en la escena de referencia;
- ancla estable para `9.9`, `10.0`, `-8.8` y `--.-`;
- extremos de escala visibles en 270° cuando caben y ocultos en 360°;
- extremos de escala diferentes de min/max históricos;
- marcas Threshold colocadas en los ángulos exactos, atravesando el track y siendo distintas de ticks;
- arco fino solo en Needle; Arc conserva grosor completo;
- alias TX visible, con `Label` personalizado como prioridad;
- ninguna coordenada negativa y ningún objeto fuera de zona;
- LCD scale 0.8, 1.0 y 1.375;
- BarPro sin regresión geométrica por los cambios compartidos.

Ejecutar los gates actuales desde `WIDGETS/GaugePro`:

```sh
lua tests/run_tests.lua ./
lua tests/smoke_test.lua ./
lua tests/widgets_test.lua ./
lua dev/split_resources.lua ./
lua dev/collide.lua ./
lua dev/instructions.lua ./
lua dev/measure_frames.lua ./
lua dev/motion_sequences.lua ./
lua dev/census.lua ./
```

Después, ejecutar el flujo nativo documentado `run.py all`, regenerar el visual kit completo y validar manifest, hashes, duplicados y archivos no referenciados.

## 7. Matriz visual obligatoria

### Zonas

- 400×160: referencia principal.
- 300×150 y 200×160: horizontal con menos espacio.
- 200×200 y 160×160: balanced/square, que no debe heredar la nueva composición.
- 120×220 y 100×260: vertical.
- 60×60: micro.
- 480×272: fullscreen/large.

### Contenido

- estados NORMAL, WARN, CRIT, NO DATA, NO LINK y STALE;
- Needle y Arc;
- sweeps 180°, 270° y 360°;
- Static, Threshold, Rail, Gradient y Sections;
- precisión 0/1/2;
- unidades `V`, `dB`, `%`, `°C`, `rpm` y sufijo vacío;
- valores que cambian longitud y signo;
- `ShowMinMax` Off, Markers y Markers + text;
- título por defecto, alias TX, `Label` personalizado y label largo;
- temas stock, light y dark.

La revisión debe mirar primero el recorte de zona. La captura de pantalla completa se usa después para asegurar que el widget convive bien con la barra superior, fondos y widgets vecinos.

## 8. Gates de aceptación

### Visuales

- El valor sigue siendo el elemento de mayor tamaño y contraste.
- En 400×160, la unidad usa el font disponible más cercano a 40% de la altura del valor, nunca supera 50% y queda visualmente unida a él.
- El título pertenece inequívocamente a la columna de información.
- WARN/CRIT/NO DATA se entienden también sin distinguir el color.
- Un observador puede diferenciar tick, límite exacto, track restante y arco activo sin consultar las opciones.
- El arco activo Needle no supera 70% del grosor del track.
- Los extremos de escala nunca se superponen con ticks, arco, valor o borde.
- No hay wrapping, clipping ni colisiones en la matriz obligatoria.
- Ninguna superficie opaca nueva tapa el tema o una imagen de fondo.

### Funcionales

- No cambia el mapeo de valores ni la semántica de `HighGood`/low-is-good.
- No cambia el algoritmo de estado, histéresis, alertas, historial o no-data.
- No cambia el orden, cantidad ni wire format de opciones.
- `Label` personalizado conserva prioridad absoluta.
- Los cambios de dígitos no desplazan el grupo valor+unidad.

### Recursos

- Refresh ordinario: `<2000` instrucciones.
- Transición/motion: `<6000` instrucciones.
- Callback estructural: `<10000` instrucciones y siempre muy por debajo del límite EdgeTX de 20000.
- Dial estable: objetivo `<=16 B/frame` frente al baseline actual de 13–14 B/frame.
- Cero trigonometría para ticks o límites dentro del refresh ordinario.
- Cero tablas nuevas por frame para aguja o marcadores móviles.
- El caso Threshold horizontal no aumenta objetos salvo las dos etiquetas de escala ya soportadas por el renderer; cualquier objeto adicional exige justificación y nuevo census.

### Evidencia

- Todas las suites Lua pasan.
- Auditoría de colisiones limpia.
- Visual kit nativo completamente fresco: cero WARN/FAIL, cero PNG sin referencia y cero duplicados inesperados.
- Before/after aprobado en stock, light y dark.
- BarPro conserva sus escenas actuales salvo el cambio intencional del alias de una fuente interna conocida.

## 9. Fuera de alcance de este incremento

- Sparkline o historial temporal.
- Flecha de tendencia.
- Iconografía específica por tipo de fuente.
- Fondo, card, blur, gradiente decorativo o sombra de DialPro.
- Nuevo selector light/dark; la adaptación al tema ya existe.
- Nuevas opciones o migración del contrato persistido.
- Reemplazo del sistema responsivo actual.
- Cambio a triángulos/canvas para la aguja.

## 10. Orden de entrega recomendado

1. Baseline y nuevas escenas.
2. Cabecera/main/footer horizontal.
3. Política de unidad con default compatible.
4. Track/arco/Threshold.
5. Ajuste A/B de aguja y hub.
6. Alias conservador de fuente.
7. Gates Lua y recursos.
8. Captura nativa completa y revisión visual final.

Cada paso debe quedar visualmente comprobable y poder revertirse de forma independiente. Si una mejora de apariencia rompe un gate de contención, legibilidad o recursos, se revierte esa mejora; no se relaja el gate.

## 11. Definición de terminado

El incremento está terminado cuando DialPro 400×160 se percibe como un solo instrumento, Threshold comunica con claridad sus límites, el valor domina sobre unidad/arco y todo ello se demuestra en el simulador nativo sin regresiones de BarPro, contratos, contención, instrucciones, objetos ni asignaciones.
