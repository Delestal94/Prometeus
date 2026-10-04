# N-950: planificación portable de aceras y accesos

Nuevo `modules/town_gen/town_walkways.gd`: `generate(plan, districts)` devuelve
`surfaces` (polígonos Vector3 con altura), `lot_paths` (dirección, puntos y
ancho) y `green_paths` (distrito, tipo, centro, puntos y ancho). Reutiliza el
filtro de calles abiertas de `town_navigation`, recorta aceras y rampas fuera
del asfalto y rodea lotes con un grafo de visibilidad para entradas verdes.
Una selección vacía construye nada. No usa RNG, autoloads ni clases del juego.

No cambia firmas existentes, semilla, generator_version ni posición de lotes,
calles o zonas verdes. El test propio cubre cinco semillas y un lote rotado
interpuesto; también se valida en un proyecto vacío. `docs/modulos.md`
registra la API nueva. Actualizar la rama antes de modificar town_gen.
