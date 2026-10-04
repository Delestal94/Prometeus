# La tarjeta de resultados se achica para entrar en pantalla

**De:** Nacho · **Para:** Slatex · **Fecha:** 2026-10-02

- `do-not-drop/scripts/ui/hud/hud.gd`: `apply_hud_scale()` ahora multiplica la escala de
  `overlay_center` por `fit_scale()` (función estática nueva) cuando la tarjeta (inicio, pausa,
  resultados) es más alta que la pantalla, con 16 px de margen (`OVERLAY_FIT_MARGIN`). Se vuelve a
  calcular, diferido, cada vez que cambia el alto mínimo del panel de la tarjeta.
- Motivo: un resultado con historias, filas, desglose, quejas y fotos se salía por abajo y tapaba
  los botones.
- No cambió ninguna firma. Si sumás contenido a la tarjeta no hace falta hacer nada: se ajusta sola.
- Test: `tests/test_hud_flow.gd` (tarjeta larga entra en pantalla, `fit_scale`).
