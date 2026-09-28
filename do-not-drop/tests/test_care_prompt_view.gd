extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_care_prompt_view.gd
##
## The care card (ui/hud/care_card.gd) and its animated strip
## (ui/hud/care_prompt_view.gd, playtest 2026-09-28): every thing it animates
## also sounds -- a tap that counted, a wrong key, hands on a box that says
## hands off, tool progress, a piece picked up, a job done, a new thing to
## do -- and none of it fires just because the card started looking at a box.

const CareCard = preload("res://scripts/ui/hud/care_card.gd")
const CarePromptView = preload("res://scripts/ui/hud/care_prompt_view.gd")
const CarePractice = preload("res://scripts/ui/hud/care_practice.gd")
const SynthAudio = preload("res://scripts/presentation/synth_audio.gd")

var _failures: int = 0


## Stand-ins for the local player and a box already on the rack.
class FakePlayer extends Node:
	var carried_package: Node = null
	var seat_node_path: NodePath = NodePath()


class FakeAboardBox extends Node:
	func is_aboard() -> bool:
		return true


func _initialize() -> void:
	await process_frame
	_check_sounds()
	var view: CarePromptView = CarePromptView.new()
	root.add_child(view)
	await process_frame
	_check_players(view)
	_check_sequence(view)
	_check_hold_and_release(view)
	_check_tool(view)
	_check_collect(view)
	await _check_draws(view)
	view.free()
	await _check_card()
	await _check_practice()
	if _failures == 0:
		print("PASS: the care card animates and sounds every step, and says what to do")
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
	view.reset()
	view.played.clear()
	var sequence: Dictionary = {"steps": [&"up", &"left", &"down"], "index": 0, "mistakes": 0, "solved": 0}
	view.show_step(&"sequence", {"sequence": sequence})
	_expect(view.played.is_empty(), "Just looking at a box plays nothing")
	sequence["index"] = 1
	view.show_step(&"sequence", {"sequence": sequence})
	_expect(view.played.back() == &"step", "A tap that counts sounds a step")
	sequence["index"] = 0
	sequence["mistakes"] = 1
	view.show_step(&"sequence", {"sequence": sequence})
	_expect(view.played.back() == &"error", "A wrong tap buzzes")
	sequence["index"] = 3
	sequence["solved"] = 1
	view.show_step(&"hold", {"sequence": sequence})
	_expect(view.played.back() == &"success", "Solving it plays the success cue")
	view.reset()
	view.show_step(&"hold", {"sequence": sequence})
	_expect(view.played.count(&"success") == 1, "A box already solved when first seen isn't celebrated again")


func _check_hold_and_release(view: CarePromptView) -> void:
	view.reset()
	view.played.clear()
	view.show_step(&"hold", {"primary": false})
	view.show_step(&"hold", {"primary": true})
	_expect(view.played.back() == &"tick", "Grabbing the box clicks")
	view.show_step(&"release", {"primary": true})
	_expect(view.played.has(&"whoosh"), "Switching to a new thing to do swishes")
	_expect(view.played.back() == &"error", "Hands on a box that says hands off buzzes")


func _check_tool(view: CarePromptView) -> void:
	view.reset()
	view.played.clear()
	view.show_step(&"tool", {"work": 0.0, "fixes": 0})
	view.show_step(&"tool", {"work": 0.05, "fixes": 0, "tool_held": true})
	view.show_step(&"tool", {"work": 0.12, "fixes": 0, "tool_held": true})
	_expect(view.played.back() == &"tick", "Progress clicks as it crosses each tenth")
	view.show_step(&"hold", {"work": 0.0, "fixes": 1})
	_expect(view.played.back() == &"success", "A finished job plays the success cue")


