class_name DepotHall
extends RefCounted
## The depot building itself: shell, roof and frames, floor paint and the
## wayfinding around the spawn, the forecourt outside, the lamps, and the
## soft contact shadows under heavy things. Static geometry goes into the
## DepotKit it's given; the few live nodes hang from the depot root.

const Layout = preload("res://scripts/gameplay/depot/depot_layout.gd")
const ContactShadow = preload("res://modules/render_budget/contact_shadow.gd")
## How big a zone's hanging sign is next to the old ones (N-319).
const SIGN_SIZE: float = 0.85
## Lining layer tops: the dark plinth, and where the sheet changes tone.
const PLINTH_TOP: float = 0.95
const SHEET_SPLIT: float = 6.0
## How thick the shadow-only slabs around the hall are (build_sun_shield).
const SHIELD: float = 1.6
## How hard the lamps' discs glow: the hall's focal points under the dark roof.
const LAMP_DISC_ENERGY: float = 3.6
## The roof's underside: neutral grey at about a third of full value.
const CEILING_GREY := Color("585858")
## Strip windows: the pane's width (a kit frame each) and the window's size.
const WINDOW_PANE: float = 1.2
const WINDOW_SIZE := Vector2(3.6, 1.1)

## Arrows painted on the floor: {"caption", "at", "direction"} in depot space.
var guides: Array[Dictionary] = []
## The floor paint: walkways, lane, bay (built by build_floor_markings).
var circulation: DepotCirculation
## The fluorescent tube over aisle B that's on its way out (DepotAmbience).
var flicker_tube: MeshInstance3D

var _root: Node3D
var _ground_apron: bool


func _init(root: Node3D, ground_apron: bool) -> void:
	_root = root
	_ground_apron = ground_apron


