extends RouteSegment
class_name MudSegment
## A stretch of deep mud where the truck can bog down (N-108, M-05 of
## docs/analisis-competencia-backseat-rv.md). Rare, announced by its own board
## (and the road's hazard sign), and the only piece of road the crew has to
## get the truck out of together.
##
## The stretch: a shallow approach that already drags and loosens the wheels,
## then a pit. Cross the pit with speed and the truck ploughs through; slow
## down in it (below BOG_SPEED for BOG_DELAY) and it sinks: bogged. A bogged
## truck is held in place (heavy drag, host-side) and the crew has three ways
## out, all decided by the host and replicated:
##   - push: passengers on foot behind the rear doors hold the primary button
##     (or the interact key). Each pusher moves the rescue along PUSH_RATE per
##     second, the engine alone only ENGINE_RATE, so one pusher is slow and
##     two are quick. A pusher is on foot, so their boxes go untended: that is
##     the dilemma.
##   - tow strap: the depot supply "tow_strap" (CrewProgression.SUPPLIES); at
##     the front bumper it hauls the truck out at once.
##   - the crane: after crane_delay seconds bogged a cartoon tow truck arrives,
##     hauls it out and fines the team (never below zero). It never blocks the
##     road for good.
## Grip goes through GripZones like GravelSegment's (the lowest active zone
## wins, the original comes back when the last one is left: mud next to gravel
## never leaves the truck slippery). A truck freed from the mud does not sink
## again in the same stretch (one rescue, one fine, per segment). The run
## ending mid-rescue drops the whole thing with no fine; in Endless (which pays
## nothing) the crane costs only the time. A peer that joins mid-rescue asks
## the host for the state. No RNG at all: the same seed builds the same mud on
## every peer.
##
## vehicle.gd is untouched: everything is forces and meta on the body. While
## the truck is anywhere in the mud it carries the meta &"in_mud" (the levels'
## stuck-detection stands down: a bogged truck ends in the crane, not in
## "stuck"), and &"mud_bogged" while it is held.

enum State { IDLE, BOGGED, CRANE_COMING, HAULING }

const MUD_BASE := Color("5a3e26")
const MUD_SHADER: Shader = preload("res://shaders/mud_ground.gdshader")
const EARTH_DETAIL: String = "res://assets/textures/detail/tx_detail_earth_512.png"
## How far the mud reaches either side of the road's centre (its ragged edge
## wanders about a metre around this).
const MUD_HALF_WIDTH: float = 5.6
## The stake the strap is tied to.
const STRAP_POST := Color("2a1a11")
const SPOT_PUSH := preload("res://scripts/gameplay/route/mud_spot.gd")
const CRANE := preload("res://scripts/gameplay/route/mud_crane.gd")
const RUN_LOG := preload("res://scripts/gameplay/route/mud_run_log.gd")
## CrewProgression and RunManager stay by name, never preloaded: route.gd pulls
## this script in, and under --script a test compiles it before the autoloads
## exist; run_manager.gd and crew_progression.gd name EventBus and the others,
## fail to compile there and leave both autoloads as script-less Nodes.

## Where the pit is, metres from the entry (z = -this).
@export var pit_start: float = 18.0
@export var pit_end: float = 30.0
## Horizontal speed under which the truck sinks in the pit, and for how long.
@export var bog_speed: float = 5.0
@export var bog_delay: float = 0.3
## Seconds bogged before the crane comes (the "N s" of the task).
@export var crane_delay: float = 45.0
## A click only pushes with the mouse captured by the game (no menu open);
## off only for tests, where a headless run never captures it.
var require_captured_mouse: bool = true
## Team money the crane charges; never more than the team has.
@export var crane_fine: int = 40

@export var reduced_friction_slip: float = 1.2
## The approach drags the truck's flat velocity (a = -drag * v, drag in 1/s).
## The pit pulls it back with a constant deceleration (m/s^2) the engine only
## partly beats: what carries the truck through is the speed it comes in with,
## and below it the truck stalls. Both tuned in test_mud_segment (--measure).
## HELD_DRAG holds a bogged truck still.
@export var approach_drag: float = 0.3
@export var pit_decel: float = 12.0
const HELD_DRAG: float = 30.0

