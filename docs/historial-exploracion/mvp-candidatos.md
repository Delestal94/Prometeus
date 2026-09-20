# MVP candidatos

> ⚠️ **ARCHIVADO — superado por decisión posterior.** Este documento recomendaba el
> Candidato 3 (puzzle/narrativa). El proyecto pivoteó después a un concepto distinto
> (delivery cooperativo — ver `docs/definicion-proyecto.md`). Se conserva como registro
> del proceso de decisión, no como referencia vigente.
>
> Basado en: `docs/investigacion-mercado.md` y `docs/checklist-exito.md`.
> Última actualización: 2026-09-20
> Estado: propuestas para decidir — ninguna elegida todavía.

Cada candidato aplica los items replicables de la checklist (scope chico, arte simple,
loop en una frase, momento clipeable, precio bajo) pero cubre un patrón distinto de los
tres grupos identificados en la investigación, para que puedas elegir según lo que más
te atraiga jugar/hacer vos mismo — el patrón más fuerte de todos los casos fue que el
dev hizo el juego que ÉL quería jugar.

---

## Candidato 1 — Roguelike de build (patrón Balatro/Brotato/Vampire Survivors)

**Loop en una frase**: cada run elegís upgrades/combinaciones que se potencian entre sí
hasta que morís o ganás, y la gracia es descubrir combos rotos.

- **Hook propuesto**: cruzar un sistema simple y conocido (dados, cartas, fichas de
  bingo, dominó, un mini-tablero) con estructura roguelike de runs cortas — el mismo
  truco de Balatro (poker + roguelike), pero con otro sistema base que todavía no esté
  saturado en Steam.
- **Scope MVP**: 1 modo de juego, ~15-20 objetos/cartas/piezas base, 3-5 combos "rotos"
  intencionales para que se compartan en redes, runs de 10-20 minutos.
- **Arte**: geometría plana / iconografía simple, sin animación de personajes — como
  Balatro, el atractivo visual está en los números y efectos, no en sprites detallados.
- **Motor sugerido**: Godot (2D, liviano, buena curva con asistencia de IA) o LÖVE2D si
  buscás algo aún más minimalista.
- **Tiempo estimado**: 6-12 meses hasta un EA jugable, apoyándote en IA para balance y
  generación de contenido repetitivo (definiciones de cartas/objetos).
- **Momento clipeable**: un combo que rompe el juego visualmente (números gigantes,
  pantalla llena de efectos) — el mismo gancho que usó Balatro.
- **Riesgo principal**: el género está más saturado que hace 2 años (post-Balatro), así
  que el hook mecánico tiene que ser genuinamente distinto, no "Balatro con skin nueva".

---

## Candidato 2 — Sim de loop diario/expedición (patrón Lethal Company/Schedule I)

**Loop en una frase**: cada ciclo (día, noche, expedición) tomás decisiones de riesgo
para conseguir recursos antes de un límite de tiempo, y la tensión + lo absurdo de los
eventos aleatorios genera momentos graciosos o tensos para compartir.

- **Hook propuesto**: un tema no explotado todavía combinado con la fórmula "expedición
  contrarreloj + eventos emergentes aleatorios + progresión de base/equipo entre
  ciclos". Lethal Company lo hizo con horror sci-fi; Schedule I con simulador de
  crimen — el espacio temático está abierto (ej. rescate, exploración submarina,
  desguace espacial, cocina bajo presión, etc.).
- **Scope MVP**: 1 sola "zona"/nivel con generación semi-aleatoria, 3-5 tipos de
  evento/amenaza, progresión simple de equipo/base entre ciclos, soporte para 1-4
  jugadores si es coop (o directamente single-player para simplificar el MVP).
- **Arte**: low-poly 3D simple o pixel art top-down — ambos patrones aparecen en la
  investigación (Lethal Company es 3D tosco, Stardew/RimWorld son 2D).
