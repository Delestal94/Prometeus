extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_vfx_vision.gd
##
## The expansion's effects never cover the view (D-1943), measured from the player's camera instead of a capture:
## eyes at EYE_M (player.tscn's Head) and the camera's vertical field of view FOV_DEG, at 16:9.
## - The packing table's marks ("✓" / "✗", PackingVfx) stay under MARK_MAX of the screen's height at arm's length
##   (ARM_M) and start over the eyes, so they never sit across the middle of the view;
## - its particles (confetti, the red puff) cover under PARTICLES_MAX of the screen at arm's length, every quad at
##   its biggest;
## - the arrows over the stations (ShedIndicators) stay under ARROW_MAX of the screen's height from NEAR_M and their
##   lowest point (bobbing down) stays over the eyes.
## How they look still needs a person (D-1945).

const EYE_M: float = 1.6
const FOV_DEG: float = 78.0
const ASPECT: float = 16.0 / 9.0
const ARM_M: float = 1.2
const NEAR_M: float = 2.0
const MARK_MAX: float = 0.15
const ARROW_MAX: float = 0.20
const PARTICLES_MAX: float = 0.05

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var vfx := PackingVfx.new()
	root.add_child(vfx)
	await process_frame
	for kind: StringName in [PackingVfx.KIND_DONE, PackingVfx.KIND_ERROR]:
		var effect: Node3D = vfx.play(kind, Vector3.ZERO)
		var mark := effect.get_node(^"Mark") as Label3D
		var tall: float = _text_height(mark)
		_expect(tall / _view_height(ARM_M) <= MARK_MAX, "%s mark: %.0f%% of the screen at arm's length"
			% [kind, 100.0 * tall / _view_height(ARM_M)])
		_expect(mark.position.y - tall * 0.5 > EYE_M, "%s mark starts over the eyes (bottom %.2f m)"
			% [kind, mark.position.y - tall * 0.5])
		var burst := effect.get_node(^"Burst") as CPUParticles3D
		var quad: Vector2 = (burst.mesh as QuadMesh).size * burst.scale_amount_max
		var covered: float = burst.amount * quad.x * quad.y / (_view_height(ARM_M) * _view_height(ARM_M) * ASPECT)
		_expect(covered <= PARTICLES_MAX, "%s particles cover %.1f%% of the screen" % [kind, 100.0 * covered])
	vfx.queue_free()
	var marks := ShedIndicators.new()
	marks.pieces_of = func() -> Array: return [{"uid": &"t", "id": &"table"}]
	marks.role_of = func(_id: StringName) -> StringName: return &"dispatch"
	marks.orders_of = func() -> Array: return [{"due_min": 0}]
	marks.minute_of = func() -> float: return 10.0
	root.add_child(marks)
	await process_frame
	marks.set_process(false)
	marks.refresh()
	var arrow := marks.get_node(^"Need_t") as Label3D
	var arrow_tall: float = _text_height(arrow)
	_expect(arrow_tall / _view_height(NEAR_M) <= ARROW_MAX, "the arrow is %.0f%% of the screen from %.0f m"
		% [100.0 * arrow_tall / _view_height(NEAR_M), NEAR_M])
	var lowest: float = ShedIndicators.HEIGHT_M - ShedIndicators.BOB_M - arrow_tall * 0.5
	_expect(lowest > EYE_M, "the arrow's lowest point is over the eyes (%.2f m)" % lowest)
	marks.queue_free()
	await process_frame
	if _failures == 0:
		print("PASS: the marks, particles and arrows stay small and over the eyes: the view stays clear")
	quit(_failures)


## The height a Label3D's text takes in metres: its lines at font size times pixel size.
static func _text_height(label: Label3D) -> float:
	return float(label.text.count("\n") + 1) * label.font_size * label.pixel_size


## The height of the view at `distance` metres.
static func _view_height(distance: float) -> float:
	return 2.0 * distance * tan(deg_to_rad(FOV_DEG) * 0.5)


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error("FAIL: " + description)
		_failures += 1
