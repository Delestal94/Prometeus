# S-311.69 — legibilidad a 20 m

La lámina `s311_69_contact_sheet.png` compara los ocho colores de la tripulación sobre el cuerpo gel real. Todos los
personajes están colocados en un arco horizontal de radio 20,0 m respecto a la cámara.

| Iluminación | Visión normal | Deuteranopia | Protanopia |
| --- | --- | --- | --- |
| Día | `s311_69_day_normal.png` | `s311_69_day_deuteranopia.png` | `s311_69_day_protanopia.png` |
| Noche | `s311_69_night_normal.png` | `s311_69_night_deuteranopia.png` | `s311_69_night_protanopia.png` |

## Resultado

- Cada jugador conserva el color de equipo en el borde y en el núcleo del torso.
- El núcleo usa cuatro bandas binarias derivadas del color cuantizado. Las ocho firmas son únicas, de modo que los
  jugadores siguen distinguiéndose cuando dos tonos se acercan bajo un filtro de daltonismo.
- Las simulaciones de deuteranopia y protanopia usan las matrices Machado 2009 a severidad completa que también
  valida `test_player_colors.gd`.
- `render_gel_legibility.gd` regenera las seis capturas y la lámina; CI las vuelve a producir en el runtime audit.

Las imágenes filtradas son evidencia anticipada para S-502. La opción de usuario que activa esos filtros sigue
perteneciendo a esa tarea; este bloque asegura que la identidad visual del jugador ya sobrevive a ellos.
