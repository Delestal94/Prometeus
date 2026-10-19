# districts

The continuous company map (expansion, D-0220): ZoneDefinition (D-0205), gates and their requirements (D-0306), and next CompanyWorld (D-0214), the road graph (D-0304) and the adapter of modules/world_cells (D-0303).
Zones and gates are data in data/zones/ and data/gates/; adding a .tres adds content without touching code.

Road graph (D-0304): `road_graph.gd` (`RoadGraph`) is modules/route_gen's `RoadNetwork` with the game's data in `data/world/road_graph.tres` (nodes `junction|dead_end|gate`, Bezier streets with width, surface `asphalt|gravel|dirt|cobble` and the kinds of piece along them). `test_road_graph` checks it; `CompanyCells.pin_streets()` pins the cells under the main streets.

Trips (D-0302): `trip.gd` (`Trip`) is one trip out of the shed over an `OrderBook` (PACKED -> OUT at the start, undelivered -> FAILED at the end); `trip_gate.gd` (`TripGate`) is the shed gate as a line on the ground that tells when a vehicle crossed outward or inward. `test_company_trip` checks both; hooking them to the roller door is D-0302.1.

Dispatch rules (D-0309): `dispatch_rules.gd` (`DispatchRules`) answers whether a vehicle can load an order, from its zone and the gates that close it: water/altitude gates only the boat/plane crosses (even when open), barriers and gear gates need the milestone/equipment or to be open. The refusal carries a `WORLD_DISPATCH_NEEDS_*` key and its args for the dispatch board (D-0310). `test_company_dispatch_rules` checks it.

Houses (D-0311): `house_map.gd` (`HouseMap`) lists the 50 delivery houses of `data/world/houses.tres` (`house_spot.gd`, `HouseSpot`); `pick_for_day()` chooses which ones order from the seed and the day, `instance()` builds the game's own `DeliveryHouse` on its spot, `problems()` checks the list against the street graph and the zones. `test_company_houses` checks it.
