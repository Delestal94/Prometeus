class_name OptionsVoiceSection
extends VBoxContainer
## The voice-chat block of the options screen (N-212.3): the general switch,
## push-to-talk, and -- for the session you are in -- a mute and a volume per
## crewmate. The talk key is rebound with the rest of the keys (options_panel.gd).
##
## The two switches write straight into GameSettings like every other option.
## The per-crewmate controls call ProximityVoice, whose mutes and volumes last
## as long as the session (they are forgotten when it ends), so the list is
## rebuilt from the roster each time the options open and while they are open.
## The rows come from the static crew_entries(), which reuses CrewPanel's
## build_entries() (name, shirt colour), so a test can feed it without a level.
##
## Voice runs over Steam only (N-212.4): the hint says so, and over LAN the
## list simply shows who is there, with nothing to take effect.

const SWATCH: float = 22.0
const VOLUME_STEP: float = 0.05

var voice_check: CheckBox
var talk_check: CheckBox
var _crew_box: VBoxContainer


func _ready() -> void:
	NetworkManager.roster_changed.connect(_on_roster_changed)
	NetworkManager.color_slots_changed.connect(_on_color_slots_changed)


## Builds the controls. Called by the panel once this node hangs under its
## column, so the font sizes follow the menu text scale of the panel.
func build() -> void:
	name = "VoiceSection"
	add_theme_constant_override("separation", 10)
	voice_check = UiTheme.check_box(self, tr("UI_OPT_VOICE_CHAT"), GameSettings.voice_chat_enabled)
	voice_check.name = "VoiceChat"
	voice_check.toggled.connect(_on_voice_chat_toggled)
	talk_check = UiTheme.check_box(self, tr("UI_OPT_VOICE_PTT"), GameSettings.voice_push_to_talk)
	talk_check.name = "PushToTalk"
	talk_check.toggled.connect(func(pressed: bool) -> void: GameSettings.voice_push_to_talk = pressed)
	var hint: Label = UiTheme.label(self, tr("UI_OPT_VOICE_HINT"), 14, UiTheme.MUTED)
	hint.name = "Hint"
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	UiTheme.tag(self, tr("UI_OPT_VOICE_CREW"), UiTheme.MINT, -1.5, 15)
	_crew_box = VBoxContainer.new()
	_crew_box.name = "Crew"
	_crew_box.add_theme_constant_override("separation", 8)
	add_child(_crew_box)
	_update_enabled()
	refresh_crew()


## Pulls both switches back in line with GameSettings (after a reset).
func sync_from_settings() -> void:
	voice_check.set_pressed_no_signal(GameSettings.voice_chat_enabled)
	talk_check.set_pressed_no_signal(GameSettings.voice_push_to_talk)
	_update_enabled()


## Push-to-talk means nothing while voice is off: shown, but greyed out.
func _update_enabled() -> void:
	talk_check.disabled = not voice_check.button_pressed


func _on_voice_chat_toggled(pressed: bool) -> void:
	GameSettings.voice_chat_enabled = pressed
	_update_enabled()


## Rebuilds the crew list from the live session.
func refresh_crew() -> void:
	# Deferred: a language rebuild may have taken this section out of the tree.
	if _crew_box == null or not is_inside_tree():
		return
	var players: Dictionary = {}
	for player: Node in get_tree().get_nodes_in_group(&"player"):
		players[player.get_multiplayer_authority()] = player
	render_crew(crew_entries(NetworkManager.peer_ids, players, NetworkManager.local_id(),
			NetworkManager.is_online()))


## Every crewmate except this player, in roster order: the CrewPanel entries
## (peer_id, name, color...) without the local one.
static func crew_entries(peer_ids: Array, players: Dictionary, local_id: int, online: bool) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for entry: Dictionary in CrewPanel.build_entries(peer_ids, players, local_id, online, 0):
		if not bool(entry["is_local"]):
			result.append(entry)
	return result


## One row per entry, or a single muted line when there is nobody else.
## A gamepad player sitting on a crewmate's control keeps the focus there
## (or on the voice switch when that crewmate left): a freed focus owner
## would leave the stick with nothing to move.
func render_crew(entries: Array[Dictionary]) -> void:
	var focus_spot: PackedStringArray = _focused_crew_spot()
	for child: Node in _crew_box.get_children():
		_crew_box.remove_child(child)
		child.queue_free()
	if entries.is_empty():
		var empty: Label = UiTheme.label(_crew_box, tr("UI_OPT_VOICE_NOBODY"), 14, UiTheme.MUTED)
		empty.name = "Nobody"
		return
	for entry: Dictionary in entries:
		_add_crewmate(entry)
	if not focus_spot.is_empty():
		var row: Node = _crew_box.get_node_or_null(NodePath(focus_spot[0]))
		var again: Control = null
		if row != null:
			again = row.find_child(focus_spot[1], true, false) as Control
		(again if again != null else voice_check).grab_focus()


## Which crewmate row ("Peer_<id>") and which of its controls ("Mute",
## "Volume") hold the focus, or empty. By name: the containers in between get
## new generated names on every rebuild.
func _focused_crew_spot() -> PackedStringArray:
	if not is_inside_tree():
		return PackedStringArray()
	var owner_control: Control = get_viewport().gui_get_focus_owner()
	if owner_control == null or not _crew_box.is_ancestor_of(owner_control):
		return PackedStringArray()
	var row: Node = owner_control
	while row.get_parent() != _crew_box:
		row = row.get_parent()
	return PackedStringArray([String(row.name), String(owner_control.name)])


func _add_crewmate(entry: Dictionary) -> void:
	var peer_id: int = int(entry["peer_id"])
	var box := VBoxContainer.new()
	box.name = "Peer_%d" % peer_id
	box.add_theme_constant_override("separation", 4)
	_crew_box.add_child(box)
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 10)
	box.add_child(header)
	var swatch := Panel.new()
	swatch.name = "Swatch"
	swatch.custom_minimum_size = Vector2(SWATCH, SWATCH)
	swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var style := StyleBoxFlat.new()
	style.bg_color = entry["color"]
	style.border_color = UiTheme.INK
	style.set_border_width_all(UiTheme.OUTLINE)
	style.set_corner_radius_all(6)
	swatch.add_theme_stylebox_override("panel", style)
	header.add_child(swatch)
	var who: Label = UiTheme.label(header, String(entry["name"]), 18, UiTheme.INK)
	who.name = "Name"
	who.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var mute: CheckBox = UiTheme.check_box(header, tr("UI_OPT_VOICE_MUTE"), ProximityVoice.is_peer_muted(peer_id))
	mute.name = "Mute"
	mute.toggled.connect(func(pressed: bool) -> void: ProximityVoice.set_peer_muted(peer_id, pressed))
	var volume: HSlider = UiTheme.slider_row(box, tr("UI_OPT_VOICE_PEER_VOLUME"), 0.0, 1.0, VOLUME_STEP,
			ProximityVoice.peer_volume(peer_id))
	volume.name = "Volume"
	volume.value_changed.connect(func(value: float) -> void: ProximityVoice.set_peer_volume(peer_id, value))


func _on_roster_changed(_peer_ids: Array) -> void:
	_refresh_if_shown()


func _on_color_slots_changed(_slots: Dictionary) -> void:
	_refresh_if_shown()


## The roster moves while the options are closed too (nobody sees it then);
## open() rebuilds the list anyway.
func _refresh_if_shown() -> void:
	if is_visible_in_tree():
		refresh_crew.call_deferred()
