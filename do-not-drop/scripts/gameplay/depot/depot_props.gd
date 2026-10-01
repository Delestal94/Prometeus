class_name DepotProps
extends RefCounted
## The depot's small-scale layer (N-319.2): the kit's props placed where the hall was
## bare -- the middle of the floor behind the crew's spawn (two roll cages with their
## loads, a wrapped pallet, the sorting table, a stack of flat-packs, a rolling ladder),
## the left wall between the supplies cage and the shelves (electrical panel, extinguisher
## cabinet, first-aid box, time clock and the emergency-exit sign) and the little
## pictogram signs by the door. Everything is static, folded into the depot's DepotKit.
##
## Wall pieces in the kit have their back at z = 0 and their front toward -Z, so a
## piece on the west wall faces +X with yaw -PI/2 and one on the front wall (the door's
## wall) faces +Z with yaw PI.

const Layout = preload("res://scripts/gameplay/depot/depot_layout.gd")

## Where the left wall's lining stands (x): the kit pieces' backs rest on it.
const WEST_WALL_X: float = -Layout.HALF_WIDTH + 0.06
const WEST_FACING: float = -PI * 0.5
## The middle of the hall: a roll cage's footprint, a pallet's, the table's.
const CAGE_FOOTPRINT := Vector3(0.85, 1.77, 0.75)
const PALLET_FOOTPRINT := Vector3(1.22, 1.24, 1.03)
const TABLE_FOOTPRINT := Vector3(2.0, 1.1, 0.91)

var _root: Node3D


func _init(root: Node3D) -> void:
	_root = root


func build(kit: DepotKit) -> void:
	_build_center(kit)
	_build_west_wall(kit)
	_build_door_signs(kit)


## Behind the crew's spawn (x -5..6, z 12..22), clear of the walkways, the gathering
## rectangle and the truck's lane: what a sorting floor has lying about, 1 to 1.8 m high.
func _build_center(kit: DepotKit) -> void:
	var floor_y: float = Layout.FLOOR_TOP
	for spot: Array in [[Vector3(-3.9, 0.0, 21.4), 0.1], [Vector3(-2.75, 0.0, 21.05), -0.15]]:
		var at: Vector3 = spot[0]
		kit.model(DepotKit.depot_model("sm_env_depot_roll_cage_loaded"), Transform3D(Basis(Vector3.UP, float(spot[1])),
				Vector3(at.x, floor_y, at.z)))
		_solid(kit, CAGE_FOOTPRINT, Vector3(at.x, 0.0, at.z), float(spot[1]))
	kit.model(DepotKit.depot_model("sm_env_depot_sorting_table"),
			Transform3D(Basis.IDENTITY, Vector3(0.4, floor_y, 21.6)))
	_solid(kit, TABLE_FOOTPRINT, Vector3(0.4, 0.0, 21.6), 0.0)
	kit.model(DepotKit.depot_model("sm_env_depot_pallet_wrapped"), Transform3D(Basis(Vector3.UP, 0.3),
			Vector3(4.4, floor_y, 21.2)))
	_solid(kit, PALLET_FOOTPRINT, Vector3(4.4, 0.0, 21.2), 0.3)
	kit.model(DepotKit.depot_model("sm_env_depot_flat_cardboard_stack"), Transform3D(Basis(Vector3.UP, -0.2),
			Vector3(5.4, floor_y, 17.6)))
	_solid(kit, Vector3(1.2, 0.46, 1.0), Vector3(5.4, 0.0, 17.6), -0.2)
	# The rolling ladder beside the dispatch shelves' east face.
	kit.model(DepotKit.depot_model("sm_env_depot_rolling_ladder"), Transform3D(Basis(Vector3.UP, PI * 0.5),
			Vector3(-5.5, floor_y, 22.8)))
	_solid(kit, Vector3(1.7, 2.2, 0.75), Vector3(-5.5, 0.0, 22.8), 0.0)
	# A wet-floor sign where the cages were wheeled through.
	kit.model(DepotKit.depot_model("sm_env_depot_wet_floor_sign"), Transform3D(Basis(Vector3.UP, 0.5),
			Vector3(-1.6, floor_y, 22.7)))


