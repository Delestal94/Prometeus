# La pantalla de carga ya no se congela; menú y HUD (N-408)

**Fecha:** 2026-10-01 · **De:** Nacho (con Claude) · **Para:** Slatex

## Qué cambió

La ruta se arma por cuadros (ver `2026-10-01-n408-ruta-por-cuadros.md`) y la pantalla de carga espera a que el
juego esté listo de verdad. En tus archivos:

`scripts/ui/loading_screen.gd`:
- `go()` precarga en hilos los `.glb` de `assets/models` (`model_paths()`, salvo headless) y oculta
  `World/Depot` y `World/Route` hasta que el nivel está armado (`REVEALS`, se muestran de a uno por cuadro).
- `_start_warm()` / `_warm_done()`: los 34 sonidos sintetizados del nivel (`LEVEL_SOUNDS`) se arman en un hilo.
- `_scene_ready()`: con sesión, la tapa espera a que exista el jugador propio.
- Etapa nueva "Últimos retoques…" (`UI_LOADING_STAGE_SETTLE`).

`scripts/ui/main_menu.gd`:
- `_go_to_level()` lleva `MenuMusic` bajo la pantalla de carga (`carry_audio`), que la funde bajo el nivel.
- **Cambió la firma** de `_cancel_loading() -> bool` (false: ya era tarde, la pantalla vuelve al menú con
  `redirect_to`) y de `_host_session(transport, scene = LEVEL_SCENE)`.
- Botón nuevo "Crear sala Endless" (`_host_endless_session`, `UI_MENU_HOST_ENDLESS`).
- `_show_failure()`: si la sesión ya mostró su motivo, el genérico "error %d" no lo pisa.
- `join_steam_lobby()`: con el nivel ya armándose, la invitación queda pendiente (`NetworkManager.defer_lobby`).

`scripts/ui/hud/hud.gd` `_on_started()`: si la tarjeta de inicio estaba abierta (el que entra tarde), al
sacarla captura el mouse.

`scripts/presentation/ingame_music.gd`: la primera frase entra a los 1,5-3 s (antes 18-35 s).

Zona compartida: `modules/scene_loader/` (precarga, `BUSY_GROUP`, `_scene_ready`, `reveal_paths`, cuadros fluidos,
`carry_audio`, `redirect_to`), `modules/synth_audio/synth_audio.gd` (`warm()`, `warm_done()`, `is_cached()`),
`modules/net_session/net_session.gd` (`is_online()` es falso con un peer ya cerrado: el fin de sesión del cliente
tiraba errores de `is_server()`), `scripts/core/network_manager.gd` (`defer_lobby()`, y `_reload_level()` por la
pantalla de carga). El reinicio de la entrega lleva la música del juego bajo la pantalla de carga.

## Qué tiene que hacer Slatex

Nada. Si un sonido sintetizado nuevo se pide en el `_ready()` de un nivel, sumalo a `LEVEL_SOUNDS`.
