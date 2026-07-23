Sí. Después de revisar el estado actual de EdgeTX, su rama 3.0, cambios recientes, documentación de LVGL, arquitectura de TouchGFX y capacidades gráficas de STM32H7, **yo no empezaría dibujando una interfaz nueva**.

El orden correcto sería:

> **medir → estabilizar arquitectura → optimizar renderizado → crear sistema de diseño → migrar pantallas → añadir animaciones y funciones premium.**

EdgeTX ya intentó avanzar hacia una nueva interfaz en 3.0, pero el propio proyecto reconoce que esa UI todavía no estaba lista para producción y por eso publicó la serie 2.12 para estabilizar los nuevos radios STM32H7. Eso demuestra que el problema no se resuelve únicamente haciendo pantallas más bonitas: requiere una migración arquitectónica controlada. ([GitHub][1])

# Las referencias que usaría como inspiración

Investigué al menos estas siete áreas:

1. **ETHOS:** diseño desde cero orientado a touch, jerarquía visual, tarjetas y navegación simplificada.
2. **LVGL moderno:** renderizado parcial, buffers configurables, observables y separación entre datos y controles.
3. **TouchGFX:** patrón Model–View–Presenter para aislar la lógica del firmware de la presentación. ([support.touchgfx.com][2])
4. **STM32H7:** CPU Cortex-M7 de hasta 480 MHz, caché L1, controladores gráficos y acceso a memoria externa. ([STMicroelectronics][3])
5. **Arquitectura pub/sub:** EdgeTX ya empezó a incorporar mensajería publish/subscribe en la interfaz de color, por lo que no conviene reemplazar ese trabajo, sino ampliarlo. ([GitHub][4])
6. **Carga diferida:** EdgeTX 2.12 ya aplica lazy loading a widgets incorporados para mejorar la respuesta, una señal clara de que la inicialización y gestión de recursos sí afectan la experiencia. ([GitHub][1])
7. **Simulación y pruebas:** EdgeTX ya tiene Companion y simulador multiplataforma, lo cual permite hacer pruebas visuales automatizadas sin depender siempre del radio físico. ([GitHub][5])

---

# Mi plan óptimo para EdgeTX

## Fase 0 — Congelar el alcance

Antes de tocar código, separaría EdgeTX en tres dominios:

```text
Flight-critical
├── Mixer
├── ADC y sticks
├── RF y generación de pulsos
├── Failsafe
└── Telemetría crítica

Application
├── Modelos
├── Configuración
├── Storage
├── Audio
└── Lua

Presentation
├── Navegación
├── Pantallas
├── Widgets
├── Temas
└── Animaciones
```

La nueva interfaz solo podría comunicarse con el núcleo mediante interfaces bien definidas.

**No permitiría que una pantalla nueva modifique directamente el mixer, estructuras internas o buffers RF.**

Esta separación es la primera condición para evitar que un error gráfico afecte funciones esenciales del transmisor.

---

# Fase 1 — Construir telemetría de rendimiento

Este sería el primer cambio real.

No se debe optimizar una interfaz embebida basándose en si “se siente lenta”. Hay que medirla.

## Métricas que añadiría

* Tiempo de creación de cada pantalla.
* Tiempo promedio y máximo de frame.
* FPS efectivo.
* Píxeles o área invalidada por frame.
* Número de objetos LVGL activos.
* Uso de CPU por tarea.
* Tiempo esperando a SD.
* Tiempo decodificando imágenes.
* Uso máximo de heap y stack.
* Fragmentación de memoria.
* Cantidad de allocations durante navegación.
* Duración de callbacks Lua.
* Frames perdidos o renderizados fuera del presupuesto.
* Transferencias DMA2D y duración.
* Fallos de caché, cuando sea posible medirlos.

Crearía un overlay de desarrollo:

```text
FPS:                29.8
Frame avg:          11.4 ms
Frame p99:          23.7 ms
Dirty area:         18 %
LVGL objects:       286
Heap free:          7.8 MB
Largest block:      6.9 MB
SD wait:            0.2 ms
Lua execution:      1.4 ms
```

## Presupuestos de rendimiento

Para H7:

