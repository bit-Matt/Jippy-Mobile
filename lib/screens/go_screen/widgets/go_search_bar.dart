import 'package:flutter/material.dart';

import 'package:jippy_mobile/core/theme/map_colors.dart';
import 'package:jippy_mobile/screens/go_screen/go_state.dart';
import 'package:jippy_mobile/services/geocoding_service.dart';

/// Go screen search: collapsed explore prompt or expanded routing header.
class GoSearchBar extends StatelessWidget {
  const GoSearchBar({
    super.key,
    required this.mode,
    required this.onCollapsedTap,
    required this.startController,
    required this.startFocusNode,
    required this.endController,
    required this.endFocusNode,
    required this.onStartTextChanged,
    required this.onEndTextChanged,
    required this.onEndSubmitted,
    required this.onStartMapPinTap,
    required this.onEndMapPinTap,
    required this.showUseCurrentLocation,
    required this.onUseCurrentLocationTap,
    required this.suggestions,
    required this.onSuggestionTap,
    required this.searchError,
    required this.showOutOfAreaDisclaimer,
    required this.isSearchingNominatim,
    required this.activeRoutingField,
    required this.onActiveRoutingFieldChanged,
  });

  final GoSearchBarMode mode;
  final VoidCallback onCollapsedTap;
  final TextEditingController startController;
  final FocusNode startFocusNode;
  final TextEditingController endController;
  final FocusNode endFocusNode;
  final ValueChanged<String> onStartTextChanged;
  final ValueChanged<String> onEndTextChanged;
  final ValueChanged<String> onEndSubmitted;
  final VoidCallback onStartMapPinTap;
  final VoidCallback onEndMapPinTap;
  final bool showUseCurrentLocation;
  final VoidCallback onUseCurrentLocationTap;
  final List<NominatimSearchHit> suggestions;
  final ValueChanged<NominatimSearchHit> onSuggestionTap;
  final String? searchError;
  final bool showOutOfAreaDisclaimer;
  final bool isSearchingNominatim;
  final GoRoutingField activeRoutingField;
  final ValueChanged<GoRoutingField> onActiveRoutingFieldChanged;

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.paddingOf(context).top + 8;
    final showOriginPinUseLocation = showUseCurrentLocation &&
      activeRoutingField == GoRoutingField.start;
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
                : _RoutingHeaderPanel(
                    startController: startController,
                    startFocusNode: startFocusNode,
                    endController: endController,
                    endFocusNode: endFocusNode,
                    onStartTextChanged: onStartTextChanged,
                    onEndTextChanged: onEndTextChanged,
                    onEndSubmitted: onEndSubmitted,
                    onStartMapPinTap: onStartMapPinTap,
                    onEndMapPinTap: onEndMapPinTap,
                    showUseCurrentLocationAction: showOriginPinUseLocation,
                    onUseCurrentLocationTap: onUseCurrentLocationTap,
                    suggestions: suggestions,
                    onSuggestionTap: onSuggestionTap,
                    searchError: searchError,
                    showOutOfAreaDisclaimer: showOutOfAreaDisclaimer,
                    isSearchingNominatim: isSearchingNominatim,
                    activeRoutingField: activeRoutingField,
                    onActiveRoutingFieldChanged: onActiveRoutingFieldChanged,
                  ),
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

class _RoutingHeaderPanel extends StatelessWidget {
  const _RoutingHeaderPanel({
    required this.startController,
    required this.startFocusNode,
    required this.endController,
    required this.endFocusNode,
    required this.onStartTextChanged,
    required this.onEndTextChanged,
    required this.onEndSubmitted,
    required this.onStartMapPinTap,
    required this.onEndMapPinTap,
    required this.showUseCurrentLocationAction,
    required this.onUseCurrentLocationTap,
    required this.suggestions,
    required this.onSuggestionTap,
    required this.searchError,
    required this.showOutOfAreaDisclaimer,
    required this.isSearchingNominatim,
    required this.activeRoutingField,
    required this.onActiveRoutingFieldChanged,
  });

  final TextEditingController startController;
  final FocusNode startFocusNode;
  final TextEditingController endController;
  final FocusNode endFocusNode;
  final ValueChanged<String> onStartTextChanged;
  final ValueChanged<String> onEndTextChanged;
  final ValueChanged<String> onEndSubmitted;
  final VoidCallback onStartMapPinTap;
  final VoidCallback onEndMapPinTap;
  final bool showUseCurrentLocationAction;
  final VoidCallback onUseCurrentLocationTap;
  final List<NominatimSearchHit> suggestions;
  final ValueChanged<NominatimSearchHit> onSuggestionTap;
  final String? searchError;
  final bool showOutOfAreaDisclaimer;
  final bool isSearchingNominatim;
  final GoRoutingField activeRoutingField;
  final ValueChanged<GoRoutingField> onActiveRoutingFieldChanged;

