# D-1905: pantalla de cierre del día con hitos, sueldos y "Mañana:"

- **Qué cambió:**
  - `scripts/gameplay/company_root.gd` (Nacho): `_on_day_summary` le pasa al panel un cuarto argumento,
    `DayCloseReport.extras(net, day)` (los empleados de la empresa y los eventos de mañana). Sin líneas nuevas.
  - `DaySummaryPanel` (`scripts/ui/`) muestra debajo de la plata "Hitos del día", "Sueldos pagados" (una fila por
    empleado y el total) y una línea "Mañana:" por evento de víspera. Cada parte se esconde vacía: hoy, sin
    contratación ni hitos ni eventos del día, la pantalla se ve igual que antes.
  - Motivos del libro que el panel ya sabe nombrar: `wages` ("Sueldos"), `milestone:<id>` ("Hito: <nombre>") y
    `day_event:<id>` ("Evento: <nombre>"). El nombre sale de la clave `WORLD_MILESTONE_<ID>` /
    `WORLD_DAY_EVENT_<ID>` si está en la tabla; si no, del id.
- **Qué tiene que hacer Nacho:** al construir lo que falta, usar esos nombres y nada más.
  - Sueldos (D-1009): cobrar con motivo `wages`. Cada entrada de `CompanyState.employees` lleva `level` (id de
    `data/employees/`), y `name` y `wage` si los tiene.
  - Hitos (grupo 04): emitir `EventBus.milestone_reached` y pagar el premio con motivo `milestone:<id>`.
  - Eventos del día (D-0123): plata con motivo `day_event:<id>`. Los de víspera van en `extras.tomorrow` (lista
    de ids), desde `DayCloseReport.extras()`.
