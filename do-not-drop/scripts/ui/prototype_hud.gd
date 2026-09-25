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
const ORANGE: Color = UiTheme.ORANGE
## Package state (OK / at risk / ruined) as bar fill and as text on cream --
## the text versions are darker so they stay readable on the card.
const STATE_FILL: Array[Color] = [UiTheme.MINT, UiTheme.ORANGE, UiTheme.RED]
const STATE_TEXT: Array[Color] = [UiTheme.INK, Color("c26a00"), Color("c73431")]

## Where the local player is, which decides what the hint line teaches.
## Every seated passenger used to be told "W/S acelerar y frenar" for the
## whole run, and the driver was told nothing about the horn.
enum Role { ON_FOOT, DRIVER, PASSENGER }

var root: Control
## Everything that sits over the game while playing -- the corner panels,
## the banners, the interaction prompt -- lives here so GameSettings.hud_scale
## can resize it as one. The pause/results card and the options stay on
## root at their own size.
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
## package id -> {"label": Label, "bar": ProgressBar}
var cargo_rows: Dictionary = {}
## package id -> hint text, kept fresh by package_hint_changed rather than
## read straight off the package node -- on a client, that node is a frozen
## puppet whose trap never advances locally, so its hint would never change.
var cargo_hints: Dictionary = {}
var route_bar: ProgressBar
## Rich text so each key in the hint line can be drawn as a keycap.
var hint_label: RichTextLabel
var overlay: ColorRect
var card: VBoxContainer
var overlay_kicker: Label
var overlay_title: Label
var overlay_body: Label
var overlay_stats: Label
## Results only: the score as the hero of the card, and the record ribbon.
var score_label: Label
var record_label: Label
var action_button: Button
var second_button: Button
var options_button: Button
var menu_button: Button
var options_panel: OptionsPanel
## The depot's station screens (lockers, workshop, supplies, board).
var depot_panel: DepotPanel
## Today's orders as the depot posted them (depot_orders_posted).
var _orders: Array = []
var _prep_refresh: float = 0.0
## "start", "preparation", "run", "pause", "results" or "disconnected".
var overlay_mode: String = "start"
var in_delivery: bool = false
var interaction_label: Label
## The raw prompt from the interactable, so it can be re-rendered with the
## other device's button the moment the player switches.
var _interaction_prompt: String = ""
var _lid_action: String = ""
var _lid_inside: String = ""
var _carrying: bool = false
var ping_label: Label
var ping_indicator: Label
var ping_seconds_left: float = 0.0
## Route events used to overwrite interaction_label, and merit/card notices
## used to overwrite ping_label -- so an event banner erased "[E] Agarrar
## paquete" mid-reach, and a teammate's ping vanished behind a card notice.
## Each kind of message gets its own line and its own clock now.
var event_label: Label
var event_seconds_left: float = 0.0
var _route_event_active_id: StringName = &""
var toast_label: Label
var toast_seconds_left: float = 0.0
var complaints_label: Label
var photo_strip: HBoxContainer
var fade_rect: ColorRect
## A peripheral warning leaves the center clear for lifting/aiming. It is
## driven from the authoritative cargo records rather than a local guessed
## trap state, so every passenger sees the same urgency.
var risk_vignette: ColorRect
## The keyboard cheat sheet along the bottom. It used to sit there for the
## whole run, competing with everything else on screen long after anyone
## needed it (docs/critica-diseno-abogado-del-diablo.md section 5). It fades
## out once the run has been going a while and comes straight back whenever
## the game is paused, which is when someone is actually looking for it.
var shortcut_label: RichTextLabel
const SHORTCUT_VISIBLE_SECONDS: float = 25.0

## A hit or the delivery zone briefly takes over the hint line; once the
## clock runs out it goes back to teaching whatever the player is doing.
var _hint_override: String = ""
var _hint_override_seconds: float = 0.0
var _role: int = Role.ON_FOOT
## Online, pausing the tree would freeze the host's simulation for everyone
## (or desync a client), so the menu opens over a game that keeps running.
var _soft_pause: bool = false
## R used to restart on the spot, mid-run, with no way back: one stray key
## (or Y on a gamepad) threw the whole delivery away. During play it has to
## be held now; on the pause and results screens it's still instant, since
## that's a menu choice rather than a slip.
const RESTART_HOLD_SECONDS: float = 0.9
var _restart_hold: float = 0.0
var _is_endless: bool = false
var _local_merit_total: int = 0


