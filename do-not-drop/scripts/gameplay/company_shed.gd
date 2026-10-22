class_name CompanyShed
extends Node3D
## The shed of the Modo Empresa as the players walk in it (expansion D-0911 and D-0620): floor and
## walls of the company's stage with the gates open where the dock and the exit are, every piece of
## CompanyState.layout (shelves, packing tables, the dispatch zone), the painted floor zones, the
## shelf labels with their units, the pallets that wait in reception, the picking carts (D-0610.b) and the pallet
## jack with the pallets it moved (D-0605.b).
##
## It only DRAWS state: the layout and the stage from CompanyState, the units from the Inventory
## (CompanyNet's copy, equal on every peer). The host fills a new company's layout and stock from
## DefaultShed before this exists; a client gets both from the snapshot (D-2004) and calls rebuild()
## when it lands. Nothing here sends or decides anything, so no RPC and no random roll: two peers
## with the same state draw the same shed. rebuild() redraws everything (a layout change, a
## snapshot); refresh_stock() only rewrites the labels, crates and pallets (a units event). With
## follow(net) it does both by itself on every peer (D-0910): a layout event (CompanyLayoutNet, the
## host's build) or a snapshot redraws the shed, a units_moved rewrites the stock.
##
## Grey-box stand-in: boxes in the palette plus the depot's own models (packing table, wrapped
## pallet, tape and padding) and the shed shelf's final model. The other final models are a pending
## art task (docs/arte-pendiente). The static geometry goes through DepotKit (one mesh per material);
## the shelf labels and crates and the pallets are separate nodes because the stock changes them.
## Everything is freed with the shed.
##
## Grid to world: the floor is centred on this node; cell (cx, cz) of the stage's grid, one
## CompanyTuning.WAREHOUSE_GRID_M each, is at ((cx - w/2) m, (cz - d/2) m). +Z is the south: the dock
## is on that wall, the customer exit on the north one (WarehouseStages). A piece turned
## `turns` quarter turns faces local +Z, which turns with it. holds() says whether a world point is in
## the shed (the walls' line, and so the gates, included): CompanyRoot asks it who is in, for DayCycle.

signal piece_used(uid: StringName, role: StringName, peer_id: int)
## A player worked a picking cart (PickingCartPoint): which cart, how (load or push), who, where they stood.
signal cart_used(cart_id: StringName, action: StringName, peer_id: int, from: Vector3)
## A player worked the pallet jack (PalletJackPoint): how (work or push), who, where they stood.
signal jack_used(action: StringName, peer_id: int, from: Vector3)

const WALL_HEIGHT: float = 4.0
const WALL_THICKNESS: float = 0.3
const LINTEL_BOTTOM: float = 3.0
const FLOOR_COLOR: Color = Color(0.42, 0.42, 0.44)
## Warehouse slab (D-0911 "Suelo del galpón"): tx_detail_concrete_512 has one saw-cut joint per axis
## on its border, so with one repetition every FLOOR_SLAB_M metres the joints fall on world multiples
## of it. The shed stands at the origin and every stage's half floor is whole cells, so they land on
## cell lines. Troweled concrete: a little sheen, less than the depot hall's polished floor (0.5).
const FLOOR_SLAB_M: float = 4.0
const FLOOR_ROUGHNESS: float = 0.75
const WALL_COLOR: Color = Color(0.72, 0.68, 0.60)
const WALL_PLASTER_M: float = 2.0
const PATCH_HEIGHT: float = 0.02
const LAMP_COLOR: Color = Color(1.0, 0.92, 0.78)
const SHELF_LEVELS: int = 2
const SHELF_COLUMNS: int = 4
## Where the slot's crate and label stand on a shelf: the top face of each level's deck and the
## label rail's height per level, as modelled in MODEL_SHELF (2 x 1 x 2 m).
const SHELF_DECKS: Array[float] = [0.175, 1.025]
const SHELF_LABELS: Array[float] = [0.62, 1.47]
## Label text size: three lines (name in two, then the count) fit the model's 0.24 m label rail.
const SHELF_LABEL_PIXEL: float = 0.0028
const CRATE_SIZE: Vector3 = Vector3(0.38, 0.3, 0.4)
const TABLE_TOP: float = 0.9
const MODEL_TABLE: String = "sm_env_depot_packing_table"
## The shed's 8-slot shelf (D-1811): centred on its footprint, front toward +Z, 2 m wide, 1 m deep, 2 m high.
const MODEL_SHELF: String = "sm_env_shed_shelf"
const SHELF_MODEL_SIZE: Vector3 = Vector3(2.0, 2.0, 1.0)
const MODEL_PALLET: String = "sm_env_depot_pallet_wrapped"
## Zone names the floor shows (translations/strings_world.csv).
const ZONE_KEYS: Dictionary = {
	&"dock": "WORLD_SHED_ZONE_DOCK",
	&"exit": "WORLD_SHED_ZONE_EXIT",
	&"reception": "WORLD_SHED_ZONE_RECEPTION",
	&"storage": "WORLD_SHED_ZONE_STORAGE",
	&"assembly": "WORLD_SHED_ZONE_ASSEMBLY",
	&"dispatch": "WORLD_SHED_ZONE_DISPATCH",
}
## Zone colours come from the depot's palette (DepotLayout), so the shed's floor reads like the
## depot's: the same colour for the same kind of place (D-0918).
const ZONE_COLORS: Dictionary = {
	&"dock": DepotLayout.LANE_YELLOW,
	&"exit": DepotLayout.TEAL,
	&"reception": DepotLayout.WALK_GREEN,
	&"storage": DepotLayout.SHELVES_BLUE,
	&"assembly": DepotLayout.WORKSHOP_RED,
	&"dispatch": DepotLayout.OFFICE_ORANGE,
}
## The zone name's size on the floor (DepotLabels.floor_text: 0.012 m per pixel, so 0.24 m tall).
const ZONE_LABEL_SIZE: int = 20

