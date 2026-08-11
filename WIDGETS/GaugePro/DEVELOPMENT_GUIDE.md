# Gauge Pro — Guía de desarrollo para Dial, Bar y Core

**Estado:** contrato normativo de desarrollo
**Aplica a:** `GaugeDial`, `GaugeBar`, `GaugeCore` y `GaugePro` legacy durante la transición
**Plan relacionado:** [`../../myplans/gaugepro-split-plan.md`](../../myplans/gaugepro-split-plan.md)

---

## 1. Principio del producto

Gauge Pro se presenta al usuario como **dos widgets separados**:

- `GaugeDial`: instrumentos circulares, Needle y Arc.
- `GaugeBar`: instrumentos lineales y sus caras de barra.

Internamente son **un solo producto con un core compartido**. No son forks ni dos copias de
Gauge Pro. Una corrección o mejora transversal se implementa una vez en el core y queda disponible
para ambas familias.

La separación visible existe para ofrecer opciones y layouts honestos. No autoriza duplicar
telemetría, estados, escalas, formato, color, historial, alertas u optimizaciones.

---

## 2. Regla principal: shared-first

Antes de modificar Dial o Bar, clasificar el cambio:

| Clase | Ejemplos | Destino obligatorio |
|---|---|---|
| Comportamiento compartido | telemetría, presets, thresholds, estado, smoothing, historial, alertas, formato, tema, contraste, batching LVGL | Core común |
| Presentación equivalente | badges, jerarquía de valor/unidad/nombre, color semántico, dropout, reconnect, min/max | contrato común + adaptación de ambas familias |
| Geometría específica | arco, aguja, sweep, eje lineal, segmentos, hex, dual rail | layout/renderer de su familia |
| Bootstrap/configuración | registro, nombre, `DEFS`, traducciones, `CORE_PATH` | frente del widget |

Si una mejora hecha para una familia tiene sentido para la otra, debe ocurrir una de estas cosas
antes de mergear:

1. se mueve la regla compartida al core y ambas familias la consumen;
2. se implementan los dos adaptadores familiares en el mismo cambio;
3. se documenta como **no aplicable** con evidencia concreta.

“Después lo copiamos al otro renderer” no es una estrategia aceptable. Una excepción temporal
requiere decisión explícita del propietario, razón técnica, test que exponga la asimetría y tarea
de cierre identificada.

---

## 3. Fronteras y dependencias

Dirección permitida:

```text
GaugeDial main ─┐
                ├─> app/composición ─> core común
GaugeBar main ──┘                     ├─> dial layout + renderer
                                      └─> bar layout + renderer
```

Reglas:

- El core común no importa módulos de Dial ni de Bar.
- Dial y Bar pueden importar core común; no pueden importarse entre sí.
- Solo la capa de composición (`app.lua`/loader) decide qué familia cargar.
- Un renderer no resuelve telemetría, thresholds, presets, alertas ni opciones.
- Un layout no lee directamente la radio; recibe configuración y estado ya resueltos.
- Los frentes no contienen lógica de negocio o dibujo. Solo registro, opciones, traducciones,
  guard de compatibilidad, ruta del core y delegación lifecycle.
- No se usan `_G`, globals implícitos ni caches globales nuevas sin una decisión arquitectónica y
  medición que la justifique.

---

## 4. Propiedad de responsabilidades

### 4.1 Core común

Debe ser la única fuente para:

- resolución y disponibilidad de fuentes;
- escalas ascendentes/descendentes, thresholds y estado;
- presets, batería y agregación de celdas;
- precision/formato, value/unit/name;
- smoothing y tiempo;
- historial, min/max y reset;
- alertas y switches;
- tokens de tema, color semántico y contraste;
- estado visual común: NO SOURCE, NO DATA, STALE, NO LINK, WARN, CRIT;
- helpers LVGL compartidos, batching, dirty-state y ausencia de object churn;
- contratos de información: badge, valor, unidad, nombre y dropout/reconnect.

### 4.2 Dial

Solo posee:

- selección `DialStyle = Auto | Needle | Arc`;
- sweep, ángulos y geometría radial;
- ticks/arcos/rail circulares;
- aguja, pivot y marcas radiales;
- composición específica dentro y alrededor del dial.

### 4.3 Bar

Solo posee:

- presets y caras de barra;
- eje horizontal/vertical y origen en mínimo/cero;
- rail, fill, segmentos, ticks, steps, hex y dual rail;
- head, casing, dirección, grosor y extremos;
- composición específica de las regiones lineales.

### 4.4 Frentes

`GaugeDial/main.lua` y `GaugeBar/main.lua` solo poseen:

- `NAME`, `SPEC.family`, `SPEC.coreApi` y `DEFS`;
- labels/traducción;
- builder de la tabla de opciones;
- `lvgl` compatibility guard;
- `CORE_PATH` fijo de producción;
- memoización de `sharedApp` y delegación `create/update/refresh`.

Si un frente empieza a necesitar una función reutilizable, esa función ya está en la capa
equivocada.

---

## 5. Guardrails de paridad

Dial y Bar deben mantener el mismo contrato cuando el concepto sea común:

| Contrato | Dial | Bar |
|---|---:|---:|
| Misma lectura y unidad | obligatorio | obligatorio |
| Mismos thresholds/estado/hysteresis | obligatorio | obligatorio |
| Mismos colores semánticos | obligatorio | obligatorio |
| Mismo significado de ColorMode | obligatorio; representación radial | obligatorio; representación lineal |
| Mismos estados de ausencia | obligatorio | obligatorio |
| Mismo reset e historial | obligatorio | obligatorio |
| Mismas reglas de badge y accesibilidad | obligatorio | obligatorio |
| Misma política de smoothing | obligatorio | obligatorio |
| Mismas alertas | obligatorio | obligatorio |
| Misma ausencia de object churn | obligatorio | obligatorio |

