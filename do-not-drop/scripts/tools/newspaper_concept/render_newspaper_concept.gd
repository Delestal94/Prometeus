extends SceneTree
## Art-direction study, not the N-606 cinematic. Reuses the actual depot
## kit, current rounded player, face layers and UiTheme fonts. No gameplay.
## GPU: Godot --path do-not-drop --resolution 1920x1080 --script
## res://scripts/tools/newspaper_concept/render_newspaper_concept.gd -- --out=<absolute dir>

const Kit = preload("res://scripts/gameplay/depot/depot_kit.gd")
const Appearance = preload("res://scripts/gameplay/player/player_appearance.gd")
const Face = preload("res://scripts/presentation/character_face.gd")
const ThemeKit = preload("res://scripts/ui/ui_theme.gd")
const STOCK_SHADER = preload("res://scripts/presentation/newspaper/newspaper_stock.gdshader")
const PHOTO_SHADER = preload("res://modules/press_photo/halftone.gdshader")
## Newsprint, not UI: warm grey stock and near-black ink instead of the
## interface's cream and navy.
const NEWS_STOCK: Color = Color("e6dcc6")
const NEWS_INK: Color = Color("2b2824")
## Body copy that fills the columns around the real stories. It is there for
## texture -- small, justified, grey -- so the page reads as a newspaper; the
## stories the crew made stay big and get their own close-up.
const FILLER: PackedStringArray = [
	"El concejo deliberante volvió a tratar el arreglo de la ruta provincial.",
	"Vecinos del barrio norte reclaman por el camión que pasa a toda hora.",
	"La cooperativa anunció cortes de luz programados para el jueves.",
	"El club local ganó por la mínima y sigue arriba en la tabla.",
	"La feria de los sábados suma puestos de dulces caseros y plantas.",
	"En la escuela técnica arrancan los talleres de soldadura para adultos.",
	"Desde el depósito aseguran que las demoras de la semana fueron excepcionales.",
	"El intendente inauguró un semáforo que todavía nadie respeta.",
	"La biblioteca popular recibe donaciones de libros y revistas viejas.",
	"Se recuerda a los conductores que la balanza de la entrada sigue rota.",
	"La cosecha viene demorada por las lluvias de fin de mes.",
	"El almacén de la esquina festejó cuarenta años con descuentos en yerba.",
]
const READING_DISTANCE: float = 1.6
const READING_TILT_DEGREES: float = 28.0

var world: Node3D
var camera: Camera3D
var chief: Node3D
var face: BoneAttachment3D
var skeleton: Skeleton3D
var paper: Node3D
var paper_page: SubViewport
var outer_page: SubViewport
var reading_targets: Array[Marker3D] = []
var overlay: Control
var out_dir: String = ""
var animate: bool = false
var frame_index: int = 0
var head_rotation: Quaternion
var head_read_rotation: Quaternion
var reading_labels: Array[Label] = []
var page_labels: Array[Label] = []
var motion_time: float = 0.0
var paper_rest_position: Vector3
var paper_rest_rotation: Vector3


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("This visual study requires GPU rendering.")
		quit(2)
		return
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out_dir = arg.trim_prefix("--out=")
		if arg == "--animate":
			animate = true
	if out_dir.is_empty():
		push_error("Pass --out=<absolute review directory>.")
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(out_dir)
	root.content_scale_size = Vector2i(1920, 1080)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	world = Node3D.new()
	# The export advances by rendered frames; game physics interpolation
	# would leave camera projection checks a physics tick behind the image.
	world.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	root.add_child(world)
	_build_room()
	_build_lights()
	_build_chief()
	await _build_paper()
	_build_grip()
	camera = Camera3D.new()
	camera.near = 0.04
	world.add_child(camera)
	camera.make_current()
	var layer := CanvasLayer.new()
	root.add_child(layer)
	overlay = Control.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(overlay)
	var morning_title := _overlay_label("A LA MAÑANA SIGUIENTE", Vector2(100, 76), 28, ThemeKit.PAPER)
	_overlay_label("Mantener para saltar", Vector2(1640, 1030), 21, ThemeKit.PAPER)
	_camera_at(Vector3(-1.75, 1.76, -2.8), Vector3(0, 1.25, 0.05), 43)
	await _save("01_oficina")
	# Finish in front of the face plane, above the spread. This clears the
	# oversized cartoon head while retaining both hands at the lower corners.
	var reading_camera := paper.global_position + Vector3(0, 1.16, 0.18)
	if animate:
		await _hold(1.0)
		morning_title.hide()
		await _orbit_to_reading(reading_camera)
	else:
		morning_title.hide()
		_camera_at(Vector3(-1.22, 1.55, -0.72), Vector3(0, 1.17, 0.24), 43)
		await _save("02_leyendo")
		_camera_at(Vector3(-0.91, 1.86, 0.95), paper.global_position, 43)
		await _save("03_sobre_hombro")
	_reading_camera_at(reading_camera)
	await _save("04_diario_completo")
	_check_reading_frame()
	_check_page_layout()
	_check_type_size("doble página de contexto", 12.0)
	if animate:
		await _hold(2.5)
	await _read_stories(reading_camera)
	face.call(&"set_expression", &"worried", &"surprised")
	_camera_at(Vector3(-0.65, 1.56, -1.9), Vector3(0, 1.28, 0.48), 30)
	if animate:
		await _lower_paper_slowly()
	else:
		_lower_paper()
	await _save("09_reaccion")
	if animate:
		await _hold(1.0)
	face.call(&"set_expression", &"sleepy", &"pout")
	_camera_at(Vector3(-0.7, 1.72, -3.5), Vector3(-0.68, 1.15, 0.18), 43)
	_results_card()
	await _save("10_resultados")
	if animate:
		await _hold(1.4)
	print("CONCEPT_COMPLETE: newsprint stock, guided reading, 30-second scene.")
	quit(0)


