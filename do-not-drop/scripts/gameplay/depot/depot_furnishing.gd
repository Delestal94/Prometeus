class_name DepotFurnishing
extends RefCounted
## Everything that stands on the depot floor: the stock racking along the left
## wall, the dispatch shelves (whose bins are the order board's slots), the
## workshop, lockers and mirror, break area, supplies counter, office,
## conveyor and the staging area. Static geometry goes into the DepotKit it's
## given; the few live nodes hang from the depot root.

const Layout = preload("res://scripts/gameplay/depot/depot_layout.gd")

## Shelf slots in board order: {"code": "A-1", "transform": Transform3D}.
var slots: Array[Dictionary] = []
## Supply id -> the prop on the counter that shows it was bought.
var supply_props: Dictionary = {}
## The conveyor belt's scrolling material and the boxes riding it (DepotAmbience).
var belt_material: StandardMaterial3D
var belt_boxes: Array[Node3D] = []

var _root: Node3D


func _init(root: Node3D) -> void:
	_root = root


## Builds every area, in the order the batches have always been laid down.
func build(kit: DepotKit) -> void:
	_build_wall_racking(kit)
	_build_dispatch_shelves(kit)
	_build_workshop(kit)
	_build_lockers(kit)
	_build_break_area(kit)
	_build_shop(kit)
	_build_office(kit)
	_build_conveyor(kit)
	_build_staging(kit)


func _build_wall_racking(kit: DepotKit) -> void:
	var blue := DepotKit.flat(Color("2f5d8a"), 0.5, 0.3)
	var orange := DepotKit.flat(Color("e8772e"), 0.5, 0.2)
	var deck := DepotKit.ribbed(Color("9ea6a9"), 0.15, 0.5, 0.4)
	var film := DepotKit.glass(Color(0.85, 0.9, 0.95, 0.35))
	var rng := RandomNumberGenerator.new()
	rng.seed = 4471
	var x_back: float = -Layout.HALF_WIDTH + 0.2
	var x_front: float = -13.5
	var centre_x: float = (x_back + x_front) * 0.5
	var depth: float = x_front - x_back
	var frames: Array[float] = [1.4, 7.0, 12.6, 18.2, 23.8, 29.4]
	var beams: Array[float] = [1.9, 3.8, 5.7]
	for z: float in frames:
		for x: float in [x_back, x_front]:
			kit.box(Vector3(0.1, 6.3, 0.1), Vector3(x, 3.15, z), blue)
		for level: int in range(6):
			kit.box(Vector3(depth, 0.05, 0.05), Vector3(centre_x, 0.5 + level * 1.05, z), blue)
	for bay: int in range(frames.size() - 1):
		var z0: float = frames[bay]
		var z1: float = frames[bay + 1]
		var length: float = z1 - z0
		kit.collider(Vector3(depth + 0.1, 6.3, length),
				Transform3D(Basis.IDENTITY, Vector3(centre_x, 3.15, (z0 + z1) * 0.5)))
		for beam_y: float in beams:
			for x: float in [x_back, x_front]:
				kit.box(Vector3(0.06, 0.12, length), Vector3(x, beam_y, (z0 + z1) * 0.5), orange)
			kit.box(Vector3(depth, 0.03, length - 0.1), Vector3(centre_x, beam_y + 0.07, (z0 + z1) * 0.5), deck)
		for level: int in range(4):
			var base_y: float = Layout.FLOOR_TOP if level == 0 else beams[level - 1] + 0.085
			for spot: int in range(2):
				var z: float = z0 + length * (0.27 + 0.46 * spot)
				_stock_pallet(kit, Vector3(centre_x + 0.05, base_y, z), rng, level == 3, film)


## One pallet position of the stock racking: a pallet with boxes stacked on
## it, a wooden crate, a stretch-wrapped load, or (now and then) nothing.
func _stock_pallet(kit: DepotKit, base: Vector3, rng: RandomNumberGenerator, top_level: bool, film: Material) -> void:
	var roll: float = rng.randf()
	if roll < 0.08:
		return
	var yaw: float = PI * 0.5 + rng.randf_range(-0.05, 0.05)
	kit.model_grounded(Layout.PALLET, Transform3D(Basis(Vector3.UP, yaw), base))
	var top: Vector3 = base + Vector3(0.0, 0.1, 0.0)
	if roll < 0.3:
		kit.model_grounded(Layout.CRATE,
				Transform3D(Basis(Vector3.UP, yaw + rng.randf_range(-0.1, 0.1)).scaled(Vector3.ONE * 0.95), top))
		return
	var layers: int = 1 if top_level else rng.randi_range(1, 2)
	var box_path: String = Layout.CARGO_BOXES[rng.randi() % Layout.CARGO_BOXES.size()]
	var bounds: AABB = kit.model_bounds(box_path)
	var scale: float = clampf(0.55 / maxf(bounds.size.x, bounds.size.z), 0.4, 1.0)
	var height: float = bounds.size.y * scale
	for layer: int in range(layers):
		for ix: int in range(2):
			for iz: int in range(2):
				if rng.randf() < 0.08 and layer == layers - 1:
					continue
				var offset := Vector3((ix - 0.5) * 0.6, layer * height, (iz - 0.5) * 0.5)
				kit.model(box_path,
						Transform3D(Basis(Vector3.UP, rng.randf_range(-0.08, 0.08)).scaled(Vector3.ONE * scale),
						top + offset.rotated(Vector3.UP, yaw)))
	if roll > 0.75:
		# Stretch wrap around the whole load.
		kit.box(Vector3(1.24, height * layers + 0.04, 1.04), top + Vector3(0.0, (height * layers) * 0.5, 0.0), film,
				false, yaw)


