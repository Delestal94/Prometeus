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
## The mural on the back wall (it arrives with the art: nothing is drawn while the file is missing):
## 8 x 1.6 m, centred, from 4.5 to 6.1 m up, worn paper white (the texture carries its 75 % alpha).
const MURAL: String = "res://assets/textures/depot/tx_depot_mural_brand.png"
const MURAL_SIZE := Vector2(8.0, 1.6)
const MURAL_CENTRE_Y: float = 5.3
## The receiving door in the back wall, left of the conveyor's start: where the stock comes in.
const RECEIVING_DOOR_X: float = -11.0
const RECEIVING_DOOR := Vector2(6.6, 4.8)
const DOOR_SLAT: float = 0.3

## The caption strip under a pictogram sign: its size and how far its centre hangs under the sign's.
const CAPTION_STRIP := Vector2(0.62, 0.13)
const CAPTION_DROP: float = 0.31

var _root: Node3D


func _init(root: Node3D) -> void:
	_root = root


func build(kit: DepotKit) -> void:
	_build_center(kit)
	_build_west_wall(kit)
	_build_door_signs(kit)
	await kit.tick()
	_build_back_wall(kit)
	await kit.tick()
	_build_grounding(kit)
	await kit.tick()
	_build_wear(kit)


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
			Layout.PAPER, tr("WORLD_DEPOT_SAFETY_EXIT"))
	_safety_sign(kit, DepotLabels.ICON_ELECTRIC, Vector3(WEST_WALL_X, 2.65, 10.3), PI * 0.5, Layout.TRUCK_YELLOW,
			Layout.INK, tr("WORLD_DEPOT_SAFETY_ELECTRIC"))
	_safety_sign(kit, DepotLabels.ICON_FIRST_AID, Vector3(WEST_WALL_X, 2.2, 11.95), PI * 0.5, Layout.BOARD_GREEN,
			Layout.PAPER, tr("WORLD_DEPOT_SAFETY_FIRST_AID"))


## Speed limit and helmets either side of the door, on the front wall inside.
func _build_door_signs(kit: DepotKit) -> void:
	_safety_sign(kit, DepotLabels.ICON_SPEED, Vector3(-4.7, 2.5, 0.07), 0.0, Layout.TRUCK_YELLOW, Layout.INK,
			tr("WORLD_DEPOT_SAFETY_SPEED"))
	_safety_sign(kit, DepotLabels.ICON_HELMET, Vector3(4.7, 2.5, 0.07), 0.0, Layout.SHELVES_BLUE, Layout.PAPER,
			tr("WORLD_DEPOT_SAFETY_HELMET"))


## A small square pictogram sign on a wall (`at` is its centre, `yaw` turns its front
## from +Z): a coloured plate and the atlas icon over it, and under it a strip of the same
## plate (same batch) with a word or two in the icon's colour (one Label3D, group `depot_safety_caption`).
func _safety_sign(kit: DepotKit, icon: int, at: Vector3, yaw: float, plate: Color, tint: Color,
		caption: String) -> void:
	var basis := Basis(Vector3.UP, yaw)
	kit.box_xf(Vector3(0.44, 0.44, 0.03), Transform3D(basis, at + basis * Vector3(0.0, 0.0, 0.015)),
			DepotKit.unlit(plate))
	DepotLabels.pictogram(kit, icon, Transform3D(basis, at + basis * Vector3(0.0, 0.0, 0.034)), 0.34, tint)
	var strip_at: Vector3 = at + Vector3(0.0, -CAPTION_DROP, 0.0)
	kit.box_xf(Vector3(CAPTION_STRIP.x, CAPTION_STRIP.y, 0.03), Transform3D(basis,
			strip_at + basis * Vector3(0.0, 0.0, 0.015)), DepotKit.unlit(plate))
	var label := DepotLabels.text(_root, caption, strip_at + basis * Vector3(0.0, 0.0, 0.032), yaw, 30, tint,
			Layout.DISPLAY_FONT, 0.0025, 0)
	DepotLabels.fit_label(label, CAPTION_STRIP.x - 0.06)
	label.add_to_group(&"depot_safety_caption")


## A solid box for a prop standing on the floor at `at` (x/z), turned `yaw`.
func _solid(kit: DepotKit, size: Vector3, at: Vector3, yaw: float) -> void:
	kit.collider(size, Transform3D(Basis(Vector3.UP, yaw), Vector3(at.x, Layout.FLOOR_TOP + size.y * 0.5, at.z)))


