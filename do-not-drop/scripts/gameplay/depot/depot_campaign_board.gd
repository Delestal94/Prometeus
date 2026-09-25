extends Node3D
class_name DepotCampaignBoard
## The depot tells the campaign so far (tareas de Nacho N-603):
##
##   - a factory sign by the door, "DÍAS SIN ACCIDENTES: N": one more "day"
##     for every run that ends with no box ruined, back to 0 the moment one
##     comes back broken (EventBus.run_ended's `cargo_ruined`), with the best
##     streak underneath;
##   - a wall of the delivery photos the crew took with the phone
##     (phone_camera.gd -> RunManager.delivery_photos), newest first, the last
##     MAX_PHOTOS of them, saved to disk when each run ends.
##
## Both live in user:// (LOG_PATH, PHOTO_DIR): every player keeps their own,
## like the rest of their profile -- the host doesn't hand its wall out, and a
## client that played the same runs counts the same days anyway, since it
## hears the same run_ended. Depot builds this in _ready (one line).

const LOG_PATH: String = "user://depot_log.json"
const PHOTO_DIR: String = "user://depot_photos"
const MAX_PHOTOS: int = 8
const DISPLAY_FONT: Font = preload("res://assets/fonts/LilitaOne-Regular.ttf")
const BODY_FONT: Font = preload("res://assets/fonts/Nunito-Variable.ttf")
const PAPER := Color("f4f1e6")
const INK := Color("263238")
const SAFETY_GREEN := Color("1f8a5b")
const CORK := Color("c9a26b")
## Sign: on the front wall's inner face, right of the door, facing inward.
const SIGN_AT := Vector3(6.6, 3.1, 0.17)
## Photo wall: on the right wall above the break area, facing -X, clear of
## the team's corkboard (depot.gd _build_team_board(), from z 21.4).
const WALL_AT := Vector3(14.92, 2.95, 19.9)
const WALL_SIZE := Vector2(2.3, 1.05)
const PHOTO_SIZE := Vector2(0.44, 0.3)
## A pushpin at each photo's top edge, in a few colours.
const PIN_COLORS: Array[Color] = [Color("d64541"), Color("2f7fc1"), Color("f2b632"), Color("3a9b5c")]
const PIN_RADIUS: float = 0.018

var days_label: Label3D
var best_label: Label3D
var photo_frames: Array[Sprite3D] = []
var _empty_note: Label3D


func _ready() -> void:
	_build_sign()
	_build_photo_wall()
	refresh()
	var bus: Node = get_node_or_null(^"/root/EventBus")
	if bus != null:
		bus.connect(&"run_ended", _on_run_ended)


## {"days": int, "best": int, "photos": [file names, newest first],
## "serial": the last photo number used}.
static func load_log() -> Dictionary:
	var log := {"days": 0, "best": 0, "photos": [], "serial": 0}
	if not FileAccess.file_exists(LOG_PATH):
		return log
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(LOG_PATH))
	if parsed is Dictionary:
		log["days"] = int((parsed as Dictionary).get("days", 0))
		log["best"] = int((parsed as Dictionary).get("best", 0))
		log["photos"] = ((parsed as Dictionary).get("photos", []) as Array).duplicate()
		log["serial"] = int((parsed as Dictionary).get("serial", 0))
	return log


static func save_log(log: Dictionary) -> void:
	var file := FileAccess.open(LOG_PATH, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(log))


## One run's worth: the streak goes on or back to 0, and the run's photos
## go up on the wall (the oldest come down past MAX_PHOTOS). Static so a
## test can feed it results without a depot.
static func record_run(results: Dictionary, photos: Dictionary) -> Dictionary:
	var log: Dictionary = load_log()
	if int(results.get("cargo_ruined", 0)) > 0:
		log["days"] = 0
	else:
		log["days"] = int(log["days"]) + 1
	log["best"] = maxi(int(log["best"]), int(log["days"]))
	var names: Array = log["photos"]
	DirAccess.make_dir_recursive_absolute(PHOTO_DIR)
	# A running number, not the clock: two runs can end in the same millisecond
	# (tests), and a name must never be reused while the old file is up.
	var serial: int = int(log.get("serial", 0))
	var houses: Array = photos.keys()
	houses.sort()
	for house: Variant in houses:
		# Textures from the phone; plain Images work too (tests: a headless
		# renderer can't read a texture back).
		var image: Image = photos[house] as Image
		if image == null and photos[house] is Texture2D:
			image = (photos[house] as Texture2D).get_image()
		if image == null or image.is_empty():
			continue
		serial += 1
		var file_name: String = "photo_%06d_casa%d.png" % [serial, int(house) + 1]
		if image.save_png(PHOTO_DIR.path_join(file_name)) == OK:
			names.push_front(file_name)
	while names.size() > MAX_PHOTOS:
		var gone: String = str(names.pop_back())
		DirAccess.remove_absolute(PHOTO_DIR.path_join(gone))
	log["photos"] = names
	log["serial"] = serial
	save_log(log)
	return log


