# F2 · Grupo 09 — Galpón construible (detalle)

> Carril 2 de la rutina `desarrollador`. Tareas de F2 del grupo 09 que se construyen de a una; el resto sigue
> en la tabla de [09-galpon-construible.md](../09-galpon-construible.md). Números de [supuestos.md](supuestos.md).

### D-0931 · Zona de carga para varios vehículos a la vez — B · Sonnet 5.5 · medium · Aviso: no · F2
**[~] ◐ Parcial (2026-10-22, PR pendiente)** — la lógica (D-0931.a): `DispatchBay` y `test_dispatch_bay`.
**Depende de:** D-0716 (`DispatchZone`), D-0717 (`DispatchLoading`)
**Qué:** con varios vehículos parados en la dársena, cada caja que espera en despacho (la más vieja primero) va al primer vehículo que la acepta.
- **D-0931.a (hecha) — la lógica.** `DispatchBay` (`scripts/gameplay/business/dispatch_bay.gd`, `RefCounted`): `plan()` reparte entre hasta `MAX_VEHICLES` (3) vehículos según `DispatchRules`, `cargo_slots` y `cargo_kg`; `load_bay()` deja la carga de cada uno en el portón (`CompanyTrips.stage_cargo`). Lo que nadie acepta sigue esperando con el motivo del primer vehículo que pasó las reglas pero estaba lleno (o el de las reglas).
- **D-0931.b (abierta) — el mundo.** Detectar qué vehículos están en la dársena y llamar a `load_bay()` desde el tablero de despacho (hoy carga de a uno con `DispatchLoading`); sitios de estacionamiento para varios (con D-0640).
**Test** `test_dispatch_bay`: desborde al segundo vehículo, reglas que eligen vehículo, caja que nadie acepta, tope de vehículos.
**Hecho cuando:** test de carga simultánea (D-0931.a); jugable cuando esté D-0931.b.

### D-0936 · Exterior del galpón que cambia con la etapa (cartel, playón) — B · Sonnet 5.5 · medium · Aviso: no · F2
**[x] Hecho (2026-10-22, PR pendiente)** — `ShedExteriorPlan` (datos) y `ShedExterior` (dibujo): 4 variantes de cartel y playón, una por etapa.
**Depende de:** D-0905 (etapas del galpón)
**Qué:** lo de afuera del galpón crece con la etapa, así se ve que la empresa creció antes de entrar.
- **Cartel** sobre el muro de la dársena (cara a +Z, hacia el patio), con el nombre de la etapa (`WORLD_SHED_SIGN_*`): galpón, depósito, centro de distribución, centro logístico. Ancho 4 / 6 / 8 / 11 m, nunca más que el muro.
- **Playón** (losa sin colisión) delante de la dársena: 2,5 / 4,5 / 6,5 / 8,5 m de fondo, más oscuro y pavimentado cuanto más grande; carriles pintados desde la etapa 3.
- **Faroles** en pares a los dos lados del portón de la dársena (0 / 2 / 4 / 6), nunca a menos de 3,5 m del eje, que es por donde retrocede el camión del proveedor.
- `CompanyShed.rebuild()` cuelga un `Exterior` por redibujo, así sigue la etapa en todos los peers sin red nueva (la etapa ya viaja con `shed_expanded` y el snapshot).
**Test** `test_shed_exterior`: una variante por etapa con su clave traducida; cartel, playón y faroles solo crecen; el cartel cabe en su muro; faroles dentro del ancho y fuera del carril del camión; el dibujo no tiene colisión; un redibujo deja un solo `Exterior` y sigue la etapa.
**Hecho cuando:** 4 variantes (cumplido; las capturas por etapa son D-0946).
Decisión: placeholder gris hecho por código (cajas y `Label3D`); el cartel y el playón de verdad están en `arte-pendiente/D-0936.md`.
