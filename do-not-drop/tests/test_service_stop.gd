extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_service_stop.gd
## Service stations on the road (tareas de Nacho N-110: service_stop_rules.gd,
## service_stop_segment.gd, service_stop.gd, service_stop_shop.gd,
## service_counter.gd, route.gd, route_streamer.gd, depot_panel.gd):
##   - Pacing rules, over many seeds: only a long route gets one (at most one),
##     never in the first stretch, the calm approach to a house, right after a
##     house or at the goal, never beside a bridge, tunnel, rail crossing or
##     hill; the plan stays continuous and every house after it moves by its
##     length (so a deadline counts the road, and stopping is spent time);
##     the same seed plans the same station.
##   - Endless lays one every so often from the session seed (first after
##     ENDLESS_FIRST_MIN, then ENDLESS_GAP_MIN apart), never right after a
##     hard segment.
##   - A real delivery route builds it: lay-by, counter, signs, the N-311
##     cosmetic spot; the station stands on the ground and the lay-by counts
##     as pulled in (the stuck rule stands down there).
##   - The shop: kit refills cost what is missing (with the road's markup),
##     a full item can't be bought, the purchase spends the team's money and
##     restocks the shared kit; the spare part fixes a broken door at once.
##   - The purchase goes through the same vote as the depot (ShopVoteManager):
##     an offer resolved there is bought by the station's shop, stamped with
##     its venue, and never by the depot (CrewProgression.supplies untouched).
##   - N-923.4 the accessory shelf: the whole catalogue, no draw, at the road's
##     markup (cap $60 -> $84), one offer per player as buyer; solo a press buys
##     it for that player and charges the team once; an accessory somebody has is
##     blocked and a second purchase charges nothing; no money buys nothing; the
##     vote buys it for its buyer and a Discount card halves the surcharged price.
##   - The panel's "service" face lists the station's offers; the HUD opens it
##     from the counter and closes it when Endless culls the station.
##   - Online (follow-up to the network audit): a second player at the counter
##     keeps the votes cast; after a purchase the vote opens again only while
##     the crew is at the station, and the host closes it once the truck has
##     left; a Priority card on a station offer charges it once.

const Rules = preload("res://scripts/gameplay/route/service_stop_rules.gd")
const Shop = preload("res://scripts/gameplay/route/service_stop_shop.gd")
const SEEDS: int = 300

var _failures: int = 0
var _manager: Node
var _crew: Node
var _network: Node
var _votes: Node


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_manager = root.get_node(^"/root/RunManager")
	_crew = root.get_node(^"/root/CrewProgression")
	_network = root.get_node(^"/root/NetworkManager")
	_votes = root.get_node(^"/root/ShopVoteManager")
	_check_plan_rules()
	await _check_endless()
	await _check_real_route()
	await _check_shop_and_vote()
	_network.set(&"world_seed", 0)
	_network.set(&"world_house_count", 0)
	if _failures == 0:
		print("PASS: long routes and Endless get a service station by the pacing rules,"
				+ " and its kit is bought through the depot's vote")
	quit(_failures)


# --- Pacing rules ------------------------------------------------------------------


