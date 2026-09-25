extends "res://scripts/gameplay/level_common.gd"
## Modo Endless (docs/plan-desarrollo.md Fase 3.5, docs/tareas-nacho.md
## #41-55): same on-foot loading / driver-seat / cargo-loading flow as
## level_base.gd, but RouteStreamer generates road indefinitely instead of
## a fixed curated route.tscn with a delivery zone. What the two share lives
## in level_common.gd (N-209); what's here is Endless's own: the streamer,
## the distance, and how a run ends (no delivery zone, no "arrived" state).
##
## Ending a run here always calls RunManager.finish_run(false, ...) (cargo
## lost, tipped over, or fell off) -- there's no "arrived" state to award
## the delivery-mode score formula. RunManager scores endless runs by
## distance instead (docs/tareas-nacho.md #52): start_run(MODE_ENDLESS)
## below switches it into that mode, and RunManager.current_distance is
## kept in sync with distance_traveled every physics frame so finish_run()
## has it however the run ends -- including the "all cargo ruined" path,
## which fires from inside RunManager itself, not from this file.

## How far off the road's centre line counts as having left it. Measured
## from the road itself (RouteStreamer.distance_from_path()), since Endless
## bends now (N-206) -- it used to be |x|, when the road was the Z axis.
const OUT_OF_BOUNDS_X: float = 42.0
## #97's automated bug bash found a real gap: driving unbraked into repeated
## SpeedBumpSegments at sustained top speed can launch the van hard enough
## that it lands wedged against route geometry -- upright (never trips the
## tip-over check) and inside bounds (never trips the out-of-bounds check),
## just permanently stopped with no way out and the run silently still
## "running" forever. 6s of being effectively stationary is long enough that
## no real player deliberately idles that long mid-drive (there's no reason
## to stop in endless mode at all -- unlike level_base.gd's delivery zone,
## there's no destination to sit still at).
const STUCK_SPEED_THRESHOLD: float = 0.3
const STUCK_SECONDS: float = 6.0
var _stuck_seconds: float = 0.0
@onready var _streamer: RouteStreamer = $World/RouteStreamer
var _streaming_started: bool = false
## Furthest along the road the truck has been (RouteStreamer.distance_along()).
var _best_distance: float = 0.0
## Public, meters -- how far the van has actually driven this run. Reset in
## _ready(), only advances while RunManager.is_running.
var distance_traveled: float = 0.0


## The same depot as level_base.gd: no houses here, so its board just says
## to load anything and go. The road is already out there when you look
## through the door.
func _prepare_mode() -> void:
	depot.post_orders(0)
	_streamer.start(vehicle)


func start_delivery() -> void:
	if RunManager.is_running or not RunManager.results.is_empty():
		return
	if not _driver_seated or not _has_loaded_cargo():
		return
	vehicle.freeze = false
	var loaded: Array[DeliveryPackage] = _release_loaded_cargo()
	RunManager.start_run(RunManager.MODE_ENDLESS)
	depot.begin_run(vehicle, loaded)
	_best_distance = 0.0
	distance_traveled = 0.0
	_stuck_seconds = 0.0
	_streamer.start(vehicle)
	_streaming_started = true


func _physics_process(delta: float) -> void:
	if not RunManager.is_running:
		return
	# Along the road, from the start line (the way out of the depot is free);
	# only new ground counts, so reversing and coming back adds nothing.
	_best_distance = maxf(_best_distance, _streamer.distance_along(vehicle.global_position))
	distance_traveled = _best_distance
	RunManager.current_distance = distance_traveled
	# Clients follow the run for the HUD; how it ends is the host's call.
	if not NetworkManager.is_host():
		return
	_check_lost_cargo()
	_update_tipped(delta)
	if vehicle.linear_velocity.length() < STUCK_SPEED_THRESHOLD:
		_stuck_seconds += delta
	else:
		_stuck_seconds = 0.0
	if tipped_seconds > 4.0:
		RunManager.finish_run(false, "La camioneta volcó. Tomá las curvas más despacio.")
	elif vehicle.global_position.y < -8.0 or _streamer.distance_from_path(vehicle.global_position) > OUT_OF_BOUNDS_X:
		RunManager.finish_run(false, "Te saliste de la ruta. Reiniciá para intentarlo de nuevo.")
	elif _stuck_seconds > STUCK_SECONDS:
		RunManager.finish_run(false, "La camioneta quedó atascada contra la ruta. Reiniciá para intentarlo de nuevo.")
