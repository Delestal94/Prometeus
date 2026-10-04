# N-950 · Candidatos espaciales de plataformas

Zona compartida: `do-not-drop/modules/route_gen/terrain_field.gd`.
Nuevo hook virtual `_platform_candidates(p: Vector2) -> Array[Dictionary]`.
Por defecto retorna `platforms` completas: las rutas actuales conservan
el resultado y sus firmas. Un adaptador puede usar un índice preparado antes
del build, de solo lectura, que incluya toda plataforma cuyo `PLATFORM_BLEND`
alcance el punto y conserve el orden original (las mezclas son secuenciales).

`test_terrain_platforms.gd` compara miles de muestras con huellas rotadas,
plataformas superpuestas a diferentes alturas y bandas de mezcla.
El juego lo usa en TownTerrain para no recorrer cada plataforma de toda
la ciudad por vértice. Actualizar la rama antes de trabajar en TerrainField.
