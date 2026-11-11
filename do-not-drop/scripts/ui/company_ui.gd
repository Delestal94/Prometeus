class_name CompanyUi
extends RefCounted
## The company world's on-screen and presentation pieces (the day's HUD, the shed's feed, the arrows over the
## stations, the packing effects, the phone, the voices, the music by district...), added in one call from
## CompanyRoot, so the root (past its line budget, N-985) grows by one line for all of them. A new piece joins
## here, not in CompanyRoot; each piece's own script says what it is.


static func add_to(root: Node) -> void:
	ShedEventFeed.add_to(root)
	CompanyDayHud.add_to(root)
	ShedIndicators.add_to(root)
	PackingVfx.add_to(root)
	DistrictMusic.add_to(root)
	CompanyVoice.add_to(root)
	CompanyPhone.add_to(root)
