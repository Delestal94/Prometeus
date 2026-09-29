extends Control
## The missing link between "multiplayer works" and "a real player can reach
## it": until this existed, the game only ever loaded straight into
## level_base.tscn, offline, with no way to host or join from the UI at all
## -- every connection in this project so far was driven by a test script.
##
## Three ways in, all behind "¡JUGAR!":
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
##
## Layout (2026-09-25): the card used to show ten buttons of equal weight,
## the LAN address field included. Now it is pages inside one card: the home
## page has a single hero "¡JUGAR!", the "Garaje" (Apariencia, Progreso,
## Récords) and a quiet row for Opciones / Cómo jugar / Salir; the modes and
## the IP field live one level down. Back / Esc returns to the home page.

# Colours and widgets live in ui_theme.gd now: this screen and the in-game
# HUD used to keep their own copies of the same five constants and drift
# apart one tweak at a time (docs/direccion-visual.md section 3).
const MUTED: Color = UiTheme.MUTED
const MINT: Color = UiTheme.MINT
const RED: Color = UiTheme.RED
const LEVEL_SCENE: String = "res://scenes/gameplay/level_base.tscn"
const ENDLESS_LEVEL_SCENE: String = "res://scenes/gameplay/level_endless.tscn"
const MENU_ART: Texture2D = preload("res://assets/ui/backgrounds/tx_ui_menu_background_1920.png")
const MENU_LOGO: Texture2D = preload("res://assets/ui/logo/tx_ui_logo_wordmark_2048.png")
const PROGRESS_PANEL_SCRIPT := preload("res://scripts/ui/progress_panel.gd")
const TUTORIAL_PANEL_SCRIPT := preload("res://scripts/ui/tutorial_panel.gd")
const COSMETICS_PANEL_SCRIPT := preload("res://scripts/ui/cosmetics_panel.gd")
const LEADERBOARD_PANEL_SCRIPT := preload("res://scripts/ui/leaderboard_panel.gd")
## How much of the cream card still covers the blurred art behind it. Only
## used when the blur could be built; otherwise the card stays opaque.
const FROSTED_CARD_ALPHA: float = 0.82
## The art is halved this many times and scaled back up: a cheap, smooth
## blur built once, instead of a screen-texture blur every frame (GL
## Compatibility has no cheap backdrop blur).
const FROST_SHRINK_STEPS: int = 4
const FROST_UPSCALE_WIDTH: int = 480
const FROST_SHADER: String = """
shader_type canvas_item;
// Card rectangle in this node's local pixels (x, y, width, height).
uniform vec4 card_rect;
uniform float radius = 16.0;
// The card's cream fill, alpha = how much it covers the blurred art. Drawn
// here too: a see-through StyleBox fill left a bright 1 px seam inside its
// own anti-aliased border.
uniform vec4 tint : source_color;
// The card's hard ink shadow is drawn here, not by its StyleBox: under a
// see-through fill the StyleBox shadow would darken the whole card.
uniform vec4 shadow_color : source_color;
uniform float shadow_offset = 6.0;
varying vec2 local_pos;

void vertex() {
	local_pos = VERTEX;
}

float rounded_rect(vec2 p) {
	vec2 half_size = card_rect.zw * 0.5;
	vec2 q = abs(p - (card_rect.xy + half_size)) - half_size + radius;
	return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - radius;
}

void fragment() {
	float card = clamp(0.5 - rounded_rect(local_pos), 0.0, 1.0);
	float shadow = clamp(0.5 - rounded_rect(local_pos - vec2(0.0, shadow_offset)), 0.0, 1.0);
	vec4 frosted = vec4(mix(COLOR.rgb, tint.rgb, tint.a), 1.0);
	COLOR = mix(vec4(shadow_color.rgb, shadow * shadow_color.a), frosted, card);
}
"""

