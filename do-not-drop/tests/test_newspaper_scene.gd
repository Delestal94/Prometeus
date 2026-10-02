extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_newspaper_scene.gd
##
## The next-day newspaper as a scene (N-606.3: newspaper_director.gd,
## newspaper_set.gd, newspaper_spread.gd, data/newspaper/shots.json,
## hud_newspaper.gd, the option in game_settings.gd):
## - with the host's newspaper_ready waiting, run_ended plays the scene first
##   (full screen, the run's 3D world not drawn behind it) and the results card
##   only comes up on newspaper_finished, with the world drawn again;
## - the printed paper is this run's: the masthead names the town, the front
##   story and the ones under it read in the viewer's language, one block per
##   story; every story of the catalogue, in Spanish and in English and with
##   long names, fits its box at a size that reads;
## - the director: office, approach, the spread, one close-up per story (each
##   framing its whole block, its text at 24 px or more at 720p), the spread
##   again and the reaction; ~30 s, the Boss lowers the paper and reacts by the
##   run (happy for the "everything arrived" scandal);
## - holding Interact skips it after 0.6 s (hint and ring on screen); a button
##   already held when it began doesn't count; a short tap doesn't skip;
## - Opciones > Diario al final: never, or only with news, keeps it off;
## - with no paper, or one that can't be read, the results come up as always;
##   a paper is shown once and a new run forgets one nobody watched;
## - losing the host during the scene ends it and leaves the results (greyed retry);
## - the run's photos (N-606.5, news_photographer.gd): with this peer's photo of
##   the front story the page prints it halftoned under that story, with its
##   caption, on the inner spread and the front page, and it gets its own
##   close-up after the front story's; else the first story under it with a
##   photo; none, no photo; every caption fits in both languages; the
##   photographer frames the deer from ahead of the van and the back door from
##   behind, takes nothing headless (once per fact), and a door's story takes
##   the phone's delivery photo of that door; the filler is the bundled PT Serif.

const DESK: GDScript = preload("res://scripts/presentation/newspaper/news_desk.gd")
const SPREAD: GDScript = preload("res://scripts/presentation/newspaper/newspaper_spread.gd")
const STEP: float = 1.0 / 30.0

