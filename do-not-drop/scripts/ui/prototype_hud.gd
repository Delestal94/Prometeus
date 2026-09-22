extends CanvasLayer
## Lightweight prototype UI: no gameplay decisions or direct physics references.

# Shared with the main menu through ui_theme.gd instead of a second copy
# of the same constants (docs/direccion-visual.md section 3).
const INK: Color = UiTheme.INK
const PAPER: Color = UiTheme.PAPER
const MUTED: Color = UiTheme.MUTED
const MINT: Color = UiTheme.MINT
const YELLOW: Color = UiTheme.YELLOW
const RED: Color = UiTheme.RED
const DRIVE_HINT: String = "W/S acelerar y frenar · A/D girar · Mouse mirar · C centrar vista"

var root: Control
var dashboard: VBoxContainer
var speed_label: Label
var time_label: Label
var economy_label: Label
var distance_label: Label
var section_label: Label
var cargo_rows_box: VBoxContainer
var cargo_hint_label: Label
## package id -> {"label": Label, "bar": ProgressBar}
var cargo_rows: Dictionary = {}
## package id -> hint text, kept fresh by package_hint_changed rather than
## read straight off the package node -- on a client, that node is a frozen
## puppet whose trap never advances locally, so its hint would never change.
var cargo_hints: Dictionary = {}
var route_bar: ProgressBar
var hint_label: Label
var overlay: ColorRect
var card: VBoxContainer
var overlay_title: Label
var overlay_body: Label
var overlay_stats: Label
var action_button: Button
var second_button: Button
var options_button: Button
var menu_button: Button
var options_panel: OptionsPanel
var overlay_mode: String = "start"
var damage_flash: float = 0.0
var in_delivery: bool = false
var interaction_label: Label
var ping_label: Label
var ping_seconds_left: float = 0.0
## Route events used to overwrite interaction_label, and merit/card notices
## used to overwrite ping_label -- so an event banner erased "[E] Agarrar
## paquete" mid-reach, and a teammate's ping vanished behind a card notice.
## Each kind of message gets its own line and its own clock now.
var event_label: Label
var event_seconds_left: float = 0.0
var toast_label: Label
var toast_seconds_left: float = 0.0
var complaints_label: Label
var photo_strip: HBoxContainer
var fade_rect: ColorRect
## The keyboard cheat sheet along the bottom. It used to sit there for the
## whole run, competing with everything else on screen long after anyone
## needed it (docs/critica-diseno-abogado-del-diablo.md section 5). It fades
## out once the run has been going a while and comes straight back whenever
## the game is paused, which is when someone is actually looking for it.
var shortcut_label: Label
const SHORTCUT_VISIBLE_SECONDS: float = 25.0


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
	EventBus.cargo_registered.connect(_on_cargo_registered)
	EventBus.package_hint_changed.connect(_on_package_hint)
	EventBus.ping_sent.connect(_on_ping)
	EventBus.quick_fade_requested.connect(_on_quick_fade_requested)
	EventBus.team_money_changed.connect(_on_team_money_changed)
	EventBus.merit_changed.connect(_on_merit_changed)
	EventBus.card_changed.connect(_on_card_changed)
	EventBus.route_event_started.connect(_on_route_event_started)
	EventBus.route_event_resolved.connect(_on_route_event_resolved)
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
	economy_label = _label(metrics, "EQUIPO  $%d" % CrewProgression.team_money, 14, MINT)
	var space := Control.new()
	space.size_flags_vertical = Control.SIZE_EXPAND_FILL
	space.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dashboard.add_child(space)
	var bottom := HBoxContainer.new()
	dashboard.add_child(bottom)
	bottom.add_theme_constant_override("separation", 16)
	var cargo := _panel(bottom, Vector2(310, 0))
	_label(cargo, "CARGA", 13, MUTED)
	cargo_rows_box = VBoxContainer.new()
	cargo_rows_box.add_theme_constant_override("separation", 6)
	cargo.add_child(cargo_rows_box)
	cargo_hint_label = _label(cargo, "", 14, MUTED)
	cargo_hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	cargo_hint_label.custom_minimum_size.x = 265
	var delivery := _panel(bottom, Vector2.ZERO)
	delivery.get_parent().size_flags_horizontal = Control.SIZE_EXPAND_FILL
	section_label = _label(delivery, "01  /  SALIDA", 13, MINT)
	distance_label = _label(delivery, "220 m hasta la entrega", 24, PAPER)
	route_bar = _bar(delivery, MINT)
	hint_label = _label(delivery, DRIVE_HINT, 14, MUTED)
	shortcut_label = _label(dashboard, "Espacio  freno de mano   /   F  celular   /   H  bocina   /   R  reiniciar   /   ESC  pausa   /   Click rueda  ping   /   Gamepad: stick derecho para mirar", 13, PAPER)
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

	ping_label = _label(root, "", 22, YELLOW)
	ping_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	ping_label.offset_left = -260
	ping_label.offset_right = 260
	ping_label.offset_top = 20
	ping_label.offset_bottom = 60
	ping_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ping_label.add_theme_color_override("font_outline_color", INK)
	ping_label.add_theme_constant_override("outline_size", 8)
	ping_label.mouse_filter = Control.MOUSE_FILTER_IGNORE

	event_label = _label(root, "", 20, YELLOW)
	event_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	event_label.offset_left = -360
	event_label.offset_right = 360
	event_label.offset_top = 96
	event_label.offset_bottom = 136
	event_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	event_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	event_label.add_theme_color_override("font_outline_color", INK)
	event_label.add_theme_constant_override("outline_size", 8)
	event_label.mouse_filter = Control.MOUSE_FILTER_IGNORE

	toast_label = _label(root, "", 18, MINT)
	toast_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	toast_label.offset_left = -260
	toast_label.offset_right = 260
	toast_label.offset_top = 60
	toast_label.offset_bottom = 92
	toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast_label.add_theme_color_override("font_outline_color", INK)
	toast_label.add_theme_constant_override("outline_size", 8)
	toast_label.mouse_filter = Control.MOUSE_FILTER_IGNORE

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
	# What the residents had to say, and the photos that answer them. Both
	# stay hidden unless the run actually produced any.
	complaints_label = _label(card, "", 16, YELLOW)
	complaints_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	complaints_label.custom_minimum_size.x = 545
	complaints_label.visible = false
	photo_strip = HBoxContainer.new()
	photo_strip.add_theme_constant_override("separation", 10)
	photo_strip.visible = false
	card.add_child(photo_strip)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 12)
	card.add_child(actions)
	action_button = _button(actions, "Empezar entrega", true)
	action_button.pressed.connect(_primary_action)
	second_button = _button(actions, "Reiniciar", false)
	second_button.pressed.connect(func() -> void: EventBus.restart_requested.emit())
	# Pausing was a dead end: continue or restart, with no way to reach the
	# options or leave the level at all
	# (docs/critica-diseno-abogado-del-diablo.md section 4).
	options_button = _button(actions, "Opciones", false)
	options_button.pressed.connect(_open_options)
	options_button.visible = false
	menu_button = _button(actions, "Menú", false)
	menu_button.pressed.connect(_leave_to_menu)
	menu_button.visible = false

	options_panel = OptionsPanel.new()
	options_panel.name = "OptionsPanel"
	root.add_child(options_panel)

	# Added last so it paints over everything else, including the pause/
	# results overlay above -- a quick black flash to soften a hard camera
	# cut (boarding a seat) or a scene reload (restarting), not a UI panel.
	fade_rect = ColorRect.new()
	fade_rect.color = Color(0, 0, 0, 0)
	fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fade_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(fade_rect)