enum Page { HOME, PLAY, JOIN, GARAGE }
const CONNECTION_ERROR_TEXT: Dictionary = {
	"version": "UI_MENU_ERROR_VERSION",
	"timeout": "UI_MENU_ERROR_TIMEOUT",
	"full": "UI_MENU_ERROR_FULL",
	"connection": "UI_MENU_ERROR_CONNECTION",
}
const PAGE_TITLES: Dictionary = {
	Page.HOME: "UI_MENU_PAGE_HOME",
	Page.PLAY: "UI_MENU_PAGE_PLAY",
	Page.JOIN: "UI_MENU_PAGE_JOIN",
	Page.GARAGE: "GARAJE",
}
## Where "Volver" (and Esc / B) lead from each sub-page.
const PAGE_PARENT: Dictionary = {
	Page.PLAY: Page.HOME,
	Page.JOIN: Page.PLAY,
	Page.GARAGE: Page.HOME,
}

var _status_label: Label
var _address_field: LineEdit
var _options: OptionsPanel
var _progress: Control
var _tutorial: Control
var _cosmetics: Control
var _leaderboard: Control
var _play_button: Button
var _cancel_button: Button
var _page_title: Label
var _card: Control
var _frost: TextureRect
var _page: Page = Page.HOME
## One VBoxContainer per Page, and the button each one focuses on arrival.
var _pages: Dictionary = {}
var _page_focus: Dictionary = {}
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
	# The menu's theme (tareas de Nacho N-403): self-contained, just added here.
	add_child(preload("res://scripts/presentation/menu_music.gd").new())
	_build_ui()
	NetworkManager.session_ready.connect(_on_session_ready)
	NetworkManager.session_failed.connect(_on_session_failed)
	# A session that ended while in a level (host gone, handshake refused):
	# say why here, where the player lands.
	var reason: String = NetworkManager.take_failure_message()
	if not reason.is_empty():
		_set_status(reason, RED)
	_handle_cmdline_args()


func _handle_cmdline_args() -> void:
	# Same shortcut level_base.gd already honours for smoke checks and quick
	# iteration -- skips the menu the same way it skips on-foot loading.
	var args: PackedStringArray = OS.get_cmdline_user_args()
	# A Steam invite accepted before the menu existed (see NetworkManager).
	var lobby: int = NetworkManager.take_pending_lobby()
	if lobby != 0:
		join_steam_lobby(lobby)
		return
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


func _unhandled_input(event: InputEvent) -> void:
	# Esc / B on a sub-page goes back one level, like every console menu.
	# The overlays (Opciones, Progreso...) close themselves first; the ones
	# that don't listen for it must not take the page away underneath them.
	if _page == Page.HOME or _busy or _overlay_open():
		return
	if event.is_action_pressed(&"ui_cancel") or event.is_action_pressed(&"ui_pause"):
		_show_page(PAGE_PARENT[_page])
		get_viewport().set_input_as_handled()


func _build_ui() -> void:
	_build_backdrop()
	_build_brand()
	var column: VBoxContainer = _build_card()
	var focus_return: Dictionary = _build_home_page(column)
	_build_play_page(column)
	_build_join_page(column)
	focus_return.merge(_build_garage_page(column))
	_build_connection_status(column)
	_build_footer()
	_build_overlays(focus_return)
	_show_page(Page.HOME, false)
	# A gamepad player has no cursor: without a focused button, the menu
	# ignored every press until someone reached for the mouse.
	_play_button.grab_focus.call_deferred()


## Backdrop, key art and the frosted copy of it behind the card.
func _build_backdrop() -> void:
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
	_frost = _build_frost()


func _build_brand() -> void:
	# Logo over the open sky, top left; the menu card on the right, so the
	# van spilling boxes (the whole joke) stays in view.
	var brand := VBoxContainer.new()
	brand.add_theme_constant_override("separation", 14)
	brand.position = Vector2(64, 48)
	add_child(brand)
	var logo := TextureRect.new()
	logo.name = "BrandLogo"
	logo.texture = MENU_LOGO
	logo.custom_minimum_size = Vector2(420, 210)
	logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	brand.add_child(logo)
	var chips := HBoxContainer.new()
	chips.add_theme_constant_override("separation", 10)
	brand.add_child(chips)
	UiTheme.tag(chips, tr("UI_MENU_TAG_COOP"), MINT, -2.0, 16)
	UiTheme.tag(chips, tr("UI_MENU_TAG_PLAYERS"), UiTheme.SKY, 1.5, 16)
	var stamp: Label = UiTheme.tag(brand, tr("UI_MENU_TAG_DONT_DROP"), RED, -5.0, 18)
	stamp.get_parent().size_flags_horizontal = Control.SIZE_SHRINK_BEGIN


