import Cocoa
import FlutterMacOS
import Darwin

class MainFlutterWindow: NSWindow {
  private let discoveryManager = MacOSNativeDiscoveryManager()

  override func awakeFromNib() {
    minSize = NSSize(width: 330, height: 520)
    setFrameAutosaveName("LocalDropMainWindow")
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    let registrar = flutterViewController.registrar(forPlugin: "LocalDropNetworkBridge")
    let channel = FlutterMethodChannel(
      name: "localdrop/network",
      binaryMessenger: registrar.messenger
    )
    channel.setMethodCallHandler { [weak self] call, result in
      self?.handleMethodCall(call, result: result)
    }

    super.awakeFromNib()
  }

  private func handleMethodCall(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "acquireMulticastLock":
      result(nil)
    case "releaseMulticastLock":
      result(nil)
    case "getPublicDownloadsDirectory":
      result(publicDownloadsDirectory())
    case "activateAppWindow":
      DispatchQueue.main.async { [weak self] in
        NSApp.activate(ignoringOtherApps: true)
        self?.deminiaturize(nil)
        self?.makeKeyAndOrderFront(nil)
        self?.orderFrontRegardless()
        result(nil)
      }
    case "getActiveInterfaces":
      result(activeInterfaceSnapshots())
    case "startNativeDiscovery":
      let args = call.arguments as? [String: Any] ?? [:]
      discoveryManager.start(arguments: args)
      result(nil)
    case "stopNativeDiscovery":
      discoveryManager.stop()
      result(nil)
    case "getNativeDiscoverySnapshot":
      result(discoveryManager.snapshot())
    default:
      result(FlutterMethodNotImplemented)
    }
  }
}

private func publicDownloadsDirectory() -> String? {
  let fileManager = FileManager.default
  if let realHome = posixHomeDirectory() {
    let homeDownloads = URL(fileURLWithPath: realHome, isDirectory: true)
      .appendingPathComponent("Downloads", isDirectory: true)
    var isDirectory: ObjCBool = false
    if fileManager.fileExists(atPath: homeDownloads.path, isDirectory: &isDirectory),
       isDirectory.boolValue {
      return homeDownloads.path
    }
  }

  if let downloadsURL = fileManager.urls(for: .downloadsDirectory, in: .userDomainMask).first {
    return downloadsURL.path
  }

  return nil
}

private func posixHomeDirectory() -> String? {
  guard let passwd = getpwuid(getuid()), let rawHome = passwd.pointee.pw_dir else {
    return nil
  }
  let home = String(cString: rawHome)
  return home.isEmpty ? nil : home
}

private func activeInterfaceSnapshots() -> [[String: Any]] {
  var snapshots: [[String: Any]] = []
  var seen = Set<String>()
  var interfacePointer: UnsafeMutablePointer<ifaddrs>?
  guard getifaddrs(&interfacePointer) == 0, let first = interfacePointer else {
    return []
  }
  defer { freeifaddrs(interfacePointer) }

  var cursor: UnsafeMutablePointer<ifaddrs>? = first
  while let current = cursor {
    let interface = current.pointee
    let flags = Int32(interface.ifa_flags)
    guard (flags & IFF_UP) != 0, (flags & IFF_LOOPBACK) == 0 else {
      cursor = interface.ifa_next
      continue
    }
    guard let addressPointer = interface.ifa_addr,
          addressPointer.pointee.sa_family == UInt8(AF_INET),
          let address = numericHost(from: addressPointer) else {
      cursor = interface.ifa_next
      continue
    }
    if address.hasPrefix("127.") || address.hasPrefix("169.254.") {
      cursor = interface.ifa_next
      continue
    }

    let interfaceName = String(cString: interface.ifa_name)
    let prefixLength = prefixLength(from: interface.ifa_netmask)
    let key = "\(interfaceName)|\(address)|\(prefixLength)"
    if seen.insert(key).inserted {
      snapshots.append([
        "interfaceName": interfaceName,
        "address": address,
        "prefixLength": prefixLength,
      ])
    }
    cursor = interface.ifa_next
  }

  return snapshots
}

