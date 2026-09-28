class_name DepotHall
extends RefCounted
## The depot building itself: shell, roof and frames, floor paint and the
## wayfinding around the spawn, the forecourt outside, the lamps, and the
## soft contact shadows under heavy things. Static geometry goes into the
## DepotKit it's given; the few live nodes hang from the depot root.

const Layout = preload("res://scripts/gameplay/depot/depot_layout.gd")
const ContactShadow = preload("res://scripts/presentation/contact_shadow.gd")

## Arrows painted on the floor: {"caption", "at", "direction"} in depot space.
var guides: Array[Dictionary] = []
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
	var liner_low := DepotKit.detailed(Color("7f8d93"), "plaster", 1.4)
	var liner_high := DepotKit.ribbed(Color("dce1e2"), 0.7, 0.6, 0.15)
	var steel := DepotKit.flat(Color("3b4c53"), 0.5, 0.4)
	var floor := DepotKit.detailed(Color("a2aaac"), "plaster", 5.0, 0.55)
	var outer_x: float = Layout.HALF_WIDTH + Layout.WALL
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
	# Interior liner: block dado below, light sheet above.
	for side: float in [-1.0, 1.0]:
		var x: float = side * (Layout.HALF_WIDTH - 0.03)
		kit.box(Vector3(0.06, 2.4, Layout.DEPTH), Vector3(x, 1.2 + Layout.FLOOR_TOP, Layout.DEPTH * 0.5), liner_low)
		kit.box(Vector3(0.06, Layout.CEILING - 2.4, Layout.DEPTH),
				Vector3(x, 2.4 + (Layout.CEILING - 2.4) * 0.5, Layout.DEPTH * 0.5), liner_high)
	kit.box(Vector3(Layout.HALF_WIDTH * 2.0, 2.4, 0.06), Vector3(0.0, 1.2 + Layout.FLOOR_TOP, Layout.DEPTH - 0.03),
			liner_low)
	kit.box(Vector3(Layout.HALF_WIDTH * 2.0, Layout.CEILING - 2.4, 0.06),
			Vector3(0.0, 2.4 + (Layout.CEILING - 2.4) * 0.5, Layout.DEPTH - 0.03), liner_high)
	for side: float in [-1.0, 1.0]:
		var inner: float = Layout.HALF_WIDTH - jamb
		var centre: float = side * (jamb + inner * 0.5)
		kit.box(Vector3(inner, 2.4, 0.06), Vector3(centre, 1.2 + Layout.FLOOR_TOP, 0.01), liner_low)
		kit.box(Vector3(inner, Layout.CEILING - 2.4, 0.06), Vector3(centre, 2.4 + (Layout.CEILING - 2.4) * 0.5, 0.01),
				liner_high)
	kit.box(Vector3(jamb * 2.0, Layout.CEILING - Layout.DOOR_HEIGHT - 0.9, 0.06),
			Vector3(0.0, Layout.DOOR_HEIGHT + 0.9 + (Layout.CEILING - Layout.DOOR_HEIGHT - 0.9) * 0.5, 0.01),
			liner_high)
	# Roof deck and its skylights.
	kit.span(Vector3(-outer_x, Layout.CEILING, -Layout.WALL),
			Vector3(outer_x, Layout.CEILING + 0.22, Layout.DEPTH + Layout.WALL),
			DepotKit.ribbed(Color("c6cccd"), 0.9, 0.7, 0.2))
	for x: float in [-7.5, 7.5]:
		for z: float in [5.0, 16.0, 27.0]:
			kit.box(Vector3(1.6, 0.04, 7.0), Vector3(x, Layout.CEILING - 0.01, z), DepotKit.glow(Color("e4f1ef"), 0.9))
	# Portal frames: columns along the walls, trusses across.
	for z: float in [2.4, 8.0, 13.6, 19.2, 24.8, 30.4]:
		for side: float in [-1.0, 1.0]:
			kit.box(Vector3(0.36, Layout.CEILING, 0.3),
					Vector3(side * (Layout.HALF_WIDTH - 0.24), Layout.CEILING * 0.5, z), steel)
			kit.box(Vector3(0.4, 0.3, 0.34), Vector3(side * (Layout.HALF_WIDTH - 0.24), 0.18, z),
					DepotKit.flat(Color("e7be51"), 0.6))
		kit.box(Vector3(Layout.HALF_WIDTH * 2.0, 0.16, 0.16), Vector3(0.0, 6.55, z), steel)
		kit.box(Vector3(Layout.HALF_WIDTH * 2.0, 0.16, 0.16), Vector3(0.0, Layout.CEILING - 0.1, z), steel)
		for index: int in range(12):
			var x0: float = -Layout.HALF_WIDTH + 1.25 + index * 2.5
			kit.box(Vector3(0.08, Layout.CEILING - 6.55, 0.08), Vector3(x0, (6.55 + Layout.CEILING) * 0.5, z), steel)
			var rise: float = Layout.CEILING - 0.1 - 6.55
			var diagonal: float = sqrt(1.25 * 1.25 + rise * rise)
			var angle: float = atan2(rise, 1.25) * (1.0 if index % 2 == 0 else -1.0)
			kit.box_xf(Vector3(diagonal, 0.07, 0.07),
					Transform3D(Basis(Vector3.BACK, angle),
					Vector3(x0 + 0.625, (6.55 + Layout.CEILING - 0.1) * 0.5, z)), steel)
	# Purlins along the length.
	for x: float in [-11.0, -3.8, 3.8, 11.0]:
		kit.box(Vector3(0.1, 0.14, Layout.DEPTH), Vector3(x, Layout.CEILING - 0.18, Layout.DEPTH * 0.5), steel)
	# High strip windows (daylight inside, dark glass outside).
	for side: float in [-1.0, 1.0]:
		for z: float in [5.2, 10.8, 16.4, 22.0, 27.6]:
			kit.box(Vector3(0.02, 1.1, 3.6), Vector3(side * (Layout.HALF_WIDTH - 0.07), 5.4, z),
					DepotKit.glow(Color("d6ecec"), 0.75))
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