func _ready() -> void:
	var level: Node = get_parent()
	_is_endless = level != null and &"distance_traveled" in level
	_local_merit_total = int(CrewProgression.merit.get(NetworkManager.local_id(), 0))
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
	EventBus.carry_changed.connect(_on_carry_changed)
	EventBus.package_lid_hint_changed.connect(_on_lid_hint_changed)
	EventBus.cargo_registered.connect(_on_cargo_registered)
	EventBus.package_hint_changed.connect(_on_package_hint)
	EventBus.ping_sent.connect(_on_ping)
	EventBus.quick_fade_requested.connect(_on_quick_fade_requested)
	EventBus.team_money_changed.connect(_on_team_money_changed)
	EventBus.merit_changed.connect(_on_merit_changed)
	EventBus.card_changed.connect(_on_card_changed)
	EventBus.route_event_started.connect(_on_route_event_started)
	EventBus.route_event_updated.connect(_on_route_event_updated)
	EventBus.route_event_resolved.connect(_on_route_event_resolved)
	EventBus.unlock_earned.connect(_on_unlock_earned)
	EventBus.depot_orders_posted.connect(func(orders: Array) -> void: _orders = orders)
	EventBus.depot_station_opened.connect(_on_depot_station_opened)
	EventBus.depot_notice.connect(_toast)
	var truck_view: Node = get_tree().get_first_node_in_group(&"vehicle")
	if truck_view != null:
		var spectator: Node = truck_view.find_child("SpectatorCamera", true, false)
		if spectator != null:
			spectator.connect(&"availability_changed", func(available: bool) -> void:
				if available:
					_toast("Tu caja ya no tiene arreglo  ·  %s: ver desde afuera" % _key("Tab", "Back")))
	EventBus.house_refused_package.connect(func(house_index: int, expected: String) -> void:
		_toast("Casa %d: \"Ese no es mío, pedí %s\"" % [house_index + 1, expected.to_lower()]))
	NetworkManager.roster_changed.connect(_on_roster_changed)
	NetworkManager.session_failed.connect(_on_connection_lost)
	GameSettings.input_device_changed.connect(_on_input_device_changed)
	GameSettings.hud_scale_changed.connect(func(_scale: float) -> void: _apply_hud_scale())
	root.resized.connect(_apply_hud_scale)
	_apply_hud_scale()
	_refresh_session()
	_refresh_shortcut_text()
	_refresh_card()
	_show_start()


