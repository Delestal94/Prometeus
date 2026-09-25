extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_level_common.gd
##
## N-209: the delivery level and Endless share one base (level_common.gd) for
## what they do alike -- spawning players, starting on a seated driver with
## cargo, pause, restart, lost cargo, the kept view -- and keep only their
## own in their files. A shared function copied back into one of them would
## drift from the other again (the reason for the refactor), so this checks
## neither redefines the shared ones, and that both still start a run.

const SHARED: Array[String] = ["_sync_players", "_on_roster_changed", "_keep_view", "_on_profile_changed",
	"_refresh_local_player", "start_debug_delivery", "_on_driver_seated", "_on_package_loaded", "_maybe_start",
	"_has_loaded_cargo", "_release_loaded_cargo", "restart_delivery", "toggle_pause", "_check_lost_cargo",
	"_on_run_ended", "_update_tipped", "_player_name", "_id_from_name"]

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var common: Script = load("res://scripts/gameplay/level_common.gd")
	for scene_path: String in ["res://scenes/gameplay/level_base.tscn", "res://scenes/gameplay/level_endless.tscn"]:
		var level: Node = load(scene_path).instantiate()
		var script: Script = level.get_script()
		_expect(script.get_base_script() == common, "%s builds on level_common.gd" % scene_path.get_file())
		var source: String = script.source_code
		for name: String in SHARED:
			_expect(not source.contains("func %s(" % name), "%s doesn't redefine the shared %s()" % [scene_path.get_file(), name])
		root.add_child(level)
		current_scene = level
		await process_frame
		await physics_frame
		level.call(&"start_debug_delivery")
		await physics_frame
		var manager: Node = root.get_node(^"/root/RunManager")
		_expect(bool(manager.get(&"is_running")), "%s still starts a run" % scene_path.get_file())
		level.queue_free()
		await process_frame
		manager.call(&"reset_run")
	if _failures == 0:
		print("PASS: both levels share level_common.gd and still start their runs")
	quit(_failures)


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1
