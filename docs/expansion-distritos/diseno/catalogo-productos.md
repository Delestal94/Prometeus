# Catálogo inicial de productos (D-0116)

> Fuente de `ProductDefinition` (D-0204) y de los pedidos de arte D-1802 a D-1805. Números base:
> [supuestos.md](../detalle/supuestos.md); trampas: [armado-y-trampas.md](armado-y-trampas.md).
> Todo valor numérico vive en los `.tres` de `data/products/` y en `company_tuning.gd` (D-0202).

## Reglas de lectura

- **Celdas**: X×Y×Z en celdas de 0,2 m (supuesto S6). Cada producto entra en la caja **XL** (4×4×4); los de
  F1 entran como mínimo en una caja M (3×3×3) o menor, y repiten los casos de `armado-y-trampas.md` §4
  (jarrón 8 celdas, gallina 4, fuegos artificiales 12, bidón 12). Las celdas son el volumen del producto,
  no del modelo 3D: el modelo se escala al bloque.
- **Compra**: entre 20 y 80 (S, números del corte vertical). **Venta** = compra × 1,6 redondeada
  (`get_sell_price()`).
- **Frágil**: sí si la trampa es `fragile`, si es vidrio o si se rompe por golpe (cuenta para el ×1,5 de la
  calidad `Q`).
- **Temperatura**: `ambiente`, `frío` o `calor` (D-0204). En F1 el frío y el calor **no se simulan** hasta
  D-0616 (heladera): el campo existe y se ignora.
- **Zona**: donde más se pide, con los ids de `ZoneDefinition` (`centro`, `campo`, `suburbio`, `puerto`,
  `islas`, `montana`, `nieve`, `volcan`; `parque_industrial` es el galpón y no pide nada). Un producto se
  puede pedir en otras zonas; la columna manda en la probabilidad (D-0807).
- **Trampa**: una de las 7 de `data/traps/`; en los nuevos es la propuesta, la fija `constructor-trampas`
  al hacer su `TrapDefinition`.

## Los 10 de F1 (contenidos existentes, sin arte nuevo)

| # | id | Contenido base | Celdas | kg | Frágil | Temp. | Compra | Venta | Zona | Trampa |
|---|---|---|---|---|---|---|---|---|---|---|
| 1 | `porcelain_vase` | `porcelain_vase` (existente) | 2×2×2 | 4 | sí | ambiente | 50 | 80 | centro | `fragile` |
| 2 | `antique_lamp` | `antique_lamp` (existente) | 2×2×3 | 6 | sí | ambiente | 60 | 96 | centro | `fragile` |
| 3 | `glass_tower` | `glass_tower` (existente) | 2×3×2 | 3 | sí | ambiente | 40 | 64 | centro | `balance` |
| 4 | `wedding_cake` | `wedding_cake` (existente) | 2×3×2 | 3 | no | frío | 70 | 112 | centro | `balance` |
| 5 | `sourdough` | `sourdough` (existente) | 3×1×3 | 2 | no | ambiente | 20 | 32 | campo | `growing_weight` |
| 6 | `milk_canister` | `milk_canister` (existente) | 2×2×3 | 7 | no | frío | 25 | 40 | campo | `liquid` |
| 7 | `hen` | `hen` (existente) | 2×2×1 | 3 | no | ambiente | 35 | 56 | campo | `noisy` |
| 8 | `puppy` | `puppy` (existente) | 2×2×2 | 4 | no | ambiente | 45 | 72 | centro | `noisy` |
| 9 | `fireworks_crate` | `fireworks_crate` (existente) | 3×2×2 | 5 | no | ambiente | 80 | 128 | centro | `explosive` |
| 10 | `raccoon_cage` | `raccoon_cage` (existente) | 2×2×3 | 8 | no | ambiente | 75 | 120 | campo | `hostile` |

Suman 4 en `campo` y 6 en `centro`: las dos zonas abiertas en F1 piden productos desde el día 1. Dificultad
creciente de las trampas: la barra de F1 la sube `UnlockManager` como hoy.

## Los 30 nuevos (pedido a `sesion-arte`)

Cada lote es un pedido de modelos de 10 piezas, con colisión simple.

### Lote 2 · frágiles (D-1803)

| # | id | Contenido base | Celdas | kg | Frágil | Temp. | Compra | Venta | Zona | Trampa |
|---|---|---|---|---|---|---|---|---|---|---|
| 11 | `glass_mirror` | nuevo, necesita modelo | 2×3×1 | 5 | sí | ambiente | 55 | 88 | centro | `fragile` |
| 12 | `ceramic_teapot` | nuevo, necesita modelo | 2×2×2 | 2 | sí | ambiente | 30 | 48 | centro | `fragile` |
| 13 | `flat_tv` | nuevo, necesita modelo | 3×3×1 | 9 | sí | ambiente | 80 | 128 | suburbio | `fragile` |
| 14 | `wine_bottles` | nuevo, necesita modelo | 2×3×2 | 6 | sí | ambiente | 65 | 104 | puerto | `fragile` |
| 15 | `crystal_chandelier` | nuevo, necesita modelo | 3×3×3 | 8 | sí | ambiente | 80 | 128 | suburbio | `balance` |
| 16 | `picture_frame` | nuevo, necesita modelo | 3×3×1 | 2 | sí | ambiente | 25 | 40 | centro | `fragile` |
| 17 | `aquarium_lamp` | nuevo, necesita modelo | 2×2×2 | 3 | sí | ambiente | 35 | 56 | islas | `fragile` |
| 18 | `seashell_lamp` | nuevo, necesita modelo | 2×2×2 | 2 | sí | ambiente | 30 | 48 | islas | `fragile` |
| 19 | `snow_globe` | nuevo, necesita modelo | 2×2×2 | 1 | sí | ambiente | 20 | 32 | nieve | `fragile` |
| 20 | `telescope` | nuevo, necesita modelo | 1×4×1 | 4 | sí | ambiente | 70 | 112 | montana | `balance` |

