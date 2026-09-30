class_name HudPrompts
extends Node
## Context-sensitive teaching: interaction/lid prompts, role hints, the
## keyboard/gamepad cheat sheet and sound subtitles.

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
var _sound_subtitle: String = ""
var _role: int = Hud.Role.ON_FOOT


func _ready() -> void:
	EventBus.package_damaged.connect(_on_damage)
	EventBus.delivery_status_changed.connect(_on_delivery)
	EventBus.interaction_prompt_changed.connect(_on_interaction_prompt)
	EventBus.carry_changed.connect(_on_carry_changed)
	EventBus.package_lid_hint_changed.connect(_on_lid_hint_changed)
	EventBus.tutorial_tip_requested.connect(_on_tutorial_tip_requested)


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
	var items: PackedStringArray = [
		hud.key_hint(tr("HUD_KEY_PHONE"), tr("HUD_PAD_PHONE")),
		hud.key_hint(tr("HUD_KEY_PING"), tr("HUD_PAD_PING")),
		hud.key_hint(tr("HUD_KEY_CENTER_VIEW"), tr("HUD_PAD_CENTER_VIEW")),
		hud.key_hint(tr("HUD_KEY_LOOK_BACK") % GameSettings.binding_label(&"look_back"), tr("HUD_PAD_LOOK_BACK")),
		hud.key_hint(tr("HUD_KEY_PAUSE"), tr("HUD_PAD_PAUSE")),
	]
	if can_restart():
		items.append(hud.key_hint(tr("HUD_KEY_RESTART"), tr("HUD_PAD_RESTART")))
	hud.shortcut_label.text = UiTheme.keycaps("   ·   ".join(items), true)


func can_restart() -> bool:
	return not session_lost and (not NetworkManager.is_online() or NetworkManager.is_host())


func refresh_role() -> void:
	_role = _local_role()


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
		hud.hint_label.text = "[b]%s[/b]" % _hint_override
		hud.hint_label.add_theme_color_override("default_color", Hud.YELLOW)
		return
	# On the dark controls pill (Hud._build_bottom_bar()).
	hud.hint_label.text = UiTheme.keycaps(_base_hint(), true)
	hud.hint_label.add_theme_color_override("default_color", Hud.PAPER)


func _base_hint() -> String:
	var waiting: bool = not RunManager.is_running and RunManager.results.is_empty()
	match _role:
		Hud.Role.DRIVER:
			if waiting:
				return tr("HUD_NO_CARGO_YET") % hud.key_hint("E", "A")
			return hud.key_hint(
				tr("HUD_KEYS_DRIVER"),
				tr("HUD_PAD_DRIVER"))
		Hud.Role.PASSENGER:
			return hud.key_hint(
				tr("HUD_KEYS_PASSENGER"),
				tr("HUD_PAD_PASSENGER"))
	if waiting:
		return hud.key_hint(
			tr("HUD_KEYS_ON_FOOT"),
			tr("HUD_PAD_ON_FOOT"))
	return hud.key_hint(
		tr("HUD_KEYS_AT_HOUSE"),
		tr("HUD_PAD_AT_HOUSE"))


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
		lines.append("[ %s ]  %s" % [hud.key_hint("E", "A"), hud.interaction_prompt])
	if _carrying:
		lines.append(tr("HUD_PROMPT_DROP") % hud.key_hint("Q", "B"))
		if action_id == &"":
			action_id = &"drop"
	if not _lid_action.is_empty():
		lines.append("[ %s ]  %s" % [hud.key_hint("T", tr("HUD_PAD_DOWN")), _lid_action])
		if action_id == &"":
			action_id = &"open_box"
	if not _lid_inside.is_empty():
		lines.append(tr("HUD_PROMPT_INSIDE") % _lid_inside)
	if not _sound_subtitle.is_empty():
		lines.append(_sound_subtitle)
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


func refresh_sound_subtitle() -> void:
	var subtitle: String = ""
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
		render_interaction_prompt()


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