## Rescue progress per second: the engine alone, and each pusher. Full at 1.
const ENGINE_RATE: float = 1.0 / 90.0
const PUSH_RATE: float = 1.0 / 20.0
## A real shove the pushers give the body too (N per pusher, along the truck).
const PUSH_FORCE: float = 1500.0
## Within this of the spot behind the rear doors to start pushing, and this
## much to keep at it (so standing at the edge doesn't flicker the count).
const PUSH_REACH: float = 4.0
const PUSH_REACH_STAY: float = 4.6
## How far ahead of the spot (towards the cab) a pusher may be: behind the truck.
const PUSH_BEHIND_MARGIN: float = 1.5
## State changes from a flickering pusher count go out at most this often.
const MIN_BROADCAST_INTERVAL: float = 0.15
## A pusher keeps the button down: the client repeats this beat and the host
## lets go of anyone silent for BEAT_TIMEOUT.
const BEAT_INTERVAL: float = 0.1
const BEAT_TIMEOUT: float = 0.5
## Where the spots hang on the truck, in its own frame: behind the rear doors
## and on the front bumper.
const PUSH_SPOT_LOCAL := Vector3(0.0, 1.0, 5.7)
const STRAP_SPOT_LOCAL := Vector3(0.0, 0.7, -3.7)
## The truck's origin above the ground (vehicle.gd RIDE_HEIGHT).
const RIDE_HEIGHT: float = 0.67
const CRANE_ARRIVE_SECONDS: float = 3.0
const CRANE_GAP: float = 11.0
const CRANE_LEAVE_SECONDS: float = 3.0
## How fast each way out hauls the truck along the road, m/s, and for how long
## at most.
const HAUL_SPEEDS: Dictionary = {&"push": 3.0, &"engine": 3.0, &"strap": 5.0, &"crane": 4.0}
const HAUL_GAIN: float = 8.0
## The haul ends this far past the pit: clear of it.
const HAUL_PAST_PIT: float = 6.0
const HAUL_MAX_SECONDS: float = 10.0
const SYNC_INTERVAL: float = 0.5

## Every peer.
var state: int = State.IDLE
var progress: float = 0.0
var pushers: int = 0
var strap_ready: bool = false
var crane_left: float = 0.0
var haul_method: StringName = &""

var _grip_on: bool = false
var _push_spot: SPOT_PUSH
var _strap_spot: SPOT_PUSH
var _crane: CRANE
var _cable: MeshInstance3D
var _strap_anchor: Node3D
var _crane_time: float = 0.0
var _crane_leaving: float = -1.0
var _crane_last: Transform3D
## Host-only.
var _sink: float = 0.0
var _bogged_seconds: float = 0.0
var _haul_seconds: float = 0.0
var _crane_arrive: float = 0.0
var _beats: Dictionary = {}
var _clock: float = 0.0
var _sync_timer: float = 0.0
var _had_pushers: bool = false
var _active_pushers: Dictionary = {}
var _last_broadcast: float = -1.0
var _rescued: bool = false
## Every peer: the run is over (between run_ended and the next run_started).
var _run_over: bool = false
## Local.
var _beat_timer: float = 0.0


func _init() -> void:
	length = 60.0


func _ready() -> void:
	super()
	var bus: Node = _bus()
	if bus != null and bus.has_signal(&"run_ended"):
		bus.connect(&"run_ended", _on_run_ended)
		bus.connect(&"run_started", _on_run_started)
	if _is_online() and not _is_host():
		# Joining mid-rescue: pick it up where the host's is.
		if multiplayer.get_peers().has(1):
			_request_state.rpc_id(1)
		else:
			multiplayer.connected_to_server.connect(_ask_host_for_state, CONNECT_ONE_SHOT)


func _ask_host_for_state() -> void:
	_request_state.rpc_id(1)


## A client that just built this segment asks where the host's rescue is.
@rpc("any_peer", "call_remote", "reliable")
func _request_state() -> void:
	if not _is_host() or state == State.IDLE or not RpcGuard.allow_request(self):
		return
	_apply_state.rpc_id(multiplayer.get_remote_sender_id(), state, progress, pushers, strap_ready, crane_left,
			haul_method, _crane_arrive)


func _on_run_started(_route_id: StringName, _players: Array) -> void:
	_run_over = false


## The run ended (every peer): a rescue in progress is dropped, with no fine
## and nothing saved -- the results are already out.
func _on_run_ended(_score: int, _results: Dictionary) -> void:
	_run_over = true
	if _is_host():
		_abort()


func _abort() -> void:
	_beats.clear()
	_active_pushers.clear()
	pushers = 0
	var truck: Node = _truck()
	if truck != null:
		truck.set_meta(&"mud_bogged", false)
		truck.set_meta(&"keep_awake", false)
	if state != State.IDLE:
		_set_state(State.IDLE)


