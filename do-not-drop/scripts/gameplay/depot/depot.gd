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
## - this script: stock and orders, the door, supplies, the team board
##   (gameplay), and putting the building together;
## - DepotLayout: the floor plan, palette and asset list (constants only);
## - DepotHall / DepotFurnishing / DepotDressing: build the building, what
##   stands in it, and what makes it feel lived in; DepotAmbience animates the
##   moving parts; DepotOrderBoard: the board and its marks;
## - DepotKit: batching static geometry; DepotLabels: text and signage;
## - DepotRollerDoor, DepotStation, DepotWorker/DepotForklift, DepotMirror.
## Orders are drawn from the session seed, so every peer posts the same board
## without a message; the door and purchases are decided by the host.

const Layout = preload("res://scripts/gameplay/depot/depot_layout.gd")
const ORDER_BALANCER = preload("res://scripts/gameplay/traps/order_balancer.gd")
const CAMPAIGN_BOARD: Script = preload("res://scripts/gameplay/depot/depot_campaign_board.gd")
const RUN_MANAGER := preload("res://scripts/core/run_manager.gd")

signal door_closed

const PACKAGE_SCENE: PackedScene = preload("res://scenes/gameplay/package/package.tscn")
const TRAP_PATH: String = "res://data/traps/%s.tres"
## The level scene declares one package of every trap type; the depot stocks
## a second of each, so the shelves hold every kind twice over and picking
## the right one actually means reading the board.
## Playing alone, the only player drives: nobody tends a box on the road, so
## the orders come only from traps that careful driving protects (N-119).
const SOLO_TRAPS: Array[StringName] = [&"fragile", &"balance"]
const EXTRA_STOCK: Array[String] =["fragile", "growing_weight", "balance", "noisy", "liquid", "explosive", "hostile"]

## The depot's public measurements (levels, route and tests read these).
const HALF_WIDTH: float = Layout.HALF_WIDTH
const DEPTH: float = Layout.DEPTH
const TRUCK_BAY: Vector3 = Layout.TRUCK_BAY
const TRUCK_CLEAR_Z: float = Layout.TRUCK_CLEAR_Z
## Supplies (CrewProgression.SUPPLIES) and what they do once a run leaves.
const PADDING_ABSORPTION: float = 0.75
const INSURANCE_REFUND: int = 30

## Builds the stock of extra packages; tests of other systems can turn it off.
@export var stock_extra_packages: bool = true
## A plain ground apron around the building, for levels with no terrain of
## their own behind the start line (modo endless).
@export var ground_apron: bool = false

## Today's orders, one per house: {"house", "package_id", "code", "trap", "trap_key", "content"}
## ("trap" and "content" already translated, for this peer's screens).
var orders: Array[Dictionary] = []
## Supplies waiting for the next run, as the host last reported them.
var supplies: Array = []
var team_money: int = 0
var door: DepotRollerDoor
## Shelf slots in board order: {"code": "A-1", "transform": Transform3D}.
var slots: Array[Dictionary] = []
## Arrows painted on the floor: {"caption", "at", "direction"} in depot space.
var guides: Array[Dictionary] = []
var _stocked: Dictionary = {}  # package_id -> DeliveryPackage
var _rng := RandomNumberGenerator.new()
var _vehicle: Node3D = null
var _watching_exit: bool = false
var _insured: bool = false
var _order_board: DepotOrderBoard
var _stats_label: Label3D
var _supply_props: Dictionary = {}  # supply id -> Node3D shown on the counter


func _ready() -> void:
	var network: Node = _autoload(&"NetworkManager")
	var session_seed: int = int(network.get(&"world_seed")) if network != null else 0
	if session_seed != 0:
		_rng.seed = session_seed ^ 0x5eed
	else:
		_rng.randomize()
	add_to_group(&"roofed_area")
	# The hall rings a little (N-402, AcousticSpace): covers() is the same test.
	add_to_group(&"acoustic_space")
	_build()
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
	if network != null:
		network.connect(&"roster_changed", func(_peers: Array) -> void:
			if bool(network.call(&"is_host")):
				_broadcast_supplies())


## The depot's acoustics (N-402): a big roofed hall.
var acoustic_space: StringName = &"roof"