func build_shell(kit: DepotKit) -> void:
	var outside := DepotKit.ribbed(Color("3f6f7a"), 0.8)
	var trim := DepotKit.flat(Color("24363d"), 0.6, 0.3)
	# The roof's steel -- columns, trusses, purlins -- in the palette's ink.
	var truss := DepotKit.flat(Layout.INK, 0.6, 0.3)
	# Medium grey polished concrete (N-319): it was nearly the walls' colour.
	var floor := DepotKit.detailed(Color("6f7272"), "plaster", 4.0, 0.5)
	var outer_x: float = Layout.HALF_WIDTH + Layout.WALL
	kit.shadowless(floor)
	# Floor slab, flush with the road's surface at the door.
	kit.span(Vector3(-outer_x, -0.6, -Layout.WALL), Vector3(outer_x, Layout.FLOOR_TOP, Layout.DEPTH + Layout.WALL),
			floor, true)
	# Outer walls, parapet high so the flat roof hides behind them.
	kit.span(Vector3(-outer_x, -0.4, -Layout.WALL),
			Vector3(-Layout.HALF_WIDTH, Layout.WALL_HEIGHT, Layout.DEPTH + Layout.WALL), outside, true)
	kit.span(Vector3(Layout.HALF_WIDTH, -0.4, -Layout.WALL),
			Vector3(outer_x, Layout.WALL_HEIGHT, Layout.DEPTH + Layout.WALL), outside, true)
	kit.span(Vector3(-Layout.HALF_WIDTH, -0.4, Layout.DEPTH),
			Vector3(Layout.HALF_WIDTH, Layout.WALL_HEIGHT, Layout.DEPTH + Layout.WALL), outside, true)
	var jamb: float = Layout.DOOR_WIDTH * 0.5 + 0.2
	kit.span(Vector3(-Layout.HALF_WIDTH, -0.4, -Layout.WALL), Vector3(-jamb, Layout.WALL_HEIGHT, -0.02), outside, true)
	kit.span(Vector3(jamb, -0.4, -Layout.WALL), Vector3(Layout.HALF_WIDTH, Layout.WALL_HEIGHT, -0.02), outside, true)
	kit.span(Vector3(-jamb, Layout.DOOR_HEIGHT, -Layout.WALL), Vector3(jamb, Layout.WALL_HEIGHT, -0.02), outside, true)
	# Parapet cap and a plinth, so the shell doesn't read as a plain box.
	for piece: Array in [[Vector3(-outer_x - 0.05, Layout.WALL_HEIGHT, -Layout.WALL - 0.05),
			Vector3(outer_x + 0.05, Layout.WALL_HEIGHT + 0.18, -Layout.WALL + 0.25)],
			[Vector3(-outer_x - 0.05, Layout.WALL_HEIGHT, Layout.DEPTH + Layout.WALL - 0.25),
					Vector3(outer_x + 0.05, Layout.WALL_HEIGHT + 0.18, Layout.DEPTH + Layout.WALL + 0.05)],
			[Vector3(-outer_x - 0.05, Layout.WALL_HEIGHT, -Layout.WALL),
					Vector3(-outer_x + 0.25, Layout.WALL_HEIGHT + 0.18, Layout.DEPTH + Layout.WALL)],
			[Vector3(outer_x - 0.25, Layout.WALL_HEIGHT, -Layout.WALL),
					Vector3(outer_x + 0.05, Layout.WALL_HEIGHT + 0.18, Layout.DEPTH + Layout.WALL)]]:
		kit.span(piece[0], piece[1], trim)
	var plinth := DepotKit.detailed(Color("6f7873"), "stone", 1.6)
	kit.span(Vector3(-outer_x - 0.06, -0.4, -Layout.WALL - 0.06), Vector3(-jamb, 0.55, -Layout.WALL), plinth)
	kit.span(Vector3(jamb, -0.4, -Layout.WALL - 0.06), Vector3(outer_x + 0.06, 0.55, -Layout.WALL), plinth)
	kit.span(Vector3(-outer_x - 0.06, -0.4, -Layout.WALL), Vector3(-outer_x, 0.55, Layout.DEPTH + Layout.WALL), plinth)
	kit.span(Vector3(outer_x, -0.4, -Layout.WALL), Vector3(outer_x + 0.06, 0.55, Layout.DEPTH + Layout.WALL), plinth)
	kit.span(Vector3(-outer_x, -0.4, Layout.DEPTH + Layout.WALL),
			Vector3(outer_x, 0.55, Layout.DEPTH + Layout.WALL + 0.06), plinth)
	# Interior lining, in layers (N-319): a dark plinth, painted block, a trim
	# line, light sheet up past the windows and a darker tone above them.
	var layers := _lining_layers()
	for layer: Array in layers:
		kit.shadowless(layer[2])
	for side: float in [-1.0, 1.0]:
		_lining(kit, layers, Vector2(side * (Layout.HALF_WIDTH - 0.03), Layout.DEPTH * 0.5), Layout.DEPTH, false, -side)
	_lining(kit, layers, Vector2(0.0, Layout.DEPTH - 0.03), Layout.HALF_WIDTH * 2.0, true, -1.0)
	for side: float in [-1.0, 1.0]:
		var inner: float = Layout.HALF_WIDTH - jamb
		_lining(kit, layers, Vector2(side * (jamb + inner * 0.5), 0.01), inner, true, 1.0)
	_lining(kit, layers, Vector2(0.0, 0.01), jamb * 2.0, true, 1.0, Layout.DOOR_HEIGHT + 0.9)
	# Roof deck (a neutral mid-dark grey underneath, value ~35 %: the ceiling is
	# the quiet part of the picture) and its skylights.
	kit.span(Vector3(-outer_x, Layout.CEILING, -Layout.WALL),
			Vector3(outer_x, Layout.CEILING + 0.22, Layout.DEPTH + Layout.WALL),
			DepotKit.ribbed(CEILING_GREY, 0.9, 0.85, 0.1))
	# The skylights and the strip windows show the sky outside: greyish blue glass,
	# by weather and hour (DepotLighting.glass_look); the hall's own light does not.
	var look: Dictionary = DepotLighting.glass_look()
	var skylight := DepotKit.glow(look.colour, float(look.energy))
	var window_glow := DepotKit.glow(look.colour, float(look.energy))
	for x: float in DepotLighting.SKYLIGHT_XS:
		for z: float in DepotLighting.SKYLIGHT_ZS:
			kit.box(Vector3(1.6, 0.04, 7.0), Vector3(x, Layout.CEILING - 0.01, z), skylight)
			# A dark frame round each skylight, so it is a window and not a hole of white.
			for edge: float in [-1.0, 1.0]:
				kit.box(Vector3(1.6 + 0.16, 0.08, 0.08), Vector3(x, Layout.CEILING - 0.05, z + edge * 3.54), truss)
				kit.box(Vector3(0.08, 0.08, 7.0), Vector3(x + edge * 0.84, Layout.CEILING - 0.05, z), truss)
	# Portal frames: columns along the walls, trusses across.
	for z: float in Layout.PORTAL_FRAMES:
		for side: float in [-1.0, 1.0]:
			kit.box(Vector3(0.36, Layout.CEILING, 0.3),
					Vector3(side * (Layout.HALF_WIDTH - 0.24), Layout.CEILING * 0.5, z), truss)
			kit.model(DepotKit.depot_model("sm_env_depot_column_guard"), Transform3D(Basis(Vector3.UP, PI * 0.5),
					Vector3(side * (Layout.HALF_WIDTH - 0.24), Layout.FLOOR_TOP, z)))
		kit.box(Vector3(Layout.HALF_WIDTH * 2.0, 0.16, 0.16), Vector3(0.0, 6.55, z), truss)
		kit.box(Vector3(Layout.HALF_WIDTH * 2.0, 0.16, 0.16), Vector3(0.0, Layout.CEILING - 0.1, z), truss)
		for index: int in range(12):
			var x0: float = -Layout.HALF_WIDTH + 1.25 + index * 2.5
			kit.box(Vector3(0.08, Layout.CEILING - 6.55, 0.08), Vector3(x0, (6.55 + Layout.CEILING) * 0.5, z), truss)
			var rise: float = Layout.CEILING - 0.1 - 6.55
			var diagonal: float = sqrt(1.25 * 1.25 + rise * rise)
			var angle: float = atan2(rise, 1.25) * (1.0 if index % 2 == 0 else -1.0)
			kit.box_xf(Vector3(diagonal, 0.07, 0.07),
					Transform3D(Basis(Vector3.BACK, angle),
					Vector3(x0 + 0.625, (6.55 + Layout.CEILING - 0.1) * 0.5, z)), truss)
	# Purlins along the length.
	for x: float in [-11.0, -3.8, 3.8, 11.0]:
		kit.box(Vector3(0.1, 0.14, Layout.DEPTH), Vector3(x, Layout.CEILING - 0.18, Layout.DEPTH * 0.5), truss)
	# Two ducts and a cable tray along the hall in 3 m pieces, between the trusses' chords;
	# their hangers reach the roof. Clear of the lamps, the fans and the signs' cables.
	var pieces: int = int((Layout.DEPTH - 0.6) / 3.0)
	var duct: String = DepotKit.depot_model("sm_env_depot_duct_straight")
	var tray: String = DepotKit.depot_model("sm_env_depot_cable_tray")
	for index: int in range(pieces):
		var z: float = 0.3 + 1.5 + index * 3.0
		for x: float in [-7.6, 12.6]:
			kit.model(duct, Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(x, 6.1, z)))
		kit.model(tray, Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(0.0, 6.5, z)))
	# High strip windows (daylight inside, dark glass outside).
	for side: float in [-1.0, 1.0]:
		for z: float in [5.2, 10.8, 16.4, 22.0, 27.6]:
			kit.box(Vector3(0.02, 1.1, 3.6), Vector3(side * (Layout.HALF_WIDTH - 0.07), 5.4, z), window_glow)
			_window_frame(kit, side, z)
			kit.box(Vector3(0.02, 1.1, 3.6), Vector3(side * (Layout.HALF_WIDTH + Layout.WALL + 0.01), 5.4, z),
					DepotKit.flat(Color("22343b"), 0.15, 0.3))
			kit.box(Vector3(0.08, 1.24, 3.74), Vector3(side * (Layout.HALF_WIDTH + Layout.WALL + 0.02), 5.4, z), trim)
	# Exterior downpipes and wall lamps on the facade.
	for x: float in [-Layout.HALF_WIDTH - 0.1, Layout.HALF_WIDTH + 0.1]:
		kit.cylinder(0.08, Layout.WALL_HEIGHT,
				Transform3D(Basis.IDENTITY, Vector3(x, Layout.WALL_HEIGHT * 0.5, -Layout.WALL - 0.12)), trim, 8)
	for x: float in [-5.6, 5.6]:
		kit.box(Vector3(0.5, 0.25, 0.3), Vector3(x, 4.6, -Layout.WALL - 0.15), trim)
		kit.box(Vector3(0.42, 0.06, 0.24), Vector3(x, 4.46, -Layout.WALL - 0.15), DepotKit.glow(Color("fff1d6"), 2.0))
	# Staff door on the facade, and its canopy.
	kit.box(Vector3(1.1, 2.2, 0.08), Vector3(9.5, 1.1 + Layout.FLOOR_TOP, -Layout.WALL - 0.04),
			DepotKit.flat(Color("2f7a64"), 0.6))
	kit.box(Vector3(1.3, 0.08, 0.7), Vector3(9.5, 2.55, -Layout.WALL - 0.35), trim)
	kit.box(Vector3(0.06, 0.3, 0.06), Vector3(9.9, 1.1, -Layout.WALL - 0.1), DepotKit.flat(Color("c9ced0"), 0.3, 0.8))
	kit.box(Vector3(1.1, 2.2, 0.06), Vector3(9.5, 1.1 + Layout.FLOOR_TOP, 0.03), DepotKit.flat(Color("2f7a64"), 0.6))