## Just under the load-bearing checks: the pit's own length.
func pit_length() -> float:
	return pit_end - pit_start


func _build() -> void:
	_box("Ground", Vector3(24.0, 1.0, length), Vector3(0.0, -0.8, -length * 0.5), SHOULDER, true)
	_box("Road", Vector3(12.0, 0.4, length), Vector3(0.0, -0.2, -length * 0.5), MUD_BASE, true)
	# The mud itself, one surface just over the road (the terrain's own surface
	# on a delivery route): mud_ground.gdshader draws the churned strip, the
	# wetter pit, the ruts and the standing water, with a ragged outline.
	var surface := MeshInstance3D.new()
	surface.name = "MudSurface"
	var plane := PlaneMesh.new()
	plane.size = Vector2(MUD_HALF_WIDTH * 2.0 + 3.0, length)
	plane.center_offset = Vector3(0.0, 0.0, -length * 0.5)
	# About a metre per quad, so it follows the ground (conform_geometry()).
	plane.subdivide_width = int(plane.size.x)
	plane.subdivide_depth = int(length)
	surface.mesh = plane
	surface.position.y = 0.05
	surface.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	surface.material_override = _mud_material(false)
	add_child(surface)
	# Lumps of churned mud thrown up at the edges.
	var lump_mesh := SphereMesh.new()
	lump_mesh.is_hemisphere = true
	lump_mesh.radius = 1.0
	lump_mesh.height = 1.0
	lump_mesh.radial_segments = 9
	lump_mesh.rings = 3
	for index: int in range(10):
		var side: float = -1.0 if index % 2 == 0 else 1.0
		var lump := MeshInstance3D.new()
		lump.name = "MudMound%d" % index
		lump.mesh = lump_mesh
		lump.material_override = _mud_material(true)
		lump.position = Vector3(side * (5.3 + float(index % 3) * 0.3), -0.04, -4.0 - float(index) * 5.5)
		lump.scale = Vector3(0.55 + float(index % 3) * 0.2, 0.16 + float(index % 2) * 0.06,
				0.45 + float(index % 2) * 0.2)
		lump.rotation.y = float(index) * 0.45
		add_child(lump)
	# The warning board on the driver's right, facing the traffic.
	RouteProps.sign(self, "MudSign", tr("WORLD_MUD_SIGN"), Vector3(7.8, 0.0, -3.0), 0.0, WARNING)
	_push_spot = _make_spot(&"push")
	_strap_spot = _make_spot(&"strap")
	# The spots start parked out of anyone's reach and ride the truck while it
	# is bogged (see _follow_spots()).


## The mud's materials, shared by every mud segment with the same layout:
## the surface (keyed by length and pit) and the lumps.
static var _mud_materials: Dictionary = {}


func _mud_material(lump: bool) -> ShaderMaterial:
	var key: Variant = &"lump" if lump else Vector3(length, pit_start, pit_end)
	if not _mud_materials.has(key):
		var material := ShaderMaterial.new()
		material.shader = MUD_SHADER
		material.set_shader_parameter(&"earth_detail", load(EARTH_DETAIL))
		material.set_shader_parameter(&"lump", 1.0 if lump else 0.0)
		material.set_shader_parameter(&"stretch_length", length)
		material.set_shader_parameter(&"pit_start", pit_start)
		material.set_shader_parameter(&"pit_end", pit_end)
		material.set_shader_parameter(&"mud_half_width", MUD_HALF_WIDTH)
		_mud_materials[key] = material
	return _mud_materials[key]


func _make_spot(kind: StringName) -> SPOT_PUSH:
	var spot: SPOT_PUSH = SPOT_PUSH.new()
	spot.name = "PushSpot" if kind == &"push" else "StrapSpot"
	spot.kind = kind
	spot.mud = self
	add_child(spot)
	spot.position = Vector3(0.0, -40.0, 0.0)
	return spot


# --- The spots (every peer) ---------------------------------------------------


func spot_prompt(kind: StringName) -> String:
	return "WORLD_MUD_PUSH_PROMPT" if kind == &"push" else "WORLD_MUD_STRAP_PROMPT"


func can_use_spot(kind: StringName, player: Node) -> bool:
	if state != State.BOGGED:
		return false
	if kind == &"push":
		return _may_push(player)
	if _hands_busy(player):
		return false
	return strap_ready


## Host: a passenger works a spot. Pushing here is one beat (the key pressed
## once); holding the button keeps sending them (_poll_local_push()).
func use_spot(kind: StringName, player: Node) -> void:
	if not _is_host() or not can_use_spot(kind, player):
		return
	if kind == &"strap":
		_use_strap()
	else:
		set_pusher(player.get_multiplayer_authority(), true)


