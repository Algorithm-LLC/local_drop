import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../core/constants/network_constants.dart';
import '../models/transfer_diagnostics_snapshot.dart';
import '../models/transfer_models.dart';
import 'local_identity_service.dart';

typedef IncomingSessionHandler = void Function(IncomingTransferSession session);
typedef TransferProgressHandler = void Function(TransferProgress progress);
typedef TransferRecordHandler = void Function(TransferRecord record);
typedef TransferTraceHandler =
    void Function(String message, {Map<String, Object?>? data});

class TransferServer {
  TransferServer({
    required this.onIncomingSessionChanged,
    required this.onProgress,
    required this.onRecord,
    required this.onDiagnostics,
    required this.resolveSaveDirectory,
    required this.nicknameProvider,
    this.appVersion = '1.0.0',
    Duration? approvalTimeout,
    Duration? incomingSessionCleanupInterval,
    Duration? terminalSessionRetention,
    Duration? acceptedSessionInactivity,
  }) : _approvalTimeout = approvalTimeout ?? NetworkConstants.approvalTimeout,
       _incomingSessionCleanupInterval =
           incomingSessionCleanupInterval ??
           NetworkConstants.incomingSessionCleanupInterval,
       _terminalSessionRetention =
           terminalSessionRetention ?? const Duration(minutes: 2),
       _acceptedSessionInactivity =
           acceptedSessionInactivity ?? const Duration(minutes: 5);

  IncomingSessionHandler onIncomingSessionChanged;
  TransferProgressHandler onProgress;
  TransferRecordHandler onRecord;
  void Function(TransferDiagnosticsSnapshot snapshot) onDiagnostics;
  TransferTraceHandler? onTrace;
  Future<String> Function() resolveSaveDirectory;
  String Function() nicknameProvider;
  String appVersion;
  final Duration _approvalTimeout;
  final Duration _incomingSessionCleanupInterval;
  final Duration _terminalSessionRetention;
  final Duration _acceptedSessionInactivity;

  final Map<String, _IncomingSession> _sessions = <String, _IncomingSession>{};
  final List<HttpServer> _servers = <HttpServer>[];
  final List<HttpServer> _secureServers = <HttpServer>[];
  int? _port;
  int? _securePort;
  bool _primaryPortUsesTls = false;
  Timer? _cleanupTimer;
  LocalIdentity? _identity;

  int? get port => _port;
  int? get securePort => _securePort;
  bool get hasIpv4Listener =>
      _servers.any((server) => server.address.type == InternetAddressType.IPv4);
  bool get hasIpv6Listener =>
      _servers.any((server) => server.address.type == InternetAddressType.IPv6);
  bool get hasSecureIpv4Listener =>
      (_primaryPortUsesTls &&
          _servers.any(
            (server) => server.address.type == InternetAddressType.IPv4,
          )) ||
      _secureServers.any((server) => server.address.type == InternetAddressType.IPv4);
  bool get hasSecureIpv6Listener =>
      (_primaryPortUsesTls &&
          _servers.any(
            (server) => server.address.type == InternetAddressType.IPv6,
          )) ||
      _secureServers.any((server) => server.address.type == InternetAddressType.IPv6);
  bool get hasSecureListener => _primaryPortUsesTls || _secureServers.isNotEmpty;

  Future<void> start({
    required int port,
    required LocalIdentity identity,
  }) async {
    await stop();
    _identity = identity;
    final servers = await _bindServers(port: port, identity: identity);
    _servers
      ..clear()
      ..addAll(servers.httpServers);
    _secureServers
      ..clear()
      ..addAll(servers.secureServers);
    _primaryPortUsesTls = servers.primaryUsesTls;
    if (!hasIpv4Listener) {
      await stop();
      throw StateError(
        'Transfer server bound without an IPv4 listener on port $port.',
      );
    }
    _port = servers.httpPort;
    _securePort = servers.securePort;
    for (final server in _servers) {
      server.listen(_handleRequest, onError: _handleServerError);
    }
    for (final server in _secureServers) {
      server.listen(_handleRequest, onError: _handleServerError);
    }
    try {
      await _verifyLocalHealth(identity);
    } catch (error) {
      await stop();
      rethrow;
    }
    _cleanupTimer = Timer.periodic(
      _incomingSessionCleanupInterval,
      (_) => unawaited(_cleanupSessions()),
    );
  }

  Future<void> stop() async {
    _cleanupTimer?.cancel();
    _cleanupTimer = null;
    for (final server in _servers) {
      await server.close(force: true);
    }
    for (final server in _secureServers) {
      await server.close(force: true);
    }
    _servers.clear();
    _secureServers.clear();
    _port = null;
    _securePort = null;
    _primaryPortUsesTls = false;
    _sessions.clear();
    _identity = null;
  }