### Lote 3 · fríos y perecederos (D-1804)

| # | id | Contenido base | Celdas | kg | Frágil | Temp. | Compra | Venta | Zona | Trampa |
|---|---|---|---|---|---|---|---|---|---|---|
| 21 | `ice_cream_tub` | nuevo, necesita modelo | 2×2×2 | 3 | no | frío | 30 | 48 | centro | `liquid` |
| 22 | `fresh_fish` | nuevo, necesita modelo | 3×1×2 | 5 | no | frío | 40 | 64 | puerto | `noisy` |
| 23 | `flower_bouquet` | nuevo, necesita modelo | 2×3×2 | 1 | sí | frío | 35 | 56 | centro | `balance` |
| 24 | `cheese_wheel` | nuevo, necesita modelo | 2×1×2 | 6 | no | frío | 45 | 72 | campo | `growing_weight` |
| 25 | `frozen_lobster` | nuevo, necesita modelo | 3×1×2 | 4 | no | frío | 70 | 112 | islas | `hostile` |
| 26 | `birthday_cake` | nuevo, necesita modelo | 3×2×3 | 4 | no | frío | 50 | 80 | suburbio | `balance` |
| 27 | `medicine_vials` | nuevo, necesita modelo | 1×1×2 | 1 | sí | frío | 75 | 120 | montana | `fragile` |
| 28 | `hot_stew_pot` | nuevo, necesita modelo | 2×2×2 | 6 | no | calor | 40 | 64 | nieve | `liquid` |
| 29 | `lava_cake` | nuevo, necesita modelo | 2×1×2 | 2 | no | calor | 55 | 88 | volcan | `explosive` |
| 30 | `thermal_soup` | nuevo, necesita modelo | 2×3×2 | 5 | no | calor | 60 | 96 | nieve | `liquid` |

### Lote 4 · grandes y raros (D-1805)

| # | id | Contenido base | Celdas | kg | Frágil | Temp. | Compra | Venta | Zona | Trampa |
|---|---|---|---|---|---|---|---|---|---|---|
| 31 | `bicycle` | nuevo, necesita modelo | 4×3×1 | 12 | no | ambiente | 80 | 128 | suburbio | `balance` |
| 32 | `mattress` | nuevo, necesita modelo | 4×1×4 | 15 | no | ambiente | 75 | 120 | suburbio | `growing_weight` |
| 33 | `potted_plant` | nuevo, necesita modelo | 3×4×3 | 9 | no | ambiente | 30 | 48 | suburbio | `balance` |
| 34 | `fish_tank` | nuevo, necesita modelo | 4×3×2 | 14 | sí | ambiente | 80 | 128 | puerto | `liquid` |
| 35 | `golf_clubs` | nuevo, necesita modelo | 1×4×2 | 7 | no | ambiente | 50 | 80 | suburbio | `balance` |
| 36 | `surfboard` | nuevo, necesita modelo | 4×1×2 | 6 | sí | ambiente | 60 | 96 | islas | `fragile` |
| 37 | `ski_pair` | nuevo, necesita modelo | 4×1×1 | 5 | no | ambiente | 55 | 88 | nieve | `balance` |
| 38 | `beehive` | nuevo, necesita modelo | 3×3×3 | 10 | no | ambiente | 65 | 104 | campo | `hostile` |
| 39 | `rooster_crate` | nuevo, necesita modelo | 3×3×2 | 6 | no | ambiente | 40 | 64 | campo | `noisy` |
| 40 | `volcanic_rock_crate` | nuevo, necesita modelo | 3×2×3 | 20 | no | calor | 45 | 72 | volcan | `explosive` |

## Distribución

| Zona | F1 | Lotes 2-4 | Total |
|---|---|---|---|
| centro | 6 | 5 | 11 |
| campo | 4 | 3 | 7 |
| suburbio | 0 | 7 | 7 |
| puerto | 0 | 3 | 3 |
| islas | 0 | 4 | 4 |
| montana | 0 | 2 | 2 |
| nieve | 0 | 4 | 4 |
| volcan | 0 | 2 | 2 |

Temperatura: 27 ambiente, 9 frío, 4 calor.

## Decisiones tomadas

- Los 10 contenidos existentes son los 10 productos de F1 (S9). Los 30 nuevos son los lotes 2, 3 y 4 de
  D-1803 a D-1805. D-1802 ("lote 1") queda cubierto por los contenidos existentes: se reduce a revisar
  sus modelos (escala al bloque de celdas) en vez de modelar 10 piezas nuevas.
- `milk_canister` y `wedding_cake` figuran como `frío` aunque F1 no lo simula: así D-0616 no obliga a
  cambiar el catálogo.
- Celdas de los altos (`glass_tower`, `wedding_cake`): 2×3×2, no 2×5×2, para entrar en la caja M. El modelo
  se escala; la caja `tall` queda como embalaje ajustado.
- Todos los precios caben entre 20 y 80, incluso los grandes (bici, pecera): la rareza se paga con celdas y
  envío, no con compra.
