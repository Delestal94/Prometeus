extends Node
## Compact route-event state. A route director can call begin_random() between
## stops; gameplay interactions call resolve_active() once the crew responds.

enum Type { INSPECTION, IMPATIENT_CLIENT, REAR_DOOR_JAM, MIXED_LABELS, MIMETIC_PACKAGE, PARASITE_BOX, CONFUSING_SHOP }

## Door jam needs Nacho's truck doors; confusing shop needs a road shop.
## Keep their definitions for later, but only draw playable events.
const ROUTE_POOL: Array[StringName] = [&"inspection", &"impatient_client", &"mixed_labels", &"mimetic_package", &"parasite_box"]
const TRAP_PATHS: Array[String] = ["res://data/traps/fragile.tres", "res://data/traps/noisy.tres", "res://data/traps/liquid.tres", "res://data/traps/hostile.tres", "res://data/traps/balance.tres", "res://data/traps/growing_weight.tres", "res://data/traps/explosive.tres"]
## These four already have dedicated icons; the remaining three join once
## S-301 lands, rather than displaying an empty Sprite3D in the meantime.
const MIMIC_DISGUISE_IDS: Array[StringName] = [&"fragile", &"balance", &"growing_weight", &"noisy"]

const EVENTS: Dictionary = {
	&"inspection": {"type": Type.INSPECTION, "title": "Inspección sorpresa", "prompt": "Aseguren toda la carga y cierren las cajas.", "action": &"secure_cargo", "merit": 20, "reward": 25, "duration": 60.0, "fine": 20},
	&"impatient_client": {"type": Type.IMPATIENT_CLIENT, "title": "Cliente impaciente", "prompt": "Entreguen su pedido intacto.", "action": &"expedite_delivery", "merit": 15, "reward": 20, "duration": 90.0, "fine": 25},
	&"rear_door_jam": {"type": Type.REAR_DOOR_JAM, "title": "Puerta trasera atascada", "prompt": "Liberen la puerta.", "action": &"free_rear_door", "merit": 20, "reward": 15, "duration": 60.0, "fine": 20},
	&"mixed_labels": {"type": Type.MIXED_LABELS, "title": "Etiquetas mezcladas", "prompt": "Esperen un golpe y abran las dos cajas.", "action": &"sort_labels", "merit": 15, "reward": 15, "duration": 75.0, "fine": 20},
	&"mimetic_package": {"type": Type.MIMETIC_PACKAGE, "title": "Paquete mimético", "prompt": "Mantengan sana la caja falsa tras revelarla.", "action": &"identify_mimic", "merit": 25, "reward": 25, "duration": 75.0, "fine": 25},
	&"parasite_box": {"type": Type.PARASITE_BOX, "title": "Caja parásita", "prompt": "Dos pasajeros: sostengan ambas cajas 2 s.", "action": &"isolate_parasite", "merit": 25, "reward": 25, "duration": 90.0, "fine": 30},
	&"confusing_shop": {"type": Type.CONFUSING_SHOP, "title": "Tienda confusa", "prompt": "Consulten la oferta.", "action": &"clarify_offer", "merit": 10, "reward": 10, "duration": 60.0, "fine": 15},
}

var active_event_id: StringName = &""
var active_event: Dictionary = {}
var resolved_events: Dictionary = {}
var crew_progression: Node
var event_bus: Node
## houses_assigned arrives before start_run; do not erase it in reset_route.
var _house_assignments: Array = []
var _update_elapsed: float = 0.0
var _hold_seconds: float = 0.0


func _ready() -> void:
	var bus: Node = _bus()
	if bus == null:
		return
	bus.connect(&"houses_assigned", _on_houses_assigned)
	bus.connect(&"house_delivery_recorded", _on_house_delivery)
	bus.connect(&"vehicle_impact", _on_vehicle_impact)
	bus.connect(&"package_lid_changed", _on_lid_changed)
	bus.connect(&"route_event_started", _on_relay_started)
	bus.connect(&"route_event_updated", _on_relay_updated)
	bus.connect(&"route_event_resolved", _on_relay_resolved)
	bus.connect(&"run_ended", _on_run_ended)


func reset_route() -> void:
	_clear_effects()
	active_event_id = &""
	active_event.clear()
	resolved_events.clear()
	_update_elapsed = 0.0
	_hold_seconds = 0.0