func _on_run_ended(_score: int, results: Dictionary) -> void:
	var manager: Node = get_node_or_null(^"/root/RunManager")
	var photos: Dictionary = manager.get(&"delivery_photos") if manager != null else {}
	record_run(results, photos)
	refresh()


## Reads the log and redraws both boards.
func refresh() -> void:
	var log: Dictionary = load_log()
	days_label.text = str(int(log["days"]))
	best_label.text = tr("WORLD_DEPOT_BEST_STREAK") % int(log["best"])
	var names: Array = log["photos"]
	for index: int in range(photo_frames.size()):
		var frame: Sprite3D = photo_frames[index]
		var texture: Texture2D = null
		if index < names.size():
			var image := Image.load_from_file(ProjectSettings.globalize_path(PHOTO_DIR.path_join(str(names[index]))))
			if image != null and not image.is_empty():
				texture = ImageTexture.create_from_image(image)
		frame.texture = texture
		frame.visible = texture != null
		if texture != null:
			frame.pixel_size = PHOTO_SIZE.x / float(texture.get_width())
	_empty_note.visible = names.is_empty()


func _build_sign() -> void:
	var sign_root := Node3D.new()
	sign_root.name = "AccidentSign"
	sign_root.position = SIGN_AT
	add_child(sign_root)
	_box(sign_root, "Board", Vector3(2.2, 1.5, 0.04), Vector3.ZERO, PAPER)
	_box(sign_root, "Header", Vector3(2.2, 0.34, 0.05), Vector3(0.0, 0.58, 0.0), SAFETY_GREEN)
	_box(sign_root, "Counter", Vector3(0.9, 0.62, 0.05), Vector3(0.0, -0.1, 0.0), INK)
	_label(sign_root, "Title", tr("WORLD_DEPOT_DAYS_TITLE"), Vector3(0.0, 0.58, 0.035), 40, PAPER, DISPLAY_FONT)
	days_label = _label(sign_root, "Days", "0", Vector3(0.0, -0.1, 0.035), 110, Color("ffc93c"), DISPLAY_FONT)
	best_label = _label(sign_root, "Best", tr("WORLD_DEPOT_BEST_STREAK") % 0, Vector3(0.0, -0.58, 0.035), 30, INK, BODY_FONT)


func _build_photo_wall() -> void:
	var wall := Node3D.new()
	wall.name = "PhotoWall"
	wall.position = WALL_AT
	wall.rotation.y = -PI * 0.5
	add_child(wall)
	_box(wall, "Cork", Vector3(WALL_SIZE.x, WALL_SIZE.y, 0.03), Vector3.ZERO, CORK)
	_box(wall, "Frame", Vector3(WALL_SIZE.x + 0.08, WALL_SIZE.y + 0.08, 0.02), Vector3(0.0, 0.0, -0.01), Color("59656a"))
	_label(wall, "Title", tr("WORLD_DEPOT_PHOTOS_TITLE"), Vector3(0.0, WALL_SIZE.y * 0.5 + 0.12, 0.02), 30, INK, DISPLAY_FONT)
	_empty_note = _label(wall, "Empty", tr("WORLD_DEPOT_PHOTOS_EMPTY"), Vector3(0.0, 0.0, 0.03), 26, INK, BODY_FONT)
	# Four across, two rows, slightly askew like pinned photos.
	for index: int in range(MAX_PHOTOS):
		var column: int = index % 4
		var row: int = index / 4
		var frame := Sprite3D.new()
		frame.name = "Photo%d" % index
		frame.position = Vector3(-0.84 + column * 0.56, 0.22 - row * 0.44, 0.025)
		frame.rotation.z = deg_to_rad([-3.0, 2.0, -1.5, 3.5, 1.0, -2.5, 2.5, -1.0][index])
		frame.shaded = false
		frame.visible = false
		wall.add_child(frame)
		photo_frames.append(frame)
		# Pinned at the top: a child of the photo, so it shows and hides with it.
		var pin := MeshInstance3D.new()
		pin.name = "Pin"
		var head := SphereMesh.new()
		head.radius = PIN_RADIUS
		head.height = PIN_RADIUS * 2.0
		head.radial_segments = 8
		head.rings = 4
		var pin_material := StandardMaterial3D.new()
		pin_material.albedo_color = PIN_COLORS[index % PIN_COLORS.size()]
		pin_material.roughness = 0.35
		head.material = pin_material
		pin.mesh = head
		pin.position = Vector3(0.0, PHOTO_SIZE.y * 0.5 - 0.035, 0.012)
		pin.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		frame.add_child(pin)


func _box(parent: Node3D, node_name: String, size: Vector3, at: Vector3, color: Color) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.85
	mesh.material = material
	var node := MeshInstance3D.new()
	node.name = node_name
	node.mesh = mesh
	node.position = at
	parent.add_child(node)


func _label(parent: Node3D, node_name: String, text: String, at: Vector3, font_size: int, color: Color, font: Font) -> Label3D:
	var label := Label3D.new()
	label.name = node_name
	label.text = text
	label.font = font
	label.font_size = font_size
	label.pixel_size = 0.004
	label.modulate = color
	label.outline_size = 0
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.position = at
	parent.add_child(label)
	return label
