extends "res://tests/sim_trap_balance.gd"
## Run: Godot --headless --path do-not-drop --script res://tests/test_box_trap_levels.gd
##
## The packing level reaches the trap (expansion D-0710.b, box_trap.gd, PackageRescue.trap_config(),
## ITrapBehavior.severity):
## - BoxTrap.severity: low, mid and high are CompanyTuning.TRAP_SEVERITY_*, rising, low is 1; an
##   unknown level is low; the plan carries the severity of its level;
## - a bare glass box (high) built by BoxToPackage with its order sets its Fragile up at the high
##   severity once in the tree, and a heavy hit costs that much more than in a padded one (low, 1);
##   a box with no plan rides at 1; a repaired box (PackageRescue.complete_care_tool) keeps it;
## - CompanyPackages.make (box_sealed on every peer) puts the severity of the host's intensity's level
##   in the plan;
## - every one of the 7 real traps, left alone through the same 20 s of tilt and bumps, keeps less
##   integrity at the high severity than at low, and at 1 it is exactly the trap without the key;
## - severity scales the harm and never the answer: a running step costs severity times as much in the 6
##   traps it touches (Growing Weight ignores it at any severity), so do a wrong key (Explosive) and a
##   wrong answer (Hostile), and the right answer does the same at 1 and at high in all 7 (leaning back,
##   the code, the cushion's share, the sequence, soothing, scrubbing, calming);
## - D-0710.b's bar on the recorded drives (sim_trap_balance.gd's harness, fewer trials than its
##   `--levels` report): more boxes lost at high than at low in at least 5 of the 7 traps.

const VASE: ProductDefinition = preload("res://data/products/porcelain_vase.tres")
const TEST_TRIALS: int = 2
const NEGLECT_SECONDS: float = 20.0
const NEGLECT_TILT_DEG: float = 20.0
const NEGLECT_BUMP: float = 8.0
const TICK: float = 1.0 / 60.0
const CARRIED_STEPS: int = 5
## Half a second of ticks: Hostile's wrong answer lands once and its passive anger runs on (attack cooldown 0.8 s).
const ANSWER_TICKS: int = 30
## Where a trap with a meter is left before it is answered.
const ANSWER_FROM: float = 50.0

var _failures: int = 0


func _initialize() -> void:
	_run_test.call_deferred()


func _run_test() -> void:
	_test_severity_table()
	await _test_packages()
	_test_company_make()
	_test_neglect()
	_test_steps()
	_test_mistakes()
	_test_answers()
	_test_drives()
	if _failures == 0:
		print("PASS: the packing level sets how hard the trap hits, and the drives lose more boxes at high")
	quit(_failures)


func _test_severity_table() -> void:
	var low: float = BoxTrap.severity(BoxTrap.LEVEL_LOW)
	var mid: float = BoxTrap.severity(BoxTrap.LEVEL_MID)
	var high: float = BoxTrap.severity(BoxTrap.LEVEL_HIGH)
	_expect(is_equal_approx(low, 1.0), "Low is the trap as it is (got %.2f)" % low)
	_expect(low < mid and mid < high, "Severity rises low < mid < high (got %.2f, %.2f, %.2f)" % [low, mid, high])
	_expect(is_equal_approx(BoxTrap.severity(&"nonsense"), low), "An unknown level is low")
	var order: Dictionary = _order()
	var bare: Dictionary = BoxTrap.plan(_box(0), order, {&"porcelain_vase": VASE})
	_expect(bare.get("level") == BoxTrap.LEVEL_HIGH and is_equal_approx(bare.get("severity", -1.0), high),
		"Bare glass plans high at the high severity (got %s, %s)" % [bare.get("level"), bare.get("severity")])


