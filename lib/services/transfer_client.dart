import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../core/constants/network_constants.dart';
import '../models/device_profile.dart';
import '../models/transfer_diagnostics_snapshot.dart';
import '../models/transfer_models.dart';
import 'transfer_pin_service.dart';

typedef TransferTraceHandler =
    void Function(String message, {Map<String, Object?>? data});

class TransferHealthPeerSnapshot {
  const TransferHealthPeerSnapshot({
    required this.profile,
    required this.selectedAddress,
    required this.selectedPort,
    required this.addressFamily,
  });

  final DeviceProfile profile;
  final String selectedAddress;
  final int selectedPort;
  final String addressFamily;
}

class TransferClient {
  TransferTraceHandler? onTrace;
  String Function()? senderDeviceIdProvider;
  String Function()? senderNicknameProvider;
  String Function()? senderFingerprintProvider;
  String Function()? senderPlatformProvider;
  String Function()? senderAppVersionProvider;
  int Function()? senderActivePortProvider;
  int? Function()? senderSecurePortProvider;

  Future<PeerAvailabilitySnapshot> probeRecipient({
    required DeviceProfile recipient,
    PeerAvailabilitySnapshot? preferredAvailability,
  }) async {
    final targets = _candidateTargets(
      recipient,
      preferredAvailability: preferredAvailability,
    );
    if (targets.isEmpty) {
      return PeerAvailabilitySnapshot(
        deviceId: recipient.deviceId,
        nickname: recipient.nickname,
        status: PeerAvailabilityStatus.securityFailure,
        updatedAt: DateTime.now(),
        selectedAddress: recipient.ipAddress,
        selectedPort: recipient.securePort ?? recipient.activePort,
        addressFamily: recipient.preferredAddressFamily,
        errorMessage:
            'Receiver does not advertise HTTPS transfer with a certificate fingerprint.',
        protocolVersion: recipient.protocolVersion,
        appVersion: recipient.appVersion,
        capabilities: recipient.capabilities,
      );
    }

    final failures = <_ProbeFailure>[];
    for (final target in targets) {
      final client = _buildClientForTarget(
        target,
        connectionTimeout: const Duration(seconds: 4),
        idleTimeout: const Duration(seconds: 6),
      );
      try {
        final payload = await _fetchHealth(client, target);
        final protocolVersion = (payload['protocolVersion'] as String?) ?? '';
        final capabilities =
            ((payload['capabilities'] as List<dynamic>?) ?? const <dynamic>[])
                .map((item) => item.toString())
                .toList(growable: false);
        if (protocolVersion != NetworkConstants.protocolVersion ||
            !capabilities.contains(
              NetworkConstants.protocolCapabilityQueuedApproval,
            )) {
          return PeerAvailabilitySnapshot(
            deviceId: recipient.deviceId,
            nickname: recipient.nickname,
            status: PeerAvailabilityStatus.incompatible,
            updatedAt: DateTime.now(),
            selectedAddress: target.address,
            selectedPort: target.port,
            addressFamily: _addressFamily(target.address),
            errorMessage: 'Update LocalDrop on both devices.',
            protocolVersion: protocolVersion,
            appVersion: payload['appVersion'] as String?,
            capabilities: capabilities,
          );
        }

        _trace(
          'Receiver health probe succeeded',
          data: <String, Object?>{
            'address': target.address,
            'port': target.port,
            'addressFamily': _addressFamily(target.address),
            'protocolVersion': payload['protocolVersion'] as String?,
            'appVersion': payload['appVersion'] as String?,
          },
        );
        return PeerAvailabilitySnapshot(
          deviceId: recipient.deviceId,
          nickname: recipient.nickname,
          status: PeerAvailabilityStatus.ready,
          updatedAt: DateTime.now(),
          selectedAddress: target.address,
          selectedPort: target.port,
          addressFamily: _addressFamily(target.address),
          protocolVersion: protocolVersion,
          appVersion: payload['appVersion'] as String?,
          capabilities: capabilities,
        );
      } on HandshakeException catch (error) {
        failures.add(_ProbeFailure(target: target, error: error));
        _traceProbeFailure(recipient, target, error);
      } on _TransferHttpException catch (error) {
        failures.add(_ProbeFailure(target: target, error: error));
        _traceProbeFailure(recipient, target, error);
        if (error.statusCode == HttpStatus.notFound ||
            error.statusCode == HttpStatus.conflict) {
          return PeerAvailabilitySnapshot(
            deviceId: recipient.deviceId,
            nickname: recipient.nickname,
            status: PeerAvailabilityStatus.incompatible,
            updatedAt: DateTime.now(),
            selectedAddress: target.address,
            selectedPort: target.port,
            addressFamily: _addressFamily(target.address),
            errorMessage: error.messageFromBody,
          );
        }
      } catch (error) {
        failures.add(_ProbeFailure(target: target, error: error));
        _traceProbeFailure(recipient, target, error);
      } finally {
        client.close(force: true);
      }
    }

    final bestFailure = _selectBestProbeFailure(recipient, failures);
    if (bestFailure == null) {
      return PeerAvailabilitySnapshot(
        deviceId: recipient.deviceId,
        nickname: recipient.nickname,
        status: PeerAvailabilityStatus.unreachable,
        updatedAt: DateTime.now(),
        selectedAddress: recipient.ipAddress,
        selectedPort: recipient.activePort,
        addressFamily: _addressFamily(recipient.ipAddress),
        errorMessage:
            'Receiver discovered, but transfer port could not be reached.',
      );
    }

    if (bestFailure.error is HandshakeException) {
      return PeerAvailabilitySnapshot(
        deviceId: recipient.deviceId,
        nickname: recipient.nickname,
        status: PeerAvailabilityStatus.securityFailure,
        updatedAt: DateTime.now(),
        selectedAddress: bestFailure.target.address,
        selectedPort: bestFailure.target.port,
        addressFamily: _addressFamily(bestFailure.target.address),
        errorMessage: _probeErrorMessage(bestFailure),
      );
    }

    if (bestFailure.error is _TransferHttpException) {
      final error = bestFailure.error as _TransferHttpException;
      return PeerAvailabilitySnapshot(
        deviceId: recipient.deviceId,
        nickname: recipient.nickname,
        status: PeerAvailabilityStatus.unreachable,
        updatedAt: DateTime.now(),
        selectedAddress: bestFailure.target.address,
        selectedPort: bestFailure.target.port,
        addressFamily: _addressFamily(bestFailure.target.address),
        errorMessage: error.messageFromBody,
      );
    }

    return PeerAvailabilitySnapshot(
      deviceId: recipient.deviceId,
      nickname: recipient.nickname,
      status: PeerAvailabilityStatus.unreachable,
      updatedAt: DateTime.now(),
      selectedAddress: bestFailure.target.address,
      selectedPort: bestFailure.target.port,
      addressFamily: _addressFamily(bestFailure.target.address),
      errorMessage: _probeErrorMessage(bestFailure),
    );
  }

