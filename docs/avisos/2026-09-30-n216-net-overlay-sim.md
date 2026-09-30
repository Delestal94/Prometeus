# Aviso: N-216, panel de red (F3) y `--net-sim` (2026-09-30)

Lo hizo Nacho (rutina de construcción, con Claude), rama `nacho/N-216-net-overlay-sim`. Toca la zona compartida
(`network_manager.gd`, `project.godot`, `README.md`), **solo agregando**. **No cambia el protocolo**: no hay RPC
ni propiedades replicadas nuevas, así que `PROTOCOL_VERSION` sigue en 4 y un cliente viejo con un host nuevo se
entienden igual. El panel y la simulación son locales de cada proceso.

## Qué cambió

- `network_manager.gd` (agregados, ninguna firma cambia):
  - `var net_sim: Dictionary`: el perfil de `--net-sim=lag,jitter,pérdida` (ms, ms, %), `{}` si no hay. Lo lee
    `_ready()` antes de salir en headless (`_read_net_sim`); si no se entiende, `push_warning` y no simula nada.
  - `_apply_steam_net_sim()`: al final de `_init_steam()`, cuando Steam queda listo, pasa el perfil a la config
    global de Steam (`FAKE_PACKET_LAG/LOSS/JITTER_*`, las dos direcciones). Sin Steam no hace nada.
  - `pose_net_sim() -> Dictionary`: el perfil que el juego simula por su cuenta (en LAN, el búfer del camión);
    vacío si el transporte activo es Steam, para no simular dos veces.
  - `_ready()` cuelga de `NetworkManager` un hijo `NetStatsOverlay` (`CanvasLayer`, capa 120, oculto y sin
    procesar hasta que se abre). Si algún código recorre los hijos del autoload o los `CanvasLayer` visibles,
    este está oculto por defecto (`test_trailer_shots` sigue en verde).
- `project.godot`: acción nueva `toggle_net_stats` en **F3** (tecla física). No es reasignable (no está en
  `GameSettings.REBINDABLE_ACTIONS`), como F10/F11. Anotada en `docs/convenciones-godot.md` §1.
- `README.md`: sección "Medir la red y simular mala conexión" con F3, `--net-stats`, `--net-sim` y el perfil
  estándar (150 ms, ±20 ms, 2 %).
- Nuevos (libres): `scripts/core/net_stats.gd` (`NetStats`, lectura de Steam/ENet y parseo del perfil) y
  `scripts/presentation/net_stats_overlay.gd` (`NetStatsOverlay`). Claves `HUD_NET_STATS_*` en
  `strings_ui.csv`, después de `UI_NET_HOST_LOST`.
- Mío: `vehicle_net_smoother.gd` suma `configure_sim()`, `fake_jitter` y `fake_loss`; `--fake-lag` sigue igual.

## Qué tiene que hacer Slatex

Nada. `git pull` antes de tocar `project.godot` (acción nueva al final de `[input]`). Si agregás una acción en
F3, elegí otra tecla.
