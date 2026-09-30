extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_ruin_feedback.gd
## Covers the "momento clipeable" from docs/requerimientos-tecnicos.md 3.4: a
## ruined package bursts into a one-shot GPUParticles3D burst instead of just
## changing color (S-310: a Frágil box breaks into RuinShards porcelain, the
## other traps have their own effect, see test_ruin_effects.gd; the 15 % hold,
## position and cleanup are shared by all of them). Regression coverage for a real bug found while
## building this: setting global_position on a Node3D before it's inside the
## tree silently no-ops in Godot (get_global_transform requires is_inside_tree()),
## which made the very first version of this scatter confetti at the origin
## instead of at the package -- and crashed outright when the package's own
## parent wasn't in the tree yet (test_multi_cargo.gd caught that one).

const PACKAGE_SCENE: PackedScene = preload("res://scenes/gameplay/package/package.tscn")

var _failures: int = 0


func _initialize() -> void:
	await process_frame
	var settings: Node = root.get_node(^"/root/GameSettings")
	var original_impact_effects: bool = bool(settings.get(&"impact_effects"))
	settings.set(&"impact_effects", true)
	var time_scale_before: float = Engine.time_scale
	# apply_impact() only does anything to a package that's actually inside
	# the tree once RunManager says a run is in progress -- see
	# Package._is_run_active(). test_fragile.gd sidesteps this by never
	# adding the package to a tree at all; this test needs the confetti's
	# own container lookup (get_tree().current_scene), so it can't.
	var run_manager: Node = root.get_node(^"/root/RunManager")
	run_manager.call(&"start_run")

	var package: RigidBody3D = PACKAGE_SCENE.instantiate()
	root.add_child(package)
	package.global_position = Vector3(3.0, 0.0, -8.0)
	# Frozen: this test only cares about a fixed reference position for the
	# burst, not real physics. Left unfrozen, gravity can nudge it during the
	# await below -- how much depends on whether a physics tick happens to
	# land inside that one process_frame, which is exactly non-deterministic
	# enough to make this assertion flaky (caught by running it repeatedly,
	# ~1 in 5 failures even before any of this file's other changes).
	package.freeze = true
	await process_frame
	package.call(&"initialize_trap")

	_expect(_count_particles() == 0, "No burst before anything goes wrong")

	# Fragile's default thresholds ruin it well before the fifth hit (see
	# test_fragile.gd for the exact curve); a few big hits is enough here.
	for _i in range(5):
		package.call(&"apply_impact", 7.0)
	# Broken opens a rescue; the burst is for a box actually lost.
	package.call(&"mark_lost", "Se perdió en el rescate.")
	_expect(int(package.get(&"trap_state")) == 2, "Package actually reached RUINED")

	var bursts: Array[GPUParticles3D] = _find_particles()
	_expect(bursts.size() == 1, "Exactly one confetti burst spawned (got %d)" % bursts.size())
	var feedback: Node = package.get_node(^"PackageFeedbackComponent")
	# The comic ruin stinger (test_audio_polish) replaced the old low thud.
	var ruin_sound := feedback.get(&"_ruin_player") as AudioStreamPlayer3D
	_expect(ruin_sound != null and ruin_sound.playing, "Ruin plays its comic stinger with the visual hold")
	if not bursts.is_empty():
		var burst: GPUParticles3D = bursts[0]
		_expect(burst.global_position.is_equal_approx(Vector3(3.0, 0.0, -8.0)),
			"Burst spawns at the package's actual position, not the world origin")
		_expect(burst.one_shot, "Never loops -- it's a one-time punctuation, not ambient VFX")
		_expect(burst.emitting, "Starts emitting immediately, no delay")
		_expect(is_equal_approx(burst.speed_scale, 0.15),
			"Ruin confetti starts at 15% speed for the local freeze-frame")
		_expect(is_equal_approx(Engine.time_scale, time_scale_before),
			"The ruin effect never changes Engine.time_scale")
		for _i in range(30):
			await physics_frame
		_expect(is_equal_approx(burst.speed_scale, 1.0),
			"Confetti returns to full speed after the 0.35 s hold")

	package.free()
	await process_frame

	# one_shot particles free themselves once the burst (lifetime + a settle
	# margin) finishes, so the scene doesn't accumulate dead nodes over a run
	# full of ruined packages.
	for _i in range(180):  # 3s of physics frames at 60Hz, comfortably past CONFETTI_LIFETIME
		await physics_frame
		if _count_particles() == 0:
			break
	_expect(_count_particles() == 0, "The burst frees itself once it finishes, it isn't left behind")
	settings.set(&"impact_effects", original_impact_effects)

	if _failures == 0:
		print("PASS: a ruined package bursts into confetti at its own position, once, and cleans up after itself")
	quit(_failures)


func _count_particles() -> int:
	return _find_particles().size()


func _find_particles() -> Array[GPUParticles3D]:
	var found: Array[GPUParticles3D] = []
	for child: Node in root.get_children():
		if child is GPUParticles3D:
			found.append(child)
	return found


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1