## Whether a world point is under the depot's roof (route_sky.gd keeps the
## rain off whoever is inside; AcousticSpace gives it the hall's echo).
func covers(world_point: Vector3) -> bool:
	var local: Vector3 = to_local(world_point)
	return absf(local.x) < HALF_WIDTH + Layout.WALL and local.z > -Layout.WALL \
			and local.z < DEPTH + Layout.WALL and local.y < Layout.CEILING


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
	sorted.sort_custom(_by_package_id)
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
		var content: Resource = null
		if package.has_method(&"content_definition"):
			content = package.call(&"content_definition")
		var half: Vector3
		if content != null:
			half = (content.get(&"box_size") as Vector3) * 0.5
		else:
			half = package.call(&"get_half_extents")
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
	candidates.sort_custom(_by_package_id)
	candidates = _solo_candidates(candidates, house_count)
	var definitions: Array = candidates.map(func(package: Node) -> Resource: return package.get(&"trap_definition"))
	var trap_ids: Array[StringName] = ORDER_BALANCER.build_order(definitions, house_count, _completed_runs(), _rng)
	for package: Node in ORDER_BALANCER.packages_for_order(candidates, trap_ids):
		var definition: Resource = package.get(&"trap_definition")
		var content: Resource = package.call(&"content_definition")
		orders.append({
			"house": orders.size(),
			"package_id": StringName(package.get(&"package_id")),
			"code": String(package.get_meta(&"dispatch_code", "?")),
			"trap": String(definition.call(&"localized_name")),
			"trap_key": String(definition.call(&"name_key")),
			"content": String(content.call(&"localized_name")) if content != null else "",
		})
	_order_board.write(orders, _endless_best())
	var bus: Node = _autoload(&"EventBus")
	if bus != null:
		bus.emit_signal(&"depot_orders_posted", orders.duplicate(true))
	return orders


func _completed_runs() -> int:
	var network: Node = _autoload(&"NetworkManager")
	if network != null and int(network.get(&"world_seed")) != 0:
		return int(network.get(&"world_completed_runs"))
	var unlocks: Node = _autoload(&"UnlockManager")
	return int(unlocks.get(&"completed_runs")) if unlocks != null else 0


## [[package_id, trap_key, code], ...] in house order, the shape
## route.assign_packages() understands. The host relays it as the run starts,
## so the trap goes as its translation key and each peer names it itself.
func assignments() -> Array:
	var result: Array = []
	for order: Dictionary in orders:
		result.append([order.package_id, order.trap_key, order.code])
	return result


## Where the Nth player to join appears, in world space, facing the truck.
func spawn_position(index: int) -> Vector3:
	return to_global(Layout.SPAWN_POINTS[index % Layout.SPAWN_POINTS.size()])


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
	var hook: Node = vehicle.get_node_or_null(^"RescueHook")
	if taken.has(&"rescue_hook") and hook != null:
		hook.call(&"arm")
	var faults: Node = get_tree().get_first_node_in_group(&"vehicle_faults")
	if taken.has(&"spare_part") and faults != null:
		faults.call(&"stock_spares", 1)
	_broadcast_supplies()
	var missing: PackedStringArray = []
	for order: Dictionary in orders:
		var package: Node = _stocked.get(order.package_id)
		if package == null or not is_instance_valid(package) or not bool(package.call(&"is_aboard")):
			missing.append(tr("WORLD_DEPOT_NOTICE_MISSING_ITEM") % [int(order.house) + 1, order.code])
	if not missing.is_empty():
		_notice(tr("WORLD_DEPOT_NOTICE_MISSING") % ", ".join(missing))


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
		_notice(tr("WORLD_DEPOT_NOTICE_DOOR"))


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
		_notice(tr("WORLD_DEPOT_NOTICE_BOUGHT") % [tr(String(item.title)).to_lower(), int(item.cost)])
	_broadcast_supplies()


## Asks the host for a supply from whichever peer this is.
func buy_supply(supply_id: StringName) -> void:
	if _is_online() and not bool(_autoload(&"NetworkManager").call(&"is_host")):
		request_supply.rpc_id(1, supply_id)
	else:
		request_supply(supply_id)