  Future<TransferRecord> sendTransfer({
    required DeviceProfile recipient,
    required TransferOffer offer,
    required String receiverPin,
    required void Function(TransferProgress progress) onProgress,
    required bool Function() isCanceled,
    required void Function(TransferDiagnosticsSnapshot snapshot) onDiagnostics,
    PeerAvailabilitySnapshot? preferredAvailability,
    String? diagnosticsLogPath,
  }) async {
    final startedAt = DateTime.now();
    final targets = _candidateTargets(
      recipient,
      preferredAvailability: preferredAvailability,
    );

    var transferredBytes = 0;
    var lastUploadProgressAt = startedAt;
    var lastUploadProgressBytes = 0;
    var currentDiagnostics = TransferDiagnosticsSnapshot(
      contextId: offer.transferId,
      peerDeviceId: recipient.deviceId,
      peerNickname: recipient.nickname,
      isIncoming: false,
      stage: TransferStage.connecting,
      updatedAt: startedAt,
      logFilePath: diagnosticsLogPath,
    );

    void emitDiagnostics({
      TransferStage? stage,
      _TransferTarget? target,
      bool? tlsFingerprintVerified,
      String? lastHttpRoute,
      int? lastHttpStatusCode,
      String? offerStatus,
      TransferDecisionStatus? decisionStatus,
      String? uploadStatus,
      TransferTerminalReason? terminalReason,
      String? errorMessage,
    }) {
      currentDiagnostics = currentDiagnostics.copyWith(
        stage: stage,
        updatedAt: DateTime.now(),
        selectedAddress: target?.address ?? currentDiagnostics.selectedAddress,
        selectedPort: target?.port ?? currentDiagnostics.selectedPort,
        addressFamily: target == null
            ? currentDiagnostics.addressFamily
            : _addressFamily(target.address),
        tlsFingerprintVerified: tlsFingerprintVerified,
        lastHttpRoute: lastHttpRoute,
        lastHttpStatusCode: lastHttpStatusCode,
        offerStatus: offerStatus,
        decisionStatus: decisionStatus,
        uploadStatus: uploadStatus,
        terminalReason: terminalReason,
        errorMessage: errorMessage,
      );
      onDiagnostics(currentDiagnostics);
    }

    void emitProgress(
      TransferStatus status, {
      TransferStage? stage,
      TransferTerminalReason? terminalReason,
      String? errorMessage,
      DateTime? updatedAt,
    }) {
      onProgress(
        TransferProgress(
          transferId: offer.transferId,
          peerDeviceId: recipient.deviceId,
          peerNickname: recipient.nickname,
          isIncoming: false,
          status: status,
          totalBytes: offer.totalBytes,
          transferredBytes: transferredBytes,
          startedAt: startedAt,
          updatedAt: updatedAt ?? DateTime.now(),
          stage: stage,
          terminalReason: terminalReason,
          errorMessage: errorMessage,
        ),
      );
    }

    void emitUploadProgressThrottled() {
      final now = DateTime.now();
      final enoughTimeElapsed =
          now.difference(lastUploadProgressAt) >=
          NetworkConstants.transferProgressMinInterval;
      final enoughBytesSent =
          transferredBytes - lastUploadProgressBytes >=
          NetworkConstants.transferProgressMinByteDelta;
      final isComplete = transferredBytes >= offer.totalBytes;
      if (!enoughTimeElapsed && !enoughBytesSent && !isComplete) {
        return;
      }
      lastUploadProgressAt = now;
      lastUploadProgressBytes = transferredBytes;
      emitProgress(
        TransferStatus.inProgress,
        stage: TransferStage.uploading,
        updatedAt: now,
      );
    }

    emitProgress(
      TransferStatus.pendingApproval,
      stage: TransferStage.connecting,
    );
    emitDiagnostics(stage: TransferStage.connecting);

    if (targets.isEmpty) {
      const failure = _FailureDetails(
        terminalReason: TransferTerminalReason.tlsVerificationFailed,
        message:
            'Receiver does not advertise HTTPS transfer with a certificate fingerprint.',
      );
      emitProgress(
        TransferStatus.failed,
        stage: TransferStage.failed,
        terminalReason: failure.terminalReason,
        errorMessage: failure.message,
      );
      emitDiagnostics(
        stage: TransferStage.failed,
        terminalReason: failure.terminalReason,
        errorMessage: failure.message,
      );
      return TransferRecord(
        transferId: offer.transferId,
        peerDeviceId: recipient.deviceId,
        peerNickname: recipient.nickname,
        isIncoming: false,
        items: offer.items,
        status: TransferStatus.failed,
        totalBytes: offer.totalBytes,
        transferredBytes: transferredBytes,
        startedAt: startedAt,
        endedAt: DateTime.now(),
        stage: TransferStage.failed,
        terminalReason: failure.terminalReason,
        errorMessage: failure.message,
      );
    }

    Object? lastError;
    for (final target in targets) {
      final client = _buildClientForTarget(target);
      try {
        emitDiagnostics(
          stage: TransferStage.connecting,
          target: target,
          lastHttpRoute: '/v1/transfer/offer',
        );
        if (isCanceled()) {
          throw const _TransferCanceledException();
        }
        final challenge = await _fetchPinChallenge(client, target);
        if (isCanceled()) {
          throw const _TransferCanceledException();
        }
        final authedOffer = offer.copyWith(
          pinAuth: await TransferPinService.buildAuthAsync(
            pin: receiverPin,
            challenge: challenge,
          ),
        );
        if (isCanceled()) {
          throw const _TransferCanceledException();
        }
        final ack = await _sendOffer(client, target, authedOffer);
        if (isCanceled()) {
          throw const _TransferCanceledException();
        }
        if (!ack.isQueued) {
          throw _TransferStageException(
            TransferStage.failed,
            ack.reason ?? 'Offer was not queued by the receiver.',
            terminalReason: ack.status == 'incompatible'
                ? TransferTerminalReason.incompatibleProtocol
                : TransferTerminalReason.unknown,
          );
        }
        if (ack.receiverProtocolVersion != NetworkConstants.protocolVersion ||
            !ack.receiverCapabilities.contains(
              NetworkConstants.protocolCapabilityQueuedApproval,
            )) {
          throw const _TransferStageException(
            TransferStage.failed,
            'Update LocalDrop on both devices.',
            terminalReason: TransferTerminalReason.incompatibleProtocol,
          );
        }

        emitProgress(
          TransferStatus.pendingApproval,
          stage: TransferStage.offerQueued,
        );
        emitDiagnostics(
          stage: TransferStage.offerQueued,
          target: target,
          lastHttpRoute: '/v1/transfer/offer',
          lastHttpStatusCode: HttpStatus.accepted,
          offerStatus: ack.status,
        );

        final decision = await _waitForDecision(
          client: client,
          target: target,
          transferId: offer.transferId,
          ack: ack,
          isCanceled: isCanceled,
          onWaiting: () {
            emitProgress(
              TransferStatus.pendingApproval,
              stage: TransferStage.awaitingApproval,
            );
            emitDiagnostics(
              stage: TransferStage.awaitingApproval,
              target: target,
              decisionStatus: TransferDecisionStatus.pending,
              lastHttpRoute: '/v1/transfer/${offer.transferId}/decision',
            );
          },
          onDecisionPoll: (statusCode) {
            emitDiagnostics(
              target: target,
              lastHttpRoute: '/v1/transfer/${offer.transferId}/decision',
              lastHttpStatusCode: statusCode,
            );
          },
        );

        switch (decision.status) {
          case TransferDecisionStatus.pending:
            throw const _TransferStageException(
              TransferStage.failed,
              'Timeout waiting for receiver approval.',
              terminalReason: TransferTerminalReason.approvalExpired,
            );
          case TransferDecisionStatus.declined:
            emitProgress(
              TransferStatus.declined,
              stage: TransferStage.failed,
              terminalReason: TransferTerminalReason.declined,
              errorMessage:
                  decision.reason ?? 'Receiver declined the transfer.',
            );
            emitDiagnostics(
              stage: TransferStage.failed,
              target: target,
              decisionStatus: TransferDecisionStatus.declined,
              terminalReason: TransferTerminalReason.declined,
              errorMessage:
                  decision.reason ?? 'Receiver declined the transfer.',
            );
            return TransferRecord(
              transferId: offer.transferId,
              peerDeviceId: recipient.deviceId,
              peerNickname: recipient.nickname,
              isIncoming: false,
              items: offer.items,
              status: TransferStatus.declined,
              totalBytes: offer.totalBytes,
              transferredBytes: transferredBytes,
              startedAt: startedAt,
              endedAt: DateTime.now(),
              stage: TransferStage.failed,
              terminalReason: TransferTerminalReason.declined,
              errorMessage:
                  decision.reason ?? 'Receiver declined the transfer.',
            );
          case TransferDecisionStatus.expired:
            throw _TransferStageException(
              TransferStage.failed,
              decision.reason ?? 'Approval expired.',
              terminalReason: TransferTerminalReason.approvalExpired,
            );
          case TransferDecisionStatus.accepted:
            break;
        }

        emitProgress(
          TransferStatus.approved,
          stage: TransferStage.awaitingApproval,
        );
        emitDiagnostics(
          stage: TransferStage.awaitingApproval,
          target: target,
          decisionStatus: TransferDecisionStatus.accepted,
        );

        for (final item in offer.items) {
          if (isCanceled()) {
            emitProgress(
              TransferStatus.canceled,
              stage: TransferStage.failed,
              terminalReason: TransferTerminalReason.canceled,
            );
            emitDiagnostics(
              stage: TransferStage.failed,
              target: target,
              terminalReason: TransferTerminalReason.canceled,
            );
            throw const _TransferCanceledException();
          }

          await _sendItemData(
            client: client,
            target: target,
            transferId: offer.transferId,
            item: item,
            isCanceled: isCanceled,
            onChunk: (chunkSize) {
              transferredBytes += chunkSize;
              emitUploadProgressThrottled();
            },
            onDataAccepted: (statusCode) {
              emitUploadProgressThrottled();
              emitDiagnostics(
                stage: TransferStage.uploading,
                target: target,
                uploadStatus: item.name,
                lastHttpRoute: '/v1/transfer/${offer.transferId}/data',
                lastHttpStatusCode: statusCode,
              );
            },
          );
        }

        emitProgress(
          TransferStatus.inProgress,
          stage: TransferStage.completing,
        );
        emitDiagnostics(
          stage: TransferStage.completing,
          target: target,
          lastHttpRoute: '/v1/transfer/${offer.transferId}/complete',
        );
        await _sendComplete(client, target, offer);
        final completedAt = DateTime.now();
        emitProgress(
          TransferStatus.completed,
          stage: TransferStage.completing,
          updatedAt: completedAt,
        );
        emitDiagnostics(
          stage: TransferStage.completing,
          target: target,
          lastHttpRoute: '/v1/transfer/${offer.transferId}/complete',
          lastHttpStatusCode: HttpStatus.ok,
        );
        return TransferRecord(
          transferId: offer.transferId,
          peerDeviceId: recipient.deviceId,
          peerNickname: recipient.nickname,
          isIncoming: false,
          items: offer.items,
          status: TransferStatus.completed,
          totalBytes: offer.totalBytes,
          transferredBytes: transferredBytes,
          startedAt: startedAt,
          endedAt: completedAt,
          stage: TransferStage.completing,
        );
      } on _TransferCanceledException {
        return TransferRecord(
          transferId: offer.transferId,
          peerDeviceId: recipient.deviceId,
          peerNickname: recipient.nickname,
          isIncoming: false,
          items: offer.items,
          status: TransferStatus.canceled,
          totalBytes: offer.totalBytes,
          transferredBytes: transferredBytes,
          startedAt: startedAt,
          endedAt: DateTime.now(),
          stage: TransferStage.failed,
          terminalReason: TransferTerminalReason.canceled,
        );
      } catch (error) {
        lastError = error;
        final failure = _failureDetails(error);
        emitDiagnostics(
          stage: TransferStage.failed,
          target: target,
          tlsFingerprintVerified: error is HandshakeException ? false : null,
          terminalReason: failure.terminalReason,
          errorMessage: failure.message,
        );
        if (_shouldRetryTarget(error)) {
          continue;
        }
        break;
      } finally {
        client.close(force: true);
      }
    }

    final failure = _failureDetails(lastError);
    emitProgress(
      TransferStatus.failed,
      stage: TransferStage.failed,
      terminalReason: failure.terminalReason,
      errorMessage: failure.message,
    );
    emitDiagnostics(
      stage: TransferStage.failed,
      terminalReason: failure.terminalReason,
      errorMessage: failure.message,
    );
    return TransferRecord(
      transferId: offer.transferId,
      peerDeviceId: recipient.deviceId,
      peerNickname: recipient.nickname,
      isIncoming: false,
      items: offer.items,
      status: TransferStatus.failed,
      totalBytes: offer.totalBytes,
      transferredBytes: transferredBytes,
      startedAt: startedAt,
      endedAt: DateTime.now(),
      stage: TransferStage.failed,
      terminalReason: failure.terminalReason,
      errorMessage: failure.message,
    );
  }

