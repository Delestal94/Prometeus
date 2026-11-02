class_name ShedMusic
extends AudioStreamPlayer
## The shed's music (expansion D-1911): the work loop SynthAudio composes in three stems (bed, groove, lead),
## played in sync as one AudioStreamSynchronized and mixed by how busy the company is. Local to each peer,
## nothing about it is networked: every peer hears the same business events and so the same mix.
##
## - Activity: every business event this peer applies (CompanyNet.event_applied) adds EVENT_ENERGY, up to 1;
##   it drains at DECAY_PER_SECOND. The clock and the day's phases are not work and add nothing.
## - The mix follows the activity smoothly (FOLLOW_PER_SECOND): the bed always plays, the groove comes in
##   between GROOVE_RAMP's two values and the lead between LEAD_RAMP's; a quiet shed falls back to the bed.
## - The day's closing screen and the time between days (SUMMARY, IDLE) fade the whole loop out; the next
##   day's opening brings it back.
## - The "Music" bus, so the player's music volume (GameSettings) sets it; it keeps playing under the pause.

const VOLUME_DB: float = -12.0
const SILENT_DB: float = -60.0
const EVENT_ENERGY: float = 0.06
const DECAY_PER_SECOND: float = 0.015
const FOLLOW_PER_SECOND: float = 0.25
const GATE_PER_SECOND: float = 0.5
## Activity where a layer starts to come in and where it is full.
const GROOVE_RAMP := Vector2(0.2, 0.45)
const LEAD_RAMP := Vector2(0.55, 0.85)
## Events that are not work: the clock's anchor and the day's phases.
const QUIET_EVENTS: Array[StringName] = [&"clock_anchor", &"day_phase"]
## Phases in which the loop is out (DayCycle.PHASE_NAMES).
const RESTING_PHASES: Array[String] = ["IDLE", "SUMMARY"]

## How busy the shed is, 0 to 1 (what the events add, draining).
var activity: float = 0.0
## The mix's level, following `activity` smoothly.
var level: float = 0.0
## 1 while a day runs, 0 resting; `gate` follows it.
var gate_target: float = 1.0
var gate: float = 1.0
var _synced: AudioStreamSynchronized


## The music under `root` (CompanyRoot), following root.net's events.
static func add_to(root: Node) -> ShedMusic:
	var music := ShedMusic.new()
	music.name = "ShedMusic"
	root.add_child(music)
	var net: Object = root.get(&"net")
	if net != null and net.has_signal(&"event_applied"):
		net.connect(&"event_applied", music.on_event)
	return music


func _ready() -> void:
	_synced = AudioStreamSynchronized.new()
	_synced.stream_count = SynthAudioWorkMusic.LAYERS
	for layer: int in SynthAudioWorkMusic.LAYERS:
		_synced.set_sync_stream(layer, SynthAudio.work_music_layer(layer))
	stream = _synced
	bus = &"Music" if AudioServer.get_bus_index(&"Music") >= 0 else &"Master"
	volume_db = VOLUME_DB
	process_mode = Node.PROCESS_MODE_ALWAYS
	_apply()
	play()


func _process(delta: float) -> void:
	advance(delta)


## A business event applied on this peer: work adds activity; a day phase opens or rests the loop.
func on_event(_seq: int, kind: StringName, data: Dictionary) -> void:
	if kind == &"day_phase":
		gate_target = 0.0 if RESTING_PHASES.has(str(data.get("phase", ""))) else 1.0
		return
	if QUIET_EVENTS.has(kind):
		return
	activity = minf(activity + EVENT_ENERGY, 1.0)


## Runs the mix `seconds` on. Public so a test can run it without frames.
func advance(seconds: float) -> void:
	activity = maxf(activity - DECAY_PER_SECOND * seconds, 0.0)
	level = move_toward(level, activity, FOLLOW_PER_SECOND * seconds)
	gate = move_toward(gate, gate_target, GATE_PER_SECOND * seconds)
	_apply()


## A layer's share at a mix level, 0 to 1: the bed always, the others along their ramps.
static func layer_gain(layer: int, at_level: float) -> float:
	match layer:
		0:
			return 1.0
		1:
			return smoothstep(GROOVE_RAMP.x, GROOVE_RAMP.y, at_level)
		2:
			return smoothstep(LEAD_RAMP.x, LEAD_RAMP.y, at_level)
	return 0.0


## The volume a layer plays at now, in dB (SILENT_DB at most quiet).
func layer_db(layer: int) -> float:
	var linear: float = layer_gain(layer, level) * smoothstep(0.0, 1.0, gate)
	return maxf(linear_to_db(maxf(linear, 0.000001)), SILENT_DB)


func _apply() -> void:
	if _synced == null:
		return
	for layer: int in SynthAudioWorkMusic.LAYERS:
		_synced.set_sync_stream_volume(layer, layer_db(layer))