# --- Pushing ---------------------------------------------------------------------


## Host: peer_id pushes right now (a beat). The host checks they really can
## every tick (_valid_pushers()).
func set_pusher(peer_id: int, active: bool) -> void:
	if active:
		_beats[peer_id] = _clock
	else:
		_beats.erase(peer_id)


@rpc("any_peer", "call_remote", "unreliable_ordered")
func _push_beat() -> void:
	if not _is_host() or not RpcGuard.sender_ok(self):
		return
	set_pusher(multiplayer.get_remote_sender_id(), true)


func _poll_local_push(delta: float) -> void:
	if state != State.BOGGED or _run_over:
		return
	# A menu or the chat has the mouse: the click there is not a shove.
	if require_captured_mouse and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	if not (Input.is_action_pressed(&"package_action_primary") or Input.is_action_pressed(&"interact")):
		return
	var player: Node = _local_player()
	if player == null or not _may_push(player):
		return
	_beat_timer -= delta
	if _beat_timer > 0.0:
		return
	_beat_timer = BEAT_INTERVAL
	if _is_host():
		set_pusher(player.get_multiplayer_authority(), true)
	else:
		_push_beat.rpc_id(1)


func _local_player() -> Node:
	for node: Node in get_tree().get_nodes_in_group(&"player"):
		if node.has_method(&"is_local") and bool(node.call(&"is_local")):
			return node
	return null


## On foot, hands free, behind the truck and off its bed: a passenger sitting
## in a seat tending a box can't push (that is the cost), nor can one who is
## down in a ragdoll.
func _may_push(player: Node, reach: float = PUSH_REACH) -> bool:
	var truck: Node3D = _truck()
	if truck == null or not player is Node3D:
		return false
	if _hands_busy(player) or player.get(&"_ragdolled") == true:
		return false
	var at: Vector3 = (player as Node3D).global_position
	if truck.to_local(at).z < PUSH_SPOT_LOCAL.z - PUSH_BEHIND_MARGIN:
		return false
	var spot: Vector3 = truck.global_transform * PUSH_SPOT_LOCAL
	if Vector2(at.x - spot.x, at.z - spot.z).length() > reach:
		return false
	return not (truck.has_method(&"carries") and bool(truck.call(&"carries", at)))


## Holding a box or sitting in a seat. By name, once for everyone: the tests put
## FakePlayer Node3Ds in the "player" group, which `as Player` would drop.
func _hands_busy(player: Node) -> bool:
	return player.get(&"carried_package") != null or not String(player.get(&"seat_node_path")).is_empty()


func _valid_pushers() -> int:
	var now: Dictionary = {}
	for peer_id: int in _beats.keys():
		if _clock - float(_beats[peer_id]) > BEAT_TIMEOUT:
			_beats.erase(peer_id)
			continue
		var player: Node = _player_of(peer_id)
		var reach: float = PUSH_REACH_STAY if _active_pushers.has(peer_id) else PUSH_REACH
		if player != null and _may_push(player, reach):
			now[peer_id] = true
	_active_pushers = now
	return now.size()


func _player_of(peer_id: int) -> Node:
	for node: Node in get_tree().get_nodes_in_group(&"player"):
		if node.get_multiplayer_authority() == peer_id:
			return node
	return null


# --- The truck (host) ------------------------------------------------------------


func _physics_process(delta: float) -> void:
	_clock += delta
	_follow_spots()
	_poll_local_push(delta)
	if not _is_host():
		_hold_predicted_truck(delta)
		return
	var truck := _truck() as VehicleBody3D
	if truck == null:
		return
	if _run_over and state != State.IDLE:
		_abort()
	var local: Vector3 = to_local(truck.global_position)
	var inside: bool = _inside(local)
	truck.set_meta(&"in_mud", inside)
	# Nobody at the wheel parks (freezes) a slow truck (vehicle.gd): not while
	# the crew or the crane are getting it out.
	if state != State.IDLE:
		truck.set_meta(&"keep_awake", true)
		if truck.freeze and not _run_over:
			truck.freeze = false
	_set_grip(truck, inside)
	if inside:
		var flat := Vector3(truck.linear_velocity.x, 0.0, truck.linear_velocity.z)
		var in_pit: bool = -local.z >= pit_start and -local.z <= pit_end
		_drag_truck(truck, flat, in_pit, delta)
		match state:
			State.IDLE:
				_tick_sinking(truck, flat, in_pit, delta)
			State.BOGGED:
				_tick_bogged(truck, delta)
			State.CRANE_COMING:
				_tick_crane_coming(delta)
			State.HAULING:
				_tick_hauling(truck, local, flat, delta)
	elif state == State.BOGGED or state == State.CRANE_COMING:
		# Shoved out of the mud by something else (a test, a teleport): done.
		_finish_haul(truck)
	elif state == State.HAULING:
		_finish_haul(truck)
	else:
		_sink = 0.0