func _panel(parent: Node, minimum: Vector2) -> VBoxContainer:
	return UiTheme.panel(parent, minimum)


func _label(parent: Node, value: String, font_size: int, color: Color) -> Label:
	return UiTheme.label(parent, value, font_size, color)


func _bar(parent: Node, color: Color) -> ProgressBar:
	return UiTheme.bar(parent, color)


func _button(parent: Node, value: String, primary: bool) -> Button:
	return UiTheme.button(parent, value, primary, Vector2(190, 48))


func _show_start() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	overlay_mode = "start"
	overlay.visible = true
	dashboard.visible = false
	overlay_body.text = "Cargá el paquete y subite a manejar.\nLa entrega arranca sola apenas estés al volante con la carga a bordo."
	overlay_stats.text = "Caminá hasta el paquete y presioná E para agarrarlo.\nLlevalo hasta la furgoneta y presioná E para dejarlo en su lugar.\nAcercate al asiento del conductor y presioná E para tomar el volante.\n\nWASD caminar     Espacio saltar     Mouse mirar     E interactuar\nR reiniciar     Esc pausa\n\nSeguí la indicación que aparece al acercarte a cada objeto."
	second_button.visible = false
	options_button.visible = true
	menu_button.visible = true
	action_button.text = "Preparar entrega"
	action_button.grab_focus()


