# Calles horneadas por celda y rango de las piezas chicas de las casas (D-2012.2) — 2026-11-11

Decidió: Claude, por delegación del usuario (2026-10-04, decisiones delegadas). No se abrió issue `decide-usuario`.

## Contexto
El presupuesto de D-2012 (`docs/rendimiento-pc.md`) pide, en la vista por defecto del galpón, ≤ 6.000 nodos y
≤ 900 draw calls de pico. Medido sobre `origin/main` con ventana: 15.363 nodos y 2.598 draw calls. Casi todo eran las
piezas de calle de las celdas (`RouteSegment` armadas por código: una recta son 37 nodos y 17 mallas, un puente
angosto 690 partes). Cerrarlo es condición del corte vertical (F1).

## Alternativas
- **Subir los límites a lo medido** (ya descartado en `revisar/D-2012.md`).
- **Hornear las celdas en archivos** (escenas por celda exportadas): ahorra también armar las piezas, pero ata el
  mapa a un paso de exportación y cambia lo que leen el autopiloto y los tests.
- **Fundir en el juego, por celda, después de armarla:** las mismas piezas, una pasada más.
- **Recortar decorado de Centro** (`corte-vertical.md` §7) si las calles no alcanzaban.

## Decisión
1. **Fundir en el juego, por celda.** `StreetBatcher` corre como segunda pasada del streamer
   (`WorldCellStreamer.finish_for`, nuevo en `modules/world_cells`) desde el paso siguiente al que armó la celda, unas
   ramas por paso dentro de la rebanada de 4 ms, y la celda no se dibuja hasta terminar. Calzadas y banquinas van a
   una malla `Streets` (el shader de la calle lee de cada vértice el x propio y el rumbo de su caja, así se ven
   igual); lo demás estático a `StaticMerger` (`modules/render_budget`); la colisión de las banquinas a un solo
   cuerpo. Quedan las piezas, su `Road`, los `GripArea` y lo que se mueve.
2. **Las calles solas dejaron el pico en 1.162.** Lo que faltaba eran las casas de Centro, a 300-800 m: ~650 draw
   calls, casi todo piezas de centímetros. En lugar de sacar decorado, esas piezas tienen **rango de dibujo por
   preset** (`WorldQuality.set_view_range`): 40 m el portero eléctrico, 120 m el buzón, el texto del cartel y la
   lamparita, 250 m las patas del cartel y el hilo y el nudo del globo. A esas distancias miden menos de medio píxel
   a 6 píxeles en 1080p. El globo, el brillo de la lamparita y los tableros del cartel, que son lo que se ve de lejos
   (N-501), no tienen rango.
3. **Precalentado en la carga:** `CompanyCells.warm_pieces()` arma, hornea y libera una pieza de cada tipo mientras se
   abre el mundo (~240 ms), para que la primera celda del Campo no pague 90-130 ms en un cuadro con el mundo a la
   vista (R-09).

## Por qué
Fundir en el juego no cambia cómo se generan las calles ni lo que se lee de ellas, y bajó los nodos a 5.177 y el
pico a 746 sin cambio visible en las capturas (menos del 0,3 % de píxeles, todo HUD y un cartel lejano). El rango de
las piezas chicas no saca nada que se distinga y deja 154 draw calls de margen; recortar decorado sí se habría visto.

## Qué queda abierto
- La compuerta de CI (D-2012.3) y la medición con la PC libre (D-2012.4): los FPS de esta medición no valen.
- Armar las piezas sigue siendo lo caro de una celda (R-09): se arma entera en un paso.
- Si un rango de las casas se nota al acercarse, se sube en `DeliveryHouse.DOORBELL_VIEW_RANGE` o
  `HouseWaitingMarker.CLOSE_VIEW_RANGE`/`THIN_VIEW_RANGE`.
