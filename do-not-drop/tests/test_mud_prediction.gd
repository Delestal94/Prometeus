extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_mud_prediction.gd
## The mud and the truck a client predicts (N-218, N-922.6; mud_segment.gd _drag_truck, _hold_predicted_truck).
## The copy the client at the wheel simulates gets the mud's forces from the state the host replicates, as the host's
## truck does, or it sits still while the host's is shoved and hauled out and is dragged after it by corrections:
##   - bogged, nobody pushing: held still;
##   - bogged with the two pushers the host counts (`pushers`): shoved forward along the truck;
##   - hauled by the strap (`haul_method`): along the road at the strap's speed;
##   - past the pit (HAUL_PAST_PIT, where the host ends the haul): let go.
## The segment's own tick (the host's) is off: only the client's hold runs, on the van as its predicted copy.

const TICK: float = 1.0 / 60.0

var _failures: int = 0
var _segment: MudSegment
var _van: VehicleBody3D


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var manager: Node = root.get_node(^"/root/RunManager")
	manager.set(&"is_running", true)
	_build_arena()
	await physics_frame
	_segment.set_physics_process(false)
	_van.set_meta(&"keep_awake", true)
	await _check_pushed()
	await _check_hauled()
	_segment._apply_state(MudSegment.State.IDLE, 1.0, 0, false, 0.0, &"strap", 0.0)
	_van.set_meta(&"keep_awake", false)
	manager.set(&"is_running", false)
	if _failures == 0:
		print("PASS: the predicted truck is held, shoved and hauled by the mud as the host's is")
	quit(_failures)


## A flat world with a MudSegment at the origin (road along -Z) and the real van.
func _build_arena() -> void:
	var world := Node3D.new()
	root.add_child(world)
	var ground := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(60.0, 1.0, 200.0)
	shape.shape = box
	shape.position = Vector3(0.0, -0.5, 0.0)
	ground.add_child(shape)
	world.add_child(ground)
	_segment = MudSegment.new()
	_segment.crane_delay = 1000.0
	world.add_child(_segment)
	_van = (load("res://scenes/gameplay/vehicle/vehicle.tscn") as PackedScene).instantiate() as VehicleBody3D
	_van.position = Vector3(0.0, 0.8, 40.0)
	world.add_child(_van)


func _check_pushed() -> void:
	_put_van(_segment.pit_start + 2.0)
	var moved: Array[float] = []
	for crew: int in [0, 2]:
		_segment._apply_state(MudSegment.State.BOGGED, 0.0, crew, false, 1000.0, &"", 0.0)
		for _i: int in range(30):
			await _hold_tick()
		var from: float = _along()
		for _i: int in range(120):
			await _hold_tick()
		moved.append(_along() - from)
	print("bogged copy: alone %.3f m, two pushers %.3f m in 2 s" % [moved[0], moved[1]])
	_expect(absf(moved[0]) < 0.05, "The predicted copy, bogged with nobody pushing, sits still (%.2f m)" % moved[0])
	_expect(moved[1] > 0.1, "...and the two pushers the host counts shove it forward (%.2f m in 2 s)" % moved[1])


func _check_hauled() -> void:
	_segment._apply_state(MudSegment.State.HAULING, 1.0, 0, false, 0.0, &"strap", 0.0)
	var road: Vector3 = _segment.global_basis * Vector3.FORWARD
	var fastest: float = 0.0
	for _i: int in range(90):
		await _hold_tick()
		fastest = maxf(fastest, _van.linear_velocity.dot(road))
	var strap_speed: float = float(MudSegment.HAUL_SPEEDS[&"strap"])
	print("hauled copy: %.2f m/s (strap %.1f)" % [fastest, strap_speed])
	_expect(fastest > 0.8 * strap_speed and fastest < 1.2 * strap_speed,
		"The strap hauls the copy along the road at its speed (%.1f m/s of %.1f)" % [fastest, strap_speed])
	_put_van(_segment.pit_end + MudSegment.HAUL_PAST_PIT + 2.0)
	for _i: int in range(60):
		await _hold_tick()
	_expect(_van.linear_velocity.length() < 1.0,
		"...and lets go of it past the pit, where the host ends the haul (%.2f m/s)" % _van.linear_velocity.length())


## The van at rest `along` metres into the segment.
func _put_van(along: float) -> void:
	_van.global_position = _segment.to_global(Vector3(0.0, 0.8, -along))
	_van.global_basis = _segment.global_basis
	_van.linear_velocity = Vector3.ZERO
	_van.angular_velocity = Vector3.ZERO
	_van.reset_physics_interpolation()


## How far into the segment the van is (m).
func _along() -> float:
	return -_segment.to_local(_van.global_position).z


## One physics tick of the client's hold on its predicted copy, nobody at the pedals.
func _hold_tick() -> void:
	_van.set_controls(0.0, 0.0, false)
	_segment._hold_predicted_truck(TICK)
	await physics_frame


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1
