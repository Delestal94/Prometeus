# D-1935: feed de eventos del galpón

- **Qué cambió:**
  - `scripts/gameplay/company_root.gd` (Nacho): `_ready()` llama a `ShedEventFeed.add_to(self)` después del
    tutorial. Para no sumar líneas (N-985) se reacomodó el primer párrafo del comentario de arriba (mismo texto).
  - `ShedEventFeed` (`scripts/ui/`) escucha `net.event_applied` en cada par y no manda nada por red.
- **Qué tiene que hacer Nacho:** nada obligatorio. El feed dice "quién" cuando el evento trae `peer` (como
  `supplier_ordered`) o unidades que salen de `hands:<peer>` (`box_placed`). `box_labeled` y `box_sealed` no traen
  a nadie, así que hoy salen sin nombre ("Caja cerrada para el pedido d1_o04"). Si alguna vez esos eventos suman
  `peer` (con su `PROTOCOL_VERSION`), el feed lo toma solo, sin cambios. Un evento nuevo que convenga contar se
  suma en `ShedEventFeed.line_for()` y `text_of()`.
