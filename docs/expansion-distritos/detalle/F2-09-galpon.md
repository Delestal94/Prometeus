# F2 · Grupo 09 — Galpón construible (detalle)

> Carril 2 de la rutina `desarrollador`. Tareas de F2 del grupo 09 que se construyen de a una; el resto sigue
> en la tabla de [09-galpon-construible.md](../09-galpon-construible.md). Números de [supuestos.md](supuestos.md).

### D-0931 · Zona de carga para varios vehículos a la vez — B · Sonnet 5.5 · medium · Aviso: no · F2
**[~] ◐ Parcial (2026-10-22, PR pendiente)** — la lógica (D-0931.a): `DispatchBay` y `test_dispatch_bay`.
**Depende de:** D-0716 (`DispatchZone`), D-0717 (`DispatchLoading`)
**Qué:** con varios vehículos parados en la dársena, cada caja que espera en despacho (la más vieja primero) va al primer vehículo que la acepta.
- **D-0931.a (hecha) — la lógica.** `DispatchBay` (`scripts/gameplay/business/dispatch_bay.gd`, `RefCounted`): `plan()` reparte entre hasta `MAX_VEHICLES` (3) vehículos según `DispatchRules`, `cargo_slots` y `cargo_kg`; `load_bay()` deja la carga de cada uno en el portón (`CompanyTrips.stage_cargo`). Lo que nadie acepta sigue esperando con el motivo del primer vehículo que pasó las reglas pero estaba lleno (o el de las reglas).
- **D-0931.b (hecha, parcial) — el mundo.** `CompanyDispatch.bay_vehicles()` junta los vehículos de la flota en el patio, sin viaje ni carga puesta (hasta 3, `ctx["bay"]`); con dos o más el tablero muestra "Cargar todo (N vehículos)" (`DispatchBoardPanel.confirm_bay()` → `DispatchBay.load_bay()`, solo host; deja afuera los que `departure_verdict` no deja salir) y emite `loaded` una vez por vehículo. Decisión: botón aparte y el "Cargar" de siempre sigue cargando uno a mano, porque así lo elegido a mano no cambia. Abierto: sitios de estacionamiento para varios (con D-0640) y replicar la carga a los clientes (D-0310.c).
**Test** `test_dispatch_bay`: desborde al segundo vehículo, reglas que eligen vehículo, caja que nadie acepta, tope de vehículos.
**Hecho cuando:** test de carga simultánea (D-0931.a); jugable cuando esté D-0931.b.
