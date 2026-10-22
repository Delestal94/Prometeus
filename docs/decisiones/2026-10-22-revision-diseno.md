# 2026-10-22 · Revisión del diseño de la expansión (D-0140)

Informe: [revision-diseno.md](../expansion-distritos/diseno/revision-diseno.md).

- **Decisión: la compuerta F1 → F2 de `.claude/rutinas/desarrollador.md` §2 mira D-2016 (con D-2016.3 y D-2016.4) y no
  D-0111** porque D-0111 es la tarea que escribió el corte, hecha desde F0, y con ella se construyeron 12 tareas F2
  con F1 abierto. Las tareas de `detalle/F2-*` no se toman hasta entonces.
- **Decisión: el corte vertical F1 es solo Barrio Centro** porque Campo está cerrado por `gate_campo_obra`
  (reputación 60) y en F1 no hay hitos que lo abran. Campo llega en F2 con el grupo 04; D-0315.b pasa a F2.
- **Decisión: el bot del corte no cuenta etapas simuladas** (D-2016.4, `BOT_STUB` bloquea `BOT_OK`) porque hoy la
  puerta, el alquiler y la red los hace el bot y `BOT_OK` no mide el juego real.
- **Decisión: D-0710 y D-0509 vuelven a ◐** (D-0710.b: las trampas leen la intensidad; D-0509.b: el cierre cobra el
  alquiler) porque su ✅ se puso por la función pura y nada del juego las usa.
- **Decisión: tareas nuevas D-0254 (partir `company_root.gd` y `company_net.gd`) y D-0551 (eventos del día, primera
  tanda de 3, en F2)**.
- **Decisión: F2 ya hecho (proveedores extra, frío, regalo, multi-caja) queda detrás de los hitos** y no entra a la
  curva de F1.
- **No se aplica en este PR** (recortes o posposiciones, cada uno en su propio PR, regla 3): relojes de pedidos
  unificados (D-0151/D-0813.1), licencias y `permit_suburbio` (D-0404/D-0407), D-1902 a F2.

Nada de esto saca algo de lo que nombró el usuario (fila 5 de
[decisiones delegadas](2026-10-04-expansion-decisiones-delegadas.md)).
