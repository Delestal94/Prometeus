class_name Depot
extends Node3D
## The company depot every delivery starts from (pedido del usuario,
## 2026-09-23): the truck parked inside, every kind of package on the dispatch
## shelves, the order board saying which box goes to which house, and the
## places to get ready -- lockers (uniform), workshop (truck and paint),
## supplies counter. Once the truck has driven out and nobody is left inside
## on foot, the roller door closes behind the crew.
##
## Space: the door's plane is z = 0 and the depot runs toward +Z (the road
## leaves toward -Z, like route.gd). The level places this node; everything
## below is in its local space.
##
## Split of responsibilities:
## - this script: layout, stock and orders, the door, supplies (gameplay);
## - DepotKit: batching static geometry; DepotRollerDoor: the door itself;
## - DepotStation: the interactable stations; DepotWorker/DepotForklift: life;
##   DepotMirror: the lockers' working mirror.
## Orders are drawn from the session seed, so every peer posts the same board
## without a message; the door and purchases are decided by the host.

const WorldMix = preload("res://scripts/presentation/world_mix.gd")

signal door_closed

const PACKAGE_SCENE: PackedScene = preload("res://scenes/gameplay/package/package.tscn")
const TRAP_PATH: String = "res://data/traps/%s.tres"
## The level scene declares one package of every trap type; the depot stocks
## a second of each, so the shelves hold every kind twice over and picking
## the right one actually means reading the board.
const EXTRA_STOCK: Array[String] = ["fragile", "growing_weight", "balance", "noisy", "liquid", "explosive", "hostile"]

const HALF_WIDTH: float = 15.0
const DEPTH: float = 32.0
const WALL: float = 0.3
const WALL_HEIGHT: float = 8.0
const CEILING: float = 7.4
const FLOOR_TOP: float = 0.03
const DOOR_WIDTH: float = 6.6
const DOOR_HEIGHT: float = 4.8
## Where the truck waits, nose to the door (for the level scene and tests).
const TRUCK_BAY := Vector3(0.0, 0.9, 7.5)
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
## How far out (depot z) the truck's centre must be before the door may close:
## its whole length plus the stowed ramp, clear of the curtain.
const TRUCK_CLEAR_Z: float = -6.5
## Supplies (CrewProgression.SUPPLIES) and what they do once a run leaves.
const PADDING_ABSORPTION: float = 0.75
const INSURANCE_REFUND: int = 30

const TEAL := Color("65b5a1")
const INK := Color("1e2235")
const PAPER := Color("fff6e6")
const YELLOW := Color("e7be51")
const WARNING_TEXTURE: String = "res://assets/textures/environment/tx_env_warning_256.png"
const DISPLAY_FONT: Font = preload("res://assets/fonts/LilitaOne-Regular.ttf")
const BODY_FONT: Font = preload("res://assets/fonts/Nunito-Variable.ttf")
const RUN_MANAGER := preload("res://scripts/core/run_manager.gd")
const CARGO_BOXES: Array[String] = [
	"res://assets/models/cargo/sm_cargo_box_cube.glb",
	"res://assets/models/cargo/sm_cargo_box_flat.glb",
	"res://assets/models/cargo/sm_cargo_box_tall.glb",
	"res://assets/models/cargo/sm_cargo_box_vented.glb",
]
const PALLET: String = "res://assets/models/environment/props/sm_env_prop_pallet.glb"
const CRATE: String = "res://assets/models/environment/props/sm_env_prop_wooden_crate.glb"

## Hanging signs: caption size, and how long an arrow drawn on one is.
const SIGN_FONT_SIZE: int = 64
const SIGN_PIXEL: float = 0.0065
const SIGN_ARROW: float = 0.5
const SIGN_GAP: float = 0.18
## Each place's colour, shared by its hanging sign and the arrow painted
## toward it on the floor (tareas de Nacho N-503).
const SHELVES_BLUE := Color("2f5d8a")
const BOARD_GREEN := Color("2e9e56")
const LOCKERS_TEAL := Color("3f7f8c")
const SHOP_PURPLE := Color("7b52b9")
const WORKSHOP_RED := Color("c0392b")
## Wayfinding from where the crew appears: an arrow painted on the floor
## toward each place, and its name beside it. The words read facing the
## truck, the way everyone spawns; each arrow aims at `toward`.
const FLOOR_GUIDES: Array[Dictionary] = [
	{"caption": "PIZARRA", "word": Vector3(-2.0, 0.0, 16.0), "arrow": Vector3(-2.7, 0.0, 15.3), "toward": Vector3(-4.3, 0.0, 13.3), "colour": BOARD_GREEN},
	{"caption": "ESTANTES", "word": Vector3(-3.0, 0.0, 17.4), "arrow": Vector3(-4.9, 0.0, 17.4), "toward": Vector3(-6.3, 0.0, 17.4), "colour": SHELVES_BLUE},
	{"caption": "TALLER", "word": Vector3(3.0, 0.0, 15.5), "arrow": Vector3(4.4, 0.0, 15.2), "toward": Vector3(4.6, 0.0, 10.1), "colour": WORKSHOP_RED},
	{"caption": "VESTUARIO", "word": Vector3(4.3, 0.0, 17.0), "arrow": Vector3(6.3, 0.0, 17.0), "toward": Vector3(14.0, 0.0, 15.5), "colour": LOCKERS_TEAL},
	{"caption": "SUMINISTROS", "word": Vector3(4.6, 0.0, 18.6), "arrow": Vector3(6.9, 0.0, 19.0), "toward": Vector3(10.8, 0.0, 23.4), "colour": SHOP_PURPLE},
]

## Builds the stock of extra packages; tests of other systems can turn it off.
@export var stock_extra_packages: bool = true
## A plain ground apron around the building, for levels with no terrain of
## their own behind the start line (modo endless).
@export var ground_apron: bool = false

## Today's orders, one per house: {"house", "package_id", "code", "trap", "content"}.
var orders: Array[Dictionary] = []
## Supplies waiting for the next run, as the host last reported them.
var supplies: Array = []
var team_money: int = 0
var door: DepotRollerDoor
## Shelf slots in board order: {"code": "A-1", "transform": Transform3D}.
var slots: Array[Dictionary] = []
var _stocked: Dictionary = {}  # package_id -> DeliveryPackage
var _rng := RandomNumberGenerator.new()
var _vehicle: Node3D = null
var _watching_exit: bool = false
var _insured: bool = false
var _board_rows: Array[Label3D] = []
var _board_marks: Array[Label3D] = []
var _board_title: Label3D
var _board_rule: Label3D
var _stats_label: Label3D
var _fans: Array[Node3D] = []
var _clock_hour: Node3D
var _clock_minute: Node3D
var _belt_material: StandardMaterial3D
var _belt_boxes: Array[Node3D] = []
var _flicker_tube: MeshInstance3D
var _flicker_time: float = 0.0
var _supply_props: Dictionary = {}  # supply id -> Node3D shown on the truck
## Arrows painted on the floor: {"caption", "at", "direction"} in depot space.
var guides: Array[Dictionary] = []


func _ready() -> void:
	var session_seed: int = int(_autoload(&"NetworkManager").get(&"world_seed")) if _autoload(&"NetworkManager") != null else 0
	if session_seed != 0:
		_rng.seed = session_seed ^ 0x5eed
	else:
		_rng.randomize()
	add_to_group(&"roofed_area")
	_build_structure()
	_build_door()
	_build_signs()
	_build_board()
	_build_team_board()
	_build_stations()
	_build_lights()
	_build_moving_parts()
	_build_life()
	_build_audio()
	if stock_extra_packages:
		_spawn_extra_stock()
	var crew: Node = _autoload(&"CrewProgression")
	if crew != null:
		supplies = (crew.get(&"supplies") as Dictionary).keys()
		team_money = int(crew.get(&"team_money"))
	for supply_id: StringName in _supply_props:
		(_supply_props[supply_id] as Node3D).visible = supplies.has(supply_id)
	var bus: Node = _autoload(&"EventBus")
	if bus != null:
		bus.connect(&"house_delivery_recorded", _on_house_delivery_recorded)
	var network: Node = _autoload(&"NetworkManager")
	if network != null:
		network.connect(&"roster_changed", func(_peers: Array) -> void:
			if bool(network.call(&"is_host")):
				_broadcast_supplies())


## Whether a world point is under the depot's roof (route_sky.gd keeps the
## rain off whoever is inside).
func covers(world_point: Vector3) -> bool:
	var local: Vector3 = to_local(world_point)
	return absf(local.x) < HALF_WIDTH + WALL and local.z > -WALL and local.z < DEPTH + WALL and local.y < CEILING


# --- Stock and orders ------------------------------------------------------


## Traps the session hasn't unlocked stay in the back: their boxes (the
## level's and the depot's own second one) are taken out of the level before
## anything is shelved, and the rest is returned. Every peer removes the same
## ones -- online the list is the host's (NetworkManager.world_locked_traps),
## solo it's this player's profile.
func withhold_locked(packages: Array) -> Array:
	var locked: Array = locked_traps()
	var kept: Array = []
	for package: Node in packages:
		if not is_instance_valid(package):
			continue
		var definition: Resource = package.get(&"trap_definition")
		if definition != null and locked.has(StringName(definition.get(&"id"))):
			# Out of the group right away (the level reads it next), gone at the
			# end of the frame; pulling it out of the tree here instead left
			# its own deferred setup reading a transform it no longer had.
			package.remove_from_group(&"cargo")
			package.visible = false
			package.process_mode = Node.PROCESS_MODE_DISABLED
			package.queue_free()
			continue
		kept.append(package)
	return kept


func locked_traps() -> Array:
	var network: Node = _autoload(&"NetworkManager")
	if network != null and int(network.get(&"world_seed")) != 0:
		return network.get(&"world_locked_traps")
	var unlocks: Node = _autoload(&"UnlockManager")
	return unlocks.call(&"locked_traps") if unlocks != null else []


## Puts every package the level has onto the dispatch shelves, one per slot,
## in an order drawn from the session seed (so every peer shelves the same box
## in the same bin). Each box keeps its bin code as meta "dispatch_code".
func stock_shelves(packages: Array) -> void:
	var sorted: Array = packages.filter(func(p: Variant) -> bool: return is_instance_valid(p))
	sorted.sort_custom(func(a: Node, b: Node) -> bool: return String(a.get(&"package_id")) < String(b.get(&"package_id")))
	var order: Array[int] = []
	for index: int in range(slots.size()):
		order.append(index)
	_shuffle(order)
	_stocked.clear()
	for index: int in range(mini(sorted.size(), slots.size())):
		var package: Node3D = sorted[index]
		var slot: Dictionary = slots[order[index]]
		# The box's real size comes from its content; the collider only takes
		# that shape a frame later (package_feedback.gd applies it deferred).
		var content: Resource = package.call(&"content_definition") if package.has_method(&"content_definition") else null
		var half: Vector3 = (content.get(&"box_size") as Vector3) * 0.5 if content != null else package.call(&"get_half_extents")
		var at: Transform3D = slot.transform
		at.origin.y += half.y + 0.01
		at.basis = at.basis * Basis(Vector3.UP, _rng.randf_range(-0.12, 0.12))
		package.global_transform = global_transform * at
		package.reset_physics_interpolation()
		package.set_meta(&"dispatch_code", String(slot.code))
		_stocked[StringName(package.get(&"package_id"))] = package


