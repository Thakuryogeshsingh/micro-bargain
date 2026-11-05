import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' as ll;

import '../../core/config/app_config.dart';
import '../../core/i18n/i18n.dart';
import '../../core/location/location_service.dart';
import '../../core/theme/app_theme.dart';

/// A place chosen on the map, with the address OpenStreetMap knows for it.
class PickedPlace {
  PickedPlace({required this.latitude, required this.longitude, this.city = '', this.state = '', this.pincode = '', this.line = ''});

  final double latitude;
  final double longitude;
  final String city;
  final String state;
  final String pincode;
  final String line;
}

// OpenStreetMap's free geocoder; it asks apps to identify themselves and stay under 1 request a second.
final _osm = Dio(BaseOptions(
  baseUrl: 'https://nominatim.openstreetmap.org',
  headers: {'User-Agent': 'MicroBargain/1.0 (com.microbargain.micro_bargain)'},
  connectTimeout: const Duration(seconds: 8),
  receiveTimeout: const Duration(seconds: 8),
));

Future<PickedPlace?> pickLocationOnMap(BuildContext context, {double? latitude, double? longitude, String title = ''}) {
  return Navigator.of(context).push<PickedPlace>(MaterialPageRoute(
    builder: (_) => LocationPickerScreen(latitude: latitude, longitude: longitude, title: title),
  ));
}

class LocationPickerScreen extends StatefulWidget {
  const LocationPickerScreen({super.key, this.latitude, this.longitude, this.title = ''});

  final double? latitude;
  final double? longitude;
  final String title;

  @override
  State<LocationPickerScreen> createState() => _LocationPickerScreenState();
}

class _LocationPickerScreenState extends State<LocationPickerScreen> {
  final _map = MapController();
  final _query = TextEditingController();
  late ll.LatLng _center = ll.LatLng(widget.latitude ?? AppConfig.fallbackLatitude, widget.longitude ?? AppConfig.fallbackLongitude);
  PickedPlace? _place;
  List<Map<String, dynamic>> _results = [];
  bool _looking = false;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _lookup();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  static String _first(Map address, List<String> keys) {
    for (final k in keys) {
      final v = address[k];
      if (v is String && v.isNotEmpty) return v;
    }
    return '';
  }

  Future<void> _lookup() async {
    final at = _center;
    setState(() => _looking = true);
    try {
      final res = await _osm.get('/reverse', queryParameters: {
        'format': 'jsonv2', 'lat': at.latitude, 'lon': at.longitude, 'zoom': 18, 'addressdetails': 1, 'accept-language': 'en',
      });
      final a = Map<String, dynamic>.from(res.data['address'] ?? {});
      if (!mounted || at != _center) return;
      setState(() => _place = PickedPlace(
            latitude: at.latitude,
            longitude: at.longitude,
            city: _first(a, ['city', 'town', 'village', 'municipality', 'county', 'state_district']),
            state: _first(a, ['state']),
            pincode: (_first(a, ['postcode'])).replaceAll(' ', ''),
            line: [_first(a, ['house_number']), _first(a, ['road', 'pedestrian']), _first(a, ['neighbourhood', 'suburb', 'quarter'])]
                .where((s) => s.isNotEmpty)
                .join(', '),
          ));
    } catch (_) {
      // Offline or rate-limited: the pin still works, the person types the address.
      if (mounted && at == _center) setState(() => _place = PickedPlace(latitude: at.latitude, longitude: at.longitude));
    } finally {
      if (mounted) setState(() => _looking = false);
    }
  }

  Future<void> _search(String text) async {
    if (text.trim().length < 2) return;
    try {
      final res = await _osm.get('/search', queryParameters: {
        'format': 'jsonv2', 'q': text.trim(), 'countrycodes': 'in', 'limit': 6, 'accept-language': 'en',
      });
      if (mounted) setState(() => _results = [for (final r in res.data as List) Map<String, dynamic>.from(r)]);
    } catch (_) {
      if (mounted) setState(() => _results = []);
    }
  }

  void _moveTo(ll.LatLng point, {double zoom = 15}) {
    _map.move(point, zoom);
    setState(() {
      _center = point;
      _results = [];
    });
    FocusScope.of(context).unfocus();
    _lookup();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title.isEmpty ? tr('मैप पर जगह चुनें') : widget.title)),
      body: Stack(children: [
        FlutterMap(
          mapController: _map,
          options: MapOptions(
            initialCenter: _center,
            initialZoom: 15,
            onPositionChanged: (camera, hasGesture) {
              if (!hasGesture) return;
              _center = camera.center;
              _debounce?.cancel();
              _debounce = Timer(const Duration(milliseconds: 900), _lookup);
            },
          ),
          children: [
            TileLayer(urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png', userAgentPackageName: 'com.microbargain.micro_bargain'),
            const SimpleAttributionWidget(source: Text('OpenStreetMap')),
          ],
        ),
        // The pin stays in the middle; the map moves under it.
        IgnorePointer(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 44),
              child: Icon(Icons.location_on_rounded, size: 48, color: AppTheme.accentInk, shadows: const [Shadow(blurRadius: 8, color: Colors.black38)]),
            ),
          ),
        ),
        Positioned(
          left: 12,
          right: 12,
          top: 12,
          child: Material(
            elevation: 6,
            borderRadius: BorderRadius.circular(16),
            color: AppTheme.card,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(
                controller: _query,
                textInputAction: TextInputAction.search,
                onSubmitted: _search,
                decoration: InputDecoration(
                  hintText: tr('शहर या इलाका खोजें (जैसे Jaipur)'),
                  prefixIcon: const Icon(Icons.search_rounded),
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  filled: false,
                ),
              ),
              for (final r in _results)
                ListTile(
                  dense: true,
                  leading: const Icon(Icons.place_outlined),
                  title: Text(r['display_name'] ?? '', maxLines: 2, overflow: TextOverflow.ellipsis),
                  onTap: () => _moveTo(ll.LatLng(double.parse(r['lat']), double.parse(r['lon'])), zoom: 14),
                ),
            ]),
          ),
        ),
        Positioned(
          right: 16,
          bottom: 190,
          child: FloatingActionButton.small(
            heroTag: 'picker-gps',
            tooltip: tr('मेरी लोकेशन'),
            onPressed: () async {
              final here = await currentLocation();
              if (mounted) _moveTo(ll.LatLng(here.latitude, here.longitude), zoom: 16);
            },
            child: const Icon(Icons.my_location_rounded),
          ),
        ),
        Positioned(
          left: 12,
          right: 12,
          bottom: 16,
          child: SafeArea(
            child: Material(
              elevation: 8,
              borderRadius: BorderRadius.circular(20),
              color: AppTheme.card,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Row(children: [
                    Icon(Icons.place_rounded, color: AppTheme.accentInk),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _looking
                          ? Text(tr('पता ढूंढ रहे हैं…'), style: TextStyle(color: AppTheme.muted))
                          : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(_place?.city.isNotEmpty == true ? _place!.city : tr('चुनी हुई जगह'),
                                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: AppTheme.ink)),
                              if ((_place?.line ?? '').isNotEmpty || (_place?.pincode ?? '').isNotEmpty)
                                Text([_place!.line, _place!.state, _place!.pincode].where((s) => s.isNotEmpty).join(', '),
                                    maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: AppTheme.muted)),
                            ]),
                    ),
                  ]),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: _place == null || _looking ? null : () => Navigator.pop(context, _place),
                    child: Text(tr('यह जगह चुनें')),
                  ),
                ]),
              ),
            ),
          ),
        ),
      ]),
    );
  }
}
