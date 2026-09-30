extends NetStatsOverlay
## Take My Package's look for the net_session module's overlay (N-216,
## docs/modulos.md): the brand's body face and palette (UiTheme), and the
## state colours that follow the colour-blind setting. NetworkManager mounts
## it; F3 (`toggle_net_stats`) shows it.


func _theme() -> Dictionary:
	# The body face is loaded here rather than through UiTheme's static
	# cache: kept by this autoload's child, that cache outlived the scripts at
	# exit and every test that opened the overlay reported leaks.
	return {"font": load(UiTheme.BODY_FONT_PATH) as Font, "ink": UiTheme.INK, "paper": UiTheme.PAPER,
		"muted": UiTheme.MUTED, "title": UiTheme.SKY, "sim": UiTheme.YELLOW}


func _severity_color(severity: int) -> Color:
	var settings: Node = get_node_or_null(^"/root/GameSettings")
	var colorblind: bool = settings != null and bool(settings.get(&"colorblind_palette"))
	return UiTheme.state_color(severity, colorblind)