private func numericHost(from pointer: UnsafePointer<sockaddr>) -> String? {
  var hostBuffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
  var copy = pointer.pointee
  let copyLength = socklen_t(copy.sa_len)
  let result = withUnsafePointer(to: &copy) { addressPointer in
    addressPointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
      getnameinfo(
        $0,
        copyLength,
        &hostBuffer,
        socklen_t(hostBuffer.count),
        nil,
        0,
        NI_NUMERICHOST
      )
    }
  }
  guard result == 0 else {
    return nil
  }
  return String(cString: hostBuffer)
}

private func prefixLength(from pointer: UnsafeMutablePointer<sockaddr>?) -> Int {
  guard let pointer, let address = numericHost(from: UnsafePointer(pointer)) else {
    return 24
  }
  return address
    .split(separator: ".")
    .compactMap { Int($0) }
    .reduce(0) { partialResult, octet in
      partialResult + UInt8(clamping: octet).nonzeroBitCount
    }
}

final class MacOSNativeDiscoveryManager: NSObject, NetServiceDelegate, NetServiceBrowserDelegate {
  private let serviceType = "_localdrop._tcp."
  private let domain = "local."

  private var localServiceName = ""
  private var localDeviceId = ""
  private var browser: NetServiceBrowser?
  private var publishedService: NetService?
  private var peersByDeviceId: [String: [String: Any]] = [:]
  private var serviceNameToDeviceId: [String: String] = [:]

  private var running = false
  private var advertising = false
  private var browsing = false
  private var lastError: String?
  private var lastPermissionIssue: String?
  private var lastBackendLogMessage: String?
  private var hasSuccessfulBrowse = false