func _build_dispatch_shelves(kit: DepotKit) -> void:
	var blue := DepotKit.flat(Color("2f5d8a"), 0.5, 0.3)
	var orange := DepotKit.flat(Color("e8772e"), 0.5, 0.2)
	var deck := DepotKit.ribbed(Color("a9b0b3"), 0.12, 0.5, 0.4)
	var length: float = Layout.BAY_LENGTH * Layout.BAYS
	for unit: Dictionary in Layout.SHELF_UNITS:
		var x: float = float(unit.x)
		for frame: int in range(Layout.BAYS + 1):
			var z: float = Layout.SHELF_START_Z + frame * Layout.BAY_LENGTH
			for side: float in [-1.0, 1.0]:
				kit.box(Vector3(0.08, 2.7, 0.08), Vector3(x + side * Layout.SHELF_DEPTH * 0.5, 1.35, z), blue, true)
			kit.box(Vector3(Layout.SHELF_DEPTH, 0.04, 0.04), Vector3(x, 0.9, z), blue)
			kit.box(Vector3(Layout.SHELF_DEPTH, 0.04, 0.04), Vector3(x, 2.1, z), blue)
		for deck_top: float in Layout.LEVEL_TOPS + [2.6]:
			for side: float in [-1.0, 1.0]:
				kit.box(Vector3(0.05, 0.1, length),
						Vector3(x + side * (Layout.SHELF_DEPTH * 0.5 - 0.02), deck_top - 0.07,
						Layout.SHELF_START_Z + length * 0.5), orange)
			kit.box(Vector3(Layout.SHELF_DEPTH - 0.04, 0.04, length),
					Vector3(x, deck_top - 0.02, Layout.SHELF_START_Z + length * 0.5), deck, true)
		# Loose small stock on the top deck, out of reach and just for show.
		var rng := RandomNumberGenerator.new()
		rng.seed = 90 + int(x)
		for bay: int in range(Layout.BAYS):
			var z: float = Layout.SHELF_START_Z + (bay + 0.5) * Layout.BAY_LENGTH
			for count: int in range(rng.randi_range(1, 3)):
				var path: String = Layout.CARGO_BOXES[rng.randi() % Layout.CARGO_BOXES.size()]
				kit.model(path,
						Transform3D(Basis(Vector3.UP, rng.randf_range(-0.3, 0.3)).scaled(Vector3.ONE * 0.5),
						Vector3(x + rng.randf_range(-0.2, 0.2), 2.6, z + (count - 1) * 0.55)))
		# Every bay-level is a slot, labelled on both faces of the shelf.
		for level: int in range(Layout.LEVEL_TOPS.size()):
			for bay: int in range(Layout.BAYS):
				var number: int = level * Layout.BAYS + bay + 1
				var code: String = "%s-%d" % [unit.aisle, number]
				var z: float = Layout.SHELF_START_Z + (bay + 0.5) * Layout.BAY_LENGTH
				slots.append({"code": code,
						"transform": Transform3D(Basis.IDENTITY, Vector3(x, Layout.LEVEL_TOPS[level], z))})
				for side: float in [-1.0, 1.0]:
					var face: float = x + side * (Layout.SHELF_DEPTH * 0.5 + 0.02)
					var tag := DepotLabels.text(_root, code, Vector3(face, Layout.LEVEL_TOPS[level] - 0.07, z),
							side * PI * 0.5, 30, Layout.INK, Layout.DISPLAY_FONT, 0.004, 0)
					tag.name = "Tag%s_%d" % [code, 0 if side < 0 else 1]
					# The card's face 6 mm behind the words: it used to stand 1 mm
					# in front of them, and they flickered through it.
					kit.box(Vector3(0.012, 0.09, 0.36),
							Vector3(face - side * 0.012, Layout.LEVEL_TOPS[level] - 0.07, z),
							DepotKit.flat(Layout.PAPER, 0.8))
		# Aisle sign hanging over the unit.
		# Named as the board reads ("ESTANTE A-3").
		DepotLabels.hanging_sign(_root, kit, tr("WORLD_DEPOT_SIGN_SHELF") % unit.aisle,
				Vector3(x, 3.7, Layout.SHELF_START_Z + length * 0.5), PI * 0.5, Layout.SHELVES_BLUE)


