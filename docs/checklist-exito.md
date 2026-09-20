# Checklist de items replicables — cómo aplicar los patrones de éxito

> Basado en: `docs/investigacion-mercado.md` (20 casos verificados de juegos de Steam
> hechos por 1-2 personas).
> Última actualización: 2026-09-20

## Evaluación: ¿estamos listos?

**Sí.** La evidencia entre los 20 casos es consistente, no dispersa — los mismos patrones
se repiten en juegos de géneros distintos, años distintos y devs distintos. Eso significa
que no son casualidades individuales, sino **decisiones replicables**. A partir de acá, lo
que falta ya no es más research de mercado, sino **decisiones tuyas**: qué género elegís,
qué tema/ambientación, y cuál es tu gancho único (el "hook") dentro del patrón.

Este documento traduce los patrones en una checklist concreta, dividida en:
- **Items replicables** (decisiones de diseño/producción con evidencia fuerte — aplicalos).
- **Items que son decisión tuya** (el research no puede elegir por vos).
- **Riesgos/mitos a evitar** (cosas que la gente cree que funcionan pero los datos no sostienen).

---

## A. Items replicables (con evidencia de ≥5 casos)

### A1. Scope y género
- [ ] Elegir un género de **sesión corta y run-based** (roguelike/roguelite) o un **sim de loop simple** (día a día, expedición a expedición). Evidencia: 11 de 20 casos.
- [ ] Definir el **loop central en una sola frase** antes de escribir código. Ej: "cada run subís de nivel eligiendo upgrades hasta morir" (Vampire Survivors/Brotato) o "cada noche mandás al equipo a robar loot y volvés antes de que amanezca" (Lethal Company).
- [ ] Acotar el scope a algo terminable en **9 meses - 2.5 años** trabajando solo. Evidencia: Papers Please (9m), Vampire Survivors (9m a EA), Balatro (2.5a), Lethal Company (~3a, con un intento previo abandonado). Evitar scope tipo RimWorld/Stardew (4-20 años) para un primer proyecto.
- [ ] Preferir **mecánicas simples y pocas, combinadas de forma profunda** (ej. Balatro: pocas reglas, combinatoria enorme) antes que muchos sistemas superficiales.

### A2. Arte y producción visual
- [ ] Usar **pixel art, geometría 2D plana, o 1-bit/paleta reducida**. Evidencia: Balatro, Vampire Survivors, Brotato, Risk of Rain, Papers Please, Return of the Obra Dinn — todos con producción visual deliberadamente simple.
- [ ] No competir en fidelidad visual 3D — ningún caso de la lista lo hizo con éxito como solo dev (Megabonk es 3D pero con estética voluntariamente tosca/cómica, no realista).
- [ ] Reservar presupuesto (dinero o favor) para **música/sonido por encargo** — es lo que más se tercerizó incluso en los "solo dev" más puros (Megabonk, Celeste, Dwarf Fortress).

### A3. Motor/tecnología
- [ ] Elegir el motor según **velocidad de iteración personal**, no prestigio. Evidencia: LÖVE2D (Balatro), Godot (Brotato) y Unity (Vampire Survivors, Lethal Company, Megabonk, RimWorld) compitieron de igual a igual en ventas.
- [ ] Si vas a usar IA como copiloto de código, priorizar un motor/lenguaje con **mucha documentación y código de ejemplo público** (Unity C# y Godot GDScript son los mejor cubiertos hoy; ver [[definicion-proyecto]] cuando lo armemos).

### A4. Precio y monetización
- [ ] Lanzar a **$8-15 USD**. Ningún caso de la lista usó precio premium ($40-60) ni microtransacciones.
- [ ] Modelo: **precio único + actualizaciones gratis post-lanzamiento**; DLC pago opcional mucho después si el juego prende (Vampire Survivors, Slay the Spire).

### A5. Estrategia de lanzamiento
- [ ] Lanzar en **Early Access** salvo que el scope sea muy chico y ya "sienta terminado" (como Papers Please o Balatro). Evidencia: 6 de 20 casos usaron EA como validación antes del pico de ventas.
- [ ] Esperar que el "boom" de ventas llegue **semanas o meses después del lanzamiento**, no el día 1 — el patrón dominante es crecimiento por boca a boca, no explosión inmediata.

### A6. Diseño para viralización
- [ ] Diseñar **al menos un momento "clipeable"** desde el día uno del diseño: una build absurda, un giro gracioso, un momento de tensión compartible. Evidencia directa: Lethal Company (horror cooperativo con momentos graciosos), Megabonk (builds rotas visualmente exageradas), Balatro (combos numéricos absurdos).
- [ ] Pensar el juego como **"divertido de mirar" además de jugar** — esto es lo que atrae streamers, y los streamers son el canal de marketing real en todos los casos recientes (Megabonk, Lethal Company, Schedule I), no la publicidad pagada.

### A7. Equipo y expectativas
- [ ] Planificar para lanzar **solo (con ayuda de IA)**, no para armar equipo antes de validar. Evidencia: en todos los casos, el equipo creció **después** del éxito (Schedule I, Vampire Survivors, Slay the Spire), nunca antes.
- [ ] Aceptar que vas a necesitar **encargar música** (y quizás arte de portada/key art) aunque el resto lo hagas vos + IA — es el patrón casi universal.

---

## B. Decisiones que son tuyas (el research no elige esto)

Estos son los puntos donde necesito tu input para avanzar a `docs/definicion-proyecto.md`:

1. **Tema/ambientación**: ¿algo que te apasione o conozcas bien? (los devs de estos casos casi siempre hicieron el juego que ELLOS querían jugar — Stardew Valley, Undertale, Lethal Company nacieron de gustos personales del dev, no de "análisis de mercado" frío).
2. **¿Roguelike/roguelite de build o sim de loop diario?** — son los dos subgéneros con más evidencia; hay que elegir uno como base.
3. **Motor concreto**: Godot, Unity, u otro — depende de tu experiencia previa y de qué tan bien te puede asistir la IA en ese stack.
4. **El "hook" único**: qué hace a TU juego distinto dentro del patrón (Balatro = cartas + poker + roguelike, nadie lo había cruzado así antes; Lethal Company = horror + comedia + cooperativo).

---

## C. Riesgos / mitos a evitar (lo que los datos NO sostienen)

- ❌ "Hay que innovar en gráficos para destacar" — falso, ningún caso de la lista compitió en fidelidad visual.
- ❌ "Hay que hacer un juego grande para que se note el esfuerzo" — falso, los scopes chicos y pulidos (Papers Please, Balatro) rindieron igual o mejor que los grandes.
- ❌ "El marketing pago es necesario" — no hay evidencia de esto en ningún caso; todos crecieron por streamers/boca a boca orgánico.
- ❌ "Hay que armar equipo desde el principio para competir" — contradicho por los 20 casos: el equipo llega después, no antes.
- ❌ "Un juego solo puede tardar años en hacerse" — cierto en algunos casos (Stardew Valley) pero **no es la norma**; la mayoría de los éxitos recientes (Balatro, Lethal Company, Vampire Survivors) fueron de 9 meses a 3 años.

---

## Próximo paso

Con esta checklist ya tenemos "qué patrones replicar" resuelto. El siguiente documento
(`docs/definicion-proyecto.md`) debería resolver la sección B: tema, subgénero, motor y
hook único de tu juego, usando esta checklist como marco de decisión.