func _process(delta: float) -> void:
	time_label.text = "TIEMPO   %02d:%02d" % [int(RunManager.elapsed_seconds) / 60, int(RunManager.elapsed_seconds) % 60]
	if damage_flash > 0.0:
		damage_flash -= delta
		if damage_flash <= 0.0 and not in_delivery:
			hint_label.text = DRIVE_HINT
	_refresh_shortcuts()
	if overlay_mode == "pause" and not get_tree().paused:
		overlay.hide()
		overlay_mode = "run" if RunManager.is_running else "preparation"
	_refresh_cargo_hint()
	if ping_seconds_left > 0.0:
		ping_seconds_left -= delta
		if ping_seconds_left <= 0.0:
			ping_label.text = ""
	if toast_seconds_left > 0.0:
		toast_seconds_left -= delta
		if toast_seconds_left <= 0.0:
			toast_label.text = ""
	if event_seconds_left > 0.0:
		event_seconds_left -= delta
		if event_seconds_left <= 0.0:
			event_label.text = ""


## Full strength while paused or before the run starts, faded to a hint
## once the run is under way. Never hidden outright: a player who forgets
## which key honks shouldn't have to pause to find out.
func _refresh_shortcuts() -> void:
	if shortcut_label == null:
		return
	var learning: bool = get_tree().paused or not RunManager.is_running or RunManager.elapsed_seconds < SHORTCUT_VISIBLE_SECONDS
	var target: float = 1.0 if learning else 0.25
	shortcut_label.modulate.a = move_toward(shortcut_label.modulate.a, target, 0.02)


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
			options_button.show()
			menu_button.show()
			action_button.grab_focus()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("run_restart"):
		EventBus.restart_requested.emit()
		get_viewport().set_input_as_handled()


func _open_options() -> void:
	options_panel.open()


## Leaving mid-run has to put the session back the way the menu expects it:
## unpaused, with the cursor back, and with no half-finished run left in
## RunManager for the next level to inherit.
func _leave_to_menu() -> void:
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	RunManager.reset_run()
	if NetworkManager.is_online():
		NetworkManager.leave_session()
	get_tree().change_scene_to_file.call_deferred("res://scenes/ui/main_menu.tscn")


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
			hint_label.text = "WASD / stick izquierdo caminar · Espacio / X saltar · Mouse / stick derecho mirar · E / A interactuar · Q soltar paquete"
		"pause": EventBus.pause_requested.emit()
		"results": EventBus.restart_requested.emit()


func _on_interaction_prompt(prompt: String) -> void:
	interaction_label.text = "[ E / A ]  " + prompt if not prompt.is_empty() else ""


const PING_DISPLAY_SECONDS: float = 2.5
## Long enough to read a two-clause event line without it becoming furniture.
const EVENT_DISPLAY_SECONDS: float = 6.0


func _on_ping(peer_id: int, _position: Vector3, label: String) -> void:
	var who: String = "Vos" if peer_id == NetworkManager.local_id() else "Jugador %d" % peer_id
	ping_label.text = "📍 %s: %s" % [who, label]
	ping_seconds_left = PING_DISPLAY_SECONDS


## Softens a hard camera cut: fades to black and back over `seconds` total.
## Purely cosmetic (a Tween on a ColorRect's alpha) -- never blocks whatever
## triggered it, so boarding a seat or reloading the level doesn't have to
## wait on this to actually happen.
func _on_quick_fade_requested(seconds: float) -> void:
	var half: float = maxf(seconds * 0.5, 0.01)
	var tween: Tween = create_tween()
	tween.tween_property(fade_rect, ^"color:a", 1.0, half)
	tween.tween_property(fade_rect, ^"color:a", 0.0, half)


func _on_started(_route: StringName, _players: Array) -> void:
	overlay.hide()
	overlay_mode = "run"
	dashboard.show()
	action_button.release_focus()
	interaction_label.text = ""
	hint_label.text = DRIVE_HINT