La geometría puede diferir. La semántica no.

Toda corrección de un contrato de esta tabla exige:

- test compartido ejecutado contra las dos familias; o
- dos casos hermanos con el mismo nombre/identificador de contrato.

---

## 6. Guardrails de opciones

- Los widgets nuevos tienen contratos independientes del legacy, pero quedan congelados después
  de su primera release.
- Slots compartidos 1–9 de Dial y Bar son idénticos en key, type, default, rango y choices.
- Slot 10 es específico: `DialStyle` en Dial, `BarPreset` en Bar.
- EdgeTX 2.11 debe declarar exactamente los primeros 10 slots.
- Las opciones posteriores son append-only. No insertar, borrar ni reordenar.
- CHOICE siempre es entero 1-based; nunca se compara con strings en runtime.
- Una opción común se añade a ambos frentes en el mismo cambio y con el mismo field/type/default.
- Una opción familiar no se filtra al otro settings screen.
- El nombre del widget y cada key deben caber en 10 caracteres.
- Los labels pueden mejorar sin alterar el wire contract.

Un cambio de opciones incluye golden lists para 2.11 y 2.12+.

---

## 7. Guardrails del core y lifecycle

- El tercer argumento de `create()` es `widgetPath`; nunca es la ruta del core.
- Producción carga exclusivamente desde `CORE_PATH = "/SCRIPTS/TOOLS/GaugeCore/"`.
- Tests inyectan `corePath` al ejecutar el chunk del frente, no mediante `create()`.
- Frente y core validan `coreApi` antes de crear el widget.
- El core se carga en primer uso; `main.lua` permanece boot-light.
- Varias instancias de la misma familia comparten `sharedApp` y módulos.
- Dial no carga módulos exclusivos de Bar; Bar no carga módulos exclusivos de Dial.
- Estado mutable vive en `widget`, no en tablas de módulo compartidas.
- Cambios no estructurales actualizan propiedades; no reconstruyen el árbol LVGL.
- Resize o cambio estructural usa la firma existente y reconstruye de forma controlada.

---

## 8. Guardrails de rendimiento

No se acepta una mejora visual que degrade silenciosamente el transmisor.

Preservar como mínimo:

- ordinary callback `< 2000` instrucciones;
- transition callback `< 6000`;
- structural callback `< 10000`;
- cero objetos nuevos durante refresh estable;
- allocations steady-state sin regresión frente al baseline aprobado;
- techo de objetos por cara y zona;
- caches acotadas;
- carga de chunks una vez por familia usada, no una vez por instancia.

Cambios en core compartido se miden con Dial, Bar y el escenario mixto Dial + Bar. Medir una sola
familia no es suficiente porque puede ocultar duplicación o regresión en la otra.

---

## 9. Guardrails de tests y evidencia

Puertas mínimas para cualquier cambio:

1. unit y lifecycle completamente verdes antes y después;
2. luacheck sin errores ni warnings nuevos;
3. tests de ambas familias para toda regla compartida modificada;
4. paridad de estados y opciones;
5. object churn = 0 durante vuelo estable;
6. containment en la matriz de zonas;
7. manifests/galerías de las familias afectadas;
8. instrucciones, allocations y census cuando cambia layout, renderer, core o carga de módulos;
9. simulador/radio para registro, settings, cold boot y paquete instalado.

No actualizar un golden count o screenshot solo para hacerlo verde. Primero determinar si cambió
el contrato o si se perdió geometría.

---

## 10. Guardrails de deploy y compatibilidad

- El paquete nuevo contiene Core + Dial + Bar.
- El paquete de transición añade GaugePro legacy.
- Copiar primero core y luego frentes.
- Verificar `coreApi` y manifest después de copiar.
- Limpiar bytecode únicamente dentro de los targets exactos y validados.
- No borrar `WIDGETS/GaugePro` automáticamente.
- No renombrar el legacy para “migrar”: el modelo referencia otra factory.
- Una instalación sin core debe registrar el frente y mostrar un error accionable al usarlo.

---

## 11. Checklist obligatorio de cambio

Antes de abrir o aprobar un PR:

- [ ] Clasifiqué el cambio como común, equivalente, específico o bootstrap.
- [ ] Expliqué por qué aplica o no aplica a la otra familia.
- [ ] La lógica compartida vive en core, no está copiada.
- [ ] Dial y Bar no se importan entre sí.
- [ ] No alteré slots publicados ni semántica 1-based.
- [ ] Añadí prueba de ambas familias cuando el contrato es común.
- [ ] Verifiqué ausencia de object churn y regresiones de recursos.
- [ ] Actualicé evidencia visual si cambió el resultado visible.
- [ ] Probé el path real del core y la incompatibilidad de `coreApi` si toqué bootstrap/deploy.
- [ ] Documenté cualquier asimetría deliberada y su evidencia.

Una revisión no debe aprobar “funciona en Dial” o “funciona en Bar” como evidencia suficiente
para una regla compartida.

---

## 12. Regla para excepciones

Una excepción a esta guía necesita:

1. problema concreto que impide compartir o mantener paridad;
2. impacto en usuario, RAM, CPU y mantenimiento;
3. alternativa descartada;
4. alcance y duración de la excepción;
5. test que haga visible la diferencia;
6. aprobación explícita del propietario.

Sin esos seis puntos, prevalece la regla shared-first.