func begin_random(excluded: Array = []) -> StringName:
	var candidates: Array[StringName] = []
	if not _is_host():
		return &""
	for event_id: StringName in ROUTE_POOL:
		if event_id == &"parasite_box" and _peer_count() < 2:
			continue
		if event_id == &"impatient_client" and _house_assignments.is_empty():
			continue
		if event_id in [&"mixed_labels", &"parasite_box"] and _loaded_packages().size() < 2:
			continue
		if event_id == &"mimetic_package":
			var possible: bool = false
			for package: DeliveryPackage in _loaded_packages():
				if int(package.trap_definition.get("difficulty")) > 1:
					possible = true
			if not possible:
				continue
		if not excluded.has(event_id) and not resolved_events.has(event_id):
			candidates.append(event_id)
	if candidates.is_empty():
		return &""
	return begin_event(candidates.pick_random())


func begin_event(event_id: StringName) -> StringName:
	if not _is_host() or not EVENTS.has(event_id) or not active_event_id.is_empty():
		return &""
	active_event_id = event_id
	active_event = EVENTS[event_id].duplicate(true)
	active_event["remaining"] = float(active_event["duration"])
	active_event["phase"] = &"waiting"
	match event_id:
		&"impatient_client":
			if _house_assignments.is_empty():
				reset_route()
				return &""
			active_event["house"] = randi_range(0, _house_assignments.size() - 1)
			active_event["prompt"] = "Entreguen intacto el pedido de la casa %d." % (int(active_event["house"]) + 1)
		&"mimetic_package":
			if not _prepare_mimic():
				reset_route()
				return &""
		&"parasite_box":
			if not _prepare_parasite():
				reset_route()
				return &""
	_emit_event(&"route_event_started", [active_event_id, active_event.duplicate(true)])
	return active_event_id


func resolve_active(peer_id: int, action: StringName, success: bool = true) -> bool:
	if not _is_host() or active_event_id.is_empty() or peer_id <= 0:
		return false
	if action != StringName(active_event.get("action", &"")):
		return false
	_resolve(success, [peer_id], not success)
	return true


func _physics_process(delta: float) -> void:
	if not _is_host() or active_event_id.is_empty() or not _run_active():
		return
	active_event["remaining"] = maxf(0.0, float(active_event["remaining"]) - delta)
	match active_event_id:
		&"inspection":
			active_event["loose"] = _loose_count()
			if float(active_event["remaining"]) <= 15.0:
				_resolve(int(active_event["loose"]) == 0, _passenger_peers(), int(active_event["loose"]) != 0)
				return
		&"mimetic_package":
			if active_event.get("phase") == &"revealed":
				active_event["reveal_remaining"] = maxf(0.0, float(active_event["reveal_remaining"]) - delta)
				if float(active_event["reveal_remaining"]) <= 0.0:
					var package: DeliveryPackage = _package_by_id(StringName(active_event.get("package", &"")))
					var success: bool = package != null and package.trap_state != ITrapBehavior.TrapState.RUINED
					_resolve(success, [int(active_event.get("revealer", 0))], not success)
					return
		&"parasite_box":
			var peers: Array[int] = _parasite_peers()
			_hold_seconds = _hold_seconds + delta if peers.size() == 2 else 0.0
			active_event["hold"] = _hold_seconds
			if _hold_seconds >= 2.0:
				_resolve(true, peers)
				return
	if float(active_event["remaining"]) <= 0.0:
		_resolve(false, [], true)
		return
	_update_elapsed += delta
	if _update_elapsed >= 0.25:
		_update_elapsed = 0.0
		_emit_event(&"route_event_updated", [active_event_id, active_event.duplicate(true)])


func _resolve(success: bool, peers: Array[int], charge_fine: bool = false) -> void:
	if active_event_id.is_empty():
		return
	var event_id: StringName = active_event_id
	var data: Dictionary = active_event.duplicate(true)
	var crew: Node = _crew()
	if success and crew != null:
		for peer: int in peers:
			if peer > 0:
				crew.award_action(peer, StringName("event_%s:%d" % [event_id, peer]), int(data.get("merit", 0)))
		crew.add_team_money(int(data.get("reward", 0)))
	elif charge_fine and crew != null:
		crew.spend(mini(int(data.get("fine", 0)), int(crew.get("team_money"))))
	if crew != null:
		var bus: Node = _bus()
		if bus != null:
			# CrewProgression is host-authoritative; publish the resulting
			# balance so clients do not keep a stale HUD after a reward/fine.
			bus.call(&"relay", &"team_money_changed", [int(crew.get("team_money"))])
	if not success and event_id == &"impatient_client":
		var run: Node = _run()
		if run != null:
			run.set(&"lost_time_bonus", true)
	_clear_effects()
	resolved_events[event_id] = success
	active_event_id = &""
	active_event.clear()
	_emit_event(&"route_event_resolved", [event_id, success, peers[0] if not peers.is_empty() else 0])


func active_snapshot() -> Dictionary:
	return {"id": active_event_id, "event": active_event.duplicate(true)} if not active_event_id.is_empty() else {}


