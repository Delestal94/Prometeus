class_name SynthAudio
extends RefCounted
## Tiny procedural waveforms, generated at runtime instead of shipping .wav
## assets -- same "no art yet, code is the source of truth" convention as
## route.gd's boxes and package_feedback.gd's confetti cubes.
##
## This is the one door to every synthesized sound: each accessor builds its stream once
## (the cache) and hands out the shared copy. The synthesis itself lives in the scripts by
## responsibility, where the details of each sound are documented:
##   SynthAudioVehicle   engine layers, impact, tyre screech, horn
##   SynthAudioTraps     the traps' cues (chime, groan, creak, slosh, tick, hiss)
##   SynthAudioHandling  camera shutter, tape, cardboard, tension bed
##   SynthAudioWorld     wind, rain, birds, crickets, road, crossing bell, roller door, reverse beep
##   SynthAudioAnimals   dog bark, sheep bleat
##   SynthAudioScenes    doorbell, cheer, comic stingers, forklift, river, train, scanner, callout
##   SynthAudioCare      the care panel's cues      SynthAudioDsp  the shared tools (seam, levels)

## Every sound is synthesized sample by sample (~50 ms for the wind bed), so each is built once and
## shared: a stream is read-only data, and every AudioStreamPlayer keeps its own playback of it.
static var _cache: Dictionary = {}
const SCENE_SOUNDS_FILE: String = "synth_audio_scenes.gd"
static var _scene_sounds_script: Script


static func _cached(key: StringName, build: Callable) -> AudioStreamWAV:
	if not _cache.has(key):
		_cache[key] = build.call()
	return _cache[key]


## Loaded by a path relative to this file (SynthAudioScenes used to call back into SynthAudio, so no preload).
static func _scene_builder(method: StringName) -> Callable:
	if _scene_sounds_script == null:
		var here: String = (SynthAudio as Script).resource_path.get_base_dir()
		_scene_sounds_script = load(here.path_join(SCENE_SOUNDS_FILE)) as Script
	return Callable(_scene_sounds_script, method)


## Vehicle sounds, built by SynthAudioVehicle.


## Quiet harmonic exhaust loop (the middle layer); VehiclePresentation adjusts pitch and volume.
static func engine_loop() -> AudioStreamWAV:
	return _cached(&"engine_loop", SynthAudioVehicle.make_engine_loop)


## Engine ticking over: the low layer of the rev crossfade.
static func engine_idle_loop() -> AudioStreamWAV:
	return _cached(&"engine_idle_loop", SynthAudioVehicle.make_engine_idle_loop)


## Engine revving hard: the high layer of the rev crossfade.
static func engine_high_loop() -> AudioStreamWAV:
	return _cached(&"engine_high_loop", SynthAudioVehicle.make_engine_high_loop)


## Short low thump for a vehicle impact (vehicle_impact).
static func impact_thud() -> AudioStreamWAV:
	return _cached(&"impact_thud", SynthAudioVehicle.make_impact_thud)


## Looping tyre screech; pitch and volume follow the wheel skid.
static func tire_screech() -> AudioStreamWAV:
	return _cached(&"tire_screech", SynthAudioVehicle.make_tire_screech)


## Two-tone car horn (player.gd): the same clip for every player.
static func honk_horn() -> AudioStreamWAV:
	return _cached(&"honk_horn", SynthAudioVehicle.make_honk_horn)


## Traps sounds, built by SynthAudioTraps.


## Frágil's chime; package_feedback.gd pitches it down when the box is ruined.
static func glass_chime() -> AudioStreamWAV:
	return _cached(&"glass_chime", SynthAudioTraps.make_glass_chime)


## Ruidoso's looping groan; pitched and mixed by the agitation.
static func creature_groan() -> AudioStreamWAV:
	return _cached(&"creature_groan", SynthAudioTraps.make_creature_groan)


## Peso Creciente's creak, a one-shot retriggered while the crate is strained.
static func wood_creak() -> AudioStreamWAV:
	return _cached(&"wood_creak", SynthAudioTraps.make_wood_creak)


## Liquid's wet slosh when the puddle grows.
static func liquid_slosh() -> AudioStreamWAV:
	return _cached(&"liquid_slosh", SynthAudioTraps.make_liquid_slosh)


## Explosive's ticking.
static func explosive_tick() -> AudioStreamWAV:
	return _cached(&"explosive_tick", SynthAudioTraps.make_explosive_tick)


## Hostile's hiss.
static func hostile_hiss() -> AudioStreamWAV:
	return _cached(&"hostile_hiss", SynthAudioTraps.make_hostile_hiss)


## Handling sounds, built by SynthAudioHandling.


## The phone camera's two clicks (phone_camera.gd).
static func camera_shutter() -> AudioStreamWAV:
	return _cached(&"camera_shutter", SynthAudioHandling.make_camera_shutter)


## Packing tape torn off the first time a box is opened.
static func tape_rip() -> AudioStreamWAV:
	return _cached(&"tape_rip", SynthAudioHandling.make_tape_rip)


