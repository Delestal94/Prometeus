# D-0606.b: el autoelevador en el mundo (zona compartida)

Tocado en zona compartida o en archivos de otro dominio:
- `project.godot`: dos acciones nuevas, `forklift_mast_up` (flecha arriba, gatillo derecho) y `forklift_mast_down` (flecha abajo, gatillo
  izquierdo). No están en Opciones (`test_options_controls` las lista como no ofrecidas).
- `scripts/gameplay/player/player_interaction.gd`: `try_interact()` y `publish_prompt()` ceden la tecla y el aviso si el jugador tiene la
  meta `interact_override` (`{use: Callable, prompt: Callable}`), que el `ForkliftView` pone mientras ese jugador maneja.
- `scripts/core/network_manager.gd`: `PROTOCOL_VERSION` 47 (petición `fork_act`, evento `fork_state`, `by` / `slot` en `jack_picked` /
  `jack_placed`, entrada `forklift` en la parte `pallets` del snapshot). Va después de 45 (cajas sueltas, D-0316.3) y 46 (`jack_departed`,
  D-0618.b, #630), que ya están en main.
- `scripts/core/company/company_net.gd`: solo las listas de pedidos y eventos y `_on_object` (la estación del autoelevador y el `peer` en la
  estación); sin líneas nuevas (el archivo está en 999).