* Navegación normal: **30 FPS estables**.
* Presupuesto por frame: **33,3 ms**.
* Interacción táctil: respuesta visual en menos de **50 ms**.
* Apertura de pantallas frecuentes: menos de **100 ms**.
* Ninguna operación gráfica podría bloquear tareas críticas.

Para F4:

* Objetivo visual: **20–30 FPS**, según resolución.
* Animaciones reducidas.
* Menor número de capas y transparencias.

### Por qué va primero

EdgeTX 2.12 incluye mejoras como carga diferida de widgets y aceleración del inicio en F4, pero sin una suite pública de benchmarks es difícil impedir regresiones futuras. ([GitHub][1])

---

# Fase 2 — Crear una plataforma gráfica común

Actualmente EdgeTX debe atender radios muy distintos. No diseñaría cada pantalla para un modelo particular.

Crearía una capa denominada, por ejemplo:

```text
EdgeUI Platform
```

## Responsabilidades

* Inicialización del display.
* Configuración de buffers.
* Gestión del framebuffer.
* Sincronización VSYNC.
* Integración con DMA2D.
* Gestión de caché del Cortex-M7.
* Touch, encoder y botones.
* Densidad y escala de pantalla.
* Carga de recursos.
* Métricas de renderizado.
* Diferencias entre F4 y H7.

La interfaz superior no debería saber si se está ejecutando en:

* 480 × 272.
* 480 × 320.
* 800 × 480.
* F4.
* H7.
* Touchscreen.
* Solo encoder.

Debería preguntar capacidades:

```cpp
struct UiCapabilities {
    bool touchscreen;
    bool dma2d;
    bool doubleBuffer;
    bool hardwareJpeg;
    bool advancedAnimations;
    uint16_t width;
    uint16_t height;
    uint32_t memoryBudget;
};
```

EdgeTX ya viene trasladando definiciones de hardware a archivos JSON y consolidando capacidades de las placas. Extender ese enfoque sería más coherente que continuar acumulando condicionales de compilación dispersos. ([GitHub][4])

---

# Fase 3 — Arreglar el pipeline de renderizado

Esta es probablemente la fase con mayor impacto en la fluidez.

## 3.1 Dirty rectangles

Solo se debe actualizar la región que cambió.

Ejemplo: si el RSSI pasa de 91 a 90, no se debe repintar:

* La imagen del modelo.
* Todas las tarjetas.
* El fondo completo.
* Los demás widgets.
* La barra de navegación.

Únicamente:

```text
RSSI value + icon/bar affected region
```

## 3.2 Frame pacing estable

Una interfaz a 30 FPS estables se percibe mejor que una que fluctúa entre 15 y 60 FPS.

Implementaría:

```text
Input sampling        100–200 Hz
GUI state updates       20–50 Hz
Animations                  30 Hz
Slow telemetry              5–10 Hz
Static elements          on-change
```

No todos los datos necesitan refrescarse a la misma frecuencia.

## 3.3 DMA2D

En los radios H7 compatibles usaría DMA2D para:

* Copias de bloques.
* Relleno de áreas.
* Alpha blending.
* Conversión de formatos.
* Composición de imágenes.
* Movimiento de regiones.

## 3.4 Double buffering

Donde el ancho de banda y la RAM lo permitan:

```text
LVGL renderiza Buffer B
LTDC muestra Buffer A
VSYNC
Intercambio A ↔ B
```

Esto reduce tearing y evita mostrar frames parcialmente dibujados.

## 3.5 Gestión correcta de memoria H7

Aquí hay que ser especialmente cuidadoso.

En STM32H7:

* Algunas memorias no son accesibles por todos los DMA.
* Los framebuffers externos requieren configuración correcta del MPU.
* La D-cache debe limpiarse o invalidarse en las regiones adecuadas.
* El ancho de banda de SDRAM puede convertirse en el cuello de botella, incluso teniendo una CPU de 480 MHz.

ST documenta que los H7 combinan caché L1, interfaces de memoria externa y aceleración gráfica, pero esas capacidades deben integrarse correctamente; no funcionan automáticamente por utilizar un MCU más rápido. ([STMicroelectronics][6])

