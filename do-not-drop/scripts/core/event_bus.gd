extends Node
## Facts shared by simulation and presentation. UI requests are separate from facts.

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
