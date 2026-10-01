class_name DepotZones
extends RefCounted
## The depot's subdivisions (N-319): what turns one big shed into a place with
## rooms and levels. All of it is solid boxes from DepotKit for now (the
## modelled kit replaces the primitives later):
##
##   - the control island: the dispatcher's desk at the order board;
##   - the wall line along the east side: the workshop's half wall with the
##     gap its kiosk is reached through, and the wardrobe's partitions with
##     their doorway, each in its zone's colour;
##   - the supplies cage (front left): wire mesh, a service window and counter;
##   - the office on its mezzanine (back right): deck, columns, railings, the
##     stair, and the glazed office on top with the terrace in front of it.
##
## Measurements come from DepotLayout; nothing here is animated or per-frame.

const Layout = preload("res://scripts/gameplay/depot/depot_layout.gd")

## The line the east side's walls stand on (x), their thickness and height.
const WALL_X: float = 9.35
const WALL_THICKNESS: float = 0.12
const WALL_HEIGHT: float = 2.7
const HALF_WALL_HEIGHT: float = 1.1
## The workshop's wall: block #5f6763, a 10 cm red stripe on top, glass from the stripe up to 2.3 m.
const WORKSHOP_BLOCK := Color("5f6763")
const WORKSHOP_STRIPE := Color("b8443a")
const WORKSHOP_GLASS_TOP: float = 2.3
## Where the wardrobe's doorway is (z).
const WARDROBE_DOOR := Vector2(16.2, 19.6)
## The supplies cage's service window (z) and the counter's height.
const CAGE_WINDOW := Vector2(4.25, 6.55)
const CAGE_HEIGHT: float = 2.7
const COUNTER_HEIGHT: float = 1.05
## The Boss's window glass: warm and always lit.
const WINDOW_WARM := Color("ffd9a0")
const WINDOW_WARM_ENERGY: float = 1.3
## One kit cage panel's width.
const CAGE_PANEL: float = 1.22
## The stair's treads.
const STEPS: int = 16
const STAIR_WIDTH: float = 1.0
## One kit railing segment's length.
const RAILING_SEGMENT: float = 1.25

## Supply id -> the prop on the cage's counter that shows it was bought.
var supply_props: Dictionary = {}

var _root: Node3D


func _init(root: Node3D) -> void:
	_root = root


func build(kit: DepotKit) -> void:
	_build_island(kit)
	_build_east_walls(kit)
	_build_cage(kit)
	_build_mezzanine(kit)
	_build_office(kit)
	_build_terrace(kit)


# --- Control island ------------------------------------------------------------


## The dispatcher's desk beside the board, turned like the board: the kit's desk
## (monitor, code reader, clipboard, mug, drawers) with its front to the crew, and
## a stool on the crew's side.
func _build_island(kit: DepotKit) -> void:
	var dark := DepotKit.flat(Color("263238"), 0.6)
	var frame := Transform3D(Basis(Vector3.UP, deg_to_rad(Layout.BOARD_YAW_DEGREES)),
			Vector3(-6.35, Layout.FLOOR_TOP, 12.55))
	kit.model(DepotKit.depot_model("sm_env_depot_dispatch_desk"),
			frame * Transform3D(Basis(Vector3.UP, PI), Vector3.ZERO))
	kit.collider(Vector3(1.6, 1.0, 0.8), frame * Transform3D(Basis.IDENTITY, Vector3(0.0, 0.5, 0.0)))
	# The desk lamp: a small arm and an emissive shade, and its pool on the floor and the desk.
	var lamp_at: Vector3 = frame * Vector3(0.55, 0.0, -0.1)
	var steel := DepotKit.flat(Color("3b4c53"), 0.5, 0.4)
	kit.cylinder(0.07, 0.03, Transform3D(Basis.IDENTITY, lamp_at + Vector3(0.0, 0.74, 0.0)), steel, 10)
	kit.box_xf(Vector3(0.025, 0.4, 0.025), Transform3D(frame.basis, lamp_at + Vector3(0.0, 0.94, 0.0)), steel)
	kit.box_xf(Vector3(0.22, 0.08, 0.16), Transform3D(frame.basis, lamp_at + Vector3(0.0, 1.16, 0.0)),
			DepotKit.glow(Color("ffe2b8"), 1.8))
	kit.floor_quad(Vector2(2.4, 2.4), Vector3(lamp_at.x, Layout.FLOOR_TOP + 0.022, lamp_at.z),
			DepotKit.light_pool(DepotLighting.POOL_COLOUR))
	# A cork board with a clipboard and a few sheets, on arms from the order board's right post.
	var cork_at := Transform3D(Basis(Vector3.UP, deg_to_rad(Layout.BOARD_YAW_DEGREES)),
			Layout.BOARD_AT + Vector3(0.0, Layout.FLOOR_TOP, 0.0))
	var post_x: float = DepotOrderBoard.PANEL_WIDTH * 0.5 + 0.06
	var wood_dark := DepotKit.flat(Color("263238"), 0.6)
	_local_box(kit, cork_at, Vector3(post_x + 0.55, 1.55, 0.03), Vector3(0.98, 0.68, 0.03), wood_dark, false)
	_local_box(kit, cork_at, Vector3(post_x + 0.55, 1.55, 0.05), Vector3(0.9, 0.6, 0.02),
			DepotKit.flat(Color("c9a26b"), 0.9), false)
	for arm_y: float in [1.35, 1.75]:
		_local_box(kit, cork_at, Vector3(post_x + 0.1, arm_y, 0.03), Vector3(0.2, 0.04, 0.04), steel, false)
	_local_box(kit, cork_at, Vector3(post_x + 0.3, 1.6, 0.075), Vector3(0.26, 0.34, 0.012),
			DepotKit.flat(Color("c9a26b"), 0.9), false)
	_local_box(kit, cork_at, Vector3(post_x + 0.3, 1.6, 0.084), Vector3(0.22, 0.3, 0.006),
			DepotKit.flat(Layout.PAPER, 0.9), false)
	for sheet: Array in [[0.62, 1.7, Color("ffc93c")], [0.8, 1.45, Layout.PAPER], [0.8, 1.72, Layout.PAPER]]:
		_local_box(kit, cork_at, Vector3(post_x + float(sheet[0]), float(sheet[1]), 0.07), Vector3(0.2, 0.26, 0.006),
				DepotKit.flat(sheet[2], 0.8), false)
	var stool := Transform3D(frame.basis, frame * Vector3(-0.1, 0.0, 0.85))
	kit.cylinder(0.2, 0.05, Transform3D(stool.basis, stool.origin + Vector3(0.0, 0.62, 0.0)),
			DepotKit.flat(Color("e8772e"), 0.6), 12)
	kit.cylinder(0.03, 0.6, Transform3D(stool.basis, stool.origin + Vector3(0.0, 0.31, 0.0)), dark, 6)
	kit.cylinder(0.2, 0.03, Transform3D(stool.basis, stool.origin + Vector3(0.0, 0.015, 0.0)), dark, 12)