func _on_team_money_changed(amount: int) -> void:
	economy_label.text = "EQUIPO  $%d" % amount


func _on_merit_changed(peer_id: int, total: int) -> void:
	if peer_id == NetworkManager.local_id():
		_toast("★ Mérito +  ·  %d" % total)


func _on_card_changed(peer_id: int, card: int) -> void:
	if peer_id == NetworkManager.local_id() and card >= 0:
		_toast("🃏 Carta obtenida")


func _toast(text: String) -> void:
	toast_label.text = text
	toast_seconds_left = PING_DISPLAY_SECONDS


func _on_route_event_started(_event_id: StringName, event: Dictionary) -> void:
	event_label.text = "[ EVENTO ]  %s — %s" % [event.get("title", "Evento"), event.get("prompt", "")]
	event_seconds_left = EVENT_DISPLAY_SECONDS


func _on_route_event_resolved(_event_id: StringName, success: bool, _peer_id: int) -> void:
	event_label.text = "Evento resuelto" if success else "Evento fallido"
	event_seconds_left = PING_DISPLAY_SECONDS


func _on_speed(speed: float) -> void:
	speed_label.text = "%02d km/h" % roundi(absf(speed))


func _on_cargo_registered(id: StringName, display_name: String) -> void:
	if cargo_rows.has(id):
		return
	var row := VBoxContainer.new()
	row.add_theme_constant_override("separation", 2)
	cargo_rows_box.add_child(row)
	var label: Label = _label(row, "%s  ·  100%%" % display_name.to_upper(), 17, MINT)
	var bar: ProgressBar = _bar(row, MINT)
	bar.value = 100
	cargo_rows[id] = {"label": label, "bar": bar, "name": display_name.to_upper()}


func _on_integrity(id: StringName, integrity: float, maximum: float) -> void:
	if not cargo_rows.has(id):
		return
	(cargo_rows[id]["bar"] as ProgressBar).value = integrity / maxf(maximum, 0.01) * 100.0
	_refresh_row(id)


func _on_package_state(id: StringName, _state: int) -> void:
	_refresh_row(id)


func _refresh_row(id: StringName) -> void:
	if not cargo_rows.has(id):
		return
	var entry: Dictionary = RunManager.cargo.get(id, {})
	var state: int = int(entry.get("state", 0))
	var integrity: float = float(entry.get("integrity", 100.0))
	var color: Color = [MINT, YELLOW, RED][state]
	var row: Dictionary = cargo_rows[id]
	var label: Label = row["label"]
	label.text = "%s  ·  %d%%  %s" % [row["name"], roundi(integrity), ["", "· EN RIESGO", "· PERDIDO"][state]]
	label.add_theme_color_override("font_color", color)
	((row["bar"] as ProgressBar).get_theme_stylebox("fill") as StyleBoxFlat).bg_color = color


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


func _on_package_hint(package_id: StringName, hint: String) -> void:
	cargo_hints[package_id] = hint


func _refresh_cargo_hint() -> void:
	# Only the most urgent box gets the hint line: with four of them there's
	# no room for four, and the one in trouble is what the player needs now.
	if cargo_hint_label == null or not RunManager.is_running:
		return
	var worst_id: StringName = &""
	var worst_integrity: float = INF
	for id: StringName in RunManager.cargo:
		var entry: Dictionary = RunManager.cargo[id]
		if int(entry.get("state", 0)) == ITrapBehavior.TrapState.RUINED:
			continue
		var value: float = float(entry.get("integrity", 100.0))
		if value < worst_integrity:
			worst_integrity = value
			worst_id = id
	cargo_hint_label.text = String(cargo_hints.get(worst_id, ""))