var _failures: int = 0
var _finished_signals: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var bus: Node = root.get_node(^"/root/EventBus")
	var network: Node = root.get_node(^"/root/NetworkManager")
	var settings: Node = root.get_node(^"/root/GameSettings")
	var mode_before: int = settings.get(&"newspaper_mode")
	settings.set(&"newspaper_mode", 0)
	# A 16:9 screen, as the game opens (headless starts at 64x64, a square canvas).
	root.size = Vector2i(1280, 720)
	var hud: CanvasLayer = load("res://scripts/ui/hud/hud.gd").new()
	root.add_child(hud)
	await process_frame
	hud.pause.primary_action()
	hud.newspaper.newspaper_finished.connect(func() -> void: _finished_signals += 1)
	var facts: Array = [{"kind": "deer_hit", "house": -1, "tags": [], "peer": 1},
			{"kind": "missed", "house": 1, "tags": ["cake"], "peer": 0},
			{"kind": "abandoned", "house": 0, "tags": ["hen"], "peer": 0},
			{"kind": "fault_mirror", "house": -1, "tags": [], "peer": 0}]
	var context: Dictionary = {"seed": 9, "town": "Villa Frágil", "km": 1.5, "minutes": 3,
			"crew": [{"peer": 1, "nick": "Turbo"}]}
	var paper: Dictionary = DESK.compose(facts, context)
	var clean: Dictionary = DESK.compose([], context)
	var results: Dictionary = {"delivered": true, "elapsed_seconds": 100.0, "score": 120, "cargo_total": 1,
			"cargo_intact": 1, "houses_delivered": 1, "best_score": 500, "breakdown": [], "deliveries": []}

	# Without a paper the results come up as always.
	bus.run_ended.emit(120, results)
	_expect(hud.overlay_mode == "results" and hud.overlay.visible and not hud.newspaper.is_open(),
			"With no paper the results come straight up (mode %s)" % hud.overlay_mode)
	_close_results(hud)

	# With one, the scene first.
	bus.newspaper_ready.emit(paper)
	bus.run_ended.emit(120, results)
	_expect(hud.newspaper.is_open() and hud.overlay_mode == "newspaper",
			"The scene comes up before the results (mode %s)" % hud.overlay_mode)
	_expect(not hud.overlay.visible, "The results card waits behind it")
	_expect(root.disable_3d, "The run's world isn't drawn behind the scene")
	await process_frame
	var director: Control = hud.newspaper.director
	_expect(director.get_parent() == hud.root and director.visible, "The scene covers the HUD")
	var stage: Node3D = director.get("stage")
	var viewport: SubViewport = director.get("viewport")
	_expect(viewport.own_world_3d and stage.get_viewport() == viewport, "The set lives in its own world")
	_expect(stage.find_child("Boss", false, false) != null and stage.find_child("Paper", false, false) != null,
			"The Boss and his paper are on the set")

	# The paper printed on the sheet is this run's, in this language.
	var spread: Node = director.get("spread")
	var texts: Array = _texts(spread)
	_expect(texts.has(tr("HUD_NEWS_MASTHEAD") % "Villa Frágil"), "The front page names the town")
	var front: Dictionary = DESK.read(paper["front"])
	_expect(texts.has(front["headline"]) and texts.has(front["body"]),
			"The front story is printed (%s)" % front["headline"])
	for entry: Dictionary in paper["stories"]:
		_expect(texts.has(DESK.read(entry)["headline"]), "A story under it is printed (%s)" % entry["id"])
	var blocks: Array = spread.get("blocks")
	_expect(blocks.size() == 1 + (paper["stories"] as Array).size() + 1,
			"One block per story and the classified (%d)" % blocks.size())
	_expect((spread.get("overflowing") as Array).is_empty(), "Every story fits its box")

	# The timeline: shots in order, one close-up per block, ~30 s.
	var timeline: Array = director.get("timeline")
	var ids: Array = timeline.map(func(shot: Dictionary) -> String: return shot["id"])
	var expected: Array = ["office", "approach", "spread"]
	for block: Dictionary in blocks:
		expected.append(block["id"])
	expected.append_array(["spread_again", "reaction"])
	_expect(ids == expected, "The shots run office, approach, spread, the stories, spread, reaction (%s)" % str(ids))
	var duration: float = director.get("duration")
	_expect(duration >= 26.0 and duration <= 32.0, "The scene lasts about 30 s (%.1f)" % duration)
	var camera: Camera3D = director.get("camera")
	for shot: Dictionary in timeline:
		if not String(shot["id"]).begins_with("story_") and shot["id"] not in ["front", "photo", "filler"]:
			continue
		director.call(&"_apply", float(shot["start"]) + float(shot["seconds"]) - 0.05, 0.0)
		var block: Dictionary = blocks[blocks.find_custom(func(b: Dictionary) -> bool: return b["id"] == shot["id"])]
		_check_close_up(stage, camera, viewport, block)

	# Played to the end: the Boss lowers the paper and reacts, then the results.
	director.set(&"time", 0.0)
	director.set(&"_shot_index", 0)
	var saw_reaction: bool = false
	while hud.newspaper.is_open() and float(director.get("time")) < duration + 1.0:
		director.call(&"_process", 0.25)
		if director.call(&"shot_id") == "reaction" and float(stage.get("lowered")) >= 1.0:
			saw_reaction = true
	_expect(saw_reaction, "The Boss lowers the paper in the reaction shot")
	var face: Node = stage.get("face")
	_expect(face == null or face.get("mouth_id") == &"surprised",
			"With bad news he is shocked (%s)" % (face.get("mouth_id") if face else ""))
	_expect(not hud.newspaper.is_open() and hud.overlay_mode == "results" and hud.overlay.visible,
			"At the end the results come up (mode %s)" % hud.overlay_mode)
	_expect(_finished_signals == 1, "newspaper_finished told the results (%d)" % _finished_signals)
	_expect(not root.disable_3d, "The run's world is drawn again behind the results")
	_expect(hud.action_button.visible and (hud.action_button.has_focus() or hud.menu_button.has_focus()),
			"The results card has focus")
	_close_results(hud)

	# A clean run: the Boss is pleased. English reads in English.
	settings.call(&"set_language", "en")
	bus.newspaper_ready.emit(clean)
	bus.run_ended.emit(120, results)
	director = hud.newspaper.director
	stage = director.get("stage")
	_expect(_texts(director.get("spread")).has(DESK.read(clean["front"])["headline"]) \
			and tr("HUD_NEWS_MASTHEAD") % "Villa Frágil" != "El Eco de Villa Frágil",
			"In English the paper is English")
	while hud.newspaper.is_open():
		director.call(&"_process", 0.5)
	face = stage.get("face")
	_expect(face == null or face.get("mouth_id") == &"grin", "With nothing to tell he is pleased")
	settings.call(&"set_language", "es")
	_close_results(hud)

	# Skipping: hold Interact 0.6 s. A tap doesn't skip; a button held from before doesn't count.
	bus.newspaper_ready.emit(paper)
	bus.run_ended.emit(120, results)
	director = hud.newspaper.director
	director.call(&"_process", 1.1)
	var skip_row: Control = director.find_child("Skip", true, false)
	_expect(skip_row != null and skip_row.visible, "After a second it says how to skip")
	director.call(&"_input", _action(&"interact", true))
	_advance(director, 0.3)
	director.call(&"_input", _action(&"interact", false))
	_advance(director, 0.5)
	_expect(hud.newspaper.is_open(), "A tap doesn't skip")
	director.call(&"_input", _action(&"interact", true))
	_advance(director, 0.4)
	_expect(hud.newspaper.is_open(), "Not before the hold is full")
	_advance(director, 0.3)
	_expect(not hud.newspaper.is_open() and hud.overlay_mode == "results", "Holding Interact skips to the results")
	_close_results(hud)
	Input.action_press(&"jump")
	bus.newspaper_ready.emit(paper)
	bus.run_ended.emit(120, results)
	director = hud.newspaper.director
	_advance(director, 1.5)
	_expect(hud.newspaper.is_open(), "Jump already held when it began doesn't skip it")
	Input.action_release(&"jump")
	director.call(&"_input", _action(&"jump", false))
	director.call(&"_input", _action(&"jump", true))
	_advance(director, 0.7)
	_expect(not hud.newspaper.is_open(), "Pressed again, it skips")
	_close_results(hud)

	# The option.
	settings.set(&"newspaper_mode", 2)
	bus.newspaper_ready.emit(paper)
	bus.run_ended.emit(120, results)
	_expect(not hud.newspaper.is_open() and hud.overlay_mode == "results", "Never: no scene")
	_close_results(hud)
	settings.set(&"newspaper_mode", 1)
	bus.newspaper_ready.emit(clean)
	bus.run_ended.emit(120, results)
	_expect(not hud.newspaper.is_open(), "Only with news: not for a clean run")
	_close_results(hud)
	bus.newspaper_ready.emit(paper)
	bus.run_ended.emit(120, results)
	_expect(hud.newspaper.is_open(), "Only with news: yes when there is news")
	hud.newspaper.dismiss()
	_close_results(hud)
	settings.set(&"newspaper_mode", 0)

	# Shown once; a paper that can't be read is skipped; a new run forgets it.
	bus.run_ended.emit(120, results)
	_expect(hud.overlay_mode == "results" and not hud.newspaper.is_open(), "A paper is shown once")
	_close_results(hud)
	var broken: Dictionary = paper.duplicate(true)
	broken["front"]["id"] = "not_a_story"
	bus.newspaper_ready.emit(broken)
	bus.run_ended.emit(120, results)
	_expect(hud.overlay_mode == "results" and not hud.newspaper.is_open(), "A paper that can't be read is skipped")
	_close_results(hud)
	bus.newspaper_ready.emit(paper)
	bus.run_started.emit(&"test_route", [1])
	bus.run_ended.emit(120, results)
	_expect(hud.overlay_mode == "results" and not hud.newspaper.is_open(), "A new run forgets a paper nobody watched")
	_close_results(hud)

	# The host goes during the scene: results stay, retry greyed out.
	hud.prompts.set(&"session_lost", false)
	bus.newspaper_ready.emit(paper)
	bus.run_ended.emit(120, results)
	await process_frame
	network.session_failed.emit("host lost")
	await process_frame
	_expect(not hud.newspaper.is_open() and hud.overlay_mode == "results",
			"Losing the host ends the scene and leaves the results (mode %s)" % hud.overlay_mode)
	_expect(hud.action_button.disabled, "The retry is greyed out, as on any results screen without its host")
	_expect(not root.disable_3d, "And the world is drawn again")

	await _check_photos(bus, hud, paper, results, settings)
	_check_catalogue_fits(settings)
	settings.set(&"newspaper_mode", mode_before)
	hud.queue_free()
	await process_frame
	if _failures == 0:
		print("PASS: the next-day scene plays the run's paper, frames every story, skips on a hold",
				" and hands over to the results")
	quit(_failures)


