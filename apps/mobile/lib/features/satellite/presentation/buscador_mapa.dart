import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/widgets/app_card.dart';
import '../data/buscador_lugares.dart';
import '../data/coordenadas.dart';

/// Zoom al ir a unas coordenadas escritas a mano: lo bastante cerca para ver
/// los lindes de un campo.
const _zoomCoordenadas = 17.0;

/// Buscador que flota sobre el mapa: pueblos, calles, portales, puntos
/// kilométricos, parajes, referencias catastrales (CartoCiudad) **y
/// coordenadas**, todo en la misma caja. Lo pidió el usuario (2026-09-22): con
/// la foto aérea sola cuesta saber dónde se está, y para encontrar la parcela
/// hacen falta referencias.
///
/// Las coordenadas no salen del dispositivo: si el texto se lee como tales
/// (`leerCoordenadas`), se va directo y no se pregunta a nadie.
class BuscadorMapa extends ConsumerStatefulWidget {
  const BuscadorMapa({required this.onElegido, super.key});

  /// Se llama con el punto elegido y el zoom al que conviene enseñarlo.
  final void Function(LatLng punto, double zoom) onElegido;

  @override
  ConsumerState<BuscadorMapa> createState() => _BuscadorMapaState();
}

class _BuscadorMapaState extends ConsumerState<BuscadorMapa> {
  static const _retardo = Duration(milliseconds: 350);
  static const _minimoLetras = 3;

  final _texto = TextEditingController();
  final _foco = FocusNode();
  Timer? _espera;

  /// Cada búsqueda lleva un número: si llega la respuesta de una vieja
  /// después de la de una nueva, se ignora.
  int _peticion = 0;

  bool _abierto = false;
  bool _buscando = false;
  String? _error;
  List<LugarSugerido> _lugares = const [];
  LatLng? _coordenadas;

  @override
  void dispose() {
    _espera?.cancel();
    _texto.dispose();
    _foco.dispose();
    super.dispose();
  }

  void _alCambiar(String valor) {
    _espera?.cancel();
    _peticion++;
    final texto = valor.trim();
    final coordenadas = leerCoordenadas(texto);
    final hayQueBuscar = coordenadas == null && texto.length >= _minimoLetras;

    setState(() {
      _coordenadas = coordenadas;
      _error = null;
      _abierto = texto.isNotEmpty;
      _buscando = hayQueBuscar;
      if (!hayQueBuscar) _lugares = const [];
    });
    if (hayQueBuscar) {
      _espera = Timer(_retardo, () => _buscar(texto));
    }
  }

  Future<void> _buscar(String texto) async {
    final esta = ++_peticion;
    try {
      final lugares = await ref.read(buscadorDeLugaresProvider).sugerencias(texto);
      if (!mounted || esta != _peticion) return;
      setState(() {
        _lugares = lugares;
        _buscando = false;
      });
    } catch (_) {
      if (!mounted || esta != _peticion) return;
      setState(() {
        _lugares = const [];
        _buscando = false;
        _error = 'No se pudo buscar. Comprueba la conexión y vuelve a probar.';
      });
    }
  }

  Future<void> _elegirLugar(LugarSugerido lugar) async {
    final esta = ++_peticion;
    setState(() {
      _buscando = true;
      _error = null;
    });
    try {
      final punto = await ref.read(buscadorDeLugaresProvider).posicion(lugar);
      if (!mounted || esta != _peticion) return;
      if (punto == null) {
        setState(() {
          _buscando = false;
          _error = 'No hay coordenadas para «${lugar.texto}». Prueba con otro resultado.';
        });
        return;
      }
      _cerrar(texto: lugar.texto);
      widget.onElegido(punto, lugar.zoom);
    } catch (_) {
      if (!mounted || esta != _peticion) return;
      setState(() {
        _buscando = false;
        _error = 'No se pudo situar «${lugar.texto}». Comprueba la conexión.';
      });
    }
  }

  void _irACoordenadas(LatLng punto) {
    _cerrar(texto: formatearCoordenadas(punto));
    widget.onElegido(punto, _zoomCoordenadas);
  }

  /// Intro: coordenadas si lo son, y si no, el primer resultado (buscándolo
  /// en el momento si todavía no había dado tiempo).
  Future<void> _alEnviar(String valor) async {
    final coordenadas = leerCoordenadas(valor);
    if (coordenadas != null) {
      _irACoordenadas(coordenadas);
      return;
    }
    final texto = valor.trim();
    if (texto.length < _minimoLetras) return;
    if (_lugares.isEmpty) {
      _espera?.cancel();
      await _buscar(texto);
    }
    if (mounted && _lugares.isNotEmpty) {
      await _elegirLugar(_lugares.first);
    }
  }

