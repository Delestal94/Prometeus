class_name PackageRescue
extends RefCounted
## The cargo rescue on the host (docs/jugabilidad-paquetes-rescate.md): care
## simulation per tick, recovery, repair tools and salvaged parts. Split out of
## package.gd to keep it readable; DeliveryPackage keeps thin wrappers (and the
## RPC) so callers and the network surface are unchanged.
##
## By name on purpose (N-224.4, test_dynamic_dispatch_budget): the truck
## (vehicle.gd has no class name and tests put plain-Node fakes in the "vehicle"
## group: carries, point_velocity, driver_peer_id), RunManager (see
## package_autoloads.gd: typing it makes a compile cycle), world_seed (declared
## by network_manager.gd, not by NetSession), the seat path of the players in
## the "player" group (tests put Node3D fakes there) and the lap mount
## (package_mount_point.gd has no class name).


static func simulate_cargo(p: DeliveryPackage, delta: float) -> void:
	if p.trap_behavior == null:
		return
	var before_integrity: float = p.integrity
	var before_state: int = p.trap_state
	var vehicle: Node3D = p._find_vehicle()  # by name: see the top of the file
	var riding: bool = vehicle != null and bool(vehicle.call(&"carries", p.global_position, 1.0))
	var speed: float = 0.0
	var velocity_now := Vector3.ZERO
	if riding:
		velocity_now = vehicle.call(&"point_velocity", p.global_position)
		speed = velocity_now.length()
		if p._motion_initialized:
			var acceleration: Vector3 = (velocity_now - p._motion_velocity) / maxf(delta, 0.001)
			var local_acceleration: Vector3 = vehicle.global_basis.inverse() * acceleration
			p._motion_acceleration = p._motion_acceleration.lerp(local_acceleration, minf(1.0, delta * 8.0))
		p._motion_velocity = velocity_now
		p._motion_initialized = true
	else:
		p._motion_initialized = false
		p._motion_acceleration = Vector3.ZERO
	var holder: Player = p.carrier as Player if is_instance_valid(p.carrier) else null
	p.care.in_lap = p.is_held and holder != null and not holder.seat_node_path.is_empty()
	var input: Dictionary = p.player_input.duplicate()
	# Solo crews get a modest rack assistant; they still stop to repair.
	var solo_assist: bool = (p.get_tree().get_nodes_in_group(&"player").size() == 1 and not p.is_held
			and p.tender_peer_id == 0)
	if solo_assist:
		input["steady"] = true
		input["calm"] = true
		input["balance"] = p.care.balance_target
	# A trap answered by something other than holding gets no shield from
	# hands on it (Fragile); the solo rack assistant is not hands.
	var hands_count: bool = p.trap_behavior.hold_protects()
	if not solo_assist and not hands_count:
		input["steady"] = false
	var strained: bool = p.care.advance(delta, p._motion_acceleration, input, hands_count and p._assist_age < 0.3)
	if strained and riding:
		p.apply_impact(4.5)
	# The road ahead, for the traps that read it (Fragile's "Amortiguá").
	var road: Dictionary = {}
	if riding and p.trap_behavior.wants_road_ahead():
		road = RoadImpacts.nearest_ahead(p.get_tree(), p.global_position, velocity_now, ROAD_LOOKAHEAD)
	# Held bodies are frozen; the trap still advances here exactly once per tick.
	# In a solo run complex traps pause while safely parked for repairs.
	if not p.care.needs_restore and p.care.phase != &"lost" and not p.care.substituted:
		if not solo_assist or speed > 1.0:
			p.trap_behavior.on_physics_process(p, delta, {
				"linear_velocity": p.linear_velocity, "angular_velocity": p.angular_velocity, "input": input,
				"impact_ahead": float(road["eta"]) if not road.is_empty() else INF,
				"truck_right": vehicle.global_basis.x if vehicle != null else Vector3.RIGHT,
				"truck_forward": -vehicle.global_basis.z if vehicle != null else Vector3.FORWARD,
				"code_reader": code_reader(p, vehicle), "radio_mode": radio_mode(p)})
			if _road_jolt(p, road, speed):
				# apply_impact() already reported it.
				before_integrity = p.integrity
				before_state = p.trap_state
		p._award_pending_trap_milestones()
	consume_input_edges(p)
	_publish_cushion_change(p)
	check_recovery(p)
	var tool := StringName(input.get("tool", "tape"))
	var run: Node = PackageAutoloads.run_manager(p)
	var available: bool = run != null and int(run.call(&"care_supply_count", tool)) > 0
	if p.care.advance_work(delta, tool, input, p._trap_kind(), speed, available, p._assist_age < 0.3):
		if bool(run.call(&"consume_care_supply", tool)):
			complete_care_tool(p, tool)
		else:
			p.care.message = LocText.make("HUD_CARE_MSG_SUPPLY_TAKEN")
	p._report_change(before_integrity, before_state, p.tr("HUD_CARE_RUINED_IN_RESCUE"))
	p._care_publish_time += delta
	if p._care_publish_time >= 0.1:
		p._care_publish_time = 0.0
		publish_care(p)
		p._emit_event(&"package_hint_changed", [p.package_id, p.hint_text()])


