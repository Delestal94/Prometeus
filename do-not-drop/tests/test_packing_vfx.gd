extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_packing_vfx.gd
##
## The packing table's effects (packing_vfx.gd), checked on their nodes (no screenshot):
## - D-1914, order completed: a box sealed for its order and packed well (trap intensity under
##   CompanyTuning.TRAP_INTENSITY_MID) plays a confetti burst (a one-shot CPUParticles3D, emitting, BURST_AMOUNT
##   quads) and a rising "✓" at the table's spot; a box without an order, a badly packed one or another event
##   plays nothing of it;
## - every effect is gone after EFFECT_SECONDS, and no more than MAX_EFFECTS live at once;
## - add_to() follows CompanyNet.event_applied, and CompanyUi adds it.

var _failures: int = 0


class FakeNet:
	extends Node
	signal event_applied(seq: int, kind: StringName, data: Dictionary)


class FakeRoot:
	extends Node3D
	var net: Node = null


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_test_choice()
	await _test_done()
	_test_wiring()
	if _failures == 0:
		print("PASS: a well packed box for its order bursts in confetti over its table, and the effects clean up")
	quit(_failures)


func _sealed(order: String, intensity: float) -> Dictionary:
	return {"order": StringName(order), "trap_intensity": intensity, "pos": Vector3(2.0, 0.0, -3.0)}


func _test_choice() -> void:
	_expect(PackingVfx.effect_for(_sealed("d1_o02", 0.0)) == PackingVfx.KIND_DONE, "a perfect box for its order")
	_expect(PackingVfx.effect_for(_sealed("", 0.0)) != PackingVfx.KIND_DONE, "no order: no confetti")
	_expect(PackingVfx.effect_for(_sealed("d1_o02", CompanyTuning.TRAP_INTENSITY_MID)) != PackingVfx.KIND_DONE,
		"a box packed under par: no confetti")


func _test_done() -> void:
	var fake_root := FakeRoot.new()
	var net := FakeNet.new()
	fake_root.net = net
	fake_root.add_child(net)
	root.add_child(fake_root)
	var vfx: PackingVfx = PackingVfx.add_to(fake_root)
	await process_frame
	net.event_applied.emit(1, &"box_placed", {"pos": Vector3.ZERO})
	net.event_applied.emit(2, CompanyTableNet.SEALED, _sealed("", 0.0))
	_expect(vfx.live().is_empty(), "other events and a box without order play nothing")
	net.event_applied.emit(3, CompanyTableNet.SEALED, _sealed("d1_o02", 0.02))
	_expect(vfx.live().size() == 1, "the completed order plays one effect")
	var effect: Node3D = vfx.live()[0] if not vfx.live().is_empty() else null
	if effect != null:
		_expect(effect.global_position.is_equal_approx(Vector3(2.0, 0.0, -3.0)), "at the table's spot")
		var burst := effect.get_node_or_null(^"Burst") as CPUParticles3D
		_expect(burst != null and burst.one_shot and burst.emitting and burst.amount == PackingVfx.BURST_AMOUNT,
			"a one-shot confetti burst")
		var mark := effect.get_node_or_null(^"Mark") as Label3D
		_expect(mark != null and mark.text == PackingVfx.DONE_MARK and mark.modulate.g > mark.modulate.r,
			"a green check")
		var start_y: float = mark.position.y if mark != null else 0.0
		await create_timer(PackingVfx.EFFECT_SECONDS * 0.5).timeout
		_expect(mark != null and mark.position.y > start_y and mark.modulate.a < 1.0, "the check rises and fades")
	for i: int in PackingVfx.MAX_EFFECTS + 3:
		net.event_applied.emit(10 + i, CompanyTableNet.SEALED, _sealed("d1_o%02d" % i, 0.0))
	_expect(vfx.live().size() == PackingVfx.MAX_EFFECTS, "at most %d at once (got %d)"
		% [PackingVfx.MAX_EFFECTS, vfx.live().size()])
	await create_timer(PackingVfx.EFFECT_SECONDS + 0.2).timeout
	await process_frame
	_expect(vfx.live().is_empty() and vfx.get_child_count() == 0, "every effect is gone after EFFECT_SECONDS")
	fake_root.queue_free()
	await process_frame


func _test_wiring() -> void:
	var ui_source: String = FileAccess.get_file_as_string("res://scripts/ui/company_ui.gd")
	_expect(ui_source.contains("PackingVfx.add_to(root)"), "CompanyUi adds the packing effects")


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error("FAIL: " + description)
		_failures += 1
