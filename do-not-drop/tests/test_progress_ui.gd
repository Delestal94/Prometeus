extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_progress_ui.gd
## Progress screens: every unlock explains its reward and keeps delivery progress
## apart from points; the records switch between Delivery and Endless with a
## readable date and crew.

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var menu := (load("res://scenes/ui/main_menu.tscn") as PackedScene).instantiate()
	root.add_child(menu)
	await process_frame
	assert(menu.get_node_or_null("ProgressPanel") != null, "El menú debe incluir Progreso")
	assert(menu.get_node_or_null("TutorialPanel") != null, "El menú debe incluir Cómo jugar")
	menu.call("_open_progress")
	var progress: Control = menu.get_node("ProgressPanel")
	assert(progress.visible, "Progreso debe abrirse")
	var unlocks: Node = root.get_node(^"UnlockManager")
	var old_score: int = int(unlocks.total_score)
	var old_deliveries: int = int(unlocks.successful_deliveries)
	unlocks.total_score = 25
	unlocks.successful_deliveries = 1
	progress.call(&"_refresh")
	await process_frame
	var noisy_row: Node = progress.find_child("Unlock_noisy_trap", true, false)
	assert(noisy_row != null, "Cada desbloqueo debe tener su propia tarjeta")
	assert(noisy_row.find_child("Reward", true, false).text.contains("Nueva trampa"),
			"La tarjeta debe explicar qué contenido entrega")
	var delivery_bar: ProgressBar = noisy_row.find_child("EntregasProgress", true, false)
	var score_bar: ProgressBar = noisy_row.find_child("PuntosProgress", true, false)
	assert(delivery_bar != null and score_bar != null and delivery_bar.value != score_bar.value,
		"Entregas y puntos deben tener barras separadas")
	unlocks.total_score = old_score
	unlocks.successful_deliveries = old_deliveries
	var new_campaign: Button = null
	for candidate: Node in progress.find_children("*", "Button", true, false):
		if (candidate as Button).text == "Empezar campaña nueva":
			new_campaign = candidate as Button
			break
	assert(new_campaign != null, "Progreso debe ofrecer empezar una campaña nueva")
	var crew: Node = root.get_node(^"CrewProgression")
	crew.team_money = 177
	new_campaign.pressed.emit()
	assert(crew.team_money == 177, "El primer click solo pide confirmación")
	assert(new_campaign.text.begins_with("Confirmar"), "El botón debe mostrar la confirmación")
	new_campaign.pressed.emit()
	assert(crew.team_money == crew.STARTING_MONEY, "El segundo click reinicia la campaña")
	var manager: Node = root.get_node(^"RunManager")
	var old_board: Array = manager.leaderboard.duplicate(true)
	manager.leaderboard = [
		{"score": 420, "mode": &"delivery", "crew_size": 3, "date": "2026-09-26"},
		{"score": 900, "mode": &"endless", "crew_size": 2, "date": "2026-09-25"},
	]
	menu.call("_open_leaderboard")
	var leaderboard: Control = menu.get_node("LeaderboardPanel")
	assert(leaderboard.visible, "Récords debe abrirse")
	await process_frame
	assert(leaderboard.find_child("Rank1", true, false) != null, "Entrega debe mostrar su clasificación")
	assert(_all_labels(leaderboard).contains("3 jugadores") and _all_labels(leaderboard).contains("26/09/2026"),
		"El récord debe mostrar tripulación y fecha legible")
	leaderboard.call(&"_set_mode", &"endless")
	await process_frame
	assert(_all_labels(leaderboard).contains("900 pts") and not _all_labels(leaderboard).contains("420 pts"),
		"Las pestañas deben separar Entrega de Endless")
	manager.leaderboard = old_board
	menu.call("_open_tutorial")
	assert(menu.get_node("TutorialPanel").visible, "Tutorial debe abrirse")
	print("PASS: progress and tutorial panels are reachable from the main menu.")
	quit(0)


func _all_labels(root_node: Node) -> String:
	var texts: PackedStringArray = []
	for label: Node in root_node.find_children("*", "Label", true, false):
		texts.append(String((label as Label).text))
	return "\n".join(texts)
