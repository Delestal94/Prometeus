# 2026-10-21 · El modo Empresa en línea (D-0214): `LEVEL_SCENES`, `PROTOCOL_VERSION` 38 y flags del menú

Para Slatex. La continuación de D-0214 pone el modo Empresa en una sala: el host la abre con
`--host-company` y los que entran van al mundo de la empresa, con su jugador.

## Zona compartida: `do-not-drop/scripts/core/network_manager.gd`

- `LEVEL_SCENES` suma `res://scenes/gameplay/company_root.tscn` al final (partido en varias líneas; la
  entrada de `max-line-length` del archivo salió de `tools/lint-baseline.txt`). `DEFAULT_LEVEL_SCENE`
  sigue siendo `level_base.tscn`.
- `PROTOCOL_VERSION` 37 → 38 (línea "38" en el historial): la escena de empresa es un nivel de sesión y su
  `World/PlayerSpawner` replica la tripulación. **El protocolo cambia:** una build de 37 no se conecta
  con una de 38 (error de versión, claro); antes, un cliente viejo habría rechazado la escena con un
  error de conexión. Ninguna firma ni RPC de `NetworkManager`/`NetSession` cambia; `net_session/` no se
  tocó. Próximo número libre: 39.

## Dominio de Slatex: `do-not-drop/scripts/ui/main_menu.gd`

- `_handle_cmdline_args()` pasa a `_handle_cmdline_args(args: PackedStringArray = OS.get_cmdline_user_args())`:
  parámetro con valor por defecto, la llamada de `_ready()` no cambia; un test le pasa sus flags.
- Flags: `--autostart-company` (el oficial, decisión `docs/decisiones/2026-10-04-flag-modo-empresa.md`;
  `--mode=company` sigue como alias), `--host-company` (sala de Empresa por ENet, como `--host-lan`) y
  `--slot=<n>` con cualquiera de los dos. El slot queda en la variable nueva `_launch_slot` del menú y
  pasa a `CompanyRoot.launch_slot` (estática, la toma el próximo mundo de empresa) recién en
  `_go_to_level()`, cuando el loader va a la escena de empresa; si el arranque falla (puerto ocupado) o se
  cancela, `_drop_launch_slot()` (nueva) lo borra de los dos lados: se llama desde `_cancel_loading()`,
  `_on_level_load_failed()`, `_cancel_connection()` y la falla de `_host_session()`. Función estática
  nueva `_slot_arg(args)`.
- `_host_tag()` ahora es un `match`: la cinta de la pantalla de carga dice "Crear sala Empresa" en una sala
  de empresa. Clave nueva en `translations/strings_ui.csv`: `UI_MENU_HOST_COMPANY` ("Crear sala Empresa" /
  "Host a Company room").
- **Sin botón todavía:** un botón chico más en la página Jugar (debajo de "Crear sala Endless") la lleva de
  581 a 635 px de alto y, con el tope de 110 px, "Volver" queda en el borde de una pantalla de 720 (ya hoy
  la tarjeta termina a 691, dentro del margen de 40). **Qué hacer:** cuando reacomodes esa página (por
  ejemplo, las dos salas en una fila, o la página de jugar en grupo aparte), sumá "Crear sala Empresa" con
  `_host_session(NetworkManager.Transport.AUTO, COMPANY_SCENE)` y `tr("UI_MENU_HOST_COMPANY")`: es lo único
  que falta para abrir una sala de Empresa por Steam desde el menú.

## Para conocer (no es de tu dominio)

- `scripts/gameplay/company_root.gd`: crea `World/PlayerSpawner` (el mismo camino que Entrega/Endless,
  así `LoadingScreen._scene_ready()` espera al jugador propio del cliente) y el host spawnea un
  `player.tscn` por peer con su mundo listo, pasando por `CompanyRoot.join_crew()` en todos los peers.
  `player` puede ser `null` en un cliente hasta que llega su spawn, y vuelve a `null` (con
  `ShedBuilder.player`) cuando su nodo sale del árbol. Llama a `level_ready()`. El que entra aparece en
  el primer lugar libre alrededor de `SPAWN` (`free_spawn()`), no por su número en la lista.
- `scripts/gameplay/shed_builder.gd` (libre): `enter()` mira `is_instance_valid(player)`, como ya hacía
  `exit()`.
- CI: `.github/workflows/tests.yml`, job `network-pair`, suma el paso `bash tools/run-net-pair.sh --company`.
- `player.tscn` y `player_spawner.gd` no cambiaron: el mundo de empresa tiene su propia función de spawn.
- Tests: `test_company_online` (par ENet en un proceso con dos `NetworkManager`), `test_company_world_boot`,
  `test_menu_session_paths` ampliado; `tools/run-net-pair.sh --company` corre el par en dos procesos con
  los flags reales del menú.