## Same authoritative purchase path as request_supply(), with the requesting
## peer attached so only that player's Discount card can pay half price.
@rpc("any_peer", "call_local", "reliable")
func request_discounted_supply(supply_id: StringName) -> void:
	var network: Node = _autoload(&"NetworkManager")
	if network != null and bool(network.call(&"is_online")) and not bool(network.call(&"is_host")):
		return
	var manager: Node = _autoload(&"RunManager")
	if manager != null and (bool(manager.get(&"is_running")) or not (manager.get(&"results") as Dictionary).is_empty()):
		return
	var crew: Node = _autoload(&"CrewProgression")
	if crew == null:
		return
	var sender_id: int = multiplayer.get_remote_sender_id()
	var peer_id: int = sender_id if sender_id != 0 else int(network.call(&"local_id")) if network != null else 1
	if bool(crew.call(&"buy_supply_discounted", peer_id, supply_id)):
		var item: Dictionary = crew.get(&"SUPPLIES")[supply_id]
		var discounted_cost: int = maxi(0, roundi(int(item.cost) * 0.5))
		_notice(tr("WORLD_DEPOT_NOTICE_DISCOUNT") % [tr(String(item.title)).to_lower(), discounted_cost])
	_broadcast_supplies()


func buy_supply_discounted(supply_id: StringName) -> void:
	if _is_online() and not bool(_autoload(&"NetworkManager").call(&"is_host")):
		request_discounted_supply.rpc_id(1, supply_id)
	else:
		request_discounted_supply(supply_id)


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
	_order_board.mark(house_index, outcome)
	var network: Node = _autoload(&"NetworkManager")
	var host: bool = network == null or bool(network.call(&"is_host"))
	if host and _insured and outcome == &"delivered_ruined":
		var crew: Node = _autoload(&"CrewProgression")
		if crew != null:
			crew.call(&"add_team_money", INSURANCE_REFUND)
			_notice(tr("WORLD_DEPOT_NOTICE_INSURANCE") % INSURANCE_REFUND)
			_broadcast_supplies()


func _notice(text: String) -> void:
	var bus: Node = _autoload(&"EventBus")
	if bus != null:
		bus.call(&"relay", &"depot_notice", [text])


func _endless_best() -> int:
	var manager: Node = _autoload(&"RunManager")
	return int(manager.call(&"best_score", RUN_MANAGER.MODE_ENDLESS)) if manager != null else 0


# --- Building ----------------------------------------------------------------


## Puts the building together. The order matters twice over: the static
## geometry shares one batch (laid down in the order it always was), and
## several nodes are looked up by name.
func _build() -> void:
	var kit := DepotKit.new(self, "BuildingColliders")
	var hall := DepotHall.new(self, ground_apron)
	var furnishing := DepotFurnishing.new(self)
	hall.build_shell(kit)
	hall.build_floor_markings(kit)
	hall.build_wayfinding(kit)
	furnishing.build(kit)
	hall.build_exterior(kit)
	kit.commit("Depot")
	hall.build_contact_shadows()
	_build_door()
	var dressing := DepotDressing.new(self)
	dressing.build_signs()
	_order_board = DepotOrderBoard.new()
	_order_board.name = "OrderBoard"
	add_child(_order_board)
	_build_team_board()
	# "Días sin accidentes" and the wall of delivery photos (N-603).
	var campaign: Node3D = CAMPAIGN_BOARD.new()
	campaign.name = "CampaignBoard"
	add_child(campaign)
	_build_stations()
	hall.build_lights()
	dressing.build_fans()
	dressing.build_life()
	dressing.build_audio()
	slots = furnishing.slots
	guides = hall.guides
	_supply_props = furnishing.supply_props
	var ambience := DepotAmbience.new()
	ambience.name = "Ambience"
	ambience.fans = dressing.fans
	ambience.clock_hour = dressing.clock_hour
	ambience.clock_minute = dressing.clock_minute
	ambience.belt_material = furnishing.belt_material
	ambience.belt_boxes = furnishing.belt_boxes
	ambience.flicker_tube = hall.flicker_tube
	add_child(ambience)


func _build_door() -> void:
	door = DepotRollerDoor.new()
	door.name = "RollerDoor"
	door.width = Layout.DOOR_WIDTH
	door.height = Layout.DOOR_HEIGHT
	door.position = Vector3(0.0, Layout.FLOOR_TOP, 0.02)
	add_child(door)


