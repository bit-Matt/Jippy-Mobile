import 'package:flutter/material.dart';

import 'package:jippy_mobile/core/theme/map_colors.dart';
import 'package:jippy_mobile/models/jeepney_route.dart';
import 'package:jippy_mobile/screens/routes_screen/widgets/route_list_item.dart';
import 'package:jippy_mobile/utils/route_color_parser.dart';

class RoutesListBody extends StatefulWidget {
  const RoutesListBody({
    super.key,
    required this.routes,
    required this.isLoading,
    required this.isFocusedMode,
    required this.isCompareMode,
    required this.selectedRouteIds,
    required this.onShowAllRoutes,
    required this.onRouteTap,
    required this.onRouteDetailsTap,
    this.loadingState = const SizedBox.shrink(),
  });

  final List<JeepneyRoute> routes;
  final bool isLoading;
  final bool isFocusedMode;
  final bool isCompareMode;
  final Set<String> selectedRouteIds;
  final VoidCallback onShowAllRoutes;
  final ValueChanged<JeepneyRoute> onRouteTap;
  final ValueChanged<JeepneyRoute> onRouteDetailsTap;
  final Widget loadingState;

  @override
  State<RoutesListBody> createState() => _RoutesListBodyState();
}

class _RoutesListBodyState extends State<RoutesListBody> {
  final TextEditingController _searchController = TextEditingController();

  String _searchQuery = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _handleSearchChanged(String value) {
    setState(() => _searchQuery = value.trim().toLowerCase());
  }

  void _showAllRoutes() {
    if (_searchController.text.isNotEmpty) {
      _searchController.clear();
      setState(() => _searchQuery = '');
    }
    widget.onShowAllRoutes();
  }

  List<JeepneyRoute> get _filteredRoutes {
    if (_searchQuery.isEmpty) return widget.routes;

    return widget.routes.where((route) {
      return route.routeNumber.toLowerCase().contains(_searchQuery) ||
          route.routeName.toLowerCase().contains(_searchQuery);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.isLoading) {
      return widget.loadingState;
    }

    if (widget.routes.isEmpty) {
      return Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: MapColors.primary.withValues(alpha: 0.18)),
          color: MapColors.background,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 18),
        child: const Text(
          'No routes available right now.',
          style: TextStyle(
            color: MapColors.text,
            fontSize: 15,
            fontWeight: FontWeight.w500,
          ),
        ),
      );
    }

    final filteredRoutes = _filteredRoutes;
    final isSearching = _searchQuery.isNotEmpty;
    final selectedRoutes = (widget.isFocusedMode && widget.isCompareMode)
        ? widget.routes
              .where((route) => widget.selectedRouteIds.contains(route.id))
              .toList()
        : const <JeepneyRoute>[];
    final shouldShowActionButton =
        widget.isCompareMode || widget.isFocusedMode || isSearching;
    final actionButtonLabel =
        widget.isCompareMode ? 'Cancel' : 'Show All Routes';
    final showCompareHint = widget.isCompareMode && !isSearching;
    final sectionHeading = isSearching
        ? 'Search Results'
        : showCompareHint
        ? 'Select Routes to Compare'
        : 'All Routes';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.isFocusedMode && widget.isCompareMode) ...[
          const Text(
            'Selected Routes',
            style: TextStyle(
              color: MapColors.text,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          if (selectedRoutes.isEmpty)
            Text(
              'No routes selected.',
              style: TextStyle(
                color: MapColors.text.withValues(alpha: 0.65),
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final route in selectedRoutes)
                  FilterChip(
                    label: Text(
                      route.routeNumber.trim().isEmpty
                          ? route.routeName
                          : route.routeNumber.trim(),
                    ),
                    selected: true,
                    onSelected: (_) => widget.onRouteTap(route),
                    showCheckmark: true,
                    selectedColor: parseRouteColor(
                      route.routeColor,
                    ).withValues(alpha: 0.18),
                    checkmarkColor: parseRouteColor(route.routeColor),
                    labelStyle: TextStyle(
                      color: parseRouteColor(route.routeColor),
                      fontWeight: FontWeight.w700,
                    ),
                    side: BorderSide(
                      color: parseRouteColor(
                        route.routeColor,
                      ).withValues(alpha: 0.55),
                    ),
                  ),
              ],
            ),
          const SizedBox(height: 18),
          const Divider(height: 1),
          const SizedBox(height: 14),
        ],
        TextField(
          controller: _searchController,
          onChanged: _handleSearchChanged,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            hintText: 'Search route number or name',
            prefixIcon: const Icon(Icons.search),
            suffixIcon: isSearching
                ? IconButton(
                    tooltip: 'Clear search',
                    icon: const Icon(Icons.close),
                    onPressed: () {
                      _searchController.clear();
                      setState(() => _searchQuery = '');
                    },
                  )
                : null,
            filled: true,
            fillColor: Colors.white,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 12,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: Text(
                sectionHeading,
                style: TextStyle(
                  color: showCompareHint
                      ? MapColors.text.withValues(alpha: 0.65)
                      : MapColors.text,
                  fontSize: showCompareHint ? 16 : 18,
                  fontWeight: showCompareHint
                      ? FontWeight.w600
                      : FontWeight.w700,
                ),
              ),
            ),
            if (shouldShowActionButton)
              TextButton(
                onPressed: _showAllRoutes,
                style: TextButton.styleFrom(
                  foregroundColor: MapColors.primary,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  textStyle: const TextStyle(fontWeight: FontWeight.w700),
                ),
                child: Text(actionButtonLabel),
              ),
          ],
        ),
        const SizedBox(height: 12),
        if (filteredRoutes.isEmpty)
          Text(
            'No routes match your search.',
            style: TextStyle(
              color: MapColors.text.withValues(alpha: 0.65),
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          )
        else
          for (int index = 0; index < filteredRoutes.length; index++) ...[
            RouteListItem(
              route: filteredRoutes[index],
              isSelected:
                  widget.isFocusedMode &&
                  widget.selectedRouteIds.contains(filteredRoutes[index].id),
              onTap: () => widget.onRouteTap(filteredRoutes[index]),
              onDetailsTap: () =>
                  widget.onRouteDetailsTap(filteredRoutes[index]),
            ),
            if (index < filteredRoutes.length - 1) const SizedBox(height: 12),
          ],
      ],
    );
  }
}

class RoutesListView extends StatelessWidget {
  const RoutesListView({
    super.key,
    required this.scrollController,
    required this.header,
    required this.body,
  });

  final ScrollController scrollController;
  final Widget header;
  final Widget body;

  @override
  Widget build(BuildContext context) {
    return ListView(
      key: const ValueKey<String>('routes-list-view'),
      controller: scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      children: [
        header,
        const SizedBox(height: 16),
        body,
        const SizedBox(height: 16),
      ],
    );
  }
}