# --- East side: workshop and wardrobe walls -----------------------------------------


## The wall line at x = WALL_X: the workshop's half wall (red cap, steel
## posts, a header over it and a strip curtain over the gap), then the
## wardrobe's full partitions with their doorway (teal band).
func _build_east_walls(kit: DepotKit) -> void:
	var block := DepotKit.detailed(Color("84a09e"), "plaster", 1.4)
	var sheet := DepotKit.ribbed(Color("bcbfbd"), 0.72, 0.6, 0.15)
	var steel := DepotKit.flat(Color("3b4c53"), 0.5, 0.4)
	var dark := DepotKit.flat(Color("263238"), 0.6)
	var red := DepotKit.flat(WORKSHOP_STRIPE, 0.55)
	var workshop_block := DepotKit.detailed(WORKSHOP_BLOCK, "plaster", 1.4)
	var teal := DepotKit.flat(Layout.LOCKERS_TEAL, 0.55)
	var gap: Vector2 = Layout.WORKSHOP_GAP
	var workshop_end: float = Layout.WORKSHOP_FLOOR.end.y
	# Workshop: half wall in two runs, red cap on each.
	for run: Vector2 in [Vector2(Layout.WORKSHOP_FLOOR.position.y, gap.x), Vector2(gap.y, workshop_end)]:
		_wall_run(kit, run, HALF_WALL_HEIGHT, workshop_block, null, red)
		# Opaque block up to 1.1 m, glass from there to 2.3 m: the bench is seen over the wall, not through it.
		kit.box(Vector3(0.03, WORKSHOP_GLASS_TOP - HALF_WALL_HEIGHT - 0.1, run.y - run.x), Vector3(WALL_X,
				Layout.FLOOR_TOP + (WORKSHOP_GLASS_TOP + HALF_WALL_HEIGHT + 0.1) * 0.5, (run.x + run.y) * 0.5),
				DepotKit.glass(Color(0.74, 0.86, 0.9, 0.16)))
	# Posts at every end, a header across the whole workshop front.
	for z: float in [Layout.WORKSHOP_FLOOR.position.y + 0.07, 3.9, gap.x, gap.y, workshop_end - 0.05]:
		_post(kit, z, 0.14, steel)
	var header_from: float = Layout.WORKSHOP_FLOOR.position.y
	kit.box(Vector3(0.16, 0.22, workshop_end - header_from), Vector3(WALL_X, WALL_HEIGHT + 0.06,
			(header_from + workshop_end) * 0.5), red)
	# A strip-curtain valance over the gap, hanging from the header.
	var strip := DepotKit.glass(Color(1.0, 0.78, 0.45, 0.5))
	var strips: int = int((gap.y - gap.x) / 0.2)
	for index: int in range(strips):
		kit.box(Vector3(0.02, 0.7, 0.16), Vector3(WALL_X, WALL_HEIGHT - 0.3, gap.x + 0.1 + index * 0.2), strip)
	# Wardrobe: partition up to the doorway, the doorway, the partition beyond.
	var north_end: float = Layout.MEZZANINE.position.y
	for run: Vector2 in [Vector2(workshop_end + 0.04, WARDROBE_DOOR.x), Vector2(WARDROBE_DOOR.y, north_end)]:
		_wall_run(kit, run, WALL_HEIGHT, block, sheet, teal)
	for z: float in [WARDROBE_DOOR.x, WARDROBE_DOOR.y]:
		_post(kit, z, 0.16, steel)
	kit.box(Vector3(0.16, 0.3, WARDROBE_DOOR.y - WARDROBE_DOOR.x), Vector3(WALL_X, WALL_HEIGHT - 0.1,
			(WARDROBE_DOOR.x + WARDROBE_DOOR.y) * 0.5), teal)
	# The wardrobe is shut off from the workshop by a wall across its north side.
	kit.box(Vector3(Layout.HALF_WIDTH - WALL_X, WALL_HEIGHT, WALL_THICKNESS),
			Vector3((WALL_X + Layout.HALF_WIDTH) * 0.5, WALL_HEIGHT * 0.5 + Layout.FLOOR_TOP,
					workshop_end + 0.1), block, true)
	kit.box(Vector3(Layout.HALF_WIDTH - WALL_X, 0.1, WALL_THICKNESS + 0.04),
			Vector3((WALL_X + Layout.HALF_WIDTH) * 0.5, WALL_HEIGHT + 0.02, workshop_end + 0.1), dark)