## The team's corkboard: deliveries, best score and the next unlock.
func _build_team_board() -> void:
	var at := Vector3(HALF_WIDTH - 0.06, 2.55, 22.5)
	var kit := DepotKit.new(self, "TeamBoardColliders")
	# Frame behind, cork 1 cm in front of it, the note 1 cm in front of that:
	# 5 mm apart they flickered. The note sits in the bottom corner, clear of
	# the title it used to cover.
	kit.box(Vector3(0.03, 1.5, 2.1), at + Vector3(0.02, 0.0, 0.0), DepotKit.flat(Color("59656a"), 0.5, 0.4))
	kit.box(Vector3(0.03, 1.4, 2.0), at, DepotKit.flat(Color("c9a26b"), 0.9))
	kit.box(Vector3(0.01, 0.22, 0.22), at + Vector3(-0.025, -0.52, 0.82), DepotKit.flat(Color("ffc93c"), 0.8),
			false, 0.1)
	kit.commit("TeamBoard")
	var title := DepotLabels.text(self, tr("WORLD_DEPOT_TEAM_TITLE"), at + Vector3(-0.04, 0.5, 0.0), -PI * 0.5, 36,
			Layout.INK, Layout.DISPLAY_FONT, 0.005, 0)
	DepotLabels.fit_label(title, 1.8)
	_stats_label = DepotLabels.text(self, "", at + Vector3(-0.04, -0.12, -0.05), -PI * 0.5, 28, Layout.INK,
			Layout.BODY_FONT, 0.0042, 0)
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
	var next: String = tr("WORLD_DEPOT_TEAM_ALL_UNLOCKED")
	for unlock_id: StringName in unlocks.get(&"UNLOCKS"):
		if not bool(unlocks.call(&"is_unlocked", unlock_id)):
			var rule: Dictionary = unlocks.get(&"UNLOCKS")[unlock_id]
			next = tr("WORLD_DEPOT_TEAM_NEXT") % [rule.title, int(rule.deliveries)]
			break
	_stats_label.text = tr("WORLD_DEPOT_TEAM_STATS") % [int(summary.deliveries), int(summary.score), best, next]


func _build_stations() -> void:
	var at_board: Vector3 = Layout.BOARD_AT + Vector3(0.0, 1.6, 0.0) + Layout.board_basis() * Vector3(0.0, 0.0, 0.35)
	_station(&"orders", tr("WORLD_DEPOT_STATION_ORDERS"), at_board)
	_station(&"garage", tr("WORLD_DEPOT_STATION_GARAGE"), Layout.KIOSK_AT + Vector3(-0.45, 1.3, 0.0))
	_station(&"wardrobe", tr("WORLD_DEPOT_STATION_WARDROBE"), Vector3(14.0, 1.2, 15.5))
	_station(&"shop", tr("WORLD_DEPOT_STATION_SHOP"), Vector3(10.8, 1.25, 23.4))
	_station(&"records", tr("WORLD_DEPOT_STATION_RECORDS"), Vector3(HALF_WIDTH - 0.5, 2.0, 22.5))


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


## Packages in a stable order every peer agrees on.
static func _by_package_id(a: Node, b: Node) -> bool:
	return String(a.get(&"package_id")) < String(b.get(&"package_id"))


func _shuffle(values: Array) -> void:
	for i: int in range(values.size() - 1, 0, -1):
		var j: int = _rng.randi_range(0, i)
		var swap: Variant = values[i]
		values[i] = values[j]
		values[j] = swap


func _is_online() -> bool:
	var network: Node = _autoload(&"NetworkManager")
	return network != null and bool(network.call(&"is_online"))


## Solo: only SOLO_TRAPS boxes, as long as there are enough of them for every
## house; otherwise (a stock that can't cover it) every box, as before.
func _solo_candidates(candidates: Array, house_count: int) -> Array:
	var network: Node = _autoload(&"NetworkManager")
	if network == null or Array(network.get(&"peer_ids")).size() > 1:
		return candidates
	var solo: Array = candidates.filter(func(package: Node) -> bool:
		var definition: Resource = package.get(&"trap_definition")
		return definition != null and StringName(definition.get(&"id")) in SOLO_TRAPS)
	return solo if solo.size() >= house_count else candidates


## Autoloads by path, not by name: a test that names this class compiles it
## before the autoloads exist (same pattern as route.gd's _session_seed()).
func _autoload(autoload_name: StringName) -> Node:
	return get_node_or_null(NodePath("/root/%s" % autoload_name)) if is_inside_tree() else null
