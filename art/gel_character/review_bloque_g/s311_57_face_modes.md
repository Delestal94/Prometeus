# S-311.57 — cara interna frente a cara en superficie

Fecha: 2026-10-18. Modelo evaluado: `gel_body_lod0.glb`, material transparente
aprobado en el bloque E y cabeza Delgada con los extremos de `head_size` y
`head_shape`.

| Criterio del bloque E | Flotando dentro | En superficie |
|---|---|---|
| Conserva la silueta lisa aprobada | Sí; queda a 68–84 % del elipsoide | Sí; sobresale sólo 2,5 mm |
| Lectura a través del gel | Variable por absorción y prepasada de profundidad | Estable en transparente y opaco |
| Riesgo al cambiar forma/tamaño | Bajo, pero el dibujo se encoge dentro del volumen | Bajo; sigue el hueso y escala X/Y con la forma |
| Lectura frontal y en movimiento | Menor contraste, especialmente en el centro denso | Contorno nítido sin z-fighting |
| Compatibilidad GL | Depende del orden de transparencia | Alpha scissor existente, sin lectura de pantalla |

## Decisión

Se elige **superficie**. Es la opción que mantiene la lectura de estudio del
bloque E sin depender del orden de transparencia, funciona también en la
variante opaca lechosa y no altera la silueta medible. La alternativa interna
permanece implementada como modo reproducible para futuras skins, pero no es el
modo de producción.

La cara por defecto es **ninguna**: ojos, cejas y boca nacen ocultos. Cuando se
elige una expresión, tres capas curvas siguen el hueso real `head`; el tamaño
del hueso y el parámetro `head_shape` escalan el dibujo con la cabeza.
