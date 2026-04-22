// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'LocalDrop';

  @override
  String get appTagline => 'Send files locally';

  @override
  String get nearbyTab => 'Nearby';

  @override
  String get transfersTab => 'Transfers';

  @override
  String get historyTab => 'History';

  @override
  String get settingsTab => 'Settings';

  @override
  String get onboardingTitle => 'Welcome to LocalDrop';

  @override
  String get onboardingSubtitle =>
      'Pick a nickname so nearby devices can recognize you instantly.';

  @override
  String get nicknameLabel => 'Nickname';

  @override
  String get continueButton => 'Continue';

  @override
  String get saveButton => 'Save';

  @override
  String get yourDeviceLabel => 'Your device';

  @override
  String get activePortLabel => 'Active port';

  @override
  String get composeSendButton => 'Compose send';

  @override
  String get selectContentTitle => 'Select content';

  @override
  String get chooseDeviceTitle => 'Choose device';

  @override
  String get selectFilesButton => 'Select files';

  @override
  String get chooseDeviceButton => 'Choose device';

  @override
  String get moreContentOptions => 'More options';

  @override
  String get addTextButton => 'Add text';

  @override
  String get selectionTrayTitle => 'Selected content';

  @override
  String get backToContent => 'Back';

  @override
  String get clearSelectionButton => 'Clear selection';

  @override
  String selectedItemsWithTotal(int count, String total) {
    return '$count item(s) • $total';
  }

  @override
  String get sendingInProgress => 'Sending...';

  @override
  String get dragDropHint => 'Drag and drop files or folders here.';

  @override
  String get dropFilesNowHint => 'Drop now to add to selection.';

  @override
  String get preparingSelectedContent => 'Preparing selected content...';

  @override
  String get textPayloadEmpty => 'Type text before adding it.';

  @override
  String get onlineLabel => 'Online';

  @override
  String sentToDevice(String device) {
    return 'Sent to $device.';
  }

  @override
  String get noDevicesFound => 'No nearby LocalDrop devices found yet.';

  @override
  String get waitingForDevices => 'Looking for nearby LocalDrop devices...';

  @override
  String get refreshDevicesButton => 'Refresh';

  @override
  String get refreshHint =>
      'Keep LocalDrop open on both devices and connected to the same local network.';

  @override
  String get networkWarmupStarting => 'Starting local network...';

  @override
  String get networkWarmupHint =>
      'LocalDrop is preparing nearby discovery and transfers in the background.';

  @override
  String get nearbyStatusTitle => 'Nearby status';

  @override
  String get nearbyStatusReady => 'Nearby sharing is ready.';

  @override
  String get nearbyStatusScanning => 'Looking for nearby devices...';

  @override
  String get nearbyStatusCheckingDevices =>
      'Found nearby devices. Finishing connection checks...';

  @override
  String get nearbyStatusNoDevices => 'No nearby devices yet.';

  @override
  String get nearbyStatusNeedsAttention => 'Nearby sharing needs attention.';

  @override
  String get nearbyStatusPaused =>
      'Nearby receiving resumes when LocalDrop is back in the foreground.';

  @override
  String nearbyReadyCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count devices ready to receive',
      one: '1 device ready to receive',
      zero: 'No devices ready to receive',
    );
    return '$_temp0';
  }

  @override
  String nearbyFoundCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count devices found nearby',
      one: '1 device found nearby',
      zero: 'No nearby devices yet',
    );
    return '$_temp0';
  }

  @override
  String get nearbyNoDevicesSummary => 'No devices found yet.';

  @override
  String get nearbyGenericDeviceLabel => 'Nearby device';

  @override
  String get nearbyPausedHint =>
      'Bring LocalDrop back to the foreground to receive nearby transfers.';

  @override
  String get nearbyIssueHint =>
      'If something looks off, refresh and open Troubleshoot for more details.';

  @override
  String get nearbyTroubleshootButton => 'Troubleshoot';

  @override
  String get nearbyTroubleshootTitle => 'Nearby connection details';

  @override
  String get nearbyTechnicalStatusLabel => 'Status';

  @override
  String get nearbyTechnicalDevicesLabel => 'Devices';

  @override
  String nearbyTechnicalDevicesValue(int found, int ready) {
    return 'Found: $found • Ready: $ready';
  }

  @override
  String get nearbyTechnicalListeningPortLabel => 'Listening port';

  @override
  String get nearbyTechnicalInterfacesLabel => 'Network interfaces';

  @override
  String get nearbyTechnicalPacketsLabel => 'Network activity';

  @override
  String get nearbyTechnicalBackendsLabel => 'Backends';

  @override
  String get nearbyTechnicalPerBackendLabel => 'Per backend';

  @override
  String get nearbyTechnicalLastScanLabel => 'Last scan';

  @override
  String get nearbyTechnicalFirewallLabel => 'Windows firewall';

  @override
  String get nearbyTechnicalPermissionLabel => 'Permission or setup';

  @override
  String get nearbyTechnicalIssueLabel => 'Issue';

  @override
  String get nearbyTechnicalBackendIssuesLabel => 'Backend issues';

  @override
  String get nearbyTechnicalRecentMessagesLabel => 'Recent messages';

  @override
  String get nearbyEmptyPaused =>
      'Nearby receiving is paused while LocalDrop is not open in the foreground.';

  @override
  String get nearbyEmptyChecking =>
      'Found devices. Finishing connection checks...';

  @override
  String get nearbyEmptyIssue =>
      'There was a nearby connection issue. Try Refresh or open Troubleshoot.';

  @override
  String get discoveryStatusTitle => 'Discovery status';

  @override
  String get discoveryStatusStarting => 'Starting nearby discovery...';

  @override
  String get discoveryStatusScanning => 'Scanning the local network now...';

  @override
  String get discoveryStatusRunning => 'Nearby discovery is running.';

  @override
  String get discoveryStatusStopped => 'Nearby discovery is not running.';

  @override
  String get discoveryStatusNoScanYet => 'No scan has completed yet.';

  @override
  String discoveryStatusLastScan(String time) {
    return 'Last scan: $time';
  }

  @override
  String get discoveryStatusPortPending =>
      'Listening port is still being prepared.';

  @override
  String discoveryStatusListeningPort(int port) {
    return 'Listening on port $port.';
  }

  @override
  String discoveryStatusInterfaces(int interfaces, int targets) {
    return '$interfaces interface(s) ready • $targets scan target(s)';
  }

  @override
  String discoveryStatusPackets(int sent, int received) {
    return '$sent packet(s) sent • $received packet(s) received';
  }

  @override
  String discoveryStatusError(String message) {
    return 'Discovery error: $message';
  }

  @override
  String get discoveryFirewallNotRequired =>
      'Windows firewall setup is not required on this device.';

  @override
  String get discoveryFirewallReady =>
      'Windows firewall already allows LocalDrop inbound traffic.';

  @override
  String get discoveryFirewallConfiguredNow =>
      'Windows firewall access was configured for LocalDrop.';

  @override
  String get discoveryFirewallDenied =>
      'Windows firewall permission was denied. Nearby devices may stay hidden until inbound access is allowed.';

  @override
  String discoveryFirewallFailed(String message) {
    return 'Windows firewall setup failed: $message';
  }

  @override
  String get repairFirewallButton => 'Repair firewall';

  @override
  String get incomingRequestsTitle => 'Incoming request';

  @override
  String incomingRequestMessage(String sender, int count) {
    return '$sender wants to send $count item(s).';
  }

  @override
  String incomingRequestSize(String size) {
    return 'Size: $size';
  }

  @override
  String incomingRequestExpiresIn(int seconds) {
    return 'Approval expires in ${seconds}s.';
  }

  @override
  String get acceptButton => 'Accept';

  @override
  String get declineButton => 'Decline';

  @override
  String get chooseRecipients => 'Recipients';

  @override
  String get chooseContentType => 'Content type';

  @override
  String selectedItemsCount(int count) {
    return '$count item(s) selected';
  }

  @override
  String get noItemsSelected => 'No content selected yet.';

  @override
  String get attachButton => 'Attach content';

  @override
  String get sendNowButton => 'Send now';

  @override
  String get recipientCheckingButton => 'Checking';

  @override
  String get recipientCheckAgainButton => 'Check again';

  @override
  String get contentFile => 'File';

  @override
  String get contentPhoto => 'Photo';

  @override
  String get contentVideo => 'Video';

  @override
  String get contentFolder => 'Folder';

  @override
  String get contentText => 'Text';

  @override
  String get contentClipboard => 'Clipboard';

  @override
  String get textPayloadHint => 'Type your text here...';

  @override
  String get clipboardEmpty => 'Clipboard is empty.';

  @override
  String get transferIncoming => 'Incoming';

  @override
  String get transferOutgoing => 'Outgoing';

  @override
  String get statusPendingApproval => 'Pending approval';

  @override
  String get statusApproved => 'Approved';

  @override
  String get statusDeclined => 'Declined';

  @override
  String get statusInProgress => 'In progress';

  @override
  String get statusCompleted => 'Completed';

  @override
  String get statusFailed => 'Failed';

  @override
  String get statusCanceled => 'Canceled';

  @override
  String get transferStageConnecting => 'Connecting to receiver';

  @override
  String get transferStageOfferQueued => 'Offer delivered';

  @override
  String get transferStageAwaitingApproval => 'Waiting for receiver approval';

  @override
  String get transferStageUploading => 'Uploading content';

  @override
  String get transferStageCompleting => 'Finalizing transfer';

  @override
  String get speedLabel => 'Speed';

  @override
  String get etaLabel => 'ETA';

  @override
  String get cancelButton => 'Cancel';

  @override
  String get retryButton => 'Retry';

  @override
  String get openFolderButton => 'Open folder';

  @override
  String get noActiveTransfers => 'No active transfers right now.';

  @override
  String get transferFolderTitle => 'Transfer folder';

  @override
  String get transferFolderPathLabel => 'Location';

  @override
  String get transferFolderEmpty => 'This folder is empty.';

  @override
  String get transferFolderUnavailable => 'This folder is no longer available.';

  @override
  String get historySearchHint => 'Search history by name or device';

  @override
  String get noHistory => 'No transfer history yet.';

  @override
  String get themeSection => 'Theme';

  @override
  String get themeSystem => 'System';

  @override
  String get themeLight => 'Light';

  @override
  String get themeDark => 'Dark';

  @override
  String get saveDirectoryLabel => 'Save directory';

  @override
  String get pickDirectoryButton => 'Choose directory';

  @override
  String get useDefaultDirectoryButton => 'Use default';

  @override
  String get websiteLinkLabel => 'Get LocalDrop on your other devices';

  @override
  String get websiteLinkDescription =>
      'Install LocalDrop on Windows, macOS, Linux, Android, or iPhone from the official website.';

  @override
  String get openWebsiteButton => 'Open website';

  @override
  String get copyLinkButton => 'Copy link';

  @override
  String get websiteOpenFailed => 'Couldn\'t open the LocalDrop website.';

  @override
  String get identitySection => 'Identity';

  @override
  String get deviceIdLabel => 'Device ID';

  @override
  String get fingerprintLabel => 'Fingerprint';

  @override
  String get removeButton => 'Remove';

  @override
  String get copied => 'Copied';

  @override
  String get nicknameSaved => 'Nickname saved.';

  @override
  String get settingsSaved => 'Settings updated.';

  @override
  String get failedToSend => 'Failed to send content.';

  @override
  String get sendErrorRecipientOffline =>
      'Recipient is offline. Refresh nearby devices and try again.';

  @override
  String get sendErrorTransferUnreachable =>
      'Receiver discovered, but the transfer port could not be reached.';

  @override
  String get sendErrorMissingFile => 'One or more selected files are missing.';

  @override
  String get sendErrorTimeout => 'Transfer timed out. Try again.';

  @override
  String get sendErrorApprovalExpired =>
      'Approval expired before the receiver accepted.';

  @override
  String get sendErrorCertificate =>
      'Security verification failed for this device.';

  @override
  String get sendErrorIntegrity => 'Integrity check failed. Please resend.';

  @override
  String get sendErrorRejected => 'Receiver declined the transfer.';

  @override
  String get sendErrorIncompatibleVersion =>
      'Update LocalDrop on both devices before sending.';

  @override
  String get sendErrorBusy => 'A send is already in progress.';

  @override
  String get sendErrorUnknown => 'Something went wrong while sending.';

  @override
  String get recipientReadyMessage => 'Ready to receive';

  @override
  String get recipientCheckingMessage => 'Checking connection...';

  @override
  String get recipientNeedsUpdateMessage =>
      'Update both devices to the latest LocalDrop build.';

  @override
  String get recipientSecurityMessage =>
      'We couldn\'t verify this device securely. Check both devices and try again.';

  @override
  String get recipientUnavailableMessage =>
      'This device was found, but it is not ready to receive yet.';

  @override
  String get recipientPendingMessage =>
      'Found nearby. Finishing connection check...';

  @override
  String get updateRequiredLabel => 'Update required';

  @override
  String get incompatibleDeviceHint =>
      'This device needs the latest LocalDrop build before transfers can start.';

  @override
  String get selectAtLeastOneDevice => 'Select at least one recipient.';

  @override
  String get selectContentFirst => 'Select content first.';

  @override
  String get securityModelTitle => 'Security';

  @override
  String get securityModelDescription =>
      'Every incoming transfer requires explicit accept/decline. This build prioritizes reliable local-network transfer startup and approval-based receiver consent.';

  @override
  String get currentTransferTitle => 'Current transfer';

  @override
  String get transferDetailsButton => 'Details';

  @override
  String get transferDiagnosticsTitle => 'Transfer details';

  @override
  String get closeButtonLabel => 'Close';

  @override
  String get transferUnknownValue => 'Unknown';

  @override
  String get transferNotAvailableValue => 'Not available';

  @override
  String get transferDiagnosticsStageLabel => 'Stage';

  @override
  String get transferDiagnosticsEndpointLabel => 'Endpoint';

  @override
  String get transferDiagnosticsAddressFamilyLabel => 'Address family';

  @override
  String get transferDiagnosticsSecurityLabel => 'Transport security';

  @override
  String get transferDiagnosticsSecurityNotUsed =>
      'Not used by the current local transport';

  @override
  String get transferDiagnosticsSecurityVerified => 'Verified';

  @override
  String get transferDiagnosticsSecurityFailed => 'Failed';

  @override
  String get transferDiagnosticsHttpRouteLabel => 'HTTP route';

  @override
  String get transferDiagnosticsHttpStatusLabel => 'HTTP status';

  @override
  String get transferDiagnosticsOfferStatusLabel => 'Offer status';

  @override
  String get transferDiagnosticsDecisionLabel => 'Decision';

  @override
  String get transferDiagnosticsUploadLabel => 'Upload';

  @override
  String get transferDiagnosticsTerminalReasonLabel => 'Reason';

  @override
  String get transferDiagnosticsMessageLabel => 'Message';

  @override
  String get transferDiagnosticsNoExtraDetails =>
      'No extra details were recorded.';

  @override
  String get transferDiagnosticsLogLabel => 'Transport log';

  @override
  String get transferReasonConnectionIssue => 'Connection issue';

  @override
  String get transferReasonSecurityIssue => 'Security check failed';

  @override
  String get transferReasonApprovalExpired => 'Approval expired';

  @override
  String get transferReasonDeclined => 'Declined';

  @override
  String get transferReasonTransferFailed => 'Transfer failed';

  @override
  String get transferReasonVerificationFailed => 'Verification failed';

  @override
  String get transferReasonUpdateRequired => 'Update required';
}