## Draws one order per house from what's on the shelves -- a different kind of
## box for each house while there are kinds to go round -- and writes them on
## the board. Returns (and keeps) the list.
func post_orders(house_count: int) -> Array[Dictionary]:
	orders.clear()
	var candidates: Array = _stocked.values()
	candidates.sort_custom(func(a: Node, b: Node) -> bool: return String(a.get(&"package_id")) < String(b.get(&"package_id")))
	_shuffle(candidates)
	var used_traps: Array[String] = []
	for pass_index: int in range(2):
		for package: Node in candidates:
			if orders.size() >= house_count:
				break
			var trap: String = String(package.get(&"trap_definition").get(&"display_name"))
			var package_id := StringName(package.get(&"package_id"))
			if orders.any(func(o: Dictionary) -> bool: return o.package_id == package_id):
				continue
			if pass_index == 0 and trap in used_traps:
				continue
			used_traps.append(trap)
			var content: Resource = package.call(&"content_definition")
			orders.append({
				"house": orders.size(),
				"package_id": package_id,
				"code": String(package.get_meta(&"dispatch_code", "?")),
				"trap": trap,
				"content": String(content.get(&"display_name")) if content != null else "",
			})
	_write_board()
	var bus: Node = _autoload(&"EventBus")
	if bus != null:
		bus.emit_signal(&"depot_orders_posted", orders.duplicate(true))
	return orders


## [[package_id, label], ...] in house order, the shape route.assign_packages()
## and the houses already understand.
func assignments() -> Array:
	var result: Array = []
	for order: Dictionary in orders:
		result.append([order.package_id, "%s %s" % [order.trap, order.code]])
	return result


## Where the Nth player to join appears, in world space, facing the truck.
func spawn_position(index: int) -> Vector3:
	return to_global(SPAWN_POINTS[index % SPAWN_POINTS.size()])


# --- The run leaves ----------------------------------------------------------


## Host-only, called by the level the moment the run starts: hands the waiting
## supplies to this run, warns about orders left on the shelf, and starts
## watching for the truck to clear the door.
func begin_run(vehicle: Node3D, loaded: Array) -> void:
	_vehicle = vehicle
	_watching_exit = true
	var crew: Node = _autoload(&"CrewProgression")
	var taken: Array = crew.call(&"take_supplies") if crew != null else []
	if taken.has(&"padding"):
		for package: Node in loaded:
			package.set(&"impact_absorption", PADDING_ABSORPTION)
	_insured = taken.has(&"insurance")
	_broadcast_supplies()
	var missing: PackedStringArray = []
	for order: Dictionary in orders:
		var package: Node = _stocked.get(order.package_id)
		if package == null or not is_instance_valid(package) or not bool(package.get(&"is_loaded")):
			missing.append("casa %d (%s)" % [int(order.house) + 1, order.code])
	if not missing.is_empty():
		_notice("Salieron sin el pedido de la %s" % ", ".join(missing))


func _physics_process(_delta: float) -> void:
	if not _watching_exit or door == null or not door.is_open:
		return
	if not is_instance_valid(_vehicle):
		_watching_exit = false
		return
	if to_local(_vehicle.global_position).z > TRUCK_CLEAR_Z or _anyone_on_foot_inside():
		return
	_watching_exit = false
	if _is_online():
		_close_door.rpc()
	else:
		_close_door()


@rpc("authority", "call_local", "reliable")
func _close_door() -> void:
	door.set_open(false)
	door_closed.emit()
	var network: Node = _autoload(&"NetworkManager")
	if network == null or bool(network.call(&"is_host")):
		_notice("El depósito cierra el portón. ¡Buen viaje!")


func _anyone_on_foot_inside() -> bool:
	for node: Node in get_tree().get_nodes_in_group(&"player"):
		var player := node as Node3D
		if player == null or not String(player.get(&"seat_node_path")).is_empty():
			continue
		var local: Vector3 = to_local(player.global_position)
		if absf(local.x) < HALF_WIDTH + 0.5 and local.z > -1.5 and local.z < DEPTH:
			return true
	return false


# --- Supplies ----------------------------------------------------------------


## Any peer asks (rpc_id(1, ...)); the host spends the team's money.
@rpc("any_peer", "call_local", "reliable")
func request_supply(supply_id: StringName) -> void:
	var network: Node = _autoload(&"NetworkManager")
	if network != null and bool(network.call(&"is_online")) and not bool(network.call(&"is_host")):
		return
	var manager: Node = _autoload(&"RunManager")
	if manager != null and (bool(manager.get(&"is_running")) or not (manager.get(&"results") as Dictionary).is_empty()):
		return
	var crew: Node = _autoload(&"CrewProgression")
	if crew == null:
		return
	if bool(crew.call(&"buy_supply", supply_id)):
		var item: Dictionary = crew.get(&"SUPPLIES")[supply_id]
		_notice("Compraron %s (-$%d)" % [String(item.title).to_lower(), int(item.cost)])
	_broadcast_supplies()


## Asks the host for a supply from whichever peer this is.
func buy_supply(supply_id: StringName) -> void:
	if _is_online() and not bool(_autoload(&"NetworkManager").call(&"is_host")):
		request_supply.rpc_id(1, supply_id)
	else:
		request_supply(supply_id)


func _broadcast_supplies() -> void:
	var crew: Node = _autoload(&"CrewProgression")
	if crew == null:
		return
	var list: Array = (crew.get(&"supplies") as Dictionary).keys()
	var money: int = int(crew.get(&"team_money"))
	if _is_online():
		_sync_supplies.rpc(list, money)
	else:
		_sync_supplies(list, money)


@rpc("authority", "call_local", "reliable")
func _sync_supplies(list: Array, money: int) -> void:
	supplies = list
	team_money = money
	var bus: Node = _autoload(&"EventBus")
	var network: Node = _autoload(&"NetworkManager")
	if bus != null:
		# The host's CrewProgression already announced its own money.
		if network != null and not bool(network.call(&"is_host")):
			bus.emit_signal(&"team_money_changed", money)
		bus.emit_signal(&"depot_supplies_changed", list.duplicate(), money)
	for supply_id: StringName in _supply_props:
		(_supply_props[supply_id] as Node3D).visible = list.has(supply_id)


func _on_house_delivery_recorded(house_index: int, outcome: StringName, _package_id: StringName) -> void:
	if house_index < _board_marks.size():
		var mark: Label3D = _board_marks[house_index]
		match outcome:
			&"delivered_ok":
				mark.text = "OK"
				mark.modulate = Color("1f8a5b")
			&"delivered_at_risk":
				mark.text = "OK"
				mark.modulate = Color("d9822b")
			&"delivered_ruined":
				mark.text = "ROTO"
				mark.modulate = Color("c0392b")
			_:
				mark.text = "NO"
				mark.modulate = Color("857a6e")
	var network: Node = _autoload(&"NetworkManager")
	var host: bool = network == null or bool(network.call(&"is_host"))
	if host and _insured and outcome == &"delivered_ruined":
		var crew: Node = _autoload(&"CrewProgression")
		if crew != null:
			crew.call(&"add_team_money", INSURANCE_REFUND)
			_notice("El seguro cubrió la caja rota: +$%d" % INSURANCE_REFUND)
			_broadcast_supplies()


func _notice(text: String) -> void:
	var bus: Node = _autoload(&"EventBus")
	if bus != null:
		bus.call(&"relay", &"depot_notice", [text])


# --- Presentation that moves ------------------------------------------------


func _process(delta: float) -> void:
	for fan: Node3D in _fans:
		fan.rotate_y(delta * 0.9)
	if _clock_hour != null:
		var now: Dictionary = Time.get_time_dict_from_system()
		var minutes: float = float(now.minute) + float(now.second) / 60.0
		_clock_minute.rotation.z = -TAU * minutes / 60.0
		_clock_hour.rotation.z = -TAU * (float(int(now.hour) % 12) + minutes / 60.0) / 12.0
	if _belt_material != null:
		_belt_material.uv1_offset.x = fmod(_belt_material.uv1_offset.x - delta * 0.6, 1.0)
		for box: Node3D in _belt_boxes:
			box.position.x += delta * 0.6
			if box.position.x > CONVEYOR_END_X - 0.2:
				box.position.x -= CONVEYOR_END_X - CONVEYOR_START_X
	if _flicker_tube != null:
		_flicker_time -= delta
		if _flicker_time <= 0.0:
			var on: bool = not _flicker_tube.visible or randf() < 0.3
			_flicker_tube.visible = on
			_flicker_time = randf_range(0.03, 0.12) if randf() < 0.7 else randf_range(1.5, 5.0)


# --- Building ----------------------------------------------------------------


const CONVEYOR_START_X: float = -9.8
const CONVEYOR_END_X: float = 7.2
const CONVEYOR_Z: float = 30.6


