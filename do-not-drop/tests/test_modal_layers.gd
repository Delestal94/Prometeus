extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_modal_layers.gd
##
## N-237: nothing of the dashboard may paint over a modal.
## - The care card and the depot practice card ("Cómo cuidar la carga") live in
##   player_cargo_care.gd's own CanvasLayer, which must sit under the HUD's
##   CanvasLayer (hud.gd): Options, pause/results, the depot and crew panels are
##   all children of the HUD, so they then paint over both cards.
## - With Options open, the modals really are inside the HUD layer.

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var profile: Node = root.get_node(^"/root/UnlockManager")
	var seen_before: Dictionary = profile.seen_tips.duplicate(true)
	# A profile that has not done the practice yet, so its card exists.
	profile.seen_tips.erase(&"care_practice")
	var level: Node = load("res://scenes/gameplay/level_base.tscn").instantiate()
	root.add_child(level)
	current_scene = level
	for _i in range(6):
		await process_frame
	var hud: CanvasLayer = level.get_node("HUD")
	var care: Node = null
	for candidate: Node in get_nodes_in_group(&"player"):
		for child: Node in candidate.get_children():
			if &"practice" in child:
				care = child
	_expect(care != null, "The local player has its care controller")
	if care == null:
		_finish(level, profile, seen_before)
		return
	var practice: Control = care.get(&"practice")
	var card: Control = care.get(&"card")
	_expect(practice != null, "A profile without the practice gets its card")

	var card_layer: CanvasLayer = _layer_of(card)
	_expect(card_layer != null and card_layer.layer < hud.layer,
		"The care card's layer is under the HUD's (card %s, HUD %d)" % [
			card_layer.layer if card_layer != null else -1, hud.layer])
	_expect(practice != null and _layer_of(practice) == card_layer,
		"The practice card shares the care card's layer")

	hud.get(&"pause").open_options()
	await process_frame
	var options: Control = hud.get(&"options_panel")
	_expect(options.visible, "Options opened")
	_expect(_layer_of(options) == hud, "Options is drawn by the HUD's layer")
	for modal: Control in [hud.get(&"overlay"), hud.get(&"depot_panel"), hud.get(&"crew_panel")]:
		_expect(_layer_of(modal) == hud, "%s is drawn by the HUD's layer" % modal.name)
	_finish(level, profile, seen_before)


func _finish(level: Node, profile: Node, seen_before: Dictionary) -> void:
	profile.seen_tips = seen_before
	level.queue_free()
	await process_frame
	if _failures == 0:
		print("PASS: care and practice cards paint under the HUD's modals")
	quit(_failures)


func _layer_of(node: Node) -> CanvasLayer:
	var current: Node = node
	while current != null:
		if current is CanvasLayer:
			return current as CanvasLayer
		current = current.get_parent()
	return null


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("FAIL: " + message)
		print("FAIL: " + message)
