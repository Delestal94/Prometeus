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

const INK: Color = Color("132a31")
const PAPER: Color = Color("edf2e8")
const MUTED: Color = Color("acc1bd")
const MINT: Color = Color("83e2ba")
const RED: Color = Color("f47e6d")
const LEVEL_SCENE: String = "res://scenes/gameplay/level_base.tscn"

var _status_label: Label
var _address_field: LineEdit
var _busy: bool = false


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
	var bg := ColorRect.new()
	bg.color = Color("0d1f24")
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(460, 0)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(INK, 0.95)
	style.border_color = Color("365458")
	style.set_border_width_all(1)
	style.set_corner_radius_all(10)
	style.content_margin_left = 32
	style.content_margin_right = 32
	style.content_margin_top = 28
	style.content_margin_bottom = 28
	panel.add_theme_stylebox_override("panel", style)
	center.add_child(panel)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 14)
	panel.add_child(column)

	_label(column, "DO NOT DROP", 36, PAPER)
	_label(column, "Delivery cooperativo · hasta 8 jugadores", 14, MUTED)
	_spacer(column, 10)

	_button(column, "Jugar solo", true).pressed.connect(_play_solo)
	_button(column, "Crear sala (con amigos)", false).pressed.connect(_host_session)

	_spacer(column, 6)
	var join_row := HBoxContainer.new()
	join_row.add_theme_constant_override("separation", 8)
	column.add_child(join_row)
	_address_field = LineEdit.new()
	_address_field.placeholder_text = "IP del anfitrión (LAN)"
	_address_field.custom_minimum_size.x = 260
	join_row.add_child(_address_field)
	_button(join_row, "Unirse", false).pressed.connect(_join_by_address)

	_spacer(column, 10)
	_status_label = _label(column, "", 14, MUTED)
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART


func _play_solo() -> void:
	if _busy:
		return
	_go_to_level()


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


func _on_session_ready(is_host: bool) -> void:
	if is_host:
		var hint: String = _lan_hint() if NetworkManager.active_transport == NetworkManager.Transport.ENET else "Invitá amigos desde la lista de amigos de Steam."
		_set_status("Sala lista. %s" % hint, MINT)
	_go_to_level()


func _on_session_failed(reason: String) -> void:
	_busy = false
	_set_status(reason, RED)


func _go_to_level() -> void:
	# Deferred: this can be reached from _ready() (the --autostart/--host/
	# --join shortcuts), and the tree is still mid-setup at that point --
	# change_scene_to_file() removing this node right then errors ("Parent
	# node is busy adding/removing children").
	get_tree().change_scene_to_file.call_deferred(LEVEL_SCENE)


func _lan_hint() -> String:
	for address: String in IP.get_local_addresses():
		if address.begins_with("192.168.") or address.begins_with("10.") or address.begins_with("172."):
			return "Pasales esta IP: %s" % address
	return "No se encontró una IP de LAN -- puede que solo funcione en esta máquina."


func _set_status(text: String, color: Color) -> void:
	_status_label.text = text
	_status_label.add_theme_color_override("font_color", color)


func _label(parent: Node, text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	parent.add_child(label)
	return label


func _button(parent: Node, text: String, primary: bool) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(0, 44)
	var style := StyleBoxFlat.new()
	style.bg_color = MINT if primary else Color("30474d")
	style.set_corner_radius_all(5)
	button.add_theme_stylebox_override("normal", style)
	var hover: StyleBoxFlat = style.duplicate()
	hover.bg_color = style.bg_color.lightened(0.12)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", hover)
	button.add_theme_color_override("font_color", INK if primary else PAPER)
	button.add_theme_color_override("font_hover_color", INK if primary else PAPER)
	parent.add_child(button)
	return button


func _spacer(parent: Node, height: int) -> void:
	var box := Control.new()
	box.custom_minimum_size.y = height
	parent.add_child(box)