func _build_structure() -> void:
	var kit := DepotKit.new(self, "BuildingColliders")
	var outside := DepotKit.ribbed(Color("3f6f7a"), 0.8)
	var trim := DepotKit.flat(Color("24363d"), 0.6, 0.3)
	var liner_low := DepotKit.detailed(Color("7f8d93"), "plaster", 1.4)
	var liner_high := DepotKit.ribbed(Color("dce1e2"), 0.7, 0.6, 0.15)
	var steel := DepotKit.flat(Color("3b4c53"), 0.5, 0.4)
	var floor := DepotKit.detailed(Color("a2aaac"), "plaster", 5.0, 0.55)
	var outer_x: float = HALF_WIDTH + WALL
	# Floor slab, flush with the road's surface at the door.
	kit.span(Vector3(-outer_x, -0.6, -WALL), Vector3(outer_x, FLOOR_TOP, DEPTH + WALL), floor, true)
	# Outer walls, parapet high so the flat roof hides behind them.
	kit.span(Vector3(-outer_x, -0.4, -WALL), Vector3(-HALF_WIDTH, WALL_HEIGHT, DEPTH + WALL), outside, true)
	kit.span(Vector3(HALF_WIDTH, -0.4, -WALL), Vector3(outer_x, WALL_HEIGHT, DEPTH + WALL), outside, true)
	kit.span(Vector3(-HALF_WIDTH, -0.4, DEPTH), Vector3(HALF_WIDTH, WALL_HEIGHT, DEPTH + WALL), outside, true)
	var jamb: float = DOOR_WIDTH * 0.5 + 0.2
	kit.span(Vector3(-HALF_WIDTH, -0.4, -WALL), Vector3(-jamb, WALL_HEIGHT, -0.02), outside, true)
	kit.span(Vector3(jamb, -0.4, -WALL), Vector3(HALF_WIDTH, WALL_HEIGHT, -0.02), outside, true)
	kit.span(Vector3(-jamb, DOOR_HEIGHT, -WALL), Vector3(jamb, WALL_HEIGHT, -0.02), outside, true)
	# Parapet cap and a plinth, so the shell doesn't read as a plain box.
	for piece: Array in [[Vector3(-outer_x - 0.05, WALL_HEIGHT, -WALL - 0.05), Vector3(outer_x + 0.05, WALL_HEIGHT + 0.18, -WALL + 0.25)],
			[Vector3(-outer_x - 0.05, WALL_HEIGHT, DEPTH + WALL - 0.25), Vector3(outer_x + 0.05, WALL_HEIGHT + 0.18, DEPTH + WALL + 0.05)],
			[Vector3(-outer_x - 0.05, WALL_HEIGHT, -WALL), Vector3(-outer_x + 0.25, WALL_HEIGHT + 0.18, DEPTH + WALL)],
			[Vector3(outer_x - 0.25, WALL_HEIGHT, -WALL), Vector3(outer_x + 0.05, WALL_HEIGHT + 0.18, DEPTH + WALL)]]:
		kit.span(piece[0], piece[1], trim)
	var plinth := DepotKit.detailed(Color("6f7873"), "stone", 1.6)
	kit.span(Vector3(-outer_x - 0.06, -0.4, -WALL - 0.06), Vector3(-jamb, 0.55, -WALL), plinth)
	kit.span(Vector3(jamb, -0.4, -WALL - 0.06), Vector3(outer_x + 0.06, 0.55, -WALL), plinth)
	kit.span(Vector3(-outer_x - 0.06, -0.4, -WALL), Vector3(-outer_x, 0.55, DEPTH + WALL), plinth)
	kit.span(Vector3(outer_x, -0.4, -WALL), Vector3(outer_x + 0.06, 0.55, DEPTH + WALL), plinth)
	kit.span(Vector3(-outer_x, -0.4, DEPTH + WALL), Vector3(outer_x, 0.55, DEPTH + WALL + 0.06), plinth)
	# Interior liner: block dado below, light sheet above.
	for side: float in [-1.0, 1.0]:
		var x: float = side * (HALF_WIDTH - 0.03)
		kit.box(Vector3(0.06, 2.4, DEPTH), Vector3(x, 1.2 + FLOOR_TOP, DEPTH * 0.5), liner_low)
		kit.box(Vector3(0.06, CEILING - 2.4, DEPTH), Vector3(x, 2.4 + (CEILING - 2.4) * 0.5, DEPTH * 0.5), liner_high)
	kit.box(Vector3(HALF_WIDTH * 2.0, 2.4, 0.06), Vector3(0.0, 1.2 + FLOOR_TOP, DEPTH - 0.03), liner_low)
	kit.box(Vector3(HALF_WIDTH * 2.0, CEILING - 2.4, 0.06), Vector3(0.0, 2.4 + (CEILING - 2.4) * 0.5, DEPTH - 0.03), liner_high)
	for side: float in [-1.0, 1.0]:
		var inner: float = HALF_WIDTH - jamb
		var centre: float = side * (jamb + inner * 0.5)
		kit.box(Vector3(inner, 2.4, 0.06), Vector3(centre, 1.2 + FLOOR_TOP, 0.01), liner_low)
		kit.box(Vector3(inner, CEILING - 2.4, 0.06), Vector3(centre, 2.4 + (CEILING - 2.4) * 0.5, 0.01), liner_high)
	kit.box(Vector3(jamb * 2.0, CEILING - DOOR_HEIGHT - 0.9, 0.06), Vector3(0.0, DOOR_HEIGHT + 0.9 + (CEILING - DOOR_HEIGHT - 0.9) * 0.5, 0.01), liner_high)
	# Roof deck and its skylights.
	kit.span(Vector3(-outer_x, CEILING, -WALL), Vector3(outer_x, CEILING + 0.22, DEPTH + WALL), DepotKit.ribbed(Color("c6cccd"), 0.9, 0.7, 0.2))
	for x: float in [-7.5, 7.5]:
		for z: float in [5.0, 16.0, 27.0]:
			kit.box(Vector3(1.6, 0.04, 7.0), Vector3(x, CEILING - 0.01, z), DepotKit.glow(Color("e4f1ef"), 0.9))
	# Portal frames: columns along the walls, trusses across.
	for z: float in [2.4, 8.0, 13.6, 19.2, 24.8, 30.4]:
		for side: float in [-1.0, 1.0]:
			kit.box(Vector3(0.36, CEILING, 0.3), Vector3(side * (HALF_WIDTH - 0.24), CEILING * 0.5, z), steel)
			kit.box(Vector3(0.4, 0.3, 0.34), Vector3(side * (HALF_WIDTH - 0.24), 0.18, z), DepotKit.flat(Color("e7be51"), 0.6))
		kit.box(Vector3(HALF_WIDTH * 2.0, 0.16, 0.16), Vector3(0.0, 6.55, z), steel)
		kit.box(Vector3(HALF_WIDTH * 2.0, 0.16, 0.16), Vector3(0.0, CEILING - 0.1, z), steel)
		for index: int in range(12):
			var x0: float = -HALF_WIDTH + 1.25 + index * 2.5
			kit.box(Vector3(0.08, CEILING - 6.55, 0.08), Vector3(x0, (6.55 + CEILING) * 0.5, z), steel)
			var rise: float = CEILING - 0.1 - 6.55
			var diagonal: float = sqrt(1.25 * 1.25 + rise * rise)
			var angle: float = atan2(rise, 1.25) * (1.0 if index % 2 == 0 else -1.0)
			kit.box_xf(Vector3(diagonal, 0.07, 0.07), Transform3D(Basis(Vector3.BACK, angle), Vector3(x0 + 0.625, (6.55 + CEILING - 0.1) * 0.5, z)), steel)
	# Purlins along the length.
	for x: float in [-11.0, -3.8, 3.8, 11.0]:
		kit.box(Vector3(0.1, 0.14, DEPTH), Vector3(x, CEILING - 0.18, DEPTH * 0.5), steel)
	# High strip windows (daylight inside, dark glass outside).
	for side: float in [-1.0, 1.0]:
		for z: float in [5.2, 10.8, 16.4, 22.0, 27.6]:
			kit.box(Vector3(0.02, 1.1, 3.6), Vector3(side * (HALF_WIDTH - 0.07), 5.4, z), DepotKit.glow(Color("d6ecec"), 0.75))
			kit.box(Vector3(0.02, 1.1, 3.6), Vector3(side * (HALF_WIDTH + WALL + 0.01), 5.4, z), DepotKit.flat(Color("22343b"), 0.15, 0.3))
			kit.box(Vector3(0.08, 1.24, 3.74), Vector3(side * (HALF_WIDTH + WALL + 0.02), 5.4, z), trim)
	# Exterior downpipes and wall lamps on the facade.
	for x: float in [-HALF_WIDTH - 0.1, HALF_WIDTH + 0.1]:
		kit.cylinder(0.08, WALL_HEIGHT, Transform3D(Basis.IDENTITY, Vector3(x, WALL_HEIGHT * 0.5, -WALL - 0.12)), trim, 8)
	for x: float in [-5.6, 5.6]:
		kit.box(Vector3(0.5, 0.25, 0.3), Vector3(x, 4.6, -WALL - 0.15), trim)
		kit.box(Vector3(0.42, 0.06, 0.24), Vector3(x, 4.46, -WALL - 0.15), DepotKit.glow(Color("fff1d6"), 2.0))
	# Staff door on the facade, and its canopy.
	kit.box(Vector3(1.1, 2.2, 0.08), Vector3(9.5, 1.1 + FLOOR_TOP, -WALL - 0.04), DepotKit.flat(Color("2f7a64"), 0.6))
	kit.box(Vector3(1.3, 0.08, 0.7), Vector3(9.5, 2.55, -WALL - 0.35), trim)
	kit.box(Vector3(0.06, 0.3, 0.06), Vector3(9.9, 1.1, -WALL - 0.1), DepotKit.flat(Color("c9ced0"), 0.3, 0.8))
	kit.box(Vector3(1.1, 2.2, 0.06), Vector3(9.5, 1.1 + FLOOR_TOP, 0.03), DepotKit.flat(Color("2f7a64"), 0.6))
	_build_floor_markings(kit)
	_build_wayfinding(kit)
	_build_wall_racking(kit)
	_build_dispatch_shelves(kit)
	_build_workshop(kit)
	_build_lockers(kit)
	_build_break_area(kit)
	_build_shop(kit)
	_build_office(kit)
	_build_conveyor(kit)
	_build_staging(kit)
	_build_exterior(kit)
	kit.commit("Depot")


func _build_floor_markings(kit: DepotKit) -> void:
	var yellow := DepotKit.flat(YELLOW, 0.7)
	var white := DepotKit.flat(Color("e8ebe4"), 0.7)
	var hazard := DepotKit.detailed(Color.WHITE, WARNING_TEXTURE, 0.9, 0.7)
	var y: float = FLOOR_TOP + 0.003
	var paint := func(size_x: float, size_z: float, centre: Vector3, material: Material) -> void:
		var mesh := BoxMesh.new()
		mesh.size = Vector3(size_x, 0.006, size_z)
		kit.add_mesh(mesh, Transform3D(Basis.IDENTITY, Vector3(centre.x, y, centre.z)), material, false)
	# Saw-cut joints of the poured slab, every six metres.
	var joint := DepotKit.flat(Color("7d8587"), 0.8)
	for index: int in range(1, 5):
		var x: float = -HALF_WIDTH + index * 6.0
		var mesh := BoxMesh.new()
		mesh.size = Vector3(0.025, 0.004, DEPTH)
		kit.add_mesh(mesh, Transform3D(Basis.IDENTITY, Vector3(x, FLOOR_TOP + 0.001, DEPTH * 0.5)), joint, false)
	for index: int in range(1, 6):
		var mesh := BoxMesh.new()
		mesh.size = Vector3(HALF_WIDTH * 2.0, 0.004, 0.025)
		kit.add_mesh(mesh, Transform3D(Basis.IDENTITY, Vector3(0.0, FLOOR_TOP + 0.001, index * 6.0)), joint, false)
	# Truck bay: a white box the truck sits in, its stop bar behind the ramp.
	paint.call(0.12, 11.2, Vector3(-1.9, 0.0, 7.8), white)
	paint.call(0.12, 11.2, Vector3(1.9, 0.0, 7.8), white)
	paint.call(3.92, 0.12, Vector3(0.0, 0.0, 13.4), white)
	# Hazard band inside the door, and the loading zone behind the truck.
	paint.call(DOOR_WIDTH, 1.2, Vector3(0.0, 0.0, 0.9), hazard)
	paint.call(3.6, 0.8, Vector3(0.0, 0.0, 14.1), hazard)
	# Yellow walkway edges and the zones' outlines.
	for x: float in [-3.3, 3.3]:
		paint.call(0.1, 13.0, Vector3(x, 0.0, 8.0), yellow)
	for unit: Dictionary in SHELF_UNITS:
		var x: float = float(unit.x)
		var length: float = BAY_LENGTH * BAYS
		for side: float in [-1.0, 1.0]:
			paint.call(0.08, length + 0.6, Vector3(x + side * (SHELF_DEPTH * 0.5 + 0.3), 0.0, SHELF_START_Z + length * 0.5), yellow)
		for end: float in [SHELF_START_Z - 0.3, SHELF_START_Z + length + 0.3]:
			paint.call(SHELF_DEPTH + 0.68, 0.08, Vector3(x, 0.0, end), yellow)
	paint.call(0.1, 30.0, Vector3(-13.1, 0.0, 16.0), yellow)
	paint.call(0.1, 25.0, Vector3(-11.0, 0.0, 15.0), DepotKit.flat(TEAL, 0.7))
	# Painted floor words, facing whoever walks toward them.
	_floor_text("CARRIL AUTOELEVADOR", Vector3(-12.05, 0.0, 12.0), -PI * 0.5, 44, Color(YELLOW, 0.85))
	_floor_text("SALIDA", Vector3(0.0, 0.0, 2.6), 0.0, 90, Color(TEAL, 0.9))
	_floor_text("ZONA DE CARGA", Vector3(0.0, 0.0, 14.1), 0.0, 40, Color(INK, 0.9))
	_floor_text("TALLER", Vector3(10.8, 0.0, 6.5), -PI * 0.5, 80, Color("e8ebe4", 0.8))


## How a new player finds each station without anyone telling them (tareas
## de Nacho N-503): arrows on the floor around the spawn, chevrons beside the
## truck toward the door, and hanging signs that read from where the crew
## appears -- over the board (and on to the shelves), over the truck, and to
## the right toward the lockers and the shop. Each place's own sign hangs
## over it too (_build_workshop, _build_lockers...).
func _build_wayfinding(kit: DepotKit) -> void:
	for guide: Dictionary in FLOOR_GUIDES:
		var at: Vector3 = guide.arrow
		_paint_arrow(kit, guide.caption, at, ((guide.toward as Vector3) - at).normalized(), guide.colour)
		_floor_text(guide.caption, guide.word, 0.0, 34, Color(guide.colour as Color, 0.95))
	for x: float in [-2.6, 2.6]:
		for z: float in [11.6, 7.6, 3.6]:
			_paint_arrow(kit, "PORTÓN", Vector3(x, 0.0, z), Vector3.FORWARD, TEAL)
	var board_yaw: float = deg_to_rad(38.0)
	var over_board: Vector3 = Vector3(-4.5, 0.0, 13.0) + Basis(Vector3.UP, board_yaw) * Vector3(0.9, 0.0, 0.0)
	_hanging_sign(kit, "← ESTANTES", over_board + Vector3(0.0, 4.3, 0.0), board_yaw, SHELVES_BLUE)
	_hanging_sign(kit, "PIZARRA", over_board + Vector3(0.0, 3.5, 0.0), board_yaw, BOARD_GREEN, 4.0)
	# High enough over the truck's roof to read above it from behind.
	_hanging_sign(kit, "CAMIÓN → PORTÓN", Vector3(0.0, 4.4, 11.0), 0.0, INK, CEILING - 0.25, Color("ffc93c"))
	var right := Vector3(4.6, 0.0, 11.0)
	var right_yaw: float = deg_to_rad(-30.0)
	_hanging_sign(kit, "VESTUARIO →", right + Vector3(0.0, 4.35, 0.0), right_yaw, LOCKERS_TEAL)
	_hanging_sign(kit, "SUMINISTROS →", right + Vector3(0.0, 3.55, 0.0), right_yaw, SHOP_PURPLE, 4.05)


