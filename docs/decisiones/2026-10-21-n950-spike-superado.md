# Decisión 2026-10-21: el spike de ciudad procedural (N-950) se cierra, lo reemplaza la expansión

Decide la conversación principal con la recomendación (regla 3 de `.claude/rutinas/README.md`; no es plata,
cuentas ni licencias), dentro del pedido del usuario de terminar la lista de Nacho.

**Decisión:** N-950 se cierra con 14 de 17 pasos hechos. Los tres que faltaban se tachan:

| Paso tachado | Por qué no se hace | Dónde vive ahora |
|---|---|---|
| Medición del spike: duración, esfuerzo de carga, visibilidad y render | Medía si una ciudad generada por semilla servía como mapa. Esa pregunta la cerró el mapa continuo de trazado fijo de la expansión, así que medir el prototipo ya no decide nada. | Rendimiento del mundo por celdas: grupos 02 y 20 de `docs/expansion-distritos/` |
| Completar manzanas interiores, horizonte y presupuesto de render | Construiría más ciudad dentro de un prototipo que el juego no carga (solo lo abren las escenas offline `town_*.tscn`). | Celdas de 256 m con impostores lejanos (decisión D-0104, punto 3) |
| Campaña persistente, guardado versionado y desbloqueo de distritos | Duplicaría la expansión. | D-0206 ✅ (guardado de empresa con versión y migraciones), D-0403, D-0408, D-0419 y D-0448 (desbloqueos por hitos), D-2010 ✅ (nube) |

**Por qué:** el spike nació el 2026-10-02 con "ciudad asimétrica y variable por semilla". Dos días después el
usuario decidió el mapa de la expansión ([2026-10-04-mapa-continuo.md](2026-10-04-mapa-continuo.md), D-0104): un
solo mapa continuo con **trazado fijo** ("un mapa fijo se puede aprender, señalizar y bloquear con sentido; uno
generado no"), celdas de 256 m y calles como grafo. Desde entonces los diez carriles de `desarrollador.md`
construyen ese mapa (D-0304, D-0304.1). Seguir con el spike sería trabajo en paralelo para un mapa que no va a salir.

**Qué queda igual:** no se borra nada. `modules/town_gen/` (plano, navegación y aceras), el módulo
`character_step` y las escenas `town_*.tscn` siguen en el repo con sus tests y su `docs/mapa-pueblo.md`, como
referencia portable. Si la expansión quiere reusar la navegación por calles o las aceras con cordón, se toman de ahí.
Borrar el prototipo es otra decisión, en su propio PR.

**Descartado:** terminar los tres pasos (unas tres corridas largas de trabajo que la expansión rehace igual) y
dejar N-950 abierta sin fecha (las rutinas la seguirían listando como trabajo real pendiente, como pasó en la
revisión del 2026-10-19).

**Cómo se revierte:** revirtiendo el PR de esta decisión. Vuelven a abrirse los tres pasos de `docs/tareas/N-950.md`.