## The mud's hold on the truck, from the state alone: the host's truck, and the
## copy the client at the wheel predicts (N-218).
func _drag_truck(truck: VehicleBody3D, flat: Vector3, in_pit: bool, delta: float) -> void:
	if state == State.BOGGED or state == State.CRANE_COMING:
		truck.apply_central_force(-flat * truck.mass * HELD_DRAG)
	elif state == State.IDLE and in_pit:
		# Never more than it takes to stop: the mud holds, it doesn't reverse.
		var pull: float = minf(pit_decel, flat.length() / delta)
		truck.apply_central_force(-flat.normalized() * truck.mass * pull)
	elif state == State.IDLE:
		truck.apply_central_force(-flat * truck.mass * approach_drag)


## A client predicting the truck it drives (N-218, vehicle_prediction.gd): its
## copy gets the same grip and drag from the replicated state, or it would
## drive on through the mud and be pulled back to the host's every tick. The
## host still decides everything (sinking, bogging, the haul, the pushes); those
## reach the copy as corrections.
func _hold_predicted_truck(delta: float) -> void:
	var truck := _truck() as VehicleBody3D
	if truck == null:
		return
	var predicted: bool = truck.has_method(&"is_predicted") and bool(truck.call(&"is_predicted"))
	var local: Vector3 = to_local(truck.global_position)
	var inside: bool = predicted and _inside(local)
	_set_grip(truck, inside)
	if inside:
		var flat := Vector3(truck.linear_velocity.x, 0.0, truck.linear_velocity.z)
		_drag_truck(truck, flat, -local.z >= pit_start and -local.z <= pit_end, delta)


func _inside(local: Vector3) -> bool:
	return absf(local.x) <= 7.0 and local.z <= 2.0 and local.z >= -length - 2.0


func _tick_sinking(truck: VehicleBody3D, flat: Vector3, in_pit: bool, delta: float) -> void:
	# Freed once is freed for this stretch; and nothing sinks after the run.
	if _rescued or _run_over:
		_sink = 0.0
		return
	if in_pit and flat.length() < bog_speed:
		_sink += delta
		if _sink >= bog_delay:
			_bog(truck)
	else:
		_sink = maxf(0.0, _sink - delta * 2.0)


func _bog(truck: VehicleBody3D) -> void:
	_sink = 0.0
	_bogged_seconds = 0.0
	progress = 0.0
	pushers = 0
	_had_pushers = false
	_beats.clear()
	_active_pushers.clear()
	strap_ready = int(truck.get_meta(&"tow_straps", 0)) > 0
	crane_left = crane_delay
	truck.set_meta(&"mud_bogged", true)
	_set_state(State.BOGGED)
	_notice(tr("WORLD_MUD_NOTICE_BOGGED"))


func _tick_bogged(truck: VehicleBody3D, delta: float) -> void:
	var count: int = _valid_pushers()
	var pedal: bool = absf(truck.engine_force) > 1.0
	progress = minf(1.0, progress + delta * (ENGINE_RATE * float(pedal) + PUSH_RATE * float(count)))
	if count > 0:
		_had_pushers = true
		var forward: Vector3 = -truck.global_basis.z
		forward.y = 0.0
		truck.apply_central_force(forward.normalized() * PUSH_FORCE * float(count))
	_bogged_seconds += delta
	crane_left = maxf(0.0, crane_delay - _bogged_seconds)
	_sync_timer -= delta
	if count != pushers:
		pushers = count
		# A count that flickers goes out at most every MIN_BROADCAST_INTERVAL;
		# what is skipped rides the next periodic sync.
		if _clock - _last_broadcast >= MIN_BROADCAST_INTERVAL:
			_sync_timer = 0.0
	if progress >= 1.0:
		_begin_haul(&"push" if _had_pushers else &"engine")
	elif crane_left <= 0.0:
		_crane_arrive = 0.0
		_set_state(State.CRANE_COMING)
	elif _sync_timer <= 0.0:
		_sync_timer = SYNC_INTERVAL
		_broadcast()