  Future<void> acceptIncoming(String transferId) async {
    final session = _sessions[transferId];
    if (session == null ||
        session.decisionStatus != TransferDecisionStatus.pending) {
      return;
    }

    final saveRoot = Directory(await resolveSaveDirectory());
    if (!await saveRoot.exists()) {
      await saveRoot.create(recursive: true);
    }

    session
      ..decisionStatus = TransferDecisionStatus.accepted
      ..transferDirectory = saveRoot
      ..terminalReason = null
      ..reason = null
      ..retireAt = null
      ..touch();
    _emitSessionUpdate(session);
    _emitIncomingStatus(
      session,
      status: TransferStatus.approved,
      stage: TransferStage.awaitingApproval,
    );
    _emitDiagnostics(
      session,
      stage: TransferStage.awaitingApproval,
      decisionStatus: TransferDecisionStatus.accepted,
    );
  }

  Future<void> declineIncoming(
    String transferId, {
    String reason = 'Receiver declined',
  }) async {
    final session = _sessions[transferId];
    if (session == null ||
        session.decisionStatus != TransferDecisionStatus.pending) {
      return;
    }
    session
      ..decisionStatus = TransferDecisionStatus.declined
      ..terminalReason = TransferTerminalReason.declined
      ..reason = reason
      ..retireAt = DateTime.now().add(_terminalSessionRetention)
      ..touch();
    _emitSessionUpdate(session);
    _emitDiagnostics(
      session,
      stage: TransferStage.failed,
      decisionStatus: TransferDecisionStatus.declined,
      terminalReason: TransferTerminalReason.declined,
      errorMessage: reason,
    );
  }

  Future<void> _handleRequest(HttpRequest request) async {
    final remoteAddress = request.connectionInfo?.remoteAddress.address;
    final remotePort = request.connectionInfo?.remotePort;
    final peerHint = _requestPeerHint(request);
    _trace(
      'Incoming transfer request',
      data: <String, Object?>{
        'method': request.method,
        'path': request.uri.path,
        'query': request.uri.hasQuery ? request.uri.query : '',
        'remoteAddress': remoteAddress,
        'remotePort': remotePort,
        ...peerHint,
      },
    );
    try {
      final segments = request.uri.pathSegments;
      if (request.method == 'GET' &&
          segments.length == 3 &&
          segments[0] == 'v1' &&
          segments[1] == 'transfer' &&
          segments[2] == 'health') {
        await _handleHealth(request);
        return;
      }

      if (request.method == 'POST' &&
          segments.length == 3 &&
          segments[0] == 'v1' &&
          segments[1] == 'transfer' &&
          segments[2] == 'offer') {
        await _handleOffer(request);
        return;
      }

      if (request.method == 'GET' &&
          segments.length == 4 &&
          segments[0] == 'v1' &&
          segments[1] == 'transfer' &&
          segments[3] == 'decision') {
        await _handleDecision(request, segments[2]);
        return;
      }

      if (request.method == 'PUT' &&
          segments.length == 4 &&
          segments[0] == 'v1' &&
          segments[1] == 'transfer' &&
          segments[3] == 'data') {
        await _handleData(request, segments[2]);
        return;
      }

      if (request.method == 'POST' &&
          segments.length == 4 &&
          segments[0] == 'v1' &&
          segments[1] == 'transfer' &&
          segments[3] == 'complete') {
        await _handleComplete(request, segments[2]);
        return;
      }

      await _respondJson(
        request.response,
        HttpStatus.notFound,
        <String, dynamic>{'error': 'Not found'},
      );
    } catch (error) {
      _trace(
        'Transfer request failed',
        data: <String, Object?>{
          'method': request.method,
          'path': request.uri.path,
          'remoteAddress': remoteAddress,
          'remotePort': remotePort,
          'error': error.toString(),
        },
      );
      await _respondJson(
        request.response,
        HttpStatus.internalServerError,
        <String, dynamic>{'error': error.toString()},
      );
    }
  }

  Future<void> _handleHealth(HttpRequest request) async {
    final identity = _identity;
    _trace(
      'Served transfer health',
      data: <String, Object?>{
        'remoteAddress': request.connectionInfo?.remoteAddress.address,
        'remotePort': request.connectionInfo?.remotePort,
        'port': _port,
        'securePort': _securePort,
        ..._requestPeerHint(request),
      },
    );
    await _respondJson(request.response, HttpStatus.ok, <String, dynamic>{
      'status': 'ok',
      'appVersion': appVersion,
      'protocolVersion': NetworkConstants.protocolVersion,
      'capabilities': _serverCapabilities,
      'activePort': _port,
      if (_securePort != null) 'securePort': _securePort,
      'nickname': nicknameProvider(),
      'deviceId': identity?.deviceId ?? '',
      'platform': Platform.operatingSystem,
      'certFingerprint': identity?.fingerprint ?? '',
      'preferredAddressFamily': 'ipv4',
    });
  }

