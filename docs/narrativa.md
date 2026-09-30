# Narrativa — premisa y tono (S-601)

> Última actualización: 2026-09-30
> Referencia corta para todo texto del juego con voz (cajas, radio, reclamos, trampas). Si un texto
> contradice esta página, se corrige el texto. Sin diseño de cuerpos ni caras de personajes (eso está
> pausado, S-311).

## La empresa

**Take My Package** es una empresa de entregas de un pueblo de campo que acepta lo que nadie más
acepta: tortas de bodas, gallinas, mapaches, fuegos artificiales. Su lema, en la valla de la ruta, es
**"entregamos (casi) todo"**; el diario local usa la variante "Todas las noticias que llegan (casi)
enteras". El "casi" es el chiste de la casa: la empresa lo sabe, el cliente lo sabe y nadie lo dice.
Trabaja con un solo camión, un depósito y un equipo de hasta 5 personas que se turnan para manejar
y cuidar cajas.

## Quién manda

- **La Jefa: Marta Bermúdez** (todos le dicen "la Jefa"). Dueña de la empresa. **Nunca se la ve**: solo
  habla por la **radio del depósito** (la misma que suena en el depósito) y por **notas** pegadas en cajas
  y en la pizarra. Es seca, práctica, siempre está "en otra cosa" y trata cada desastre como un trámite.
- **El Jefe del depósito** (ya existe, ver `diario-final.md`) es el encargado que sí se ve: el del
  chaleco y el mate que lee *El Eco de {pueblo}* al día siguiente. No habla por radio. La Jefa manda;
  el Jefe carga con las consecuencias.
- La competencia es una camioneta rival, sin nombre: aparece varada en la banquina.

## Por qué los paquetes son tan raros

Porque los clientes son **excéntricos del pueblo** y le mandan a Take My Package lo que las otras
empresas rechazaron. Cada uno tiene una manía y pide cosas que encajan con ella; la trampa de la caja
sale de esa manía (el que ama el silencio manda algo que hace ruido, y al revés). Los pueblos del
camino tienen nombres de humor ("Villa Frágil", "Paso del Golpe"): el mundo también sabe que esto es
una entrega complicada.

## Tono

Humor absurdo, cálido, de comedia de barrio. Nunca cruel, nunca con sangre, nunca con un animal
sufriendo: la gallina, el cachorro y el mapache siempre salen indignados, no lastimados.

| Sí | No |
|---|---|
| La culpa es de la situación (el bache, la gallina, la torta) | Burlarse del jugador que falló |
| Quejas exageradas y formales ("Voy a llamar a la empresa") | Insultos, amenazas, sarcasmo hiriente |
| Voseo rioplatense, frases cortas, un solo chiste por texto | Chistes de dos renglones o explicados |
| Los objetos rotos son graciosos (polvo, migas, plumas) | Sangre, heridas, muerte de animales |
| La Jefa minimiza el desastre | La Jefa grita o humilla |

Ejemplos en la voz correcta:

- Jefa por radio: "Chicos, la torta es para las 14. Casamiento, no velorio. Gracias."
- Nota en una caja: "Contiene una gallina. Ella ya sabe que está en una caja. No la mires fijo."
- Cliente, entrega rota: "Era un regalo... ERA." (ya está en el juego)
- Trampa: "Esta caja tiene opiniones sobre los baches."

Ejemplos en la voz incorrecta:

- "Inútiles, otra caja rota." Humilla al jugador; el chiste es un reto, no una situación.
- "El mapache no sobrevivió al viaje." Muerte de un animal: rompe el "nunca cruel".
- "La caja contiene un objeto frágil de origen porcelánico que debe ser tratado con cuidado." Sin
  gracia, sin voz, sin voseo.

## Diez clientes recurrentes

Los pueblos son los 12 de `TownSign.NAMES`; el juego sortea cuáles aparecen, así que el cliente vive
en "su" pueblo pero el nombre solo sale cuando ese pueblo está en la ruta.