## The menu card on the right; returns the column the pages go in.
func _build_card() -> VBoxContainer:
	var side := MarginContainer.new()
	side.set_anchors_and_offsets_preset(Control.PRESET_RIGHT_WIDE)
	side.offset_left = -500
	side.add_theme_constant_override("margin_right", 64)
	# Anchored at a fixed top, not centred: the pages differ in height and a
	# centred card made the title and "Volver" jump on every page change.
	side.add_theme_constant_override("margin_top", 110)
	side.add_theme_constant_override("margin_bottom", 40)
	add_child(side)
	var holder := VBoxContainer.new()
	side.add_child(holder)
	var column: VBoxContainer = UiTheme.panel(holder, Vector2(420, 0), 28)
	column.add_theme_constant_override("separation", 12)
	_card = column.get_parent()
	if _frost != null:
		# Outline only: the frost draws the fill and the shadow (FROST_SHADER).
		var style: StyleBoxFlat = UiTheme.surface_style(28)
		style.draw_center = false
		style.shadow_size = 0
		_card.add_theme_stylebox_override("panel", style)
		_card.item_rect_changed.connect(_fit_frost, CONNECT_DEFERRED)
	_page_title = UiTheme.tag(column, tr(PAGE_TITLES[Page.HOME]), UiTheme.YELLOW, -1.5, 17)
	_spacer(column, 2)
	return column


## Returns the buttons the overlays opened from here give focus back to.
func _build_home_page(column: VBoxContainer) -> Dictionary:
	var home: VBoxContainer = _add_page(column, Page.HOME)
	_play_button = UiTheme.button(home, tr("UI_MENU_PLAY"), true, Vector2(0, 78))
	_play_button.add_theme_font_size_override("font_size", 34)
	_play_button.pressed.connect(_show_page.bind(Page.PLAY))
	_entry_buttons.append(_play_button)
	_page_focus[Page.HOME] = _play_button
	var garage_button: Button = _button(home, tr("UI_MENU_GARAGE"), false)
	garage_button.pressed.connect(_show_page.bind(Page.GARAGE))
	_entry_buttons.append(garage_button)
	_label(home, tr("UI_MENU_GARAGE_HINT"), 14, MUTED).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_spacer(home, 8)
	# The quiet row: smaller, so nothing here competes with ¡JUGAR!.
	var bottom_row := HBoxContainer.new()
	bottom_row.add_theme_constant_override("separation", 10)
	home.add_child(bottom_row)
	var options_button: Button = _small_button(bottom_row, tr("UI_OPTIONS"))
	options_button.pressed.connect(_open_options)
	_entry_buttons.append(options_button)
	var tutorial_button: Button = _small_button(bottom_row, tr("UI_HOW_TO_PLAY"),
			int(UnlockManager.completed_runs) == 0)
	tutorial_button.set_meta(&"first_run_highlighted", int(UnlockManager.completed_runs) == 0)
	tutorial_button.pressed.connect(_open_tutorial)
	_entry_buttons.append(tutorial_button)
	# A game you can only leave with Alt+F4 reads as unfinished before a
	# player has pressed anything (docs/critica-diseno-abogado-del-diablo.md
	# section 4).
	var quit_button: Button = _small_button(bottom_row, tr("UI_MENU_QUIT"))
	quit_button.pressed.connect(_quit_game)
	return {"options": options_button, "tutorial": tutorial_button}


func _build_play_page(column: VBoxContainer) -> void:
	var play: VBoxContainer = _add_page(column, Page.PLAY)
	var solo_button: Button = UiTheme.button(play, tr("UI_MENU_SOLO"), true, Vector2(0, 62))
	solo_button.add_theme_font_size_override("font_size", 26)
	solo_button.pressed.connect(_play_solo)
	_entry_buttons.append(solo_button)
	_page_focus[Page.PLAY] = solo_button
	_entry_buttons.append(_button(play, tr("UI_MENU_ENDLESS"), false))
	_entry_buttons[-1].pressed.connect(_play_endless)
	_spacer(play, 4)
	_label(play, tr("UI_MENU_WITH_FRIENDS"), 15, MUTED).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_entry_buttons.append(_button(play, tr("UI_MENU_HOST"), false))
	_entry_buttons[-1].pressed.connect(_host_session)
	_entry_buttons.append(_button(play, tr("UI_MENU_JOIN"), false))
	_entry_buttons[-1].pressed.connect(_show_page.bind(Page.JOIN))
	_back_button(play)