- **Motor sugerido**: Unity si vas a 3D low-poly (mejor soporte/documentación con IA
  para ese caso); Godot si te quedás en 2D top-down.
- **Tiempo estimado**: 12-24 meses — es el patrón con desarrollo más largo de los tres
  candidatos, por la cantidad de sistemas emergentes que hay que balancear.
- **Momento clipeable**: eventos aleatorios que generan situaciones graciosas o de
  pánico compartibles en clip corto (la clave del éxito de Lethal Company en streams).
- **Riesgo principal**: es el candidato de mayor scope y mayor riesgo de "spiral" de
  desarrollo (like el propio Zeekerss tuvo un intento previo abandonado) — necesita
  disciplina fuerte de scope desde el día uno.

---

## Candidato 3 — Puzzle/narrativa de autor (patrón Papers Please/Obra Dinn)

**Loop en una frase**: revisás/investigás casos o situaciones aplicando una regla o
herramienta simple, y la dificultad crece agregando capas a esa misma regla, sin
necesidad de mundo abierto ni sistemas emergentes.

- **Hook propuesto**: una "lente" o mecánica de verificación/deducción original aplicada
  a un contexto con tensión moral o curiosidad (Papers Please = burocracia + dilema
  moral; Obra Dinn = deducción visual + misterio naval). El contexto puede ser lo que
  vos elijas (algo que conozcas bien ayuda mucho acá, ya que el contenido es curado a
  mano, no procedural).
- **Scope MVP**: 1 mecánica central, 10-15 "casos"/niveles curados a mano que escalan
  en complejidad, duración total de 2-4 horas de juego.
- **Arte**: paleta reducida / 1-bit / pixel art muy simple — el estilo visual de estos
  casos es deliberadamente austero, lo cual reduce muchísimo la carga de producción.
- **Motor sugerido**: Godot o incluso un framework 2D minimalista — el requerimiento
  técnico es el más bajo de los tres candidatos.
- **Tiempo estimado**: **6-9 meses** — es el candidato de desarrollo más corto y más
  predecible, porque el contenido es lineal y curado (no hay que balancear sistemas
  emergentes ni generación procedural).
- **Momento clipeable**: menos orientado a viralización por streaming en vivo y más a
  "giros" narrativos o de deducción que se comentan/recomiendan boca a boca (reseñas,
  posts, video-ensayos) — un canal de marketing distinto a los otros dos candidatos.
- **Riesgo principal**: sin sistemas emergentes ni generación procedural, la rejugabilidad
  es baja — el volumen de ventas depende más de la calidad del "giro"/concepto que de
  push viral en streams, así que el diseño tiene que ser muy afilado.

---

## Comparación rápida

| | Candidato 1 (Roguelike build) | Candidato 2 (Sim loop) | Candidato 3 (Puzzle narrativo) |
|---|---|---|---|
| Tiempo estimado | 6-12 meses | 12-24 meses | 6-9 meses |
| Complejidad técnica | Media | Alta | Baja |
| Rejugabilidad | Alta (runs infinitas) | Alta (runs/ciclos) | Baja (una vez completado) |
| Canal de marketing principal | Clips de combos | Clips de streamers | Boca a boca/reseñas |
| Riesgo de saturación de mercado | Alto (post-Balatro) | Medio | Bajo |
| Riesgo de scope creep | Bajo-medio | **Alto** | Bajo |

## Mi lectura

Para un primer proyecto solo + IA, el **Candidato 3** es el de menor riesgo de ejecución
(scope más controlable, motor más simple, tiempo más corto y predecible), aunque tiene
techo de ventas más bajo si no encontrás un concepto realmente afilado. El
**Candidato 1** es el de mejor relación riesgo/recompensa si encontrás un hook mecánico
genuinamente original (el género tiene demanda probada pero exige diferenciarte de
Balatro). El **Candidato 2** es el de mayor potencial viral pero también el de mayor
riesgo de que el desarrollo se te vaya de scope, como le pasó al propio dev de Lethal
Company en su intento anterior.

