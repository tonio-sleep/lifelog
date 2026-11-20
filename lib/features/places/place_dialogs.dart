import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../app/providers/providers.dart';
import '../../app/theme/app_theme.dart';
import '../../app/widgets/common.dart';
import '../../core/util/dates.dart';
import '../../domain/models/places.dart';
import '../../domain/models/timeline.dart';
import '../../integrations/location/location_tracking.dart';
import '../../integrations/maps/map_models.dart';
import '../../integrations/maps/map_platform.dart';
import 'place_map.dart';

const placeColorChoices = <int>[
  0xFF52796F,
  0xFF4C7F96,
  0xFF8A6BA1,
  0xFFA08052,
  0xFFB5655B,
  0xFF6B8F71,
  0xFF6A7A8C,
];

Future<Place?> showPlaceEditor(
  BuildContext context,
  WidgetRef ref, {
  Place? existing,
  double? initialLatitude,
  double? initialLongitude,
  String? initialName,
}) async {
  final saved = await showDialog<Place>(
    context: context,
    builder: (_) => _PlaceEditorDialog(
      existing: existing,
      initialLatitude: initialLatitude,
      initialLongitude: initialLongitude,
      initialName: initialName,
    ),
  );
  if (saved == null) return null;
  if (!context.mounted) return saved;
  final savedOk = await guard<int>(
    context,
    ref.read(archiveProvider.notifier).savePlace(saved).then((_) => 1),
    errorPrefix: 'Could not save place',
  );
  return savedOk == null ? null : saved;
}

class _PlaceEditorDialog extends ConsumerStatefulWidget {
  const _PlaceEditorDialog({
    this.existing,
    this.initialLatitude,
    this.initialLongitude,
    this.initialName,
  });

  final Place? existing;
  final double? initialLatitude;
  final double? initialLongitude;
  final String? initialName;

  @override
  ConsumerState<_PlaceEditorDialog> createState() => _PlaceEditorDialogState();
}