## The lining's layers as [bottom y, top y, material, trim above it], shared by
## every wall: one place to retune the room's colours.
func _lining_layers() -> Array:
	var plinth := DepotKit.detailed(Color("4c5a61"), "stone", 1.4)
	var block := DepotKit.detailed(Color("8a9693"), "plaster", 1.4)
	# The sheet up past the windows is a mid grey-green (<= 58 % value, N-319) and the
	# band above them darker still: the walls recede, the floor and the truck lead.
	var sheet_low := DepotKit.ribbed(Color("8f918e"), 0.7, 0.6, 0.15)
	var sheet_high := DepotKit.ribbed(Color("63666a"), 0.7, 0.6, 0.15)
	return [
		[Layout.FLOOR_TOP, PLINTH_TOP, plinth, DepotKit.flat(Color("2c3a40"), 0.6)],
		[PLINTH_TOP, Layout.LINER_SPLIT, block, null],
		[Layout.LINER_SPLIT, SHEET_SPLIT, sheet_low, DepotKit.flat(Color("3b4c53"), 0.5, 0.4)],
		[SHEET_SPLIT, Layout.CEILING, sheet_high, null],
	]


## One stretch of lining, `length` long along X (or Z), centred on `centre`
## (x/z) and facing `inward` (+1/-1 along the other axis), from `y_min` up.
## Each layer is a thin slab; where it has a trim, a bar juts 4 cm proud on top.
func _lining(kit: DepotKit, layers: Array, centre: Vector2, length: float, along_x: bool, inward: float,
		y_min: float = 0.0) -> void:
	for layer: Array in layers:
		var bottom: float = maxf(float(layer[0]), y_min)
		var top: float = float(layer[1])
		if top <= bottom + 0.001:
			continue
		var size := Vector3(length, top - bottom, 0.06) if along_x else Vector3(0.06, top - bottom, length)
		kit.box(size, Vector3(centre.x, (bottom + top) * 0.5, centre.y), layer[2])
		if layer[3] != null and top > y_min:
			var bar := Vector3(length, 0.1, 0.1) if along_x else Vector3(0.1, 0.1, length)
			var proud := Vector3(0.0, 0.0, inward * 0.03) if along_x else Vector3(inward * 0.03, 0.0, 0.0)
			kit.box(bar, Vector3(centre.x, top, centre.y) + proud, layer[3])