## A steel post of the wall line at `z`, `width` square, a little over the wall's height.
func _post(kit: DepotKit, z: float, width: float, material: Material) -> void:
	var height: float = WALL_HEIGHT + 0.05
	kit.box(Vector3(width, height, width), Vector3(WALL_X, height * 0.5 + Layout.FLOOR_TOP, z), material, true)


## One run of the wall line between z = `run.x` and `run.y`: a block plinth,
## optionally sheet above it to `height`, and a colour band as its cap.
func _wall_run(kit: DepotKit, run: Vector2, height: float, lower: Material, upper: Material, band: Material) -> void:
	var length: float = run.y - run.x
	var centre: float = (run.x + run.y) * 0.5
	var low: float = minf(HALF_WALL_HEIGHT, height)
	kit.box(Vector3(WALL_THICKNESS, low, length), Vector3(WALL_X, Layout.FLOOR_TOP + low * 0.5, centre), lower, true)
	if upper != null and height > low:
		kit.box(Vector3(WALL_THICKNESS, height - low, length),
				Vector3(WALL_X, Layout.FLOOR_TOP + low + (height - low) * 0.5, centre), upper, true)
	kit.box(Vector3(WALL_THICKNESS + 0.06, 0.1, length + 0.02), Vector3(WALL_X, Layout.FLOOR_TOP + low, centre), band)
	if upper != null:
		kit.box(Vector3(WALL_THICKNESS + 0.04, 0.08, length + 0.02), Vector3(WALL_X, Layout.FLOOR_TOP + height, centre),
				DepotKit.flat(Color("263238"), 0.6))


# --- Supplies cage ---------------------------------------------------------------