class _PlaceEditorDialogState extends ConsumerState<_PlaceEditorDialog> {
  late final TextEditingController _name;
  late final TextEditingController _notes;
  late final TextEditingController _latitude;
  late final TextEditingController _longitude;
  late double _radius;
  late int _color;
  bool _locating = false;
  String? _locationError;
  final TextEditingController _address = TextEditingController();
  final FocusNode _addressFocus = FocusNode();
  bool _searching = false;
  String? _searchError;
  List<MapSearchResult> _searchResults = const [];

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    final initialLat = existing?.latitude ?? widget.initialLatitude;
    final initialLon = existing?.longitude ?? widget.initialLongitude;
    _name = TextEditingController(
      text: existing?.name ?? widget.initialName ?? '',
    );
    _notes = TextEditingController(text: existing?.notes ?? '');
    _latitude = TextEditingController(
      text: initialLat?.toStringAsFixed(6) ?? '',
    );
    _longitude = TextEditingController(
      text: initialLon?.toStringAsFixed(6) ?? '',
    );
    _radius = existing?.radiusMeters ?? 120;
    _color = existing?.colorValue ?? placeColorChoices.first;
  }

  @override
  void dispose() {
    _name.dispose();
    _notes.dispose();
    _latitude.dispose();
    _longitude.dispose();
    _address.dispose();
    _addressFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = LifelogPalette.of(context);
    return AlertDialog(
      title: Text(widget.existing == null ? 'New place' : 'Edit place'),
      content: SizedBox(
        width: 430,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _name,
                autofocus: widget.existing == null,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Name',
                  hintText: 'Home, Work, Campus, a friend’s flat…',
                ),
              ),
              const SizedBox(height: Insets.md),
              TextField(
                controller: _notes,
                maxLines: 2,
                textInputAction: TextInputAction.done,
                onEditingComplete: () =>
                    FocusManager.instance.primaryFocus?.unfocus(),
                decoration: const InputDecoration(
                  labelText: 'Notes (optional)',
                ),
              ),
              const SizedBox(height: Insets.lg),
              Text(
                'Find an address or place',
                style: Theme.of(context).textTheme.labelMedium,
              ),
              const SizedBox(height: 2),
              Text(
                'Search a street address, business or landmark, or choose an '
                'exact point on the map. Search requests go to Apple Maps.',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: palette.mutedText),
              ),
              const SizedBox(height: Insets.sm),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _address,
                      focusNode: _addressFocus,
                      textInputAction: TextInputAction.search,
                      onSubmitted: (_) => _searchAddress(),
                      decoration: const InputDecoration(
                        labelText: 'Street address or place',
                        hintText: 'e.g. 10 Downing Street, London',
                      ),
                    ),
                  ),
                  const SizedBox(width: Insets.sm),
                  IconButton.filledTonal(
                    tooltip: 'Search',
                    onPressed: _searching ? null : _searchAddress,
                    icon: _searching
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 1.8),
                          )
                        : const Icon(Icons.search_rounded),
                  ),
                ],
              ),
              if (_searchError != null)
                Padding(
                  padding: const EdgeInsets.only(top: Insets.xs),
                  child: Text(
                    _searchError!,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.error,
                        ),
                  ),
                ),
              for (final result in _searchResults.take(5))
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.place_outlined, size: 18),
                  title: Text(
                    result.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    result.subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  onTap: () => _applySearchResult(result),
                ),
              const SizedBox(height: Insets.sm),
              OutlinedButton.icon(
                onPressed: _chooseOnMap,
                icon: const Icon(Icons.gps_fixed_rounded, size: 17),
                label: const Text('Choose exact point on map'),
              ),
              const SizedBox(height: Insets.lg),
              Text(
                'Or enter coordinates',
                style: Theme.of(context).textTheme.labelMedium,
              ),
              const SizedBox(height: 2),
              Text(
                'A named place can be useful without precise coordinates. '
                'Coordinates are only captured when you ask for them, and '
                'they are stored inside the encrypted archive.',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: palette.mutedText),
              ),
              const SizedBox(height: Insets.md),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _latitude,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                        signed: true,
                      ),
                      decoration: const InputDecoration(labelText: 'Latitude'),
                    ),
                  ),
                  const SizedBox(width: Insets.md),
                  Expanded(
                    child: TextField(
                      controller: _longitude,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                        signed: true,
                      ),
                      decoration: const InputDecoration(labelText: 'Longitude'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: Insets.sm),
              Row(
                children: [
                  OutlinedButton.icon(
                    onPressed: _locating ? null : _useCurrentLocation,
                    icon: _locating
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 1.6),
                          )
                        : const Icon(Icons.my_location_rounded, size: 17),
                    label: Text(_locating ? 'Locating…' : 'Use current position'),
                  ),
                  const SizedBox(width: Insets.sm),
                  TextButton(
                    onPressed: () {
                      _latitude.clear();
                      _longitude.clear();
                    },
                    child: const Text('Clear'),
                  ),
                ],
              ),
              if (_locationError != null) ...[
                const SizedBox(height: Insets.xs),
                Text(
                  _locationError!,
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.error,
                  ),
                ),
              ],
              const SizedBox(height: Insets.md),
              Row(
                children: [
                  Text(
                    'Visit radius',
                    style: Theme.of(context).textTheme.labelMedium,
                  ),
                  const Spacer(),
                  Text(
                    '${_radius.round()} m',
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: palette.mutedText,
                    ),
                  ),
                ],
              ),
              Slider(
                value: _radius,
                min: 40,
                max: 600,
                divisions: 28,
                label: '${_radius.round()} m',
                onChanged: (value) => setState(() => _radius = value),
              ),
              const SizedBox(height: Insets.sm),
              Wrap(
                spacing: Insets.sm,
                children: [
                  for (final color in placeColorChoices)
                    InkWell(
                      borderRadius: BorderRadius.circular(Radii.pill),
                      onTap: () => setState(() => _color = color),
                      child: Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: Color(color),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: _color == color
                                ? Theme.of(context).colorScheme.onSurface
                                : Colors.transparent,
                            width: 2,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _save, child: const Text('Save place')),
      ],
    );
  }

  Future<void> _useCurrentLocation() async {
    setState(() {
      _locating = true;
      _locationError = null;
    });
    final position = await LocationTracking.getCurrentPosition(
      requestPermission: true,
      attempts: 2,
    );
    if (!mounted) return;
    final sample = position == null
        ? null
        : LocationTracking.sampleFromPosition(position);
    if (sample == null) {
      setState(() {
        _locating = false;
        _locationError =
            'Could not get a precise GPS fix. Try again, or choose a point on the map.';
      });
      return;
    }
    setState(() {
      _latitude.text = sample.latitude.toStringAsFixed(6);
      _longitude.text = sample.longitude.toStringAsFixed(6);
      _locating = false;
      _address.clear();
      _searchResults = const [];
    });
  }

  Future<void> _searchAddress() async {
    final query = _address.text.trim();
    if (query.isEmpty) return;
    _addressFocus.unfocus();
    setState(() {
      _searching = true;
      _searchError = null;
    });
    try {
      final results = await MapSearchService().search(query);
      if (!mounted) return;
      setState(() {
        _searching = false;
        _searchResults = results;
        if (results.isEmpty) {
          _searchError = 'No matching address or place was found.';
        }
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _searching = false;
        _searchError = 'Address search is unavailable: ${_clean(error)}';
      });
    }
  }

  void _applySearchResult(MapSearchResult result) {
    setState(() {
      _latitude.text = result.latitude.toStringAsFixed(6);
      _longitude.text = result.longitude.toStringAsFixed(6);
      if (_name.text.trim().isEmpty) _name.text = result.title;
      if (_notes.text.trim().isEmpty) _notes.text = result.subtitle;
      _address.text = result.subtitle.isEmpty ? result.title : result.subtitle;
      _locationError = null;
    });
  }

  Future<void> _chooseOnMap() async {
    final lat = double.tryParse(_latitude.text.trim());
    final lon = double.tryParse(_longitude.text.trim());
    final point = await showMapPinPicker(
      context,
      initial: lat != null && lon != null
          ? MapPoint(latitude: lat, longitude: lon, name: _name.text.trim())
          : null,
    );
    if (point == null || !mounted) return;
    setState(() {
      _latitude.text = point.latitude.toStringAsFixed(6);
      _longitude.text = point.longitude.toStringAsFixed(6);
      if (_name.text.trim().isEmpty && point.name.isNotEmpty) {
        _name.text = point.name;
      }
      if (_notes.text.trim().isEmpty && point.notes.isNotEmpty) {
        _notes.text = point.notes;
      }
      _locationError = null;
    });
  }

  String _clean(Object error) {
    final text = '$error';
    return text.startsWith('Bad state: ') ? text.substring(11) : text;
  }

  void _save() {
    final name = _name.text.trim();
    if (name.isEmpty) {
      showSnack(context, 'Give the place a name.');
      return;
    }
    final latitude = _latitude.text.trim().isEmpty
        ? null
        : double.tryParse(_latitude.text.trim());
    final longitude = _longitude.text.trim().isEmpty
        ? null
        : double.tryParse(_longitude.text.trim());
    if ((latitude == null) != (longitude == null)) {
      showSnack(context, 'Enter both latitude and longitude, or neither.');
      return;
    }
    if (latitude != null && (latitude < -90 || latitude > 90)) {
      showSnack(context, 'Latitude must be between -90 and 90.');
      return;
    }
    if (longitude != null && (longitude < -180 || longitude > 180)) {
      showSnack(context, 'Longitude must be between -180 and 180.');
      return;
    }
    final existing = widget.existing;
    Navigator.of(context).pop(
      Place(
        id: existing?.id ?? const Uuid().v4(),
        name: name,
        createdAt: existing?.createdAt ?? DateTime.now(),
        latitude: latitude,
        longitude: longitude,
        radiusMeters: _radius,
        notes: _notes.text.trim(),
        colorValue: _color,
      ),
    );
  }
}