  Future<TransferHealthPeerSnapshot?> discoverPeerAt({
    required String address,
    required int port,
    String? expectedFingerprint,
  }) async {
    final normalizedExpectedFingerprint =
        expectedFingerprint?.trim().isNotEmpty == true
        ? expectedFingerprint!.trim()
        : null;
    String? presentedFingerprint;
    final target = _TransferTarget(
      address: address,
      port: port,
      useTls: true,
      expectedFingerprint: normalizedExpectedFingerprint,
    );
    final client = _buildClientForTarget(
      target,
      connectionTimeout: const Duration(milliseconds: 700),
      idleTimeout: const Duration(seconds: 2),
      allowUnknownCertificate: normalizedExpectedFingerprint == null,
      onCertificateFingerprint: (fingerprint) {
        presentedFingerprint = fingerprint;
      },
    );
    try {
      final payload = await _fetchHealth(client, target);
      if (normalizedExpectedFingerprint == null) {
        final advertisedFingerprint =
            (payload['certFingerprint'] as String?)?.trim().toUpperCase() ?? '';
        final observedFingerprint =
            presentedFingerprint?.trim().toUpperCase() ?? '';
        if (advertisedFingerprint.isEmpty ||
            advertisedFingerprint != observedFingerprint) {
          return null;
        }
      }
      return _peerSnapshotFromHealthPayload(payload, target);
    } catch (_) {
      return null;
    } finally {
      client.close(force: true);
    }
  }