## An arrow painted on the floor at `at`, pointing along `direction`.
func _paint_arrow(kit: DepotKit, caption: String, at: Vector3, direction: Vector3, colour: Color) -> void:
	var flat := Basis(direction, Vector3.UP.cross(direction), Vector3.UP)
	_arrow_shape(kit, Transform3D(flat, Vector3(at.x, FLOOR_TOP + 0.004, at.z)), 1.1, 0.62, 0.006, DepotKit.flat(colour, 0.7))
	guides.append({"caption": caption, "at": Vector3(at.x, 0.0, at.z), "direction": direction})


## A flat arrow along `xform`'s +X: `length` long, `width` across the head,
## `thickness` deep along its Z.
func _arrow_shape(kit: DepotKit, xform: Transform3D, length: float, width: float, thickness: float, material: Material) -> void:
	var head_length: float = length * 0.45
	var shaft := BoxMesh.new()
	shaft.size = Vector3(length - head_length + 0.02, width * 0.36, thickness)
	kit.add_mesh(shaft, xform * Transform3D(Basis.IDENTITY, Vector3((0.02 - head_length) * 0.5, 0.0, 0.0)), material, false)
	var head := PrismMesh.new()
	head.size = Vector3(width, head_length, thickness)
	kit.add_mesh(head, xform * Transform3D(Basis(Vector3.BACK, -PI * 0.5), Vector3((length - head_length) * 0.5, 0.0, 0.0)), material, false)


func _build_wall_racking(kit: DepotKit) -> void:
	var blue := DepotKit.flat(Color("2f5d8a"), 0.5, 0.3)
	var orange := DepotKit.flat(Color("e8772e"), 0.5, 0.2)
	var deck := DepotKit.ribbed(Color("9ea6a9"), 0.15, 0.5, 0.4)
	var film := DepotKit.glass(Color(0.85, 0.9, 0.95, 0.35))
	var rng := RandomNumberGenerator.new()
	rng.seed = 4471
	var x_back: float = -HALF_WIDTH + 0.2
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
		kit.collider(Vector3(depth + 0.1, 6.3, length), Transform3D(Basis.IDENTITY, Vector3(centre_x, 3.15, (z0 + z1) * 0.5)))
		for beam_y: float in beams:
			for x: float in [x_back, x_front]:
				kit.box(Vector3(0.06, 0.12, length), Vector3(x, beam_y, (z0 + z1) * 0.5), orange)
			kit.box(Vector3(depth, 0.03, length - 0.1), Vector3(centre_x, beam_y + 0.07, (z0 + z1) * 0.5), deck)
		for level: int in range(4):
			var base_y: float = FLOOR_TOP if level == 0 else beams[level - 1] + 0.085
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
	kit.model_grounded(PALLET, Transform3D(Basis(Vector3.UP, yaw), base))
	var top: Vector3 = base + Vector3(0.0, 0.1, 0.0)
	if roll < 0.3:
		kit.model_grounded(CRATE, Transform3D(Basis(Vector3.UP, yaw + rng.randf_range(-0.1, 0.1)).scaled(Vector3.ONE * 0.95), top))
		return
	var layers: int = 1 if top_level else rng.randi_range(1, 2)
	var box_path: String = CARGO_BOXES[rng.randi() % CARGO_BOXES.size()]
	var bounds: AABB = kit.model_bounds(box_path)
	var scale: float = clampf(0.55 / maxf(bounds.size.x, bounds.size.z), 0.4, 1.0)
	var height: float = bounds.size.y * scale
	for layer: int in range(layers):
		for ix: int in range(2):
			for iz: int in range(2):
				if rng.randf() < 0.08 and layer == layers - 1:
					continue
				var offset := Vector3((ix - 0.5) * 0.6, layer * height, (iz - 0.5) * 0.5)
				kit.model(box_path, Transform3D(Basis(Vector3.UP, rng.randf_range(-0.08, 0.08)).scaled(Vector3.ONE * scale), top + offset.rotated(Vector3.UP, yaw)))
	if roll > 0.75:
		# Stretch wrap around the whole load.
		kit.box(Vector3(1.24, height * layers + 0.04, 1.04), top + Vector3(0.0, (height * layers) * 0.5, 0.0), film, false, yaw)


func _build_dispatch_shelves(kit: DepotKit) -> void:
	var blue := DepotKit.flat(Color("2f5d8a"), 0.5, 0.3)
	var orange := DepotKit.flat(Color("e8772e"), 0.5, 0.2)
	var deck := DepotKit.ribbed(Color("a9b0b3"), 0.12, 0.5, 0.4)
	var length: float = BAY_LENGTH * BAYS
	for unit: Dictionary in SHELF_UNITS:
		var x: float = float(unit.x)
		for frame: int in range(BAYS + 1):
			var z: float = SHELF_START_Z + frame * BAY_LENGTH
			for side: float in [-1.0, 1.0]:
				kit.box(Vector3(0.08, 2.7, 0.08), Vector3(x + side * SHELF_DEPTH * 0.5, 1.35, z), blue, true)
			kit.box(Vector3(SHELF_DEPTH, 0.04, 0.04), Vector3(x, 0.9, z), blue)
			kit.box(Vector3(SHELF_DEPTH, 0.04, 0.04), Vector3(x, 2.1, z), blue)
		for deck_top: float in LEVEL_TOPS + [2.6]:
			for side: float in [-1.0, 1.0]:
				kit.box(Vector3(0.05, 0.1, length), Vector3(x + side * (SHELF_DEPTH * 0.5 - 0.02), deck_top - 0.07, SHELF_START_Z + length * 0.5), orange)
			kit.box(Vector3(SHELF_DEPTH - 0.04, 0.04, length), Vector3(x, deck_top - 0.02, SHELF_START_Z + length * 0.5), deck, true)
		# Loose small stock on the top deck, out of reach and just for show.
		var rng := RandomNumberGenerator.new()
		rng.seed = 90 + int(x)
		for bay: int in range(BAYS):
			var z: float = SHELF_START_Z + (bay + 0.5) * BAY_LENGTH
			for count: int in range(rng.randi_range(1, 3)):
				var path: String = CARGO_BOXES[rng.randi() % CARGO_BOXES.size()]
				kit.model(path, Transform3D(Basis(Vector3.UP, rng.randf_range(-0.3, 0.3)).scaled(Vector3.ONE * 0.5), Vector3(x + rng.randf_range(-0.2, 0.2), 2.6, z + (count - 1) * 0.55)))
		# Every bay-level is a slot, labelled on both faces of the shelf.
		for level: int in range(LEVEL_TOPS.size()):
			for bay: int in range(BAYS):
				var number: int = level * BAYS + bay + 1
				var code: String = "%s-%d" % [unit.aisle, number]
				var z: float = SHELF_START_Z + (bay + 0.5) * BAY_LENGTH
				slots.append({"code": code, "transform": Transform3D(Basis.IDENTITY, Vector3(x, LEVEL_TOPS[level], z))})
				for side: float in [-1.0, 1.0]:
					var face: float = x + side * (SHELF_DEPTH * 0.5 + 0.02)
					var tag := _text(code, Vector3(face, LEVEL_TOPS[level] - 0.07, z), side * PI * 0.5, 30, INK, DISPLAY_FONT, 0.004, 0)
					tag.name = "Tag%s_%d" % [code, 0 if side < 0 else 1]
					kit.box(Vector3(0.012, 0.09, 0.36), Vector3(face - side * 0.005, LEVEL_TOPS[level] - 0.07, z), DepotKit.flat(PAPER, 0.8))
		# Aisle sign hanging over the unit.
		# Named as the board reads ("ESTANTE A-3").
		_hanging_sign(kit, "ESTANTE %s" % unit.aisle, Vector3(x, 3.7, SHELF_START_Z + length * 0.5), PI * 0.5, SHELVES_BLUE)


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
		kit.box(Vector3(0.04, tool_height, 0.05), Vector3(14.88, 2.0 - tool_height * 0.2, z), steel if index % 2 == 0 else red)
	kit.cylinder(0.12, 0.14, Transform3D(Basis(Vector3.FORWARD, PI * 0.5), Vector3(14.1, 1.07, 6.8)), DepotKit.flat(Color("ffc93c"), 0.5), 12)  # tape roll
	kit.box(Vector3(0.3, 0.2, 0.45), Vector3(14.3, 1.09, 4.4), red)  # toolbox
	# Rolling tool chest.
	kit.box(Vector3(0.7, 1.1, 1.2), Vector3(14.4, 0.6, 9.0), red, true)
	for drawer: int in range(5):
		kit.box(Vector3(0.02, 0.03, 1.0), Vector3(14.04, 0.3 + drawer * 0.2, 9.0), steel)
	# Paint station: cans on a rack and swatches of what the truck can wear.
	kit.box(Vector3(0.5, 1.6, 2.0), Vector3(14.65, 0.8, 11.6), dark, true)
	var paints: Array[Color] = [Color("dde2e8"), Color("7b52b9"), Color("2dd4a3"), Color("ff5e5b"), Color("ffc93c"), Color("4cc9f0")]
	for index: int in range(paints.size()):
		for level: int in range(2):
			kit.cylinder(0.11, 0.24, Transform3D(Basis.IDENTITY, Vector3(14.35, 0.5 + level * 0.6, 10.85 + index * 0.3)), DepotKit.flat(paints[(index + level) % paints.size()], 0.5, 0.3), 10)
	for index: int in range(paints.size()):
		kit.box(Vector3(0.02, 0.45, 0.45), Vector3(14.9, 3.0, 9.2 + index * 0.55), DepotKit.flat(paints[index], 0.6))
	# Air compressor with its hose reel.
	kit.cylinder(0.3, 1.0, Transform3D(Basis(Vector3.FORWARD, PI * 0.5), Vector3(13.1, 0.4, 2.2)), red, 14, true)
	kit.box(Vector3(0.4, 0.3, 0.3), Vector3(13.1, 0.85, 2.2), dark)
	kit.cylinder(0.22, 0.1, Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(14.9, 1.6, 1.5)), DepotKit.flat(Color("ffc93c"), 0.6), 14)
	# Customisation kiosk facing the crew as they come round the truck.
	kit.box(Vector3(0.7, 1.2, 0.5), Vector3(4.6, 0.6, 9.6), dark, true)
	kit.box(Vector3(0.66, 0.5, 0.06), Vector3(4.6, 1.45, 9.8), dark)
	kit.box(Vector3(0.56, 0.4, 0.02), Vector3(4.6, 1.45, 9.84), DepotKit.glow(Color("4cc9f0"), 1.1))
	_text("TALLER", Vector3(4.6, 1.56, 9.86), 0.0, 40, PAPER, DISPLAY_FONT, 0.004, 4)
	_text("pintura · camión", Vector3(4.6, 1.38, 9.86), 0.0, 26, INK, BODY_FONT, 0.004, 0)
	_hanging_sign(kit, "TALLER", Vector3(11.5, 3.9, 6.0), 0.0, WORKSHOP_RED)


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
		kit.box(Vector3(0.01, 0.07, 0.2), Vector3(14.4, 1.45, z), DepotKit.flat(PAPER, 0.8))
	kit.collider(Vector3(0.58, 2.0, 5.0), Transform3D(Basis.IDENTITY, Vector3(14.68, 1.0, 13.3 + 3.5 * 0.62)))
	# Bench in front of them, and a full-length mirror (a real one: DepotMirror)
	# at the end of the row, to check the uniform.
	kit.box(Vector3(0.4, 0.06, 3.2), Vector3(13.4, 0.46, 15.5), DepotKit.detailed(Color("b08a5a"), "wood_planks", 1.0), true)
	for z: float in [14.2, 16.8]:
		kit.box(Vector3(0.3, 0.44, 0.06), Vector3(13.4, 0.22, z), dark)
	# Clear of the lining (to x 14.94) and of the column at z 19.05.
	kit.box(Vector3(0.05, 2.0, 0.9), Vector3(14.91, 1.1, 18.5), dark)
	var mirror := DepotMirror.new()
	mirror.name = "Mirror"
	mirror.glass_size = Vector2(0.8, 1.9)
	mirror.position = Vector3(14.875, 1.1, 18.5)
	mirror.rotation.y = -PI * 0.5
	add_child(mirror)
	# A vanity lamp over it, so the uniform reads even on a dark day.
	kit.box(Vector3(0.12, 0.06, 0.7), Vector3(14.85, 2.14, 18.5), DepotKit.glow(Color("fff1d6"), 2.0), false)
	var vanity := OmniLight3D.new()
	vanity.name = "MirrorLamp"
	vanity.position = Vector3(14.3, 2.1, 18.5)
	vanity.light_color = Color("fff1d6")
	vanity.light_energy = 0.9
	vanity.omni_range = 2.6
	add_child(vanity)
	_hanging_sign(kit, "VESTUARIO", Vector3(13.2, 3.4, 15.5), -PI * 0.5, LOCKERS_TEAL)


