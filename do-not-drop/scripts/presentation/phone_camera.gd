extends CanvasLayer
class_name PhoneCamera
## The delivery photo. Pull the phone out with F and the screen becomes the
## phone's screen; the shutter files a photo against whichever door you just
## delivered to. The photo is worth a small bonus on its own, and it's the
## only thing that settles a complaint on the results screen -- a resident
## claiming the box arrived wrecked has no case against a photo of it
## sitting on their own porch.
##
## Deliberately self-contained. It borrows the active camera's pose into a
## camera of its own instead of touching player.gd (Slatex's file, see
## docs/colaboracion-equipo.md), and never writes the player's FOV, which
## _apply_context_fov() lerps every physics frame and would fight it. Drop
## this node into a level and it works; nothing else has to know it exists.

const PHONE_FOV: float = 52.0
## How far a door can be and still be the subject of the shot. Generous on
## purpose: you're standing on the porch when you take it, and being asked
## to find an exact spot would turn a joke into a chore.
const PHOTO_RANGE: float = 16.0
const FLASH_SECONDS: float = 0.28
## Thumbnails, not screenshots -- a handful of these live in memory until
## the results screen and then go away with the run.
const PHOTO_SIZE: Vector2i = Vector2i(384, 216)
## Darker than UiTheme.INK on purpose: this is the phone's body, not a panel.
const INK: Color = Color("0a1418")
const PAPER: Color = UiTheme.PAPER
const MINT: Color = UiTheme.MINT
const MUTED: Color = UiTheme.MUTED
const RED: Color = UiTheme.RED

var is_open: bool = false

var _camera: Camera3D
var _previous_camera: Camera3D
## The level's HUD, hidden while the phone is up: it's a different screen,
## and the run's cards would otherwise sit on top of the viewfinder and end
## up in every photo.
var _hud: CanvasLayer
var _frame: Control
var _status_label: Label
var _hint_label: Label
var _flash: ColorRect
var _shutter: AudioStreamPlayer
var _busy: bool = false


func _ready() -> void:
	layer = 5
	# Keeps running while paused so it can put itself away the moment a
	# pause starts -- otherwise the pause menu would open on a hidden HUD.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_camera()
	_build_ui()
	_shutter = AudioStreamPlayer.new()
	_shutter.stream = SynthAudio.camera_shutter()
	_shutter.volume_db = -6.0
	add_child(_shutter)
	EventBus.run_ended.connect(_on_run_ended)


func _on_run_ended(_score: int, _results: Dictionary) -> void:
	_close()


func _build_camera() -> void:
	_camera = Camera3D.new()
	_camera.name = "PhoneLens"
	_camera.fov = PHONE_FOV
	_camera.current = false
	add_child(_camera)


func _build_ui() -> void:
	_frame = Control.new()
	_frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_frame.visible = false
	add_child(_frame)

	# The phone's own body, drawn as a border around the whole screen: you
	# are looking at its screen, so the bezel is the frame of the shot.
	for side: String in ["top", "bottom", "left", "right"]:
		var bezel := ColorRect.new()
		bezel.color = Color(INK, 0.97)
		bezel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		match side:
			"top":
				bezel.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
				bezel.offset_bottom = 58
			"bottom":
				bezel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
				bezel.offset_top = -58
			"left":
				bezel.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)
				bezel.offset_right = 130
			_:
				bezel.set_anchors_and_offsets_preset(Control.PRESET_RIGHT_WIDE)
				bezel.offset_left = -130
		_frame.add_child(bezel)

	var top := HBoxContainer.new()
	top.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	top.offset_top = 16
	top.offset_left = 150
	top.offset_right = -150
	top.add_theme_constant_override("separation", 14)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_frame.add_child(top)
	_label(top, "● CÁMARA", 15, RED)
	_status_label = _label(top, "", 15, MUTED)
	_status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	# Framing brackets, so there's something to aim with instead of a bare
	# rectangle. Purely cosmetic: the shot is never actually cropped to them.
	for corner: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
		_bracket(corner)

	_hint_label = _label(_frame, "", 15, PAPER)
	_hint_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_hint_label.offset_top = -40
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_refresh_hint()

	_flash = ColorRect.new()
	_flash.color = Color(1, 1, 1, 0)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_flash)


func _refresh_hint() -> void:
	_hint_label.text = GameSettings.prompt(
		"[ Click ]  sacar foto        [ F ]  guardar el celular",
		"[ RB ]  sacar foto        [ LB ]  guardar el celular")


func _bracket(corner: Vector2) -> void:
	var length: float = 34.0
	var thickness: float = 3.0
	var inset := Vector2(200.0, 110.0)
	for horizontal: bool in [true, false]:
		var bar := ColorRect.new()
		bar.color = Color(PAPER, 0.7)
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bar.set_anchors_preset(Control.PRESET_CENTER)
		bar.anchor_left = 0.5 + corner.x * 0.5
		bar.anchor_right = bar.anchor_left
		bar.anchor_top = 0.5 + corner.y * 0.5
		bar.anchor_bottom = bar.anchor_top
		var size := Vector2(length, thickness) if horizontal else Vector2(thickness, length)
		bar.offset_left = -inset.x * corner.x - (size.x if corner.x > 0.0 else 0.0)
		bar.offset_top = -inset.y * corner.y - (size.y if corner.y > 0.0 else 0.0)
		bar.offset_right = bar.offset_left + size.x
		bar.offset_bottom = bar.offset_top + size.y
		_frame.add_child(bar)


