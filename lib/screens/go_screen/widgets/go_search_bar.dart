import 'package:flutter/material.dart';

import 'package:jippy_mobile/core/theme/map_colors.dart';
import 'package:jippy_mobile/screens/go_screen/go_state.dart';
import 'package:jippy_mobile/screens/go_screen/widgets/go_map_pin_instruction_banner.dart';
import 'package:jippy_mobile/services/geocoding_service.dart';

/// Go screen search: collapsed destination prompt or expanded origin + destination rows.
class GoSearchBar extends StatelessWidget {
  const GoSearchBar({
    super.key,
    required this.mode,
    required this.onCollapsedTap,
    required this.onCollapseExpanded,
    required this.originLabel,
    required this.onOriginRowTap,
    required this.showRevertOriginToGps,
    required this.onRevertOriginToGps,
    required this.onDestinationMapPinTap,
    required this.destinationController,
    required this.destinationFocusNode,
    required this.onDestinationTextChanged,
    required this.suggestions,
    required this.onSuggestionTap,
    required this.searchError,
    required this.showOutOfAreaDisclaimer,
    required this.isSearchingNominatim,
    required this.routePreviewLoading,
    required this.mapPinAwaitingTap,
    required this.onCancelMapPinMode,
  });

  final GoSearchBarMode mode;
  final VoidCallback onCollapsedTap;
  final VoidCallback onCollapseExpanded;
  final String originLabel;
  final VoidCallback onOriginRowTap;
  final bool showRevertOriginToGps;
  final VoidCallback onRevertOriginToGps;
  final VoidCallback onDestinationMapPinTap;
  final TextEditingController destinationController;
  final FocusNode destinationFocusNode;
  final ValueChanged<String> onDestinationTextChanged;
  final List<NominatimSearchHit> suggestions;
  final ValueChanged<NominatimSearchHit> onSuggestionTap;
  final String? searchError;
  final bool showOutOfAreaDisclaimer;
  final bool isSearchingNominatim;
  final bool routePreviewLoading;
  final GoPinTarget? mapPinAwaitingTap;
  final VoidCallback onCancelMapPinMode;

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.paddingOf(context).top + 8;
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: Padding(
        padding: EdgeInsets.only(top: topPadding, left: 16, right: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            mode == GoSearchBarMode.collapsed
                ? _CollapsedBar(onTap: onCollapsedTap)
                : _ExpandedPanel(
                    onCollapse: onCollapseExpanded,
                    originLabel: originLabel,
                    onOriginRowTap: onOriginRowTap,
                    showRevertOriginToGps: showRevertOriginToGps,
                    onRevertOriginToGps: onRevertOriginToGps,
                    onDestinationMapPinTap: onDestinationMapPinTap,
                    destinationController: destinationController,
                    destinationFocusNode: destinationFocusNode,
                    onDestinationTextChanged: onDestinationTextChanged,
                    suggestions: suggestions,
                    onSuggestionTap: onSuggestionTap,
                    searchError: searchError,
                    showOutOfAreaDisclaimer: showOutOfAreaDisclaimer,
                    isSearchingNominatim: isSearchingNominatim,
                    routePreviewLoading: routePreviewLoading,
                  ),
            if (mapPinAwaitingTap != null) ...[
              const SizedBox(height: 8),
              GoMapPinInstructionBanner(
                forOrigin: mapPinAwaitingTap == GoPinTarget.origin,
                onCancel: onCancelMapPinMode,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _CollapsedBar extends StatelessWidget {
  const _CollapsedBar({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 2,
      shadowColor: Colors.black26,
      borderRadius: BorderRadius.circular(24),
      color: MapColors.background,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Row(
          children: [
            const Padding(
              padding: EdgeInsets.all(12),
              child: Icon(Icons.search, color: MapColors.primary, size: 24),
            ),
            Expanded(
              child: GestureDetector(
                onTap: onTap,
                behavior: HitTestBehavior.opaque,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  child: Text(
                    'Where do you want to go?',
                    style: TextStyle(
                      color: MapColors.text.withValues(alpha: 0.6),
                      fontSize: 16,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Icon(
                Icons.mic_none,
                color: MapColors.text.withValues(alpha: 0.7),
                size: 22,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ExpandedPanel extends StatelessWidget {
  const _ExpandedPanel({
    required this.onCollapse,
    required this.originLabel,
    required this.onOriginRowTap,
    required this.showRevertOriginToGps,
    required this.onRevertOriginToGps,
    required this.onDestinationMapPinTap,
    required this.destinationController,
    required this.destinationFocusNode,
    required this.onDestinationTextChanged,
    required this.suggestions,
    required this.onSuggestionTap,
    required this.searchError,
    required this.showOutOfAreaDisclaimer,
    required this.isSearchingNominatim,
    required this.routePreviewLoading,
  });

  final VoidCallback onCollapse;
  final String originLabel;
  final VoidCallback onOriginRowTap;
  final bool showRevertOriginToGps;
  final VoidCallback onRevertOriginToGps;
  final VoidCallback onDestinationMapPinTap;
  final TextEditingController destinationController;
  final FocusNode destinationFocusNode;
  final ValueChanged<String> onDestinationTextChanged;
  final List<NominatimSearchHit> suggestions;
  final ValueChanged<NominatimSearchHit> onSuggestionTap;
  final String? searchError;
  final bool showOutOfAreaDisclaimer;
  final bool isSearchingNominatim;
  final bool routePreviewLoading;

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 3,
      shadowColor: Colors.black26,
      borderRadius: BorderRadius.circular(20),
      color: MapColors.background,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                IconButton(
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                  icon: const Icon(Icons.expand_less),
                  onPressed: onCollapse,
                  tooltip: 'Collapse',
                ),
                Expanded(
                  child: Text(
                    'Go',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 16,
                      color: MapColors.text.withValues(alpha: 0.85),
                    ),
                  ),
                ),
              ],
            ),
            if (routePreviewLoading) ...[
              const LinearProgressIndicator(minHeight: 3),
              const SizedBox(height: 8),
            ],
            InkWell(
              onTap: onOriginRowTap,
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
                child: Row(
                  children: [
                    Icon(Icons.trip_origin, color: MapColors.primary, size: 22),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        originLabel.isEmpty ? 'Tap to set on map' : originLabel,
                        style: TextStyle(
                          fontSize: 15,
                          color: originLabel.isEmpty
                              ? MapColors.text.withValues(alpha: 0.45)
                              : MapColors.text,
                          fontWeight: FontWeight.w500,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Icon(
                      Icons.edit_location_alt_outlined,
                      size: 20,
                      color: MapColors.text.withValues(alpha: 0.5),
                    ),
                  ],
                ),
              ),
            ),
            if (showRevertOriginToGps) ...[
              const SizedBox(height: 4),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: onRevertOriginToGps,
                  icon: Icon(
                    Icons.my_location,
                    size: 18,
                    color: MapColors.primary.withValues(alpha: 0.9),
                  ),
                  label: const Text('Use my current location'),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    foregroundColor: MapColors.primary,
                    textStyle: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
            const Divider(height: 20),
            Row(
              children: [
                Icon(Icons.search, color: MapColors.primary, size: 22),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: destinationController,
                    focusNode: destinationFocusNode,
                    onChanged: onDestinationTextChanged,
                    textInputAction: TextInputAction.search,
                    decoration: const InputDecoration(
                      isDense: true,
                      border: InputBorder.none,
                      hintText: 'Search destination...',
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Place destination on map',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
                  icon: Icon(
                    Icons.edit_location_alt_outlined,
                    size: 22,
                    color: MapColors.text.withValues(alpha: 0.55),
                  ),
                  onPressed: onDestinationMapPinTap,
                ),
                if (isSearchingNominatim)
                  const Padding(
                    padding: EdgeInsets.only(left: 2),
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
              ],
            ),
            if (searchError != null) ...[
              const SizedBox(height: 6),
              Text(
                searchError!,
                style: const TextStyle(
                  color: Color(0xFFB00020),
                  fontSize: 13,
                ),
              ),
            ],
            if (showOutOfAreaDisclaimer) ...[
              const SizedBox(height: 6),
              Text(
                'This destination is outside the covered area — results may be limited.',
                style: TextStyle(
                  color: MapColors.text.withValues(alpha: 0.72),
                  fontSize: 12,
                ),
              ),
            ],
            if (suggestions.isNotEmpty) ...[
              const SizedBox(height: 6),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 220),
                child: ListView.separated(
                  shrinkWrap: true,
                  physics: const ClampingScrollPhysics(),
                  itemCount: suggestions.length,
                  separatorBuilder: (context, index) =>
                      const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final hit = suggestions[index];
                    return ListTile(
                      dense: true,
                      title: Text(
                        hit.displayName,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 14),
                      ),
                      onTap: () => onSuggestionTap(hit),
                    );
                  },
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
