extends CanvasLayer
## Shared HUD state plus the cargo panel and route telemetry presentation.
## prototype_hud.gd inherits this script so its long-standing public fields
## remain available to scenes and tests while the behavior lives here.

const INK: Color = UiTheme.INK
const PAPER: Color = UiTheme.PAPER
const MUTED: Color = UiTheme.MUTED
const MINT: Color = UiTheme.MINT
const YELLOW: Color = UiTheme.YELLOW
const RED: Color = UiTheme.RED
const ORANGE: Color = UiTheme.ORANGE
const STATE_FILL: Array[Color] = [UiTheme.MINT, UiTheme.ORANGE, UiTheme.RED]
const STATE_TEXT: Array[Color] = [UiTheme.INK, Color("c26a00"), Color("c73431")]
const STATE_STATUS: Array[String] = ["OK ✓", "EN RIESGO !", "ARRUINADA ✕"]

enum Role { ON_FOOT, DRIVER, PASSENGER }

var root: Control
var hud_layer: Control
var dashboard: VBoxContainer
var session_label: Label
var speed_label: Label
var speed_unit_label: Label
var time_label: Label
var economy_label: Label
var card_label: RichTextLabel
var distance_label: Label
var section_label: Label
var cargo_rows_box: VBoxContainer
var cargo_hint_label: Label
var cargo_rows: Dictionary = {}
var cargo_hints: Dictionary = {}
var route_bar: ProgressBar
var hint_label: RichTextLabel
var overlay: ColorRect
var card: VBoxContainer
var overlay_kicker: Label
var overlay_title: Label
var overlay_body: Label
var overlay_stats: Label
var score_label: Label
var record_label: Label
var action_button: Button
var second_button: Button
var options_button: Button
var menu_button: Button
var options_panel: OptionsPanel
var depot_panel: DepotPanel
var _orders: Array = []
var _prep_refresh: float = 0.0
var overlay_mode: String = "start"
var in_delivery: bool = false
var interaction_label: Label
var _interaction_prompt: String = ""
var _lid_action: String = ""
var _lid_inside: String = ""
var _carrying: bool = false
var ping_label: Label
var ping_indicator: Label
var ping_seconds_left: float = 0.0
var event_label: Label
var event_seconds_left: float = 0.0
var _route_event_active_id: StringName = &""
var toast_label: Label
var toast_seconds_left: float = 0.0
var complaints_label: Label
var photo_strip: HBoxContainer
var fade_rect: ColorRect
var risk_vignette: ColorRect
var shortcut_label: RichTextLabel
const SHORTCUT_VISIBLE_SECONDS: float = 60.0
var _shortcut_learning_seconds: float = 0.0
## One label per fixed HUD zone. Each source keeps its queued entry here;
## hud_notices.gd renders only the highest-priority one in that zone.
var _notice_sources: Dictionary = {&"critical": {}, &"information": {}}
var _notice_serial: int = 0
var _hint_override: String = ""
var _hint_override_seconds: float = 0.0
var _sound_subtitle: String = ""
var _role: int = Role.ON_FOOT
var _soft_pause: bool = false
const RESTART_HOLD_SECONDS: float = 0.9
var _restart_hold: float = 0.0
var _is_endless: bool = false
var _local_merit_total: int = 0
var _last_states: Dictionary = {}
var _rescue_player: AudioStreamPlayer


func _apply_hud_scale() -> void:
	if hud_layer == null:
		return
	var hud_scale: float = GameSettings.hud_scale
	hud_layer.position = Vector2.ZERO
	hud_layer.scale = Vector2(hud_scale, hud_scale)
	hud_layer.size = root.size / hud_scale


func _rich(parent: Node, font_size: int) -> RichTextLabel:
	var node := RichTextLabel.new()
	node.bbcode_enabled = true
	node.fit_content = true
	node.scroll_active = false
	node.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	node.add_theme_font_size_override("normal_font_size", font_size)
	node.add_theme_font_override("normal_font", UiTheme.body_font(700))
	node.add_theme_color_override("default_color", INK)
	parent.add_child(node)
	return node


