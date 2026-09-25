extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_acoustic_space.gd
##
## Echo under a roof (N-402, acoustic_space.gd, acoustic_zone.gd):
## - a tunnel carries an AcousticZone from portal to portal: inside it the
##   listener is in a "tunnel", a step outside the portal they're in the open;
## - the depot's hall is a "roof";
## - the reverb switches on (tunnel: long and wet) on the world's buses while
##   the camera is in one, and off again outside -- RouteSky does it every frame;
## - #68: a camera anchored to the truck from outside (the chase view) is
##   outdoors, not inside the cab: the rain isn't the drumming-on-the-roof one.

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var tunnel := TunnelSegment.new()
	root.add_child(tunnel)
	await process_frame
	var zone := tunnel.get_node_or_null(^"AcousticZone") as AcousticZone
	_expect(zone != null, "The tunnel has an acoustic zone")
	_expect(AcousticSpace.listening_space(self, tunnel.to_global(Vector3(0.0, 1.7, -tunnel.length * 0.5))) == &"tunnel",
		"In the middle of the bore you're in the tunnel")
	_expect(AcousticSpace.listening_space(self, tunnel.to_global(Vector3(0.0, 1.7, 3.0))) == &"open",
		"Three metres out of the portal you're in the open")
	_expect(AcousticSpace.listening_space(self, tunnel.to_global(Vector3(0.0, 8.0, -tunnel.length * 0.5))) == &"open",
		"On top of the hill over it you're in the open")

	AcousticSpace.apply(&"tunnel")
	_expect(AcousticSpace.is_on(), "In a tunnel the reverb is on")
	for bus_name: StringName in AcousticSpace.BUSES:
		var bus: int = AudioServer.get_bus_index(bus_name)
		var reverb: AudioEffectReverb = null
		for index: int in range(AudioServer.get_bus_effect_count(bus)):
			var effect: AudioEffect = AudioServer.get_bus_effect(bus, index)
			if effect.resource_name == AcousticSpace.EFFECT_NAME:
				reverb = effect as AudioEffectReverb
		_expect(reverb != null and reverb.room_size > 0.9 and reverb.wet > 0.3, "%s gets the tunnel's long, wet echo" % bus_name)
	AcousticSpace.apply(&"open")
	_expect(not AcousticSpace.is_on(), "In the open the reverb is off")
	var effects_before: int = AudioServer.get_bus_effect_count(AudioServer.get_bus_index(&"SFX"))
	for repeat: int in range(5):
		AcousticSpace.apply(&"tunnel")
		AcousticSpace.apply(&"open")
	_expect(AudioServer.get_bus_effect_count(AudioServer.get_bus_index(&"SFX")) == effects_before, "Going in and out never stacks more reverbs")
	tunnel.queue_free()

	# The level: the camera in the depot's hall, then out in the yard.
	var network: Node = root.get_node(^"/root/NetworkManager")
	network.set(&"world_seed", 4242)
	network.set(&"world_house_count", 1)
	var level: Node = load("res://scenes/gameplay/level_base.tscn").instantiate()
	root.add_child(level)
	current_scene = level
	await process_frame
	var depot: Node3D = level.get(&"depot")
	var probe := Camera3D.new()
	level.add_child(probe)
	probe.global_position = depot.to_global(Vector3(0.0, 1.7, 20.0))
	probe.make_current()
	for frame: int in range(3):
		await process_frame
	_expect(AcousticSpace.current == &"roof" and AcousticSpace.is_on(), "In the depot the hall's echo is on (%s)" % AcousticSpace.current)
	probe.global_position = depot.to_global(Vector3(0.0, 1.7, -30.0))
	for frame: int in range(3):
		await process_frame
	_expect(AcousticSpace.current == &"open" and not AcousticSpace.is_on(), "Out in the yard it's off (%s)" % AcousticSpace.current)

	# #68: the chase camera hangs off the truck but looks at it from outside.
	var van: VehicleBody3D = level.get(&"vehicle")
	var presentation: Node = van.get_node(^"VehiclePresentation")
	var chase := presentation.get(&"spectator_camera") as Camera3D
	var sky: Node = level.find_child("Sky", true, false)
	if chase != null and sky != null:
		chase.global_position = van.to_global(Vector3(0.0, 3.0, 9.0))
		chase.make_current()
		await process_frame
		_expect(not bool(sky.call(&"_inside_vehicle", chase)), "A camera anchored to the truck from outside is outdoors")
		var seat := van.find_child("DriverCamera", true, false) as Camera3D
		if seat == null:
			for camera: Node in van.find_children("*", "Camera3D", true, false):
				if camera != chase and presentation.get(&"_seat_cameras").has(camera):
					seat = camera as Camera3D
					break
		if seat != null:
			seat.make_current()
			await process_frame
			_expect(bool(sky.call(&"_inside_vehicle", seat)), "A seat's camera is inside")
	else:
		_expect(false, "The truck has its chase camera and the level its sky")
	level.queue_free()
	await process_frame
	AcousticSpace.apply(&"open")
	network.set(&"world_seed", 0)
	network.set(&"world_house_count", 0)
	if _failures == 0:
		print("PASS: tunnels and the depot echo while you're in them, and outside cameras stay outdoors")
	quit(_failures)


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1