## The truck radio's mode (TruckRadio, N-406), for the traps it moves (Ruidoso):
## &"off" when the level has no radio.
static func radio_mode(p: DeliveryPackage) -> StringName:
	var radio: TruckRadio = p.get_tree().get_first_node_in_group(&"truck_radio") as TruckRadio \
			if p.is_inside_tree() else null
	return radio.mode if radio != null else &"off"


## Harm that comes from outside the box's own trap -- the parasite sharing its
## wear, a dog on an open box, bees round the cake (N-109, route/cargo_animals.gd).
## Kept apart from the trap's own integrity for the parasite's reason: some traps
## recompute theirs every frame. Reported like any other damage (package_damaged,
## integrity, state) and never passed on to a parasite partner. `ruin_cause_key` is
## the translation key of the reason shown if this ruins it.
static func apply_external_damage(p: DeliveryPackage, amount: float, ruin_cause_key: String) -> void:
	if not p.is_multiplayer_authority() or p.trap_behavior == null or amount <= 0.0:
		return
	var before_integrity: float = p.integrity
	var before_state: int = p.trap_state
	p._sharing_parasite_damage = true
	p._parasite_damage = minf(p._parasite_damage + amount, p.integrity_max)
	p._report_change(before_integrity, before_state, p.tr(ruin_cause_key))
	p._sharing_parasite_damage = false


## How far ahead (s) a box looks for a bump the road announces: a little
## beyond the trap's own warning, so the trap decides when to show it.
const ROAD_LOOKAHEAD: float = 1.2
## What a trap that draws something (the bomb's code) rolls it from: the
## session seed and the box, so the same session deals the same code to the
## same box, and each box its own. 0 without a seeded session (solo): the
## trap then draws from the clock.
static func roll_seed(p: DeliveryPackage) -> int:
	var network := PackageAutoloads.network(p)
	# world_seed is declared by network_manager.gd, not by NetSession: by name.
	var session_seed: int = int(network.get(&"world_seed")) if network != null else 0
	return hash([session_seed, String(p.package_id)]) if session_seed != 0 else 0


