extends RefCounted
class_name AcousticSpace
## Echo under a roof (tareas de Nacho N-402): while the listener -- this
## client's camera -- is inside a tunnel or the depot, the world's sounds get
## a long reverb; out in the open, none. Purely local, like the Interior /
## Exterior pick (vehicle_presentation.gd): each client hears the space its
## own camera is in.
##
## Spaces are nodes in the "acoustic_space" group that answer
## covers(point) and have an `acoustic_space` property (&"tunnel", &"roof"):
## TunnelSegment's AcousticZone (an Area3D along the bore) and the depot.
## RouteSky asks listening_space() every frame and hands the answer to
## apply(), which switches one AudioEffectReverb on BUSES (added once, at
## runtime: the bus layout file stays as it is).

## The world's sounds (SFX: horn, bells, animals, the depot's machines) and
## the truck heard from outside (Exterior). Inside the cab (Interior) the
## cabin's own reverb already colours everything.
const BUSES: Array[StringName] = [&"SFX", &"Exterior"]
const EFFECT_NAME: String = "AcousticSpaceReverb"
## [room_size, damping, wet, predelay_msec] per space.
const SPACES: Dictionary = {
	&"tunnel": [0.95, 0.15, 0.42, 70.0],
	&"roof": [0.8, 0.35, 0.26, 40.0],
}

static var current: StringName = &"open"


## Which space `point` is in: the first node of the group that covers it.
static func listening_space(tree: SceneTree, point: Vector3) -> StringName:
	if tree == null:
		return &"open"
	for node: Node in tree.get_nodes_in_group(&"acoustic_space"):
		if node.has_method(&"covers") and bool(node.call(&"covers", point)):
			return StringName(node.get(&"acoustic_space"))
	return &"open"


## Switches the reverb for `space` on (or off, for &"open"). Cheap to call
## every frame: it only touches the AudioServer when the space changes.
static func apply(space: StringName) -> void:
	if space == current and _all_buses_ready():
		return
	current = space
	for bus_name: StringName in BUSES:
		var bus: int = AudioServer.get_bus_index(bus_name)
		if bus < 0:
			continue
		var index: int = _effect_index(bus)
		var reverb := AudioServer.get_bus_effect(bus, index) as AudioEffectReverb
		var settings: Array = SPACES.get(space, [])
		if not settings.is_empty():
			reverb.room_size = float(settings[0])
			reverb.damping = float(settings[1])
			reverb.wet = float(settings[2])
			reverb.predelay_msec = float(settings[3])
			reverb.dry = 1.0
		AudioServer.set_bus_effect_enabled(bus, index, not settings.is_empty())


## The reverb's slot on a bus, adding it (disabled) the first time.
static func _effect_index(bus: int) -> int:
	for index: int in range(AudioServer.get_bus_effect_count(bus)):
		var effect: AudioEffect = AudioServer.get_bus_effect(bus, index)
		if effect is AudioEffectReverb and effect.resource_name == EFFECT_NAME:
			return index
	var reverb := AudioEffectReverb.new()
	reverb.resource_name = EFFECT_NAME
	AudioServer.add_bus_effect(bus, reverb)
	var added: int = AudioServer.get_bus_effect_count(bus) - 1
	AudioServer.set_bus_effect_enabled(bus, added, false)
	return added


static func _all_buses_ready() -> bool:
	for bus_name: StringName in BUSES:
		var bus: int = AudioServer.get_bus_index(bus_name)
		if bus < 0:
			continue
		var found: bool = false
		for index: int in range(AudioServer.get_bus_effect_count(bus)):
			var effect: AudioEffect = AudioServer.get_bus_effect(bus, index)
			if effect is AudioEffectReverb and effect.resource_name == EFFECT_NAME:
				found = true
		if not found:
			return false
	return true


## Whether the reverb for a space is on right now, on every bus (tests).
static func is_on() -> bool:
	for bus_name: StringName in BUSES:
		var bus: int = AudioServer.get_bus_index(bus_name)
		if bus < 0:
			continue
		var index: int = _effect_index(bus)
		if not AudioServer.is_bus_effect_enabled(bus, index):
			return false
	return true
