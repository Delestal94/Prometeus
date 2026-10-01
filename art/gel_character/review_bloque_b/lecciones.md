# Lecciones de la preparación B

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