func _test_packages() -> void:
	var holder := Node3D.new()
	root.add_child(holder)
	var products: Dictionary = {&"porcelain_vase": VASE}
	var bare: DeliveryPackage = BoxToPackage.build(_box(0), products, _order())
	var padded: DeliveryPackage = BoxToPackage.build(_box(19), products, _order())
	var plain: DeliveryPackage = BoxToPackage.build(_box(0), products)
	for package: DeliveryPackage in [bare, padded, plain]:
		holder.add_child(package)
	await process_frame
	var high: float = BoxTrap.severity(BoxTrap.LEVEL_HIGH)
	_expect(is_equal_approx(bare.trap_behavior.severity, high),
		"Bare glass's Fragile rides at the high severity (got %.2f)" % bare.trap_behavior.severity)
	_expect(is_equal_approx(padded.trap_behavior.severity, 1.0),
		"Padded glass's rides at 1 (got %.2f)" % padded.trap_behavior.severity)
	_expect(is_equal_approx(plain.trap_behavior.severity, 1.0),
		"A box with no plan rides at 1 (got %.2f)" % plain.trap_behavior.severity)
	var heavy: float = float(bare.trap_definition.params["impact_damage_heavy"])
	var bare_lost: float = bare.trap_behavior.on_impact(NEGLECT_BUMP)
	var padded_lost: float = padded.trap_behavior.on_impact(NEGLECT_BUMP)
	_expect(is_equal_approx(padded_lost, heavy) and is_equal_approx(bare_lost, heavy * high),
		"A heavy hit costs %.1f padded and %.1f bare (got %.1f and %.1f)"
		% [heavy, heavy * high, padded_lost, bare_lost])
	PackageRescue.complete_care_tool(bare, &"repair")
	_expect(is_equal_approx(bare.trap_behavior.severity, high),
		"A repaired box keeps its severity (got %.2f)" % bare.trap_behavior.severity)
	holder.free()


func _test_company_make() -> void:
	var holder := Node3D.new()
	root.add_child(holder)
	var packages := CompanyPackages.new()
	packages.parent = holder
	var data: Dictionary = {"node_name": "Package_box_9", "package_id": &"box_9", "trap": &"fragile",
		"trap_intensity": 0.5, "absorption": 1.0, "quality": 50.0, "pos": Vector3.ZERO, "basis": Basis.IDENTITY}
	var package: DeliveryPackage = packages.make(_box(0), data)
	var plan: Dictionary = package.get_meta(BoxToPackage.META_TRAP_PLAN, {}) if package != null else {}
	_expect(plan.get("level") == BoxTrap.LEVEL_HIGH
		and is_equal_approx(plan.get("severity", -1.0), BoxTrap.severity(BoxTrap.LEVEL_HIGH)),
		"box_sealed's intensity 0.5 makes a high plan at the high severity (got %s)" % plan)
	if package != null:
		package.free()
	holder.free()


## The same 20 s for every trap with nobody answering it: the box tilted past every safe angle (under
## Balance's danger one) and a bump past every threshold each second.
func _test_neglect() -> void:
	var high: float = BoxTrap.severity(BoxTrap.LEVEL_HIGH)
	for definition: TrapDefinition in _load_traps():
		var bare: float = _neglect(definition, -1.0)
		var low: float = _neglect(definition, 1.0)
		var harsh: float = _neglect(definition, high)
		_expect(is_equal_approx(bare, low), "%s at 1 is the trap without the key (%.1f vs %.1f)"
			% [definition.id, low, bare])
		_expect(harsh < low, "%s left alone keeps less at high than at low (%.1f vs %.1f)"
			% [definition.id, harsh, low])


## Integrity summed over the scenario's frames (0 once ruined); severity < 0 leaves the key out.
func _neglect(definition: TrapDefinition, severity: float) -> float:
	var body := RigidBody3D.new()
	body.mass = 8.0
	root.add_child(body)
	body.transform = Transform3D(Basis(Vector3.FORWARD, deg_to_rad(NEGLECT_TILT_DEG)), Vector3.ZERO)
	var behavior := definition.create_behavior() as ITrapBehavior
	var config: Dictionary = definition.params.duplicate(true)
	config["roll_seed"] = 7
	if severity >= 0.0:
		config["severity"] = severity
	behavior.on_setup(body, config)
	var dt: float = 1.0 / 60.0
	var frames: int = roundi(NEGLECT_SECONDS / dt)
	var area: float = 0.0
	for frame: int in range(frames):
		if frame % 60 == 30:
			behavior.on_impact(NEGLECT_BUMP)
		behavior.on_physics_process(body, dt, {"input": {}, "truck_right": Vector3.RIGHT})
		if behavior.get_state() == ITrapBehavior.TrapState.RUINED:
			break
		area += behavior.integrity
	body.free()
	return area


