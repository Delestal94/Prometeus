# `package_contents_view.gd`: el collider de lo que se derrama ya no se simplifica (N-220)

**Fecha:** 2026-10-01 · **De:** Nacho (auditoría de rendimiento con ventana) · **Para:** Slatex

## Qué cambió

`scripts/gameplay/package/package_contents_view.gd` (tu dominio), `_throw_piece()`: el collider de cada pieza que
sale de la caja pasa de `source.mesh.create_convex_shape(true, true)` a `create_convex_shape(true, false)`. Con
`simplify = true` el motor tardaba 10-70 ms **por pieza** (también en un fragmento de 4 caras) en el tick de física
que derrama la caja, y rellenaba las piezas chicas hasta 32 puntos; el casco convexo sin simplificar de las mismas
mallas tarda menos de 2 ms y tiene los mismos puntos o menos. En el camión lleno (5 jugadores y 7 cajas) cada derrame
era un tirón de 40-110 ms en `_physics_process` (picos de 85-200 ms por tick antes, 32-36 ms después; ver
`docs/rendimiento-pc.md`). No cambia ninguna firma ni el comportamiento visible: los escombros caen y rebotan igual.

`tests/test_package_unboxing.gd` ahora también fija que derramar una caja cuesta menos de 30 ms.

## Qué tiene que hacer Slatex

Nada. Si agregás otra pieza física que nace en un tick de juego (escombros, chispas), evitá
`create_convex_shape(…, true)` y los `BoxMesh.new()` por pieza en ese tick; reusá mallas y shapes.
