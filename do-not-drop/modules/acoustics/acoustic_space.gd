extends RefCounted
class_name AcousticSpace
## Echo under a roof: while the listener -- this client's camera -- is inside
## a tunnel or a hall, the world's sounds get a long reverb; out in the open,
## none. Purely local: each client hears the space its own camera is in.
##
## Spaces are nodes in the GROUP that answer covers(point) and have an
## `acoustic_space` property (a key of `spaces`): an AcousticZone (an Area3D
## box), or anything else that implements the same two members. Whoever
## follows the camera asks listening_space() every frame and hands the answer
## to apply(), which switches one AudioEffectReverb on `buses` (added once, at
## runtime: the bus layout file stays as it is).
##
## Portable module (docs/modulos.md): `buses` and `spaces` are configuration
## with Take My Package's values as defaults.

const GROUP: StringName = &"acoustic_space"
## The buses that get the reverb (the world's sounds, and a vehicle heard from
## outside; a cabin's own reverb already colours the inside).
static var buses: Array[StringName] = [&"SFX", &"Exterior"]
const EFFECT_NAME: String = "AcousticSpaceReverb"
## space -> [room_size, damping, wet, predelay_msec].
static var spaces: Dictionary = {
	&"tunnel": [0.95, 0.15, 0.42, 70.0],
	&"roof": [0.8, 0.35, 0.26, 40.0],
}

static var current: StringName = &"open"


## Which space `point` is in: the first node of the group that covers it.
static func listening_space(tree: SceneTree, point: Vector3) -> StringName:
	if tree == null:
		return &"open"
	for node: Node in tree.get_nodes_in_group(GROUP):
		if node.has_method(&"covers") and bool(node.call(&"covers", point)):
			return StringName(node.get(&"acoustic_space"))
	return &"open"


## Switches the reverb for `space` on (or off, for &"open"). Cheap to call
## every frame: it only touches the AudioServer when the space changes.
static func apply(space: StringName) -> void:
	if space == current and _all_buses_ready():
		return
	current = space
	for bus_name: StringName in buses:
		var bus: int = AudioServer.get_bus_index(bus_name)
		if bus < 0:
			continue
		var index: int = _effect_index(bus)
		var reverb := AudioServer.get_bus_effect(bus, index) as AudioEffectReverb
		var settings: Array = spaces.get(space, [])
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
	for bus_name: StringName in buses:
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
	for bus_name: StringName in buses:
		var bus: int = AudioServer.get_bus_index(bus_name)
		if bus < 0:
			continue
		var index: int = _effect_index(bus)
		if not AudioServer.is_bus_effect_enabled(bus, index):
			return false
	return true