func _build_join_page(column: VBoxContainer) -> void:
	var join: VBoxContainer = _add_page(column, Page.JOIN)
	# INK, not MUTED: these are the page's instructions, and MUTED over the
	# frosted art dropped to ~2.6:1 contrast.
	for hint: String in [tr("UI_MENU_JOIN_STEAM_HINT"),
			tr("UI_MENU_JOIN_LAN_HINT")]:
		_label(join, hint, 15, UiTheme.INK).autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var join_row := HBoxContainer.new()
	join_row.add_theme_constant_override("separation", 10)
	join.add_child(join_row)
	_address_field = UiTheme.line_edit(join_row, tr("UI_MENU_HOST_IP"))
	_address_field.text = GameSettings.last_join_address
	_address_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# Enter in the field is the obvious way to confirm an address; it used
	# to do nothing and leave the player hunting for the button.
	_address_field.text_submitted.connect(func(_text: String) -> void: _join_by_address())
	_page_focus[Page.JOIN] = _address_field
	_entry_buttons.append(_button(join_row, tr("UI_MENU_JOIN_BUTTON"), true))
	_entry_buttons[-1].pressed.connect(_join_by_address)
	_back_button(join)


## Returns the buttons the overlays opened from here give focus back to.
func _build_garage_page(column: VBoxContainer) -> Dictionary:
	var garage: VBoxContainer = _add_page(column, Page.GARAGE)
	var cosmetics_button: Button = _button(garage, tr("UI_APPEARANCE"), false)
	cosmetics_button.pressed.connect(_open_cosmetics)
	_entry_buttons.append(cosmetics_button)
	_page_focus[Page.GARAGE] = cosmetics_button
	var progress_button: Button = _button(garage, tr("UI_PROGRESS"), false)
	progress_button.pressed.connect(_open_progress)
	_entry_buttons.append(progress_button)
	var leaderboard_button: Button = _button(garage, tr("UI_RECORDS"), false)
	leaderboard_button.pressed.connect(_open_leaderboard)
	_entry_buttons.append(leaderboard_button)
	_back_button(garage)
	return {"cosmetics": cosmetics_button, "progress": progress_button, "leaderboard": leaderboard_button}


func _build_connection_status(column: VBoxContainer) -> void:
	_status_label = _label(column, "", 15, MUTED)
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status_label.visible = false
	# Only while a connection is in flight: a join to a wrong IP used to
	# leave every button dead until the timeout, with no way back out.
	_cancel_button = _button(column, tr("UI_CANCEL"), false)
	_cancel_button.pressed.connect(_cancel_connection)
	_cancel_button.visible = false


func _build_footer() -> void:
	# The release job (N-210) stamps the tag into config/version before exporting.
	var version: String = str(ProjectSettings.get_setting("application/config/version", "0.1.0"))
	var footer: Label = UiTheme.chip(self, tr("UI_MENU_FOOTER") % version, UiTheme.WHITE, 14)
	var footer_holder: Control = footer.get_parent()
	footer_holder.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	footer_holder.offset_left = 24
	footer_holder.offset_top = -52
	footer_holder.offset_bottom = -20
	footer_holder.grow_vertical = Control.GROW_DIRECTION_BEGIN