## The supplies cage: a wire-mesh room with a counter window on the side that
## faces the truck bay, shelves of what it sells along the wall, the clerk's
## side lit warm. Its window is where the shop station stands.
func _build_cage(kit: DepotKit) -> void:
	var cage: Rect2 = Layout.SHOP_CAGE
	var mesh := DepotKit.wire_mesh(Color("b4bfc4"), 0.1)
	var steel := DepotKit.flat(Color("3b4c53"), 0.5, 0.4)
	var dark := DepotKit.flat(Color("263238"), 0.7)
	var shelf := DepotKit.flat(Color("59656a"), 0.5, 0.4)
	var board := DepotKit.flat(Color("263238"), 0.5, 0.2)
	var east: float = cage.end.x
	var south: float = cage.position.y
	var north: float = cage.end.y
	var west: float = cage.position.x
	var height: float = CAGE_HEIGHT
	# Floor: a dark rubber pad marks the room.
	kit.box(Vector3(cage.size.x, 0.008, cage.size.y), Vector3(cage.get_center().x, Layout.FLOOR_TOP + 0.004,
			cage.get_center().y), DepotKit.detailed(Color("2a2c30"), "plaster", 0.9, 0.9))
	# East face: kit panels (diamond mesh in a tubular frame) to either side of the service
	# window, and the kit's window with its counter and sliding grille between them.
	var window_width: float = CAGE_WINDOW.y - CAGE_WINDOW.x
	var window_centre: float = (CAGE_WINDOW.x + CAGE_WINDOW.y) * 0.5
	for run: Vector2 in [Vector2(south, CAGE_WINDOW.x), Vector2(CAGE_WINDOW.y, north)]:
		_cage_run(kit, Vector3(east, Layout.FLOOR_TOP, run.x), Vector3(east, Layout.FLOOR_TOP, run.y), -PI * 0.5)
		kit.collider(Vector3(0.1, height, run.y - run.x), Transform3D(Basis.IDENTITY,
				Vector3(east, Layout.FLOOR_TOP + height * 0.5, (run.x + run.y) * 0.5)))
	kit.model(DepotKit.depot_model("sm_env_depot_cage_window"), Transform3D(Basis(Vector3.UP, -PI * 0.5),
			Vector3(east, Layout.FLOOR_TOP, window_centre)))
	kit.collider(Vector3(0.6, COUNTER_HEIGHT, window_width), Transform3D(Basis.IDENTITY,
			Vector3(east + 0.2, Layout.FLOOR_TOP + COUNTER_HEIGHT * 0.5, window_centre)))
	# South and north faces, the north one with the staff door's gap.
	_cage_run(kit, Vector3(west, Layout.FLOOR_TOP, south), Vector3(east, Layout.FLOOR_TOP, south), 0.0)
	kit.collider(Vector3(cage.size.x, height, 0.1), Transform3D(Basis.IDENTITY,
			Vector3(cage.get_center().x, Layout.FLOOR_TOP + height * 0.5, south)))
	var door := Vector2(west + 0.7, west + 1.7)
	for run: Vector2 in [Vector2(west, door.x), Vector2(door.y, east)]:
		_cage_run(kit, Vector3(run.x, Layout.FLOOR_TOP, north), Vector3(run.y, Layout.FLOOR_TOP, north), PI)
		kit.collider(Vector3(run.y - run.x, height, 0.1), Transform3D(Basis.IDENTITY,
				Vector3((run.x + run.y) * 0.5, Layout.FLOOR_TOP + height * 0.5, north)))
	# Steel posts at the corners and the window's mullions, a top frame and a kick plate.
	for corner: Vector2 in [Vector2(east, south), Vector2(east, north), Vector2(west + 0.05, south),
			Vector2(west + 0.05, north), Vector2(door.x, north), Vector2(door.y, north)]:
		kit.box(Vector3(0.1, height, 0.1), Vector3(corner.x, Layout.FLOOR_TOP + height * 0.5, corner.y), steel, true)
	kit.box(Vector3(0.08, 0.1, cage.size.y), Vector3(east, Layout.FLOOR_TOP + height, cage.get_center().y), steel)
	kit.box(Vector3(cage.size.x, 0.1, 0.08), Vector3(cage.get_center().x, Layout.FLOOR_TOP + height, south), steel)
	kit.box(Vector3(cage.size.x, 0.1, 0.08), Vector3(cage.get_center().x, Layout.FLOOR_TOP + height, north), steel)
	kit.box(Vector3(cage.size.x, 0.06, cage.size.y), Vector3(cage.get_center().x, Layout.FLOOR_TOP + height + 0.03,
			cage.get_center().y), mesh)
	kit.box(Vector3(0.04, 0.25, cage.size.y), Vector3(east, Layout.FLOOR_TOP + 0.125, cage.get_center().y), dark)
	# A strip light under the roof, and its glow on the floor around the window.
	kit.box(Vector3(0.12, 0.04, 5.2), Vector3(-12.2, Layout.FLOOR_TOP + height - 0.06, cage.get_center().y),
			DepotKit.glow(Color("fff1d6"), 2.0))
	# (The same material as the lamps' pools, so it shares their batch: two quads stacked are twice as bright.)
	var pool := DepotKit.light_pool(DepotLighting.POOL_COLOUR)
	for size: Vector2 in [Vector2(6.0, 6.4), Vector2(3.8, 4.4)]:
		kit.floor_quad(size, Vector3(-11.0, Layout.FLOOR_TOP + 0.022, window_centre), pool)
	kit.floor_quad(Vector2(3.4, 4.0), Vector3(-8.3, Layout.FLOOR_TOP + 0.022, window_centre), pool)
	# What it sells, on shelves along the west wall: bubble wrap, tape, foam.
	var shelf_x: float = west + 0.45
	kit.box(Vector3(0.5, 2.2, cage.size.y - 1.6), Vector3(shelf_x, 1.1 + Layout.FLOOR_TOP, cage.get_center().y), shelf,
			true)
	for level: int in range(3):
		kit.box(Vector3(0.55, 0.04, cage.size.y - 1.6), Vector3(shelf_x + 0.02, 0.45 + level * 0.7,
				cage.get_center().y), board)
		var base_y: float = 0.47 + level * 0.7
		for index: int in range(9):
			var z: float = south + 1.0 + index * 0.62
			var at := Vector3(shelf_x + 0.22, base_y, z)
			match (index + level) % 3:
				0:
					kit.model(DepotKit.depot_model("sm_env_depot_supply_padding"), Transform3D(Basis(Vector3.UP,
							-PI * 0.5), at))
				1:
					kit.model(DepotKit.depot_model("sm_env_depot_shop_tape_roll"),
							Transform3D(Basis(Vector3.UP, -PI * 0.5 + (index - 4) * 0.06), at))
				_:
					var foam: String = "sm_env_depot_shop_foam_blue" if level == 1 else "sm_env_depot_shop_foam_orange"
					kit.model(DepotKit.depot_model(foam), Transform3D(Basis(Vector3.UP, -PI * 0.5), at))
	# Boxes between the small supplies, so the shelves read as full.
	for level: int in range(3):
		for index: int in range(8):
			var box_path: String = Layout.CARGO_BOXES[(index + level) % Layout.CARGO_BOXES.size()]
			var at := Vector3(shelf_x + 0.1, 0.47 + level * 0.7, south + 1.31 + index * 0.62)
			kit.model(box_path, Transform3D(Basis(Vector3.UP, -PI * 0.5 + 0.1 * index).scaled(Vector3.ONE * 0.34), at))
	# The window's sign: the kit's board says what it is, with the box pictogram.
	var board_x: float = east + 0.045
	var board_y: float = Layout.FLOOR_TOP + 2.82
	DepotLabels.pictogram(kit, DepotLabels.ICON_BOX, Transform3D(Basis(Vector3.UP, PI * 0.5),
			Vector3(board_x, board_y, window_centre - 0.45)), 0.12, Layout.INK)
	var window_label := DepotLabels.text(_root, tr("WORLD_DEPOT_WINDOW"), Vector3(board_x + 0.003, board_y,
			window_centre + 0.08), PI * 0.5, 30, Layout.INK, Layout.DISPLAY_FONT, 0.0036, 0)
	DepotLabels.fit_label(window_label, 0.78)
	# Stock waiting to go on the shelves, on a pallet by the north wall.
	kit.model_grounded(Layout.PALLET, Transform3D(Basis(Vector3.UP, 0.1), Vector3(-12.4, Layout.FLOOR_TOP,
			north - 1.1)))
	for index: int in range(4):
		var box_path: String = Layout.CARGO_BOXES[index % Layout.CARGO_BOXES.size()]
		kit.model(box_path, Transform3D(Basis(Vector3.UP, 0.25 * index).scaled(Vector3.ONE * 0.6),
				Vector3(-12.4 + (index % 2 - 0.5) * 0.5, Layout.FLOOR_TOP + 0.36 + (index / 2) * 0.3,
						north - 1.1 + (index % 2) * 0.1)))
	kit.collider(Vector3(1.2, 0.9, 0.9), Transform3D(Basis.IDENTITY, Vector3(-12.4, 0.5, north - 1.1)))
	# On the counter: the till, a service bell, and the supplies once bought.
	var counter_top: float = Layout.FLOOR_TOP + COUNTER_HEIGHT
	kit.box(Vector3(0.3, 0.2, 0.34), Vector3(east + 0.3, counter_top + 0.15, window_centre - 0.75),
			DepotKit.flat(Color("2a3439"), 0.5))
	kit.box(Vector3(0.02, 0.12, 0.26), Vector3(east + 0.14, counter_top + 0.22, window_centre - 0.75),
			DepotKit.glow(Color("2dd4a3"), 0.8))
	var bell := SphereMesh.new()
	bell.radius = 0.07
	bell.height = 0.07
	bell.is_hemisphere = true
	bell.radial_segments = 10
	bell.rings = 3
	kit.add_mesh(bell, Transform3D(Basis.IDENTITY, Vector3(east + 0.32, counter_top + 0.05, window_centre + 0.85)),
			DepotKit.flat(Color("c9a26b"), 0.3, 0.8))
	var supplies: Array = [
		[&"padding", Vector3(east + 0.2, counter_top + 0.05, window_centre - 0.05), "sm_env_depot_supply_padding"],
		[&"insurance", Vector3(east + 0.2, counter_top + 0.05, window_centre + 0.45), "sm_env_depot_supply_insurance"],
	]
	for supply: Array in supplies:
		var prop := MeshInstance3D.new()
		prop.name = "Supply_%s" % supply[0]
		prop.mesh = DepotKit.merged_mesh(DepotKit.depot_model(supply[2]))
		prop.position = supply[1]
		prop.rotation.y = -PI * 0.5
		prop.visible = false
		_root.add_child(prop)
		supply_props[supply[0]] = prop
	DepotLabels.hanging_sign(_root, kit, tr("WORLD_DEPOT_SUPPLIES"), Vector3(east + 0.3, 3.6, window_centre), PI * 0.5,
			Layout.SHOP_PURPLE, Layout.CEILING - 0.25, Layout.PAPER, DepotHall.SIGN_SIZE,
			DepotLabels.ICON_BOX)