---

# Fase 4 — Convertir la interfaz a un modelo reactivo

Este paso ya tiene una base importante: en enero de 2026 EdgeTX integró mensajería publish/subscribe para simplificar y consolidar el código de la interfaz de color. Yo tomaría esa implementación como fundamento, no comenzaría otra distinta. ([GitHub][4])

## Estado actual típico

Una pantalla consulta datos:

```cpp
void Widget::refresh()
{
    auto value = getTelemetryValue(source);
    label->setText(format(value));
}
```

Aunque el valor no cambie:

* Se consulta.
* Se convierte.
* Se formatea.
* Se compara.
* Posiblemente se invalida.

## Arquitectura propuesta

```cpp
Subject<float> batteryVoltage;
Subject<int16_t> rssi;
Subject<bool> telemetryConnected;
```

El widget se suscribe:

```cpp
batteryVoltage.subscribe([](float value) {
    batteryCard.setVoltage(value);
});
```

Solo se ejecuta cuando el estado cambia.

## Flujo

```text
Telemetry task
      │
      ▼
State store / snapshot
      │
      ▼
Publish-subscribe bus
      │
      ▼
View model
      │
      ▼
LVGL component
```

## Ventajas

* Menos polling.
* Menos redibujados.
* Menos dependencia entre módulos.
* Pruebas unitarias más fáciles.
* Pantallas más sencillas.
* Mejor soporte para Companion.
* Mayor facilidad para registrar y reproducir sesiones.

---

# Fase 5 — Adoptar una arquitectura MVP/MVVM ligera

No usaría un framework pesado, pero sí una división estricta inspirada en el patrón Model–View–Presenter utilizado por TouchGFX.

TouchGFX separa la vista gráfica de la lógica mediante presenters y un modelo compartido, precisamente para reducir el acoplamiento entre pantallas y backend. ([support.touchgfx.com][2])

## En EdgeTX

```text
Model
└── Datos reales de EdgeTX

ViewModel / Presenter
└── Convierte datos técnicos en estado visual

View
└── Controles LVGL
```

Ejemplo:

```cpp
struct BatteryViewState {
    std::string text;
    uint8_t percentage;
    BatterySeverity severity;
    bool showWarning;
};
```

La vista no debería saber:

* Cómo se calcula el porcentaje.
* Cuántas celdas tiene la batería.
* Cuál es el umbral configurado.
* Qué sensor produjo el valor.

Solo recibe un estado listo para dibujar.

---

# Fase 6 — Crear un sistema de diseño oficial

Solo después de estabilizar la arquitectura comenzaría la renovación visual.

## Design tokens

```cpp
namespace UiToken {
    constexpr int SpaceXs = 4;
    constexpr int SpaceSm = 8;
    constexpr int SpaceMd = 12;
    constexpr int SpaceLg = 16;

    constexpr int RadiusSm = 6;
    constexpr int RadiusMd = 10;
    constexpr int RadiusLg = 14;

    constexpr int MotionFast = 120;
    constexpr int MotionNormal = 180;
}
```

## Tipografía

Definiría roles, no tamaños arbitrarios:

```text
Display
Title
Heading
Body
Label
Caption
NumericLarge
NumericCompact
```

## Colores semánticos

```text
surface
surfaceElevated
surfaceSelected
textPrimary
textSecondary
accent
success
warning
critical
focus
disabled
```

No permitiría usar colores RGB directos dentro de una pantalla.

## Componentes oficiales

Crearía una biblioteca única:

* `UiCard`
* `UiListItem`
* `UiSection`
* `UiToolbar`
* `UiBottomSheet`
* `UiDialog`
* `UiToggle`
* `UiSlider`
* `UiValueEditor`
* `UiSourcePicker`
* `UiSwitchPicker`
* `UiChart`
* `UiStatusChip`
* `UiTelemetryTile`
* `UiEmptyState`
* `UiToast`

Esto evitaría que cada desarrollador construya sus propios botones, márgenes y diálogos.

---

# Fase 7 — Sistema responsive por breakpoints

EdgeTX ya soporta resoluciones y layouts diferentes, incluyendo nuevos diseños y recursos para 800 × 480, pero también ha tenido errores relacionados con redimensionamiento de widgets y layouts. ([GitHub][1])