## Station state of every packing table, by piece uid (D-0701), kept across redraws: the table node
## is drawn here, the box in its hollow is PackingStation's. Shelf labels by uid (D-0608) too.
var stations: Dictionary = {}
var shelves: Dictionary = {}
## The stage drawn and its floor in cells; the pieces drawn, as {uid, id, rect (cells), node}.
var stage: int = 0
var grid: Vector2i = Vector2i.ZERO
var pieces: Array[Dictionary] = []
## The point to use each piece drawn, by uid (ShedPiecePoint, D-0914), and who used which.
var use_points: Dictionary = {}
## Where the pallets stood at the last redraw: pallet id -> its node.
var pallet_nodes: Dictionary = {}
## The picking carts drawn, by id (PickingCartView). Each stands at its default spot (DefaultShed.cart_spots)
## or, once pushed, where the CompanyNet it follows says (CompanyCarts).
var cart_views: Dictionary = {}
## The pallet jack and the pallets on the floor (PalletYardView), redrawn from the CompanyNet it follows.
var yard: PalletYardView
## The supplier's truck beside the shed (CompanyRoot sets it): whether its bed is open and where its rear is.
var truck: SupplierTruckView

var _default: DefaultShed
var _slot_views: Array[Dictionary] = []
var _pallet_root: Node3D
## The CompanyNet this shed follows (follow()), or null.
var _net: CompanyNet


func _init() -> void:
	_default = DefaultShed.load_default()


## Redraws from `company_net` from now on, the same on every peer: the whole shed when a layout event
## is applied (layout_placed / moved / sold) or a snapshot replaced the state
## (company_state_restored), the labels and pallets when units move. It only draws.
func follow(company_net: CompanyNet) -> void:
	_net = company_net
	if not company_net.event_applied.is_connected(_on_event_applied):
		company_net.event_applied.connect(_on_event_applied)
	if not company_net.company_state_restored.is_connected(_on_state_restored):
		company_net.company_state_restored.connect(_on_state_restored)


func _on_event_applied(_seq: int, kind: StringName, data: Dictionary) -> void:
	if _net == null or not is_instance_valid(_net) or _net.company == null:
		return
	if CompanyLayoutNet.EVENT_KINDS.has(kind):
		rebuild(_net.company, _net.inventory)
	elif kind == &"units_moved" and _pallet_root != null:
		refresh_stock(_net.inventory)
	elif kind == CompanyCarts.MOVED:
		_on_cart_moved(data)
	elif CompanyPallets.EVENT_KINDS.has(kind) and _pallet_root != null:
		if kind == CompanyPallets.MOVED and yard != null:
			yard.refresh(_net.pallets, true)
		refresh_stock(_net.inventory)


func _on_state_restored(_snapshot_seq: int) -> void:
	if _net != null and is_instance_valid(_net) and _net.company != null:
		rebuild(_net.company, _net.inventory)


## Cell (may be fractional, the middle of a piece) to a point on the floor of this shed.
func cell_to_local(cell: Vector2, height: float = 0.0) -> Vector3:
	var metres: float = CompanyTuning.WAREHOUSE_GRID_M
	return Vector3((cell.x - grid.x * 0.5) * metres, height, (cell.y - grid.y * 0.5) * metres)