## A run of kit cage panels from `from` to `to` (floor level), the panels' fronts turned
## `yaw`, stretched a little so a whole number of them fills the run.
func _cage_run(kit: DepotKit, from: Vector3, to: Vector3, yaw: float) -> void:
	var length: float = from.distance_to(to)
	var count: int = maxi(roundi(length / CAGE_PANEL), 1)
	var step: float = length / count
	var direction: Vector3 = (to - from) / length
	var panel: String = DepotKit.depot_model("sm_env_depot_cage_panel")
	for index: int in range(count):
		var at: Vector3 = from + direction * (step * (index + 0.5))
		var stretch := Basis.from_scale(Vector3(step / CAGE_PANEL, 1.0, 1.0))
		kit.model(panel, Transform3D(Basis(Vector3.UP, yaw) * stretch, at))


# --- Mezzanine and office ---------------------------------------------------------


## The office's deck: a steel platform on columns, a yellow-and-black edge,
## railings on its open sides and the stair up to it from the hall.
func _build_mezzanine(kit: DepotKit) -> void:
	var m: Rect2 = Layout.MEZZANINE
	var top: float = Layout.MEZZANINE_HEIGHT
	var steel := DepotKit.flat(Color("3b4c53"), 0.5, 0.4)
	var dark := DepotKit.flat(Color("263238"), 0.6)
	var deck := DepotKit.detailed(Color("6f7b80"), "plaster", 1.2, 0.7)
	var centre: Vector2 = m.get_center()
	kit.box(Vector3(m.size.x, 0.3, m.size.y), Vector3(centre.x, top - 0.15, centre.y), deck, true)
	# Fascia beams and the hazard edge along the two open sides.
	kit.box(Vector3(m.size.x + 0.1, 0.4, 0.1), Vector3(centre.x, top - 0.2, m.position.y - 0.04), dark)
	kit.box(Vector3(0.1, 0.4, m.size.y), Vector3(m.position.x - 0.04, top - 0.2, centre.y), dark)
	var hazard := DepotKit.stripes(Layout.YELLOW, Color("2b3136"), 0.2)
	kit.box(Vector3(m.size.x, 0.012, 0.22), Vector3(centre.x, top + 0.006, m.position.y + 0.11), hazard)
	kit.box(Vector3(0.22, 0.012, m.size.y), Vector3(m.position.x + 0.11, top + 0.006, centre.y), hazard)
	# Columns under the open edges.
	for at: Vector2 in [Vector2(m.position.x + 0.1, m.position.y + 0.15), Vector2(11.3, m.position.y + 0.15),
			Vector2(14.3, m.position.y + 0.15), Vector2(m.position.x + 0.1, 28.1), Vector2(m.position.x + 0.1, 31.7)]:
		kit.box(Vector3(0.18, top - 0.3, 0.18), Vector3(at.x, Layout.FLOOR_TOP + (top - 0.3) * 0.5, at.y), steel, true)
	# Railings: the front edge right of the stair's head, and the west edge.
	_railing(kit, Vector3(Layout.STAIR_X + STAIR_WIDTH * 0.5 + 0.05, top, m.position.y + 0.05),
			Vector3(m.end.x - 0.05, top, m.position.y + 0.05))
	_railing(kit, Vector3(m.position.x + 0.05, top, m.position.y + 0.05),
			Vector3(Layout.STAIR_X - STAIR_WIDTH * 0.5 - 0.05, top, m.position.y + 0.05))
	_railing(kit, Vector3(m.position.x + 0.05, top, m.position.y + 0.05),
			Vector3(m.position.x + 0.05, top, m.end.y - 0.05))
	_build_stair(kit)


