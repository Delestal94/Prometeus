extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_fragile.gd

const PACKAGE_SCENE: PackedScene = preload("res://scenes/gameplay/package/package.tscn")
var _failures: int = 0


func _initialize() -> void:
	# Keep test instances outside SceneTree so autoload startup is irrelevant.
	var first: RigidBody3D = PACKAGE_SCENE.instantiate()
	var second: RigidBody3D = PACKAGE_SCENE.instantiate()
	first.call("initialize_trap")
	second.call("initialize_trap")
	_expect(float(first.get("integrity")) == 100.0, "Starts with full integrity")
	first.call("apply_impact", 2.99)
	_expect(float(first.get("integrity")) == 100.0, "Subthreshold motion causes no damage")
	first.call("apply_impact", 3.0)
	_expect(float(first.get("integrity")) == 90.0, "Light threshold applies 10 damage")
	first.call("apply_impact", 7.0)
	_expect(float(first.get("integrity")) == 55.0, "Heavy threshold applies 35 damage")
	_expect(int(first.get("trap_state")) == 0, "Integrity above 40 is OK")
	first.call("apply_impact", 7.0)
	_expect(float(first.get("integrity")) == 20.0, "Damage is progressive")
	_expect(int(first.get("trap_state")) == 1, "Low integrity enters AT_RISK")
	_expect(float(second.get("integrity")) == 100.0, "Shared definition never shares mutable state")
	first.call("apply_impact", 7.0)
	_expect(float(first.get("integrity")) == 0.0, "Integrity clamps at zero")
	_expect(int(first.get("trap_state")) == 2, "Zero integrity is RUINED")
	first.call("apply_impact", 20.0)
	_expect(float(first.get("integrity")) == 0.0, "Ruined package cannot lose further integrity")
	first.call("initialize_trap")
	_expect(float(first.get("integrity")) == 100.0, "Reinitializing creates fresh behavior state")
	for index in range(6):
		first.call("apply_impact", 3.0)
	_expect(float(first.get("integrity")) == 40.0 and int(first.get("trap_state")) == 1, "AT_RISK boundary includes exactly 40")
	first.free()
	second.free()
	if _failures == 0:
		print("PASS: fragile package thresholds, states, reset and instance isolation")
	quit(_failures)


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1
