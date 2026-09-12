// Galatea Link mobile 主活动，桥接共享文件和连接期间前台保活

package com.noctfom.galatealink

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.database.Cursor
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.OpenableColumns
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    companion object {
        private const val channelName = "galatea_link_mobile/platform"
        private const val notificationPermissionRequest = 813
    }

    private var methodChannel: MethodChannel? = null
    private var pendingImportIntent: Intent? = null

    // 保存用于冷启动应用的文件打开请求
    override fun onCreate(savedInstanceState: Bundle?) {
        pendingImportIntent = intent.takeIf(::isImportIntent)
        super.onCreate(savedInstanceState)
    }

    // 注册 Flutter 平台通道
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        methodChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            channelName,
        ).also { channel ->
            channel.setMethodCallHandler { call, result ->
                when (call.method) {
                    "getPendingSharedFile" -> consumePendingSharedFile(result)
                    "getAppInfo" -> result.success(readAppInfo())
                    "openExternalUrl" -> openExternalUrl(
                        call.argument<String>("url"),
                        result,
                    )
                    "startKeepAlive" -> {
                        try {
                            requestNotificationPermissionIfNeeded()
                            DuelKeepAliveService.start(this)
                            result.success(null)
                        } catch (error: Throwable) {
                            result.error(
                                "keep_alive_start_failed",
                                error.message ?: error.javaClass.simpleName,
                                null,
                            )
                        }
                    }
                    "stopKeepAlive" -> {
                        try {
                            DuelKeepAliveService.stop(this)
                            result.success(null)
                        } catch (error: Throwable) {
                            result.error(
                                "keep_alive_stop_failed",
                                error.message ?: error.javaClass.simpleName,
                                null,
                            )
                        }
                    }
                    else -> result.notImplemented()
                }
            }
        }
    }

    // 接收应用运行期间再次打开的关联文件
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        if (isImportIntent(intent)) {
            pendingImportIntent = intent
            methodChannel?.invokeMethod("sharedFileAvailable", null)
        }
    }

    // 判断 Intent 是否携带应用支持的共享文件
    private fun isImportIntent(intent: Intent): Boolean {
        return intent.action == Intent.ACTION_VIEW || intent.action == Intent.ACTION_SEND
    }

    // 读取安装包当前应用标识和版本信息
    private fun readAppInfo(): Map<String, Any> {
        @Suppress("DEPRECATION")
        val packageInfo = packageManager.getPackageInfo(packageName, 0)
        val versionCode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            packageInfo.longVersionCode
        } else {
            @Suppress("DEPRECATION")
            packageInfo.versionCode.toLong()
        }
        return mapOf(
            "application_id" to packageName,
            "version_name" to (packageInfo.versionName ?: "0.0.0"),
            "version_code" to versionCode,
        )
    }

    // 使用系统浏览器打开经过限制的 HTTPS 更新页面
    private fun openExternalUrl(url: String?, result: MethodChannel.Result) {
        try {
            val uri = Uri.parse(requireNotNull(url) { "缺少更新地址" })
            require(uri.scheme == "https" && !uri.host.isNullOrBlank()) {
                "只允许打开 HTTPS 更新地址"
            }
            val target = Intent(Intent.ACTION_VIEW, uri).apply {
                addCategory(Intent.CATEGORY_BROWSABLE)
            }
            startActivity(target)
            result.success(true)
        } catch (error: Throwable) {
            result.error(
                "open_url_failed",
                error.message ?: error.javaClass.simpleName,
                null,
            )
        }
    }

    // 在工作线程复制一次性 URI 并把缓存路径交给 Flutter
    private fun consumePendingSharedFile(result: MethodChannel.Result) {
        val sourceIntent = pendingImportIntent
        pendingImportIntent = null
        if (sourceIntent == null) {
            result.success(null)
            return
        }
        Thread {
            try {
                val uri = sharedUri(sourceIntent)
                    ?: throw IllegalArgumentException("文件请求不包含可读取 URI")
                val displayName = resolveDisplayName(uri)
                val safeName = sanitizeFileName(displayName)
                val directory = File(cacheDir, "shared_imports")
                directory.mkdirs()
                cleanExpiredImports(directory)
                val target = File(
                    directory,
                    "${System.currentTimeMillis()}_$safeName",
                )
                try {
                    contentResolver.openInputStream(uri).use { input ->
                        requireNotNull(input) { "无法打开共享文件" }
                        target.outputStream().use { output ->
                            copyWithLimit(input, output, maximumImportBytes(safeName))
                        }
                    }
                } catch (error: Throwable) {
                    target.delete()
                    throw error
                }
                val payload = mapOf(
                    "name" to safeName,
                    "path" to target.absolutePath,
                    "mime_type" to (contentResolver.getType(uri) ?: ""),
                )
                runOnUiThread { result.success(payload) }
            } catch (error: Throwable) {
                runOnUiThread {
                    result.error(
                        "shared_file_failed",
                        error.message ?: error.javaClass.simpleName,
                        null,
                    )
                }
            }
        }.start()
    }

    // 提取查看或分享请求中的文件 URI
    private fun sharedUri(intent: Intent): Uri? {
        if (intent.action == Intent.ACTION_VIEW) return intent.data
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            intent.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java)
        } else {
            @Suppress("DEPRECATION")
            intent.getParcelableExtra(Intent.EXTRA_STREAM)
        }
    }

    // 从内容提供器查询用户可见文件名
    private fun resolveDisplayName(uri: Uri): String {
        var cursor: Cursor? = null
        try {
            cursor = contentResolver.query(
                uri,
                arrayOf(OpenableColumns.DISPLAY_NAME),
                null,
                null,
                null,
            )
            if (cursor != null && cursor.moveToFirst()) {
                val index = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                if (index >= 0) return cursor.getString(index)
            }
        } finally {
            cursor?.close()
        }
        return uri.lastPathSegment ?: "shared_file"
    }

    // 清理文件名中的路径和控制字符
    private fun sanitizeFileName(value: String): String {
        val normalized = value
            .substringAfterLast('/')
            .substringAfterLast('\\')
            .replace(Regex("[<>:\"/\\\\|?*\\u0000-\\u001f]"), "_")
            .take(180)
        return normalized.ifBlank { "shared_file" }
    }

    // 删除共享导入目录中超过七天的临时副本
    private fun cleanExpiredImports(directory: File) {
        val cutoff = System.currentTimeMillis() - 7L * 24L * 60L * 60L * 1000L
        directory.listFiles()?.forEach { file ->
            if (file.isFile && file.lastModified() < cutoff) file.delete()
        }
    }

    // 根据文件扩展名返回共享缓存允许的最大字节数
    private fun maximumImportBytes(fileName: String): Long {
        return when {
            fileName.endsWith(".ydk", ignoreCase = true) -> 512L * 1024L
            fileName.endsWith(".cdb", ignoreCase = true) -> 4L * 1024L * 1024L * 1024L
            fileName.endsWith(".gkg", ignoreCase = true) -> 8L * 1024L * 1024L * 1024L
            else -> 16L * 1024L * 1024L
        }
    }

    // 流式复制共享文件并阻止异常内容占满设备存储
    private fun copyWithLimit(
        input: java.io.InputStream,
        output: java.io.OutputStream,
        maximumBytes: Long,
    ) {
        val buffer = ByteArray(DEFAULT_BUFFER_SIZE)
        var total = 0L
        while (true) {
            val count = input.read(buffer)
            if (count < 0) break
            total += count
            if (total > maximumBytes) {
                throw IllegalArgumentException("共享文件超过移动端安全限制")
            }
            output.write(buffer, 0, count)
        }
    }

    // 在 Android 13 及以上请求显示保活通知的权限
    private fun requestNotificationPermissionIfNeeded() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return
        if (ContextCompat.checkSelfPermission(
                this,
                Manifest.permission.POST_NOTIFICATIONS,
            ) == PackageManager.PERMISSION_GRANTED
        ) {
            return
        }
        ActivityCompat.requestPermissions(
            this,
            arrayOf(Manifest.permission.POST_NOTIFICATIONS),
            notificationPermissionRequest,
        )
    }
}