## The floor of this shed in the world of `local`'s parent, in cells: where a world point stands.
func local_to_cell(local: Vector3) -> Vector2:
	var metres: float = CompanyTuning.WAREHOUSE_GRID_M
	return Vector2(local.x / metres + grid.x * 0.5, local.z / metres + grid.y * 0.5)


## The piece (uid) whose footprint holds the cell, or &"" when none does.
func piece_at(cell: Vector2i) -> StringName:
	for piece: Dictionary in pieces:
		if (piece["rect"] as Rect2i).has_point(cell):
			return piece["uid"]
	return &""


## True when `world_point` stands in this shed (who is in it, D-0316.1: DayCycle.crew_in_shed): over
## the floor of the stage drawn, grown by WALL_THICKNESS on every side so whoever stands in the dock's
## or the exit's gate is in. The height is not looked at. Out of the tree it holds nothing.
func holds(world_point: Vector3) -> bool:
	if not is_inside_tree():
		return false
	var local: Vector3 = to_local(world_point)
	var half: Vector2 = WarehouseStages.floor_size_m(stage) * 0.5 + Vector2(WALL_THICKNESS, WALL_THICKNESS)
	return absf(local.x) <= half.x and absf(local.z) <= half.y


## Draws the shed of `state` (a CompanyState: layout and warehouse_stage) with the units of `stock`.
func rebuild(state: Object, stock: Inventory) -> void:
	for child: Node in get_children():
		remove_child(child)
		child.queue_free()
	pieces.clear()
	use_points.clear()
	_slot_views.clear()
	pallet_nodes.clear()
	cart_views.clear()
	yard = null
	stage = int(state.warehouse_stage)
	grid = WarehouseStages.grid_size_for(stage)
	_build_shell()
	_build_lights(state.layout)
	var furniture := Node3D.new()
	furniture.name = "Furniture"
	add_child(furniture)
	var kit := DepotKit.new(furniture)
	_paint_fixed_zones(kit)
	_paint_default_zones(kit)
	var layout: Array = state.layout
	var live_uids: Dictionary = {}
	for index: int in layout.size():
		var piece: Dictionary = layout[index]
		var def: PlaceableDefinition = PlaceableShop.definition(StringName(str(piece.get("id", ""))))
		if def == null:
			continue
		var uid: StringName = DefaultShed.piece_uid(layout, index)
		live_uids[uid] = true
		_build_piece(kit, uid, def, piece, furniture)
	kit.commit("Batch")
	for uid: Variant in stations.keys():
		if not live_uids.has(uid):
			stations.erase(uid)
			shelves.erase(uid)
	_pallet_root = Node3D.new()
	_pallet_root.name = "Pallets"
	add_child(_pallet_root)
	_build_carts()
	_build_yard()
	refresh_stock(stock)


## Hangs the lamps of ShedLighting (D-0913): a ceiling grid for the stage and a task lamp over each
## packing table, so no corner of the floor is dark and moving a table moves its light. No shadows
## (the renderer is GL Compatibility; the table and the shelves are low).
func _build_lights(layout: Array) -> void:
	var lights := Node3D.new()
	lights.name = "Lights"
	add_child(lights)
	var index: int = 0
	for lamp: Dictionary in ShedLighting.lamps_for(grid, layout):
		var omni := OmniLight3D.new()
		omni.name = "%sLamp%d" % [String(lamp["kind"]).capitalize(), index]
		omni.omni_range = float(lamp["range_m"])
		omni.omni_attenuation = 0.9
		omni.light_energy = float(lamp["energy"])
		omni.light_color = LAMP_COLOR
		omni.position = cell_to_local(lamp["at"], CompanyTuning.SHED_LAMP_HEIGHT_M)
		lights.add_child(omni)
		index += 1


## Rewrites what the units change: each labeled slot's text and crate, and the pallets in reception.
func refresh_stock(stock: Inventory) -> void:
	for view: Dictionary in _slot_views:
		var qty: int = stock.count(view["product"], view["location"])
		var label := view["label"] as Label3D
		label.text = "%s\n×%d" % [view["name"], qty]
		label.modulate = Color(1, 1, 1) if qty > 0 else Color(1.0, 0.62, 0.55)
		(view["crate"] as Node3D).visible = qty > 0
	_draw_pallets(stock)
	for cart_view: PickingCartView in cart_views.values():
		cart_view.refresh(stock)
	if yard != null and _net != null and is_instance_valid(_net):
		yard.refresh(_net.pallets)


