# Recortes de D-0112: zona gris y alcance del Early Access (D-0113) — 2026-11-04

Decidió: Claude, por delegación del usuario (2026-11-04). Issue `decide-usuario`: **#470** (no se tocó en
GitHub; queda abierto hasta que alguien lo cierre con esta decisión).

## Contexto
D-0112 ([critica-alcance.md](../expansion-distritos/diseno/critica-alcance.md)) tachó 287 tareas el
2026-10-19 ([recortes-expansion](2026-10-19-recortes-expansion.md)) sin tocar la fila 5 de
[decisiones delegadas](2026-10-04-expansion-decisiones-delegadas.md): **nunca se recorta lo que nombró el
usuario** (zonas, bici, carrito, lancha, avioneta, armado, camiones de mercadería, empleados, automatización,
desbloqueos por hitos, modelos nuevos). Dejó para D-0113, en el issue #470, lo que roza esa fila:

| IDs | Qué es | Toca de la fila 5 |
|---|---|---|
| D-1027, D-1028, D-1037, D-1239, D-1440 | Repartidor, choferes, empleados de zona y piloto NPC | Empleados |
| D-1122 | Brazo robótico armador | Automatización |
| D-1139 | Empleado técnico que repara máquinas | Empleados |
| D-1826 | Modelo de la oficina del jefe | Modelos nuevos |
| D-1834, D-1835 | Modelos y animaciones de animales nuevos | Modelos nuevos |

Y tres preguntas de su §6: qué parte de la expansión entra al Early Access (1), si el "Contenido cerrado
2026-10-30" de `plan-desarrollo.md` vale para la expansión (5) y las horas de la PC de arte (3). Ninguna de las
diez tareas está construida.

## Alternativas
- **Posponer la zona gris a post-lanzamiento** (lo que recomienda la crítica para siete de las diez): solo los
  NPC ahorran unas 39 corridas (§3.2), pero las diez rozan algo que el usuario nombró. Posponer es tachar (así lo trata
  D-0112) y el límite de esta decisión es no recortar nada nombrado.
- **Construirlas tal como están escritas**: los repartidores y choferes NPC entregan solos y comen el núcleo
  (la entrega la hace la tripulación, `referencia-schedule-1.md` §8.5); el brazo con calidad máxima deja sin
  sentido el armado a mano; el técnico le saca al jugador el atasco que destraba (D-1113), que es el momento
  coop.
- **Construirlas en su versión mínima, al final de su grupo** (la otra opción que da la crítica en §3.2 y §4.4).

## Decisión
**No se tacha ninguna de las diez.** Se construyen en su versión mínima y al final de su grupo:

1. **Repartidores, choferes y pilotos NPC** (D-1027, D-1028, D-1037, D-1239, D-1440): solo llevan cajas
   **sin trampa fuerte** a **distritos ya dominados**, y cobran **la mitad** de la paga. Todos los productos
   del catálogo tienen trampa ([armado-y-trampas](../expansion-distritos/diseno/armado-y-trampas.md) §1), así
   que "sin trampa" sería dejarlas vacías; se toma la definición de
   [referencia-schedule-1](../expansion-distritos/diseno/referencia-schedule-1.md) §8 ("sin trampa fuerte en
   zonas ya dominadas"):
   - **Sin trampa fuerte:** la trampa que manda en la caja (la de mayor dificultad, regla 1 de
     armado-y-trampas §3, la que elige `BoxToPackage`) tiene `difficulty` (del `.tres` de la trampa) ≤
     `NPC_MAX_TRAP_DIFFICULTY = 1`, y la caja no está floja (`META_LOOSE_BOX`, que le suma `balance`). Hoy
     eso deja solo `fragile` (12 de los 40 productos); `balance`, `growing_weight` y `liquid` (2), `noisy` (3),
     `explosive` y `hostile` (4) son siempre de la tripulación.
   - **Distrito dominado:** reputación del distrito (D-0406) ≥ `NPC_MIN_DISTRICT_REPUTATION = 60`.

   Los tres números van en `CompanyTuning` (`NPC_TRIP_PAY_FACTOR = 0.5`, `NPC_MAX_TRAP_DIFFICULTY = 1`,
   `NPC_MIN_DISTRICT_REPUTATION = 60`) y D-0543 (estrategias degeneradas) los mide.
2. **Brazo robótico armador** (D-1122): arma con **calidad tope 70** (`ROBOT_PACK_MAX_QUALITY = 70` en
   `CompanyTuning`). Lo armado a mano puede llegar a 100 y amortigua más en la ruta.
3. **Técnico** (D-1139): hace **mantenimiento preventivo** (baja la chance de avería de las máquinas que
   cuida y su costo de mantenimiento, D-0527). **No destraba atascos ni averías en vivo**: eso sigue siendo
   del jugador (D-1113).
4. **Modelos de la oficina del jefe y de animales** (D-1826, D-1834, D-1835): van **al final de la cola de la
   PC**, después de todos los modelos de su fase. Como sus tareas de juego están pospuestas (D-0924, D-1324,
   D-1626), al hacerse se usan como **decorado**: la oficina como sala cerrada del galpón por defecto y los
   animales como fauna de ambiente sin colisión ni peligro en Islas y Montaña.

Las preguntas del §6:

- **(1) Early Access:** se construye en el orden de la opción A de la crítica: **F0-F2 completos para el
  lanzamiento** (Centro, Suburbio, Campo, bici, carrito, empleados, cintas, hitos) y **F3-F4 como
  actualizaciones gratuitas del Early Access**, que `plan-desarrollo.md` ya prevé. Nada se recorta: Islas,
  Montaña, Nieve, Volcán, lancha y avioneta llegan en esas actualizaciones. **Las versiones mínimas de la zona
  gris que caen en grupos de F2** (10 Empleados: D-1027, D-1028, D-1037, D-1139; 11 Automatización: D-1122;
  12 Bici y carrito: D-1239) **no frenan el lanzamiento**: llegan en la **primera actualización gratuita del
  Early Access**. F0-F2 "completos" quiere decir completos sin esas seis; no se recortan, solo se ordenan, y
  su costo (solo los NPC son unos 9,5 días-persona contando D-1440, §3.2 de la crítica) no se suma a lo que tiene que estar listo para el 2027-03-12.
  D-1440 es de F4 y llega con la avioneta. **No se decide**: correr la fecha
  (opción B), qué promete la página de Steam (D-0139) ni el precio; siguen siendo del usuario.
- **(5) Contenido cerrado 2026-10-30:** vale para el **juego base** (Entrega, Endless y las listas `N-`/`S-`).
  La expansión sigue sus fases F0-F5; si valiera para ella, la expansión estaría congelada desde el
  2026-10-30, al revés de lo que el usuario pidió.
- **(3) Horas de la PC de arte:** no se decide: es la máquina del usuario.

## Por qué
- El límite (no recortar lo nombrado) descarta posponer; la versión mínima cuida el núcleo (la caja difícil
  siempre en manos de la tripulación, el armado a mano vale más, el atasco es coop) sin sacar ningún sistema.
- Ponerlas al final de su grupo y, las de F2, en la primera actualización del Early Access da el mismo
  calendario de lanzamiento que posponerlas, sin tachar nada.
- La opción A no mueve la fecha ni recorta zonas: solo ordena qué se termina primero, y coincide con las
  fases que ya tienen las tablas.

## Qué cambia
- Las filas de las diez tareas en las tablas de grupo (10, 11, 12, 14 y 18) llevan la versión mínima; ninguna
  se tacha.
- `critica-alcance.md` §4.4 y §6 apuntan a esta decisión.
- `plan-desarrollo.md` lleva, debajo del calendario, una nota: el "Contenido cerrado" vale para el juego base
  y la expansión sigue F0-F5 con F0-F2 al lanzamiento (sin la zona gris) y F3-F4 en actualizaciones.
- Tareas y notas que hacen falta: [`revisar/D-0113.md`](../expansion-distritos/revisar/D-0113.md).