func _check_plan_rules() -> void:
	var long_routes: int = 0
	var with_station: int = 0
	for houses: int in range(1, 5):
		for seed_value: int in range(1, SEEDS + 1):
			var plan: Dictionary = RoutePlanner.plan_spine(seed_value, houses)
			var segments: Array = plan.segments
			var stations: Array[int] = []
			var cursor: float = 0.0
			for index: int in range(segments.size()):
				var segment: Dictionary = segments[index]
				if not is_equal_approx(float(segment.start), cursor):
					_expect(false, "Seed %d/%d: segment %d starts where the last ended (%.1f vs %.1f)" % [
						seed_value, houses, index, float(segment.start), cursor])
					break
				cursor += float(segment.length)
				if segment.script == Rules.SEGMENT:
					stations.append(index)
			_expect(is_equal_approx(cursor, float(plan.total)),
					"Seed %d/%d: the total is the road's length" % [seed_value, houses])
			_expect(stations.size() <= 1,
					"Seed %d/%d: at most one station (got %d)" % [seed_value, houses, stations.size()])
			var length: float = Rules.segment_length()
			var without: float = float(plan.total) - length * stations.size()
			var long_route: bool = Rules.is_long_route(houses, without)
			long_routes += int(long_route)
			if not long_route:
				_expect(stations.is_empty(),
						"Seed %d/%d: a short route (%.0f m) has no station" % [seed_value, houses, without])
				continue
			if stations.is_empty():
				continue
			with_station += 1
			var index: int = stations[0]
			var at: float = float(segments[index].start)
			_expect(bool(segments[index].get("service_stop", false)) and bool(segments[index].moment),
					"Seed %d/%d: the station's entry is marked and counts as a moment" % [seed_value, houses])
			_expect(Rules.fits(at, plan.house_distances, float(plan.total)),
					"Seed %d/%d: the station at %.0f m keeps clear of the start, the houses and the goal (%s)" % [
					seed_value, houses, at, plan.house_distances])
			for neighbour: int in [index - 1, index + 1]:
				if neighbour >= 0 and neighbour < segments.size():
					var script: Script = segments[neighbour].script
					_expect(script != NarrowBridgeSegment and script != TunnelSegment
							and script != RailCrossingSegment and script != HillSegment,
							"Seed %d/%d: no bridge, tunnel, rail crossing or hill beside the station (%s)" % [
							seed_value, houses, script.get_global_name()])
			# Every house after the station is that much further: its deadline counts the road.
			var plain: Dictionary = _plan_without_station(plan)
			for house: int in range(plan.house_distances.size()):
				var shift: float = float(plan.house_distances[house]) - float(plain.house_distances[house])
				var expected: float = length if float(plain.house_distances[house]) >= at else 0.0
				_expect(is_equal_approx(shift, expected), "Seed %d/%d: house %d moves %.0f m (got %.0f)" % [
					seed_value, houses, house, expected, shift])
	_expect(long_routes > 0, "Some routes are long enough for a station (%d)" % long_routes)
	_expect(with_station >= long_routes * 0.8, "Most long routes find room for their station (%d of %d)" % [
		with_station, long_routes])
	var again: Dictionary = RoutePlanner.plan_spine(77, 3)
	var first: Dictionary = RoutePlanner.plan_spine(77, 3)
	_expect(_station_start(again) == _station_start(first), "The same seed plans the same station")
	print("SERVICE delivery: %d of %d long routes have a station" % [with_station, long_routes])


## The plan as it was before the station went in (its entry out, later starts back).
func _plan_without_station(plan: Dictionary) -> Dictionary:
	var at: float = _station_start(plan)
	var length: float = Rules.segment_length()
	var stops: Array = (plan.house_distances as Array).map(
			func(stop: float) -> float: return stop - length if stop > at else stop)
	return {"house_distances": stops}


func _station_start(plan: Dictionary) -> float:
	for segment: Dictionary in plan.segments:
		if segment.script == Rules.SEGMENT:
			return float(segment.start)
	return -1.0


# --- Endless -------------------------------------------------------------------------


func _check_endless() -> void:
	_expect(is_equal_approx(Rules.endless_next_at(5, 2, 1000.0), Rules.endless_next_at(5, 2, 1000.0)),
			"Endless spacing comes from the seed alone")
	for seed_value: int in [31337, 777]:
		_network.set(&"world_seed", seed_value)
		var stations: Array[float] = []
		var previous_hard: Array[bool] = []
		var streamer := RouteStreamer.new()
		root.add_child(streamer)
		var last: Array = [null]
		streamer.child_entered_tree.connect(func(node: Node) -> void:
			if not node is RouteSegment:
				return
			if node.get_script() == Rules.SEGMENT:
				stations.append(float(node.get_meta(&"route_distance", 0.0)))
				previous_hard.append(last[0] != null and streamer.hard_segments.has(last[0]))
			last[0] = node.get_script())
		var target := Node3D.new()
		root.add_child(target)
		streamer.start(target)
		var ridden: float = 0.0
		var pulled_in: bool = false
		while ridden < 4000.0:
			ridden += 40.0
			target.global_position = streamer.point_at(ridden)
			streamer.call(&"_fill_ahead")
			streamer.call(&"_cull_behind")
			for child: Node in streamer.get_children():
				if child.get_script() == Rules.SEGMENT and not pulled_in:
					var stop: Node3D = child.get(&"stop")
					var bay: Vector3 = stop.to_global(Vector3(9.0, stop.get(&"ground_y"), 0.0))
					var far_lane: Vector3 = (child as Node3D).to_global(Vector3(-3.0, 0.0, -70.0))
					pulled_in = streamer.in_service_bay(bay) and not streamer.in_service_bay(far_lane)
			await process_frame
		streamer.free()
		target.free()
		_expect(stations.size() >= 2,
				"Seed %d: Endless lays stations every so often (%d in 4 km)" % [seed_value, stations.size()])
		_expect(pulled_in, "Seed %d: the lay-by counts as pulled in, the far lane doesn't" % seed_value)
		for index: int in range(stations.size()):
			var floor_at: float = Rules.ENDLESS_FIRST_MIN if index == 0 else stations[index - 1] + Rules.ENDLESS_GAP_MIN
			_expect(stations[index] >= floor_at, "Seed %d: station %d at %.0f m, not before %.0f" % [
				seed_value, index, stations[index], floor_at])
			_expect(not previous_hard[index],
					"Seed %d: station %d doesn't come right after a hard segment" % [seed_value, index])
	_network.set(&"world_seed", 0)