func _build_workshop(kit: DepotKit) -> void:
	var red := DepotKit.flat(Color("c0392b"), 0.45, 0.2)
	var dark := DepotKit.flat(Color("263238"), 0.7)
	var steel := DepotKit.flat(Color("8a9499"), 0.35, 0.7)
	var wood := DepotKit.detailed(Color("b08a5a"), "wood_planks", 1.2)
	var pegboard := DepotKit.flat(Color("cfb58b"), 0.9)
	# Workbench against the right wall, pegboard with tools above it.
	kit.box(Vector3(0.9, 0.08, 4.0), Vector3(14.4, 0.95, 5.5), wood, true)
	for z: float in [3.7, 7.3]:
		kit.box(Vector3(0.8, 0.9, 0.06), Vector3(14.4, 0.48, z), dark)
	kit.box(Vector3(0.8, 0.5, 3.4), Vector3(14.4, 0.55, 5.5), dark)
	kit.box(Vector3(0.04, 1.3, 3.8), Vector3(14.93, 1.85, 5.5), pegboard)
	for index: int in range(9):
		var z: float = 3.9 + index * 0.4
		var tool_height: float = 0.25 + (index % 3) * 0.12
		kit.box(Vector3(0.04, tool_height, 0.05), Vector3(14.88, 2.0 - tool_height * 0.2, z),
				steel if index % 2 == 0 else red)
	kit.cylinder(0.12, 0.14, Transform3D(Basis(Vector3.FORWARD, PI * 0.5), Vector3(14.1, 1.07, 6.8)),
			DepotKit.flat(Color("ffc93c"), 0.5), 12)  # tape roll
	kit.box(Vector3(0.3, 0.2, 0.45), Vector3(14.3, 1.09, 4.4), red)  # toolbox
	# Rolling tool chest.
	kit.box(Vector3(0.7, 1.1, 1.2), Vector3(14.4, 0.6, 9.0), red, true)
	for drawer: int in range(5):
		kit.box(Vector3(0.02, 0.03, 1.0), Vector3(14.04, 0.3 + drawer * 0.2, 9.0), steel)
	# Paint station: cans on a rack and swatches of what the truck can wear.
	kit.box(Vector3(0.5, 1.6, 2.0), Vector3(14.65, 0.8, 11.6), dark, true)
	var paints: Array[Color] = [Color("dde2e8"), Color("7b52b9"), Color("2dd4a3"), Color("ff5e5b"), Color("ffc93c"),
			Color("4cc9f0")]
	for index: int in range(paints.size()):
		for level: int in range(2):
			kit.cylinder(0.11, 0.24,
					Transform3D(Basis.IDENTITY, Vector3(14.35, 0.5 + level * 0.6, 10.85 + index * 0.3)),
					DepotKit.flat(paints[(index + level) % paints.size()], 0.5, 0.3), 10)
	for index: int in range(paints.size()):
		kit.box(Vector3(0.02, 0.45, 0.45), Vector3(14.9, 3.0, 9.2 + index * 0.55), DepotKit.flat(paints[index], 0.6))
	# Air compressor with its hose reel.
	kit.cylinder(0.3, 1.0, Transform3D(Basis(Vector3.FORWARD, PI * 0.5), Vector3(13.1, 0.4, 2.2)), red, 14, true)
	kit.box(Vector3(0.4, 0.3, 0.3), Vector3(13.1, 0.85, 2.2), dark)
	kit.cylinder(0.22, 0.1, Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(14.9, 1.6, 1.5)),
			DepotKit.flat(Color("ffc93c"), 0.6), 14)
	_build_workshop_floor(kit)
	_build_workshop_kiosk()
	DepotLabels.hanging_sign(_root, kit, tr("WORLD_DEPOT_WORKSHOP"), Vector3(11.5, 3.9, 6.0), 0.0, Layout.WORKSHOP_RED)


## The workshop's own floor (sealed dark concrete with a red border, so the
## area reads as a place and not as more hall), a red band on the wall behind
## it, a work lamp over the bench, an oil drum and a stack of spare tyres.
func _build_workshop_floor(kit: DepotKit) -> void:
	var area: Rect2 = Layout.WORKSHOP_FLOOR
	var centre: Vector2 = area.get_center()
	var epoxy := BoxMesh.new()
	epoxy.size = Vector3(area.size.x, 0.008, area.size.y)
	kit.add_mesh(epoxy, Transform3D(Basis.IDENTITY, Vector3(centre.x, Layout.FLOOR_TOP + 0.004, centre.y)),
			DepotKit.detailed(Color("59636a"), "plaster", 2.0, 0.45), false)
	var border := DepotKit.flat(Layout.WORKSHOP_RED, 0.6)
	for edge: Array in [[Vector3(area.size.x, 0.004, 0.1), Vector3(centre.x, 0.0, area.position.y + 0.05)],
			[Vector3(area.size.x, 0.004, 0.1), Vector3(centre.x, 0.0, area.end.y - 0.05)],
			[Vector3(0.1, 0.004, area.size.y), Vector3(area.position.x + 0.05, 0.0, centre.y)]]:
		var line := BoxMesh.new()
		line.size = edge[0]
		var line_at: Vector3 = (edge[1] as Vector3) + Vector3(0.0, Layout.FLOOR_TOP + 0.01, 0.0)
		kit.add_mesh(line, Transform3D(Basis.IDENTITY, line_at), border, false)
	kit.box(Vector3(0.02, 0.16, area.size.y), Vector3(Layout.HALF_WIDTH - 0.07, Layout.LINER_SPLIT - 0.12, centre.y),
			border)
	kit.box(Vector3(0.3, 0.06, 1.6), Vector3(14.3, 2.9, 5.5), DepotKit.flat(Color("263238"), 0.5, 0.4))
	kit.box(Vector3(0.24, 0.02, 1.5), Vector3(14.3, 2.865, 5.5), DepotKit.glow(Color("fff1d6"), 2.0))
	var bench_lamp := OmniLight3D.new()
	bench_lamp.name = "WorkshopLamp"
	bench_lamp.position = Vector3(14.0, 2.6, 5.5)
	bench_lamp.light_color = Color("fff1d6")
	bench_lamp.light_energy = 0.8
	bench_lamp.omni_range = 3.5
	_root.add_child(bench_lamp)
	var floor_y: float = Layout.FLOOR_TOP
	kit.cylinder(0.29, 0.88, Transform3D(Basis.IDENTITY, Vector3(14.45, 0.44 + floor_y, 0.55)),
			DepotKit.flat(Color("2f5d8a"), 0.5, 0.3), 16, true)
	kit.cylinder(0.3, 0.03, Transform3D(Basis.IDENTITY, Vector3(14.45, 0.895 + floor_y, 0.55)),
			DepotKit.flat(Color("c9ced0"), 0.4, 0.6), 16)
	for index: int in range(3):
		var tyre_at := Vector3(11.4, 0.1 + index * 0.21 + floor_y, 0.75)
		kit.cylinder(0.34, 0.2, Transform3D(Basis.IDENTITY, tyre_at), DepotKit.flat(Color("1b1f22"), 0.9), 16,
				index == 0)
		kit.cylinder(0.18, 0.205, Transform3D(Basis.IDENTITY, tyre_at), DepotKit.flat(Color("8a9499"), 0.4, 0.6), 12)


