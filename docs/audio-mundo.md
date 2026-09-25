# Audio del mundo y del camión: calma y claridad

## Dirección sonora (2026-09-25)

Pedido del usuario: buscar la sensación relajante que asocia con Minecraft. Para
Take My Package, el objetivo es un mundo agradable de habitar: sonidos cálidos,
espacio entre eventos y una base tranquila sobre la que se entiendan los accidentes
y avisos. Es una referencia de sensación; la identidad sonora se construye con los
materiales, el campo y el reparto de este juego.

Criterios para cualquier sonido nuevo:

- **Timbre suave:** ataques redondeados, colas cortas o naturales; evitar pitidos
  agudos sostenidos, estática decorativa y graves que retumben constantemente.
- **Dejar respirar:** naturaleza en frases separadas, variaciones pequeñas de
  duración e intensidad y silencios perceptibles. Evitar repetir un evento corto
  como un metrónomo durante toda la partida.
- **Materiales cercanos y agradables:** pasos, cartón, madera y objetos del camión
  deben comunicar su acción con poco volumen. Reservar lo más marcado para un
  peligro inmediato o una acción que necesita confirmación.
- **Música ocasional:** entradas y salidas suaves, afinación estable, frases
  sencillas y descanso entre apariciones. La música comparte espacio con el mundo
  y con las conversaciones de los jugadores.
- **Evaluar el conjunto:** escuchar depósito, caminata y conducción con auriculares
  y parlantes, incluyendo varios minutos seguidos. Un sonido no está aprobado por
  cumplir un número: no debería cansar ni obligar a bajar todos los efectos para
  tolerar una sola fuente.

Primera implementación:

- `ingame_music.gd` conserva la pista actual, pero espera 18–35 s al entrar y
  45–85 s entre reproducciones, con fundidos de 5 s al entrar y 7 s al salir.
  La capa de peligro ya no cambia la afinación, baja 10 dB y aparece solamente
  cuando una caja está en riesgo; los golpes anteriores no sostienen el pulso.
- `ambient_birds()` reparte cinco frases en 28 s, con silbidos menos agudos y
  ataques redondeados. La mayor parte del buffer queda en silencio.
- La radio del depósito usa `mus_depot_radio_loop.ogg`, integrado desde `main`.
  Su mezcla se comprueba junto con las otras pistas.
- Los avisos de bocina, cruce, trampas y golpes conservan sus niveles. Los grillos
  mantienen las frases y pausas incorporadas en el playtest anterior.

Pruebas automáticas: `test_tension_music` verifica pausas, fundidos, afinación y
recuperación de la calma; `test_world_audio_levels` verifica mezcla, espacios de
silencio y extremos sin saltos en pájaros. **Pendiente de evaluación auditiva:**
confirmar la sensación y fatiga en una partida; estos tests no pueden medirlas.

## Base de mezcla

