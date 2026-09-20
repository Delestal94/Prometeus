# Prometeus

Proyecto de desarrollo de un videojuego indie (desarrollo en solitario, asistido por
IA), con el objetivo de aplicar patrones de éxito observados en juegos de Steam hechos
por 1-2 personas.

Nombre del juego (de trabajo): **Do Not Drop** — delivery cooperativo de hasta 5
jugadores: 1 conduce, hasta 4 llevan un paquete con una "trampa" cada uno (ver
`docs/definicion-proyecto.md` y `docs/requerimientos-tecnicos.md`).

## Motor
Godot 4.x

## Documentación

### Vigente (proyecto actual: Do Not Drop)
- `docs/investigacion-mercado.md` — investigación de 20 juegos de Steam hechos por 1-2
  personas: equipo, ventas, motor, tiempo de desarrollo. (Contexto general, sigue
  vigente como referencia de fondo.)
- `docs/checklist-exito.md` — items replicables extraídos de esa investigación.
  (Igual de vigente, son patrones generales.)
- `docs/mecanicas-candidatas.md` — banco de mecánicas transversales reutilizables
  (recurso de referencia general para futuras decisiones).
- `docs/definicion-proyecto.md` — **definición del concepto actual** (Do Not Drop).
- `docs/requerimientos-tecnicos.md` — stack técnico, motor, networking, arte, diseño
  de adicción/rejugabilidad.
- `docs/arquitectura.md` — arquitectura de software del proyecto (componentes,
  patrones, estructura de carpetas).
- `docs/plan-desarrollo.md` — plan de desarrollo por fases, con Definition of Done.
- `docs/parametros-diseno.md` — valores numéricos iniciales de cada trampa y fórmula
  de puntaje.
- `docs/controles-y-ui.md` — esquema de controles y flujo de UI/lobby.
- `docs/convenciones-godot.md` — Input Map, capas de física, estructura real de
  carpetas y convenciones de nombres dentro del proyecto Godot (`do-not-drop/`).

### Archivado (`docs/historial-exploracion/`)
Documentos de una etapa de exploración anterior, **superados** por el pivote a
"Do Not Drop". Se conservan como registro del proceso, no como referencia vigente:
- `mvp-candidatos.md`, `ideas-candidatas.md`,
  `opcion-descartada-aseguradora-paranormal.md`.
