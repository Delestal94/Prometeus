# D-1901: guía de la primera semana del modo Empresa

- **Qué cambió:** arriba a la izquierda aparece una línea con el objetivo de ahora y su tecla
  (`CompanyOnboardingLine`). El día 1 recorre el bucle: guardar el palet, buscar en el estante, armar, manejar,
  entregar y volver. Del día 2 en adelante muestra bajar el palet del proveedor y sumar lo que faltó al pedido de
  mañana. Lo decide `CompanyOnboarding.current()`, una función pura, sobre la copia de cada máquina; sin RPC.
  Lo hecho queda en el perfil del jugador (`company_onboard_<id>`, `UnlockManager.mark_tip_seen`), no en la empresa.
- **Archivos sin dueño que cambian:**
  - `company_root.gd`: sin líneas nuevas. Un comentario de dos líneas pasa a una y `_ready()` llama a
    `CompanyOnboardingTracker.add_to(self)` (nodo `Onboarding` y capa `OnboardingLayer`).
  - `tests/test_company_bot_day.gd`: después de `return` comprueba que el bot tildó los 6 objetivos del día 1.
- **Qué lee de lo de Nacho (sin cambiarlo):** los `units_moved` de `CompanyNet`, los estados de los pedidos en
  `CompanyNet.orders.book` y en `CompanyTrips.book`, `CompanyTripsView.trip_closed`, `CompanyShed.pallets_in()` y
  `supplier_ordered`.
- **Qué tiene que hacer Nacho:** nada. Si la mesa o la puerta pasan a publicar eventos con el `peer`, armar y
  entregar pueden tildarse por jugador. Hoy los tilda la tripulación junta.
