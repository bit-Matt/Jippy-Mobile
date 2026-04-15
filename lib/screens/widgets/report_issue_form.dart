import 'package:flutter/material.dart';

import '../../core/theme/map_colors.dart';

class ReportIssueData {
  const ReportIssueData({
    required this.email,
    required this.phoneNumber,
    required this.reportType,
    required this.description,
  });

  final String email;
  final String phoneNumber;
  final String reportType;
  final String description;
}

class ReportIssueForm extends StatefulWidget {
  const ReportIssueForm({super.key, this.onSubmit});

  final ValueChanged<ReportIssueData>? onSubmit;

  @override
  State<ReportIssueForm> createState() => _ReportIssueFormState();
}

class _ReportIssueFormState extends State<ReportIssueForm> {
  static const List<String> _reportTypes = <String>[
    'Application Bug',
    'Inaccurate Route Data',
    'Inaccurate Tricycle Data',
    'Road Closure',
  ];

  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();

  String? _selectedReportType;
  String? _contactErrorText;

  @override
  void initState() {
    super.initState();
    _emailController.addListener(_clearContactErrorWhenValid);
    _phoneController.addListener(_clearContactErrorWhenValid);
  }

  @override
  void dispose() {
    _emailController
      ..removeListener(_clearContactErrorWhenValid)
      ..dispose();
    _phoneController
      ..removeListener(_clearContactErrorWhenValid)
      ..dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  void _clearContactErrorWhenValid() {
    if (_contactErrorText != null && _hasContactValue()) {
      setState(() => _contactErrorText = null);
    }
  }

  bool _hasContactValue() {
    return _emailController.text.trim().isNotEmpty ||
        _phoneController.text.trim().isNotEmpty;
  }

  bool _isValidEmail(String value) {
    final emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
    return emailPattern.hasMatch(value);
  }

  bool _isValidPhoneNumber(String value) {
    final digitsOnly = value.replaceAll(RegExp(r'\D'), '');
    return digitsOnly.length >= 7;
  }

  void _submit() {
    final formValid = _formKey.currentState?.validate() ?? false;
    final hasContact = _hasContactValue();
    setState(() {
      _contactErrorText = hasContact
          ? null
          : 'Please provide at least an email address or phone number.';
    });

    if (!formValid || !hasContact) return;

    final payload = ReportIssueData(
      email: _emailController.text.trim(),
      phoneNumber: _phoneController.text.trim(),
      reportType: _selectedReportType!,
      description: _descriptionController.text.trim(),
    );

    widget.onSubmit?.call(payload);

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Report submitted. Thank you for your feedback.'),
        behavior: SnackBarBehavior.floating,
      ),
    );

    _formKey.currentState?.reset();
    setState(() {
      _selectedReportType = null;
      _contactErrorText = null;
    });
    _emailController.clear();
    _phoneController.clear();
    _descriptionController.clear();
  }

  @override
  Widget build(BuildContext context) {
    final inputDecoration = InputDecoration(
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: MapColors.text.withValues(alpha: 0.2)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: MapColors.text.withValues(alpha: 0.2)),
      ),
      focusedBorder: const OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(12)),
        borderSide: BorderSide(color: MapColors.primary, width: 1.4),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    );

    return Form(
      key: _formKey,
      autovalidateMode: AutovalidateMode.onUserInteraction,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextFormField(
            controller: _emailController,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.next,
            decoration: inputDecoration.copyWith(
              labelText: 'Email address',
              hintText: 'name@example.com',
            ),
            validator: (value) {
              final trimmed = (value ?? '').trim();
              if (trimmed.isEmpty) return null;
              if (!_isValidEmail(trimmed)) {
                return 'Enter a valid email address.';
              }
              return null;
            },
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _phoneController,
            keyboardType: TextInputType.phone,
            textInputAction: TextInputAction.next,
            decoration: inputDecoration.copyWith(
              labelText: 'Phone number',
              hintText: '+63 912 345 6789',
            ),
            validator: (value) {
              final trimmed = (value ?? '').trim();
              if (trimmed.isEmpty) return null;
              if (!_isValidPhoneNumber(trimmed)) {
                return 'Enter a valid phone number.';
              }
              return null;
            },
          ),
          if (_contactErrorText != null) ...[
            const SizedBox(height: 8),
            Text(
              _contactErrorText!,
              style: TextStyle(
                color: Theme.of(context).colorScheme.error,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            initialValue: _selectedReportType,
            decoration: inputDecoration.copyWith(labelText: 'Report Type'),
            items: _reportTypes
                .map(
                  (type) => DropdownMenuItem<String>(
                    value: type,
                    child: Text(type),
                  ),
                )
                .toList(),
            onChanged: (value) {
              setState(() => _selectedReportType = value);
            },
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return 'Please select a report type.';
              }
              return null;
            },
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _descriptionController,
            minLines: 5,
            maxLines: 8,
            textInputAction: TextInputAction.newline,
            decoration: inputDecoration.copyWith(
              labelText: 'Describe the problem',
              hintText: 'Share as much detail as possible to help us investigate.',
              alignLabelWithHint: true,
            ),
            validator: (value) {
              if ((value ?? '').trim().isEmpty) {
                return 'Please describe the problem.';
              }
              return null;
            },
          ),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _submit,
              icon: const Icon(Icons.send_outlined),
              label: const Text('Submit Report'),
              style: FilledButton.styleFrom(
                backgroundColor: MapColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                textStyle: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}