## The tender's, the assistant's and the care worker's latest samples, mixed
## into the one input the trap sees (player_input): holds add up (the
## assistant at half strength), an edge from any of them counts.
static func refresh_combined_input(p: DeliveryPackage) -> void:
	var combined: Dictionary = {"steady": false, "calm": false, "steady_strength": 0.0, "calm_strength": 0.0,
			"direction_pressed": null, "tap": false, "lean": 0.0, "lean_long": 0.0, "directions": []}
	# The care worker (carrying it) counts in full, like the tender.
	var worker: int = p._care_worker if p._care_worker not in [p.tender_peer_id, p.assistant_peer_id] else 0
	for peer_id: int in [p.tender_peer_id, p.assistant_peer_id, worker]:
		if peer_id <= 0 or not p._has_fresh_input(peer_id):
			continue
		var sample: Dictionary = p._tender_inputs[peer_id]["input"]
		var weight: float = 0.5 if peer_id == p.assistant_peer_id else 1.0
		if bool(sample.get("steady", false)):
			combined["steady_strength"] = float(combined["steady_strength"]) + weight
			# Pushing only counts with the primary held (Balance's "Contrapesá"),
			# turned from the passenger's own view into the truck's frame.
			var push: Vector2 = push_in_truck(p, peer_id, sample)
			combined["lean"] = float(combined["lean"]) + weight * push.x
			combined["lean_long"] = float(combined["lean_long"]) + weight * push.y
		if bool(sample.get("calm", false)):
			combined["calm_strength"] = float(combined["calm_strength"]) + weight
		if combined["direction_pressed"] == null and sample.get("direction_pressed") != null:
			combined["direction_pressed"] = sample["direction_pressed"]
		# Every key pressed this tick, once each: the tender and their helper
		# see the same arrows and may press the same one at the same moment.
		var pressed: Variant = sample.get("direction_pressed")
		if pressed != null and not (combined["directions"] as Array).has(pressed):
			(combined["directions"] as Array).append(pressed)
		if bool(sample.get("tap", false)):
			combined["tap"] = true
	combined["steady"] = float(combined["steady_strength"]) > 0.0
	combined["calm"] = float(combined["calm_strength"]) > 0.0
	p.player_input = combined if float(combined["steady_strength"]) > 0.0 \
			or float(combined["calm_strength"]) > 0.0 \
			or combined["direction_pressed"] != null or bool(combined["tap"]) else {}
	add_care_fields(p)


## The edges of what the trap just saw (a sequence key, a tap) are spent. They
## were true for one tick on the sender, but the host keeps the last sample
## for up to TENDER_INPUT_TIMEOUT and may tick twice before the next one
## arrives: without this one press could count twice.
static func consume_input_edges(p: DeliveryPackage) -> void:
	for raw_peer: Variant in p._tender_inputs.keys():
		var sample: Dictionary = (p._tender_inputs[raw_peer] as Dictionary)["input"]
		sample["direction_pressed"] = null
		sample["tap"] = false
	refresh_combined_input(p)


## Who may read a bomb's code (see reader_for()).
const READER_DRIVER: StringName = &"driver"
const READER_OWNER: StringName = &"owner"


## The box just crossed the bump the road announced: the trap says what that
## does at this speed (0 when the truck took it slowly enough). True when it hurt.
static func _road_jolt(p: DeliveryPackage, road: Dictionary, speed: float) -> bool:
	if road.is_empty() or float(road["distance"]) > 0.0 or int(road["id"]) == p._road_jolted:
		return false
	p._road_jolted = int(road["id"])
	var strength: float = p.trap_behavior.road_jolt_strength(speed)
	if strength <= 0.0:
		return false
	p.apply_impact(strength)
	return true


## Whose screen shows a bomb's code: the driver's, unless the box's owner is
## the driver (or nobody else is at the wheel), then the owner's.
static func code_reader(p: DeliveryPackage, vehicle: Node3D) -> StringName:
	var driver: int = int(vehicle.get(&"driver_peer_id")) if vehicle != null else 0
	return reader_for(driver, owner_peer(p))


static func reader_for(driver_peer: int, owner_peer_id: int) -> StringName:
	return READER_DRIVER if driver_peer > 0 and driver_peer != owner_peer_id else READER_OWNER


## The peer looking after the box: who sits at its seat, else who carries it
## or is working on it.
static func owner_peer(p: DeliveryPackage) -> int:
	if p.tender_peer_id > 0:
		return p.tender_peer_id
	if is_instance_valid(p.carrier):
		return int(p.carrier.get_multiplayer_authority())
	return p._care_worker


## The ring on the box and the card's "tap now" follow the trap's cushion
## state, and a bump warning that arrives 0.1 s late is most of what a tap
## can use: send it as soon as it changes.
static func _publish_cushion_change(p: DeliveryPackage) -> void:
	var cushion: Dictionary = p.trap_behavior.cushion_state()
	if cushion.is_empty():
		return
	var signature: int = int(float(cushion["eta"]) >= 0.0) + 2 * int(bool(cushion["shield"])) \
			+ 4 * int(cushion["saved"]) + 4096 * int(cushion["taps"])
	if signature != p._cushion_signature:
		p._cushion_signature = signature
		p._care_publish_time = 0.1


