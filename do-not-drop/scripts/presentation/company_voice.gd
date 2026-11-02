class_name CompanyVoice
extends Control
## Who talks in the company world, and how (expansion D-1928, diseno/narrativa-empresa.md: no recorded voice, only
## text and murmurs): say() shows the line in a speech bubble and plays the speaker's murmur
## (SynthAudio.murmur(), one syllable per vowel group of the line), on the Voice bus.
## - The boss (the Jefa) speaks on the radio: a bubble at the bottom of the screen with her name, the murmur through
##   the radio, not positional. She opens every day (day_phase OPENING): "Arrancamos el día N".
## - Anyone else with a spot (`at`, a world position) speaks in a bubble over it (Label3D) with a positional murmur.
## A bubble stays BUBBLE_SECONDS plus a little per syllable, then goes. Local to each peer: every peer applies the
## same events, so every peer hears the same lines.

const BUBBLE_SECONDS: float = 2.5
const PER_SYLLABLE_SECONDS: float = 0.15
const VOICE_DB: float = -6.0
const BOSS: StringName = &"boss"
const KEY_BOSS_NAME: String = "WORLD_VOICE_BOSS"
const KEY_DAY_OPEN: String = "WORLD_VOICE_BOSS_DAY_OPEN"

## The last line said ({voice, text, syllables}), for a test.
var last_line: Dictionary = {}
var _radio_box: PanelContainer
var _radio_label: Label
var _radio_player: AudioStreamPlayer
var _radio_left: float = 0.0


## The voices under `root` (CompanyRoot), with the boss opening each day from root.net's events.
static func add_to(root: Node) -> CompanyVoice:
	var layer := CanvasLayer.new()
	layer.name = "CompanyVoiceLayer"
	root.add_child(layer)
	var voice := CompanyVoice.new()
	voice.name = "CompanyVoice"
	layer.add_child(voice)
	var net: Object = root.get(&"net")
	if net != null and net.has_signal(&"event_applied"):
		net.connect(&"event_applied", voice.on_event)
	return voice


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	UiTheme.apply(self, false)
	set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	offset_top = -150.0
	offset_bottom = -90.0
	offset_left = -320.0
	offset_right = 320.0
	_radio_box = PanelContainer.new()
	_radio_box.name = "RadioBubble"
	_radio_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_radio_box.add_theme_stylebox_override(&"panel", UiTheme.surface_style(12))
	_radio_box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_radio_box)
	_radio_label = UiTheme.label(_radio_box, "", 18, UiTheme.INK)
	_radio_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_radio_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_radio_box.hide()
	_radio_player = AudioStreamPlayer.new()
	_radio_player.name = "RadioVoice"
	_radio_player.bus = &"Voice" if AudioServer.get_bus_index(&"Voice") >= 0 else &"Master"
	_radio_player.volume_db = VOICE_DB
	add_child(_radio_player)


func _process(delta: float) -> void:
	if _radio_left > 0.0:
		_radio_left -= delta
		if _radio_left <= 0.0:
			_radio_box.hide()


## A business event: the day's opening has the boss on the radio.
func on_event(_seq: int, kind: StringName, data: Dictionary) -> void:
	if kind == &"day_phase" and str(data.get("phase", "")) == "OPENING":
		say(BOSS, tr(KEY_DAY_OPEN) % int(data.get("day", 0)))


## `voice` says `text`: the boss on the radio, anyone else over `at` (a world position) when given. Returns the
## bubble (the radio's PanelContainer, or the Label3D over the spot).
func say(voice: StringName, text: String, at: Variant = null) -> Node:
	var syllables: int = SynthAudioMurmur.syllables_of(text)
	var seconds: float = BUBBLE_SECONDS + PER_SYLLABLE_SECONDS * syllables
	last_line = {"voice": voice, "text": text, "syllables": syllables}
	if voice == BOSS or not at is Vector3:
		_radio_label.text = "%s: %s" % [tr(KEY_BOSS_NAME), text] if voice == BOSS else text
		_radio_box.show()
		_radio_left = seconds
		_radio_player.stream = SynthAudio.murmur(voice, syllables)
		_radio_player.play()
		return _radio_box
	var bubble := Label3D.new()
	bubble.name = "Bubble"
	bubble.text = text
	bubble.font = UiTheme.display_font()
	bubble.font_size = 40
	bubble.pixel_size = 0.004
	bubble.modulate = UiTheme.INK
	bubble.outline_modulate = UiTheme.PAPER
	bubble.outline_size = 12
	bubble.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	bubble.width = 600.0
	bubble.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var speaker := AudioStreamPlayer3D.new()
	speaker.name = "Murmur"
	speaker.stream = SynthAudio.murmur(voice, syllables)
	speaker.bus = _radio_player.bus
	speaker.volume_db = VOICE_DB
	speaker.unit_size = 4.0
	bubble.add_child(speaker)
	var holder: Node = get_tree().current_scene if get_tree().current_scene != null else get_tree().root
	holder.add_child(bubble)
	bubble.global_position = (at as Vector3) + Vector3.UP * 2.2
	speaker.play()
	get_tree().create_timer(seconds).timeout.connect(func() -> void:
		if is_instance_valid(bubble):
			bubble.queue_free())
	return bubble


func radio_text() -> String:
	return _radio_label.text if _radio_box.visible else ""
