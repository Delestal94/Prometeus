# Aviso: pistas de carga como claves e íconos de prompt por clave (2026-09-30)

Lo hizo Nacho (rutina de construcción, con Claude). Cierra las dos subtareas que le quedaban a N-805.
Toca archivos tuyos (trampas, paquete, HUD, interacción) y la zona compartida (`event_bus.gd`,
`network_manager.gd`). No tenés que hacer nada: `git pull` antes de seguir con trampas, paquetes o HUD.

**Por qué:** las pistas de carga y los mensajes del rescate se traducían en el host y viajaban ya
armados, así que un cliente en inglés leía la crisis de su caja en español. Además, el ícono del prompt
de interacción se buscaba con palabras en español ("agarrar", "timbre"…), y en inglés los prompts se
quedaban sin ícono.

**Qué cambió (firmas y datos):**
- `LocText` (`scripts/core/loc_text.gd`, nuevo): una línea es `[clave, args...]`. `LocText.make(clave, args)`
  la arma y `LocText.render(línea)` la traduce en el par que la muestra. Un arg que es Array es otra línea
  (el nombre de la herramienta dentro del progreso). Si le pasás un String, lo devuelve tal cual.
- Trampas: `get_hint() -> String` pasa a `hint_text() -> Array`. `ITrapBehavior.get_hint()` sigue
  existiendo y devuelve `LocText.render(hint_text())`, así que el código y los tests locales no cambian.
  **Si agregás una trampa, sobreescribí `hint_text()` y no `get_hint()`.**
- `package.gd`: `hint_text()` es nuevo y `get_hint()` lo traduce. `mark_lost(cause)` recibe una **clave**
  (`level_common` manda `"HUD_CARGO_FELL_OFF"`). Un texto suelto también sirve: pasa sin traducir.
- `package_care.gd`: `message` pasa a `Array`, y también `crisis_prompt()` y `tool_blocker()` (vacío = se
  puede usar: `.is_empty()` funciona igual). `tool_name_key()` es nuevo; `tool_name()` sigue devolviendo
  el texto. Si `apply_snapshot` recibe un mensaje viejo en String, lo descarta.
- `EventBus.package_hint_changed(package_id, hint: Array)`: el segundo argumento pasa a ser la línea.
  `hud_cargo_panel` guarda la línea y la traduce al mostrarla.
- `care_state["hint"]` (en `package_rescue.publish_care`) también es la línea. `CareGuide.next_step` la traduce.
- El `"verb"` de `sequence_state()` (bomba y peso creciente) también viaja como clave (`HUD_CARE_VERB_DEFUSE`,
  `HUD_CARE_VERB_SECURE`, nuevas `HUD_CARE_VERB_SECURE`/`HUD_CARE_VERB_SOLVE`) y `CareGuide` lo traduce: antes el
  peso creciente decía "Asegurar" en cualquier idioma.
- Los números de las pistas van redondeados (grados y segundos enteros), como ya los mostraba el `%.0f`.
- `NetworkManager.PROTOCOL_VERSION` pasa a 4.
- `hud_prompts.PROMPT_ACTIONS` pasa a mapear cada acción a **claves**, que se buscan traducidas en el
  idioma del jugador. Salen foto, bocina, ping y carta: ningún prompt de interacción las usa.
  `hud_prompts.gd` ya no está en `SPANISH_LITERAL_FILES`.
- Los prompts de los montajes de `vehicle.tscn` pasan a claves (`HUD_PROMPT_PLACE_PACKAGE`,
  `HUD_PROMPT_STORE_ON_SHELF`) y `package_mount_point.get_prompt()` los traduce. `seat_point` usa
  `HUD_PROMPT_DRIVE` en vez del literal "Subirse a manejar". Las tres claves son nuevas en `strings_ui.csv`.

**Test:** `test_hint_relay.gd` cubre ahora:
- la pista viaja como clave y se lee distinto en es y en;
- los mensajes de rescate (con args y con herramienta anidada) y su snapshot;
- los íconos de prompt en los dos idiomas.
