# Modelo económico en papel (D-0117)

> Fuente de D-0502, D-0509, D-0511 a D-0515 y de `sim_economy` (D-0540). Confirma los números del corte
> vertical de [supuestos.md](../detalle/supuestos.md) y fija los que faltaban (precios de mejoras, empleados,
> palet inicial). Todo valor vive en `company_tuning.gd` / los `.tres`, nunca suelto en el código.
> Reproducible con los parámetros del §6.

## 1. Un pedido promedio

Catálogo de F1 ([catalogo-productos.md](catalogo-productos.md)): compra media de los 10 productos = **50**,
venta = compra × 1,6 = **80**. Pedido medio = 2 productos (1 a 3).

| Concepto | Valor | Cuenta |
|---|---|---|
| Venta de los productos | 160 | 2 × 80 |
| Envío (mitad Centro 40, mitad Campo 60) | 50 | |
| **Ingreso bruto del pedido** | **210** | |
| Costo de mercadería | −100 | 2 × 50 |
| Embalaje medio (caja M 3 + relleno ~4 + cinta 1) | −8 | |
| **Margen por pedido perfecto** | **≈ 102** | 49 % del ingreso |

Un pedido pierde plata solo si se cobra ≤ 51 % de la paga: **la tardanza (−25 %) nunca lo hunde**; lo que
duele es el producto roto o equivocado (esa caja paga 0 y la mercadería ya se gastó, ≈ −108).
Supuesto de la curva: **80 %** de los pedidos se cobran enteros, el resto no cobra (peor caso razonable).

## 2. Cuántos pedidos se alcanzan a cerrar

Pedidos del día = `min(16, 6 + 2 × jugadores)` → 8 / 10 / 14 para 1 / 2 / 4. La limitante al empezar no es
la demanda sino las manos: armar 20-40 s (D-0745), buscar en el estante, cargar, manejar.

| Jugadores | Pedidos que cierran el día 1 | Techo (demanda) |
|---|---|---|
| 1 | 4 | 8 |
| 2 | 7 | 10 |
| 4 | 12 | 14 |

Práctica: **+12 % por día hasta ×1,6**. Mejora 1 suma ×1,25; mejora 2 suma ×1,15. Desde ahí el techo es la
demanda: con la demanda topada la plata sobra, y **eso es a propósito**: F2+ la gasta en flota, empleados
y distritos (tablas del §4), no en más pedidos.

## 3. Stock, alquiler y arranque

- **Palet inicial regalado**: la empresa nueva empieza con **500 de plata y 10 unidades** (una de cada
  producto, valen 500 a precio de compra) para que el día 1 se juegue sin pensar compras. Es **nuevo**:
  `new_company` lo pone en la dársena como si lo hubiera traído el proveedor.
- Desde el día 1 se compra al cierre lo del día siguiente (llega 08:30). Regla de la simulación: se pide el
  110 % de lo que se espera cerrar y no se baja de **100 de caja** tras pagar el alquiler (si no alcanza,
  se compra menos).
- **Alquiler 100 por día** (confirmado). A 1 jugador el día 1 deja ~+100 neto: no quiebra jugando mal.
- **Quiebra** (D-0510): si la caja no cubre el alquiler, el día siguiente se abre con el 60 % de los
  pedidos y un aviso; no hay reinicio.

## 4. Precios de mejoras (los que faltaban)

| Qué | Precio | Para qué | Objetivo de momento de compra |
|---|---|---|---|
| **Mejora 1** (segunda mesa de armado + estantes extra) | **450** | ×1,25 de capacidad | día 2 (1-2 jug.), día 3 (4 jug.) |
| **Segundo distrito** (licencia/barrera de Suburbio, D-0312) | **1 200** | abre zona y ×1,15 | día 5 (2 y 4 jug.), día 6 (1 jug.) |
| Flota (D-0512): bici 250 · carrito 900 · 4x4 2 500 · lancha 5 000 · avioneta 12 000 | | | F2+ |
| Máquinas (D-0513): lectora de etiquetas 600 · cinta transportadora 1 500 · embaladora 4 000 | | | F2+ |
| Ampliación del galpón (D-0514): 800 / 2 000 / 5 000 | | | F2+ |
| Sueldo de empleado (D-0515, por día): novato 60 · normal 90 · experto 130 | | rinde 0,5 / 0,7 / 1,0 jugadores | F2 |

Regla de escala: cada tramo cuesta 2,5-3× el anterior; el empleado novato se paga solo si cierra ≥ 1 pedido
más por día (margen 102 > 60).

## 5. Curva de 20 días (saldo al cierre, después de comprar y de mejoras)

Mejoras compradas apenas alcanza la plata con 100 de reserva. Nunca baja de 100.

| Día | 1 jugador | 2 jugadores | 4 jugadores |
|---|---|---|---|
| 1 | 206 | 353 | 100 |
| 2 | 203 (mejora 1) | 172 (mejora 1) | 220 |
| 3 | 402 | 490 | 510 (mejora 1) |
| 4 | 638 | 990 | 1 250 |
| 5 | 924 | 290 (distrito 2) | 790 (distrito 2) |
| 6 | 104 (distrito 2) | 790 | 1 530 |
| 7 | 484 | 1 290 | 2 270 |
| 8 | 864 | 1 790 | 3 010 |
| 9 | 1 244 | 2 290 | 3 750 |
| 10 | 1 624 | 2 790 | 4 490 |
| 12 | 2 384 | 3 790 | 5 970 |
| 14 | 3 144 | 4 790 | 7 450 |
| 16 | 3 904 | 5 790 | 8 930 |
| 18 | 4 664 | 6 790 | 10 410 |
| 20 | 5 424 | 7 790 | 11 890 |

(En el día 1 la mejora se *decide* al cierre y se aplica el día siguiente; la columna marca el día del cierre
en que se paga.) Ritmo medido en saldo: 1 jugador +380/día, 2 jugadores +500, 4 jugadores +740 al llegar al
techo. Más gente rinde menos que proporcional (demanda topada): es el comportamiento buscado.

## 6. Objetivos cumplidos y números que cambian

| Objetivo | Resultado |
|---|---|
| Primera mejora día 2-3 | 1 y 2 jug.: día 2; 4 jug.: día 3 ✅ |
| Segundo distrito día 4-6 | 5 (2 y 4 jug.), 6 (1 jug.) ✅ |
| Nunca quiebra con juego correcto | mínimo 100 de caja en las tres curvas ✅ |

**Para `company_tuning.gd` (D-0202), nuevos o confirmados:** `STARTER_STOCK_UNITS = 10` (una por producto),
`RESTOCK_FACTOR = 1.1`, `CASH_RESERVE = 100`, `UPGRADE_1_PRICE = 450`, `DISTRICT_2_PRICE = 1200`,
`PRACTICE_GAIN_PER_DAY = 0.12` (solo para `sim_economy`), `ORDER_FULL_PAY_RATE_ASSUMED = 0.8` (idem), y las
tablas de flota/máquinas/ampliaciones/sueldos del §4. Confirmados sin cambios: plata 500, alquiler 100,
venta ×1,6, envío 40/60, pedidos `min(16, 6+2n)`, tardanza −25 %.

**Para el script (`sim_economy`, D-0540 en F2):** modelo del §2-§3 con estos parámetros: capacidad inicial
{1: 4, 2: 7, 4: 12}, práctica +12 %/día tope ×1,6, mejora 1 ×1,25, mejora 2 ×1,15, compra del 110 % de lo
esperado con reserva de 100, mercadería 50, embalaje 8, envío 50, 2 productos por pedido, 80 % cobrado.
