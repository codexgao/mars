package com.codexgao.xlog_flutter_example

object XlogNativeBridge {
    init {
        System.loadLibrary("xlog_native_bridge")
    }

    external fun nativeInit(logDir: String, cacheDir: String, namePrefix: String): Long
    external fun nativeWrite(handle: Long, level: Int, tag: String, message: String): Int
    external fun nativeFlush(handle: Long, isSync: Boolean): Int
    external fun nativeRelease(handle: Long): Int
}
