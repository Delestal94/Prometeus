extends "res://tests/sim_trap_balance.gd"
## Run: Godot --headless --path do-not-drop --script res://tests/test_box_trap_levels.gd
##
## The packing level reaches the trap (expansion D-0710.b, box_trap.gd, package.gd trap_config(),
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
## - D-0710.b's bar on the recorded drives (sim_trap_balance.gd's harness, fewer trials than its
##   `--levels` report): more boxes lost at high than at low in at least 5 of the 7 traps.

const VASE: ProductDefinition = preload("res://data/products/porcelain_vase.tres")
const TEST_TRIALS: int = 2
const NEGLECT_SECONDS: float = 20.0
const NEGLECT_TILT_DEG: float = 20.0
const NEGLECT_BUMP: float = 8.0

var _failures: int = 0


func _initialize() -> void:
	_run_test.call_deferred()


func _run_test() -> void:
	_test_severity_table()
	await _test_packages()
	_test_company_make()
	_test_neglect()
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