func build_floor_markings(kit: DepotKit) -> void:
	var yellow := DepotKit.flat(Layout.YELLOW, 0.7)
	var white := DepotKit.flat(Color("e8ebe4"), 0.7)
	var hazard := DepotKit.detailed(Color.WHITE, Layout.WARNING_TEXTURE, 0.9, 0.7)
	var y: float = Layout.FLOOR_TOP + 0.003
	var paint := func(size_x: float, size_z: float, centre: Vector3, material: Material) -> void:
		var mesh := BoxMesh.new()
		mesh.size = Vector3(size_x, 0.006, size_z)
		kit.add_mesh(mesh, Transform3D(Basis.IDENTITY, Vector3(centre.x, y, centre.z)), material, false)
	# Saw-cut joints of the poured slab, every six metres.
	var joint := DepotKit.flat(Color("7d8587"), 0.8)
	for index: int in range(1, 5):
		var x: float = -Layout.HALF_WIDTH + index * 6.0
		var mesh := BoxMesh.new()
		mesh.size = Vector3(0.025, 0.004, Layout.DEPTH)
		kit.add_mesh(mesh, Transform3D(Basis.IDENTITY, Vector3(x, Layout.FLOOR_TOP + 0.001, Layout.DEPTH * 0.5)), joint,
				false)
	for index: int in range(1, 6):
		var mesh := BoxMesh.new()
		mesh.size = Vector3(Layout.HALF_WIDTH * 2.0, 0.004, 0.025)
		kit.add_mesh(mesh, Transform3D(Basis.IDENTITY, Vector3(0.0, Layout.FLOOR_TOP + 0.001, index * 6.0)), joint,
				false)
	# Truck bay: a white box the truck sits in, its stop bar behind the ramp.
	paint.call(0.12, 11.2, Vector3(-1.9, 0.0, 7.8), white)
	paint.call(0.12, 11.2, Vector3(1.9, 0.0, 7.8), white)
	paint.call(3.92, 0.12, Vector3(0.0, 0.0, 13.4), white)
	# Hazard band inside the door, and the loading zone behind the truck.
	paint.call(Layout.DOOR_WIDTH, 1.2, Vector3(0.0, 0.0, 0.9), hazard)
	paint.call(3.6, 0.8, Vector3(0.0, 0.0, 14.1), hazard)
	# Yellow walkway edges and the zones' outlines.
	for x: float in [-3.3, 3.3]:
		paint.call(0.1, 13.0, Vector3(x, 0.0, 8.0), yellow)
	for unit: Dictionary in Layout.SHELF_UNITS:
		var x: float = float(unit.x)
		var length: float = Layout.BAY_LENGTH * Layout.BAYS
		for side: float in [-1.0, 1.0]:
			paint.call(0.08, length + 0.6,
					Vector3(x + side * (Layout.SHELF_DEPTH * 0.5 + 0.3), 0.0, Layout.SHELF_START_Z + length * 0.5),
					yellow)
		for end: float in [Layout.SHELF_START_Z - 0.3, Layout.SHELF_START_Z + length + 0.3]:
			paint.call(Layout.SHELF_DEPTH + 0.68, 0.08, Vector3(x, 0.0, end), yellow)
	paint.call(0.1, 30.0, Vector3(-13.1, 0.0, 16.0), yellow)
	paint.call(0.1, 25.0, Vector3(-11.0, 0.0, 15.0), DepotKit.flat(Layout.TEAL, 0.7))
	# Painted floor words, facing whoever walks toward them.
	DepotLabels.floor_text(_root, tr("WORLD_DEPOT_FLOOR_FORKLIFT"), Vector3(-12.05, 0.0, 12.0), -PI * 0.5, 44,
			Color(Layout.YELLOW, 0.85))
	DepotLabels.floor_text(_root, tr("WORLD_DEPOT_FLOOR_EXIT"), Vector3(0.0, 0.0, 2.6), 0.0, 90,
			Color(Layout.TEAL, 0.9))
	DepotLabels.floor_text(_root, tr("WORLD_DEPOT_FLOOR_LOADING"), Vector3(0.0, 0.0, 14.1), 0.0, 40,
			Color(Layout.INK, 0.9))
	DepotLabels.floor_text(_root, tr("WORLD_DEPOT_WORKSHOP"), Vector3(10.8, 0.0, 6.5), -PI * 0.5, 80,
			Color("e8ebe4", 0.8))