  Future<void> _handleOffer(HttpRequest request) async {
    final payload = await _readJson(request);
    final offer = TransferOffer.fromJson(payload);
    final remoteIp = request.connectionInfo?.remoteAddress.address ?? 'unknown';

    if (offer.protocolVersion != NetworkConstants.protocolVersion) {
      await _respondJson(
        request.response,
        HttpStatus.conflict,
        TransferOfferAck(
          transferId: offer.transferId,
          status: 'incompatible',
          expiresAt: DateTime.now().toUtc(),
          receiverAppVersion: appVersion,
          receiverProtocolVersion: NetworkConstants.protocolVersion,
          receiverCapabilities: _serverCapabilities,
          reason: 'Incompatible protocol. Update both devices.',
        ).toJson(),
      );
      return;
    }

    final existing = _sessions[offer.transferId];
    if (existing != null) {
      existing.touch();
      _emitDiagnostics(
        existing,
        stage: TransferStage.offerQueued,
        offerStatus: existing.decisionStatus == TransferDecisionStatus.pending
            ? 'queued'
            : existing.decisionStatus.name,
      );
      await _respondJson(
        request.response,
        HttpStatus.accepted,
        _offerAckFor(existing).toJson(),
      );
      return;
    }

    final now = DateTime.now();
    final session = _IncomingSession(
      offer: offer,
      receivedAt: now,
      peerIp: remoteIp,
      expiresAt: now.add(_approvalTimeout),
    );
    _sessions[offer.transferId] = session;
    _emitSessionUpdate(session);
    _emitDiagnostics(
      session,
      stage: TransferStage.offerQueued,
      offerStatus: 'queued',
    );

    await _respondJson(
      request.response,
      HttpStatus.accepted,
      _offerAckFor(session).toJson(),
    );
  }

  Future<void> _handleDecision(HttpRequest request, String transferId) async {
    final session = _sessions[transferId];
    if (session == null) {
      await _respondJson(
        request.response,
        HttpStatus.notFound,
        <String, dynamic>{'error': 'Unknown transfer'},
      );
      return;
    }

    session.touch();
    _emitDiagnostics(
      session,
      stage: session.decisionStatus == TransferDecisionStatus.accepted
          ? TransferStage.awaitingApproval
          : TransferStage.offerQueued,
      decisionStatus: session.decisionStatus,
      lastHttpRoute: '/v1/transfer/$transferId/decision',
      lastHttpStatusCode: HttpStatus.ok,
    );
    await _respondJson(
      request.response,
      HttpStatus.ok,
      TransferDecisionSnapshot(
        transferId: transferId,
        status: session.decisionStatus,
        expiresAt: session.expiresAt,
        reason: session.reason,
      ).toJson(),
    );
  }