func _build_room() -> void:
	var kit := Kit.new(world)
	var steel := Kit.flat(Color("263238"), 0.68, 0.15)
	var plaster := Kit.flat(Color("b8c4ba"), 0.94)
	var wood := Kit.detailed(Color("b08a5a"), "wood_planks", 1.0)
	var blue := Kit.flat(Color("2f5d8a"))
	var yellow := Kit.flat(ThemeKit.YELLOW)
	kit.box(Vector3(6.2, 0.12, 5.0), Vector3(0, -0.06, 0), Kit.flat(Color("737a74")))
	kit.box(Vector3(6.2, 3.1, 0.12), Vector3(0, 1.55, 2.12), plaster)
	kit.box(Vector3(0.12, 3.1, 4.4), Vector3(3.06, 1.55, 0), plaster)
	kit.box(Vector3(6.1, 0.06, 0.04), Vector3(0, 1.02, 2.04), steel)
	kit.box(Vector3(6.1, 0.12, 0.04), Vector3(0, 0.08, 2.04), steel)
	# The window's dark mullions and half-drawn blind echo the actual mezzanine.
	kit.box(Vector3(0.12, 0.9, 4.4), Vector3(-3.06, 0.45, 0), plaster)
	kit.box(Vector3(0.12, 0.42, 4.4), Vector3(-3.06, 2.89, 0), plaster)
	var window_material := Kit.flat(Color("667d7e"), 0.9)
	kit.box(Vector3(0.03, 1.75, 4.35), Vector3(-3.08, 1.8, 0), window_material)
	kit.shadowless(window_material)
	for z: float in [-2.1, -0.65, 0.75, 2.1]:
		kit.box(Vector3(0.14, 1.8, 0.08), Vector3(-3.0, 1.8, z), steel)
	for y: float in [1.0, 2.65]:
		kit.box(Vector3(0.14, 0.08, 4.4), Vector3(-3.0, y, 0), steel)
	_model("sm_env_depot_office_blind", Vector3(-2.98, 1.45, -0.85), -PI / 2.0)
	_model("sm_env_depot_office_blind", Vector3(-2.98, 1.45, 0.42), -PI / 2.0)
	# The desk is the game's own imported piece, with dispatch equipment
	# cleared from its centre to leave space for the newspaper and the mate.
	var desk := _model("sm_env_depot_dispatch_desk", Vector3(0.0, 0, -0.26), PI)
	desk.scale = Vector3(1.65, 1, 1.25)
	var clear_props: Array[StringName] = [
		&"Keyboard", &"Keys", &"Mouse", &"Cradle", &"Mug", &"MugCoffee", &"Clip", &"Clipboard", &"ClipSheet",
	]
	for part: Node in desk.find_children("*", "MeshInstance3D", true, false):
		if String(part.name).begins_with("Monitor") or String(part.name).begins_with("Screen") \
				or String(part.name).begins_with("Scanner") or part.name in clear_props:
			(part as Node3D).hide()
	_model("sm_env_depot_desk_lamp", Vector3(-0.95, 0.765, -0.1), -0.2)
	_model("sm_env_depot_cork_board", Vector3(1.62, 0.15, 2.04))
	for index: int in 3:
		kit.box(Vector3(0.17, 0.22, 0.012), Vector3(1.36 + index * 0.26, 1.63 + (index % 2) * 0.08, 2.008),
				Kit.flat(ThemeKit.PAPER))
		for row: int in 3:
			kit.box(Vector3(0.10 - row * 0.014, 0.006, 0.002),
					Vector3(1.36 + index * 0.26, 1.66 + (index % 2) * 0.08 - row * 0.035, 1.999), steel)
	_model("sm_env_depot_wall_clock", Vector3(-1.58, 2.16, 2.005), PI).scale = Vector3.ONE * 0.36
	var hour := _model("sm_env_depot_clock_hand_hour", Vector3(-1.58, 2.16, 1.982), PI)
	hour.scale = Vector3.ONE * 0.36
	hour.rotation.z = -0.65
	var minute := _model("sm_env_depot_clock_hand_minute", Vector3(-1.58, 2.16, 1.98), PI)
	minute.scale = Vector3.ONE * 0.36
	minute.rotation.z = 1.1
	# Filing cabinet and modest shelf, with the depot's blue/yellow identity.
	kit.box(Vector3(0.68, 1.06, 0.65), Vector3(2.29, 0.53, 1.59), blue)
	for index: int in 3:
		kit.box(Vector3(0.61, 0.29, 0.028), Vector3(2.29, 0.18 + index * 0.33, 1.25), steel)
		kit.box(Vector3(0.17, 0.026, 0.04), Vector3(2.29, 0.27 + index * 0.33, 1.22), yellow)
	kit.box(Vector3(0.5, 0.08, 0.5), Vector3(0, 0.5, 0.6), steel)
	kit.box(Vector3(0.52, 0.58, 0.1), Vector3(0, 0.9, 0.95), blue)
	for x: float in [-0.22, 0.22]:
		kit.box(Vector3(0.045, 0.45, 0.045), Vector3(x, 0.23, 0.6), steel)
	# Mate and thermos: understated props at human scale, clear of the paper.
	kit.cylinder(0.067, 0.105, Transform3D(Basis.IDENTITY, Vector3(0.89, 0.827, -0.58)), wood)
	kit.cylinder(0.05, 0.01, Transform3D(Basis.IDENTITY, Vector3(0.89, 0.882, -0.58)), Kit.flat(Color("455038")))
	kit.cylinder(0.007, 0.19, Transform3D(Basis(Vector3.FORWARD, -0.2), Vector3(0.92, 0.96, -0.58)),
			Kit.flat(Color("adb6b5"), 0.3, 0.7), 8)
	var thermos: Node3D = load("res://assets/models/props/cargo/sm_prop_cargo_thermos.glb").instantiate()
	world.add_child(thermos)
	thermos.position = Vector3(1.08, 0.77, -0.05)
	thermos.scale = Vector3.ONE * 0.7
	# A shallow document tray and a pen give the cleared desk a working life.
	kit.box(Vector3(0.37, 0.012, 0.26), Vector3(-1.10, 0.786, -0.50), blue)
	for x: float in [-1.28, -0.92]:
		kit.box(Vector3(0.012, 0.05, 0.26), Vector3(x, 0.811, -0.50), blue)
	for z: float in [-0.625, -0.375]:
		kit.box(Vector3(0.37, 0.05, 0.012), Vector3(-1.10, 0.811, z), blue)
	for sheet: int in 3:
		kit.box(Vector3(0.29, 0.002, 0.21), Vector3(-1.10 + sheet * 0.003, 0.80 + sheet * 0.003, -0.5),
				Kit.flat(Color("dedbd0")))
	kit.cylinder(0.006, 0.19, Transform3D(Basis(Vector3.FORWARD, PI / 2), Vector3(-0.82, 0.789, -0.51)),
			steel, 8)
	kit.contact(Vector3(0, 0.006, -0.26), Vector2(2.8, 1.5))
	kit.contact(Vector3(0, 0.008, 0.6), Vector2(0.8, 0.8))
	kit.commit("OfficeStudy")