## The back wall: the receiving door, shut, behind the conveyor's start (the kit's slats and bottom
## bar flush with the wall, hazard-striped jambs and a dark header: no deep frame, so nothing
## cuts across the belt), and the brand mural when its art is in the project.
func _build_back_wall(kit: DepotKit) -> void:
	var z: float = Layout.DEPTH - 0.08
	var turn := Basis(Vector3.UP, PI)
	var slat: String = DepotKit.depot_model("sm_env_depot_door_slat")
	for index: int in range(ceili(RECEIVING_DOOR.y / DOOR_SLAT)):
		kit.model(slat, Transform3D(turn, Vector3(RECEIVING_DOOR_X, Layout.FLOOR_TOP + (index + 0.5) * DOOR_SLAT, z)))
	kit.model(DepotKit.depot_model("sm_env_depot_door_bottom_bar"), Transform3D(turn,
			Vector3(RECEIVING_DOOR_X, Layout.FLOOR_TOP + 0.04, z - 0.02)))
	var stripes := DepotKit.stripes(Layout.YELLOW, Layout.INK, 0.2)
	for side: float in [-1.0, 1.0]:
		var jamb_x: float = RECEIVING_DOOR_X + side * (RECEIVING_DOOR.x * 0.5 + 0.1)
		kit.box(Vector3(0.2, RECEIVING_DOOR.y + 0.3, 0.12), Vector3(jamb_x,
				(RECEIVING_DOOR.y + 0.3) * 0.5 + Layout.FLOOR_TOP, z - 0.01), stripes)
	kit.box(Vector3(RECEIVING_DOOR.x + 0.6, 0.35, 0.14), Vector3(RECEIVING_DOOR_X,
			Layout.FLOOR_TOP + RECEIVING_DOOR.y + 0.3, z - 0.02), DepotKit.flat(Layout.INK, 0.6))
	if ResourceLoader.exists(MURAL):
		var quad := QuadMesh.new()
		quad.size = MURAL_SIZE
		var material := StandardMaterial3D.new()
		material.albedo_texture = load(MURAL) as Texture2D
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		var mural := MeshInstance3D.new()
		mural.name = "BrandMural"
		mural.mesh = quad
		mural.material_override = material
		mural.position = Vector3(0.0, MURAL_CENTRE_Y, Layout.DEPTH - 0.075)
		mural.rotation.y = PI
		mural.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_root.add_child(mural)


## Soft contact shadows under what stands on the floor (one multiplicative batch in the kit): bollards,
## column guards, the racks, the cages and tables of the middle, the desk, the stair's foot, the workshop's
## machines, the break area's appliances and the lockers.
func _build_grounding(kit: DepotKit) -> void:
	var floor_y: float = Layout.FLOOR_TOP
	for at: Vector2 in [Vector2(-3.85, 1.9), Vector2(3.85, 1.9), Vector2(-3.85, 12.9), Vector2(3.85, 12.9)]:
		kit.contact(Vector3(at.x, floor_y, at.y), Vector2(0.34, 0.34))
	for z: float in Layout.PORTAL_FRAMES:
		for side: float in [-1.0, 1.0]:
			kit.contact(Vector3(side * (Layout.HALF_WIDTH - 0.24), floor_y, z), Vector2(0.45, 0.63))
	var rack_length: float = Layout.BAY_LENGTH * Layout.BAYS
	for unit: Dictionary in Layout.SHELF_UNITS:
		kit.contact(Vector3(float(unit.x), floor_y, Layout.SHELF_START_Z + rack_length * 0.5),
				Vector2(Layout.SHELF_DEPTH, rack_length))
	for spot: Array in [[Vector3(-3.9, 0.0, 21.4), Vector2(0.85, 0.75), 0.1], [Vector3(-2.75, 0.0, 21.05),
			Vector2(0.85, 0.75), -0.15], [Vector3(0.4, 0.0, 21.6), Vector2(2.0, 0.91), 0.0],
			[Vector3(4.4, 0.0, 21.2), Vector2(1.22, 1.03), 0.3], [Vector3(5.4, 0.0, 17.6), Vector2(1.2, 1.0), -0.2],
			[Vector3(-5.5, 0.0, 22.8), Vector2(1.71, 0.75), 0.0],
			[Vector3(-6.35, 0.0, 12.55), Vector2(1.6, 0.8), deg_to_rad(Layout.BOARD_YAW_DEGREES)],
			[Vector3(11.6, 0.0, 5.3), Vector2(2.8, 5.0), 0.0], [Vector3(13.1, 0.0, 2.2), Vector2(0.5, 0.95), 0.0],
			[Vector3(14.45, 0.0, 5.5), Vector2(0.9, 4.0), 0.0], [Vector3(14.4, 0.0, 9.0), Vector2(0.7, 1.2), 0.0],
			[Vector3(10.3, 0.0, 0.85), Vector2(1.6, 0.8), 0.0], [Vector3(14.6, 0.0, 20.8), Vector2(0.61, 1.4), 0.0],
			[Vector3(14.58, 0.0, 22.0), Vector2(0.71, 0.62), 0.0],
			[Vector3(14.75, 0.0, 22.75), Vector2(0.38, 0.41), 0.0],
			[Vector3(14.68, 0.0, 23.62), Vector2(0.51, 1.34), 0.0], [Vector3(14.68, 0.0, 15.8), Vector2(0.6, 5.0), 0.0],
			[Vector3(2.2, 0.0, 27.4), Vector2(2.4, 1.0), 0.0],
			[Vector3(Layout.STAIR_X, 0.0, Layout.MEZZANINE.position.y - Layout.STAIR_RUN + 0.3), Vector2(1.0, 0.8),
					0.0]]:
		var at: Vector3 = spot[0]
		kit.contact(Vector3(at.x, floor_y, at.z), spot[1], float(spot[2]))


