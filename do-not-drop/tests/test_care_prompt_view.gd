extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_care_prompt_view.gd
##
## The care panel's animated "what do I press" card (ui/hud/care_prompt_view.gd,
## playtest 2026-09-28): each thing it animates also sounds -- a tap that
## counted, a wrong key, the arrow turning, tool progress, a job done -- and
## none of it fires just because the card started looking at a box.

const CarePromptView = preload("res://scripts/ui/hud/care_prompt_view.gd")
const SynthAudio = preload("res://scripts/presentation/synth_audio.gd")

var _failures: int = 0


func _initialize() -> void:
	await process_frame
	_check_sounds()
	var view: CarePromptView = CarePromptView.new()
	root.add_child(view)
	await process_frame
	_check_players(view)
	_check_sequence(view)
	_check_work(view)
	await _check_draws(view)
	view.free()
	if _failures == 0:
		print("PASS: the care card animates and sounds taps, mistakes, arrows, progress and finished jobs")
	quit(_failures)


## Every cue is real audio: long enough to hear, never clipping.
func _check_sounds() -> void:
	var synth: RefCounted = SynthAudio.new()  # Calls its static builders by name.
	for cue: StringName in [&"care_step", &"care_error", &"care_success", &"care_whoosh", &"care_tick"]:
		var stream: AudioStreamWAV = synth.call(cue)
		var peak: int = 0
		for i: int in range(0, stream.data.size(), 2):
			peak = maxi(peak, absi(stream.data.decode_s16(i)))
		var seconds: float = stream.data.size() / 2.0 / stream.mix_rate
		_expect(seconds >= 0.03 and seconds <= 0.6, "%s is a short cue (%.2f s)" % [cue, seconds])
		_expect(peak > 6000 and peak < 32700, "%s is audible and doesn't clip (peak %d)" % [cue, peak])
		_expect(synth.call(cue) == stream, "%s is built once and cached" % cue)


func _check_players(view: CarePromptView) -> void:
	var players: Array[Node] = view.find_children("*", "AudioStreamPlayer", false, false)
	_expect(players.size() == 5, "One player per cue (got %d)" % players.size())
	for player: AudioStreamPlayer in players:
		_expect(player.bus == &"SFX" and player.stream != null, "%s plays on the SFX bus" % player.name)


func _check_sequence(view: CarePromptView) -> void:
	var steps: Array = [&"up", &"left", &"down"]
	var state: Dictionary = {"steps": steps, "index": 0, "mistakes": 0, "solved": 0, "seconds": 14.0, "verb": "Desactivar"}
	_expect(view.show_sequence(state, false, "Desactivar: tocá W (↑), sin clic"), "A pending sequence shows")
	_expect(view.played.is_empty(), "Just looking at a box plays nothing")
	_expect(view.mode == CarePromptView.Mode.SEQUENCE, "...in sequence mode")
	state["index"] = 1
	view.show_sequence(state, false, "")
	_expect(view.played.back() == &"step", "A tap that counts sounds a step")
	state["index"] = 0
	state["mistakes"] = 1
	view.show_sequence(state, false, "")
	_expect(view.played.back() == &"error", "A wrong tap buzzes")
	state["index"] = 3
	state["solved"] = 1
	_expect(view.show_sequence(state, false, ""), "A solved sequence stays up to be celebrated")
	_expect(view.played.back() == &"success", "Solving it plays the success cue")
	view._process(CarePromptView.DONE_HOLD + 0.1)
	_expect(not view.show_sequence(state, false, ""), "...then gives the card back to the tool")
	view.reset()
	_expect(not view.show_sequence(state, false, ""), "A box already defused when first seen isn't celebrated again")
	_expect(view.played.back() == &"success" and view.played.count(&"success") == 1, "...and plays nothing")


func _check_work(view: CarePromptView) -> void:
	view.reset()
	view.played.clear()
	view.show_work(Vector2.LEFT, 0.0, false, false, 0, true, false, "Encintar: mantené clic der. + A (←)")
	_expect(view.played.is_empty() and view.mode == CarePromptView.Mode.WORK, "The tool card shows quietly")
	view.show_work(Vector2.LEFT, 0.0, true, false, 0, true, false, "")
	_expect(view.played.back() == &"error", "Holding the button on the wrong key buzzes")
	view.show_work(Vector2.LEFT, 0.05, true, true, 0, true, false, "")
	view.show_work(Vector2.LEFT, 0.12, true, true, 0, true, false, "")
	_expect(view.played.back() == &"tick", "Progress clicks as it crosses each tenth")
	view.show_work(Vector2.UP, 0.3, true, false, 0, true, false, "")
	_expect(view.played.has(&"whoosh"), "The arrow turning swishes")
	view.show_work(Vector2.LEFT, 0.0, false, false, 1, true, false, "")
	_expect(view.played.back() == &"success", "A finished job plays the success cue")
	view.played.clear()
	view.show_work(Vector2.LEFT, 0.0, true, true, 1, false, false, "")
	_expect(view.played == [&"error"] or view._time - view._last_error_time < CarePromptView.ERROR_COOLDOWN,
		"Pressing a tool that can't be used right now says no")


## Both modes draw without errors, keyboard and gamepad.
func _check_draws(view: CarePromptView) -> void:
	for pad: bool in [false, true]:
		view.reset()
		view.show_work(Vector2.RIGHT, 0.5, true, true, 0, true, pad, "x")
		await process_frame
		view.reset()
		view.show_sequence({"steps": [&"up", &"down", &"left", &"right"], "index": 2, "mistakes": 0, "solved": 0,
			"seconds": 5.0}, pad, "x")
		await process_frame
	_expect(view.size.y >= CarePromptView.CARD_SIZE.y, "The card reserves its room in the panel")


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("FAIL: " + message)