func _build_lights() -> void:
	var environment := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("303a3c")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("b5c4ca")
	env.ambient_light_energy = 0.38
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.fog_enabled = false
	environment.environment = env
	world.add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-35, -135, 0)
	sun.light_color = Color("ffdcb0")
	sun.light_energy = 0.40
	sun.shadow_enabled = false
	sun.directional_shadow_max_distance = 14.0
	world.add_child(sun)
	var key := SpotLight3D.new()
	world.add_child(key)
	key.position = Vector3(-1.65, 2.75, -1.6)
	key.look_at(Vector3(0, 1.04, 0.05))
	key.spot_range = 5.2
	key.spot_angle = 65
	key.light_color = Color("ffdcb0")
	key.light_energy = 0.24
	key.shadow_enabled = true
	var fill := OmniLight3D.new()
	fill.position = Vector3(0.5, 2.45, -1.6)
	fill.omni_range = 5.0
	fill.light_color = Color("c6d5df")
	fill.light_energy = 0.2
	world.add_child(fill)
	var lamp := OmniLight3D.new()
	lamp.position = Vector3(-0.93, 1.11, -0.27)
	lamp.omni_range = 1.3
	lamp.light_color = Color("ffe2b8")
	lamp.light_energy = 0.26
	world.add_child(lamp)


func _build_chief() -> void:
	chief = load("res://assets/models/characters/sm_char_player_rounded.glb").instantiate()
	world.add_child(chief)
	chief.position = Vector3(0, 0.48, 0.57)
	# An office shirt and a moustache set the chief apart from the crew,
	# who wear the same body in orange.
	Appearance.tint_shirt(chief, Color("7fa6c9"))
	skeleton = Appearance.find_skeleton(chief)
	face = Face.new()
	face.call(&"setup", chief, skeleton, 1)
	face.call(&"set_expression", &"sleepy", &"smile")
	face.set_process(false)
	_add_moustache()
	var animation: AnimationPlayer = Appearance.find_animation_player(chief)
	animation.play(&"Sit")
	animation.seek(0.8, true)
	animation.advance(0)
	animation.pause()
	var head := skeleton.find_bone("head")
	head_rotation = skeleton.get_bone_pose_rotation(head)
	var parent_basis := skeleton.global_basis * skeleton.get_bone_global_pose(skeleton.get_bone_parent(head)).basis
	var tilt_axis: Vector3 = parent_basis.inverse() * Vector3.RIGHT
	head_read_rotation = Quaternion(tilt_axis.normalized(), -0.22) * head_rotation
	skeleton.set_bone_pose_rotation(head, head_read_rotation)


func _build_paper() -> void:
	paper_page = _blank_page()
	outer_page = _blank_page()
	_inner_layout()
	_outer_layout()
	# An illustration made with the real hen model; explicitly a study, not
	# a captured event. Production photos will come from N-606.5.
	var photo := SubViewport.new()
	photo.size = Vector2i(900, 495)
	photo.own_world_3d = true
	photo.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(photo)
	var hen: Node3D = load("res://assets/models/cargo/contents/sm_cargo_content_hen.glb").instantiate()
	photo.add_child(hen)
	for part: Node in hen.find_children("*", "Node3D", true, false):
		if String(part.name).begins_with("Damage") or String(part.name).begins_with("Ruined"):
			(part as Node3D).hide()
	var pe := WorldEnvironment.new()
	pe.environment = Environment.new()
	pe.environment.background_mode = Environment.BG_COLOR
	pe.environment.background_color = Color("8e9688")
	pe.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	pe.environment.ambient_light_color = Color.WHITE
	pe.environment.ambient_light_energy = 0.55
	photo.add_child(pe)
	var pl := DirectionalLight3D.new()
	pl.rotation_degrees = Vector3(-35, -30, 0)
	pl.light_energy = 0.65
	photo.add_child(pl)
	var pc := Camera3D.new()
	photo.add_child(pc)
	pc.position = Vector3(0.7, 0.43, 0.9)
	pc.look_at(Vector3(0, 0.22, 0))
	pc.projection = Camera3D.PROJECTION_ORTHOGONAL
	pc.keep_aspect = Camera3D.KEEP_HEIGHT
	pc.size = 0.46
	pc.make_current()
	var picture := TextureRect.new()
	picture.position = Vector2(64, 576)
	picture.size = Vector2(600, 330)
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.texture = photo.get_texture()
	picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	var photo_material := ShaderMaterial.new()
	photo_material.shader = PHOTO_SHADER
	picture.material = photo_material
	paper_page.add_child(picture)
	for _i: int in 6:
		await process_frame
	paper = Node3D.new()
	world.add_child(paper)
	paper.position = Vector3(0, 1.18, -0.12)
	paper.rotation_degrees = Vector3(-60, 0, -1)
	paper_rest_position = paper.position
	paper_rest_rotation = paper.rotation_degrees
	var inner_print := _baked(paper_page)
	var outer_print := _baked(outer_page)
	# Four nested sheets, each with its own front/back. Shallow V at the
	# central fold; staggered lower edges make the stack visible in profile.
	for sheet: int in 4:
		for reverse: bool in [false, true]:
			var leaf := MeshInstance3D.new()
			leaf.mesh = _folded_sheet(sheet, reverse)
			var material := ShaderMaterial.new()
			material.shader = STOCK_SHADER
			material.set_shader_parameter("page_texture", outer_print if reverse else inner_print)
			material.set_shader_parameter("reverse_texture", inner_print if reverse else outer_print)
			material.set_shader_parameter("sheet_tint", 1.0 - sheet * 0.012)
			material.set_shader_parameter("self_light", 0.5)
			leaf.material_override = material
			paper.add_child(leaf)
	paper_page.render_target_update_mode = SubViewport.UPDATE_ONCE
	outer_page.render_target_update_mode = SubViewport.UPDATE_ONCE
	photo.render_target_update_mode = SubViewport.UPDATE_ONCE