static func check_recovery(p: DeliveryPackage) -> void:
	if p._lost or p.trap_behavior == null:
		return
	var failed: bool = p.trap_behavior.get_state() == ITrapBehavior.TrapState.RUINED or p.integrity <= 0.0
	if p.care.observe(p.integrity, failed, p._trap_kind()):
		spawn_salvage(p)
		publish_care(p)


static func complete_care_tool(p: DeliveryPackage, tool: StringName) -> void:
	p.care.complete_tool(tool, p._trap_kind())
	if tool in [&"repair", &"substitute", &"rag"]:
		p._lost = false
		p._parasite_damage = 0.0
		p.contents_spilled = false
		p.salvage_state = {}
		p.trap_behavior.on_setup(p, p.trap_definition.params.duplicate(true))
		# A neutralized explosive is inert, not a new bomb with a fresh timer.
		var bomb := p.trap_behavior as ExplosiveTrapBehavior
		if p._trap_kind() == &"explosive" and bomb != null:
			bomb._defused = true
		p.care.recent_hit = 1.25
		p._emit_event(&"package_contents_recovered", [p.package_id])
		p._award_milestone(p._care_worker, &"rescued")
	if tool == &"tape":
		# Tape seals the box even if its contents are still on the floor.
		p.is_open = false
		p._emit_event(&"package_lid_changed", [p.package_id, false])
	publish_care(p)


static func publish_care(p: DeliveryPackage) -> void:
	var state: Dictionary = p.care.snapshot()
	# Trap state lives in the host-only behavior: what it asks of the hands,
	# its hint and any tap sequence ride along, so every peer's care panel
	# (and the bomb's sign) shows the real thing.
	if p.trap_behavior != null:
		state["action"] = p.trap_behavior.care_action()
		state["hint"] = p.trap_behavior.hint_text()
		var sequence: Dictionary = p.trap_behavior.sequence_state()
		if not sequence.is_empty():
			state["sequence"] = sequence
		var cushion: Dictionary = p.trap_behavior.cushion_state()
		if not cushion.is_empty():
			state["cushion"] = cushion
		var gesture: Dictionary = p.trap_behavior.gesture_state()
		if not gesture.is_empty():
			state["gesture"] = gesture
	p.care_state = state
	var run: Node = PackageAutoloads.run_manager(p)
	if run != null and (run.get(&"cargo") as Dictionary).has(p.package_id):
		run.call(&"record_care", p.package_id, p.delivery_assessment())


static func spawn_salvage(p: DeliveryPackage) -> void:
	if p.care.missing_parts <= 0 or not p.salvage_state.is_empty():
		return
	var vehicle: Node3D = p._find_vehicle()
	var aboard: bool = vehicle != null and bool(vehicle.call(&"carries", p.global_position, 1.0))
	var origin: Vector3 = vehicle.to_local(p.global_position) if aboard else p.global_position
	var parts: Array = []
	for index: int in p.care.missing_parts:
		parts.append(origin + Vector3((index - 1) * 0.32, -0.2, 0.45))
	p.salvage_state = {"aboard": aboard, "parts": parts, "collected": [], "kind": p._trap_kind()}
	p.contents_spilled = true
	p._emit_event(&"package_contents_spilled", [p.package_id, Vector3.ZERO, p.trap_state])


static func collect_salvage(p: DeliveryPackage, index: int, player: Node, point: Vector3) -> void:
	if not p.is_multiplayer_authority() or p._consumed or p.care.phase == &"lost":
		return
	if p._reach_origin(player).distance_to(point) > 3.0:
		return
	var collected: Array = p.salvage_state.get("collected", [])
	var parts: Array = p.salvage_state.get("parts", [])
	if index < 0 or index >= parts.size() or collected.has(index):
		return
	if p.care.collect_part():
		collected.append(index)
		p.salvage_state = p.salvage_state.duplicate(true)
		p.salvage_state["collected"] = collected
		publish_care(p)


