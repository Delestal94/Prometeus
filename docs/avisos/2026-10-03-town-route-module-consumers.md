# N-950: nuevos consumidores de los módulos de carretera

`docs/modulos.md` registra los adaptadores de ciudad como consumidores de
TerrainField, StraightSegment/RouteSegment y DressingBatcher. Reutilizan
las API existentes; no cambia ningún archivo de modules, firma pública ni
configuración global. Detalles del montaje y sus límites en mapa-pueblo.md.
Actualizar esta documentación antes de ampliar el catálogo de consumidores.