## A railing along X or Z from `from` to `to` (floor level y): the kit's 1.2 m segments
## (posts, top and mid rail, toe board) stretched to fill the run, a closing post, and
## one solid box to keep people on the deck.
func _railing(kit: DepotKit, from: Vector3, to: Vector3) -> void:
	var length: float = from.distance_to(to)
	var direction: Vector3 = (to - from) / length
	var count: int = maxi(roundi(length / RAILING_SEGMENT), 1)
	var step: float = length / count
	var yaw: float = atan2(-direction.z, direction.x)
	var segment: String = DepotKit.depot_model("sm_env_depot_railing_segment")
	for index: int in range(count):
		var at: Vector3 = from + direction * (step * (index + 0.5))
		var stretch := Basis.from_scale(Vector3(step / RAILING_SEGMENT, 1.0, 1.0))
		kit.model(segment, Transform3D(Basis(Vector3.UP, yaw) * stretch, at))
	kit.model(DepotKit.depot_model("sm_env_depot_railing_post"), Transform3D(Basis(Vector3.UP, yaw), to))
	var along_x: bool = absf(direction.x) > 0.5
	var centre: Vector3 = (from + to) * 0.5
	var fence := Vector3(length, 1.05, 0.1) if along_x else Vector3(0.1, 1.05, length)
	kit.collider(fence, Transform3D(Basis.IDENTITY, centre + Vector3(0.0, 0.525, 0.0)))


## Open steel stair up the hall's east side to the deck's front edge: the kit's stair
## (treads on two stringers with handrails). Walkable through one ramp collider (its
## slope follows the treads' noses), so nobody has to climb boxes.
func _build_stair(kit: DepotKit) -> void:
	var top: float = Layout.MEZZANINE_HEIGHT
	var z_foot: float = Layout.MEZZANINE.position.y - Layout.STAIR_RUN
	var x: float = Layout.STAIR_X
	kit.model(DepotKit.depot_model("sm_env_depot_stair"), Transform3D(Basis.IDENTITY,
			Vector3(x, Layout.FLOOR_TOP, z_foot)))
	var slope: float = atan2(top, Layout.STAIR_RUN)
	var length: float = sqrt(top * top + Layout.STAIR_RUN * Layout.STAIR_RUN)
	# The slope's frame: X along the stair's width, Y up its normal, Z along it (up-hill toward +Z).
	var basis := Basis(Vector3.RIGHT, -slope)
	var middle := Vector3(x, Layout.FLOOR_TOP + top * 0.5, z_foot + Layout.STAIR_RUN * 0.5)
	for side: float in [-1.0, 1.0]:
		# Keeps people on the ramp.
		kit.collider(Vector3(0.1, 1.2, length), Transform3D(basis,
				middle + Vector3(side * (STAIR_WIDTH * 0.5 + 0.05), 0.5, 0.0)))
	# The walkable ramp, its top surface along the noses of the treads.
	var normal: Vector3 = basis * Vector3.UP
	kit.collider(Vector3(STAIR_WIDTH, 0.12, length), Transform3D(basis, middle - normal * 0.06))