## Options, progress, tutorial, appearance and records open over the menu;
## closing one gives focus back to the button that opened it.
func _build_overlays(focus_return: Dictionary) -> void:
	_options = OptionsPanel.new()
	_options.name = "OptionsPanel"
	add_child(_options)
	_options.closed.connect((focus_return["options"] as Button).grab_focus)
	_progress = PROGRESS_PANEL_SCRIPT.new()
	_progress.name = "ProgressPanel"
	add_child(_progress)
	_progress.connect(&"closed", (focus_return["progress"] as Button).grab_focus)
	_tutorial = TUTORIAL_PANEL_SCRIPT.new()
	_tutorial.name = "TutorialPanel"
	add_child(_tutorial)
	_tutorial.connect(&"closed", (focus_return["tutorial"] as Button).grab_focus)
	_cosmetics = COSMETICS_PANEL_SCRIPT.new()
	_cosmetics.name = "CosmeticsPanel"
	add_child(_cosmetics)
	_cosmetics.hide()
	_cosmetics.connect(&"closed", (focus_return["cosmetics"] as Button).grab_focus)
	_leaderboard = LEADERBOARD_PANEL_SCRIPT.new()
	_leaderboard.name = "LeaderboardPanel"
	add_child(_leaderboard)
	_leaderboard.hide()
	_leaderboard.connect(&"closed", (focus_return["leaderboard"] as Button).grab_focus)


## A blurred copy of the key art, masked to the card's rounded rectangle, so
## the card reads as frosted glass over the scene instead of a flat sheet.
## Returns null where the art's pixels can't be read (headless: the dummy
## renderer has no texture data) and the card simply stays opaque.
func _build_frost() -> TextureRect:
	var image: Image = MENU_ART.get_image()
	if image == null or image.is_empty():
		return null
	image = image.duplicate()
	if image.is_compressed():
		image.decompress()
	for i: int in range(FROST_SHRINK_STEPS):
		image.shrink_x2()
	var height: int = roundi(float(FROST_UPSCALE_WIDTH) * image.get_height() / image.get_width())
	image.resize(FROST_UPSCALE_WIDTH, height, Image.INTERPOLATE_CUBIC)
	var frost := TextureRect.new()
	frost.name = "Frost"
	frost.texture = ImageTexture.create_from_image(image)
	# Same sizing as the art, so the blurred copy lines up with it exactly.
	frost.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	frost.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	frost.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frost.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var shader := Shader.new()
	shader.code = FROST_SHADER
	var material := ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter(&"radius", float(UiTheme.CORNER_RADIUS))
	material.set_shader_parameter(&"tint", Color(UiTheme.PAPER, FROSTED_CARD_ALPHA))
	material.set_shader_parameter(&"shadow_color", UiTheme.INK)
	material.set_shader_parameter(&"shadow_offset", float(UiTheme.SHADOW))
	# Hidden until the card has a real rectangle to mask to.
	material.set_shader_parameter(&"card_rect", Vector4.ZERO)
	frost.material = material
	add_child(frost)
	# Deferred: the frost is resized before the card's MarginContainer moves
	# with the window, and fitted right then it masked the card's old spot --
	# a second, offset card behind the real one (playtest 2026-09-29).
	frost.resized.connect(_fit_frost, CONNECT_DEFERRED)
	return frost


func _fit_frost() -> void:
	if _frost == null or _card == null:
		return
	var rect := Rect2(_card.global_position - _frost.global_position, _card.size)
	(_frost.material as ShaderMaterial).set_shader_parameter(&"card_rect",
		Vector4(rect.position.x, rect.position.y, rect.size.x, rect.size.y))


func _add_page(column: VBoxContainer, page: Page) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.name = "Page%s" % Page.keys()[page].capitalize()
	box.add_theme_constant_override("separation", 12)
	column.add_child(box)
	_pages[page] = box
	return box


func _back_button(page: VBoxContainer) -> void:
	_spacer(page, 4)
	var back: Button = _small_button(page, tr("UI_BACK"))
	back.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	back.custom_minimum_size.x = 140
	back.pressed.connect(func() -> void: _show_page(PAGE_PARENT[_page]))
	_entry_buttons.append(back)


func _show_page(page: Page, focus: bool = true) -> void:
	_page = page
	for key: Page in _pages:
		(_pages[key] as Control).visible = key == page
	_page_title.text = tr(PAGE_TITLES[page])
	# A status from another page ("Conexión cancelada.") would read as being
	# about this one; a failure the player hasn't seen yet stays.
	if not _busy and _status_label.visible and _status_label.get_theme_color(&"font_color") != RED:
		_set_status("", MUTED)
	if focus:
		(_page_focus[page] as Control).grab_focus()


