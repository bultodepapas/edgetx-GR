# Migración de GaugePro a GaugeDialPro y GaugeBarPro

**Estado:** guía vigente para el paquete Gauge Dial Pro/Gauge Bar Pro con `coreApi = 1`.

GaugePro ahora se ofrece como dos widgets visibles que comparten `GaugeCore`:

- `GaugeDialPro`: Auto, Needle y Arc.
- `GaugeBarPro`: barras continuas, segmentadas, Hex, Ticks, Steps y Dual Rail.

En la interfaz aparecen como **Gauge Dial Pro** y **Gauge Bar Pro**. Sus identificadores
internos compatibles con EdgeTX son `DialPro` y `BarPro`.

La migración es manual porque EdgeTX guarda la factory del widget y sus opciones por posición.
Renombrar una carpeta no convierte una instancia existente.

## Instalación

Desde `WIDGETS/GaugePro`:

```powershell
# Paquete nuevo: instala Core + Dial + Bar
pwsh dev/sync-sd.ps1 -Destination E:\

# Paquete de transición: también actualiza GaugePro legacy (3 visibles)
pwsh dev/sync-sd.ps1 -Destination E:\ -IncludeLegacy
```

El instalador copia primero `/SCRIPTS/TOOLS/GaugeCore/`, después los dos frentes, valida
`coreApi = 1`, limpia únicamente bytecode dentro de los tres destinos exactos y nunca borra
`/WIDGETS/GaugePro/`. En una SD limpia habrá dos widgets visibles. Si la SD ya contiene el
frontend legacy, el script emite una advertencia y seguirán visibles tres widgets hasta que
termine la migración y se retire esa carpeta manualmente.

## Mapeo

| GaugePro actual | Widget nuevo | Ajuste principal |
|---|---|---|
| `Style = Needle` | GaugeDialPro | `Dial style = Needle` |
| `Style = Arc` | GaugeDialPro | `Dial style = Arc` |
| `Style = Auto` en zona no ancha | GaugeDialPro | `Dial style = Auto` |
| `Style = Bar` | GaugeBarPro | copiar `Bar preset` y overrides |
| `Style = Auto` con `w/h > 2.6` | GaugeBarPro | empezar con `Bar preset = Classic` |

Los conceptos comunes conservan su significado: fuente, escala, thresholds, `High = good`,
modo de color, precisión, min/max, batería/celdas, alertas, reset, nombre, unidad y badges.

## Flujo seguro por modelo

1. Instalar el paquete de transición.
2. Añadir **Gauge Dial Pro** o **Gauge Bar Pro** junto a la instancia GaugePro existente.
3. Copiar la configuración y comparar lectura, unidad, estado, alertas e historial.
4. Eliminar la instancia legacy del modelo, no la carpeta todavía.
5. Repetir en todos los modelos.
6. Retirar `/WIDGETS/GaugePro/` manualmente solo cuando ningún modelo la referencie.

No se debe borrar ni renombrar GaugePro automáticamente: conservar su carpeta mantiene
recuperable la configuración de los modelos que aún no se han migrado.