## A proper terminal instead of a box with a screen: plinth, slim column, a
## tilted screen in a bezel with a red header. Every word on it is fitted to
## the glass (DepotLabels.fit_label), so no language runs off the edge.
func _build_workshop_kiosk() -> void:
	var kiosk := Node3D.new()
	kiosk.name = "WorkshopKiosk"
	kiosk.position = Layout.KIOSK_AT + Vector3(0.0, Layout.FLOOR_TOP, 0.0)
	# Its front (local +Z) toward the hall, -X.
	kiosk.rotation.y = -PI * 0.5
	_root.add_child(kiosk)
	var kit := DepotKit.new(kiosk, "KioskColliders")
	var body := DepotKit.flat(Color("2b3338"), 0.45, 0.35)
	kit.box(Vector3(0.8, 0.06, 0.6), Vector3(0.0, 0.03, 0.0), body)
	kit.box(Vector3(0.36, 1.0, 0.26), Vector3(0.0, 0.56, -0.04), body, true)
	kit.box(Vector3(0.37, 0.05, 0.27), Vector3(0.0, 0.3, -0.04), DepotKit.flat(Layout.WORKSHOP_RED, 0.45, 0.2))
	var head := Node3D.new()
	head.name = "Head"
	head.position = Vector3(0.0, 1.38, 0.0)
	head.rotation.x = deg_to_rad(-18.0)
	kiosk.add_child(head)
	var head_kit := DepotKit.new(head, "KioskHeadColliders")
	var screen := Vector2(0.78, 0.54)
	head_kit.box(Vector3(screen.x + 0.08, screen.y + 0.08, 0.07), Vector3.ZERO, body)
	head_kit.box(Vector3(screen.x, screen.y, 0.01), Vector3(0.0, 0.0, 0.04), DepotKit.glow(Color("1d2b33"), 1.0))
	head_kit.box(Vector3(screen.x, 0.14, 0.012), Vector3(0.0, screen.y * 0.5 - 0.07, 0.042),
			DepotKit.glow(Layout.WORKSHOP_RED, 1.0))
	# Paint swatches along the bottom of the screen: what the truck can wear.
	var swatches: Array[Color] = [Color("dde2e8"), Color("7b52b9"), Color("2dd4a3"), Color("ff5e5b"), Color("ffc93c"),
			Color("4cc9f0")]
	for index: int in range(swatches.size()):
		var x: float = (index - (swatches.size() - 1) * 0.5) * 0.11
		head_kit.box(Vector3(0.08, 0.06, 0.012), Vector3(x, -screen.y * 0.5 + 0.08, 0.042),
				DepotKit.glow(swatches[index], 1.0))
	head_kit.commit("KioskHead")
	kit.commit("Kiosk")
	var title := DepotLabels.text(head, tr("WORLD_DEPOT_WORKSHOP"), Vector3(0.0, screen.y * 0.5 - 0.07, 0.05), 0.0, 40,
			Layout.PAPER, Layout.DISPLAY_FONT, 0.004, 0)
	title.name = "KioskTitle"
	DepotLabels.fit_label(title, screen.x - 0.1)
	var sub := DepotLabels.text(head, tr("WORLD_DEPOT_WORKSHOP_SUB"), Vector3(0.0, 0.02, 0.05), 0.0, 26,
			Color("cfe8f2"), Layout.BODY_FONT, 0.004, 0)
	sub.name = "KioskSubtitle"
	DepotLabels.fit_label(sub, screen.x - 0.12)


