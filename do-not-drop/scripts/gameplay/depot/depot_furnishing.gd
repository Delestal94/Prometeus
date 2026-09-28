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
	var rack_frame: String = DepotKit.depot_model("sm_env_depot_rack_frame")
	var rack_level: String = DepotKit.depot_model("sm_env_depot_rack_beam_level")
	var film := DepotKit.glass(Color(0.85, 0.9, 0.95, 0.35))
	var rng := RandomNumberGenerator.new()
	rng.seed = 4471
	var x_back: float = -Layout.HALF_WIDTH + 0.2
	var x_front: float = -13.5
	var centre_x: float = (x_back + x_front) * 0.5
	var depth: float = x_front - x_back
	var frames: Array[float] = [1.4, 7.0, 12.6, 18.2, 23.8, 29.4]
	var beams: Array[float] = [1.9, 3.8, 5.7]
	# Upright frames (their post guard on the aisle side, +X) and, per bay
	# and level, a pair of beams with the deck the pallets sit on (+0.085).
	for z: float in frames:
		kit.model(rack_frame, Transform3D(Basis.IDENTITY, Vector3(centre_x, 0.0, z)))
	for bay: int in range(frames.size() - 1):
		var z0: float = frames[bay]
		var z1: float = frames[bay + 1]
		var length: float = z1 - z0
		kit.collider(Vector3(depth + 0.1, 6.3, length),
				Transform3D(Basis.IDENTITY, Vector3(centre_x, 3.15, (z0 + z1) * 0.5)))
		for beam_y: float in beams:
			kit.model(rack_level, Transform3D(Basis.IDENTITY, Vector3(centre_x, beam_y, (z0 + z1) * 0.5)))
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
	var shelf_frame: String = DepotKit.depot_model("sm_env_depot_shelf_frame")
	var shelf_deck: String = DepotKit.depot_model("sm_env_depot_shelf_deck")
	var length: float = Layout.BAY_LENGTH * Layout.BAYS
	for unit: Dictionary in Layout.SHELF_UNITS:
		var x: float = float(unit.x)
		for frame: int in range(Layout.BAYS + 1):
			var z: float = Layout.SHELF_START_Z + frame * Layout.BAY_LENGTH
			kit.model(shelf_frame, Transform3D(Basis.IDENTITY, Vector3(x, 0.0, z)))
			for side: float in [-1.0, 1.0]:
				kit.collider(Vector3(0.08, 2.7, 0.08),
						Transform3D(Basis.IDENTITY, Vector3(x + side * Layout.SHELF_DEPTH * 0.5, 1.35, z)))
		# One deck model per bay (origin at the top, where the packages sit);
		# one collider per level, as before.
		for deck_top: float in Layout.LEVEL_TOPS + [2.6]:
			for bay: int in range(Layout.BAYS):
				kit.model(shelf_deck, Transform3D(Basis.IDENTITY,
						Vector3(x, deck_top, Layout.SHELF_START_Z + (bay + 0.5) * Layout.BAY_LENGTH)))
			kit.collider(Vector3(Layout.SHELF_DEPTH - 0.04, 0.04, length),
					Transform3D(Basis.IDENTITY, Vector3(x, deck_top - 0.02, Layout.SHELF_START_Z + length * 0.5)))
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
					kit.box(Vector3(0.012, 0.09, 0.36),
							Vector3(face - side * 0.005, Layout.LEVEL_TOPS[level] - 0.07, z),
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
	# Customisation kiosk facing the crew as they come round the truck.
	kit.box(Vector3(0.7, 1.2, 0.5), Vector3(4.6, 0.6, 9.6), dark, true)
	kit.box(Vector3(0.66, 0.5, 0.06), Vector3(4.6, 1.45, 9.8), dark)
	kit.box(Vector3(0.56, 0.4, 0.02), Vector3(4.6, 1.45, 9.84), DepotKit.glow(Color("4cc9f0"), 1.1))
	DepotLabels.text(_root, tr("WORLD_DEPOT_WORKSHOP"), Vector3(4.6, 1.56, 9.86), 0.0, 40, Layout.PAPER,
			Layout.DISPLAY_FONT, 0.004, 4)
	DepotLabels.text(_root, tr("WORLD_DEPOT_WORKSHOP_SUB"), Vector3(4.6, 1.38, 9.86), 0.0, 26, Layout.INK,
			Layout.BODY_FONT, 0.004, 0)
	DepotLabels.hanging_sign(_root, kit, tr("WORLD_DEPOT_WORKSHOP"), Vector3(11.5, 3.9, 6.0), 0.0, Layout.WORKSHOP_RED)


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
	DepotLabels.hanging_sign(_root, kit, tr("WORLD_DEPOT_LOCKERS"), Vector3(13.2, 3.4, 15.5), -PI * 0.5,
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
		# Models stand on the shelf board (top at 0.47 + 0.7 per level).
		var base_y: float = 0.47 + level * 0.7
		for index: int in range(7):
			var x: float = 8.9 + index * 0.62
			match (index + level) % 3:
				0:
					kit.model(DepotKit.depot_model("sm_env_depot_supply_padding"),
							Transform3D(Basis.IDENTITY, Vector3(x, base_y, 26.75)))
				1:
					kit.model(DepotKit.depot_model("sm_env_depot_shop_tape_roll"),
							Transform3D(Basis(Vector3.UP, (index - 3) * 0.08), Vector3(x, base_y, 26.57)))
				_:
					var foam: String = "sm_env_depot_shop_foam_blue" if level == 1 else "sm_env_depot_shop_foam_orange"
					kit.model(DepotKit.depot_model(foam), Transform3D(Basis.IDENTITY, Vector3(x, base_y, 26.75)))
	# The supplies that are bought wait on the counter, ready to go.
	for supply: Array in [[&"padding", Vector3(11.6, 1.06, 23.9), "sm_env_depot_supply_padding"],
			[&"insurance", Vector3(12.4, 1.06, 23.95), "sm_env_depot_supply_insurance"]]:
		var prop := MeshInstance3D.new()
		prop.name = "Supply_%s" % supply[0]
		prop.mesh = DepotKit.merged_mesh(DepotKit.depot_model(supply[2]))
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
	kit.box(Vector3(0.9, 2.1, 0.05), Vector3(x0 - 0.02, 1.05, Layout.DEPTH - 0.8), DepotKit.flat(Color("2f7a64"), 0.6),
			false, 0.0)
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
	var length: float = Layout.CONVEYOR_END_X - Layout.CONVEYOR_START_X
	var centre: float = (Layout.CONVEYOR_START_X + Layout.CONVEYOR_END_X) * 0.5
	# Bed, legs, guard rails and both end portals: one model (17 m, origin
	# under the middle of the belt). Colliders as before.
	kit.model(DepotKit.depot_model("sm_env_depot_conveyor"),
			Transform3D(Basis.IDENTITY, Vector3(centre, 0.0, Layout.CONVEYOR_Z)))
	kit.collider(Vector3(length, 0.14, 0.9), Transform3D(Basis.IDENTITY, Vector3(centre, 0.84, Layout.CONVEYOR_Z)))
	# Portals at each end with PVC strip curtains: stock appears from one and
	# disappears into the other.
	for x: float in [Layout.CONVEYOR_START_X, Layout.CONVEYOR_END_X]:
		kit.collider(Vector3(1.2, 1.3, 1.3), Transform3D(Basis.IDENTITY, Vector3(x, 1.55, Layout.CONVEYOR_Z)))
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
	# Packing table (model: cardboard, tape gun, label roll, flat-packs
	# below), its top solid as before, and a box being packed.
	kit.model(DepotKit.depot_model("sm_env_depot_packing_table"), Transform3D(Basis.IDENTITY, Vector3(2.2, 0.0, 27.4)))
	kit.collider(Vector3(2.4, 0.06, 1.0), Transform3D(Basis.IDENTITY, Vector3(2.2, 0.9, 27.4)))
	kit.model(Layout.CARGO_BOXES[0],
			Transform3D(Basis(Vector3.UP, 0.2).scaled(Vector3.ONE * 0.7), Vector3(1.6, 0.93, 27.4)))
	# Pallet jack parked beside it, forks toward the door.
	kit.model(DepotKit.depot_model("sm_env_depot_pallet_jack"),
			Transform3D(Basis.IDENTITY, Vector3(4.52, Layout.FLOOR_TOP, 27.1)))
