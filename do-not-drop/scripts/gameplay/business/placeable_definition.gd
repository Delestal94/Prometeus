class_name PlaceableDefinition
extends Resource
## One object the crew can place in the warehouse (expansion D-0904, "Modo Empresa").
##
## Data only, like ProductDefinition and ZoneDefinition: what the object is, how much floor
## it takes on the warehouse grid, what it costs and what it does. The build mode (D-0901 to
## D-0903) and the default layout (D-0911) read it; nothing here names autoloads, the HUD or
## any UI class (lesson N-919: a class_name that references autoloads breaks --script runs).

## Same id (and file name) as the .tres in data/placeables/.
@export var id: StringName = &""
## Translation key of the name the players see.
@export var display_key: String = ""
## Floor cells it covers (X x Z) at rotation 0, on the warehouse grid of
## CompanyTuning.WAREHOUSE_GRID_M.
@export var footprint: Vector2i = Vector2i.ONE
## Height in meters; the ceiling and the navmesh bake read it.
@export var height_m: float = 1.0
## What it costs to buy. Selling refunds CompanyTuning.PLACEABLE_REFUND_RATIO of it (D-0920).
@export var price: int = 0
## What the object is for: &"assembly" (packing table), &"storage" (shelf, fridge) or
## &"dispatch" (where finished boxes wait for the truck).
@export var role: StringName = &"storage"
## Product slots it holds (storage only; 0 for the rest).
@export var slots: int = 0
## Stores &"cold" products (D-0616): the fridge. Other storage keeps &"ambient" ones.
@export var cold: bool = false
## Blocks walking over its footprint. A dispatch zone painted on the floor does not.
@export var blocks_walking: bool = true
## Whether it is already in the default warehouse, without buying it (D-0911).
@export var owned_at_start: bool = false


## The footprint after turning the object `quarter_turns` times by 90 degrees (any integer).
func footprint_for(quarter_turns: int) -> Vector2i:
	if posmod(quarter_turns, 2) == 1:
		return Vector2i(footprint.y, footprint.x)
	return footprint


## Money back when selling it (D-0920).
func refund() -> int:
	return floori(price * CompanyTuning.PLACEABLE_REFUND_RATIO)
