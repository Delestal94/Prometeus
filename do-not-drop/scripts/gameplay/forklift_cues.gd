class_name ForkliftCues
extends Node3D
## What the shed's forklift sounds and shows (expansion D-0606.c3), a child of ForkliftView that feeds it from
## refresh() and _process(). Pure presentation, local to every peer: it reads the book's state (is there a
## driver, are the forks moving) and nothing travels.
##
## - While somebody drives: the electric motor of the depot's forklift (SynthAudio.forklift_motor_loop), steady
##   at a walking-pace idle and a tone higher while the forklift is actually moving, and the amber beacon on its
##   post blinking (a light that turns would need a spot and a shadow; a pulse of the lens and of a small
##   shadowless OmniLight3D reads the same and costs nothing in GL Compatibility).
## - While the forks go up or down: the hydraulic pump (SynthAudio.forklift_hydraulic_loop), a tone lower going
##   down, whoever has the forklift. No reverse beeper: the depot's already beeps and this one is driven by hand.
## Both sounds are positional (AudioStreamPlayer3D, bus SFX like the depot forklift's), so a teammate is heard
## fading with distance, and fade in and out in a few tenths of a second instead of starting and stopping on a click.

const WorldMix = preload("res://scripts/presentation/world_mix.gd")
const BEACON_COLOR := Color("ffb02e")
## Where the beacon sits: on a post above the driver's seat (the forklift is built facing -Z).
const BEACON_AT := Vector3(0.4, 2.05, 0.7)
const POST_HEIGHT: float = 1.4
## Blinks per second (as in the depot forklift's: about 1.4 Hz).
const FLASH_RATE: float = 9.0
const FADE_SECONDS: float = 0.25
## Metres per second from which the forklift counts as moving (its engine gets the higher tone).
const MOVING_MPS: float = 0.3
const IDLE_PITCH: float = 0.85
const MOVING_PITCH: float = 1.25
const FORKS_UP_PITCH: float = 1.0
const FORKS_DOWN_PITCH: float = 0.8

var _engine: AudioStreamPlayer3D
var _hydraulic: AudioStreamPlayer3D
var _lens: MeshInstance3D
var _light: OmniLight3D
var _driving: bool = false
var _fork_dir: int = 0
## 0..1, how much of each sound has faded in.
var _engine_gain: float = 0.0
var _hydraulic_gain: float = 0.0
var _flash_time: float = 0.0
var _last_position: Vector3 = Vector3.ZERO
var _has_last: bool = false


## The cues, built and silent (no driver, forks still): ForkliftView adds it to itself.
static func make() -> ForkliftCues:
	var cues := ForkliftCues.new()
	cues.name = "Cues"
	cues._build()
	cues.set_process(false)
	return cues


## What happens now: somebody `driving`, and the forks going `fork_dir` (1 up, -1 down, 0 still).
func update(driving: bool, fork_dir: int) -> void:
	_driving = driving
	_fork_dir = clampi(fork_dir, -1, 1)
	if _fork_dir != 0:
		_hydraulic.pitch_scale = FORKS_UP_PITCH if _fork_dir > 0 else FORKS_DOWN_PITCH
	if not driving:
		_has_last = false
	_apply_beacon()
	set_process(_busy())


## Whether the engine is meant to sound (somebody drives).
func engine_on() -> bool:
	return _driving


## Whether the hydraulic pump is meant to sound (the forks are going).
func hydraulic_on() -> bool:
	return _fork_dir != 0


## Whether the beacon is lit (the lens and the light are on, whatever phase of the blink they are in).
func beacon_on() -> bool:
	return _driving


## Whether a sound is still being played out (a fade in or out is not over).
func engine_playing() -> bool:
	return _engine.playing


func hydraulic_playing() -> bool:
	return _hydraulic.playing


func _process(delta: float) -> void:
	_fade(_engine, _driving, delta, true)
	_fade(_hydraulic, _fork_dir != 0, delta, false)
	if _driving:
		_flash_time += delta
		_steer_engine(delta)
	_apply_beacon()
	if not _busy():
		set_process(false)