## The sun must not light the hall: its lamps do, and the weather only shows
## at the windows. The level's sun has a coarse shadow bias and the roof and
## walls are thin, so its light leaked in through them and a clear noon washed
## the floor out. Thick slabs over the roof and outside the side and back walls
## that only cast shadows (never drawn) close the leak: 4 boxes, no draw calls.
func build_sun_shield() -> void:
	var outer_x: float = Layout.HALF_WIDTH + Layout.WALL
	var back: float = Layout.DEPTH + Layout.WALL
	var slabs: Array[AABB] = [
		AABB(Vector3(-outer_x - SHIELD, Layout.CEILING + 0.22, -Layout.WALL),
				Vector3(outer_x * 2.0 + SHIELD * 2.0, SHIELD, back + Layout.WALL + SHIELD)),
		AABB(Vector3(-outer_x - SHIELD, -0.4, -Layout.WALL),
				Vector3(SHIELD, Layout.CEILING + 0.62, back + Layout.WALL)),
		AABB(Vector3(outer_x, -0.4, -Layout.WALL), Vector3(SHIELD, Layout.CEILING + 0.62, back + Layout.WALL)),
		AABB(Vector3(-outer_x, -0.4, back), Vector3(outer_x * 2.0, Layout.CEILING + 0.62, SHIELD)),
	]
	var holder := Node3D.new()
	holder.name = "SunShield"
	_root.add_child(holder)
	for slab: AABB in slabs:
		var box := BoxMesh.new()
		box.size = slab.size
		var instance := MeshInstance3D.new()
		instance.mesh = box
		instance.position = slab.get_center()
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
		holder.add_child(instance)


