class_name HudPrompts
extends Node
## Context-sensitive teaching: interaction/lid prompts, role hints, the
## keyboard/gamepad cheat sheet and sound subtitles.

const SubtitleQueue = preload("res://scripts/ui/hud/sound_subtitle_queue.gd")
const ControlHints = preload("res://scripts/ui/control_hints.gd")

## Set by Hud before this is added as its child.
var hud: Hud
## The session under this level ended (the host left, N-222; HudPause sets
## it). Offline now, this peer would pass for a host that can restart, and a
## restart would reload a solo world, not the crew's.
var session_lost: bool = false
var in_delivery: bool = false
var _lid_action: String = ""
var _lid_inside: String = ""
var _carrying: bool = false
var _shortcut_learning_seconds: float = 0.0
var _hint_override: String = ""
var _hint_override_seconds: float = 0.0
var _hint_shown_text: String = ""
var _hint_shown_color: Color = Color(0.0, 0.0, 0.0, 0.0)
var _sound_subtitle: String = ""
## The subtitles that come and go with the world's sounds (N-965): horn,
## doorbell and the customer, animals, rain. The trap's standing one above stays
## apart, on top.
var _subtitles := SubtitleQueue.new()
var _role: int = Hud.Role.ON_FOOT


func _ready() -> void:
	EventBus.package_damaged.connect(_on_damage)
	EventBus.delivery_status_changed.connect(_on_delivery)
	EventBus.interaction_prompt_changed.connect(_on_interaction_prompt)
	EventBus.carry_changed.connect(_on_carry_changed)
	EventBus.package_lid_hint_changed.connect(_on_lid_hint_changed)
	EventBus.tutorial_tip_requested.connect(_on_tutorial_tip_requested)
	EventBus.horn_honked.connect(_on_horn_honked)
	EventBus.house_delivery_recorded.connect(_on_house_delivery_subtitle)
	EventBus.house_refused_package.connect(_on_house_refused_subtitle)
	EventBus.cargo_animal_alert.connect(_on_animal_subtitle)
	EventBus.cargo_animal_ended.connect(_on_animal_ended_subtitle)
	EventBus.run_started.connect(_on_run_started_subtitle)


func refresh_shortcuts(delta: float = 0.0) -> void:
	if hud.shortcut_label == null:
		return
	var pill: Control = hud.shortcut_label.get_parent() as Control
	if hud.overlay_mode in ["preparation", "run"] and not get_tree().paused:
		_shortcut_learning_seconds += delta
	var visible_now: bool = false
	match GameSettings.control_help_mode:
		GameSettings.ControlHelp.ALWAYS:
			visible_now = true
		GameSettings.ControlHelp.BEGINNING:
			visible_now = int(UnlockManager.completed_runs) < 3 \
				and _shortcut_learning_seconds < Hud.SHORTCUT_VISIBLE_SECONDS
		GameSettings.ControlHelp.NEVER:
			visible_now = false
	pill.visible = visible_now
	pill.modulate.a = 1.0


func refresh_shortcut_text() -> void:
	# At most four shortcuts, picked by what the player is doing (N-977.1); the rest
	# live in the pause menu and the phone. Ping, phone and look back follow the
	# player's bindings (N-966.4); pause and restart are not rebindable.
	var ping: String = ControlHints.hint("HUD_KEY_PING", [&"ui_ping"], "HUD_PAD_PING", [&"ui_ping"])
	var phone: String = ControlHints.hint("HUD_KEY_PHONE", [&"phone_toggle"], "HUD_PAD_PHONE", [&"phone_toggle"])
	var pause: String = hud.key_hint(tr("HUD_KEY_PAUSE"), tr("HUD_PAD_PAUSE"))
	var items: PackedStringArray = []
	if _role == Hud.Role.DRIVER:
		items.append(hud.key_hint(tr("HUD_KEY_LOOK_BACK") % GameSettings.binding_label(&"look_back"), tr("HUD_PAD_LOOK_BACK")))
		items.append(ping)
	else:
		items.append(phone)
		items.append(ping)
	items.append(pause)
	# Only while the depot is open: it is the one place the crew panel shows.
	if hud.overlay_mode == "preparation":
		items.append(ControlHints.hint("HUD_KEY_CREW", [&"crew_panel"], "HUD_PAD_CREW", [&"crew_panel"]))
	elif can_restart() and items.size() < 4:
		items.append(hud.key_hint(tr("HUD_KEY_RESTART"), tr("HUD_PAD_RESTART")))
	hud.shortcut_label.text = UiTheme.keycaps("   ·   ".join(items), true)


func can_restart() -> bool:
	return not session_lost and (not NetworkManager.is_online() or NetworkManager.is_host())


