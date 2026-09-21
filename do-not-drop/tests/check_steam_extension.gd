extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/check_steam_extension.gd
## Reports whether the GodotSteam extension actually loaded and whether Steam
## itself is reachable. These are two different things: the extension can be
## installed correctly while Steam isn't running, and the game has to cope
## with that rather than fall over.

func _initialize() -> void:
	await process_frame
	var has_peer_class: bool = ClassDB.class_exists(&"SteamMultiplayerPeer")
	var has_singleton: bool = Engine.has_singleton(&"Steam")
	print("SteamMultiplayerPeer class: %s" % ("yes" if has_peer_class else "no"))
	print("Steam singleton:            %s" % ("yes" if has_singleton else "no"))

	var network: Node = root.get_node(^"/root/NetworkManager")
	var available: bool = bool(network.call(&"steam_available"))
	var choice: int = int(network.call(&"chosen_transport"))
	print("steam_available():          %s" % ("yes" if available else "no (Steam probably isn't running)"))
	print("AUTO transport picks:       %s" % ("STEAM" if choice == 1 else "ENET"))

	if not has_peer_class:
		print("FAIL: the extension is not loaded -- check addons/godotsteam/")
		quit(1)
		return
	print("PASS: extension loaded; transport choice is consistent with it")
	quit(0)
