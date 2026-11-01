extends Node3D
## D-1902: what the player holds in the hand that is not a box, so the rest of the crew sees it
## (portapapeles.md §6). Today only the company's clipboard (CompanyClipboard): `&"clipboard_up"` while it
## is raised (F1); `&"clipboard"` is the lowered one of D-1004 and `&""` is nothing.
##
## `held_tool` is written only by the owning peer and replicated by player.tscn
## (`PlayerHeldTool:held_tool`, spawn + on change, so a late joiner gets it). No RPC. Not anim_state:
## PlayerAnimator writes that every frame.
##
## Pure presentation, drawn by every peer: a brown board of CLIPBOARD_SIZE hangs from a BoneAttachment3D
## on hand.R with the arm in its usual pose (the model is D-1816, the clip D-1840). The owner's body sits on
## RenderLayers.LOCAL_BODY and is culled from their first-person view, so the owner sees the 2D frame and
## nobody else does. The board is put away while the player sits or is knocked over (they own the rig).

const RenderLayers = preload("res://scripts/core/render_layers.gd")
const NONE: StringName = &""
const CLIPBOARD: StringName = &"clipboard"
const CLIPBOARD_UP: StringName = &"clipboard_up"
const HAND_BONE: StringName = &"hand.R"
## The clipboard's board, in metres (portapapeles.md §6).
const CLIPBOARD_SIZE: Vector3 = Vector3(0.23, 0.32, 0.01)
const CLIPBOARD_COLOR: Color = Color("8a5a2b")
## Where the board's centre rests, in the hand bone's frame (+Y along the fingers, -Z out of the palm).
const BOARD_IN_HAND: Vector3 = Vector3(0.0, 0.1, -0.03)

## What the hand holds (NONE, CLIPBOARD or CLIPBOARD_UP); see the class doc.
var held_tool: StringName = NONE

var _player: Player
var _skeleton: Skeleton3D
var _attachment: BoneAttachment3D
var _board: MeshInstance3D


func _ready() -> void:
	_player = get_parent() as Player


## True when the hand holds something.
func is_holding() -> bool:
	return held_tool != NONE


## The board while it is drawn (null otherwise).
func board() -> MeshInstance3D:
	return _board if _board != null and _board.visible else null


## Owner only: what its hand holds now. Nothing changes (and nothing goes out) when it is the same.
func set_held(what: StringName) -> void:
	if held_tool != what:
		held_tool = what


func _process(_delta: float) -> void:
	update_board()


## Builds the board the first time it is needed and shows it while something is held and the rig is free.
func update_board() -> void:
	var shown: bool = is_holding() and not _is_blocked()
	if not shown:
		if _board != null:
			_board.visible = false
		return
	if _board == null and not _build():
		return
	_board.visible = true


func _is_blocked() -> bool:
	if _player == null:
		return true
	return not _player.seat_node_path.is_empty() or _player._ragdolled


## The character is built by Player._ready, after this node's own: the skeleton is picked up when needed.
func _build() -> bool:
	if _player == null or _player._body_visual == null:
		return false
	_skeleton = PlayerAppearance.find_skeleton(_player._body_visual)
	if _skeleton == null or _skeleton.find_bone(HAND_BONE) < 0:
		return false
	_attachment = BoneAttachment3D.new()
	_attachment.name = "HeldToolHand"
	_attachment.bone_name = HAND_BONE
	_skeleton.add_child(_attachment)
	var mesh := BoxMesh.new()
	mesh.size = CLIPBOARD_SIZE
	var material := StandardMaterial3D.new()
	material.albedo_color = CLIPBOARD_COLOR
	mesh.material = material
	_board = MeshInstance3D.new()
	_board.name = "Clipboard"
	_board.mesh = mesh
	_board.position = BOARD_IN_HAND
	_attachment.add_child(_board)
	var layers: int = RenderLayers.LOCAL_BODY if _player.is_local() else RenderLayers.WORLD
	PlayerAppearance.set_layers(_board, layers)
	PlayerAppearance.enable_shadows(_board)
	return true


func _exit_tree() -> void:
	if _attachment != null and is_instance_valid(_attachment):
		_attachment.queue_free()
	_attachment = null
	_board = null
