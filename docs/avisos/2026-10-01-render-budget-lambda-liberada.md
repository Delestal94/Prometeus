# `WorldQuality.watch()` ya no loguea "Lambda capture was freed"

**Fecha:** 2026-10-01 · **De:** Nacho · **Para:** Slatex

## Qué cambió

`modules/render_budget/world_quality.gd`, `watch()`: el aplicado diferido de la calidad a un nodo nuevo captura
el id del nodo (`instance_from_id`) en vez del nodo. Si el nodo se liberaba en el mismo frame en que se agregó
(una ruta que se arma y se tira, por ejemplo un `RouteStreamer` con lluvia), el motor imprimía
`Lambda capture at index 0 was freed` antes de que el chequeo del lambda pudiera correr. Salía de vez en cuando
en `test_mud_segment` (solo cuando el clima al azar daba lluvia). No cambia qué se aplica ni cuándo.

`modules/render_budget/tests/test_render_budget.gd` suma el caso: agrega un `GPUParticles3D`, lo libera en el
mismo frame y exige que no se loguee ningún error (falla con el código anterior).

## Qué tiene que hacer Slatex

Nada.