  HttpClient _buildClient({
    Duration connectionTimeout = const Duration(seconds: 8),
    Duration idleTimeout = const Duration(seconds: 20),
  }) {
    final client = HttpClient();
    client.connectionTimeout = connectionTimeout;
    client.idleTimeout = idleTimeout;
    return client;
  }

  List<_TransferTarget> _candidateTargets(
    DeviceProfile recipient, {
    PeerAvailabilitySnapshot? preferredAvailability,
  }) {
    final prioritized = <_TransferTarget>[];
    if (!_recipientSupportsHttpsTransfer(recipient)) {
      return const <_TransferTarget>[];
    }
    final expectedFingerprint = recipient.certFingerprint.trim();
    final seen = <String>{};

    void addTarget(String? address, int? port) {
      final trimmedAddress = address?.trim() ?? '';
      final resolvedPort = port ?? 0;
      if (trimmedAddress.isEmpty || resolvedPort <= 0) {
        return;
      }
      final target = _TransferTarget(
        address: trimmedAddress,
        port: resolvedPort,
        useTls: true,
        expectedFingerprint: expectedFingerprint,
      );
      if (seen.add(target.key)) {
        prioritized.add(target);
      }
    }

    if (preferredAvailability?.selectedAddress != null &&
        preferredAvailability?.selectedPort != null) {
      addTarget(
        preferredAvailability!.selectedAddress,
        preferredAvailability.selectedPort,
      );
    }

    final defaultSecurePort = recipient.securePort ?? recipient.activePort;
    final addresses = _orderedAddresses(
      recipient,
      preferredAvailability: preferredAvailability,
    );
    for (final address in addresses) {
      addTarget(address, defaultSecurePort);
    }

    for (final source in recipient.discoverySources) {
      final sourcePort = source.securePort ?? source.activePort;
      for (final address in source.ipAddresses) {
        addTarget(address, sourcePort);
      }
      if (source.ipAddresses.isEmpty) {
        addTarget(recipient.ipAddress, sourcePort);
      }
    }
    return prioritized;
  }

