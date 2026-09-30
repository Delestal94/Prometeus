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
## Where the wardrobe's doorway is (z).
const WARDROBE_DOOR := Vector2(16.2, 19.6)
## The supplies cage's service window (z) and the counter's height.
const CAGE_WINDOW := Vector2(4.3, 6.5)
const CAGE_HEIGHT: float = 2.7
const COUNTER_HEIGHT: float = 1.05
## The stair's treads.
const STEPS: int = 16
const STAIR_WIDTH: float = 1.0

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


## The dispatcher's desk beside the board, turned like the board: a monitor,
## a code reader, a clipboard and a stool.
func _build_island(kit: DepotKit) -> void:
	var wood := DepotKit.detailed(Color("b08a5a"), "wood_planks", 1.0)
	var dark := DepotKit.flat(Color("263238"), 0.6)
	var steel := DepotKit.flat(Color("8a9499"), 0.4, 0.6)
	var frame := Transform3D(Basis(Vector3.UP, deg_to_rad(Layout.BOARD_YAW_DEGREES)),
			Vector3(-6.35, Layout.FLOOR_TOP, 12.55))
	# Desk: top, two side panels, a drawer block.
	_local_box(kit, frame, Vector3(0.0, 0.92, 0.0), Vector3(1.5, 0.06, 0.66), wood, true)
	for x: float in [-0.68, 0.68]:
		_local_box(kit, frame, Vector3(x, 0.45, 0.0), Vector3(0.06, 0.9, 0.6), dark, false)
	_local_box(kit, frame, Vector3(0.0, 0.5, -0.27), Vector3(1.3, 0.8, 0.04), dark, false)
	_local_box(kit, frame, Vector3(0.45, 0.6, 0.0), Vector3(0.4, 0.55, 0.56), DepotKit.flat(Color("59656a"), 0.5, 0.4),
			false)
	# The monitor, facing the dispatcher (toward the board), its screen lit.
	_local_box(kit, frame, Vector3(-0.3, 1.18, -0.12), Vector3(0.56, 0.36, 0.04), dark, false)
	_local_box(kit, frame, Vector3(-0.3, 1.18, -0.1), Vector3(0.5, 0.3, 0.012), DepotKit.glow(Color("8fd3e8"), 0.9),
			false)
	_local_box(kit, frame, Vector3(-0.3, 1.0, -0.12), Vector3(0.06, 0.12, 0.05), dark, false)
	# Code reader, clipboard and a cup.
	_local_box(kit, frame, Vector3(0.25, 0.97, 0.12), Vector3(0.06, 0.05, 0.14), steel, false)
	_local_box(kit, frame, Vector3(0.25, 0.975, 0.12), Vector3(0.02, 0.01, 0.1), DepotKit.glow(Color("ff5e5b"), 1.2),
			false)
	_local_box(kit, frame, Vector3(-0.05, 0.955, 0.16), Vector3(0.22, 0.02, 0.3), DepotKit.flat(Color("c9a26b"), 0.9),
			false)
	_local_box(kit, frame, Vector3(-0.05, 0.968, 0.16), Vector3(0.19, 0.004, 0.26), DepotKit.flat(Layout.PAPER, 0.9),
			false)
	# A stool on the crew's side.
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
	var red := DepotKit.flat(Layout.WORKSHOP_RED, 0.55)
	var teal := DepotKit.flat(Layout.LOCKERS_TEAL, 0.55)
	var gap: Vector2 = Layout.WORKSHOP_GAP
	var workshop_end: float = Layout.WORKSHOP_FLOOR.end.y
	# Workshop: half wall in two runs, red cap on each.
	for run: Vector2 in [Vector2(Layout.WORKSHOP_FLOOR.position.y, gap.x), Vector2(gap.y, workshop_end)]:
		_wall_run(kit, run, HALF_WALL_HEIGHT, block, null, red)
	# Posts at every end, a header across the whole workshop front.
	for z: float in [Layout.WORKSHOP_FLOOR.position.y + 0.07, 3.9, gap.x, gap.y, workshop_end - 0.05]:
		_post(kit, z, 0.14, steel)
	var header_from: float = Layout.WORKSHOP_FLOOR.position.y
	kit.box(Vector3(0.16, 0.22, workshop_end - header_from), Vector3(WALL_X, WALL_HEIGHT + 0.06,
			(header_from + workshop_end) * 0.5), red)
	# A strip-curtain valance over the gap, hanging from the header.
	var strip := DepotKit.glass(Color(0.78, 0.86, 0.8, 0.5))
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
	var purple := DepotKit.flat(Layout.SHOP_PURPLE, 0.55)
	var wood := DepotKit.detailed(Color("b08a5a"), "wood_planks", 1.0)
	var shelf := DepotKit.flat(Color("59656a"), 0.5, 0.4)
	var board := DepotKit.flat(Color("263238"), 0.5, 0.2)
	var east: float = cage.end.x
	var south: float = cage.position.y
	var north: float = cage.end.y
	var west: float = cage.position.x
	var height: float = CAGE_HEIGHT
	# Floor: a dark rubber pad marks the room.
	kit.box(Vector3(cage.size.x, 0.008, cage.size.y), Vector3(cage.get_center().x, Layout.FLOOR_TOP + 0.004,
			cage.get_center().y), DepotKit.detailed(Color("4a4760"), "plaster", 0.9, 0.9))
	# East face: mesh to either side of the window, the counter front below it
	# and a purple header above it.
	for run: Vector2 in [Vector2(south, CAGE_WINDOW.x), Vector2(CAGE_WINDOW.y, north)]:
		var face := Vector3(east, Layout.FLOOR_TOP + height * 0.5, (run.x + run.y) * 0.5)
		kit.box(Vector3(0.03, height, run.y - run.x), face, mesh, true)
	var window_width: float = CAGE_WINDOW.y - CAGE_WINDOW.x
	var window_centre: float = (CAGE_WINDOW.x + CAGE_WINDOW.y) * 0.5
	kit.box(Vector3(0.06, COUNTER_HEIGHT, window_width), Vector3(east, Layout.FLOOR_TOP + COUNTER_HEIGHT * 0.5,
			window_centre), wood, true)
	kit.box(Vector3(0.55, 0.05, window_width + 0.3), Vector3(east + 0.22, Layout.FLOOR_TOP + COUNTER_HEIGHT + 0.025,
			window_centre), board, true)
	kit.box(Vector3(0.1, 0.5, window_width + 0.3), Vector3(east, Layout.FLOOR_TOP + height - 0.25, window_centre),
			purple)
	# The window's frame.
	var frame_y: float = Layout.FLOOR_TOP + (height + COUNTER_HEIGHT) * 0.5
	for z: float in [CAGE_WINDOW.x, CAGE_WINDOW.y]:
		kit.box(Vector3(0.1, height - COUNTER_HEIGHT, 0.08), Vector3(east, frame_y, z), steel)
	# South and north faces, the north one with the staff door's gap.
	kit.box(Vector3(cage.size.x, height, 0.03), Vector3(cage.get_center().x, Layout.FLOOR_TOP + height * 0.5, south),
			mesh, true)
	var door := Vector2(west + 0.7, west + 1.7)
	for run: Vector2 in [Vector2(west, door.x), Vector2(door.y, east)]:
		var face := Vector3((run.x + run.y) * 0.5, Layout.FLOOR_TOP + height * 0.5, north)
		kit.box(Vector3(run.y - run.x, height, 0.03), face, mesh, true)
	var lintel := Vector3((door.x + door.y) * 0.5, Layout.FLOOR_TOP + height - 0.15, north)
	kit.box(Vector3(door.y - door.x + 0.2, 0.3, 0.1), lintel, purple)
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
			Layout.SHOP_PURPLE, Layout.CEILING - 0.25, Layout.PAPER, DepotHall.SIGN_SIZE)


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


