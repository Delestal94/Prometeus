# Lecciones de la preparación B

## Axila reconstruida y simplificación, 2026-10-02

- Dividir sólo longitudinalmente un quad largo conserva su pliegue transversal.
  Reconstruir loops en ambas direcciones y sus posiciones curvas redujo el
  dihedro A75 de 143,17° a 72,80°; comprobar también la superficie animada real.
- Una corrección que pasa las poses base puede fallar en morphs combinados.
  LOD2 había borrado la transición cadera-muslo: la muestra 30 invertía una cara.
  Proteger esos loops y repetir el barrido, sin alterar rangos ni tolerancias.
- Los pesos normalizados del GLB sufren cuantización al importarse en Godot.
  Se midió un déficit máximo de 4,581e-5, compatible con pasos de 1/65535.
  La prueba de importación permite cuatro pasos por los cuatro slots; mantiene
  estrictas las comprobaciones de finitud, signo e índices de huesos.
- Guardar evidencia nueva sin presentar capturas antiguas como actuales.
  A60/A75 sin aberturas y LOD dentro del 5 % no prueban A90, todo el continuo
  ni la aprobación final del material y de los ítems corporales completos.

- Incidencia de dos caras por arista no demuestra una superficie manifold:
  verificar también que el enlace de cada vértice sea un único ciclo.
- No soldar costuras por tolerancia espacial, ni solo por posición evaluada:
  exigir posiciones/deltas originales y evaluados iguales para todos los morphs.
- Normales unitarias pueden estar invertidas. Verificar hemisferio contra la
  cara geométrica sin exigir igualdad de normales suaves con normales planas.
- El error de plano de un simplificador puede plegar una planta plana. Proteger
  sus vértices, comprobar la regresión y volver a barrer el GLB exportado.
- Skeleton3D recibe rotaciones locales totales, no solamente deltas: conservar
  el reposo local al construir poses diagnósticas. Preservar los clips fuente;
  el pull de N-115 añadió Run: reexportar los nueve clips y repetir los tests.
- UV fija no implica decal estable: los valores singulares de la deformación
  muestran distorsión física. El límite15% no se reduce para aprobar una entrega.
- Un núcleo o ajuste lineal experimental no es una solución aprobada: contar
  exterior+nucleo y reportar errores reales antes de diseñar el shaderD.

Captura de conocimiento antes de PR; bd/self-reflect no disponible como comando
en este entorno, por lo que estas lecciones quedan junto a la evidencia revisable.

## Corrección de defaults y ensayo descartado

- `shape_key_add` deja la nueva key activa: fijar su `value` explícitamente a
  cero y verificar también el `.blend` guardado y los valores del GLB, no solo
  la captura que restablece morphs antes de renderizar.
- Un importador puede ignorar un default declarado. La prueba actual de Godot
  pasó con los archivos anteriores; no atribuirle una deformación de carga que
  no se reprodujo. Validar la autoría/exportación en su capa responsable.
- Pesos normalizados y gradientes menores no garantizan una pose sin pliegues.
  El ensayo de hombro pasó esas métricas, pero generó dos aberturas visibles en
  axilas. El chequeo de aristas no detectaba los triángulos invertidos de la pose.
  Se retiró la corrección y se conservaron los pesos originales; no ocultar
  pliegues usando materiales de doble cara ni rebajar umbrales para aprobar.
- Una mejora numérica no reemplaza la comparación visual. Esta entrega corrige
  únicamente defaults; el ajuste visual del hombro sigue pendiente.

## Contacto numérico en anillos de retopología

- En una arista segmentada válida, el skinning en reposo desplazó posiciones
  hasta 0,125 µm. Signos opuestos de distancias al plano, ambos dentro de la
  tolerancia, generaban un falso cruce 31 nm más allá del vértice compartido.
- Un producto cruzado mide área: su tolerancia debe escalarse por el largo de
  la arista para conservar la tolerancia de distancia. No aumentar el epsilon
  global ni excluir caras que comparten sólo un vértice: pueden cruzarse fuera
  de él. Las regresiones conservan esos cruces reales y los casi coplanares.
- No suprimir cruces sólo porque sus extremos estén cerca del plano: una
  intersección transversal puede tener distancias menores que epsilon y un
  segmento interior real. La corrección conserva el cálculo de signos opuestos.
- Dividir anillos conservando las posiciones no resolvió los pliegues de los
  LOD reducidos. Los candidatos quedaron locales y se descartaron: esta
  corrección del predicado no aprueba la retopología ni los ítems 10/12/13.
