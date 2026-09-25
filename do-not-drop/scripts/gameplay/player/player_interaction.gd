extends Node
## Local interaction targeting and prompts. The Player keeps its established
## method surface (and every RPC); those small wrappers delegate here.

var player


func _ready() -> void:
	player = get_parent()


func is_interact_event(event: InputEvent) -> bool:
	if event.is_action_pressed(&"interact"):
		return true
	if event is InputEventKey and event.pressed and not event.echo:
		return event.keycode == KEY_E or event.physical_keycode == KEY_E
	return false


func is_drop_event(event: InputEvent) -> bool:
	if event.is_action_pressed(&"package_drop"):
		return true
	return event is InputEventKey and event.pressed and not event.echo and (event.keycode == KEY_Q or event.physical_keycode == KEY_Q)


func is_open_event(event: InputEvent) -> bool:
	if event.is_action_pressed(&"package_open"):
		return true
	return event is InputEventKey and event.pressed and not event.echo and (event.keycode == KEY_T or event.physical_keycode == KEY_T)


func lid_target(aimed: Node = null) -> DeliveryPackage:
	if is_instance_valid(player.carried_package):
		return player.carried_package
	if player._seated:
		return player.tended_package if is_instance_valid(player.tended_package) else null
	if aimed == null:
		aimed = closest_interactable()
	if aimed != null and aimed.get_parent() is DeliveryPackage:
		return aimed.get_parent() as DeliveryPackage
	return null


func toggle_package_lid() -> void:
	var package: DeliveryPackage = lid_target()
	if package == null or package.contents_spilled:
		return
	package.rpc_id(1, &"request_set_open", not package.is_open)


func publish_lid_hint(package: DeliveryPackage) -> void:
	var action: String = ""
	var inside: String = ""
	if package != null:
		if not package.contents_spilled:
			action = "Cerrar caja" if package.is_open else "Abrir caja"
		var view: Node = package.get_node_or_null(^"PackageContentsView")
		if view != null:
			inside = str(view.call(&"describe"))
	var key: String = action + "|" + inside
	if key == player._last_lid_hint:
		return
	player._last_lid_hint = key
	var bus: Node = player.get_node_or_null("/root/EventBus")
	if bus != null:
		bus.emit_signal(&"package_lid_hint_changed", action, inside)


func poll_interact() -> void:
	var is_down: bool = Input.is_action_pressed(&"interact") or Input.is_key_pressed(KEY_E)
	if is_down and not player._interact_was_down:
		try_interact()
	player._interact_was_down = is_down


func publish_prompt(value: String) -> void:
	if value == player._last_prompt:
		return
	player._last_prompt = value
	var bus: Node = player.get_node_or_null("/root/EventBus")
	if bus != null:
		bus.emit_signal(&"interaction_prompt_changed", value)


func update_highlight(target: Node) -> void:
	if target == player._highlighted:
		return
	if is_instance_valid(player._highlighted) and player._highlighted.has_method(&"highlight"):
		player._highlighted.call(&"highlight", false)
	player._highlighted = target
	if is_instance_valid(player._highlighted) and player._highlighted.has_method(&"highlight"):
		player._highlighted.call(&"highlight", true)


func send_ping() -> void:
	var network: Node = player.get_node_or_null("/root/NetworkManager")
	var bus: Node = player.get_node_or_null("/root/EventBus")
	if bus == null:
		return
	if network != null and network.call(&"is_online") and not network.call(&"is_host"):
		bus.rpc_id(1, &"request_ping", player.reach_origin(), player.PING_LABEL)
	else:
		bus.call(&"request_ping", player.reach_origin(), player.PING_LABEL)


func use_card() -> void:
	var network: Node = player.get_node_or_null(^"/root/NetworkManager")
	var crew: Node = player.get_node_or_null(^"/root/CrewProgression")
	if crew == null:
		return
	if network != null and bool(network.call(&"is_online")) and not bool(network.call(&"is_host")):
		crew.rpc_id(1, &"request_use_card")
	else:
		crew.call(&"request_use_card")


func try_interact() -> void:
	if player.carried_package != null:
		var teammate: Player = player._transfer_target()
		if teammate != null:
			player.carried_package.rpc_id(1, &"request_transfer", teammate.get_path())
			return
	var target: Node = closest_interactable()
	if target == null:
		return
	var network: Node = player.get_node_or_null("/root/NetworkManager")
	if network != null and network.call(&"is_online") and not network.call(&"is_host"):
		target.rpc_id(1, &"request_interact")
	else:
		target.call(&"interact", player)


func closest_interactable() -> Node:
	var best: Node = null
	var best_score: float = -INF
	var eye: Vector3 = player._camera.global_position
	var look: Vector3 = -player._camera.global_basis.z
	for area: Node in player._nearby:
		if not is_instance_valid(area):
			continue
		if not bool(area.call(&"can_interact", player)):
			continue
		if not within_reach(area as Node3D):
			continue
		var to_target: Vector3 = (area as Node3D).global_position - eye
		var distance: float = to_target.length()
		var alignment: float = look.dot(to_target / distance) if distance > 0.001 else 1.0
		var score: float = alignment - distance * player.AIM_DISTANCE_WEIGHT
		if score > best_score:
			best_score = score
			best = area
	return best


func within_reach(target: Node3D) -> bool:
	var eye: Vector3 = player._camera.global_position
	var hit: Dictionary = player._raycast(eye, target.global_position, 1 | 2)
	if hit.is_empty():
		return true
	return (hit["position"] as Vector3).distance_to(target.global_position) <= player.REACH_SURFACE_TOLERANCE


func on_probe_entered(area: Area3D) -> void:
	if area.has_method(&"interact"):
		player._nearby.append(area)


func on_probe_exited(area: Area3D) -> void:
	player._nearby.erase(area)
