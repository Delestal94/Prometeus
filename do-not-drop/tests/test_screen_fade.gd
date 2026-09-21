extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_screen_fade.gd
## Covers items #62 (seat transition) and #77 (restart) of
## docs/especificaciones-visuales.md: both used to be a hard, instant cut.
## Both now route through the same EventBus.quick_fade_requested ->
## prototype_hud.gd mechanism, covered here directly rather than through
## the full board_seat()/restart_delivery() call chains (already exercised
## by test_interaction.gd and test_loading_flow.gd).

var _failures: int = 0


func _initialize() -> void:
	await process_frame
	var bus: Node = root.get_node(^"/root/EventBus")
	var hud: CanvasLayer = load("res://scripts/ui/prototype_hud.gd").new()
	root.add_child(hud)
	await process_frame

	_expect(is_equal_approx(hud.fade_rect.color.a, 0.0), "Starts fully transparent, no fade visible at rest")

	bus.emit_signal(&"quick_fade_requested", 0.2)
	var peaked: bool = false
	for _i: int in range(30):  # 0.5s of frames, comfortably past the 0.2s total
		await process_frame
		if hud.fade_rect.color.a > 0.5:
			peaked = true
	_expect(peaked, "The fade actually goes dark at some point, not just a no-op tween")

	for _i: int in range(30):
		await process_frame
	_expect(is_equal_approx(hud.fade_rect.color.a, 0.0), "Fades back to fully transparent on its own afterward")

	hud.free()

	# board_seat() itself (level_base.gd's own player) requesting the fade
	# is covered end to end by test_interaction.gd's board_seat assertions
	# not needing changes here -- this only needed to prove the mechanism
	# those calls rely on actually works.

	if _failures == 0:
		print("PASS: the screen fade goes dark and recovers on its own")
	quit(_failures)


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1