## The office on the deck: a glazed room with its door on the west gangway,
## lit warm from inside, blinds half drawn over the window to the hall. The
## Jefe's desk, dispatch computer, cork board and filing cabinet as before.
func _build_office(kit: DepotKit) -> void:
	var frame := DepotKit.flat(Color("263238"), 0.6, 0.3)
	var panel := DepotKit.detailed(Color("d5d9d2"), "plaster", 1.6)
	# The Boss's window is always lit, warm: after the truck and the board it is the third brightest thing
	# in the hall, whatever the weather (one emissive batch).
	var glass := DepotKit.glow(WINDOW_WARM, WINDOW_WARM_ENERGY)
	var lift: float = Layout.MEZZANINE_HEIGHT
	var x0: float = 8.6
	var z0: float = 27.8
	var x1: float = Layout.HALF_WIDTH
	var depth_end: float = Layout.DEPTH
	var wall_depth: float = depth_end - z0
	var side_width: float = x1 - x0
	# Front wall (toward -Z) and west wall (toward -X): solid below, glazed above.
	kit.box(Vector3(side_width, 1.0, 0.12), Vector3((x0 + x1) * 0.5, lift + 0.5, z0), panel, true)
	kit.box(Vector3(side_width, 1.4, 0.04), Vector3((x0 + x1) * 0.5, lift + 1.7, z0), glass, true)
	kit.box(Vector3(side_width, 0.6, 0.12), Vector3((x0 + x1) * 0.5, lift + 2.7, z0), panel, true)
	var west_len: float = wall_depth - 1.3
	kit.box(Vector3(0.12, 1.0, west_len), Vector3(x0, lift + 0.5, z0 + west_len * 0.5), panel, true)
	kit.box(Vector3(0.04, 1.4, west_len), Vector3(x0, lift + 1.7, z0 + west_len * 0.5), glass, true)
	kit.box(Vector3(0.12, 0.6, wall_depth), Vector3(x0, lift + 2.7, z0 + wall_depth * 0.5), panel)
	kit.box(Vector3(0.12, 2.4, 0.12), Vector3(x0, lift + 1.2, depth_end - 1.3), frame)
	var door_z: float = depth_end - 0.8
	kit.box(Vector3(0.05, 2.1, 0.9), Vector3(x0 - 0.02, lift + 1.05, door_z), DepotKit.flat(Color("2f7a64"), 0.6))
	for z: float in [depth_end - 1.29, depth_end - 0.31]:
		kit.box(Vector3(0.14, 2.2, 0.08), Vector3(x0 - 0.02, lift + 1.1, z), frame)
	kit.box(Vector3(0.14, 0.1, 1.06), Vector3(x0 - 0.02, lift + 2.2, door_z), frame)
	kit.box(Vector3(0.05, 0.04, 0.16), Vector3(x0 - 0.07, lift + 1.05, depth_end - 1.1), DepotKit.flat(Color("c9ced0"),
			0.3, 0.8))
	# Roof and mullions.
	kit.box(Vector3(side_width + 0.1, 0.1, wall_depth + 0.1), Vector3((x0 + x1) * 0.5, lift + 3.05,
			(z0 + depth_end) * 0.5), frame)
	for x: float in [x0, 11.0, 13.2]:
		kit.box(Vector3(0.06, 1.44, 0.14), Vector3(x, lift + 1.7, z0), frame)
	# Blinds half drawn over the window's west half (their slats are the kit's), and the warm light inside.
	for x: float in [9.25, 10.5]:
		kit.model(DepotKit.depot_model("sm_env_depot_office_blind"), Transform3D(Basis.IDENTITY,
				Vector3(x, lift + 1.3, z0 + 0.15)))
	# A warm pool on the terrace in front of the window (shares the lamps' pool batch).
	kit.floor_quad(Vector2(3.0, 2.0), Vector3(11.4, lift + 0.02, z0 - 1.1),
			DepotKit.light_pool(DepotLighting.POOL_COLOUR))
	var lamp := DepotKit.glow(Color("fff1d6"), 2.2)
	for z: float in [29.0, 30.9]:
		kit.box(Vector3(3.4, 0.03, 0.14), Vector3(11.8, lift + 2.98, z), lamp)
	# Desk 0.8 m behind the glass with the dispatch computer, its back to the hall: a silhouette against
	# the lit window as seen from below, and the desk lamp that is the room's other light.
	var wood := DepotKit.detailed(Color("b08a5a"), "wood_planks", 1.0)
	var desk_z: float = z0 + 1.2
	kit.box(Vector3(2.0, 0.06, 0.8), Vector3(11.6, lift + 0.76, desk_z), wood, true)
	for x: float in [10.7, 12.5]:
		kit.box(Vector3(0.06, 0.74, 0.7), Vector3(x, lift + 0.38, desk_z), frame)
	kit.box(Vector3(0.6, 0.38, 0.05), Vector3(11.4, lift + 1.1, desk_z - 0.12), frame)
	kit.box(Vector3(0.54, 0.32, 0.02), Vector3(11.4, lift + 1.1, desk_z - 0.095), DepotKit.glow(Color("8fd3e8"), 0.9))
	kit.box(Vector3(0.45, 0.02, 0.15), Vector3(11.4, lift + 0.8, desk_z + 0.2), frame)
	kit.cylinder(0.08, 0.03, Transform3D(Basis.IDENTITY, Vector3(12.3, lift + 0.805, desk_z)), frame, 10)
	kit.box(Vector3(0.03, 0.34, 0.03), Vector3(12.3, lift + 0.98, desk_z), frame)
	kit.box(Vector3(0.2, 0.1, 0.14), Vector3(12.3, lift + 1.17, desk_z - 0.04), DepotKit.glow(Color("ffe2b8"), 1.8))
	kit.box(Vector3(0.5, 1.3, 0.6), Vector3(14.5, lift + 0.65, 29.2), DepotKit.flat(Color("8a9499"), 0.4, 0.5), true)
	kit.box(Vector3(0.04, 0.9, 1.4), Vector3(14.95, lift + 1.8, 30.6), DepotKit.flat(Color("c9a26b"), 0.9))
	for index: int in range(5):
		kit.box(Vector3(0.01, 0.22, 0.18), Vector3(14.92, lift + 1.65 + (index % 2) * 0.35, 30.1 + index * 0.24),
				DepotKit.flat(Layout.PAPER, 0.9))
	var sign_at := Vector3(11.3, 4.75, Layout.MEZZANINE.position.y - 1.0)
	DepotLabels.hanging_sign(_root, kit, tr("WORLD_DEPOT_OFFICE"), sign_at, PI, Layout.OFFICE_ORANGE,
			Layout.CEILING - 0.25, Layout.PAPER, DepotHall.SIGN_SIZE, DepotLabels.ICON_PHONE)


