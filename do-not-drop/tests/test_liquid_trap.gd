extends SceneTree

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var behavior := preload("res://scripts/gameplay/traps/liquid_trap_behavior.gd").new()
	var package := Node3D.new()
	root.add_child(package)
	await process_frame
	behavior.on_setup(package, {
		"integrity_max": 100.0, "safe_angle": 10.0, "danger_angle": 24.0,
		"leak_per_second": 8.0, "surge_per_second": 26.0, "impact_threshold": 4.0,
		"impact_spill": 18.0, "mop_rate": 25.0, "integrity_loss_per_spill": 0.25,
	})
	package.rotation_degrees.z = 20.0
	for i: int in 20:
		behavior.on_physics_process(package, 0.1, {"input": {}})
	assert(behavior.spill_amount > 0.0, "Inclinar una carga líquida debe crear derrame")
	var before_mop: float = behavior.spill_amount
	for i: int in 5:
		behavior.on_physics_process(package, 0.1, {"input": {"calm": true}})
	assert(behavior.spill_amount < before_mop, "Mantener la acción debe secar el charco")
	var before_impact: float = behavior.spill_amount
	behavior.on_impact(8.0)
	assert(behavior.spill_amount > before_impact, "Un golpe fuerte debe provocar un derrame súbito")
	for i: int in 80:
		behavior.on_physics_process(package, 0.1, {"input": {}})
	assert(behavior.integrity < behavior.integrity_max, "Un derrame desatendido debe causar daño permanente")
	assert(behavior.get_state() != ITrapBehavior.TrapState.OK, "Un charco grande debe comunicar riesgo")
	package.free()
	print("PASS: liquid trap leaks on tilt/impact, can be mopped, and damages when ignored.")
	quit(0)