func _build_ui() -> void:
	root = Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UiTheme.apply(root)
	add_child(root)
	risk_vignette = ColorRect.new()
	risk_vignette.color = Color(0.62, 0.05, 0.04, 0.0)
	risk_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	risk_vignette.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	risk_vignette.material = _vignette_material()
	root.add_child(risk_vignette)
	hud_layer = Control.new()
	hud_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(hud_layer)
	var margin := MarginContainer.new()
	hud_layer.add_child(margin)
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 24)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dashboard = VBoxContainer.new()
	margin.add_child(dashboard)
	dashboard.add_theme_constant_override("separation", 12)
	dashboard.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# --- Top: who's playing (left), the van's numbers (right) ---
	var top := HBoxContainer.new()
	dashboard.add_child(top)
	top.add_theme_constant_override("separation", 16)
	# This corner used to be a permanent "DO NOT DROP / PRUEBA DE RUTA / 01"
	# logo. It says who's in the session now -- and, hosting over LAN, the
	# IP friends need, which the menu only ever showed for the single frame
	# before loading the level.
	var brand := _panel(top, Vector2.ZERO)
	brand.get_parent().size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	brand.add_theme_constant_override("separation", 6)
	UiTheme.title(brand, "TAKE MY PACKAGE", 22)
	session_label = UiTheme.tag(brand, "", MINT, -1.5, 14)
	var stretch := Control.new()
	stretch.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stretch.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(stretch)
	var metrics := _panel(top, Vector2(210, 0))
	metrics.get_parent().size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	metrics.add_theme_constant_override("separation", 6)
	var speed_row := HBoxContainer.new()
	speed_row.add_theme_constant_override("separation", 6)
	metrics.add_child(speed_row)
	speed_label = UiTheme.title(speed_row, "00", 50)
	speed_unit_label = UiTheme.label(speed_row, "km/h", 16, MUTED)
	speed_unit_label.size_flags_vertical = Control.SIZE_SHRINK_END
	var chips := HBoxContainer.new()
	chips.add_theme_constant_override("separation", 8)
	metrics.add_child(chips)
	time_label = UiTheme.chip(chips, "00:00", UiTheme.SKY, 17)
	economy_label = UiTheme.chip(chips, "$%d" % CrewProgression.team_money, YELLOW, 17)
	card_label = _rich(metrics, 14)
	card_label.custom_minimum_size.x = 190
	card_label.add_theme_color_override("default_color", INK)

	var space := Control.new()
	space.size_flags_vertical = Control.SIZE_EXPAND_FILL
	space.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dashboard.add_child(space)

	# --- Bottom: the cargo (left), the objective (right) ---
	var bottom := HBoxContainer.new()
	dashboard.add_child(bottom)
	bottom.add_theme_constant_override("separation", 16)
	var cargo := _panel(bottom, Vector2(330, 0))
	cargo.get_parent().size_flags_vertical = Control.SIZE_SHRINK_END
	UiTheme.tag(cargo, "CARGA", UiTheme.CARDBOARD, -2.0, 15)
	cargo_rows_box = VBoxContainer.new()
	cargo_rows_box.add_theme_constant_override("separation", 10)
	cargo.add_child(cargo_rows_box)
	cargo_hint_label = _label(cargo, "", 15, MUTED)
	cargo_hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	cargo_hint_label.custom_minimum_size.x = 285
	var delivery := _panel(bottom, Vector2.ZERO)
	delivery.get_parent().size_flags_horizontal = Control.SIZE_EXPAND_FILL
	delivery.get_parent().size_flags_vertical = Control.SIZE_SHRINK_END
	delivery.add_theme_constant_override("separation", 8)
	section_label = UiTheme.tag(delivery, "PREPARACIÓN", MINT, -1.5, 15)
	# Used to open on "220 m hasta la entrega", a leftover from the fixed
	# route: the real one is random and runs closer to 2000 m.
	distance_label = UiTheme.title(delivery, "", 30)
	route_bar = UiTheme.bar(delivery, MINT, 16)
	route_bar.visible = not _is_endless
	hint_label = _rich(delivery, 16)

	var shortcut_pill := PanelContainer.new()
	var pill_style := StyleBoxFlat.new()
	pill_style.bg_color = Color(INK, 0.82)
	pill_style.set_corner_radius_all(99)
	pill_style.content_margin_left = 18
	pill_style.content_margin_right = 18
	pill_style.content_margin_top = 5
	pill_style.content_margin_bottom = 6
	shortcut_pill.add_theme_stylebox_override("panel", pill_style)
	shortcut_pill.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	shortcut_pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dashboard.add_child(shortcut_pill)
	shortcut_label = _rich(shortcut_pill, 15)
	shortcut_label.add_theme_color_override("default_color", PAPER)
	shortcut_label.fit_content = true
	shortcut_label.autowrap_mode = TextServer.AUTOWRAP_OFF

	ping_label = UiTheme.floating_label(hud_layer, "", 26, YELLOW, 560, 20)
	ping_indicator = UiTheme.floating_label(hud_layer, "", 34, YELLOW, 260, 0)
	ping_indicator.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	ping_indicator.offset_left = -130
	ping_indicator.offset_right = 130
	ping_indicator.offset_top = -190
	ping_indicator.offset_bottom = -145
	toast_label = UiTheme.floating_label(hud_layer, "", 21, MINT, 560, 64)
	event_label = UiTheme.floating_label(hud_layer, "", 23, YELLOW, 760, 104)
	interaction_label = UiTheme.floating_label(hud_layer, "", 25, PAPER, 560, 0)
	# Just under the crosshair, where the eye already is when reaching for
	# something -- not with the banners along the top.
	interaction_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	interaction_label.offset_left = -280
	interaction_label.offset_right = 280
	interaction_label.offset_top = 45
	interaction_label.offset_bottom = 95

	overlay = ColorRect.new()
	root.add_child(overlay)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.color = Color(UiTheme.BACKDROP, 0.72)
	var center := CenterContainer.new()
	overlay.add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	card = _panel(center, Vector2(640, 0))
	card.add_theme_constant_override("separation", 14)
	overlay_kicker = UiTheme.tag(card, "", YELLOW, -2.0, 16)
	overlay_title = UiTheme.title(card, "¡A REPARTIR!", 62)
	var hero := HBoxContainer.new()
	hero.add_theme_constant_override("separation", 14)
	card.add_child(hero)
	score_label = UiTheme.chip(hero, "", YELLOW, 40)
	record_label = UiTheme.tag(hero, "¡NUEVO RÉCORD!", UiTheme.GRAPE, 4.0, 20)
	record_label.add_theme_color_override("font_color", UiTheme.WHITE)
	record_label.get_parent().size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_set_hero(false)
	overlay_body = _label(card, "", 21, INK)
	overlay_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	overlay_body.custom_minimum_size.x = 575
	overlay_stats = _label(card, "", 17, MUTED)
	overlay_stats.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	overlay_stats.custom_minimum_size.x = 575
	# What the residents had to say, and the photos that answer them. Both
	# stay hidden unless the run actually produced any.
	complaints_label = _label(card, "", 17, STATE_TEXT[1])
	complaints_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	complaints_label.custom_minimum_size.x = 575
	complaints_label.visible = false
	photo_strip = HBoxContainer.new()
	photo_strip.add_theme_constant_override("separation", 14)
	photo_strip.visible = false
	card.add_child(photo_strip)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 12)
	card.add_child(actions)
	action_button = _button(actions, "Empezar entrega", true)
	action_button.pressed.connect(_primary_action)
	second_button = _button(actions, "Reiniciar", false)
	second_button.pressed.connect(_request_restart)
	# Pausing was a dead end: continue or restart, with no way to reach the
	# options or leave the level at all
	# (docs/critica-diseno-abogado-del-diablo.md section 4).
	options_button = _button(actions, "Opciones", false)
	options_button.pressed.connect(_open_options)
	menu_button = _button(actions, "Menú", false)
	menu_button.pressed.connect(_leave_to_menu)

	options_panel = OptionsPanel.new()
	options_panel.name = "OptionsPanel"
	root.add_child(options_panel)
	depot_panel = DepotPanel.new()
	depot_panel.name = "DepotPanel"
	root.add_child(depot_panel)
	# Back to the button that opened it: otherwise a gamepad player comes
	# back from the options with nothing focused and no way to move.
	options_panel.closed.connect(func() -> void:
		_refresh_card()
		if overlay.visible:
			options_button.grab_focus())

	# Added last so it paints over everything else, including the pause/
	# results overlay above -- a quick black flash to soften a hard camera
	# cut (boarding a seat) or a scene reload (restarting), not a UI panel.
	fade_rect = ColorRect.new()
	fade_rect.color = Color(0, 0, 0, 0)
	fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fade_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(fade_rect)


## Scaling a full-rect Control would push its right and bottom edges off
## screen, so the layer is laid out at screen size / scale and then scaled
## back up (or down) to cover the screen exactly -- anchored panels stay in
## their corners at any size.
func _apply_hud_scale() -> void:
	if hud_layer == null:
		return
	var hud_scale: float = GameSettings.hud_scale
	hud_layer.position = Vector2.ZERO
	hud_layer.scale = Vector2(hud_scale, hud_scale)
	hud_layer.size = root.size / hud_scale


