import 'package:flutter/material.dart';

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
    final showOriginPinUseLocation =
        showUseCurrentLocation && activeRoutingField == GoRoutingField.start;
    return mode == GoSearchBarMode.collapsed
        ? _CollapsedBar(onTap: onCollapsedTap)
        : _RoutingHeaderPanel(
            startController: startController,
            startFocusNode: startFocusNode,
            endController: endController,
            endFocusNode: endFocusNode,
            onStartTextChanged: onStartTextChanged,
            onEndTextChanged: onEndTextChanged,
            onEndSubmitted: onEndSubmitted,
            showUseCurrentLocationAction: showOriginPinUseLocation,
            onUseCurrentLocationTap: onUseCurrentLocationTap,
            suggestions: suggestions,
            onSuggestionTap: onSuggestionTap,
            searchError: searchError,
            showOutOfAreaDisclaimer: showOutOfAreaDisclaimer,
            isSearchingNominatim: isSearchingNominatim,
            activeRoutingField: activeRoutingField,
            onActiveRoutingFieldChanged: onActiveRoutingFieldChanged,
          );
  }
}

class _CollapsedBar extends StatelessWidget {
  const _CollapsedBar({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Material(
      elevation: 2,
      shadowColor: colorScheme.shadow.withValues(alpha: 0.3),
      borderRadius: BorderRadius.circular(24),
      color: colorScheme.surfaceContainerHighest,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Row(
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: Icon(Icons.search, color: colorScheme.primary, size: 24),
            ),
            Expanded(
              child: GestureDetector(
                onTap: onTap,
                behavior: HitTestBehavior.opaque,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(0, 14, 12, 14),
                  child: Text(
                    'Where do you want to go?',
                    style: textTheme.bodyLarge?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
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
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Material(
      elevation: 3,
      shadowColor: colorScheme.shadow.withValues(alpha: 0.3),
      borderRadius: BorderRadius.circular(20),
      color: colorScheme.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _RoutingInputRow(
              icon: Icons.place_rounded,
              iconColor: colorScheme.primary,
              controller: startController,
              focusNode: startFocusNode,
              hintText: 'Choose starting point',
              textInputAction: TextInputAction.next,
              isActive: activeRoutingField == GoRoutingField.start,
              onTap: () => onActiveRoutingFieldChanged(GoRoutingField.start),
              onChanged: onStartTextChanged,
            ),
            const SizedBox(height: 6),
            _RoutingInputRow(
              icon: Icons.place_rounded,
              iconColor: colorScheme.secondary,
              controller: endController,
              focusNode: endFocusNode,
              hintText: 'Search destination',
              textInputAction: TextInputAction.search,
              isActive: activeRoutingField == GoRoutingField.end,
              onTap: () => onActiveRoutingFieldChanged(GoRoutingField.end),
              onChanged: onEndTextChanged,
              onSubmitted: onEndSubmitted,
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
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 4,
                    ),
                    textStyle: textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
            if (searchError != null) ...[
              const SizedBox(height: 6),
              Text(
                searchError!,
                style: textTheme.bodySmall?.copyWith(
                  color: colorScheme.error,
                ),
              ),
            ],
            if (showOutOfAreaDisclaimer) ...[
              const SizedBox(height: 6),
              Text(
                'This destination is outside the covered area - results may be limited.',
                style: textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            if (suggestions.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                'Results for ${activeRoutingField == GoRoutingField.start ? 'Start' : 'End'}',
                style: textTheme.labelMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
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
                        style: textTheme.bodyMedium,
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
  final bool trailingProgress;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    void handleTextFieldTap() {
      onTap();
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
                  ? colorScheme.primary.withValues(alpha: 0.65)
                  : colorScheme.outlineVariant,
            ),
            color: colorScheme.surfaceContainerHighest,
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
                  onTap: handleTextFieldTap,
                  onChanged: onChanged,
                  onSubmitted: onSubmitted,
                  textInputAction: textInputAction,
                  decoration: InputDecoration(
                    isDense: true,
                    filled: false,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    hintText: hintText,
                  ),
                ),
              ),
              if (trailingProgress)
                const Padding(
                  padding: EdgeInsets.only(left: 8, right: 8),
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class GoManualPinLocationButton extends StatelessWidget {
  const GoManualPinLocationButton({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return FilledButton(
      onPressed: onTap,
      style: FilledButton.styleFrom(
        foregroundColor: colorScheme.onPrimary,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        shape: const StadiumBorder(),
      ),
      child: Text(
        'Manually pin location',
        style: textTheme.labelLarge?.copyWith(
          color: colorScheme.onPrimary,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}
