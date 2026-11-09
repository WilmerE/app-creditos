import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:webview_flutter_windows/webview_flutter_windows.dart';

const _googleMapsApiKey = String.fromEnvironment('GOOGLE_MAPS_API_KEY');

class ClientLocationPickerDialog extends StatefulWidget {
  const ClientLocationPickerDialog({
    super.key,
    this.initialLatitude,
    this.initialLongitude,
  });

  final double? initialLatitude;
  final double? initialLongitude;

  @override
  State<ClientLocationPickerDialog> createState() =>
      _ClientLocationPickerDialogState();
}

class _ClientLocationPickerDialogState
    extends State<ClientLocationPickerDialog> {
  final _controller = WebviewController();
  StreamSubscription<Object?>? _messageSubscription;
  double? _latitude;
  double? _longitude;
  Object? _error;
  bool _initialized = false;
  bool _gettingLocation = false;

  @override
  void initState() {
    super.initState();
    _latitude = widget.initialLatitude;
    _longitude = widget.initialLongitude;
    if (defaultTargetPlatform != TargetPlatform.windows) {
      _error = UnsupportedError('Google Maps picker requires Windows.');
    } else if (_googleMapsApiKey.isNotEmpty) {
      _initializeMap();
    }
  }

  Future<void> _initializeMap() async {
    try {
      await _controller.initialize();
      await _controller.setPopupWindowPolicy(WebviewPopupWindowPolicy.deny);
      _messageSubscription = _controller.webMessage.listen(_onMapMessage);
      await _controller.loadUrl(
        'data:text/html;charset=utf-8,${Uri.encodeComponent(_mapHtml)}',
      );
      if (mounted) setState(() => _initialized = true);
    } on Object catch (error) {
      if (mounted) setState(() => _error = error);
    }
  }

  String get _mapHtml {
    final latitude = widget.initialLatitude ?? 14.6349;
    final longitude = widget.initialLongitude ?? -90.5069;
    final key = Uri.encodeQueryComponent(_googleMapsApiKey);
    final hasInitialLocation =
        widget.initialLatitude != null && widget.initialLongitude != null;
    return '''
<!doctype html>
<html><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<style>html,body,#map{height:100%;width:100%;margin:0;padding:0}</style>
<script>
let map, marker;
function initMap(){
  const start={lat:$latitude,lng:$longitude};
  map=new google.maps.Map(document.getElementById('map'),{center:start,zoom:16,mapTypeControl:true,streetViewControl:false,fullscreenControl:false});
  if($hasInitialLocation) setMarker(start);
  map.addListener('click',e=>setMarker({lat:e.latLng.lat(),lng:e.latLng.lng()}));
}
function setMarker(point){
  if(marker) marker.setMap(null);
  marker=new google.maps.Marker({position:point,map:map,draggable:true});
  marker.addListener('dragend',()=>sendPoint(marker.getPosition()));
  sendPoint(point);
}
function useCurrentLocation(lat,lng){
  const point={lat:lat,lng:lng};
  map.setCenter(point);
  map.setZoom(17);
  setMarker(point);
}
function sendPoint(point){
  const lat=typeof point.lat==='function'?point.lat():point.lat;
  const lng=typeof point.lng==='function'?point.lng():point.lng;
  window.chrome.webview.postMessage(JSON.stringify({latitude:lat,lng:lng}));
}
</script>
<script async defer src="https://maps.googleapis.com/maps/api/js?key=$key&callback=initMap"></script>
</head><body><div id="map"></div></body></html>
''';
  }

  Future<void> _useCurrentLocation() async {
    setState(() => _gettingLocation = true);
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        throw StateError('Activa los servicios de ubicación del dispositivo.');
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied) {
        throw StateError('No se concedió permiso para consultar la ubicación.');
      }
      if (permission == LocationPermission.deniedForever) {
        throw StateError(
          'El permiso está bloqueado. Habilita la ubicación para la app en la configuración del dispositivo.',
        );
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 25),
        ),
      );
      await _controller.executeScript(
        'useCurrentLocation(${position.latitude},${position.longitude})',
      );
    } on Object catch (error) {
      if (mounted) {
        final message = error is StateError
            ? error.message.toString()
            : 'No se pudo obtener la ubicación. Revisa permisos, señal y servicios de ubicación.';
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(message)));
      }
    } finally {
      if (mounted) setState(() => _gettingLocation = false);
    }
  }

  void _onMapMessage(Object? message) {
    try {
      final decoded = message is String ? jsonDecode(message) : message;
      if (decoded is! Map) return;
      final latitude = decoded['latitude'];
      final longitude = decoded['lng'];
      if (latitude is! num || longitude is! num) return;
      if (mounted) {
        setState(() {
          _latitude = latitude.toDouble();
          _longitude = longitude.toDouble();
        });
      }
    } on Object {
      // Ignore messages that are not a selected coordinate.
    }
  }

  @override
  void dispose() {
    unawaited(_messageSubscription?.cancel());
    unawaited(_controller.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Dialog(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 900, maxHeight: 720),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Seleccionar ubicación',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            if (_initialized)
              Align(
                alignment: Alignment.centerRight,
                child: OutlinedButton.icon(
                  onPressed: _gettingLocation ? null : _useCurrentLocation,
                  icon: _gettingLocation
                      ? const SizedBox.square(
                          dimension: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.my_location),
                  label: Text(
                    _gettingLocation
                        ? 'Buscando ubicación…'
                        : 'Usar mi ubicación',
                  ),
                ),
              ),
            if (_initialized) const SizedBox(height: 8),
            if (_googleMapsApiKey.isEmpty)
              const _MapMessage(
                icon: Icons.key_off_outlined,
                message: 'Configura GOOGLE_MAPS_API_KEY al compilar la aplicación para habilitar Google Maps.',
              )
            else if (_error != null)
              const _MapMessage(
                icon: Icons.map_outlined,
                message: 'No se pudo iniciar el mapa. Verifica que WebView2 esté disponible y que la app corra en Windows.',
              )
            else if (!_initialized)
              const Expanded(child: Center(child: CircularProgressIndicator()))
            else
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Webview(_controller),
                ),
              ),
            if (_latitude != null && _longitude != null) ...[
              const SizedBox(height: 12),
              Text(
                'Latitud: ${_latitude!.toStringAsFixed(6)}  ·  Longitud: ${_longitude!.toStringAsFixed(6)}',
              ),
            ],
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancelar'),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: _latitude == null || _longitude == null
                      ? null
                      : () => Navigator.of(
                          context,
                        ).pop((latitude: _latitude!, longitude: _longitude!)),
                  icon: const Icon(Icons.check),
                  label: const Text('Usar ubicación'),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

class _MapMessage extends StatelessWidget {
  const _MapMessage({required this.icon, required this.message});

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) => Expanded(
    child: Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
          ],
        ),
      ),
    ),
  );
}
