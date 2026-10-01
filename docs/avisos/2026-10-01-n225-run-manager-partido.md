# Aviso: `run_manager.gd` partido por responsabilidad (N-225.5)

Zona compartida: `scripts/core/run_manager.gd` (1000 → 669 líneas) y seis archivos nuevos en la misma carpeta.
Refactor puro: sin cambio de comportamiento, de RPC ni de `PROTOCOL_VERSION`; los números del puntaje y de los
plazos son los mismos.

Helpers estáticos que reciben lo que necesitan (nada nombra un autoload, así que compilan antes que ellos), cargados
solo por `run_manager.gd` con `preload` (sin `class_name`):

- `run_scoring.gd`: puntos por puerta (`resolve_deliveries`), carga que volvió (`settle`) y puntaje del infinito.
- `run_results.gd`: filas por parada, evento de ruta del resultado e historias (`rescue_stories`, `world_stories`).
- `run_deadlines.gd`: plan de plazos, el próximo abierto y el conteo de cumplidos / vencidos.
- `run_deliveries.gd`: registros de entrega (¿llegó la caja?, fotos, a quién reclamar) y cercanía a la puerta.
- `run_leaderboard.gd`: tabla local (mejor puntaje, alta, tope por modo, leer y guardar).
- `run_session.gd`: la parte de la escena de un ingreso tardío (puerta del depósito, cajas ya entregadas).

`RunManager` conserva todas las variables, las señales, `_ready` / `_physics_process`, los cinco `@rpc` en el mismo
orden y con las mismas anotaciones, y los métodos que usan otros archivos o tests (`finish_run`, `_record_score`,
`_resolve_deliveries`, `deadline_tally`, `plan_deadlines`, `handed_over`, `rescue_stories`…) como envoltorios. Las
constantes públicas (`POINTS_*`, `PENALTY_*`, `MAX_DEADLINES`, `PHOTO_REACH`…) ahora viven junto al código que las
usa y `RunManager` las reexporta con el mismo nombre y valor. Se quitó de `RunManager` la constante `SAFE_JSON` (nadie
la leía de afuera; la usa `run_leaderboard.gd`).

Si agregás lógica a la corrida, va en el helper de su responsabilidad; `tests/test_run_manager_split.gd` falla si
`run_manager.gd` pasa de 700 líneas, si cambia la tabla de RPC o si se pierde algo de la API pública.

Qué hacer: `git pull` antes de tocar la corrida o el puntaje.