# --- A real delivery route --------------------------------------------------------


func _check_real_route() -> void:
	var found_seed: int = 0
	for seed_value: int in range(1, SEEDS + 1):
		if _station_start(RoutePlanner.plan_spine(seed_value, 3)) >= 0.0:
			found_seed = seed_value
			break
	_expect(found_seed != 0, "Some 3-house route has a station")
	if found_seed == 0:
		return
	_network.set(&"world_seed", found_seed)
	_network.set(&"world_house_count", 3)
	var route: Node3D = (load("res://scenes/gameplay/route/route.tscn") as PackedScene).instantiate()
	route.set(&"batch_dressing", false)
	root.add_child(route)
	await process_frame
	if not bool(route.get(&"is_built")):
		await route.built
	var stop: Node3D = route.get(&"service_stop")
	_expect(stop != null, "The built route has its station (seed %d)" % found_seed)
	if stop != null:
		var segment: Node3D = stop.get_parent()
		for path: String in ["LayBy", "ServiceSignFarBoard", "ServiceSignNearBoard"]:
			_expect(segment.get_node_or_null(NodePath(path)) != null, "The station's segment has its %s" % path)
		_expect(stop.get_node_or_null(^"Counter") is Interactable, "The station has a counter to use")
		_expect(get_nodes_in_group(&"hidden_cosmetic_spot").size() == 1,
				"The station keeps a spot for N-311's cosmetic")
		var terrain: Node = route.get(&"terrain")
		for part: String in ["Forecourt", "Kiosk"]:
			var node: Node3D = stop.get_node(NodePath(part))
			var ground: float = float(terrain.call(&"height_at", route.to_local(node.global_position)))
			var height: float = route.to_local(node.global_position).y
			_expect(absf(height - ground) < 0.3, "The %s stands on the ground (%.2f vs %.2f)" % [part, height, ground])
		var bay: Vector3 = stop.to_global(Vector3(9.0, 0.0, 0.0))
		bay.y = route.to_global(Vector3(0.0, float(terrain.call(&"height_at", route.to_local(bay))), 0.0)).y + 0.5
		_expect(bool(route.call(&"in_service_bay", bay)), "A truck on the lay-by counts as pulled in")
		_expect(not bool(route.call(&"in_service_bay", segment.to_global(Vector3(-3.0, 0.5, -70.0)))),
				"A truck in the far lane is not in the lay-by")
	route.free()
	_network.set(&"world_seed", 0)
	_network.set(&"world_house_count", 0)
	await process_frame


# --- Shop and vote -----------------------------------------------------------------


