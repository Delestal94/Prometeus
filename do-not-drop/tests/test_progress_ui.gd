extends SceneTree

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var menu := (load("res://scenes/ui/main_menu.tscn") as PackedScene).instantiate()
	root.add_child(menu)
	await process_frame
	assert(menu.get_node_or_null("ProgressPanel") != null, "El menú debe incluir Progreso")
	assert(menu.get_node_or_null("TutorialPanel") != null, "El menú debe incluir Cómo jugar")
	menu.call("_open_progress")
	assert(menu.get_node("ProgressPanel").visible, "Progreso debe abrirse")
	menu.call("_open_tutorial")
	assert(menu.get_node("TutorialPanel").visible, "Tutorial debe abrirse")
	print("PASS: progress and tutorial panels are reachable from the main menu.")
	quit(0)
