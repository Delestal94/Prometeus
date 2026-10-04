class_name ZoneDefinition
extends Resource
## One zone of the continuous map (expansion D-0205). A "district" is a zone.
##
## Data only, like ProductDefinition: where the zone is, what drives and hurts
## inside it, which gates close it and what a trip there pays. Nothing here
## names autoloads or UI classes (lesson N-919). The bounds are provisional
## until the map sketch (D-0301) adjusts them in data/zones/*.tres; the other
## numbers come from docs/expansion-distritos/diseno/distritos.md.

## Same id (and file name) as the .tres in data/zones/.
@export var id: StringName = &""
## Translation key of the zone name (WORLD_ZONE_<ID>). The CSV row is added
## by the task that first shows the name.
@export var display_key: String = ""
## The zone's rectangle on the world XZ plane, in meters (x, z, width, depth).
@export var bounds: Rect2 = Rect2()
## Vehicle ids that may deliver inside the zone.
@export var vehicles: Array[StringName] = []
## Hazard ids (snake_case of the route class) found in the zone.
@export var hazards: Array[StringName] = []
## Ids of the gates that close the zone (data/gates/<id>.tres, D-0306).
## Empty means the zone is open from the first day.
@export var gates: Array[StringName] = []
## WorldMood weather profiles allowed in the zone (WorldMood.WEATHER_NAMES).
@export var mood_profiles: Array[StringName] = []
## What the company earns per delivered trip to this zone.
@export var shipping_fee: int = 0
## Houses per trip, as (min, max). (0, 0) means no deliveries (the depot).
@export var houses_per_trip: Vector2i = Vector2i.ZERO
## Reputation gained per delivery before bonuses. A starting number for
## sim_economy, not a final balance.
@export var base_reputation_gain: float = 0.0


## True when no gate closes the zone, so it is playable from the start.
func is_open_at_start() -> bool:
	return gates.is_empty()


## True when the world position falls inside the zone (height is ignored).
func contains_xz(pos: Vector3) -> bool:
	return bounds.has_point(Vector2(pos.x, pos.z))
