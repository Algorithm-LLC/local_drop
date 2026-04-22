import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[Locale('en')];

  /// No description provided for @appTitle.
  ///
  /// In en, this message translates to:
  /// **'LocalDrop'**
  String get appTitle;

  /// No description provided for @appTagline.
  ///
  /// In en, this message translates to:
  /// **'Send files locally'**
  String get appTagline;

  /// No description provided for @nearbyTab.
  ///
  /// In en, this message translates to:
  /// **'Nearby'**
  String get nearbyTab;

  /// No description provided for @transfersTab.
  ///
  /// In en, this message translates to:
  /// **'Transfers'**
  String get transfersTab;

  /// No description provided for @historyTab.
  ///
  /// In en, this message translates to:
  /// **'History'**
  String get historyTab;

  /// No description provided for @settingsTab.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settingsTab;

  /// No description provided for @onboardingTitle.
  ///
  /// In en, this message translates to:
  /// **'Welcome to LocalDrop'**
  String get onboardingTitle;

  /// No description provided for @onboardingSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Pick a nickname so nearby devices can recognize you instantly.'**
  String get onboardingSubtitle;

  /// No description provided for @nicknameLabel.
  ///
  /// In en, this message translates to:
  /// **'Nickname'**
  String get nicknameLabel;

  /// No description provided for @continueButton.
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get continueButton;

  /// No description provided for @saveButton.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get saveButton;

  /// No description provided for @yourDeviceLabel.
  ///
  /// In en, this message translates to:
  /// **'Your device'**
  String get yourDeviceLabel;

  /// No description provided for @activePortLabel.
  ///
  /// In en, this message translates to:
  /// **'Active port'**
  String get activePortLabel;

  /// No description provided for @composeSendButton.
  ///
  /// In en, this message translates to:
  /// **'Compose send'**
  String get composeSendButton;

  /// No description provided for @selectContentTitle.
  ///
  /// In en, this message translates to:
  /// **'Select content'**
  String get selectContentTitle;

  /// No description provided for @chooseDeviceTitle.
  ///
  /// In en, this message translates to:
  /// **'Choose device'**
  String get chooseDeviceTitle;

  /// No description provided for @selectFilesButton.
  ///
  /// In en, this message translates to:
  /// **'Select files'**
  String get selectFilesButton;

  /// No description provided for @chooseDeviceButton.
  ///
  /// In en, this message translates to:
  /// **'Choose device'**
  String get chooseDeviceButton;

  /// No description provided for @moreContentOptions.
  ///
  /// In en, this message translates to:
  /// **'More options'**
  String get moreContentOptions;

  /// No description provided for @addTextButton.
  ///
  /// In en, this message translates to:
  /// **'Add text'**
  String get addTextButton;

  /// No description provided for @selectionTrayTitle.
  ///
  /// In en, this message translates to:
  /// **'Selected content'**
  String get selectionTrayTitle;

  /// No description provided for @backToContent.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get backToContent;

  /// No description provided for @clearSelectionButton.
  ///
  /// In en, this message translates to:
  /// **'Clear selection'**
  String get clearSelectionButton;

  /// No description provided for @selectedItemsWithTotal.
  ///
  /// In en, this message translates to:
  /// **'{count} item(s) • {total}'**
  String selectedItemsWithTotal(int count, String total);

  /// No description provided for @sendingInProgress.
  ///
  /// In en, this message translates to:
  /// **'Sending...'**
  String get sendingInProgress;

  /// No description provided for @dragDropHint.
  ///
  /// In en, this message translates to:
  /// **'Drag and drop files or folders here.'**
  String get dragDropHint;

  /// No description provided for @dropFilesNowHint.
  ///
  /// In en, this message translates to:
  /// **'Drop now to add to selection.'**
  String get dropFilesNowHint;

  /// No description provided for @preparingSelectedContent.
  ///
  /// In en, this message translates to:
  /// **'Preparing selected content...'**
  String get preparingSelectedContent;

  /// No description provided for @textPayloadEmpty.
  ///
  /// In en, this message translates to:
  /// **'Type text before adding it.'**
  String get textPayloadEmpty;

  /// No description provided for @onlineLabel.
  ///
  /// In en, this message translates to:
  /// **'Online'**
  String get onlineLabel;

  /// No description provided for @sentToDevice.
  ///
  /// In en, this message translates to:
  /// **'Sent to {device}.'**
  String sentToDevice(String device);

  /// No description provided for @noDevicesFound.
  ///
  /// In en, this message translates to:
  /// **'No nearby LocalDrop devices found yet.'**
  String get noDevicesFound;

  /// No description provided for @waitingForDevices.
  ///
  /// In en, this message translates to:
  /// **'Looking for nearby LocalDrop devices...'**
  String get waitingForDevices;

  /// No description provided for @refreshDevicesButton.
  ///
  /// In en, this message translates to:
  /// **'Refresh'**
  String get refreshDevicesButton;

  /// No description provided for @refreshHint.
  ///
  /// In en, this message translates to:
  /// **'Keep LocalDrop open on both devices and connected to the same local network.'**
  String get refreshHint;

  /// No description provided for @networkWarmupStarting.
  ///
  /// In en, this message translates to:
  /// **'Starting local network...'**
  String get networkWarmupStarting;

  /// No description provided for @networkWarmupHint.
  ///
  /// In en, this message translates to:
  /// **'LocalDrop is preparing nearby discovery and transfers in the background.'**
  String get networkWarmupHint;

  /// No description provided for @nearbyStatusTitle.
  ///
  /// In en, this message translates to:
  /// **'Nearby status'**
  String get nearbyStatusTitle;

  /// No description provided for @nearbyStatusReady.
  ///
  /// In en, this message translates to:
  /// **'Nearby sharing is ready.'**
  String get nearbyStatusReady;

  /// No description provided for @nearbyStatusScanning.
  ///
  /// In en, this message translates to:
  /// **'Looking for nearby devices...'**
  String get nearbyStatusScanning;

  /// No description provided for @nearbyStatusCheckingDevices.
  ///
  /// In en, this message translates to:
  /// **'Found nearby devices. Finishing connection checks...'**
  String get nearbyStatusCheckingDevices;

  /// No description provided for @nearbyStatusNoDevices.
  ///
  /// In en, this message translates to:
  /// **'No nearby devices yet.'**
  String get nearbyStatusNoDevices;

  /// No description provided for @nearbyStatusNeedsAttention.
  ///
  /// In en, this message translates to:
  /// **'Nearby sharing needs attention.'**
  String get nearbyStatusNeedsAttention;

  /// No description provided for @nearbyStatusPaused.
  ///
  /// In en, this message translates to:
  /// **'Nearby receiving resumes when LocalDrop is back in the foreground.'**
  String get nearbyStatusPaused;

  /// No description provided for @nearbyReadyCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{No devices ready to receive} =1{1 device ready to receive} other{{count} devices ready to receive}}'**
  String nearbyReadyCount(int count);

  /// No description provided for @nearbyFoundCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{No nearby devices yet} =1{1 device found nearby} other{{count} devices found nearby}}'**
  String nearbyFoundCount(int count);

  /// No description provided for @nearbyNoDevicesSummary.
  ///
  /// In en, this message translates to:
  /// **'No devices found yet.'**
  String get nearbyNoDevicesSummary;

  /// No description provided for @nearbyGenericDeviceLabel.
  ///
  /// In en, this message translates to:
  /// **'Nearby device'**
  String get nearbyGenericDeviceLabel;

  /// No description provided for @nearbyPausedHint.
  ///
  /// In en, this message translates to:
  /// **'Bring LocalDrop back to the foreground to receive nearby transfers.'**
  String get nearbyPausedHint;

  /// No description provided for @nearbyIssueHint.
  ///
  /// In en, this message translates to:
  /// **'If something looks off, refresh and open Troubleshoot for more details.'**
  String get nearbyIssueHint;

  /// No description provided for @nearbyTroubleshootButton.
  ///
  /// In en, this message translates to:
  /// **'Troubleshoot'**
  String get nearbyTroubleshootButton;

  /// No description provided for @nearbyTroubleshootTitle.
  ///
  /// In en, this message translates to:
  /// **'Nearby connection details'**
  String get nearbyTroubleshootTitle;

  /// No description provided for @nearbyTechnicalStatusLabel.
  ///
  /// In en, this message translates to:
  /// **'Status'**
  String get nearbyTechnicalStatusLabel;

  /// No description provided for @nearbyTechnicalDevicesLabel.
  ///
  /// In en, this message translates to:
  /// **'Devices'**
  String get nearbyTechnicalDevicesLabel;

  /// No description provided for @nearbyTechnicalDevicesValue.
  ///
  /// In en, this message translates to:
  /// **'Found: {found} • Ready: {ready}'**
  String nearbyTechnicalDevicesValue(int found, int ready);

  /// No description provided for @nearbyTechnicalListeningPortLabel.
  ///
  /// In en, this message translates to:
  /// **'Listening port'**
  String get nearbyTechnicalListeningPortLabel;

  /// No description provided for @nearbyTechnicalInterfacesLabel.
  ///
  /// In en, this message translates to:
  /// **'Network interfaces'**
  String get nearbyTechnicalInterfacesLabel;

  /// No description provided for @nearbyTechnicalPacketsLabel.
  ///
  /// In en, this message translates to:
  /// **'Network activity'**
  String get nearbyTechnicalPacketsLabel;

  /// No description provided for @nearbyTechnicalBackendsLabel.
  ///
  /// In en, this message translates to:
  /// **'Backends'**
  String get nearbyTechnicalBackendsLabel;

  /// No description provided for @nearbyTechnicalPerBackendLabel.
  ///
  /// In en, this message translates to:
  /// **'Per backend'**
  String get nearbyTechnicalPerBackendLabel;

  /// No description provided for @nearbyTechnicalLastScanLabel.
  ///
  /// In en, this message translates to:
  /// **'Last scan'**
  String get nearbyTechnicalLastScanLabel;

  /// No description provided for @nearbyTechnicalFirewallLabel.
  ///
  /// In en, this message translates to:
  /// **'Windows firewall'**
  String get nearbyTechnicalFirewallLabel;

  /// No description provided for @nearbyTechnicalPermissionLabel.
  ///
  /// In en, this message translates to:
  /// **'Permission or setup'**
  String get nearbyTechnicalPermissionLabel;

  /// No description provided for @nearbyTechnicalIssueLabel.
  ///
  /// In en, this message translates to:
  /// **'Issue'**
  String get nearbyTechnicalIssueLabel;

  /// No description provided for @nearbyTechnicalBackendIssuesLabel.
  ///
  /// In en, this message translates to:
  /// **'Backend issues'**
  String get nearbyTechnicalBackendIssuesLabel;

  /// No description provided for @nearbyTechnicalRecentMessagesLabel.
  ///
  /// In en, this message translates to:
  /// **'Recent messages'**
  String get nearbyTechnicalRecentMessagesLabel;

  /// No description provided for @nearbyEmptyPaused.
  ///
  /// In en, this message translates to:
  /// **'Nearby receiving is paused while LocalDrop is not open in the foreground.'**
  String get nearbyEmptyPaused;

  /// No description provided for @nearbyEmptyChecking.
  ///
  /// In en, this message translates to:
  /// **'Found devices. Finishing connection checks...'**
  String get nearbyEmptyChecking;

  /// No description provided for @nearbyEmptyIssue.
  ///
  /// In en, this message translates to:
  /// **'There was a nearby connection issue. Try Refresh or open Troubleshoot.'**
  String get nearbyEmptyIssue;

  /// No description provided for @discoveryStatusTitle.
  ///
  /// In en, this message translates to:
  /// **'Discovery status'**
  String get discoveryStatusTitle;

  /// No description provided for @discoveryStatusStarting.
  ///
  /// In en, this message translates to:
  /// **'Starting nearby discovery...'**
  String get discoveryStatusStarting;

  /// No description provided for @discoveryStatusScanning.
  ///
  /// In en, this message translates to:
  /// **'Scanning the local network now...'**
  String get discoveryStatusScanning;

  /// No description provided for @discoveryStatusRunning.
  ///
  /// In en, this message translates to:
  /// **'Nearby discovery is running.'**
  String get discoveryStatusRunning;

  /// No description provided for @discoveryStatusStopped.
  ///
  /// In en, this message translates to:
  /// **'Nearby discovery is not running.'**
  String get discoveryStatusStopped;

  /// No description provided for @discoveryStatusNoScanYet.
  ///
  /// In en, this message translates to:
  /// **'No scan has completed yet.'**
  String get discoveryStatusNoScanYet;

  /// No description provided for @discoveryStatusLastScan.
  ///
  /// In en, this message translates to:
  /// **'Last scan: {time}'**
  String discoveryStatusLastScan(String time);

  /// No description provided for @discoveryStatusPortPending.
  ///
  /// In en, this message translates to:
  /// **'Listening port is still being prepared.'**
  String get discoveryStatusPortPending;

  /// No description provided for @discoveryStatusListeningPort.
  ///
  /// In en, this message translates to:
  /// **'Listening on port {port}.'**
  String discoveryStatusListeningPort(int port);

  /// No description provided for @discoveryStatusInterfaces.
  ///
  /// In en, this message translates to:
  /// **'{interfaces} interface(s) ready • {targets} scan target(s)'**
  String discoveryStatusInterfaces(int interfaces, int targets);

  /// No description provided for @discoveryStatusPackets.
  ///
  /// In en, this message translates to:
  /// **'{sent} packet(s) sent • {received} packet(s) received'**
  String discoveryStatusPackets(int sent, int received);

  /// No description provided for @discoveryStatusError.
  ///
  /// In en, this message translates to:
  /// **'Discovery error: {message}'**
  String discoveryStatusError(String message);

  /// No description provided for @discoveryFirewallNotRequired.
  ///
  /// In en, this message translates to:
  /// **'Windows firewall setup is not required on this device.'**
  String get discoveryFirewallNotRequired;

  /// No description provided for @discoveryFirewallReady.
  ///
  /// In en, this message translates to:
  /// **'Windows firewall already allows LocalDrop inbound traffic.'**
  String get discoveryFirewallReady;

  /// No description provided for @discoveryFirewallConfiguredNow.
  ///
  /// In en, this message translates to:
  /// **'Windows firewall access was configured for LocalDrop.'**
  String get discoveryFirewallConfiguredNow;

  /// No description provided for @discoveryFirewallDenied.
  ///
  /// In en, this message translates to:
  /// **'Windows firewall permission was denied. Nearby devices may stay hidden until inbound access is allowed.'**
  String get discoveryFirewallDenied;

  /// No description provided for @discoveryFirewallFailed.
  ///
  /// In en, this message translates to:
  /// **'Windows firewall setup failed: {message}'**
  String discoveryFirewallFailed(String message);

  /// No description provided for @repairFirewallButton.
  ///
  /// In en, this message translates to:
  /// **'Repair firewall'**
  String get repairFirewallButton;

  /// No description provided for @incomingRequestsTitle.
  ///
  /// In en, this message translates to:
  /// **'Incoming request'**
  String get incomingRequestsTitle;

  /// No description provided for @incomingRequestMessage.
  ///
  /// In en, this message translates to:
  /// **'{sender} wants to send {count} item(s).'**
  String incomingRequestMessage(String sender, int count);

  /// No description provided for @incomingRequestSize.
  ///
  /// In en, this message translates to:
  /// **'Size: {size}'**
  String incomingRequestSize(String size);

  /// No description provided for @incomingRequestExpiresIn.
  ///
  /// In en, this message translates to:
  /// **'Approval expires in {seconds}s.'**
  String incomingRequestExpiresIn(int seconds);

  /// No description provided for @acceptButton.
  ///
  /// In en, this message translates to:
  /// **'Accept'**
  String get acceptButton;

  /// No description provided for @declineButton.
  ///
  /// In en, this message translates to:
  /// **'Decline'**
  String get declineButton;

  /// No description provided for @chooseRecipients.
  ///
  /// In en, this message translates to:
  /// **'Recipients'**
  String get chooseRecipients;

  /// No description provided for @chooseContentType.
  ///
  /// In en, this message translates to:
  /// **'Content type'**
  String get chooseContentType;

  /// No description provided for @selectedItemsCount.
  ///
  /// In en, this message translates to:
  /// **'{count} item(s) selected'**
  String selectedItemsCount(int count);

  /// No description provided for @noItemsSelected.
  ///
  /// In en, this message translates to:
  /// **'No content selected yet.'**
  String get noItemsSelected;

  /// No description provided for @attachButton.
  ///
  /// In en, this message translates to:
  /// **'Attach content'**
  String get attachButton;

  /// No description provided for @sendNowButton.
  ///
  /// In en, this message translates to:
  /// **'Send now'**
  String get sendNowButton;

  /// No description provided for @recipientCheckingButton.
  ///
  /// In en, this message translates to:
  /// **'Checking'**
  String get recipientCheckingButton;

  /// No description provided for @recipientCheckAgainButton.
  ///
  /// In en, this message translates to:
  /// **'Check again'**
  String get recipientCheckAgainButton;

  /// No description provided for @contentFile.
  ///
  /// In en, this message translates to:
  /// **'File'**
  String get contentFile;

  /// No description provided for @contentPhoto.
  ///
  /// In en, this message translates to:
  /// **'Photo'**
  String get contentPhoto;

  /// No description provided for @contentVideo.
  ///
  /// In en, this message translates to:
  /// **'Video'**
  String get contentVideo;

  /// No description provided for @contentFolder.
  ///
  /// In en, this message translates to:
  /// **'Folder'**
  String get contentFolder;

  /// No description provided for @contentText.
  ///
  /// In en, this message translates to:
  /// **'Text'**
  String get contentText;

  /// No description provided for @contentClipboard.
  ///
  /// In en, this message translates to:
  /// **'Clipboard'**
  String get contentClipboard;

  /// No description provided for @textPayloadHint.
  ///
  /// In en, this message translates to:
  /// **'Type your text here...'**
  String get textPayloadHint;

  /// No description provided for @clipboardEmpty.
  ///
  /// In en, this message translates to:
  /// **'Clipboard is empty.'**
  String get clipboardEmpty;

  /// No description provided for @transferIncoming.
  ///
  /// In en, this message translates to:
  /// **'Incoming'**
  String get transferIncoming;

  /// No description provided for @transferOutgoing.
  ///
  /// In en, this message translates to:
  /// **'Outgoing'**
  String get transferOutgoing;

  /// No description provided for @statusPendingApproval.
  ///
  /// In en, this message translates to:
  /// **'Pending approval'**
  String get statusPendingApproval;

  /// No description provided for @statusApproved.
  ///
  /// In en, this message translates to:
  /// **'Approved'**
  String get statusApproved;

  /// No description provided for @statusDeclined.
  ///
  /// In en, this message translates to:
  /// **'Declined'**
  String get statusDeclined;

  /// No description provided for @statusInProgress.
  ///
  /// In en, this message translates to:
  /// **'In progress'**
  String get statusInProgress;

  /// No description provided for @statusCompleted.
  ///
  /// In en, this message translates to:
  /// **'Completed'**
  String get statusCompleted;

  /// No description provided for @statusFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed'**
  String get statusFailed;

  /// No description provided for @statusCanceled.
  ///
  /// In en, this message translates to:
  /// **'Canceled'**
  String get statusCanceled;

  /// No description provided for @transferStageConnecting.
  ///
  /// In en, this message translates to:
  /// **'Connecting to receiver'**
  String get transferStageConnecting;

  /// No description provided for @transferStageOfferQueued.
  ///
  /// In en, this message translates to:
  /// **'Offer delivered'**
  String get transferStageOfferQueued;

  /// No description provided for @transferStageAwaitingApproval.
  ///
  /// In en, this message translates to:
  /// **'Waiting for receiver approval'**
  String get transferStageAwaitingApproval;

  /// No description provided for @transferStageUploading.
  ///
  /// In en, this message translates to:
  /// **'Uploading content'**
  String get transferStageUploading;

  /// No description provided for @transferStageCompleting.
  ///
  /// In en, this message translates to:
  /// **'Finalizing transfer'**
  String get transferStageCompleting;

  /// No description provided for @speedLabel.
  ///
  /// In en, this message translates to:
  /// **'Speed'**
  String get speedLabel;

  /// No description provided for @etaLabel.
  ///
  /// In en, this message translates to:
  /// **'ETA'**
  String get etaLabel;

  /// No description provided for @cancelButton.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancelButton;

  /// No description provided for @retryButton.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get retryButton;

  /// No description provided for @openFolderButton.
  ///
  /// In en, this message translates to:
  /// **'Open folder'**
  String get openFolderButton;

  /// No description provided for @noActiveTransfers.
  ///
  /// In en, this message translates to:
  /// **'No active transfers right now.'**
  String get noActiveTransfers;

  /// No description provided for @transferFolderTitle.
  ///
  /// In en, this message translates to:
  /// **'Transfer folder'**
  String get transferFolderTitle;

  /// No description provided for @transferFolderPathLabel.
  ///
  /// In en, this message translates to:
  /// **'Location'**
  String get transferFolderPathLabel;

  /// No description provided for @transferFolderEmpty.
  ///
  /// In en, this message translates to:
  /// **'This folder is empty.'**
  String get transferFolderEmpty;

  /// No description provided for @transferFolderUnavailable.
  ///
  /// In en, this message translates to:
  /// **'This folder is no longer available.'**
  String get transferFolderUnavailable;

  /// No description provided for @historySearchHint.
  ///
  /// In en, this message translates to:
  /// **'Search history by name or device'**
  String get historySearchHint;

  /// No description provided for @noHistory.
  ///
  /// In en, this message translates to:
  /// **'No transfer history yet.'**
  String get noHistory;

  /// No description provided for @themeSection.
  ///
  /// In en, this message translates to:
  /// **'Theme'**
  String get themeSection;

  /// No description provided for @themeSystem.
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get themeSystem;

  /// No description provided for @themeLight.
  ///
  /// In en, this message translates to:
  /// **'Light'**
  String get themeLight;

  /// No description provided for @themeDark.
  ///
  /// In en, this message translates to:
  /// **'Dark'**
  String get themeDark;

  /// No description provided for @saveDirectoryLabel.
  ///
  /// In en, this message translates to:
  /// **'Save directory'**
  String get saveDirectoryLabel;

  /// No description provided for @pickDirectoryButton.
  ///
  /// In en, this message translates to:
  /// **'Choose directory'**
  String get pickDirectoryButton;

  /// No description provided for @useDefaultDirectoryButton.
  ///
  /// In en, this message translates to:
  /// **'Use default'**
  String get useDefaultDirectoryButton;

  /// No description provided for @websiteLinkLabel.
  ///
  /// In en, this message translates to:
  /// **'Get LocalDrop on your other devices'**
  String get websiteLinkLabel;

  /// No description provided for @websiteLinkDescription.
  ///
  /// In en, this message translates to:
  /// **'Install LocalDrop on Windows, macOS, Linux, Android, or iPhone from the official website.'**
  String get websiteLinkDescription;

  /// No description provided for @openWebsiteButton.
  ///
  /// In en, this message translates to:
  /// **'Open website'**
  String get openWebsiteButton;

  /// No description provided for @copyLinkButton.
  ///
  /// In en, this message translates to:
  /// **'Copy link'**
  String get copyLinkButton;

  /// No description provided for @websiteOpenFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t open the LocalDrop website.'**
  String get websiteOpenFailed;

  /// No description provided for @identitySection.
  ///
  /// In en, this message translates to:
  /// **'Identity'**
  String get identitySection;

  /// No description provided for @deviceIdLabel.
  ///
  /// In en, this message translates to:
  /// **'Device ID'**
  String get deviceIdLabel;

  /// No description provided for @fingerprintLabel.
  ///
  /// In en, this message translates to:
  /// **'Fingerprint'**
  String get fingerprintLabel;

  /// No description provided for @removeButton.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get removeButton;

  /// No description provided for @copied.
  ///
  /// In en, this message translates to:
  /// **'Copied'**
  String get copied;

  /// No description provided for @nicknameSaved.
  ///
  /// In en, this message translates to:
  /// **'Nickname saved.'**
  String get nicknameSaved;

  /// No description provided for @settingsSaved.
  ///
  /// In en, this message translates to:
  /// **'Settings updated.'**
  String get settingsSaved;

  /// No description provided for @failedToSend.
  ///
  /// In en, this message translates to:
  /// **'Failed to send content.'**
  String get failedToSend;

  /// No description provided for @sendErrorRecipientOffline.
  ///
  /// In en, this message translates to:
  /// **'Recipient is offline. Refresh nearby devices and try again.'**
  String get sendErrorRecipientOffline;

  /// No description provided for @sendErrorTransferUnreachable.
  ///
  /// In en, this message translates to:
  /// **'Receiver discovered, but the transfer port could not be reached.'**
  String get sendErrorTransferUnreachable;

  /// No description provided for @sendErrorMissingFile.
  ///
  /// In en, this message translates to:
  /// **'One or more selected files are missing.'**
  String get sendErrorMissingFile;

  /// No description provided for @sendErrorTimeout.
  ///
  /// In en, this message translates to:
  /// **'Transfer timed out. Try again.'**
  String get sendErrorTimeout;

  /// No description provided for @sendErrorApprovalExpired.
  ///
  /// In en, this message translates to:
  /// **'Approval expired before the receiver accepted.'**
  String get sendErrorApprovalExpired;

  /// No description provided for @sendErrorCertificate.
  ///
  /// In en, this message translates to:
  /// **'Security verification failed for this device.'**
  String get sendErrorCertificate;

  /// No description provided for @sendErrorIntegrity.
  ///
  /// In en, this message translates to:
  /// **'Integrity check failed. Please resend.'**
  String get sendErrorIntegrity;

  /// No description provided for @sendErrorRejected.
  ///
  /// In en, this message translates to:
  /// **'Receiver declined the transfer.'**
  String get sendErrorRejected;

  /// No description provided for @sendErrorIncompatibleVersion.
  ///
  /// In en, this message translates to:
  /// **'Update LocalDrop on both devices before sending.'**
  String get sendErrorIncompatibleVersion;

  /// No description provided for @sendErrorBusy.
  ///
  /// In en, this message translates to:
  /// **'A send is already in progress.'**
  String get sendErrorBusy;

  /// No description provided for @sendErrorUnknown.
  ///
  /// In en, this message translates to:
  /// **'Something went wrong while sending.'**
  String get sendErrorUnknown;

  /// No description provided for @recipientReadyMessage.
  ///
  /// In en, this message translates to:
  /// **'Ready to receive'**
  String get recipientReadyMessage;

  /// No description provided for @recipientCheckingMessage.
  ///
  /// In en, this message translates to:
  /// **'Checking connection...'**
  String get recipientCheckingMessage;

  /// No description provided for @recipientNeedsUpdateMessage.
  ///
  /// In en, this message translates to:
  /// **'Update both devices to the latest LocalDrop build.'**
  String get recipientNeedsUpdateMessage;

  /// No description provided for @recipientSecurityMessage.
  ///
  /// In en, this message translates to:
  /// **'We couldn\'t verify this device securely. Check both devices and try again.'**
  String get recipientSecurityMessage;

  /// No description provided for @recipientUnavailableMessage.
  ///
  /// In en, this message translates to:
  /// **'This device was found, but it is not ready to receive yet.'**
  String get recipientUnavailableMessage;

  /// No description provided for @recipientPendingMessage.
  ///
  /// In en, this message translates to:
  /// **'Found nearby. Finishing connection check...'**
  String get recipientPendingMessage;

  /// No description provided for @updateRequiredLabel.
  ///
  /// In en, this message translates to:
  /// **'Update required'**
  String get updateRequiredLabel;

  /// No description provided for @incompatibleDeviceHint.
  ///
  /// In en, this message translates to:
  /// **'This device needs the latest LocalDrop build before transfers can start.'**
  String get incompatibleDeviceHint;

  /// No description provided for @selectAtLeastOneDevice.
  ///
  /// In en, this message translates to:
  /// **'Select at least one recipient.'**
  String get selectAtLeastOneDevice;

  /// No description provided for @selectContentFirst.
  ///
  /// In en, this message translates to:
  /// **'Select content first.'**
  String get selectContentFirst;

  /// No description provided for @securityModelTitle.
  ///
  /// In en, this message translates to:
  /// **'Security'**
  String get securityModelTitle;

  /// No description provided for @securityModelDescription.
  ///
  /// In en, this message translates to:
  /// **'Every incoming transfer requires explicit accept/decline. This build prioritizes reliable local-network transfer startup and approval-based receiver consent.'**
  String get securityModelDescription;

  /// No description provided for @currentTransferTitle.
  ///
  /// In en, this message translates to:
  /// **'Current transfer'**
  String get currentTransferTitle;

  /// No description provided for @transferDetailsButton.
  ///
  /// In en, this message translates to:
  /// **'Details'**
  String get transferDetailsButton;

  /// No description provided for @transferDiagnosticsTitle.
  ///
  /// In en, this message translates to:
  /// **'Transfer details'**
  String get transferDiagnosticsTitle;

  /// No description provided for @closeButtonLabel.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get closeButtonLabel;

  /// No description provided for @transferUnknownValue.
  ///
  /// In en, this message translates to:
  /// **'Unknown'**
  String get transferUnknownValue;

  /// No description provided for @transferNotAvailableValue.
  ///
  /// In en, this message translates to:
  /// **'Not available'**
  String get transferNotAvailableValue;

  /// No description provided for @transferDiagnosticsStageLabel.
  ///
  /// In en, this message translates to:
  /// **'Stage'**
  String get transferDiagnosticsStageLabel;

  /// No description provided for @transferDiagnosticsEndpointLabel.
  ///
  /// In en, this message translates to:
  /// **'Endpoint'**
  String get transferDiagnosticsEndpointLabel;

  /// No description provided for @transferDiagnosticsAddressFamilyLabel.
  ///
  /// In en, this message translates to:
  /// **'Address family'**
  String get transferDiagnosticsAddressFamilyLabel;

  /// No description provided for @transferDiagnosticsSecurityLabel.
  ///
  /// In en, this message translates to:
  /// **'Transport security'**
  String get transferDiagnosticsSecurityLabel;

  /// No description provided for @transferDiagnosticsSecurityNotUsed.
  ///
  /// In en, this message translates to:
  /// **'Not used by the current local transport'**
  String get transferDiagnosticsSecurityNotUsed;

  /// No description provided for @transferDiagnosticsSecurityVerified.
  ///
  /// In en, this message translates to:
  /// **'Verified'**
  String get transferDiagnosticsSecurityVerified;

  /// No description provided for @transferDiagnosticsSecurityFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed'**
  String get transferDiagnosticsSecurityFailed;

  /// No description provided for @transferDiagnosticsHttpRouteLabel.
  ///
  /// In en, this message translates to:
  /// **'HTTP route'**
  String get transferDiagnosticsHttpRouteLabel;

  /// No description provided for @transferDiagnosticsHttpStatusLabel.
  ///
  /// In en, this message translates to:
  /// **'HTTP status'**
  String get transferDiagnosticsHttpStatusLabel;

  /// No description provided for @transferDiagnosticsOfferStatusLabel.
  ///
  /// In en, this message translates to:
  /// **'Offer status'**
  String get transferDiagnosticsOfferStatusLabel;

  /// No description provided for @transferDiagnosticsDecisionLabel.
  ///
  /// In en, this message translates to:
  /// **'Decision'**
  String get transferDiagnosticsDecisionLabel;

  /// No description provided for @transferDiagnosticsUploadLabel.
  ///
  /// In en, this message translates to:
  /// **'Upload'**
  String get transferDiagnosticsUploadLabel;

  /// No description provided for @transferDiagnosticsTerminalReasonLabel.
  ///
  /// In en, this message translates to:
  /// **'Reason'**
  String get transferDiagnosticsTerminalReasonLabel;

  /// No description provided for @transferDiagnosticsMessageLabel.
  ///
  /// In en, this message translates to:
  /// **'Message'**
  String get transferDiagnosticsMessageLabel;

  /// No description provided for @transferDiagnosticsNoExtraDetails.
  ///
  /// In en, this message translates to:
  /// **'No extra details were recorded.'**
  String get transferDiagnosticsNoExtraDetails;

  /// No description provided for @transferDiagnosticsLogLabel.
  ///
  /// In en, this message translates to:
  /// **'Transport log'**
  String get transferDiagnosticsLogLabel;

  /// No description provided for @transferReasonConnectionIssue.
  ///
  /// In en, this message translates to:
  /// **'Connection issue'**
  String get transferReasonConnectionIssue;

  /// No description provided for @transferReasonSecurityIssue.
  ///
  /// In en, this message translates to:
  /// **'Security check failed'**
  String get transferReasonSecurityIssue;

  /// No description provided for @transferReasonApprovalExpired.
  ///
  /// In en, this message translates to:
  /// **'Approval expired'**
  String get transferReasonApprovalExpired;

  /// No description provided for @transferReasonDeclined.
  ///
  /// In en, this message translates to:
  /// **'Declined'**
  String get transferReasonDeclined;

  /// No description provided for @transferReasonTransferFailed.
  ///
  /// In en, this message translates to:
  /// **'Transfer failed'**
  String get transferReasonTransferFailed;

  /// No description provided for @transferReasonVerificationFailed.
  ///
  /// In en, this message translates to:
  /// **'Verification failed'**
  String get transferReasonVerificationFailed;

  /// No description provided for @transferReasonUpdateRequired.
  ///
  /// In en, this message translates to:
  /// **'Update required'**
  String get transferReasonUpdateRequired;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
