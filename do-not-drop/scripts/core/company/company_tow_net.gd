class_name CompanyTowNet
extends RefCounted
## The tow home over the network (expansion D-0307.1): any peer may ask for it, only the host does it.
##
## CompanyNet hands it the request (ask(), host only) and lives there as CompanyNet.tow. The rule is TripTow's and
## the world's part (the vehicle's state, the money, the trip, the teleport) is CompanyTow's, which sets `handler`
## on the host. This node only checks the data (rule 5) and gives back the refusal, or &"" when it was done:
##
##   trip_tow  {vehicle: a vehicle id, rid}  ->  no event of its own: the tow goes out as the events it already is,
##                                              wallet_moved {amount: -TOW_COST, reason: tow, ...} and trip_closed
##                                              {trip, vehicle, failed, minute} (rows 25 and 19 of red-autoridad.md)
##
## Refusals (the requester hears them, request_rejected): bad_data (a vehicle that is not a short id, or no world to
## do it), and TripTow's own, WORLD_TOW_NO_TRIP / WORLD_TOW_NOT_STUCK / WORLD_TOW_NO_MONEY, translation keys the HUD
## shows as they are. A client never writes the wallet nor the trip: it asks, as for any business request.

const ASK: StringName = &"trip_tow"
const REASON_BAD_DATA: StringName = &"bad_data"

## Host: the world's tow, Callable(vehicle_id: StringName) -> StringName: the refusal, or &"" when it was done.
## Unset (a world with no vehicles, or a client): every ask is bad_data.
var handler: Callable = Callable()


## Host: a trip_tow's refusal (&"" when the vehicle was towed home).
func ask(data: Dictionary) -> StringName:
	var vehicle: Variant = data.get("vehicle")
	if not CompanyAsk.is_id(vehicle) or not CompanyTrips.id_fits(StringName(vehicle)) or not handler.is_valid():
		return REASON_BAD_DATA
	return StringName(handler.call(StringName(vehicle)))