## A strip window's frame from the kit: three 1.2 m frames side by side (the shared
## sides are the mullions), on the inside face of the wall at `side` (-1 west, +1 east).
func _window_frame(kit: DepotKit, side: float, z: float) -> void:
	var frame: String = DepotKit.depot_model("sm_env_depot_window_frame")
	var panes: int = int(round(WINDOW_SIZE.x / WINDOW_PANE))
	for index: int in range(panes):
		var along: float = z + (index - (panes - 1) * 0.5) * WINDOW_PANE
		kit.model(frame, Transform3D(Basis(Vector3.UP, side * PI * 0.5),
				Vector3(side * (Layout.HALF_WIDTH - 0.06), 5.4 - WINDOW_SIZE.y * 0.5 - 0.1, along)))


func build_floor_markings(kit: DepotKit) -> void:
	var white := DepotKit.detailed(Layout.MARKING, "stone", 0.8, 0.8)
	var hazard := DepotKit.stripes(Layout.YELLOW, Color("2b3136"), 0.25)
	var paint := func(size_x: float, size_z: float, centre: Vector3, material: Material) -> void:
		var mesh := BoxMesh.new()
		mesh.size = Vector3(size_x, 0.006, size_z)
		kit.add_mesh(mesh, Transform3D(Basis.IDENTITY, Vector3(centre.x, Layout.FLOOR_TOP + 0.003, centre.z)), material,
				false)
	# Saw-cut joints of the poured slab, every six metres: dark and a bit wider
	# (N-319), so the floor reads as concrete slabs and not one grey sheet.
	var joint := DepotKit.flat(Color("3f474a"), 0.9)
	for index: int in range(1, 5):
		var x: float = -Layout.HALF_WIDTH + index * 6.0
		var mesh := BoxMesh.new()
		mesh.size = Vector3(0.04, 0.004, Layout.DEPTH)
		kit.add_mesh(mesh, Transform3D(Basis.IDENTITY, Vector3(x, Layout.FLOOR_TOP + 0.001, Layout.DEPTH * 0.5)), joint,
				false)
	for index: int in range(1, 6):
		var mesh := BoxMesh.new()
		mesh.size = Vector3(Layout.HALF_WIDTH * 2.0, 0.004, 0.04)
		kit.add_mesh(mesh, Transform3D(Basis.IDENTITY, Vector3(0.0, Layout.FLOOR_TOP + 0.001, index * 6.0)), joint,
				false)
	_build_loading_zone(kit, hazard)
	# The shelving units' footprints, in white: yellow is the forklift's.
	for unit: Dictionary in Layout.SHELF_UNITS:
		var x: float = float(unit.x)
		var length: float = Layout.BAY_LENGTH * Layout.BAYS
		for side: float in [-1.0, 1.0]:
			paint.call(0.07, length + 0.6,
					Vector3(x + side * (Layout.SHELF_DEPTH * 0.5 + 0.3), 0.0,
							Layout.SHELF_START_Z + length * 0.5), white)
		for end: float in [Layout.SHELF_START_Z - 0.3, Layout.SHELF_START_Z + length + 0.3]:
			paint.call(Layout.SHELF_DEPTH + 0.68, 0.07, Vector3(x, 0.0, end), white)
	# The truck bay, the walkways, the forklift's lane and the wear.
	circulation = DepotCirculation.new(_root)
	circulation.build(kit)
	DepotLabels.floor_text(_root, tr("WORLD_DEPOT_FLOOR_EXIT"), Vector3(0.0, 0.0, 2.9), 0.0, 80,
			Color(Layout.TEAL, 0.9))