  List<String> _orderedAddresses(
    DeviceProfile recipient, {
    PeerAvailabilitySnapshot? preferredAvailability,
  }) {
    final ordered = <String>[];
    final seen = <String>{};

    void addAddress(String? value) {
      final address = value?.trim() ?? '';
      if (address.isEmpty || !seen.add(address)) {
        return;
      }
      ordered.add(address);
    }

    addAddress(preferredAvailability?.selectedAddress);

    final rawAddresses = <String>[...recipient.ipAddresses, recipient.ipAddress]
      ..removeWhere((item) => item.trim().isEmpty);
    rawAddresses.sort((a, b) {
      final preferredCompare = _preferredAddressWeight(
        recipient.preferredAddressFamily,
        a,
      ).compareTo(_preferredAddressWeight(recipient.preferredAddressFamily, b));
      if (preferredCompare != 0) {
        return preferredCompare;
      }
      final familyCompare = _addressFamilyPriority(
        a,
      ).compareTo(_addressFamilyPriority(b));
      if (familyCompare != 0) {
        return familyCompare;
      }
      return 0;
    });

    for (final address in rawAddresses) {
      addAddress(address);
    }
    return ordered;
  }

  bool _shouldRetryTarget(Object error) {
    if (error is SocketException || error is TimeoutException) {
      return true;
    }
    if (error is _TransferHttpException) {
      return error.retryable;
    }
    return false;
  }

  _FailureDetails _failureDetails(Object? error) {
    if (error is _TransferStageException) {
      return _FailureDetails(
        terminalReason: error.terminalReason,
        message: error.message,
      );
    }
    if (error is HandshakeException) {
      return const _FailureDetails(
        terminalReason: TransferTerminalReason.tlsVerificationFailed,
        message: 'Security verification failed.',
      );
    }
    if (error is SocketException || error is TimeoutException) {
      return const _FailureDetails(
        terminalReason: TransferTerminalReason.discoveryVisibleButUnreachable,
        message: 'Receiver discovered, but transfer port could not be reached.',
      );
    }
    if (error is _TransferHttpException) {
      final lowerMessage = error.messageFromBody.toLowerCase();
      return _FailureDetails(
        terminalReason: lowerMessage.contains('pin')
            ? TransferTerminalReason.pinVerificationFailed
            : error.statusCode == HttpStatus.conflict &&
                  lowerMessage.contains('checksum')
            ? TransferTerminalReason.integrityCheckFailed
            : error.statusCode == HttpStatus.notFound
            ? TransferTerminalReason.incompatibleProtocol
            : TransferTerminalReason.uploadFailed,
        message: error.messageFromBody,
      );
    }
    return _FailureDetails(
      terminalReason: TransferTerminalReason.unknown,
      message: (error ?? StateError('Unknown transfer error')).toString(),
    );
  }

  _ProbeFailure? _selectBestProbeFailure(
    DeviceProfile recipient,
    List<_ProbeFailure> failures,
  ) {
    if (failures.isEmpty) {
      return null;
    }
    final sorted = List<_ProbeFailure>.from(failures)
      ..sort((a, b) {
        final scoreCompare = _probeFailureScore(
          recipient,
          b,
        ).compareTo(_probeFailureScore(recipient, a));
        if (scoreCompare != 0) {
          return scoreCompare;
        }
        return failures.indexOf(b).compareTo(failures.indexOf(a));
      });
    return sorted.first;
  }

  int _probeFailureScore(DeviceProfile recipient, _ProbeFailure failure) {
    final advertisedPort = failure.target.useTls
        ? recipient.securePort ?? recipient.activePort
        : recipient.activePort;
    final isAdvertisedPort = failure.target.port == advertisedPort;
    final isAdvertisedAddress = recipient.ipAddresses.contains(
      failure.target.address,
    );
    final targetWeight =
        (isAdvertisedPort ? 100 : 0) + (isAdvertisedAddress ? 10 : 0);
    final errorWeight = switch (failure.error) {
      HandshakeException _ => 1000,
      _TransferHttpException _ => 800,
      TimeoutException _ => 600,
      SocketException _ => 500,
      _ => 100,
    };
    return errorWeight + targetWeight;
  }

  String _probeErrorMessage(_ProbeFailure failure) {
    final endpoint = '${failure.target.address}:${failure.target.port}';
    final error = failure.error;
    if (error is HandshakeException) {
      return 'Security verification failed for $endpoint.';
    }
    if (error is TimeoutException) {
      return 'Timed out reaching receiver at $endpoint.';
    }
    if (error is SocketException) {
      final lower = error.toString().toLowerCase();
      if (lower.contains('refused')) {
        return 'Receiver at $endpoint refused the connection.';
      }
      if (lower.contains('host is down') ||
          lower.contains('host unreachable')) {
        return 'Receiver at $endpoint is not reachable on the local network.';
      }
      return 'Receiver discovered, but $endpoint could not be reached.';
    }
    if (error is _TransferHttpException) {
      return error.messageFromBody;
    }
    return 'Receiver discovered, but $endpoint could not be reached.';
  }

