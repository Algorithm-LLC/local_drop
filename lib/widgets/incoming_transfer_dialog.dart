import 'package:flutter/material.dart';
import 'package:local_drop/l10n/app_localizations.dart';

import '../models/transfer_models.dart';
import '../state/app_controller.dart';
import 'security_code_comparison_panel.dart';

class IncomingTransferDialog extends StatefulWidget {
  const IncomingTransferDialog({
    super.key,
    required this.controller,
    required this.session,
  });

  final AppController controller;
  final IncomingTransferSession session;

  @override
  State<IncomingTransferDialog> createState() => _IncomingTransferDialogState();
}

class _IncomingTransferDialogState extends State<IncomingTransferDialog> {
  bool _isSubmitting = false;
  bool _securityCodesConfirmed = false;
  String? _errorMessage;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final session = widget.session;
    final remaining = session.remainingApprovalTime.inSeconds;
    final requiresSecurityConfirmation = widget.controller
        .incomingRequiresFirstTransferConfirmation(session);
    return AlertDialog(
      title: Text(l10n.incomingRequestsTitle),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              l10n.incomingRequestMessage(
                session.senderNickname,
                session.items.length,
              ),
            ),
            const SizedBox(height: 8),
            Text(l10n.incomingRequestSize(_formatBytes(session.totalBytes))),
            const SizedBox(height: 8),
            Text(l10n.incomingRequestExpiresIn(remaining.clamp(0, 999))),
            const SizedBox(height: 12),
            SecurityCodeComparisonPanel(
              title: 'Compare before accepting',
              message:
                  'The sender should see a Receiver PIN screen. Compare these two codes on both devices before you accept.',
              peerLabel: '${session.senderNickname} code',
              peerCode: widget.controller.securityCodeForIncomingSession(
                session,
              ),
              localLabel: 'This device code',
              localCode: widget.controller.localSecurityCode,
              footer:
                  'If either code is different, decline the transfer and do not share the PIN.',
            ),
            if (requiresSecurityConfirmation) ...<Widget>[
              const SizedBox(height: 8),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _securityCodesConfirmed,
                onChanged: _isSubmitting
                    ? null
                    : (value) {
                        setState(() {
                          _securityCodesConfirmed = value ?? false;
                          if (_securityCodesConfirmed) {
                            _errorMessage = null;
                          }
                        });
                      },
                title: const Text('I compared both screens and the codes match'),
                controlAffinity: ListTileControlAffinity.leading,
              ),
            ],
            if ((_errorMessage ?? '').trim().isNotEmpty) ...<Widget>[
              const SizedBox(height: 12),
              Text(
                _errorMessage!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: _isSubmitting ? null : _handleDecline,
          child: Text(l10n.declineButton),
        ),
        FilledButton(
          onPressed: _isSubmitting ? null : _handleAccept,
          child: Text(l10n.acceptButton),
        ),
      ],
    );
  }

  Future<void> _handleAccept() async {
    if (widget.controller.incomingRequiresFirstTransferConfirmation(
          widget.session,
        ) &&
        !_securityCodesConfirmed) {
      setState(() {
        _errorMessage = 'Confirm that the security codes match first.';
      });
      return;
    }
    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });
    final result = await widget.controller.acceptIncoming(
      widget.session.transferId,
      trustConfirmed: _securityCodesConfirmed,
    );
    if (!mounted) {
      return;
    }
    if (result.success) {
      Navigator.of(context).pop();
      return;
    }
    setState(() {
      _isSubmitting = false;
      _errorMessage = result.message ?? 'Could not accept the transfer.';
    });
  }

  Future<void> _handleDecline() async {
    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });
    final result = await widget.controller.declineIncoming(
      widget.session.transferId,
    );
    if (!mounted) {
      return;
    }
    if (result.success) {
      Navigator.of(context).pop();
      return;
    }
    setState(() {
      _isSubmitting = false;
      _errorMessage = result.message ?? 'Could not decline the transfer.';
    });
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) {
      return '$bytes B';
    }
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }
}
