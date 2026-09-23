extends Control
## The missing link between "multiplayer works" and "a real player can reach
## it": until this existed, the game only ever loaded straight into
## level_base.tscn, offline, with no way to host or join from the UI at all
## -- every connection in this project so far was driven by a test script.
##
## Three ways in:
##   - Jugar solo: no session at all, exactly today's default.
##   - Crear sala: AUTO transport (Steam if it's actually running, else LAN).
##     Steam friends can then join via the friends-list invite --
##     NetworkManager already answers that (join_requested) from anywhere.
##   - Unirse por IP: forces ENet specifically. Steam lobbies aren't joined
##     by typing an address, so this button would be misleading if it went
##     through AUTO and silently tried Steam instead.
##
## The host doesn't wait in a lobby screen for anyone: level_base.gd already
## spawns players dynamically as the roster changes, so jumping straight into
## the level and letting friends join mid-session already works.

# Colours and widgets live in ui_theme.gd now: this screen and the in-game
# HUD used to keep their own copies of the same five constants and drift
# apart one tweak at a time (docs/direccion-visual.md section 3).
const MUTED: Color = UiTheme.MUTED
const MINT: Color = UiTheme.MINT
const RED: Color = UiTheme.RED
const LEVEL_SCENE: String = "res://scenes/gameplay/level_base.tscn"
const ENDLESS_LEVEL_SCENE: String = "res://scenes/gameplay/level_endless.tscn"
const MENU_ART: Texture2D = preload("res://assets/ui/backgrounds/tx_ui_menu_background_1920.png")
const PROGRESS_PANEL_SCRIPT := preload("res://scripts/ui/progress_panel.gd")
const TUTORIAL_PANEL_SCRIPT := preload("res://scripts/ui/tutorial_panel.gd")
const COSMETICS_PANEL_SCRIPT := preload("res://scripts/ui/cosmetics_panel.gd")
const LEADERBOARD_PANEL_SCRIPT := preload("res://scripts/ui/leaderboard_panel.gd")

var _status_label: Label
var _address_field: LineEdit
var _options: OptionsPanel
var _progress: Control
var _tutorial: Control
var _cosmetics: Control
var _leaderboard: Control
var _play_button: Button
var _cancel_button: Button
## Everything that starts a session or opens another screen. Disabled while
## a connection is in flight, so a second click can't start a second one.
var _entry_buttons: Array[Button] = []
var _busy: bool = false:
	set(value):
		_busy = value
		for button: Button in _entry_buttons:
			button.disabled = value
		if _address_field != null:
			_address_field.editable = not value
		if _cancel_button != null:
			_cancel_button.visible = value


func _ready() -> void:
	_build_ui()
	NetworkManager.session_ready.connect(_on_session_ready)
	NetworkManager.session_failed.connect(_on_session_failed)
	_handle_cmdline_args()


func _handle_cmdline_args() -> void:
	# Same shortcut level_base.gd already honours for smoke checks and quick
	# iteration -- skips the menu the same way it skips on-foot loading.
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if "--autostart" in args:
		_play_solo()
		return
	if "--autostart-endless" in args:
		_play_endless()
		return
	if "--host" in args:
		_host_session()
		return
	if "--host-lan" in args:
		# Forces ENet even if Steam happens to be running -- otherwise this
		# and --join= (which also forces ENet) could end up on two different
		# transports and never find each other. Useful for testing, and for
		# anyone who explicitly wants a Steam-free LAN session.
		_host_session(NetworkManager.Transport.ENET)
		return
	for arg: String in args:
		if arg.begins_with("--join="):
			_address_field.text = arg.trim_prefix("--join=")
			_join_by_address()
			return