## How a new player finds each station without anyone telling them (tareas
## de Nacho N-503): arrows on the floor around the spawn, chevrons beside the
## truck toward the door, and hanging signs that read from where the crew
## appears -- over the board (and on to the shelves), over the truck, and to
## the right toward the lockers and the shop. Each place's own sign hangs
## over it too (_build_workshop, _build_lockers...).
func build_wayfinding(kit: DepotKit) -> void:
	for guide: Dictionary in Layout.FLOOR_GUIDES:
		var at: Vector3 = guide.arrow
		guides.append(DepotLabels.paint_arrow(kit, tr(guide.caption), at, ((guide.toward as Vector3) - at).normalized(),
				guide.colour))
		DepotLabels.floor_text(_root, tr(guide.caption), guide.word, 0.0, 34, Color(guide.colour as Color, 0.95))
	for x: float in [-2.6, 2.6]:
		for z: float in [11.6, 7.6, 3.6]:
			guides.append(DepotLabels.paint_arrow(kit, tr("WORLD_DEPOT_GATE"), Vector3(x, 0.0, z), Vector3.FORWARD,
					Layout.TEAL))
	var board_yaw: float = deg_to_rad(38.0)
	var over_board: Vector3 = Vector3(-4.5, 0.0, 13.0) + Basis(Vector3.UP, board_yaw) * Vector3(0.9, 0.0, 0.0)
	DepotLabels.hanging_sign(_root, kit, tr("WORLD_DEPOT_SIGN_SHELVES"), over_board + Vector3(0.0, 4.3, 0.0), board_yaw,
			Layout.SHELVES_BLUE)
	DepotLabels.hanging_sign(_root, kit, tr("WORLD_DEPOT_BOARD"), over_board + Vector3(0.0, 3.5, 0.0), board_yaw,
			Layout.BOARD_GREEN, 4.0)
	# High enough over the truck's roof to read above it from behind.
	DepotLabels.hanging_sign(_root, kit, tr("WORLD_DEPOT_SIGN_TRUCK"), Vector3(0.0, 4.4, 11.0), 0.0, Layout.INK,
			Layout.CEILING - 0.25, Color("ffc93c"))
	var right := Vector3(4.6, 0.0, 11.0)
	var right_yaw: float = deg_to_rad(-30.0)
	DepotLabels.hanging_sign(_root, kit, tr("WORLD_DEPOT_SIGN_LOCKERS"), right + Vector3(0.0, 4.35, 0.0), right_yaw,
			Layout.LOCKERS_TEAL)
	DepotLabels.hanging_sign(_root, kit, tr("WORLD_DEPOT_SIGN_SUPPLIES"), right + Vector3(0.0, 3.55, 0.0), right_yaw,
			Layout.SHOP_PURPLE, 4.05)


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


