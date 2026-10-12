# Aviso: `RoadNetwork` en `route_gen` y grafo de calles del modo Empresa (D-0304, 2026-10-12)

Lo hizo Nacho (rutina `desarrollador`, carril 4). Zona compartida: `do-not-drop/modules/route_gen/`, `docs/modulos.md`.

- **Nuevo** en `modules/route_gen/`: `RoadNetwork`, `RoadNode`, `RoadEdge` (grafo de calles con aristas Bézier; largo,
  muestreo, punto más cercano, celdas cruzadas, camino mínimo que se frena en un bloqueo cerrado, validación) y su test
  `tests/test_road_network.gd`. No cambia ningún archivo existente del módulo (solo el `summary` de `module.cfg`).
  Sin nombres del juego: `check_modules.py` y `portability-check.sh route_gen` pasan.
- El juego lo usa desde `scripts/gameplay/districts/road_graph.gd` y `data/world/road_graph.tres`. Nada de la ruta de
  entregas ni del Endless lo usa todavía.
- Slatex: nada que hacer.
