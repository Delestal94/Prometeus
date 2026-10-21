# fleet

Vehicles of the company mode (expansion, D-0220): VehicleDefinition (D-0207), the common FleetVehicle base (D-0208) and its movement interface (D-0209), then the bike, cart, boat and plane.

- `vehicle_definition.gd` (D-0207): the data of a vehicle (seats, cargo, price, movement).
- `fleet_cargo.gd` (D-0208): carries / point_velocity / needs_sweep, the cargo shell and the shelving of a box, on any `Node3D` owner.
- `fleet_seats.gd` (D-0208): seat and driver queries on any `Node3D` owner.
- `fleet_motion.gd` (D-0209): the movement interface (`speed_kmh`, `forward`, `ground_contact` 0-1, `cargo_acceleration`) the cargo reads instead of the `VehicleBody3D`; the vehicle exposes it as `fleet_motion`.

The base is made by composition: vehicle.gd (the van, still in scripts/gameplay/vehicle/) holds a FleetCargo, a FleetSeats and a FleetMotion and keeps its public API; driving (engine, steering, prediction, net pose, wheels, parking) stays in it. How a vehicle without wheels uses them: docs/agregar-vehiculo.md.
