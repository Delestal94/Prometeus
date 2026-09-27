class_name DepotAmbience
extends Node
## The depot's moving presentation, animated every frame: ceiling fans, the
## wall clock (real time), the conveyor belt and its boxes, and the
## fluorescent tube that's on its way out. Pure presentation -- nothing here
## is replicated or read back by gameplay. Any part may be missing (a test
## that builds only some of the depot): it's simply skipped.

const Layout = preload("res://scripts/gameplay/depot/depot_layout.gd")
const FAN_SPEED: float = 0.9
const BELT_SPEED: float = 0.6

var fans: Array[Node3D] = []
var clock_hour: Node3D
var clock_minute: Node3D
var belt_material: StandardMaterial3D
var belt_boxes: Array[Node3D] = []
var flicker_tube: MeshInstance3D

var _flicker_time: float = 0.0


func _process(delta: float) -> void:
	for fan: Node3D in fans:
		fan.rotate_y(delta * FAN_SPEED)
	if clock_hour != null and clock_minute != null:
		_tick_clock()
	if belt_material != null:
		_run_belt(delta)
	if flicker_tube != null:
		_flicker(delta)


func _tick_clock() -> void:
	var now: Dictionary = Time.get_time_dict_from_system()
	var minutes: float = float(now.minute) + float(now.second) / 60.0
	clock_minute.rotation.z = -TAU * minutes / 60.0
	clock_hour.rotation.z = -TAU * (float(int(now.hour) % 12) + minutes / 60.0) / 12.0


func _run_belt(delta: float) -> void:
	belt_material.uv1_offset.x = fmod(belt_material.uv1_offset.x - delta * BELT_SPEED, 1.0)
	for box: Node3D in belt_boxes:
		box.position.x += delta * BELT_SPEED
		if box.position.x > Layout.CONVEYOR_END_X - 0.2:
			box.position.x -= Layout.CONVEYOR_END_X - Layout.CONVEYOR_START_X


## Short stutters most of the time, now and then a few steady seconds.
func _flicker(delta: float) -> void:
	_flicker_time -= delta
	if _flicker_time > 0.0:
		return
	flicker_tube.visible = not flicker_tube.visible or randf() < 0.3
	_flicker_time = randf_range(0.03, 0.12) if randf() < 0.7 else randf_range(1.5, 5.0)