## A running step in the arms (N-115), on each trap's own failure axis.
func _test_steps() -> void:
	var high: float = BoxTrap.severity(BoxTrap.LEVEL_HIGH)
	for definition: TrapDefinition in _load_traps():
		var low_trap: ITrapBehavior = _trap(definition, 1.0)
		var high_trap: ITrapBehavior = _trap(definition, high)
		for _step: int in range(CARRIED_STEPS):
			low_trap.on_carried_step(1.0)
			high_trap.on_carried_step(1.0)
		var at_low: float = _harm(low_trap)
		var at_high: float = _harm(high_trap)
		if definition.id == &"growing_weight":
			_expect(is_zero_approx(at_low) and is_zero_approx(at_high),
				"Running with a growing weight shakes nothing (got %.2f, %.2f)" % [at_low, at_high])
			continue
		_expect(at_low > 0.0 and is_equal_approx(at_high, at_low * high),
			"%s: running steps cost %.2f at high, %.2f times the %.2f at 1 (got %.2f)"
			% [definition.id, at_low * high, high, at_low, at_high])


func _test_mistakes() -> void:
	var high: float = BoxTrap.severity(BoxTrap.LEVEL_HIGH)
	for definition: TrapDefinition in _load_traps():
		if definition.id != &"explosive" and definition.id != &"hostile":
			continue
		var at_low: float = _harm(_mistaken(definition, 1.0))
		var at_high: float = _harm(_mistaken(definition, high))
		_expect(at_low > 0.0 and is_equal_approx(at_high, at_low * high),
			"%s: a wrong answer costs %.2f at high, %.2f times the %.2f at 1 (got %.2f)"
			% [definition.id, at_low * high, high, at_low, at_high])


## Explosive: a wrong key, in a tick with no time in it. Hostile: no hands on it while it asks for them.
func _mistaken(definition: TrapDefinition, severity: float) -> ITrapBehavior:
	var trap: ITrapBehavior = _trap(definition, severity, {"sequence": [&"up", &"down", &"left"]})
	if trap is ExplosiveTrapBehavior:
		trap.on_physics_process(null, 0.0, {"input": {"direction_pressed": &"right"}})
		return trap
	for _tick: int in range(ANSWER_TICKS):
		trap.on_physics_process(null, TICK, {"input": {}})
	return trap


func _test_answers() -> void:
	var high: float = BoxTrap.severity(BoxTrap.LEVEL_HIGH)
	var answers: Dictionary = {&"balance": _lean_back, &"explosive": _key_code, &"fragile": _cushion,
		&"growing_weight": _secure, &"hostile": _soothe, &"liquid": _scrub, &"noisy": _calm}
	for definition: TrapDefinition in _load_traps():
		var answer: Callable = answers[definition.id]
		var at_low: float = answer.call(definition, 1.0)
		var at_high: float = answer.call(definition, high)
		_expect(at_low > 0.0 and is_equal_approx(at_low, at_high),
			"%s: the right answer does the same at high as at 1 (%.3f vs %.3f)" % [definition.id, at_high, at_low])


## Degrees of tilt taken back by holding on.
func _lean_back(definition: TrapDefinition, severity: float) -> float:
	var body := RigidBody3D.new()
	root.add_child(body)
	body.transform = Transform3D(Basis(Vector3.FORWARD, deg_to_rad(NEGLECT_TILT_DEG)), Vector3.ZERO)
	var trap := _trap(definition, severity, {}, body) as BalanceTrapBehavior
	for _tick: int in range(ANSWER_TICKS):
		trap.on_physics_process(body, TICK, {"input": {"steady": true}, "truck_right": Vector3.RIGHT})
	body.free()
	return NEGLECT_TILT_DEG - trap.tilt_degrees


## The keys the code took to defuse it (0 if it did not).
func _key_code(definition: TrapDefinition, severity: float) -> float:
	var trap := _trap(definition, severity) as ExplosiveTrapBehavior
	var code: Array[StringName] = trap.sequence.duplicate()
	for key: StringName in code:
		trap.on_physics_process(null, TICK, {"input": {"direction_pressed": key}})
	return float(code.size()) if int(trap.sequence_state()["solved"]) == 1 else 0.0


## The share of an announced heavy hit that gets through a tap in time.
func _cushion(definition: TrapDefinition, severity: float) -> float:
	var trap := _trap(definition, severity) as FragileTrapBehavior
	var bare: float = _trap(definition, severity).on_impact(NEGLECT_BUMP)
	trap.on_physics_process(null, TICK, {"impact_ahead": 0.1, "input": {"tap": true}})
	return trap.on_impact(NEGLECT_BUMP) / bare


