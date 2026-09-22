# ADR-0011: El mapa de la app se dibuja con flutter_map, y el mapa base se decide aparte

- Estado: Aceptada
- Fecha: 2026-09-22

## Contexto

La sección Satélite (BACKLOG.md #36) necesita algo que la app no tenía en absoluto: un mapa. Hace falta para tres cosas concretas —dibujar el contorno de una parcela tocando vértices, pintar ese contorno después, y superponer la imagen de NDVI recortada a la parcela— y tiene que funcionar igual en **web, iOS y Android**, que es donde corre esta app desde el mismo código.

Se compararon las dos opciones vivas en 2026:

- **`flutter_map`** (8.3.2, publicada hace tres semanas): Dart puro, sin plugin nativo. Trae `PolygonLayer`, `MarkerLayer`, `OverlayImageLayer` (imagen georreferenciada por `LatLngBounds`) y `onTap` en el mapa. Renderiza teselas ráster.
- **MapLibre para Flutter**: vectorial y acelerado por GPU, con estilos y PMTiles. Usa los SDK nativos en móvil y `maplibre-gl-js` en web.

## Decisión

**`flutter_map`**, más `latlong2`.

Cubre exactamente lo que pide la v1 y no trae nada más. Al ser Dart puro no añade una cadena de compilación nativa por plataforma ni un JS aparte en web: un problema menos en un proyecto donde el despliegue de la web ya es manual y la app se compila para tres destinos. `OverlayImageLayer` es justo la pieza que hacía falta para el PNG del NDVI —una imagen colocada por sus límites geográficos— y no hay que inventar nada alrededor.

MapLibre es mejor herramienta si algún día hay que pintar miles de parcelas vectoriales con estilos propios. Hoy se pinta **una** parcela y una imagen encima; pagar por adelantado el coste de los SDK nativos por una ventaja que no se usa no compensa.

Obliga a subir el mínimo declarado en `pubspec.yaml` a Dart 3.6 / Flutter 3.27. La herramienta real del proyecto y la del CI ya son 3.44.8, así que en la práctica no cambia nada.

## El mapa base: ortofoto PNOA del IGN

**La librería que dibuja y el servidor que sirve las teselas son cosas distintas**, y conviene no confundirlas: cambiar de proveedor de teselas es cambiar una URL (`MAP_TILE_URL` y `MAP_ATTRIBUTION` por `--dart-define`, en `MapaBase`).

La primera versión salió con OpenStreetMap, que vale para desarrollo pero **no** para un SaaS: su política de uso no lo ampara, y la propia librería lo avisaba por consola. Al verlo, el usuario pidió un mapa satélite (2026-09-22). Para mirar un cultivo tiene toda la razón: se reconoce la parcela por la forma del campo y los caminos, no por el nombre de la calle.

**Decisión: la ortofoto PNOA de máxima actualidad del Instituto Geográfico Nacional**, por su servicio WMTS (`OI.OrthoimageCoverage`, malla `GoogleMapsCompatible`). Comprobado antes de adoptarla:

- **Licencia**: acceso libre también para uso comercial, compatible con CC BY 4.0 (Orden FOM/2807/2015), con una condición: la atribución literal **«PNOA cedido por © Instituto Geográfico Nacional de España»**, que va fija en el mapa.
- **Resolución**: 25-50 cm por píxel, de sobra para dibujar el contorno de una parcela a mano.
- **Zoom**: hay imagen hasta el nivel 20; el 21 ya devuelve 400, así que el mapa no deja acercarse más.
- **Web**: el servidor manda `Access-Control-Allow-Origin: *`, así que las teselas funcionan también en la app web (WebAssembly), no solo en móvil.
- **Coste**: ninguno. Frente a Esri, MapTiler o Stadia, que piden cuenta o clave para uso comercial.

**Límite conocido: solo cubre España.** Hoy todos los clientes están aquí. Si entra uno de fuera, habrá que contratar un proveedor comercial para esa zona y elegirlo por organización; el cambio no toca más que `MapaBase`.

### Zoom con la rueda y con botones

Primero se quitó la rueda y se pusieron botones (+ y −), porque en la ficha de la parcela el mapa está dentro de una página con scroll y la rueda acercaba el mapa en vez de bajar. El usuario lo corrigió el mismo día: los botones eran para **afinar**, no para sustituir la rueda. Quedan los dos. El precio es el que se sabía: con el cursor encima del mapa de la ficha, la rueda hace zoom; para bajar por la página hay que sacarlo del mapa. En pantallas táctiles, pellizcar.

### Llegar a la parcela: nombres, buscador y "mi ubicación"

Con la foto sola se reconoce la parcela, pero **no se sabe dónde se está** para ir a buscarla: faltan pueblos, carreteras, algo con lo que orientarse. Lo dijo el usuario al dibujar la primera parcela real (2026-09-22). Tres piezas, todas comprobadas contra el servicio antes de usarlas:

- **Capa de nombres y carreteras** encima de la ortofoto: `IGNBaseOrto`, del servicio WMTS `ign-base` del IGN. Son teselas PNG transparentes (pueblos, carreteras con su código, calles al acercarse), con imagen hasta el nivel 20 como la ortofoto, CORS abierto y licencia **CC BY 4.0 scne.es**, que es lo que declara el propio servicio en su `GetCapabilities`. Se puede apagar: al dibujar, a veces estorba.
- **Buscador sobre CartoCiudad**, el geocodificador oficial del IGN: pueblos, municipios, calles, portales, puntos kilométricos, parajes, códigos postales y **referencias catastrales**. Gratuito, sin clave ni cuota, datos CC BY 4.0 y CORS abierto, así que la app lo llama directamente. Dos llamadas: `candidates` sugiere mientras se escribe, y `find` da las coordenadas, porque las sugerencias de pueblos y calles vienen con `0, 0` (los portales y los puntos kilométricos sí las traen). **Va con un cliente HTTP propio, no con el de la API**: el de la API pone el token de sesión en cada petición, y ese token no puede salir hacia un servidor que no es el nuestro.
- **Coordenadas en la misma caja**: si lo escrito se lee como coordenadas (grados decimales con punto o coma, o grados-minutos-segundos como los copia Google Maps), se va directo, sin preguntar a nadie. No se adivinan coordenadas UTM: no son grados, y leerlas como tales llevaría a otro sitio sin avisar.
- **"Mi ubicación"** con `geolocator`: GPS en el móvil, la API del navegador en la web (pide HTTPS, que staging y producción tienen). Se pinta el círculo de incertidumbre y, si pasa de 100 m, se avisa: en un ordenador la ubicación suele salir de la red y puede ser de kilómetros, que vale para acercarse pero no para dibujar.

El buscador y "mi ubicación" solo están al **dibujar**. En la ficha de una parcela ya dibujada el mapa es pequeño (260 px) y lo que hace falta es **volver a la parcela** después de moverse, que es un botón propio; además, el mapa se encuadra en la parcela entera al abrirse, sea del tamaño que sea, en vez de un zoom fijo.

## Consecuencias

- La app gana tres dependencias: `flutter_map` y `latlong2`, sin código nativo, y `geolocator`, que sí lo tiene. Esta es la primera con permisos del sistema: ubicación en `AndroidManifest.xml` e `Info.plist`. De paso se añadió al manifiesto principal de Android el permiso de Internet, que la plantilla de Flutter solo pone en debug: sin él, una APK de release no llegaba ni a la API.
- `ParcelMap` es deliberadamente tonto: recibe anillos, una imagen opcional y vértices en curso, y los pinta. No sabe de NDVI ni de observaciones, así que sirve igual para la ficha de una parcela y para el dibujo de una nueva.
- El NDVI va **entre** el mapa base y el contorno, para que el borde de la parcela siempre se vea, y con un control de opacidad: el usuario querrá comparar lo que ve con lo que hay debajo.
- Las pruebas de widget no comprueban el mapa tesela a tesela: eso pediría red y no diría nada útil. Se prueban los estados de la pantalla, que es donde están las decisiones.
