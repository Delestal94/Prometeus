# Aviso 2026-11-07 · las cajas del tablero van al estante y no se congelan en la flota (D-0302.2.b.3)

Toca un archivo de Slatex: `scripts/gameplay/package/package_handling.gd`. **Sin cambio de protocolo**: ni RPC ni
propiedades replicadas nuevas.

- **`PackageHandling.place_at()`**: una caja puesta en un estante de un vehículo del grupo `company_vehicle` queda sin
  congelar (`rack_drives()`), porque ahí no hay corrida que la descongele y se quedaba en el aire al arrancar. En el
  depósito y en la corrida nada cambia: con la flota de la empresa afuera, `freeze` sigue igual que antes.
- **`DispatchRack`** (`scripts/gameplay/business/dispatch_rack.gd`, nuevo): "Cargar" en el tablero llama al `store()` de
  `PackageMountPoint` en el host. `package_mount_point.gd` no cambia. Qué va arriba lo dice `DispatchRack.rides()` (la
  bahía): en la flota `is_loaded` y `occupied_by` pueden quedar viejos si una caja se cae, y el host los suelta al leer
  el tablero, al guardar otra caja o al cerrar la salida.
- **`CompanyFleet.send_home()` y `recover_fallen()`** llevan las cajas de la bahía con el vehículo
  (`DispatchRack.haul()`). Quien estacione una camioneta con `park(at)` por otro camino tiene que hacer lo mismo.
- **`CompanyTripsView`**: el libro compartido sigue a `trip_started` y `trip_closed`. Quien lea
  `CompanyNet.orders.book` ahora ve pedidos `OUT` y `FAILED` por salidas reales.
- Decisión: `docs/decisiones/2026-11-07-carga-al-estante-y-libro-de-salidas.md`. Revisar:
  `docs/expansion-distritos/revisar/D-0302.2.b.3.md`.