func _on_ended(score: int, results: Dictionary) -> void:
	overlay_mode = "results"
	overlay.show()
	var best_line: String = "\n\n¡NUEVO RÉCORD!" if bool(results.get("is_new_best", false)) else "\n\nRécord: %d pts" % int(results.get("best_score", 0))
	if results.has("distance_traveled"):
		# Endless (docs/tareas-nacho.md #52): no delivery zone, so there's no
		# "success" state, only how far the run got before it ended.
		overlay_title.text = "FIN DEL RECORRIDO"
		overlay_body.text = String(results["reason"])
		overlay_stats.text = "%d PUNTOS     /     %.0f m recorridos     /     %.1f s%s" % [score, float(results["distance_traveled"]), results["elapsed_seconds"], best_line]
		action_button.text = "Volver a intentar"
		second_button.hide()
		action_button.grab_focus()
		return
	var success: bool = results["delivered"]
	var total: int = int(results.get("cargo_total", 0))
	var intact: int = int(results.get("cargo_intact", 0))
	var ruined: int = int(results.get("cargo_ruined", 0))
	var delivered_doors: int = int(results.get("houses_delivered", 0))
	var missed_doors: int = int(results.get("houses_missed", 0))
	overlay_title.text = "¡ENTREGADO!" if success else "OTRA VUELTA"
	overlay_body.text = _delivery_summary(delivered_doors, missed_doors, total, ruined, intact) if success else String(results["reason"])
	var chaos: float = float(results.get("chaos_multiplier", 1.0))
	var chaos_line: String = "\nBonus por caos compartido: x%.1f" % chaos if chaos > 1.0 else ""
	var door_line: String = "\nPuertas: %d pts" % int(results.get("delivery_points", 0)) if results.has("delivery_points") else ""
	overlay_stats.text = "%d PUNTOS     /     %.1f s\n\nCarga: %d pts   +   Rapidez: %d pts%s%s%s" % [score, results["elapsed_seconds"], results["cargo_points"], results["time_bonus"], door_line, chaos_line, best_line]
	_show_complaints(results.get("complaints", []))
	_show_photos()
	action_button.text = "Volver a intentar"
	second_button.hide()
	options_button.hide()
	menu_button.show()
	action_button.grab_focus()


## The headline leads with the doors, because that's where the run is
## actually won -- what's still in the van is the leftover, not the point.
func _delivery_summary(delivered_doors: int, missed_doors: int, aboard: int, ruined: int, intact: int) -> String:
	var lines: PackedStringArray = []
	if delivered_doors > 0:
		lines.append("Entregaste en %d puerta%s." % [delivered_doors, "" if delivered_doors == 1 else "s"])
	if missed_doors > 0:
		lines.append("%d vecino%s se quedó esperando." % [missed_doors, "" if missed_doors == 1 else "s"])
	if aboard > 0:
		lines.append("Volvieron %d paquetes en la furgoneta, %d intactos." % [aboard - ruined, intact])
	return "\n".join(lines) if not lines.is_empty() else "Llegaste, y eso ya es algo."


## Residents who got a battered box speak up afterwards. The photo taken at
## their door is what settles it -- that's the whole reason to stop and take
## one instead of running straight back to the van.
func _show_complaints(complaints: Array) -> void:
	if complaints.is_empty():
		complaints_label.visible = false
		return
	var lines: PackedStringArray = []
	for complaint: Dictionary in complaints:
		var house: int = int(complaint["house"]) + 1
		if bool(complaint["dismissed"]):
			lines.append("Casa %d reclamó que llegó roto — les mostraste la foto. Caso cerrado." % house)
		else:
			lines.append("Casa %d reclamó que llegó roto y no tenías foto. Te lo descuentan." % house)
	complaints_label.text = "\n".join(lines)
	complaints_label.visible = true


## The shots themselves, as a contact sheet under the numbers. Nothing is
## drawn headless (no framebuffer to capture), so this simply stays hidden.
func _show_photos() -> void:
	for child: Node in photo_strip.get_children():
		child.queue_free()
	var photos: Dictionary = RunManager.delivery_photos
	if photos.is_empty():
		photo_strip.visible = false
		return
	var houses: Array = photos.keys()
	houses.sort()
	for house: int in houses:
		var frame := PanelContainer.new()
		var style := StyleBoxFlat.new()
		style.bg_color = Color(PAPER, 0.9)
		style.set_corner_radius_all(4)
		style.set_content_margin_all(4)
		frame.add_theme_stylebox_override("panel", style)
		var thumbnail := TextureRect.new()
		thumbnail.texture = photos[house]
		thumbnail.custom_minimum_size = Vector2(160, 90)
		thumbnail.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		thumbnail.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		frame.add_child(thumbnail)
		photo_strip.add_child(frame)
	photo_strip.visible = true
