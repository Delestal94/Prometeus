# Material objetivo de la referencia

> Medición: 2026-09-30 sobre `referencia_frente.jpg` (832 × 1248 px).
>
> Los valores son sRGB **ya compuestos sobre fondo blanco y tone-mapeados en el
> JPG**. Sirven como objetivos del render/comparador; no son `albedo_color`, alpha ni
> transmisión recuperados del material original.

## Método

- Fondo de control: ROI `[30,30]–[130,130]`, mediana `#FFFFFF`.
- Las muestras usan la mediana de una región fija para reducir ruido JPEG.
- ROI `[x0,y0]–[x1,y1]` incluye el inicio y excluye el final, como
  `pixels[y0:y1, x0:x1]` en `measure_reference.py`.
- El origen `(0,0)` está arriba a la izquierda.
- El análisis de forma usa `H=1038 px` y `D=282 px`, definidos en `../LEEME.md`.

## Muestras de color

| Zona y ROI | RGB mediano | Hex | Lectura |
|---|---:|---:|---|
| Cabeza centro `[370,225]–[460,300]` | 222, 221, 226 | `#DEDDE2` | Blanco lechoso lavanda. |
| Torso centro `[360,455]–[475,680]` | 220, 219, 225 | `#DCDBE1` | Más denso que extremidades. |
| Pierna izq. `[300,815]–[345,980]` | 230, 227, 233 | `#E6E3E9` | Más transmisiva. |
| Rim cabeza izq. `[278,205]–[298,285]` | 206, 207, 219 | `#CECFDB` | Borde denso azulado. |
| Rim pie izq. `[225,1050]–[255,1100]` | 208, 209, 221 | `#D0D1DD` | Masa acumulada en bota. |
| Brazo translúcido `[210,520]–[238,650]` | 229, 227, 232 | `#E5E3E8` | Fondo visible, tinte leve. |
| Pierna translúcida `[315,820]–[345,970]` | 231, 229, 234 | `#E7E5EA` | Zona más clara. |

El torso queda aproximadamente nueve niveles de luma por debajo de brazo/pierna.
Los hex se comparan contra la salida final, no se copian al shader como color base.

## Reflejos

- **Ventana principal de cabeza:** `x≈300..361`, `y≈142..210`, caja aproximada
  62 × 69 px (`0,22 D × 0,24 D`), centro local `(0,21, 0,28)`. Tiene paneles
  rectangulares blancos, no un brillo circular genérico.
- **Glare secundario:** abajo-derecha de cabeza, `x≈461..530`, `y≈282..356`, blando.
- **Brazos:** cintas curvas longitudinales; izquierda `x≈174..296`, `y≈397..716`,
  derecha `x≈533..612`, `y≈404..706`, núcleo de 6–14 px.
- **Piernas:** cintas casi verticales `x≈269..301` y `x≈522..552`, desde
  `y≈764` hasta `y≈1020`, núcleo de 4–10 px.

El shader debe producir reflejos continuos que describan volumen. Un contorno blanco
uniforme o un punto especular redondo no pasa el criterio.

## Motas y burbujas

Las motas visibles miden principalmente 1–4 px (`0,004–0,014 D`) y tienen un
contraste local de 3–8 niveles. Hay pocas de 5–8 px. Deben quedar en espacio de
objeto, ser irregulares y sobrevivir a la animación sin convertirse en grano de
pantalla. El ruido JPEG no cuenta; la validación se hace sobre un render PNG.

## Sombra de contacto

La envolvente central del 90 % es aproximadamente `x=222..659`, `y=1138..1182`:
438 × 45 px (`0,42 H × 0,043 H`). El centro ponderado está en `(473,1154)`, unos
59 px a la derecha del centro del cuerpo, coherente con luz arriba-izquierda.
Mediana `#F7F7F7`, zona derecha `#F4F4F4`, déficit de luma mediano 4, p90 8 y máximo
aproximado 15. Debe verse blanda y sin borde duro.

## Objetivos operativos del material

- Fresnel/borde con 8–18 niveles sRGB más densos que el centro sobre fondo blanco.
  El rim difuso medido es más oscuro; el brillo especular que lo recorre es claro.
- Torso 6–12 niveles más oscuro que extremidades equivalentes; objetivo ≈9.
- Fondo de checker todavía reconocible en cabeza y extremidades, más atenuado en
  torso.
- Reflejo de ventana y cintas de extremidades dentro de las cajas/tolerancias de
  `LEEME.md`.
- Sombra dentro del rango medido y motas de bajo contraste.
- Cero facetas a 100 % y 200 %.

## Lo que la foto no puede medir

- Alpha o transmisión física: falta una captura equivalente sobre checker.
- Albedo lineal: el JPG ya está iluminado, compuesto y tone-mapeado.
- Índice de refracción y grosor real.
- Profundidad anteroposterior del pie.

Estos valores se fijan en los bloques B–E mediante perfil/turnaround, mapa de grosor
y renders de Godot; no se deducen falsamente del JPG frontal.

