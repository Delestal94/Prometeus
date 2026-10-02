class_name PackageTending
extends RefCounted
## Whoever looks after the box and the one helper (host side): the input each sends, how it ages, who may
## assist, and the merit they earn. Split out of package.gd (N-225.4) like package_rescue.gd: the state stays
## on the DeliveryPackage, which keeps thin wrappers (and the RPCs: who may ask, and how often, is checked
## there before anything here runs).
##
## By name on purpose (N-224.4, test_dynamic_dispatch_budget): RunManager's cargo and CrewProgression's
## color and award_milestone (see package_autoloads.gd: typing the autoloads makes a compile cycle).

## Seconds of continuous help it takes to earn one "assist" merit.
const ASSIST_MERIT_SECONDS: float = 10.0


## The host's physics tick of the tending side: stale samples expire, the helper steps back when the box no
## longer needs one (and earns merit while it does), and a care worker whose input stopped arriving is no
## longer working the box.
static func tick(p: DeliveryPackage, delta: float) -> void:
	_age_inputs(p, delta)
	if p.assistant_peer_id > 0 and p.trap_state != ITrapBehavior.TrapState.AT_RISK:
		set_assistant(p, 0)
	elif p.assistant_peer_id > 0 and has_fresh_input(p, p.assistant_peer_id):
		p._assist_seconds += delta
		if p._assist_seconds >= ASSIST_MERIT_SECONDS:
			p._assist_seconds -= ASSIST_MERIT_SECONDS
			award_milestone(p, p.assistant_peer_id, &"assist")
	if p._care_worker != 0 and not has_fresh_input(p, p._care_worker):
		p._care_worker = 0
	p._assist_age += delta


## One sample from the tender or the helper; false when it comes from anyone else.
static func accept_input(p: DeliveryPackage, peer_id: int, input: Dictionary) -> bool:
	if peer_id <= 0 or (peer_id != p.tender_peer_id and peer_id != p.assistant_peer_id):
		return false
	p._tender_inputs[peer_id] = {"input": input.duplicate(true), "age": 0.0}
	if has_useful_input(input):
		p._last_tender_peer = peer_id
	p._refresh_combined_input()
	return true


## Host: the seat's occupant changed (seat_point.gd). Nobody tending means no
## input at all -- not the last sample the previous passenger left behind.
static func set_tender(p: DeliveryPackage, peer_id: int) -> void:
	p.tender_peer_id = peer_id
	p._tender_inputs.clear()
	p.player_input = {}
	if peer_id == 0 or p.assistant_peer_id == peer_id:
		set_assistant(p, 0)
	p._assist_seconds = 0.0


static func set_assistant(p: DeliveryPackage, peer_id: int) -> bool:
	if peer_id > 0 and (p.tender_peer_id <= 0 or peer_id == p.tender_peer_id or (p.assistant_peer_id > 0
			and p.assistant_peer_id != peer_id)):
		return false
	var previous: int = p.assistant_peer_id
	if previous > 0:
		p._tender_inputs.erase(previous)
	p.assistant_peer_id = peer_id
	p._assist_seconds = 0.0
	p._refresh_combined_input()
	if previous > 0 and previous != peer_id and p.is_inside_tree():
		var previous_player: Node = player_for_peer(p, previous)
		if previous_player != null and previous_player.has_method(&"stop_assisting"):
			previous_player.rpc_id(previous, &"stop_assisting", p.get_path())
	return true


static func can_assist(p: DeliveryPackage, peer_id: int) -> bool:
	return peer_id > 0 and peer_id != p.tender_peer_id and p.tender_peer_id > 0 \
			and (p.assistant_peer_id == 0 or p.assistant_peer_id == peer_id) \
			and assist_available(p)


static func assist_available(p: DeliveryPackage) -> bool:
	return p.tender_peer_id > 0 and run_state(p) == ITrapBehavior.TrapState.AT_RISK


static func run_state(p: DeliveryPackage) -> int:
	var run: Node = PackageAutoloads.run_manager(p)
	if run != null:
		var run_cargo: Dictionary = run.get(&"cargo")
		if run_cargo.has(p.package_id):
			return int((run_cargo[p.package_id] as Dictionary).get("state", p.trap_state))
	return p.trap_state


static func assist_prompt(p: DeliveryPackage) -> String:
	var crew: Node = PackageAutoloads.crew(p)
	var color: String = String(crew.call(&"player_color_name", p.tender_peer_id)) if crew != null \
		else p.tr("HUD_YOUR_TEAMMATE")
	return p.tr("HUD_PROMPT_HELP_PACKAGE") % color


## `peer_id` asks to help: the host checks they can and are within reach, then tells their client.
static func assist(p: DeliveryPackage, peer_id: int) -> void:
	if not can_assist(p, peer_id) or not _peer_within_assist_reach(p, peer_id):
		return
	if not set_assistant(p, peer_id):
		return
	var player: Node = player_for_peer(p, peer_id)
	if player != null and player.has_method(&"assist_package"):
		player.rpc_id(peer_id, &"assist_package", p.get_path())


static func stop_assist(p: DeliveryPackage, peer_id: int) -> void:
	if peer_id == p.assistant_peer_id:
		set_assistant(p, 0)


static func _age_inputs(p: DeliveryPackage, delta: float) -> void:
	for raw_peer: Variant in p._tender_inputs.keys():
		var sample: Dictionary = p._tender_inputs[raw_peer]
		sample["age"] = float(sample.get("age", 0.0)) + delta
		if float(sample["age"]) > DeliveryPackage.TENDER_INPUT_TIMEOUT:
			p._tender_inputs.erase(raw_peer)
		else:
			p._tender_inputs[raw_peer] = sample
	p._refresh_combined_input()


static func has_fresh_input(p: DeliveryPackage, peer_id: int) -> bool:
	return p._tender_inputs.has(peer_id) and float((p._tender_inputs[peer_id] as Dictionary).get("age",
			INF)) <= DeliveryPackage.TENDER_INPUT_TIMEOUT


static func _peer_within_assist_reach(p: DeliveryPackage, peer_id: int) -> bool:
	var player: Node = player_for_peer(p, peer_id)
	return player != null and DeliveryPackage._reach_origin(player).distance_to(p.global_position) \
			<= DeliveryPackage.ASSIST_REACH + p.reach_slack(peer_id)


static func player_for_peer(p: DeliveryPackage, peer_id: int) -> Node:
	for player: Node in p.get_tree().get_nodes_in_group(&"player"):
		if player.get_multiplayer_authority() == peer_id:
			return player
	return null


## An input that could actually affect the box: a held button or a chosen direction.
static func has_useful_input(input: Dictionary) -> bool:
	for value: Variant in input.values():
		if value is bool and bool(value):
			return true
		if (value is StringName or value is String) and not String(value).is_empty():
			return true
	return false


static func award_pending_trap_milestones(p: DeliveryPackage) -> void:
	if p.trap_behavior == null:
		return
	for milestone: StringName in p.trap_behavior.take_milestones():
		award_milestone(p, p._last_tender_peer, milestone)


static func award_milestone(p: DeliveryPackage, peer_id: int, milestone: StringName) -> bool:
	if peer_id <= 0 or milestone.is_empty() or not p.is_inside_tree():
		return false
	var progression: Node = PackageAutoloads.crew(p)
	if progression == null or not progression.has_method(&"award_milestone"):
		return false
	var occurrence: int = int(p._milestone_counts.get(milestone, 0)) + 1
	if not bool(progression.call(&"award_milestone", peer_id, p.package_id, milestone, occurrence)):
		return false
	p._milestone_counts[milestone] = occurrence
	return true
