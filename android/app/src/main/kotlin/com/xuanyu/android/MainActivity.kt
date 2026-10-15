package com.xuanyu.android

import android.content.ContentValues
import android.content.Intent
import android.os.Vibrator
import android.os.VibrationEffect
import android.os.VibratorManager
import android.content.Context
import android.os.Build
import android.os.Bundle
import android.media.MediaRecorder
import android.os.Environment
import android.provider.MediaStore
import android.view.View
import android.view.ViewGroup
import java.io.File
import androidx.core.view.WindowCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import com.google.android.play.core.appupdate.AppUpdateManager
import com.google.android.play.core.appupdate.AppUpdateManagerFactory
import com.google.android.play.core.install.InstallStateUpdatedListener
import com.google.android.play.core.install.model.AppUpdateType
import com.google.android.play.core.install.model.InstallStatus
import com.google.android.play.core.install.model.UpdateAvailability

class MainActivity : FlutterActivity() {
    private var audioRecorder: MediaRecorder? = null
    private var audioRecordingPath: String? = null
    private var startupOverlay: View? = null
    private var flutterUiDisplayed = false
    private lateinit var appUpdateManager: AppUpdateManager
    private var appUpdateChannel: MethodChannel? = null
    private var deepLinkChannel: MethodChannel? = null
    private var pendingDeepLink: String? = null
    private var pendingGallerySave: PendingGallerySave? = null
    private val updateStateListener = InstallStateUpdatedListener { state ->
        if (state.installStatus() == InstallStatus.DOWNLOADED) {
            appUpdateChannel?.invokeMethod("onFlexibleUpdateDownloaded", null)
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        // 内容延伸到状态栏/导航栏，颜色由 Flutter 层透出
        WindowCompat.setDecorFitsSystemWindows(window, false)
        super.onCreate(savedInstanceState)
        receiveDeepLink(intent)
        appUpdateManager = AppUpdateManagerFactory.create(this)
        appUpdateManager.registerListener(updateStateListener)
        showStartupOverlay()
    }

    /**
     * Flutter 首帧出现前用同款原生页面承接 Android 启动窗口，避免先白屏再切入启动寄语。
     */
    private fun showStartupOverlay() {
        if (flutterUiDisplayed) return
        val overlay = StartupQuoteOverlay.create(this)
        startupOverlay = overlay
        addContentView(
            overlay,
            ViewGroup.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT,
            ),
        )
    }

