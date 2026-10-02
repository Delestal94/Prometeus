class_name FrameSlicer
extends RefCounted
## Cuts a long job on the main thread into slices, so the window keeps drawing
## (a loading screen that never freezes). The job is a coroutine that calls
## `await slicer.tick()` between its small steps: while the slice's time budget
## isn't spent tick() returns at once, once it is the coroutine waits a frame
## and gets a fresh budget. A job keeps working the same with a null slicer or
## one without a tree (the callers check `if slicer != null`): it just doesn't
## wait, which is what a headless test or a tool wants.
##
## The coroutine waits on the tree's process_frame, not on a node of its own:
## a node freed mid-job drops the job quietly, and a paused or
## process-disabled branch can still finish building.

## Where a slice's budget starts counting, in microseconds (Time.get_ticks_usec()).
var _slice_start: int = 0
var _budget_usec: int = 0
var _tree: SceneTree
## Frames waited so far (tests and tuning).
var frames_waited: int = 0
## The longest stretch of work between two frames, microseconds: what the main
## thread actually held (tests and tuning).
var longest_slice_usec: int = 0


## `budget_msec` is how much work one frame takes before the job lets it draw.
func _init(scene_tree: SceneTree, budget_msec: float = 12.0) -> void:
	_tree = scene_tree
	_budget_usec = int(budget_msec * 1000.0)
	_slice_start = Time.get_ticks_usec()


## True once this frame's budget is spent.
func due() -> bool:
	return _tree != null and Time.get_ticks_usec() - _slice_start >= _budget_usec


## Call between steps of a job: waits for the next frame if the budget is spent.
func tick() -> void:
	if due():
		await frame()


## Waits one frame whatever the budget (the job has nothing to do but wait for
## something else, a worker thread say), then starts a new slice.
func frame() -> void:
	if _tree == null:
		return
	longest_slice_usec = maxi(longest_slice_usec, Time.get_ticks_usec() - _slice_start)
	await _tree.process_frame
	frames_waited += 1
	_slice_start = Time.get_ticks_usec()
