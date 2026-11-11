extends SceneTree
## S-311.89: the existing keyboard/gamepad ping wheel exposes an emote page,
## radial selection maps to the eight authored clips, the owner plays the
## choice, movement cancels it, and anim_clip remains the replicated contract.

const PLAYER_SCENE: PackedScene = preload("res://scenes/gameplay/player/player.tscn")
const PingWheelScript = preload("res://scripts/ui/ping_wheel.gd")
const EmoteCatalogData = preload("res://scripts/core/emote_catalog.gd")
const PadBindingData = preload("res://scripts/core/pad_binding.gd")

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_check_catalog()
	await _check_wheel()
	await _check_player_playback()
	if _failures == 0:
		print("PASS: keyboard/gamepad radial emotes select and replicate exact gel clips")
	quit(_failures)


func _check_catalog() -> void:
	_expect(EmoteCatalogData.OPTIONS.size() == 8, "the emote page has the eight S-311.86 clips")
	_expect(EmoteCatalogData.clips() == PlayerAnimator.EMOTE_CLIPS,
		"the radial catalog and animator accept exactly the same clips")
	for option: Dictionary in EmoteCatalogData.OPTIONS:
		var clip: StringName = option["clip"] as StringName
		_expect(not EmoteCatalogData.display_text(clip).is_empty(), "%s has a translated radial label" % clip)
		_expect(EmoteCatalogData.lock_msec(clip) >= 1800, "%s keeps its authored one-shot duration" % clip)
	var settings: Node = root.get_node(^"/root/GameSettings")
	_expect(int(settings.call(&"bound_key", &"ui_ping")) != KEY_NONE
			and PadBindingData.default_code(&"ui_ping") == "b11",
		"the shared wheel opens from a keyboard binding and D-pad up")
	var switch_events: Array[InputEvent] = InputMap.action_get_events(&"look_center")
	_expect(switch_events.any(func(event: InputEvent) -> bool:
		return event is InputEventKey and (event as InputEventKey).physical_keycode == KEY_C)
		and switch_events.any(func(event: InputEvent) -> bool:
			return event is InputEventJoypadButton and (event as InputEventJoypadButton).button_index == 8),
		"the page switch is available on keyboard C and gamepad R3")


func _check_wheel() -> void:
	var wheel: PingWheel = PingWheelScript.new()
	root.add_child(wheel)
	await process_frame
	wheel.show_wheel()
	_expect(not wheel.is_emote_page() and wheel.selected_label() == "¡Cuidado!",
		"the shared wheel still opens on its quick-ping page")
	wheel.toggle_page()
	_expect(wheel.is_emote_page() and wheel.selected_clip() == &"Wave",
		"C / R3 changes to emotes with Wave at the safe default sector")
	wheel.select_from_vector(Vector2.RIGHT * 100.0)
	_expect(wheel.selected_clip() == &"Facepalm", "right stick right selects Facepalm")
	wheel.select_from_vector(Vector2.DOWN * 100.0)
	_expect(wheel.selected_clip() == &"Point", "right stick down selects Point")
	wheel.select_from_vector(Vector2.LEFT * 100.0)
	_expect(wheel.selected_clip() == &"MeltAndReturn", "right stick left selects MeltAndReturn")
	wheel.free()


func _check_player_playback() -> void:
	var player: Player = PLAYER_SCENE.instantiate()
	player.name = "Player_1"
	root.add_child(player)
	await process_frame
	var radial: Object = player.get(&"_ping_input") as Object
	_expect(radial.call(&"handle_event", _action(&"ui_ping", true)),
		"pressing the shared wheel action is consumed")
	radial.call(&"update", 0.3)
	_expect(bool(radial.get(&"wheel_open")), "holding the keyboard/gamepad action opens the radial")
	_expect(radial.call(&"handle_event", _action(&"look_center", true)),
		"C / R3 switches the open radial to emotes")
	_expect(radial.call(&"handle_event", _action(&"ui_ping", false)),
		"releasing the keyboard/gamepad action confirms the emote")
	player.animator.animate()
	_expect(player.anim_state == &"Wave" and player.anim_clip == &"Wave",
		"the selected emote becomes the replicated state and exact clip")
	_expect(player.animator.anim_player != null
			and StringName(player.animator.anim_player.current_animation) == &"Wave",
		"the owner's visible gel plays the chosen emote")
	var sync := player.get_node(^"MultiplayerSynchronizer") as MultiplayerSynchronizer
	var clip_path := NodePath(".:anim_clip")
	_expect(sync.replication_config.has_property(clip_path)
			and sync.replication_config.property_get_spawn(clip_path)
			and sync.replication_config.property_get_replication_mode(clip_path)
			== SceneReplicationConfig.REPLICATION_MODE_ON_CHANGE,
		"anim_clip sends the wheel choice to peers and late joiners without a new RPC")
	player.animator.update_movement(1.0, 2.0)
	player.animator.animate()
	_expect(player.anim_state == Player.ANIM_IDLE and player.anim_clip == Player.ANIM_IDLE,
		"walking cancels a planted emote instead of sliding its pose")
	_expect(not player.animator.play_emote(&"NotAnEmote"), "unknown clips cannot enter replicated emote state")
	player.free()


func _action(action: StringName, pressed: bool) -> InputEventAction:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = pressed
	return event


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1