  Future<void> _handleData(HttpRequest request, String transferId) async {
    final session = _sessions[transferId];
    if (session == null) {
      await _respondJson(
        request.response,
        HttpStatus.notFound,
        <String, dynamic>{'error': 'Unknown transfer'},
      );
      return;
    }
    if (session.decisionStatus != TransferDecisionStatus.accepted ||
        session.transferDirectory == null) {
      await _respondJson(
        request.response,
        HttpStatus.conflict,
        <String, dynamic>{'error': 'Transfer not accepted yet'},
      );
      return;
    }

    final itemId = request.uri.queryParameters['itemId'];
    if (itemId == null || itemId.isEmpty) {
      await _respondJson(
        request.response,
        HttpStatus.badRequest,
        <String, dynamic>{'error': 'Missing itemId'},
      );
      return;
    }

    final item = session.offer.items.cast<TransferItem?>().firstWhere(
      (candidate) => candidate?.id == itemId,
      orElse: () => null,
    );
    if (item == null) {
      await _respondJson(
        request.response,
        HttpStatus.badRequest,
        <String, dynamic>{'error': 'Unknown item'},
      );
      return;
    }

    try {
      if (item.isText) {
        final bytes = await request.expand((chunk) => chunk).toList();
        final checksum = sha256.convert(bytes).toString().toUpperCase();
        if (checksum != item.checksumSha256.toUpperCase()) {
          throw const _IncomingTransferException(
            TransferTerminalReason.integrityCheckFailed,
            'Checksum mismatch',
          );
        }

        final text = utf8.decode(bytes, allowMalformed: true);
        final outputPath = _incomingResolvedOutputPath(session, item);
        await File(outputPath).writeAsString(text, flush: true);
        session
          ..receivedBytes += bytes.length
          ..receivedPathByItemId[item.id] = outputPath
          ..textPayloads[item.id] = text
          ..touch();
      } else {
        final outputPath = _incomingPayloadPath(session, item);
        final outputFile = File(outputPath);
        final sink = outputFile.openWrite();
        var receivedBytes = 0;
        try {
          await for (final chunk in request) {
            sink.add(chunk);
            receivedBytes += chunk.length;
            session
              ..receivedBytes += chunk.length
              ..touch();
            _emitIncomingStatus(
              session,
              status: TransferStatus.inProgress,
              stage: TransferStage.uploading,
            );
          }
        } finally {
          await sink.flush();
          await sink.close();
        }

        final digest = await _sha256File(outputFile);
        if (digest != item.checksumSha256.toUpperCase()) {
          try {
            await outputFile.delete();
          } catch (_) {
            // Ignore cleanup failures.
          }
          throw const _IncomingTransferException(
            TransferTerminalReason.integrityCheckFailed,
            'Checksum mismatch',
          );
        }

        session
          ..receivedPathByItemId[item.id] = outputPath
          ..receivedItemSizes[item.id] = receivedBytes
          ..touch();
      }

      _emitIncomingStatus(
        session,
        status: TransferStatus.inProgress,
        stage: TransferStage.uploading,
      );
      _emitDiagnostics(
        session,
        stage: TransferStage.uploading,
        uploadStatus: item.name,
        lastHttpRoute: '/v1/transfer/$transferId/data',
        lastHttpStatusCode: HttpStatus.ok,
      );
      await _respondJson(request.response, HttpStatus.ok, <String, dynamic>{
        'ok': true,
      });
    } on _IncomingTransferException catch (error) {
      session
        ..terminalReason = error.reason
        ..reason = error.message
        ..retireAt = DateTime.now().add(_terminalSessionRetention)
        ..touch();
      _emitSessionUpdate(session);
      _emitDiagnostics(
        session,
        stage: TransferStage.failed,
        terminalReason: error.reason,
        errorMessage: error.message,
      );
      await _respondJson(
        request.response,
        HttpStatus.conflict,
        <String, dynamic>{'error': error.message},
      );
    }
  }

  Future<void> _handleComplete(
    HttpRequest request,
    String transferIdFromPath,
  ) async {
    final payload = await _readJson(request);
    final transferId = payload['transferId'] as String? ?? transferIdFromPath;
    final session = _sessions[transferIdFromPath];
    if (transferId.isEmpty || session == null) {
      await _respondJson(
        request.response,
        HttpStatus.notFound,
        <String, dynamic>{'error': 'Unknown transfer'},
      );
      return;
    }
    if (session.decisionStatus != TransferDecisionStatus.accepted ||
        session.transferDirectory == null) {
      await _respondJson(
        request.response,
        HttpStatus.conflict,
        <String, dynamic>{'error': 'Transfer not accepted yet'},
      );
      return;
    }

    try {
      for (final item in session.offer.items) {
        if (!session.receivedPathByItemId.containsKey(item.id)) {
          throw const _IncomingTransferException(
            TransferTerminalReason.uploadFailed,
            'Missing item payload',
          );
        }
        if (item.type == TransferPayloadType.folder) {
          final zipPath = session.receivedPathByItemId[item.id]!;
          final extractPath = _incomingResolvedOutputPath(session, item);
          final extractDir = await _extractIncomingFolder(
            zipPath: zipPath,
            saveRoot: session.transferDirectory!,
            targetPath: extractPath,
            folderName: item.displayName,
            itemId: item.id,
          );
          if (!await extractDir.exists()) {
            throw const _IncomingTransferException(
              TransferTerminalReason.uploadFailed,
              'Folder extraction failed',
            );
          }
          try {
            await File(zipPath).delete();
          } catch (_) {
            // Ignore cleanup failures for the temporary uploaded archive.
          }
          session
            ..receivedPathByItemId[item.id] = extractPath
            ..receivedItemSizes[item.id] = await _directorySize(extractDir);
        }
      }

      final completedAt = DateTime.now();
      _emitIncomingStatus(
        session,
        status: TransferStatus.completed,
        stage: TransferStage.completing,
        updatedAt: completedAt,
      );
      _emitDiagnostics(
        session,
        stage: TransferStage.completing,
        uploadStatus: 'completed',
        lastHttpRoute: '/v1/transfer/$transferId/complete',
        lastHttpStatusCode: HttpStatus.ok,
      );
      onRecord(
        TransferRecord(
          transferId: transferId,
          peerDeviceId: session.offer.senderDeviceId,
          peerNickname: session.offer.senderNickname,
          isIncoming: true,
          items: _completedIncomingRecordItems(session),
          status: TransferStatus.completed,
          totalBytes: session.offer.totalBytes,
          transferredBytes: session.receivedBytes,
          startedAt: session.receivedAt,
          endedAt: completedAt,
          stage: TransferStage.completing,
        ),
      );

      session
        ..touch()
        ..retireAt = DateTime.now().add(_terminalSessionRetention);
      await _respondJson(request.response, HttpStatus.ok, <String, dynamic>{
        'transferId': transferId,
        'status': 'completed',
      });
    } on _IncomingTransferException catch (error) {
      session
        ..terminalReason = error.reason
        ..reason = error.message
        ..retireAt = DateTime.now().add(_terminalSessionRetention)
        ..touch();
      _emitSessionUpdate(session);
      _emitDiagnostics(
        session,
        stage: TransferStage.failed,
        terminalReason: error.reason,
        errorMessage: error.message,
      );
      await _respondJson(
        request.response,
        HttpStatus.conflict,
        <String, dynamic>{'error': error.message},
      );
    }
  }

