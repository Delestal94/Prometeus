# Aviso: nombres de trampa por la red como claves, y los últimos textos sin tr() (2026-09-30)

Lo hizo Nacho (rutina de construcción, con Claude). Cierra lo que le quedaba a N-805. Toca archivos
tuyos y la zona compartida, pero no tenés que hacer nada: `git pull` antes de seguir con HUD o paquetes.

**Por qué:** el host armaba los nombres de trampa ya traducidos y los mandaba así. Un cliente en inglés
veía las tarjetas de carga, los resultados, los carteles de las casas y el "no es mío" de la puerta en
el idioma del host.

**Qué cambió (firmas y datos):**
- `TrapDefinition.name_key()` es nuevo y devuelve la clave (`HUD_TRAP_FRAGILE`, etc.).
  `localized_name()` ahora es `tr(name_key())`.
- `EventBus.cargo_registered(package_id, name_key)`: el segundo argumento pasa a ser la **clave**, no el
  nombre (antes `display_name`). La manda `package.gd report_to_run()` y `hud_cargo_panel` la pasa por
  `tr()`. `RunManager.cargo_names` guarda claves y los joins tardíos las reciben igual.
- Las filas de resultados (`results["deliveries"][i]["trap"]`) son claves, y
  `HUD_RESULT_PACKAGE_FALLBACK` también. `hud_results` hace el `tr()`.
- `UiTheme.trap_icon()` acepta una clave además del nombre, en cualquiera de los dos idiomas.
- `Depot.assignments()` / `houses_assigned`: pasan a `[package_id, trap_key, code]` (antes
  `[package_id, "Frágil A-3"]`). `Route.assign_packages()` traduce en cada par y sigue aceptando la
  forma vieja. Las órdenes del depósito suman `"trap_key"`, y `"trap"`/`"content"` salen de
  `localized_name()`.
- `house_refused_package`: `hud.gd` (`_house_order_label`) y `delivery_house` usan el cartel de la casa
  local en vez del texto del host.
- `RunManager.session_names()` es nueva: lo que recibe un join tardío sale de `cargo_names` (claves, también
  las de cajas ya entregadas). `NetworkManager.PROTOCOL_VERSION` pasa a 3, porque una build vieja mostraría
  las claves sin traducir.
- `player_cargo_care.gd`: la tarjeta usa `localized_name()` y no `display_name`.
- `progress_panel.gd`: las recompensas nombran la trampa con su clave.
- Claves nuevas en `strings_ui.csv`: `HUD_KICKER_MULTIPLAYER` (`hud_pause`, pantalla de desconexión),
  `HUD_KICKER_PAUSE`, `HUD_KICKER_RESULTS`, `UI_MENU_PAGE_GARAGE` (`main_menu`) y `UI_SOUND_MUTED`
  (`sound_check_panel`); `HUD_CARE_CHIP_*` (`care_card`, chip de estado), `HUD_CARGO_TITLE` y
  `HUD_SESSION_MODE_DELIVERY` (`hud.gd`), `HUD_PROMPT_RECAPTURE` / `HUD_PROMPT_SALVAGE` (`package_salvage.gd`).
- `hud_cargo_panel`: cada fila de `hud.cargo_rows` suma `"key"`; `hud_prompts.refresh_sound_subtitle()` elige el
  subtítulo por esa clave (antes comparaba el nombre en español y fallaba en inglés).

**Regla nueva en `test_ui_translations`:** ningún script fuera de `trap_definition.gd` /
`package_content.gd` lee el `display_name` de un `.tres` para mostrarlo. Un `.text = "PALABRA"` suelto
falla, salvo las palabras que se escriben igual en los dos idiomas (`SAME_IN_BOTH`: ENDLESS, PING). Si
agregás una trampa: su clave va en `TrapDefinition.NAME_KEYS`, y su texto en español tiene que ser el
mismo que el `display_name` del `.tres`.
