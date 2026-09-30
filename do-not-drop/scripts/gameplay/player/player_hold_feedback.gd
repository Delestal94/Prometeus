class_name PlayerHoldFeedback
extends RefCounted
## What the local player sees the instant they hold the primary action on a
## box (S-205), without waiting for the host to answer.
##
## The hold is sent to the host (submit_care_input / submit_tender_input), which
## alone decides what it does: integrity, the trap's state and the card's
## progress keep coming back from it. This is only the "I'm holding" answer the
## hands of the person at the controls deserve at once, like carry prediction
## (test_carry_prediction): a flag, set the same frame the input is read, and a
## glow on the box they are steadying. It is never sent anywhere and never read
## by the host, so a wrong guess only ever shows for a moment.
##
## The hands themselves: the seated body has no hold pose today and the
## carrying hands (carry_pose.gd) follow the box regardless, so nothing there
## reads `holding` yet. Character work is on hold (S-311); when it reopens,
## `holding` / `press_count` are what a hand squeeze should follow.

## The package whose grip glow this is lighting, if any. Variant: a box freed
## from under us (ruined and cleaned up, run over) must not stop a typed call.
var package: Variant = null
## Held right now, as far as the local input says.
var holding: bool = false
## Times the hold went down (released to held, on the box chosen), for tests
## and sounds.
var press_count: int = 0
## The inputs read this frame: [target, steady, is_assist]. A seated passenger
## whose own box is lost can send for it and for the box they help in the same
## frame; only one of them is "the box I'm holding".
var _candidates: Array = []
## What the last finished frame ended on, to tell a new press from a hold going on.
var _start_package: Variant = null
var _start_holding: bool = false
var _start_count: int = 0


## The input just read for `target` (the box in hand, at the seat or being
## helped). `steady` is the hold as the host will count it. Reacts in this same
## call; with several boxes in one frame the one being held wins, and on a tie
## the one being helped.
func set_input(target: Variant, steady: bool, is_assist: bool = false) -> void:
	if not is_instance_valid(target):
		return
	_candidates.append([target, steady, is_assist])
	_decide()


## After the frame's inputs: with none read, nothing is being held.
func end_frame() -> void:
	if _candidates.is_empty():
		release()
	_candidates.clear()
	_start_package = package
	_start_holding = holding
	_start_count = press_count


func release() -> void:
	var old: Variant = package
	package = null
	holding = false
	_start_package = null
	_start_holding = false
	_apply(old, false)


func _decide() -> void:
	var best: Array = _candidates[0]
	for candidate: Array in _candidates:
		if _rank(candidate) > _rank(best):
			best = candidate
	var target: Variant = best[0]
	var steady: bool = bool(best[1])
	var old: Variant = package
	package = target
	holding = steady
	var continuing: bool = is_same(target, _start_package) and _start_holding
	press_count = _start_count + (1 if steady and not continuing else 0)
	if not is_same(old, target):
		_apply(old, false)
	_apply(target, steady)


## Held first, then the box being helped over the one at the seat.
static func _rank(candidate: Array) -> int:
	return (2 if bool(candidate[1]) else 0) + (1 if bool(candidate[2]) else 0)


static func _apply(target: Variant, active: bool) -> void:
	if not is_instance_valid(target):
		return
	var feedback: Node = (target as Node).get_node_or_null(^"PackageFeedbackComponent")
	if feedback != null and feedback.has_method(&"set_local_grip"):
		feedback.call(&"set_local_grip", active)
