extends CanvasLayer
## Lightweight prototype UI: no gameplay decisions or direct physics references.

const INK: Color = Color("132a31")
const PAPER: Color = Color("edf2e8")
const MUTED: Color = Color("acc1bd")
const MINT: Color = Color("83e2ba")
const YELLOW: Color = Color("f4c562")
const RED: Color = Color("f47e6d")
const DRIVE_HINT: String = "W/S acelerar y frenar · A/D girar · Mouse mirar · C centrar vista"

var root: Control
var dashboard: VBoxContainer
var speed_label: Label
var time_label: Label
var distance_label: Label
var section_label: Label
var integrity_label: Label
var integrity_bar: ProgressBar
var route_bar: ProgressBar
var hint_label: Label
var overlay: ColorRect
var card: VBoxContainer
var overlay_title: Label
var overlay_body: Label
var overlay_stats: Label
var action_button: Button
var second_button: Button
var overlay_mode: String = "start"
var damage_flash: float = 0.0
var in_delivery: bool = false
var interaction_label: Label


func _ready() -> void:
	_build_ui()
	EventBus.vehicle_telemetry.connect(_on_speed)
	EventBus.package_integrity_changed.connect(_on_integrity)
	EventBus.package_state_changed.connect(_on_package_state)
	EventBus.package_damaged.connect(_on_damage)
	EventBus.route_progress_changed.connect(_on_progress)
	EventBus.delivery_status_changed.connect(_on_delivery)
	EventBus.run_started.connect(_on_started)
	EventBus.run_ended.connect(_on_ended)
	EventBus.interaction_prompt_changed.connect(_on_interaction_prompt)
	_show_start()


func _build_ui() -> void:
	root = Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	var margin := MarginContainer.new()
	root.add_child(margin)
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 26)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dashboard = VBoxContainer.new()
	margin.add_child(dashboard)
	dashboard.add_theme_constant_override("separation", 12)
	dashboard.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var top := HBoxContainer.new()
	dashboard.add_child(top)
	top.add_theme_constant_override("separation", 16)
	var brand := _panel(top, Vector2(240, 0))
	_label(brand, "DO NOT DROP", 26, PAPER)
	_label(brand, "PRUEBA DE RUTA  /  01", 12, MINT)
	var stretch := Control.new()
	stretch.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(stretch)
	var metrics := _panel(top, Vector2(190, 0))
	speed_label = _label(metrics, "00 km/h", 28, PAPER)
	time_label = _label(metrics, "TIEMPO   00:00", 14, MUTED)
	var space := Control.new()
	space.size_flags_vertical = Control.SIZE_EXPAND_FILL
	space.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dashboard.add_child(space)
	var bottom := HBoxContainer.new()
	dashboard.add_child(bottom)
	bottom.add_theme_constant_override("separation", 16)
	var cargo := _panel(bottom, Vector2(285, 0))
	_label(cargo, "CARGA  /  FRÁGIL", 13, MUTED)
	integrity_label = _label(cargo, "100%  ·  ESTABLE", 24, MINT)
	integrity_bar = _bar(cargo, MINT)
	integrity_bar.value = 100
	_label(cargo, "Cada golpe deja huella.", 14, MUTED)
	var delivery := _panel(bottom, Vector2.ZERO)
	delivery.get_parent().size_flags_horizontal = Control.SIZE_EXPAND_FILL
	section_label = _label(delivery, "01  /  SALIDA", 13, MINT)
	distance_label = _label(delivery, "220 m hasta la entrega", 24, PAPER)
	route_bar = _bar(delivery, MINT)
	hint_label = _label(delivery, DRIVE_HINT, 14, MUTED)
	_label(dashboard, "Espacio  freno de mano   /   R  reiniciar   /   ESC  pausa   /   Gamepad: stick derecho para mirar", 13, PAPER)
	interaction_label = _label(root, "", 22, PAPER)
	interaction_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	interaction_label.offset_left = -260
	interaction_label.offset_right = 260
	interaction_label.offset_top = 45
	interaction_label.offset_bottom = 85
	interaction_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	interaction_label.add_theme_color_override("font_outline_color", INK)
	interaction_label.add_theme_constant_override("outline_size", 8)
	interaction_label.mouse_filter = Control.MOUSE_FILTER_IGNORE

	overlay = ColorRect.new()
	root.add_child(overlay)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.color = Color(0.035, 0.09, 0.11, 0.78)
	var center := CenterContainer.new()
	overlay.add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	card = _panel(center, Vector2(610, 0))
	card.add_theme_constant_override("separation", 18)
	_label(card, "PROMETEUS   /   PROTOTIPO 0.1", 13, MINT)
	overlay_title = _label(card, "DO NOT\nDROP", 64, PAPER)
	overlay_body = _label(card, "", 20, PAPER)
	overlay_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	overlay_body.custom_minimum_size.x = 545
	overlay_stats = _label(card, "", 16, MUTED)
	overlay_stats.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 12)
	card.add_child(actions)
	action_button = _button(actions, "Empezar entrega", true)
	action_button.pressed.connect(_primary_action)
	second_button = _button(actions, "Reiniciar", false)
	second_button.pressed.connect(func() -> void: EventBus.restart_requested.emit())