func load_snapshot(snapshot: Dictionary) -> void:
	active_event_id = StringName(snapshot.get("id", &""))
	active_event = (snapshot.get("event", {}) as Dictionary).duplicate(true) if not active_event_id.is_empty() else {}
	if not active_event_id.is_empty():
		var bus: Node = _bus()
		if bus != null:
			bus.emit_signal(&"route_event_started", active_event_id, active_event.duplicate(true))


func on_package_impact(package: DeliveryPackage, strength: float) -> void:
	if not _is_host() or active_event_id != &"mimetic_package" or active_event.get("phase") == &"revealed" or package.package_id != active_event.get("package"):
		return
	var params: Dictionary = package.trap_definition.get("params")
	if strength <= float(params.get("impact_threshold_light", 3.0)):
		return
	package.disguise_revealed = true
	active_event["phase"] = &"revealed"
	active_event["reveal_remaining"] = 20.0
	active_event["prompt"] = "Caja revelada: manténganla sana 20 s."
	active_event["revealer"] = package.tender_peer_id
	_emit_event(&"route_event_updated", [active_event_id, active_event.duplicate(true)])


func current_prompt() -> String:
	return String(active_event.get("prompt", ""))


func use_rescue(peer_id: int) -> bool:
	var crew: Node = _crew()
	if not _is_host() or active_event_id.is_empty() or crew == null or not crew.consume_card(peer_id, crew.Card.RESCUE):
		return false
	return resolve_active(peer_id, StringName(active_event.get("action", &"")), true)


func _on_houses_assigned(assignments: Array) -> void:
	_house_assignments = assignments.duplicate(true)


func _on_house_delivery(house: int, outcome: StringName, _package_id: StringName) -> void:
	if _is_host() and active_event_id == &"impatient_client" and house == int(active_event.get("house", -1)):
		_resolve(outcome == &"delivered_ok", [], outcome != &"delivered_ok")


func _on_vehicle_impact(strength: float, _position: Vector3) -> void:
	if not _is_host() or active_event_id != &"mixed_labels" or active_event.get("phase") != &"waiting" or strength <= 6.0:
		return
	var packages: Array[DeliveryPackage] = _loaded_packages()
	if packages.size() < 2:
		return
	packages.shuffle()
	packages[0].label_swapped_with = packages[1].package_id
	packages[1].label_swapped_with = packages[0].package_id
	active_event["packages"] = [packages[0].package_id, packages[1].package_id]
	active_event["opened"] = {}
	active_event["phase"] = &"swapped"
	active_event["prompt"] = "Etiquetas cambiadas: abran ambas cajas."
	_emit_event(&"route_event_updated", [active_event_id, active_event.duplicate(true)])


func _on_lid_changed(package_id: StringName, open: bool) -> void:
	if not _is_host() or active_event_id != &"mixed_labels" or active_event.get("phase") != &"swapped" or not open:
		return
	var ids: Array = active_event.get("packages", [])
	if not ids.has(package_id):
		return
	var opened: Dictionary = active_event.get("opened", {})
	opened[package_id] = true
	active_event["opened"] = opened
	if opened.size() == 2:
		var package: DeliveryPackage = _package_by_id(package_id)
		_resolve(true, [package.last_opener_peer_id if package != null else 0])
	else:
		_emit_event(&"route_event_updated", [active_event_id, active_event.duplicate(true)])


func _on_relay_started(event_id: StringName, event: Dictionary) -> void:
	if bool(event.get("incident", false)):
		return
	active_event_id = event_id
	active_event = event.duplicate(true)


func _on_relay_updated(event_id: StringName, event: Dictionary) -> void:
	if event_id == active_event_id:
		active_event = event.duplicate(true)


func _on_relay_resolved(event_id: StringName, _success: bool, _peer: int) -> void:
	if event_id == active_event_id:
		active_event_id = &""
		active_event.clear()


func _on_run_ended(_score: int, _results: Dictionary) -> void:
	if _is_host() and not active_event_id.is_empty():
		_resolve(false, [], false)


func close_for_run_end() -> void:
	if _is_host() and not active_event_id.is_empty():
		_resolve(false, [], false)


func _prepare_mimic() -> bool:
	var options: Array[Dictionary] = []
	for package: DeliveryPackage in _loaded_packages():
		for path: String in TRAP_PATHS:
			var candidate: Resource = load(path)
			if candidate != null and candidate.get("id") in MIMIC_DISGUISE_IDS and candidate.get("id") != package.trap_definition.get("id") and int(candidate.get("difficulty")) <= int(package.trap_definition.get("difficulty")):
				options.append({"package": package, "disguise": candidate})
	if options.is_empty():
		return false
	var option: Dictionary = options.pick_random()
	var package: DeliveryPackage = option["package"]
	var disguise: Resource = option["disguise"]
	package.disguise_trap_id = StringName(disguise.get("id"))
	active_event["package"] = package.package_id
	active_event["disguise_name"] = String(disguise.get("display_name"))
	return true


