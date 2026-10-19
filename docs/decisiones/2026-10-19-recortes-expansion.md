# Decisión 2026-10-19: recortes de alcance de la expansión (D-0112 / D-0113)

Fila 5 de [decisiones delegadas](2026-10-04-expansion-decisiones-delegadas.md): los recortes los aplica quien
hace D-0112, sin tocar nada de lo que nombró el usuario.

**Decisión:** se tachan en las tablas de grupo de `docs/expansion-distritos/` **287 tareas**: 42 recortadas,
148 pospuestas a post-lanzamiento (después de cerrar F5, plan de D-2035) y 97 fusionadas en otra tarea, que
lleva "(incluye D-xxxx, fusión de D-0112)" en su título. La lista, el motivo de cada bloque y la estimación por
grupo están en [critica-alcance.md](../expansion-distritos/diseno/critica-alcance.md). D-0223 se marca hecha
(`modules/day_clock/` existe desde D-0219).

**Por qué:** 913 tareas abiertas al ritmo medido (≈ 55 corridas por día) no entran antes del Early Access
(2027-03-12). Los recortes ahorran ≈ 20 % sin tocar zonas, bici, carrito, lancha, avioneta, armado,
camiones de mercadería, empleados, automatización, desbloqueos por hitos ni modelos nuevos.

**Descartado:**
- Recortar también la "zona gris" (repartidores NPC, brazo robótico, técnico, modelos de oficina y animales):
  rozan la fila 5, quedan en el issue `decide-usuario` #470.
- Recortes más chicos (solo los de la fila 5): ahorran < 2 % y dejan duplicados exactos en las tablas.

**Cómo se lee una tachada:** `| ~~D-XXXX~~ | ~~título~~ **Recortada / Pospuesta a post-lanzamiento /
Fusionada en D-YYYY (D-0112)** |`. Una tachada no se toma (`desarrollador.md` §2). Para reabrir una, se
saca el tachado en su tabla con un PR que diga por qué. Todo este cambio se revierte entero revirtiendo su PR.

**Queda para el usuario** (issue #470): qué parte de la expansión entra al Early Access (recomendado: F0-F2,
y F3-F4 como actualizaciones gratis), la zona gris y las horas de la PC de arte.