## Every story's whole block on screen in its close-up, its text big enough.
func _check_close_up(stage: Node3D, camera: Camera3D, viewport: SubViewport, block: Dictionary) -> void:
	var page: Vector2 = Vector2(SPREAD.PAGE_SIZE)
	var rect: Rect2 = block["rect"]
	var screen := Rect2(Vector2.ZERO, Vector2(viewport.size))
	for corner: Vector2 in [rect.position, rect.position + Vector2(rect.size.x, 0), rect.end,
			rect.position + Vector2(0, rect.size.y)]:
		var point: Vector3 = stage.call(&"paper_point", corner / page)
		var projected: Vector2 = camera.unproject_position(point)
		_expect(not camera.is_position_behind(point) and screen.has_point(projected),
				"The close-up of %s shows its whole block (%s in %s)" % [block["id"], projected, screen.size])
	var smallest: float = INF
	for label: Label in block["labels"]:
		var font_size: float = label.get_theme_font_size("font_size")
		var top: Vector2 = camera.unproject_position(stage.call(&"paper_point", label.position / page))
		var foot: Vector2 = label.position + Vector2(0, font_size)
		var bottom: Vector2 = camera.unproject_position(stage.call(&"paper_point", foot / page))
		smallest = minf(smallest, top.distance_to(bottom) * 720.0 / screen.size.y)
	_expect(smallest >= 24.0, "The text of %s reads at %.1f px at 720p (24 or more)" % [block["id"], smallest])