## The loading zone behind the truck's ramp: a hazard-striped frame around a
## dark plate, and the words painted in yellow on the plate -- written over
## the stripes they were unreadable. Each layer sits FLOOR_PAINT_STEP over the
## one under it, so none of them z-fight.
func _build_loading_zone(kit: DepotKit, hazard: Material) -> void:
	var zone: Rect2 = Layout.LOADING_ZONE
	var centre := Vector3(zone.get_center().x, 0.0, zone.get_center().y)
	var frame := BoxMesh.new()
	frame.size = Vector3(zone.size.x, 0.006, zone.size.y)
	kit.add_mesh(frame, Transform3D(Basis.IDENTITY, Vector3(centre.x, Layout.FLOOR_TOP + 0.003, centre.z)), hazard,
			false)
	var plate := BoxMesh.new()
	plate.size = Vector3(zone.size.x - 0.36, 0.006, zone.size.y - 0.36)
	var plate_y: float = Layout.FLOOR_TOP + 0.003 + Layout.FLOOR_PAINT_STEP
	kit.add_mesh(plate, Transform3D(Basis.IDENTITY, Vector3(centre.x, plate_y, centre.z)),
			DepotKit.flat(Color("2b3136"), 0.75), false)
	var words := DepotLabels.floor_text(_root, tr("WORLD_DEPOT_FLOOR_LOADING"), centre, 0.0, 56, Layout.YELLOW)
	words.position.y = Layout.FLOOR_TOP + 0.006 + Layout.FLOOR_PAINT_STEP * 2.0
	DepotLabels.fit_label(words, zone.size.x - 0.7)


## How a new player finds each station without anyone telling them (tareas
## de Nacho N-503, reworked in N-319): the green walkways and one small arrow
## per place in its colour (DepotCirculation), chevrons beside the truck
## toward the door, and a sign per zone hanging over the zone itself -- smaller
## than they used to be, none of them crowded in front of the spawn. Each
## place's own sign hangs from where it is built (_build_workshop, ...).
func build_wayfinding(kit: DepotKit) -> void:
	guides.append_array(circulation.arrows())
	for x: float in [-2.6, 2.6]:
		for z: float in [11.6, 7.6, 3.6]:
			guides.append(DepotLabels.paint_arrow(kit, tr("WORLD_DEPOT_GATE"), Vector3(x, 0.0, z), Vector3.FORWARD,
					Layout.TEAL))
	# Over the truck bay, high enough over the truck's roof to read above it from behind. (The control
	# island has no hanging sign: its lit board is the brightest thing in the hall.)
	DepotLabels.hanging_sign(_root, kit, tr("WORLD_DEPOT_SIGN_TRUCK"), Vector3(0.0, 4.4, 11.0), 0.0,
			Layout.TRUCK_YELLOW, Layout.CEILING - 0.25, Layout.PAPER, SIGN_SIZE, DepotLabels.ICON_EXIT)


