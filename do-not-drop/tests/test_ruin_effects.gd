extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_ruin_effects.gd
## S-310: every trap has its own "it broke" moment (package_ruin_effects.gd), all
## presentation-only and local. For each of the seven traps this emits the
## relayed package_ruined signal for a frozen package and checks that: the trap's
## own effect nodes appear at the package's position (Frágil RuinShards, Líquido
## RuinSplash + RuinPuddle, Explosivo RuinSmoke, Ruidoso/Hostil RuinCritter,
## Equilibrio RuinTower, Peso creciente RuinDust); the generic confetti is not
## spawned on top; particles start in the 15 % freeze-frame and return to full
## speed after 0.35 s when impact effects are on (and never slow when off);
## Engine.time_scale is untouched; and the effect frees itself within the promised
## time (< 2 s, the critter's 3 s run <= 3.5 s). A trap the effects do not know keeps
## the generic confetti. The critter must really move away from the box.

const PACKAGE_SCENE: PackedScene = preload("res://scenes/gameplay/package/package.tscn")
const ORIGIN: Vector3 = Vector3(3.0, 0.5, -8.0)
## Real seconds an effect may live (its effect time + the freeze-frame's ~0.3 s) plus slack.
const REGULAR_LIMIT: float = 2.1
const CRITTER_LIMIT: float = 3.6
const UNKNOWN_TRAP: StringName = &"mystery"

## trap id -> [name of the effect's root, names of the nodes it must contain, real-time limit]
const CASES: Dictionary = {
	&"fragile": ["RuinShards", [], REGULAR_LIMIT],
	&"liquid": ["RuinLiquid", ["RuinSplash", "RuinPuddle"], REGULAR_LIMIT],
	&"explosive": ["RuinBlast", ["RuinSmoke", "RuinBlastConfetti"], REGULAR_LIMIT],
	&"noisy": ["RuinCritter", ["Ear", "Eye"], CRITTER_LIMIT],
	&"hostile": ["RuinCritter", ["Ear", "Eye"], CRITTER_LIMIT],
	&"balance": ["RuinTower", ["TowerCrate"], REGULAR_LIMIT],
	&"growing_weight": ["RuinDust", ["RuinDustRing", "RuinDustPuffs"], REGULAR_LIMIT],
}

var _failures: int = 0


func _initialize() -> void:
	await process_frame
	var settings: Node = root.get_node(^"/root/GameSettings")
	var original_impact_effects: bool = bool(settings.get(&"impact_effects"))
	var time_scale_before: float = Engine.time_scale
	root.get_node(^"/root/RunManager").call(&"start_run")

	settings.set(&"impact_effects", true)
	for trap_id: StringName in CASES:
		await _check_trap(trap_id, true)
		_expect(is_equal_approx(Engine.time_scale, time_scale_before), "%s: Engine.time_scale untouched" % trap_id)

	# Effects off: still visible, but no freeze-frame.
	settings.set(&"impact_effects", false)
	await _check_trap(&"liquid", false)
	await _check_trap(&"fragile", false)

	settings.set(&"impact_effects", true)
	await _check_generic_fallback()
	await _check_squash()
	settings.set(&"impact_effects", original_impact_effects)

	if _failures == 0:
		print("PASS: each trap ruins with its own effect, at the box, slowed then normal, and frees itself in time")
	quit(_failures)


func _spawn_package(trap_id: StringName) -> RigidBody3D:
	var package: RigidBody3D = PACKAGE_SCENE.instantiate()
	if trap_id == UNKNOWN_TRAP:
		# A trap the effects do not know: fragile's definition under another id.
		var definition: Resource = (load("res://data/traps/fragile.tres") as Resource).duplicate()
		definition.set(&"id", UNKNOWN_TRAP)
		package.set(&"trap_definition", definition)
	else:
		package.set(&"trap_definition", load("res://data/traps/%s.tres" % trap_id))
	root.add_child(package)
	package.global_position = ORIGIN
	# Frozen: a fixed reference position, no dependency on physics ticks.
	package.freeze = true
	await process_frame
	await process_frame
	if trap_id != UNKNOWN_TRAP:
		package.call(&"initialize_trap")
	return package


func _ruin(package: RigidBody3D) -> void:
	root.get_node(^"/root/EventBus").emit_signal(&"package_ruined", package.get(&"package_id"), "test")