  Future<_BoundTransferServers> _bindServers({
    required int port,
    required LocalIdentity identity,
  }) async {
    final servers = <HttpServer>[];
    Object? ipv4Error;
    Object? ipv6Error;

    try {
      servers.add(
        await HttpServer.bindSecure(
          InternetAddress.anyIPv4,
          port,
          identity.buildServerContext(),
          shared: false,
        ),
      );
    } catch (error) {
      ipv4Error = error;
    }

    try {
      servers.add(
        await HttpServer.bindSecure(
          InternetAddress.anyIPv6,
          port,
          identity.buildServerContext(),
          shared: false,
          v6Only: true,
        ),
      );
    } catch (error) {
      ipv6Error = error;
    }

    if (servers.isEmpty) {
      throw StateError(
        'Failed to bind transfer server: IPv4=$ipv4Error / IPv6=$ipv6Error',
      );
    }

    return _BoundTransferServers(
      httpPort: port,
      httpServers: servers,
      securePort: port,
      secureServers: const <HttpServer>[],
      primaryUsesTls: true,
    );
  }

  Map<String, Object?> _requestPeerHint(HttpRequest request) {
    String? headerValue(String name) {
      final values = request.headers[name];
      if (values == null || values.isEmpty) {
        return null;
      }
      final trimmed = values.first.trim();
      return trimmed.isEmpty ? null : trimmed;
    }

    final activePort = int.tryParse(
      headerValue('x-localdrop-active-port') ?? '',
    );
    final securePort = int.tryParse(
      headerValue('x-localdrop-secure-port') ?? '',
    );
    return <String, Object?>{
      'peerDeviceId': headerValue('x-localdrop-device-id'),
      'peerNickname': headerValue('x-localdrop-nickname'),
      'peerFingerprint': headerValue('x-localdrop-cert-fingerprint'),
      'peerPlatform': headerValue('x-localdrop-platform'),
      'peerAppVersion': headerValue('x-localdrop-app-version'),
      'peerActivePort': activePort,
      'peerSecurePort': securePort,
    };
  }

  List<String> get _serverCapabilities => <String>[
    NetworkConstants.protocolCapabilityMdns,
    NetworkConstants.protocolCapabilityQueuedApproval,
    if (hasSecureListener) NetworkConstants.protocolCapabilityHttpsTransfer,
  ];

  Future<void> _verifyLocalHealth(LocalIdentity identity) async {
    final port = _port;
    if (port == null) {
      throw StateError('Transfer server port is not available for self-check.');
    }

    await _verifyHealthEndpoint(
      identity: identity,
      port: port,
      useTls: _primaryPortUsesTls,
      hasIpv4Listener: hasIpv4Listener,
      hasIpv6Listener: hasIpv6Listener,
    );

    final securePort = _securePort;
    if (securePort == null || securePort == port) {
      return;
    }

    await _verifyHealthEndpoint(
      identity: identity,
      port: securePort,
      useTls: true,
      hasIpv4Listener: hasSecureIpv4Listener,
      hasIpv6Listener: hasSecureIpv6Listener,
    );
  }