## The score chip and record ribbon only belong on the results card.
func _set_hero(visible_: bool, score: int = 0, new_best: bool = false) -> void:
	var hero: Control = score_label.get_parent().get_parent() as Control
	hero.visible = visible_
	score_label.text = "%d PTS" % score
	record_label.get_parent().get_parent().visible = new_best


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


## Shorthand for the device-appropriate half of a prompt.
func _key(keyboard: String, gamepad: String) -> String:
	return GameSettings.prompt(keyboard, gamepad)


## One place decides which overlay buttons exist on each screen -- the
## endless results used to inherit whatever the start screen had left on.
## An empty primary text hides the primary button.
func _set_buttons(primary: String, restart: bool, options: bool, menu: bool) -> void:
	action_button.visible = not primary.is_empty()
	action_button.text = primary
	second_button.visible = restart and _can_restart()
	options_button.visible = options
	menu_button.visible = menu
	var first: Button = action_button if action_button.visible else menu_button
	first.grab_focus()


func _show_start() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	overlay_mode = "start"
	overlay.visible = true
	dashboard.visible = false
	overlay_kicker.text = "%s  ·  PROTOTIPO 0.1" % ("MODO ENDLESS" if _is_endless else "PRUEBA DE RUTA")
	overlay_title.text = "¡A REPARTIR!"
	_set_hero(false)
	overlay_body.text = "Arrancás en el depósito, con el camión estacionado adentro.\nLa entrega sale apenas alguien toma el volante con carga a bordo; el portón se cierra detrás de ustedes."
	overlay_stats.text = "1.  Leé la pizarra de pedidos: cada casa espera un paquete de un estante (A-1, B-6...).\n2.  Buscalo, presioná %s para agarrarlo y %s en el rack del camión para dejarlo.\n3.  Antes de salir: vestuario, taller y mostrador de suministros.\n4.  Subite al asiento del conductor (%s) y salí por el portón.\n\nCada cosa te muestra su indicación cuando te acercás." % [_key("E", "A"), _key("E", "A"), _key("E", "A")]
	_set_buttons("Preparar entrega", false, true, true)


func _process(delta: float) -> void:
	time_label.text = "%02d:%02d" % [int(RunManager.elapsed_seconds) / 60, int(RunManager.elapsed_seconds) % 60]
	_refresh_role()
	_refresh_hint(delta)
	_refresh_shortcuts()
	_refresh_restart_hold(delta)
	_refresh_risk_vignette(delta)
	if overlay_mode == "pause" and not _soft_pause and not get_tree().paused:
		overlay.hide()
		overlay_mode = "run" if RunManager.is_running else "preparation"
	# A panel with buttons keeps the cursor free, even if something captured
	# it after the panel opened (the local player spawns after the start
	# screen shows, and its _ready() grabs the mouse for looking around).
	if overlay.visible and overlay_mode in ["start", "pause", "results", "disconnected"] 			and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_refresh_cargo_hint()
	if overlay_mode == "preparation" and not RunManager.is_running:
		_prep_refresh -= delta
		if _prep_refresh <= 0.0:
			_prep_refresh = 0.25
			distance_label.text = _preparation_text()
	if _is_endless and RunManager.is_running:
		distance_label.text = "%d m recorridos" % roundi(float(get_parent().get(&"distance_traveled")))
	if ping_seconds_left > 0.0:
		ping_seconds_left -= delta
		if ping_seconds_left <= 0.0:
			ping_label.text = ""
			ping_indicator.text = ""
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
	var pill: Control = shortcut_label.get_parent() as Control
	pill.modulate.a = move_toward(pill.modulate.a, target, 0.02)


## The things you can do from anywhere. What depends on where you are (the
## pedals, the package, the seat) lives in the hint line above instead.
func _refresh_shortcut_text() -> void:
	var items: PackedStringArray = [
		_key("F  celular", "LB  celular"),
		_key("Click rueda  ping", "D-pad arriba  ping"),
		_key("C  centrar vista", "Clic stick der.  centrar vista"),
		_key("%s  mirar atrás" % GameSettings.binding_label(&"look_back"), "Clic stick izq.  mirar atrás"),
		_key("Esc  pausa", "Start  pausa"),
	]
	if _can_restart():
		items.append(_key("Mantener R  reiniciar", "Mantener Y  reiniciar"))
	shortcut_label.text = UiTheme.keycaps("   ·   ".join(items), true)


func _refresh_role() -> void:
	_role = _local_role()


func _local_role() -> int:
	var level: Node = get_parent()
	if level == null:
		return Role.ON_FOOT
	var player: Variant = level.get(&"local_player")
	if not is_instance_valid(player):
		return Role.ON_FOOT
	var seat: String = String((player as Node).get(&"seat_node_path"))
	if seat.is_empty():
		return Role.ON_FOOT
	return Role.DRIVER if seat.contains("DriverEyePoint") else Role.PASSENGER


func _flash_hint(text: String, seconds: float) -> void:
	_hint_override = text
	_hint_override_seconds = seconds


func _refresh_hint(delta: float) -> void:
	if _hint_override_seconds > 0.0:
		_hint_override_seconds -= delta
		hint_label.text = "[b]%s[/b]" % _hint_override
		hint_label.add_theme_color_override("default_color", STATE_TEXT[1])
		return
	hint_label.text = UiTheme.keycaps(_base_hint())
	hint_label.add_theme_color_override("default_color", MUTED)


