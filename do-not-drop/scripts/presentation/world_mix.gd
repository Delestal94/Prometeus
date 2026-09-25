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
##   ambient  loop RMS       -28 dBFS   wind, distant road, depot hum, forklift engine
##   nature   loudest 100 ms -24 dBFS   birds or crickets: chirps with silence between,
##                                      whose RMS would say nothing about how loud they are
##   rain     loop RMS       -24 dBFS   outdoors; louder drumming under a roof
##   signal   loudest 100 ms -18 dBFS   one-shots that call for attention: horn,
##                                      crossing bell, doorbell, animals, door motor
##   detail   peak           -26 dBFS   small things: loose clutter in the cargo box
##   music    loop RMS       -24 dBFS   the depot's radio (Music bus)
##   room     loop RMS       -42 dBFS   the depot's hum: always on, felt more than heard
##   machine  loop RMS       -40 dBFS   the forklift's engine going back and forth
##   repeat   loudest 100 ms -30 dBFS   the forklift's reverse beep, over and over
## (The last three were "ambient" and "signal" at first, and the depot got
## grating: a sound that never stops sits well under one that calls once.)
##
## The table and the before/after values are in docs/audio-mundo.md.

# Truck (vehicle_presentation.gd, vehicle.gd, cargo_clutter.gd).
const ENGINE_DB: float = -7.0
const IMPACT_DB: float = -14.0
const SCREECH_DB: float = -8.0
const HORN_DB: float = -10.5
const CLUTTER_DB: float = -26.0

# Outdoors (route.gd, route_sky.gd).
const WIND_DB: float = -14.5
const BIRDS_DB: float = -4.5
const CRICKETS_DB: float = -4.0
const DISTANT_ROAD_DB: float = -12.0
const RAIN_DB: float = 0.0
## Rain drums louder on a roof overhead (the cabin, the depot).
const RAIN_UNDER_ROOF_BOOST_DB: float = 6.0

# Along the route (rail_crossing_segment.gd, chasing_dog.gd,
# flock_crossing.gd, delivery_house.gd).
const CROSSING_BELL_DB: float = 0.0
const DOG_BARK_DB: float = -7.5
const SHEEP_BLEAT_DB: float = -7.5
const DOORBELL_DB: float = -7.0
## The resident at the door: a cheer for a good box, a groan for a wreck, a
## quieter groan for a dented one, and a quieter still for the wrong box.
const RESIDENT_CHEER_DB: float = -10.5
const RESIDENT_GROAN_DB: float = -13.0
const RESIDENT_AT_RISK_OFFSET_DB: float = -6.0
const RESIDENT_WRONG_BOX_OFFSET_DB: float = -10.0

# The depot (depot.gd, depot_forklift.gd, depot_roller_door.gd).
const WAREHOUSE_HUM_DB: float = -21.5
## The radio plays mus_depot_radio_loop.ogg (N-403, tools/audio/compose_music.py),
## measured in assets/audio/music/loudness.json: -19.4 dBFS RMS, -4.5 dB to -24.
const DEPOT_RADIO_DB: float = -4.5
const FORKLIFT_BEEP_DB: float = -17.5
const FORKLIFT_ENGINE_DB: float = -27.0
const ROLLER_DOOR_DB: float = -1.0

# Menus (menu_music.gd, N-403): the menu theme sits exactly as loud as the
# in-game track does under ingame_music.gd's -14 dB (loudness.json: in-game
# -15.8, menu -16.6 dBFS RMS).
const MENU_MUSIC_DB: float = -13.2
