class_name DepotLayout
extends RefCounted
## The depot's floor plan, palette and asset list, shared by Depot and the
## builders that dress it (DepotHall, DepotFurnishing, DepotDressing,
## DepotOrderBoard). Only constants: change a number here and every piece
## that depends on it moves with it.
##
## Space: the door's plane is z = 0 and the depot runs toward +Z (the road
## leaves toward -Z, like route.gd). Everything is in the Depot node's space.

# --- Shell ---------------------------------------------------------------------

const HALF_WIDTH: float = 15.0
const DEPTH: float = 32.0
const WALL: float = 0.3
const WALL_HEIGHT: float = 8.0
const CEILING: float = 7.4
const FLOOR_TOP: float = 0.03
const DOOR_WIDTH: float = 6.6
const DOOR_HEIGHT: float = 4.8

# --- Where things are ------------------------------------------------------------

## Where the truck waits, nose to the door (for the level scene and tests).
const TRUCK_BAY := Vector3(0.0, 0.9, 7.5)
## How far out (depot z) the truck's centre must be before the door may close:
## its whole length plus the stowed ramp, clear of the curtain.
const TRUCK_CLEAR_Z: float = -6.5
## Dispatch shelving: two units of four bays, two levels each.
const SHELF_UNITS: Array[Dictionary] = [{"aisle": "A", "x": -6.8}, {"aisle": "B", "x": -10.2}]
const SHELF_START_Z: float = 15.5
const BAY_LENGTH: float = 2.0
const BAYS: int = 4
const SHELF_DEPTH: float = 1.0
const LEVEL_TOPS: Array[float] = [0.35, 1.5]
const SPAWN_POINTS: Array[Vector3] = [
	Vector3(-1.2, 1.0, 16.8), Vector3(0.0, 1.0, 16.8), Vector3(1.2, 1.0, 16.8), Vector3(2.4, 1.0, 16.8),
	Vector3(-1.2, 1.0, 18.0), Vector3(0.0, 1.0, 18.0), Vector3(1.2, 1.0, 18.0), Vector3(2.4, 1.0, 18.0),
]
## The order board: a whiteboard on a stand beside the truck, angled toward
## where the crew appears.
const BOARD_AT := Vector3(-4.5, 0.0, 13.0)
const BOARD_YAW_DEGREES: float = 38.0
## The conveyor along the back wall; its boxes loop from start to end.
const CONVEYOR_START_X: float = -9.8
## Ends well short of the office (x 8.6): at 7.2 its end portal stood right
## in front of the office door.
const CONVEYOR_END_X: float = 5.0
const CONVEYOR_Z: float = 30.6
## Where the portal frames stand along the hall: a column on each wall.
const PORTAL_FRAMES: Array[float] = [2.4, 8.0, 13.6, 19.2, 24.8, 30.4]
## Where the wall lining's block dado meets the sheet above: exactly the
## dado's top. The sheet used to start 3 cm lower, and the overlap z-fought
## in a flickering line all the way round the hall.
const LINER_SPLIT: float = 2.4 + FLOOR_TOP
## The loading zone behind the truck's ramp (x/z), and how far each layer of
## floor paint sits over the one under it so none of them z-fight.
const LOADING_ZONE := Rect2(-1.9, 13.55, 3.8, 1.3)
const FLOOR_PAINT_STEP: float = 0.004
## The workshop's floor (x/z), from the front wall to the lockers.
const WORKSHOP_FLOOR := Rect2(9.4, 0.3, HALF_WIDTH - 9.4 - 0.06, 12.2)
## The truck and paint terminal: inside the workshop, facing the hall.
const KIOSK_AT := Vector3(10.6, 0.0, 9.0)

# --- Palette and type ------------------------------------------------------------

const TEAL := Color("65b5a1")
const INK := Color("1e2235")
const PAPER := Color("fff6e6")
const YELLOW := Color("e7be51")
const DISPLAY_FONT: Font = preload("res://assets/fonts/LilitaOne-Regular.ttf")
const BODY_FONT: Font = preload("res://assets/fonts/Nunito-Variable.ttf")
## Each place's colour, shared by its hanging sign and the arrow painted
## toward it on the floor (tareas de Nacho N-503).
const SHELVES_BLUE := Color("2f5d8a")
const BOARD_GREEN := Color("2e9e56")
const LOCKERS_TEAL := Color("3f7f8c")
const SHOP_PURPLE := Color("7b52b9")
const WORKSHOP_RED := Color("c0392b")