func _base_hint() -> String:
	var waiting: bool = not RunManager.is_running and RunManager.results.is_empty()
	match _role:
		Role.DRIVER:
			if waiting:
				# Seated with nothing aboard is the one way the run silently
				# never starts -- say so instead of teaching the pedals.
				return "Todavía no hay carga a bordo  ·  %s bajarte a buscar un paquete" % _key("E", "A")
			return _key(
				"W/S  acelerar y frenar   ·   A/D  girar   ·   Espacio  freno de mano   ·   H  bocina   ·   E  bajarte",
				"RT  acelerar   ·   LT  frenar   ·   Stick izq.  girar   ·   X  freno de mano   ·   B  bocina   ·   A  bajarte")
		Role.PASSENGER:
			return _key(
				"Click izq. (mantener)  cuidar tu paquete   ·   WASD  secuencias   ·   E  bajarte",
				"RT (mantener)  cuidar tu paquete   ·   Stick izq.  secuencias   ·   A  bajarte")
	if waiting:
		return _key(
			"WASD  caminar   ·   Espacio  saltar   ·   E  agarrar / dejar   ·   Q  soltar paquete",
			"Stick izq.  caminar   ·   X  saltar   ·   A  agarrar / dejar")
	return _key(
		"WASD  caminar   ·   E  interactuar   ·   F  sacar una foto de la entrega",
		"Stick izq.  caminar   ·   A  interactuar   ·   LB  sacar una foto de la entrega")


## Online, only the host may restart: a client reloading its own copy of
## the level tears down the spawner the host replicates players into, and
## comes back to an empty world.
func _can_restart() -> bool:
	return not NetworkManager.is_online() or NetworkManager.is_host()


func _request_restart() -> void:
	if _can_restart():
		EventBus.restart_requested.emit()


func _refresh_restart_hold(delta: float) -> void:
	var playing: bool = overlay_mode == "run" or overlay_mode == "preparation"
	if playing and _can_restart() and Input.is_action_pressed(&"run_restart"):
		_restart_hold += delta
		toast_label.text = "Reiniciando…  soltá para cancelar"
		toast_seconds_left = 0.2
		if _restart_hold >= RESTART_HOLD_SECONDS:
			_restart_hold = 0.0
			_request_restart()
	else:
		_restart_hold = 0.0


func _on_input_device_changed(_gamepad: bool) -> void:
	_refresh_shortcut_text()
	_refresh_card()
	_render_interaction_prompt()
	if overlay_mode == "start":
		_show_start()
	elif overlay_mode == "pause":
		overlay_stats.text = _pause_stats()


func _on_roster_changed(_peer_ids: Array) -> void:
	_refresh_session()


func _refresh_session() -> void:
	if session_label == null:
		return
	var mode: String = "ENDLESS" if _is_endless else "ENTREGA"
	if not NetworkManager.is_online():
		session_label.text = "%s  ·  SOLO" % mode
		_session_color(MINT)
		return
	var count: int = NetworkManager.peer_ids.size()
	var players: String = "%d jugador%s" % [count, "" if count == 1 else "es"]
	if not NetworkManager.is_host():
		session_label.text = "EN SALA  ·  %s" % players
		_session_color(UiTheme.SKY)
	elif NetworkManager.active_transport == NetworkManager.Transport.ENET:
		var address: String = NetworkManager.lan_address()
		session_label.text = "SALA LAN  ·  %s\nIP  %s" % [players, address if not address.is_empty() else "sin red local"]
		_session_color(UiTheme.SKY)
	else:
		session_label.text = "SALA STEAM  ·  %s\nInvitá desde la lista de amigos" % players
		_session_color(UiTheme.GRAPE)


## The session tape changes colour with the mode: mint solo, sky on LAN or
## as a guest, grape on Steam -- readable at a glance before the words are.
func _session_color(color: Color) -> void:
	var holder: PanelContainer = session_label.get_parent() as PanelContainer
	var style: StyleBoxFlat = holder.get_theme_stylebox("panel").duplicate()
	style.bg_color = color
	holder.add_theme_stylebox_override("panel", style)


func _unhandled_input(event: InputEvent) -> void:
	if depot_panel != null and depot_panel.visible:
		return
	if event.is_action_pressed("ui_pause"):
		match overlay_mode:
			"pause":
				_resume()
			"run", "preparation":
				_pause()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("run_restart"):
		# Instant only where it's clearly a menu choice; during play it's the
		# hold in _refresh_restart_hold().
		if overlay_mode == "pause" or overlay_mode == "results":
			_request_restart()
			get_viewport().set_input_as_handled()


func _pause() -> void:
	if NetworkManager.is_online():
		_soft_pause = true
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	else:
		EventBus.pause_requested.emit()
		if not get_tree().paused:
			return
	overlay_mode = "pause"
	overlay.show()
	overlay_kicker.text = "PAUSA"
	overlay_title.text = "EN PAUSA" if not _soft_pause else "MENÚ"
	overlay_body.text = "Tu entrega puede esperar." if not _soft_pause else "La partida sigue corriendo para el resto del equipo."
	overlay_stats.text = _pause_stats()
	complaints_label.visible = false
	photo_strip.visible = false
	_set_hero(false)
	_set_buttons("Continuar", true, true, true)


func _pause_stats() -> String:
	return "%s para volver a la ruta." % _key("Esc", "Start")


func _resume() -> void:
	if _soft_pause:
		_soft_pause = false
		overlay.hide()
		overlay_mode = "run" if RunManager.is_running else "preparation"
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	else:
		EventBus.pause_requested.emit()


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
			distance_label.text = _preparation_text()
		"pause": _resume()
		"results": _request_restart()
		"disconnected": _leave_to_menu()


