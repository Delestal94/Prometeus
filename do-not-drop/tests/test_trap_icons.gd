extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_trap_icons.gd
## Covers S-301: every trap definition resolves to its own dedicated HUD icon.

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	await process_frame
	var paths: PackedStringArray = []
	var files: PackedStringArray = DirAccess.get_files_at("res://data/traps")
	files.sort()
	for file: String in files:
		if not file.ends_with(".tres"):
			continue
		var definition: Resource = load("res://data/traps/%s" % file)
		var trap_id: String = String(definition.get(&"id"))
		var icon: Texture2D = UiTheme.trap_icon(String(definition.get(&"display_name")))
		var expected_path := "res://assets/ui/icons/tx_ui_trap_%s_256.png" % trap_id
		_expect(icon != null, "%s has a HUD icon" % trap_id)
		if icon != null:
			_expect(icon.resource_path == expected_path, "%s uses its own icon (%s)" % [trap_id, icon.resource_path])
			_expect(not paths.has(icon.resource_path), "%s does not reuse another trap icon" % trap_id)
			paths.append(icon.resource_path)

	_expect(paths.size() == 7, "all seven trap definitions have distinct icons")
	if _failures == 0:
		print("PASS: all seven traps use their own HUD icon")
	quit(_failures)


func _expect(condition: bool, description: String) -> void:
	if not condition:
		_failures += 1
		push_error(description)