## A mipmapped copy of a rendered page. Viewport textures have no mipmaps,
## so small type shimmered into dark noise on the sheet seen from afar.
func _baked(page: SubViewport) -> ImageTexture:
	var image := page.get_texture().get_image()
	image.generate_mipmaps()
	return ImageTexture.create_from_image(image)


func _blank_page() -> SubViewport:
	var page := SubViewport.new()
	page.size = Vector2i(2048, 1448)
	page.disable_3d = true
	page.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(page)
	var bg := ColorRect.new()
	bg.size = Vector2(page.size)
	bg.color = NEWS_STOCK
	page.add_child(bg)
	return page


## Inside spread, pages 2 and 3. A real paper's grid: running heads, section
## tags, columns with rules, a press photo with caption and boxed classifieds.
## The crew's stories are the big type; the filler only gives the page body.
func _inner_layout() -> void:
	_folio("2   ·   EL ECO DE TRES POZOS   ·   Miércoles 2 de octubre", 64.0, HORIZONTAL_ALIGNMENT_LEFT)
	_folio("Miércoles 2 de octubre   ·   EL ECO DE TRES POZOS   ·   3", 1080.0, HORIZONTAL_ALIGNMENT_RIGHT)
	# Page 2: the lead story.
	_section_tag("SOCIEDAD", Vector2(64, 112))
	_page_label("LA GALLINA CRUZÓ LA RUTA", Vector2(64, 168), Vector2(904, 230), 92, true)
	_story_body("«Viajaba sin correa», explicó el reparto.", Vector2(64, 404), Vector2(904, 150), 50)
	_page_rule(Vector2(64, 562), Vector2(904, 2))
	var caption := _page_label("La pasajera, antes del viaje. (Archivo)", Vector2(64, 914), Vector2(600, 48), 28)
	caption.add_theme_font_override("font", _serif(true))
	_story_body("El gallo pidió explicaciones. El depósito revisará correas.",
			Vector2(64, 972), Vector2(600, 260), 46)
	_page_rule(Vector2(64, 1244), Vector2(600, 1))
	_filler(Rect2(64, 1258, 290, 142), 0)
	_filler(Rect2(374, 1258, 290, 142), 3)
	_page_rule(Vector2(676, 576), Vector2(1, 824))
	_page_label("Piden un lomo de burro frente a la plaza", Vector2(688, 576), Vector2(280, 175), 32, true)
	_filler(Rect2(688, 760, 280, 640), 6)
	# Page 3: the repair, the weather column and the classifieds.
	_section_tag("OFICIOS", Vector2(1080, 112))
	_page_label("EL ESPEJO ERA UN CELULAR", Vector2(1080, 168), Vector2(600, 210), 76, true)
	_story_body("Un teléfono hizo de espejo. Funcionó… hasta que sonó.",
			Vector2(1080, 390), Vector2(600, 260), 46)
	_page_rule(Vector2(1080, 660), Vector2(600, 1))
	_filler(Rect2(1080, 672, 290, 228), 9)
	_filler(Rect2(1390, 672, 290, 228), 1)
	_page_rule(Vector2(1692, 112), Vector2(1, 788))
	_page_label("EL TIEMPO", Vector2(1704, 112), Vector2(280, 48), 34, true)
	_page_label("Sol, viento del sur y rutas secas. Ideal para cargas frágiles.",
			Vector2(1704, 166), Vector2(280, 200), 26)
	_page_rule(Vector2(1704, 376), Vector2(280, 1))
	_page_label("AGENDA", Vector2(1704, 390), Vector2(280, 48), 34, true)
	_filler(Rect2(1704, 446, 280, 454), 4)
	_page_rule(Vector2(1080, 914), Vector2(904, 3))
	var strip := ColorRect.new()
	strip.position = Vector2(1080, 928)
	strip.size = Vector2(904, 52)
	strip.color = NEWS_INK
	paper_page.add_child(strip)
	var strip_title := _page_label("CLASIFICADOS", Vector2(1080, 930), Vector2(904, 48), 36, true)
	strip_title.add_theme_color_override("font_color", NEWS_STOCK)
	strip_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_page_box(Rect2(1080, 996, 440, 250))
	_page_label("SE BUSCA GALLINA", Vector2(1100, 1008), Vector2(400, 60), 40, true)
	_story_body("Blanca y curiosa. Si la ve, avise al depósito.", Vector2(1100, 1070), Vector2(400, 168), 38)
	_page_box(Rect2(1544, 996, 440, 250))
	_page_label("TALLER EL REMIENDO", Vector2(1564, 1008), Vector2(400, 60), 38, true)
	_story_body("Reparamos casi todo. Casi.", Vector2(1564, 1070), Vector2(400, 168), 38)
	var small_ads: Array[String] = ["VENDO TERMO. Sin tapa, con historia.",
			"ALQUILO GALPÓN. Ideal camiones lentos.", "PERDÍ UN ESPEJO. Si suena, es mío."]
	for index: int in small_ads.size():
		var box := Rect2(1080 + index * 307, 1260, 290, 100)
		_page_box(box)
		_page_label(small_ads[index], box.position + Vector2(10, 6), Vector2(270, 90), 20)
	_page_rule(Vector2(1080, 1372), Vector2(904, 1))
	_page_label("Avisos: de lunes a viernes en la redacción.", Vector2(1080, 1380), Vector2(560, 34), 20)


