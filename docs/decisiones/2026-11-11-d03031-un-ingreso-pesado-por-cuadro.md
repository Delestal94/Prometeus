# Un ingreso pesado por cuadro al cargar celdas, y cómo se mide (D-0303.1) — 2026-11-11

Decidió: Claude, por delegación del usuario (2026-10-04, decisiones delegadas). No se abrió issue `decide-usuario`.

## Contexto
El corte vertical exige que ningún cuadro pase de 50 ms al manejar del galpón a la última casa de Centro por la
carga de celdas (`docs/expansion-distritos/diseno/corte-vertical.md` §4). `test_company_cells` lo medía con celdas
vacías (riesgo R-09). Medido sobre las celdas reales (calles, `CentroDecor` y las 30 casas), un cuadro del viaje
llegaba a 40-47 ms en una PC ocupada: el streamer metía una celda (5-12 ms) y, en el mismo cuadro, cada celda
vecina soltaba una casa (12-18 ms cada una), porque `HOUSES_PER_FRAME = 1` valía por celda. Pasaba el límite por
poco y con un runner más lento no pasaba.

## Alternativas
- **Dejarlo y subir el límite del test para CI** (como `HOUSE_BUDGET_MSEC`, 100 ms): el test dejaría de decir lo
  que dice el criterio.
- **Repartir los cuadros entre todas las celdas**: una casa por cuadro para todo el mapa.
- **Lo anterior y, además, ninguna casa en el cuadro en que entra una celda con contenido.**
- Abaratar la casa (guardar por modelo la malla unida): más margen todavía, pero es de `delivery_house.gd`, que
  también usa la entrega; queda anotado en `revisar/D-0303.1.md`.

## Decisión
1. **Un cuadro toma una sola cosa pesada**: las celdas que el streamer arma en su rebanada, o una casa. Las casas
   de todas las celdas comparten los cuadros (`CentroDecor.take_frame()`, primero la que está antes en el árbol) y
   el cuadro en que entra una celda con contenido queda tomado (`CentroDecor.hold_houses()`, que llama
   `CompanyCells` desde `cell_loaded`). Una celda vacía no toma nada.
2. **El test mide trabajo de celdas, no el cuadro entero**: por paso de 60 fps, lo que tarda
   `CompanyCells.step()` más lo que tarda en estar lista cada casa que entra en el cuadro real que sigue. El
   reloj del cuadro entero no sirve: en una PC ocupada un cuadro vacío tarda 50-100 ms cada tanto.
3. **El límite es el del criterio, 50 ms**, sin margen extra para CI. Lo medido (15-19 ms) deja más de dos veces y media.
4. **Un cuadro pasado del límite se repite**: hasta 3 viajes, cada uno con celdas nuevas, y solo falla lo que
   aparece en un cuadro pasado en los 3. Lo que sí es determinista (más de una casa por cuadro, casa junto con
   celda) falla al primer viaje.
5. **Los cuadros del arranque** (el mundo acomodándose en el galpón antes de salir) se imprimen y no tienen límite
   en este test.

## Por qué
- El criterio es del juego: si el límite se pasa, se arregla el juego y no el número (nota del análisis de la
  tarea). Repartir los cuadros baja el peor cuadro del viaje de 40-47 ms a 15-19 ms sin tocar las piezas de calle
  (D-2012.2, otro carril) ni la casa.
- El costo es que las casas tardan más en estar todas: al abrir el mundo, unos 30 cuadros después de las celdas.
  Entran a 512 m o más de quien maneja, así que no se ve.
- Un test de tiempo que da rojo cada tanto frena a todos los PRs (los checks son la única compuerta); repetir el
  viaje descarta el ruido sin aflojar el límite. Lo que se pierde, un costo que solo se paga la primera vez que
  se usa algo, queda a la vista en la línea `PASS` (imprime el peor cuadro del primer viaje).
- El arranque es de D-0313 y su peor cuadro (90 ms la primera vez, 30 ms después) es una celda de piezas de calle
  del Camino del Campo: el arreglo es de D-2012.2 y del precalentado de la carga inicial (R-09), no de esta tarea.

## Qué cambia
- `scripts/gameplay/districts/centro_decor.gd`: `take_frame()`, `hold_houses()`; `HouseDrip._process` pide el
  cuadro antes de soltar una casa. `HOUSES_PER_FRAME` pasa a ser por cuadro para todo el mapa.
- `scripts/gameplay/districts/company_cells.gd`: `use_graph()` conecta `cell_loaded` a `_on_cell_in`.
- `tests/test_company_cells.gd` (el viaje sobre celdas reales), `tests/test_company_root_graph.gd` (lo mismo en el
  mundo real con su propio `_process`), `tests/test_company_centro.gd` (apaga su streamer y comprueba que mientras
  una celda suelta sus casas ninguna otra suelta una).
- Detalle de D-0303, fila de `03-mapa-y-distritos.md`, `corte-vertical.md` §4 y R-09 de `riesgos.md`.
