extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_company_care_publish.gd
##
## A company box publishes its care_state every CompanyTuning.CARE_PUBLISH_SEC (BoxToPackage.tune(),
## D-2002.4), a delivery's every PackageRescue.CARE_PUBLISH_SEC; what the hands answer to still goes
## out on the next tick (package_rescue.gd _publish_hand_change(), PackageRescue.care_signature()):
## - a company box waits 0.2 s, a delivery box 0.1 s;
## - the bomb's code: a step taken, a mistake, defused, each forces the publish; its seconds running
##   down don't;
## - the growing weight's sequence solved forces it;
## - the balance's push: changing side (or letting go) forces it, the same side pushed harder doesn't;
## - a box whose trap publishes none of these never forces one.

const PACKAGE_SCENE: PackedScene = preload("res://scenes/gameplay/package/package.tscn")
const TRAPS: String = "res://data/traps/%s.tres"

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var company := _box(&"explosive")
	BoxToPackage.tune(company)
	var delivery := _box(&"explosive")
	_expect(is_equal_approx(PackageRescue.care_publish_interval(company), CompanyTuning.CARE_PUBLISH_SEC)
		and is_equal_approx(PackageRescue.care_publish_interval(delivery), PackageRescue.CARE_PUBLISH_SEC),
		"A company box publishes every %.2f s, a delivery box every %.2f s" % [
			PackageRescue.care_publish_interval(company), PackageRescue.care_publish_interval(delivery)])
	var bomb: Object = company.trap_behavior
	bomb.set(&"seconds_left", 10.0)
	_expect(not _forced(company), "Nothing the hands answer to changed: no publish forced")
	bomb.set(&"seconds_left", 9.5)
	_expect(not _forced(company), "The bomb's seconds running down wait for the next publish")
	bomb.set(&"sequence_index", int(bomb.get(&"sequence_index")) + 1)
	_expect(_forced(company), "A step of the bomb's code taken goes out on the next tick")
	bomb.set(&"_mistakes", 1)
	_expect(_forced(company), "A mistake on the bomb's code goes out on the next tick")
	bomb.set(&"_defused", true)
	_expect(_forced(company), "The bomb defused goes out on the next tick")

	var weight := _box(&"growing_weight")
	BoxToPackage.tune(weight)
	_forced(weight)
	if not (weight.trap_behavior.sequence_state() as Dictionary).is_empty():
		weight.trap_behavior.set(&"_solved", int(weight.trap_behavior.get(&"_solved")) + 1)
		_expect(_forced(weight), "The growing weight's sequence solved goes out on the next tick")
	else:
		_expect(false, "The growing weight publishes a sequence")

	var balance := _box(&"balance")
	BoxToPackage.tune(balance)
	balance.trap_behavior.set(&"_push", 0.3)
	_forced(balance)
	balance.trap_behavior.set(&"_push", 0.9)
	_expect(not _forced(balance), "The balance pushed harder to the same side waits for the next publish")
	balance.trap_behavior.set(&"_push", -0.4)
	_expect(_forced(balance), "The balance pushed to the other side goes out on the next tick")
	balance.trap_behavior.set(&"_push", 0.0)
	_expect(_forced(balance), "Letting go of the balance goes out on the next tick")

	var plain := _box(&"noisy")
	BoxToPackage.tune(plain)
	if PackageRescue.care_signature(plain.trap_behavior) == 0:
		_expect(not _forced(plain), "A trap with no cushion, sequence or gesture never forces a publish")
	for box: Node in [company, delivery, weight, balance, plain]:
		box.queue_free()
	await process_frame
	if _failures == 0:
		print("PASS: a company box publishes its care every 0.2 s and what the hands answer to at once")
	quit(_failures)


func _box(trap: StringName) -> DeliveryPackage:
	var box := PACKAGE_SCENE.instantiate() as DeliveryPackage
	box.trap_definition = load(TRAPS % trap) as TrapDefinition
	box.freeze = true
	root.add_child(box)
	box.set_physics_process(false)
	box._cushion_signature = PackageRescue.care_signature(box.trap_behavior)
	return box


## Whether the hands' check forces the publish on this tick (the publish timer pushed to its interval).
func _forced(box: DeliveryPackage) -> bool:
	box._care_publish_time = 0.0
	PackageRescue._publish_hand_change(box)
	return box._care_publish_time >= PackageRescue.care_publish_interval(box)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("FAIL: " + message)
