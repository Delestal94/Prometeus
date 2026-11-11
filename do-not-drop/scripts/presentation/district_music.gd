class_name DistrictMusic
extends Node
## Music by district (expansion D-1929, with D-0343): out of the shed, the zone the local player stands in plays its
## own theme (SynthAudio.theme_music(): nine themes composed in code, THEME_OF picks one per zone), crossfading over
## FADE_SECONDS when the player crosses into another zone; inside the shed, or out of every zone, none plays and
## the shed's own loop (ShedMusic) comes back. Two players on the Music bus take turns for the crossfade. Local to
## each peer: it follows this peer's player only. It looks every CHECK_SECONDS.

const THEME_OF: Dictionary = {
	&"parque_industrial": 0, &"centro": 1, &"suburbio": 2, &"campo": 3, &"puerto": 4, &"islas": 5,
	&"montana": 6, &"nieve": 7, &"volcan": 8,
}
const VOLUME_DB: float = -6.0
const SILENT_DB: float = -60.0
const FADE_SECONDS: float = 2.5
const CHECK_SECONDS: float = 0.5

## () -> Node3D: the local player; () -> Array: ZoneDefinitions; (Vector3) -> bool: the point is in the shed;
## () -> Node: the shed's music (ShedMusic) or null.
var player_of: Callable = func() -> Node3D: return null
var zones_of: Callable = func() -> Array: return []
var in_shed: Callable = func(_at: Vector3) -> bool: return false
var shed_music_of: Callable = func() -> Node: return null

## The theme playing (or fading in), -1 for none.
var theme: int = -1
var _players: Array[AudioStreamPlayer] = []
var _current: int = 0
var _wait: float = 0.0


## The district music under `root` (CompanyRoot: player, zones, shed, its ShedMusic child).
static func add_to(root: Node) -> DistrictMusic:
	var music := DistrictMusic.new()
	music.name = "DistrictMusic"
	music.player_of = func() -> Node3D: return root.get(&"player") as Node3D if is_instance_valid(root) else null
	music.zones_of = func() -> Array: return root.get(&"zones") if is_instance_valid(root) else []
	music.in_shed = func(at: Vector3) -> bool:
		var shed: Node = root.get(&"shed") if is_instance_valid(root) else null
		return shed != null and bool(shed.call(&"holds", at))
	music.shed_music_of = func() -> Node:
		return root.get_node_or_null(^"ShedMusic") if is_instance_valid(root) else null
	root.add_child(music)
	return music


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for i: int in 2:
		var player := AudioStreamPlayer.new()
		player.name = "Theme%d" % i
		player.bus = &"Music" if AudioServer.get_bus_index(&"Music") >= 0 else &"Master"
		player.volume_db = SILENT_DB
		add_child(player)
		_players.append(player)


func _process(delta: float) -> void:
	_wait -= delta
	if _wait <= 0.0:
		_wait = CHECK_SECONDS
		check()
	fade(delta)


## The theme for where the player is now (-1 in the shed or out of every zone), switched to when it changed.
func check() -> void:
	var wanted: int = theme_at(player_of.call())
	if wanted != theme:
		_switch(wanted)
	var shed_music: Node = shed_music_of.call()
	if shed_music != null and &"away" in shed_music:
		shed_music.set(&"away", theme >= 0)


## The theme of the zone `player` stands in, -1 in the shed, out of every zone or without a player.
func theme_at(player: Node3D) -> int:
	if player == null or not player.is_inside_tree():
		return -1
	var at: Vector3 = player.global_position
	if bool(in_shed.call(at)):
		return -1
	for raw: Variant in zones_of.call():
		var zone := raw as ZoneDefinition
		if zone != null and zone.bounds.has_point(Vector2(at.x, at.z)) and THEME_OF.has(zone.id):
			return int(THEME_OF[zone.id])
	return -1


## Moves the volumes `seconds` along the crossfade: the current player up to VOLUME_DB (silent with no theme), the
## other down to silence. Public so a test can run it without frames.
func fade(seconds: float) -> void:
	var step: float = seconds / FADE_SECONDS
	for i: int in _players.size():
		var player: AudioStreamPlayer = _players[i]
		var target: float = 1.0 if i == _current and theme >= 0 else 0.0
		var level: float = move_toward(_linear(player.volume_db), target, step)
		player.volume_db = linear_to_db(maxf(level * db_to_linear(VOLUME_DB), db_to_linear(SILENT_DB)))
		if level <= 0.0 and player.playing:
			player.stop()


func players() -> Array[AudioStreamPlayer]:
	return _players


func _switch(wanted: int) -> void:
	theme = wanted
	if wanted < 0:
		return
	_current = 1 - _current
	var player: AudioStreamPlayer = _players[_current]
	player.stream = SynthAudio.theme_music(wanted)
	player.volume_db = SILENT_DB
	player.play()


## A player's volume as a share (0 to 1) of VOLUME_DB.
static func _linear(volume_db: float) -> float:
	if volume_db <= SILENT_DB + 0.01:
		return 0.0
	return clampf(db_to_linear(volume_db) / db_to_linear(VOLUME_DB), 0.0, 1.0)
