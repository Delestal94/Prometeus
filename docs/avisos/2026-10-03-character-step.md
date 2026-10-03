# Movimiento: subida acotada de cordones (zona compartida)

N-950, Nacho. Nuevo módulo portable `character_step` sin referencias al juego.
`move_and_slide(body, delta, height=.22)` delega el movimiento ordinario y sólo
sube un escalón bajo con barridos de cuerpo completo y apoyo verificado.
La diferencia de superficies impide trepar muros con el borde de la cápsula.
No actúa durante salto/caída. Tests: .16, pared .24/2 m, techo, aire, salto y
piso plano. Hacer pull antes de integrar rutinas de movimiento.
