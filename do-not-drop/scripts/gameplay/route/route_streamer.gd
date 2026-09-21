extends Node3D
class_name RouteStreamer
## Base technical piece for Fase 3: instances RouteSegments ahead of a
## tracked node and frees them once they're well behind it, so the world
## never needs to exist all at once. Segments are chained end-to-end along
## -Z, the same convention route.gd already uses for progress.
##
## Combination rule (kept deliberately simple, per the plan): never repeat
## the same segment type twice in a row. Curated "modo normal" routes don't
## use this at all -- route.gd's handcrafted sequence stays as-is; this is
## the piece "modo endless" (Fase 3.5+) will build on.

@export var segment_scripts: Array[Script] = [
	StraightSegment, SpeedBumpSegment, ChicaneSegment, NarrowBridgeSegment,
	SCurveSegment, GravelSegment, ConstructionZoneSegment,
]
@export var lookahead_distance: float = 60.0
@export var behind_keep_distance: float = 40.0
## The very first segment ignores the random pick and is always this one
## (default: plain Straight) -- found the hard way while wiring this up to
## a real vehicle for the first time: a chicane or narrow bridge picked as
## segment #1 throws an obstacle at a driver who hasn't even had a second
## to get their bearings yet. Null disables this and goes fully random from
## the start, if a test genuinely needs that.
@export var first_segment_script: Script = StraightSegment

var target: Node3D = null

var _active: Array[RouteSegment] = []
var _next_z: float = 0.0
var _last_script: Script = null
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
## Tracks "has anything ever spawned", separately from _active.is_empty() --
## _active shrinks as segments get culled behind, so it stops meaning
## "nothing has spawned yet" well before the run is actually over.
var _spawned_any: bool = false


func _ready() -> void:
	_rng.randomize()


func start(tracked: Node3D) -> void:
	target = tracked
	_fill_ahead()


func _physics_process(_delta: float) -> void:
	if target == null:
		return
	_fill_ahead()
	_cull_behind()


func _fill_ahead() -> void:
	var horizon: float = target.global_position.z - lookahead_distance
	while _active.is_empty() or _next_z > horizon:
		_spawn_next()


func _spawn_next() -> void:
	var script: Script = first_segment_script if (first_segment_script != null and not _spawned_any) else _pick_next_script()
	_spawned_any = true
	var segment: RouteSegment = script.new()
	segment.position = Vector3(0.0, 0.0, _next_z)
	add_child(segment)
	_active.append(segment)
	_next_z -= segment.length
	_last_script = script


func _pick_next_script() -> Script:
	var candidates: Array[Script] = segment_scripts
	if segment_scripts.size() > 1 and _last_script != null:
		candidates = segment_scripts.filter(func(s: Script) -> bool: return s != _last_script)
	return candidates[_rng.randi() % candidates.size()]


func _cull_behind() -> void:
	for segment: RouteSegment in _active.duplicate():
		var exit_z: float = segment.position.z - segment.length
		if target.global_position.z < exit_z - behind_keep_distance:
			_active.erase(segment)
			segment.queue_free()