  Future<void> _verifyHealthEndpoint({
    required LocalIdentity identity,
    required int port,
    required bool useTls,
    required bool hasIpv4Listener,
    required bool hasIpv6Listener,
  }) async {
    final targets = <InternetAddress>[
      if (hasIpv4Listener) InternetAddress.loopbackIPv4,
      if (hasIpv6Listener) InternetAddress.loopbackIPv6,
    ];
    Object? lastError;
    for (final address in targets) {
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 3);
      if (useTls) {
        client.badCertificateCallback = (certificate, host, port) {
          final fingerprint = sha256
              .convert(certificate.der)
              .toString()
              .toUpperCase();
          return fingerprint == identity.fingerprint;
        };
      }
      try {
        final uri = Uri(
          scheme: useTls ? 'https' : 'http',
          host: address.address,
          port: port,
          path: '/v1/transfer/health',
        );
        final request = await client.getUrl(uri);
        final response = await request.close();
        await utf8.decoder.bind(response).join();
        if (response.statusCode != HttpStatus.ok) {
          throw StateError(
            'Unexpected status ${response.statusCode} from local health check.',
          );
        }
        _trace(
          'Local transfer health check succeeded',
          data: <String, Object?>{
            'address': address.address,
            'port': port,
            'scheme': useTls ? 'https' : 'http',
            'addressFamily': address.type == InternetAddressType.IPv6
                ? 'ipv6'
                : 'ipv4',
            'fingerprint': identity.fingerprint,
          },
        );
        return;
      } catch (error) {
        lastError = error;
        _trace(
          'Local transfer health check failed',
          data: <String, Object?>{
            'address': address.address,
            'port': port,
            'scheme': useTls ? 'https' : 'http',
            'addressFamily': address.type == InternetAddressType.IPv6
                ? 'ipv6'
                : 'ipv4',
            'fingerprint': identity.fingerprint,
            'error': error.toString(),
          },
        );
      } finally {
        client.close(force: true);
      }
    }