## Outer sheet: the front page on the right half (what the office sees while
## the chief reads) and the back page of town ads on the left.
func _outer_layout() -> void:
	var masthead := _page_label("El Eco de Tres Pozos", Vector2(1080, 50), Vector2(904, 130), 84, true, outer_page)
	masthead.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_page_rule(Vector2(1080, 190), Vector2(904, 4), outer_page)
	_page_rule(Vector2(1080, 200), Vector2(904, 1), outer_page)
	var dateline := _page_label("Miércoles 2 de octubre   ·   Año XLI   ·   N.º 12.408   ·   $ 2,50",
			Vector2(1080, 208), Vector2(904, 40), 24, false, outer_page)
	dateline.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_page_rule(Vector2(1080, 252), Vector2(904, 1), outer_page)
	_page_label("UN REPARTO QUE DA QUE HABLAR", Vector2(1080, 272), Vector2(904, 220), 86, true, outer_page)
	_page_label("Historias de ruta, inventos de taller y una gallina con otros planes.",
			Vector2(1080, 500), Vector2(904, 110), 36, false, outer_page)
	_page_rule(Vector2(1080, 620), Vector2(904, 1), outer_page)
	var cover_photo := ColorRect.new()
	cover_photo.position = Vector2(1080, 636)
	cover_photo.size = Vector2(594, 380)
	cover_photo.color = Color("9a968c")
	outer_page.add_child(cover_photo)
	_filler(Rect2(1080, 1030, 290, 370), 2, outer_page)
	_filler(Rect2(1384, 1030, 290, 370), 5, outer_page)
	_page_rule(Vector2(1684, 636), Vector2(1, 764), outer_page)
	_filler(Rect2(1694, 636, 290, 764), 8, outer_page)
	_page_label("AVISOS DEL PUEBLO", Vector2(64, 50), Vector2(904, 90), 64, true, outer_page)
	_page_rule(Vector2(64, 150), Vector2(904, 4), outer_page)
	var titles: Array[String] = ["TALLER EL REMIENDO", "ALMACÉN DON POZO", "DEPÓSITO LOCAL",
			"SE ALQUILA CARRETILLA", "GOMERÍA LA RUEDA", "CLASES DE MANEJO"]
	var lines: Array[String] = ["Reparamos casi todo. Casi.", "Hoy: yerba, pan y buenas noticias.",
			"Los paquetes también tienen historias.", "Con una rueda y mucha voluntad.",
			"Atendemos pinchaduras y pinchados.", "Frene antes. Le va a ir mejor."]
	for index: int in titles.size():
		var box := Rect2(64 + (index % 2) * 462, 176 + int(index / 2.0) * 410, 442, 390)
		_page_box(box, outer_page)
		_page_label(titles[index], box.position + Vector2(16, 14), Vector2(410, 50), 32, true, outer_page)
		_page_label(lines[index], box.position + Vector2(16, 70), Vector2(410, 80), 28, false, outer_page)
		_filler(Rect2(box.position + Vector2(16, 160), Vector2(410, 214)), index * 2, outer_page)


func _folio(text: String, x: float, alignment: HorizontalAlignment) -> void:
	var label := _page_label(text, Vector2(x, 36), Vector2(904, 40), 24)
	label.horizontal_alignment = alignment
	_page_rule(Vector2(x, 84), Vector2(904, 3))
	_page_rule(Vector2(x, 92), Vector2(904, 1))


func _section_tag(text: String, at: Vector2) -> void:
	var tag := ColorRect.new()
	tag.position = at
	tag.size = Vector2(220, 44)
	tag.color = NEWS_INK
	paper_page.add_child(tag)
	var label := _page_label(text, at + Vector2(0, 2), Vector2(220, 40), 28, true)
	label.add_theme_color_override("font_color", NEWS_STOCK)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER


func _page_box(area: Rect2, target: SubViewport = null) -> void:
	_page_rule(area.position, Vector2(area.size.x, 2), target)
	_page_rule(area.position + Vector2(0, area.size.y - 2), Vector2(area.size.x, 2), target)
	_page_rule(area.position, Vector2(2, area.size.y), target)
	_page_rule(area.position + Vector2(area.size.x - 2, 0), Vector2(2, area.size.y), target)


## Small justified serif copy, cut at the last whole line that fits. Not in
## page_labels: it is meant to overflow and be trimmed.
func _filler(area: Rect2, first: int, target: SubViewport = null) -> void:
	const SIZE: int = 21
	const SPACING: int = -3
	var text := ""
	var index := first
	while text.length() < int(area.size.x * area.size.y / 170.0):
		text += FILLER[index % FILLER.size()] + " "
		index += 1
	var label := Label.new()
	label.position = area.position
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_FILL
	label.clip_text = true
	var font := _serif()
	label.add_theme_font_override("font", font)
	label.add_theme_font_size_override("font_size", SIZE)
	label.add_theme_constant_override("line_spacing", SPACING)
	label.add_theme_color_override("font_color", Color(NEWS_INK, 0.82))
	label.max_lines_visible = int(area.size.y / (font.get_height(SIZE) + SPACING))
	label.size = area.size
	label.text = text
	(target if target != null else paper_page).add_child(label)


