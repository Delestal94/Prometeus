extends SegmentStreamer
class_name RouteStreamer
## Endless mode's road on the route_gen module's SegmentStreamer
## (docs/modulos.md): the module chains and culls segments; this file is
## the game's pool (the tramos with assets and sounds too), the session
## seed, the sky that follows the truck and the deer crossings.
##
## "Hard" (test_level_endless.gd/test_endless_multi_cargo.gd restrict
## themselves to Straight/SpeedBump for an un-steered drive): chicane,
## narrow bridge, S-curve, gravel, roadworks. docs/tareas-nacho.md #47: never
## three of these back to back.

## Endless mode's deer crossings: same odds for every peer (the streamer's
## RNG is seeded from the session seed), never in the first stretch, and
## spaced out so they stay a surprise.
const CROSSING_CHANCE: float = 0.12
const CROSSING_MIN_GAP: float = 300.0
const CROSSING_FIRST_AT: float = 120.0
var _last_crossing_distance: float = -INF


func _init() -> void:
	segment_scripts = [
		StraightSegment, SpeedBumpSegment, ChicaneSegment, NarrowBridgeSegment,
		SCurveSegment, GravelSegment, ConstructionZoneSegment, TunnelSegment,
		CurveSegment, CurveSegment,  # weighted up: this is the one that turns
	]
	hard_segments = [ChicaneSegment, NarrowBridgeSegment, SCurveSegment, GravelSegment, ConstructionZoneSegment]


func _ready() -> void:
	super()
	var sky := RouteSky.new()
	sky.name = "Sky"
	add_child(sky)


## Looked up by node path rather than by the NetworkManager identifier on
## purpose. A test that names this script's class_name compiles it before
## the autoloads exist, and a bare `NetworkManager.world_seed` is a compile
## error at that point -- the same node-path pattern the rest of the project
## already uses for EventBus.
func _session_seed() -> int:
	var network: Node = get_node_or_null(^"/root/NetworkManager")
	return int(network.get(&"world_seed")) if network != null else 0


func _on_segment_spawned(segment: RouteSegment) -> void:
	var roll: float = _rng.randf()
	var side: float = -1.0 if _rng.randf() < 0.5 else 1.0
	if not segment is StraightSegment or _next_distance < CROSSING_FIRST_AT:
		return
	if _next_distance - _last_crossing_distance < CROSSING_MIN_GAP or roll > CROSSING_CHANCE:
		return
	var crossing := WildlifeCrossing.new()
	crossing.name = "DeerCrossing"
	crossing.side = side
	crossing.with_sign = true
	crossing.position = Vector3(0.0, 0.0, -segment.length * 0.5)
	segment.add_child(crossing)
	_last_crossing_distance = _next_distance