func _build_break_area(kit: DepotKit) -> void:
	var dark := DepotKit.flat(Color("263238"), 0.7)
	# Coffee machine: body, glowing panel, drip tray and a cup.
	kit.box(Vector3(0.6, 1.8, 0.7), Vector3(14.6, 0.9, 20.2), DepotKit.flat(Color("8c2f39"), 0.4, 0.2), true)
	kit.box(Vector3(0.02, 0.5, 0.45), Vector3(14.29, 1.35, 20.2), DepotKit.glow(Color("ffd08a"), 0.9))
	kit.box(Vector3(0.12, 0.03, 0.3), Vector3(14.26, 0.75, 20.2), dark)
	kit.cylinder(0.04, 0.09, Transform3D(Basis.IDENTITY, Vector3(14.24, 0.81, 20.2)), DepotKit.flat(PAPER, 0.7), 10)
	_text("CAFÉ", Vector3(14.28, 1.7, 20.2), -PI * 0.5, 40, PAPER, DISPLAY_FONT, 0.004, 4)
	# Water cooler.
	kit.box(Vector3(0.4, 1.0, 0.4), Vector3(14.6, 0.5, 21.2), DepotKit.flat(Color("e8ebe4"), 0.6), true)
	kit.cylinder(0.17, 0.45, Transform3D(Basis.IDENTITY, Vector3(14.6, 1.25, 21.2)), DepotKit.glass(Color(0.55, 0.78, 0.95, 0.55)), 14)
	# Round table with two stools.
	kit.cylinder(0.55, 0.05, Transform3D(Basis.IDENTITY, Vector3(12.6, 0.95, 20.8)), DepotKit.flat(Color("e8ebe4"), 0.5), 18, true)
	kit.cylinder(0.05, 0.92, Transform3D(Basis.IDENTITY, Vector3(12.6, 0.47, 20.8)), dark, 8)
	for offset: Vector3 in [Vector3(-0.8, 0.0, 0.1), Vector3(0.2, 0.0, 0.8)]:
		kit.cylinder(0.2, 0.05, Transform3D(Basis.IDENTITY, Vector3(12.6, 0.62, 20.8) + offset), DepotKit.flat(Color("e8772e"), 0.6), 12)
		kit.cylinder(0.03, 0.6, Transform3D(Basis.IDENTITY, Vector3(12.6, 0.31, 20.8) + offset), dark, 6)
	kit.cylinder(0.045, 0.1, Transform3D(Basis.IDENTITY, Vector3(12.45, 1.02, 20.7)), DepotKit.flat(Color("4cc9f0"), 0.6), 10)
	# The radio on the table that plays all day.
	kit.box(Vector3(0.34, 0.2, 0.14), Vector3(12.8, 1.07, 21.0), DepotKit.flat(Color("2f7a64"), 0.5), false, 0.4)
	kit.cylinder(0.06, 0.02, Transform3D(Basis(Vector3.RIGHT, PI * 0.5).rotated(Vector3.UP, 0.4), Vector3(12.76, 1.07, 20.93)), dark, 12)


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
					kit.cylinder(0.2, 0.5, Transform3D(Basis(Vector3.FORWARD, PI * 0.5), Vector3(x, 0.67 + level * 0.7, 26.75)), DepotKit.glass(Color(0.85, 0.92, 0.98, 0.6)), 12)
				1:
					kit.cylinder(0.11, 0.08, Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(x, 0.58 + level * 0.7, 26.7)), DepotKit.flat(Color("e0a867"), 0.5), 12)
				_:
					kit.box(Vector3(0.45, 0.3, 0.4), Vector3(x, 0.62 + level * 0.7, 26.75), DepotKit.flat(Color("7fa7b5") if level == 1 else Color("e8772e"), 0.9))
	# The supplies that are bought wait on the counter, ready to go.
	for supply: Array in [[&"padding", Vector3(11.6, 1.25, 23.9), Color("7fa7b5")], [&"insurance", Vector3(12.4, 1.1, 23.95), PAPER]]:
		var prop := MeshInstance3D.new()
		prop.name = "Supply_%s" % supply[0]
		var mesh := BoxMesh.new()
		mesh.size = Vector3(0.5, 0.4, 0.4) if supply[0] == &"padding" else Vector3(0.3, 0.02, 0.22)
		prop.mesh = mesh
		prop.material_override = DepotKit.flat(supply[2], 0.8)
		prop.position = supply[1]
		prop.visible = false
		add_child(prop)
		_supply_props[supply[0]] = prop
	_hanging_sign(kit, "SUMINISTROS", Vector3(10.8, 3.4, 24.0), PI, SHOP_PURPLE)


func _build_office(kit: DepotKit) -> void:
	var frame := DepotKit.flat(Color("263238"), 0.6, 0.3)
	var panel := DepotKit.detailed(Color("d5d9d2"), "plaster", 1.6)
	var glass := DepotKit.glass()
	var x0: float = 8.6
	var z0: float = 27.8
	# Front wall (toward -Z) and side wall (toward -X): solid below, glazed above.
	kit.box(Vector3(HALF_WIDTH - x0, 1.0, 0.12), Vector3((x0 + HALF_WIDTH) * 0.5, 0.5, z0), panel, true)
	kit.box(Vector3(HALF_WIDTH - x0, 1.4, 0.04), Vector3((x0 + HALF_WIDTH) * 0.5, 1.7, z0), glass, true)
	kit.box(Vector3(HALF_WIDTH - x0, 0.6, 0.12), Vector3((x0 + HALF_WIDTH) * 0.5, 2.7, z0), panel, true)
	kit.box(Vector3(0.12, 1.0, DEPTH - z0 - 1.3), Vector3(x0, 0.5, z0 + (DEPTH - z0 - 1.3) * 0.5), panel, true)
	kit.box(Vector3(0.04, 1.4, DEPTH - z0 - 1.3), Vector3(x0, 1.7, z0 + (DEPTH - z0 - 1.3) * 0.5), glass, true)
	kit.box(Vector3(0.12, 0.6, DEPTH - z0), Vector3(x0, 2.7, (z0 + DEPTH) * 0.5), panel)
	kit.box(Vector3(0.12, 2.4, 0.12), Vector3(x0, 1.2, DEPTH - 1.3), frame)
	kit.box(Vector3(0.9, 2.1, 0.05), Vector3(x0 - 0.02, 1.05, DEPTH - 0.8), DepotKit.flat(Color("2f7a64"), 0.6), false, 0.0)
	kit.box(Vector3(HALF_WIDTH - x0 + 0.1, 0.1, DEPTH - z0 + 0.1), Vector3((x0 + HALF_WIDTH) * 0.5, 3.05, (z0 + DEPTH) * 0.5), frame)
	for x: float in [x0, 11.0, 13.2]:
		kit.box(Vector3(0.06, 1.44, 0.14), Vector3(x, 1.7, z0), frame)
	# Desk with the dispatch computer, a chair and a filing cabinet.
	kit.box(Vector3(2.0, 0.06, 0.8), Vector3(11.6, 0.76, 30.6), DepotKit.detailed(Color("b08a5a"), "wood_planks", 1.0), true)
	for x: float in [10.7, 12.5]:
		kit.box(Vector3(0.06, 0.74, 0.7), Vector3(x, 0.38, 30.6), frame)
	kit.box(Vector3(0.6, 0.38, 0.05), Vector3(11.4, 1.1, 30.85), frame)
	kit.box(Vector3(0.54, 0.32, 0.02), Vector3(11.4, 1.1, 30.82), DepotKit.glow(Color("8fd3e8"), 0.9))
	kit.box(Vector3(0.45, 0.02, 0.15), Vector3(11.4, 0.8, 30.35), frame)
	kit.box(Vector3(0.5, 1.3, 0.6), Vector3(14.5, 0.65, 29.2), DepotKit.flat(Color("8a9499"), 0.4, 0.5), true)
	kit.box(Vector3(0.04, 0.9, 1.4), Vector3(14.95, 1.8, 30.6), DepotKit.flat(Color("c9a26b"), 0.9))  # corkboard
	for index: int in range(5):
		kit.box(Vector3(0.01, 0.22, 0.18), Vector3(14.92, 1.65 + (index % 2) * 0.35, 30.1 + index * 0.24), DepotKit.flat(PAPER, 0.9))
	_hanging_sign(kit, "OFICINA", Vector3(11.8, 3.5, z0 - 0.1), PI, Color("263238"))


func _build_conveyor(kit: DepotKit) -> void:
	var frame := DepotKit.flat(Color("59656a"), 0.45, 0.5)
	var guard := DepotKit.flat(Color("e7be51"), 0.6)
	var length: float = CONVEYOR_END_X - CONVEYOR_START_X
	var centre: float = (CONVEYOR_START_X + CONVEYOR_END_X) * 0.5
	kit.box(Vector3(length, 0.14, 0.9), Vector3(centre, 0.84, CONVEYOR_Z), frame, true)
	for x: float in range(int(CONVEYOR_START_X) + 1, int(CONVEYOR_END_X), 2):
		for z: float in [CONVEYOR_Z - 0.4, CONVEYOR_Z + 0.4]:
			kit.box(Vector3(0.08, 0.8, 0.08), Vector3(x, 0.4, z), frame)
	for z: float in [CONVEYOR_Z - 0.47, CONVEYOR_Z + 0.47]:
		kit.box(Vector3(length, 0.12, 0.05), Vector3(centre, 1.0, z), guard)
	# Portals at each end with PVC strip curtains: stock appears from one and
	# disappears into the other.
	for x: float in [CONVEYOR_START_X, CONVEYOR_END_X]:
		kit.box(Vector3(1.2, 1.3, 1.3), Vector3(x, 1.55, CONVEYOR_Z), DepotKit.ribbed(Color("3b4c53"), 0.4), true)
		kit.box(Vector3(1.2, 0.9, 1.3), Vector3(x, 0.45, CONVEYOR_Z), frame)
		var face: float = x + (0.61 if x < 0.0 else -0.61)
		for strip: int in range(6):
			kit.box(Vector3(0.01, 0.6, 0.14), Vector3(face, 1.2, CONVEYOR_Z - 0.4 + strip * 0.16), DepotKit.glass(Color(0.75, 0.85, 0.8, 0.5)))
	# The belt itself scrolls (see _process); its boxes ride it.
	var belt := MeshInstance3D.new()
	belt.name = "ConveyorBelt"
	var belt_mesh := BoxMesh.new()
	belt_mesh.size = Vector3(length, 0.02, 0.8)
	belt.mesh = belt_mesh
	_belt_material = StandardMaterial3D.new()
	_belt_material.albedo_color = Color("3a3f42")
	_belt_material.albedo_texture = DepotKit._rib_texture()
	_belt_material.uv1_scale = Vector3(length * 2.0, 1.0, 1.0)
	_belt_material.roughness = 0.9
	belt.material_override = _belt_material
	belt.position = Vector3(centre, 0.92, CONVEYOR_Z)
	add_child(belt)
	var rng := RandomNumberGenerator.new()
	rng.seed = 17
	for index: int in range(9):
		var box_path: String = CARGO_BOXES[index % CARGO_BOXES.size()]
		var box := (load(box_path) as PackedScene).instantiate() as Node3D
		LowpolyMaterials.apply(box)
		box.name = "BeltBox%d" % index
		box.scale = Vector3.ONE * 0.6
		box.rotation.y = rng.randf_range(-0.2, 0.2)
		box.position = Vector3(CONVEYOR_START_X + 0.4 + index * (length / 9.0), 0.93, CONVEYOR_Z + rng.randf_range(-0.12, 0.12))
		add_child(box)
		_belt_boxes.append(box)


