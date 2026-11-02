class_name CompanyMix
extends RefCounted
## The company world's mixing desk (expansion D-1912): its buses and the levels its sounds are measured at.
##
## Buses (default_bus_layout.tres), each sending to the one before it, so the player's volumes still apply:
##   Shed       the shed's room: a big-hall reverb, sends to SFX (the effects volume)
##   Machines   what runs by itself in the shed (the forklift today; conveyors and machines later), sends to Shed
##   Districts  the districts' own ambience and cues (D-1929, D-1931), sends to Exterior (its outdoor reverb)
## Every bus stays at 0 dB: they are knobs for the mix pass (D-1942), not a change of level. test_company_mix
## measures each company sound through its route (the stream, its player's volume_db, every bus on the way) and
## checks it lands within TOLERANCE_DB of its class here, as test_world_audio_levels does for the world's.
##
##   handling   loudest 100 ms  -31.5 dBFS  the clipboard in the hand: close, dry, under the world's foley
##   machine    loop RMS        -40 dBFS    the shed's forklift (WorldMix's machine class)
##   work music loop RMS        -30 dBFS    the shed's work loop with its bed alone (under the depot radio's -24:
##                                          it plays all day; the full three stems sum about 5 dB more)

const SHED: StringName = &"Shed"
const MACHINES: StringName = &"Machines"
const DISTRICTS: StringName = &"Districts"
const TOLERANCE_DB: float = 2.0
## Buses whose volume is a player's option (GameSettings.apply_bus_volume).
const PLAYER_BUSES: Array[StringName] = [&"Master", &"Music", &"SFX", &"Voice"]
const TARGETS_DB: Dictionary = {"handling": -31.5, "machine": -40.0, "work music": -30.0}


## `wanted` when the layout has it; else the bus it sends to in the layout (Machines -> Shed -> SFX, Districts ->
## Exterior), and Master at last: a project without the expansion's buses still plays the sound.
static func bus(wanted: StringName) -> StringName:
	var fallbacks: Dictionary = {MACHINES: SHED, SHED: &"SFX", DISTRICTS: &"Exterior", &"SFX": &"Master",
		&"Exterior": &"Master"}
	var name: StringName = wanted
	while name != &"Master" and AudioServer.get_bus_index(name) < 0:
		name = fallbacks.get(name, &"Master")
	return name


## The buses a sound on `from` goes through, Master included, in order.
static func route(from: StringName) -> Array[StringName]:
	var path: Array[StringName] = []
	var name: StringName = from
	while AudioServer.get_bus_index(name) >= 0 and not path.has(name):
		path.append(name)
		if name == &"Master":
			break
		name = AudioServer.get_bus_send(AudioServer.get_bus_index(name))
	return path


## The gain the mix adds on the route, in dB: every bus but the ones the player's volume sliders own
## (PLAYER_BUSES: GameSettings sets them from the saved options, so they are the player's, not the mix's).
static func route_gain_db(from: StringName) -> float:
	var gain: float = 0.0
	for name: StringName in route(from):
		if not PLAYER_BUSES.has(name):
			gain += AudioServer.get_bus_volume_db(AudioServer.get_bus_index(name))
	return gain