func build_contact_shadows() -> void:
	var holder := Node3D.new()
	holder.name = "ContactShadows"
	_root.add_child(holder)
	for patch: Array in Layout.CONTACT_SHADOWS:
		ContactShadow.add(holder, (patch[0] as Vector3) + Vector3.UP * Layout.FLOOR_TOP, patch[1], patch[2], patch[3])


func build_lights() -> void:
	var kit := DepotKit.new(_root, "LightColliders")
	var lamp := DepotKit.glow(Color("fff1d6"), 2.2)
	var fixtures: Array[Vector3] = []
	for x: float in [-9.0, -3.0, 3.0, 9.0]:
		for z: float in [5.2, 13.0, 20.8, 28.0]:
			fixtures.append(Vector3(x, 5.9, z))
	var high_bay: String = DepotKit.depot_model("sm_env_depot_high_bay_lamp")
	var tube_fixture: String = DepotKit.depot_model("sm_env_depot_tube_fixture")
	for at: Vector3 in fixtures:
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
			kit.model(tube_fixture, Transform3D(Basis.IDENTITY, Vector3(float(unit.x), 4.3, z)))
			if unit.aisle == "B" and index == 1:
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
				var tube_mesh := BoxMesh.new()
				tube_mesh.size = Vector3(0.1, 0.04, 1.2)
				kit.add_mesh(tube_mesh, Transform3D(Basis.IDENTITY, Vector3(float(unit.x), 4.26, z)),
						DepotKit.glow(Color("eaf6ff"), 2.0), false)
	kit.commit("Lamps")
	# Few real lights (the GL Compatibility renderer caps lights per mesh):
	# four warm high-bay pools; the fixtures above do the rest of the look.
	for at: Vector3 in [Vector3(-6.0, 5.4, 9.0), Vector3(6.0, 5.4, 9.0), Vector3(-6.0, 5.4, 23.0),
			Vector3(6.0, 5.4, 23.0)]:
		var light := OmniLight3D.new()
		light.name = "HighBay"
		light.position = at
		light.light_color = Color("fff3df")
		light.light_energy = 1.2
		light.omni_range = 15.0
		light.omni_attenuation = 0.9
		light.shadow_enabled = false
		_root.add_child(light)
	# Motes drifting in the air under the skylights.
	var dust := CPUParticles3D.new()
	dust.name = "DustMotes"
	dust.amount = 90
	dust.lifetime = 12.0
	dust.preprocess = 12.0
	dust.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	dust.emission_box_extents = Vector3(12.0, 2.5, 14.0)
	dust.position = Vector3(0.0, 3.5, 16.0)
	dust.direction = Vector3(0.2, 0.1, 0.1)
	dust.spread = 180.0
	dust.gravity = Vector3.ZERO
	dust.initial_velocity_min = 0.02
	dust.initial_velocity_max = 0.08
	var mote := QuadMesh.new()
	mote.size = Vector2(0.025, 0.025)
	var mote_material := StandardMaterial3D.new()
	mote_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mote_material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mote_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mote_material.albedo_color = Color(1.0, 0.95, 0.85, 0.35)
	mote.material = mote_material
	dust.mesh = mote
	_root.add_child(dust)