func _overlay_open() -> bool:
	for overlay: Control in [_options, _progress, _tutorial, _cosmetics, _leaderboard]:
		if overlay != null and overlay.visible:
			return true
	return false


func _open_options() -> void:
	_options.open()


func _open_progress() -> void:
	_progress.call(&"open")


func _open_tutorial() -> void:
	_tutorial.call(&"open")


func _open_cosmetics() -> void:
	_cosmetics.call(&"open")


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
	_show_page(Page.PLAY, false)
	_busy = true
	_set_status(tr("UI_MENU_STATUS_HOSTING"), MUTED)
	NetworkManager.transport = transport
	var error: Error = NetworkManager.host_session()
	if error != OK:
		_busy = false
		_set_status(tr("UI_MENU_STATUS_HOST_FAILED") % error, RED)


## A friend's Steam room, from an accepted invite or "Unirse a la partida".
func join_steam_lobby(lobby: int) -> void:
	# Always taken, even mid-connection: NetworkManager already left whatever
	# was in progress, and returning here left the menu stuck "Conectando…"
	# with the invite thrown away.
	_show_page(Page.JOIN, false)
	_busy = true
	_set_status(tr("UI_MENU_STATUS_JOINING_FRIEND"), MUTED)
	NetworkManager.transport = NetworkManager.Transport.STEAM
	var error: Error = NetworkManager.join_session(str(lobby))
	if error != OK:
		_busy = false
		_set_status(tr("UI_MENU_STATUS_JOIN_FAILED") % error, RED)


func _join_by_address() -> void:
	if _busy:
		return
	_show_page(Page.JOIN, false)
	var address: String = _address_field.text.strip_edges()
	if address.is_empty():
		_set_status(tr("UI_MENU_STATUS_NEED_IP"), RED)
		return
	_busy = true
	_set_status(tr("UI_MENU_STATUS_CONNECTING") % address, MUTED)
	# Typing an address only makes sense for ENet -- a Steam lobby is joined
	# by id, not by IP, so AUTO would be the wrong choice here even if Steam
	# happens to be running.
	NetworkManager.transport = NetworkManager.Transport.ENET
	var error: Error = NetworkManager.join_session(address)
	if error != OK:
		_busy = false
		_set_status(tr("UI_MENU_STATUS_CONNECT_FAILED") % error, RED)


## The LAN address to share used to be printed here, one frame before the
## level replaced the menu -- nobody ever saw it. The in-game HUD shows it
## for as long as the session lasts instead.
func _on_session_ready(is_host: bool) -> void:
	if not is_host:
		GameSettings.last_join_address = _address_field.text
	_set_status(tr("UI_MENU_STATUS_ENTERING"), MINT)
	_go_to_level(NetworkManager.session_scene if not NetworkManager.session_scene.is_empty() else LEVEL_SCENE)


func _cancel_connection() -> void:
	NetworkManager.leave_session()
	NetworkManager.transport = NetworkManager.Transport.AUTO
	_busy = false
	_set_status(tr("UI_MENU_STATUS_CANCELLED"), MUTED)
	(_page_focus[_page] as Control).grab_focus()


func _on_session_failed(reason: String) -> void:
	NetworkManager.take_failure_message()  # Shown right here; not again later.
	_busy = false
	_set_status(connection_error_text(reason), RED)


static func connection_error_text(reason: String) -> String:
	return TranslationServer.translate(String(CONNECTION_ERROR_TEXT.get(reason, reason)))


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
	if not text.is_empty() and color == RED:
		UiTheme.UI_SOUNDS.play(self, UiTheme.UI_SOUNDS.ERROR)


func _label(parent: Node, text: String, font_size: int, color: Color) -> Label:
	return UiTheme.label(parent, text, font_size, color)


func _button(parent: Node, text: String, primary: bool) -> Button:
	return UiTheme.button(parent, text, primary)


## Secondary actions: shorter and smaller type than the page's real choices.
func _small_button(parent: Node, text: String, highlighted: bool = false) -> Button:
	var button: Button = UiTheme.button(parent, text, highlighted, Vector2(0, 42))
	button.add_theme_font_size_override("font_size", 17)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return button


func _spacer(parent: Node, height: int) -> void:
	var box := Control.new()
	box.custom_minimum_size.y = height
	parent.add_child(box)