No intentaría escalar coordenadas proporcionalmente.

Definiría breakpoints:

```text
Compact:   320 × 240
Standard:  480 × 272 / 480 × 320
Large:     800 × 480
```

Una pantalla podría comportarse así:

```text
Compact
┌────────────────┐
│ Title          │
│ Single column  │
│ Bottom actions │
└────────────────┘

Standard
┌────────────────────────┐
│ Title                   │
│ Main list │ Information │
└────────────────────────┘

Large
┌────────────────────────────────┐
│ Navigation │ Content │ Details │
└────────────────────────────────┘
```

No usaría simplemente:

```cpp
x = originalX * screenWidth / 480;
```

Eso agranda una interfaz antigua, pero no la convierte en una buena interfaz.

---

# Fase 8 — Rediseñar primero los flujos más usados

No migraría todas las pantallas simultáneamente.

## Orden óptimo

### 1. Home/dashboard

Porque es lo primero que ve el usuario y permite validar:

* Tarjetas.
* Widgets.
* Temas.
* Responsive layout.
* Telemetría reactiva.
* Rendimiento.

### 2. Selector y gestión de modelos

Debe tener:

* Imagen.
* Búsqueda.
* Favoritos.
* Modelos recientes.
* Duplicar.
* Categorías.
* Estado del receptor.
* Último uso.

### 3. Creación de modelos

Un asistente progresivo:

```text
Tipo de modelo
→ Ala/plato cíclico
→ Canales
→ Receptor
→ Controles
→ Prueba
→ Guardar
```

### 4. Inputs, mixes y outputs

Es el núcleo funcional y la parte más difícil.

Aquí usaría:

* Vista resumida.
* Vista avanzada.
* Diagrama del flujo.
* Detección automática de controles.
* Previsualización en tiempo real.
* Validación de configuraciones.
* Deshacer.

### 5. Telemetría

* Descubrimiento más claro.
* Estado de cada sensor.
* Unidades.
* Valores mínimos/máximos.
* Frecuencia de actualización.
* Alertas.
* Gráficas.

### 6. Configuración del radio

Agrupada por intención:

```text
Display
Sound
Controls
Connectivity
Storage
Safety
Advanced
About
```

### 7. Herramientas y Lua

Solo después de estabilizar la API visual.

---

# Fase 9 — Animaciones, pero después del rendimiento

Las animaciones serían una capa final, no el fundamento de la nueva UI.

## Permitidas

* Feedback al tocar: 80–120 ms.
* Cambio de foco: 100–150 ms.
* Apertura de modal: 150–180 ms.
* Cambio de página: 180–220 ms.
* Interpolación de barras e indicadores.
* Expansión de secciones.

## Evitaría

* Blur dinámico.
* Transparencia de pantalla completa.
* Sombras grandes recalculadas.
* Fondos animados.
* Escalado continuo de fotografías.
* Animaciones que bloqueen navegación.
* Transiciones obligatorias en F4.

## Regla

```text
La animación debe explicar el cambio de estado.
No debe existir únicamente para decorar.
```

También incluiría:

* `Reduced motion`.
* Desactivación automática de animaciones en hardware limitado.
* Cancelación inmediata al recibir otra interacción.

---

# Fase 10 — Gestión profesional de recursos

EdgeTX ya aplica lazy loading en widgets incorporados para mejorar la respuesta. Extendería esa idea a todo el sistema. ([GitHub][1])

## Recursos esenciales en firmware/QSPI

* Iconos del sistema.
* Fuentes básicas.
* Controles esenciales.
* Pantallas de recuperación.
* Recursos del bootloader.
* Tema predeterminado.

## Recursos de usuario en SD

* Fotos de modelos.
* Temas adicionales.
* Sonidos.
* Scripts.
* Widgets comunitarios.

## Añadiría

* Caché LRU de imágenes.
* Precarga de la siguiente pantalla probable.
* Decodificación asíncrona.
* Placeholders mientras carga una foto.
* Límites de tamaño y resolución.
* Conversión previa de recursos en Companion/Buddy.
* Atlas de iconos monocromáticos recoloreables.
* Fuentes con subconjuntos de glyphs.