## A system serif for body copy (the project ships only Lilita and Nunito);
## production would bundle one. Falls back to Nunito where none exists.
func _serif(italic: bool = false) -> Font:
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Georgia", "Times New Roman", "DejaVu Serif", "Liberation Serif", "serif"])
	font.font_italic = italic
	font.fallbacks = [ThemeKit.body_font(600)]
	return font


## Two flattened capsules under the nose, on the head bone so they follow
## every tilt. Placed with the face patch's own head shape.
func _add_moustache() -> void:
	var attach := BoneAttachment3D.new()
	attach.bone_name = "head"
	skeleton.add_child(attach)
	var bone := skeleton.find_bone("head")
	var head_rest: Transform3D = chief.global_transform.affine_inverse() * skeleton.global_transform \
			* skeleton.get_bone_global_rest(bone)
	var to_bone := head_rest.affine_inverse()
	var hair := Kit.flat(Color("4a2a17"), 0.9)
	for side: float in [-1.0, 1.0]:
		var capsule := CapsuleMesh.new()
		capsule.radius = 0.026
		capsule.height = 0.14
		var tuft := MeshInstance3D.new()
		tuft.mesh = capsule
		tuft.material_override = hair
		attach.add_child(tuft)
		var anchor: Vector3 = Face._patch_point(Vector2(0.5 - side * 0.055, 0.64))
		var lie := Basis(Vector3.BACK, side * (PI / 2.0 - 0.38)) * Basis.from_scale(Vector3(1.0, 1.0, 0.55))
		tuft.transform = to_bone * Transform3D(lie, anchor + Vector3(0, 0, -0.012))


func _paper_vertex(uv: Vector2, sheet: int = 0) -> Vector3:
	var x: float = (uv.x - 0.5) * (0.94 + sheet * 0.0017)
	var fold: float = absf(x) * 0.15
	var curl: float = pow(absf(x) / 0.47, 3.0) * 0.011 * sin(uv.y * PI)
	var ripple: float = sin(uv.x * 21.0 + uv.y * 11.0) * 0.0012
	var cross_fold: float = exp(-absf(uv.y - 0.51) * 65.0) * 0.0015
	# Held only along the bottom edge, the far outer corners flop back and
	# each half bellies a little between the fold and its edge.
	var reach: float = minf(absf(x) / 0.47, 1.0)
	var unheld: float = maxf(0.0, 1.0 - uv.y)
	var droop: float = -0.1 * reach * reach * unheld * unheld
	var belly: float = -0.006 * sin(reach * PI) * sin(clampf(uv.y, 0.0, 1.0) * PI)
	return Vector3(x, (0.5 - uv.y) * (0.66 + sheet * 0.0014),
			fold + curl + ripple + cross_fold + droop + belly - sheet * 0.0006)


func _folded_sheet(sheet: int, reverse: bool) -> ArrayMesh:
	var mesh := SurfaceTool.new()
	mesh.begin(Mesh.PRIMITIVE_TRIANGLES)
	for strip: int in 32:
		for row: int in 24:
			var uv00 := Vector2(float(strip) / 32.0, float(row) / 24.0)
			var uv11 := Vector2(float(strip + 1) / 32.0, float(row + 1) / 24.0)
			var uv01 := Vector2(uv00.x, uv11.y)
			var uv10 := Vector2(uv11.x, uv00.y)
			var triangles: Array[Vector2] = [uv00, uv10, uv01, uv10, uv11, uv01]
			if reverse:
				triangles.reverse()
			for uv: Vector2 in triangles:
				mesh.set_uv(Vector2(1.0 - uv.x, uv.y) if reverse else uv)
				var vertex := _paper_vertex(uv, sheet)
				vertex.z -= 0.0003 if reverse else 0.0
				mesh.add_vertex(vertex)
	mesh.generate_normals()
	return mesh.commit()


func _build_grip() -> void:
	for side: String in ["L", "R"]:
		var target := Marker3D.new()
		world.add_child(target)
		var sign_value: float = -1.0 if side == "L" else 1.0
		target.position = paper.to_global(_grip_vertex(sign_value))
		var bone: int = skeleton.find_bone("hand." + side)
		target.global_basis = (skeleton.global_basis * skeleton.get_bone_global_pose(bone).basis).orthonormalized()
		reading_targets.append(target)
		var solver := SkeletonIK3D.new()
		solver.root_bone = "upper_arm." + side
		solver.tip_bone = "hand." + side
		solver.override_tip_basis = true
		skeleton.add_child(solver)
		solver.target_node = target.get_path()
		solver.start(false)


func _lower_paper() -> void:
	paper.position.y = 0.87
	paper.rotation_degrees.x = -62
	skeleton.set_bone_pose_rotation(skeleton.find_bone("head"), head_rotation)
	for index: int in reading_targets.size():
		var sign_value: float = -1.0 if index == 0 else 1.0
		reading_targets[index].position = paper.to_global(_grip_vertex(sign_value))


func _lower_paper_slowly() -> void:
	var start := paper.position
	var start_rotation := paper.rotation_degrees
	for frame: int in 18:
		var t: float = smoothstep(0, 1, float(frame) / 17.0)
		paper.position = start.lerp(Vector3(start.x, 0.87, start.z), t)
		paper.rotation_degrees = start_rotation.lerp(Vector3(-62, 0, -1), t)
		skeleton.set_bone_pose_rotation(skeleton.find_bone("head"),
				head_read_rotation.slerp(head_rotation, t))
		for index: int in reading_targets.size():
			reading_targets[index].position = paper.to_global(_grip_vertex(-1.0 if index == 0 else 1.0))
		await _capture_motion_frame()


