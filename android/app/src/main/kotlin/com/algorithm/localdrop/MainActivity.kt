package com.algorithm.localdrop

import android.content.Intent
import android.content.Context
import android.net.ConnectivityManager
import android.net.Uri
import android.net.nsd.NsdManager
import android.net.nsd.NsdServiceInfo
import android.net.wifi.WifiManager
import android.os.Environment
import android.provider.DocumentsContract
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.net.Inet4Address
import java.nio.charset.StandardCharsets
import java.util.Locale

class MainActivity : FlutterActivity() {
    private val channelName = "localdrop/network"
    private var multicastLock: WifiManager.MulticastLock? = null
    private var wifiLock: WifiManager.WifiLock? = null
    private lateinit var nativeDiscoveryManager: NativeDiscoveryManager

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        nativeDiscoveryManager = NativeDiscoveryManager(applicationContext)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName).setMethodCallHandler { call, result ->
            when (call.method) {
                "acquireMulticastLock" -> {
                    acquireMulticastLock()
                    result.success(null)
                }
                "releaseMulticastLock" -> {
                    releaseMulticastLock()
                    result.success(null)
                }
                "acquireWifiLock" -> {
                    acquireWifiLock()
                    result.success(null)
                }
                "releaseWifiLock" -> {
                    releaseWifiLock()
                    result.success(null)
                }
                "getActiveInterfaces" -> {
                    result.success(getActiveInterfaces())
                }
                "getPublicDownloadsDirectory" -> {
                    result.success(getPublicDownloadsDirectory())
                }
                "openFolder" -> {
                    val args =
                        (call.arguments as? Map<*, *>)?.entries?.associate { (key, value) ->
                            key.toString() to value
                        } ?: emptyMap()
                    val path = args["path"]?.toString()?.trim().orEmpty()
                    result.success(openFolder(path))
                }
                "startNativeDiscovery" -> {
                    val args =
                        (call.arguments as? Map<*, *>)?.entries?.associate { (key, value) ->
                            key.toString() to value
                        } ?: emptyMap()
                    nativeDiscoveryManager.start(args)
                    result.success(null)
                }
                "stopNativeDiscovery" -> {
                    nativeDiscoveryManager.stop()
                    result.success(null)
                }
                "getNativeDiscoverySnapshot" -> {
                    result.success(nativeDiscoveryManager.snapshot())
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onDestroy() {
        nativeDiscoveryManager.stop()
        releaseMulticastLock()
        releaseWifiLock()
        super.onDestroy()
    }

    private fun acquireMulticastLock() {
        val wifiManager = applicationContext.getSystemService(Context.WIFI_SERVICE) as? WifiManager ?: return
        val lock = multicastLock ?: wifiManager.createMulticastLock("localdrop_multicast_lock").also {
            it.setReferenceCounted(false)
            multicastLock = it
        }
        if (!lock.isHeld) {
            lock.acquire()
        }
    }

    private fun releaseMulticastLock() {
        val lock = multicastLock ?: return
        if (lock.isHeld) {
            lock.release()
        }
    }

    private fun acquireWifiLock() {
        val wifiManager = applicationContext.getSystemService(Context.WIFI_SERVICE) as? WifiManager ?: return
        val lock = wifiLock ?: wifiManager.createWifiLock(
            WifiManager.WIFI_MODE_FULL_HIGH_PERF,
            "localdrop_wifi_lock",
        ).also {
            it.setReferenceCounted(false)
            wifiLock = it
        }
        if (!lock.isHeld) {
            lock.acquire()
        }
    }

    private fun releaseWifiLock() {
        val lock = wifiLock
        if (lock != null && lock.isHeld) {
            lock.release()
        }
    }

    private fun getActiveInterfaces(): List<Map<String, Any>> {
        val connectivityManager =
            applicationContext.getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager
                ?: return emptyList()
        val snapshots = mutableListOf<Map<String, Any>>()
        val seen = mutableSetOf<String>()

        for (network in connectivityManager.allNetworks) {
            val linkProperties = connectivityManager.getLinkProperties(network) ?: continue
            val interfaceName = linkProperties.interfaceName ?: continue
            for (linkAddress in linkProperties.linkAddresses) {
                val address = linkAddress.address
                if (address !is Inet4Address ||
                    address.isLoopbackAddress ||
                    address.isLinkLocalAddress ||
                    address.isMulticastAddress
                ) {
                    continue
                }
                val hostAddress = address.hostAddress ?: continue
                val prefixLength = linkAddress.prefixLength.coerceIn(0, 32)
                val key = "$interfaceName:$hostAddress:$prefixLength"
                if (!seen.add(key)) {
                    continue
                }
                snapshots.add(
                    mapOf(
                        "interfaceName" to interfaceName,
                        "address" to hostAddress,
                        "prefixLength" to prefixLength,
                    )
                )
            }
        }

        return snapshots
    }

    private fun getPublicDownloadsDirectory(): String? {
        return try {
            Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS)?.absolutePath
        } catch (_: Throwable) {
            null
        }
    }

    private fun openFolder(path: String): Boolean {
        if (path.isBlank()) {
            return false
        }

        val rawTarget = File(path)
        val targetDirectory = if (rawTarget.isFile) rawTarget.parentFile else rawTarget
        if (targetDirectory == null || !targetDirectory.exists()) {
            return false
        }

        for (intent in buildOpenFolderIntents(targetDirectory)) {
            try {
                startActivity(intent)
                return true
            } catch (_: Exception) {
            }
        }

        return false
    }

    private fun buildOpenFolderIntents(directory: File): List<Intent> {
        val intents = mutableListOf<Intent>()

        buildExternalStorageDocumentUri(directory)?.let { uri ->
            intents += buildFolderViewIntent(uri, DocumentsContract.Document.MIME_TYPE_DIR)
            intents += buildFolderViewIntent(uri, "resource/folder")
        }

        buildFileProviderUri(directory)?.let { uri ->
            intents += buildFolderViewIntent(
                uri,
                DocumentsContract.Document.MIME_TYPE_DIR,
                grantReadAccess = true,
            )
            intents += buildFolderViewIntent(
                uri,
                "resource/folder",
                grantReadAccess = true,
            )
        }

        intents +=
            Intent(Intent.ACTION_VIEW).apply {
                data = Uri.parse(directory.toURI().toString())
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }

        return intents
    }

    private fun buildFolderViewIntent(
        uri: Uri,
        mimeType: String,
        grantReadAccess: Boolean = false,
    ): Intent {
        return Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(uri, mimeType)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            if (grantReadAccess) {
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                addFlags(Intent.FLAG_GRANT_PREFIX_URI_PERMISSION)
            }
        }
    }

    private fun buildFileProviderUri(directory: File): Uri? {
        return try {
            FileProvider.getUriForFile(
                this,
                "${applicationContext.packageName}.fileprovider",
                directory,
            )
        } catch (_: Throwable) {
            null
        }
    }

    private fun buildExternalStorageDocumentUri(directory: File): Uri? {
        return try {
            val externalRoot = Environment.getExternalStorageDirectory()?.absolutePath ?: return null
            val normalizedRoot = externalRoot.trimEnd(File.separatorChar)
            val normalizedDirectory = directory.absolutePath

            if (
                normalizedDirectory != normalizedRoot &&
                    !normalizedDirectory.startsWith("$normalizedRoot${File.separator}")
            ) {
                return null
            }

            val relativePath = normalizedDirectory.removePrefix(normalizedRoot).trimStart(File.separatorChar)
            val documentId =
                if (relativePath.isEmpty()) {
                    "primary:"
                } else {
                    "primary:${relativePath.replace(File.separatorChar, '/')}"
                }
            DocumentsContract.buildDocumentUri(
                "com.android.externalstorage.documents",
                documentId,
            )
        } catch (_: Throwable) {
            null
        }
    }
}

