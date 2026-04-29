import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/transfer_pin_service.dart';
import 'security_code_comparison_panel.dart';

class ReceiverPinResult {
  const ReceiverPinResult({required this.pin, required this.trustConfirmed});

  final String pin;
  final bool trustConfirmed;
}

Future<ReceiverPinResult?> showReceiverPinDialog(
  BuildContext context, {
  required String peerNickname,
  bool requiresSecurityConfirmation = false,
  String? peerSecurityCode,
  String? localSecurityCode,
}) {
  return showDialog<ReceiverPinResult>(
    context: context,
    builder: (context) => _ReceiverPinDialog(
      peerNickname: peerNickname,
      requiresSecurityConfirmation: requiresSecurityConfirmation,
      peerSecurityCode: peerSecurityCode,
      localSecurityCode: localSecurityCode,
    ),
  );
}

class _ReceiverPinDialog extends StatefulWidget {
  const _ReceiverPinDialog({
    required this.peerNickname,
    required this.requiresSecurityConfirmation,
    this.peerSecurityCode,
    this.localSecurityCode,
  });

  final String peerNickname;
  final bool requiresSecurityConfirmation;
  final String? peerSecurityCode;
  final String? localSecurityCode;

  @override
  State<_ReceiverPinDialog> createState() => _ReceiverPinDialogState();
}

class _ReceiverPinDialogState extends State<_ReceiverPinDialog> {
  final TextEditingController _controller = TextEditingController();
  bool _securityCodesConfirmed = false;
  String? _errorText;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Receiver PIN'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            if (widget.requiresSecurityConfirmation) ...<Widget>[
              SecurityCodeComparisonPanel(
                title: 'Security code check',
                message:
                    'Before the first transfer, compare these two codes with the incoming request on ${widget.peerNickname}. Both screens must show the same pair of codes.',
                peerLabel: '${widget.peerNickname} code',
                peerCode: widget.peerSecurityCode ?? 'Not available',
                localLabel: 'This device code',
                localCode: widget.localSecurityCode ?? 'Not available',
                footer:
                    'Ask the other device owner to accept only after the codes match.',
              ),
              const SizedBox(height: 10),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _securityCodesConfirmed,
                onChanged: (value) {
                  setState(() {
                    _securityCodesConfirmed = value ?? false;
                    if (_securityCodesConfirmed) {
                      _errorText = null;
                    }
                  });
                },
                title: const Text('I compared both screens and the codes match'),
                controlAffinity: ListTileControlAffinity.leading,
              ),
              const SizedBox(height: 8),
            ],
            TextField(
              controller: _controller,
              autofocus: true,
              obscureText: true,
              keyboardType: TextInputType.number,
              textInputAction: TextInputAction.done,
              maxLength: TransferPinService.maxPinLength,
              inputFormatters: <TextInputFormatter>[
                FilteringTextInputFormatter.digitsOnly,
              ],
              decoration: InputDecoration(
                labelText: 'PIN for ${widget.peerNickname}',
                helperText: TransferPinService.pinRequirementsLabel,
                errorText: _errorText,
              ),
              onSubmitted: (_) => _submit(),
            ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Continue')),
      ],
    );
  }

  void _submit() {
    final value = _controller.text.trim();
    if (widget.requiresSecurityConfirmation && !_securityCodesConfirmed) {
      setState(() {
        _errorText = 'Confirm the security codes before continuing.';
      });
      return;
    }
    if (TransferPinService.isValidPin(value)) {
      Navigator.of(context).pop(
        ReceiverPinResult(
          pin: value,
          trustConfirmed: widget.requiresSecurityConfirmation,
        ),
      );
      return;
    }
    setState(() {
      _errorText = 'Enter ${TransferPinService.pinRequirementsLabel}.';
    });
  }
}