func _build_staging(kit: DepotKit) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 311
	var film := DepotKit.glass(Color(0.85, 0.9, 0.95, 0.35))
	# Pallets waiting to be put away, between the shelves and the belt.
	for spot: Vector3 in [Vector3(-5.2, FLOOR_TOP, 27.6), Vector3(-3.4, FLOOR_TOP, 27.6), Vector3(-5.2, FLOOR_TOP, 29.3)]:
		_stock_pallet(kit, spot, rng, false, film)
		kit.collider(Vector3(1.25, 1.5, 0.9), Transform3D(Basis.IDENTITY, spot + Vector3(0.0, 0.75, 0.0)))
	# Empty pallets stacked by the wall.
	for layer: int in range(6):
		kit.model_grounded(PALLET, Transform3D(Basis(Vector3.UP, rng.randf_range(-0.06, 0.06)), Vector3(-1.4, FLOOR_TOP + layer * 0.1, 31.3)))
	kit.collider(Vector3(1.3, 0.62, 0.9), Transform3D(Basis.IDENTITY, Vector3(-1.4, 0.31, 31.3)))
	# Packing table: cardboard, a tape gun and a roll of labels.
	var wood := DepotKit.detailed(Color("b08a5a"), "wood_planks", 1.2)
	kit.box(Vector3(2.4, 0.06, 1.0), Vector3(2.2, 0.9, 27.4), wood, true)
	for x: float in [1.1, 3.3]:
		for z: float in [27.0, 27.8]:
			kit.box(Vector3(0.06, 0.88, 0.06), Vector3(x, 0.44, z), DepotKit.flat(Color("59656a"), 0.5, 0.4))
	kit.model(CARGO_BOXES[0], Transform3D(Basis(Vector3.UP, 0.2).scaled(Vector3.ONE * 0.7), Vector3(1.6, 0.93, 27.4)))
	kit.box(Vector3(0.7, 0.01, 0.5), Vector3(2.5, 0.935, 27.3), DepotKit.flat(Color("e0a867"), 0.9), false, -0.15)
	kit.box(Vector3(0.12, 0.16, 0.2), Vector3(2.95, 1.0, 27.5), DepotKit.flat(Color("c0392b"), 0.5))
	kit.cylinder(0.08, 0.07, Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(3.2, 0.98, 27.1)), DepotKit.flat(PAPER, 0.7), 12)
	# Pallet jack parked beside it.
	var dark := DepotKit.flat(Color("263238"), 0.6)
	for x: float in [4.3, 4.75]:
		kit.box(Vector3(0.16, 0.08, 1.15), Vector3(x, 0.08, 26.4), DepotKit.flat(Color("e8772e"), 0.5))
	kit.box(Vector3(0.6, 0.3, 0.25), Vector3(4.52, 0.2, 27.1), DepotKit.flat(Color("e8772e"), 0.5))
	kit.box(Vector3(0.05, 1.0, 0.05), Vector3(4.52, 0.75, 27.35), dark, false, 0.0)


func _build_exterior(kit: DepotKit) -> void:
	var concrete := DepotKit.detailed(Color("8d948f"), "stone", 3.0, 0.8)
	var white := DepotKit.flat(Color("e8ebe4"), 0.7)
	var yellow := DepotKit.flat(YELLOW, 0.7)
	# Forecourt apron in front of the door, a hair above the ground around it.
	kit.span(Vector3(-HALF_WIDTH - 6.0, -0.5, -9.0), Vector3(HALF_WIDTH + 6.0, FLOOR_TOP, -WALL), concrete, true)
	if ground_apron:
		var grass := DepotKit.detailed(Color("5d7a4f"), "grass", 2.0)
		kit.span(Vector3(-60.0, -0.6, -9.0), Vector3(60.0, -0.02, 70.0), grass, true)
	# Staff parking on the left: bays, two cars, a kerb stop each.
	var bay_y: float = FLOOR_TOP + 0.003
	for index: int in range(4):
		var x: float = -19.8 + index * 2.6
		var mesh := BoxMesh.new()
		mesh.size = Vector3(0.1, 0.006, 4.6)
		kit.add_mesh(mesh, Transform3D(Basis.IDENTITY, Vector3(x, bay_y, -5.2)), white, false)
	kit.model_grounded("res://assets/models/vehicles/sm_vehicle_parked_sedan_refined.glb", Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(-18.5, FLOOR_TOP, -5.2)))
	kit.model_grounded("res://assets/models/vehicles/sm_vehicle_competitor_van.glb", Transform3D(Basis(Vector3.UP, PI * 0.5 + 0.04), Vector3(-11.8, FLOOR_TOP, -5.4)))
	kit.collider(Vector3(1.8, 1.5, 4.0), Transform3D(Basis.IDENTITY, Vector3(-18.5, 0.75, -5.2)))
	kit.collider(Vector3(1.8, 1.5, 4.0), Transform3D(Basis.IDENTITY, Vector3(-15.9, 0.75, -5.4)))
	# Dumpster and a stack of spare pallets on the right.
	kit.box(Vector3(2.0, 1.3, 1.2), Vector3(17.8, 0.65 + FLOOR_TOP, -2.0), DepotKit.flat(Color("2f6b4f"), 0.7, 0.2), true)
	kit.box(Vector3(2.1, 0.08, 1.3), Vector3(17.8, 1.34 + FLOOR_TOP, -2.0), DepotKit.flat(Color("24363d"), 0.7), false)
	for layer: int in range(8):
		kit.model_grounded(PALLET, Transform3D(Basis(Vector3.UP, 0.05 * (layer % 3)), Vector3(17.6, FLOOR_TOP + layer * 0.1, -5.6)))
	kit.collider(Vector3(1.3, 0.8, 0.9), Transform3D(Basis.IDENTITY, Vector3(17.6, 0.4, -5.6)))
	# Street lamps either side of the gate out, cones by the door.
	for x: float in [-8.6, 8.6]:
		kit.model_grounded("res://assets/models/environment/props/sm_env_prop_street_lamp_refined.glb", Transform3D(Basis.IDENTITY, Vector3(x, FLOOR_TOP, -8.4)))
		kit.collider(Vector3(0.3, 4.8, 0.3), Transform3D(Basis.IDENTITY, Vector3(x, 2.4, -8.4)))
	for spot: Vector3 in [Vector3(-4.6, FLOOR_TOP, -2.2), Vector3(4.7, FLOOR_TOP, -2.6), Vector3(5.2, FLOOR_TOP, -3.3)]:
		kit.model_grounded("res://assets/models/environment/props/sm_env_prop_traffic_cone.glb", Transform3D(Basis.IDENTITY, spot))
	# Painted exit lane out of the forecourt.
	for x: float in [-3.3, 3.3]:
		var mesh := BoxMesh.new()
		mesh.size = Vector3(0.12, 0.006, 8.4)
		kit.add_mesh(mesh, Transform3D(Basis.IDENTITY, Vector3(x, bay_y, -4.8)), yellow, false)
	_floor_text("A LA RUTA", Vector3(0.0, 0.0, -6.2), 0.0, 90, Color(PAPER, 0.85))


func _build_door() -> void:
	door = DepotRollerDoor.new()
	door.name = "RollerDoor"
	door.width = DOOR_WIDTH
	door.height = DOOR_HEIGHT
	door.position = Vector3(0.0, FLOOR_TOP, 0.02)
	add_child(door)


func _build_signs() -> void:
	# Facade: the company's name over the door, readable from the road.
	var facade := _text("TAKE MY PACKAGE", Vector3(0.0, 6.6, -WALL - 0.05), PI, 110, Color("ffc93c"), DISPLAY_FONT, 0.009, 20)
	facade.name = "FacadeTitle"
	_text("DEPÓSITO CENTRAL  ·  ENTREGAS COOPERATIVAS", Vector3(0.0, 5.65, -WALL - 0.05), PI, 44, PAPER, DISPLAY_FONT, 0.008, 10)
	_text("PERSONAL", Vector3(9.5, 2.35, -WALL - 0.09), PI, 36, PAPER, DISPLAY_FONT, 0.006, 6)
	# Inside, over the door.
	_text("SALIDA  ·  CUIDÁ LA CARGA", Vector3(0.0, DOOR_HEIGHT + 1.3, 0.12), 0.0, 64, Color("ffc93c"), DISPLAY_FONT, 0.008, 14)
	# Safety posters on the walls.
	_poster(Vector3(-HALF_WIDTH + 0.07, 2.2, 3.4), PI * 0.5, "USÁ EL CHALECO", "Te tienen que ver\nlos autoelevadores", Color("ff9f1c"))
	_poster(Vector3(-HALF_WIDTH + 0.07, 2.2, 31.2), PI * 0.5, "LEVANTÁ CON LAS PIERNAS", "Las cajas pesadas\nse levantan entre dos", Color("4cc9f0"))
	_poster(Vector3(HALF_WIDTH - 0.07, 2.2, 26.3), -PI * 0.5, "FRÁGIL = DESPACIO", "Frená antes del badén,\nno encima", Color("ff5e5b"))
	_poster(Vector3(-8.0, 2.4, DEPTH - 0.07), PI, "UNA CAJA POR CASA", "Leé la pizarra antes\nde cargar el camión", Color("2dd4a3"))
	_build_clock()


func _poster(at: Vector3, yaw: float, title: String, body: String, accent: Color) -> void:
	var kit := DepotKit.new(self, "PosterColliders")
	var basis := Basis(Vector3.UP, yaw)
	kit.box_xf(Vector3(1.1, 1.5, 0.02), Transform3D(basis, at), DepotKit.flat(PAPER, 0.9))
	kit.box_xf(Vector3(1.1, 0.34, 0.025), Transform3D(basis, at + Vector3(0.0, 0.58, 0.0)), DepotKit.flat(accent, 0.8))
	kit.commit("Poster")
	var face: Vector3 = basis * Vector3(0.0, 0.0, 0.03)
	_text(title, at + face + Vector3(0.0, 0.58, 0.0), yaw, 34, PAPER, DISPLAY_FONT, 0.0045, 6).width = 230
	var text := _text(body, at + face + Vector3(0.0, -0.05, 0.0), yaw, 30, INK, BODY_FONT, 0.004, 0)
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.width = 250