## The run's photos on the page, the photographer's framing and its fallbacks.
func _check_photos(bus: Node, hud: CanvasLayer, paper: Dictionary, results: Dictionary, settings: Node) -> void:
	var image := Image.create(64, 36, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.4, 0.5, 0.3))
	var photo := ImageTexture.create_from_image(image)
	# Loaded here, not preloaded: it uses EventBus, which a --script can't name at compile time.
	var photographer: Node = (load("res://scripts/presentation/newspaper/news_photographer.gd") as GDScript).new()
	root.add_child(photographer)
	var front_id: String = String(paper["front"]["id"])
	photographer.get("photos")[front_id] = photo
	bus.newspaper_ready.emit(paper)
	bus.run_ended.emit(120, results)
	var director: Control = hud.newspaper.director
	var spread: Node = director.get("spread")
	_expect(spread.get("photo_story") == front_id,
			"The front story's photo is printed (%s)" % spread.get("photo_story"))
	var printed: Array = spread.find_children("Photo", "TextureRect", true, false)
	_expect(printed.size() == 2 and printed.all(func(rect: TextureRect) -> bool:
			return rect.texture == photo and rect.material is ShaderMaterial \
					and (rect.material as ShaderMaterial).shader == PressPhoto.HALFTONE),
			"Halftoned on the spread and on the front page (%d)" % printed.size())
	var caption_text: String = tr(SPREAD.caption_of(front_id))
	_expect(_texts(spread).has(caption_text) and caption_text != SPREAD.caption_of(front_id),
			"With its caption, translated (%s)" % caption_text)
	var blocks: Array = spread.get("blocks")
	_expect(blocks.size() >= 2 and blocks[1]["id"] == "photo", "The photo's block comes after the front story's")
	_expect((spread.get("overflowing") as Array).is_empty(), "The caption fits")
	var timeline: Array = director.get("timeline")
	var ids: Array = timeline.map(func(shot: Dictionary) -> String: return shot["id"])
	_expect(ids.find("photo") == ids.find("front") + 1, "Its close-up follows the front story's (%s)" % str(ids))
	_expect(float(director.get("duration")) <= 32.0,
			"And the scene still lasts about 30 s (%.1f)" % director.get("duration"))
	for shot: Dictionary in timeline:
		if shot["id"] == "photo":
			director.call(&"_apply", float(shot["start"]) + float(shot["seconds"]) - 0.05, 0.0)
			_check_close_up(director.get("stage"), director.get("camera"), director.get("viewport"), blocks[1])
	hud.newspaper.dismiss()
	_close_results(hud)

	# A photo of a story under the front one; none at all.
	var second: String = String(paper["stories"][0]["id"])
	_expect(SPREAD.chosen_photo(paper, {second: photo}) == second, "Without the front's, the first story with one")
	_expect(SPREAD.chosen_photo(paper, {"not_printed": photo}).is_empty(), "A photo of a story not printed isn't used")
	var plain: Node = SPREAD.new()
	root.add_child(plain)
	plain.call(&"print_paper", paper)
	_expect(plain.find_children("Photo", "TextureRect", true, false).is_empty() \
			and (plain.get("blocks") as Array).all(func(block: Dictionary) -> bool: return block["id"] != "photo"),
			"No photos, no photo block")
	_expect((plain.call(&"serif") as FontVariation).base_font == SPREAD.SERIF_REGULAR, "The filler is PT Serif")
	var bad: Array = []
	for language: String in ["es", "en"]:
		settings.call(&"set_language", language)
		for key: String in SPREAD.PHOTO_CAPTIONS.values():
			var font: Font = plain.call(&"serif_italic")
			var size: int = SPREAD.fitted_size(font, tr(key), Vector2(SPREAD.PHOTO_SIZE.x, SPREAD.CAPTION_HEIGHT),
					SPREAD.CAPTION_SIZES)
			if not SPREAD.fits(font, tr(key), Vector2(SPREAD.PHOTO_SIZE.x, SPREAD.CAPTION_HEIGHT), size):
				bad.append("%s %s" % [language, key])
	settings.call(&"set_language", "es")
	_expect(bad.is_empty(), "Every caption fits under its photo: %s" % str(bad))
	plain.queue_free()

	# The photographer: framing around the van, nothing headless, the phone's photo for a door.
	var van := Node3D.new()
	van.add_to_group(&"vehicle")
	root.add_child(van)
	van.global_position = Vector3(5, 0, 20)
	var deer: Dictionary = photographer.call(&"pose_for", &"deer_hit")
	var door: Dictionary = photographer.call(&"pose_for", &"rear_door")
	_expect((deer["at"] as Vector3).z < 20.0 - 5.0 and (deer["look"] as Vector3).z < 20.0,
			"The deer is shot from ahead of the van, looking at its nose (%s)" % deer["at"])
	_expect((door["at"] as Vector3).z > 20.0 + 5.0, "The back door from behind (%s)" % door["at"])
	var box: Dictionary = photographer.call(&"pose_for", &"box", Vector3(5, 0, 40))
	_expect((box["at"] as Vector3).z > 40.0, "A box on the road from beyond it, the van behind (%s)" % box["at"])
	photographer.get("photos").clear()
	bus.run_started.emit(&"test_route", [1])
	photographer.call(&"shoot", &"deer_hit")
	photographer.call(&"shoot", &"deer_hit")
	_expect((photographer.get("asked") as Dictionary).size() == 1 \
			and (photographer.get("photos") as Dictionary).is_empty(),
			"Headless a fact is noted once and no photo is taken")
	var run_manager: Node = root.get_node(^"/root/RunManager")
	run_manager.get("delivery_photos")[2] = photo
	var door_paper: Dictionary = {"front": {"id": "photo", "variant": 0, "slots": {"house": 3}}, "stories": [
			{"id": "deer_hit", "variant": 0, "slots": {}}]}
	var found: Dictionary = photographer.call(&"photos_for", door_paper)
	_expect(found.get("photo") == photo and not found.has("deer_hit"), "A door's story takes the phone's photo of it")
	run_manager.get("delivery_photos").erase(2)
	van.queue_free()
	photographer.queue_free()
	await process_frame


