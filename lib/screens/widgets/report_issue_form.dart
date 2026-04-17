import 'package:flutter/material.dart';

import '../../data/feedback_client.dart';
import '../../core/theme/map_colors.dart';

class ReportIssueForm extends StatefulWidget {
  const ReportIssueForm({super.key});

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
  final TextEditingController _descriptionController = TextEditingController();
  final FocusNode _emailFocusNode = FocusNode();
  final FocusNode _descriptionFocusNode = FocusNode();

  String? _selectedReportType;
  bool _submitted = false;
  bool _emailTouched = false;
  bool _reportTypeTouched = false;
  bool _descriptionTouched = false;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _emailFocusNode.addListener(_handleEmailFocusChange);
    _descriptionFocusNode.addListener(_handleDescriptionFocusChange);
    _emailController.addListener(_handleEmailTextChange);
    _descriptionController.addListener(_handleDescriptionTextChange);
  }

  @override
  void dispose() {
    _emailFocusNode
      ..removeListener(_handleEmailFocusChange)
      ..dispose();
    _descriptionFocusNode
      ..removeListener(_handleDescriptionFocusChange)
      ..dispose();
    _emailController
      ..removeListener(_handleEmailTextChange)
      ..dispose();
    _descriptionController
      ..removeListener(_handleDescriptionTextChange)
      ..dispose();
    super.dispose();
  }

  void _handleEmailFocusChange() {
    if (!_emailFocusNode.hasFocus && !_emailTouched) {
      setState(() => _emailTouched = true);
    }
  }

  void _handleDescriptionFocusChange() {
    if (!_descriptionFocusNode.hasFocus && !_descriptionTouched) {
      setState(() => _descriptionTouched = true);
    }
  }

  void _handleEmailTextChange() {
    if (_submitted || _emailTouched) {
      setState(() {});
    }
  }

  void _handleDescriptionTextChange() {
    if (_submitted || _descriptionTouched) {
      setState(() {});
    }
  }

  bool _isValidEmail(String value) {
    final emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
    return emailPattern.hasMatch(value);
  }

  bool get _showEmailError => _submitted || _emailTouched;

  bool get _showReportTypeError => _submitted || _reportTypeTouched;

  bool get _showDescriptionError => _submitted || _descriptionTouched;

  String? _emailErrorText() {
    if (!_showEmailError) return null;
    final value = _emailController.text.trim();
    if (value.isEmpty) {
      return 'Email address is required.';
    }
    if (!_isValidEmail(value)) {
      return 'Enter a valid email address.';
    }
    return null;
  }

  String? _reportTypeErrorText() {
    if (!_showReportTypeError) return null;
    if (_selectedReportType == null || _selectedReportType!.trim().isEmpty) {
      return 'Please select a report type.';
    }
    return null;
  }

  String? _descriptionErrorText() {
    if (!_showDescriptionError) return null;
    if (_descriptionController.text.trim().isEmpty) {
      return 'Please describe the problem.';
    }
    return null;
  }

  void _showSnackBar(String message) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  Future<void> _submit() async {
    if (_isSubmitting) return;

    setState(() {
      _submitted = true;
    });

    FocusScope.of(context).unfocus();

    final formValid = _formKey.currentState?.validate() ?? false;
    if (!formValid) return;

    final email = _emailController.text.trim();
    final reportType = _selectedReportType!;
    final description = _descriptionController.text.trim();

    setState(() {
      _isSubmitting = true;
    });

    try {
      await submitFeedback(
        email: email,
        type: reportType,
        details: description,
      );

      if (!mounted) return;
      _showSnackBar('Report submitted. Thank you for your feedback.');
      Navigator.of(context).pop();
    } on FeedbackSubmissionException catch (error) {
      if (!mounted) return;
      _showSnackBar(error.message);
    } catch (_) {
      if (!mounted) return;
      _showSnackBar('Unable to submit feedback right now. Please try again.');
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextFormField(
            controller: _emailController,
            focusNode: _emailFocusNode,
            enabled: !_isSubmitting,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.next,
            autovalidateMode: _showEmailError
                ? AutovalidateMode.always
                : AutovalidateMode.disabled,
            decoration: inputDecoration.copyWith(
              labelText: 'Email address',
              hintText: 'name@example.com',
            ),
            validator: (_) => _emailErrorText(),
            onFieldSubmitted: (_) {
              FocusScope.of(context).requestFocus(_descriptionFocusNode);
            },
          ),
          const SizedBox(height: 12),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            initialValue: _selectedReportType,
            onChanged: _isSubmitting
                ? null
                : (value) {
                    setState(() {
                      _selectedReportType = value;
                      _reportTypeTouched = true;
                    });
                  },
            autovalidateMode: _showReportTypeError
                ? AutovalidateMode.always
                : AutovalidateMode.disabled,
            decoration: inputDecoration.copyWith(labelText: 'Report Type'),
            items: _reportTypes
                .map(
                  (type) =>
                      DropdownMenuItem<String>(value: type, child: Text(type)),
                )
                .toList(),
            validator: (_) => _reportTypeErrorText(),
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _descriptionController,
            focusNode: _descriptionFocusNode,
            enabled: !_isSubmitting,
            minLines: 5,
            maxLines: 8,
            textInputAction: TextInputAction.newline,
            autovalidateMode: _showDescriptionError
                ? AutovalidateMode.always
                : AutovalidateMode.disabled,
            decoration: inputDecoration.copyWith(
              labelText: 'Describe the problem',
              hintText:
                  'Share as much detail as possible to help us investigate.',
              alignLabelWithHint: true,
            ),
            validator: (_) => _descriptionErrorText(),
          ),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _isSubmitting ? null : _submit,
              icon: _isSubmitting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.send_outlined),
              label: Text(_isSubmitting ? 'Submitting...' : 'Submit Report'),
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