func _panel(parent: Node, minimum: Vector2) -> VBoxContainer:
	return UiTheme.panel(parent, minimum)


func _label(parent: Node, value: String, font_size: int, color: Color) -> Label:
	return UiTheme.label(parent, value, font_size, color)


func _bar(parent: Node, color: Color) -> ProgressBar:
	return UiTheme.bar(parent, color)


func _button(parent: Node, value: String, primary: bool) -> Button:
	return UiTheme.button(parent, value, primary, Vector2(150, 52))


func _key(keyboard: String, gamepad: String) -> String:
	return GameSettings.prompt(keyboard, gamepad)


func _on_speed(speed: float) -> void:
	speed_label.text = "%02d" % roundi(absf(speed))


func _on_cargo_registered(id: StringName, display_name: String) -> void:
	if cargo_rows.has(id):
		return
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	cargo_rows_box.add_child(row)
	var icon := TextureRect.new()
	icon.texture = UiTheme.trap_icon(display_name)
	icon.custom_minimum_size = Vector2(42, 42)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT
	row.add_child(icon)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 4)
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(column)
	var label: Label = UiTheme.title(column, "%s  ·  100%%" % display_name.to_upper(), 18)
	var bar: ProgressBar = UiTheme.bar(column, MINT, 12)
	bar.value = 100
	cargo_rows[id] = {"label": label, "bar": bar, "name": display_name.to_upper(), "icon": icon, "row": row}


func _on_integrity(id: StringName, integrity: float, maximum: float) -> void:
	if not cargo_rows.has(id):
		return
	(cargo_rows[id]["bar"] as ProgressBar).value = integrity / maxf(maximum, 0.01) * 100.0
	_refresh_row(id)


func _refresh_risk_vignette(delta: float) -> void:
	var risk: float = 0.0
	for entry: Dictionary in RunManager.cargo.values():
		if int(entry.get("state", 0)) == 2:
			continue
		var ratio: float = float(entry.get("integrity", 100.0)) / maxf(float(entry.get("maximum", 100.0)), 0.01)
		risk = maxf(risk, clampf((0.6 - ratio) / 0.6, 0.0, 1.0))
	var target_alpha: float = risk * 0.38
	risk_vignette.color.a = move_toward(risk_vignette.color.a, target_alpha, delta * 1.8)


func _vignette_material() -> ShaderMaterial:
	var shader := Shader.new()
	shader.code = "shader_type canvas_item; void fragment(){ vec2 p = UV * 2.0 - 1.0; float edge = smoothstep(0.28, 1.25, dot(p,p)); COLOR = texture(TEXTURE, UV) * COLOR; COLOR.a *= edge; }"
	var material := ShaderMaterial.new()
	material.shader = shader
	return material


func _on_package_state(id: StringName, state: int) -> void:
	var previous: int = int(_last_states.get(id, 0))
	_last_states[id] = state
	_refresh_row(id)
	if previous == 1 and state == 0 and RunManager.is_running:
		_celebrate_rescue(id)


func _celebrate_rescue(id: StringName) -> void:
	var name_text: String = String(cargo_rows[id]["name"]) if cargo_rows.has(id) else "LA CARGA"
	call(&"_toast", "¡%s a salvo!" % name_text.capitalize())
	if _rescue_player == null:
		_rescue_player = AudioStreamPlayer.new()
		_rescue_player.stream = SynthAudio.glass_chime()
		_rescue_player.pitch_scale = 1.5
		_rescue_player.volume_db = -9.0
		_rescue_player.bus = &"SFX" if AudioServer.get_bus_index(&"SFX") >= 0 else &"Master"
		add_child(_rescue_player)
	_rescue_player.play()
	if cargo_rows.has(id):
		var row: Control = cargo_rows[id]["row"]
		var flash := row.create_tween()
		flash.tween_property(row, ^"modulate", Color(0.6, 1.6, 1.1), 0.12)
		flash.tween_property(row, ^"modulate", Color.WHITE, 0.5)