func _check_trap(trap_id: StringName, slow: bool) -> void:
	var label: String = "%s%s" % [trap_id, "" if slow else " (effects off)"]
	var case: Array = CASES[trap_id]
	var package: RigidBody3D = await _spawn_package(trap_id)
	_expect(_ruin_roots().is_empty(), "%s: no ruin effect before anything goes wrong" % label)
	_ruin(package)
	var started: int = Time.get_ticks_msec()

	var effect: Node3D = _find_effect(String(case[0]))
	_expect(effect != null, "%s: its own effect %s appears" % [label, case[0]])
	if effect == null:
		package.free()
		return
	_expect(effect.global_position.is_equal_approx(ORIGIN), "%s: effect spawns at the package" % label)
	_expect(effect.top_level, "%s: effect is top_level, not parented to the box" % label)
	for part: String in case[1]:
		_expect(effect.find_child("*%s*" % part, true, false) != null, "%s: effect has %s" % [label, part])
	_expect(_ruin_roots().size() == 1, "%s: only its own effect spawns (got %d)" % [label, _ruin_roots().size()])
	_expect(_find_generic_confetti() == null, "%s: no generic confetti on top" % label)
	var budget: int = 0
	for particles: GPUParticles3D in _particles_of(effect):
		budget += particles.amount
		_expect(particles.one_shot and particles.emitting,
			"%s: %s is a one-shot, emitting now" % [label, particles.name])
		var expected_scale: float = 0.15 if slow else 1.0
		_expect(is_equal_approx(particles.speed_scale, expected_scale),
			"%s: %s starts at speed %.2f" % [label, particles.name, expected_scale])
	_expect(budget <= 40, "%s: particle budget %d <= 40" % [label, budget])

	var critter_start: Vector3 = _critter_position(effect)
	for _i in range(30):
		await physics_frame
	for particles: GPUParticles3D in _particles_of(effect):
		_expect(is_equal_approx(particles.speed_scale, 1.0),
			"%s: %s back to full speed after the hold" % [label, particles.name])

	if case[0] == "RuinCritter":
		for _i in range(30):
			await physics_frame
		_expect(is_instance_valid(effect), "%s: the animal is still running after a second" % label)
		if is_instance_valid(effect):
			_expect(_critter_position(effect).distance_to(critter_start) > 0.5,
				"%s: the animal ran away from the box" % label)

	# The whole thing frees itself, well before the promised limit.
	var limit: float = case[2]
	while is_instance_valid(effect) and not effect.is_queued_for_deletion() \
			and float(Time.get_ticks_msec() - started) / 1000.0 < limit + 0.5:
		await process_frame
	var elapsed: float = float(Time.get_ticks_msec() - started) / 1000.0
	_expect(not is_instance_valid(effect) or effect.is_queued_for_deletion(), "%s: the effect frees itself" % label)
	_expect(elapsed <= limit, "%s: gone in %.2f s (limit %.1f s)" % [label, elapsed, limit])
	package.free()
	await process_frame
	await process_frame
	_expect(_ruin_roots().is_empty() and _find_generic_confetti() == null, "%s: nothing left in the tree" % label)


## A trap without its own effect: the old confetti burst is still there.
func _check_generic_fallback() -> void:
	var package: RigidBody3D = await _spawn_package(UNKNOWN_TRAP)
	_ruin(package)
	_expect(_ruin_roots().is_empty(), "Unknown trap: no per-trap effect")
	_expect(_find_generic_confetti() != null, "Unknown trap: falls back to the generic confetti")
	package.free()
	for _i in range(200):
		await physics_frame
		if _find_generic_confetti() == null:
			break
	_expect(_find_generic_confetti() == null, "The generic confetti frees itself too")


## Peso creciente also squashes the box (the settle bounce), without touching the simulation.
func _check_squash() -> void:
	var package: RigidBody3D = await _spawn_package(&"growing_weight")
	var feedback: Node = package.get_node(^"PackageFeedbackComponent")
	_expect(float(feedback.get(&"_bounce_time")) < 0.0, "Growing weight: no squash before the ruin")
	var frozen_before: bool = package.freeze
	_ruin(package)
	_expect(float(feedback.get(&"_bounce_time")) >= 0.0, "Growing weight: the box squashes on the thud")
	_expect(package.freeze == frozen_before, "The squash never touches the package's physics")
	package.free()
	await process_frame


func _ruin_roots() -> Array[Node]:
	var found: Array[Node] = []
	for child: Node in root.get_children():
		if String(child.name).contains("Ruin") and child is Node3D and not String(child.name).contains("Confetti"):
			found.append(child)
	return found


func _find_effect(effect_name: String) -> Node3D:
	for child: Node in root.get_children():
		if String(child.name).contains(effect_name):
			return child as Node3D
	return null


func _find_generic_confetti() -> GPUParticles3D:
	for child: Node in root.get_children():
		var node_name: String = String(child.name)
		if child is GPUParticles3D and (node_name.contains("RuinConfetti") or node_name.contains("ConfettiBurst")):
			return child
	return null


func _particles_of(effect: Node) -> Array[GPUParticles3D]:
	var found: Array[GPUParticles3D] = []
	if effect is GPUParticles3D:
		found.append(effect)
	for node: Node in effect.find_children("*", "GPUParticles3D", true, false):
		found.append(node as GPUParticles3D)
	return found


func _critter_position(effect: Node) -> Vector3:
	var pivot: Node3D = effect.get_node_or_null(^"CritterPivot") as Node3D
	return pivot.position if pivot != null else Vector3.ZERO


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1