func refresh_role() -> void:
	var role: int = _local_role()
	if role == _role:
		return
	_role = role
	if hud.shortcut_label != null:
		refresh_shortcut_text()


func _local_role() -> int:
	var level: Node = hud.get_parent()
	if level == null:
		return Hud.Role.ON_FOOT
	var player: Variant = level.get(&"local_player")
	if not is_instance_valid(player):
		return Hud.Role.ON_FOOT
	var seat: String = String((player as Node).get(&"seat_node_path"))
	if seat.is_empty():
		return Hud.Role.ON_FOOT
	return Hud.Role.DRIVER if seat.contains("DriverEyePoint") else Hud.Role.PASSENGER


func _flash_hint(text: String, seconds: float) -> void:
	_hint_override = text
	_hint_override_seconds = seconds


func _on_tutorial_tip_requested(text: String) -> void:
	_flash_hint(text, 6.0)


func refresh_hint(delta: float) -> void:
	if _hint_override_seconds > 0.0:
		_hint_override_seconds -= delta
		_show_hint("[b]%s[/b]" % _hint_override, Hud.YELLOW)
		return
	# On the dark controls pill (Hud._build_bottom_bar()).
	_show_hint(UiTheme.keycaps(_base_hint(), true), Hud.PAPER)


## Writes the hint only when it changed: every text or theme-override write
## re-parses the BBCode and relayouts the pill, and this runs every frame
## (S-208: 0.28 of the HUD's 0.37 ms per frame in the depot).
func _show_hint(bbcode: String, color: Color) -> void:
	if bbcode != _hint_shown_text:
		_hint_shown_text = bbcode
		hud.hint_label.text = bbcode
	if color != _hint_shown_color:
		_hint_shown_color = color
		hud.hint_label.add_theme_color_override("default_color", color)


func _base_hint() -> String:
	var waiting: bool = not RunManager.is_running and RunManager.results.is_empty()
	var walk: StringName = ControlHints.WALK
	var accelerate_brake: Array[StringName] = [&"drive_accelerate", &"drive_brake"]
	var steer: Array[StringName] = [&"drive_left", &"drive_right"]
	match _role:
		Hud.Role.DRIVER:
			if waiting:
				return tr("HUD_NO_CARGO_YET") % GameSettings.binding_label(&"interact")
			return ControlHints.hint(
				"HUD_KEYS_DRIVER",
				[accelerate_brake, steer, &"drive_handbrake", &"drive_horn", &"interact"],
				"HUD_PAD_DRIVER",
				[&"drive_accelerate", &"drive_brake", steer, &"drive_handbrake", &"drive_horn",
				&"interact"])
		Hud.Role.PASSENGER:
			return ControlHints.hint(
				"HUD_KEYS_PASSENGER", [walk, &"interact"],
				"HUD_PAD_PASSENGER", [walk, &"interact"])
	if waiting:
		return ControlHints.hint(
			"HUD_KEYS_ON_FOOT", [walk, &"jump", &"interact", &"package_drop"],
			"HUD_PAD_ON_FOOT", [walk, &"jump", &"interact"])
	return ControlHints.hint(
		"HUD_KEYS_AT_HOUSE", [walk, &"interact", &"phone_toggle"],
		"HUD_PAD_AT_HOUSE", [walk, &"interact", &"phone_toggle"])


func _on_interaction_prompt(prompt: String) -> void:
	hud.interaction_prompt = prompt
	render_interaction_prompt()


func _on_carry_changed(carrying: bool) -> void:
	_carrying = carrying
	render_interaction_prompt()


func render_interaction_prompt() -> void:
	var lines: PackedStringArray = []
	var action_id: StringName = _action_id_for_prompt(hud.interaction_prompt)
	if not hud.interaction_prompt.is_empty():
		lines.append("[ %s ]  %s" % [GameSettings.binding_label(&"interact"), hud.interaction_prompt])
	if _carrying:
		lines.append(tr("HUD_PROMPT_DROP") % GameSettings.binding_label(&"package_drop"))
		if action_id == &"":
			action_id = &"drop"
	if not _lid_action.is_empty():
		lines.append("[ %s ]  %s" % [GameSettings.binding_label(&"package_open"), _lid_action])
		if action_id == &"":
			action_id = &"open_box"
	if not _lid_inside.is_empty():
		lines.append(tr("HUD_PROMPT_INSIDE") % _lid_inside)
	if not _sound_subtitle.is_empty():
		lines.append(_sound_subtitle)
	lines.append_array(_subtitles.lines())
	hud.interaction_label.text = "\n".join(lines)
	hud.interaction_icon.texture = UiTheme.action_icon(action_id)
	hud.interaction_icon.visible = hud.interaction_icon.texture != null


