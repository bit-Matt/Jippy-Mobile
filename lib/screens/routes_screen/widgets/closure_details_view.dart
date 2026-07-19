import 'package:flutter/material.dart';

import 'package:jippy_mobile/models/road_closure.dart';
import 'package:jippy_mobile/screens/routes_screen/widgets/details_back_button.dart';

class ClosureDetailsView extends StatelessWidget {
  const ClosureDetailsView({
    super.key,
    required this.scrollController,
    required this.closure,
    required this.onBackPressed,
  });

  final ScrollController scrollController;
  final RoadClosure? closure;
  final VoidCallback onBackPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final title = (closure != null && closure!.closureName.trim().isNotEmpty)
        ? '❌ ${closure!.closureName.trim()}'
        : '❌ (untitled)';
    final detailText =
        (closure != null && closure!.closureDescription.trim().isNotEmpty)
        ? closure!.closureDescription.trim()
        : 'No description available.';

    return ListView(
      key: const ValueKey<String>('closure-details-view'),
      controller: scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      children: [
        Row(
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(left: 8),
                child: Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    height: 1.1,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            DetailsBackButton(onPressed: onBackPressed),
          ],
        ),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Text(
              detailText,
              style: theme.textTheme.bodyLarge?.copyWith(
                fontWeight: FontWeight.w500,
                height: 1.35,
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }
}
