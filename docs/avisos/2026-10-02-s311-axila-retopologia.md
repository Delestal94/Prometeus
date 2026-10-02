# S-311: transición de axila y simplificación LOD2

Se reconstruyen loops cruzados de quads en LOD1 sobre la superficie curva de
LOD0 y se sustituyen los cortes espaciales de pesos por pesos de superficie,
normalizados a cuatro influencias. Se conservan las botas plantadas. LOD2 protege
la transición cadera-muslo para no plegarla al combinar morphs.

Cambian `art/gel_character/build_gel_body.py`, sus pruebas, la fuente gel derivada,
los tres GLB aislados y sus reportes. No cambia el master redondeado, el jugador
activo, los veinte reposos/inverse binds, los nueve clips, los once morphs ni
sus rangos/defaults. No cambia ninguna firma pública del juego ni la red.

Verificados A0/A30/A60/A75, 53 muestras de morph por LOD, importación y cuatro
tests Godot; 144 comparaciones de silueta quedan por debajo del 5 %. No se
certifica A90, todas las animaciones ni el continuo de morphs y poses. Los ítems
10/12/13 y la aprobación visual/material E siguen pendientes en su alcance total.

Hacer pull antes de seguir. No regenerar gel desde un builder anterior: las
regresiones nuevas conservan los loops de axila y de transición cadera-muslo.