func _label(parent: Node, text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", INK)
	label.add_theme_constant_override("outline_size", 6)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)
	return label


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"phone_toggle"):
		toggle()
		get_viewport().set_input_as_handled()
	elif is_open and event.is_action_pressed(&"phone_shutter"):
		shoot()
		get_viewport().set_input_as_handled()


func toggle() -> void:
	if is_open:
		_close()
	else:
		_open()


func _open() -> void:
	# On foot only, and never over a menu: the phone is something you pull
	# out standing at someone's door, not something to fiddle with mid-run
	# from the driver's seat.
	if is_open or get_tree().paused or Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	_previous_camera = get_viewport().get_camera_3d()
	if _previous_camera == null:
		return
	_match_lens(_previous_camera)
	_camera.global_transform = _previous_camera.global_transform
	_camera.current = true
	is_open = true
	_hud = get_parent().get_node_or_null(^"HUD") as CanvasLayer if get_parent() != null else null
	if _hud != null:
		_hud.visible = false
	_frame.visible = true
	_refresh_hint()
	_refresh_status()


func _close() -> void:
	if not is_open:
		return
	is_open = false
	_frame.visible = false
	_camera.current = false
	if _hud != null and is_instance_valid(_hud):
		_hud.visible = true
	_hud = null
	if _previous_camera != null and is_instance_valid(_previous_camera):
		_previous_camera.current = true


## Sees what the eyes it replaces see. The first-person camera culls the
## local player's own body (RenderLayers.LOCAL_BODY); a fresh Camera3D renders
## every layer, so without this the lens would be looking out from inside
## the player's head.
func _match_lens(source: Camera3D) -> void:
	_camera.cull_mask = source.cull_mask
	_camera.near = source.near
	_camera.far = source.far
	_camera.environment = source.environment
	_camera.attributes = source.attributes


func _process(_delta: float) -> void:
	if not is_open:
		return
	if get_tree().paused:
		_close()
		return
	if _previous_camera == null or not is_instance_valid(_previous_camera):
		_close()
		return
	# Tracks the player's own head rather than moving on its own: looking
	# around and walking keep working exactly as they do without the phone.
	_camera.global_transform = _previous_camera.global_transform
	_refresh_status()


## The door this shot would be filed against: the nearest house in range
## that's already been delivered to. Returns -1 when there's nothing here
## worth documenting.
func subject_house() -> int:
	var best: int = -1
	var best_distance: float = PHOTO_RANGE
	var origin: Vector3 = _camera.global_position
	for house: Node in get_tree().get_nodes_in_group(&"delivery_house"):
		if not bool(house.get(&"delivered")):
			continue
		var distance: float = origin.distance_to(house.call(&"porch_position"))
		if distance < best_distance:
			best_distance = distance
			best = int(house.get(&"house_index"))
	return best


func _refresh_status() -> void:
	var index: int = subject_house()
	if index < 0:
		_status_label.text = "sin entrega cerca"
		_status_label.add_theme_color_override("font_color", MUTED)
		return
	if _already_photographed(index):
		_status_label.text = "CASA %d  ·  ya documentada" % (index + 1)
		_status_label.add_theme_color_override("font_color", MUTED)
		return
	_status_label.text = "CASA %d  ·  listo para documentar" % (index + 1)
	_status_label.add_theme_color_override("font_color", MINT)


func _already_photographed(house_index: int) -> bool:
	for entry: Dictionary in RunManager.deliveries:
		if int(entry["house"]) == house_index:
			return bool(entry["photo"])
	return false


## Takes the shot. Public so a test can fire it without synthesising input.
func shoot() -> void:
	if _busy:
		return
	_busy = true
	var index: int = subject_house()
	var image: Texture2D = await _capture()
	var accepted: bool = index >= 0 and RunManager.attach_delivery_photo(index)
	if accepted and image != null:
		RunManager.delivery_photos[index] = image
	_shutter.play()
	_play_flash()
	if accepted:
		_hint_label.text = "Foto de la casa %d guardada. Ahora tenés con qué contestarles." % (index + 1)
	elif index >= 0:
		_hint_label.text = "Esa entrega ya estaba documentada."
	else:
		_hint_label.text = "Linda foto, pero no hay ninguna entrega que probar acá."
	_busy = false


## Grabs what the lens is actually seeing. The phone's own overlay is hidden
## for the frame being captured, otherwise every photo would come back with
## a picture of the phone's own bezel in it.
func _capture() -> Texture2D:
	var viewport: Viewport = get_viewport()
	if viewport == null:
		return null
	# Nothing is ever drawn headless, so frame_post_draw never fires and
	# awaiting it would hang forever. Taking the photo still has to count
	# there (tests, smoke checks) -- it just comes back with no image.
	if DisplayServer.get_name() == "headless":
		return null
	_frame.visible = false
	await RenderingServer.frame_post_draw
	var texture: ViewportTexture = viewport.get_texture()
	_frame.visible = is_open
	if texture == null:
		return null
	var image: Image = texture.get_image()
	if image == null or image.is_empty():
		return null
	image.resize(PHOTO_SIZE.x, PHOTO_SIZE.y, Image.INTERPOLATE_BILINEAR)
	return ImageTexture.create_from_image(image)


func _play_flash() -> void:
	var tween: Tween = create_tween()
	_flash.color.a = 0.0
	tween.tween_property(_flash, ^"color:a", 0.55, FLASH_SECONDS * 0.25)
	tween.tween_property(_flash, ^"color:a", 0.0, FLASH_SECONDS * 0.75)
