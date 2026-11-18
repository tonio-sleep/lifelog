import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/app_theme.dart';
import '../../app/widgets/common.dart';
import '../../app/widgets/components.dart';
import '../../core/util/dates.dart';
import '../../domain/models/timeline.dart';
import 'event_dialogs.dart';
import 'timeline_widgets.dart';

class TimelineScreen extends ConsumerStatefulWidget {
  const TimelineScreen({super.key, this.initialDate});
  final DateTime? initialDate;

  @override
  ConsumerState<TimelineScreen> createState() => _TimelineScreenState();
}

class _TimelineScreenState extends ConsumerState<TimelineScreen> {
  late DateTime _day;
  TimelineSource? _filter;
  bool _showHidden = false;

  @override
  void initState() {
    super.initState();
    _day = dayStart(widget.initialDate ?? DateTime.now());
  }

  void _shift(int delta) =>
      setState(() => _day = DateTime(_day.year, _day.month, _day.day + delta));

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    return ScreenFrame(
      title: 'Timeline',
      actions: [
        HeaderButton(
          icon: _showHidden
              ? Icons.visibility_rounded
              : Icons.visibility_off_outlined,
          tooltip: _showHidden ? 'Hide hidden events' : 'Show hidden events',
          onPressed: () => setState(() => _showHidden = !_showHidden),
        ),
        HeaderButton(
          icon: Icons.add_rounded,
          tooltip: 'Add event',
          filled: true,
          onPressed: () =>
              showTimelineEventEditor(context, ref, initialDate: _day),
        ),
      ],
      children: [
        DayNavigator(
          day: _day,
          onChanged: (value) => setState(() => _day = value),
        ),
        const SizedBox(height: Insets.md),
        FilterRow<TimelineSource?>(
          values: <TimelineSource?>[null, ...TimelineSource.values],
          selected: _filter,
          labelFor: (source) => source?.label ?? 'All',
          iconFor: (source) =>
              source == null ? null : sourceStyle(source, scheme).icon,
          colorFor: (source) =>
              source == null ? scheme.primary : sourceStyle(source, scheme).color,
          onChanged: (value) => setState(() => _filter = value),
        ),
        const SizedBox(height: Insets.lg),
        DaySwitcher(
          day: _day,
          onSwipe: _shift,
          builder: (context, day) => TimelineDayList(
            day: day,
            sources: _filter == null ? null : {_filter!},
            includeHidden: _showHidden,
            emptyMessage: _filter == null
                ? 'No records for this day.'
                : 'No ${_filter!.label.toLowerCase()} records for this day.',
          ),
        ),
      ],
    );
  }
}