func build_exterior(kit: DepotKit) -> void:
	var concrete := DepotKit.detailed(Color("8d948f"), "stone", 3.0, 0.8)
	var white := DepotKit.flat(Color("e8ebe4"), 0.7)
	var yellow := DepotKit.flat(Layout.YELLOW, 0.7)
	# Forecourt apron in front of the door, a hair above the ground around it.
	kit.span(Vector3(-Layout.HALF_WIDTH - 6.0, -0.5, -9.0),
			Vector3(Layout.HALF_WIDTH + 6.0, Layout.FLOOR_TOP, -Layout.WALL), concrete, true)
	if _ground_apron:
		var grass := DepotKit.detailed(Color("5d7a4f"), "grass", 2.0)
		kit.span(Vector3(-60.0, -0.6, -9.0), Vector3(60.0, -0.02, 70.0), grass, true)
	# Staff parking on the left: bays, two cars, a kerb stop each.
	var bay_y: float = Layout.FLOOR_TOP + 0.003
	for index: int in range(4):
		var x: float = -19.8 + index * 2.6
		var mesh := BoxMesh.new()
		mesh.size = Vector3(0.1, 0.006, 4.6)
		kit.add_mesh(mesh, Transform3D(Basis.IDENTITY, Vector3(x, bay_y, -5.2)), white, false)
	kit.model_grounded("res://assets/models/vehicles/sm_vehicle_parked_sedan_refined.glb",
			Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(-18.5, Layout.FLOOR_TOP, -5.2)))
	kit.model_grounded("res://assets/models/vehicles/sm_vehicle_competitor_van.glb",
			Transform3D(Basis(Vector3.UP, PI * 0.5 + 0.04), Vector3(-11.8, Layout.FLOOR_TOP, -5.4)))
	kit.collider(Vector3(1.8, 1.5, 4.0), Transform3D(Basis.IDENTITY, Vector3(-18.5, 0.75, -5.2)))
	kit.collider(Vector3(1.8, 1.5, 4.0), Transform3D(Basis.IDENTITY, Vector3(-15.9, 0.75, -5.4)))
	# Dumpster and a stack of spare pallets on the right.
	kit.box(Vector3(2.0, 1.3, 1.2), Vector3(17.8, 0.65 + Layout.FLOOR_TOP, -2.0),
			DepotKit.flat(Color("2f6b4f"), 0.7, 0.2), true)
	kit.box(Vector3(2.1, 0.08, 1.3), Vector3(17.8, 1.34 + Layout.FLOOR_TOP, -2.0), DepotKit.flat(Color("24363d"), 0.7),
			false)
	for layer: int in range(8):
		kit.model_grounded(Layout.PALLET,
				Transform3D(Basis(Vector3.UP, 0.05 * (layer % 3)), Vector3(17.6, Layout.FLOOR_TOP + layer * 0.1, -5.6)))
	kit.collider(Vector3(1.3, 0.8, 0.9), Transform3D(Basis.IDENTITY, Vector3(17.6, 0.4, -5.6)))
	# Street lamps either side of the gate out, cones by the door.
	for x: float in [-8.6, 8.6]:
		kit.model_grounded("res://assets/models/environment/props/sm_env_prop_street_lamp_refined.glb",
				Transform3D(Basis.IDENTITY, Vector3(x, Layout.FLOOR_TOP, -8.4)))
		kit.collider(Vector3(0.3, 4.8, 0.3), Transform3D(Basis.IDENTITY, Vector3(x, 2.4, -8.4)))
	for spot: Vector3 in [Vector3(-4.6, Layout.FLOOR_TOP, -2.2), Vector3(4.7, Layout.FLOOR_TOP, -2.6),
			Vector3(5.2, Layout.FLOOR_TOP, -3.3)]:
		kit.model_grounded("res://assets/models/environment/props/sm_env_prop_traffic_cone.glb",
				Transform3D(Basis.IDENTITY, spot))
	# Painted exit lane out of the forecourt.
	for x: float in [-3.3, 3.3]:
		var mesh := BoxMesh.new()
		mesh.size = Vector3(0.12, 0.006, 8.4)
		kit.add_mesh(mesh, Transform3D(Basis.IDENTITY, Vector3(x, bay_y, -4.8)), yellow, false)
	DepotLabels.floor_text(_root, tr("WORLD_DEPOT_FLOOR_TO_ROAD"), Vector3(0.0, 0.0, -6.2), 0.0, 90,
			Color(Layout.PAPER, 0.85))