func _tick_crane_coming(delta: float) -> void:
	_crane_arrive += delta
	if _crane_arrive >= CRANE_ARRIVE_SECONDS:
		_begin_haul(&"crane")


func _use_strap() -> void:
	var truck: Node3D = _truck()
	if truck == null or not strap_ready:
		return
	truck.set_meta(&"tow_straps", maxi(0, int(truck.get_meta(&"tow_straps", 0)) - 1))
	strap_ready = false
	_begin_haul(&"strap")


## Host: the truck is on its way out, by `method` (&"push", &"engine", &"strap"
## or &"crane"). The crane charges its fine here; each way leaves its line for
## the results (MudRunLog).
func _begin_haul(method: StringName) -> void:
	haul_method = method
	_haul_seconds = 0.0
	progress = 1.0
	var fine: int = 0
	match method:
		&"crane":
			if _is_endless():
				# Endless pays nothing: the crane costs only the time.
				_notice(tr("WORLD_MUD_NOTICE_CRANE_FREE"))
				_story(tr("WORLD_MUD_STORY_CRANE_FREE"))
			else:
				fine = _charge_fine()
				_notice(tr("WORLD_MUD_NOTICE_CRANE") % fine)
				_story(tr("WORLD_MUD_STORY_CRANE") % fine)
		&"strap":
			_notice(tr("WORLD_MUD_NOTICE_STRAP"))
			_story(tr("WORLD_MUD_STORY_STRAP"))
		&"push":
			_notice(tr("WORLD_MUD_NOTICE_PUSH"))
			_story(tr("WORLD_MUD_STORY_PUSH"))
		_:
			_notice(tr("WORLD_MUD_NOTICE_ENGINE"))
			_story(tr("WORLD_MUD_STORY_ENGINE"))
	_set_state(State.HAULING)


## The crane's fine: CRANE_FINE, or whatever the team has if that is less --
## the balance never goes negative. Saved with the campaign like any spend.
func _charge_fine() -> int:
	var crew: Node = _crew()
	if crew == null:
		return 0
	var fine: int = mini(crane_fine, int(crew.get(&"team_money")))
	if fine > 0 and bool(crew.call(&"spend", fine)):
		crew.call(&"save_campaign")
		return fine
	return 0


func _tick_hauling(truck: VehicleBody3D, local: Vector3, flat: Vector3, delta: float) -> void:
	_haul_seconds += delta
	var along: Vector3 = -global_basis.z
	along.y = 0.0
	along = along.normalized()
	var wanted: Vector3 = along * float(HAUL_SPEEDS.get(haul_method, 3.0))
	truck.apply_central_force((wanted - flat) * truck.mass * HAUL_GAIN)
	if -local.z >= pit_end + HAUL_PAST_PIT or _haul_seconds >= HAUL_MAX_SECONDS:
		_finish_haul(truck)


func _finish_haul(truck: Node3D) -> void:
	truck.set_meta(&"mud_bogged", false)
	truck.set_meta(&"keep_awake", false)
	_sink = 0.0
	_beats.clear()
	_active_pushers.clear()
	pushers = 0
	_rescued = true
	_set_state(State.IDLE)


# --- Grip and cleanup ----------------------------------------------------------


func _set_grip(truck: Node3D, inside: bool) -> void:
	if inside and not _grip_on:
		GripZones.enter(truck, self, reduced_friction_slip)
		_grip_on = true
	elif not inside and _grip_on:
		GripZones.leave(truck, self)
		_grip_on = false


func _exit_tree() -> void:
	# Endless culling this segment with the truck still tracked (reversing far
	# back) must not leave the grip lowered or the truck marked as bogged.
	var truck: Node = get_tree().get_first_node_in_group(&"vehicle") if get_tree() != null else null
	if truck != null:
		if _grip_on:
			GripZones.leave(truck, self)
			_grip_on = false
		truck.set_meta(&"in_mud", false)
		truck.set_meta(&"mud_bogged", false)
		truck.set_meta(&"keep_awake", false)


# --- State and replication ---------------------------------------------------------


func _set_state(value: int) -> void:
	var previous: int = state
	state = value
	_sync_timer = SYNC_INTERVAL
	_broadcast()
	if previous != state:
		_on_state_changed(previous)


func _broadcast() -> void:
	_last_broadcast = _clock
	_apply_state(state, progress, pushers, strap_ready, crane_left, haul_method, _crane_arrive)
	if _is_online():
		_apply_state.rpc(state, progress, pushers, strap_ready, crane_left, haul_method, _crane_arrive)


