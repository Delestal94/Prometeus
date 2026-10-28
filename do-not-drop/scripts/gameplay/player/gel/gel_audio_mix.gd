class_name GelAudioMix
extends RefCounted
## Shared mix policy for every sound owned by the gel character. The active
## listener decides Interior/Exterior locally; no environment state travels
## over the network.

const INTERIOR_BUS: StringName = &"Interior"
const EXTERIOR_BUS: StringName = &"Exterior"
const SILENT_DB: float = -80.0
## Small, deterministic colour-slot variation for foley and dance music. The
## wordless voice already has a much wider per-slot fundamental of its own.
const SLOT_PITCH: Array[float] = [1.0, 1.035, 0.97, 1.06, 0.94, 1.02, 0.985, 1.045]


static func listener_bus(context: Node) -> StringName:
	if context == null or not context.is_inside_tree():
		return EXTERIOR_BUS
	for vehicle: Node in context.get_tree().get_nodes_in_group(&"vehicle"):
		var presentation: Node = vehicle.get_node_or_null(^"VehiclePresentation")
		if presentation != null and presentation.has_method(&"viewer_inside") \
				and bool(presentation.call(&"viewer_inside")):
			return _available_bus(INTERIOR_BUS)
	return _available_bus(EXTERIOR_BUS)


## Height carries most of the perceived body mass; thickness adds a smaller
## contribution so a broad gel sounds heavier than a thin gel of equal height.
static func body_size(proportions: Resource) -> float:
	if proportions == null:
		return 1.0
	var height: float = clampf(float(proportions.get(&"total_height")), 0.85, 1.20)
	var thickness: float = clampf(float(proportions.get(&"general_thickness")), -1.0, 1.0)
	return clampf(height * (1.0 + thickness * 0.08), 0.78, 1.30)


static func body_pitch(proportions: Resource) -> float:
	return clampf(pow(body_size(proportions), -0.72), 0.82, 1.20)


static func player_pitch(player: Node, proportions: Resource = null) -> float:
	var slot: int = PlayerColorSlot.slot(player.get_multiplayer_authority(), SLOT_PITCH.size()) \
		if player != null else 0
	return clampf(SLOT_PITCH[slot] * body_pitch(
		proportions if proportions != null else proportions_for(player)), 0.78, 1.24)


static func proportions_for(player: Node) -> Resource:
	if player == null:
		return null
	var state: Node = player.get_node_or_null(^"GelProportions")
	var value: Variant = state.get(&"proportions") if state != null else null
	return value as Resource


## Interior/Exterior are environment buses rather than the three option buses,
## so preserve the matching user slider as a gain on the individual emitter.
static func with_setting(context: Node, base_db: float, property: StringName) -> float:
	var settings: Node = context.get_node_or_null(^"/root/GameSettings") \
		if context != null and context.is_inside_tree() else null
	var amount: float = clampf(float(settings.get(property)), 0.0, 1.0) if settings != null else 1.0
	return SILENT_DB if amount <= 0.0001 else base_db + linear_to_db(amount)


static func _available_bus(wanted: StringName) -> StringName:
	return wanted if AudioServer.get_bus_index(wanted) >= 0 else &"Master"