La SD nunca debería ser necesaria para dibujar un botón crítico o abrir la configuración básica.

---

# Fase 11 — Virtualización de listas

Las listas grandes no deberían crear cientos de objetos LVGL.

Ejemplo: una lista de 200 fuentes debería mantener solamente:

```text
3 filas anteriores
8 filas visibles
3 filas siguientes
```

Al desplazarse, los controles se reciclan.

Aplicaría virtualización a:

* Sensores.
* Fuentes.
* Switches.
* Funciones especiales.
* Modelos.
* Archivos.
* Herramientas Lua.
* Selección de sonidos.

Esto reduce:

* Heap.
* Tiempo de apertura.
* Número de objetos.
* Trabajo de layout.
* Redibujado.

---

# Fase 12 — Mejorar Lua sin permitir que bloquee la UI

Lua es una de las mayores fortalezas de EdgeTX, pero necesita límites claros.

## Implementaría

* Presupuesto de ejecución por frame.
* Yield obligatorio para trabajos largos.
* API asíncrona para archivos.
* Cola de mensajes hacia la interfaz.
* Límites de memoria por widget.
* Estadísticas por script.
* Suspensión del widget que exceda repetidamente su presupuesto.
* API de componentes oficiales.
* API declarativa opcional.

Ejemplo conceptual:

```lua
local voltage = ui.observable("telemetry:RxBt")

return ui.card {
    title = "Receiver",
    ui.value {
        source = voltage,
        format = "%.2f V"
    }
}
```

No permitiría que cada script dibuje continuamente la pantalla completa píxel por píxel en radios modernos.

EdgeTX continúa ampliando herramientas Lua y la posibilidad de ejecutarlas desde accesos rápidos, por lo que una API visual estable será cada vez más importante. ([GitHub][4])

---

# Fase 13 — Testing visual y funcional

Este proyecto fracasaría sin automatización.

## Pruebas que añadiría

### Golden screenshots

Cada pantalla se renderiza en Companion y se compara con una imagen de referencia.

```text
Expected image
       vs
Current render
       ↓
Pixel difference
```

### Matriz

* 320 × 240.
* 480 × 272.
* 480 × 320.
* 800 × 480.
* Encoder.
* Touch.
* Inglés.
* Alemán.
* Francés.
* Español.
* Texto largo.
* Tema claro.
* Tema oscuro.

### Pruebas de interacción

* Abrir página.
* Mover foco.
* Editar valor.
* Cancelar.
* Confirmar.
* Rotar encoder rápidamente.
* Tocar repetidamente.
* Cambiar de modelo.
* Desconectar SD.
* Ejecutar Lua pesado.

### Performance gates

Un pull request fallaría si:

* Aumenta el tiempo de frame más de cierto porcentaje.
* Reduce memoria libre por debajo del límite.
* Introduce allocations durante animación.
* Aumenta el tiempo de apertura de una pantalla.
* Cambia visualmente una pantalla sin actualizar su golden image.

El simulador y Companion ya forman parte central del ecosistema EdgeTX; aprovecharlos para pruebas visuales sería mucho más eficiente que validar todo manualmente en cada radio. ([GitHub][5])

---

# Fase 14 — Compatibilidad y despliegue

Mantendría dos experiencias:

## EdgeUI Core

Para F4:

* Mismo sistema de diseño.
* Pocas animaciones.
* Buffers parciales.
* Menos transparencias.
* Menor caché.
* Componentes simples.

## EdgeUI Enhanced

Para H7:

* Doble buffer.
* DMA2D.
* Transiciones.
* Más caché.
* 800 × 480.
* Mejor antialiasing.
* Navegación multipanel.
* Gráficas más avanzadas.

El usuario no debería elegir manualmente. El firmware seleccionaría el perfil según las capacidades declaradas por la placa.

La rama actual ya distingue entre radios F2, F4 y H7: la serie 2.11 permanece como última línea para F2, mientras 2.12 está orientada a estabilizar F4 y los nuevos H7. Por eso la modernización visual debería concentrarse primero en H7 sin abandonar una variante eficiente para F4. ([GitHub][1])

