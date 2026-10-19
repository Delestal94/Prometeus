class_name VehicleDefinition
extends Resource
## One vehicle of the company's fleet (expansion D-0207).
##
## Data only, like ZoneDefinition and ProductDefinition: what a vehicle is, seats,
## cargo and price, without changing how it drives. Nothing here names autoloads
## or UI classes (lesson N-919). The numbers come from the table "Campos para
## VehicleDefinition" of docs/expansion-distritos/diseno/flota.md (D-0115).

## How a vehicle moves (`movement`). The common FleetVehicle base (D-0208) reads it.
const MOVEMENTS: Array[StringName] = [&"wheels", &"hull", &"wings", &"pedal"]

## Same id (and file name) as the .tres in data/vehicles/.
@export var id: StringName = &""
## The vehicle's scene (the van's is scenes/gameplay/vehicle/vehicle.tscn).
@export var scene: PackedScene
## Key of vehicle.gd VARIANTS this vehicle runs as. Empty for vehicles that have no variants.
@export var variant: StringName = &""
## Places for the crew, driver included.
@export var seats: int = 0
## Boxes aboard at once, in hands or on a rack.
@export var cargo_slots: int = 0
## Cargo weight the vehicle takes, in kg.
@export var cargo_kg: float = 0.0
## One of MOVEMENTS.
@export var movement: StringName = &"wheels"
## Which closed gate it crosses without collision (`water`, `altitude`); empty when none.
@export var gate_key: StringName = &""
## What one unit costs at the dealer.
@export var price: int = 0
## Key that ZoneDefinition.vehicles, GateRequirement.vehicle_key and the "vehicle" entry of
## CompanyState.fleet look at: the three vans are all `van`.
@export var fleet_key: StringName = &""
## Id of the trap in data/traps/ that this vehicle amplifies; empty when none.
@export var amplified_trap: StringName = &""


## True when the numbers make a vehicle that can be used: an id, a scene, a known movement,
## seats, cargo and a fleet key.
func is_valid() -> bool:
	return (
		id != &""
		and scene != null
		and MOVEMENTS.has(movement)
		and seats > 0
		and cargo_slots > 0
		and cargo_kg > 0.0
		and fleet_key != &""
	)
