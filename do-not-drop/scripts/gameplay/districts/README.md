# districts

The continuous company map (expansion, D-0220): ZoneDefinition (D-0205), gates and their requirements (D-0306), and next CompanyWorld (D-0214), the road graph (D-0304) and the adapter of modules/world_cells (D-0303).
Zones and gates are data in data/zones/ and data/gates/; adding a .tres adds content without touching code.

Road graph (D-0304): `road_graph.gd` (`RoadGraph`) is modules/route_gen's `RoadNetwork` with the game's data in `data/world/road_graph.tres` (nodes `junction|dead_end|gate`, Bezier streets with width, surface `asphalt|gravel|dirt|cobble` and the kinds of piece along them). `test_road_graph` checks it; `CompanyCells.pin_streets()` pins the cells under the main streets.