  void _cerrar({String? texto}) {
    _espera?.cancel();
    _peticion++;
    if (texto != null) _texto.text = texto;
    _foco.unfocus();
    setState(() {
      _abierto = false;
      _buscando = false;
      _lugares = const [];
      _coordenadas = null;
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return TapRegion(
      // Tocar el mapa cierra la lista, pero no borra lo escrito.
      onTapOutside: (_) {
        if (_abierto) setState(() => _abierto = false);
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppCard(
            padding: EdgeInsets.zero,
            child: TextField(
              controller: _texto,
              focusNode: _foco,
              onChanged: _alCambiar,
              onSubmitted: _alEnviar,
              onTap: () {
                if (_texto.text.trim().isNotEmpty) setState(() => _abierto = true);
              },
              textInputAction: TextInputAction.search,
              style: theme.textTheme.bodyMedium,
              decoration: InputDecoration(
                hintText: 'Pueblo, calle, ref. catastral o coordenadas',
                hintStyle: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                prefixIcon: const Icon(Icons.search),
                // Cada cambio del texto pasa por setState (`_alCambiar`,
                // `_cerrar`), así que basta con mirarlo aquí.
                suffixIcon: _texto.text.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Borrar la búsqueda',
                        icon: const Icon(Icons.close),
                        onPressed: () {
                          _texto.clear();
                          _cerrar();
                        },
                      ),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
          if (_abierto) ...[
            const SizedBox(height: 4),
            AppCard(
              padding: EdgeInsets.zero,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 300),
                child: _Resultados(
                  buscando: _buscando,
                  error: _error,
                  coordenadas: _coordenadas,
                  lugares: _lugares,
                  textoCorto: _texto.text.trim().length < _minimoLetras,
                  pareceNumerico: RegExp(r'^[\d\s.,;°º-]+$').hasMatch(_texto.text.trim()),
                  onCoordenadas: _irACoordenadas,
                  onLugar: _elegirLugar,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Resultados extends StatelessWidget {
  const _Resultados({
    required this.buscando,
    required this.error,
    required this.coordenadas,
    required this.lugares,
    required this.textoCorto,
    required this.pareceNumerico,
    required this.onCoordenadas,
    required this.onLugar,
  });

  final bool buscando;
  final String? error;
  final LatLng? coordenadas;
  final List<LugarSugerido> lugares;
  final bool textoCorto;
  final bool pareceNumerico;
  final void Function(LatLng) onCoordenadas;
  final void Function(LugarSugerido) onLugar;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pie = Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 8),
      child: Text(
        BuscadorDeLugares.atribucion,
        style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
      ),
    );

    Widget aviso(String texto) => Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Text(texto, style: theme.textTheme.bodySmall),
        );

    if (coordenadas != null) {
      return ListTile(
        leading: const Icon(Icons.pin_drop_outlined),
        title: Text('Ir a ${formatearCoordenadas(coordenadas!)}'),
        subtitle: const Text('Coordenadas'),
        onTap: () => onCoordenadas(coordenadas!),
      );
    }

    final List<Widget> filas;
    if (buscando) {
      filas = [
        const Padding(
          padding: EdgeInsets.all(16),
          child: Center(child: CircularProgressIndicator()),
        ),
      ];
    } else if (error != null) {
      filas = [aviso(error!)];
    } else if (textoCorto) {
      filas = [aviso('Escribe al menos tres letras.')];
    } else if (lugares.isEmpty) {
      filas = [
        aviso(
          pareceNumerico
              ? 'Si son coordenadas, van en grados y con la latitud primero: 39.5116, -0.4536.'
              : 'No se ha encontrado nada con ese nombre.',
        ),
      ];
    } else {
      filas = [
        for (final lugar in lugares)
          ListTile(
            dense: true,
            leading: const Icon(Icons.place_outlined),
            title: Text(lugar.texto, maxLines: 2, overflow: TextOverflow.ellipsis),
            subtitle: lugar.detalle == null ? null : Text(lugar.detalle!),
            onTap: () => onLugar(lugar),
          ),
      ];
    }

    return ListView(
      shrinkWrap: true,
      padding: EdgeInsets.zero,
      children: [...filas, pie],
    );
  }
}