func _build_lockers(kit: DepotKit) -> void:
	var colours: Array[Color] = [Color("3f7f8c"), Color("4f8f9c")]
	var dark := DepotKit.flat(Color("263238"), 0.7)
	var handle := DepotKit.flat(Color("c9ced0"), 0.3, 0.8)
	for index: int in range(8):
		var z: float = 13.3 + index * 0.62
		var body := DepotKit.ribbed(colours[index % 2], 0.08, 0.5, 0.3)
		kit.box(Vector3(0.55, 1.95, 0.58), Vector3(14.68, 1.0, z), body)
		# Door slots, a handle and a name card on each.
		for vent: int in range(3):
			kit.box(Vector3(0.01, 0.02, 0.3), Vector3(14.4, 1.7 - vent * 0.05, z), dark)
		kit.box(Vector3(0.03, 0.14, 0.03), Vector3(14.39, 1.05, z + 0.18), handle)
		kit.box(Vector3(0.01, 0.07, 0.2), Vector3(14.4, 1.45, z), DepotKit.flat(Layout.PAPER, 0.8))
	kit.collider(Vector3(0.58, 2.0, 5.0), Transform3D(Basis.IDENTITY, Vector3(14.68, 1.0, 13.3 + 3.5 * 0.62)))
	# Bench in front of them, and a full-length mirror (a real one: DepotMirror)
	# at the end of the row, to check the uniform.
	kit.box(Vector3(0.4, 0.06, 3.2), Vector3(13.4, 0.46, 15.5), DepotKit.detailed(Color("b08a5a"), "wood_planks", 1.0),
			true)
	for z: float in [14.2, 16.8]:
		kit.box(Vector3(0.3, 0.44, 0.06), Vector3(13.4, 0.22, z), dark)
	# Clear of the lining (to x 14.94) and of the column at z 19.05.
	kit.box(Vector3(0.05, 2.0, 0.9), Vector3(14.91, 1.1, 18.5), dark)
	var mirror := DepotMirror.new()
	mirror.name = "Mirror"
	mirror.glass_size = Vector2(0.8, 1.9)
	mirror.position = Vector3(14.875, 1.1, 18.5)
	mirror.rotation.y = -PI * 0.5
	_root.add_child(mirror)
	# A vanity lamp over it, so the uniform reads even on a dark day.
	kit.box(Vector3(0.12, 0.06, 0.7), Vector3(14.85, 2.14, 18.5), DepotKit.glow(Color("fff1d6"), 2.0), false)
	var vanity := OmniLight3D.new()
	vanity.name = "MirrorLamp"
	vanity.position = Vector3(14.3, 2.1, 18.5)
	vanity.light_color = Color("fff1d6")
	vanity.light_energy = 0.9
	vanity.omni_range = 2.6
	_root.add_child(vanity)
	# Rubber mat under the bench, the row's own floor.
	var mat := BoxMesh.new()
	mat.size = Vector3(2.3, 0.008, 5.6)
	kit.add_mesh(mat, Transform3D(Basis.IDENTITY, Vector3(13.55, Layout.FLOOR_TOP + 0.004, 15.6)),
			DepotKit.detailed(Color("35494f"), "plaster", 0.8, 0.95), false)
	# On top of the lockers: hard hats and folded hi-vis vests, turn about.
	var helmet := SphereMesh.new()
	helmet.radius = 0.14
	helmet.height = 0.14
	helmet.is_hemisphere = true
	helmet.radial_segments = 12
	helmet.rings = 4
	for index: int in range(8):
		var z: float = 13.3 + index * 0.62
		if index % 2 == 0:
			kit.add_mesh(helmet, Transform3D(Basis.IDENTITY, Vector3(14.62, 1.975, z)),
					DepotKit.flat(Color("ffc93c") if index % 4 == 0 else Layout.PAPER, 0.4))
		else:
			kit.box(Vector3(0.34, 0.08, 0.3), Vector3(14.62, 2.015, z), DepotKit.flat(Color("ff9f1c"), 0.8))
			kit.box(Vector3(0.345, 0.02, 0.05), Vector3(14.62, 2.03, z), DepotKit.flat(Color("e8ebe4"), 0.4))
	# Laundry hamper at the start of the row.
	kit.cylinder(0.24, 0.62, Transform3D(Basis.IDENTITY, Vector3(13.8, 0.31 + Layout.FLOOR_TOP, 12.75)),
			DepotKit.flat(Color("3f7f8c"), 0.8), 14, true)
	kit.box(Vector3(0.3, 0.12, 0.26), Vector3(13.8, 0.66, 12.75), DepotKit.flat(Color("ff9f1c"), 0.9), false, 0.3)
	# High enough to hang clear over the photo wall behind it.
	DepotLabels.hanging_sign(_root, kit, tr("WORLD_DEPOT_LOCKERS"), Vector3(13.2, 4.25, 15.5), -PI * 0.5,
			Layout.LOCKERS_TEAL)


func _build_break_area(kit: DepotKit) -> void:
	var dark := DepotKit.flat(Color("263238"), 0.7)
	# Coffee machine: body, glowing panel, drip tray and a cup.
	kit.box(Vector3(0.6, 1.8, 0.7), Vector3(14.6, 0.9, 20.2), DepotKit.flat(Color("8c2f39"), 0.4, 0.2), true)
	kit.box(Vector3(0.02, 0.5, 0.45), Vector3(14.29, 1.35, 20.2), DepotKit.glow(Color("ffd08a"), 0.9))
	kit.box(Vector3(0.12, 0.03, 0.3), Vector3(14.26, 0.75, 20.2), dark)
	kit.cylinder(0.04, 0.09, Transform3D(Basis.IDENTITY, Vector3(14.24, 0.81, 20.2)), DepotKit.flat(Layout.PAPER, 0.7),
			10)
	DepotLabels.text(_root, tr("WORLD_DEPOT_COFFEE"), Vector3(14.28, 1.7, 20.2), -PI * 0.5, 40, Layout.PAPER,
			Layout.DISPLAY_FONT, 0.004, 4)
	# Water cooler.
	kit.box(Vector3(0.4, 1.0, 0.4), Vector3(14.6, 0.5, 21.2), DepotKit.flat(Color("e8ebe4"), 0.6), true)
	kit.cylinder(0.17, 0.45, Transform3D(Basis.IDENTITY, Vector3(14.6, 1.25, 21.2)),
			DepotKit.glass(Color(0.55, 0.78, 0.95, 0.55)), 14)
	# Round table with two stools.
	kit.cylinder(0.55, 0.05, Transform3D(Basis.IDENTITY, Vector3(12.6, 0.95, 20.8)),
			DepotKit.flat(Color("e8ebe4"), 0.5), 18, true)
	kit.cylinder(0.05, 0.92, Transform3D(Basis.IDENTITY, Vector3(12.6, 0.47, 20.8)), dark, 8)
	for offset: Vector3 in [Vector3(-0.8, 0.0, 0.1), Vector3(0.2, 0.0, 0.8)]:
		kit.cylinder(0.2, 0.05, Transform3D(Basis.IDENTITY, Vector3(12.6, 0.62, 20.8) + offset),
				DepotKit.flat(Color("e8772e"), 0.6), 12)
		kit.cylinder(0.03, 0.6, Transform3D(Basis.IDENTITY, Vector3(12.6, 0.31, 20.8) + offset), dark, 6)
	kit.cylinder(0.045, 0.1, Transform3D(Basis.IDENTITY, Vector3(12.45, 1.02, 20.7)),
			DepotKit.flat(Color("4cc9f0"), 0.6), 10)
	# The radio on the table that plays all day.
	kit.box(Vector3(0.34, 0.2, 0.14), Vector3(12.8, 1.07, 21.0), DepotKit.flat(Color("2f7a64"), 0.5), false, 0.4)
	kit.cylinder(0.06, 0.02,
			Transform3D(Basis(Vector3.RIGHT, PI * 0.5).rotated(Vector3.UP, 0.4), Vector3(12.76, 1.07, 20.93)), dark, 12)


