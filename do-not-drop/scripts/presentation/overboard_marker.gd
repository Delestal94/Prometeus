extends Node3D
## The flag over a box lying on the road (N-213.1): a billboard "¡RESCATAR!"
## with the seconds left, riding above the box while the host keeps its rescue
## window open (LevelCommon._check_lost_cargo()). Presentation only, on every
## peer: it follows EventBus.cargo_overboard / cargo_overboard_ended, which the
## host relays, and never decides anything about the box.

const HEIGHT: float = 1.4
const COLOR: Color = Color("ffb020")
const URGENT_COLOR: Color = Color("ff4a3a")
## Under this many seconds left, the flag turns red.
const URGENT_SECONDS: float = 10.0

## package_id -> {"label": Label3D, "left": float}
var _markers: Dictionary = {}


func _ready() -> void:
	EventBus.cargo_overboard.connect(_on_overboard)
	EventBus.cargo_overboard_ended.connect(_on_ended)


func has_marker(package_id: StringName) -> bool:
	return _markers.has(package_id)


func _on_overboard(package_id: StringName, at: Vector3, seconds: float) -> void:
	_on_ended(package_id, false)
	var label := Label3D.new()
	label.name = "Overboard_%s" % package_id
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.fixed_size = true
	label.pixel_size = 0.0015
	label.font_size = 48
	label.outline_size = 12
	label.modulate = COLOR
	add_child(label)
	label.global_position = at + Vector3.UP * HEIGHT
	_markers[package_id] = {"label": label, "left": seconds}
	_refresh(package_id)


func _on_ended(package_id: StringName, _rescued: bool) -> void:
	if not _markers.has(package_id):
		return
	var label: Node = _markers[package_id]["label"]
	if is_instance_valid(label):
		label.queue_free()
	_markers.erase(package_id)


func _process(delta: float) -> void:
	for package_id: StringName in _markers.keys():
		var entry: Dictionary = _markers[package_id]
		entry["left"] = maxf(0.0, float(entry["left"]) - delta)
		var box: Node3D = _find_package(package_id)
		if box != null:
			(entry["label"] as Label3D).global_position = box.global_position + Vector3.UP * HEIGHT
		_refresh(package_id)


func _refresh(package_id: StringName) -> void:
	var entry: Dictionary = _markers[package_id]
	var left: float = float(entry["left"])
	var label: Label3D = entry["label"]
	label.text = "¡RESCATAR!\n%d s" % ceili(left)
	label.modulate = URGENT_COLOR if left <= URGENT_SECONDS else COLOR


func _find_package(package_id: StringName) -> Node3D:
	for candidate: Node in get_tree().get_nodes_in_group(&"cargo"):
		if candidate is DeliveryPackage and (candidate as DeliveryPackage).package_id == package_id:
			return candidate
	return null