## Client sends intent only. Ownership/reach, action duration, direction, speed,
## inventory and the final result are all checked by the host.
static func submit_care_input(p: DeliveryPackage, input: Dictionary) -> void:
	if not p.is_multiplayer_authority() or p._consumed or not p._is_run_active():
		return
	var sender: int = p.multiplayer.get_remote_sender_id()
	var peer: int = sender if sender != 0 else p.multiplayer.get_unique_id()
	var operator: Node = null
	for candidate: Node in p.get_tree().get_nodes_in_group(&"player"):
		if candidate.get_multiplayer_authority() == peer:
			operator = candidate
			break
	if operator == null or p._reach_origin(operator).distance_to(p.global_position) > 3.5:
		return
	var owns: bool = p.carrier == operator or p.tender_peer_id == peer
	var someone_else_holds: bool = is_instance_valid(p.carrier) and p.carrier != operator
	var someone_else_works: bool = p._care_worker != 0 and p._care_worker != peer and p._has_fresh_input(p._care_worker)
	if not owns and (someone_else_holds or someone_else_works):
		if bool(input.get("steady", false)):
			p._assist_age = 0.0
		return
	var balance: Variant = input.get("balance", Vector2.ZERO)
	if not balance is Vector2 or not (balance as Vector2).is_finite():
		return
	var pressed: Variant = input.get("direction_pressed")
	var direction: StringName = StringName(pressed) if pressed != null else &""
	var sample: Dictionary = {"steady": bool(input.get("steady", false)), "calm": bool(input.get("calm", false)),
		"balance": (balance as Vector2).limit_length(1.0), "work": bool(input.get("work", false)),
		"tool": StringName(input.get("tool", "tape")), "tap": bool(input.get("tap", false)),
		"lean": clean_axis(input.get("lean", 0.0)), "lean_fwd": clean_axis(input.get("lean_fwd", 0.0)),
		"direction_pressed": direction if direction in [&"up", &"down", &"left", &"right"] else null}
	if bool(sample["work"]):
		sample["steady"] = false
		sample["calm"] = false
		sample["tap"] = false
		sample["lean"] = 0.0
		sample["lean_fwd"] = 0.0
	# Same per-peer samples as submit_tender_input(), so the two never fight
	# over player_input; add_care_fields() adds the tool work on top.
	p._tender_inputs[peer] = {"input": sample, "age": 0.0}
	p._care_worker = peer
	p._last_tender_peer = peer
	p._refresh_combined_input()


## What a passenger pressed (`lean` A/D, `lean_fwd` W/S, both as their own view
## sees them) as a push in the truck's frame: x to the truck's right, y forward.
## A seat on the truck's side looks across it, so its "left" is forward or back
## on the road; the view is the seat's, or the body's on foot. With no player
## or no truck to read them from, the axes are taken as they come.
static func push_in_truck(p: DeliveryPackage, peer_id: int, sample: Dictionary) -> Vector2:
	var pressed := Vector2(clean_axis(sample.get("lean", 0.0)), clean_axis(sample.get("lean_fwd", 0.0)))
	var vehicle: Node3D = p._find_vehicle()
	var player: Node = p._player_for_peer(peer_id) if p.is_inside_tree() else null
	if vehicle == null or player == null or pressed == Vector2.ZERO:
		return pressed
	var view: Basis = view_basis_of(player)
	var world: Vector3 = view.x * pressed.x + -view.z * pressed.y
	var right: Vector3 = vehicle.global_basis.x
	var forward: Vector3 = -vehicle.global_basis.z
	return Vector2(world.dot(right), world.dot(forward)).limit_length(1.0)


## Where a player's eyes face: their seat (its own -Z, the way the seat
## camera looks), or their body on foot.
static func view_basis_of(player: Node) -> Basis:
	# By name: tests put Node3D fakes in the "player" group, `as Player` would drop them.
	var recorded: Variant = player.get(&"seat_node_path")
	var seat_path: NodePath = recorded if recorded is NodePath else NodePath()
	var seat: Node3D = player.get_node_or_null(seat_path) as Node3D if not seat_path.is_empty() else null
	return seat.global_basis if seat != null else (player as Node3D).global_basis


## A stick or key axis from a client: a number in -1..1, or 0 for anything else.
static func clean_axis(value: Variant) -> float:
	if not (value is float or value is int) or not is_finite(float(value)):
		return 0.0
	return clampf(float(value), -1.0, 1.0)