func _grip_vertex(sign_value: float) -> Vector3:
	# Just past the lower outer corners: the fingers close on the edge without
	# covering a column.
	return _paper_vertex(Vector2(-0.035 if sign_value < 0 else 1.035, 1.08))


func _model(asset: String, at: Vector3, yaw: float = 0) -> Node3D:
	var prop: Node3D = load(Kit.depot_model(asset)).instantiate()
	world.add_child(prop)
	prop.position = at
	prop.rotation.y = yaw
	return prop


func _page_label(text: String, at: Vector2, bounds: Vector2, size: int, display: bool = false,
		target: SubViewport = null) -> Label:
	var label := Label.new()
	label.position = at
	# Wrap mode, font and size before the text: with the text first, the label
	# grows to its unwrapped width at the default font and spills out of its column.
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_override("font", ThemeKit.display_font() if display else ThemeKit.body_font(600))
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", NEWS_INK)
	label.size = bounds
	label.text = text
	label.set_meta(&"bounds", bounds)
	(target if target != null else paper_page).add_child(label)
	page_labels.append(label)
	return label


func _story_body(text: String, at: Vector2, bounds: Vector2, size: int) -> void:
	reading_labels.append(_page_label(text, at, bounds, size))


func _page_rule(at: Vector2, bounds: Vector2, target: SubViewport = null) -> void:
	var line := ColorRect.new()
	line.position = at
	line.size = bounds
	line.color = NEWS_INK
	(target if target != null else paper_page).add_child(line)


func _overlay_label(text: String, at: Vector2, size: int, color: Color, outline: bool = true) -> Label:
	var label := Label.new()
	label.text = text
	label.position = at
	label.add_theme_font_override("font", ThemeKit.body_font(700))
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", ThemeKit.INK)
	label.add_theme_constant_override("outline_size", 6 if outline else 0)
	overlay.add_child(label)
	return label


func _results_card() -> void:
	var panel := Panel.new()
	panel.position = Vector2(1270, 230)
	panel.size = Vector2(550, 590)
	panel.add_theme_stylebox_override("panel", ThemeKit.surface_style(28))
	overlay.add_child(panel)
	var tape := ColorRect.new()
	tape.position = Vector2(1300, 258)
	tape.size = Vector2(490, 65)
	tape.color = ThemeKit.YELLOW
	overlay.add_child(tape)
	var title := _overlay_label("REPARTO TERMINADO", Vector2(1325, 269), 36, ThemeKit.INK, false)
	title.add_theme_font_override("font", ThemeKit.display_font())
	_overlay_label("El pueblo ya se enteró.", Vector2(1320, 355), 33, ThemeKit.INK, false)
	_overlay_label("ENTREGAS", Vector2(1320, 448), 25, ThemeKit.MUTED, false)
	_overlay_label("3 de 5", Vector2(1320, 486), 56, ThemeKit.INK, false)
	_overlay_label("Dos pedidos quedaron\nen el camino.", Vector2(1320, 588), 27, ThemeKit.INK, false)
	var button := Button.new()
	button.text = "VOLVER AL DEPÓSITO"
	button.position = Vector2(1310, 705)
	button.size = Vector2(470, 74)
	button.theme = ThemeKit.theme()
	button.add_theme_font_override("font", ThemeKit.display_font())
	button.add_theme_font_size_override("font_size", 32)
	button.add_theme_stylebox_override("normal", ThemeKit.surface_style(12, ThemeKit.MINT))
	overlay.add_child(button)


func _camera_at(at: Vector3, target: Vector3, fov: float) -> void:
	camera.position = at
	camera.look_at(target)
	camera.fov = fov


func _reading_camera_at(at: Vector3) -> void:
	camera.position = at
	camera.look_at(paper.global_position, paper.global_basis.y)
	camera.fov = 42


func _orbit_to_reading(end: Vector3) -> void:
	var start := camera.position
	var start_target := Vector3(0, 1.25, 0.05)
	var control_a := Vector3(-2.0, 1.9, -0.35)
	var control_b := Vector3(-1.15, 2.24, 1.1)
	for frame: int in 105:
		var t: float = smoothstep(0, 1, float(frame) / 104.0)
		var s: float = 1.0 - t
		camera.position = s * s * s * start + 3 * s * s * t * control_a \
				+ 3 * s * t * t * control_b + t * t * t * end
		var target := start_target.lerp(paper.global_position, t)
		camera.look_at(target, Vector3.UP.lerp(paper.global_basis.y, t).normalized())
		camera.fov = lerpf(43, 42, t)
		await _capture_motion_frame()
		if frame == 48:
			await _save("02_leyendo")
		if frame == 80:
			await _save("03_sobre_hombro")


func _read_stories(full_camera: Vector3) -> void:
	var views: Array[Dictionary] = [
		{"uv": Vector2(0.252, 0.483), "fov": 19.5,
			"move": 0.7, "hold": 5.5, "name": "05_noticia_gallina", "labels": [0, 1],
			"area": Rect2(64, 168, 904, 1064)},
		{"uv": Vector2(0.674, 0.282), "fov": 10.5,
			"move": 0.7, "hold": 5.0, "name": "06_noticia_espejo", "labels": [2],
			"area": Rect2(1080, 168, 600, 482)},
		{"uv": Vector2(0.748, 0.786), "fov": 10.5,
			"move": 0.6, "hold": 5.5, "name": "07_clasificados", "labels": [3, 4],
			"area": Rect2(1080, 928, 904, 420)},
	]
	for view: Dictionary in views:
		var target := paper.to_global(_paper_vertex(view.uv))
		# Nearly square to the sheet, leaning past the far edge so the chief's
		# head stays out of the narrow lens on the lower blocks.
		var away: Vector3 = paper.global_basis.z.normalized().rotated(paper.global_basis.x.normalized(),
				-deg_to_rad(READING_TILT_DEGREES))
		var position: Vector3 = target + away * READING_DISTANCE
		if animate:
			await _move_reading_camera(position, target, view.fov, view.move)
		else:
			camera.position = position
			camera.look_at(target, paper.global_basis.y)
			camera.fov = view.fov
		await _save(view.name)
		_check_type_size(view.name, 24.0, view.labels)
		_check_news_fit(view.name, view.area)
		if animate:
			await _hold(view.hold)
	if animate:
		await _move_reading_camera(full_camera, paper.global_position, 42.0, 0.8)
	else:
		_reading_camera_at(full_camera)
	await _save("08_diario_final")
	if animate:
		await _hold(1.2)


