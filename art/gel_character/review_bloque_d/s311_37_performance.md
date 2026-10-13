# S-311.37 — costo de cuatro personajes gel

Medición del 2026-10-12 con `tests/bench_gel_character.gd`.

## Escenario fijo

- Resolución: 1280 × 720, VSync desactivado.
- Renderizador: Forward Mobile sobre Vulkan 1.4.349.
- GPU: AMD Radeon RX 7800 XT.
- Comparación A: cuatro instancias de `sm_char_player_rounded.glb`, el personaje activo al medir.
- Comparación B: cuatro instancias de `gel_body_lod0.glb` con material de ejecución y los presets
  Delgada, Flaca, Rellena y Larguirucha.
- Mismo fondo, cámara, suelo, dos luces, sombra, animación Idle, calentamiento de 60 cuadros y cinco
  segundos de muestras por variante.
- Tiempo GPU: mediana de los timestamps de `RenderingDevice`; se valida contra la línea independiente
  `GPU PROFILE` que imprime Godot.

Comando:

```powershell
Godot_v4.7.2-stable_win64_console.exe --gpu-profile --path do-not-drop `
  --rendering-method mobile --rendering-driver vulkan `
  --script res://tests/bench_gel_character.gd -- --seconds=5 --warmup=60
```

## Resultado

| Variante | GPU p50 | Draw calls | Primitivas |
| --- | ---: | ---: | ---: |
| 4 personajes actuales | 0,146 ms | 5 | 189 324 |
| 4 personajes gel | 0,135 ms | 5 | 37 636 |
| Diferencia gel − actual | **−0,011 ms** | 0 | −151 688 |

Presupuesto del ítem S-311.7: **≤ +0,500 ms** con cuatro personajes. Resultado: **PASA**, con un
margen de 0,511 ms respecto del límite.

El proyecto usa Compatibility durante el juego normal, pero ese backend no expone los timestamps de
`RenderingDevice`. Por eso la puerta automática usa Mobile/Vulkan en ambos lados de la comparación.
La CI repite el escenario con el dispositivo de software disponible y conserva el log como dato
informativo; la decisión del presupuesto se basa en la corrida de hardware anterior.
