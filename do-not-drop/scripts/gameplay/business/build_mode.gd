class_name BuildMode
extends RefCounted
## State of the warehouse build mode (expansion D-0901, "Modo Empresa").
##
## Pure logic, no nodes: whether the crew member is building, the grid the player sees and the
## raised camera pose. A thin adapter in the world draws the grid lines and moves the camera
## from `grid_lines()` and `camera_pose()` (placeholder visuals; the hologram shader is D-0944).
## Placing, rotating and selling are D-0902 and D-0903; this class only decides when the mode
## can start and what the view looks like. Nothing here names autoloads or UI classes (N-919).

signal entered
signal exited

## Why enter() said no, or &"" when it worked.
var last_refusal: StringName = &""

## True while building.
var active: bool = false
## Warehouse floor in grid cells (X x Z); the current stage of the shed sets it.
var grid_size: Vector2i = Vector2i(12, 8)
## Camera focus on the floor, in meters from the shed corner.
var focus: Vector2 = Vector2.ZERO
## Camera zoom: multiplier of the base height, clamped to the tuning limits.
var zoom: float = 1.0
## Whether the grid is drawn. On while building; the player can hide it (D-0943).
var grid_visible: bool = false


## Starts the mode on a floor of `size` cells. Refused (false, `last_refusal` says why) when it
## is already active, the floor is empty, or the caller says the crew member cannot build now
## (`can_build = false`: in a vehicle, away from the shed, carrying a box).
func enter(size: Vector2i, can_build: bool = true) -> bool:
	last_refusal = &""
	if active:
		last_refusal = &"already_active"
		return false
	if size.x <= 0 or size.y <= 0:
		last_refusal = &"empty_floor"
		return false
	if not can_build:
		last_refusal = &"busy"
		return false
	active = true
	grid_size = size
	grid_visible = true
	zoom = 1.0
	focus = floor_size_m() * 0.5
	entered.emit()
	return true


## Leaves the mode. False when it was not active.
func exit() -> bool:
	if not active:
		return false
	active = false
	grid_visible = false
	exited.emit()
	return true


## Floor size in meters.
func floor_size_m() -> Vector2:
	return Vector2(grid_size) * CompanyTuning.WAREHOUSE_GRID_M


## Moves the camera focus by `delta` meters, keeping it over the floor. No effect when inactive.
func pan(delta: Vector2) -> void:
	if not active:
		return
	var limit: Vector2 = floor_size_m()
	focus = Vector2(clampf(focus.x + delta.x, 0.0, limit.x), clampf(focus.y + delta.y, 0.0, limit.y))


## Changes the zoom by `amount` (positive zooms out), within the tuning limits.
func zoom_by(amount: float) -> void:
	if not active:
		return
	zoom = clampf(zoom + amount, CompanyTuning.BUILD_ZOOM_MIN, CompanyTuning.BUILD_ZOOM_MAX)


func set_grid_visible(value: bool) -> void:
	if active:
		grid_visible = value


## Where the raised camera sits: `position` (X/Z = floor meters, Y = height) and `pitch_deg`.
## Looks from the south side of the focus point so the pitch tilts toward the north.
func camera_pose() -> Dictionary:
	var height: float = CompanyTuning.BUILD_CAMERA_HEIGHT_M * zoom
	var pitch: float = CompanyTuning.BUILD_CAMERA_PITCH_DEG
	var back: float = height / tan(deg_to_rad(pitch))
	return {
		"position": Vector3(focus.x, height, focus.y + back),
		"pitch_deg": pitch,
	}


## Segments of the grid as pairs of floor points (meters): one pair per grid line, the border
## included. Empty when the grid is hidden. The world adapter turns them into an ImmediateMesh.
func grid_lines() -> Array[Vector2]:
	var lines: Array[Vector2] = []
	if not active or not grid_visible:
		return lines
	var cell: float = CompanyTuning.WAREHOUSE_GRID_M
	var size: Vector2 = floor_size_m()
	for i: int in range(grid_size.x + 1):
		lines.append(Vector2(i * cell, 0.0))
		lines.append(Vector2(i * cell, size.y))
	for j: int in range(grid_size.y + 1):
		lines.append(Vector2(0.0, j * cell))
		lines.append(Vector2(size.x, j * cell))
	return lines
