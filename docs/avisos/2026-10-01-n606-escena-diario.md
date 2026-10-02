# El diario del día siguiente ahora es una escena 3D (N-606.3)

**Fecha:** 2026-10-01 · **De:** Nacho (con Claude) · **Para:** Slatex

## Qué cambió

- `scripts/ui/hud/hud_newspaper.gd` (tu dominio): `present(then)` ya no abre la página 2D (`NewspaperPage`, borrada)
  sino `NewspaperDirector` (`scripts/presentation/newspaper/`), la escena del Jefe leyendo el diario (~30 s, se
  salta manteniendo Interactuar/Saltar/Atrás 0,6 s). Señal nueva `newspaper_finished` (al terminar o saltarla);
  `page` pasó a llamarse `director`. `is_open()`, `dismiss()` y `present()` mantienen la firma; `HudResults` no se
  tocó y sigue pasando su callable. Mientras dura la escena, la ventana tiene `disable_3d = true` (el mundo de la
  partida no se dibuja detrás) y se restaura al terminar.
- `scripts/core/game_settings.gd` (tu dominio): `enum NewspaperMode { ALWAYS, NEWS_ONLY, NEVER }` y
  `newspaper_mode` (guardado en `SAVED_KEYS`). `HudNewspaper.wanted()` lo lee.
- `scripts/ui/options_panel.gd` (tu dominio): fila «Diario al final» (`_newspaper_option`, `UI_OPT_NEWSPAPER*`)
  después de los subtítulos de sonido; se resincroniza con el resto.
- `translations/strings_ui.csv`: claves nuevas `HUD_NEWS_*` (rótulo, aviso de saltar, folio, avisos y relleno del
  diario) y `UI_OPT_NEWSPAPER*`; se borró `HUD_NEWS_CONTINUE` (era el botón de la página 2D).
- `tests/test_ui_translations.gd`: `SCAN_DATA` también lee `data/newspaper/shots.json` (pide el rótulo).
- Zona compartida: módulo nuevo `modules/camera_rail/` (`CameraRail`, con su test) y su fila en `docs/modulos.md`.
- `tests/test_newspaper_page.gd` y `tests/render_newspaper.gd` se reemplazaron por `test_newspaper_scene.gd` y
  `render_newspaper_scene.gd`.

## Qué tiene que hacer Slatex

Nada. Si tocás el flujo de resultados, esperá `newspaper_finished` (o el callable de `present()`) antes de mostrar
la tarjeta. Si agregás un modo de overlay que pueda abrirse encima de la escena, cerrala antes con
`hud.newspaper.dismiss()`, como hace `HudPause._on_connection_lost()`.
