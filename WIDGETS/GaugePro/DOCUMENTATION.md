# Gauge Pro — mapa de documentación

Este índice separa el contrato vigente de los artefactos históricos del GaugePro monolítico.

## Identidad vigente

| Concepto | Dial | Bar |
|---|---|---|
| Nombre visible | **Gauge Dial Pro** | **Gauge Bar Pro** |
| ID interno EdgeTX | `DialPro` | `BarPro` |
| Carpeta SD | `/WIDGETS/GaugeDialPro/` | `/WIDGETS/GaugeBarPro/` |
| Familia fija | `dial` | `bar` |
| Opciones en 2.11 | 10 | 10 |
| Opciones en 2.12+ | 24 | 42 |

Los IDs internos respetan el límite de 10 caracteres de EdgeTX. Ambos frentes cargan
`/SCRIPTS/TOOLS/GaugeCore/app.lua` y exigen `coreApi = 1`. `GaugePro` es únicamente el frente
legacy opcional de transición y conserva su contrato histórico de 44 opciones.

## Documentos normativos y actuales

- [`README.md`](README.md): presentación, instalación, arquitectura y comandos de prueba.
- [`DOCS.md`](DOCS.md): referencia completa de usuario y técnica.
- [`MIGRATION.md`](MIGRATION.md): migración manual segura desde `GaugePro`.
- [`DEVELOPMENT_GUIDE.md`](DEVELOPMENT_GUIDE.md): guardrails shared-first y límites entre familias.
- [`../../myplans/gaugepro-split-plan.md`](../../myplans/gaugepro-split-plan.md): plan ejecutado,
  decisiones, gates y evidencia del split.
- [`../../tools/gaugepro-visual-kit/README.md`](../../tools/gaugepro-visual-kit/README.md):
  emulador visual sobre firmware real, contratos split y comandos de captura.
- [`docs/visual-kit/RUN_SUMMARY.md`](docs/visual-kit/RUN_SUMMARY.md): última corrida del catálogo.

Ante una contradicción, prevalecen en ese orden la implementación y las pruebas de contrato,
la guía de desarrollo, la referencia técnica y el plan ejecutado.

## Artefactos históricos

`PLAN.md`, `IMPROVEMENT_PLAN.md`, `BAR_STYLE_IMPROVEMENT_PLAN.md`, `AUDIT.md`, los reportes
`PHASE*.md`, `USERDATA_INDEX_REMEDIATION.md` y los reviews de `dev/` documentan
etapas anteriores. Conservan nombres, conteos y enlaces de línea del GaugePro monolítico para
mantener trazabilidad; no definen la arquitectura o instalación actual. Algunos enlaces a los
antiguos `layout.lua` y `renderer.lua` ya no resuelven porque esos módulos se dividieron en
`layout_common.lua`, `dial_layout.lua`, `bar_layout.lua`, `ui_core.lua` y `dial_renderer.lua`.

Las capturas antiguas fuera de `docs/visual-kit/` siguen siendo snapshots del monolito. El visual
kit vigente adapta su catálogo de escenas a ambos contratos sin reintroducir `Style` en el YAML.

## Convención para documentación nueva

- Usar **Gauge Dial Pro** y **Gauge Bar Pro** al describir lo que ve el usuario.
- Usar `DialPro` y `BarPro` únicamente para `name`, factories o datos persistidos por EdgeTX.
- Usar `GaugeDialPro` y `GaugeBarPro` para carpetas, paquetes y nombres técnicos de los frentes.
- Llamar `GaugeCore` al runtime compartido y mencionar `coreApi` cuando se documente despliegue.
- Llamar `GaugePro legacy` al frontend de transición; no presentarlo como instalación nueva.
