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
        assertEquals(0, XlogNativeBridge.nativeRelease(handle))
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

        assertTrue("keyword must exist in log file", containsKeyword(root, keyword))
        assertEquals(0, XlogNativeBridge.nativeRelease(handle))
    }

    @Test
    fun nativeRelease_thenReinit_stillWorks() {
        val ctx = InstrumentationRegistry.getInstrumentation().targetContext
        val keyword1 = "ANDROID_NATIVE_KEYWORD_REINIT_1"
        val keyword2 = "ANDROID_NATIVE_KEYWORD_REINIT_2"

        val root1 = File(ctx.filesDir, "xlog_native_test/reinit1_${System.currentTimeMillis()}")
        val cache1 = File(ctx.cacheDir, "xlog_native_test/reinit1_${System.currentTimeMillis()}")
        root1.mkdirs(); cache1.mkdirs()

        val h1 = XlogNativeBridge.nativeInit(root1.absolutePath, cache1.absolutePath, "native_reinit_1")
        assertTrue(h1 != 0L)
        assertEquals(0, XlogNativeBridge.nativeWrite(h1, 2, "NativeTest", "hello $keyword1"))
        assertEquals(0, XlogNativeBridge.nativeFlush(h1, true))
        assertTrue(containsKeyword(root1, keyword1))
        assertEquals(0, XlogNativeBridge.nativeRelease(h1))

        val root2 = File(ctx.filesDir, "xlog_native_test/reinit2_${System.currentTimeMillis()}")
        val cache2 = File(ctx.cacheDir, "xlog_native_test/reinit2_${System.currentTimeMillis()}")
        root2.mkdirs(); cache2.mkdirs()

        val h2 = XlogNativeBridge.nativeInit(root2.absolutePath, cache2.absolutePath, "native_reinit_2")
        assertTrue(h2 != 0L)
        assertEquals(0, XlogNativeBridge.nativeWrite(h2, 2, "NativeTest", "hello $keyword2"))
        assertEquals(0, XlogNativeBridge.nativeFlush(h2, true))
        assertTrue(containsKeyword(root2, keyword2))
        assertEquals(0, XlogNativeBridge.nativeRelease(h2))
    }

    private fun containsKeyword(root: File, keyword: String): Boolean {
        return root.walkTopDown()
            .filter { it.isFile }
            .any { it.readText().contains(keyword) }
    }
}
