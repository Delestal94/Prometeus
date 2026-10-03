# N-950: conectores con acceso por ambos distritos

`do-not-drop/modules/town_gen/town_plan.gd` añade `district_pair: Vector2i`
a las aristas de conexión y conserva el dato en `_split_crossings`. Las
coordenadas, lotes, RNG y `generator_version = 1` siguen iguales.

`town_navigation.gd` añade `accessible_edges(plan, districts)` y `route`
usa el mismo filtro. Con una lista explícita, un conector exige sus dos
extremos abiertos; sin lista mantiene el acceso a todo el grafo. Un conector
sin metadatos se excluye con lista explícita. La firma de `route` no cambia.
El constructor y el GPS comparten el filtro, para construir lo que navegan.

Tests portables: división de conectores en cruces, exclusión de zonas
cerradas, 100 rutas depósito–Centro y los 300 recorridos iniciales.
Actualizar la rama antes de reutilizar el módulo. Sin RPC ni cambios de protocolo.