## The objective while still in the depot: each house's order and whether
## it's aboard yet, read off the boxes themselves.
func _preparation_text() -> String:
	if _orders.is_empty():
		return "Cargá paquetes y tomá el volante"
	var parts: PackedStringArray = []
	for order: Dictionary in _orders:
		var aboard: bool = false
		for package: Node in get_tree().get_nodes_in_group(&"cargo"):
			if StringName(package.get(&"package_id")) == StringName(order.package_id):
				aboard = bool(package.get(&"is_loaded"))
				break
		parts.append("Casa %d: %s %s" % [int(order.house) + 1, order.code, "(a bordo)" if aboard else "(falta)"])
	return "   ".join(parts)


func _on_depot_station_opened(station: StringName) -> void:
	if overlay_mode != "preparation" or RunManager.is_running:
		return
	var level: Node = get_parent()
	depot_panel.open(station, level.get(&"depot") if level != null and &"depot" in level else null)


func _on_interaction_prompt(prompt: String) -> void:
	_interaction_prompt = prompt
	_render_interaction_prompt()


func _on_carry_changed(carrying: bool) -> void:
	_carrying = carrying
	_render_interaction_prompt()


func _render_interaction_prompt() -> void:
	var lines: PackedStringArray = []
	if not _interaction_prompt.is_empty():
		lines.append("[ %s ]  %s" % [_key("E", "A"), _interaction_prompt])
	if _carrying:
		lines.append("[ %s ]  Soltar paquete" % _key("Q", "B"))
	if not _lid_action.is_empty():
		lines.append("[ %s ]  %s" % [_key("T", "D-pad abajo"), _lid_action])
	if not _lid_inside.is_empty():
		lines.append("Adentro:  %s" % _lid_inside)
	interaction_label.text = "\n".join(lines)


func _on_lid_hint_changed(action: String, inside: String) -> void:
	_lid_action = action
	_lid_inside = inside
	_render_interaction_prompt()


const PING_DISPLAY_SECONDS: float = 2.5
## Long enough to read a two-clause event line without it becoming furniture.
const EVENT_DISPLAY_SECONDS: float = 6.0


func _on_ping(peer_id: int, _position: Vector3, label: String) -> void:
	# No emoji: the default font has none, and a fallback isn't guaranteed on
	# every machine -- a box glyph in front of a ping reads as a bug.
	var who: String = "Vos" if peer_id == NetworkManager.local_id() else "Jugador %d" % peer_id
	ping_label.text = "%s:  %s" % [who, label]
	ping_indicator.text = _ping_arrow(_position) + "  PING"
	ping_seconds_left = PING_DISPLAY_SECONDS
	if peer_id != NetworkManager.local_id():
		_mark_pinger(peer_id)


## A marker over whoever pinged (tareas de Slatex #32), drawn through the
## truck's walls, so you know who called without turning around to look.
func _mark_pinger(peer_id: int) -> void:
	for player: Node in get_tree().get_nodes_in_group(&"player"):
		if player.get_multiplayer_authority() != peer_id or not player is Node3D:
			continue
		var old: Node = player.get_node_or_null(^"PingMarker")
		if old != null:
			old.free()
		var marker := Label3D.new()
		marker.name = "PingMarker"
		marker.text = "!"
		marker.font = load(UiTheme.DISPLAY_FONT_PATH)
		marker.font_size = 110
		marker.outline_size = 18
		marker.modulate = UiTheme.YELLOW
		marker.outline_modulate = UiTheme.INK
		marker.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		marker.no_depth_test = true
		marker.fixed_size = true
		marker.pixel_size = 0.0009
		marker.position = Vector3(0.0, 2.25, 0.0)
		player.add_child(marker)
		var tween := marker.create_tween()
		tween.tween_interval(PING_DISPLAY_SECONDS - 0.6)
		tween.tween_property(marker, ^"modulate:a", 0.0, 0.6)
		tween.tween_callback(marker.queue_free)


func _ping_arrow(world_position: Vector3) -> String:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return "PING"
	var local: Vector3 = camera.global_transform.basis.inverse() * (world_position - camera.global_position)
	if absf(local.x) > absf(local.y):
		return "→" if local.x > 0.0 else "←"
	return "↓" if local.y > 0.0 else "↑"


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
	if WorldMood.active.has("description"):
		_toast("Ruta de hoy: %s" % String(WorldMood.active["description"]).to_lower())
	overlay.hide()
	overlay_mode = "run"
	dashboard.show()
	action_button.release_focus()
	_interaction_prompt = ""
	interaction_label.text = ""
	if _is_endless:
		section_label.text = "ENDLESS"
		distance_label.text = "0 m recorridos"


func _on_team_money_changed(amount: int) -> void:
	economy_label.text = "$%d" % amount


func _on_merit_changed(peer_id: int, total: int) -> void:
	if peer_id == NetworkManager.local_id():
		var gained: int = maxi(total - _local_merit_total, 0)
		_local_merit_total = total
		_toast("Mérito +%d  ·  total %d" % [gained, total])


func _on_card_changed(peer_id: int, card_id: int) -> void:
	if peer_id != NetworkManager.local_id():
		return
	_refresh_card()
	if card_id >= 0:
		_toast("Carta obtenida: %s" % CrewProgression.card_name(card_id))


