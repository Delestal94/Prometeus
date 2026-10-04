extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://modules/character_step/tests/test_character_step.gd
## character_step.gd: capsule climbs a 16 cm curb without jumping, respects
## its height limit, walls and headroom, never steps in the air or during a
## jump, and preserves the speed and height of ordinary flat-ground walking.

const STEP := preload("res://modules/character_step/character_step.gd")
const SPEED: float = 3.6
var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var curb: Dictionary = await _walk(.16)
	_expect(
		curb.position.x > 1.5 and absf(curb.position.y - .16) < .02 and curb.steps > 0,
		"Capsule climbs a 16 cm vertical curb (got %s, %d steps)" % [curb.position, curb.steps]
	)
	for height: float in [.24, 2.0]:
		var blocked: Dictionary = await _walk(height)
		_expect(
			blocked.position.x < 0 and blocked.steps == 0,
			(
				"Obstacles taller than the limit stop walking (height %s, got %s)"
				% [height, blocked.position]
			)
		)
	var ceiling: Dictionary = await _walk(.16, true)
	_expect(
		ceiling.position.x < 0 and ceiling.steps == 0,
		"Low headroom blocks climbing without pushing into the ceiling (got %s)" % ceiling.position
	)
	var falling: Dictionary = await _walk(.16, false, true)
	_expect(falling.steps == 0, "An airborne body never steps (got %d)" % falling.steps)
	var jumping: Dictionary = await _walk(.16, false, false, true)
	_expect(
		jumping.steps == 0, "A requested jump never gets a step correction (got %d)" % jumping.steps
	)
	var flat: Dictionary = await _walk(0)
	_expect(
		absf(flat.position.x - 2.6) < .03 and absf(flat.position.y) < .02 and flat.steps == 0,
		"Flat walking preserves 3.6 m/s and floor height (got %s)" % flat.position
	)
	if _failures == 0:
		print(
			"PASS: character step clears low curbs and respects walls, ceilings, air and normal walking"
		)
	quit(_failures)


func _walk(
	height: float, ceiling: bool = false, air: bool = false, jump: bool = false
) -> Dictionary:
	var world := Node3D.new()
	root.add_child(world)
	_box(world, Vector3(12, .5, 6), Vector3(0, -.25, 0))
	if height > 0:
		_box(world, Vector3(4, height, 6), Vector3(2, height * .5, 0))
	if ceiling:
		_box(world, Vector3(12, .2, 6), Vector3(0, 1.9, 0))
	var body := CharacterBody3D.new()
	var collision := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = .35
	capsule.height = 1.7
	collision.shape = capsule
	collision.position.y = .85
	body.add_child(collision)
	body.position = Vector3(-1, .01, 0)
	world.add_child(body)
	for tick: int in range(5):
		await physics_frame
		body.velocity = Vector3(0, -.3, 0)
		body.move_and_slide()
	_expect(body.is_on_floor(), "Fixture starts on its floor (got %s)" % body.position)
	if air:
		body.position = Vector3(-.4, .4, 0)
		body.velocity = Vector3.ZERO
		body.move_and_slide()
	var steps: int = 0
	var ticks: int = 1 if air or jump else 60
	if jump:
		body.position.x = -.31
	for tick: int in range(ticks):
		await physics_frame
		body.velocity = Vector3(SPEED, 4.0 if jump else -.2, 0)
		if STEP.move_and_slide(body, 1.0 / Engine.physics_ticks_per_second):
			steps += 1
	var result: Dictionary = {"position": body.global_position, "steps": steps}
	world.queue_free()
	await process_frame
	return result


func _box(parent: Node3D, size: Vector3, at: Vector3) -> void:
	var body := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	body.position = at
	body.add_child(collision)
	parent.add_child(body)


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1
