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

### Zoom con botones, no con la rueda

También a petición del usuario. No es solo gusto: en la ficha de la parcela el mapa está dentro de una página con scroll, y con la rueda activa, bajar por la página acercaba el mapa en vez de moverse. La rueda queda desactivada y el zoom va con dos botones (+ y −); en pantallas táctiles se sigue pudiendo pellizcar.

## Consecuencias

- La app gana dos dependencias (`flutter_map`, `latlong2`) y ninguna nativa.
- `ParcelMap` es deliberadamente tonto: recibe anillos, una imagen opcional y vértices en curso, y los pinta. No sabe de NDVI ni de observaciones, así que sirve igual para la ficha de una parcela y para el dibujo de una nueva.
- El NDVI va **entre** el mapa base y el contorno, para que el borde de la parcela siempre se vea, y con un control de opacidad: el usuario querrá comparar lo que ve con lo que hay debajo.
- Las pruebas de widget no comprueban el mapa tesela a tesela: eso pediría red y no diría nada útil. Se prueban los estados de la pantalla, que es donde están las decisiones.
