# shed

The shed a new company starts with (expansion D-0911, D-0620): `default_shed.tres` is one DefaultShed resource with the pieces placed for free (shelves, packing tables, dispatch zone: ids of data/placeables/ and their cells), the shelf slots with their starting units, the supplier's first order (its pallets wait in reception) and the painted floor zones. Edit the cells and the stock here; `tests/test_company_default_layout.gd` checks every piece fits (inside the floor, off the dock and exit, no overlap, all reachable on foot).