func _prepare_parasite() -> bool:
	var packages: Array[DeliveryPackage] = []
	for package: DeliveryPackage in _loaded_packages():
		# Only the four mounts paired with passenger seats are tendable. The
		# two free shelf mounts cannot complete this cooperative event.
		if "Seat" in String(package.current_mount_path):
			packages.append(package)
	if packages.size() < 2 or _peer_count() < 2:
		return false
	packages.shuffle()
	var first: DeliveryPackage = packages[0]
	var second: DeliveryPackage = packages[1]
	first.parasite_partner_id = second.package_id
	second.parasite_partner_id = first.package_id
	active_event["packages"] = [first.package_id, second.package_id]
	return true


func _parasite_peers() -> Array[int]:
	var ids: Array = active_event.get("packages", [])
	if ids.size() != 2:
		return []
	var first: DeliveryPackage = _package_by_id(StringName(ids[0]))
	var second: DeliveryPackage = _package_by_id(StringName(ids[1]))
	if first == null or second == null or first.tender_peer_id <= 0 or second.tender_peer_id <= 0 or first.tender_peer_id == second.tender_peer_id:
		return []
	if first._tender_input_age > first.TENDER_INPUT_TIMEOUT or second._tender_input_age > second.TENDER_INPUT_TIMEOUT:
		return []
	if not bool(first.player_input.get("steady", false)) or not bool(second.player_input.get("steady", false)):
		return []
	return [first.tender_peer_id, second.tender_peer_id]


func _loose_count() -> int:
	var count: int = 0
	for package: Node in _cargo_nodes():
		var run: Node = _run()
		var registered: Dictionary = run.get("cargo") if run != null else {}
		if not registered.is_empty() and not registered.has(package.get("package_id")):
			continue
		if not bool(package.get("is_loaded")) or bool(package.get("is_open")):
			count += 1
	return count


func _passenger_peers() -> Array[int]:
	var peers: Array[int] = []
	if not is_inside_tree():
		return peers
	for vehicle: Node in get_tree().get_nodes_in_group(&"vehicle"):
		for area: Node in vehicle.find_children("*", "Area3D", true, false):
			if "role" in area and area.get("role") == &"passenger":
				var occupant: Node = area.get("occupant")
				if is_instance_valid(occupant) and not peers.has(occupant.get_multiplayer_authority()):
					peers.append(occupant.get_multiplayer_authority())
	return peers


func _clear_effects() -> void:
	for package: Node in _cargo_nodes():
		if package is DeliveryPackage:
			package.label_swapped_with = &""
			package.disguise_trap_id = &""
			package.disguise_revealed = false
			package.parasite_partner_id = &""


func _loaded_packages() -> Array[DeliveryPackage]:
	var packages: Array[DeliveryPackage] = []
	for package: Node in _cargo_nodes():
		if package is DeliveryPackage and package.is_loaded:
			packages.append(package)
	return packages


func _cargo_nodes() -> Array[Node]:
	return get_tree().get_nodes_in_group(&"cargo") if is_inside_tree() else []


func _package_by_id(id: StringName) -> DeliveryPackage:
	for package: Node in _cargo_nodes():
		if package is DeliveryPackage and package.package_id == id:
			return package
	return null


func _peer_count() -> int:
	var network: Node = get_node_or_null(^"/root/NetworkManager") if is_inside_tree() else null
	return (network.get("peer_ids") as Array).size() if network != null else 1


func _is_host() -> bool:
	var network: Node = get_node_or_null(^"/root/NetworkManager") if is_inside_tree() else null
	return network == null or bool(network.call("is_host"))


func _run_active() -> bool:
	var run: Node = _run()
	return run != null and bool(run.get("is_running"))


func _run() -> Node:
	return get_node_or_null(^"/root/RunManager") if is_inside_tree() else null


func _crew() -> Node:
	if crew_progression != null:
		return crew_progression
	if not is_inside_tree():
		return null
	return get_node_or_null("/root/CrewProgression")


func _bus() -> Node:
	return event_bus if event_bus != null else (get_node_or_null(^"/root/EventBus") if is_inside_tree() else null)


func _emit_event(signal_name: StringName, arguments: Array) -> void:
	var bus: Node = _bus()
	if bus != null and bus.has_signal(signal_name):
		bus.call(&"relay", signal_name, arguments)