## Every story of the catalogue, in both languages and with long names, fits
## the boxes it can land in at a size that reads.
func _check_catalogue_fits(settings: Node) -> void:
	var display: Font = UiTheme.display_font()
	var body: Font = UiTheme.body_font(600)
	var slots: Dictionary = {"town": "San Ceferino del Bache", "house": 12, "neighbor": "Doña Eustaquia Perengano",
			"player": "Manos de Manteca", "km": 12.5, "minutes": 48, "count": 7}
	var stories: Dictionary = DESK.stories()
	var bad: Array = []
	for language: String in ["es", "en"]:
		settings.call(&"set_language", language)
		for kind: String in stories:
			var variants: Array = stories[kind].get("variants", [])
			var filler: bool = bool(stories[kind].get("filler", false))
			for variant: int in variants.size():
				var story: Dictionary = DESK.read({"id": kind, "variant": variant, "slots": slots})
				var boxes: Array = [[Vector2(560, 104), Vector2(560, 196)]] if filler \
						else [[Vector2(904, 272), Vector2(904, 296)], [Vector2(904, 112), Vector2(904, 110)]]
				var sizes: Array = [[SPREAD.STORY_HEADLINE, SPREAD.STORY_BODY]] if filler \
						else [[SPREAD.FRONT_HEADLINE, SPREAD.FRONT_BODY], [SPREAD.STORY_HEADLINE, SPREAD.STORY_BODY]]
				for index: int in boxes.size():
					var headline_size: int = SPREAD.fitted_size(display, story["headline"], boxes[index][0],
							sizes[index][0])
					var body_size: int = SPREAD.fitted_size(body, story["body"], boxes[index][1], sizes[index][1])
					if not SPREAD.fits(display, story["headline"], boxes[index][0], headline_size) \
							or not SPREAD.fits(body, story["body"], boxes[index][1], body_size) \
							or body_size < SPREAD.MIN_STORY_SIZE:
						bad.append("%s %s#%d box %d" % [language, kind, variant, index])
	settings.call(&"set_language", "es")
	_expect(bad.is_empty(), "Every story of the catalogue fits its boxes: %s" % str(bad))


func _advance(director: Control, seconds: float) -> void:
	var left: float = seconds
	while left > 0.0 and is_instance_valid(director) and not bool(director.get("done")):
		director.call(&"_process", minf(STEP, left))
		left -= STEP


func _action(action: StringName, pressed: bool) -> InputEventAction:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = pressed
	return event


func _close_results(hud: CanvasLayer) -> void:
	hud.overlay.hide()
	hud.overlay_mode = "run"


func _texts(node: Node) -> Array:
	var found: Array = []
	for label: Node in node.find_children("*", "Label", true, false):
		found.append((label as Label).text)
	return found


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1
