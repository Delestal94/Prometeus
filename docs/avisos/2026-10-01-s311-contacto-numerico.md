# S-311: falsos contactos junto a vértices compartidos

`art/gel_character/gel_body_validation.py`, función `triangle_intersection`:
la comprobación interior escala la tolerancia por la longitud de la arista,
respetando las unidades de distancia. Así no acepta como interior un hit
numérico que cae fuera del extremo de una arista segmentada.

No cambia el epsilon global, la API pública ni la exclusión por adyacencia.
Fixtures independientes reproducen los cuatro falsos positivos y conservan
cruces reales casi coplanares y fuera de un vértice compartido. También se prueba
un cruce transversal real con distancias menores que epsilon: no se suprime
el chequeo de signos opuestos cerca del plano.

No se modifican modelos, rig, morphs, clips, jugador activo, red o colisiones.
Los ensayos de loops del hombro fueron descartados; 10/12/13 siguen pendientes.
Hacer pull antes de continuar el trabajo del personaje o ejecutar su validador.
