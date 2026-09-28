class_name HudCargoPanel
extends Node
## The cargo panel and route telemetry: one row per package with its state and
## integrity, the speed/progress readout, and the risk vignette at the screen's edge.

## Set by Hud before this is added as its child.
var hud: Hud
var cargo_hints: Dictionary = {}
var _last_states: Dictionary = {}
var _rescue_player: AudioStreamPlayer
const RUIN_FLASH_SECONDS: float = 0.35
const RUIN_FLASH_ALPHA: float = 0.24
var _ruin_flash_left: float = 0.0


func _ready() -> void:
	EventBus.vehicle_telemetry.connect(_on_speed)
	EventBus.package_integrity_changed.connect(_on_integrity)
	EventBus.package_state_changed.connect(_on_package_state)
	EventBus.package_ruined.connect(_on_ruin_impact)
	EventBus.route_progress_changed.connect(_on_progress)
	EventBus.cargo_registered.connect(_on_cargo_registered)
	EventBus.package_hint_changed.connect(_on_package_hint)
	GameSettings.colorblind_palette_changed.connect(_refresh_accessibility_colors)


func _on_speed(speed: float) -> void:
	hud.speed_label.text = "%02d" % roundi(absf(speed))


func _on_cargo_registered(id: StringName, display_name: String) -> void:
	if hud.cargo_rows.has(id):
		return
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	hud.cargo_rows_box.add_child(row)
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
	var bar: ProgressBar = UiTheme.bar(column, Hud.MINT, 12)
	bar.value = 100
	hud.cargo_rows[id] = {"label": label, "bar": bar, "name": display_name.to_upper(), "icon": icon, "row": row}


func _on_integrity(id: StringName, integrity: float, maximum: float) -> void:
	if not hud.cargo_rows.has(id):
		return
	(hud.cargo_rows[id]["bar"] as ProgressBar).value = integrity / maxf(maximum, 0.01) * 100.0
	refresh_row(id)


func refresh_risk_vignette(delta: float) -> void:
	var risk: float = 0.0
	for entry: Dictionary in RunManager.cargo.values():
		if int(entry.get("state", 0)) == 2:
			continue
		var ratio: float = float(entry.get("integrity", 100.0)) / maxf(float(entry.get("maximum", 100.0)), 0.01)
		risk = maxf(risk, clampf((0.6 - ratio) / 0.6, 0.0, 1.0))
	var target_alpha: float = risk * 0.38
	hud.risk_vignette.color.a = move_toward(hud.risk_vignette.color.a, target_alpha, delta * 1.8)


func _on_ruin_impact(_id: StringName, _cause: String) -> void:
	if not GameSettings.impact_effects:
		return
	_ruin_flash_left = RUIN_FLASH_SECONDS
	hud.ruin_vignette.color = Color(1.0, 1.0, 1.0, RUIN_FLASH_ALPHA)


func refresh_ruin_impact(delta: float) -> void:
	if not GameSettings.impact_effects:
		_ruin_flash_left = 0.0
		hud.ruin_vignette.color.a = 0.0
		return
	_ruin_flash_left = maxf(0.0, _ruin_flash_left - delta)
	var amount: float = _ruin_flash_left / RUIN_FLASH_SECONDS
	hud.ruin_vignette.color.a = RUIN_FLASH_ALPHA * smoothstep(0.0, 1.0, amount)


func vignette_material() -> ShaderMaterial:
	var shader := Shader.new()
	shader.code = "shader_type canvas_item; void fragment(){ vec2 p = UV * 2.0 - 1.0; float edge = smoothstep(0.28, 1.25, dot(p,p)); COLOR = texture(TEXTURE, UV) * COLOR; COLOR.a *= edge; }"
	var material := ShaderMaterial.new()
	material.shader = shader
	return material


func _on_package_state(id: StringName, state: int) -> void:
	var previous: int = int(_last_states.get(id, 0))
	_last_states[id] = state
	refresh_row(id)
	if previous == 1 and state == 0 and RunManager.is_running:
		_celebrate_rescue(id)


func _celebrate_rescue(id: StringName) -> void:
	var name_text: String = String(hud.cargo_rows[id]["name"]) if hud.cargo_rows.has(id) else tr("HUD_THE_CARGO")
	hud.notices.toast(tr("HUD_RESCUED") % name_text.capitalize())
	if _rescue_player == null:
		_rescue_player = AudioStreamPlayer.new()
		_rescue_player.stream = SynthAudio.glass_chime()
		_rescue_player.pitch_scale = 1.5
		_rescue_player.volume_db = -9.0
		_rescue_player.bus = &"SFX" if AudioServer.get_bus_index(&"SFX") >= 0 else &"Master"
		add_child(_rescue_player)
	_rescue_player.play()
	if hud.cargo_rows.has(id):
		var row: Control = hud.cargo_rows[id]["row"]
		var flash := row.create_tween()
		flash.tween_property(row, ^"modulate", Color(0.6, 1.6, 1.1), 0.12)
		flash.tween_property(row, ^"modulate", Color.WHITE, 0.5)


