# Protocolo 48: la camioneta de la empresa existe en el mundo de la empresa (D-0302.2.b)

**Fecha:** 2026-10-22 · **De:** Nacho (red) · **Para:** Slatex

## Qué cambió

- **`PROTOCOL_VERSION` 48** (`scripts/core/network_manager.gd`, zona compartida): solo la constante y su línea del
  historial (46 es D-0618.b, 47 D-0517, ya en `main`). Ninguna firma ni RPC de `NetworkManager`, `NetSession` o
  `EventBus` cambió y `modules/` no se tocó.
  **Cambió el protocolo** aunque no hay RPC nuevo: el mundo de la empresa tiene un nodo replicado nuevo en cada peer,
  `World/Vehicles/van_classic` (la `vehicle.tscn` con su `MultiplayerSynchronizer` de siempre). Un cliente viejo no
  tiene ese nodo (no resuelve el sincronizador del host) y no esconde la copia lejana que el host deja de mandar.
- **`scripts/gameplay/districts/company_fleet.gd`** (nuevo, `class_name CompanyFleet`): arma un vehículo por entrada de
  la flota de `CompanyState` (vacía: `CompanyTuning.STARTING_FLEET`), con su id como nombre, en el grupo
  `company_vehicle`, estacionado afuera de la salida norte del galpón, congelado y con un `NetRestThrottle` (quieto
  manda su pose cada 0,5 s: 0,4 KB/s por cliente). El cliente lo arma cuando le llega el snapshot del host; el host
  le abre el sincronizador a ese peer recién después de mandarle el snapshot (regla 10 de `red-autoridad.md`).
- `CompanyTrips.forget()` ahora cierra la salida del vehículo que deja el mundo (lo no entregado falla) y solo mira
  los vehículos de su propio `multiplayer`. `CompanyRoot` suma `fleet` (una línea en `_ready`).
- Tests: `test_company_fleet` (nuevo: solo y par ENet), `test_company_trips` (`forget`, otra sesión),
  `test_company_root` (las anclas cuentan la flota; el chequeo de la tasa de pose al ir a bordo usa la camioneta real,
  no un `Carrier` de prueba) y `test_company_online` (el cliente en el mismo proceso tiene su propio `EventBus`: la
  camioneta del host retransmite `vehicle_telemetry` por ahí, como en la ruta).

## Qué tiene que hacer Slatex

Nada obligatorio. Para saber: en el mundo de la empresa ahora hay un nodo en el grupo `vehicle`, así que lo que en
`player/` y `package/` busca la camioneta con `get_first_node_in_group(&"vehicle")` (ir a bordo, `net_in_vehicle`,
la tasa de pose, el asiento) la encuentra como en la ruta. Con más de un vehículo en la flota solo cuenta el primero:
queda para cuando la flota tenga dos (D-0302.2.b.2). Si una rama tuya sube `PROTOCOL_VERSION`, la próxima libre es 49.