## The pallets waiting in the Inventory (pallet:<id> locations) as {id, product, qty}, by id.
static func pallets_in(stock: Inventory) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	var by_product: Dictionary = stock.to_dict().get("stock", {})
	for product: Variant in by_product:
		var locations: Dictionary = by_product[product]
		for location: Variant in locations:
			if String(location).begins_with("pallet:"):
				found.append({"id": String(location).trim_prefix("pallet:"),
					"product": StringName(product), "qty": int(locations[location])})
	found.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return String(a["id"]) < String(b["id"]))
	return found


## A StaticBody3D box with its mesh: the floor and the walls (and the zone slabs of the map).
## `material` replaces the flat `color` when given (the shed's concrete and plaster).
static func solid_box(box_name: String, size: Vector3, center: Vector3, color: Color,
		material: Material = null) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = box_name
	body.position = center
	var shape := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	box_shape.size = size
	shape.shape = box_shape
	body.add_child(shape)
	var mesh_instance := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = material if material != null else DepotKit.flat(color)
	mesh_instance.mesh = mesh
	body.add_child(mesh_instance)
	return body


# --- Shell: floor, walls with the two gates open ---


## The shed's concrete floor: shared (DepotKit caches it), the same for every stage and redraw.
static func floor_material() -> StandardMaterial3D:
	return DepotKit.detailed(FLOOR_COLOR, "concrete", FLOOR_SLAB_M, FLOOR_ROUGHNESS)


## The shed's walls: painted plaster, like the depot hall's blocks.
static func wall_material() -> StandardMaterial3D:
	return DepotKit.detailed(WALL_COLOR, "plaster", WALL_PLASTER_M)


func _build_shell() -> void:
	var floor_m: Vector2 = WarehouseStages.floor_size_m(stage)
	var half := floor_m * 0.5
	var shell := Node3D.new()
	shell.name = "Shell"
	add_child(shell)
	shell.add_child(solid_box("Floor", Vector3(floor_m.x, 0.2, floor_m.y), Vector3(0.0, -0.1, 0.0), FLOOR_COLOR,
		floor_material()))
	var reach: float = half.x + WALL_THICKNESS
	var y: float = WALL_HEIGHT * 0.5
	var gates: Array[Rect2i] = WarehouseStages.gate_rects(stage)
	var dock_span: Vector2 = _span_x(gates[0])
	var exit_span: Vector2 = _span_x(gates[1])
	_wall_row(shell, "WallFront", half.y + WALL_THICKNESS * 0.5, -reach, reach, dock_span, y)
	_wall_row(shell, "WallBack", -half.y - WALL_THICKNESS * 0.5, -reach, reach, exit_span, y)
	var side := Vector3(WALL_THICKNESS, WALL_HEIGHT, floor_m.y)
	shell.add_child(solid_box("WallLeft", side, Vector3(-half.x - WALL_THICKNESS * 0.5, y, 0.0), WALL_COLOR,
		wall_material()))
	shell.add_child(solid_box("WallRight", side, Vector3(half.x + WALL_THICKNESS * 0.5, y, 0.0), WALL_COLOR,
		wall_material()))


## A wall along X at depth `z` from x0 to x1 with a gap `gap` (x range): two pieces and a lintel.
func _wall_row(parent: Node3D, base: String, z: float, x0: float, x1: float, gap: Vector2, y: float) -> void:
	var thick: float = WALL_THICKNESS
	var left_len: float = gap.x - x0
	var right_len: float = x1 - gap.y
	parent.add_child(solid_box(base + "Left", Vector3(left_len, WALL_HEIGHT, thick),
		Vector3(x0 + left_len * 0.5, y, z), WALL_COLOR, wall_material()))
	parent.add_child(solid_box(base + "Right", Vector3(right_len, WALL_HEIGHT, thick),
		Vector3(gap.y + right_len * 0.5, y, z), WALL_COLOR, wall_material()))
	var lintel_h: float = WALL_HEIGHT - LINTEL_BOTTOM
	parent.add_child(solid_box(base + "Lintel", Vector3(gap.y - gap.x, lintel_h, thick),
		Vector3((gap.x + gap.y) * 0.5, LINTEL_BOTTOM + lintel_h * 0.5, z), WALL_COLOR, wall_material()))


