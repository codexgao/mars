package com.codexgao.xlog_flutter_example

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
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

    @Test
    fun nativeWrite_generatesFile_andContainsKeyword() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val keyword = "ANDROID_NATIVE_KEYWORD_001"
        val root = File(context.filesDir, "xlog_native_test/keyword_${System.currentTimeMillis()}")
        val cache = File(context.cacheDir, "xlog_native_test/keyword_${System.currentTimeMillis()}")
        root.mkdirs()
        cache.mkdirs()

        val handle = XlogNativeBridge.nativeInit(root.absolutePath, cache.absolutePath, "native_keyword")
        assertTrue(handle != 0L)
        assertEquals(0, XlogNativeBridge.nativeWrite(handle, 2, "NativeTest", "hello $keyword"))
        assertEquals(0, XlogNativeBridge.nativeFlush(handle, true))

        val anyHit = root.walkTopDown()
            .filter { it.isFile }
            .any { it.readText().contains(keyword) }
        assertTrue("keyword must exist in log file", anyHit)
        assertEquals(0, XlogNativeBridge.nativeRelease(handle))
    }
}