func _check_collect(view: CarePromptView) -> void:
	view.reset()
	view.played.clear()
	view.show_step(&"collect", {"missing": 3})
	view.show_step(&"collect", {"missing": 2})
	_expect(view.played.back() == &"step", "Picking up a piece sounds a step")
	view.show_step(&"tool", {"missing": 0})
	_expect(view.played.back() == &"success", "The last piece is celebrated")


## Every step draws without errors, keyboard and gamepad.
func _check_draws(view: CarePromptView) -> void:
	for pad: bool in [false, true]:
		for step: StringName in [&"hold", &"release", &"tool", &"sequence", &"collect", &"idle"]:
			view.reset()
			view.show_step(step, {"pad": pad, "primary": true, "work": 0.5, "missing": 2,
				"sequence": {"steps": [&"up", &"down", &"left", &"right"], "index": 2}})
			await process_frame
	_expect(view.size.y >= CarePromptView.VIEW_SIZE.y, "The strip reserves its room on the card")


## The card spells the step out and colours its state.
func _check_card() -> void:
	var card: CareCard = CareCard.new()
	root.add_child(card)
	await process_frame
	card.update("Frágil", 1, 42.0, {"step": &"hold", "title": "SOSTENELA", "detail": "Mantené clic izq."},
		{"primary": false}, PackedStringArray(["Q  soltar"]))
	await process_frame
	_expect(card.step_title.text == "SOSTENELA" and card.name_label.text == "FRÁGIL", "The card names the box and the step")
	_expect(card.state_chip.text == "EN RIESGO" and is_equal_approx(card.integrity_bar.value, 42.0),
		"...its state and integrity")
	_expect(card.footer.get_child_count() == 1 and card.footer.get_child(0).get_child_count() == 2,
		"...and the secondary keys, each key beside its action")
	_expect(card.prompt_view.step == &"hold", "The strip shows the same step")
	card.free()


## The depot practice ticks each step only when the player actually does it.
func _check_practice() -> void:
	var practice: CarePractice = CarePractice.new()
	root.add_child(practice)
	var player := FakePlayer.new()
	root.add_child(player)
	var keys: Dictionary = {"primary": "Clic izq.", "tool": "Clic der.", "interact": "E"}
	await process_frame
	practice.advance(0.1, player, keys, false)
	_expect(practice.step == 0, "Nothing ticks before a box is picked up")
	player.carried_package = Node.new()
	practice.advance(0.1, player, keys, false)
	_expect(practice.step == 1, "Picking a box up ticks the first step")
	practice.advance(1.2, player, keys, false)
	_expect(practice.step == 1, "Holding nothing doesn't count as holding")
	Input.action_press(&"package_action_primary")
	practice.advance(0.6, player, keys, false)
	practice.advance(0.6, player, keys, false)
	Input.action_release(&"package_action_primary")
	_expect(practice.step == 2, "A second of holding the primary action ticks it")
	Input.action_press(&"care_work")
	practice.advance(1.1, player, keys, false)
	Input.action_release(&"care_work")
	_expect(practice.step == 3, "A second on the tool button ticks it")
	practice.tap(&"up")
	practice.tap(&"right")
	practice.advance(0.1, player, keys, false)
	_expect(practice.step == 3, "A wrong tap starts the sequence over")
	for direction: StringName in [&"up", &"left", &"down"]:
		practice.tap(direction)
	practice.advance(0.1, player, keys, false)
	_expect(practice.step == 4, "W, A, S in order ticks it")
	var box := FakeAboardBox.new()
	box.add_to_group(&"cargo")
	root.add_child(box)
	practice.advance(0.1, player, keys, false)
	_expect(practice.finished, "A box aboard finishes the practice")
	_expect(practice.prompt_view.played.count(&"success") >= 4, "Every step done is celebrated")
	_expect(not practice.advance(CarePractice.FAREWELL_SECONDS + 0.1, player, keys, false), "...and then it goes away")
	(player.carried_package as Node).free()
	for node: Node in [practice, player, box]:
		node.free()


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("FAIL: " + message)