func _check_shop_and_vote() -> void:
	var start_money: int = int(_crew.get(&"team_money"))
	var start_kit: Dictionary = (_manager.get(&"care_supplies") as Dictionary).duplicate()
	var start_supplies: Dictionary = (_crew.get(&"supplies") as Dictionary).duplicate()
	var segment: Node3D = (Rules.SEGMENT as Script).new()
	segment.name = "Segment9"
	root.add_child(segment)
	await process_frame
	var shop: Node = (segment.get(&"stop") as Node).get_node(^"Shop")
	_manager.set(&"is_running", true)
	_crew.set(&"team_money", 1000)
	var kit: Dictionary = _manager.get(&"care_supplies")
	var full: Dictionary = _manager.get(&"CARE_SUPPLIES_START")
	for tool: StringName in full:
		kit[tool] = int(full[tool])
	kit[&"tape"] = 0
	var offers: Dictionary = shop.call(&"offers")
	var tape_cost: int = roundi(float(Shop.KIT_UNIT_COST[&"tape"]) * Shop.PRICE_MARKUP * int(full[&"tape"]))
	_expect(int(offers[&"tape"].cost) == tape_cost,
			"A tape refill costs what's missing at road prices ($%d, got $%d)" % [tape_cost, int(offers[&"tape"].cost)])
	_expect(offers[&"tape"].get("venue") == Shop.VENUE and String(offers[&"tape"].get("stop")) == "Segment9",
			"Every offer carries the station's venue and its own stop")
	_expect((shop.call(&"unavailable") as Array).has(&"rag"), "A full kit item can't be bought")
	_expect(not bool(shop.call(&"buy_supply", &"rag")), "Buying a full item does nothing")

	# Solo: a press buys at once.
	_expect(bool(shop.call(&"buy_supply", &"tape")), "Solo, the counter sells the tape refill")
	var tape: int = int(_manager.call(&"care_supply_count", &"tape"))
	_expect(tape == int(full[&"tape"]), "The kit's tape is back to full (%d)" % tape)
	_expect(int(_crew.get(&"team_money")) == 1000 - tape_cost,
			"The team paid $%d (has $%d)" % [tape_cost, int(_crew.get(&"team_money"))])

	# The same vote as the depot: an offer resolved there is bought here, never at the depot.
	kit[&"strap"] = 0
	var money: int = int(_crew.get(&"team_money"))
	var strap_cost: int = int((shop.call(&"offers") as Dictionary)[&"strap"].cost)
	_votes.call(&"open_shop", shop.call(&"offers"))
	_expect(bool(_votes.call(&"vote", 1, &"strap")), "The crew votes on the station's offers")
	_votes.call(&"finish_vote", [1])
	_expect(int(_manager.call(&"care_supply_count", &"strap")) == int(full[&"strap"]),
			"The voted strap refill is stocked")
	_expect(int(_crew.get(&"team_money")) == money - strap_cost, "The vote's winner was paid once ($%d)" % strap_cost)

	# By path, not class name: both scripts name autoloads, which a test's own
	# compile can't see yet.
	var faults: Node = (load("res://scripts/gameplay/vehicle/vehicle_faults.gd") as Script).new()
	root.add_child(faults)
	await process_frame
	(faults.get(&"active") as Dictionary)[&"rear_door"] = true
	money = int(_crew.get(&"team_money"))
	var spare_cost: int = int((shop.call(&"offers") as Dictionary)[Shop.SPARE].cost)
	_votes.call(&"open_shop", shop.call(&"offers"))
	_votes.call(&"vote", 1, Shop.SPARE)
	_votes.call(&"finish_vote", [1])
	_expect(not bool(faults.call(&"is_broken", &"rear_door")),
			"The spare part bought on the road fixes the broken door at once")
	_expect(int(faults.get(&"spares")) == 0,
			"The spare part was used on the spot (%d left)" % int(faults.get(&"spares")))
	_expect(int(_crew.get(&"team_money")) == money - spare_cost, "The spare part cost $%d on the road" % spare_cost)
	_expect(spare_cost > int(_crew.SUPPLIES[&"spare_part"].cost), "The road charges more than the depot")
	_expect(not (_crew.get(&"supplies") as Dictionary).has(&"spare_part") or start_supplies.has(&"spare_part"),
			"The depot didn't buy a spare part for the next run off the station's vote")

	await _check_accessory_shelf(shop)

	# The panel's service face lists the station's offers.
	var panel: Control = (load("res://scripts/ui/depot_panel.gd") as Script).new()
	root.add_child(panel)
	await process_frame
	panel.call(&"open", &"service", shop)
	await process_frame
	var texts: Array[String] = []
	for button: Node in panel.find_children("*", "Button", true, false):
		texts.append((button as Button).text)
	var listed: bool = texts.any(func(text: String) -> bool: return text.contains(tr("UI_SERVICE_TAPE")))
	_expect(listed, "The service face lists the station's tape (%s)" % [texts])
	panel.call(&"close")
	panel.free()

	await _check_online_vote(shop, segment, full)
	faults.free()
	await _check_panel_follows_station(segment)
	_votes.call(&"reset")
	_manager.set(&"is_running", false)
	_manager.set(&"care_supplies", start_kit)
	_crew.set(&"team_money", start_money)
	_crew.set(&"supplies", start_supplies)


