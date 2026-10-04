# N-950 — navegación portable por calles

Nacho agrega `modules/town_gen/town_navigation.gd`: API estática
`route(plan, start: Vector2, destination: Vector2, districts: PackedInt32Array)`.
Devuelve `{points: PackedVector2Array, distance: float}` o `{}` si no hay
camino. El filtro vacío permite todas las calles; un filtro explícito usa
solo los IDs indicados, sin cambiar el plano ni su versión de generación.

Sin autoloads ni recursos del juego. Test portable cubre tramos parciales,
desvíos, distritos cerrados y 300 rutas de clientes. Hacer pull antes de
extender el módulo. No se cambian RPC, protocolo ni firmas existentes.
