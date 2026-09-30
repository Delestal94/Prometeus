# Aviso: N-113, evento de visibilidad limitada (parabrisas embarrado) (2026-09-30)

Rama `nacho/N-113-low-visibility-event`. Toca zona compartida (`event_bus.gd`, `network_manager.gd`) y un archivo de
Slatex (`hud_notices.gd`). **Solo agrega**: ninguna firma existente cambia.

## Qué cambió

- `event_bus.gd`: señal nueva `low_visibility_changed(active, kind, duration, elapsed)` (el host la decide y la
  reparte con `relay()`; `elapsed` es 0 salvo para quien entra tarde).
- `network_manager.gd`: `PROTOCOL_VERSION` 4 -> 5 (RPC nuevo `_receive_state` de `LowVisibilityEvent`, para quien
  entra a mitad del evento). Si otra rama también lo sube, al mezclar queda el mayor.
- `hud_notices.gd` (Slatex): escucha la señal. El conductor ve el aviso fijo "¡No ves nada! Que te guíen"
  (`HUD_LOW_VISIBILITY_DRIVER`, zona crítica, mientras dura); el resto recibe un toast que sugiere guiarlo con la
  rueda de frases (`HUD_LOW_VISIBILITY_GUIDE_KEY` / `_PAD`). Tres claves nuevas en `strings_ui.csv`.
- Nuevo (Nacho): `low_visibility_event.gd` (nodo que cuelga `level_common.gd`; el host sortea desde
  `NetworkManager.world_seed`), `low_visibility_plan.gd` (números y sorteo puro), `shaders/windshield_mud.gdshader`;
  `windshield_rain.gd` suma el overlay de barro (solo lo ve quien conduce) y los limpiaparabrisas corren mientras dura.
- Test nuevo `tests/test_low_visibility_event.gd`.

## Qué tiene que hacer Slatex

Nada. Si tocás el HUD del conductor, el aviso vive en `hud_notices.gd::_on_low_visibility_changed`.
