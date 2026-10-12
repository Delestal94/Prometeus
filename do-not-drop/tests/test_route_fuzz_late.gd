extends "res://tests/test_route_fuzz.gd"
## Run: Godot --headless --path do-not-drop --script res://tests/test_route_fuzz_late.gd
## The second half of test_route_fuzz.gd's built routes (seeds FIRST_HALF + 1 .. BUILT_SEEDS):
## the same checks on the same code, in its own process so CI deals the two halves to different
## shards and neither gets near the 240 s limit (#398). Pass 1 (the planned roads) stays in the
## first script.


func _built_seeds() -> Vector2i:
	return Vector2i(FIRST_HALF + 1, BUILT_SEEDS)


func _runs_plans() -> bool:
	return false