## The level's sun, or null (a depot built on its own, in a test).
func _sun() -> DirectionalLight3D:
	if not _root.is_inside_tree():
		return null
	var suns: Array[Node] = _root.get_tree().root.find_children("*", "DirectionalLight3D", true, false)
	return suns[0] as DirectionalLight3D if not suns.is_empty() else null


func build_contact_shadows() -> void:
	var holder := Node3D.new()
	holder.name = "ContactShadows"
	_root.add_child(holder)
	for patch: Array in Layout.CONTACT_SHADOWS:
		ContactShadow.add(holder, (patch[0] as Vector3) + Vector3.UP * Layout.FLOOR_TOP, patch[1], patch[2], patch[3])


func build_lights() -> void:
	var kit := DepotKit.new(_root, "LightColliders")
	var lamp := DepotKit.glow(Color("fff1d6"), LAMP_DISC_ENERGY)
	var fixtures: Array[Vector3] = []
	for x: float in DepotLighting.LAMP_XS:
		for z: float in DepotLighting.LAMP_ZS:
			# Not the one that would hang through the office's roof.
			if not Layout.MEZZANINE.grow(0.6).has_point(Vector2(x, z)):
				fixtures.append(Vector3(x, 5.9, z))
	var high_bay: String = DepotKit.depot_model("sm_env_depot_high_bay_lamp")
	var tube_fixture: String = DepotKit.depot_model("sm_env_depot_tube_fixture")
	var tube_linear: String = DepotKit.depot_model("sm_env_depot_tube_linear")
	var bell: String = DepotKit.depot_model("sm_env_depot_bay_lamp_bell")
	for at: Vector3 in fixtures:
		# The truck's bay is lit by the big bell lamps (with their own disc and halo).
		if absf(at.x) < 3.5 and at.z < 14.0:
			kit.model(bell, Transform3D(Basis.IDENTITY, Vector3(at.x, 6.75, at.z)))
			continue
		# Shade model hangs from its hook, 0.65 m above the shade's centre.
		kit.model(high_bay, Transform3D(Basis.IDENTITY, at + Vector3(0.0, 0.65, 0.0)))
		var bulb := CylinderMesh.new()
		bulb.top_radius = 0.36
		bulb.bottom_radius = 0.36
		bulb.height = 0.02
		bulb.radial_segments = 14
		kit.add_mesh(bulb, Transform3D(Basis.IDENTITY, at - Vector3(0.0, 0.16, 0.0)), lamp, false)
	# Fluorescent tubes over the dispatch shelves; one of them is on its way out.
	for unit: Dictionary in Layout.SHELF_UNITS:
		for index: int in range(2):
			var z: float = Layout.SHELF_START_Z + 2.0 + index * 4.0
			if unit.aisle == "B" and index == 1:
				# The old fixture, on its way out.
				kit.model(tube_fixture, Transform3D(Basis.IDENTITY, Vector3(float(unit.x), 4.3, z)))
				flicker_tube = MeshInstance3D.new()
				flicker_tube.name = "FlickeringTube"
				var tube := BoxMesh.new()
				tube.size = Vector3(0.1, 0.04, 1.2)
				flicker_tube.mesh = tube
				flicker_tube.material_override = DepotKit.glow(Color("eaf6ff"), 2.0)
				flicker_tube.position = Vector3(float(unit.x), 4.26, z)
				flicker_tube.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				_root.add_child(flicker_tube)
			else:
				# The linear fixture carries its own lit diffuser; its chains reach the trusses.
				kit.model(tube_linear, Transform3D(Basis.IDENTITY, Vector3(float(unit.x), 5.2, z)))
	var sun: DirectionalLight3D = _sun()
	DepotLighting.build_pools(kit, sun)
	kit.commit("Lamps")
	# Few real lights (the GL Compatibility renderer caps lights per mesh),
	# each with a job (DepotLighting); the fixtures above and the pools and
	# shafts of light on the floor do the rest of the look.
	DepotLighting.build_lights(_root)
	DepotLighting.build_shafts(_root, sun)
	# Motes of dust inside each shaft of light (none at night, none on Low).
	DepotLighting.build_dust(_root, sun)
