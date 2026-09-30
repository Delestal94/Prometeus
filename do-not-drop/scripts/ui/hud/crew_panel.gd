class_name CrewPanel
extends Control
## The crew list (S-507): hold Tab (Back on a gamepad) in the depot, before the
## truck leaves, to see who is here -- the colour of each uniform, who sits at
## the wheel, who has a box -- and, for the host, the room code to pass on.
## It is the lobby the game does not have, without stopping anyone: no pause,
## no free cursor, no focus; the movement input keeps flowing while it shows.
##
## It only reads what is already replicated (the roster in NetworkManager,
## each player's cosmetic_id / carried_package / tended_package, the truck's
## driver_peer_id) and adds no RPC. The data comes from the static
## build_entries() / invite_info(), so the test can feed them without a level.
##
## Input: the "crew_panel" action shares Tab and Back with "spectate_toggle".
## They never meet: the spectator view exists only mid-run, this panel only
## while the depot is still open (docs/convenciones-godot.md section 1).

const ACTION: StringName = &"crew_panel"
const REFRESH_SECONDS: float = 0.25
const PANEL_WIDTH: float = 660.0
const SWATCH: float = 30.0
const BADGE_ICON: float = 30.0
const ICON_DRIVER: StringName = &"sit"
const ICON_BOX: StringName = &"grab"
const TEAM_UNIFORM: StringName = &"team_color"
## What the invite block shows (invite_info()["kind"]).
const INVITE_NONE: StringName = &"none"
const INVITE_LAN: StringName = &"lan"
const INVITE_NO_LAN: StringName = &"no_lan"
const INVITE_STEAM: StringName = &"steam"
const INVITE_GUEST: StringName = &"guest"

## Set by Hud right after it creates this panel.
var hud: Hud
var _body: VBoxContainer
var _signature: String = ""
var _refresh_left: float = 0.0
var _dirty: bool = true


func _ready() -> void:
	name = "CrewPanel"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	focus_mode = Control.FOCUS_NONE
	UiTheme.apply(self)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	_body = UiTheme.panel(center, Vector2(PANEL_WIDTH, 0))
	_body.get_parent().mouse_filter = Control.MOUSE_FILTER_IGNORE
	_body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_body.add_theme_constant_override("separation", 10)
	hide()
	NetworkManager.roster_changed.connect(func(_peer_ids: Array) -> void: _dirty = true)
	# The colours follow the host's slot map, which can change on its own.
	NetworkManager.color_slots_changed.connect(func(_slots: Dictionary) -> void: _dirty = true)


func _process(delta: float) -> void:
	var wanted: bool = in_depot() and Input.is_action_pressed(ACTION)
	if wanted != visible:
		visible = wanted
		_dirty = true
	if not visible:
		return
	_refresh_left -= delta
	if _dirty or _refresh_left <= 0.0:
		_refresh_left = REFRESH_SECONDS
		refresh()


## Only while the depot is open: the preparation phase, the truck not gone
## yet, and nothing else (start card, pause, results, a depot station or the
## options) on screen.
func in_depot() -> bool:
	if hud == null or hud.overlay_mode != "preparation" or RunManager.is_running:
		return false
	if hud.overlay != null and hud.overlay.visible:
		return false
	for other: Control in [hud.depot_panel, hud.options_panel]:
		if other != null and other.visible:
			return false
	return not get_tree().paused


## Rebuilds the list from the live game when something changed.
func refresh() -> void:
	_dirty = false
	var truck: Node = get_tree().get_first_node_in_group(&"vehicle")
	var entries: Array[Dictionary] = build_entries(NetworkManager.peer_ids, _players_by_peer(),
			NetworkManager.local_id(), NetworkManager.is_online(),
			int(truck.get(&"driver_peer_id")) if truck != null else 0)
	var invite: Dictionary = invite_info(NetworkManager.is_online(), NetworkManager.is_host(),
			NetworkManager.active_transport == NetworkManager.Transport.STEAM, NetworkManager.lan_address())
	var signature: String = str([entries, invite, TranslationServer.get_locale()])
	if signature == _signature:
		return
	_signature = signature
	render(entries, invite)


