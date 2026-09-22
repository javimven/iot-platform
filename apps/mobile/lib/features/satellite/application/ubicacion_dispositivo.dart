import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

/// Dónde está el dispositivo, con cuánta precisión lo sabe.
class PosicionDispositivo {
  const PosicionDispositivo({required this.punto, required this.precisionMetros});

  final LatLng punto;

  /// Radio de incertidumbre. En un móvil al aire libre son unos metros; en un
  /// ordenador suele salir de la red y pueden ser kilómetros.
  final double precisionMetros;

  /// Por encima de esto no sirve para dibujar una parcela, solo para acercarse.
  static const precisionUtil = 100.0;

  bool get esAproximada => precisionMetros > precisionUtil;

  /// Zoom al que se ve el círculo de incertidumbre entero.
  double get zoom {
    if (precisionMetros <= 30) return 18;
    if (precisionMetros <= 150) return 17;
    if (precisionMetros <= 1000) return 15;
    if (precisionMetros <= 5000) return 13;
    return 11;
  }
}

/// No se ha podido saber dónde está el dispositivo; [mensaje] dice por qué y
/// qué hacer, en palabras de quien lo va a leer.
class UbicacionNoDisponible implements Exception {
  const UbicacionNoDisponible(this.mensaje);

  final String mensaje;

  @override
  String toString() => mensaje;
}

/// Separado para que las pruebas no dependan del GPS ni de los permisos.
abstract class UbicacionDelDispositivo {
  Future<PosicionDispositivo> actual();
}

/// La de verdad, con `geolocator`: GPS en el móvil, la API de geolocalización
/// del navegador en la web (solo funciona con HTTPS, como staging y
/// producción).
class UbicacionConGeolocator implements UbicacionDelDispositivo {
  @override
  Future<PosicionDispositivo> actual() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw const UbicacionNoDisponible(
        'La ubicación del dispositivo está desactivada. Actívala y vuelve a probar.',
      );
    }

    var permiso = await Geolocator.checkPermission();
    if (permiso == LocationPermission.denied) {
      permiso = await Geolocator.requestPermission();
    }
    if (permiso == LocationPermission.denied) {
      throw const UbicacionNoDisponible('Sin permiso para usar tu ubicación.');
    }
    if (permiso == LocationPermission.deniedForever) {
      throw const UbicacionNoDisponible(
        'El permiso de ubicación está bloqueado. Actívalo en los ajustes del navegador '
        'o del teléfono para esta aplicación.',
      );
    }

    try {
      final posicion = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 20),
        ),
      );
      return PosicionDispositivo(
        punto: LatLng(posicion.latitude, posicion.longitude),
        precisionMetros: posicion.accuracy,
      );
    } on TimeoutException {
      throw const UbicacionNoDisponible(
        'No llegó la ubicación a tiempo. Si estás bajo techo, prueba al aire libre.',
      );
    }
  }
}

final ubicacionDelDispositivoProvider = Provider<UbicacionDelDispositivo>(
  (ref) => UbicacionConGeolocator(),
);
