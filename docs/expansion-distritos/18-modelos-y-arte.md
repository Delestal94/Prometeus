# Grupo 18 — Modelos 3D y arte compartido

> Fase **F1-F5** (gris primero, final después) · Dueño: Nacho · Depende de: D-0147, D-0148.
> Todo lo marcado `*` corre en la PC (rutina `sesion-arte`). Los modelos de cada vehículo y distrito
> están en su grupo; acá van productos, embalaje, galpón, personas y bibliotecas compartidas.
> Cada modelo: low-poly, pivote y escala listos para Godot, revisado con `check_pivots.gd` y una captura.

## Núcleo

| ID | Tarea | Agente | Esf. | Hecho cuando |
|---|---|---|---|---|
| D-1801 | Guía de estilo de modelos de la expansión (polys, paleta, texel) | director-arte | medium | sección en `direccion-visual.md` |
| D-1802 | Productos lote 1: 10 del corte vertical (botella, libro, taza, zapatillas, lámpara…) | modelador-blender* | high | 10 modelos con colisión simple |
| D-1803 | Productos lote 2: 10 frágiles (vidrio, cerámica, TV, espejo) | modelador-blender* | high | 10 modelos |
| D-1804 | Productos lote 3: 10 fríos y perecederos (helado, pescado, flores) | modelador-blender* | high | 10 modelos |
| D-1805 | Productos lote 4: 10 grandes y raros (bici, colchón, planta, pecera) | modelador-blender* | high | 10 modelos |
| D-1806 | Cajas S, M, L, XL abiertas y cerradas (reusar texturas de N-315) | modelador-blender* | medium | 8 mallas |
| D-1807 | Insumos: rollo de cinta, dispensador, burbuja, papel, espuma | modelador-blender* | medium | 5 modelos |
| D-1808 | Sellos y etiquetas como decals | artista-conceptual* | low | 8 texturas |
| D-1809 | Conservadora, caja térmica, caja impermeable | modelador-blender* | medium | 3 modelos |
| D-1810 | Mesa de armado | modelador-blender* | medium | modelo |
| D-1811 | Estanterías (rack chico y grande), heladera industrial | modelador-blender* | medium | 3 modelos |
| D-1812 | Palet con cajas de proveedor (variantes) | modelador-blender* | medium | 4 variantes |
| D-1813 | Zorra (transpaleta) y carrito de picking | modelador-blender* | medium | 2 modelos |
| D-1814 | Camión de proveedor NPC | modelador-blender* | high | modelo |
| D-1815 | Impresora de pedidos y tablero | modelador-blender* | low | 2 modelos |
| D-1816 | Portapapeles en la mano (primera persona) | modelador-blender* | low | modelo |
| D-1817 | Kit de paredes del galpón por etapa | modelador-blender* | high | kit |
| D-1818 | Empleado base (D-1018) con uniforme de la empresa | modelador-blender* | medium | modelo rigueado |
| D-1819 | Clientes NPC en la puerta (6 variantes) | modelador-blender* | high | 6 modelos |
| D-1820 | Inventario de assets actualizado con todo lo nuevo | documentador | low | `inventario-assets.md` |

## Ampliación

| ID | Tarea | Agente | Esf. | Hecho cuando |
|---|---|---|---|---|
| D-1821 | Productos lote 5: 10 de distritos (cocos, quesos, souvenirs volcánicos) | modelador-blender* | high | 10 modelos |
| D-1822 | Productos lote 6: 10 peligrosos/vivos (garrafa, fuegos, gallina, planta) | modelador-blender* | high | 10 modelos |
| D-1823 | Máquinas finales (ver D-1141) — coordinación de estilo | director-arte | low | revisión |
| D-1824 | Decoración del galpón (plantas, cafetera, carteles motivacionales) | modelador-blender* | medium | 10 props |
| D-1825 | Vestuario y comedor de empleados | modelador-blender* | medium | 6 props |
| D-1826 | Oficina del jefe | modelador-blender* | medium | kit |
| D-1827 | Cartel exterior de la empresa por etapa | modelador-blender* | low | 4 variantes |
| D-1828 | Logo de la empresa (editable por el jugador) | artista-conceptual* | medium | plantillas |
| D-1829 | Uniformes por rango | artista-conceptual* | low | texturas |
| D-1830 | Retratos de clientes (D-0847) | artista-conceptual* | medium | 18 retratos |
| D-1831 | Arte conceptual de cada distrito (referencia para modelar) | artista-conceptual* | high | 9 imágenes |
| D-1832 | Arte conceptual de cada vehículo | artista-conceptual* | medium | 5 imágenes |
| D-1833 | Texturas de productos (marcas ficticias graciosas) | artista-conceptual* | medium | 30 etiquetas |
| D-1834 | Animales nuevos (cabras, delfín, cóndor) | modelador-blender* | medium | 3 modelos |
| D-1835 | Animaciones de animales nuevos | animador* | medium | clips |
| D-1836 | Variantes de casas de entrega por distrito (fachadas) | modelador-blender* | high | 20 fachadas |
| D-1837 | Carteles de calle y de distrito | modelador-blender* | low | kit |
| D-1838 | Props de venta: kiosco, puesto de feria, cabina | modelador-blender* | low | 5 props |
| D-1839 | Biblioteca de props compartidos (barriles, conos, vallas) | modelador-blender* | medium | 15 props |
| D-1840 | Animación del jugador con portapapeles y escáner | animador* | medium | 2 clips |

## Pulido

| ID | Tarea | Agente | Esf. | Hecho cuando |
|---|---|---|---|---|
| D-1841 | LODs de todos los modelos nuevos con más de 2k tris | modelador-blender* | high | LODs exportados |
| D-1842 | Atlas de texturas de productos (menos draw calls) | artista-shaders | high | medido |
| D-1843 | Auditoría de arte de la expansión | director-arte | high | lista priorizada |
| D-1844 | Rehacer lo marcado REHACER por D-1843 | modelador-blender* | high | lista cerrada |
| D-1845 | Íconos de productos para UI (render automático) | revisor-visual | medium | 60 íconos generados por script |
| D-1846 | Capturas de producto para Steam | revisor-visual | low | set |
| D-1847 | Chequeo de pivotes de todo lo nuevo | revisor-visual | low | `check_pivots` verde |
| D-1848 | Peso de assets: texturas a 512 salvo excepción (lección N-315) | perfilador-rendimiento | medium | informe |
| D-1849 | Licencias y origen de cada asset descargado | documentador | low | tabla en inventario |
| D-1850 | Cápsulas de Steam con la expansión | artista-conceptual* | high | cápsulas en `docs/marketing/` |