## The left wall's bare stretch (z 9..13): a panel with its conduits to a cable tray,
## an extinguisher cabinet, a first-aid box, the time clock and the exit sign.
func _build_west_wall(kit: DepotKit) -> void:
	var facing := Basis(Vector3.UP, WEST_FACING)
	kit.model(DepotKit.depot_model("sm_env_depot_electrical_panel"), Transform3D(facing,
			Vector3(WEST_WALL_X, Layout.FLOOR_TOP, 10.3)))
	# The tray the panel's conduits reach, along the wall at 3.45 m (its hangers go up to 4.3).
	kit.model(DepotKit.depot_model("sm_env_depot_cable_tray"), Transform3D(Basis(Vector3.UP, PI * 0.5),
			Vector3(WEST_WALL_X + 0.28, 3.45, 10.5)))
	kit.model(DepotKit.depot_model("sm_env_depot_extinguisher_cabinet"), Transform3D(facing,
			Vector3(WEST_WALL_X, Layout.FLOOR_TOP, 11.35)))
	kit.model(DepotKit.depot_model("sm_env_depot_first_aid"), Transform3D(facing,
			Vector3(WEST_WALL_X, Layout.FLOOR_TOP, 11.95)))
	kit.model(DepotKit.depot_model("sm_env_depot_time_clock"), Transform3D(facing,
			Vector3(WEST_WALL_X, Layout.FLOOR_TOP, 12.75)))
	# Pictogram signs: the way out above the cabinet, the hazard over the panel.
	_safety_sign(kit, DepotLabels.ICON_EXIT, Vector3(WEST_WALL_X, 2.65, 11.35), PI * 0.5, Layout.BOARD_GREEN,
			Layout.PAPER)
	_safety_sign(kit, DepotLabels.ICON_ELECTRIC, Vector3(WEST_WALL_X, 2.65, 10.3), PI * 0.5, Layout.YELLOW, Layout.INK)
	_safety_sign(kit, DepotLabels.ICON_FIRST_AID, Vector3(WEST_WALL_X, 2.2, 11.95), PI * 0.5, Layout.BOARD_GREEN,
			Layout.PAPER)


## Speed limit and helmets either side of the door, on the front wall inside.
func _build_door_signs(kit: DepotKit) -> void:
	_safety_sign(kit, DepotLabels.ICON_SPEED, Vector3(-4.7, 2.5, 0.07), 0.0, Layout.YELLOW, Layout.INK)
	_safety_sign(kit, DepotLabels.ICON_HELMET, Vector3(4.7, 2.5, 0.07), 0.0, Layout.SHELVES_BLUE, Layout.PAPER)


## A small square pictogram sign on a wall (`at` is its centre, `yaw` turns its front
## from +Z): a coloured plate and the atlas icon over it.
func _safety_sign(kit: DepotKit, icon: int, at: Vector3, yaw: float, plate: Color, tint: Color) -> void:
	var basis := Basis(Vector3.UP, yaw)
	kit.box_xf(Vector3(0.44, 0.44, 0.03), Transform3D(basis, at + basis * Vector3(0.0, 0.0, 0.015)),
			DepotKit.flat(plate, 0.6))
	DepotLabels.pictogram(kit, icon, Transform3D(basis, at + basis * Vector3(0.0, 0.0, 0.034)), 0.34, tint)


## A solid box for a prop standing on the floor at `at` (x/z), turned `yaw`.
func _solid(kit: DepotKit, size: Vector3, at: Vector3, yaw: float) -> void:
	kit.collider(size, Transform3D(Basis(Vector3.UP, yaw), Vector3(at.x, Layout.FLOOR_TOP + size.y * 0.5, at.z)))