## A cardboard flap folding over.
static func cardboard_flap() -> AudioStreamWAV:
	return _cached(&"cardboard_flap", SynthAudioHandling.make_cardboard_flap)


## Tension bed under the music: drone and double heartbeat (ingame_music.gd).
static func tension_pulse() -> AudioStreamWAV:
	return _cached(&"tension_pulse", SynthAudioHandling.make_tension_pulse)


## World sounds, built by SynthAudioWorld.


## Rain loop (route_sky.gd); louder and through Interior inside the truck.
static func rain_loop() -> AudioStreamWAV:
	return _cached(&"rain_loop", SynthAudioWorld.make_rain_loop)


## Level crossing bell (rail_crossing_segment.gd).
static func crossing_bell() -> AudioStreamWAV:
	return _cached(&"crossing_bell", SynthAudioWorld.make_crossing_bell)


## Depot roller door motor and slats (depot_roller_door.gd).
static func roller_door() -> AudioStreamWAV:
	return _cached(&"roller_door", SynthAudioWorld.make_roller_door)


## Forklift reversing alarm.
static func reverse_beep() -> AudioStreamWAV:
	return _cached(&"reverse_beep", SynthAudioWorld.make_reverse_beep)


## World ambience: soft looping wind.
static func ambient_wind() -> AudioStreamWAV:
	return _cached(&"ambient_wind", SynthAudioWorld.make_ambient_wind)


## Outdoor bed: sparse birdsong, seeded.
static func ambient_birds() -> AudioStreamWAV:
	return _cached(&"ambient_birds", SynthAudioWorld.make_ambient_birds)


## Night bed: a few crickets, mostly silence.
static func night_crickets() -> AudioStreamWAV:
	return _cached(&"night_crickets", SynthAudioWorld.make_night_crickets)


## Far-off road: a car swelling and fading, looped.
static func distant_road() -> AudioStreamWAV:
	return _cached(&"distant_road", SynthAudioWorld.make_distant_road)


## Animals sounds, built by SynthAudioAnimals.


## The chasing dog's bark, one-shot (ChasingDog repeats it).
static func dog_bark() -> AudioStreamWAV:
	return _cached(&"dog_bark", SynthAudioAnimals.make_dog_bark)


## The flock's bleat, one-shot.
static func sheep_bleat() -> AudioStreamWAV:
	return _cached(&"sheep_bleat", SynthAudioAnimals.make_sheep_bleat)


## Scene sounds: built by SynthAudioScenes (see there for each), cached here like the rest.
static func doorbell_ding_dong() -> AudioStreamWAV:
	return _cached(&"doorbell_ding_dong", _scene_builder(&"make_doorbell_ding_dong"))


static func neighbor_cheer() -> AudioStreamWAV:
	return _cached(&"neighbor_cheer", _scene_builder(&"make_neighbor_cheer"))


static func comic_ruin_stinger() -> AudioStreamWAV:
	return _cached(&"comic_ruin_stinger", _scene_builder(&"make_comic_ruin_stinger"))


static func comic_boom() -> AudioStreamWAV:
	return _cached(&"comic_boom", _scene_builder(&"make_comic_boom"))


static func forklift_motor_loop() -> AudioStreamWAV:
	return _cached(&"forklift_motor_loop", _scene_builder(&"make_forklift_motor_loop"))


static func river_flow_loop() -> AudioStreamWAV:
	return _cached(&"river_flow_loop", _scene_builder(&"make_river_flow_loop"))


static func train_horn() -> AudioStreamWAV:
	return _cached(&"train_horn", _scene_builder(&"make_train_horn"))


static func train_chug_loop() -> AudioStreamWAV:
	return _cached(&"train_chug_loop", _scene_builder(&"make_train_chug_loop"))


static func scanner_beep() -> AudioStreamWAV:
	return _cached(&"scanner_beep", _scene_builder(&"make_scanner_beep"))


## A crewmate's quick callout (N-505): babble pitched by their colour slot.
static func callout_voice(color_slot: int = 0, syllables: int = 3) -> AudioStreamWAV:
	var slot: int = posmod(color_slot, SynthAudioScenes.CALLOUT_VOICE_PITCHES.size())
	var count: int = clampi(syllables, 1, SynthAudioScenes.CALLOUT_MAX_SYLLABLES)
	var key := StringName("callout_voice_%d_%d" % [slot, count])
	return _cached(key, SynthAudioScenes.make_callout_voice.bind(slot, count))


## Care panel cues (a HUD's short interface sounds), built by SynthAudioCare.


static func care_step() -> AudioStreamWAV:
	return _cached(&"care_step", SynthAudioCare.make_care_step)


static func care_error() -> AudioStreamWAV:
	return _cached(&"care_error", SynthAudioCare.make_care_error)


static func care_success() -> AudioStreamWAV:
	return _cached(&"care_success", SynthAudioCare.make_care_success)


static func care_whoosh() -> AudioStreamWAV:
	return _cached(&"care_whoosh", SynthAudioCare.make_care_whoosh)


static func care_tick() -> AudioStreamWAV:
	return _cached(&"care_tick", SynthAudioCare.make_care_tick)