## The terrace in front of the office (a bench, crates, a cup) and what hides
## under the deck: pallets in the half dark.
func _build_terrace(kit: DepotKit) -> void:
	var lift: float = Layout.MEZZANINE_HEIGHT
	kit.model_grounded("res://assets/models/environment/props/sm_env_prop_bench.glb",
			Transform3D(Basis(Vector3.UP, PI), Vector3(13.2, lift, 27.3)))
	var crate_at := Transform3D(Basis(Vector3.UP, 0.3).scaled(Vector3.ONE * 0.8), Vector3(10.4, lift, 26.9))
	kit.model_grounded(Layout.CRATE, crate_at)
	var box_at := Transform3D(Basis(Vector3.UP, -0.2).scaled(Vector3.ONE * 0.7), Vector3(9.3, lift, 27.2))
	kit.model_grounded(Layout.CARGO_BOXES[0], box_at)
	# Under the deck: a pair of pallets with loads, and a hand-truck's worth of boxes.
	var rng := RandomNumberGenerator.new()
	rng.seed = 6042
	var film := DepotKit.glass(Color(0.85, 0.9, 0.95, 0.35))
	for spot: Vector3 in [Vector3(11.6, Layout.FLOOR_TOP, 26.4), Vector3(13.6, Layout.FLOOR_TOP, 26.4),
			Vector3(11.8, Layout.FLOOR_TOP, 29.9), Vector3(13.8, Layout.FLOOR_TOP, 29.6)]:
		_stock_pallet(kit, spot, rng, film)
		kit.collider(Vector3(1.25, 1.5, 0.9), Transform3D(Basis.IDENTITY, spot + Vector3(0.0, 0.75, 0.0)))
	# Two fixtures under the deck so it is half dark, not black.
	for z: float in [26.5, 29.8]:
		kit.box(Vector3(1.4, 0.04, 0.12), Vector3(11.4, Layout.MEZZANINE_HEIGHT - 0.33, z),
				DepotKit.glow(Color("eaf6ff"), 1.6))


## A pallet with a load on it, for the space under the deck.
func _stock_pallet(kit: DepotKit, base: Vector3, rng: RandomNumberGenerator, film: Material) -> void:
	var yaw: float = PI * 0.5 + rng.randf_range(-0.06, 0.06)
	kit.model_grounded(Layout.PALLET, Transform3D(Basis(Vector3.UP, yaw), base))
	var top: Vector3 = base + Vector3(0.0, 0.1, 0.0)
	var box_path: String = Layout.CARGO_BOXES[rng.randi() % Layout.CARGO_BOXES.size()]
	var bounds: AABB = kit.model_bounds(box_path)
	var scale: float = clampf(0.55 / maxf(bounds.size.x, bounds.size.z), 0.4, 1.0)
	var height: float = bounds.size.y * scale
	for layer: int in range(2):
		for ix: int in range(2):
			for iz: int in range(2):
				var offset := Vector3((ix - 0.5) * 0.6, layer * height, (iz - 0.5) * 0.5)
				var turn: float = rng.randf_range(-0.08, 0.08)
				kit.model(box_path, Transform3D(Basis(Vector3.UP, turn).scaled(Vector3.ONE * scale),
						top + offset.rotated(Vector3.UP, yaw)))
	kit.box(Vector3(1.24, height * 2.0 + 0.04, 1.04), top + Vector3(0.0, height, 0.0), film, false, yaw)


# --- Helpers ---------------------------------------------------------------------


## A box placed in `frame`'s space (a desk turned like the board).
func _local_box(kit: DepotKit, frame: Transform3D, at: Vector3, size: Vector3, material: Material, solid: bool) -> void:
	kit.box_xf(size, frame * Transform3D(Basis.IDENTITY, at), material, solid)
