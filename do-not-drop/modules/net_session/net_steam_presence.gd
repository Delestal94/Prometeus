class_name NetSteamPresence
extends RefCounted
## What Steam shows of the game a NetSession plays: the data on the lobby it
## hosts (what a friend sees of the room, a lobby list) and the local player's
## rich presence (the friends list). Portable module (docs/modulos.md): the game
## says what (set_lobby_meta(), set_rich_presence()), this keeps it and writes
## it whenever Steam can take it. NetSession owns one (steam_presence).
##
## Without Steam -- ENet, CI, a build with no Steam client running -- a call
## only keeps what was asked: nothing is sent and nothing fails. Steam is never
## initialised from here (NetSession does that, and not in headless runs), so a
## test never touches the local Steam client.
##
## Steam takes text only: a value goes as str(value). "" removes its key, here
## and on Steam: deleteLobbyData on the lobby, and an empty rich presence value
## (SetRichPresence documents that "" removes the key). Only the lobby's owner,
## as Steam says (getLobbyOwner), may write its data: a client keeps what it is
## given and writes it if it ever hosts a lobby of its own.

## Steam's limits, in UTF-8 bytes without the terminator: a lobby value
## (k_cubChatMetadataMax, 8192) and a rich presence value
## (k_cchMaxRichPresenceValueLength, 256). Longer text is cut whole characters.
const MAX_LOBBY_VALUE_BYTES: int = 8191
const MAX_PRESENCE_VALUE_BYTES: int = 255

var _session: NetSession
## What the game wants its lobby to say, {key: text}, kept across sessions.
var _lobby_meta: Dictionary = {}
## The rich presence the game asked for, {key: text}.
var _presence: Dictionary = {}


func _init(session: NetSession) -> void:
	_session = session
	session.session_ready.connect(_on_session_ready)


## Merges `meta` into what this process's Steam lobby says: on the lobby now,
## if this process owns one, and on every lobby it hosts later, as soon as it
## exists (_on_session_ready()). Values go as text; "" forgets the key and
## deletes it from the lobby (deleteLobbyData).
func set_lobby_meta(meta: Dictionary) -> void:
	for raw_key: Variant in meta:
		var key: String = str(raw_key)
		var value: String = fit(str(meta[raw_key]), MAX_LOBBY_VALUE_BYTES)
		if value.is_empty():
			_lobby_meta.erase(key)
		else:
			_lobby_meta[key] = value
		if _owns_lobby():
			_write_lobby(key, value)


## What the lobby says, or will say once there is one: a copy, {key: text}.
func lobby_meta() -> Dictionary:
	return _lobby_meta.duplicate()


## One key of the local player's rich presence ("status" is the line Steam shows
## in the friend's game info); "" removes it. Set on Steam now if it is up, and
## again whenever a session starts with Steam up (it may have come up for it).
func set_rich_presence(key: String, value: String) -> void:
	var text: String = fit(value, MAX_PRESENCE_VALUE_BYTES)
	if text.is_empty():
		_presence.erase(key)
	else:
		_presence[key] = text
	if _steam_up():
		_steam().call(&"setRichPresence", key, text)


## The rich presence asked for: a copy, {key: text}.
func rich_presence() -> Dictionary:
	return _presence.duplicate()


## `text` cut to at most `max_bytes` of UTF-8, on a character boundary.
static func fit(text: String, max_bytes: int) -> String:
	if text.to_utf8_buffer().size() <= max_bytes:
		return text
	var cut: String = text.left(max_bytes)
	while cut.to_utf8_buffer().size() > max_bytes:
		cut = cut.left(-1)
	return cut


## A session started. With Steam up the rich presence goes again; on a Steam
## lobby this process just created, everything kept goes on it.
func _on_session_ready(is_host: bool) -> void:
	if not _steam_up():
		return
	for key: String in _presence:
		_steam().call(&"setRichPresence", key, _presence[key])
	if not is_host or not _owns_lobby():
		return
	for key: String in _lobby_meta:
		_write_lobby(key, _lobby_meta[key])


func _steam_up() -> bool:
	return is_instance_valid(_session) and _session._steam_ready and _session._steam != null


## This process hosts a Steam lobby right now (NetSession.lobby_id, set by
## _on_lobby_created and cleared when the session ends) and Steam says it owns
## it: a client whose peer already dropped counts as a host (is_host()) while
## its lobby_id is still set.
func _owns_lobby() -> bool:
	if not _steam_up() or _session.lobby_id == 0 or not _session.is_host():
		return false
	if _session.active_transport != NetSession.Transport.STEAM:
		return false
	var owner: int = int(_steam().call(&"getLobbyOwner", _session.lobby_id))
	return owner != 0 and owner == int(_steam().call(&"getSteamID"))


## One key on the owned lobby: its text, or deleted when "".
func _write_lobby(key: String, value: String) -> void:
	if value.is_empty():
		_steam().call(&"deleteLobbyData", _session.lobby_id, key)
	else:
		_steam().call(&"setLobbyData", _session.lobby_id, key, value)


func _steam() -> Object:
	return _session._steam
