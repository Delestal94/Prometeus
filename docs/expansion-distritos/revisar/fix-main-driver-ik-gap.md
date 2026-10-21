# fix-main: test_driver_ik inestable

## Decidir al final
- `player_seat_pose.gd:127` (dominio Slatex): #530 (S-311.70) cambió el offset Z del conductor de -0.37 a
  -0.35 con el comentario "2 cm adelante", pero -Z es adelante: quedó 2 cm atrás y las muñecas del gel
  quedan ~3 cm cortas del aro (gap real 0.028 m; con -0.37 sería 0.013, con -0.39 0.008). Este PR solo
  arregla la carrera del test; el offset queda para Slatex / `revisor-visual` (`check_driver_sightline.gd`).