func _build_ui() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	UiTheme.apply(self)
	var bg := ColorRect.new()
	bg.color = UiTheme.BACKDROP
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	# Key art (2026-09-23): the first thing a player sees should say "delivery
	# van losing its cargo", not a flat colour. The backdrop stays underneath
	# so a missing texture still leaves a usable menu.
	var art := TextureRect.new()
	art.texture = MENU_ART
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(art)

	# Logo over the open sky, top left; the menu card on the right, so the
	# van spilling boxes (the whole joke) stays in view.
	var brand := VBoxContainer.new()
	brand.add_theme_constant_override("separation", 14)
	brand.position = Vector2(64, 48)
	add_child(brand)
	UiTheme.logo(brand, 78)
	var chips := HBoxContainer.new()
	chips.add_theme_constant_override("separation", 10)
	brand.add_child(chips)
	UiTheme.tag(chips, "DELIVERY COOPERATIVO", MINT, -2.0, 16)
	UiTheme.tag(chips, "1 A 5 JUGADORES", UiTheme.SKY, 1.5, 16)
	var stamp: Label = UiTheme.tag(brand, "¡NO LO DEJES CAER!", RED, -5.0, 18)
	stamp.get_parent().size_flags_horizontal = Control.SIZE_SHRINK_BEGIN

	var side := MarginContainer.new()
	side.set_anchors_and_offsets_preset(Control.PRESET_RIGHT_WIDE)
	side.offset_left = -500
	side.add_theme_constant_override("margin_right", 64)
	side.add_theme_constant_override("margin_top", 40)
	side.add_theme_constant_override("margin_bottom", 40)
	add_child(side)
	var holder := CenterContainer.new()
	side.add_child(holder)
	var column: VBoxContainer = UiTheme.panel(holder, Vector2(420, 0), 28)
	column.add_theme_constant_override("separation", 12)
	UiTheme.tag(column, "¿LISTOS PARA REPARTIR?", UiTheme.YELLOW, -1.5, 17)
	_spacer(column, 2)

	_play_button = UiTheme.button(column, "Jugar solo", true, Vector2(0, 62))
	_play_button.add_theme_font_size_override("font_size", 26)
	_play_button.pressed.connect(_play_solo)
	_entry_buttons.append(_play_button)
	_entry_buttons.append(_button(column, "Modo Endless", false))
	_entry_buttons[-1].pressed.connect(_play_endless)
	_entry_buttons.append(_button(column, "Crear sala con amigos", false))
	_entry_buttons[-1].pressed.connect(_host_session)

	_spacer(column, 4)
	_label(column, "Unirse por LAN", 15, MUTED)
	var join_row := HBoxContainer.new()
	join_row.add_theme_constant_override("separation", 10)
	column.add_child(join_row)
	_address_field = UiTheme.line_edit(join_row, "IP del anfitrión")
	_address_field.text = GameSettings.last_join_address
	_address_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# Enter in the field is the obvious way to confirm an address; it used
	# to do nothing and leave the player hunting for the button.
	_address_field.text_submitted.connect(func(_text: String) -> void: _join_by_address())
	_entry_buttons.append(_button(join_row, "Unirse", false))
	_entry_buttons[-1].pressed.connect(_join_by_address)

	_spacer(column, 6)
	var bottom_row := HBoxContainer.new()
	bottom_row.add_theme_constant_override("separation", 10)
	column.add_child(bottom_row)
	var options_button: Button = _button(bottom_row, "Opciones", false)
	options_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	options_button.pressed.connect(_open_options)
	_entry_buttons.append(options_button)
	var progress_button: Button = _button(bottom_row, "Progreso", false)
	progress_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	progress_button.pressed.connect(_open_progress)
	_entry_buttons.append(progress_button)
	var tutorial_button: Button = _button(column, "Cómo jugar", false)
	tutorial_button.pressed.connect(_open_tutorial)
	_entry_buttons.append(tutorial_button)
	var cosmetics_button: Button = _button(column, "Apariencia", false)
	cosmetics_button.pressed.connect(_open_cosmetics)
	_entry_buttons.append(cosmetics_button)
	var leaderboard_button: Button = _button(column, "Récords", false)
	leaderboard_button.pressed.connect(_open_leaderboard)
	_entry_buttons.append(leaderboard_button)
	# A game you can only leave with Alt+F4 reads as unfinished before a
	# player has pressed anything (docs/critica-diseno-abogado-del-diablo.md
	# section 4).
	var quit_button: Button = _button(bottom_row, "Salir", false)
	quit_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	quit_button.pressed.connect(_quit_game)

	_status_label = _label(column, "", 15, MUTED)
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status_label.visible = false
	# Only while a connection is in flight: a join to a wrong IP used to
	# leave every button dead until the timeout, with no way back out.
	_cancel_button = _button(column, "Cancelar", false)
	_cancel_button.pressed.connect(_cancel_connection)
	_cancel_button.visible = false

	var footer: Label = UiTheme.chip(self, "Prototipo 0.1   ·   F11 pantalla completa", UiTheme.WHITE, 14)
	var footer_holder: Control = footer.get_parent()
	footer_holder.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	footer_holder.offset_left = 24
	footer_holder.offset_top = -52
	footer_holder.offset_bottom = -20
	footer_holder.grow_vertical = Control.GROW_DIRECTION_BEGIN

	_options = OptionsPanel.new()
	_options.name = "OptionsPanel"
	add_child(_options)
	_options.closed.connect(options_button.grab_focus)
	_progress = PROGRESS_PANEL_SCRIPT.new()
	_progress.name = "ProgressPanel"
	add_child(_progress)
	_progress.connect(&"closed", progress_button.grab_focus)
	_tutorial = TUTORIAL_PANEL_SCRIPT.new()
	_tutorial.name = "TutorialPanel"
	add_child(_tutorial)
	_tutorial.connect(&"closed", tutorial_button.grab_focus)
	_cosmetics = COSMETICS_PANEL_SCRIPT.new()
	_cosmetics.name = "CosmeticsPanel"
	add_child(_cosmetics)
	_cosmetics.hide()
	_cosmetics.connect(&"closed", cosmetics_button.grab_focus)
	_leaderboard = LEADERBOARD_PANEL_SCRIPT.new()
	_leaderboard.name = "LeaderboardPanel"
	add_child(_leaderboard)
	_leaderboard.hide()
	_leaderboard.connect(&"closed", leaderboard_button.grab_focus)
	# A gamepad player has no cursor: without a focused button, the menu
	# ignored every press until someone reached for the mouse.
	_play_button.grab_focus.call_deferred()


