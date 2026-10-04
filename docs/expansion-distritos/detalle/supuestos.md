# Supuestos de trabajo (mientras el usuario no decide)

> Pedido del usuario (2026-10-04): avanzar sin esperar las decisiones ⏸. Cada supuesto dice qué
> decisión reemplaza y qué tareas cambian si la decisión sale distinta. Cuando el usuario decida, se
> anota acá y en `docs/decisiones/`, y se corrigen las tareas listadas.

## Decisiones de diseño

| # | Reemplaza | Supuesto | Por qué | Si sale distinto, cambian |
|---|---|---|---|---|
| S1 | D-0102 | **Modo Empresa nuevo** al lado de Entrega y Endless; esos dos quedan como están | No rompe nada de lo hecho ni los tests actuales; la expansión se puede cortar sin perder el juego | D-0214, D-0301, D-0520, D-2014, D-2020 |
| S2 | D-0104 | ✅ **Decidido por el usuario (2026-10-04)**: **un solo mapa continuo** que se desbloquea con barreras, calles cortadas, agua (lancha), equipo (Nieve, Volcán) y altura (avioneta → Montaña). Detalle y lo que decidió la conversación (trazado fijo ≤ 6×6 km, celdas de 256 m, grafo de calles, máx. 2 vehículos lejos) en `docs/decisiones/2026-10-04-mapa-continuo.md` | — | ya aplicado en grupo 03, D-0214 |
| S3 | D-0105 | **Día de 08:00 a 20:00 de juego; 1 h de juego = 90 s reales** (18 min por día). El reloj corre en el galpón y en las salidas. A las 20:00 no se corta una salida: el cierre espera a que vuelva | Cabe en una sesión; el número vive en `company_tuning.gd` | D-0203, D-0219, D-0319 |
| S4 | D-0106 | **Si toda la tripulación sale, el galpón se congela** en F1 (no hay empleados). Desde F2, los empleados siguen trabajando | En F1 no hay nadie que trabaje; congelar evita castigar al que sale | D-0203, D-0316 |
| S5 | D-0505 | **Sin combustible** en F1 y F2 | Un costo más sin decisión interesante todavía | D-0323, D-1223 |
| S6 | D-0704 | **Armado en grilla**: la caja tiene celdas; cada producto ocupa un bloque de celdas y se encastra, sin física libre | Determinista, barato en red, jugable con mando | D-0703, D-0705, D-0709 |
| S7 | D-0103 | **Carrito = carrito eléctrico tipo golf**; la zorra de mano existe como herramienta del galpón (D-0605), no como vehículo | Separa herramienta del galpón de vehículo de reparto | D-1221 a D-1230 |
| S8 | — | En modo Empresa **la plata vive en `CompanyState`**; `CrewProgression.team_money` sigue para Entrega/Endless. Mérito y cartas se siguen ganando en las salidas | No mezcla dos economías en el mismo número | D-0501, D-0520, D-0427 |
| S9 | — | **Producto = `ProductDefinition` que referencia un `PackageContent`** existente (modelo, textos, notas). Los 10 contenidos de `data/contents/` son los primeros 10 productos y conservan su trampa | Cero arte nuevo para el corte vertical | D-0204, D-0213, D-0710 |

## Números del corte vertical (los ajusta D-0117)

Todos en `scripts/core/company/company_tuning.gd` o en los `.tres`, nunca sueltos en el código.

| Qué | Valor |
|---|---|
| Plata inicial de la empresa | 500 |
| Alquiler del galpón | 100 por día |
| Celda de la grilla de armado | 0,2 m |
| Cajas (celdas X×Y×Z · costo) | S 2×2×2 · 2 — M 3×3×3 · 3 — L 4×3×3 · 5 — XL 4×4×4 · 8 |
| Relleno | 1 por celda rellenada |
| Cinta / etiqueta / sello | 1 / 0 / 0 |
| Compra de producto al proveedor | 20 a 80 (por producto, en su `.tres`) |
| Precio de venta | compra × 1,6 |
| Envío por distrito | Barrio Centro 40, Campo 60 |
| Pedidos por día | 6 + 2 por jugador, tope 16; 1 a 3 productos cada uno |
| Ventana de entrega | 4 h de juego desde que entra el pedido |
| Tardanza | −25 % de la paga del pedido |
| Producto roto | no se cobra ese producto; reputación −5 |
| Producto equivocado o faltante | esa caja paga 0; reputación −3 |
| Reputación inicial | 50 (0-100) |
| Proveedor | 1 camión por día a las 08:30 con lo pedido el día anterior; espera 3 h de juego en la dársena |
| Palet | hasta 24 unidades de un mismo producto |
| En la mano | hasta 4 unidades de un mismo producto (`HAND_MAX_UNITS`, D-2003; lo ajusta el picking, D-0609) |

## Calidad del armado → trampa (base de D-0709 y D-0710)

- **Calidad `Q` de 0 a 100**: empieza en 100.
  - −40 si el contenido no coincide con el pedido.
  - −30 × fracción de celdas libres sin relleno (×1,5 si algún producto es frágil).
  - −15 por cada sello requerido que falte.
  - −10 sin cinta o sin etiqueta.
- **La trampa sale del producto** (el `PackageContent` ya tiene la suya). En una caja con varios productos
  manda el de mayor dificultad, según `UnlockManager.TRAP_DIFFICULTY_ORDER`.
- **El armado mueve la intensidad**: `impact_absorption = lerp(1.0, 0.6, protección)`, donde
  `protección` = fracción de celdas libres rellenadas. Es el mismo campo que hoy pone el relleno del
  depósito (`Depot.PADDING_ABSORPTION = 0.75`).
- **Caja demasiado grande** (más del 50 % de celdas libres sin relleno): suma la trampa Equilibrio con
  intensidad baja.
