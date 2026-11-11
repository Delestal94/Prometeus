# Cosméticos de la empresa (D-0137) — 2026-10-22

## Decisión
El diseño está en `docs/expansion-distritos/diseno/cosmeticos-empresa.md`; lo construyen D-0437 y D-1234.
- **Cuatro ranuras de la empresa**: pintura, franja, logo y uniforme. Lo desbloqueado sale de los hitos cumplidos
  (`milestones_done`), sin lista aparte; nada pasa al perfil ni viene de él.
- **Elige el host, en el cierre**, en un bloque "Empresa" de la tienda (4 filas con "Cambiar"), gratis. Sin
  pantalla nueva (D-1925 pospuesta).
- **Una sola pintura para toda la flota**; cambia solo la carrocería, la moldura de cada camioneta se conserva.
- **Logo de lista cerrada** (Inicial de base + 6 del `logo_pack`), sin editor.
- **El uniforme de la empresa lo visten solo los empleados**; los jugadores siguen con su vestuario y su color de
  equipo (N-226).
- **Trofeo del volcán**: copa fija al lado de la entrada del galpón, no depende del tablero de hitos.
- **Colores**: primera pintura crema `#F0D58C` (para que se note frente al blanco de fábrica); `paint_national`
  azul noche plano, sin techo blanco.
- **Red**: ayudante `CompanyCosmeticsNet`, petición `cosmetic_set`, evento `cosmetics_set` con el diccionario
  entero; color de carrocería local en `vehicle.gd`, no replicado.

## Por qué
Es el mínimo cosmético que deja P8 de `critica-alcance.md`: unas 3,5 jornadas entre D-0437 y D-1234 en vez de las
5-6 del primer borrador. El host ya elige construcción y compras; una pintura por flota se lee como marca. El
jugador es un gel sin remera, así que un uniforme de empresa en él casi no se vería y borraría el color que
distingue a cada uno. Revisado por `critico-diseno` (15 puntos aplicados).

## Alternativas descartadas
- Pestaña con tarjetas en la tienda: rompe el foco de una sola columna con mando y cuesta el doble.
- Uniforme opcional para jugadores: guardaría algo de la empresa en el perfil y toca `player.gd` por un tono de borde.
- Usar `paint_id` de `vehicle.gd`: solo acepta las claves de `PAINTS` y se replica, un color externo se perdería.
- Logo en las puertas: giran y el logo quedaría flotando.
