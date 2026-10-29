package dev.macclip.android

import android.content.Context
import android.net.nsd.NsdManager
import android.net.nsd.NsdServiceInfo
import android.os.Build
import androidx.work.Constraints
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.NetworkType
import androidx.work.PeriodicWorkRequest
import androidx.work.WorkManager
import androidx.work.Worker
import androidx.work.WorkerParameters
import java.io.File
import java.net.Inet4Address
import java.util.concurrent.LinkedBlockingQueue
import java.util.concurrent.TimeUnit

object Graph {
    fun outbox(context: Context) = Outbox(File(context.noBackupFilesDir, "outbox"))

    fun pairing(context: Context): Pairing? {
        val prefs = prefs(context)
        return Pairing.create(
            prefs.getString("host", "") ?: "",
            prefs.getInt("port", DEFAULT_PORT).toString(),
            prefs.getString("key", "") ?: "",
            prefs.getString("name", "Mac") ?: "Mac",
        )
    }

    fun savePairing(context: Context, pairing: Pairing) {
        prefs(context).edit()
            .putString("host", pairing.host)
            .putInt("port", pairing.port)
            .putString("key", pairing.key)
            .putString("name", pairing.name)
            .apply()
    }

    fun sender(context: Context, pairing: Pairing): Sender {
        val app = context.applicationContext
        return Sender(outbox(app), pairing) { Discovery.find(app, pairing.keyId, timeoutMs = 2500) }
    }

    private fun prefs(context: Context) = context.getSharedPreferences("pairing", Context.MODE_PRIVATE)
}

/** Finds the paired Mac over Bonjour by the key fingerprint in its TXT record. Blocks; never call on the main thread. */
object Discovery {
    private const val SERVICE_TYPE = "_macclip._tcp"

    fun find(context: Context, keyId: String, timeoutMs: Long): Pair<String, Int>? {
        val nsd = context.getSystemService(NsdManager::class.java) ?: return null
        val deadline = System.currentTimeMillis() + timeoutMs
        val found = LinkedBlockingQueue<NsdServiceInfo>()
        val listener = object : NsdManager.DiscoveryListener {
            override fun onServiceFound(info: NsdServiceInfo) { found.put(info) }
            override fun onServiceLost(info: NsdServiceInfo) {}
            override fun onDiscoveryStarted(serviceType: String) {}
            override fun onDiscoveryStopped(serviceType: String) {}
            override fun onStartDiscoveryFailed(serviceType: String, errorCode: Int) {}
            override fun onStopDiscoveryFailed(serviceType: String, errorCode: Int) {}
        }
        try {
            nsd.discoverServices(SERVICE_TYPE, NsdManager.PROTOCOL_DNS_SD, listener)
        } catch (e: RuntimeException) {
            return null
        }
        try {
            while (true) {
                val left = deadline - System.currentTimeMillis()
                if (left <= 0) return null
                val candidate = found.poll(left, TimeUnit.MILLISECONDS) ?: return null
                val resolved = resolve(nsd, candidate, deadline - System.currentTimeMillis()) ?: continue
                val kid = resolved.attributes["kid"]?.toString(Charsets.UTF_8)
                val host = hostOf(resolved) ?: continue
                if (kid == keyId) return host to resolved.port
            }
        } finally {
            runCatching { nsd.stopServiceDiscovery(listener) }
        }
    }

    @Suppress("DEPRECATION")
    private fun resolve(nsd: NsdManager, info: NsdServiceInfo, timeoutMs: Long): NsdServiceInfo? {
        if (timeoutMs <= 0) return null
        val result = LinkedBlockingQueue<Result<NsdServiceInfo>>()
        nsd.resolveService(info, object : NsdManager.ResolveListener {
            override fun onServiceResolved(resolved: NsdServiceInfo) { result.put(Result.success(resolved)) }
            override fun onResolveFailed(info: NsdServiceInfo, errorCode: Int) {
                result.put(Result.failure(IllegalStateException("resolve failed: $errorCode")))
            }
        })
        return result.poll(timeoutMs, TimeUnit.MILLISECONDS)?.getOrNull()
    }

    @Suppress("DEPRECATION")
    private fun hostOf(info: NsdServiceInfo): String? {
        val addresses = if (Build.VERSION.SDK_INT >= 34) info.hostAddresses else listOfNotNull(info.host)
        return (addresses.firstOrNull { it is Inet4Address } ?: addresses.firstOrNull())?.hostAddress
    }
}

/** Retries the outbox every ~15 minutes while on Wi-Fi, and cancels itself once the outbox is empty. */
class OutboxWorker(context: Context, params: WorkerParameters) : Worker(context, params) {
    override fun doWork(): Result {
        val pairing = Graph.pairing(applicationContext) ?: return Result.success()
        Graph.sender(applicationContext, pairing).flush()
        if (Graph.outbox(applicationContext).count() == 0) Retry.cancel(applicationContext)
        return Result.success()
    }
}

object Retry {
    private const val NAME = "outbox-retry"

    fun schedule(context: Context) {
        val request = PeriodicWorkRequest.Builder(OutboxWorker::class.java, 15, TimeUnit.MINUTES)
            .setConstraints(Constraints.Builder().setRequiredNetworkType(NetworkType.UNMETERED).build())
            .build()
        WorkManager.getInstance(context).enqueueUniquePeriodicWork(NAME, ExistingPeriodicWorkPolicy.KEEP, request)
    }

    fun cancel(context: Context) {
        WorkManager.getInstance(context).cancelUniqueWork(NAME)
    }
}