  void _traceProbeFailure(
    DeviceProfile recipient,
    _TransferTarget target,
    Object error,
  ) {
    _trace(
      'Receiver health probe failed',
      data: <String, Object?>{
        'deviceId': recipient.deviceId,
        'nickname': recipient.nickname,
        'address': target.address,
        'port': target.port,
        'addressFamily': _addressFamily(target.address),
        'advertisedPort': recipient.activePort,
        'errorType': error.runtimeType.toString(),
        'error': error.toString(),
      },
    );
  }

  Future<Map<String, dynamic>> _fetchHealth(
    HttpClient client,
    _TransferTarget target,
  ) async {
    final uri = _uri(target, '/v1/transfer/health');
    final request = await client.getUrl(uri);
    _applySenderHeaders(request);
    final response = await request.close();
    final body = await utf8.decoder.bind(response).join();
    if (response.statusCode != HttpStatus.ok) {
      throw _TransferHttpException(
        statusCode: response.statusCode,
        message: 'Failed to probe receiver health',
        body: body,
        uri: uri,
        retryable: response.statusCode == HttpStatus.notFound,
      );
    }
    return body.trim().isEmpty
        ? <String, dynamic>{}
        : jsonDecode(body) as Map<String, dynamic>;
  }

  Future<TransferPinChallenge> _fetchPinChallenge(
    HttpClient client,
    _TransferTarget target,
  ) async {
    final uri = _uri(target, '/v1/transfer/pin-challenge');
    final request = await client.getUrl(uri);
    _applySenderHeaders(request);
    final response = await request.close();
    final body = await utf8.decoder.bind(response).join();
    if (response.statusCode != HttpStatus.ok) {
      throw _TransferHttpException(
        statusCode: response.statusCode,
        message: 'Failed to request receiver PIN challenge',
        body: body,
        uri: uri,
        retryable: false,
      );
    }
    final json = body.trim().isEmpty
        ? <String, dynamic>{}
        : jsonDecode(body) as Map<String, dynamic>;
    return TransferPinChallenge.fromJson(json);
  }

  Future<TransferOfferAck> _sendOffer(
    HttpClient client,
    _TransferTarget target,
    TransferOffer offer,
  ) async {
    final uri = _uri(target, '/v1/transfer/offer');
    final request = await client.postUrl(uri);
    _applySenderHeaders(request);
    request.headers.contentType = ContentType.json;
    request.write(jsonEncode(offer.toJson()));
    final response = await request.close();
    final body = await utf8.decoder.bind(response).join();

    if (response.statusCode == HttpStatus.accepted) {
      final json = body.trim().isEmpty
          ? <String, dynamic>{}
          : jsonDecode(body) as Map<String, dynamic>;
      return TransferOfferAck.fromJson(json);
    }

    throw _TransferHttpException(
      statusCode: response.statusCode,
      message: 'Offer rejected',
      body: body,
      uri: uri,
      retryable: response.statusCode == HttpStatus.notFound,
    );
  }

  Future<TransferDecisionSnapshot> _waitForDecision({
    required HttpClient client,
    required _TransferTarget target,
    required String transferId,
    required TransferOfferAck ack,
    required bool Function() isCanceled,
    required void Function() onWaiting,
    required void Function(int statusCode) onDecisionPoll,
  }) async {
    final localStartedAt = DateTime.now();
    final localDeadline = localStartedAt.add(
      NetworkConstants.approvalTimeout + NetworkConstants.approvalPollInterval,
    );
    if (ack.expiresAt.isBefore(localStartedAt)) {
      _trace(
        'Receiver approval expiry appears earlier than the local clock; using local timeout window',
        data: <String, Object?>{
          'transferId': transferId,
          'receiverExpiresAt': ack.expiresAt.toIso8601String(),
          'localStartedAt': localStartedAt.toIso8601String(),
          'localDeadline': localDeadline.toIso8601String(),
        },
      );
    }

    while (DateTime.now().isBefore(localDeadline)) {
      if (isCanceled()) {
        throw const _TransferCanceledException();
      }
      onWaiting();
      final snapshot = await _fetchDecision(
        client,
        target,
        transferId,
        onDecisionPoll: onDecisionPoll,
      );
      if (snapshot.status != TransferDecisionStatus.pending) {
        return snapshot;
      }
      await Future<void>.delayed(NetworkConstants.approvalPollInterval);
    }

    return TransferDecisionSnapshot(
      transferId: transferId,
      status: TransferDecisionStatus.expired,
      expiresAt: ack.expiresAt,
      reason: 'Approval expired.',
    );
  }

  Future<TransferDecisionSnapshot> _fetchDecision(
    HttpClient client,
    _TransferTarget target,
    String transferId, {
    required void Function(int statusCode) onDecisionPoll,
  }) async {
    final uri = _uri(target, '/v1/transfer/$transferId/decision');
    final request = await client.getUrl(uri);
    _applySenderHeaders(request);
    final response = await request.close();
    final body = await utf8.decoder.bind(response).join();
    onDecisionPoll(response.statusCode);
    if (response.statusCode != HttpStatus.ok) {
      throw _TransferHttpException(
        statusCode: response.statusCode,
        message: 'Failed to read receiver approval status',
        body: body,
        uri: uri,
        retryable: false,
      );
    }

    final json = body.trim().isEmpty
        ? <String, dynamic>{}
        : jsonDecode(body) as Map<String, dynamic>;
    return TransferDecisionSnapshot.fromJson(json);
  }