## A railing along X or Z from `from` to `to` (floor level y): posts, a top
## rail, a mid rail, and one solid box to keep people on the deck.
func _railing(kit: DepotKit, from: Vector3, to: Vector3) -> void:
	var yellow := DepotKit.flat(Color("e7be51"), 0.45, 0.3)
	var length: float = from.distance_to(to)
	var direction: Vector3 = (to - from) / length
	var posts: int = maxi(int(ceilf(length / 1.2)), 1)
	for index: int in range(posts + 1):
		kit.box(Vector3(0.05, 1.05, 0.05), from + direction * (length * index / posts) + Vector3(0.0, 0.525, 0.0),
				yellow)
	var centre: Vector3 = (from + to) * 0.5
	var along_x: bool = absf(direction.x) > 0.5
	var size := Vector3(length, 0.05, 0.05) if along_x else Vector3(0.05, 0.05, length)
	kit.box(size, centre + Vector3(0.0, 1.05, 0.0), yellow)
	kit.box(size, centre + Vector3(0.0, 0.55, 0.0), yellow)
	kit.box(Vector3(size.x, 0.12, size.z), centre + Vector3(0.0, 0.06, 0.0), DepotKit.flat(Color("263238"), 0.6))
	var fence := Vector3(length, 1.05, 0.1) if along_x else Vector3(0.1, 1.05, length)
	kit.collider(fence, Transform3D(Basis.IDENTITY, centre + Vector3(0.0, 0.525, 0.0)))


