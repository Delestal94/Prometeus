extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_music_tracks.gd
##
## The menu's theme and the depot's radio (N-403, menu_music.gd, depot.gd):
## - the main menu plays its own theme, looping, on the Music bus (so the
##   player's music volume governs it), and it stops with the menu;
## - the depot's radio plays its composed program, looping, on the Music bus;
## - both tracks come with their origin and licence noted beside them.

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var menu: Control = load("res://scenes/ui/main_menu.tscn").instantiate()
	root.add_child(menu)
	await process_frame
	var theme := menu.get_node_or_null(^"MenuMusic") as AudioStreamPlayer
	_expect(theme != null and theme.playing, "The menu plays its theme")
	if theme != null:
		_expect(theme.stream is AudioStreamOggVorbis and (theme.stream as AudioStreamOggVorbis).loop, "The theme loops")
		_expect(theme.bus == &"Music", "On the Music bus (got %s)" % theme.bus)
	var network: Node = root.get_node(^"/root/NetworkManager")
	network.call(&"leave_session")
	menu.queue_free()
	await process_frame
	_expect(not is_instance_valid(theme), "The theme goes with the menu")

	var level: Node = load("res://scenes/gameplay/level_base.tscn").instantiate()
	root.add_child(level)
	await process_frame
	var radio := level.find_child("Radio", true, false) as AudioStreamPlayer3D
	_expect(radio != null and radio.stream is AudioStreamOggVorbis, "The depot's radio plays its composed program")
	if radio != null and radio.stream is AudioStreamOggVorbis:
		_expect((radio.stream as AudioStreamOggVorbis).loop and radio.bus == &"Music", "...looping, on the Music bus")
	level.queue_free()
	await process_frame
	root.get_node(^"/root/RunManager").call(&"reset_run")

	var licence: String = FileAccess.get_file_as_string("res://assets/audio/music/LICENCIA.md")
	for file_name: String in ["mus_menu_loop.ogg", "mus_depot_radio_loop.ogg"]:
		_expect(licence.contains(file_name), "%s's origin and licence are noted beside it" % file_name)
	if _failures == 0:
		print("PASS: the menu has its theme and the depot its radio, both looping on the Music bus, both accounted for")
	quit(_failures)


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1
