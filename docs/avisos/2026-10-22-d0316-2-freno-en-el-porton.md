# D-0316.2: el portón frena al tercer vehículo; `world_cells` suma `keep_shown` y `copy_hidden`

Zona compartida:

- `modules/world_cells/cell_interest.gd`: dos agregados. Ninguna firma cambia.
  - `var keep_shown: Callable`: una copia para la que devuelve true nunca se esconde en este peer.
  - `signal copy_hidden(body)`: se emite al esconder una copia y en cada actualización que llega mientras
    está escondida. Cubre el pulso, que podía volver a escribir el estado.
- `scripts/core/network_manager.gd`: `PROTOCOL_VERSION` pasa de 50 a **51**. Hay un RPC nuevo,
  `CompanyTripsView._held_here`, que va del host al conductor: cuando su vehículo queda frenado en el portón,
  le dice el motivo. Un cliente con el protocolo 50 no se entiende con un host con el 51.

No se tocaron archivos de Slatex. El soporte (`occupied_by`) que deja ocupado una caja escondida se resuelve en
`company_interest.gd`; `package_mount_point.gd` queda como estaba.