  Future<void> _sendItemData({
    required HttpClient client,
    required _TransferTarget target,
    required String transferId,
    required TransferItem item,
    required bool Function() isCanceled,
    required void Function(int chunkSize) onChunk,
    required void Function(int statusCode) onDataAccepted,
  }) async {
    if (isCanceled()) {
      throw const _TransferCanceledException();
    }
    final uri = _uri(
      target,
      '/v1/transfer/$transferId/data',
      queryParameters: <String, String>{'itemId': item.id},
    );
    final request = await client.putUrl(uri);
    _applySenderHeaders(request);
    request.headers.contentType = item.isText
        ? ContentType.text
        : ContentType.binary;
    request.headers.set('x-localdrop-item-name', item.name);
    request.headers.set('x-localdrop-item-type', item.type.name);
    request.headers.set('x-localdrop-checksum', item.checksumSha256);

    if (item.isText) {
      final bytes = utf8.encode(item.textContent ?? '');
      request.headers.contentLength = bytes.length;
      if (isCanceled()) {
        throw const _TransferCanceledException();
      }
      request.add(bytes);
      onChunk(bytes.length);
    } else {
      final path = item.sourcePath;
      if (path == null || path.isEmpty) {
        throw const _TransferStageException(
          TransferStage.failed,
          'Missing source path for transfer item.',
          terminalReason: TransferTerminalReason.uploadFailed,
        );
      }
      final sourceFile = File(path);
      if (!await sourceFile.exists()) {
        throw _TransferStageException(
          TransferStage.failed,
          'File not found: $path',
          terminalReason: TransferTerminalReason.uploadFailed,
        );
      }
      request.headers.contentLength = item.sizeBytes;
      await request.addStream(
        _progressStream(
          _fileChunks(sourceFile),
          isCanceled: isCanceled,
          onChunk: onChunk,
        ),
      );
    }

    if (isCanceled()) {
      throw const _TransferCanceledException();
    }
    final response = await request.close();
    final body = await utf8.decoder.bind(response).join();
    onDataAccepted(response.statusCode);
    if (response.statusCode != HttpStatus.ok) {
      throw _TransferHttpException(
        statusCode: response.statusCode,
        message: 'Failed to upload ${p.basename(item.name)}',
        body: body,
        uri: uri,
        retryable: false,
      );
    }
  }

  Future<void> _sendComplete(
    HttpClient client,
    _TransferTarget target,
    TransferOffer offer,
  ) async {
    final uri = _uri(target, '/v1/transfer/${offer.transferId}/complete');
    final request = await client.postUrl(uri);
    _applySenderHeaders(request);
    request.headers.contentType = ContentType.json;
    request.write(
      jsonEncode(<String, dynamic>{
        'transferId': offer.transferId,
        'completedAt': DateTime.now().toUtc().toIso8601String(),
        'itemChecksums': <String, String>{
          for (final item in offer.items) item.id: item.checksumSha256,
        },
      }),
    );
    final response = await request.close();
    final body = await utf8.decoder.bind(response).join();
    if (response.statusCode != HttpStatus.ok) {
      throw _TransferHttpException(
        statusCode: response.statusCode,
        message: 'Failed to complete transfer',
        body: body,
        uri: uri,
        retryable: false,
      );
    }
  }

  TransferHealthPeerSnapshot? _peerSnapshotFromHealthPayload(
    Map<String, dynamic> payload,
    _TransferTarget target,
  ) {
    final protocolVersion = (payload['protocolVersion'] as String?) ?? '';
    final capabilities =
        ((payload['capabilities'] as List<dynamic>?) ?? const <dynamic>[])
            .map((item) => item.toString())
            .where((item) => item.trim().isNotEmpty)
            .toList(growable: false);
    if (protocolVersion != NetworkConstants.protocolVersion ||
        !capabilities.contains(
          NetworkConstants.protocolCapabilityQueuedApproval,
        )) {
      return null;
    }

    final deviceId = (payload['deviceId'] as String?)?.trim() ?? '';
    final nickname = (payload['nickname'] as String?)?.trim() ?? '';
    final certFingerprint =
        (payload['certFingerprint'] as String?)?.trim() ?? '';
    final activePort = (payload['activePort'] as num?)?.toInt() ?? target.port;
    final securePort = (payload['securePort'] as num?)?.toInt();
    if (deviceId.isEmpty ||
        nickname.isEmpty ||
        certFingerprint.isEmpty ||
        activePort <= 0) {
      return null;
    }

    final addressFamily =
        (payload['preferredAddressFamily'] as String?)?.trim().isNotEmpty ??
            false
        ? (payload['preferredAddressFamily'] as String).trim()
        : _addressFamily(target.address);

    return TransferHealthPeerSnapshot(
      profile: DeviceProfile(
        deviceId: deviceId,
        nickname: nickname,
        platform: (payload['platform'] as String?)?.trim().isNotEmpty ?? false
            ? (payload['platform'] as String).trim()
            : 'unknown',
        ipAddress: target.address,
        ipAddresses: <String>[target.address],
        activePort: activePort,
        securePort: securePort,
        certFingerprint: certFingerprint,
        appVersion: (payload['appVersion'] as String?) ?? '',
        protocolVersion: protocolVersion,
        capabilities: capabilities,
        preferredAddressFamily: addressFamily,
        lastSeen: DateTime.now(),
      ),
      selectedAddress: target.address,
      selectedPort: securePort ?? activePort,
      addressFamily: addressFamily,
    );
  }