  func start(arguments: [String: Any]) {
    stop()

    let deviceId = (arguments["deviceId"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    let nickname = (arguments["nickname"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    let fingerprint = (arguments["certFingerprint"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    let appVersion = (arguments["appVersion"] as? String) ?? ""
    let protocolVersion = (arguments["protocolVersion"] as? String) ?? ""
    let activePort = (arguments["activePort"] as? NSNumber)?.int32Value ?? 0
    let securePort = (arguments["securePort"] as? NSNumber)?.int32Value ?? 0
    let capabilities = (arguments["capabilities"] as? [Any])?.map { "\($0)" } ?? []

    guard !deviceId.isEmpty, !nickname.isEmpty, !fingerprint.isEmpty, activePort > 0 else {
      lastError = "Apple Bonjour could not start because the discovery payload was incomplete."
      lastBackendLogMessage = lastError
      return
    }

    localDeviceId = deviceId
    localServiceName = buildServiceName(deviceId: deviceId, nickname: nickname)
    lastError = nil
    lastPermissionIssue = nil
    lastBackendLogMessage = "Starting Apple Bonjour advertising and browsing."
    hasSuccessfulBrowse = false

    var txtAttributes: [String: Data] = [
      "id": Data(deviceId.utf8),
      "name": Data(nickname.utf8),
      "plat": Data("macos".utf8),
      "fp": Data(fingerprint.utf8),
      "ver": Data(appVersion.utf8),
      "proto": Data(protocolVersion.utf8),
      "caps": Data(capabilities.joined(separator: ",").utf8),
      "af": Data("ipv4".utf8),
    ]
    if securePort > 0 {
      txtAttributes["spt"] = Data("\(securePort)".utf8)
    }
    let txtRecord = NetService.data(fromTXTRecord: txtAttributes)

    let service = NetService(domain: domain, type: serviceType, name: localServiceName, port: activePort)
    service.delegate = self
    service.setTXTRecord(txtRecord)
    service.publish()
    publishedService = service

    let serviceBrowser = NetServiceBrowser()
    serviceBrowser.delegate = self
    serviceBrowser.searchForServices(ofType: serviceType, inDomain: domain)
    browser = serviceBrowser
  }

  func stop() {
    browser?.delegate = nil
    browser?.stop()
    browser = nil

    publishedService?.delegate = nil
    publishedService?.stop()
    publishedService = nil

    peersByDeviceId.removeAll()
    serviceNameToDeviceId.removeAll()
    advertising = false
    browsing = false
    running = false
    localServiceName = ""
    localDeviceId = ""
    lastError = nil
    lastPermissionIssue = nil
    lastBackendLogMessage = "Apple Bonjour stopped."
    hasSuccessfulBrowse = false
  }

  func snapshot() -> [String: Any] {
    return [
      "running": running,
      "advertising": advertising,
      "browsing": browsing,
      "peers": Array(peersByDeviceId.values),
      "lastError": lastError ?? NSNull(),
      "lastPermissionIssue": lastPermissionIssue ?? NSNull(),
      "lastBackendLogMessage": lastBackendLogMessage ?? NSNull(),
    ]
  }

  func netServiceDidPublish(_ sender: NetService) {
    guard sender == publishedService else {
      return
    }
    advertising = true
    running = advertising || browsing
    if hasSuccessfulBrowse {
      lastError = nil
      lastPermissionIssue = nil
    }
    lastBackendLogMessage = "Apple Bonjour advertising is active."
  }

  func netService(_ sender: NetService, didNotPublish errorDict: [String : NSNumber]) {
    guard sender == publishedService else {
      return
    }
    advertising = false
    running = browsing
    let errorMessage = "Apple Bonjour publish failed: \(errorDict)"
    lastError = errorMessage
    if !hasSuccessfulBrowse {
      lastPermissionIssue = setupBlockingIssueMessage()
    }
    lastBackendLogMessage = errorMessage
  }

  func netServiceBrowserWillSearch(_ browser: NetServiceBrowser) {
    guard browser == self.browser else {
      return
    }
    browsing = true
    running = advertising || browsing
    hasSuccessfulBrowse = true
    lastError = nil
    lastPermissionIssue = nil
    lastBackendLogMessage = "Apple Bonjour browsing started."
  }

  func netServiceBrowser(_ browser: NetServiceBrowser, didNotSearch errorDict: [String : NSNumber]) {
    guard browser == self.browser else {
      return
    }
    browsing = false
    running = advertising
    let errorMessage = "Apple Bonjour browse start failed: \(errorDict)"
    lastError = errorMessage
    if !hasSuccessfulBrowse {
      lastPermissionIssue = setupBlockingIssueMessage()
    }
    lastBackendLogMessage = errorMessage
  }

  func netServiceBrowserDidStopSearch(_ browser: NetServiceBrowser) {
    guard browser == self.browser else {
      return
    }
    browsing = false
    running = advertising
    lastBackendLogMessage = "Apple Bonjour browsing stopped."
  }

  func netServiceBrowser(
    _ browser: NetServiceBrowser,
    didFind service: NetService,
    moreComing: Bool
  ) {
    guard browser == self.browser else {
      return
    }
    if service.name == localServiceName {
      return
    }
    service.delegate = self
    service.resolve(withTimeout: 5)
  }

  func netServiceBrowser(
    _ browser: NetServiceBrowser,
    didRemove service: NetService,
    moreComing: Bool
  ) {
    guard browser == self.browser else {
      return
    }
    if let deviceId = serviceNameToDeviceId.removeValue(forKey: service.name) {
      peersByDeviceId.removeValue(forKey: deviceId)
      lastBackendLogMessage = "Apple Bonjour peer lost: \(service.name)."
    }
  }

  func netServiceDidResolveAddress(_ sender: NetService) {
    guard let peer = buildPeer(from: sender),
          let deviceId = peer["deviceId"] as? String,
          deviceId != localDeviceId else {
      return
    }
    peersByDeviceId[deviceId] = peer
    serviceNameToDeviceId[sender.name] = deviceId
    running = advertising || browsing
    lastError = nil
    lastPermissionIssue = nil
    hasSuccessfulBrowse = true
    lastBackendLogMessage = "Apple Bonjour resolved \(sender.name)."
  }

  func netService(_ sender: NetService, didNotResolve errorDict: [String : NSNumber]) {
    let errorMessage = "Apple Bonjour resolve failed: \(errorDict)"
    lastError = errorMessage
    lastBackendLogMessage = errorMessage
  }

  private func setupBlockingIssueMessage() -> String {
    return "Nearby discovery is blocked. Allow Local Network access for LocalDrop. On iPhone and iPad builds, also sign the app with the multicast entitlement (com.apple.developer.networking.multicast)."
  }

  private func buildPeer(from service: NetService) -> [String: Any]? {
    let attributes = txtAttributes(from: service)
    let deviceId = attributes["id"] ?? ""
    let nickname = attributes["name"] ?? ""
    let fingerprint = attributes["fp"] ?? ""
    let ipAddresses = numericAddresses(for: service)
    let activePort = Int(service.port)

    guard !deviceId.isEmpty,
          !nickname.isEmpty,
          !fingerprint.isEmpty,
          !ipAddresses.isEmpty,
          activePort > 0 else {
      return nil
    }

    let capabilities = attributes["caps"]?
      .split(separator: ",")
      .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty } ?? []
    let securePort = Int(attributes["spt"] ?? "")
    let preferredAddressFamily = attributes["af"]
      ?? (ipAddresses.first?.contains(":") == true ? "ipv6" : "ipv4")

    var peer: [String: Any] = [
      "deviceId": deviceId,
      "nickname": nickname,
      "platform": attributes["plat"] ?? "macos",
      "ipAddresses": ipAddresses,
      "activePort": activePort,
      "certFingerprint": fingerprint,
      "appVersion": attributes["ver"] ?? "",
      "protocolVersion": attributes["proto"] ?? "",
      "capabilities": capabilities,
      "preferredAddressFamily": preferredAddressFamily,
    ]
    if let securePort, securePort > 0 {
      peer["securePort"] = securePort
    }
    return peer
  }

  private func txtAttributes(from service: NetService) -> [String: String] {
    guard let txtData = service.txtRecordData() else {
      return [:]
    }
    let raw = NetService.dictionary(fromTXTRecord: txtData)
    return raw.reduce(into: [String: String]()) { partialResult, entry in
      partialResult[entry.key] = String(data: entry.value, encoding: .utf8) ?? ""
    }
  }

  private func numericAddresses(for service: NetService) -> [String] {
    guard let addresses = service.addresses else {
      return []
    }
    return addresses.compactMap { data -> String? in
      return data.withUnsafeBytes { buffer -> String? in
        guard let rawPointer = buffer.baseAddress else {
          return nil
        }
        let socketAddress = rawPointer.assumingMemoryBound(to: sockaddr.self)
        var hostBuffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
        let length = socklen_t(socketAddress.pointee.sa_len)
        let result = getnameinfo(
          socketAddress,
          length,
          &hostBuffer,
          socklen_t(hostBuffer.count),
          nil,
          0,
          NI_NUMERICHOST
        )
        guard result == 0 else {
          return nil
        }
        return String(cString: hostBuffer)
      }
    }
  }

  private func buildServiceName(deviceId: String, nickname: String) -> String {
    let cleanedNickname = nickname
      .components(separatedBy: CharacterSet.alphanumerics.union(.whitespaces).inverted)
      .joined()
      .trimmingCharacters(in: .whitespacesAndNewlines)
    let baseName = cleanedNickname.isEmpty ? "LocalDrop" : cleanedNickname
    let suffix = deviceId.count <= 6 ? deviceId : String(deviceId.suffix(6))
    return "\(baseName)-\(suffix)"
  }
}
