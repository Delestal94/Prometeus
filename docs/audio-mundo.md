# Audio del mundo y del camión: mezcla medida

Tarea de Nacho N-404 (2026-09-24). Los sonidos del mundo y del camión se nivelan midiendo, no
de oído: el oído queda para cuando haya playtesting (fila #83 de "Para cuando haya
playtesting" en `docs/tareas-nacho.md`).

## Cómo se mide

- Todos los sonidos salen de `scripts/presentation/synth_audio.gd` (WAV mono de 16 bits).
  `tests/test_world_audio_levels.gd` genera cada uno, lo mide en dBFS y le suma el `volume_db`
  con que se reproduce. Ese resultado tiene que caer a ±2 dB del objetivo de su clase.
- Los niveles viven todos en un solo lugar: `scripts/presentation/world_mix.gd`. Los scripts
  que reproducen sonidos (camión, ruta, cielo, depósito, casas) los leen de ahí.
- Para los sonidos 3D, el nivel es el de la distancia de referencia del reproductor
  (`unit_size`): de ahí para afuera baja con la distancia como siempre.
- Tabla completa: `<godot> --headless --path do-not-drop --script res://tests/test_world_audio_levels.gd -- --report`.
- Los sonidos con ruido cambian un poco en cada síntesis (±0,5 dB). Por eso la tolerancia es de 2 dB.

## Clases y objetivos

| Clase | Medida | Objetivo | Qué entra |
|---|---|---|---|
| motor | RMS del loop | −20 dBFS | motor del camión a fondo |
| golpe | pico | −14 dBFS | el golpe más fuerte del camión |
| fondo | RMS del loop | −28 dBFS | viento, ruta lejana |
| naturaleza | 100 ms más fuertes | −24 dBFS | pájaros o grillos (chirridos con silencio en el medio: su RMS no dice cuán fuerte suenan) |
| lluvia | RMS del loop | −24 dBFS | afuera; bajo techo (cabina, depósito) +6 dB |
| señal | 100 ms más fuertes | −18 dBFS | bocina, derrape, campana del cruce, timbre, perro, ovejas, vecino, portón del depósito |
| detalle | pico | −26 dBFS | objetos sueltos en la caja de carga |
| música | RMS del loop | −24 dBFS | la radio del depósito (bus Music) |
| sala | RMS del loop | −42 dBFS | el zumbido del depósito: siempre prendido, se siente más de lo que se oye |
| máquina | RMS del loop | −40 dBFS | el motor del autoelevador que va y viene |
| repetido | 100 ms más fuertes | −30 dBFS | el beep de marcha atrás del autoelevador, una y otra vez |

Las tres últimas empezaron en "fondo" y "señal", y el depósito quedó molesto (reporte del usuario,
2026-09-24): un sonido que no para tiene que quedar bien por debajo de uno que llama una vez.

Los de "señal" usan el mismo objetivo que la S-404 de Slatex para los efectos de trampa
(−18 dBFS RMS), así los dos dominios quedan en la misma escala.

## Antes y después

Resultado = sonido medido + nivel del reproductor, en dBFS con la medida de su clase.

| Sonido | Clase | Nivel antes | Resultado antes | Nivel ahora | Resultado ahora |
|---|---|---|---|---|---|
| Motor del camión | motor | −21 | −33,8 | −7 | −19,8 |
| Golpe del camión | golpe | −6 | −6,0 | −14 | −14,4 |
| Derrape | señal | −14 | −23,9 | −8 | −17,9 |
| Bocina | señal | −6 | −13,3 | −10,5 | −17,8 |
| Objetos sueltos | detalle | −20 | −20,0 | −26 | −26,4 |
| Viento | fondo | −26 | −39,4 | −14,5 | −27,5 |
| Pájaros | naturaleza | −24 | −43,3 | −4,5 | ≈ −23,8 |
| Grillos | naturaleza | −24 | −43,9 | −4 | ≈ −23,9 |
| Ruta lejana | fondo | −31 | −46,8 | −12 | −27,8 |
| Lluvia (afuera) | lluvia | −17 | −41,3 | 0 | −24,3 |
| Campana del cruce | señal | 0 | −17,4 | 0 | −17,4 |
| Ladrido | señal | 0 | −10,6 | −7,5 | −18,0 |
| Balido | señal | 0 | −10,3 | −7,5 | −17,8 |
| Timbre de la casa | señal | 0 | −11,1 | −7 | −18,1 |
| Vecino contento | señal | 0 | −7,3 | −10,5 | −17,8 |
| Vecino que se queja | señal | 0 | −4,8 | −13 | −17,9 |
| Zumbido del depósito | sala | −20 | −40,5 | −21,5 | −42,0 |
| Radio del depósito | música | −9 | −32,3 | −0,5 | −23,8 |
| Beep del autoelevador | repetido | −14 | −26,3 | −17,5 | −29,8 |
| Motor del autoelevador | máquina | −30 | −42,8 | −27 | −39,8 |
| Portón | señal | −4 | −21,0 | −1 | −18,0 |

Qué cambia al jugar:

- Antes, el mundo sonaba al revés: el motor, el viento y la lluvia quedaban 11 a 17 dB por
  debajo de su objetivo, y los sonidos de un disparo (golpes, perro, ovejas, vecino) 5 a 13 dB
  por encima.
- Ahora el motor y la lluvia se oyen de fondo continuo, y las señales sobresalen parejas por encima.
- Los desvíos relativos que eran de diseño se conservan: el vecino se queja 6 dB más bajo por
  una caja golpeada y 10 dB más bajo por la caja equivocada; la lluvia suena 6 dB más fuerte
  bajo techo; afuera se oye 9 dB más apagado desde adentro (`route_sky.gd`).
