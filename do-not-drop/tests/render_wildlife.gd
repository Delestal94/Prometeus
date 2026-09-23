extends SceneTree
## Run (needs a GPU, not --headless):
##   Godot --path do-not-drop --script res://tests/render_wildlife.gd
## Review shots of the wildlife models: a lineup next to a 1.8 m post for
## scale, and close-ups. Saved to user://wildlife_*.png.

const MODELS := {
	"deer": ["res://assets/models/environment/wildlife/sm_env_animal_stag_rigged.glb", Vector3(0.0, 0.0, 0.0)],
	"rabbit": ["res://assets/models/environment/wildlife/sm_env_animal_rabbit.glb", Vector3(1.3, 0.0, 0.3)],
	"frog": ["res://assets/models/environment/wildlife/sm_env_animal_frog.glb", Vector3(1.9, 0.0, 0.3)],
	"bird": ["res://assets/models/environment/wildlife/sm_env_animal_bird.glb", Vector3(2.4, 0.0, 0.3)],
	"sign": ["res://assets/models/environment/signs/sm_env_sign_animal_crossing.glb", Vector3(-1.6, 0.0, 0.0)],
}
const SHOTS := [
	["lineup", Vector3(2.6, 1.3, 3.2), Vector3(0.5, 0.6, 0.0)],
	["deer", Vector3(1.6, 1.6, 1.9), Vector3(0.0, 1.0, 0.0)],
	["small", Vector3(2.1, 0.45, 1.1), Vector3(1.9, 0.1, 0.3)],
	["sign", Vector3(-1.6, 2.0, 2.4), Vector3(-1.6, 2.0, 0.0)],
]


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var world := Node3D.new()
	root.add_child(world)
	var environment := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.62, 0.74, 0.84)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.78, 0.84, 0.95)
	env.ambient_light_energy = 0.8
	environment.environment = env
	world.add_child(environment)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-50.0, -35.0, 0.0)
	light.light_energy = 1.5
	light.shadow_enabled = true
	world.add_child(light)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(20.0, 20.0)
	var grass := StandardMaterial3D.new()
	grass.albedo_color = Color(0.47, 0.6, 0.36)
	plane.material = grass
	ground.mesh = plane
	world.add_child(ground)
	for key: String in MODELS:
		var model := (load(MODELS[key][0]) as PackedScene).instantiate() as Node3D
		model.position = MODELS[key][1]
		model.rotation.y = -0.6 if key != "sign" else PI
		world.add_child(model)
	var camera := Camera3D.new()
	camera.fov = 55.0
	world.add_child(camera)
	for shot: Array in SHOTS:
		camera.position = shot[1]
		camera.look_at(shot[2])
		camera.make_current()
		await process_frame
		await process_frame
		await RenderingServer.frame_post_draw
		var path := "user://wildlife_%s.png" % shot[0]
		root.get_viewport().get_texture().get_image().save_png(path)
		print("RENDER: ", ProjectSettings.globalize_path(path))
	quit(0)
