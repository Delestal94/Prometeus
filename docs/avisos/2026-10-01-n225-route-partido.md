# Aviso: `route.gd` partido por responsabilidad (N-225.3)

Zona compartida tocada solo en comentarios: `modules/route_gen/terrain_field.gd` (líneas 35 y 275) ahora nombra
`route_ground.gd` `clamp_river_reach()` en vez de `route.gd` `_clamp_river_reach()`. Sin cambio de código en el módulo.

- `route.gd` (948 → 499) mantiene su API pública y los miembros que leen los tests (`_path_points`,
  `_progress_samples`, `_house_anchors`, `_segments`, `_path_cumulative`, `_local_bounds`, `_house_road_gap`,
  `VERGE_ROUGHNESS`).
- Nuevos: `route_houses.gd` (casas y patios), `route_path.gd` (consultas sobre el camino), `route_ground.gd`
  (lo que se registra en el terreno y el recorte del río).
- Test: `tests/test_route_golden.gd` compara tres rutas con lo que armaba el archivo único.
