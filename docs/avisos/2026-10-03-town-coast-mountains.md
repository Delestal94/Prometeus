# N-950 · Puerto y Sierra sobre el terreno original

`town_biomes.gd` configura una bahía orientada según el plano y fuera de todos
los lotes, calles y verdes; genera agua recortada contra el lecho, muelle con
colisión y acceso que reutiliza el grafo de visibilidad peatonal. No modifica
el plano, sus direcciones ni el GPS. `town_dresser` reserva el camino al muelle
y usa la consulta de profundidad original para descartar lugares sumergidos.

`TownTerrain` agrega `coast`, `mountain_outline` y cobertura de teselas para
el litoral sin calles ficticias. Sierra deja de aplanar su interior completo;
conserva el relieve original y las plataformas a altura cero de calles,
parcelas y accesos. `route_terrain.gdshader` agrega `snow_enabled` (false por
defecto) y `snow_outline[7]`: las rutas originales conservan su aspecto.
La nieve se limita a terreno alto dentro del polígono de Sierra. El agua
local usa `town_water.gdshader` con ondas suaves de color.

Escenas anteriores con distritos [0] y [0,1] sin cambios. Import y cinco filtros
headless pasan, incluyendo 20 semillas de biomas y muelle físico en la ciudad.
Actualizar esta rama antes de continuar el spike. Campaña, guardado, pasos de
ribera y carreteras elevadas de montaña continúan pendientes.
