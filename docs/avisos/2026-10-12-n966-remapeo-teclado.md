# Remapeo de teclado completo en Opciones (N-966.1 y N-966.2)

**Fecha:** 2026-10-12 · **De:** Nacho · **Para:** Slatex

## Qué cambió

- `do-not-drop/scripts/ui/options_controls_section.gd` (nuevo, `class_name OptionsControlsSection`): todas las filas de
  teclas de Opciones, en tres grupos plegables ("A pie", "Manejando", "Tripulación"). Cada fila tiene el botón de la
  tecla, un botón "Original" (restablecer esa acción) y, debajo, un aviso cuando hubo intercambio o rechazo. Escucha la
  tecla con `_input` (antes de la navegación de foco, así Tab, flechas y Espacio también se pueden asignar); Esc o B
  cancelan la espera.
- `do-not-drop/scripts/ui/options_panel.gd`: la lista de 9 pares se reemplazó por la sección (`_controls_section`;
  `_binding_buttons` sigue existiendo y apunta a los botones de la sección). Se fue `_listen_for_key` y la rama de
  escucha de `_unhandled_input`.
- `do-not-drop/scripts/core/game_settings.gd`: `REBINDABLE_ACTIONS` pasa de 9 a 23 (caminar, saltar, `drive_*`,
  `package_drop/open`, `care_work`, `phone_toggle`, `crew_panel`, `spectate_toggle`). API nueva: `rebind_key()`,
  `reset_binding()`, `binding_conflicts()`, `bound_key()`, `is_binding_default()`. Un conflicto se resuelve
  intercambiando las teclas, pero solo cuenta entre acciones que se leen en el mismo contexto (`BINDING_CONTEXTS`:
  W es "caminar" y "acelerar" por defecto sin chocar). Si el intercambio no puede ser limpio, no cambia nada y avisa.
  Esc y F11 están reservadas. `care_work` no trae tecla (clic derecho): `KEY_NONE` en `DEFAULT_KEY_BINDINGS`.
  `bind_key()` del módulo sigue igual y no mira conflictos.
- `do-not-drop/translations/strings_ui.csv`: claves `UI_OPT_BIND_*` nuevas (acciones, grupos, "Original", avisos).
- Test: `do-not-drop/tests/test_options_controls.gd`.

Ninguna firma existente cambió; no hay RPC.

## Qué tiene que hacer Slatex

Nada. Si rehacés Opciones, las teclas viven en `ControlsSection`. Falta el remapeo de mando (N-966.3).

## Extra: `scripts/ui/ui_theme.gd`

`_refresh_text_scale` now takes its screen as `Variant` and casts after `is_instance_valid`: a freed panel no longer raises "Cannot convert argument" when `menu_text_scale_changed` fires after it was freed (seen in `reset_to_defaults()` from tests).
