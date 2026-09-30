extends Node3D
## What the truck's radio shows and plays (tareas de Nacho N-406), on every
## peer: the dial turned to the mode, its name under it, the newscast's line
## above it for a few seconds, and the program by the Interior bus (the cab's
## room). Pure presentation: it only listens to TruckRadio's signals, so the
## mode it shows is whatever the host decided. Hung by TruckRadio on the
## knob, in the van's frame (its screen faces +Z, toward the driver).

const SOUNDS: Script = preload("res://scripts/presentation/synth_audio_radio.gd")
## Dial angle around its axis (degrees) for each mode, turning clockwise.
const DIAL_ANGLES: Dictionary = {&"calm": 60.0, &"loud": 20.0, &"news": -20.0, &"off": -60.0}
## Player level per mode (dB, on top of the loops' -24 dBFS RMS).
const PROGRAM_DB: Dictionary = {&"calm": -4.0, &"loud": 0.0}
const JINGLE_DB: float = -2.0
const CLICK_DB: float = -6.0
const NEWS_SECONDS: float = 7.0
const LIT := Color("39c4c9")
const DIM := Color("5b6b70")

## The TruckRadio whose mode this shows. Set by it before the node enters the tree.
var radio: Node
var dial: Node3D
var mode_label: Label3D
var news_label: Label3D
var music_player: AudioStreamPlayer3D
var cue_player: AudioStreamPlayer3D
var _news_left: float = 0.0


func _ready() -> void:
	_build()
	SOUNDS.call(&"warm")
	if radio == null:
		return
	radio.connect(&"mode_changed", _show_mode)
	radio.connect(&"news_announced", _on_news)
	_show_mode(radio.get(&"mode"), false)


func _process(delta: float) -> void:
	if _news_left <= 0.0:
		return
	_news_left -= delta
	if _news_left <= 0.0:
		news_label.text = ""


func _show_mode(mode: StringName, with_click: bool = true) -> void:
	dial.rotation.z = deg_to_rad(float(DIAL_ANGLES.get(mode, DIAL_ANGLES[&"off"])))
	mode_label.text = tr(String(radio.call(&"mode_key", mode)))
	mode_label.modulate = DIM if mode == &"off" else LIT
	if mode != &"news":
		news_label.text = ""
		_news_left = 0.0
	if PROGRAM_DB.has(mode):
		music_player.stream = SOUNDS.call(&"calm_loop") if mode == &"calm" else SOUNDS.call(&"loud_loop")
		music_player.volume_db = float(PROGRAM_DB[mode])
		music_player.play()
	else:
		music_player.stop()
	if with_click:
		_cue(SOUNDS.call(&"knob_click"), CLICK_DB)


func _on_news(line: String) -> void:
	news_label.text = line
	_news_left = NEWS_SECONDS
	_cue(SOUNDS.call(&"news_jingle"), JINGLE_DB)


func _cue(stream: AudioStreamWAV, volume_db: float) -> void:
	cue_player.stream = stream
	cue_player.volume_db = volume_db
	cue_player.play()


func _build() -> void:
	dial = Node3D.new()
	dial.name = "Dial"
	add_child(dial)
	var body := MeshInstance3D.new()
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = 0.032
	cylinder.bottom_radius = 0.036
	cylinder.height = 0.03
	cylinder.radial_segments = 14
	body.mesh = cylinder
	body.material_override = _flat(Color("1c2226"))
	# The cylinder's axis is Y; the dial turns about Z, facing the driver.
	body.rotation.x = PI * 0.5
	dial.add_child(body)
	var notch := MeshInstance3D.new()
	var bar := BoxMesh.new()
	bar.size = Vector3(0.006, 0.026, 0.006)
	notch.mesh = bar
	notch.material_override = _flat(Color("ffc93c"))
	notch.position = Vector3(0.0, 0.017, 0.017)
	dial.add_child(notch)
	mode_label = _label("ModeLabel", Vector3(0.0, -0.06, 0.01), 26)
	news_label = _label("NewsLabel", Vector3(0.0, 0.085, 0.01), 30)
	news_label.modulate = Color("e8fbff")
	music_player = _speaker("Program")
	music_player.max_distance = 9.0
	cue_player = _speaker("Cue")
	cue_player.max_distance = 9.0


func _label(label_name: String, at: Vector3, size: int) -> Label3D:
	var label := Label3D.new()
	label.name = label_name
	label.position = at
	label.pixel_size = 0.0007
	label.font_size = size
	label.outline_size = 6
	label.no_depth_test = false
	label.shaded = false
	label.text = ""
	add_child(label)
	return label


func _speaker(speaker_name: String) -> AudioStreamPlayer3D:
	var player := AudioStreamPlayer3D.new()
	player.name = speaker_name
	player.bus = &"Interior" if AudioServer.get_bus_index(&"Interior") >= 0 else &"Master"
	player.unit_size = 2.0
	add_child(player)
	return player


func _flat(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.8
	return material