func _refresh_card() -> void:
	if card_label == null:
		return
	var card_id: int = int(CrewProgression.cards.get(NetworkManager.local_id(), -1))
	card_label.visible = card_id >= 0
	if card_id < 0:
		card_label.text = ""
		return
	var action: String = GameSettings.prompt("%s  usar" % GameSettings.binding_label(&"use_card"), "D-pad izquierda  usar")
	card_label.text = UiTheme.keycaps("CARTA: %s   ·   %s" % [CrewProgression.card_name(card_id), action])


func _on_unlock_earned(_unlock_id: StringName, title: String) -> void:
	_toast("¡Desbloqueaste %s!" % title)


func _toast(text: String) -> void:
	toast_label.text = text
	toast_seconds_left = PING_DISPLAY_SECONDS


func _on_route_event_started(_event_id: StringName, event: Dictionary) -> void:
	if bool(event.get("incident", false)):
		_toast("%s — %s" % [event.get("title", "Incidente"), event.get("prompt", "")])
		return
	_route_event_active_id = _event_id
	_on_route_event_updated(_event_id, event)
	event_label.add_theme_color_override("font_color", YELLOW)
	event_seconds_left = 0.0


func _on_route_event_updated(_event_id: StringName, event: Dictionary) -> void:
	if bool(event.get("incident", false)):
		return
	var objective: String = String(event.get("prompt", ""))
	if _event_id == &"inspection" and int(event.get("loose", 0)) > 0:
		objective = "Faltan asegurar %d cajas" % int(event["loose"])
	elif _event_id == &"mixed_labels" and event.get("phase") == &"swapped":
		objective = "%s  ?" % objective
	var seconds: int = ceili(float(event.get("remaining", 0.0)))
	event_label.text = "%s\n%s\n%02d:%02d" % [event.get("title", "Evento"), objective, seconds / 60, seconds % 60]
	if _event_id in [&"mixed_labels", &"mimetic_package"]:
		for id: StringName in cargo_rows:
			_refresh_row(id)


func _on_route_event_resolved(_event_id: StringName, success: bool, _peer_id: int) -> void:
	if _event_id not in RouteEventManager.EVENTS:
		return
	if _route_event_active_id == _event_id:
		_route_event_active_id = &""
	for id: StringName in cargo_rows:
		_refresh_row(id)
	event_label.text = "Evento resuelto" if success else "Evento fallido"
	event_label.add_theme_color_override("font_color", MINT if success else RED)
	event_seconds_left = PING_DISPLAY_SECONDS


func _on_speed(speed: float) -> void:
	speed_label.text = "%02d" % roundi(absf(speed))


func _on_cargo_registered(id: StringName, display_name: String) -> void:
	if cargo_rows.has(id):
		return
	# One row per box: its trap's icon, name and health, then a chunky bar.
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


## Somebody pulled a box back from the brink (tareas de Slatex #91): the
## whole crew hears a bright chime, its row flashes and a toast names it --
## the save gets as much attention as the scare did.
var _last_states: Dictionary = {}
var _rescue_player: AudioStreamPlayer


func _celebrate_rescue(id: StringName) -> void:
	var name_text: String = String(cargo_rows[id]["name"]) if cargo_rows.has(id) else "LA CARGA"
	_toast("¡%s a salvo!" % name_text.capitalize())
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
	label.text = "%s  ·  %d%%  %s" % [display_name, roundi(integrity), ["", "· ¡EN RIESGO!", "· PERDIDO"][state]]
	label.add_theme_color_override("font_color", STATE_TEXT[state])
	((row["bar"] as ProgressBar).get_theme_stylebox("fill") as StyleBoxFlat).bg_color = STATE_FILL[state]
	# A lost box's icon greys out, so the row reads "gone" before the words do.
	(row["icon"] as TextureRect).modulate = Color(1, 1, 1, 0.35) if state == 2 else Color.WHITE


func _on_damage(_id: StringName, damage: float) -> void:
	_flash_hint("¡Golpe!  −%d de integridad. Bajá la velocidad antes del próximo obstáculo." % roundi(damage), 2.5)


func _on_progress(progress: float, meters: float, section: String) -> void:
	route_bar.value = progress * 100.0
	distance_label.text = "%d m hasta la entrega" % ceili(meters)
	section_label.text = section.to_upper()


func _on_delivery(in_zone: bool, stopped: float) -> void:
	if in_zone:
		# Re-sent every physics frame while inside, so a short clock is
		# enough to keep it up and lets it lapse the moment the van leaves.
		_flash_hint("Mantené la camioneta detenida…" if stopped > 0.0 else "¡Llegaste! Frená dentro de la zona marcada para entregar.", 0.25)
	elif in_delivery:
		_flash_hint("Volvé a la zona de entrega y detené la camioneta.", 3.0)
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


## A client whose host vanished used to be left driving a frozen puppet van
## with no word of what happened and only Alt+F4 to get out.
func _on_connection_lost(reason: String) -> void:
	get_tree().paused = false
	_soft_pause = false
	overlay_mode = "disconnected"
	overlay.show()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	overlay_kicker.text = "MULTIJUGADOR"
	overlay_title.text = "SIN CONEXIÓN"
	overlay_body.text = reason
	overlay_stats.text = "La partida del anfitrión ya no está disponible."
	_set_hero(false)
	complaints_label.visible = false
	photo_strip.visible = false
	_set_buttons("Volver al menú", false, false, false)


