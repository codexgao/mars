package com.codexgao.xlog_flutter_example

import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import android.util.Log
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import com.codexgao.xlog_flutter.XLog
import com.codexgao.xlog_flutter.XLogConfig
import com.codexgao.xlog_flutter.XLogLevel
import io.flutter.embedding.android.FlutterActivity
import java.io.File

/**
 * XLog Android Native API 使用示例
 */
class MainActivity : FlutterActivity() {

    companion object {
        private const val TAG = "XLogExample"
        private const val REQUEST_CODE_STORAGE = 1001
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // 检查并申请存储权限
        if (checkStoragePermission()) {
            initXLog()
        }
    }

    /**
     * 检查存储权限，Android 6.0+ 需要运行时申请
     */
    private fun checkStoragePermission(): Boolean {
        // Android 10+ 使用 Scoped Storage，无需运行时权限
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            return true
        }

        val permissions = arrayOf(
            Manifest.permission.WRITE_EXTERNAL_STORAGE,
            Manifest.permission.READ_EXTERNAL_STORAGE
        )

        val needPermissions = permissions.filter {
            ContextCompat.checkSelfPermission(this, it) != PackageManager.PERMISSION_GRANTED
        }

        return if (needPermissions.isNotEmpty()) {
            ActivityCompat.requestPermissions(this, needPermissions.toTypedArray(), REQUEST_CODE_STORAGE)
            false
        } else {
            true
        }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == REQUEST_CODE_STORAGE) {
            if (grantResults.all { it == PackageManager.PERMISSION_GRANTED }) {
                Log.i(TAG, "Storage permission granted")
                initXLog()
            } else {
                Log.e(TAG, "Storage permission denied, XLog will use internal storage")
                // 权限被拒绝，使用内部存储作为降级方案
                initXLog(useInternalStorage = true)
            }
        }
    }

    /**
     * 初始化 XLog
     */
    private fun initXLog(useInternalStorage: Boolean = false) {
        try {
            testXLog(useInternalStorage)
        } catch (e: Exception) {
            Log.e(TAG, "XLog test failed", e)
        }
    }

    private fun testXLog(useInternalStorage: Boolean = false) {
        // 创建日志目录
        val logDir = if (useInternalStorage) {
            File(filesDir, "xlog_test") // 内部存储降级方案
        } else {
            File(getExternalFilesDir(null), "xlog_test") // 外部存储/sdcard
        }.apply {
            if (!exists()) mkdirs()
        }
        Log.i(TAG, "Log directory: ${logDir.absolutePath}")

        // 创建配置
        val config = XLogConfig(logDir.absolutePath, "testapp")
        Log.i(TAG, "Config created: logdir=${config.logdir}, nameprefix=${config.nameprefix}")

        // 创建实例
        val instance = XLog.newInstance(config, XLogLevel.DEBUG)
        Log.i(TAG, "XLog instance created: $instance")

        if (instance == 0L) {
            Log.e(TAG, "Failed to create XLog instance")
            return
        }

        // 写日志
        XLog.i(instance, TAG, "Hello from XLog Kotlin API!")
        Log.i(TAG, "Log written")

        // 获取日志路径
        val logPath = XLog.getLogPath(instance)
        Log.i(TAG, "Log path: $logPath")

        // 刷新
        XLog.flush(instance, sync = true)
        Log.i(TAG, "Log flushed")

        // 释放
        XLog.releaseInstance("testapp")
        Log.i(TAG, "XLog released")
    }
}
