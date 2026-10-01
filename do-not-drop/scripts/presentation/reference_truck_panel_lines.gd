class_name ReferenceTruckPanelLines
extends RefCounted
## Panel seams of the reference truck's body, made by ReferenceTruck once the
## model is hung: `build()` returns every strip it added.

## Panel lines (tareas de Nacho N-301): the thin dark seams where a real
## truck's panels meet -- round each cab door and each rear door leaf, the
## hood's shut line, and the joints of the cargo box's side sheets. A seam is
## a dark strip a hair proud of the panel's outer face (a "decal"), hung on the
## panel itself so it swings with its door; no collision anywhere.
const PANEL_LINES: Dictionary = {
	"CabDoorLower_Left": &"outline", "CabDoorLower_Right": &"outline",
	"RearDoor_Left": &"outline", "RearDoor_Right": &"outline",
	"FrontNose": &"hood", "CargoSide": &"joints", "CargoSide.001": &"joints", "CargoSide_001": &"joints",
}
const SEAM_WIDTH: float = 0.02
const SEAM_INSET: float = 0.02
const SEAM_PROUD: float = 0.002
const SIDE_JOINT_SPACING: float = 1.05
const SEAM_COLOR := Color(0.045, 0.05, 0.055)

var _vehicle: VehicleBody3D
var _model: Node3D
var _lines: Array[MeshInstance3D] = []


func _init(vehicle: VehicleBody3D, model: Node3D) -> void:
	_vehicle = vehicle
	_model = model


func build() -> Array[MeshInstance3D]:
	var seam := StandardMaterial3D.new()
	seam.resource_name = "PanelSeam"
	seam.albedo_color = SEAM_COLOR
	seam.roughness = 0.9
	for panel_name: String in PANEL_LINES:
		var panel := _model.find_child(panel_name, true, false) as MeshInstance3D
		if panel == null or panel.mesh == null:
			continue
		_seam_panel(panel, PANEL_LINES[panel_name], seam)
	return _lines


## `mode`: outline (all four edges), hood (the shut line across the top
## front and down both sides of the top), joints (vertical joints between
## the sheets of a long side).
func _seam_panel(panel: MeshInstance3D, mode: StringName, seam: Material) -> void:
	var box: AABB = panel.get_aabb()
	var size: Vector3 = box.size
	# The panel's thin axis is its face normal; the outer face is the one
	# away from the truck's middle.
	var normal_axis: int = 0 if size.x <= size.y and size.x <= size.z else (1 if size.y <= size.z else 2)
	if mode == &"hood":
		normal_axis = _axis_along(panel, Vector3.UP)
	var normal := Vector3.ZERO
	normal[normal_axis] = 1.0
	var middle: Vector3 = _vehicle.to_global(Vector3(0.0, 1.0, 0.0))
	var centre_world: Vector3 = panel.global_transform * box.get_center()
	if (centre_world - middle).dot(panel.global_basis * normal) < 0.0:
		normal = -normal
	var scale: float = maxf(panel.global_basis.get_scale().x, 0.001)
	var width: float = SEAM_WIDTH / scale
	var inset: float = SEAM_INSET / scale
	var face: Vector3 = box.get_center() + normal * (size[normal_axis] * 0.5 + SEAM_PROUD / scale)
	var axes: Array[int] = [0, 1, 2]
	axes.erase(normal_axis)
	var a: int = axes[0]
	var b: int = axes[1]
	var lines: Array = []  # [centre, along-axis, length]
	match mode:
		&"outline":
			for sign_b: float in [-1.0, 1.0]:
				var offset := Vector3.ZERO
				offset[b] = sign_b * (size[b] * 0.5 - inset)
				lines.append([face + offset, a, size[a] - inset * 2.0])
			for sign_a: float in [-1.0, 1.0]:
				var offset := Vector3.ZERO
				offset[a] = sign_a * (size[a] * 0.5 - inset)
				lines.append([face + offset, b, size[b] - inset * 2.0])
		&"hood":
			# Across the front edge of the top, and back along both sides.
			var across: int = _axis_along(panel, Vector3.RIGHT)
			var along: int = a if a != across else b
			var front_dot: float = (panel.global_basis * _unit(along)).dot(-_vehicle.global_basis.z)
			var front_sign: float = 1.0 if front_dot > 0.0 else -1.0
			var front := Vector3.ZERO
			front[along] = front_sign * (size[along] * 0.5 - inset * 3.0)
			lines.append([face + front, across, size[across] - inset * 4.0])
			for sign_x: float in [-1.0, 1.0]:
				var offset := Vector3.ZERO
				offset[across] = sign_x * (size[across] * 0.5 - inset * 2.0)
				lines.append([face + offset, along, size[along] - inset * 6.0])
		&"joints":
			var vertical: int = _axis_along(panel, Vector3.UP)
			var lengthwise: int = a if a != vertical else b
			var count: int = maxi(1, floori(size[lengthwise] * scale / SIDE_JOINT_SPACING))
			for index: int in range(1, count):
				var offset := Vector3.ZERO
				offset[lengthwise] = -size[lengthwise] * 0.5 + size[lengthwise] * float(index) / float(count)
				lines.append([face + offset, vertical, size[vertical] - inset * 2.0])
	for line: Array in lines:
		var strip := MeshInstance3D.new()
		strip.name = "PanelLine"
		var mesh := BoxMesh.new()
		var dims := Vector3.ONE * width
		dims[int(line[1])] = maxf(float(line[2]), width)
		dims[normal_axis] = SEAM_PROUD / scale
		mesh.size = dims
		mesh.material = seam
		strip.mesh = mesh
		strip.position = line[0]
		strip.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		panel.add_child(strip, true)
		_lines.append(strip)


## Which of the panel's local axes points most along `world_direction`.
func _axis_along(panel: Node3D, world_direction: Vector3) -> int:
	var best: int = 0
	var best_dot: float = -1.0
	for axis: int in range(3):
		var d: float = absf((panel.global_basis * _unit(axis)).normalized().dot(world_direction))
		if d > best_dot:
			best_dot = d
			best = axis
	return best


func _unit(axis: int) -> Vector3:
	var v := Vector3.ZERO
	v[axis] = 1.0
	return v
