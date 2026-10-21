# F5 · Grupo 20 — Red, calidad y bots de carga (detalle)

> Las tareas de **Ampliación** del grupo 20 ([20-red-calidad-lanzamiento.md](../20-red-calidad-lanzamiento.md))
> con el formato de [README.md](README.md). Se apoyan en lo que dejó el núcleo de F0: `CompanyNet` (eventos
> con `seq`, snapshot), `bot_company_day` (D-2016), `bench_company` (D-2011) y la medición de ancho de banda
> (D-2002). Dueño: Nacho, todas. Detalladas el 2026-10-21 (carril 5, sin tarea tomable).

### D-2021 · Mala conexión con el galpón lleno — B · Opus 5.5 · medium · Aviso: no · F5
**Depende de:** D-2003, D-2004, D-2006, D-2016
**Qué:** el perfil estándar de N-216 (`--net-sim=standard`: 150 ms, ±20 ms, 2 % de pérdida) aplicado al
modo Empresa con un cliente ENet local y el galpón lleno (todas las estaciones de la disposición por
defecto, estantes con stock, 20 pedidos abiertos).
- Los eventos de `CompanyNet` van por RPC confiable: la pérdida solo los atrasa. Lo que hay que probar es
  que el atraso no rompe nada: un `units_take` que llega cuando otro ya vació el estante se rechaza
  (`_rejected`) y el cliente no queda con unidades fantasma en la mano.
- Para la pérdida y el atraso en LAN se usa el retenedor de `NetworkManager.pose_net_sim()` /
  `TenderInputLag` (los mismos números de `--net-sim`): una cola en el test que entrega los `_request` del
  cliente con `lag` + 0..`jitter` ms. No hace falta Steam.
- [ ] **D-2021.1** Test con el host y un cliente en el mismo proceso (como `test_company_rejoin`): 200
  peticiones mezcladas (`units_take`, `units_store`, `units_drop`, armado de mesa) con el atraso del perfil
  estándar, dos jugadores peleando por el mismo estante.
- [ ] **D-2021.2** Una caída de 3 s a mitad (sin paquetes en ninguna dirección): al volver, si hay salto de
  `seq` el cliente pide snapshot (D-2004) y termina igual al host.
**Test** `test_company_bad_connection`: al final `CompanyState.to_dict()` y `Inventory.to_dict()` del
cliente son iguales a los del host; ninguna unidad se duplicó ni se perdió (la suma de todas las
estaciones, manos y `floor:<n>` es la del arranque más lo recibido); cero `ERROR` en la salida.
**Hecho cuando:** el test pasa con el perfil estándar y con 300 ms / 5 %.

### D-2023 · Bot de 8 jugadores simulados — B · Opus 5.5 · high · Aviso: sí (`.github/workflows/`) · F5
**Depende de:** D-2016, D-2017, D-2002
**Qué:** `tests/bot_company_load.gd` (`extends SceneTree`, no es `test_*`): un host y 7 clientes ENet en
procesos separados (como `net_trio.gd` + `tools/run-net-trio.sh`), cada uno con un actor que hace lo que
haría una persona en el galpón: toma pedidos, busca unidades, arma cajas, despacha. Se reparten las
estaciones por número de peer para que no se pisen todo el tiempo, y un 20 % de las acciones va a la
estación de otro a propósito.
- [ ] **D-2023.1** Script de lanzamiento `tools/run-company-load.sh` (8 procesos, timeout duro de 10 min,
  junta las salidas).
- [ ] **D-2023.2** Cada proceso imprime al cierre del día `LOAD peer=<n> hash=<hash de to_dict()>
  kbps_in=<> kbps_out=<> errors=<n>`; el script compara los hashes.
- [ ] **D-2023.3** Workflow nocturno nuevo `company-load.yml` (cron diario, `workflow_dispatch`), no es un
  check requerido; si falla abre o comenta un issue `test-inestable` con las líneas `LOAD` (lo sigue
  `ingeniero-ci`).
**Test** `test_company_load_script`: corre el script con 3 procesos y un día recortado (5 min de juego) y
comprueba que los hashes coinciden y que el script falla si uno no coincide (un peer con `--corrupt`).
**Hecho cuando:** el workflow nocturno corre 8 peers un día completo con los 8 hashes iguales, sin `ERROR`,
y los KB/s por cliente dentro del presupuesto de D-2002 (≤ 24 KB/s en el galpón).