---

# Orden resumido de ejecución

| Orden | Cambio                                 | Motivo                                       |
| ----: | -------------------------------------- | -------------------------------------------- |
|     1 | Instrumentación y benchmarks           | Sin métricas no se sabe qué mejorar          |
|     2 | Separación del núcleo crítico y GUI    | Evita riesgos para mixer/RF                  |
|     3 | Plataforma gráfica común               | Elimina código específico disperso           |
|     4 | Pipeline DMA2D/LTDC/buffers/caché      | Produce la mejora real de fluidez            |
|     5 | Pub/sub y estado reactivo              | Reduce polling y redibujados                 |
|     6 | MVP/MVVM ligero                        | Hace mantenibles las pantallas               |
|     7 | Sistema de diseño y componentes        | Crea consistencia visual                     |
|     8 | Responsive layouts                     | Soporta correctamente todas las resoluciones |
|     9 | Migrar dashboard y modelos             | Valida la arquitectura con bajo riesgo       |
|    10 | Migrar inputs/mixes/outputs            | Aborda después el flujo más crítico          |
|    11 | Recursos, caché y listas virtualizadas | Reduce latencia y memoria                    |
|    12 | API Lua nueva                          | Permite ecosistema moderno sin bloquear GUI  |
|    13 | Animaciones adaptativas                | Se añaden cuando ya existen FPS estables     |
|    14 | Golden tests y performance gates       | Evita regresiones                            |
|    15 | Lanzamiento gradual H7 → F4            | Minimiza el riesgo del despliegue            |

# Lo que no haría

No haría ninguna de estas cosas inicialmente:

* Cambiar FreeRTOS.
* Portar EdgeTX a Linux.
* Introducir Flutter.
* Introducir Qt/QML.
* Reescribir el mixer.
* Reemplazar toda la interfaz en un solo merge.
* Migrar a LVGL 9 antes de medir y desacoplar el código actual.
* Abandonar F4 inmediatamente.
* Usar más animaciones para ocultar problemas de rendimiento.
* Leer todos los recursos esenciales desde SD.
* Permitir allocations dinámicas ilimitadas dentro del render loop.

# Mi decisión final como senior developer

El proyecto debería organizarse como **una modernización arquitectónica y no como un cambio de tema visual**.

La secuencia crítica es:

```text
Observabilidad
    ↓
Aislamiento
    ↓
Pipeline gráfico
    ↓
Estado reactivo
    ↓
Componentes
    ↓
UX
    ↓
Animaciones
```

El error más costoso sería comenzar por diseñar tarjetas bonitas. Eso produciría una demo atractiva, pero seguiría arrastrando acoplamiento, latencia, exceso de redibujado y problemas entre resoluciones.

La mejor ruta sería aprovechar lo que EdgeTX ya ha comenzado —H7, lazy loading, hardware definido por capacidades y publish/subscribe— y convertirlo en una plataforma gráfica formal. EdgeTX 3.0 debería salir cuando esa base sea medible, estable y compatible; no simplemente cuando todas las pantallas hayan recibido un nuevo estilo. ([GitHub][1])

[1]: https://github.com/EdgeTX/edgetx/releases "Releases · EdgeTX/edgetx · GitHub"
[2]: https://support.touchgfx.com/docs/development/ui-development/software-architecture/model-view-presenter-design-pattern "Model-View-Presenter Design Pattern | TouchGFX Documentation"
[3]: https://www.st.com/en/microcontrollers-microprocessors/stm32h7-series.html?utm_source=chatgpt.com "STM32H7 - Arm Cortex-M7 and Cortex-M4 MCUs (480 MHz)"
[4]: https://github.com/EdgeTX/edgetx/milestone/12?closed=1 "GitHub · Where software is built"
[5]: https://github.com/edgetx/edgetx "GitHub - EdgeTX/edgetx: EdgeTX is the cutting edge open source firmware for your R/C radio · GitHub"
[6]: https://www.st.com/en/microcontrollers-microprocessors/stm32h7-series/products.html?utm_source=chatgpt.com "STM32H7 series - Products"
