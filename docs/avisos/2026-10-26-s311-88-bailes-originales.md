# Aviso: S-311.88, ocho bailes originales del personaje gel

La biblioteca compartida del personaje pasa de 37 a 45 clips con ocho bucles
originales: `SimpleStep`, `Robot`, `Disco`, `FloorWorm`, `Headbang`,
`VictoryDance`, `Flan` y `Conga`. Los tres LOD incluyen exactamente los mismos
clips, duraciones y huesos nombrados.

Contratos nuevos:

- Los ocho bailes cierran su primer y último fotograma sin salto y conservan
  siluetas distintas: paso lateral, bloqueos angulares, diagonales disco,
  gusano bajo, golpe de cabeza, salto de victoria, onda gelatinosa y marcha.
- `Flan` es el único baile que usa escalas animadas del torso y cabeza. Esas
  escalas siguen restringidas al conjunto explícito de deformaciones gel; los
  huesos secundarios continúan bajo `SpringBoneSimulator3D`.
- Cuando dos jugadores reproducen `Conga` a cuatro metros o menos, cada cliente
  dibuja ambos sobre una fase común de reloj monotónico. No se añade tráfico de
  red: `anim_clip` ya identifica el clip replicado y un bailarín lejano no entra
  en esa sincronización.
- Este bloque no añade rueda ni acciones de entrada. La selección por teclado,
  gamepad y su flujo de red siguen reservados para S-311.89.

Validación final:

- barrido de 360/360 muestras: ocho bailes, cinco tiempos, tres LOD y tres
  estados de grosor; cero contactos internos y cero orientaciones invertidas;
- contratos Godot de bailes, fase cercana de conga, LOD y retarget: 4/4 en
  serie;
- 39 unitarias Python y contrato focal Blender: todas pasan;
- gdlint y `git diff --check` sin problemas; objetivos inalcanzables: cero.
