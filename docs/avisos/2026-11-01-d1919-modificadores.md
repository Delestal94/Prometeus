# D-1919: modificadores de la empresa (Armado asistido, Días tranquilos)

- **Qué cambió (diseño: `docs/expansion-distritos/diseno/dificultad.md` §6, puntos 1 a 3):**
  - `scripts/core/company/company_state.gd`: `options` (`assisted_packing`, `calm_days`, los dos apagados), con
    `option()`, `sanitize_options()` y `default_options()`. Va en `to_dict()` / `from_dict()` y, por eso, en el
    snapshot. Un save sin la clave carga los dos apagados. No sube la versión de `CompanySave`.
  - `scripts/core/company/company_save.gd`: `list_slots()` suma `"options"` a cada slot.
  - `scripts/core/company/company_table_net.gd`: con `assisted_packing`, el `box_tape` del host calcula
    `PackingStation.assisted_cells()` y `box_sealed` lleva `assisted` y `filled`. Cada copia rellena esas celdas
    (cobro con el minuto del host) y después pone la cinta. `_assist_ok()` rechaza un `filled` que no entra.
  - `scripts/gameplay/business/packing_station.gd`: `seal(wallet, fill = 0)` y `assisted_cells(money)`.
  - `scripts/gameplay/business/packed_box.gd`: `assisted` (va en `to_dict`). `box_to_package.gd`: una caja asistida
    absorbe como mínimo `CompanyTuning.ASSISTED_MIN_ABSORPTION` (0,75, nueva en `company_tuning.gd`).
  - `tests/test_company_shared_table.gd`: el contrato de campos de `box_sealed` suma `assisted` y `filled`.
- **Red:** `PROTOCOL_VERSION` 65 (`network_manager.gd`, zona compartida).
- **Qué tiene que hacer Nacho:** cuando exista el sorteo de eventos del día (D-0123), que no saque ninguno con
  `CompanyState.option("calm_days")`, ni el aviso de la víspera (dificultad.md §3). Lo demás no le pide nada.
