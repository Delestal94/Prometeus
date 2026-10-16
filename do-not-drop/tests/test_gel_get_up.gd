extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_gel_get_up.gd
## S-311.50: face-up/down clip selection, timing and endpoint continuity.

const GetUp := preload("res://scripts/gameplay/player/gel/gel_get_up.gd")

var _failures: int = 0


func _initialize() -> void:
	var face_up_basis := Basis(Vector3.RIGHT, PI * 0.5)
	var face_down_basis := Basis(Vector3.RIGHT, -PI * 0.5)
	_expect(GetUp.select_clip(face_up_basis) == GetUp.FACE_UP,
		"local face direction toward the sky selects the face-up clip")
	_expect(GetUp.select_clip(face_down_basis) == GetUp.FACE_DOWN,
		"local face direction toward the floor selects the face-down clip")

	var fallen := Transform3D(Basis(Vector3.FORWARD, 0.8), Vector3(3.0, 0.4, -2.0))
	var standing := Transform3D(Basis.IDENTITY, Vector3(3.0, 1.0, -2.0))
	for clip: StringName in [GetUp.FACE_UP, GetUp.FACE_DOWN]:
		var start: Transform3D = GetUp.blend_pose(clip, &"pelvis", fallen, standing, 0.0)
		var finish: Transform3D = GetUp.blend_pose(clip, &"pelvis", fallen, standing, 1.0)
		_expect(start.is_equal_approx(fallen), "%s begins at the exact physical pose" % clip)
		_expect(finish.is_equal_approx(standing), "%s ends at the animation pose" % clip)

	var face_up_chest: float = GetUp.pose_weight(GetUp.FACE_UP, &"chest", 0.2)
	var face_up_shin: float = GetUp.pose_weight(GetUp.FACE_UP, &"shin.L", 0.2)
	_expect(face_up_chest > face_up_shin, "face-up recovery leads with the torso")
	var face_down_arm: float = GetUp.pose_weight(GetUp.FACE_DOWN, &"upper_arm.L", 0.2)
	var face_down_hips: float = GetUp.pose_weight(GetUp.FACE_DOWN, &"pelvis", 0.2)
	_expect(face_down_arm > face_down_hips, "face-down recovery plants the arms before the hips")

	if _failures == 0:
		print("PASS: face-up/down get-up clips preserve both endpoints and use distinct timing")
	quit(_failures)


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1
