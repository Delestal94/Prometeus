# Detalle de F0 + F1 (180 tareas)

> Las tareas **Núcleo** de los grupos de F0 (01, 02, 20) y F1 (03, 05, 06, 07, 08, 09) reescritas con el
> formato de `docs/tareas-nacho.md`: archivos, subtareas, números, test con lo que comprueba, aviso y
> dependencias exactas. Listas para promover tal cual (copiar el bloque a `tareas-nacho.md` bajo el hito
> nuevo). Dueño: Nacho, todas.

| Archivo | Tareas | Fase |
|---|---|---|
| [supuestos.md](supuestos.md) | Lo que se asume mientras el usuario no decide los ⏸ | — |
| [F0-01-diseno.md](F0-01-diseno.md) | D-0101 a D-0120 | F0 |
| [F0-02-arquitectura.md](F0-02-arquitectura.md) | D-0201 a D-0220 | F0 |
| [F0-20-red-y-ci.md](F0-20-red-y-ci.md) | D-2001 a D-2020 | F0 |
| [F1-02-arquitectura.md](F1-02-arquitectura.md) | D-0251 a D-0253 | F1 |
| [F1-03-distritos.md](F1-03-distritos.md) | D-0301 a D-0320, y D-0340 (la puerta del cliente, del cierre de F1) | F1 |
| [F1-05-economia.md](F1-05-economia.md) | D-0501 a D-0520 (las que ya se construyeron) | F1 |
| [F1-06-stock.md](F1-06-stock.md) | D-0601 a D-0620, menos D-0616 y D-0617 (están en F2-06) | F1 |
| [F1-07-armado.md](F1-07-armado.md) | D-0701 a D-0720 | F1 |
| [F1-08-pedidos.md](F1-08-pedidos.md) | D-0801 a D-0820 y D-0851 | F1 |
| [F1-09-galpon.md](F1-09-galpon.md) | D-0901 a D-0920 y D-0948 | F1 |
| [F2-04-progresion.md](F2-04-progresion.md) | D-0437 | F2 |
| [F2-06-stock.md](F2-06-stock.md) | D-0616, D-0617, D-0621 | F2 |
| [F2-07-armado.md](F2-07-armado.md) | D-0721, D-0723, D-0726, D-0727, D-0729, D-0731, D-0732, D-0734 | F2 |
| [F2-08-pedidos.md](F2-08-pedidos.md) | D-0822, D-0840 | F2 |
| [F2-09-galpon.md](F2-09-galpon.md) | D-0931, D-0936 | F2 |
| [F2-12-flota.md](F2-12-flota.md) | D-1234 | F2 |
| [F5-20-red-y-calidad.md](F5-20-red-y-calidad.md) | D-2021, D-2023 a D-2026 (Ampliación) | F5 |

Lo de F2 no se toma hasta que D-2016 cierre F1, aunque la fila esté en un bloque Núcleo: los archivos `F2-*` (entre ellos D-0616, el frío) y también D-0315 con D-0315.b (Campo), que la revisión D-0140 pasó a F2 y siguen en `F1-03-distritos.md` con la fase en el encabezado.

## Orden recomendado dentro de F0 + F1

1. **Decisiones y diseño** (D-0102 a D-0106, D-0109, D-0111, D-0116, D-0117): sin esto los números de abajo
   son supuestos.
2. **Esqueleto de datos** (D-0202, D-0203, D-0204, D-0205, D-0207, D-0210, D-0211, D-0212, D-0215, D-0216,
   D-0218) y **red** (D-2001, D-2003, D-2007, D-2008).
3. **Galpón jugable** (D-0214, D-0620, D-0911, D-0904) → **stock** (D-0601 a D-0612) → **pedidos** (D-0801
   a D-0808) → **armado** (D-0701 a D-0717) → **economía** (D-0501 a D-0508).
4. **Salida y vuelta** (D-0301 a D-0320) con Barrio Centro en gris (D-1501, fuera de este detalle).
5. **Cierre del corte vertical**: `bot_company_day` (D-0111) completa un día sin errores, con
   `bench_company` (D-2011) dentro del presupuesto.

## Convenciones de este detalle

- **Encabezado:** `### D-XXXX · título — Prio · Opus 5.5 · esfuerzo · Aviso · Fase`.
- **Prio:** A, sin esto no hay corte vertical; B, suma claro dentro de la fase.
- **Estado:** debajo del encabezado, `**[x] Hecho (fecha, PR #n)**` o `**[~] Parcial (fecha, PR #n)**` con lo que
  falta; en la tabla del grupo, ✅ o ◐ al principio de la columna "Tarea". Una línea que empieza con "Antes (...)"
  es el estado anterior, guardado como historia.
- **Hecho es hecho en el juego.** Una tarea cuyo test pasa pero cuyo resultado no ocurre en el juego (nadie la
  llama fuera de `tests/`) queda `[~]` y ◐. Lo que falta va en una subtarea con casilla (`- [ ] **D-XXXX.b**`), que
  es lo que se toma y se cierra. La excepción es una subtarea abierta que no está en la lista del corte
  ([corte-vertical.md](../diseno/corte-vertical.md) §2): lo dice en su línea y no le saca el `[x]` a su tarea.
- **Test:** `tests/test_<nombre>.gd` (`extends SceneTree`, `_expect`, `quit(_failures)`, skill `nuevo-test`),
  corrido con `ejecutor-tests` y filtro. Cada tarea dice qué afirma su test.
- **Rutas nuevas:** `scripts/gameplay/business/` (galpón, stock, armado, pedidos),
  `scripts/gameplay/districts/`, `scripts/gameplay/fleet/`, `scripts/core/company/` (estado persistente),
  `data/products/`, `data/districts/`, `data/vehicles/`, `data/boxes/`, `data/suppliers/`,
  `scenes/company/`.
- **Números:** los de [supuestos.md](supuestos.md). Si D-0117 los cambia, se cambian **solo** en los
  `.tres` y en `company_tuning.gd` (D-0202), nunca dispersos en el código.