## Prompt translation keys to the action they ask for, checked in this order.
## Matched against the prompt in this player's language, so an English prompt
## gets its icon too (N-805).
const PROMPT_ACTIONS: Array = [
	[&"grab", ["HUD_PROMPT_PICK_UP_PACKAGE", "HUD_PROMPT_UNLOAD_PACKAGE"]],
	[&"drop", ["HUD_PROMPT_DROP_TO_DRIVE", "HUD_PROMPT_PLACE_PACKAGE", "HUD_PROMPT_STORE_ON_SHELF"]],
	[&"sit", ["HUD_PROMPT_DRIVE", "HUD_PROMPT_SIT_BY_CARGO", "HUD_PROMPT_SIT"]],
	[&"bell", ["WORLD_DOORBELL_PROMPT"]],
	[&"open_box", ["HUD_PROMPT_OPEN_BOX", "HUD_PROMPT_CLOSE_BOX"]],
]


func _action_id_for_prompt(prompt: String) -> StringName:
	var normalized: String = prompt.to_lower()
	if normalized.is_empty():
		return &""
	for entry: Array in PROMPT_ACTIONS:
		for key: String in entry[1]:
			if tr(key).to_lower() in normalized:
				return entry[0]
	return &""


## Every frame (Hud._process): the at-risk trap's standing subtitle, and the
## queue's expiry by `delta`.
func refresh_sound_subtitle(delta: float = 0.0) -> void:
	var subtitle: String = ""
	var queue_changed: bool = _subtitles.tick(delta) if GameSettings.sound_subtitles else _subtitles.clear()
	if GameSettings.sound_subtitles:
		var package_id: StringName = hud.cargo.local_package_id()
		if int(RunManager.cargo.get(package_id, {}).get("state", 0)) != ITrapBehavior.TrapState.AT_RISK:
			package_id = &""
			for candidate: StringName in hud.cargo_rows:
				if int(RunManager.cargo.get(candidate, {}).get("state", 0)) == ITrapBehavior.TrapState.AT_RISK:
					package_id = candidate
					break
		if not package_id.is_empty() and hud.cargo_rows.has(package_id):
			# By the trap's key (TrapDefinition.name_key()): the name is in this
			# player's language, which may not be Spanish.
			var trap_key: String = String(hud.cargo_rows[package_id].get("key", ""))
			subtitle = tr({
				"HUD_TRAP_EXPLOSIVE": "HUD_SUB_EXPLOSIVE",
				"HUD_TRAP_NOISY": "HUD_SUB_NOISY",
				"HUD_TRAP_FRAGILE": "HUD_SUB_FRAGILE",
				"HUD_TRAP_GROWING_WEIGHT": "HUD_SUB_GROWING_WEIGHT",
				"HUD_TRAP_LIQUID": "HUD_SUB_LIQUID",
				"HUD_TRAP_HOSTILE": "HUD_SUB_HOSTILE",
				"HUD_TRAP_BALANCE": "HUD_SUB_BALANCE",
			}.get(trap_key, "HUD_SUB_DEFAULT"))
	if subtitle != _sound_subtitle:
		_sound_subtitle = subtitle
		queue_changed = true
	if queue_changed:
		render_interaction_prompt()


## What each sound with a game meaning shows, by what announces it (N-965,
## inventory in docs/tareas/N-965.md): priority and seconds on screen.
const SUB_HORN: Array = [50, 1.5]
const SUB_DOORBELL: Array = [45, 2.5]
const SUB_CLIENT: Array = [40, 2.5]
const SUB_WEATHER: Array = [20, 6.0]
const SUB_ANIMAL_PRIORITY: int = 70
const SUB_ANIMAL_SECONDS: Vector2 = Vector2(2.0, 4.0)
## The animals' cry by kind (cargo_animal_alert), the customer's reaction by
## outcome (house_delivery_recorded; a missed or lost door rings nothing).
const ANIMAL_SUBTITLES: Dictionary = {
	&"gull": "HUD_SUB_GULL", &"dog": "HUD_SUB_DOG", &"bees": "HUD_SUB_BEES",
}
const CLIENT_SUBTITLES: Dictionary = {
	&"delivered_ok": "HUD_SUB_CLIENT_CHEER",
	&"delivered_at_risk": "HUD_SUB_CLIENT_GROAN",
	&"delivered_ruined": "HUD_SUB_CLIENT_GROAN",
}
## Outcomes with no real bell: the box was lost on the road, or the deadline closed
## the door (RunManager.force_resolve_if_missed) with nobody ringing.
const SILENT_OUTCOMES: Array[StringName] = [&"lost", &"missed"]