Tarea de Nacho N-404 (2026-09-24). Los niveles se comprueban con mediciones para evitar
desbalances. La elección de timbres y su comodidad se valida además escuchando
(fila #83 de "Para cuando haya playtesting" en `docs/tareas-nacho.md`).

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
| ruido | RMS del loop | −35 dBFS | viento y ruta lejana: siseo de banda ancha (a −28 sonaba como lluvia sobre el techo del depósito) |
| naturaleza | 100 ms más fuertes | −24 dBFS | pájaros o grillos (chirridos con silencio en el medio: su RMS no dice cuán fuerte suenan) |
| lluvia | RMS del loop | −32 dBFS | afuera (era −24 y tapaba todo); en la cabina +3 dB; dentro del depósito no se oye (se apaga en ~½ s al entrar) |
| señal | 100 ms más fuertes | −18 dBFS | bocina, derrape, campana del cruce, timbre, perro, ovejas, vecino, portón del depósito |
| detalle | pico | −26 dBFS | objetos sueltos en la caja de carga |
| música | RMS del loop | −24 dBFS | la radio del depósito (bus Music) |
| máquina | RMS del loop | −40 dBFS | el motor del autoelevador que va y viene |
| repetido | 100 ms más fuertes | −30 dBFS | el beep de marcha atrás del autoelevador, una y otra vez |

Las dos últimas empezaron en "fondo" y "señal", y el depósito quedó molesto (reporte del usuario,
2026-09-24): un sonido que no para tiene que quedar bien por debajo de uno que llama una vez. Lo
mismo con el viento y la ruta lejana (clase "ruido"): a −28 se oían como lluvia fea en el
depósito, y el viento además no se apagaba bajo techo; ahora `route_sky.gd` lo baja 9 dB adentro
(cabina o depósito) como a los pájaros y la ruta.

Los de "señal" usan el mismo objetivo que la S-404 de Slatex para los efectos de trampa
(−18 dBFS RMS), así los dos dominios quedan en la misma escala.

## Encontrar un sonido que molesta: "Sonidos del juego"

En Opciones, "Sonidos del juego (uno por uno)…" lista todo lo que está cargado, con quién lo
toca ("Autoelevador · Motor", "Caja (trampa) · Crujido de madera"…), si está sonando ahora y su
bus, y deja silenciar cada uno o escuchar uno solo. Abierta desde la pausa, el juego sigue
sonando mientras está abierta: uno se para donde se oye el ruido y prueba. El silencio dura
hasta cerrar el juego. `presentation/sound_audit.gd` + `ui/sound_check_panel.gd`,
`test_sound_check`.

Así apareció el ruido del playtest: el **zumbido del depósito**. Era un sonido 3D con `unit_size`
30 a 4 m sobre la zona de carga, y el volumen de Godot sube por encima del nivel medido cuando uno
está más cerca que `unit_size`: debajo, ~+17 dB. Ahora no tiene caída por distancia (el nivel medido
en todo el piso, bajando hacia los bordes hasta `max_distance`) y el loop no tiene el hueco que
tenía cada 3 s. Regla para lo nuevo: un tono de ambiente no es una fuente puntual. Aun así molestaba y, por
pedido del usuario, **se sacó**: el depósito ya no tiene zumbido.

## Sonidos rehechos por el playtest del 2026-09-25

Reporte del usuario: "un ruido como de interferencia" que obligaba a bajar los efectos, el
grillo en bucle y un ladrido que no parecía ladrido. En `synth_audio.gd`:

- **Viento** y **ruta lejana**: eran ruido por debajo de ~50-70 Hz, un retumbo sub-grave
  que en auriculares suena a viento pegando en un micrófono. Ahora son una banda de ruido
  (~160-870 Hz el viento, ~130-500 Hz la ruta), con ráfagas que abren la banda, loops de
  10 y 12 s que empalman con fundido cruzado (antes el vaivén del viento se cortaba cada 4 s)
  y a 11025 Hz, porque no tienen nada arriba de 1 kHz.
- **Crujido de Peso creciente** (bus de efectos): era un diente de sierra con la frecuencia
  sorteada en cada muestra, un zumbido de estática que se repetía más seguido cuanto más
  pesaba la caja. Es el candidato más fuerte a "interferencia": estaba en el bus que el
  usuario bajó. Ahora es stick-slip: golpecitos irregulares que hacen sonar tres
  resonancias de madera. Mismos 100 ms más fuertes que antes.
- **Grillos**: tres grillos a distintas distancias, frases de 3 a 7 chirridos y 3 a 7 s de
  silencio entre frases (loop de 20 s, casi todo silencio). Quedan 1,5 dB por debajo del
  objetivo de naturaleza a propósito.
- **Ladrido**: voz armónica con tono que sube al abrirse y cae, soplo, y dos formantes que
  van de "u" a "a" ("guau"). `chasing_dog.gd` ladra con intervalos al azar y a veces doble.

Estos cinco se normalizan solos al generarse (`_normalized()`, con la misma medida que el
test), así que su nivel en `world_mix.gd` es el objetivo de la clase menos esa constante.

## Antes y después

Resultado = sonido medido + nivel del reproductor, en dBFS con la medida de su clase.

| Sonido | Clase | Nivel antes | Resultado antes | Nivel ahora | Resultado ahora |
|---|---|---|---|---|---|
| Motor del camión | motor | −21 | −33,8 | −7 | −19,8 |
| Golpe del camión | golpe | −6 | −6,0 | −14 | −14,4 |
| Derrape | señal | −14 | −23,9 | −8 | −17,9 |
| Bocina | señal | −6 | −13,3 | −10,5 | −17,8 |
| Objetos sueltos | detalle | −20 | −20,0 | −26 | −26,4 |
| Viento | ruido | −26 | −39,4 | −15 | −35,0 |
| Pájaros | naturaleza | −24 | −43,3 | −4,5 | −24,5 |
| Grillos | naturaleza | −24 | −43,9 | −5,5 | −25,5 |
| Ruta lejana | ruido | −31 | −46,8 | −15 | −35,0 |
| Lluvia (afuera) | lluvia | −17 | −41,3 | −8 | −32,3 |
| Campana del cruce | señal | 0 | −17,4 | 0 | −17,4 |
| Ladrido | señal | 0 | −10,6 | −6 | −18,0 |
| Balido | señal | 0 | −10,3 | −7,5 | −17,8 |
| Timbre de la casa | señal | 0 | −11,1 | −7 | −18,1 |
| Vecino contento | señal | 0 | −7,3 | −10,5 | −17,8 |
| Vecino que se queja | señal | 0 | −4,8 | −13 | −17,9 |
| Radio del depósito | música | −9 | −32,3 | −0,5 | −24,0 |
| Beep del autoelevador | repetido | −14 | −26,3 | −17,5 | −29,8 |
| Motor del autoelevador | máquina | −30 | −42,8 | −27 | −39,8 |
| Portón | señal | −4 | −21,0 | −1 | −18,0 |

Qué cambia al jugar:

- Antes, el mundo sonaba al revés: el motor, el viento y la lluvia quedaban 11 a 17 dB por
  debajo de su objetivo, y los sonidos de un disparo (golpes, perro, ovejas, vecino) 5 a 13 dB
  por encima.
- Ahora el motor y la lluvia se oyen de fondo continuo, y las señales sobresalen parejas por encima.
- Los desvíos relativos que eran de diseño se conservan: el vecino se queja 6 dB más bajo por
  una caja golpeada y 10 dB más bajo por la caja equivocada; la lluvia suena 3 dB más fuerte
  en la cabina y no se oye dentro del depósito; afuera se oye 9 dB más apagado desde adentro (`route_sky.gd`).

## Lo que se sumó el 2026-09-25

- **Motor en capas (N-401).** Tres loops del mismo motor —en ralentí (`engine_idle_loop()`), el de
  siempre (`engine_loop()`) y acelerado (`engine_high_loop()`)— sintetizados al mismo RMS, así que
  el cruce no sube ni baja el volumen. `vehicle_presentation.gd` simula un cuentavueltas con caja:
  las RPM salen de la velocidad por la marcha puesta, suben al acelerar parado, y al pasar el punto
  de cambio se corta el acelerador `shift_seconds` y las vueltas caen a las de la marcha nueva (el
  "bajón"). La clásica: 4 marchas, corte a 3500 rpm, 0,38 s por cambio; la ágil: 5 marchas, corte
  a 5000, 0,16 s y todo un 14 % más agudo. Mezcla por potencia constante (raíz del peso de cada
  capa). Las tres capas entran en `test_world_audio_levels` con el nivel del motor.
- **Eco bajo techo (N-402).** `presentation/acoustic_space.gd` agrega, una vez y en tiempo de
  ejecución, una reverb a los buses `SFX` y `Exterior`, y la prende según dónde esté la cámara de
  cada cliente: en un túnel (`AcousticZone` a lo largo de cada `TunnelSegment`) sala 0,95, húmedo
  0,42, predelay 70 ms; bajo el techo del depósito sala 0,8, húmedo 0,26, 40 ms; al aire libre,
  apagada. `default_bus_layout.tres` no cambió. De paso, #68: una cámara anclada al camión desde
  afuera (la de persecución) ya no cuenta como "adentro" para la lluvia y el ambiente.
- **Música del menú y radio del depósito (N-403).** `mus_menu_loop.ogg` (112 BPM, do mayor, 34 s) y
  `mus_depot_radio_loop.ogg` (88 BPM con swing, fa mayor, 44 s, por un parlante chico con
  crujidos), compuestas por `tools/audio/compose_music.py` —síntesis propia, sin samples ni
  terceros; licencia en `assets/audio/music/LICENCIA.md`—. Como Godot no le da a un test las
  muestras de un `.ogg`, el compositor anota el RMS de cada archivo en
  `assets/audio/music/loudness.json` y el test de niveles lo usa.

| Sonido | Medido (dBFS) | Nivel (dB) | Resultado | Objetivo |
|---|---|---|---|---|
| Radio del depósito (música) | −19,4 RMS | −4,5 | −23,9 | −24 |
| Tema del menú | −16,6 RMS | −13,2 | −29,8 | igual que la música del juego (−15,8 − 14 = −29,8) |