| Cliente | Pueblo | Manía | Manda o pide | Ejemplo |
|---|---|---|---|---|
| Doña Ofelia Peralta | Villa Frágil | Colecciona vajilla y le tiene miedo al viento | Torre de copas (`glass_tower`) | "Si sopla, no respiro yo tampoco." |
| Ramiro "el Padrino" Ledesma | Colonia Esquina | Organiza casamientos con 14 hermanos | Torta de bodas (`wedding_cake`) | "Tres pisos. Cuatro, si Dios quiere." |
| Norma Gutiérrez | Arroyo Chueco | Cría gallinas y les habla como a nietas | Gallina ponedora (`hen`) | "Trátenla bien, tiene carácter." |
| Tobías Kaplan | Loma Movida | Jura que los mapaches son mensajeros | Mapache en jaula (`raccoon_cage`) | "Viene con un recado. No lo abran." |
| Eufrasio Toledo | Puerto Sin Mar | Capitán retirado sin barco; quiere ruido y festejo | Fuegos artificiales (`fireworks_crate`) | "Lo que no se enciende, se lo lleva el mar." |
| Amalia Quiroga | El Pozo Hondo | Anticuaria: todo tiene 200 años, hasta lo nuevo | Lámpara antigua (`antique_lamp`) | "Se la dio Napoleón a mi bisabuela, creo." |
| Beto Salvatierra | Paso del Golpe | Panadero que le habla a la masa madre | Masa madre (`sourdough`) | "No la sacudan: se ofende." |
| Clara Ibarra | San Ceferino del Bache | Jarrones sobre jarrones, ninguno para usar | Jarrón de porcelana (`porcelain_vase`) | "Es para mirar. Si lo usan, no vale." |
| Facundo Meneses | Bajada Lenta | Tambero que nunca llega a horario | Bidón de leche (`milk_canister`) | "Llegó fresca. Iba a decir: llegó." |
| Lucía Barrios | Tres Pozos | Rescata cachorros de quien se los regaló | Cachorro inquieto (`puppy`) | "Si aúlla, es que le gustó el camino." |

Pueblos sin cliente fijo todavía: Villa Caja Vacía y Cuesta Abajo.

## Cómo lo usan S-602 a S-605

- **S-602 (remitentes y notas en cajas):** cada caja lleva el nombre del cliente de la tabla como
  remitente y, a veces, una nota corta en su voz con su manía.
- **S-603 (la Jefa habla en el depósito):** las frases de la Jefa salen por la radio; pocas por día,
  secas, minimizan el desastre. Nunca gritan.
- **S-604 (reclamos con voz propia):** los reclamos de `REACTION_LINES` usan al cliente de la caja
  cuando se sabe: quejas exageradas y formales, sin insulto. Las frases genéricas actuales quedan de
  respaldo.
  Hecho en la pantalla de resultados (`client_complaints.gd`, `WORLD_COMPLAINT_<CLIENTE>_<RESULTADO>_<n>`);
  la burbuja de la puerta sigue con `REACTION_LINES`.
- **S-605 (textos de trampas con tono):** las descripciones de las 7 trampas (Frágil, Peso creciente,
  Equilibrio, Ruidoso, Explosivo, Hostil, Líquido) hablan de la situación, no del jugador: un chiste,
  voseo, sin regaños.

## Canon que ya está en el juego

- `do-not-drop/scripts/gameplay/route/town_sign.gd`: los 12 nombres de pueblo (`NAMES`).
- `do-not-drop/scripts/gameplay/route/roadside_story.gd` y `docs/tareas-nacho.md` (N-602): cartel
  "TAKE MY PACKAGE — entregamos (casi) todo", camioneta de la competencia, gallina suelta.
- `do-not-drop/translations/strings_world.csv`: `WORLD_REACTION_*` (tono de los reclamos: "Era un
  regalo... ERA.", "¿Por qué mi gallina tiene pilas?").
- `docs/diario-final.md`: el Jefe del depósito, el mate, *El Eco de {pueblo}*, el lema.
- `do-not-drop/data/contents/*.tres`: los 10 contenidos (nombres de `display_name`).
- `do-not-drop/data/traps/*.tres`: las 7 trampas.
- `do-not-drop/assets/audio/music/mus_depot_radio_loop.ogg` (radio del depósito, N-403).
