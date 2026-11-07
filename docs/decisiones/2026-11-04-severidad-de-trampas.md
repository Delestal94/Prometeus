# 2026-11-04 · El armado mueve la severidad de la trampa (D-0710.b)

Decidido por la sesión que construyó D-0710.b (lote local). Detalle en
[F1-07-armado.md](../expansion-distritos/detalle/F1-07-armado.md), D-0710.

- **Decisión: el nivel low / mid / high es una severidad, un solo número por nivel**
  (`CompanyTuning.TRAP_SEVERITY_LOW` 1, `_MID` 1,1, `_HIGH` 1,25). La revisión (D-0140) suponía que cada `.tres`
  ya tenía variantes de dificultad que el comportamiento sabía ejecutar; no existen (solo el campo `difficulty`
  1-4, que usa el sorteo de pedidos). En vez de inventar 7 × 3 juegos de parámetros, el módulo `hazards` suma
  `ITrapBehavior.severity` (clave `severity` del config, 1 por defecto) y cada comportamiento sabe qué parte de
  sus números es daño: lo multiplica por la severidad. Ningún `.tres` cambia.
- **Decisión: la severidad sube solo el daño, nunca la respuesta.** Frágil: golpes y pasos corriendo. Equilibrio:
  daño por segundo inclinado y menos tiempo pasado del ángulo de peligro antes de volcar. Peso creciente: crece
  más rápido cuando se acaba el tiempo. Ruidoso: cada sacudida y cada paso agitan más y, en el máximo, se escapa
  antes. Hostil: respuesta equivocada, golpe, paso y enojo pasivo. Líquido: derrame por inclinación, golpe y paso.
  Explosivo: mecha más corta y penalidad por error, golpe y paso. Amortiguar, contrapesar, asegurar, calmar,
  fregar y desactivar hacen lo mismo: una caja mal armada pide el mismo gesto, antes y más seguido.
- **Decisión: low = 1, la trampa como es hoy** (`armado-y-trampas.md` §5: con Q = 100 se comporta como hoy).
  Una caja sin plan (el juego de siempre, la partida rápida) también va a 1.
- **Decisión: 1,25 en alto y no 1,5.** Medido con `sim_trap_balance.gd -- --levels --trials=10`
  ([levels_report.md](../../do-not-drop/tests/sim_data/levels_report.md): 10 repeticiones, aunque `LEVEL_TRIALS`
  sea 20). Con 1,25 las 7 trampas pierden más cajas en alto que en bajo (pide ≥ 5): 6 por el torpe (+8 a +46
  puntos) y Frágil por el experto, de 2 % a 20 % (el choque grabado que nadie puede amortiguar), porque el torpe
  se queda en 50 %. Fuera de Frágil el experto pierde 2 % como mucho (Ruidoso en alto). Hostil no separa 1,25 de
  1,5: el torpe llega al 100 % con los dos. Lo que descarta 1,5 (el ×1,5 de flota) es Frágil, que lleva al torpe
  del 50 % al 96 %, y que Peso creciente y Líquido suben al 82 %. Con 1,25 en medio, Hostil ya llegaba al 100 %
  con una sola falla de sello (Q 85). Medio queda en 1,1.
- **Decisión: el paquete lee la severidad del plan** (`META_TRAP_PLAN.severity`, que escriben `BoxTrap.plan` y
  `CompanyPackages.make` con la intensidad del host) al armar la trampa (`PackageRescue.trap_config`, usado por
  `DeliveryPackage.initialize_trap` y al reparar: la caja es la misma, conserva su severidad). No viaja por red:
  la trampa la simula solo el host.
- **Queda para después (D-0710 sigue ◐):** que `META_LOOSE_BOX` sume Equilibrio de verdad. El paquete tiene un
  solo comportamiento de trampa; una segunda trampa toca cuidado, HUD, pistas e integridad, y el "mecanismo de
  trampa extra" del ×1,5 de flota que la revisión nombra tampoco existe todavía.

- **Límite (revisión de D-0710.b, 2026-11-07): todavía no se juega.** Las cajas con plan solo nacen en el mundo
  Empresa (`CompanyPackages.make`) y ese mundo no arranca `RunManager` ([revisar/D-0119.md](../expansion-distritos/revisar/D-0119.md)):
  con `is_running` en falso `PackageImpacts.apply_impact` y `PackageRunShake.jolt` no hacen nada y `package.gd` no
  llama a `_simulate_cargo`, y `CompanyTrips` no le pasa `broken_boxes` a `trip.close`. La severidad queda puesta
  en la trampa y medida en el arnés, pero una salida no daña la caja. Lo cierra **D-0710.d**.

Revisar al final: [revisar/D-0710.md](../expansion-distritos/revisar/D-0710.md).