func _build_shop(kit: DepotKit) -> void:
	var counter := DepotKit.detailed(Color("b08a5a"), "wood_planks", 1.0)
	var top := DepotKit.flat(Color("263238"), 0.5, 0.2)
	var shelf := DepotKit.flat(Color("59656a"), 0.5, 0.4)
	# Counter along X, the clerk behind it (toward +Z).
	kit.box(Vector3(4.6, 1.0, 0.6), Vector3(10.8, 0.5, 24.0), counter, true)
	kit.box(Vector3(4.8, 0.06, 0.72), Vector3(10.8, 1.03, 24.0), top)
	kit.box(Vector3(0.36, 0.22, 0.3), Vector3(9.6, 1.17, 24.05), DepotKit.flat(Color("2a3439"), 0.5))  # till
	kit.box(Vector3(0.3, 0.02, 0.2), Vector3(9.6, 1.29, 23.98), DepotKit.glow(Color("2dd4a3"), 0.8), false, 0.0)
	# What it sells, on the shelves behind: bubble wrap, tape, foam, straps.
	kit.box(Vector3(4.6, 2.2, 0.5), Vector3(10.8, 1.1, 26.9), shelf, true)
	for level: int in range(3):
		kit.box(Vector3(4.6, 0.04, 0.55), Vector3(10.8, 0.45 + level * 0.7, 26.8), top)
		for index: int in range(7):
			var x: float = 8.9 + index * 0.62
			match (index + level) % 3:
				0:
					kit.cylinder(0.2, 0.5,
							Transform3D(Basis(Vector3.FORWARD, PI * 0.5), Vector3(x, 0.67 + level * 0.7, 26.75)),
							DepotKit.glass(Color(0.85, 0.92, 0.98, 0.6)), 12)
				1:
					kit.cylinder(0.11, 0.08,
							Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(x, 0.58 + level * 0.7, 26.7)),
							DepotKit.flat(Color("e0a867"), 0.5), 12)
				_:
					kit.box(Vector3(0.45, 0.3, 0.4), Vector3(x, 0.62 + level * 0.7, 26.75),
							DepotKit.flat(Color("7fa7b5") if level == 1 else Color("e8772e"), 0.9))
	# The supplies that are bought wait on the counter, ready to go.
	for supply: Array in [[&"padding", Vector3(11.6, 1.25, 23.9), Color("7fa7b5")],
			[&"insurance", Vector3(12.4, 1.1, 23.95), Layout.PAPER]]:
		var prop := MeshInstance3D.new()
		prop.name = "Supply_%s" % supply[0]
		var mesh := BoxMesh.new()
		mesh.size = Vector3(0.5, 0.4, 0.4) if supply[0] == &"padding" else Vector3(0.3, 0.02, 0.22)
		prop.mesh = mesh
		prop.material_override = DepotKit.flat(supply[2], 0.8)
		prop.position = supply[1]
		prop.visible = false
		_root.add_child(prop)
		supply_props[supply[0]] = prop
	DepotLabels.hanging_sign(_root, kit, tr("WORLD_DEPOT_SUPPLIES"), Vector3(10.8, 3.4, 24.0), PI, Layout.SHOP_PURPLE)


