class_name CompanyLobbyMeta
extends RefCounted
## What Steam shows of the company in play (expansion D-2009, "Modo Empresa"): the lobby's
## company_name and company_day, and the player's rich presence, "Empresa <name> — día N" in this
## peer's language. CompanyRoot publishes it through NetSession.steam_presence (net_session module,
## NetSteamPresence), which writes it on Steam and only keeps it without Steam (ENet, CI).
##
## Pure: the company comes as a parameter (the CompanyState node, or null for none) and no autoload
## is named (lesson N-919), so a test hands it its own.
##
## Without an active company every key is still there, with "" as its value: NetSteamPresence
## takes "" as "remove this key" (deleteLobbyData on the lobby, an empty value for the rich
## presence, which Steam documents as removing it), so a lobby or a presence that showed a company
## stops showing it, where an empty dictionary would leave the old values up. An active company
## with no name (the default until it is named) has no company_name either, and its presence reads
## "Modo Empresa — día N" instead.
##
## Steam values are text: the day goes as str(day). The rich presence uses the "status" key with
## the text already translated: "steam_display" would need the line localised as tokens in a rich
## presence file uploaded to Steamworks, which this game doesn't have; "status" shows as it is in a
## friend's view of the game.

const COMPANY_STATE := preload("res://scripts/core/company/company_state.gd")
const NAME_KEY: String = "company_name"
const DAY_KEY: String = "company_day"
const PRESENCE_KEY: String = "status"
const PRESENCE_TEXT: String = "UI_COMPANY_PRESENCE"
const PRESENCE_TEXT_UNNAMED: String = "UI_COMPANY_PRESENCE_UNNAMED"
## At most this many characters of the name, without control characters: the presence line stays
## within Steam's 256 bytes for a value even at 4 bytes a character.
const MAX_NAME_CHARS: int = 48


## The lobby's data for `company`: {company_name, company_day} as text, "" for what isn't there
## (no active company: both; no name: company_name).
static func lobby_meta(company: COMPANY_STATE) -> Dictionary:
	if not _is_active(company):
		return {NAME_KEY: "", DAY_KEY: ""}
	return {NAME_KEY: shown_name(company), DAY_KEY: str(company.day)}


## The player's rich presence for `company`: {"status": presence_text()}.
static func rich_presence(company: COMPANY_STATE) -> Dictionary:
	return {PRESENCE_KEY: presence_text(company)}


## "Empresa <name> — día N" (UI_COMPANY_PRESENCE) in the current language, "Modo Empresa — día N"
## (UI_COMPANY_PRESENCE_UNNAMED) for a company with no name, "" without an active company.
static func presence_text(company: COMPANY_STATE) -> String:
	if not _is_active(company):
		return ""
	var shown: String = shown_name(company)
	if shown.is_empty():
		return String(TranslationServer.translate(PRESENCE_TEXT_UNNAMED)) % company.day
	return String(TranslationServer.translate(PRESENCE_TEXT)) % [shown, company.day]


## The company's name as Steam shows it: no control characters or surrounding spaces, at most
## MAX_NAME_CHARS characters.
static func shown_name(company: COMPANY_STATE) -> String:
	return company.company_name.strip_escapes().strip_edges().left(MAX_NAME_CHARS).strip_edges()


## Hands `presence` what Steam shows of `company`: the lobby's data when `as_host` (only the host's
## lobby says what is played there) and the rich presence always. null clears both.
static func publish(presence: NetSteamPresence, company: COMPANY_STATE, as_host: bool) -> void:
	if presence == null:
		return
	if as_host:
		presence.set_lobby_meta(lobby_meta(company))
	var lines: Dictionary = rich_presence(company)
	for key: String in lines:
		presence.set_rich_presence(key, lines[key])


static func _is_active(company: COMPANY_STATE) -> bool:
	return company != null and is_instance_valid(company) and company.is_active()