func _build_clock() -> void:
	var clock := Node3D.new()
	clock.name = "WallClock"
	clock.position = Vector3(3.0, 4.8, DEPTH - 0.08)
	clock.rotation.y = PI
	add_child(clock)
	var face := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = 0.55
	disc.bottom_radius = 0.55
	disc.height = 0.06
	disc.radial_segments = 32
	face.mesh = disc
	face.rotation.x = PI * 0.5
	face.material_override = DepotKit.flat(PAPER, 0.6)
	clock.add_child(face)
	var rim := MeshInstance3D.new()
	var rim_mesh := CylinderMesh.new()
	rim_mesh.top_radius = 0.6
	rim_mesh.bottom_radius = 0.6
	rim_mesh.height = 0.04
	rim_mesh.radial_segments = 32
	rim.mesh = rim_mesh
	rim.rotation.x = PI * 0.5
	rim.position.z = -0.02
	rim.material_override = DepotKit.flat(INK, 0.5)
	clock.add_child(rim)
	for hour: int in range(12):
		var tick := MeshInstance3D.new()
		var tick_mesh := BoxMesh.new()
		tick_mesh.size = Vector3(0.03, 0.1 if hour % 3 == 0 else 0.06, 0.01)
		tick.mesh = tick_mesh
		tick.material_override = DepotKit.flat(INK, 0.6)
		var angle: float = TAU * hour / 12.0
		tick.position = Vector3(sin(angle) * 0.46, cos(angle) * 0.46, 0.04)
		tick.rotation.z = -angle
		clock.add_child(tick)
	_clock_hour = _clock_hand(clock, 0.28, 0.05)
	_clock_minute = _clock_hand(clock, 0.42, 0.03)


func _clock_hand(clock: Node3D, length: float, thickness: float) -> Node3D:
	var pivot := Node3D.new()
	pivot.position.z = 0.05
	clock.add_child(pivot)
	var hand := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(thickness, length, 0.01)
	hand.mesh = mesh
	hand.position.y = length * 0.4
	hand.material_override = DepotKit.flat(INK, 0.5)
	pivot.add_child(hand)
	return pivot


const BOARD_TITLE: String = "PEDIDOS DE HOY"
const BOARD_RULE: String = "Una caja por casa  ·  cargá sólo lo que pide cada una"


## The order board: a whiteboard on a stand beside the truck, angled toward
## where the crew appears. Rows are filled in by post_orders().
func _build_board() -> void:
	var board := Node3D.new()
	board.name = "OrderBoard"
	board.position = Vector3(-4.5, FLOOR_TOP, 13.0)
	board.rotation.y = deg_to_rad(38.0)
	add_child(board)
	var kit := DepotKit.new(board, "BoardColliders")
	var frame := DepotKit.flat(Color("59656a"), 0.4, 0.6)
	kit.box(Vector3(3.3, 1.95, 0.05), Vector3(0.0, 1.85, 0.0), DepotKit.flat(Color("f4f6f2"), 0.25))
	kit.box(Vector3(3.42, 0.06, 0.08), Vector3(0.0, 2.85, 0.0), frame)
	kit.box(Vector3(3.42, 0.06, 0.08), Vector3(0.0, 0.85, 0.0), frame)
	kit.box(Vector3(3.3, 0.05, 0.12), Vector3(0.0, 0.84, 0.07), frame)  # marker tray
	for x: float in [-1.74, 1.74]:
		kit.box(Vector3(0.06, 2.05, 0.08), Vector3(x, 1.85, 0.0), frame)
		kit.box(Vector3(0.06, 0.85, 0.06), Vector3(x, 0.42, 0.0), frame)
		kit.box(Vector3(0.08, 0.04, 0.7), Vector3(x, 0.03, 0.0), frame)
	for index: int in range(3):
		kit.box(Vector3(0.12, 0.02, 0.02), Vector3(-1.2 + index * 0.2, 0.88, 0.09), DepotKit.flat([Color("2a4d9b"), Color("c0392b"), Color("1f8a5b")][index], 0.5))
	kit.collider(Vector3(3.5, 2.1, 0.2), Transform3D(Basis.IDENTITY, Vector3(0.0, 1.85, 0.0)))
	kit.commit("Board")
	_board_title = _text(BOARD_TITLE, Vector3(0.0, 2.6, 0.035), 0.0, 64, Color("2a4d9b"), DISPLAY_FONT, 0.0052, 0, board)
	_board_title.name = "Title"
	var date: Dictionary = Time.get_date_dict_from_system()
	_text("%02d/%02d" % [int(date.day), int(date.month)], Vector3(1.42, 2.72, 0.035), 0.0, 30, Color("c0392b"), DISPLAY_FONT, 0.0045, 0, board)
	_board_rule = _text(BOARD_RULE, Vector3(0.0, 2.4, 0.035), 0.0, 26, Color("c0392b"), BODY_FONT, 0.0045, 0, board)
	_board_rule.name = "Rule"
	for row: int in range(4):
		var y: float = 2.1 - row * 0.36
		# Left-aligned from the board's left margin, whatever its length.
		var line := _text("", Vector3(-1.42, y, 0.035), 0.0, 32, Color("2a4d9b"), BODY_FONT, 0.0045, 0, board)
		line.name = "Row%d" % row
		line.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		_board_rows.append(line)
		var mark := _text("", Vector3(1.38, y, 0.035), 0.0, 40, Color("857a6e"), DISPLAY_FONT, 0.005, 0, board)
		mark.name = "Mark%d" % row
		_board_marks.append(mark)


func _write_board() -> void:
	for row: int in range(_board_rows.size()):
		var line: Label3D = _board_rows[row]
		var mark: Label3D = _board_marks[row]
		if row < orders.size():
			var order: Dictionary = orders[row]
			line.text = "CASA %d  ·  ESTANTE %s
%s · %s" % [int(order.house) + 1, order.code, order.trap, String(order.content).to_lower()]
			mark.text = ""
		else:
			line.text = ""
			mark.text = ""
	_board_title.text = BOARD_TITLE
	_board_rule.text = BOARD_RULE
	if orders.is_empty():
		# Endless (tareas de Nacho N-101): no houses, so no orders. The depot
		# stays the lobby it is, and the board sets the goal and the bar.
		_board_title.text = "RUTA SIN FIN"
		_board_rule.text = "Llevá todo lo que puedas lo más lejos posible"
		_board_rows[0].text = "Cargá las cajas que quieras y salí:
el portón está abierto."
		var manager: Node = _autoload(&"RunManager")
		var best: int = int(manager.call(&"best_score", RUN_MANAGER.MODE_ENDLESS)) if manager != null else 0
		_board_rows[1].text = ("RÉCORD  ·  %d m" % best) if best > 0 else "RÉCORD  ·  todavía ninguno"


## The team's corkboard: deliveries, best score and the next unlock.
func _build_team_board() -> void:
	var at := Vector3(HALF_WIDTH - 0.06, 2.55, 22.5)
	var kit := DepotKit.new(self, "TeamBoardColliders")
	kit.box(Vector3(0.04, 1.4, 2.0), at, DepotKit.flat(Color("c9a26b"), 0.9))
	kit.box(Vector3(0.05, 1.5, 2.1), at + Vector3(0.01, 0.0, 0.0), DepotKit.flat(Color("59656a"), 0.5, 0.4))
	kit.box(Vector3(0.01, 0.3, 0.3), at + Vector3(-0.03, 0.4, 0.75), DepotKit.flat(Color("ffc93c"), 0.8), false, 0.1)
	kit.commit("TeamBoard")
	_text("EQUIPO DEL MES", at + Vector3(-0.04, 0.5, 0.0), -PI * 0.5, 36, INK, DISPLAY_FONT, 0.005, 0)
	_stats_label = _text("", at + Vector3(-0.04, -0.12, -0.05), -PI * 0.5, 28, INK, BODY_FONT, 0.0042, 0)
	_stats_label.name = "TeamStats"
	_stats_label.width = 420
	_stats_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	refresh_team_board()
	var unlocks: Node = _autoload(&"UnlockManager")
	if unlocks != null:
		unlocks.connect(&"progress_changed", refresh_team_board)


func refresh_team_board() -> void:
	if _stats_label == null:
		return
	var unlocks: Node = _autoload(&"UnlockManager")
	var manager: Node = _autoload(&"RunManager")
	if unlocks == null:
		return
	var summary: Dictionary = unlocks.call(&"progress_summary")
	var best: int = int(manager.call(&"best_score")) if manager != null else 0
	var next: String = "¡todo desbloqueado!"
	for unlock_id: StringName in unlocks.get(&"UNLOCKS"):
		if not bool(unlocks.call(&"is_unlocked", unlock_id)):
			var rule: Dictionary = unlocks.get(&"UNLOCKS")[unlock_id]
			next = "%s (%d entregas)" % [rule.title, int(rule.deliveries)]
			break
	_stats_label.text = "Entregas exitosas: %d\nPuntos acumulados: %d\nMejor reparto: %d pts\nPróximo: %s" % [int(summary.deliveries), int(summary.score), best, next]


func _build_stations() -> void:
	_station(&"orders", "Leer pedidos", Vector3(-4.5, 1.6, 13.0) + Basis(Vector3.UP, deg_to_rad(38.0)) * Vector3(0.0, 0.0, 0.35))
	_station(&"garage", "Personalizar el camión", Vector3(4.6, 1.3, 10.1))
	_station(&"wardrobe", "Cambiarte el uniforme", Vector3(14.0, 1.2, 15.5))
	_station(&"shop", "Comprar suministros", Vector3(10.8, 1.25, 23.4))
	_station(&"records", "Ver el progreso del equipo", Vector3(HALF_WIDTH - 0.5, 2.0, 22.5))


func _station(id: StringName, prompt_text: String, at: Vector3) -> void:
	var station := DepotStation.new()
	station.name = "Station_%s" % id
	station.station_id = id
	station.prompt = prompt_text
	station.position = at
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.6
	shape.shape = sphere
	station.add_child(shape)
	add_child(station)


## Hanging sign: a board on two cables with its caption on both faces. An
## arrow in the caption ("← ESTANTES", "CAMIÓN → PORTÓN") is drawn as a
## shape, not a glyph, and only on the front face (the one `yaw` turns toward
## +Z): read from behind it would point the wrong way, so the back just names
## the place. A sign hung under another stops its cables at `cable_top`.
## Every caption label is in the "depot_sign" group, tagged with the whole
## caption and its face (test_depot_signage).
func _hanging_sign(kit: DepotKit, caption: String, at: Vector3, yaw: float, colour: Color, cable_top: float = CEILING - 0.25, ink: Color = PAPER) -> void:
	var basis := Basis(Vector3.UP, yaw)
	var tokens: Array = _sign_tokens(caption)
	var words: PackedStringArray = []
	var widths: Array[float] = []
	var content: float = SIGN_GAP * (tokens.size() - 1)
	for token: Variant in tokens:
		var token_width: float = SIGN_ARROW
		if token is String:
			words.append(token)
			token_width = DISPLAY_FONT.get_string_size(token, HORIZONTAL_ALIGNMENT_LEFT, -1, SIGN_FONT_SIZE).x * SIGN_PIXEL
		widths.append(token_width)
		content += token_width
	var width: float = content + 0.7
	kit.box_xf(Vector3(width, 0.6, 0.06), Transform3D(basis, at), DepotKit.flat(colour, 0.7))
	kit.box_xf(Vector3(width + 0.08, 0.06, 0.08), Transform3D(basis, at + Vector3(0.0, 0.33, 0.0)), DepotKit.flat(Color("e8ebe4"), 0.6))
	for side: float in [-0.4, 0.4]:
		var cable_at: Vector3 = at + basis * Vector3(side * width, 0.0, 0.0)
		kit.box_xf(Vector3(0.015, cable_top - at.y - 0.3, 0.015), Transform3D(Basis.IDENTITY, Vector3(cable_at.x, (cable_top + at.y + 0.3) * 0.5, cable_at.z)), DepotKit.flat(Color("263238"), 0.6))
	var cursor: float = -content * 0.5
	for index: int in range(tokens.size()):
		var centre: float = cursor + widths[index] * 0.5
		if tokens[index] is String:
			_sign_label(tokens[index], at + basis * Vector3(centre, 0.0, 0.035), yaw, ink, caption, true)
		else:
			var turn := Basis(Vector3.BACK, PI if int(tokens[index]) < 0 else 0.0)
			_arrow_shape(kit, Transform3D(basis * turn, at + basis * Vector3(centre, 0.0, 0.036)), SIGN_ARROW, 0.34, 0.012, DepotKit.unlit(ink))
		cursor += widths[index] + SIGN_GAP
	_sign_label("  ·  ".join(words), at + basis * Vector3(0.0, 0.0, -0.035), yaw + PI, ink, caption, false)