@rpc("authority", "call_remote", "reliable")
func _apply_state(new_state: int, new_progress: float, new_pushers: int, new_strap: bool, new_crane_left: float,
		new_method: StringName, new_crane_arrive: float) -> void:
	var previous: int = state
	if new_state == State.CRANE_COMING and state != State.CRANE_COMING:
		# Joining mid-arrival: the crane is where the host's is by now.
		_crane_time = new_crane_arrive
	state = new_state
	progress = new_progress
	pushers = new_pushers
	strap_ready = new_strap
	crane_left = new_crane_left
	haul_method = new_method
	if previous != state:
		_on_state_changed(previous)
	_show_status()


func _on_state_changed(previous: int) -> void:
	if state == State.CRANE_COMING:
		_ensure_crane()
	elif state == State.HAULING:
		# A peer that joined mid-haul never saw the crane arrive: it is parked
		# already, so the cable has somewhere to start from.
		_ensure_crane()
		_start_cable()
	elif state == State.IDLE and previous != State.IDLE:
		_stop_cable()
		if _crane != null:
			_crane_leaving = 0.0


func _show_status() -> void:
	if _push_spot == null:
		return
	var text: String = ""
	if state == State.BOGGED:
		text = tr("WORLD_MUD_STATUS") % [roundi(progress * 100.0), ceili(crane_left)]
	elif state == State.CRANE_COMING:
		text = tr("WORLD_MUD_STATUS_CRANE")
	_push_spot.show_status(text)


# --- Visuals (every peer) ------------------------------------------------------------


func _process(delta: float) -> void:
	_ensure_crane()
	_move_crane(delta)
	_place_cable()


func _follow_spots() -> void:
	var truck: Node3D = _truck()
	var active: bool = state == State.BOGGED and truck != null
	if active:
		_push_spot.global_position = truck.global_transform * PUSH_SPOT_LOCAL
		_strap_spot.global_position = truck.global_transform * STRAP_SPOT_LOCAL if strap_ready else _parked()
	else:
		_push_spot.global_position = _parked()
		_strap_spot.global_position = _parked()


func _parked() -> Vector3:
	return to_global(Vector3(0.0, -40.0, -length * 0.5))


func _road_forward() -> Vector3:
	var along: Vector3 = -global_basis.z
	along.y = 0.0
	return along.normalized()


## The crane the state calls for, if there should be one and is not yet (the
## truck may not exist yet on a peer that just joined: tried again each frame).
func _ensure_crane() -> void:
	if _crane != null or _crane_leaving >= 0.0:
		return
	if state == State.CRANE_COMING:
		_summon_crane(clampf(_crane_time / CRANE_ARRIVE_SECONDS, 0.0, 1.0))
	elif state == State.HAULING and haul_method == &"crane":
		_summon_crane(1.0)


## `arrived` is how far along its arrival it stands (0 = far off, 1 = parked).
func _summon_crane(arrived: float = 0.0) -> void:
	var truck: Node3D = _truck()
	if truck == null or _crane != null:
		return
	_crane = CRANE.new()
	add_child(_crane)
	_crane.top_level = true
	_crane_time = arrived * CRANE_ARRIVE_SECONDS
	_crane_leaving = -1.0
	_crane.global_transform = _crane_pose(truck, arrived)
	_crane_last = _crane.global_transform


## Where the crane stands `u` (0 = far off to the side, 1 = parked ahead of the
## truck, its tail toward it).
func _crane_pose(truck: Node3D, u: float) -> Transform3D:
	var forward: Vector3 = _road_forward()
	var side: Vector3 = forward.cross(Vector3.UP).normalized()
	var ground: Vector3 = truck.global_position + Vector3.DOWN * RIDE_HEIGHT
	var park: Vector3 = ground + forward * CRANE_GAP
	var start: Vector3 = park + forward * 34.0 + side * 16.0
	var eased: float = smoothstep(0.0, 1.0, u)
	var at: Vector3 = start.lerp(park, eased)
	# Drives in nose first, then swings round so the hook faces the truck.
	var heading: Vector3 = (park - start).normalized()
	var facing_yaw: float = atan2(-heading.x, -heading.z)
	var turn: float = PI * smoothstep(0.65, 1.0, u)
	return Transform3D(Basis(Vector3.UP, facing_yaw + turn), at)


