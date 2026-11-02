class_name CompanyUi
extends RefCounted
## The company world's on-screen pieces, added in one call from CompanyRoot (so the root, past its line
## budget, N-985, grows by one line for all of them): the shed's event feed (D-1935) and the day's HUD (D-1903).
## A new piece of the company's screen joins here, not in CompanyRoot.


static func add_to(root: Node) -> void:
	ShedEventFeed.add_to(root)
	CompanyDayHud.add_to(root)
