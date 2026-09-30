# Aviso: caja de cambios manual, el furgón clásico viejo (N-114, 2026-09-30)

Lo hizo Nacho (con Claude), PR `nacho/N-114-manual-gearbox-v2`. Toca archivos de Slatex y zona compartida.

## Qué cambió

- Variante nueva del camión, `vintage` ("Furgón clásico viejo"): se desbloquea con 6 entregas y 550
  puntos (`UnlockManager.UNLOCKS[&"vintage_van"]`), se elige en el depósito (taller) y en el panel de
  personalización como las otras. Tiene caja manual de 5 marchas y **paga un 25 % más** (compensación).
- Archivos de Slatex tocados, todos chicos y solo aditivos:
  - `scripts/core/game_settings.gd`: dos acciones reasignables nuevas, `drive_shift_up` (flecha arriba,
    bumper derecho del mando) y `drive_shift_down` (flecha abajo, bumper izquierdo). Entran en
    `REBINDABLE_ACTIONS` y `DEFAULT_KEY_BINDINGS`. No hay ajustes nuevos: no toca `SAVED_KEYS`. Además
    `GameSettings.binding_label` (override, misma firma) muestra las flechas como "↑ ↓ ← →" en vez de
    "Up"/"Down"; vale en Opciones y en cualquier cartel que use `binding_label`.
  - `scripts/ui/options_panel.gd`: dos filas más en la lista de teclas.
  - `scripts/ui/hud/hud_cargo_panel.gd`: una línea "MARCHA n" bajo la velocidad (solo si el camión es
    manual) y, en el tope de la marcha, un "¡SUBÍ! [↑]" grande, rojo y titilante (`gear_label`,
    `shift_up_label`). Se actualiza con `vehicle_telemetry` y al instante con `Gearbox.gear_changed`.
  - `scripts/ui/hud/hud_results.gd`: la línea "Pago del equipo" suma "(incluye +$N del furgón viejo)".
  - `translations/strings_ui.csv`: claves nuevas `UI_TRUCK_VINTAGE`, `UI_TRUCK_MANUAL`,
    `UI_UNLOCK_VINTAGE_VAN`, `UI_OPT_BIND_SHIFT_UP/DOWN`, `HUD_GEAR`, `HUD_GEAR_SHIFT_UP`,
    `HUD_RESULT_PAY_BONUS`; y la ayuda de controles (`UI_OPT_CONTROLS_KEYS/PAD`) menciona las marchas.
- Zona compartida:
  - `project.godot`: acciones de input `drive_shift_up` / `drive_shift_down`.
  - `scripts/core/crew_progression.gd`: `award_delivery` multiplica el pago por el multiplicador del
    camión que está en la ruta (`Vehicle.pay_multiplier()`, que sale de `Vehicle.VARIANTS`: única
    fuente; nunca menos de 1.0) y deja `results["pay_multiplier"]` y `results["pay_bonus"]`. Sin camión
    o con uno común, todo igual que antes. `run_manager.gd` no se toca.
  - `scripts/core/network_manager.gd`: **`PROTOCOL_VERSION` pasa a 12** (nodo `Gearbox` en el camión con
    `gear` replicado y RPC `request_gear_shift`). Si otra rama también subió a 12 por otra cosa, al
    rebasear hay que pasar al siguiente número libre y mantener las líneas del historial del comentario
    (`tests/test_protocol_version.gd`, cuando entre, exige que sea único y consecutivo).
  - `request_gear_shift` es un RPC `any_peer` + `reliable`: cuando entre `RpcGuard` (N-221) hay que sumar
    `RpcGuard.allow_request(self)`; la comparación explícita del remitente con `driver_peer_id` se queda
    (con nadie al volante, `RpcGuard.sender_ok` dejaría pasar a cualquiera).
  - `scripts/presentation/phone_camera.gd`: el conductor de un camión manual no saca el celular (el
    bumper izquierdo del mando es de `phone_toggle` y de la marcha abajo).
- Ninguna firma existente cambió. `Vehicle.set_controls`/`submit_driver_input` siguen igual; el camión
  clásico y el ágil no cambian (los tests de manejo N-104 no se tocaron).

## Qué tiene que hacer Slatex

Nada obligatorio. Si agregás acciones de conducción o más filas al panel de teclas, usá las mismas
listas (`REBINDABLE_ACTIONS`, `DEFAULT_KEY_BINDINGS`). Si hacés otra pantalla de resultados, el pago
extra viene en `results["pay_bonus"]`.