# --- Assets ----------------------------------------------------------------------

const CARGO_BOXES: Array[String] = [
	"res://assets/models/cargo/sm_cargo_box_cube.glb",
	"res://assets/models/cargo/sm_cargo_box_flat.glb",
	"res://assets/models/cargo/sm_cargo_box_tall.glb",
	"res://assets/models/cargo/sm_cargo_box_vented.glb",
]
const PALLET: String = "res://assets/models/environment/props/sm_env_prop_pallet.glb"
const CRATE: String = "res://assets/models/environment/props/sm_env_prop_wooden_crate.glb"

# --- Wayfinding and contact shadows ----------------------------------------------

## Wayfinding from where the crew appears: an arrow painted on the floor
## toward each place, and its name beside it. The words read facing the
## truck, the way everyone spawns; each arrow aims at `toward`.
const FLOOR_GUIDES: Array[Dictionary] = [
	{"caption": "WORLD_DEPOT_BOARD", "word": Vector3(-2.0, 0.0, 16.0),
		"arrow": Vector3(-2.7, 0.0, 15.3), "toward": Vector3(-4.3, 0.0, 13.3), "colour": BOARD_GREEN},
	{"caption": "WORLD_DEPOT_SHELVES", "word": Vector3(-3.0, 0.0, 17.4),
		"arrow": Vector3(-4.9, 0.0, 17.4), "toward": Vector3(-6.3, 0.0, 17.4), "colour": SHELVES_BLUE},
	{"caption": "WORLD_DEPOT_WORKSHOP", "word": Vector3(3.0, 0.0, 15.5),
		"arrow": Vector3(4.4, 0.0, 15.2), "toward": Vector3(10.15, 0.0, 9.0), "colour": WORKSHOP_RED},
	{"caption": "WORLD_DEPOT_LOCKERS", "word": Vector3(4.3, 0.0, 17.0),
		"arrow": Vector3(6.3, 0.0, 17.0), "toward": Vector3(14.0, 0.0, 15.5), "colour": LOCKERS_TEAL},
	{"caption": "WORLD_DEPOT_SUPPLIES", "word": Vector3(4.6, 0.0, 18.6),
		"arrow": Vector3(6.9, 0.0, 19.0), "toward": Vector3(10.8, 0.0, 23.4), "colour": SHOP_PURPLE},
]
## Soft dark patches where heavy things meet the floor (tareas de Nacho
## N-308.2; no SSAO on GL Compatibility): the cars outside, the dumpster,
## the pallets waiting to be put away and the stacks of empty ones.
## [centre, footprint (x by z), band half-width, opacity]
const CONTACT_SHADOWS: Array = [
	[Vector3(-18.5, 0.0, -5.2), Vector2(4.4, 1.8), 0.5, 0.55],
	[Vector3(-11.8, 0.0, -5.4), Vector2(4.8, 2.0), 0.5, 0.55],
	[Vector3(17.8, 0.0, -2.0), Vector2(2.0, 1.2), 0.4, 0.5],
	[Vector3(17.6, 0.0, -5.6), Vector2(1.2, 1.0), 0.35, 0.45],
	[Vector3(-5.2, 0.0, 27.6), Vector2(1.2, 1.0), 0.35, 0.45],
	[Vector3(-3.4, 0.0, 27.6), Vector2(1.2, 1.0), 0.35, 0.45],
	[Vector3(-5.2, 0.0, 29.3), Vector2(1.2, 1.0), 0.35, 0.45],
	[Vector3(-1.4, 0.0, 31.3), Vector2(1.2, 1.0), 0.35, 0.45],
]


## The board's transform in depot space (its foot on the floor).
static func board_basis() -> Basis:
	return Basis(Vector3.UP, deg_to_rad(BOARD_YAW_DEGREES))
