# Lo que armás es la trampa (D-0109)

> Fuente de D-0709 (calidad del armado) y D-0710 (calidad → trampa). Los números base están en
> [supuestos.md](../detalle/supuestos.md); acá se fijan los casos y los ejemplos que repite el test de D-0709.
> Todo valor numérico vive en `company_tuning.gd` (D-0202), nunca suelto en el código.

## 1. La trampa sale del producto

Un producto es un `ProductDefinition` que referencia un `PackageContent` (S9). La trampa es la del
`TrapDefinition` que lista ese contenido en `data/traps/*.tres`. El armado **no cambia qué trampa es**:
cambia **cuánto pega** (`impact_absorption`, intensidad).

| Contenido (`data/contents/`) | Trampa actual | Dif. | Qué la baja (embalaje) | Qué la sube (error) |
|---|---|---|---|---|
| `porcelain_vase` | `fragile` | 1 | Relleno en todas las celdas libres; caja ajustada | Sin relleno; caja grande; mezclado con algo pesado |
| `antique_lamp` | `fragile` | 1 | Relleno completo; etiqueta "frágil" | Sin relleno; caja grande |
| `glass_tower` | `balance` | 2 | Caja alta (`tall`) ajustada; relleno a los lados | Caja ancha con huecos; sin relleno |
| `wedding_cake` | `balance` | 2 | Caja alta ajustada; relleno | Caja grande; sin relleno |
| `sourdough` | `growing_weight` | 2 | Caja plana (`flat`); sello de ventilación | Sin sello; caja cerrada con cinta sin ventilar |
| `milk_canister` | `liquid` | 2 | Cinta y sello de cierre; relleno contra el vuelco | Sin cinta; sin sello; huecos |
| `hen` | `noisy` | 3 | Caja ventilada (`vented`); sello de ventilación; relleno suave | Caja sin ventilar; sin sello |
| `puppy` | `noisy` | 3 | Caja ventilada; sello de ventilación; relleno | Caja sin ventilar; sin sello |
| `fireworks_crate` | `explosive` | 4 | Sello de seguridad; relleno completo; caja ajustada | Sin sello; sin relleno; mezclado con un frágil (prohibido) |
| `raccoon_cage` | `hostile` | 4 | Caja ventilada reforzada; sello de jaula; caja ajustada | Sin sello; caja grande; sin ventilar |

(Dificultad = `difficulty` del `.tres`. Los sellos requeridos por producto los define el `.tres` de
producto en D-0204; los de esta tabla son los propuestos: `vent` para sourdough/hen/puppy, `seal` para
milk_canister, `safety` para fireworks_crate, `cage` para raccoon_cage.)

## 2. Calidad `Q` (0-100)

Definiciones sobre una caja de `T` celdas (X×Y×Z), con `P` celdas ocupadas por productos, `L = T − P`
celdas libres y `R` celdas de relleno (`R ≤ L`):

- `libres_sin_relleno = L − R`; `f = libres_sin_relleno / T` (fracción de la **caja**, así un hueco
  chico en una caja casi llena casi no castiga).
- `protección = R / L` (1 si `L = 0`).
- `frágil` = el producto tiene trampa `fragile` o `balance` de vidrio (`porcelain_vase`, `antique_lamp`,
  `glass_tower`).

```
Q = 100
  − 40                      si el contenido no coincide con el pedido
  − 30 × f × (1,5 si hay un producto frágil, si no 1)
  − 15 × sellos_requeridos_que_faltan
  − 10                      si falta la cinta o la etiqueta (una sola vez, no por cada una)
Q = clamp(Q, 0, 100)
```

`impact_absorption = lerp(1.0, 0.6, protección)` (mismo campo que `Depot.PADDING_ABSORPTION = 0.75` pone hoy
con el relleno del depósito: protección total da 0,6, mejor que el 0,75 actual).

**Caja demasiado grande**: si `f > 0,5`, suma la trampa `balance` con intensidad baja (0,3).

## 3. Reglas de mezcla

1. Dos o más productos en una caja: **manda la trampa del de mayor dificultad** según
   `UnlockManager.TRAP_DIFFICULTY_ORDER` (`fragile`, `balance`, `growing_weight`, `liquid`, `noisy`,
   `explosive`, `hostile`; el que aparece más a la derecha).
2. **Explosivo + frágil → prohibido**: la grilla no deja confirmar la caja y dice por qué.
3. Un producto `hostile` o de contenido vivo (`hen`, `puppy`, `raccoon_cage`) no comparte caja con
   otro producto vivo ni con líquido. (Decisión: evita cajas con dos trampas de ruido a la vez.)
4. Más de un sello requerido: se cuentan por separado (cada faltante resta 15).

## 4. Seis ejemplos resueltos

Todos con cinta y etiqueta puestas, salvo donde se aclare. Los repite `test_company_packing_quality`
(D-0709) y los usa D-0710.

| # | Caja | Producto | Armado | Cuenta | `Q` | `protección` | `impact_absorption` | Trampa |
|---|---|---|---|---|---|---|---|---|
| 1 | M 3×3×3 (`T`=27) | `porcelain_vase`, `P`=8, `L`=19 | `R`=19, sin faltantes | `f`=0 → 100 | **100** | 1,000 | **0,600** | `fragile` |
| 2 | M | `porcelain_vase`, `P`=8 | `R`=0 | `f`=19/27=0,7037; 30×0,7037×1,5=31,67 | **68,33** | 0,000 | **1,000** | `fragile` + `balance` baja (`f`>0,5) |
| 3 | M | `porcelain_vase`, `P`=8 | `R`=10 | `f`=9/27=0,3333; 30×0,3333×1,5=15 | **85,00** | 10/19=0,5263 | **0,789** | `fragile` |
| 4 | S 2×2×2 (`T`=8) | `hen`, `P`=4, `L`=4, sello `vent` puesto | `R`=2, **sin cinta** | `f`=2/8=0,25; 30×0,25=7,5; −10 | **82,50** | 0,500 | **0,800** | `noisy` |
| 5 | L 4×3×3 (`T`=36) | `fireworks_crate`, `P`=12, `L`=24 | `R`=24, **falta el sello `safety`** | `f`=0; −15 | **85,00** | 1,000 | **0,600** | `explosive` |
| 6 | M | `milk_canister`, `P`=12, `L`=15, pedido era otro producto | `R`=15 | −40 (contenido equivocado) | **60,00** | 1,000 | **0,600** | `liquid` (y la caja paga 0 al entregar) |

Verificación de las cuentas (por si el test las rehace): ejemplo 3: `absorption = 1 − 0,4 × 0,5263 = 0,7895`
(se redondea a 3 decimales: 0,789); ejemplo 4: `1 − 0,4 × 0,5 = 0,8`.

## 5. Intensidad de la trampa en el viaje (propuesta para D-0710)

`intensidad = clamp(1 − Q/100, 0, 1)` sumada al piso de la dificultad base del `.tres`: con `Q`=100 la
trampa se comporta como hoy en su nivel más bajo; con `Q`=0, en el más alto. D-0710 la ajusta con
`sim_trap_balance`; este documento fija solo la dirección (más calidad, menos intensidad).

## Decisiones tomadas

- `f` se mide sobre la caja entera, no sobre las celdas libres (más estable para cajas casi llenas).
- Cinta y etiqueta faltantes restan 10 **una vez**, no 20.
- Protección total da absorción 0,6 (más fuerte que el relleno actual de 0,75): el armado manual tiene que
  valer más que el relleno automático de la partida rápida.
- Vidrio (`glass_tower`) cuenta como frágil para el ×1,5 aunque su trampa sea `balance`.