## Actualización 2026-09-20 — Chequeo de saturación de mercado actual

Los patrones de `investigacion-mercado.md` están basados en éxitos de 2013-2025. Antes de
recomendar "el de mayor probabilidad de éxito" verifiqué el estado del mercado **hoy**
(2026), porque un patrón que funcionó hace 2-3 años puede estar saturado ahora.

Resultado — **los tres géneros están más competidos que cuando salieron sus referentes**,
pero en distinto grado:

| Género | Estado del mercado en 2026 | Fuente |
|---|---|---|
| Roguelike deckbuilder (Candidato 1) | **Muy saturado**: un solo publisher (Krafton) revisó ~250 juegos del género en 12 meses; publishers activamente evitan financiarlos por falta de diferenciación. Sigue vendiendo fuerte en la cima (Slay the Spire 2, Balatro-likes) pero la barrera de entrada para destacar es alta. | [ingamenews](https://www.ingamenews.com/2026/05/gaming-news-why-publishers-are-avoiding.html) |
| Bullet heaven (variante del Candidato 1) | **Saturado**, Steam le dio categoría oficial en mayo 2026 por la cantidad de juegos; la próxima ola exige hibridar con otros sistemas para destacar. | [PC Gamer](https://www.pcgamer.com/gaming-industry/its-official-steam-decrees-bullet-heaven-the-name-of-the-vampire-survivors-genre/) |
| Extraction horror co-op (Candidato 2) | **Saturado**, "año de masa crítica" en 2026 con varios clones grandes (R.E.P.O., Peak, FEEDERS) compitiendo directo con la fórmula de Lethal Company. | [Summer Engine](https://www.summerengine.com/blog/games-like-lethal-company) |
| Puzzle/narrativa de autor (Candidato 3) | Sin señales de saturación equivalente en la búsqueda — sigue siendo un espacio más despejado, aunque también más chico en techo de ventas. | — |

### Qué significa esto para "mayor probabilidad de éxito"

Probabilidad de éxito = (probabilidad de **terminar** el juego) × (probabilidad de
**destacar** en su género) × (demanda probada del género). Con los datos de 2026:

- **Candidato 1 y 2** siguen teniendo demanda probada alta, pero ahora requieren un hook
  mecánico *genuinamente* original para no perderse entre cientos de clones — el listón
  para destacar subió mucho desde que Balatro/Lethal Company salieron.
- **Candidato 3** tiene menor riesgo de ejecución (ya lo tenía) Y ahora también menor
  riesgo de saturación — es el único de los tres que no compite contra una ola reciente
  de clones directos.

## Recomendación final

Para **maximizar probabilidad de éxito** (no de pegar un batazo gigante, sino de que el
proyecto se termine, se note, y venda bien para ser un primer juego solo), recomiendo el
**Candidato 3 (puzzle/narrativa de autor)** como base, con un ajuste:

- Tomar prestado del Candidato 1 un elemento de **rejugabilidad ligera** (ej. variaciones
  aleatorias en los casos/niveles, o un modo "endless" post-final) para mitigar su
  principal debilidad (baja rejugabilidad) sin agregar la complejidad de sistemas
  emergentes del Candidato 2.
- Esto da: scope controlable, tiempo de desarrollo corto y predecible (6-9 meses),
  mercado menos competido, y un empujón extra de valor percibido para justificar reseñas
  positivas y recomendaciones boca a boca.

Si en cambio preferís apostar más alto asumiendo más riesgo, el **Candidato 1** sigue
siendo defendible — pero solo si ya tenés en mente un hook mecánico que honestamente no
hayas visto en ningún roguelike/deckbuilder existente. Si no lo tenés todavía, es una señal
de que el Candidato 3 es la apuesta más segura ahora mismo.

## Próximo paso
Elegir uno (o la combinación sugerida) para pasar a `docs/definicion-proyecto.md` con el
diseño concreto: tema, hook definitivo, mecánicas exactas del MVP.