## Another player's horn, with the way to the truck. Your own you press.
func _on_horn_honked(peer_id: int) -> void:
	if not GameSettings.sound_subtitles or peer_id == NetworkManager.local_id():
		return
	var truck: Node3D = get_tree().get_first_node_in_group(&"vehicle") as Node3D
	var text: String = _with_arrow(tr("HUD_SUB_HORN") % (tr("UI_PLAYER_N") % peer_id), _arrow_to(truck))
	_subtitles.push(&"horn", text, int(SUB_HORN[0]), float(SUB_HORN[1]))


## The bell at that door and, after it, how the customer took the box.
func _on_house_delivery_subtitle(house_index: int, outcome: StringName, _package_id: StringName) -> void:
	if not GameSettings.sound_subtitles or outcome in SILENT_OUTCOMES:
		return
	_push_doorbell(house_index)
	if CLIENT_SUBTITLES.has(outcome):
		_subtitles.push(StringName("client_%d" % house_index), tr(CLIENT_SUBTITLES[outcome]),
			int(SUB_CLIENT[0]), float(SUB_CLIENT[1]))


func _on_house_refused_subtitle(house_index: int, _expected_label: String) -> void:
	if not GameSettings.sound_subtitles:
		return
	_push_doorbell(house_index)
	_subtitles.push(StringName("client_%d" % house_index), tr("HUD_SUB_CLIENT_REFUSE"),
		int(SUB_CLIENT[0]), float(SUB_CLIENT[1]))


func _push_doorbell(house_index: int) -> void:
	var door: Node3D = null
	for house: Node in get_tree().get_nodes_in_group(&"delivery_house"):
		if house is Node3D and int(house.get(&"house_index")) == house_index:
			door = house as Node3D
			break
	_subtitles.push(StringName("doorbell_%d" % house_index),
		_with_arrow(tr("HUD_SUB_DOORBELL") % (house_index + 1), _arrow_to(door)),
		int(SUB_DOORBELL[0]), float(SUB_DOORBELL[1]))


## The cry, bark or buzz that warns an animal is going for a box; it lives as
## long as the warning (clamped), the box is on the truck so no arrow.
func _on_animal_subtitle(kind: StringName, _package_id: StringName, warn_seconds: float, _act_seconds: float) -> void:
	if not GameSettings.sound_subtitles or not ANIMAL_SUBTITLES.has(kind) or warn_seconds <= 0.0:
		return
	_subtitles.push(StringName("animal_%s" % kind), tr(ANIMAL_SUBTITLES[kind]), SUB_ANIMAL_PRIORITY,
		clampf(warn_seconds, SUB_ANIMAL_SECONDS.x, SUB_ANIMAL_SECONDS.y))


## The animal is gone: its cry is not news any more.
func _on_animal_ended_subtitle(kind: StringName, _package_id: StringName, _outcome: StringName, _peer_id: int) -> void:
	if _subtitles.remove(StringName("animal_%s" % kind)):
		render_interaction_prompt()


## Weather has no event of its own: the sky builds its rain and its sound at
## the start of the route (route_sky.gd, node "RainSound"), so as the run starts
## the rain is told once.
func _on_run_started_subtitle(_route_id: StringName, _players: Array) -> void:
	if not GameSettings.sound_subtitles:
		return
	if not get_tree().root.find_children("RainSound", "AudioStreamPlayer", true, false).is_empty():
		_subtitles.push(&"weather", tr("HUD_SUB_RAIN"), int(SUB_WEATHER[0]), float(SUB_WEATHER[1]))


func _with_arrow(text: String, arrow: String) -> String:
	return text if arrow.is_empty() else "%s %s" % [arrow, text]


## Which way `target` is from this player's view; "" without a camera or target.
func _arrow_to(target: Node3D) -> String:
	var camera: Camera3D = get_viewport().get_camera_3d() if is_inside_tree() else null
	if camera == null or target == null:
		return ""
	return SubtitleQueue.arrow(camera.global_transform.affine_inverse() * target.global_position)


func _on_lid_hint_changed(action: String, inside: String) -> void:
	_lid_action = action
	_lid_inside = inside
	render_interaction_prompt()


func _on_damage(_id: StringName, damage: float) -> void:
	_flash_hint(tr("HUD_HIT") % roundi(damage), 2.5)


func _on_delivery(in_zone: bool, stopped: float) -> void:
	if in_zone:
		_flash_hint(tr("HUD_HOLD_STILL") if stopped > 0.0 else tr("HUD_ARRIVED"), 0.25)
	elif in_delivery:
		_flash_hint(tr("HUD_BACK_TO_ZONE"), 3.0)
	in_delivery = in_zone
