package com.xuanyu.android

import android.content.Context
import android.content.SharedPreferences
import java.time.Instant

/**
 * 与 Dart [AppConstants] / SharedPreferences.getInstance() 共用同一份偏好。
 *
 * 存储文件：FlutterSharedPreferences
 * Key 前缀：flutter.
 * 版本拼接：userAgreementVersion|privacyPolicyVersion
 *
 * 改协议版本时必须同步 [lib/core/constants/app_constants.dart]。
 */
object PrivacyConsentStore {
    const val PREFS_NAME = "FlutterSharedPreferences"
    const val KEY_PREFIX = "flutter."
    const val KEY_ACCEPTED = KEY_PREFIX + "agreement_accepted"
    const val KEY_ACCEPTED_AT = KEY_PREFIX + "agreement_accepted_at"
    const val KEY_VERSION = KEY_PREFIX + "agreement_version"

    const val USER_AGREEMENT_VERSION = "2026-10-02"
    const val PRIVACY_POLICY_VERSION = "2026-10-14"
    const val ACCEPTED_VERSION = "$USER_AGREEMENT_VERSION|$PRIVACY_POLICY_VERSION"

    fun prefs(context: Context): SharedPreferences {
        return context.applicationContext.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
    }

    fun hasValidConsent(context: Context): Boolean {
        val stored = prefs(context)
        return stored.getBoolean(KEY_ACCEPTED, false) &&
            stored.getString(KEY_VERSION, null) == ACCEPTED_VERSION
    }

    fun persistConsent(context: Context) {
        prefs(context).edit()
            .putBoolean(KEY_ACCEPTED, true)
            .putString(KEY_ACCEPTED_AT, Instant.now().toString())
            .putString(KEY_VERSION, ACCEPTED_VERSION)
            .commit()
    }
}
