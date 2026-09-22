extends Node
## Compact route-event state. A route director can call begin_random() between
## stops; gameplay interactions call resolve_active() once the crew responds.

enum Type { INSPECTION, IMPATIENT_CLIENT, REAR_DOOR_JAM, MIXED_LABELS, MIMETIC_PACKAGE, PARASITE_BOX, CONFUSING_SHOP }

const EVENTS: Dictionary = {
	&"inspection": {"type": Type.INSPECTION, "title": "Inspección sorpresa", "prompt": "Dejen la carga ordenada antes de que revisen.", "action": &"secure_cargo", "merit": 20, "reward": 25},
	&"impatient_client": {"type": Type.IMPATIENT_CLIENT, "title": "Cliente impaciente", "prompt": "Entreguen rápido y sin romper la caja.", "action": &"expedite_delivery", "merit": 15, "reward": 20},
	&"rear_door_jam": {"type": Type.REAR_DOOR_JAM, "title": "Puerta trasera atascada", "prompt": "Usen la herramienta correcta para liberar la puerta.", "action": &"free_rear_door", "merit": 20, "reward": 15},
	&"mixed_labels": {"type": Type.MIXED_LABELS, "title": "Etiquetas mezcladas", "prompt": "Revisen las etiquetas y separen los paquetes.", "action": &"sort_labels", "merit": 15, "reward": 15},
	&"mimetic_package": {"type": Type.MIMETIC_PACKAGE, "title": "Paquete mimético", "prompt": "Encuentren la caja falsa antes de cargarla.", "action": &"identify_mimic", "merit": 25, "reward": 25},
	&"parasite_box": {"type": Type.PARASITE_BOX, "title": "Caja parásito", "prompt": "Aíslen la caja antes de que contamine la carga.", "action": &"isolate_parasite", "merit": 25, "reward": 25},
	&"confusing_shop": {"type": Type.CONFUSING_SHOP, "title": "Tienda confusa", "prompt": "Las ofertas están ocultas: consulten su carta de información.", "action": &"clarify_offer", "merit": 10, "reward": 10},
}

var active_event_id: StringName = &""
var active_event: Dictionary = {}
var resolved_events: Dictionary = {}
var crew_progression: Node
var event_bus: Node


func reset_route() -> void:
	active_event_id = &""
	active_event.clear()
	resolved_events.clear()


func begin_random(excluded: Array = []) -> StringName:
	var candidates: Array[StringName] = []
	for event_id: StringName in EVENTS:
		if not excluded.has(event_id) and not resolved_events.has(event_id):
			candidates.append(event_id)
	if candidates.is_empty():
		return &""
	return begin_event(candidates.pick_random())


func begin_event(event_id: StringName) -> StringName:
	if not EVENTS.has(event_id) or not active_event_id.is_empty():
		return &""
	active_event_id = event_id
	active_event = EVENTS[event_id].duplicate(true)
	_emit_event(&"route_event_started", [active_event_id, active_event.duplicate(true)])
	return active_event_id


func resolve_active(peer_id: int, action: StringName, success: bool = true) -> bool:
	if active_event_id.is_empty() or peer_id <= 0:
		return false
	if action != StringName(active_event.get("action", &"")):
		return false
	var event_id: StringName = active_event_id
	if success:
		var action_id: StringName = StringName("event_%s" % event_id)
		var crew: Node = _crew()
		if crew == null:
			return false
		crew.award_action(peer_id, action_id, int(active_event.get("merit", 0)))
		crew.add_team_money(int(active_event.get("reward", 0)))
	resolved_events[event_id] = success
	active_event_id = &""
	active_event.clear()
	_emit_event(&"route_event_resolved", [event_id, success, peer_id])
	return true


func current_prompt() -> String:
	return String(active_event.get("prompt", ""))


func use_rescue(peer_id: int) -> bool:
	var crew: Node = _crew()
	if active_event_id.is_empty() or crew == null or not crew.consume_card(peer_id, crew.Card.RESCUE):
		return false
	return resolve_active(peer_id, StringName(active_event.get("action", &"")), true)


func _crew() -> Node:
	if crew_progression != null:
		return crew_progression
	if not is_inside_tree():
		return null
	return get_node_or_null("/root/CrewProgression")


func _emit_event(signal_name: StringName, arguments: Array) -> void:
	var bus: Node = event_bus
	if bus == null and is_inside_tree():
		bus = get_node_or_null("/root/EventBus")
	if bus != null and bus.has_signal(signal_name):
		var payload: Array = [signal_name]
		payload.append_array(arguments)
		bus.callv(&"emit_signal", payload)