  @override
  Widget build(BuildContext context) {
    final mutedText = MapColors.text.withValues(alpha: 0.6);

    return Material(
      elevation: 3,
      shadowColor: Colors.black26,
      borderRadius: BorderRadius.circular(20),
      color: MapColors.background,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _RoutingInputRow(
              icon: Icons.place_rounded,
              iconColor: MapColors.primary,
              controller: startController,
              focusNode: startFocusNode,
              hintText: 'Choose starting point',
              textInputAction: TextInputAction.next,
              isActive: activeRoutingField == GoRoutingField.start,
              onTap: () => onActiveRoutingFieldChanged(GoRoutingField.start),
              onChanged: onStartTextChanged,
              onTrailingTap: onStartMapPinTap,
              trailingIcon: Icons.edit_location_alt_outlined,
              trailingTooltip: 'Pin start on map',
            ),
            const SizedBox(height: 6),
            _RoutingInputRow(
              icon: Icons.place_rounded,
              iconColor: MapColors.secondary,
              controller: endController,
              focusNode: endFocusNode,
              hintText: 'Search destination',
              textInputAction: TextInputAction.search,
              isActive: activeRoutingField == GoRoutingField.end,
              onTap: () => onActiveRoutingFieldChanged(GoRoutingField.end),
              onChanged: onEndTextChanged,
              onSubmitted: onEndSubmitted,
              onTrailingTap: onEndMapPinTap,
              trailingIcon: Icons.edit_location_alt_outlined,
              trailingTooltip: 'Pin destination on map',
              trailingProgress: isSearchingNominatim,
            ),
            if (showUseCurrentLocationAction) ...[
              const SizedBox(height: 6),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: onUseCurrentLocationTap,
                  icon: const Icon(Icons.my_location, size: 18),
                  label: const Text('Use my current location'),
                  style: TextButton.styleFrom(
                    foregroundColor: MapColors.primary,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 4,
                    ),
                    textStyle: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                ),
              ),
            ],
            if (searchError != null) ...[
              const SizedBox(height: 6),
              Text(
                searchError!,
                style: const TextStyle(color: Color(0xFFB00020), fontSize: 13),
              ),
            ],
            if (showOutOfAreaDisclaimer) ...[
              const SizedBox(height: 6),
              Text(
                'This destination is outside the covered area - results may be limited.',
                style: TextStyle(
                  color: MapColors.text.withValues(alpha: 0.72),
                  fontSize: 12,
                ),
              ),
            ],
            if (suggestions.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                'Results for ${activeRoutingField == GoRoutingField.start ? 'Start' : 'End'}',
                style: TextStyle(
                  color: mutedText,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
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

class _RoutingInputRow extends StatelessWidget {
  const _RoutingInputRow({
    required this.icon,
    required this.iconColor,
    required this.controller,
    required this.focusNode,
    required this.hintText,
    required this.textInputAction,
    required this.isActive,
    required this.onTap,
    required this.onChanged,
    this.onSubmitted,
    required this.onTrailingTap,
    required this.trailingIcon,
    required this.trailingTooltip,
    this.trailingProgress = false,
  });

  final IconData icon;
  final Color iconColor;
  final TextEditingController controller;
  final FocusNode focusNode;
  final String hintText;
  final TextInputAction textInputAction;
  final bool isActive;
  final VoidCallback onTap;
  final ValueChanged<String> onChanged;
  final ValueChanged<String>? onSubmitted;
  final VoidCallback onTrailingTap;
  final IconData trailingIcon;
  final String trailingTooltip;
  final bool trailingProgress;

  @override
  Widget build(BuildContext context) {
    void selectAllText() {
      final text = controller.text;
      if (text.isEmpty) return;
      controller.selection = TextSelection(
        baseOffset: 0,
        extentOffset: text.length,
      );
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isActive
                  ? MapColors.primary.withValues(alpha: 0.65)
                  : MapColors.text.withValues(alpha: 0.14),
            ),
            color: MapColors.background,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            children: [
              Icon(icon, color: iconColor, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: controller,
                  focusNode: focusNode,
                  onTap: selectAllText,
                  onChanged: onChanged,
                  onSubmitted: onSubmitted,
                  textInputAction: textInputAction,
                  decoration: InputDecoration(
                    isDense: true,
                    border: InputBorder.none,
                    hintText: hintText,
                  ),
                ),
              ),
              IconButton(
                tooltip: trailingTooltip,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
                icon: Icon(
                  trailingIcon,
                  size: 20,
                  color: MapColors.text.withValues(alpha: 0.58),
                ),
                onPressed: onTrailingTap,
              ),
              if (trailingProgress)
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