func _move_reading_camera(at: Vector3, target: Vector3, fov: float, seconds: float) -> void:
	var start := camera.position
	var start_rotation := camera.quaternion
	var end_rotation := Basis.looking_at((target - at).normalized(), paper.global_basis.y).get_rotation_quaternion()
	var start_fov := camera.fov
	var frames := int(seconds * 30)
	for frame: int in frames:
		var t: float = smoothstep(0, 1, float(frame) / float(frames - 1))
		camera.position = start.lerp(at, t)
		camera.quaternion = start_rotation.slerp(end_rotation, t)
		camera.fov = lerpf(start_fov, fov, t)
		await _capture_motion_frame()


func _hold(seconds: float) -> void:
	for _frame: int in int(seconds * 30):
		await _capture_motion_frame()


func _capture_motion_frame() -> void:
	# Fixed frame count, independent of render speed. Encode the PNG sequence
	# at 30 fps for a reproducible animatic, without recording setup frames.
	motion_time += 1.0 / 30.0
	face.call(&"_process", 1.0 / 30.0)
	chief.position.y = 0.48 + sin(motion_time * 1.65) * 0.0025
	if motion_time <= 4.5:
		var settle: float = 1.0 - smoothstep(3.8, 4.5, motion_time)
		paper.position = paper_rest_position + Vector3(0, sin(motion_time * 1.65) * 0.002 * settle, 0)
		paper.rotation_degrees = paper_rest_rotation + Vector3(0, 0, sin(motion_time) * 0.2 * settle)
		for index: int in reading_targets.size():
			reading_targets[index].position = paper.to_global(_grip_vertex(-1.0 if index == 0 else 1.0))
	await process_frame
	await RenderingServer.frame_post_draw
	var frame_dir := out_dir.path_join("frames")
	DirAccess.make_dir_recursive_absolute(frame_dir)
	var path := frame_dir.path_join("frame_%04d.png" % frame_index)
	var error := root.get_texture().get_image().save_png(path)
	if error != OK:
		push_error("Could not save motion frame: " + error_string(error))
		quit(2)
	frame_index += 1


func _check_reading_frame() -> void:
	var screen := root.get_visible_rect()
	var valid := true
	for uv: Vector2 in [Vector2.ZERO, Vector2(1, 0), Vector2(0, 1), Vector2.ONE]:
		var corner := paper.to_global(_paper_vertex(uv, 3))
		var projected := camera.unproject_position(corner)
		if camera.is_position_behind(corner) or not screen.grow(-24).has_point(projected):
			push_error("Reading frame crops newspaper corner: " + str(projected))
			valid = false
	if not valid:
		quit(2)
		return
	print("READING_FRAME: all four newspaper corners inside the viewport.")


func _check_page_layout() -> void:
	for label: Label in page_labels:
		var bounds: Vector2 = label.get_meta(&"bounds")
		if label.size.y > bounds.y + 1 or label.size.x > bounds.x + 1:
			push_error("Newspaper text overflows: %s (size %s, box %s)" % [label.text, label.size, bounds])
			quit(2)
	print("PAGE_LAYOUT: all labels fit their allocated space.")


func _check_news_fit(shot: String, area: Rect2) -> void:
	var screen := root.get_visible_rect().grow(-20)
	for point: Vector2 in [area.position, area.position + Vector2(area.size.x, 0),
			area.end, area.position + Vector2(0, area.size.y)]:
		var corner := paper.to_global(_paper_vertex(point / Vector2(paper_page.size)))
		if camera.is_position_behind(corner) or not screen.has_point(camera.unproject_position(corner)):
			push_error("News block clipped in %s: %s -> %s, screen %s." %
					[shot, point, camera.unproject_position(corner), screen])
			quit(2)
			return
	print("NEWS_FIT: complete article block visible in ", shot)


func _check_type_size(shot: String, minimum: float, indices: Array = []) -> void:
	var smallest: float = INF
	var output_height: float = root.get_texture().get_image().get_height()
	for index: int in reading_labels.size():
		if not indices.is_empty() and index not in indices:
			continue
		var label := reading_labels[index]
		var font_size: float = label.get_theme_font_size("font_size")
		var uv := label.position / Vector2(paper_page.size)
		var top := camera.unproject_position(paper.to_global(_paper_vertex(uv)))
		var bottom := camera.unproject_position(
				paper.to_global(_paper_vertex(uv + Vector2(0, font_size / 1448.0))))
		var pixels: float = top.distance_to(bottom) * output_height / root.get_visible_rect().size.y
		smallest = minf(smallest, pixels)
	if smallest < minimum:
		push_error("Text too small in %s: %.1f px (minimum %.1f)." % [shot, smallest, minimum])
		quit(2)
		return
	print("READABLE_TYPE: %s minimum %.1f px at %dp." % [shot, smallest, int(output_height)])


func _save(name: String) -> void:
	for _i: int in 12:
		await process_frame
	await RenderingServer.frame_post_draw
	var error: Error = root.get_texture().get_image().save_png(out_dir.path_join(name + ".png"))
	if error != OK:
		push_error("Could not save %s: %s" % [name, error_string(error)])
		quit(2)
	print("CONCEPT_FRAME: ", name)