### D-2024 · Bot de jugador solo, 20 días — A · Opus 5.5 · high · Aviso: no · F5
**Depende de:** D-0126, D-2016, D-0510 (quiebra), D-1001 (empleados, si el modo solo los usa)
**Qué:** `tests/bot_company_solo.gd`: las etapas de `bot_company_day` con **un** jugador, 20 días seguidos
con el reloj acelerado (`GameClock` a ×20) y el save cargado entre día y día (como se jugaría). Juega con
la política del modo solo de [roles-tripulacion.md](../diseno/roles-tripulacion.md) (sale solo cuando
hay 3-4 cajas listas o un pedido por vencer; el galpón se pausa mientras maneja).
- [ ] **D-2024.1** Bucle de días sobre `bot_company_day` (la lista de etapas se reusa, no se copia): sale
  con `BOT_FAIL day=<n> <etapa>:<motivo>` en el primer error.
- [ ] **D-2024.2** Política simple de compras (reponer el producto con menos stock que pedidos abiertos) y
  de salidas (la regla de arriba). Los números van en `CompanyTuning` si son de diseño; los del bot, en el
  bot.
- [ ] **D-2024.3** Resumen por día: plata, entregas, vencidos, roturas, minutos de galpón y de ruta. Una
  línea `SOLO day=<n> money=<> delivered=<> expired=<>`.
**Test** `test_company_bot_solo`: corre 3 días con una semilla fija y comprueba que imprime 3 líneas
`SOLO`, que la plata del día 3 es la del save (`CompanySave.load_into`) y que con plata inicial 0 sale
`BOT_FAIL day=1 bankrupt` (prueba que la quiebra se detecta).
**Hecho cuando:** con la semilla de CI juega 20 días sin quiebra, sin etapa bloqueada y con al menos el
70 % de los pedidos entregados (si no llega, es un hallazgo de balance para `pulidor-jugabilidad`, no un
cambio del umbral).

### D-2025 · Bot de la campaña completa acelerada — B · Opus 5.5 · high · Aviso: no · F5
**Depende de:** D-2024, D-0401 (hitos), D-0418 (hito de Volcán)
**Qué:** `tests/bot_company_campaign.gd`: el bot de D-2024 sin el límite de 20 días, que compra los
desbloqueos en el orden de [hitos.md](../diseno/hitos.md) cuando le alcanza la plata y abre cada distrito
nuevo en cuanto el hito lo permite. Las salidas se **simulan** (sin manejar): duración y roturas salen de
la tabla de cada distrito de [distritos.md](../diseno/distritos.md) con la semilla, como
`sim_trap_balance` hace con las trampas. Así una campaña entera corre en minutos.
- [ ] **D-2025.1** Simulador de salida por distrito (`scripts/gameplay/districts/trip_sim.gd`, sin escena):
  `simulate(district, cargo, seed) -> {minutes, delivered, broken}`; lo usa el bot y lo puede usar el
  balance.
- [ ] **D-2025.2** El bot de campaña: imprime `CAMPAIGN day=<n> district=<id> money=<>` en cada desbloqueo y
  `CAMPAIGN_OK days=<n>` al llegar al hito final del Volcán, o `CAMPAIGN_FAIL day=<n> <motivo>`.
- [ ] **D-2025.3** La curva (día de cada desbloqueo) va a `docs/expansion-distritos/revisar/D-2025.md`
  para comparar con la de `hitos.md`.
**Test** `test_company_trip_sim`: misma semilla → mismo resultado; un distrito sin vehículo que llegue da
`delivered=0`; la media de 200 salidas a Centro queda a ±15 % de la duración de `distritos.md`.
**Hecho cuando:** el bot llega al Volcán en simulación con la semilla de CI y la curva queda anotada.

### D-2026 · Save de 50 días — B · Opus 5.5 · medium · Aviso: no · F5
**Depende de:** D-0206 (save de empresa), D-0236 (guardado al cerrar el día)
**Qué:** un save de 50 días con todo lo que crece con el tiempo: historial de días (resúmenes), libro
de pedidos con los cerrados, disposición del galpón con todas las estaciones, stock lleno y bultos en el
piso. Medir tamaño y tiempo de `CompanySave.save()` / `load_into()`.
- [ ] **D-2026.1** Generador del save (en el test, sin jugar): estado sintético con los máximos de
  `CompanyTuning` (`ORDERS_MAX_PER_DAY`, la etapa mayor de `WAREHOUSE_STAGE_MAX_PIECES`, todos los
  productos) repetido 50 días.
- [ ] **D-2026.2** Si el historial crece sin techo, recortarlo: el save guarda los últimos N días
  completos y de los anteriores solo los totales (N en `CompanyTuning`, decisión documentada).
**Test** `test_company_save_50_days`: el save de 50 días pesa < 2 MB, `load_into()` tarda < 2 s (medido
con `Time.get_ticks_usec`, el peor de 3) y cargar → guardar → cargar da el mismo `to_dict()`; un save de 100
días no pesa más del doble del de 50.
**Hecho cuando:** el test pasa en CI.
