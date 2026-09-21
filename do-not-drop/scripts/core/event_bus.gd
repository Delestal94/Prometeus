extends Node
## Facts shared by simulation and presentation. UI requests are separate from facts.
##
## In multiplayer these facts are decided on the host (the van and every
## package are host-authoritative). relay() is how a host-side fact reaches
## every client's own local EventBus, so their HUD and RunManager react the
## same way theirs would offline. Emit UI requests (start_requested and
## friends) with plain emit() as before -- those are per-peer, not facts.

signal cargo_registered(package_id: StringName, display_name: String)
signal package_state_changed(package_id: StringName, new_state: int)
signal package_integrity_changed(package_id: StringName, integrity: float, maximum: float)
signal package_ruined(package_id: StringName, cause: String)
signal package_damaged(package_id: StringName, damage: float)
signal vehicle_telemetry(speed_kmh: float)
signal vehicle_impact(strength: float, impact_position: Vector3)
signal run_started(route_id: StringName, players: Array)
signal run_ended(score: int, results: Dictionary)
signal route_progress_changed(progress: float, remaining_meters: float, section: String)
signal delivery_status_changed(in_zone: bool, stopped_seconds: float)
signal start_requested
signal restart_requested
signal pause_requested
signal interaction_prompt_changed(prompt: String)


## Emits locally and, if this is the host of an online session, rebroadcasts
## to every client so their own EventBus fires the same signal. Call this
## instead of emit_signal() for anything that originates from host-run
## simulation (package/vehicle facts, run state) so clients stay in sync.
func relay(event_name: StringName, args: Array = []) -> void:
	callv(&"emit_signal", [event_name] + args)
	if NetworkManager.is_online() and NetworkManager.is_host():
		_relay.rpc(event_name, args)


@rpc("authority", "call_remote", "reliable")
func _relay(event_name: StringName, args: Array) -> void:
	callv(&"emit_signal", [event_name] + args)