func _on_ended(score: int, results: Dictionary) -> void:
	_soft_pause = false
	overlay_mode = "results"
	overlay.show()
	overlay_kicker.text = "RESULTADO"
	var new_best: bool = bool(results.get("is_new_best", false))
	_set_hero(true, score, new_best)
	var best_line: String = "" if new_best else "\nRécord: %d pts" % int(results.get("best_score", 0))
	var retry: String = "Volver a intentar" if _can_restart() else ""
	var client_line: String = "" if _can_restart() else "\n\nSolo el anfitrión puede reiniciar. Para otra vuelta, volvé al menú y unite de nuevo a la sala."
	if results.has("distance_traveled"):
		# Endless (docs/tareas-nacho.md #52): no delivery zone, so there's no
		# "success" state, only how far the run got before it ended.
		overlay_title.text = "FIN DEL RECORRIDO"
		overlay_body.text = String(results["reason"])
		overlay_stats.text = "%.0f m recorridos   ·   %.1f s%s%s" % [float(results["distance_traveled"]), results["elapsed_seconds"], best_line, client_line]
		complaints_label.visible = false
		photo_strip.visible = false
		_set_buttons(retry, false, false, true)
		return
	var success: bool = results["delivered"]
	var total: int = int(results.get("cargo_total", 0))
	var intact: int = int(results.get("cargo_intact", 0))
	var ruined: int = int(results.get("cargo_ruined", 0))
	var delivered_doors: int = int(results.get("houses_delivered", 0))
	var missed_doors: int = int(results.get("houses_missed", 0))
	# Reaching the end without a single door isn't a delivery, whatever the
	# run's own success flag says -- the headline shouldn't cheer over it.
	if not success:
		overlay_title.text = "OTRA VUELTA"
	elif delivered_doors == 0 and missed_doors > 0:
		overlay_title.text = "RUTA TERMINADA"
	else:
		overlay_title.text = "¡ENTREGADO!"
	overlay_body.text = _delivery_summary(delivered_doors, missed_doors, total, ruined, intact) if success else String(results["reason"])
	var chaos: float = float(results.get("chaos_multiplier", 1.0))
	var chaos_line: String = "\nBonus por caos compartido: x%.1f" % chaos if chaos > 1.0 else ""
	var door_line: String = "\nPuertas: %d pts" % int(results.get("delivery_points", 0)) if results.has("delivery_points") else ""
	if results.has("breakdown"):
		overlay_stats.text = score_breakdown_text(results, score) + best_line + client_line
	else:
		overlay_stats.text = "En ruta: %.1f s\nCarga: %d pts   +   Rapidez: %d pts%s%s%s%s" % [results["elapsed_seconds"], results["cargo_points"], results["time_bonus"], door_line, chaos_line, best_line, client_line]
	_show_complaints(results.get("complaints", []))
	_show_photos()
	_set_buttons(retry, false, false, true)


## The score as a sum you can check (tareas de Slatex #89): one line per
## thing that earned or cost points, the shared-chaos multiplier, the total.
static func score_breakdown_text(results: Dictionary, score: int) -> String:
	var lines: PackedStringArray = ["En ruta: %.1f s" % float(results.get("elapsed_seconds", 0.0))]
	for line: Dictionary in results.get("breakdown", []):
		var points: int = int(line["points"])
		lines.append("%s   %s%d" % [String(line["label"]), "+" if points >= 0 else "−", absi(points)])
	var chaos: float = float(results.get("chaos_multiplier", 1.0))
	if chaos > 1.0:
		lines.append("Caos compartido   ×%.1f" % chaos)
	lines.append("Total   %d pts" % score)
	return "\n".join(lines)


## The headline leads with the doors, because that's where the run is
## actually won -- what's still in the van is the leftover, not the point.
func _delivery_summary(delivered_doors: int, missed_doors: int, aboard: int, ruined: int, intact: int) -> String:
	var lines: PackedStringArray = []
	if delivered_doors > 0:
		lines.append("Entregaste en %d puerta%s." % [delivered_doors, "" if delivered_doors == 1 else "s"])
	if missed_doors > 0:
		lines.append("1 vecino se quedó esperando." if missed_doors == 1 else "%d vecinos se quedaron esperando." % missed_doors)
	if aboard > 0:
		var back: int = aboard - ruined
		if back == 1:
			lines.append("Volvió 1 paquete en la furgoneta%s." % (", intacto" if intact >= 1 else ""))
		elif back > 1:
			lines.append("Volvieron %d paquetes en la furgoneta, %d intactos." % [back, intact])
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
	for index: int in range(houses.size()):
		var house: int = houses[index]
		# Polaroids, each stuck on at its own slight angle.
		var frame := PanelContainer.new()
		var style := StyleBoxFlat.new()
		style.bg_color = UiTheme.WHITE
		style.border_color = INK
		style.set_border_width_all(2)
		style.set_corner_radius_all(3)
		style.set_content_margin_all(6)
		style.content_margin_bottom = 22
		style.shadow_color = INK
		style.shadow_size = 1
		style.shadow_offset = Vector2(0, 4)
		frame.add_theme_stylebox_override("panel", style)
		frame.rotation_degrees = [-3.0, 2.0, -1.5, 3.0][index % 4]
		var thumbnail := TextureRect.new()
		thumbnail.texture = photos[house]
		thumbnail.custom_minimum_size = Vector2(160, 90)
		thumbnail.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		thumbnail.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		frame.add_child(thumbnail)
		photo_strip.add_child(frame)
	photo_strip.visible = true
