class_name BoxDefinition
extends Resource
## One empty box size of the packing table (expansion D-0217, "Modo Empresa").
##
## Data only, like SupplierDefinition: the cell grid a PackedBox packs into, what
## one empty box costs and the model the presentation scales to size_m(). The
## numbers mirror CompanyTuning.BOX_CELLS and BOX_COST (supuestos.md).

## Same as the file name in data/boxes/ and the key of CompanyTuning.BOX_CELLS.
@export var id: StringName = &""
## Cells along X, Y and Z, each CompanyTuning.GRID_CELL_M wide.
@export var cells: Vector3i = Vector3i.ONE
## What one empty box costs.
@export var cost: int = 0
## Box model; sm_cargo_box_cube.glb scaled until the D-1806 boxes exist.
@export var model: PackedScene


## Number of cells the box holds.
func volume() -> int:
	return cells.x * cells.y * cells.z


## Outer size in meters, what the model is scaled to.
func size_m() -> Vector3:
	return Vector3(cells) * CompanyTuning.GRID_CELL_M