func _move_crane(delta: float) -> void:
	if _crane == null:
		return
	var truck: Node3D = _truck()
	if _crane_leaving >= 0.0:
		_crane_leaving += delta
		var away: Vector3 = _road_forward() + _road_forward().cross(Vector3.UP).normalized() * 0.6
		_crane.global_position += away.normalized() * 7.0 * delta
		if _crane_leaving >= CRANE_LEAVE_SECONDS:
			_crane.queue_free()
			_crane = null
			_crane_leaving = -1.0
		return
	if truck == null:
		return
	if state == State.CRANE_COMING:
		_crane_time += delta
		_crane.global_transform = _crane_pose(truck, clampf(_crane_time / CRANE_ARRIVE_SECONDS, 0.0, 1.0))
	elif state == State.HAULING:
		# Parked ahead and reeling the truck in: it rides the cable's length.
		_crane.global_transform = _crane_pose(truck, 1.0)
	_crane_last = _crane.global_transform


func _start_cable() -> void:
	if _cable != null:
		return
	_cable = MeshInstance3D.new()
	_cable.name = "HaulCable"
	var box := BoxMesh.new()
	box.size = Vector3(0.07, 0.07, 1.0)
	_cable.mesh = box
	_cable.material_override = _material(Color("2b2f33"))
	_cable.top_level = true
	# Hidden until it has both ends: a box at the origin is not a cable.
	_cable.visible = false
	add_child(_cable)
	if haul_method == &"strap":
		_strap_anchor = Node3D.new()
		_strap_anchor.name = "StrapAnchor"
		_strap_anchor.top_level = true
		add_child(_strap_anchor)
		var post := MeshInstance3D.new()
		var post_mesh := BoxMesh.new()
		post_mesh.size = Vector3(0.4, 1.6, 0.4)
		post.mesh = post_mesh
		post.material_override = _material(STRAP_POST)
		post.position.y = 0.8
		_strap_anchor.add_child(post)
		var truck: Node3D = _truck()
		if truck != null:
			_strap_anchor.global_position = truck.global_position + Vector3.DOWN * RIDE_HEIGHT \
					+ _road_forward() * 14.0 + _road_forward().cross(Vector3.UP).normalized() * 1.5


func _stop_cable() -> void:
	if _cable != null:
		_cable.queue_free()
		_cable = null
	if _strap_anchor != null:
		_strap_anchor.queue_free()
		_strap_anchor = null


func _place_cable() -> void:
	if _cable == null:
		return
	var truck: Node3D = _truck()
	if truck == null:
		return
	var from: Vector3
	if haul_method == &"crane" and _crane != null:
		from = _crane.hook_position()
	elif _strap_anchor != null:
		from = _strap_anchor.global_position + Vector3.UP * 1.3
	else:
		return
	var to: Vector3 = truck.global_transform * STRAP_SPOT_LOCAL
	var offset: Vector3 = to - from
	var span: float = offset.length()
	if span < 0.05:
		return
	var up: Vector3 = Vector3.UP if absf(offset.normalized().dot(Vector3.UP)) < 0.98 else Vector3.RIGHT
	var basis := Basis.looking_at(offset / span, up).scaled(Vector3(1.0, 1.0, span))
	_cable.global_transform = Transform3D(basis, from + offset * 0.5)
	_cable.visible = true


# --- Small helpers -----------------------------------------------------------------------


func _truck() -> Node3D:
	if not is_inside_tree():
		return null
	return get_tree().get_first_node_in_group(&"vehicle") as Node3D


func _notice(text: String) -> void:
	var bus: Node = _bus()
	if bus != null:
		bus.call(&"relay", &"depot_notice", [text])


func _story(line: String) -> void:
	var owner_node: Node = get_parent()
	if owner_node == null:
		return
	var log_node: RUN_LOG = owner_node.get_node_or_null(^"MudRunLog") as RUN_LOG
	if log_node == null:
		log_node = RUN_LOG.new()
		log_node.name = "MudRunLog"
		owner_node.add_child(log_node)
	log_node.add_story(line)


func _is_endless() -> bool:
	var manager: Node = _run_manager()
	return manager != null and manager.get(&"current_mode") == &"endless"


func _is_online() -> bool:
	var network: NetSession = _network()
	return network != null and network.is_online()


func _is_host() -> bool:
	var network: NetSession = _network()
	return network == null or network.is_host()


## EventBus by name, not typed: tests replace it with a plain Node.
func _bus() -> Node:
	return get_node_or_null(^"/root/EventBus")


func _network() -> NetSession:
	return get_node_or_null(^"/root/NetworkManager") as NetSession


func _crew() -> Node:
	return get_node_or_null(^"/root/CrewProgression")


func _run_manager() -> Node:
	return get_node_or_null(^"/root/RunManager")
