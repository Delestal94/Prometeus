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
## Endless mud (N-108): none in the first metres, and spaced out.
const MUD_FIRST_AT: float = 300.0
const MUD_MIN_GAP: float = 600.0
var _last_mud_distance: float = -INF
## Service stations (N-110, ServiceStopRules): when the next one is due and
## how many have been laid. Their spacing comes from the seed and their number,
## not from _rng, so a station only takes the place of the segment it replaces.
const SERVICE_STOP = preload("res://scripts/gameplay/route/service_stop_rules.gd")
var _service_seed: int = 0
var _service_count: int = 0
var _service_next_at: float = INF
## Every model the Endless pool's segments instance (N-219): read on a
## background thread from the start of the level, so the first bridge, tunnel
## or roadworks does not load them in the physics tick that builds it. A new
## segment with a model adds it here (test_route_streaming checks they exist).
const WARM_MODELS: Array[String] = [
	"res://assets/models/environment/route/sm_env_route_chicane_barrier.glb",
	"res://assets/models/environment/route/sm_env_route_bridge_deck.glb",
	"res://assets/models/environment/route/sm_env_route_bridge_post.glb",
	"res://assets/models/environment/route/sm_env_route_bridge_water.glb",
	"res://assets/models/environment/route/sm_env_route_tunnel_module.glb",
	"res://assets/models/environment/route/sm_env_route_tunnel_portal.glb",
	"res://assets/models/environment/route/sm_env_route_tunnel_lamp.glb",
	"res://assets/models/environment/route/sm_env_route_tunnel_hill_props.glb",
	"res://assets/models/environment/props/sm_env_prop_bridge_railing.glb",
	"res://assets/models/environment/props/sm_env_prop_traffic_cone.glb",
	"res://assets/models/environment/props/sm_env_prop_road_barrier.glb",
]


func _init() -> void:
	segment_scripts = [
		StraightSegment, SpeedBumpSegment, ChicaneSegment, NarrowBridgeSegment,
		SCurveSegment, GravelSegment, ConstructionZoneSegment, TunnelSegment,
		CurveSegment, CurveSegment,  # weighted up: this is the one that turns
		MudSegment,  # rare (RoutePlanner.MUD_WEIGHT): the crew gets the truck out together
	]
	hard_segments = [ChicaneSegment, NarrowBridgeSegment, SCurveSegment, GravelSegment, ConstructionZoneSegment,
			MudSegment]


func _ready() -> void:
	super()
	_service_seed = _session_seed() if _session_seed() != 0 else int(_rng.seed)
	_service_next_at = SERVICE_STOP.endless_next_at(_service_seed, 0, 0.0)
	RouteSegment.warm_models(WARM_MODELS)
	# The service station's borrowed depot props (N-110), loaded by path as its segment does.
	(load("res://scripts/gameplay/route/service_stop.gd") as Script).call(&"warm_models")
	# The bridge's river loop is synthesized the first time it is asked for
	# (~55 ms): cached here, while the level loads, not under the first bridge.
	SynthAudio.river_flow_loop()
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


## Mud (N-108) is rare, comes after the first stretch and never twice within
## MUD_MIN_GAP metres; if that leaves nothing, the rule gives way.
func _limit_candidates(candidates: Array[Script]) -> Array[Script]:
	if _next_distance >= MUD_FIRST_AT and _next_distance - _last_mud_distance >= MUD_MIN_GAP:
		return candidates
	var without_mud: Array[Script] = candidates.filter(func(s: Script) -> bool: return s != MudSegment)
	return without_mud if not without_mud.is_empty() else candidates


func _pick_weight(script: Script, hard_weight: float) -> float:
	if script == MudSegment:
		return RoutePlanner.MUD_WEIGHT
	return super(script, hard_weight)


## The draw as always; once a station is due (and the road just behind is one
## the crew can pull off from) it takes that draw's place.
func _pick_next_script() -> Script:
	var picked: Script = super()
	if _next_distance >= _service_next_at \
			and SERVICE_STOP.endless_can_start(_hard_streak, hard_segments.has(_last_script)):
		# Counted as it is picked (the next spawn is this pick): the next one is
		# then a full gap away, however often the pick is asked again.
		_service_count += 1
		_service_next_at = SERVICE_STOP.endless_next_at(_service_seed, _service_count, _next_distance)
		return SERVICE_STOP.SEGMENT
	return picked


## Whether `world_point` is on a live station's lay-by (a truck pulled in to
## shop): the level doesn't count a crew that parked there as stuck.
func in_service_bay(world_point: Vector3) -> bool:
	for segment: RouteSegment in _active:
		if is_instance_valid(segment) and segment.get_script() == SERVICE_STOP.SEGMENT:
			var stop: Node3D = segment.get(&"stop")
			if stop != null and bool(stop.call(&"in_bay", world_point)):
				return true
	return false


func _on_segment_spawned(segment: RouteSegment) -> void:
	if segment is MudSegment:
		_last_mud_distance = _next_distance
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
