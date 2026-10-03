# Ciudad: relieve natural y movimiento del jugador

N-950, Nacho. Adaptadores town usan anchos 8/12 m, plataformas locales y
reservas previas de landmarks. El relieve ya no aplana contornos completos.
Aceras con cordón físico, sin paredes internas entre superficies contiguas;
rebajes sólo vehiculares y en esquinas.

`player_movement.gd` (dominio Slatex) delega el movimiento final al módulo
`character_step` para subir cordones sin saltar. Firma on_foot_step intacta;
input, sprint, salto y replicación siguen su flujo. Hacer pull antes de seguir
el movimiento del jugador. Campaña, multijugador de ciudad y guardado pendientes.