Future<Visit?> showVisitEditor(
  BuildContext context,
  WidgetRef ref, {
  Visit? existing,
  DateTime? day,
  Place? initialPlace,
  DateTime? initialStart,
}) async {
  final saved = await showDialog<Visit>(
    context: context,
    builder: (_) => _VisitEditorDialog(
      existing: existing,
      day: day,
      initialPlace: initialPlace,
      initialStart: initialStart,
    ),
  );
  if (saved == null) return null;
  if (!context.mounted) return saved;
  await guard(
    context,
    ref.read(archiveProvider.notifier).saveVisit(saved),
    errorPrefix: 'Could not save visit',
  );
  return saved;
}

class _VisitEditorDialog extends ConsumerStatefulWidget {
  const _VisitEditorDialog({
    this.existing,
    this.day,
    this.initialPlace,
    this.initialStart,
  });

  final Visit? existing;
  final DateTime? day;
  final Place? initialPlace;
  final DateTime? initialStart;

  @override
  ConsumerState<_VisitEditorDialog> createState() => _VisitEditorDialogState();
}

class _VisitEditorDialogState extends ConsumerState<_VisitEditorDialog> {
  late final TextEditingController _label;
  late final TextEditingController _notes;
  String? _placeId;
  late DateTime _start;
  DateTime? _end;
  late TimelineConfidence _confidence;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    final initialStart =
        existing?.startAt ??
        widget.initialStart ??
        _defaultStart(widget.day ?? DateTime.now());
    _start = initialStart;
    _end = existing?.endAt;
    _placeId = existing?.placeId ?? widget.initialPlace?.id;
    _label = TextEditingController(
      text:
          existing?.label ??
          widget.initialPlace?.name ??
          '',
    );
    _notes = TextEditingController(text: existing?.notes ?? '');
    _confidence = existing?.confidence ?? TimelineConfidence.confirmed;
  }

  DateTime _defaultStart(DateTime day) {
    final now = DateTime.now();
    if (sameDay(day, now)) {
      return DateTime(day.year, day.month, day.day, now.hour, now.minute);
    }
    return DateTime(day.year, day.month, day.day, 12);
  }

  @override
  void dispose() {
    _label.dispose();
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final places = ref.watch(archiveProvider).places;
    final palette = LifelogPalette.of(context);
    return AlertDialog(
      title: Text(widget.existing == null ? 'Log a visit' : 'Edit visit'),
      content: SizedBox(
        width: 430,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DropdownButtonFormField<String?>(
                initialValue: _placeId,
                decoration: const InputDecoration(labelText: 'Saved place'),
                items: [
                  const DropdownMenuItem<String?>(
                    value: null,
                    child: Text('No saved place'),
                  ),
                  for (final place in places)
                    DropdownMenuItem<String?>(
                      value: place.id,
                      child: Text(place.name),
                    ),
                ],
                onChanged: (value) {
                  setState(() {
                    _placeId = value;
                    if (value != null) {
                      final place = places.firstWhere((p) => p.id == value);
                      if (_label.text.trim().isEmpty) {
                        _label.text = place.name;
                      }
                    }
                  });
                },
              ),
              const SizedBox(height: Insets.md),
              TextField(
                controller: _label,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Label',
                  hintText: 'Home, a walk, a friend’s place…',
                ),
              ),
              const SizedBox(height: Insets.md),
              _TimeRow(
                label: 'Arrived',
                value: _start,
                onPick: () => _pick(kind: _TimeField.start),
              ),
              const SizedBox(height: Insets.sm),
              Row(
                children: [
                  Expanded(
                    child: _TimeRow(
                      label: 'Left',
                      value: _end,
                      placeholder: 'No end time',
                      onPick: _end == null
                          ? null
                          : () => _pick(kind: _TimeField.end),
                    ),
                  ),
                  Switch(
                    value: _end != null,
                    onChanged: (value) => setState(() {
                      _end = value
                          ? _start.add(const Duration(hours: 1))
                          : null;
                    }),
                  ),
                ],
              ),
              const SizedBox(height: Insets.md),
              DropdownButtonFormField<TimelineConfidence>(
                initialValue: _confidence,
                decoration: const InputDecoration(labelText: 'Confidence'),
                items: [
                  for (final confidence in TimelineConfidence.values)
                    DropdownMenuItem(
                      value: confidence,
                      child: Text(confidence.label),
                    ),
                ],
                onChanged: (value) {
                  if (value != null) setState(() => _confidence = value);
                },
              ),
              const SizedBox(height: Insets.md),
              TextField(
                controller: _notes,
                maxLines: 2,
                textInputAction: TextInputAction.done,
                onEditingComplete: () =>
                    FocusManager.instance.primaryFocus?.unfocus(),
                decoration: const InputDecoration(
                  labelText: 'Notes (optional)',
                ),
              ),
              const SizedBox(height: Insets.md),
              Text(
                'You can log visits manually. If day tracking is turned on in Places, '
                'Lifelog can also estimate visits from your location while the app is in use. '
                'Location data stays on this device.',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: palette.mutedText),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _save, child: const Text('Save visit')),
      ],
    );
  }

  Future<void> _pick({required _TimeField kind}) async {
    final initial = kind == _TimeField.start ? _start : (_end ?? _start);
    final date = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
    );
    if (!mounted) return;
    final picked = DateTime(
      date.year,
      date.month,
      date.day,
      time?.hour ?? initial.hour,
      time?.minute ?? initial.minute,
    );
    setState(() {
      if (kind == _TimeField.start) {
        final duration = _end?.difference(_start);
        _start = picked;
        if (_end != null) {
          _end = picked.add(duration ?? const Duration(hours: 1));
        }
      } else {
        _end = picked;
      }
    });
  }

  void _save() {
    final placeId = _placeId;
    final place = placeId == null
        ? null
        : ref.read(archiveProvider).placeById(placeId);
    final label = _label.text.trim().isEmpty
        ? (place?.name ?? 'Visit')
        : _label.text.trim();
    if (_end != null && !_end!.isAfter(_start)) {
      showSnack(context, 'The departure time must be after arrival.');
      return;
    }
    final existing = widget.existing;
    Navigator.of(context).pop(
      Visit(
        id: existing?.id ?? const Uuid().v4(),
        label: label,
        startAt: _start,
        placeId: placeId,
        endAt: _end,
        confidence: _confidence,
        notes: _notes.text.trim(),
      ),
    );
  }
}

enum _TimeField { start, end }

class _TimeRow extends StatelessWidget {
  const _TimeRow({
    required this.label,
    required this.value,
    required this.onPick,
    this.placeholder,
  });

  final String label;
  final DateTime? value;
  final VoidCallback? onPick;
  final String? placeholder;

  @override
  Widget build(BuildContext context) {
    final palette = LifelogPalette.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(Radii.sm),
      onTap: onPick,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: Insets.sm),
        child: Row(
          children: [
            Icon(
              Icons.schedule_rounded,
              size: 16,
              color: palette.mutedText,
            ),
            const SizedBox(width: Insets.sm),
            Text(
              label,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: palette.mutedText),
            ),
            const Spacer(),
            Text(
              value == null
                  ? (placeholder ?? '—')
                  : '${formatShortDate(value!)} · ${formatTime(value!)}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}