## After the steady/calm mix: the balance, tool and work of whoever is working
## the box (the care worker, else the seat's tender). Working takes both hands,
## so it cancels steadying and calming.
static func add_care_fields(p: DeliveryPackage) -> void:
	var worker: int = p._care_worker if p._has_fresh_input(p._care_worker) else p.tender_peer_id
	if worker <= 0 or not p._has_fresh_input(worker):
		return
	var own: Dictionary = p._tender_inputs[worker]["input"]
	if not own.has("tool"):
		return
	var combined: Dictionary = p.player_input.duplicate() if not p.player_input.is_empty() else {
			"steady": false, "calm": false, "steady_strength": 0.0, "calm_strength": 0.0, "direction_pressed": null,
				"tap": false, "lean": 0.0, "lean_long": 0.0, "directions": []}
	for key: String in ["balance", "work", "tool"]:
		combined[key] = own[key]
	if bool(combined["work"]):
		combined["steady"] = false
		combined["calm"] = false
	p.player_input = combined


## Host: the seated passenger tending this box moves it between their lap
## and the rack it came from. The lap cushions hits but ties up the hands;
## the rack frees them for tools but needs a strap (package_care.gd).
static func request_lap_toggle(p: DeliveryPackage) -> void:
	if not p.is_multiplayer_authority() or p._consumed:
		return
	var sender: int = p.multiplayer.get_remote_sender_id()
	var peer: int = sender if sender != 0 else p.multiplayer.get_unique_id()
	if peer != p.tender_peer_id:
		return
	var operator: Node = null
	for candidate: Node in p.get_tree().get_nodes_in_group(&"player"):
		if candidate.get_multiplayer_authority() == peer:
			operator = candidate
	# Seated as the host sees it (the seat's occupant): the player's replicated
	# seat path lags a sitting down, and the lap toggle is often the first thing pressed.
	if operator == null or not SeatTending.is_seated(p.get_tree(), operator, p.multiplayer.is_server()):
		return
	if p.is_held and p.carrier == operator:
		var lap_mount: Node = SeatTending.lap_mount_of(p)  # PackageMountPoint: no class name
		if lap_mount != null and lap_mount.get(&"occupied_by") == null:
			lap_mount.call(&"store", p)
	elif p.is_loaded and not p.is_held and p.current_mount != null:
		var shelf: Node = p.current_mount
		p.take_by(operator)
		SeatTending.bind_lap(p, shelf)
	p.care.in_lap = p.is_held and p.carrier == operator
	p._publish_care()


## Host: someone dropped out. If they were looking after this box, its
## rescue window is held so the crew can reach it -- leaving never loses a
## box on the spot (docs/jugabilidad-paquetes-rescate.md, "Caída de un jugador").
## Every peer hears of a leave (NetworkManager.peer_removed); only the host's
## box changes.
static func peer_left(p: DeliveryPackage, peer_id: int) -> void:
	if not p.is_inside_tree() or not p.is_multiplayer_authority():
		return
	var carried_by_them: bool = is_instance_valid(p.carrier) and p.carrier.get_multiplayer_authority() == peer_id
	if peer_id in [p.tender_peer_id, p._care_worker] or carried_by_them:
		p.care.hold_crisis(DeliveryPackage.CareModel.CRISIS_SECONDS)
		var was_tender: bool = p.tender_peer_id == peer_id
		if was_tender:
			p.tender_peer_id = 0
		p._care_worker = 0
		p.player_input = {}
		p._publish_care()
		if was_tender:
			# Someone else sitting at a seat facing this mount takes it over.
			SeatTending.hand_over(p, peer_id)


static func delivery_assessment(p: DeliveryPackage) -> Dictionary:
	var category: StringName = &"intact"
	if p.care.substituted:
		category = &"substituted"
	elif p._lost or p.care.phase == &"lost" or p.care.needs_restore or p.contents_spilled:
		category = &"unconvincing"
	elif p.care.repairs > 0:
		category = &"repaired" if not p.is_open and p.integrity >= 60.0 else &"unconvincing"
	elif p.is_open or p.integrity < 85.0 or p.trap_state != 0:
		category = &"damaged"
	return {"category": category, "kind": p._trap_kind(), "quality": p.integrity,
		"repairs": p.care.repairs, "worst": p.care.worst_quality, "substituted": p.care.substituted}
