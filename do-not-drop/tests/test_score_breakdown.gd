extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_score_breakdown.gd
## The results screen's itemised score (docs/tareas-slatex.md #89): every
## line comes from RunManager's own sums, so together (times the chaos
## multiplier) they always make exactly the score shown -- including the
## penalties for a door nobody reached.

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var manager: Node = root.get_node(^"/root/RunManager")
	manager.call(&"reset_run")
	manager.set(&"expected_houses", 4)
	manager.call(&"start_run")
	manager.set(&"cargo", {
		&"a": {"integrity": 100.0, "maximum": 100.0, "state": 0},
		&"b": {"integrity": 60.0, "maximum": 100.0, "state": 1},
	})
	manager.call(&"register_delivery", 0, &"delivered_ok", &"")
	manager.call(&"attach_delivery_photo", 0)
	manager.call(&"register_delivery", 1, &"delivered_ruined", &"")
	manager.call(&"register_delivery", 2, &"missed", &"")
	manager.call(&"finish_run", true)
	var results: Dictionary = manager.get(&"results")
	var lines: Array = results.get("breakdown", [])
	var sum: int = 0
	var labels: PackedStringArray = []
	for line: Dictionary in lines:
		sum += int(line["points"])
		labels.append(String(line["label"]))
	var expected: int = maxi(roundi(sum * float(results["chaos_multiplier"])), 0)
	_expect(expected == int(results["score"]), "The lines add up to the score (%d x %.1f vs %d)" % [sum, float(results["chaos_multiplier"]), int(results["score"])])
	_expect("Vecinos sin su paquete (2)" in labels, "Both the skipped door and the one never reached cost points (%s)" % ", ".join(labels))
	_expect("Fotos de entrega (1)" in labels, "The photo shows as its own line")
	var text: String = load("res://scripts/ui/prototype_hud.gd").score_breakdown_text(results, int(results["score"]))
	_expect(text.contains("Total") and text.contains(str(int(results["score"]))), "The results text ends on the total")
	manager.call(&"reset_run")
	if _failures == 0:
		print("PASS: the itemised results always add up to the score")
	quit(_failures)


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1
