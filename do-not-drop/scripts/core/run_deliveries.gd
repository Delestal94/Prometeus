extends RefCounted
## Reading and filing the per-door delivery records of a run (N-225.5). Split out of run_manager.gd: the
## records themselves (`RunManager.deliveries`) stay on the autoload, which owns them and the RPCs around them;
## these are static helpers over that array and over the scene tree, so nothing here names an autoload (the
## autoload scripts compile before them, see package_autoloads.gd).

## The phone's own range plus some slack for the time the request travelled.
const PHOTO_REACH: float = 20.0


## Whether the resident actually got a box: not a house the run drove past
## (&"missed") nor an order closed empty because its box was left on the road
## (&"lost", N-213.4). Only those can earn a photo, a met deadline or care pay.
static func handed_over(outcome: StringName) -> bool:
	return outcome != &"missed" and outcome != &"lost"


## True when the box for `house_index` reached its door (see handed_over()).
static func delivered_at(deliveries: Array, house_index: int) -> bool:
	for entry: Dictionary in deliveries:
		if int(entry["house"]) == house_index:
			return handed_over(StringName(entry["outcome"]))
	return false


## Marks the door's record as photographed; false when there is nothing to file it against.
static func mark_photo(deliveries: Array, house_index: int) -> bool:
	for entry: Dictionary in deliveries:
		if int(entry["house"]) == house_index:
			# Nothing was delivered at a house the run drove past: there's
			# nothing for a photo to prove, and it used to earn the bonus.
			if bool(entry["photo"]) or not handed_over(StringName(entry["outcome"])):
				return false
			entry["photo"] = true
			return true
	return false


## Only a damaged delivery can have a complaint dismissed. Intact-delivery
## photos still earn their normal run bonus, but not the photo_saved merit.
static func claim_package_at(deliveries: Array, house_index: int) -> StringName:
	for entry: Dictionary in deliveries:
		if int(entry["house"]) != house_index:
			continue
		var outcome := StringName(entry["outcome"])
		if outcome in [&"delivered_at_risk", &"delivered_ruined"]:
			return StringName(entry["package_id"])
	return &""


## Whether the player owned by `peer_id` stands within PHOTO_REACH of that house's porch.
static func peer_near_house(tree: SceneTree, peer_id: int, house_index: int) -> bool:
	var house_position: Variant = null
	for house: Node in tree.get_nodes_in_group(&"delivery_house"):
		if int(house.get(&"house_index")) == house_index:
			house_position = house.call(&"porch_position")
	if house_position == null:
		return false
	for player: Node in tree.get_nodes_in_group(&"player"):
		if player.get_multiplayer_authority() == peer_id:
			return (player.call(&"reach_origin") as Vector3).distance_to(house_position) <= PHOTO_REACH
	return false
