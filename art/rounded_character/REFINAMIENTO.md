# Personaje: animación y rostro

El modelo de juego sigue siendo `sm_char_player_rounded.glb`, con unos 18.600
triángulos, camiseta teñible y los cinco clips que utiliza el jugador. El archivo
`personaje_animado.blend` conserva las acciones editables. La referencia de modelado
original queda en `personaje_redondeado.blend`.

## Movimiento

- `animation_library.py` genera curvas muestreadas a 60 Hz. Idle y Sit cierran
  respiración, cabeza y movimiento secundario; Walk cierra posiciones y rotaciones.
- Walk es un trote corto para la velocidad del juego, con contacto lineal de pies
  y arco de recuperación. La reproducción se ajusta a la velocidad del jugador;
  la referencia de autoría es 3,2 m/s, sin cambiar la velocidad de desplazamiento.
- Jump se muestrea según velocidad vertical y contacto real con el suelo. La
  recuperación de aterrizaje cede antes si se continúa caminando.
- PickUpPackage anticipa el alcance, sostiene brevemente el contacto y levanta.
  La caja acompaña la secuencia; el overlay de brazos sigue sus esquinas reales.
  Si se empieza a caminar, los pies vuelven a Walk mientras las manos mantienen
  la caja. El punto de carga está dentro del alcance de los brazos.
- La piel oculta de las rodillas sigue el borde del pantalón al flexionarse.
  Sit conserva la altura de pelvis de los asientos y mejora la posición de muslos.

`test_character_motion.gd` mide cierre de loops, apoyo del pie con desplazamiento
compensado y distancia de muñecas a objetivos de caja. No sustituye una revisión
artística de todos los ángulos y terrenos. La locomoción no incluye todavía
plantado IK sobre pendientes, pasos laterales dedicados ni simulación de ropa.

## Personalización del rostro

Seis ojos y seis bocas originales de estilo caricatura, más partes vacías. Se
pueden combinar libremente: cambiar los ojos conserva la boca y viceversa.
Las mismas texturas SVG se usan en el mockup 2D y sobre la cabeza 3D, donde siguen
su hueso durante las animaciones. El perfil persiste ambas selecciones y las
propiedades del jugador las replican. Los perfiles anteriores reciben valores
válidos sin perder uniforme ni progreso.

Las expresiones son cosméticas estáticas: no hay sincronización labial ni cambios
automáticos de expresión por emociones. Se eligen desde **Personalización → Rostro**.
**Sin ojos + Sin boca** recupera la cabeza lisa original.

Validación funcional: `test_character_faces.gd`. Revisión visual en Godot real:
`render_character_faces.gd`, capturas en `review/customization_*.png` y
`review/face_*.png`.