## X range (metres, from the centre) of a wall-line gate rect.
func _span_x(gate: Rect2i) -> Vector2:
	var metres: float = CompanyTuning.WAREHOUSE_GRID_M
	return Vector2((gate.position.x - grid.x * 0.5) * metres, (gate.end.x - grid.x * 0.5) * metres)


# --- Painted zones ---


func _paint_fixed_zones(kit: DepotKit) -> void:
	var dock: Rect2i = WarehouseStages.dock_rect(stage)
	var door: Rect2i = WarehouseStages.exit_rect(stage)
	_paint_zone(kit, &"dock", dock, Vector2(dock.get_center()) + Vector2(0.0, 0.2))
	_paint_zone(kit, &"exit", door, Vector2(door.get_center()) + Vector2(0.0, 0.2))


func _paint_default_zones(kit: DepotKit) -> void:
	if _default == null or _default.stage != stage:
		return
	for zone: Dictionary in _default.zones:
		_paint_zone(kit, StringName(str(zone.get("role", ""))), zone.get("rect", Rect2i()),
			zone.get("label_at", Vector2.ZERO))


## A flat patch of colour over the rect and its name written on the floor, readable from the south.
func _paint_zone(kit: DepotKit, role: StringName, rect: Rect2i, label_at: Vector2) -> void:
	var from: Vector3 = cell_to_local(Vector2(rect.position), PATCH_HEIGHT * 0.5)
	var to: Vector3 = cell_to_local(Vector2(rect.end), PATCH_HEIGHT * 0.5)
	var color: Color = ZONE_COLORS.get(role, Color(0.5, 0.5, 0.5))
	kit.box(Vector3(absf(to.x - from.x) - 0.06, PATCH_HEIGHT, absf(to.z - from.z) - 0.06),
		(from + to) * 0.5, DepotKit.flat(color.darkened(0.15), 0.95))
	_zone_label(role, label_at)


func _zone_label(role: StringName, label_at: Vector2) -> void:
	if not ZONE_KEYS.has(role):
		return
	var at: Vector3 = cell_to_local(label_at)
	var label: Label3D = DepotLabels.floor_text(self, tr(ZONE_KEYS[role]), at, 0.0, ZONE_LABEL_SIZE,
		DepotLayout.PAPER)
	label.name = "Zone_%s" % role
	label.position.y = PATCH_HEIGHT + 0.01


# --- Pieces ---


func _build_piece(kit: DepotKit, uid: StringName, def: PlaceableDefinition, piece: Dictionary,
		furniture: Node3D) -> void:
	var turns: int = posmod(int(piece.get("turns", 0)), 4)
	var rect := Rect2i(Vector2i(int(piece.get("x", 0)), int(piece.get("z", 0))), def.footprint_for(turns))
	var center: Vector3 = cell_to_local(Vector2(rect.position) + Vector2(rect.size) * 0.5)
	var at := Transform3D(Basis(Vector3.UP, turns * PI * 0.5), center)
	pieces.append({"uid": uid, "id": def.id, "rect": rect})
	_add_use_point(uid, def, at)
	match def.role:
		&"storage":
			_build_shelf(kit, uid, def, at, furniture)
		&"assembly":
			_build_table(kit, uid, def, at)
		&"dispatch":
			# Painted on the floor (it does not block walking): the patch and its name are all of it.
			_paint_zone(kit, &"dispatch", rect, Vector2(rect.position) + Vector2(rect.size) * 0.5)
		_:
			kit.box(Vector3(def.footprint.x, def.height_m, def.footprint.y) * CompanyTuning.WAREHOUSE_GRID_M,
				center + Vector3.UP * def.height_m * 0.5, DepotKit.flat(Color(0.5, 0.5, 0.52)), true)


## Every piece the crew can work gets its ShedPiecePoint, placed or default alike (D-0914). The
## furniture of other roles (a plain block) has nothing to use.
func _add_use_point(uid: StringName, def: PlaceableDefinition, at: Transform3D) -> void:
	if not ShedPiecePoint.PROMPT_KEYS.has(def.role):
		return
	var point := ShedPiecePoint.make(uid, def.role, def.footprint.y * CompanyTuning.WAREHOUSE_GRID_M)
	point.transform = at * Transform3D(Basis.IDENTITY, point.position)
	point.used.connect(func(piece_uid: StringName, role: StringName, peer_id: int) -> void:
		piece_used.emit(piece_uid, role, peer_id))
	add_child(point)
	use_points[uid] = point