func _refresh_row(id: StringName) -> void:
	if not cargo_rows.has(id):
		return
	var entry: Dictionary = RunManager.cargo.get(id, {})
	var state: int = clampi(int(entry.get("state", 0)), 0, 2)
	var integrity: float = float(entry.get("integrity", 100.0))
	var row: Dictionary = cargo_rows[id]
	var label: Label = row["label"]
	var display_name: String = String(row["name"])
	(row["icon"] as TextureRect).texture = UiTheme.trap_icon(display_name.capitalize())
	for node: Node in get_tree().get_nodes_in_group(&"cargo"):
		if node is DeliveryPackage and node.package_id == id:
			if _route_event_active_id == &"mixed_labels" and not node.label_swapped_with.is_empty():
				display_name += " ?"
			if _route_event_active_id == &"mimetic_package" and not node.disguise_trap_id.is_empty() and not node.disguise_revealed:
				var disguise: Resource = load("res://data/traps/%s.tres" % node.disguise_trap_id)
				if disguise != null:
					display_name = String(disguise.get("display_name")).to_upper()
					(row["icon"] as TextureRect).texture = UiTheme.trap_icon(String(disguise.get("display_name")))
			break
	label.text = "%s  ·  %d%%  ·  %s" % [display_name, roundi(integrity), STATE_STATUS[state]]
	label.add_theme_color_override("font_color", _state_text_color(state))
	((row["bar"] as ProgressBar).get_theme_stylebox("fill") as StyleBoxFlat).bg_color = UiTheme.state_color(state, GameSettings.colorblind_palette)
	(row["icon"] as TextureRect).modulate = Color(1, 1, 1, 0.35) if state == 2 else Color.WHITE


func _state_text_color(state: int) -> Color:
	if state == ITrapBehavior.TrapState.OK:
		return INK
	return UiTheme.state_color(state, GameSettings.colorblind_palette).darkened(0.18)


func _refresh_accessibility_colors(_enabled: bool = GameSettings.colorblind_palette) -> void:
	for id: StringName in cargo_rows:
		_refresh_row(id)
	if risk_vignette != null:
		var alpha: float = risk_vignette.color.a
		risk_vignette.color = Color(UiTheme.state_color(ITrapBehavior.TrapState.AT_RISK, GameSettings.colorblind_palette), alpha)


func _refresh_state_pulses() -> void:
	var pulse: float = 0.72 + sin(Time.get_ticks_msec() * 0.009) * 0.28
	for id: StringName in cargo_rows:
		var state: int = int(RunManager.cargo.get(id, {}).get("state", 0))
		(cargo_rows[id]["label"] as Label).modulate.a = pulse if state == ITrapBehavior.TrapState.AT_RISK else 1.0


func _on_progress(progress: float, meters: float, section: String) -> void:
	route_bar.value = progress * 100.0
	distance_label.text = "%d m hasta la entrega" % ceili(meters)
	section_label.text = section.to_upper()


func _on_package_hint(package_id: StringName, hint: String) -> void:
	cargo_hints[package_id] = hint


func _refresh_cargo_hint() -> void:
	if cargo_hint_label == null:
		return
	if not RunManager.is_running:
		call(&"_clear_notice", &"critical", &"cargo")
		return
	var package_id := _local_package_id()
	var entry: Dictionary = RunManager.cargo.get(package_id, {})
	var at_risk: bool = int(entry.get("state", 0)) == ITrapBehavior.TrapState.AT_RISK
	var text: String = String(cargo_hints.get(package_id, "")) if at_risk else ""
	call(&"_set_notice", &"critical", &"cargo", text, 100, RED)


func _local_package_id() -> StringName:
	var level: Node = get_parent()
	var player: Variant = level.get(&"local_player") if level != null and &"local_player" in level else null
	if not is_instance_valid(player):
		return &""
	for property: StringName in [&"tended_package", &"carried_package"]:
		var package: Variant = (player as Node).get(property)
		if is_instance_valid(package):
			return StringName((package as Node).get(&"package_id"))
	return &""
