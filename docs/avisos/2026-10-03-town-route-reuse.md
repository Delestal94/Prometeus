# N-950: ciudad sobre los sistemas existentes de carretera

Nuevos adaptadores `town_environment.gd`, `town_terrain.gd` y `town_dresser.gd`:
- El primero reutiliza `route_terrain.gd`/TerrainField y StraightSegment sobre
  los segmentos del grafo, en lugar del suelo plano gigante. Registra reservas
  niveladas para calles, lotes y accesos; conserva el shader/texturas originales
  y relieve en los alrededores. TownTerrain extiende el terreno del juego:
  nivela contornos urbanos y mezcla el relieve por fuera en 24 m. Recorta pintura que invadiría otra calle.
- El segundo extiende RouteDresser y reutiliza catálogo, _apply_rule y
  RoutePlacement con un perfil urbano y reservas para lotes/caminos/plazas.
  Suelta los helpers del recorrido lineal que no utiliza para romper sus
  referencias circulares; no cambia la clase original ni sus eventos.

`town_prototype.gd` monta terreno, tramos y decorado agrupado. Conserva el
mismo grafo, semillas, versión, direcciones, accesos y dos distritos abiertos.
No se modifica route_gen, la ruta anterior ni la lógica de campaña/RPC.
`test_town_prototype` verifica esta integración además de sus comprobaciones
previas; `test_town_delivery` cubre reparto, conducción y marcha reales.
Capturas en `render_town_prototype` muestran el nuevo conjunto. Actualizar
la rama antes de tocar estos adaptadores; densidad de manzanas pendiente.
