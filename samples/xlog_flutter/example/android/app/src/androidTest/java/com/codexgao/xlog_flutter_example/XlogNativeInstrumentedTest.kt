package com.codexgao.xlog_flutter_example

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.assertNotEquals
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File

@RunWith(AndroidJUnit4::class)
class XlogNativeInstrumentedTest {
    @Test
    fun nativeInit_returnsNonZeroHandle() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val logDir = File(context.filesDir, "xlog-native-test-logs").absolutePath
        val cacheDir = File(context.cacheDir, "xlog-native-test-cache").absolutePath
        val namePrefix = "native-test"

        val handle = XlogNativeBridge.nativeInit(logDir, cacheDir, namePrefix)
        assertNotEquals(0L, handle)
    }
}