## The keys the sequence took to bring the mass back to 1 (0 if it did not).
func _secure(definition: TrapDefinition, severity: float) -> float:
	var trap := _trap(definition, severity) as GrowingWeightTrapBehavior
	trap.mass_multiplier = 2.0
	var keys: Array[StringName] = trap.sequence.duplicate()
	for key: StringName in keys:
		trap.press_direction(key)
	return float(keys.size()) if is_equal_approx(trap.mass_multiplier, 1.0) else 0.0


## Aggression taken off with the hands it asks for.
func _soothe(definition: TrapDefinition, severity: float) -> float:
	var trap := _trap(definition, severity) as HostileTrapBehavior
	trap.aggression = ANSWER_FROM
	var input: Dictionary = {"calm_strength": float(definition.params["calm_strength_required"])}
	for _tick: int in range(ANSWER_TICKS):
		trap.on_physics_process(null, TICK, {"input": input})
	return ANSWER_FROM - trap.aggression


## Spill dried by a scrub, one swing every 0.1 s.
func _scrub(definition: TrapDefinition, severity: float) -> float:
	var trap := _trap(definition, severity) as LiquidTrapBehavior
	trap.spill_amount = ANSWER_FROM
	for swing: int in range(6):
		var side: StringName = &"left" if swing % 2 == 0 else &"right"
		trap.on_physics_process(null, 0.1, {"input": {"direction_pressed": side}})
	return ANSWER_FROM - trap.spill_amount


## Agitation taken off by calming it.
func _calm(definition: TrapDefinition, severity: float) -> float:
	var trap := _trap(definition, severity) as NoisyTrapBehavior
	trap.agitation = ANSWER_FROM
	for _tick: int in range(ANSWER_TICKS):
		trap.on_physics_process(null, TICK, {"input": {"calm": true}})
	return ANSWER_FROM - trap.agitation


func _trap(definition: TrapDefinition, severity: float, config_extra: Dictionary = {},
		body: Node = null) -> ITrapBehavior:
	var trap := definition.create_behavior() as ITrapBehavior
	var config: Dictionary = definition.params.duplicate(true)
	config.merge(config_extra, true)
	config["roll_seed"] = 7
	config["severity"] = severity
	trap.on_setup(body, config)
	return trap


## How far along its own failure axis the trap has gone.
func _harm(trap: ITrapBehavior) -> float:
	if trap is ExplosiveTrapBehavior:
		var bomb := trap as ExplosiveTrapBehavior
		return bomb._countdown_total - bomb.seconds_left
	if trap is HostileTrapBehavior:
		return (trap as HostileTrapBehavior).aggression
	if trap is NoisyTrapBehavior:
		return (trap as NoisyTrapBehavior).agitation
	if trap is LiquidTrapBehavior:
		return (trap as LiquidTrapBehavior).spill_amount
	if trap is GrowingWeightTrapBehavior:
		return (trap as GrowingWeightTrapBehavior).mass_multiplier - 1.0
	return trap.integrity_max - trap.integrity


func _test_drives() -> void:
	var drives: Array[Dictionary] = _load_drives()
	var traps: Array[TrapDefinition] = _load_traps()
	_expect(drives.size() == 5 and traps.size() == 7,
		"The harness has its 5 drives and 7 traps (got %d and %d)" % [drives.size(), traps.size()])
	var levels: Array[StringName] = [BoxTrap.LEVEL_LOW, BoxTrap.LEVEL_HIGH]
	var ruins: Dictionary = level_ruins(traps, drives, TEST_TRIALS, levels)
	var harsher: Array[String] = harsher_at_high(ruins)
	_expect(harsher.size() >= LEVEL_TRAPS_REQUIRED,
		"More boxes lost at high than at low in at least %d of 7 traps (got %d: %s; ruins %s)"
		% [LEVEL_TRAPS_REQUIRED, harsher.size(), harsher, ruins])


func _order() -> Dictionary:
	return {"id": &"o1", "items": [{"product": &"porcelain_vase", "qty": 1}], "requirements": []}


func _box(padding: int) -> PackedBox:
	var box := PackedBox.new(&"M")
	box.place(VASE, Vector3i.ZERO)
	box.fill_free_cells(padding)
	box.taped = true
	box.label_order_id = &"o1"
	return box


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1