func render(entries: Array[Dictionary], invite: Dictionary) -> void:
	for child: Node in _body.get_children():
		_body.remove_child(child)
		child.queue_free()
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 12)
	header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_body.add_child(header)
	UiTheme.tag(header, tr("HUD_CREW_TITLE"), UiTheme.MINT, -1.5, 18)
	UiTheme.chip(header, tr("HUD_CREW_COUNT") % [entries.size(), NetworkManager.MAX_PLAYERS], UiTheme.SKY, 16)
	for entry: Dictionary in entries:
		_add_row(entry)
	_add_invite(invite)
	_ignore_mouse(_body.get_parent())


## One dictionary per connected player, in roster order:
## peer_id, name (the crew colour, how the game calls them), is_local,
## is_host, color (the shirt they wear), uniform (its name), driving, has_box.
## `players` maps peer id -> the Player node (missing while it still spawns).
static func build_entries(peer_ids: Array, players: Dictionary, local_id: int, online: bool,
		driver_peer_id: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for peer_id: int in peer_ids:
		var player: Object = players.get(peer_id)
		var cosmetic_id: StringName = TEAM_UNIFORM
		var has_box: bool = false
		if player != null and is_instance_valid(player):
			cosmetic_id = StringName(player.get(&"cosmetic_id"))
			# On the arms, or on the lap of whoever sits tending it.
			has_box = is_instance_valid(player.get(&"carried_package")) \
					or is_instance_valid(player.get(&"tended_package"))
		result.append({
			"peer_id": peer_id,
			"name": CrewProgression.player_color_name(peer_id).capitalize(),
			"is_local": peer_id == local_id,
			"is_host": online and peer_id == NetworkManager.HOST_ID,
			"color": shirt_color(peer_id, cosmetic_id),
			"uniform": uniform_name(cosmetic_id),
			"driving": driver_peer_id > 0 and peer_id == driver_peer_id,
			"has_box": has_box,
		})
	return result


## The colour of the shirt the world sees on this peer: the crew colour of
## the seat, or the uniform they picked (Player._apply_cosmetic()).
static func shirt_color(peer_id: int, cosmetic_id: StringName) -> Color:
	var crew_colors: Array[Color] = Player.PLAYER_COLORS
	if UnlockManager.cosmetic_is_auto(cosmetic_id):
		return crew_colors[PlayerColorSlot.slot(peer_id, crew_colors.size())]
	return UnlockManager.cosmetic_color(cosmetic_id)


static func uniform_name(cosmetic_id: StringName) -> String:
	if UnlockManager.cosmetic_is_auto(cosmetic_id):
		return TranslationServer.translate("HUD_CREW_TEAM_COLOR")
	var item: Dictionary = Dictionary(UnlockManager.COSMETICS.get(cosmetic_id,
			UnlockManager.COSMETICS[&"mint_uniform"]))
	return TranslationServer.translate(String(item["title"]))


## What to tell the person who has this open about getting others in:
## {"kind", "code", "address"}. Only the LAN host gets a code (S-207); a Steam
## host invites from the friends list; guests are told why they see none.
static func invite_info(online: bool, host: bool, steam: bool, lan_address: String) -> Dictionary:
	var info: Dictionary = {"kind": INVITE_NONE, "code": "", "address": ""}
	if not online:
		return info
	if not host:
		info["kind"] = INVITE_GUEST
		return info
	if steam:
		info["kind"] = INVITE_STEAM
		return info
	var code: String = RoomCode.encode(lan_address, RoomCode.default_port())
	if code.is_empty():
		info["kind"] = INVITE_NO_LAN
		return info
	info["kind"] = INVITE_LAN
	info["code"] = code
	info["address"] = lan_address
	return info


## Cards and chips stop the mouse by default; this panel is only to be read.
func _ignore_mouse(node: Node) -> void:
	if node is Control:
		(node as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	for child: Node in node.get_children():
		_ignore_mouse(child)


func _players_by_peer() -> Dictionary:
	var result: Dictionary = {}
	for player: Node in get_tree().get_nodes_in_group(&"player"):
		result[player.get_multiplayer_authority()] = player
	return result


func _add_row(entry: Dictionary) -> void:
	var row := HBoxContainer.new()
	row.name = "Row_%d" % int(entry["peer_id"])
	row.set_meta(&"entry", entry)
	row.add_theme_constant_override("separation", 12)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_body.add_child(row)
	var swatch := Panel.new()
	swatch.name = "Swatch"
	swatch.custom_minimum_size = Vector2(SWATCH, SWATCH)
	swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	swatch.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = entry["color"]
	style.border_color = UiTheme.INK
	style.set_border_width_all(UiTheme.OUTLINE)
	style.set_corner_radius_all(8)
	swatch.add_theme_stylebox_override("panel", style)
	row.add_child(swatch)
	var who := HBoxContainer.new()
	who.custom_minimum_size.x = 250
	who.add_theme_constant_override("separation", 8)
	who.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(who)
	var name_label := UiTheme.title(who, String(entry["name"]), 22)
	name_label.name = "Name"
	if bool(entry["is_local"]):
		UiTheme.chip(who, tr("HUD_CREW_YOU"), UiTheme.YELLOW, 13).name = "You"
	if bool(entry["is_host"]):
		UiTheme.chip(who, tr("HUD_CREW_HOST"), UiTheme.GRAPE, 13).name = "Host"
	var uniform := UiTheme.label(row, String(entry["uniform"]), 16, UiTheme.MUTED)
	uniform.name = "Uniform"
	uniform.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	uniform.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var badges := HBoxContainer.new()
	badges.name = "Badges"
	badges.add_theme_constant_override("separation", 8)
	badges.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(badges)
	# An icon and words, never a colour alone.
	if bool(entry["driving"]):
		_add_badge(badges, "Driving", ICON_DRIVER, tr("HUD_CREW_DRIVING"), UiTheme.SKY)
	if bool(entry["has_box"]):
		_add_badge(badges, "Box", ICON_BOX, tr("HUD_CREW_BOX"), UiTheme.CARDBOARD)


func _add_badge(parent: Control, badge_name: String, icon_id: StringName, text: String, color: Color) -> void:
	var badge := HBoxContainer.new()
	badge.name = badge_name
	badge.add_theme_constant_override("separation", 4)
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(badge)
	var icon := TextureRect.new()
	icon.texture = UiTheme.action_icon(icon_id)
	icon.custom_minimum_size = Vector2(BADGE_ICON, BADGE_ICON)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge.add_child(icon)
	var chip := UiTheme.chip(badge, text, color, 14)
	chip.get_parent().size_flags_vertical = Control.SIZE_SHRINK_CENTER


func _add_invite(invite: Dictionary) -> void:
	var kind: StringName = StringName(invite["kind"])
	if kind == INVITE_NONE:
		return
	var box := VBoxContainer.new()
	box.name = "Invite"
	box.add_theme_constant_override("separation", 4)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_body.add_child(HSeparator.new())
	_body.add_child(box)
	match kind:
		INVITE_LAN:
			UiTheme.label(box, tr("HUD_CREW_INVITE_LAN"), 16, UiTheme.MUTED).name = "Hint"
			var code := UiTheme.title(box, String(invite["code"]), 44)
			code.name = "Code"
			UiTheme.label(box, tr("HUD_CREW_INVITE_IP") % String(invite["address"]), 16, UiTheme.MUTED).name = "Address"
		INVITE_STEAM:
			UiTheme.label(box, tr("HUD_CREW_INVITE_STEAM"), 18, UiTheme.INK).name = "Hint"
		INVITE_NO_LAN:
			UiTheme.label(box, tr("HUD_CREW_NO_LAN"), 16, UiTheme.MUTED).name = "Hint"
		INVITE_GUEST:
			UiTheme.label(box, tr("HUD_CREW_GUEST"), 16, UiTheme.MUTED).name = "Hint"