func _build_shelf(kit: DepotKit, uid: StringName, def: PlaceableDefinition, at: Transform3D,
		furniture: Node3D) -> void:
	var metres: float = CompanyTuning.WAREHOUSE_GRID_M
	var width: float = def.footprint.x * metres
	var depth: float = def.footprint.y * metres
	# The model is made for the default shelf (2 x 2 x 1 cells of 1 m); any other footprint or height
	# stretches it, so the decks and label rails keep their proportions.
	var fit := Vector3(width / SHELF_MODEL_SIZE.x, def.height_m / SHELF_MODEL_SIZE.y, depth / SHELF_MODEL_SIZE.z)
	kit.model(DepotKit.depot_model(MODEL_SHELF), at * Transform3D(Basis.from_scale(fit), Vector3.ZERO))
	# Solid as one block: nobody walks through the rack.
	kit.collider(Vector3(width, def.height_m, depth), at * Transform3D(Basis.IDENTITY,
		Vector3(0.0, def.height_m * 0.5, 0.0)))
	var shelf: Shelf = Shelf.make(uid, def.slots)
	var node := Node3D.new()
	node.name = "Shelf_%s" % uid
	node.transform = at
	furniture.add_child(node)
	if _default != null:
		for entry: Dictionary in _default.shelf_stock:
			if StringName(str(entry.get("shelf", ""))) == uid:
				_label_slot(node, shelf, def, int(entry["slot"]), StringName(str(entry["product"])), width, depth)
	shelves[uid] = shelf


## One labeled slot of a shelf: the product on the shelf's label, a crate standing for its units and
## the count under the name. refresh_stock() rewrites them from the Inventory.
func _label_slot(node: Node3D, shelf: Shelf, def: PlaceableDefinition, slot: int, product: StringName,
		width: float, depth: float) -> void:
	if slot < 0 or slot >= def.slots or not shelf.set_label(Inventory.new(), slot, product):
		return
	var level: int = floori(slot / float(SHELF_COLUMNS))
	var column: int = slot % SHELF_COLUMNS
	var slot_w: float = width / SHELF_COLUMNS
	var x: float = -width * 0.5 + slot_w * (column + 0.5)
	var crate := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = CRATE_SIZE
	mesh.material = DepotKit.flat(Color(0.74, 0.58, 0.38))
	crate.mesh = mesh
	crate.name = "Crate_%d" % slot
	crate.position = Vector3(x, SHELF_DECKS[level] + CRATE_SIZE.y * 0.5, 0.0)
	node.add_child(crate)
	var label := Label3D.new()
	label.name = "Label_%d" % slot
	label.font_size = 22
	label.pixel_size = SHELF_LABEL_PIXEL
	label.outline_size = 8
	label.width = (slot_w - 0.04) / SHELF_LABEL_PIXEL
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.position = Vector3(x, SHELF_LABELS[level], depth * 0.5 + 0.01)
	node.add_child(label)
	var content: PackageContent = null
	var definition := load("res://data/products/%s.tres" % product) as ProductDefinition
	if definition != null:
		content = definition.content
	_slot_views.append({"label": label, "crate": crate, "product": product,
		"location": shelf.location(slot), "name": content.localized_name() if content != null else String(product)})


## The shelf slot a units request names (ShelfPicking.station_id) as CompanyNet's `stations` resolver
## wants it: where its units lie, the spot to reach (the piece's use point), what it accepts and holds
## (D-0609). A picking cart is a station too, named by its location, cart:<id> (D-0610.b). {} for anything
## else, or a slot with no label.
func station_for(id: StringName) -> Dictionary:
	if id == CompanyPallets.STATION:
		return _jack_station()
	var cart_id: StringName = PickingCart.parse_location(id)
	if cart_id != &"":
		return _cart_station(cart_id)
	var named: Dictionary = ShelfPicking.parse_station(id)
	if named.is_empty():
		return {}
	var uid: StringName = named["uid"]
	var shelf: Shelf = shelves.get(uid) as Shelf
	var point: ShedPiecePoint = use_points.get(uid) as ShedPiecePoint
	var slot: int = int(named["slot"])
	if shelf == null or point == null or not point.is_inside_tree() or shelf.label_of(slot) == &"":
		return {}
	return {
		"location": shelf.location(slot), "spot": point.global_position,
		"accepts": shelf.label_of(slot), "capacity": CompanyTuning.SHELF_SLOT_CAPACITY,
	}


# --- Picking carts ---