func _build_office(kit: DepotKit) -> void:
	var frame := DepotKit.flat(Color("263238"), 0.6, 0.3)
	var panel := DepotKit.detailed(Color("d5d9d2"), "plaster", 1.6)
	var glass := DepotKit.glass()
	var x0: float = 8.6
	var z0: float = 27.8
	# Front wall (toward -Z) and side wall (toward -X): solid below, glazed above.
	kit.box(Vector3(Layout.HALF_WIDTH - x0, 1.0, 0.12), Vector3((x0 + Layout.HALF_WIDTH) * 0.5, 0.5, z0), panel, true)
	kit.box(Vector3(Layout.HALF_WIDTH - x0, 1.4, 0.04), Vector3((x0 + Layout.HALF_WIDTH) * 0.5, 1.7, z0), glass, true)
	kit.box(Vector3(Layout.HALF_WIDTH - x0, 0.6, 0.12), Vector3((x0 + Layout.HALF_WIDTH) * 0.5, 2.7, z0), panel, true)
	kit.box(Vector3(0.12, 1.0, Layout.DEPTH - z0 - 1.3), Vector3(x0, 0.5, z0 + (Layout.DEPTH - z0 - 1.3) * 0.5), panel,
			true)
	kit.box(Vector3(0.04, 1.4, Layout.DEPTH - z0 - 1.3), Vector3(x0, 1.7, z0 + (Layout.DEPTH - z0 - 1.3) * 0.5), glass,
			true)
	kit.box(Vector3(0.12, 0.6, Layout.DEPTH - z0), Vector3(x0, 2.7, (z0 + Layout.DEPTH) * 0.5), panel)
	kit.box(Vector3(0.12, 2.4, 0.12), Vector3(x0, 1.2, Layout.DEPTH - 1.3), frame)
	var door_z: float = Layout.DEPTH - 0.8
	kit.box(Vector3(0.05, 2.1, 0.9), Vector3(x0 - 0.02, 1.05 + Layout.FLOOR_TOP, door_z),
			DepotKit.flat(Color("2f7a64"), 0.6))
	# The door's frame, a handle and a mat, so the way in reads from the hall.
	for z: float in [Layout.DEPTH - 1.29, Layout.DEPTH - 0.31]:
		kit.box(Vector3(0.14, 2.2, 0.08), Vector3(x0 - 0.02, 1.1 + Layout.FLOOR_TOP, z), frame)
	kit.box(Vector3(0.14, 0.1, 1.06), Vector3(x0 - 0.02, 2.2 + Layout.FLOOR_TOP, door_z), frame)
	kit.box(Vector3(0.05, 0.04, 0.16), Vector3(x0 - 0.07, 1.05, Layout.DEPTH - 1.1),
			DepotKit.flat(Color("c9ced0"), 0.3, 0.8))
	var mat := BoxMesh.new()
	mat.size = Vector3(0.9, 0.008, 1.0)
	kit.add_mesh(mat, Transform3D(Basis.IDENTITY, Vector3(x0 - 0.6, Layout.FLOOR_TOP + 0.004, door_z)),
			DepotKit.flat(Color("2b3136"), 0.95), false)
	var plate := DepotLabels.text(_root, tr("WORLD_DEPOT_OFFICE"), Vector3(x0 - 0.08, 2.55, door_z), -PI * 0.5, 36,
			Layout.PAPER, Layout.DISPLAY_FONT, 0.005, 8)
	plate.name = "OfficeDoorSign"
	DepotLabels.fit_label(plate, 1.0)
	kit.box(Vector3(Layout.HALF_WIDTH - x0 + 0.1, 0.1, Layout.DEPTH - z0 + 0.1),
			Vector3((x0 + Layout.HALF_WIDTH) * 0.5, 3.05, (z0 + Layout.DEPTH) * 0.5), frame)
	for x: float in [x0, 11.0, 13.2]:
		kit.box(Vector3(0.06, 1.44, 0.14), Vector3(x, 1.7, z0), frame)
	# Desk with the dispatch computer, a chair and a filing cabinet.
	kit.box(Vector3(2.0, 0.06, 0.8), Vector3(11.6, 0.76, 30.6), DepotKit.detailed(Color("b08a5a"), "wood_planks", 1.0),
			true)
	for x: float in [10.7, 12.5]:
		kit.box(Vector3(0.06, 0.74, 0.7), Vector3(x, 0.38, 30.6), frame)
	kit.box(Vector3(0.6, 0.38, 0.05), Vector3(11.4, 1.1, 30.85), frame)
	kit.box(Vector3(0.54, 0.32, 0.02), Vector3(11.4, 1.1, 30.82), DepotKit.glow(Color("8fd3e8"), 0.9))
	kit.box(Vector3(0.45, 0.02, 0.15), Vector3(11.4, 0.8, 30.35), frame)
	kit.box(Vector3(0.5, 1.3, 0.6), Vector3(14.5, 0.65, 29.2), DepotKit.flat(Color("8a9499"), 0.4, 0.5), true)
	kit.box(Vector3(0.04, 0.9, 1.4), Vector3(14.95, 1.8, 30.6), DepotKit.flat(Color("c9a26b"), 0.9))  # corkboard
	for index: int in range(5):
		kit.box(Vector3(0.01, 0.22, 0.18), Vector3(14.92, 1.65 + (index % 2) * 0.35, 30.1 + index * 0.24),
				DepotKit.flat(Layout.PAPER, 0.9))
	DepotLabels.hanging_sign(_root, kit, tr("WORLD_DEPOT_OFFICE"), Vector3(11.8, 3.5, z0 - 0.1), PI, Color("263238"))


