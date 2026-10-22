# Primera semana del modo Empresa (D-0130) — 2026-10-22

## Decisión
Diseño en `docs/expansion-distritos/diseno/onboarding.md`:
- **El día 1 es el tutorial** (no hay nivel ni día de práctica): 6 objetivos del bucle (`stock_pallet`, `pick`,
  `pack` con los pasos de `PackingTutorial`, `drive`, `deliver`, `return`). El día 1 abre con un pedido de 1
  producto y 1 unidad, sin sellos, a las 08:00, de lo que trae el palet regalado.
- **Del día 2 al 7 se enseña por disparador** (lo primero que lo hace necesario) con un día mínimo de calendario,
  no por columnas de 1 / 2 / 4 jugadores.
- **Una sola línea guía** en pantalla; el resto son notas de la Jefa o el Jefe en el feed de avisos.
- **El progreso es de cada jugador** (`UnlockManager.mark_tip_seen`, local): sin RPC, sin campo en
  `CompanyState`, sin opción del host. El veterano no ve la guía aunque juegue con alguien nuevo.
- `teaches_key` de los hitos 1 a 5 es **repaso**, no primera enseñanza: la tabla funciona en F1 sin hitos.
- El palet regalado no cambia (1 por producto): el pedido en espera del día 1 se enseña con una nota y lo
  resuelve el pedido sugerido (D-0151.3).

## Por qué
- `critico-diseno` marcó que el primer borrador prometía días por cantidad de jugadores que el calendario no
  permite (proveedor, rampa, eventos), objetivos que el host no ve (ventanas del cliente) y un objetivo común
  que dejaba a dos jugadores mirando el mismo paso. Los disparadores y el progreso por jugador lo resuelven con
  menos código.
- Guardar por empresa obligaba a un campo en el save, una línea más en el snapshot (`company_net.gd` está al
  tope) y una opción del host; `seen_tips` ya existe y es lo que usa el juego base.

## Qué cambia
- D-1901 construye `CompanyOnboarding` con este diseño; D-0412 escribe `teaches_key` como repaso; D-0801 / D-0812
  suman el pedido de las 08:00 del día 1.
