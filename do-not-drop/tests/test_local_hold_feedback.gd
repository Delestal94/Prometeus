extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_local_hold_feedback.gd
##
## S-205: holding the primary action on a box answers at once on the holder's
## screen, even when the host hears about it late.
##
## - `--fake-lag=<ms>` (tender_input_lag.gd, debug builds) holds the care input
##   back on its way to the host; without it the input is sent straight away.
## - With the lag on, the local "I'm holding" flag (player_hold_feedback.gd,
##   which the box's grip glow in package_feedback.gd follows) changes in the
##   very call that reads the input (player_cargo_care.gd update_assisting),
##   while the host's copy of the input -- and so the box's integrity -- stays
##   as it was until the held sample arrives.
## - Letting go answers at once too, and the samples leave in order.

const InputLag = preload("res://scripts/gameplay/package/tender_input_lag.gd")

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	await process_frame
	var level: Node = load("res://scenes/gameplay/level_base.tscn").instantiate()
	root.add_child(level)
	current_scene = level
	await process_frame
	await physics_frame
	await physics_frame
	var player: Player = level.local_player
	var care: Node = player._cargo_care
	var box: DeliveryPackage = get_nodes_in_group(&"cargo")[1] as DeliveryPackage
	box.set_tender(1)
	box.global_position = player.global_position
	player.assisted_package = box
	var feedback: Node = box.get_node(^"PackageFeedbackComponent")

	# --- the command line: --fake-lag=<ms> ---
	var parsed := InputLag.new(false)
	parsed.call(&"_read_args", PackedStringArray(["--other", "--fake-lag=150"]))
	_expect(is_equal_approx(parsed.fake_lag, 0.15),
		"--fake-lag=150 is 0.15 s (got %s)" % parsed.fake_lag)
	_expect(not InputLag.new(false).is_lagging(), "No flag, no lag")

	# --- without lag the host hears it in the same call ---
	var lag: RefCounted = care.input_lag
	lag.fake_lag = 0.0
	Input.action_press(&"package_action_primary")
	care.update_assisting()
	_expect(bool(box.player_input.get("steady", false)), "No lag: the host has the hold at once")
	_expect(care.hold_feedback.holding, "No lag: the local flag is up too")
	care.hold_feedback.end_frame()
	Input.action_release(&"package_action_primary")
	care.update_assisting()
	care.hold_feedback.end_frame()
	box.set_tender(1)
	care.hold_feedback.release()

	# --- with lag: the local answer is immediate, the host's is not ---
	lag.fake_lag = 0.15
	lag.fake_jitter = 0.0
	lag.include_host = true
	_expect(lag.is_lagging(), "--fake-lag is on (needs a debug build of Godot)")
	var integrity_before: float = box.integrity
	var holds_before: int = care.hold_feedback.press_count
	_expect(not care.hold_feedback.holding, "Not holding before the press")
	Input.action_press(&"package_action_primary")
	care.update_assisting()
	_expect(care.hold_feedback.holding, "Lag: the local flag changes in the same call as the input")
	_expect(care.hold_feedback.press_count == holds_before + 1, "...counted once")
	_expect(care.hold_feedback.package == box, "...on the box being steadied")
	feedback.call(&"_process", 0.2)
	_expect(float(feedback.call(&"grip_glow")) > 0.9,
		"Lag: the box glows the frame after the press (got %s)" % feedback.call(&"grip_glow"))
	_expect(lag.pending() == 1, "The sample is held back on its way (%d pending)" % lag.pending())
	_expect(box.player_input.is_empty(), "Lag: the host has heard nothing yet")
	_expect(is_equal_approx(box.integrity, integrity_before),
		"Lag: integrity is the host's and has not moved (%s)" % box.integrity)
	care.hold_feedback.end_frame()

	# Still holding a frame later: no second press, and the sample keeps queueing in order.
	care.update_assisting()
	_expect(care.hold_feedback.press_count == holds_before + 1, "Holding on is not a new press")
	care.hold_feedback.end_frame()
	var now: float = Time.get_ticks_msec() / 1000.0
	lag.flush(now)
	_expect(box.player_input.is_empty(), "Before its time the sample has still not arrived")

	# --- letting go answers at once as well ---
	Input.action_release(&"package_action_primary")
	care.update_assisting()
	_expect(not care.hold_feedback.holding, "Lag: letting go clears the flag in the same call")
	feedback.call(&"_process", 0.2)
	_expect(float(feedback.call(&"grip_glow")) < 0.01, "...and the glow goes out")
	_expect(box.player_input.is_empty(), "...while the host still has nothing")
	care.hold_feedback.end_frame()

	# --- the held samples reach the host, oldest first ---
	lag.flush(now + 5.0)
	_expect(lag.pending() == 0, "Every held sample is sent once its time comes")
	_expect(box._tender_inputs.has(1), "The host finally has the tender's input")
	_expect(not bool((box._tender_inputs[1] as Dictionary)["input"].get("steady", true)),
		"...the last one sent, in order: the release")

	# --- the host's own hold never crosses a network ---
	lag.include_host = false
	Input.action_press(&"package_action_primary")
	care.update_assisting()
	_expect(lag.pending() == 0 and bool(box.player_input.get("steady", false)),
		"The host's own input is not delayed")
	care.hold_feedback.end_frame()
	Input.action_release(&"package_action_primary")

	# --- no input, nothing held ---
	care.hold_feedback.end_frame()
	care.hold_feedback.end_frame()
	_expect(not care.hold_feedback.holding and care.hold_feedback.package == null,
		"A frame without input lets go")

	Input.action_release(&"package_action_primary")
	var boxes: Array[Node] = get_nodes_in_group(&"cargo")
	_expect(boxes.size() >= 4, "The level has boxes to spare (%d)" % boxes.size())
	var script: GDScript = care.hold_feedback.get_script()
	var here: DeliveryPackage = boxes[3] as DeliveryPackage
	var gone: DeliveryPackage = boxes[2] as DeliveryPackage

	# --- a box freed under the feedback does not wedge it ---
	var fresh: RefCounted = script.new()
	fresh.set_input(gone, true)
	fresh.end_frame()
	gone.free()
	fresh.end_frame()
	fresh.end_frame()
	_expect(fresh.package == null and not fresh.holding,
		"A freed box is let go of, not held on to (holding %s)" % fresh.holding)
	fresh.set_input(here, true)
	here.get_node(^"PackageFeedbackComponent").call(&"_process", 0.2)
	_expect(fresh.package == here and fresh.holding, "...and the next box is taken")
	_expect(float(here.get_node(^"PackageFeedbackComponent").call(&"grip_glow")) > 0.9,
		"...and glows")
	fresh.release()
	here.get_node(^"PackageFeedbackComponent").call(&"_process", 0.2)

	# --- lag: a freed box in the queue does not stop the rest from leaving ---
	var late: RefCounted = InputLag.new(false)
	late.fake_lag = 0.15
	late.fake_jitter = 0.0
	late.include_host = true
	var ghost := DeliveryPackage.new()
	root.add_child(ghost)
	late.send(ghost, &"submit_tender_input", {"steady": true}, true, 0.0)
	late.send(box, &"submit_tender_input", {"steady": true}, true, 0.0)
	ghost.free()
	box.set_tender(1)
	late.flush(5.0)
	_expect(late.pending() == 0 and bool(box.player_input.get("steady", false)),
		"A freed box in the queue is skipped and the next sample still leaves")

	# --- lag: a client that became the host does not send what it held ---
	late.send(box, &"submit_tender_input", {"steady": true}, false, 0.0)
	_expect(late.pending() == 1, "A client's sample is held")
	box.set_tender(1)
	late.flush(5.0)
	_expect(late.pending() == 0 and box.player_input.is_empty(),
		"Held samples are dropped once this peer is the host")

	# --- two boxes in one frame: the box being held wins, the helped one on a tie ---
	var pair: RefCounted = script.new()
	pair.set_input(box, true, true)
	pair.set_input(here, true, false)
	_expect(pair.package == box and pair.press_count == 1,
		"Both held: the box being helped is the one (press %d)" % pair.press_count)
	_expect(float(here.get_node(^"PackageFeedbackComponent").call(&"grip_glow")) < 0.01,
		"...and the other does not glow")
	pair.end_frame()
	pair.set_input(here, true, false)
	pair.set_input(box, true, true)
	_expect(pair.package == box and pair.press_count == 1,
		"The order they are read in does not matter, and holding on is not a press")
	pair.end_frame()
	pair.set_input(here, true, false)
	pair.set_input(box, false, true)
	_expect(pair.package == here and pair.holding, "The one being held beats the one only helped")
	_expect(pair.press_count == 2, "...a new box held is a press (%d)" % pair.press_count)
	pair.release()
	here.get_node(^"PackageFeedbackComponent").call(&"_process", 0.2)

	# --- the hold the host counts: a tool at work is not steadying ---
	care.hold_feedback.release()
	care.send_input(box, &"submit_tender_input", {"steady": true, "work": true})
	_expect(not care.hold_feedback.holding, "Working a tool is not holding, as the host reads it")
	care.hold_feedback.end_frame()
	care.send_input(box, &"submit_tender_input", {"steady": true, "work": false})
	_expect(care.hold_feedback.holding, "...without the tool it is")
	care.hold_feedback.release()

	player.assisted_package = null
	level.queue_free()
	await process_frame
	if _failures == 0:
		print("PASS: the hold shows at once under --fake-lag while integrity waits for the host")
	quit(_failures)


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1
