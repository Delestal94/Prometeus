# F1 · Grupo 09 — Galpón construible (detalle)

> Carril 2 de la rutina `desarrollador`. Solo las tareas que ya se construyeron o se están construyendo;
> el resto sigue en la tabla de [09-galpon-construible.md](../09-galpon-construible.md) y se detalla
> cuando le toque a un carril. Números de [supuestos.md](supuestos.md).

### D-0904 · Objetos colocables iniciales — A · Sonnet 5.5 · medium · Aviso: no · F1
**[x] Hecho (2026-10-04, PR pendiente)** — `PlaceableDefinition` (`scripts/gameplay/business/placeable_definition.gd`) + 4 `.tres` en `data/placeables/` (mesa de armado, estante, heladera, zona de despacho); `test_placeable_definitions`.
**Depende de:** nada que falte (solo datos; la grilla de colocación D-0225 y el layout D-0620 los usan, no al revés)
**Qué:** `class_name PlaceableDefinition`, `Resource` solo de datos como `ProductDefinition`:
`id`, `display_key` (`WORLD_PLACEABLE_<ID>`), `footprint` (celdas X×Z), `height_m`, `price`, `role`
(`assembly` / `storage` / `dispatch`), `slots`, `cold`, `blocks_walking`, `owned_at_start`.
- `footprint_for(quarter_turns)`: huella girada (cuartos de vuelta impares cambian X por Z).
- `refund()`: `floor(price × CompanyTuning.PLACEABLE_REFUND_RATIO)` (base de D-0920).
- Celda del galpón: `CompanyTuning.WAREHOUSE_GRID_M = 1.0` (no es la celda de 0,2 m del armado).

| Objeto | Huella | Alto | Precio | Rol | Huecos | Propio al inicio |
|---|---|---|---|---|---|---|
| `assembly_table` | 2×1 | 0,9 m | 120 | armado | 0 | sí |
| `shelf` | 2×1 | 2,0 m | 80 | estante | 8 | sí |
| `fridge` | 1×1 | 1,9 m | 200 | estante frío | 4 | no (D-0616/D-0617) |
| `dispatch_zone` | 3×2 | 0,05 m | 60 | despacho | 0 | sí, y no bloquea el paso |

**Test** `test_placeable_definitions`: los 4 archivos cargan con id y clave correctos, huella/alto/precio
positivos, rol conocido, solo los estantes tienen huecos, solo la heladera es fría, solo el despacho se
puede pisar, la rotación y el reembolso.
**Hecho cuando:** 4 objetos `.tres` y el test pasa.

### D-0912 · Electricidad como restricción de máquinas — A · Sonnet 5.5 · low · Aviso: no · F1
**[x] Hecho (2026-10-04, PR pendiente)** — decidido **no**: sin enchufes ni tablero; `docs/decisiones/2026-10-04-sin-electricidad-en-galpon.md`.
**Depende de:** nada
**Qué:** decidir si las máquinas necesitan enchufe. Decisión: no, coherente con D-0505 (sin energía).
**Test:** ninguno (decisión). **Hecho cuando:** decisión escrita y el detalle de D-0904 y D-0922 coherente.

### D-0920 · Precio y venta con devolución parcial — B · Sonnet 5.5 · low · Aviso: no · F1
**[x] Hecho (2026-10-04, PR pendiente)** — `PlaceableShop` (`scripts/gameplay/business/placeable_shop.gd`): `buy` cobra el precio y suma la pieza al `layout`, `sell` la saca y paga `PlaceableDefinition.refund()` (50 %); `test_placeable_shop`.
**Depende de:** D-0904 (`PlaceableDefinition`), D-0501 (billetera)
**Qué:** helpers estáticos sobre el `CompanyState` que recibe el llamador (sin nombrar autoloads). Una pieza
colocada es una entrada de `layout`: `{id, x, z, turns}`. Si la celda está libre lo decide la grilla
(D-0225 / D-0902); acá solo se mueve plata y entradas. Movimientos en el libro: `placeable_buy`,
`placeable_sell`. Las piezas `owned_at_start` se agregan con `free = true` (D-0911).
**Test** `test_placeable_shop`: comprar cobra y registra; sin plata no cambia nada; `free` no cobra; vender
devuelve `floor(precio × ratio)` y quita la pieza; índice o id inválido devuelve -1 sin cambios.
**Hecho cuando:** el test pasa.
