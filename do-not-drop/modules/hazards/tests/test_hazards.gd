extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://modules/hazards/tests/test_hazards.gd
##
## The hazards module on its own (docs/modulos.md), with a behavior defined
## here: a TrapDefinition creates one behavior instance per object, each
## with its own integrity from the params; its name travels as the name key
## (or the display name); content is picked deterministically per object
## id; ITrapBehavior's damage() clamps and reports the real loss, milestones
## are queued once and taken once, and its hint renders through LocText.

var _failures: int = 0


class WobbleBehavior extends ITrapBehavior:
	var wobble: float = 0.0

	func on_setup(package: Node, config: Dictionary) -> void:
		super(package, config)
		wobble = float(config.get("wobble", 1.0))

	func on_impact(delta_velocity: float) -> float:
		var lost: float = damage(delta_velocity * wobble)
		if lost > 0.0:
			_add_milestone(&"took_a_hit")
		return lost

	func get_state() -> int:
		if integrity <= 0.0:
			return TrapState.RUINED
		return TrapState.AT_RISK if integrity < integrity_max * 0.5 else TrapState.OK

	func hint_text() -> Array:
		return LocText.make("%s: %d%%", ["Steady", int(integrity)])


func _initialize() -> void:
	var definition := TrapDefinition.new()
	definition.id = &"wobble"
	definition.display_name = "Wobbly"
	definition.behavior_script = WobbleBehavior
	definition.params = {"integrity_max": 40.0, "wobble": 2.0}
	_expect(definition.name_key() == "Wobbly", "Without a key the display name travels")
	definition.translation_key = "HAZARD_WOBBLE"
	_expect(definition.name_key() == "HAZARD_WOBBLE" and definition.localized_name() == "HAZARD_WOBBLE",
		"The name key travels and is translated where shown (got %s)" % definition.localized_name())
	var one: ITrapBehavior = definition.create_behavior()
	var two: ITrapBehavior = definition.create_behavior()
	_expect(one != null and two != null and one != two, "Every object gets its own behavior instance")
	one.on_setup(null, definition.params)
	two.on_setup(null, definition.params)
	_expect(is_equal_approx(one.integrity_max, 40.0) and is_equal_approx(one.integrity, 40.0),
		"Setup takes the params' integrity")
	_expect(one.get_state() == ITrapBehavior.TrapState.OK, "A fresh hazard is fine")
	var lost: float = one.on_impact(15.0)
	_expect(is_equal_approx(lost, 30.0) and is_equal_approx(one.integrity, 10.0),
		"An impact costs integrity by the params (lost %.1f)" % lost)
	_expect(one.get_state() == ITrapBehavior.TrapState.AT_RISK and two.get_state() == ITrapBehavior.TrapState.OK,
		"One object's damage never touches another's")
	_expect(is_equal_approx(one.on_impact(100.0), 10.0) and is_zero_approx(one.integrity),
		"Damage clamps at zero and reports the real loss")
	_expect(one.get_state() == ITrapBehavior.TrapState.RUINED, "At zero it's ruined")
	_expect(is_zero_approx(one.damage(-5.0)), "Negative damage does nothing")
	_expect(one.take_milestones() == [&"took_a_hit"], "A milestone is queued once however many times it happened")
	_expect(one.take_milestones().is_empty(), "Milestones are taken once")
	_expect(one.get_hint() == "Steady: 0%", "The hint renders through LocText (got %s)" % one.get_hint())
	var contents: Array[Resource] = [Resource.new(), Resource.new(), Resource.new()]
	definition.contents = contents
	var first_pick: Resource = definition.pick_content(&"box_7")
	_expect(first_pick == definition.pick_content(&"box_7"),
		"Content is deterministic per object id")
	var picks: Dictionary = {}
	for index: int in range(30):
		picks[definition.pick_content(StringName("box_%d" % index))] = true
	_expect(picks.size() > 1, "Different objects get different contents")
	var empty := TrapDefinition.new()
	_expect(empty.pick_content(&"x") == null, "No contents, no pick")
	if _failures == 0:
		print("PASS: hazard definitions and behaviors work on the module alone")
	quit(_failures)


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1
