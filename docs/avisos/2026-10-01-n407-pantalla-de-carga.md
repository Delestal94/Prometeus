# Pantalla de carga entre el menú y el nivel (N-407)

**Fecha:** 2026-10-01 · **De:** Nacho (con Claude) · **Para:** Slatex

## Qué cambió

Al tocar "¡JUGAR!" el menú se quedaba congelado en su último frame mientras el nivel cargaba y se armaba. Ahora
pasa por una pantalla de carga.

`scripts/ui/main_menu.gd` (tu dominio):
- `_go_to_level(scene_path, mode = "")`: **cambió la firma** (segundo parámetro opcional, el texto de la cinta). Ya
  no llama a `change_scene_to_file`: arma un `LoadingScreen` con `LoadingScreen.go()` y lo guarda en `_loading`.
  Pone `_busy = true` también al jugar solo / endless, y un segundo toque no arma otra carga.
- `_cancel_loading()` (nuevo): lo llaman `_on_session_failed()` y `join_steam_lobby()`; si la carga todavía no
  empezó a armar el nivel, se cancela y el menú queda con el error.
- `_on_level_load_failed()` (nuevo): si la escena no carga, deja la sesión y muestra `UI_LOADING_FAILED`.

`scripts/ui/loading_screen.gd` (nuevo, tu carpeta): `LoadingScreen extends SceneLoader`. Solo el look: arte y logo
del menú en el mismo lugar, tarjeta con la cinta del modo, caja que salta, etapa, barra (`UiTheme.bar`) y un
consejo (`TIPS`). El mecanismo (hilo, cambio de escena, frames de asentamiento, fundido, input) es el módulo
`modules/scene_loader/` (zona compartida, catálogo en `docs/modulos.md`).

Fondo nuevo `assets/ui/backgrounds/tx_ui_loading_background_1920.png` (ComfyUI, fila en `art/ai-registro.md`).

`translations/strings_ui.csv`: claves nuevas `UI_LOADING_*` (etapas, cinta, consejos, error).

Tests nuevos: `tests/test_loading_screen.gd`, `modules/scene_loader/tests/test_scene_loader.gd`. Captura:
`tests/render_loading_screen.gd`.

## Qué tiene que hacer Slatex

Nada. Si querés otro arte de fondo, otra cinta o más consejos, todo está en `loading_screen.gd` (constantes
`ART`, `TIPS`, `STAGE_TEXT`); un consejo nuevo es una clave `UI_LOADING_TIP_*` en el CSV y su entrada en `TIPS`.