func _panel(parent: Node, minimum: Vector2) -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = minimum
	var style := StyleBoxFlat.new()
	style.bg_color = Color(INK, 0.94)
	style.border_color = Color("365458")
	style.set_border_width_all(1)
	style.set_corner_radius_all(8)
	style.content_margin_left = 22
	style.content_margin_right = 22
	style.content_margin_top = 18
	style.content_margin_bottom = 18
	panel.add_theme_stylebox_override("panel", style)
	parent.add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	panel.add_child(column)
	return column


func _label(parent: Node, value: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = value
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	parent.add_child(label)
	return label


func _bar(parent: Node, color: Color) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.custom_minimum_size.y = 8
	bar.show_percentage = false
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color("2e454b")
	bg.set_corner_radius_all(4)
	var fill := StyleBoxFlat.new()
	fill.bg_color = color
	fill.set_corner_radius_all(4)
	bar.add_theme_stylebox_override("background", bg)
	bar.add_theme_stylebox_override("fill", fill)
	parent.add_child(bar)
	return bar


func _button(parent: Node, value: String, primary: bool) -> Button:
	var button := Button.new()
	button.text = value
	button.custom_minimum_size = Vector2(190, 48)
	button.add_theme_font_size_override("font_size", 18)
	var style := StyleBoxFlat.new()
	style.bg_color = MINT if primary else Color("30474d")
	style.set_corner_radius_all(5)
	style.content_margin_left = 18
	style.content_margin_right = 18
	button.add_theme_stylebox_override("normal", style)
	var hover: StyleBoxFlat = style.duplicate()
	hover.bg_color = style.bg_color.lightened(0.12)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", hover)
	button.add_theme_color_override("font_color", INK if primary else PAPER)
	button.add_theme_color_override("font_hover_color", INK if primary else PAPER)
	button.add_theme_color_override("font_pressed_color", INK if primary else PAPER)
	parent.add_child(button)
	return button


func _show_start() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	overlay_mode = "start"
	overlay.visible = true
	dashboard.visible = false
	overlay_body.text = "Cargá el paquete y subite a manejar.\nLa entrega arranca sola apenas estés al volante con la carga a bordo."
	overlay_stats.text = "Caminá hasta el paquete y presioná E para agarrarlo.\nLlevalo hasta la furgoneta y presioná E para dejarlo en su lugar.\nAcercate al asiento del conductor y presioná E para tomar el volante.\n\nWASD caminar     Mouse mirar     E interactuar\nR reiniciar     Esc pausa\n\nSeguí la indicación que aparece al acercarte a cada objeto."
	second_button.visible = false
	action_button.text = "Preparar entrega"
	action_button.grab_focus()


func _process(delta: float) -> void:
	time_label.text = "TIEMPO   %02d:%02d" % [int(RunManager.elapsed_seconds) / 60, int(RunManager.elapsed_seconds) % 60]
	if damage_flash > 0.0:
		damage_flash -= delta
		if damage_flash <= 0.0 and not in_delivery:
			hint_label.text = DRIVE_HINT
	if overlay_mode == "pause" and not get_tree().paused:
		overlay.hide()
		overlay_mode = "run" if RunManager.is_running else "preparation"


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_pause"):
		if overlay_mode == "start" or overlay_mode == "results":
			return
		EventBus.pause_requested.emit()
		if get_tree().paused:
			overlay_mode = "pause"
			overlay.show()
			overlay_title.text = "EN PAUSA"
			overlay_body.text = "Tu entrega puede esperar."
			overlay_stats.text = "Esc para volver a la ruta."
			action_button.text = "Continuar"
			second_button.show()
			action_button.grab_focus()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("run_restart"):
		EventBus.restart_requested.emit()
		get_viewport().set_input_as_handled()


func _primary_action() -> void:
	match overlay_mode:
		"start":
			overlay.hide()
			overlay_mode = "preparation"
			dashboard.show()
			action_button.release_focus()
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			section_label.text = "PREPARACIÓN"
			distance_label.text = "Cargá el paquete y tomá el volante"
			hint_label.text = "WASD / stick izquierdo caminar · Mouse / stick derecho mirar · E / A interactuar"
		"pause": EventBus.pause_requested.emit()
		"results": EventBus.restart_requested.emit()


func _on_interaction_prompt(prompt: String) -> void:
	interaction_label.text = "[ E / A ]  " + prompt if not prompt.is_empty() else ""


func _on_started(_route: StringName, _players: Array) -> void:
	overlay.hide()
	overlay_mode = "run"
	dashboard.show()
	action_button.release_focus()
	interaction_label.text = ""
	hint_label.text = DRIVE_HINT
	_on_integrity(&"fragile_01", RunManager.package_integrity, RunManager.package_maximum)


func _on_speed(speed: float) -> void:
	speed_label.text = "%02d km/h" % roundi(absf(speed))


func _on_integrity(_id: StringName, integrity: float, maximum: float) -> void:
	integrity_bar.value = integrity / maximum * 100.0
	_update_integrity_text(integrity)


func _on_package_state(_id: StringName, _state: int) -> void:
	_update_integrity_text(RunManager.package_integrity)


func _update_integrity_text(integrity: float) -> void:
	var state: int = RunManager.package_state
	var color: Color = [MINT, YELLOW, RED][state]
	integrity_label.text = "%d%%  ·  %s" % [roundi(integrity), ["ESTABLE", "EN RIESGO", "ARRUINADO"][state]]
	integrity_label.add_theme_color_override("font_color", color)
	(integrity_bar.get_theme_stylebox("fill") as StyleBoxFlat).bg_color = color


func _on_damage(_id: StringName, damage: float) -> void:
	damage_flash = 2.5
	hint_label.text = "¡Golpe!  −%d de integridad. Bajá la velocidad antes del próximo obstáculo." % roundi(damage)


func _on_progress(progress: float, meters: float, section: String) -> void:
	route_bar.value = progress * 100.0
	distance_label.text = "%d m hasta la entrega" % ceili(meters)
	section_label.text = section.to_upper()


func _on_delivery(in_zone: bool, stopped: float) -> void:
	if in_zone:
		hint_label.text = "Mantené la camioneta detenida…" if stopped > 0.0 else "¡Llegaste! Frená dentro de la zona marcada para entregar."
	elif in_delivery:
		hint_label.text = "Volvé a la zona de entrega y detené la camioneta."
	in_delivery = in_zone


func _on_ended(score: int, results: Dictionary) -> void:
	overlay_mode = "results"
	overlay.show()
	var success: bool = results["delivered"]
	overlay_title.text = "¡ENTREGADO!" if success else "OTRA VUELTA"
	overlay_body.text = ("El paquete llegó %s." % ("en buen estado" if results["package_state"] == 0 else "en riesgo, pero llegó")) if success else results["reason"]
	overlay_stats.text = "%d PUNTOS     /     %d%% INTEGRIDAD     /     %.1f s\n\nEntrega: %d pts   +   Rapidez: %d pts" % [score, roundi(results["integrity"]), results["elapsed_seconds"], results["package_points"], results["time_bonus"]]
	action_button.text = "Volver a intentar"
	second_button.hide()
	action_button.grab_focus()