## One cart per DefaultShed.cart_spots entry ("cart_1", "cart_2"...), where the host's pushes left it.
func _build_carts() -> void:
	var spots: Array[Vector2] = []
	if _default != null and _default.stage == stage:
		spots = _default.cart_spots
	for index: int in spots.size():
		var id := StringName("cart_%d" % (index + 1))
		var local: Vector3 = cell_to_local(spots[index])
		if _net != null and is_instance_valid(_net):
			var pushed: Variant = _net.carts.position_of(id)
			if pushed is Vector3:
				local = pushed
		var view: PickingCartView = PickingCartView.make(id, local)
		view.used.connect(func(cart_id: StringName, action: StringName, peer_id: int, from: Vector3) -> void:
			cart_used.emit(cart_id, action, peer_id, from))
		add_child(view)
		cart_views[id] = view


## A cart_moved reached this peer: the cart rolls to where the host left it.
func _on_cart_moved(data: Dictionary) -> void:
	var view: Variant = cart_views.get(StringName(str(data.get("cart", ""))))
	var pos: Variant = data.get("pos")
	if view is PickingCartView and is_instance_valid(view) and pos is Vector3:
		(view as PickingCartView).place_at(pos, true)


## A cart as CompanyNet's `stations` resolver wants it (D-0610.b): its units' location, a spot over the
## platform to measure reach to, the units it holds at most and, for a push, where it stands now (shed
## frame) and whether the floor at a point is free (cart_can_stand). {} for a cart that is not drawn.
func _cart_station(cart_id: StringName) -> Dictionary:
	var view: Variant = cart_views.get(cart_id)
	if not (view is PickingCartView) or not is_instance_valid(view) or not (view as PickingCartView).is_inside_tree():
		return {}
	var cart_view := view as PickingCartView
	return {
		"location": cart_view.cart.location(), "spot": cart_view.global_position + Vector3.UP * 0.5,
		"capacity": CompanyTuning.CART_MAX_UNITS, "at": cart_view.position,
		"stand_ok": cart_can_stand,
	}


## Whether a cart may be left at `local` (shed frame): inside the floor with CompanyTuning.CART_CLEARANCE_M
## to the walls, and that far from every piece of furniture (the dispatch zone is only painted).
func cart_can_stand(local: Vector3) -> bool:
	var clearance: float = CompanyTuning.CART_CLEARANCE_M
	var half: Vector2 = WarehouseStages.floor_size_m(stage) * 0.5
	if absf(local.x) > half.x - clearance or absf(local.z) > half.y - clearance:
		return false
	var cell: Vector2 = local_to_cell(local)
	for piece: Dictionary in pieces:
		var def: PlaceableDefinition = PlaceableShop.definition(StringName(str(piece["id"])))
		if def != null and def.role == &"dispatch":
			continue
		if Rect2(piece["rect"]).grow(clearance / CompanyTuning.WAREHOUSE_GRID_M).has_point(cell):
			return false
	return true


# --- The pallet jack ---


## The jack and the floor pallets, one yard per drawing; its jack's points forward who used it.
func _build_yard() -> void:
	yard = PalletYardView.make(stage)
	yard.jack_used.connect(func(action: StringName, peer_id: int, from: Vector3) -> void:
		jack_used.emit(action, peer_id, from))
	add_child(yard)


## The pallet jack as CompanyNet's `stations` resolver wants it (D-0605.b, see CompanyPallets): a spot over the
## forks to measure reach to, where the jack stands now, the floor, the checks only a shed can make, and the
## truck's bed. {} for a shed that draws no jack.
func _jack_station() -> Dictionary:
	if yard == null or not is_instance_valid(yard) or not yard.is_inside_tree():
		return {}
	var rear: Vector2 = SupplierTruckView.rear_of(stage)
	return {
		"location": &"jack:yard", "spot": yard.jack.global_position + Vector3.UP * 0.5,
		"at": Vector2(yard.jack.position.x, yard.jack.position.z), "floor": PalletYardView.floor_rect(stage),
		"stand_ok": jack_can_stand, "free_ok": pallet_spot_free, "bed_at": rear,
		"bed_open": truck != null and is_instance_valid(truck) and truck.bed_open(),
	}


## Whether the jack may stand at `at` (metres, shed frame): as a picking cart (cart_can_stand).
func jack_can_stand(at: Vector2) -> bool:
	return cart_can_stand(Vector3(at.x, 0.0, at.y))


## Whether a pallet may lie at `at` (metres, shed frame): not over one of the pallets of reception that
## the Inventory draws (_draw_pallets). Furniture and walls are the jack's own check (cart_can_stand).
func pallet_spot_free(at: Vector2) -> bool:
	var size: Vector2 = CompanyTuning.PALLET_FOOTPRINT_M
	var footprint := Rect2(at - size * 0.5, size)
	for node: Node3D in pallet_nodes.values():
		if footprint.intersects(Rect2(Vector2(node.position.x, node.position.z) - size * 0.5, size)):
			return false
	return true


