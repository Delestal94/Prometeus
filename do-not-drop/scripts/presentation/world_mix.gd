extends RefCounted
## The mixing desk for the world's and the truck's sounds (tareas de Nacho
## N-404): every player's volume_db lives here, set by measurement instead of
## by ear. tests/test_world_audio_levels.gd synthesizes each sound
## (SynthAudio), measures it and checks that the sound plus its level lands
## within 2 dB of its class's target, at the player's reference distance
## (unit_size):
##
##   engine   loop RMS       -20 dBFS   the truck's engine at full throttle
##   impact   peak           -14 dBFS   the hardest hit
##   noise    loop RMS       -35 dBFS   wind and the distant road: band noise, which
##                                      at -28 read as rain on the depot's roof
##   nature   loudest 100 ms -24 dBFS   birds or crickets: chirps with silence between,
##                                      whose RMS would say nothing about how loud they are
##   rain     loop RMS       -32 dBFS   outdoors; louder in the cabin, silent in the depot
##                                      (-24 at first: it drowned everything, playtest 2026-09-25)
##   signal   loudest 100 ms -18 dBFS   one-shots that call for attention: horn,
##                                      crossing bell, doorbell, animals, door motor
##   detail   peak           -26 dBFS   small things: loose clutter in the cargo box
##   music    loop RMS       -24 dBFS   the depot's radio (Music bus)
##   machine  loop RMS       -40 dBFS   the forklift's engine going back and forth
##   repeat   loudest 100 ms -30 dBFS   the forklift's reverse beep, over and over
## (The last two were "ambient" and "signal" at first, and the depot got
## grating: a sound that never stops sits well under one that calls once.)
##
## The table and the before/after values are in docs/audio-mundo.md.

# Truck (vehicle_presentation.gd, vehicle.gd, cargo_clutter.gd).
const ENGINE_DB: float = -7.0
const IMPACT_DB: float = -14.0
const SCREECH_DB: float = -8.0
const HORN_DB: float = -10.5
const CLUTTER_DB: float = -26.0

# The crew (player_sprint.gd): a footfall while running, "detail" class.
const FOOTSTEP_DB: float = -20.0

# Outdoors (route.gd, route_sky.gd).
## The wind, the distant road, the crickets and the dog's bark are
## normalised by SynthAudio itself (its *_STREAM_*_DB constants), so these
## four are just the class target minus that.
const WIND_DB: float = -15.0
const BIRDS_DB: float = -4.5
## 1.5 dB under the nature target on purpose: crickets are the one bed
## that plays all night (playtest 2026-09-25).
const CRICKETS_DB: float = -5.5
const DISTANT_ROAD_DB: float = -15.0
const RAIN_DB: float = -8.0
## Rain drums louder on the cabin's roof. Inside the depot it isn't heard at
## all (RouteSky.rain_db): under the big tin roof it was deafening.
const RAIN_UNDER_ROOF_BOOST_DB: float = 3.0

# Along the route (rail_crossing_segment.gd, chasing_dog.gd,
# flock_crossing.gd, delivery_house.gd).
const CROSSING_BELL_DB: float = 0.0
const DOG_BARK_DB: float = -6.0
const SHEEP_BLEAT_DB: float = -7.5
## The animals that go for the cargo (cargo_animals.gd, N-109): the gull's cry
## is a signal like the bark (class "signal", measured by test_cargo_animals); the
## bees' buzz is a steady drone of the "noise" class, quiet enough to be a warning
## you notice rather than one you're startled by.
const GULL_CRY_DB: float = -5.0
const BEE_BUZZ_DB: float = -14.5
## doorbell_ding_dong() and neighbor_cheer() self-normalise to their own
## *_STREAM_LOUDEST_DB (SynthAudio), so these two are just the "signal"
## target (-18) minus that -- same reasoning as DOG_BARK_DB.
const DOORBELL_DB: float = -6.0
## The resident at the door: a cheer for a good box, a groan for a wreck, a
## quieter groan for a dented one, and a quieter still for the wrong box.
const RESIDENT_CHEER_DB: float = -6.0
const RESIDENT_GROAN_DB: float = -13.0
const RESIDENT_AT_RISK_OFFSET_DB: float = -6.0
const RESIDENT_WRONG_BOX_OFFSET_DB: float = -10.0
## The cartoon steam train at the crossing (rail_crossing_segment.gd): the
## whistle self-normalises like the doorbell above; the chugging loop to
## -20 (the "engine" target) minus its own -14 RMS -- as loud passing by as
## the truck's own engine at full throttle, which is the point.
const TRAIN_HORN_DB: float = -6.0
const TRAIN_CHUG_DB: float = -6.0
## A crewmate's quick callout (N-505, hud_notices.gd): callout_voice()
## self-normalises like the doorbell, so this is the "signal" target minus that.
const CALLOUT_VOICE_DB: float = -6.0

# The depot (depot.gd, depot_forklift.gd, depot_roller_door.gd).
## The radio plays mus_depot_radio_loop.ogg (N-403, tools/audio/compose_music.py),
## measured in assets/audio/music/loudness.json: -19.4 dBFS RMS, -4.5 dB to -24.
const DEPOT_RADIO_DB: float = -4.5
const FORKLIFT_BEEP_DB: float = -17.5
## forklift_motor_loop() self-normalises to -16 RMS; the "machine" target is
## -40, same reasoning as the truck's own ENGINE_DB is engine_loop()'s raw level.
const FORKLIFT_ENGINE_DB: float = -24.0
const ROLLER_DOOR_DB: float = -1.0

# The river under the narrow bridge (narrow_bridge_segment.gd). Positioned
# 3D, so this is its level at the player's unit_size, same as the crossing
# bell above. river_flow_loop() self-normalises to -20 RMS; the "noise"
# target is -35, same reasoning as WIND_DB.
const RIVER_DB: float = -15.0

# Menus (menu_music.gd, N-403): the menu theme sits exactly as loud as the
# in-game track does under ingame_music.gd's -14 dB (loudness.json: in-game
# -15.8, menu -16.6 dBFS RMS).
const MENU_MUSIC_DB: float = -13.2