## Open steel stair up the hall's east side to the deck's front edge: treads
## on two stringers with handrails. Walkable through one ramp collider (its
## slope follows the treads' noses), so nobody has to climb boxes.
func _build_stair(kit: DepotKit) -> void:
	var top: float = Layout.MEZZANINE_HEIGHT
	var run: float = Layout.STAIR_RUN / STEPS
	var rise: float = top / STEPS
	var z_foot: float = Layout.MEZZANINE.position.y - Layout.STAIR_RUN
	var steel := DepotKit.flat(Color("3b4c53"), 0.5, 0.4)
	var tread := DepotKit.flat(Color("8a9499"), 0.5, 0.6)
	var yellow := DepotKit.flat(Color("e7be51"), 0.45, 0.3)
	var x: float = Layout.STAIR_X
	for index: int in range(STEPS):
		var z: float = z_foot + index * run
		var nose: float = Layout.FLOOR_TOP + (index + 1) * rise
		kit.box(Vector3(STAIR_WIDTH, 0.05, run + 0.04), Vector3(x, nose - 0.025, z + run * 0.5), tread)
		kit.box(Vector3(STAIR_WIDTH, 0.04, 0.05), Vector3(x, nose + 0.002, z + run - 0.03), yellow)
	var slope: float = atan2(top, Layout.STAIR_RUN)
	var length: float = sqrt(top * top + Layout.STAIR_RUN * Layout.STAIR_RUN)
	# The slope's frame: X along the stair's width, Y up its normal, Z along it (up-hill toward +Z).
	var basis := Basis(Vector3.RIGHT, -slope)
	var middle := Vector3(x, Layout.FLOOR_TOP + top * 0.5, z_foot + Layout.STAIR_RUN * 0.5)
	for side: float in [-1.0, 1.0]:
		var at: Vector3 = middle + Vector3(side * (STAIR_WIDTH * 0.5 + 0.02), -0.1, 0.0)
		kit.box_xf(Vector3(0.05, 0.3, length), Transform3D(basis, at), steel)
		# Handrail: a bar parallel to the slope, 0.95 m over the treads, and its posts.
		var rail_at: Vector3 = middle + Vector3(side * (STAIR_WIDTH * 0.5 + 0.02), 0.95 / cos(slope), 0.0)
		kit.box_xf(Vector3(0.05, 0.05, length), Transform3D(basis, rail_at), yellow)
		for index: int in range(0, STEPS + 1, 4):
			var post_z: float = z_foot + index * run
			var post_y: float = Layout.FLOOR_TOP + index * rise
			kit.box(Vector3(0.05, 0.95, 0.05), Vector3(x + side * (STAIR_WIDTH * 0.5 + 0.02), post_y + 0.475, post_z),
					yellow)
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
	var glass := DepotKit.glass()
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
	var plate_at := Vector3(x0 - 0.08, lift + 2.55, door_z)
	var plate := DepotLabels.text(_root, tr("WORLD_DEPOT_OFFICE"), plate_at, -PI * 0.5, 36, Layout.PAPER,
			Layout.DISPLAY_FONT, 0.005, 8)
	plate.name = "OfficeDoorSign"
	DepotLabels.fit_label(plate, 1.0)
	# Roof and mullions.
	kit.box(Vector3(side_width + 0.1, 0.1, wall_depth + 0.1), Vector3((x0 + x1) * 0.5, lift + 3.05,
			(z0 + depth_end) * 0.5), frame)
	for x: float in [x0, 11.0, 13.2]:
		kit.box(Vector3(0.06, 1.44, 0.14), Vector3(x, lift + 1.7, z0), frame)
	# Blinds half drawn over the window's west third, and the warm light inside.
	var blind := DepotKit.flat(Color("c9c4b6"), 0.8)
	for index: int in range(6):
		kit.box(Vector3(2.0, 0.035, 0.06), Vector3(9.7, lift + 2.35 - index * 0.085, z0 + 0.05), blind, false, 0.0)
	var lamp := DepotKit.glow(Color("fff1d6"), 2.2)
	for z: float in [29.0, 30.9]:
		kit.box(Vector3(3.4, 0.03, 0.14), Vector3(11.8, lift + 2.98, z), lamp)
	# Desk with the dispatch computer, a chair and a filing cabinet.
	var wood := DepotKit.detailed(Color("b08a5a"), "wood_planks", 1.0)
	kit.box(Vector3(2.0, 0.06, 0.8), Vector3(11.6, lift + 0.76, 30.6), wood, true)
	for x: float in [10.7, 12.5]:
		kit.box(Vector3(0.06, 0.74, 0.7), Vector3(x, lift + 0.38, 30.6), frame)
	kit.box(Vector3(0.6, 0.38, 0.05), Vector3(11.4, lift + 1.1, 30.85), frame)
	kit.box(Vector3(0.54, 0.32, 0.02), Vector3(11.4, lift + 1.1, 30.82), DepotKit.glow(Color("8fd3e8"), 0.9))
	kit.box(Vector3(0.45, 0.02, 0.15), Vector3(11.4, lift + 0.8, 30.35), frame)
	kit.box(Vector3(0.5, 1.3, 0.6), Vector3(14.5, lift + 0.65, 29.2), DepotKit.flat(Color("8a9499"), 0.4, 0.5), true)
	kit.box(Vector3(0.04, 0.9, 1.4), Vector3(14.95, lift + 1.8, 30.6), DepotKit.flat(Color("c9a26b"), 0.9))
	for index: int in range(5):
		kit.box(Vector3(0.01, 0.22, 0.18), Vector3(14.92, lift + 1.65 + (index % 2) * 0.35, 30.1 + index * 0.24),
				DepotKit.flat(Layout.PAPER, 0.9))
	var sign_at := Vector3(11.3, 4.75, Layout.MEZZANINE.position.y - 1.0)
	DepotLabels.hanging_sign(_root, kit, tr("WORLD_DEPOT_OFFICE"), sign_at, PI, Color("263238"), Layout.CEILING - 0.25,
			Layout.PAPER, DepotHall.SIGN_SIZE)


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