func _build_conveyor(kit: DepotKit) -> void:
	var frame := DepotKit.flat(Color("59656a"), 0.45, 0.5)
	var guard := DepotKit.flat(Color("e7be51"), 0.6)
	var length: float = Layout.CONVEYOR_END_X - Layout.CONVEYOR_START_X
	var centre: float = (Layout.CONVEYOR_START_X + Layout.CONVEYOR_END_X) * 0.5
	kit.box(Vector3(length, 0.14, 0.9), Vector3(centre, 0.84, Layout.CONVEYOR_Z), frame, true)
	for x: float in range(int(Layout.CONVEYOR_START_X) + 1, int(Layout.CONVEYOR_END_X), 2):
		for z: float in [Layout.CONVEYOR_Z - 0.4, Layout.CONVEYOR_Z + 0.4]:
			kit.box(Vector3(0.08, 0.8, 0.08), Vector3(x, 0.4, z), frame)
	for z: float in [Layout.CONVEYOR_Z - 0.47, Layout.CONVEYOR_Z + 0.47]:
		kit.box(Vector3(length, 0.12, 0.05), Vector3(centre, 1.0, z), guard)
	# Portals at each end with PVC strip curtains: stock appears from one and
	# disappears into the other.
	for x: float in [Layout.CONVEYOR_START_X, Layout.CONVEYOR_END_X]:
		kit.box(Vector3(1.2, 1.3, 1.3), Vector3(x, 1.55, Layout.CONVEYOR_Z), DepotKit.ribbed(Color("3b4c53"), 0.4),
				true)
		kit.box(Vector3(1.2, 0.9, 1.3), Vector3(x, 0.45, Layout.CONVEYOR_Z), frame)
		var face: float = x + (0.61 if x < 0.0 else -0.61)
		for strip: int in range(6):
			kit.box(Vector3(0.01, 0.6, 0.14), Vector3(face, 1.2, Layout.CONVEYOR_Z - 0.4 + strip * 0.16),
					DepotKit.glass(Color(0.75, 0.85, 0.8, 0.5)))
	# The belt itself scrolls (DepotAmbience); its boxes ride it.
	var belt := MeshInstance3D.new()
	belt.name = "ConveyorBelt"
	var belt_mesh := BoxMesh.new()
	belt_mesh.size = Vector3(length, 0.02, 0.8)
	belt.mesh = belt_mesh
	belt_material = StandardMaterial3D.new()
	belt_material.albedo_color = Color("3a3f42")
	belt_material.albedo_texture = DepotKit._rib_texture()
	belt_material.uv1_scale = Vector3(length * 2.0, 1.0, 1.0)
	belt_material.roughness = 0.9
	belt.material_override = belt_material
	belt.position = Vector3(centre, 0.92, Layout.CONVEYOR_Z)
	_root.add_child(belt)
	var rng := RandomNumberGenerator.new()
	rng.seed = 17
	for index: int in range(9):
		var box_path: String = Layout.CARGO_BOXES[index % Layout.CARGO_BOXES.size()]
		var box := (load(box_path) as PackedScene).instantiate() as Node3D
		LowpolyMaterials.apply(box)
		box.name = "BeltBox%d" % index
		box.scale = Vector3.ONE * 0.6
		box.rotation.y = rng.randf_range(-0.2, 0.2)
		box.position = Vector3(Layout.CONVEYOR_START_X + 0.4 + index * (length / 9.0), 0.93,
				Layout.CONVEYOR_Z + rng.randf_range(-0.12, 0.12))
		_root.add_child(box)
		belt_boxes.append(box)


func _build_staging(kit: DepotKit) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 311
	var film := DepotKit.glass(Color(0.85, 0.9, 0.95, 0.35))
	# Pallets waiting to be put away, between the shelves and the belt.
	for spot: Vector3 in [Vector3(-5.2, Layout.FLOOR_TOP, 27.6), Vector3(-3.4, Layout.FLOOR_TOP, 27.6),
			Vector3(-5.2, Layout.FLOOR_TOP, 29.3)]:
		_stock_pallet(kit, spot, rng, false, film)
		kit.collider(Vector3(1.25, 1.5, 0.9), Transform3D(Basis.IDENTITY, spot + Vector3(0.0, 0.75, 0.0)))
	# Empty pallets stacked by the wall.
	for layer: int in range(6):
		kit.model_grounded(Layout.PALLET,
				Transform3D(Basis(Vector3.UP, rng.randf_range(-0.06, 0.06)),
				Vector3(-1.4, Layout.FLOOR_TOP + layer * 0.1, 31.3)))
	kit.collider(Vector3(1.3, 0.62, 0.9), Transform3D(Basis.IDENTITY, Vector3(-1.4, 0.31, 31.3)))
	# Packing table: cardboard, a tape gun and a roll of labels.
	var wood := DepotKit.detailed(Color("b08a5a"), "wood_planks", 1.2)
	kit.box(Vector3(2.4, 0.06, 1.0), Vector3(2.2, 0.9, 27.4), wood, true)
	for x: float in [1.1, 3.3]:
		for z: float in [27.0, 27.8]:
			kit.box(Vector3(0.06, 0.88, 0.06), Vector3(x, 0.44, z), DepotKit.flat(Color("59656a"), 0.5, 0.4))
	kit.model(Layout.CARGO_BOXES[0],
			Transform3D(Basis(Vector3.UP, 0.2).scaled(Vector3.ONE * 0.7), Vector3(1.6, 0.93, 27.4)))
	kit.box(Vector3(0.7, 0.01, 0.5), Vector3(2.5, 0.935, 27.3), DepotKit.flat(Color("e0a867"), 0.9), false, -0.15)
	kit.box(Vector3(0.12, 0.16, 0.2), Vector3(2.95, 1.0, 27.5), DepotKit.flat(Color("c0392b"), 0.5))
	kit.cylinder(0.08, 0.07, Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(3.2, 0.98, 27.1)),
			DepotKit.flat(Layout.PAPER, 0.7), 12)
	# Pallet jack parked beside it.
	var dark := DepotKit.flat(Color("263238"), 0.6)
	for x: float in [4.3, 4.75]:
		kit.box(Vector3(0.16, 0.08, 1.15), Vector3(x, 0.08, 26.4), DepotKit.flat(Color("e8772e"), 0.5))
	kit.box(Vector3(0.6, 0.3, 0.25), Vector3(4.52, 0.2, 27.1), DepotKit.flat(Color("e8772e"), 0.5))
	kit.box(Vector3(0.05, 1.0, 0.05), Vector3(4.52, 0.75, 27.35), dark, false, 0.0)