## Wear, in one alpha batch: the floor's slab-to-slab variation (soft blotches, a few percent of value),
## grime where the floor meets the walls (40 cm, #2b2f33 at 35 %), the edges of the walkways eaten at the
## crossings, rust and scuffs at the feet of bollards and column guards, and the oil under the truck.
func _build_wear(kit: DepotKit) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 2087
	for column: int in range(5):
		for row: int in range(6):
			var centre := Vector2(-Layout.HALF_WIDTH + 3.0 + column * 6.0, 3.0 + row * 6.0)
			var dark: bool = rng.randf() < 0.6
			var strength: float = rng.randf_range(0.02, 0.05)
			kit.wear_floor(centre, Vector2(6.4, 6.4), Color(0.0, 0.0, 0.0, strength) if dark
					else Color(1.0, 1.0, 1.0, strength * 0.7), 0.0, 0.002)
	var grime := Color("2b2f33")
	grime.a = 0.35
	var depth: float = Layout.DEPTH
	for wall: Array in [[Vector3(-Layout.HALF_WIDTH + 0.04, 0.0, depth * 0.5), PI * 0.5, depth],
			[Vector3(Layout.HALF_WIDTH - 0.04, 0.0, depth * 0.5), -PI * 0.5, depth],
			[Vector3(0.0, 0.0, depth - 0.04), PI, Layout.HALF_WIDTH * 2.0]]:
		var at: Vector3 = wall[0]
		kit.wear(Transform3D(Basis(Vector3.UP, float(wall[1])), Vector3(at.x, Layout.FLOOR_TOP, at.z)),
				Vector2(float(wall[2]), 0.8), grime)
	var bare := Color(0.43, 0.44, 0.44, 0.5)
	for crossing: Vector2 in [Vector2(2.7, Layout.SPINE_Z), Vector2(-2.7, Layout.SPINE_Z),
			Vector2(Layout.FORKLIFT_LANE_X, Layout.SPINE_Z), Vector2(Layout.FORKLIFT_LANE_X, 25.2)]:
		for edge: float in [-1.0, 1.0]:
			var along_x: bool = crossing.x != Layout.FORKLIFT_LANE_X
			var offset := Vector2(0.0, edge * (Layout.WALK_WIDTH * 0.5 - 0.035)) if along_x \
					else Vector2(edge * (Layout.WALK_WIDTH * 0.5 - 0.035), 0.0)
			var span := Vector2(1.6, 0.3) if along_x else Vector2(0.3, 1.6)
			kit.wear_floor(crossing + offset, span, bare, 0.0, 0.018)
	var rust := Color(0.45, 0.22, 0.1, 0.38)
	for at: Vector2 in [Vector2(-3.85, 1.9), Vector2(3.85, 1.9), Vector2(-3.85, 12.9), Vector2(3.85, 12.9)]:
		kit.wear_floor(at, Vector2(0.55, 0.55), rust, 0.0, 0.03)
	for z: float in Layout.PORTAL_FRAMES:
		for side: float in [-1.0, 1.0]:
			kit.wear_floor(Vector2(side * (Layout.HALF_WIDTH - 0.24), z), Vector2(0.8, 1.0),
					Color(0.08, 0.08, 0.08, 0.3), 0.0, 0.03)
	# The oil under the truck (the circulation's oil material).
	var oil := DepotKit.stain(Color(0.02, 0.02, 0.02, 0.32))
	kit.floor_quad(Vector2(2.2, 1.4), Vector3(0.3, Layout.FLOOR_TOP + 0.012, 7.9), oil, 0.2)
