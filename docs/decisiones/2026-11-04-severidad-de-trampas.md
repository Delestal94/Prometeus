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
- **Decisión: 1,25 en alto y no 1,5.** Medido con `sim_trap_balance.gd -- --levels`
  ([levels_report.md](../../do-not-drop/tests/sim_data/levels_report.md)): con 1,25 las 7 trampas pierden más
  cajas en alto que en bajo (pide ≥ 5) y el experto sigue sin perder ninguna salvo en Frágil (el choque grabado
  que nadie puede amortiguar). Con 1,5 (el ×1,5 de flota) Hostil y Frágil llevaban al torpe al 96-100 %; con
  1,25 en medio, Hostil ya llegaba al 100 % con una sola falla de sello (Q 85). Medio queda en 1,1.
- **Decisión: el paquete lee la severidad del plan** (`META_TRAP_PLAN.severity`, que escriben `BoxTrap.plan` y
  `CompanyPackages.make` con la intensidad del host) al armar la trampa (`PackageRescue.trap_config`, usado por
  `DeliveryPackage.initialize_trap` y al reparar: la caja es la misma, conserva su severidad). No viaja por red:
  la trampa la simula solo el host.
- **Queda para después (D-0710 sigue ◐):** que `META_LOOSE_BOX` sume Equilibrio de verdad. El paquete tiene un
  solo comportamiento de trampa; una segunda trampa toca cuidado, HUD, pistas e integridad, y el "mecanismo de
  trampa extra" del ×1,5 de flota que la revisión nombra tampoco existe todavía.

Revisar al final: [revisar/D-0710.md](../expansion-distritos/revisar/D-0710.md).