    override fun onFlutterUiDisplayed() {
        super.onFlutterUiDisplayed()
        flutterUiDisplayed = true
        startupOverlay?.let { overlay ->
            (overlay.parent as? ViewGroup)?.removeView(overlay)
        }
        startupOverlay = null
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "xuanyu/haptics")
            .setMethodCallHandler { call, result ->
                if (call.method != "nudge") {
                    result.notImplemented()
                } else {
                    try {
                        val vibrator = if (Build.VERSION.SDK_INT >= 31) {
                            (getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as VibratorManager).defaultVibrator
                        } else {
                            @Suppress("DEPRECATION")
                            (getSystemService(Context.VIBRATOR_SERVICE) as Vibrator)
                        }
                        if (vibrator.hasVibrator()) {
                            if (Build.VERSION.SDK_INT >= 29) {
                                vibrator.vibrate(VibrationEffect.createPredefined(VibrationEffect.EFFECT_TICK))
                            } else if (Build.VERSION.SDK_INT >= 26) {
                                vibrator.vibrate(VibrationEffect.createOneShot(18, 45))
                            } else {
                                @Suppress("DEPRECATION")
                                vibrator.vibrate(18)
                            }
                        }
                        result.success(null)
                    } catch (_: Exception) {
                        result.error("haptics_unavailable", "Vibration unavailable", null)
                    }
                }
            }
        deepLinkChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            DEEP_LINK_CHANNEL,
        ).also { channel ->
            channel.setMethodCallHandler { call, result ->
                when (call.method) {
                    "getInitialLink" -> {
                        result.success(pendingDeepLink)
                        pendingDeepLink = null
                    }
                    else -> result.notImplemented()
                }
            }
        }
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "xuanyu/device_abi",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "getSupportedAbis" -> result.success(Build.SUPPORTED_ABIS.toList())
                "getAbiInfo" -> {
                    val abis = Build.SUPPORTED_ABIS.toList()
                    result.success(
                        mapOf(
                            "abis" to abis,
                            "primary" to (abis.firstOrNull() ?: ""),
                            "emulator" to isProbablyEmulator(),
                            "sdkInt" to Build.VERSION.SDK_INT,
                            "manufacturer" to Build.MANUFACTURER,
                            "brand" to Build.BRAND,
                            "model" to Build.MODEL,
                        ),
                    )
                }
                else -> result.notImplemented()
            }
        }

        appUpdateChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "xuanyu/app_update",
        ).also { channel ->
            channel.setMethodCallHandler { call, result ->
                when (call.method) {
                    "startUpdate" -> startPlayCoreUpdate(
                        call.argument<Boolean>("immediate") == true,
                        result,
                    )
                    "completeFlexibleUpdate" -> {
                        appUpdateManager.completeUpdate()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
        }

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "xuanyu/voice_room_audio",
        ).setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "start" -> {
                        val title = call.argument<String>("title").orEmpty()
                        val microphone = call.argument<Boolean>("microphone") == true
                        VoiceRoomAudioService.start(applicationContext, title, microphone, call.argument<String>("owner") ?: "room", call.argument<Boolean>("camera") == true)
                        result.success(null)
                    }
                    "stop" -> {
                        VoiceRoomAudioService.stop(applicationContext, call.argument<String>("owner") ?: "room")
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            } catch (error: Exception) {
                result.error(
                    "VOICE_ROOM_AUDIO_SERVICE",
                    "无法更新语音房后台音频状态",
                    error.message,
                )
            }
        }

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "xuanyu/audio_recorder",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "startRecording" -> startAudioRecording(result)
                "stopRecording" -> stopAudioRecording(result)
                "cancelRecording" -> {
                    cancelAudioRecording()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            MEDIA_SAVE_CHANNEL,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "savePng" -> {
                    val bytes = call.argument<ByteArray>("bytes")
                    val fileName = safePngFileName(call.argument<String>("fileName"))
                    if (bytes == null || bytes.isEmpty()) {
                        result.error("IMAGE_EMPTY", "图片生成失败", null)
                    } else {
                        savePngToGallery(bytes, fileName, result)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        receiveDeepLink(intent)
    }

    private fun receiveDeepLink(intent: Intent?) {
        val uri = intent?.data ?: return
        if (uri.scheme != "xuanyu" || uri.host != "group") return
        val value = uri.toString()
        val channel = deepLinkChannel
        if (channel == null) {
            pendingDeepLink = value
        } else {
            channel.invokeMethod("onLink", value)
        }
    }

    private fun safePngFileName(raw: String?): String {
        val value = raw.orEmpty().replace(Regex("[^A-Za-z0-9_.-]"), "_")
        val base = value.ifBlank { "xuanyu_card_${System.currentTimeMillis()}.png" }
        return if (base.lowercase().endsWith(".png")) base else "$base.png"
    }

    private fun savePngToGallery(
        bytes: ByteArray,
        fileName: String,
        result: MethodChannel.Result,
    ) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            writeModernGalleryImage(bytes, fileName, result)
            return
        }
        if (pendingGallerySave != null) {
            result.error("SAVE_IN_PROGRESS", "正在保存上一张图片", null)
            return
        }
        pendingGallerySave = PendingGallerySave(bytes, fileName, result)
        try {
            val intent = Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
                addCategory(Intent.CATEGORY_OPENABLE)
                type = "image/png"
                putExtra(Intent.EXTRA_TITLE, fileName)
            }
            startActivityForResult(intent, GALLERY_DOCUMENT_REQUEST_CODE)
        } catch (error: Exception) {
            pendingGallerySave = null
            result.error("PHOTO_SAVE_FAILED", "系统文件保存界面不可用", null)
        }
    }

    private fun cancelPendingGallerySave() {
        val pending = pendingGallerySave ?: return
        pendingGallerySave = null
        pending.result.error("PHOTO_SAVE_CANCELLED", "已取消保存图片", null)
    }

    private fun writeModernGalleryImage(
        bytes: ByteArray,
        fileName: String,
        result: MethodChannel.Result,
    ) {
        var uri: android.net.Uri? = null
        try {
            val values = ContentValues().apply {
                put(MediaStore.Images.Media.DISPLAY_NAME, fileName)
                put(MediaStore.Images.Media.MIME_TYPE, "image/png")
                put(
                    MediaStore.Images.Media.RELATIVE_PATH,
                    "${Environment.DIRECTORY_PICTURES}/玄遇",
                )
                put(MediaStore.Images.Media.IS_PENDING, 1)
            }
            uri = contentResolver.insert(
                MediaStore.Images.Media.EXTERNAL_CONTENT_URI,
                values,
            ) ?: throw IllegalStateException("无法创建相册文件")
            contentResolver.openOutputStream(uri, "w")?.use { output ->
                output.write(bytes)
                output.flush()
            } ?: throw IllegalStateException("无法写入相册文件")
            values.clear()
            values.put(MediaStore.Images.Media.IS_PENDING, 0)
            contentResolver.update(uri, values, null, null)
            result.success(uri.toString())
        } catch (error: Exception) {
            uri?.let { contentResolver.delete(it, null, null) }
            result.error("PHOTO_SAVE_FAILED", "保存到相册失败", error.message)
        }
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != GALLERY_DOCUMENT_REQUEST_CODE) return
        val pending = pendingGallerySave ?: return
        pendingGallerySave = null
        val uri = data?.data
        if (resultCode != RESULT_OK || uri == null) {
            pending.result.error("PHOTO_SAVE_CANCELLED", "已取消保存图片", null)
            return
        }
        if (uri.scheme != "content") {
            pending.result.error("PHOTO_SAVE_FAILED", "系统返回的保存位置不可用", null)
            return
        }
        try {
            contentResolver.openOutputStream(uri, "w")?.use { output ->
                output.write(pending.bytes)
                output.flush()
            } ?: throw IllegalStateException("无法写入图片文件")
            pending.result.success(mapOf("uri" to uri.toString(), "destination" to "file"))
        } catch (error: Exception) {
            // ACTION_CREATE_DOCUMENT creates a new file; remove only a failed new export.
            runCatching { android.provider.DocumentsContract.deleteDocument(contentResolver, uri) }
            pending.result.error("PHOTO_SAVE_FAILED", "图片文件保存失败", null)
        }
    }

    @Suppress("DEPRECATION")
    private fun startPlayCoreUpdate(immediate: Boolean, result: MethodChannel.Result) {
        val updateType = if (immediate) AppUpdateType.IMMEDIATE else AppUpdateType.FLEXIBLE
        appUpdateManager.appUpdateInfo
            .addOnSuccessListener { info ->
                val available = info.updateAvailability() == UpdateAvailability.UPDATE_AVAILABLE
                if (!available || !info.isUpdateTypeAllowed(updateType)) {
                    result.success(mapOf("started" to false, "reason" to "not_available"))
                    return@addOnSuccessListener
                }
                try {
                    val started = appUpdateManager.startUpdateFlowForResult(
                        info,
                        updateType,
                        this,
                        APP_UPDATE_REQUEST_CODE,
                    )
                    result.success(mapOf("started" to started))
                } catch (error: Exception) {
                    result.error("PLAY_UPDATE_START", "无法启动 Google Play 更新", error.message)
                }
            }
            .addOnFailureListener { error ->
                result.error("PLAY_UPDATE_CHECK", "无法检查 Google Play 更新", error.message)
            }
    }

    @Suppress("DEPRECATION")
    override fun onResume() {
        super.onResume()
        if (!::appUpdateManager.isInitialized) return
        appUpdateManager.appUpdateInfo.addOnSuccessListener { info ->
            if (info.updateAvailability() == UpdateAvailability.DEVELOPER_TRIGGERED_UPDATE_IN_PROGRESS) {
                appUpdateManager.startUpdateFlowForResult(
                    info,
                    AppUpdateType.IMMEDIATE,
                    this,
                    APP_UPDATE_REQUEST_CODE,
                )
            }
        }
    }

    @Suppress("DEPRECATION")
    private fun startAudioRecording(result: MethodChannel.Result) {
        try {
            cancelAudioRecording()
            val output = File.createTempFile("xuanyu_voice_", ".m4a", cacheDir)
            val recorder = MediaRecorder().apply {
                setAudioSource(MediaRecorder.AudioSource.MIC)
                setOutputFormat(MediaRecorder.OutputFormat.MPEG_4)
                setAudioEncoder(MediaRecorder.AudioEncoder.AAC)
                setAudioEncodingBitRate(128000)
                setAudioSamplingRate(44100)
                setOutputFile(output.absolutePath)
                prepare()
                start()
            }
            audioRecorder = recorder
            audioRecordingPath = output.absolutePath
            result.success(null)
        } catch (error: Exception) {
            cancelAudioRecording()
            result.error("AUDIO_RECORD_START", "无法开始录音", error.message)
        }
    }

    private fun stopAudioRecording(result: MethodChannel.Result) {
        val recorder = audioRecorder
        val path = audioRecordingPath
        if (recorder == null || path == null) {
            result.error("AUDIO_RECORD_EMPTY", "当前没有正在进行的录音", null)
            return
        }
        try {
            recorder.stop()
            recorder.release()
            audioRecorder = null
            audioRecordingPath = null
            result.success(path)
        } catch (error: Exception) {
            recorder.release()
            audioRecorder = null
            audioRecordingPath = null
            File(path).delete()
            result.error("AUDIO_RECORD_STOP", "录音时间过短，请重新录制", error.message)
        }
    }

    private fun cancelAudioRecording() {
        val recorder = audioRecorder
        val path = audioRecordingPath
        if (recorder != null) {
            try {
                recorder.stop()
            } catch (_: Exception) {
            }
            recorder.release()
        }
        audioRecorder = null
        audioRecordingPath = null
        if (path != null) File(path).delete()
    }

    override fun onDestroy() {
        cancelPendingGallerySave()
        startupOverlay = null
        cancelAudioRecording()
        if (::appUpdateManager.isInitialized) {
            appUpdateManager.unregisterListener(updateStateListener)
        }
        appUpdateChannel = null
        deepLinkChannel = null
        super.onDestroy()
    }

    private fun isProbablyEmulator(): Boolean {
        val fingerprint = Build.FINGERPRINT.lowercase()
        val model = Build.MODEL.lowercase()
        val product = Build.PRODUCT.lowercase()
        val brand = Build.BRAND.lowercase()
        val device = Build.DEVICE.lowercase()
        val hardware = Build.HARDWARE.lowercase()
        val manufacturer = Build.MANUFACTURER.lowercase()
        return fingerprint.startsWith("generic") ||
            fingerprint.startsWith("unknown") ||
            model.contains("google_sdk") ||
            model.contains("emulator") ||
            model.contains("android sdk built for") ||
            model.contains("sdk_gphone") ||
            product.contains("sdk") ||
            product.contains("emulator") ||
            product.contains("google_sdk") ||
            product.contains("sdk_gphone") ||
            brand.startsWith("generic") && device.startsWith("generic") ||
            hardware.contains("goldfish") ||
            hardware.contains("ranchu") ||
            manufacturer.contains("genymotion")
    }

    companion object {
        private const val APP_UPDATE_REQUEST_CODE = 9712
        private const val DEEP_LINK_CHANNEL = "xuanyu/deep_links"
        private const val MEDIA_SAVE_CHANNEL = "xuanyu/media_save"
        private const val GALLERY_DOCUMENT_REQUEST_CODE = 9713
    }

    private data class PendingGallerySave(
        val bytes: ByteArray,
        val fileName: String,
        val result: MethodChannel.Result,
    )

}
