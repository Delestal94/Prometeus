# world

Fixed data of the company map (expansion D-0220).

- `road_graph.tres` (`RoadGraph`, D-0304): the street graph, shed to Centro to Campo, about 12 km. Nodes carry their position (meters, X east, Z south, shed at the origin), `kind` (`junction|dead_end|gate`), the zone they lie in and, for a gate, the id of the `data/gates/` file that closes it. Streets are cubic Beziers: `out_handle` and `in_handle` are offsets from their end nodes (zero = straight), `width` is the full roadway, `surface` is `asphalt|gravel|dirt|cobble`, `segments` the kinds of piece laid along it (`RoadGraph.SEGMENT_SCRIPTS`), repeated to fill the length. Edit it by hand and run `tools/run-tests.sh road_graph`: the test names whatever is wrong (a street between nodes that do not exist, a node outside the zone it says, a crossing without a junction).
- `houses.tres` (D-0311) will list the delivery houses.
