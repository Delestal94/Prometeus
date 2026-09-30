# Aviso: si el anfitrión se va con los resultados abiertos, los resultados quedan (N-222, 2026-09-30)

Toca tres archivos de Slatex (`hud_pause.gd`, `hud_results.gd`, `hud_prompts.gd`). Sin cambios de firmas, sin RPCs
nuevos ni cambios de replicación: el protocolo es el mismo (`PROTOCOL_VERSION` sigue en 4).

- **`scripts/ui/hud/hud_pause.gd`** (`_on_connection_lost`): si la pantalla de resultados está abierta cuando se cae la
  sesión, ya no la cambia por la de desconexión: llama a `HudResults.show_host_gone()` y sale. Mid-run o en el depósito
  sigue abriendo la pantalla de desconexión con lo jugado, como antes.
- **`scripts/ui/hud/hud_results.gd`**:
  - `show_host_gone()` (nueva, pública): deja título, puntaje, filas y premios como estaban (redibujarlos ahora nombraría
    mal a los jugadores: sin sesión este peer es el id 1), cambia la nota del invitado (`HUD_RESULT_GUEST_NOTE`) por
    `HUD_RESULT_HOST_GONE_NOTE` ("El anfitrión se fue y la sala se cerró...") y muestra "Volver a intentar"
    deshabilitado con el motivo en el tooltip (`HUD_RETRY_NEEDS_HOST`). "Volver al menú" queda visible, habilitado y
    con el foco. Llamarla dos veces no repite la nota.
  - `set_buttons()`: ahora siempre vuelve a habilitar el botón principal y borra su tooltip, para que ninguna otra
    pantalla herede el botón gris.
- **`scripts/ui/hud/hud_prompts.gd`**: `session_lost` (var nueva, la pone `HudPause`) y `can_restart()` da `false` si
  la sesión se cayó. Sin sesión el cliente pasa a ser "anfitrión offline" y `can_restart()` daba `true`: R o el botón
  habrían recargado el nivel como partida solo, en otro mundo.
- Claves nuevas en `translations/strings_ui.csv`: `HUD_RESULT_HOST_GONE_NOTE`, `HUD_RETRY_NEEDS_HOST`.
- Tests: `test_host_gone_tally.gd` (sección nueva: resultados abiertos + el anfitrión se va) y `test_hud_flow.gd` (la
  caída con resultados ahora los conserva; la pantalla de desconexión se prueba desde una partida en curso).

Qué tiene que hacer Slatex: nada más que `git pull` antes de tocar esos tres archivos. Si agregás otra pantalla que use
`set_buttons()`, el botón principal ya arranca habilitado.
