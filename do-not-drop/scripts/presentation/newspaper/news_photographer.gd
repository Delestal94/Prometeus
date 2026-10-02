class_name NewsPhotographer
extends Node
## The next-day paper's "paparazzi" (N-606.5, docs/diario-final.md): when
## something worth a photo happens on the road it takes a small still from a
## good angle (PressPhoto, a throwaway SubViewport over the run's world) and
## keeps it for the story that fact becomes. NewspaperSpread prints one of
## them under the front story with a halftone screen.
##
## The facts it shoots already travel on EventBus to every peer (a deer or
## sheep hit, the back door that swings open, the mirror that goes, a box
## left on the road), so every peer takes its own photo of the same moment:
## nothing goes over the network, and a peer that draws nothing (headless)
## just has none. A delivery photo the player took with the phone
## (RunManager.delivery_photos) illustrates the stories about that door.
##
## At most one photo per story and MAX_PHOTOS per run, ~330 KB each, dropped
## with the level.

const GROUP: StringName = &"news_photographer"
const MAX_PHOTOS: int = 6
## How each fact is shot: the story ids it illustrates, where the subject is
## on the van (its local space; -Z ahead) or "box" for a box's own spot, the
## side the camera stands on (van space), the framing and how long after the
## fact (so the door has swung, the deer has tumbled).
const SHOTS: Dictionary = {
	&"deer_hit": {"stories": ["deer_hit"], "subject": Vector3(0, 0.6, -3.2), "side": Vector3(0.35, 0, -1),
			"distance": 8.0, "height": 2.4, "yaw": 0.0, "delay": 0.35},
	&"sheep_hit": {"stories": ["sheep_hit"], "subject": Vector3(0, 0.6, -3.2), "side": Vector3(0.35, 0, -1),
			"distance": 8.0, "height": 2.4, "yaw": 0.0, "delay": 0.35},
	&"rear_door": {"stories": ["fault_rear_door"], "subject": Vector3(0, 1.2, 4.0), "side": Vector3(0.45, 0, 1),
			"distance": 7.0, "height": 2.2, "yaw": 0.0, "delay": 0.7},
	&"mirror": {"stories": ["fault_mirror"], "subject": Vector3(-1.2, 1.6, -2.4), "side": Vector3(-1, 0, -0.8),
			"distance": 5.5, "height": 1.4, "yaw": 0.0, "delay": 0.4},
	&"box": {"stories": ["cargo_fell", "cargo_recovered"], "subject": "box", "side": Vector3.ZERO,
			"distance": 4.5, "height": 1.6, "yaw": 25.0, "delay": 0.1},
}
## Stories about a door, illustrated by the phone's photo of that door.
const DOOR_STORIES: Array[String] = ["photo", "delivered_ok", "complaint", "delivered_ruined"]

## story id -> Texture2D, this run's.
var photos: Dictionary = {}
## Shots asked for this run (taken or not), so a fact that repeats isn't shot twice.
var asked: Dictionary = {}
var _running: bool = false


func _ready() -> void:
	name = "NewsPhotographer"
	add_to_group(GROUP)
	EventBus.run_started.connect(_on_run_started)
	EventBus.run_ended.connect(func(_score: int, _results: Dictionary) -> void: _running = false)
	EventBus.route_event_started.connect(_on_route_event)
	EventBus.vehicle_fault_started.connect(func(fault_id: StringName, _at: Vector3) -> void: shoot(fault_id))
	EventBus.cargo_overboard.connect(func(_id: StringName, at: Vector3, _seconds: float) -> void:
		shoot(&"box", at))


static func find(tree: SceneTree) -> NewsPhotographer:
	return tree.get_first_node_in_group(GROUP) as NewsPhotographer if tree != null else null


func _on_run_started(_route: StringName, _players: Array) -> void:
	photos.clear()
	asked.clear()
	_running = true


func _on_route_event(event_id: StringName, event: Dictionary) -> void:
	if SHOTS.has(event_id) and bool(event.get("incident", false)):
		shoot(event_id)


## Takes the photo for `kind` (a key of SHOTS) once per run, after its delay.
## `at` is where a box is. Public for the tests.
func shoot(kind: StringName, at: Vector3 = Vector3.ZERO) -> void:
	if not _running or not SHOTS.has(kind) or asked.has(kind) or asked.size() >= MAX_PHOTOS:
		return
	asked[kind] = true
	if not PressPhoto.can_capture():
		return
	var shot: Dictionary = SHOTS[kind]
	await get_tree().create_timer(float(shot["delay"])).timeout
	var pose: Dictionary = pose_for(kind, at)
	if pose.is_empty() or not _running:
		return
	var image: Texture2D = await PressPhoto.capture(self, pose)
	if image != null:
		for story: String in shot["stories"]:
			photos[story] = image


## Where the camera stands for `kind`: framed around the van (or the box at
## `at`, looking at it from the far side so the van is behind). Empty with no van.
func pose_for(kind: StringName, at: Vector3 = Vector3.ZERO) -> Dictionary:
	var shot: Dictionary = SHOTS.get(kind, {})
	var vehicle := get_tree().get_first_node_in_group(&"vehicle") as Node3D if is_inside_tree() else null
	if shot.is_empty() or vehicle == null:
		return {}
	var subject: Vector3
	var side: Vector3
	if shot["subject"] is String:
		subject = at
		side = at - vehicle.global_position
	else:
		subject = vehicle.to_global(shot["subject"])
		side = vehicle.global_basis * (shot["side"] as Vector3)
	return PressPhoto.framing(subject, side, float(shot["distance"]), float(shot["height"]), float(shot["yaw"]))


## The photos for the stories of `paper` this peer has: entry id -> Texture2D.
func photos_for(paper: Dictionary) -> Dictionary:
	var found: Dictionary = {}
	for entry: Variant in [paper.get("front", {})] + Array(paper.get("stories", [])):
		if entry is not Dictionary:
			continue
		var id: String = String((entry as Dictionary).get("id", ""))
		var image: Texture2D = photos.get(id) as Texture2D
		if image == null and id in DOOR_STORIES:
			var house: int = int(((entry as Dictionary).get("slots", {}) as Dictionary).get("house", 0)) - 1
			image = RunManager.delivery_photos.get(house) as Texture2D
		if image != null:
			found[id] = image
	return found
