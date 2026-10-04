# Boceto del mapa del mundo (D-0301)

> Fuente de los `bounds` de `data/zones/*.tres` (D-0205) y del grafo de calles (D-0304). Sigue
> `docs/decisiones/2026-10-04-mapa-continuo.md` (trazado fijo, ≤ 6 × 6 km, celdas de 256 m) y
> [distritos.md](distritos.md). Coordenadas en metros, **X** al este, **Z** al sur, origen en el centro del
> galpón. Una celda = 256 m, así que todo `bounds` es múltiplo de 256.

## Reglas

- Mapa total: X y Z de −3072 a +3072 (`MAP_LIMIT` de `test_zone_definitions`), 24 × 24 celdas. Lo
  transitable en F1 es una fracción: el resto es costa, montaña o relleno liviano.
- Velocidad de referencia de la camioneta: 12 m/s (43 km/h) de promedio con curvas y tránsito.
- **Regla de oro (N-102):** del portón a la primera casa de Centro ≤ 90 s (≤ 1080 m); a la primera de
  Campo ≤ 3 min (≤ 2160 m). Las salidas completas de [distritos.md](distritos.md) (2-5 min) se cuentan
  desde el portón hasta la última parada de ida.

## Zonas (en celdas de 256 m, x0..x1 / z0..z1)

| Zona | `bounds` (x, z, ancho, alto) | Celdas | Lado |
|---|---|---|---|
| `parque_industrial` | (−256, −256, 512, 512) | −1..1 / −1..1 | centro, galpón en el origen |
| `centro` | (256, −512, 768, 1024) | 1..4 / −2..2 | este del galpón |
| `suburbio` | (−1280, −512, 1024, 1024) | −5..−1 / −2..2 | oeste |
| `campo` | (−1280, 512, 2304, 1536) | −5..4 / 2..8 | sur |
| `puerto` | (1024, −512, 1024, 2560) | 4..8 / −2..8 | este de Centro, sobre la costa |
| `islas` | (2048, −1536, 1024, 3584) | 8..12 / −6..8 | mar al este del Puerto |
| `montana` | (−1280, −2048, 1536, 1536) | −5..1 / −8..−2 | norte-oeste |
| `nieve` | (−1280, −3072, 1536, 1024) | −5..1 / −12..−8 | detrás de Montaña |
| `volcan` | (256, −3072, 1792, 1536) | 1..8 / −12..−6 | norte-este |

Vista de arriba (cada letra ≈ una celda de 512 m; norte arriba):

```
 X→   -1280    -256  0  256   1024   2048   3072
 -3072 +--------------+--------------------+
       | NIEVE        | VOLCÁN             |
 -2048 +--------------+                    |
       | MONTAÑA      |                    |  ~ mar ~
 -1536 |  (sin camino |--------------------+  ISLAS
       |   desde el   |                    |  (agua)
 -512  +--------------+---+-----+----------+
       | SUBURBIO     | G | CEN | PUERTO   | ~ costa ~
  512  +--------------+---+-----+          |
       |                              |    |
       | CAMPO                        |    |
 2048  +------------------------------+----+
```

G = Parque Industrial (galpón). El Puerto cubre el borde este de Centro hasta la costa en X = 2048;
Islas está en el agua, más allá.

## Calles principales

Tres calles salen del Parque Industrial (nodos del grafo de D-0304, posiciones aproximadas):

1. **Avenida Este** (`asphalt`): portón (0, 0) → (256, 0) entrada de Centro → (1024, 0) borde del Puerto →
   (1792, 256) muelle. Sirve a Centro y Puerto.
2. **Camino del Campo** (`gravel` desde Z = 512): portón → (0, 512) → (0, 1024) → (−640, 1536) →
   (512, 1792). Sirve al Campo; ~1.5 km hasta la primera chacra.
3. **Calle Oeste** (`asphalt`): portón → (−256, 0) → (−768, 0) → (−1024, −256). Sirve al Suburbio.

Fuera del llano: **sin calle desde el llano a Montaña, Nieve y Volcán**. Se llega en avioneta a las pistas
(Montaña (−512, −1280), Volcán (1024, −2304)) y adentro hay un tramo corto de calle local de 4x4.

## Bloqueos (D-0306)

| id | Tipo | Posición (x, z) | Dónde | Estado inicial |
|---|---|---|---|---|
| `gate_suburbio` | barrera (guardia + tranquera) | (−768, 0) | Calle Oeste, borde de Suburbio | cerrado, hito de 25 entregas |
| `gate_campo_obra` | calle cortada (obra, vallas) | (0, 512) | Camino del Campo, a 512 m del portón | cerrado, hito de reputación 60 |
| `gate_puerto` | barrera portuaria | (1024, 0) | Avenida Este, entrada al Puerto | cerrado, hito + licencia náutica |
| `gate_islas_agua` | agua (sin colisión) | x = 2048 | costa del Puerto | cerrado, lancha |
| `gate_montana_altura` | altura (sin colisión) | borde norte z = −512 | cordillera entre el llano y Montaña | cerrado, avioneta |
| `gate_nieve_equipo` | equipo (cartel + guardaparque) | (−512, −2048) | límite Montaña/Nieve | cerrado, cadenas + abrigo |
| `gate_volcan_equipo` | equipo (cartel + guardaparque) | (1024, −1536) | base del Volcán | cerrado, traje térmico + cajas térmicas |

Centro y Parque Industrial son abiertos desde el inicio.

## Chequeo de la regla de oro

| Destino | Camino | Largo | Tiempo a 12 m/s | Límite |
|---|---|---|---|---|
| Primera casa de Centro | Avenida Este hasta (384, 0) | ~400 m | ~33 s | 90 s ✔ |
| Última casa de Centro | hasta (1000, 450) | ~1100 m | ~92 s | salida completa 2-3 min ✔ |
| Primera chacra de Campo | Camino del Campo hasta (0, 1536) | ~1550 m | ~130 s | 3 min ✔ |
| Última chacra de Campo | hasta (512, 1900) | ~2100 m | ~175 s | 5 min con paradas ✔ |

## Decisiones

- **Decisión: Campo al sur y Centro al este**, porque `bounds` de D-0205 ya los tiene así y el Campo
  actual necesita tramo largo continuo (gravel/barro) que quepa en 2304 × 1536 m.
- **Decisión: Puerto al este de Centro** (no al costado del galpón) para que la costa quede lejos y el
  Puerto sea una segunda zona de la misma avenida, detrás de su barrera.
- **Decisión: las coordenadas de bloqueo son del boceto**; D-0304/D-0306 pueden moverlas hasta 128 m para
  encajar con la geometría real sin cambiar el tipo ni el hito.
