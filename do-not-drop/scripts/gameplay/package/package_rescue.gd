class_name PackageRescue
extends RefCounted
## The cargo rescue on the host (docs/jugabilidad-paquetes-rescate.md): care
## simulation per tick, recovery, repair tools and salvaged parts. Split out of
## package.gd to keep it readable; DeliveryPackage keeps thin wrappers (and the
## RPC) so callers and the network surface are unchanged.


static func simulate_cargo(p: DeliveryPackage, delta: float) -> void:
	if p.trap_behavior == null:
		return
	var before_integrity: float = p.integrity
	var before_state: int = p.trap_state
	var vehicle: Node3D = p._find_vehicle()
	var riding: bool = vehicle != null and bool(vehicle.call(&"carries", p.global_position, 1.0))
	var speed: float = 0.0
	if riding:
		var velocity_now: Vector3 = vehicle.call(&"point_velocity", p.global_position)
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
	p.care.in_lap = (p.is_held and is_instance_valid(p.carrier)
			and not String(p.carrier.get(&"seat_node_path")).is_empty())
	var input: Dictionary = p.player_input.duplicate()
	# Solo crews get a modest rack assistant; they still stop to repair.
	var solo_assist: bool = (p.get_tree().get_nodes_in_group(&"player").size() == 1 and not p.is_held
			and p.tender_peer_id == 0)
	if solo_assist:
		input["steady"] = true
		input["calm"] = true
		input["balance"] = p.care.balance_target
	var strained: bool = p.care.advance(delta, p._motion_acceleration, input, p._assist_age < 0.3)
	if strained and riding:
		p.apply_impact(4.5)
	# Held bodies are frozen; the trap still advances here exactly once per tick.
	# In a solo run complex traps pause while safely parked for repairs.
	if not p.care.needs_restore and p.care.phase != &"lost" and not p.care.substituted:
		if not solo_assist or speed > 1.0:
			p.trap_behavior.call("on_physics_process", p, delta, {
				"linear_velocity": p.linear_velocity, "angular_velocity": p.angular_velocity, "input": input})
		p._award_pending_trap_milestones()
	check_recovery(p)
	var tool := StringName(input.get("tool", "tape"))
	var run: Node = p.get_node_or_null(^"/root/RunManager")
	var available: bool = run != null and int(run.call(&"care_supply_count", tool)) > 0
	if p.care.advance_work(delta, tool, input, p._trap_kind(), speed, available, p._assist_age < 0.3):
		if bool(run.call(&"consume_care_supply", tool)):
			complete_care_tool(p, tool)
		else:
			p.care.message = p.tr("HUD_CARE_MSG_SUPPLY_TAKEN")
	p._report_change(before_integrity, before_state, p.tr("HUD_CARE_RUINED_IN_RESCUE"))
	p._care_publish_time += delta
	if p._care_publish_time >= 0.1:
		p._care_publish_time = 0.0
		publish_care(p)
		p._emit_event(&"package_hint_changed", [p.package_id, p.get_hint()])


static func check_recovery(p: DeliveryPackage) -> void:
	if p._lost or p.trap_behavior == null:
		return
	var failed: bool = int(p.trap_behavior.call(&"get_state")) == ITrapBehavior.TrapState.RUINED or p.integrity <= 0.0
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
		var config: Dictionary = p.trap_definition.get(&"params")
		p.trap_behavior.call(&"on_setup", p, config.duplicate(true))
		# A neutralized explosive is inert, not a new bomb with a fresh timer.
		if p._trap_kind() == &"explosive":
			p.trap_behavior.set(&"_defused", true)
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
		state["action"] = p.trap_behavior.call(&"care_action")
		state["hint"] = String(p.trap_behavior.call(&"get_hint"))
		var sequence: Dictionary = p.trap_behavior.call(&"sequence_state")
		if not sequence.is_empty():
			state["sequence"] = sequence
	p.care_state = state
	var run: Node = p.get_node_or_null(^"/root/RunManager")
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
		"tool": StringName(input.get("tool", "tape")),
		"direction_pressed": direction if direction in [&"up", &"down", &"left", &"right"] else null}
	if bool(sample["work"]):
		sample["steady"] = false
		sample["calm"] = false
	# Same per-peer samples as submit_tender_input(), so the two never fight
	# over player_input; add_care_fields() adds the tool work on top.
	p._tender_inputs[peer] = {"input": sample, "age": 0.0}
	p._care_worker = peer
	p._last_tender_peer = peer
	p._refresh_combined_input()


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
			"steady": false, "calm": false, "steady_strength": 0.0, "calm_strength": 0.0, "direction_pressed": null}
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
	if operator == null or String(operator.get(&"seat_node_path")).is_empty():
		return
	if p.is_held and p.carrier == operator:
		if is_instance_valid(p._lap_mount) and p._lap_mount.get(&"occupied_by") == null:
			p._lap_mount.call(&"store", p)
	elif p.is_loaded and not p.is_held and p.current_mount != null:
		p._lap_mount = p.current_mount
		p.take_by(operator)
	p.care.in_lap = p.is_held and p.carrier == operator
	p._publish_care()


## Host: someone dropped out. If they were looking after this box, its
## rescue window is held so the crew can reach it -- leaving never loses a
## box on the spot (docs/jugabilidad-paquetes-rescate.md, "Caída de un jugador").
static func peer_left(p: DeliveryPackage, peer_id: int) -> void:
	var carried_by_them: bool = is_instance_valid(p.carrier) and p.carrier.get_multiplayer_authority() == peer_id
	if peer_id in [p.tender_peer_id, p._care_worker] or carried_by_them:
		p.care.hold_crisis(DeliveryPackage.CareModel.CRISIS_SECONDS)
		if p.tender_peer_id == peer_id:
			p.tender_peer_id = 0
		p._care_worker = 0
		p.player_input = {}
		p._publish_care()


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
