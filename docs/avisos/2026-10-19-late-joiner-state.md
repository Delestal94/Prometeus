# Joiner tardío: gancho de rescate y casas ya entregadas (N-975), PROTOCOL_VERSION 36

Para Slatex. Toca zona compartida (`event_bus.gd`, `run_manager.gd`, `network_manager.gd`).

- **`EventBus.delivery_restored(house_index: int, outcome: StringName)`**, señal nueva (se agrega, no cambia
  ninguna): **local**, nunca pasa por `relay()`. La emite `RunManager._receive_session_state` en un peer que
  entra a mitad de la corrida, una vez por cada entrada de `deliveries` que trae el estado del host, al final
  de copiarlo. La escuchan las vistas que muestran una casa esperando: `HouseWaitingMarker` (farol, cartel,
  globo), `DeliveryHouse` (timbre), `DashboardGps` y el pizarrón del depósito. `house_delivery_recorded` no se
  reemite: dispararía la voz y la cara de cada jugador, la escena del vecino y `register_delivery()` otra vez.
  **Si una vista tuya guarda estado por casa** (no un momento como un subtítulo o una voz), que escuche
  también `delivery_restored`; lo que reacciona al momento de la entrega no tiene que hacer nada.
- **`RunManager._receive_session_state`**: misma firma y misma anotación `@rpc` (orden de RPCs intacto). Su
  cuerpo pasó a `_load_session_state(state)`, privada; después emite lo de arriba.
- **`RescueHook`** (`scripts/gameplay/vehicle/rescue_hook.gd`, de Nacho): el host escucha
  `NetworkManager.peer_level_ready` y le manda `_set_armed.rpc_id(peer, armed)` diferido (canal 0,
  `reliable`, el RPC `authority` que ya existía), como la radio. Antes un joiner veía el gancho guardado.
- **Protocolo: sí, 35 → 36.** Ningún RPC cambió de nombre ni de argumentos, pero lo que recibe y hace un
  joiner sí: con builds mezcladas (host nuevo y cliente viejo, o al revés) el joiner se quedaba con medio
  estado sin explicación; ahora el handshake dice "otra versión". La línea "36" está en el historial de la
  constante. **El próximo número libre es 37.**