## N-923.4: the accessory shelf at the counter, bought on a test campaign file.
func _check_accessory_shelf(shop: Node) -> void:
	var old_path: String = String(_crew.get(&"campaign_path"))
	var test_path: String = "user://service_shelf_%d.json" % Time.get_ticks_usec()
	_crew.set(&"campaign_path", test_path)
	var accessories: AccessoryInventory = _crew.get(&"accessories")
	accessories.clear()
	_crew.set(&"team_money", 1000)
	var offers: Dictionary = shop.call(&"offers")
	var cap_id: StringName = AccessoryOffers.offer_id(1, &"cap")
	for id: StringName in AccessoryCatalog.ids():
		_expect(offers.has(AccessoryOffers.offer_id(1, id)), "The station sells the whole catalogue (%s)" % id)
	_expect(int(offers[cap_id].cost) == 84 and int(offers[AccessoryOffers.offer_id(1, &"hard_hat")].cost) == 168,
			"The road charges the 40%% surcharge over the depot's price (cap $84, got $%d)" % int(offers[cap_id].cost))
	_expect(offers[cap_id].get("venue") == Shop.VENUE and String(offers[cap_id].get("stop")) == "Segment9",
			"An accessory offer carries the station's venue and its own stop")
	_expect(not (shop.call(&"unavailable") as Array).has(cap_id), "A free accessory can be bought")

	var money: int = int(_crew.get(&"team_money"))
	_expect(bool(shop.call(&"buy_supply", cap_id)), "Solo, a press buys the cap")
	_expect(accessories.owns("mint", &"cap"), "The cap is the player's (mint, the host)")
	_expect(int(_crew.get(&"team_money")) == money - 84, "The team paid $84 once (had $%d)" % money)
	_expect((shop.call(&"unavailable") as Array).has(cap_id), "An accessory somebody has is blocked")
	money = int(_crew.get(&"team_money"))
	_expect(not bool(shop.call(&"buy_supply", cap_id)) and int(_crew.get(&"team_money")) == money,
			"A second purchase of the same accessory charges nothing")

	_crew.set(&"team_money", 50)
	var backpack_id: StringName = AccessoryOffers.offer_id(1, &"thermal_backpack")
	_expect(not bool(shop.call(&"buy_supply", backpack_id)) and not accessories.owns("mint", &"thermal_backpack")
			and int(_crew.get(&"team_money")) == 50, "Without the money nothing is bought or spent")

	# The vote buys it for the offer's buyer; a Discount card halves the road's price.
	_crew.set(&"team_money", 1000)
	var vest_id: StringName = AccessoryOffers.offer_id(1, &"hi_vis_vest")
	_votes.call(&"open_shop", shop.call(&"offers"))
	_votes.call(&"vote", 1, vest_id)
	_votes.call(&"finish_vote", [1])
	_expect(accessories.owns("mint", &"hi_vis_vest") and int(_crew.get(&"team_money")) == 1000 - 126,
			"The vote bought the vest at $126 (has $%d)" % int(_crew.get(&"team_money")))
	(_crew.get(&"cards") as Dictionary)[1] = int((_crew.get(&"Card") as Dictionary)["DISCOUNT"])
	_votes.call(&"open_shop", shop.call(&"offers"))
	_votes.call(&"use_discount", 1, AccessoryOffers.offer_id(1, &"hard_hat"))
	_expect(accessories.owns("mint", &"hard_hat") and int(_crew.get(&"team_money")) == 1000 - 126 - 84
			and not bool(_crew.call(&"has_card", 1, int((_crew.get(&"Card") as Dictionary)["DISCOUNT"]))),
			"A Discount card pays half the road's $168 and is used up (has $%d)" % int(_crew.get(&"team_money")))
	_votes.call(&"reset")
	accessories.clear()
	_crew.set(&"campaign_path", old_path)
	for path: String in [test_path, test_path + ".tmp", test_path + ".bak"]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	_crew.set(&"team_money", 1000)


