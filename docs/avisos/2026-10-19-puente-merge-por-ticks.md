# 2026-10-19 · El merge del puente se reparte en ticks (N-979)

Toca `modules/render_budget/dressing_batcher.gd` (`merge_segment_geometry` aborta si el tramo se libera
mientras espera un cuadro y cede antes del `commit`) y `modules/route_gen/segment_streamer.gd`
(`_batch_next(slice_msec)` con `FrameSlicer`, un merge a la vez). Sin cambios de red ni de golden.
