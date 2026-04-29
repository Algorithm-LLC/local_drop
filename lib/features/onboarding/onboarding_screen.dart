import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:local_drop/l10n/app_localizations.dart';

import '../../services/transfer_pin_service.dart';
import '../../state/app_controller.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key, required this.controller});

  final AppController controller;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  late final TextEditingController _nicknameController;
  late final TextEditingController _pinController;
  late final TextEditingController _confirmPinController;
  String? _pinErrorText;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _nicknameController = TextEditingController(
      text: widget.controller.preferences.nickname,
    );
    _pinController = TextEditingController();
    _confirmPinController = TextEditingController();
  }

  @override
  void dispose() {
    _nicknameController.dispose();
    _pinController.dispose();
    _confirmPinController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: <Color>[
              Theme.of(context).colorScheme.primary.withValues(alpha: 0.15),
              Theme.of(context).colorScheme.secondary.withValues(alpha: 0.08),
              Theme.of(context).scaffoldBackgroundColor,
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final minHeight = constraints.maxHeight > 48
                  ? constraints.maxHeight - 48
                  : 0.0;
              return SingleChildScrollView(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                padding: const EdgeInsets.all(24),
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: minHeight),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 560),
                      child: Card(
                        margin: EdgeInsets.zero,
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: <Widget>[
                              Text(
                                l10n.onboardingTitle,
                                style: Theme.of(
                                  context,
                                ).textTheme.headlineMedium,
                              ),
                              const SizedBox(height: 10),
                              Text(
                                l10n.onboardingSubtitle,
                                style: Theme.of(context).textTheme.bodyLarge,
                              ),
                              const SizedBox(height: 24),
                              TextField(
                                controller: _nicknameController,
                                maxLength: 24,
                                textInputAction: TextInputAction.next,
                                decoration: InputDecoration(
                                  labelText: l10n.nicknameLabel,
                                ),
                              ),
                              const SizedBox(height: 12),
                              TextField(
                                controller: _pinController,
                                maxLength: TransferPinService.maxPinLength,
                                obscureText: true,
                                keyboardType: TextInputType.number,
                                textInputAction: TextInputAction.next,
                                inputFormatters: <TextInputFormatter>[
                                  FilteringTextInputFormatter.digitsOnly,
                                ],
                                decoration: InputDecoration(
                                  labelText: 'Transfer PIN',
                                  helperText:
                                      TransferPinService.pinRequirementsLabel,
                                  errorText: _pinErrorText,
                                ),
                              ),
                              const SizedBox(height: 12),
                              TextField(
                                controller: _confirmPinController,
                                maxLength: TransferPinService.maxPinLength,
                                obscureText: true,
                                keyboardType: TextInputType.number,
                                textInputAction: TextInputAction.done,
                                inputFormatters: <TextInputFormatter>[
                                  FilteringTextInputFormatter.digitsOnly,
                                ],
                                onSubmitted: (_) => _submit(),
                                decoration: const InputDecoration(
                                  labelText: 'Confirm PIN',
                                ),
                              ),
                              const SizedBox(height: 18),
                              FilledButton(
                                onPressed: _saving ? null : _submit,
                                child: _saving
                                    ? const SizedBox.square(
                                        dimension: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : Text(l10n.continueButton),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Future<void> _submit() async {
    final value = _nicknameController.text.trim();
    if (value.isEmpty) {
      return;
    }
    final pin = _pinController.text.trim();
    final confirmPin = _confirmPinController.text.trim();
    if (!TransferPinService.isValidPin(pin) || pin != confirmPin) {
      setState(() {
        _pinErrorText = pin == confirmPin
            ? 'Enter ${TransferPinService.pinRequirementsLabel}.'
            : 'PINs do not match.';
      });
      return;
    }
    setState(() {
      _saving = true;
      _pinErrorText = null;
    });
    await widget.controller.saveOnboardingProfile(
      nickname: value,
      transferPin: pin,
    );
    if (mounted) {
      setState(() {
        _saving = false;
      });
    }
  }
}