    throw StateError(
      'Transfer server failed local ${useTls ? 'https' : 'http'} health check on port $port: $lastError',
    );
  }

  Future<void> _cleanupSessions() async {
    final now = DateTime.now();
    final expiredIds = <String>[];
    for (final entry in _sessions.entries) {
      final session = entry.value;
      if (session.decisionStatus == TransferDecisionStatus.pending &&
          now.isAfter(session.expiresAt)) {
        session
          ..decisionStatus = TransferDecisionStatus.expired
          ..terminalReason = TransferTerminalReason.approvalExpired
          ..reason = 'Approval expired'
          ..touch()
          ..retireAt = now.add(_terminalSessionRetention);
        _emitSessionUpdate(session);
        _emitDiagnostics(
          session,
          stage: TransferStage.failed,
          decisionStatus: TransferDecisionStatus.expired,
          terminalReason: TransferTerminalReason.approvalExpired,
          errorMessage: 'Approval expired',
        );
      }

      if (session.decisionStatus == TransferDecisionStatus.accepted &&
          now.difference(session.updatedAt) > _acceptedSessionInactivity) {
        session
          ..decisionStatus = TransferDecisionStatus.expired
          ..terminalReason = TransferTerminalReason.uploadFailed
          ..reason = 'Transfer session timed out after acceptance'
          ..touch()
          ..retireAt = now.add(_terminalSessionRetention);
        _emitSessionUpdate(session);
        _emitDiagnostics(
          session,
          stage: TransferStage.failed,
          decisionStatus: TransferDecisionStatus.expired,
          terminalReason: TransferTerminalReason.uploadFailed,
          errorMessage: 'Transfer session timed out after acceptance',
        );
      }

      final retireAt = session.retireAt;
      if (retireAt != null && now.isAfter(retireAt)) {
        expiredIds.add(entry.key);
      }
    }

    for (final transferId in expiredIds) {
      _sessions.remove(transferId);
    }
  }

  TransferOfferAck _offerAckFor(_IncomingSession session) {
    final status = session.decisionStatus == TransferDecisionStatus.pending
        ? 'queued'
        : session.decisionStatus.name;
    return TransferOfferAck(
      transferId: session.offer.transferId,
      status: status,
      expiresAt: session.expiresAt,
      receiverAppVersion: appVersion,
      receiverProtocolVersion: NetworkConstants.protocolVersion,
      receiverCapabilities: _serverCapabilities,
      reason: session.reason,
    );
  }

  void _emitSessionUpdate(_IncomingSession session) {
    onIncomingSessionChanged(
      IncomingTransferSession(
        transferId: session.offer.transferId,
        senderDeviceId: session.offer.senderDeviceId,
        senderNickname: session.offer.senderNickname,
        senderFingerprint: session.offer.senderFingerprint,
        senderAppVersion: session.offer.senderAppVersion,
        protocolVersion: session.offer.protocolVersion,
        items: session.offer.items
            .map(_presentIncomingItem)
            .toList(growable: false),
        remoteAddress: session.peerIp,
        receivedAt: session.receivedAt,
        expiresAt: session.expiresAt,
        status: session.decisionStatus,
        terminalReason: session.terminalReason,
        reason: session.reason,
      ),
    );
  }

  void _emitIncomingStatus(
    _IncomingSession session, {
    required TransferStatus status,
    required TransferStage stage,
    DateTime? updatedAt,
    String? errorMessage,
  }) {
    onProgress(
      TransferProgress(
        transferId: session.offer.transferId,
        peerDeviceId: session.offer.senderDeviceId,
        peerNickname: session.offer.senderNickname,
        isIncoming: true,
        status: status,
        totalBytes: session.offer.totalBytes,
        transferredBytes: session.receivedBytes,
        startedAt: session.receivedAt,
        updatedAt: updatedAt ?? DateTime.now(),
        stage: stage,
        terminalReason: session.terminalReason,
        errorMessage: errorMessage,
      ),
    );
  }

  void _emitDiagnostics(
    _IncomingSession session, {
    required TransferStage stage,
    TransferDecisionStatus? decisionStatus,
    String? offerStatus,
    String? uploadStatus,
    TransferTerminalReason? terminalReason,
    String? errorMessage,
    String? lastHttpRoute,
    int? lastHttpStatusCode,
  }) {
    onDiagnostics(
      TransferDiagnosticsSnapshot(
        contextId: session.offer.transferId,
        peerDeviceId: session.offer.senderDeviceId,
        peerNickname: session.offer.senderNickname,
        isIncoming: true,
        stage: stage,
        updatedAt: DateTime.now(),
        selectedAddress: session.peerIp,
        selectedPort: _port,
        addressFamily:
            InternetAddress.tryParse(session.peerIp)?.type ==
                InternetAddressType.IPv6
            ? 'ipv6'
            : 'ipv4',
        lastHttpRoute: lastHttpRoute,
        lastHttpStatusCode: lastHttpStatusCode,
        offerStatus: offerStatus,
        decisionStatus: decisionStatus,
        uploadStatus: uploadStatus,
        terminalReason: terminalReason,
        errorMessage: errorMessage,
      ),
    );
  }

  Future<Map<String, dynamic>> _readJson(HttpRequest request) async {
    final text = await utf8.decoder.bind(request).join();
    if (text.trim().isEmpty) {
      return <String, dynamic>{};
    }
    return jsonDecode(text) as Map<String, dynamic>;
  }

  Future<void> _respondJson(
    HttpResponse response,
    int statusCode,
    Map<String, dynamic> payload,
  ) async {
    response.statusCode = statusCode;
    response.headers.contentType = ContentType.json;
    response.write(jsonEncode(payload));
    await response.close();
  }

  Future<String> _sha256File(File file) async {
    final digest = await sha256.bind(file.openRead()).first;
    return digest.toString().toUpperCase();
  }

  String _incomingResolvedOutputPath(_IncomingSession session, TransferItem item) {
    final existingPath = session.resolvedOutputPathByItemId[item.id];
    if (existingPath != null) {
      return existingPath;
    }

    final preferredPath = p.join(
      session.transferDirectory!.path,
      item.type == TransferPayloadType.folder ? item.displayName : item.name,
    );
    final resolvedPath = _dedupeIncomingPath(
      preferredPath,
      reservedPaths: session.reservedResolvedOutputPaths,
    );
    session.resolvedOutputPathByItemId[item.id] = resolvedPath;
    session.reservedResolvedOutputPaths.add(p.normalize(resolvedPath));
    return resolvedPath;
  }

  String _dedupeIncomingPath(
    String preferredPath, {
    required Set<String> reservedPaths,
  }) {
    final normalizedPreferredPath = p.normalize(preferredPath);
    final parent = p.dirname(normalizedPreferredPath);
    final basename = p.basename(normalizedPreferredPath);
    final extension = p.extension(basename);
    final stem =
        extension.isEmpty
            ? basename
            : basename.substring(0, basename.length - extension.length);

    var suffix = 0;
    while (true) {
      final candidateName =
          suffix == 0 ? basename : '$stem ($suffix)$extension';
      final candidatePath = p.join(parent, candidateName);
      final normalizedCandidatePath = p.normalize(candidatePath);
      final isReserved = reservedPaths.contains(normalizedCandidatePath);
      final alreadyExists =
          FileSystemEntity.typeSync(
            normalizedCandidatePath,
            followLinks: false,
          ) !=
          FileSystemEntityType.notFound;
      if (!isReserved && !alreadyExists) {
        return normalizedCandidatePath;
      }
      suffix += 1;
    }
  }

  String _incomingPayloadPath(_IncomingSession session, TransferItem item) {
    if (item.type != TransferPayloadType.folder) {
      return _incomingResolvedOutputPath(session, item);
    }
    return p.join(session.transferDirectory!.path, '.localdrop_${item.id}.zip');
  }

  Future<Directory> _extractIncomingFolder({
    required String zipPath,
    required Directory saveRoot,
    required String targetPath,
    required String folderName,
    required String itemId,
  }) async {
    final normalizedTargetPath = p.normalize(targetPath);
    final defaultPath = p.join(saveRoot.path, folderName);
    final normalizedDefaultPath = p.normalize(defaultPath);
    if (normalizedTargetPath == normalizedDefaultPath) {
      extractFileToDisk(zipPath, saveRoot.path);
      return Directory(normalizedTargetPath);
    }

    final stagingDir = Directory(
      p.join(saveRoot.path, '.localdrop_extract_$itemId'),
    );
    if (await stagingDir.exists()) {
      await stagingDir.delete(recursive: true);
    }
    await stagingDir.create(recursive: true);
    try {
      extractFileToDisk(zipPath, stagingDir.path);
      final stagedExtractDir = Directory(p.join(stagingDir.path, folderName));
      if (!await stagedExtractDir.exists()) {
        throw const _IncomingTransferException(
          TransferTerminalReason.uploadFailed,
          'Folder extraction failed',
        );
      }
      final movedDir = await stagedExtractDir.rename(normalizedTargetPath);
      return movedDir;
    } finally {
      if (await stagingDir.exists()) {
        try {
          await stagingDir.delete(recursive: true);
        } catch (_) {
          // Ignore cleanup failures for the temporary extraction directory.
        }
      }
    }
  }

  List<TransferItem> _completedIncomingRecordItems(_IncomingSession session) {
    return session.offer.items
        .map((item) => _presentIncomingItem(item, session))
        .toList(growable: false);
  }

  TransferItem _presentIncomingItem(
    TransferItem item, [
    _IncomingSession? session,
  ]) {
    return TransferItem(
      id: item.id,
      type: item.type,
      name: item.displayName,
      sizeBytes: session?.receivedItemSizes[item.id] ?? item.sizeBytes,
      checksumSha256: item.checksumSha256,
      sourcePath: session?.receivedPathByItemId[item.id],
      textContent: item.textContent,
    );
  }

  Future<int> _directorySize(Directory directory) async {
    var total = 0;
    await for (final entity in directory.list(
      recursive: true,
      followLinks: false,
    )) {
      if (entity is! File) {
        continue;
      }
      total += await entity.length();
    }
    return total;
  }

  void _handleServerError(Object error) {
    _trace(
      'Transfer server listener error',
      data: <String, Object?>{'error': error.toString(), 'port': _port},
    );
  }

  void _trace(String message, {Map<String, Object?>? data}) {
    onTrace?.call(message, data: data);
  }
}