## Online, as the host (an ENet server with nobody else): a second use of the
## counter keeps the votes already cast; the vote opens again after a purchase
## only while the crew is at the station and closes once the truck leaves; a
## Priority card on a station offer charges it once.
func _check_online_vote(shop: Node, segment: Node3D, full: Dictionary) -> void:
	var enet := ENetMultiplayerPeer.new()
	_expect(enet.create_server(24610, 2) == OK, "The test can host an ENet session")
	root.multiplayer.multiplayer_peer = enet
	var kit: Dictionary = _manager.get(&"care_supplies")
	kit[&"tape"] = 0
	kit[&"rag"] = 0
	shop.call(&"open_for_crew", 1)
	_expect(bool(shop.call(&"vote_is_mine")), "Using the counter opens the crew's vote on the station")
	_votes.call(&"vote", 1, &"tape")
	shop.call(&"open_for_crew", 2)
	_expect(StringName((_votes.get(&"votes") as Dictionary).get(1, &"")) == &"tape",
			"A second player at the counter keeps the votes already cast (%s)" % [_votes.get(&"votes")])

	var truck := Node3D.new()
	truck.add_to_group(&"vehicle")
	root.add_child(truck)
	var stop: Node3D = segment.get(&"stop")
	truck.global_position = stop.to_global(Vector3(9.0, float(stop.get(&"ground_y")) + 0.5, 0.0))
	_votes.call(&"finish_vote", [1])
	await process_frame
	_expect(bool(shop.call(&"vote_is_mine")), "With the truck in the lay-by the vote opens again after a purchase")
	truck.global_position = stop.to_global(Vector3(0.0, 0.0, -400.0))
	await create_timer(0.8).timeout
	_expect(not bool(_votes.get(&"active")), "The vote closes once the truck has left the station")
	shop.call(&"_reopen_vote")
	_expect(not bool(_votes.get(&"active")), "Away from the station the vote doesn't open again")

	# Priority on a station offer: the station charges it, once.
	truck.global_position = stop.to_global(Vector3(9.0, float(stop.get(&"ground_y")) + 0.5, 0.0))
	shop.call(&"open_for_crew", 1)
	(_crew.get(&"cards") as Dictionary)[1] = int((_crew.get(&"Card") as Dictionary)["PRIORITY"])
	var money: int = int(_crew.get(&"team_money"))
	var rag_cost: int = int((shop.call(&"offers") as Dictionary)[&"rag"].cost)
	_votes.call(&"use_priority", 1, &"rag")
	_expect(int(_crew.get(&"team_money")) == money - rag_cost,
			"A Priority card on a station offer charges it once ($%d, paid $%d)" % [
			rag_cost, money - int(_crew.get(&"team_money"))])
	_expect(int(_manager.call(&"care_supply_count", &"rag")) == int(full[&"rag"]), "The rags were stocked")
	await process_frame
	_votes.call(&"reset")
	truck.free()
	root.multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	enet.close()


## The HUD opens the service face from the counter, and Endless culling the
## station closes it.
func _check_panel_follows_station(segment: Node3D) -> void:
	# Reloaded: this test's own compile met hud.gd before the autoloads existed
	# and left a broken copy in the cache: compile it again now.
	var hud_script: GDScript = load("res://scripts/ui/hud/hud.gd")
	if not hud_script.can_instantiate():
		hud_script.reload()
	var hud: CanvasLayer = hud_script.new()
	root.add_child(hud)
	await process_frame
	hud.set(&"overlay_mode", "run")
	var shop: Node = (segment.get(&"stop") as Node).get_node(^"Shop")
	root.get_node(^"/root/EventBus").emit_signal(&"service_counter_opened", shop)
	var panel: Control = hud.get(&"depot_panel")
	_expect(panel.visible, "The counter opens the service face")
	segment.queue_free()
	await process_frame
	await process_frame
	_expect(not panel.visible, "The station going closes its screen")
	hud.free()
	await process_frame


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1
