extends SceneTree

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var package := (load("res://scenes/gameplay/package/package.tscn") as PackedScene).instantiate() as DeliveryPackage
	package.trap_definition = load("res://data/traps/hostile.tres")
	root.add_child(package)
	await process_frame
	await process_frame
	var feedback := package.get_node("PackageFeedbackComponent")
	assert(feedback.get_node_or_null("../Box/HostileEyes") != null, "Hostil debe mostrar ojos/tentáculos")
	assert(feedback.get("_hostile_hiss_player") != null, "Hostil debe tener siseo propio")
	package.free()
	print("PASS: hostile package has creature visual and hiss audio presentation.")
	quit(0)