func _busy() -> bool:
	return _driving or _fork_dir != 0 or _engine.playing or _hydraulic.playing


func _fade(player: AudioStreamPlayer3D, wanted: bool, delta: float, is_engine: bool) -> void:
	var gain: float = _engine_gain if is_engine else _hydraulic_gain
	gain = move_toward(gain, 1.0 if wanted else 0.0, delta / FADE_SECONDS)
	if is_engine:
		_engine_gain = gain
	else:
		_hydraulic_gain = gain
	if wanted and not player.playing:
		player.play()
	elif gain <= 0.0 and player.playing and not wanted:
		player.stop()
		return
	var base: float = WorldMix.SHED_FORKLIFT_ENGINE_DB if is_engine else WorldMix.SHED_FORKLIFT_HYDRAULIC_DB
	player.volume_db = base + linear_to_db(maxf(gain, 0.0001))


## The motor takes the higher tone while the forklift moves, measured on where it is (the driver's own
## replicated pose on every peer, so no speed has to be sent).
func _steer_engine(delta: float) -> void:
	var here: Vector3 = global_position
	var speed: float = 0.0
	if _has_last and delta > 0.0:
		speed = here.distance_to(_last_position) / delta
	_last_position = here
	_has_last = true
	_engine.pitch_scale = lerpf(_engine.pitch_scale, MOVING_PITCH if speed > MOVING_MPS else IDLE_PITCH,
		clampf(delta * 3.0, 0.0, 1.0))


func _apply_beacon() -> void:
	var flash: bool = _driving and sin(_flash_time * FLASH_RATE) > 0.2
	_light.visible = _driving
	_light.light_energy = 0.9 if flash else 0.1
	(_lens.material_override as StandardMaterial3D).emission_energy_multiplier = 3.0 if flash \
		else (0.4 if _driving else 0.0)


func _build() -> void:
	var post := MeshInstance3D.new()
	post.name = "BeaconPost"
	var rod := BoxMesh.new()
	rod.size = Vector3(0.05, POST_HEIGHT, 0.05)
	rod.material = DepotKit.flat(ForkliftView.DARK_COLOR)
	post.mesh = rod
	post.position = Vector3(BEACON_AT.x, BEACON_AT.y - 0.07 - POST_HEIGHT * 0.5, BEACON_AT.z)
	add_child(post)
	_lens = MeshInstance3D.new()
	_lens.name = "Beacon"
	var dome := CylinderMesh.new()
	dome.top_radius = 0.07
	dome.bottom_radius = 0.09
	dome.height = 0.14
	_lens.mesh = dome
	# Its own copy: the glow is shared and cached, and this one blinks.
	_lens.material_override = DepotKit.glow(BEACON_COLOR, 0.4).duplicate()
	_lens.position = BEACON_AT
	add_child(_lens)
	_light = OmniLight3D.new()
	_light.name = "BeaconLight"
	_light.light_color = BEACON_COLOR
	_light.omni_range = 4.0
	_light.shadow_enabled = false
	_light.position = BEACON_AT + Vector3(0.0, 0.2, 0.0)
	_light.visible = false
	add_child(_light)
	_engine = _player("Motor", SynthAudio.forklift_motor_loop(), WorldMix.SHED_FORKLIFT_ENGINE_DB)
	_engine.pitch_scale = IDLE_PITCH
	_hydraulic = _player("Hydraulics", SynthAudio.forklift_hydraulic_loop(), WorldMix.SHED_FORKLIFT_HYDRAULIC_DB)
	_apply_beacon()


func _player(player_name: String, stream: AudioStream, volume_db: float) -> AudioStreamPlayer3D:
	var player := AudioStreamPlayer3D.new()
	player.name = player_name
	player.stream = stream
	player.bus = &"SFX"
	player.volume_db = volume_db
	player.unit_size = 3.0
	player.max_distance = 25.0
	add_child(player)
	return player
