extends SteamVoice
## Proximity voice, Steam only (N-212), on the net_session module's
## SteamVoice (docs/modulos.md): this file is only what the game decides --
## the general switch and push-to-talk live in GameSettings, and the session
## is NetworkManager.
##
## LAN/ENet has no voice (N-212.4, decided with critico-diseno in N-704.3):
## an AudioEffectCapture + encoder path would double the bugs in the feature
## that was the number one complaint in both reference games. Over LAN the
## crew is in the same room anyway.
##
## Playback (AudioStreamPlayer3D at each player's head, N-212.2) is the next
## slice: until then received packets are handed out through `voice_received`.


func _ready() -> void:
	super()
	session = get_node_or_null(^"/root/NetworkManager") as NetSession


## Off never records and never plays (N-212.3).
func _voice_enabled() -> bool:
	return _settings_bool(&"voice_chat_enabled", false)


## Push-to-talk is the default (critico-diseno, N-704.3); off means open mic.
func _push_to_talk() -> bool:
	return _settings_bool(&"voice_push_to_talk", true)


func _settings_bool(property: StringName, fallback: bool) -> bool:
	var settings: Node = get_node_or_null(^"/root/GameSettings")
	if settings == null:
		return fallback
	return bool(settings.get(property))
