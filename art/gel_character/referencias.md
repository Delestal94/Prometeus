# Referencias de estudio — personaje de gelatina

> Investigación: 2026-09-30.
>
> La fuente de verdad visual es
> `art/gel_character/referencia/referencia_frente.jpg`. Estas referencias sirven
> para estudiar decisiones de silueta, movimiento, personalización y material.
> **No se copian modelos, personajes, paletas, animaciones, shaders ni interfaces.**
> Cuando una referencia contradiga la imagen objetivo, gana la imagen objetivo.

## Cómo usar esta lista

- **Tomar** significa observar un principio y resolverlo de nuevo para este personaje.
- **No copiar** marca los rasgos que harían que el resultado se parezca a otra obra.
- Los shaders publicados son material de estudio. La implementación final tiene que
  ser propia, medida contra la referencia y compatible con Godot 4.7 en GL
  Compatibility.

## Juegos: forma, lectura y movimiento

### 1. Fall Guys — comportamiento del Bean

**Enlace:** [Working with Fall Guys Islands — Epic Games](https://dev.epicgames.com/documentation/en-us/fortnite/working-with-fall-guys-islands-in-fortnite-creative)

**Tomar:** silueta legible durante carrera, salto, giro y caída; bamboleo que comunica
peso; gestos grandes que se leen con otros personajes alrededor. **No copiar:**
proporción de poroto, cara ovalada, división de disfraces, paleta ni tiempos exactos.

### 2. Fall Guys — caída y recuperación

**Enlace:** [Fall Forever Update](https://www.fallguys.com/news/fall-forever-update?lang=en-US)

**Tomar:** ragdoll solo cuando el golpe lo justifica, recuperación rápida y separación
entre bamboleo habitual y caída fuerte. **No copiar:** umbrales, poses y animaciones;
los valores se ajustan al rig y a la cámara de primera persona del proyecto.

### 3. Gang Beasts — personaje gelatinoso en acción

**Enlace:** [Sitio oficial](https://gangbeasts.game/)

**Tomar:** deformación legible en la silueta, masas simples en extremidades y contraste
entre cuerpo flexible y escenario rígido. **No copiar:** anatomía corta y ancha,
cabeza cilíndrica, colores opacos, caras, disfraces ni poses de combate.

### 4. Gang Beasts — estabilidad del controlador físico

**Enlace:** [Patch notes 0.5.0 — Boneloaf](https://gangbeasts.game/posts/2016/12/21/hgxgssm2b4n7me03ixuk3eg8b4443o)

**Tomar:** ajustar juntos pies, arrastre, fuerzas, alcance y recuperación; probar
personalización y ragdoll como un solo sistema. **No copiar:** daño, golpes, patadas,
fuerzas ni selección de blancos.

### 5. Human: Fall Flat — cuerpo simple para interacción física

**Enlace:** [Página del desarrollador](https://nobrakesgames.itch.io/human)

**Tomar:** postura, manos y equilibrio cargan la actuación; la intención sigue
legible aun con torpeza; las manos tocan de verdad paquete, volante y apoyos.
**No copiar:** cuerpo blanco opaco, anatomía de Bob, control independiente de brazos
ni sistema de escalada.

### 6. Slime Rancher 2 — biblioteca visual de slimes

**Enlace:** [Media oficial](https://www.slimerancher.com/media/)

**Tomar:** volúmenes redondeados legibles bajo luces distintas, highlights grandes y
separación entre color, brillo y zonas internas. **No copiar:** caras, apéndices,
siluetas, paletas ni acabado gomoso opaco.

### 7. Slime Rancher 2 — variantes Radiant

**Enlace:** [Radiant Slime Sanctuary — Monomi Park](https://www.slimerancher.com/news/slime-rancher-2-radiant-slime-sanctuary-update-1-2-0-notes/)

**Tomar:** una variante conserva identidad si mantiene la silueta y sus highlights.
**No copiar:** efectos prismáticos, glow, paletas Radiant ni emisión como sustituto
de transparencia.

## Creadores de personaje: presets y proporciones

### 8. The Sims 4 — personalización accesible

**Enlace:** [Ways to Start Playing The Sims 4 — EA](https://www.ea.com/en-au/games/the-sims/the-sims-4/how-to-play-the-sims)

**Tomar:** partir de una forma válida, separar cuerpo de cosméticos, previsualizar en
vivo y ofrecer aleatorización. **No copiar:** interfaz, categorías, nombres ni sliders
libres que rompan animación, IK, asientos o ropa.

### 9. MetaHuman Creator — preset primero, parámetros después

**Enlace:** [Head and Body Tools — Epic Games](https://dev.epicgames.com/documentation/metahuman/metahuman-creator-head-and-body-tools-in-unreal-engine)

**Tomar:** flujo preset → parámetros semánticos y controles nombrados por resultado
visible. **No copiar:** realismo, topología, rig, volumen de parámetros ni controles
faciales.

### 10. Dragon's Dogma — riesgos de variar largos y tamaño

**Enlace:** [Deep Customization Features — Capcom](https://news.capcomusa.com/lets/browse/dragons-dogma-dev-blog-deep-customization-features)

**Tomar:** alto y largos afectan cámaras, contactos, ropa y animaciones; probar
extremos en escenas reales. **No copiar:** rangos extremos, piezas, posturas ni
variantes de cuerpo fijas.

## Material real: gomitas y gelatina

### 11. HARIBO Goldbears — gomita bajo luz de producto

**Enlace:** [Goldbears — HARIBO](https://www.haribo.com/en-us/products/goldbears)

**Tomar:** borde con más color y densidad, centro transmisivo, highlights blancos
nítidos y zonas gruesas más oscuras. **No copiar:** silueta de oso, cara, colores por
sabor ni saturación comercial.

### 12. JELL-O — gelatina moldeada

**Enlace:** [Juicy JELL-O — Kraft Heinz](https://www.kraftheinz.com/jell-o/recipes/505016-juicy-jell-o)

**Tomar:** reflejos anchos sobre superficie húmeda, masa en zonas profundas, sombra
de contacto blanda y distorsión moderada. **No copiar:** color saturado, forma del
molde, estrías ni transparencia limpia de postre.

## Shaders publicados: técnicas a evaluar, no código a copiar

### 13. Goo — Godot Shaders

**Enlace:** [Goo, por dairycultist](https://godotshaders.com/shader/goo/)

**Tomar:** separar color base, highlight, rim y distorsión, y exponer controles para
evaluar el material. **No copiar:** código, valores, rim amarillo, texturas,
`cull_disabled`, `depth_draw_always` ni refracción fuerte sin medirlos.

### 14. Refractive Transparent Crystal — Godot Shaders

**Enlace:** [Shader publicado por Giancarlo Niccolai](https://godotshaders.com/shader/synty-refractive_transparent-crystal-shader/)

**Tomar:** grosor por profundidad y separación de opacidad, distorsión y especular.
**No copiar:** código, metallic alto, prismas, glow, triplanar ni complejidad que no
aporte al lado a lado.

### 15. Godot — transparencia y renderer Compatibility

**Enlaces:** [Overview of renderers](https://docs.godotengine.org/en/stable/tutorials/rendering/renderers.html) ·
[Standard Material 3D](https://docs.godotengine.org/en/latest/tutorials/3d/standard_material_3d.html)

**Tomar:** GL Compatibility no ofrece SSS; el aspecto se aproxima con grosor,
Fresnel, especular, alpha y backlight barato. La transparencia cuesta, puede ordenar
mal superficies y exige probar cuatro personajes en el juego. **No copiar:** recetas
de Forward+, caparazones no medidos ni una migración de renderer para conseguir
efectos.

## Síntesis para S-311

- **Forma:** manda la imagen local; silueta clara quieta, corriendo, sentada,
  cargando y en ragdoll.
- **Movimiento:** bamboleo pequeño habitual, ragdoll para impactos claros y control
  recuperado rápido.
- **Personalización:** preset → sliders semánticos → restaurar/deshacer → al azar
  válido; Delgada es la fuente de verdad del bloque E.
- **Material:** blanco lechoso lavanda-azulado, borde denso, reflejo de ventana,
  centro transmisivo, torso algo más opaco, motas finas y sombra suave.
- **Implementación:** empezar por malla cerrada, grosor, Fresnel, especular, alpha y
  motas; sumar refracción solo si mejora de forma medible el render de Godot.