class _BoundTransferServers {
  const _BoundTransferServers({
    required this.httpPort,
    required this.httpServers,
    required this.securePort,
    required this.secureServers,
    required this.primaryUsesTls,
  });

  final int httpPort;
  final List<HttpServer> httpServers;
  final int? securePort;
  final List<HttpServer> secureServers;
  final bool primaryUsesTls;
}

class _IncomingSession {
  _IncomingSession({
    required this.offer,
    required this.receivedAt,
    required this.peerIp,
    required this.expiresAt,
  });

  final TransferOffer offer;
  final DateTime receivedAt;
  final String peerIp;
  final DateTime expiresAt;

  TransferDecisionStatus decisionStatus = TransferDecisionStatus.pending;
  TransferTerminalReason? terminalReason;
  String? reason;
  Directory? transferDirectory;
  int receivedBytes = 0;
  DateTime updatedAt = DateTime.now();
  DateTime? retireAt;
  final Map<String, String> receivedPathByItemId = <String, String>{};
  final Map<String, int> receivedItemSizes = <String, int>{};
  final Map<String, String> textPayloads = <String, String>{};
  final Map<String, String> resolvedOutputPathByItemId = <String, String>{};
  final Set<String> reservedResolvedOutputPaths = <String>{};

  void touch() {
    updatedAt = DateTime.now();
  }
}

class _IncomingTransferException implements Exception {
  const _IncomingTransferException(this.reason, this.message);

  final TransferTerminalReason reason;
  final String message;
}