func _build_table(kit: DepotKit, uid: StringName, def: PlaceableDefinition, at: Transform3D) -> void:
	var metres: float = CompanyTuning.WAREHOUSE_GRID_M
	var width: float = def.footprint.x * metres
	var depth: float = def.footprint.y * metres
	var table_path: String = DepotKit.depot_model(MODEL_TABLE)
	var bounds: AABB = DepotKit.merged_mesh(table_path).get_aabb()
	# The depot's table already carries its paper roll, tape gun and the mat where the box sits
	# (its hollow); only the width and depth are fitted to the footprint, its top stays at TABLE_TOP.
	var fit := Vector3(width / bounds.size.x, 1.0, depth / bounds.size.z)
	kit.model(table_path, at * Transform3D(Basis.from_scale(fit), Vector3.ZERO))
	kit.collider(Vector3(width, TABLE_TOP, depth), at * Transform3D(Basis.IDENTITY, Vector3(0.0, TABLE_TOP * 0.5, 0.0)))
	# The box dispenser stands at the table's far end, behind the box's hollow.
	kit.box_xf(Vector3(0.36, 0.34, 0.3), at * Transform3D(Basis.IDENTITY,
		Vector3(width * 0.5 - 0.22, TABLE_TOP + 0.17, -depth * 0.5 + 0.2)), DepotKit.flat(Color(0.86, 0.52, 0.18)))
	if not stations.has(uid):
		stations[uid] = PackingStation.make(uid)


# --- Pallets in reception ---


func _draw_pallets(stock: Inventory) -> void:
	var waiting: Array[Dictionary] = pallets_in(stock)
	if _net != null and is_instance_valid(_net):
		# The pallets the jack moves are the yard's (D-0605.b), wherever they are.
		var in_reception: Array[Dictionary] = []
		for entry: Dictionary in waiting:
			if not _net.pallets.book.places.has(StringName(entry["id"])):
				in_reception.append(entry)
		waiting = in_reception
	var same: bool = waiting.size() == pallet_nodes.size()
	for entry: Dictionary in waiting:
		same = same and pallet_nodes.has(entry["id"])
	if same:
		for entry: Dictionary in waiting:
			var label := (pallet_nodes[entry["id"]] as Node3D).get_node_or_null(^"Label") as Label3D
			if label != null:
				label.text = _pallet_text(entry)
		return
	for child: Node in _pallet_root.get_children():
		_pallet_root.remove_child(child)
		child.queue_free()
	pallet_nodes.clear()
	var spots: Array[Vector2] = _default.pallet_spots if _default != null and _default.stage == stage else []
	for index: int in waiting.size():
		var spot: Vector2 = spots[index % spots.size()] if not spots.is_empty() else Vector2(grid) * 0.5
		var lift: float = floorf(index / float(maxi(spots.size(), 1))) * 1.25
		pallet_nodes[waiting[index]["id"]] = _make_pallet(waiting[index], cell_to_local(spot, lift))


func _make_pallet(entry: Dictionary, at: Vector3) -> Node3D:
	var body := StaticBody3D.new()
	body.name = "Pallet_%s" % entry["id"]
	body.position = at
	var path: String = DepotKit.depot_model(MODEL_PALLET)
	var mesh := MeshInstance3D.new()
	mesh.mesh = DepotKit.merged_mesh(path)
	body.add_child(mesh)
	var bounds: AABB = mesh.mesh.get_aabb()
	var shape := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	box_shape.size = bounds.size
	shape.shape = box_shape
	shape.position = bounds.get_center()
	body.add_child(shape)
	var label := Label3D.new()
	label.name = "Label"
	label.text = _pallet_text(entry)
	label.font_size = 28
	label.pixel_size = 0.0035
	label.outline_size = 8
	label.position = Vector3(0.0, bounds.size.y + 0.2, 0.0)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	body.add_child(label)
	_pallet_root.add_child(body)
	return body


func _pallet_text(entry: Dictionary) -> String:
	var definition := load("res://data/products/%s.tres" % entry["product"]) as ProductDefinition
	var product_name: String = String(entry["product"])
	if definition != null and definition.content != null:
		product_name = definition.content.localized_name()
	return "%s\n×%d" % [product_name, int(entry["qty"])]