private class NativeDiscoveryManager(
    private val context: Context,
) {
    private val serviceType = "_localdrop._tcp."
    private val nsdManager = context.getSystemService(Context.NSD_SERVICE) as? NsdManager

    private var registrationListener: NsdManager.RegistrationListener? = null
    private var discoveryListener: NsdManager.DiscoveryListener? = null

    private var localServiceName: String = ""
    private var localDeviceId: String = ""
    private var running: Boolean = false
    private var advertising: Boolean = false
    private var browsing: Boolean = false
    private var lastError: String? = null
    private var lastPermissionIssue: String? = null
    private var lastBackendLogMessage: String? = null

    private val peersByDeviceId = linkedMapOf<String, Map<String, Any>>()
    private val serviceNameToDeviceId = mutableMapOf<String, String>()

    fun start(args: Map<String, Any?>) {
        stop()
        if (nsdManager == null) {
            lastError = "Android NSD is unavailable on this device."
            lastBackendLogMessage = lastError
            return
        }

        val deviceId = args["deviceId"]?.toString()?.trim().orEmpty()
        val nickname = args["nickname"]?.toString()?.trim().orEmpty()
        val fingerprint = args["certFingerprint"]?.toString()?.trim().orEmpty()
        val appVersion = args["appVersion"]?.toString()?.trim().orEmpty()
        val protocolVersion = args["protocolVersion"]?.toString()?.trim().orEmpty()
        val activePort = (args["activePort"] as? Number)?.toInt() ?: 0
        val securePort = (args["securePort"] as? Number)?.toInt()
        val capabilities =
            (args["capabilities"] as? List<*>)?.map { item -> item.toString() } ?: emptyList()

        if (deviceId.isEmpty() || nickname.isEmpty() || fingerprint.isEmpty() || activePort <= 0) {
            lastError = "Android NSD could not start because the discovery payload was incomplete."
            lastBackendLogMessage = lastError
            return
        }

        localDeviceId = deviceId
        localServiceName = buildServiceName(deviceId, nickname)
        lastError = null
        lastPermissionIssue = null
        lastBackendLogMessage = "Starting Android NSD advertising and browsing."

        val serviceInfo = NsdServiceInfo().apply {
            serviceName = localServiceName
            serviceType = this@NativeDiscoveryManager.serviceType
            port = activePort
            setAttribute("id", deviceId)
            setAttribute("name", nickname)
            setAttribute("plat", "android")
            setAttribute("fp", fingerprint)
            setAttribute("ver", appVersion)
            setAttribute("proto", protocolVersion)
            setAttribute("caps", capabilities.joinToString(","))
            if (securePort != null && securePort > 0) {
                setAttribute("spt", securePort.toString())
            }
            setAttribute("af", "ipv4")
        }

        registrationListener = object : NsdManager.RegistrationListener {
            override fun onRegistrationFailed(serviceInfo: NsdServiceInfo, errorCode: Int) {
                advertising = false
                running = browsing
                lastError = "Android NSD registration failed ($errorCode)."
                lastBackendLogMessage = lastError
            }

            override fun onUnregistrationFailed(serviceInfo: NsdServiceInfo, errorCode: Int) {
                advertising = false
                running = browsing
                lastError = "Android NSD unregister failed ($errorCode)."
                lastBackendLogMessage = lastError
            }

            override fun onServiceRegistered(serviceInfo: NsdServiceInfo) {
                localServiceName = serviceInfo.serviceName ?: localServiceName
                advertising = true
                running = advertising || browsing
                lastBackendLogMessage = "Android NSD advertising is active."
            }

            override fun onServiceUnregistered(serviceInfo: NsdServiceInfo) {
                advertising = false
                running = browsing
                lastBackendLogMessage = "Android NSD advertising stopped."
            }
        }

        discoveryListener = object : NsdManager.DiscoveryListener {
            override fun onDiscoveryStarted(serviceType: String) {
                browsing = true
                running = advertising || browsing
                lastBackendLogMessage = "Android NSD browsing started."
            }

            override fun onStartDiscoveryFailed(serviceType: String, errorCode: Int) {
                browsing = false
                running = advertising
                lastError = "Android NSD browse start failed ($errorCode)."
                lastBackendLogMessage = lastError
            }

            override fun onStopDiscoveryFailed(serviceType: String, errorCode: Int) {
                browsing = false
                running = advertising
                lastError = "Android NSD browse stop failed ($errorCode)."
                lastBackendLogMessage = lastError
            }

            override fun onDiscoveryStopped(serviceType: String) {
                browsing = false
                running = advertising
                lastBackendLogMessage = "Android NSD browsing stopped."
            }

            override fun onServiceFound(serviceInfo: NsdServiceInfo) {
                val foundType = normalizeServiceType(serviceInfo.serviceType)
                if (foundType != normalizeServiceType(serviceType)) {
                    return
                }
                if (serviceInfo.serviceName == localServiceName) {
                    return
                }
                resolve(serviceInfo)
            }

            override fun onServiceLost(serviceInfo: NsdServiceInfo) {
                val deviceId = serviceNameToDeviceId.remove(serviceInfo.serviceName ?: "")
                if (deviceId != null) {
                    peersByDeviceId.remove(deviceId)
                    lastBackendLogMessage = "Android NSD peer lost: ${serviceInfo.serviceName}."
                }
            }
        }

        try {
            nsdManager.registerService(
                serviceInfo,
                NsdManager.PROTOCOL_DNS_SD,
                registrationListener,
            )
            nsdManager.discoverServices(
                serviceType,
                NsdManager.PROTOCOL_DNS_SD,
                discoveryListener,
            )
        } catch (error: Exception) {
            advertising = false
            browsing = false
            running = false
            lastError = error.message ?: error.toString()
            lastBackendLogMessage = "Android NSD failed to start: $lastError"
        }
    }

    fun stop() {
        val manager = nsdManager ?: run {
            peersByDeviceId.clear()
            serviceNameToDeviceId.clear()
            advertising = false
            browsing = false
            running = false
            localServiceName = ""
            localDeviceId = ""
            return
        }

        discoveryListener?.let { listener ->
            try {
                manager.stopServiceDiscovery(listener)
            } catch (_: Exception) {
            }
        }
        discoveryListener = null

        registrationListener?.let { listener ->
            try {
                manager.unregisterService(listener)
            } catch (_: Exception) {
            }
        }
        registrationListener = null

        peersByDeviceId.clear()
        serviceNameToDeviceId.clear()
        advertising = false
        browsing = false
        running = false
        localServiceName = ""
        localDeviceId = ""
        lastError = null
        lastPermissionIssue = null
        lastBackendLogMessage = "Android NSD stopped."
    }

    fun snapshot(): Map<String, Any?> {
        return mapOf(
            "running" to running,
            "advertising" to advertising,
            "browsing" to browsing,
            "peers" to peersByDeviceId.values.toList(),
            "lastError" to lastError,
            "lastPermissionIssue" to lastPermissionIssue,
            "lastBackendLogMessage" to lastBackendLogMessage,
        )
    }

    private fun resolve(serviceInfo: NsdServiceInfo) {
        val manager = nsdManager ?: return
        try {
            manager.resolveService(
                serviceInfo,
                object : NsdManager.ResolveListener {
                    override fun onResolveFailed(serviceInfo: NsdServiceInfo, errorCode: Int) {
                        lastError = "Android NSD resolve failed ($errorCode)."
                        lastBackendLogMessage = lastError
                    }

                    override fun onServiceResolved(serviceInfo: NsdServiceInfo) {
                        val peer = buildPeer(serviceInfo) ?: return
                        val deviceId = peer["deviceId"]?.toString() ?: return
                        if (deviceId == localDeviceId) {
                            return
                        }
                        peersByDeviceId[deviceId] = peer
                        serviceNameToDeviceId[serviceInfo.serviceName ?: deviceId] = deviceId
                        running = advertising || browsing
                        lastError = null
                        lastBackendLogMessage = "Android NSD resolved ${serviceInfo.serviceName}."
                    }
                },
            )
        } catch (error: Exception) {
            lastError = error.message ?: error.toString()
            lastBackendLogMessage = "Android NSD resolve threw an error: $lastError"
        }
    }

    private fun buildPeer(serviceInfo: NsdServiceInfo): Map<String, Any>? {
        val attributes =
            serviceInfo.attributes.mapValues { (_, value) ->
                String(value ?: ByteArray(0), StandardCharsets.UTF_8)
            }
        val deviceId = attributes["id"].orEmpty()
        val nickname = attributes["name"].orEmpty()
        val fingerprint = attributes["fp"].orEmpty()
        val hostAddress = serviceInfo.host?.hostAddress.orEmpty()
        val activePort = serviceInfo.port

        if (deviceId.isEmpty() || nickname.isEmpty() || fingerprint.isEmpty() || hostAddress.isEmpty() || activePort <= 0) {
            return null
        }

        val capabilities =
            attributes["caps"]
                ?.split(',')
                ?.map { value -> value.trim() }
                ?.filter { value -> value.isNotEmpty() }
                ?: emptyList()
        val securePort = attributes["spt"]?.toIntOrNull()

        val peer = mutableMapOf<String, Any>(
            "deviceId" to deviceId,
            "nickname" to nickname,
            "platform" to (attributes["plat"] ?: "android"),
            "ipAddresses" to listOf(hostAddress),
            "activePort" to activePort,
            "certFingerprint" to fingerprint,
            "appVersion" to (attributes["ver"] ?: ""),
            "protocolVersion" to (attributes["proto"] ?: ""),
            "capabilities" to capabilities,
            "preferredAddressFamily" to (
                attributes["af"]
                    ?: if (hostAddress.contains(':')) "ipv6" else "ipv4"
                ),
        )
        if (securePort != null && securePort > 0) {
            peer["securePort"] = securePort
        }
        return peer
    }

    private fun buildServiceName(deviceId: String, nickname: String): String {
        val cleanNickname =
            nickname.replace(Regex("[^A-Za-z0-9 _-]"), "").trim().ifEmpty { "LocalDrop" }
        val suffix = if (deviceId.length <= 6) deviceId else deviceId.takeLast(6)
        return "$cleanNickname-$suffix"
    }

    private fun normalizeServiceType(value: String?): String {
        return value?.trim()?.trimEnd('.')?.lowercase(Locale.US).orEmpty()
    }
}