func _sign_label(value: String, at: Vector3, yaw: float, ink: Color, caption: String, front: bool) -> void:
	var label := _text(value, at, yaw, SIGN_FONT_SIZE, ink, DISPLAY_FONT, SIGN_PIXEL, 10)
	label.add_to_group(&"depot_sign")
	label.set_meta(&"sign", caption)
	label.set_meta(&"front", front)


## "CAMIÓN → PORTÓN" -> ["CAMIÓN", 1, "PORTÓN"]: words, and -1 / 1 for
## arrows pointing left / right.
static func _sign_tokens(caption: String) -> Array:
	var tokens: Array = []
	var word: String = ""
	for character: String in caption:
		if character != "←" and character != "→":
			word += character
			continue
		if not word.strip_edges().is_empty():
			tokens.append(word.strip_edges())
		tokens.append(-1 if character == "←" else 1)
		word = ""
	if not word.strip_edges().is_empty():
		tokens.append(word.strip_edges())
	return tokens


func _build_lights() -> void:
	var kit := DepotKit.new(self, "LightColliders")
	var housing := DepotKit.flat(Color("3b4c53"), 0.5, 0.4)
	var lamp := DepotKit.glow(Color("fff1d6"), 2.2)
	var fixtures: Array[Vector3] = []
	for x: float in [-9.0, -3.0, 3.0, 9.0]:
		for z: float in [5.2, 13.0, 20.8, 28.0]:
			fixtures.append(Vector3(x, 5.9, z))
	for at: Vector3 in fixtures:
		kit.box(Vector3(0.015, 0.65, 0.015), at + Vector3(0.0, 0.33, 0.0), housing)
		var shade := CylinderMesh.new()
		shade.top_radius = 0.12
		shade.bottom_radius = 0.42
		shade.height = 0.32
		shade.radial_segments = 14
		kit.add_mesh(shade, Transform3D(Basis.IDENTITY, at), housing)
		var bulb := CylinderMesh.new()
		bulb.top_radius = 0.36
		bulb.bottom_radius = 0.36
		bulb.height = 0.02
		bulb.radial_segments = 14
		kit.add_mesh(bulb, Transform3D(Basis.IDENTITY, at - Vector3(0.0, 0.16, 0.0)), lamp, false)
	# Fluorescent tubes over the dispatch shelves; one of them is on its way out.
	for unit: Dictionary in SHELF_UNITS:
		for index: int in range(2):
			var z: float = SHELF_START_Z + 2.0 + index * 4.0
			kit.box(Vector3(0.2, 0.06, 1.3), Vector3(float(unit.x), 4.3, z), housing)
			if unit.aisle == "B" and index == 1:
				_flicker_tube = MeshInstance3D.new()
				_flicker_tube.name = "FlickeringTube"
				var tube := BoxMesh.new()
				tube.size = Vector3(0.1, 0.04, 1.2)
				_flicker_tube.mesh = tube
				_flicker_tube.material_override = DepotKit.glow(Color("eaf6ff"), 2.0)
				_flicker_tube.position = Vector3(float(unit.x), 4.26, z)
				_flicker_tube.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				add_child(_flicker_tube)
			else:
				var tube_mesh := BoxMesh.new()
				tube_mesh.size = Vector3(0.1, 0.04, 1.2)
				kit.add_mesh(tube_mesh, Transform3D(Basis.IDENTITY, Vector3(float(unit.x), 4.26, z)), DepotKit.glow(Color("eaf6ff"), 2.0), false)
			for cable: float in [-0.5, 0.5]:
				kit.box(Vector3(0.01, 2.2, 0.01), Vector3(float(unit.x), 5.4, z + cable), housing)
	kit.commit("Lamps")
	# Few real lights (the GL Compatibility renderer caps lights per mesh):
	# four warm high-bay pools; the fixtures above do the rest of the look.
	for at: Vector3 in [Vector3(-6.0, 5.4, 9.0), Vector3(6.0, 5.4, 9.0), Vector3(-6.0, 5.4, 23.0), Vector3(6.0, 5.4, 23.0)]:
		var light := OmniLight3D.new()
		light.name = "HighBay"
		light.position = at
		light.light_color = Color("fff3df")
		light.light_energy = 1.2
		light.omni_range = 15.0
		light.omni_attenuation = 0.9
		light.shadow_enabled = false
		add_child(light)
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
	add_child(dust)


func _build_moving_parts() -> void:
	# Two big ceiling fans turning slowly.
	for at: Vector3 in [Vector3(-3.0, 6.3, 20.8), Vector3(6.5, 6.3, 16.0)]:
		var fan := Node3D.new()
		fan.name = "CeilingFan"
		fan.position = at
		add_child(fan)
		var kit := DepotKit.new(fan, "FanColliders")
		var dark := DepotKit.flat(Color("263238"), 0.5, 0.4)
		kit.cylinder(0.2, 0.3, Transform3D.IDENTITY, dark, 12)
		for blade: int in range(5):
			var basis := Basis(Vector3.UP, TAU * blade / 5.0)
			kit.box_xf(Vector3(0.28, 0.03, 2.2), Transform3D(basis * Basis(Vector3.BACK, 0.12), basis * Vector3(0.0, -0.1, 1.2)), DepotKit.flat(Color("c9ced0"), 0.4, 0.5))
		kit.commit("Fan")
		var rod := MeshInstance3D.new()
		var rod_mesh := CylinderMesh.new()
		rod_mesh.top_radius = 0.03
		rod_mesh.bottom_radius = 0.03
		rod_mesh.height = CEILING - at.y
		rod.mesh = rod_mesh
		rod.material_override = DepotKit.flat(Color("263238"), 0.5, 0.4)
		rod.position = at + Vector3(0.0, (CEILING - at.y) * 0.5, 0.0)
		add_child(rod)
		_fans.append(fan)


func _build_life() -> void:
	var clerk := _worker(Vector3(10.4, FLOOR_TOP, 24.9), 0.0, Color("2dd4a3"), [
		"¡Hola! ¿Qué llevás hoy?", "El acolchado salva jarrones.", "Con seguro, dormís tranquilo."])
	clerk.name = "Clerk"
	var dispatcher := _worker(Vector3(11.4, FLOOR_TOP, 29.95), PI, Color("4cc9f0"), [
		"Revisá la pizarra antes de salir.", "Casa por casa, sin mezclar."])
	dispatcher.name = "Dispatcher"
	var packer := _worker(Vector3(2.2, FLOOR_TOP, 28.2), 0.0, Color("ff9f1c"), [
		"Esta cinta no pega nada...", "¡Cuidado con la gallina!", "Etiqueta arriba, siempre."])
	packer.name = "Packer"
	var mechanic := _worker(Vector3(13.5, FLOOR_TOP, 5.2), -PI * 0.5, Color("c0392b"), [
		"¿Le cambiamos la pintura?", "Frenos revisados, ¡a la ruta!"])
	mechanic.name = "Mechanic"
	var walker := _worker(Vector3(-8.5, FLOOR_TOP, 25.2), 0.0, Color("ffc93c"), [
		"¡Permiso!", "Inventario, inventario...", "¿Viste mi lapicera?"])
	walker.name = "StockWalker"
	walker.waypoints = [Vector3(-8.5, FLOOR_TOP, 14.4), Vector3(-8.5, FLOOR_TOP, 25.2), Vector3(-2.6, FLOOR_TOP, 25.0),
		Vector3(0.6, FLOOR_TOP, 29.0), Vector3(-2.6, FLOOR_TOP, 25.0), Vector3(-8.5, FLOOR_TOP, 25.2)]
	var forklift := DepotForklift.new()
	forklift.name = "Forklift"
	forklift.place(Vector3(-12.05, FLOOR_TOP, 3.2), Vector3(-12.05, FLOOR_TOP, 26.2))
	add_child(forklift)


func _worker(at: Vector3, yaw: float, uniform: Color, lines: Array) -> DepotWorker:
	var worker := DepotWorker.new()
	worker.uniform = uniform
	worker.position = at
	worker.rotation.y = yaw
	worker.lines = PackedStringArray(lines)
	add_child(worker)
	return worker


func _build_audio() -> void:
	var hum := AudioStreamPlayer3D.new()
	hum.name = "RoomTone"
	hum.stream = SynthAudio.warehouse_hum()
	hum.bus = &"SFX"
	hum.volume_db = WorldMix.WAREHOUSE_HUM_DB
	hum.unit_size = 30.0
	hum.max_distance = 60.0
	hum.position = Vector3(0.0, 4.0, 16.0)
	hum.autoplay = true
	add_child(hum)
	var radio := AudioStreamPlayer3D.new()
	radio.name = "Radio"
	radio.stream = SynthAudio.radio_tune()
	radio.bus = &"Music"
	radio.volume_db = WorldMix.DEPOT_RADIO_DB
	radio.unit_size = 3.0
	radio.max_distance = 22.0
	radio.position = Vector3(12.8, 1.1, 21.0)
	radio.autoplay = true
	add_child(radio)


func _spawn_extra_stock() -> void:
	var stock := Node3D.new()
	stock.name = "Stock"
	add_child(stock)
	for trap: String in EXTRA_STOCK:
		var definition: Resource = load(TRAP_PATH % trap)
		if definition == null:
			continue
		var package: Node3D = PACKAGE_SCENE.instantiate()
		package.name = "Package_%s_02" % trap
		package.set(&"package_id", StringName("%s_02" % trap))
		package.set(&"trap_definition", definition)
		# Parked out of the way until stock_shelves() puts it in its bin.
		package.position = Vector3(0.0, 0.5, DEPTH - 1.0)
		stock.add_child(package)
		package.set(&"freeze", true)


# --- Helpers ----------------------------------------------------------------


func _text(value: String, at: Vector3, yaw: float, font_size: int, colour: Color, font: Font, pixel: float, outline: int, parent: Node = null) -> Label3D:
	var label := Label3D.new()
	label.text = value
	label.font = font
	label.font_size = font_size
	label.pixel_size = pixel
	label.modulate = colour
	label.outline_size = outline
	label.outline_modulate = INK
	label.position = at
	label.rotation.y = yaw
	label.double_sided = false
	(parent if parent != null else self).add_child(label)
	return label


## Paint on the floor, lying flat. yaw 0 reads for someone walking toward -Z
## (toward the door); -PI/2 for someone walking toward +X.
func _floor_text(value: String, at: Vector3, yaw: float, font_size: int, colour: Color) -> void:
	var label := _text(value, Vector3(at.x, FLOOR_TOP + 0.008, at.z), 0.0, font_size, colour, DISPLAY_FONT, 0.012, 0)
	label.basis = Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, -PI * 0.5)
	label.no_depth_test = false
	label.shaded = true


func _shuffle(values: Array) -> void:
	for i: int in range(values.size() - 1, 0, -1):
		var j: int = _rng.randi_range(0, i)
		var swap: Variant = values[i]
		values[i] = values[j]
		values[j] = swap


func _is_online() -> bool:
	var network: Node = _autoload(&"NetworkManager")
	return network != null and bool(network.call(&"is_online"))


## Autoloads by path, not by name: a test that names this class compiles it
## before the autoloads exist (same pattern as route.gd's _session_seed()).
func _autoload(autoload_name: StringName) -> Node:
	return get_node_or_null(NodePath("/root/%s" % autoload_name)) if is_inside_tree() else null
