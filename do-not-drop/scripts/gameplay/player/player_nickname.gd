class_name PlayerNickname
extends Node
## What the next-day newspaper calls this player (N-606.1), replicated with the
## rest of their appearance (player.tscn: "PlayerNickname:nickname", sent on
## spawn and on change, like the face). The owner copies it from their profile
## (UnlockManager.nickname, typed in the appearance panel); everyone else
## receives it. Cleaned on every write, so a remote peer can't put anything else
## in it; an empty one is the game's to fill with a funny name (Nickname.resolve).

const NICKNAME = preload("res://scripts/core/nickname.gd")

var nickname: String = "":
	set(value):
		nickname = NICKNAME.clean(value)


func _ready() -> void:
	var player: Node = get_parent()
	var profile: Node = get_node_or_null("/root/UnlockManager")
	if profile != null and player.has_method(&"is_local") and player.call(&"is_local"):
		_sync_from_profile()
		profile.progress_changed.connect(_sync_from_profile)


func _sync_from_profile() -> void:
	nickname = get_node("/root/UnlockManager").nickname


## The nickname of a player node (empty when it has none, or it isn't a player).
static func of(player: Node) -> String:
	var component: Node = player.get_node_or_null(^"PlayerNickname") if player != null else null
	return String(component.get(&"nickname")) if component != null else ""