func refresh_row(id: StringName) -> void:
	if not hud.cargo_rows.has(id):
		return
	var entry: Dictionary = RunManager.cargo.get(id, {})
	var state: int = clampi(int(entry.get("state", 0)), 0, 2)
	var integrity: float = float(entry.get("integrity", 100.0))
	var row: Dictionary = hud.cargo_rows[id]
	var label: Label = row["label"]
	var display_name: String = String(row["name"])
	(row["icon"] as TextureRect).texture = UiTheme.trap_icon(display_name.capitalize())
	for node: Node in get_tree().get_nodes_in_group(&"cargo"):
		if node is DeliveryPackage and node.package_id == id:
			if hud.route_event_active_id == &"mixed_labels" and not node.label_swapped_with.is_empty():
				display_name += " ?"
			if hud.route_event_active_id == &"mimetic_package" and not node.disguise_trap_id.is_empty() and not node.disguise_revealed:
				var disguise: Resource = load("res://data/traps/%s.tres" % node.disguise_trap_id)
				if disguise != null:
					display_name = String(disguise.get("display_name")).to_upper()
					(row["icon"] as TextureRect).texture = UiTheme.trap_icon(String(disguise.get("display_name")))
			break
	label.text = "%s  ·  %d%%  ·  %s" % [display_name, roundi(integrity), tr(Hud.STATE_STATUS[state])]
	label.add_theme_color_override("font_color", _state_text_color(state))
	((row["bar"] as ProgressBar).get_theme_stylebox("fill") as StyleBoxFlat).bg_color = UiTheme.state_color(state,
			GameSettings.colorblind_palette)
	(row["icon"] as TextureRect).modulate = Color(1, 1, 1, 0.35) if state == 2 else Color.WHITE


func _state_text_color(state: int) -> Color:
	if state == ITrapBehavior.TrapState.OK:
		return Hud.INK
	return UiTheme.state_color(state, GameSettings.colorblind_palette).darkened(0.18)


func _refresh_accessibility_colors(_enabled: bool = GameSettings.colorblind_palette) -> void:
	for id: StringName in hud.cargo_rows:
		refresh_row(id)
	if hud.risk_vignette != null:
		var alpha: float = hud.risk_vignette.color.a
		hud.risk_vignette.color = Color(UiTheme.state_color(ITrapBehavior.TrapState.AT_RISK,
				GameSettings.colorblind_palette), alpha)


func refresh_state_pulses() -> void:
	var pulse: float = 0.72 + sin(Time.get_ticks_msec() * 0.009) * 0.28
	for id: StringName in hud.cargo_rows:
		var state: int = int(RunManager.cargo.get(id, {}).get("state", 0))
		(hud.cargo_rows[id]["label"] as Label).modulate.a = pulse if state == ITrapBehavior.TrapState.AT_RISK else 1.0


func _on_progress(progress: float, meters: float, section: String) -> void:
	hud.route_bar.value = progress * 100.0
	hud.distance_label.text = tr("HUD_METERS_TO_DELIVERY") % ceili(meters)
	hud.section_label.text = section.to_upper()


func _on_package_hint(package_id: StringName, hint: String) -> void:
	cargo_hints[package_id] = hint


func refresh_cargo_hint() -> void:
	if hud.cargo_hint_label == null:
		return
	if not RunManager.is_running:
		hud.notices.clear_notice(&"critical", &"cargo")
		return
	var package_id := local_package_id()
	var entry: Dictionary = RunManager.cargo.get(package_id, {})
	var at_risk: bool = int(entry.get("state", 0)) == ITrapBehavior.TrapState.AT_RISK
	var text: String = String(cargo_hints.get(package_id, "")) if at_risk else ""
	hud.notices.set_notice(&"critical", &"cargo", text, 100, Hud.RED)


func local_package_id() -> StringName:
	var level: Node = hud.get_parent()
	var player: Variant = level.get(&"local_player") if level != null and &"local_player" in level else null
	if not is_instance_valid(player):
		return &""
	for property: StringName in [&"tended_package", &"carried_package"]:
		var package: Variant = (player as Node).get(property)
		if is_instance_valid(package):
			return StringName((package as Node).get(&"package_id"))
	return &""