  void _applySenderHeaders(HttpClientRequest request) {
    void setHeader(String name, String? value) {
      final trimmed = value?.trim() ?? '';
      if (trimmed.isEmpty) {
        return;
      }
      request.headers.set(name, trimmed);
    }

    setHeader('x-localdrop-device-id', senderDeviceIdProvider?.call());
    setHeader('x-localdrop-nickname', senderNicknameProvider?.call());
    setHeader(
      'x-localdrop-cert-fingerprint',
      senderFingerprintProvider?.call(),
    );
    setHeader('x-localdrop-platform', senderPlatformProvider?.call());
    setHeader('x-localdrop-app-version', senderAppVersionProvider?.call());
    final activePort = senderActivePortProvider?.call();
    if (activePort != null && activePort > 0) {
      request.headers.set('x-localdrop-active-port', '$activePort');
    }
    final securePort = senderSecurePortProvider?.call();
    if (securePort != null && securePort > 0) {
      request.headers.set('x-localdrop-secure-port', '$securePort');
    }
  }

  Uri _uri(
    _TransferTarget target,
    String path, {
    Map<String, String>? queryParameters,
  }) {
    return Uri(
      scheme: 'https',
      host: target.address,
      port: target.port,
      path: path,
      queryParameters: queryParameters,
    );
  }

  bool _recipientSupportsHttpsTransfer(DeviceProfile recipient) {
    final securePort = recipient.securePort ?? recipient.activePort;
    return securePort > 0 &&
        recipient.certFingerprint.trim().isNotEmpty &&
        (recipient.capabilities.contains(
              NetworkConstants.protocolCapabilityHttpsTransfer,
            ) ||
            recipient.protocolVersion == NetworkConstants.protocolVersion ||
            recipient.discoverySources.any(
              (source) =>
                  (source.securePort ?? source.activePort) > 0 &&
                  source.ipAddresses.isNotEmpty,
            ));
  }

  HttpClient _buildClientForTarget(
    _TransferTarget target, {
    Duration connectionTimeout = const Duration(seconds: 8),
    Duration idleTimeout = const Duration(seconds: 20),
    bool allowUnknownCertificate = false,
    void Function(String fingerprint)? onCertificateFingerprint,
  }) {
    final client = _buildClient(
      connectionTimeout: connectionTimeout,
      idleTimeout: idleTimeout,
    );
    if (!target.useTls) {
      return client;
    }
    final expectedFingerprint = target.expectedFingerprint?.trim() ?? '';
    client.badCertificateCallback = (certificate, host, port) {
      final fingerprint = sha256
          .convert(certificate.der)
          .toString()
          .toUpperCase();
      onCertificateFingerprint?.call(fingerprint);
      if (expectedFingerprint.isEmpty) {
        return allowUnknownCertificate;
      }
      return fingerprint == expectedFingerprint.toUpperCase();
    };
    return client;
  }

  String _addressFamily(String address) {
    final parsed = InternetAddress.tryParse(address);
    if (parsed?.type == InternetAddressType.IPv6) {
      return 'ipv6';
    }
    return 'ipv4';
  }

  int _preferredAddressWeight(String preferredFamily, String address) {
    return _addressFamily(address) == preferredFamily ? 0 : 1;
  }

  int _addressFamilyPriority(String address) {
    return _addressFamily(address) == 'ipv4' ? 0 : 1;
  }

  Stream<List<int>> _progressStream(
    Stream<List<int>> source, {
    required bool Function() isCanceled,
    required void Function(int chunkSize) onChunk,
  }) async* {
    await for (final chunk in source) {
      if (isCanceled()) {
        throw const _TransferCanceledException();
      }
      onChunk(chunk.length);
      yield chunk;
    }
  }

  Stream<List<int>> _fileChunks(File file) async* {
    final input = await file.open();
    try {
      while (true) {
        final chunk = await input.read(NetworkConstants.transferChunkSizeBytes);
        if (chunk.isEmpty) {
          break;
        }
        yield chunk;
      }
    } finally {
      await input.close();
    }
  }

  void _trace(String message, {Map<String, Object?>? data}) {
    onTrace?.call(message, data: data);
  }
}

class _TransferTarget {
  const _TransferTarget({
    required this.address,
    required this.port,
    required this.useTls,
    this.expectedFingerprint,
  });

  final String address;
  final int port;
  final bool useTls;
  final String? expectedFingerprint;

  String get key => '${useTls ? 'https' : 'http'}://$address:$port';
}

class _FailureDetails {
  const _FailureDetails({required this.terminalReason, required this.message});

  final TransferTerminalReason terminalReason;
  final String message;
}

class _ProbeFailure {
  const _ProbeFailure({required this.target, required this.error});

  final _TransferTarget target;
  final Object error;
}

class _TransferCanceledException implements Exception {
  const _TransferCanceledException();
}

class _TransferStageException implements Exception {
  const _TransferStageException(
    this.stage,
    this.message, {
    required this.terminalReason,
  });

  final TransferStage stage;
  final String message;
  final TransferTerminalReason terminalReason;

  @override
  String toString() => message;
}

class _TransferHttpException implements Exception {
  const _TransferHttpException({
    required this.statusCode,
    required this.message,
    required this.body,
    required this.uri,
    required this.retryable,
  });

  final int statusCode;
  final String message;
  final String body;
  final Uri uri;
  final bool retryable;

  String get messageFromBody {
    if (body.trim().isEmpty) {
      return message;
    }
    try {
      final json = jsonDecode(body) as Map<String, dynamic>;
      final error = json['error'] as String?;
      final reason = json['reason'] as String?;
      if (reason != null && reason.trim().isNotEmpty) {
        return reason;
      }
      if (error != null && error.trim().isNotEmpty) {
        return error;
      }
    } catch (_) {
      // Fall through to the raw body below.
    }
    return '$message: ${body.trim()}';
  }

  @override
  String toString() {
    return '$message ($statusCode) ${uri.toString()} ${body.trim()}'.trim();
  }
}