func _open_options() -> void:
	_options.open()


func _open_progress() -> void:
	_progress.call(&"open")


func _open_tutorial() -> void:
	_tutorial.call(&"open")


func _open_cosmetics() -> void:
	_cosmetics.show()


func _open_leaderboard() -> void:
	_leaderboard.call(&"open")


func _quit_game() -> void:
	get_tree().quit()


func _play_solo() -> void:
	if _busy:
		return
	_go_to_level(LEVEL_SCENE)


func _play_endless() -> void:
	if _busy:
		return
	_go_to_level(ENDLESS_LEVEL_SCENE)


func _host_session(transport: int = NetworkManager.Transport.AUTO) -> void:
	if _busy:
		return
	_busy = true
	_set_status("Creando sala…", MUTED)
	NetworkManager.transport = transport
	var error: Error = NetworkManager.host_session()
	if error != OK:
		_busy = false
		_set_status("No se pudo crear la sala (error %d)." % error, RED)


func _join_by_address() -> void:
	if _busy:
		return
	var address: String = _address_field.text.strip_edges()
	if address.is_empty():
		_set_status("Escribí la IP del anfitrión primero.", RED)
		return
	_busy = true
	_set_status("Conectando a %s…" % address, MUTED)
	# Typing an address only makes sense for ENet -- a Steam lobby is joined
	# by id, not by IP, so AUTO would be the wrong choice here even if Steam
	# happens to be running.
	NetworkManager.transport = NetworkManager.Transport.ENET
	var error: Error = NetworkManager.join_session(address)
	if error != OK:
		_busy = false
		_set_status("No se pudo conectar (error %d)." % error, RED)


## The LAN address to share used to be printed here, one frame before the
## level replaced the menu -- nobody ever saw it. The in-game HUD shows it
## for as long as the session lasts instead.
func _on_session_ready(is_host: bool) -> void:
	if not is_host:
		GameSettings.last_join_address = _address_field.text
	_set_status("Entrando…", MINT)
	_go_to_level(LEVEL_SCENE)


func _cancel_connection() -> void:
	NetworkManager.leave_session()
	NetworkManager.transport = NetworkManager.Transport.AUTO
	_busy = false
	_set_status("Conexión cancelada.", MUTED)
	_play_button.grab_focus()


func _on_session_failed(reason: String) -> void:
	_busy = false
	_set_status(reason, RED)


func _go_to_level(scene_path: String) -> void:
	# Deferred: this can be reached from _ready() (the --autostart/--host/
	# --join shortcuts), and the tree is still mid-setup at that point --
	# change_scene_to_file() removing this node right then errors ("Parent
	# node is busy adding/removing children").
	get_tree().change_scene_to_file.call_deferred(scene_path)


func _set_status(text: String, color: Color) -> void:
	_status_label.text = text
	_status_label.visible = not text.is_empty()
	_status_label.add_theme_color_override("font_color", color)


func _label(parent: Node, text: String, font_size: int, color: Color) -> Label:
	return UiTheme.label(parent, text, font_size, color)


func _button(parent: Node, text: String, primary: bool) -> Button:
	return UiTheme.button(parent, text, primary)


func _spacer(parent: Node, height: int) -> void:
	var box := Control.new()
	box.custom_minimum_size.y = height
	parent.add_child(box)
