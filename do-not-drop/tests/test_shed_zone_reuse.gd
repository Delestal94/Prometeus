extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_shed_zone_reuse.gd
##
## The shed's painted zones reuse the depot's look instead of keeping their own copy (expansion
## D-0918, DepotLayout and DepotLabels):
## - every zone colour of CompanyShed is a colour of the depot's palette (DepotLayout);
## - every role with a name has a translation key and a colour;
## - the zone names drawn on the floor are DepotLabels.floor_text labels: the depot's display
##   font, paper colour, lying flat, just above the painted patch.

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var state: Node = root.get_node_or_null(^"CompanyState")
	if state == null or state.get_script() == null:
		push_error("CompanyState autoload missing")
		quit(1)
		return
	_check_palette()
	await _check_labels(state)
	if _failures == 0:
		print("PASS: the shed's zones use the depot's palette and floor labels")
	quit(_failures)


func _check_palette() -> void:
	var depot_colors: Array[Color] = [DepotLayout.LANE_YELLOW, DepotLayout.TEAL, DepotLayout.WALK_GREEN,
		DepotLayout.SHELVES_BLUE, DepotLayout.WORKSHOP_RED, DepotLayout.OFFICE_ORANGE]
	for role: StringName in CompanyShed.ZONE_KEYS:
		_expect(CompanyShed.ZONE_COLORS.has(role), "%s has a colour" % role)
		_expect(CompanyShed.ZONE_COLORS.get(role, Color.BLACK) in depot_colors,
			"%s's colour is from the depot's palette" % role)


func _check_labels(state: Node) -> void:
	state.call(&"new_company", "Zone Co")
	var shed := CompanyShed.new()
	root.add_child(shed)
	await process_frame
	shed.rebuild(state, Inventory.new())
	var seen: int = 0
	for child: Node in shed.get_children():
		if not String(child.name).begins_with("Zone_"):
			continue
		seen += 1
		var label := child as Label3D
		_expect(label != null, "%s is a Label3D" % child.name)
		if label == null:
			continue
		_expect(label.font == DepotLayout.DISPLAY_FONT, "%s uses the depot's display font" % child.name)
		_expect(label.modulate == DepotLayout.PAPER, "%s is paper coloured" % child.name)
		_expect(label.position.y > CompanyShed.PATCH_HEIGHT, "%s sits above the painted patch" % child.name)
		_expect(absf(label.basis.y.dot(Vector3.UP)) < 0.01, "%s lies flat on the floor" % child.name)
	_expect(seen >= 2, "the dock and the exit are named (%d zone labels)" % seen)
	shed.queue_free()
	await process_frame


func _expect(cond: bool, msg: String) -> void:
	if not cond:
		_failures += 1
		push_error("FAIL: " + msg)
