# Aviso: módulo nuevo `world_cells` (D-0303, 2026-10-12)

Lo hizo Nacho (rutina `desarrollador`, carril 4). Zona compartida: `do-not-drop/modules/` y `docs/modulos.md`.

- **Nuevo** `modules/world_cells/` (`WorldCellGrid`, `WorldCellStreamer`): celdas cuadradas cargadas alrededor
  de anclas que se mueven, con histéresis, carga en hilo e instanciación en rebanadas. Sin dependencias.
- `CompanyTuning` suma `CELL_*` (sin cambiar nada existente). Nada del juego actual usa el módulo todavía.
- Slatex: no hay nada que hacer; si tocás `modules/`, `check_modules.py` corre como siempre.
