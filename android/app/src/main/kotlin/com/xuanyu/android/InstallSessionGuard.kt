package com.xuanyu.android

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import java.security.KeyStore
import javax.crypto.KeyGenerator

/**
 * 防止 Android/OEM 在卸载重装后把旧登录 Token 一并恢复。
 *
 * AndroidKeyStore 中的应用密钥在卸载时会被系统删除，且不会进入云备份。
 * SharedPreferences 中只保存“本安装已绑定”的标志：如果标志被恢复但密钥
 * 不存在，就说明当前是一次重装/数据恢复，此时必须清掉旧的登录与应用数据。
 *
 * 从没有该机制的旧版本正常覆盖升级时，标志和密钥都不存在，只会建立绑定，
 * 不会让正在使用的用户无故退出。
 */
object InstallSessionGuard {
    private const val KEY_ALIAS = "xuanyu_install_session_v1"
    private const val PREF_BOUND = "flutter.install_session_bound_v1"

    fun verify(context: Context) {
        val prefs = PrivacyConsentStore.prefs(context)
        val wasBound = prefs.getBoolean(PREF_BOUND, false)
        val keyExists = hasInstallKey()

        if (wasBound && keyExists == false) {
            // 恢复的数据属于已经卸载的旧安装。清空 Token、已保存账号、档案索引
            // 及隐私同意状态，让本次安装从干净登录流程开始。
            prefs.edit().clear().commit()
            clearRestoredPrivateFiles(context)
        }

        val keyReady = keyExists == true ||
            (keyExists == false && createInstallKey())
        if (keyReady) {
            prefs.edit().putBoolean(PREF_BOUND, true).commit()
        }
    }

    /** null 表示 KeyStore 暂时不可用，此时不误判为重装，也不清用户登录。 */
    private fun hasInstallKey(): Boolean? = try {
        val keyStore = KeyStore.getInstance("AndroidKeyStore")
        keyStore.load(null)
        keyStore.containsAlias(KEY_ALIAS)
    } catch (_: Exception) {
        null
    }

    private fun createInstallKey(): Boolean = try {
        val generator = KeyGenerator.getInstance(
            KeyProperties.KEY_ALGORITHM_AES,
            "AndroidKeyStore",
        )
        generator.init(
            KeyGenParameterSpec.Builder(
                KEY_ALIAS,
                KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT,
            )
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .build(),
        )
        generator.generateKey()
        true
    } catch (_: Exception) {
        // 个别系统的 KeyStore 暂时不可用时，备份禁用规则仍会阻止常规恢复。
        false
    }

    private fun clearRestoredPrivateFiles(context: Context) {
        try {
            context.filesDir.listFiles()?.forEach { file -> file.deleteRecursively() }
        } catch (_: Exception) {
            // SharedPreferences 已先清空，文件清理失败也不会恢复登录态。
        }
        try {
            context.cacheDir.listFiles()?.forEach { file -> file.deleteRecursively() }
        } catch (_: Exception) {
        }
    }
}
