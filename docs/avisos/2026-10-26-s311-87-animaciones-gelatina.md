# Aviso: S-311.87, seis animaciones de gelatina pura

La biblioteca compartida del personaje gel pasa de 31 a 37 clips con seis
deformaciones propias del material: `Pancake`, `GumStretch`, `BallBounce`,
`SplitAndJoin`, `ColdShiver` e `Inflate`. Todas vuelven exactamente a `Idle` y
están exportadas en los tres LOD.

Contratos nuevos:

- Solo estos seis clips pueden usar escalas animadas; `test_gel_body_asset.gd`
  sigue rechazándolas en los otros 31. Los huesos secundarios no reciben tracks
  propios y continúan bajo `SpringBoneSimulator3D`.
- El retarget conserva por separado las métricas rígidas y las deformables. Los
  clips normales mantienen longitudes y rotaciones exactas; pancake, estirado,
  rebote e inflado pueden cambiar escala de torso/cabeza de forma explícita.
- `SplitAndJoin` separa 22 cm el subárbol conectado de pecho, cabeza y brazos
  respecto de pelvis/piernas y después lo reúne. La separación vive en el
  adaptador del rig gel porque Blender ignora traslaciones sobre los huesos
  conectados del rig fuente.

Validación final:

- barrido de 270/270 muestras: seis clips, cinco tiempos, tres LOD y tres estados
  de grosor; cero contactos internos y cero orientaciones invertidas;
- contratos Godot de activo, retarget y siluetas: 3/3 en serie;
- unitarias Python: 15/15; prueba Blender específica de los 37 clips: 1/1;
- gdlint sin problemas; endpoints inalcanzables: cero.

Este bloque solo entrega clips y su retarget. La rueda, el input y la replicación
específica de emotes siguen reservados para S-311.89.
