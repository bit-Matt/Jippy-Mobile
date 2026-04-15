import 'package:flutter/material.dart';

import '../core/theme/map_colors.dart';
import 'widgets/report_issue_form.dart';

/// Stand-alone screen for submitting issue reports.
class ReportScreen extends StatelessWidget {
  const ReportScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: MapColors.background,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: MapColors.text),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text(
          'Report an Issue',
          style: TextStyle(
            color: MapColors.text,
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Help us improve Jippy',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    color: MapColors.text,
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              'Report bugs, inaccurate data, or road closures. Your feedback helps us serve you better.',
              style: TextStyle(
                color: MapColors.text.withValues(alpha: 0.75),
                fontSize: 14,
                fontWeight: FontWeight.w500,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 24),
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: MapColors.primary.withValues(alpha: 0.18),
                ),
                color: MapColors.background,
              ),
              padding: const EdgeInsets.all(14),
              child: const ReportIssueForm(),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}
