extends SeatCamera
## Take My Package's seat camera on the seat_camera module's SeatCamera
## (docs/modulos.md): the player's settings (field of view, sensitivity,
## inversion, shake), the local body hidden from its own lens, and what
## shakes it -- a vehicle impact (with a FOV kick, the "slow-mo breve" of
## docs/requerimientos-tecnicos.md 3.4 without touching Engine.time_scale)
## and a ruined package (docs/especificaciones-visuales.md #67: losing cargo
## to a trap running out felt weightless next to a real collision; no FOV
## kick there on purpose, that's reserved for the physical punch).

## A brief FOV kick on impact.
@export var impact_fov_kick_degrees: float = 7.0
const RenderLayers = preload("res://scripts/core/render_layers.gd")


func _ready() -> void:
	RenderLayers.configure_first_person(self)
	super()
	var bus: Node = get_node_or_null("/root/EventBus")
	if bus != null:
		bus.connect("vehicle_impact", _on_vehicle_impact)
		bus.connect("package_ruined", _on_package_ruined)


func _preferred_fov() -> float:
	return GameSettings.preferred_fov


func _look_sensitivity() -> float:
	return GameSettings.look_sensitivity


func _look_y_sign() -> float:
	return GameSettings.look_y_sign()


func _shake_scale() -> float:
	return GameSettings.camera_shake_scale


func _on_vehicle_impact(strength: float, _impact_position: Vector3) -> void:
	add_shake(strength * 0.15)
	kick_fov(impact_fov_kick_degrees * shake_strength())


func _on_package_ruined(_package_id: StringName, _cause: String) -> void:
	add_shake(0.6)
