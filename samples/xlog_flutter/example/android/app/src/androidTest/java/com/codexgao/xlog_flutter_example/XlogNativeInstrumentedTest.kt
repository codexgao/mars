package com.codexgao.xlog_flutter_example

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.codexgao.xlog_flutter.XLog
import com.codexgao.xlog_flutter.XLogAppenderMode
import com.codexgao.xlog_flutter.XLogCompressMode
import com.codexgao.xlog_flutter.XLogConfig
import com.codexgao.xlog_flutter.XLogLevel
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import java.io.ByteArrayOutputStream
import java.io.File
import java.util.zip.DataFormatException
import java.util.zip.Inflater

/**
 * XLog Kotlin API  instrumented tests
 * Tests the JNA-based native API
 */
@RunWith(AndroidJUnit4::class)
class XlogNativeInstrumentedTest {

    @Test
    fun newInstance_returnsNonZeroHandle() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val logDir = File(context.filesDir, "xlog-test-logs").apply { mkdirs() }

        val config = XLogConfig(logDir.absolutePath, "test-instance")
        val handle = XLog.newInstance(config, XLogLevel.DEBUG)

        assertNotEquals("Handle should not be zero", 0L, handle)

        // Cleanup
        XLog.releaseInstance("test-instance")
    }

    @Test
    fun writeLog_generatesFile_andContainsKeyword() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val keyword = "KOTLIN_API_KEYWORD_001"
        val logDir = File(context.filesDir, "xlog_test/keyword_${System.currentTimeMillis()}").apply { mkdirs() }

        val config = XLogConfig(logDir.absolutePath, "keyword_test")
        val handle = XLog.newInstance(config, XLogLevel.DEBUG)
        assertTrue("Handle should be valid", handle != 0L)

        // Write log
        XLog.i(handle, "TestTag", "Test message with keyword: $keyword")

        // Flush synchronously
        XLog.flush(handle, sync = true)

        // Verify keyword exists in log file
        assertTrue("Keyword must exist in log file", containsKeyword(logDir, keyword))

        // Cleanup
        XLog.releaseInstance("keyword_test")
    }

    @Test
    fun logLevel_filteringWorks() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val keywordDebug = "DEBUG_LEVEL_TEST"
        val keywordWarn = "WARN_LEVEL_TEST"
        val logDir = File(context.filesDir, "xlog_test/level_${System.currentTimeMillis()}").apply { mkdirs() }

        val config = XLogConfig(logDir.absolutePath, "level_test")
        val handle = XLog.newInstance(config, XLogLevel.DEBUG)
        assertTrue("Handle should be valid", handle != 0L)

        // Set level to WARN
        XLog.setLevel(handle, XLogLevel.WARN)
        assertEquals("Level should be WARN", XLogLevel.WARN, XLog.getLevel(handle))

        // Debug message should be filtered
        XLog.d(handle, "TestTag", "Debug: $keywordDebug")

        // Warning message should pass
        XLog.w(handle, "TestTag", "Warning: $keywordWarn")

        XLog.flush(handle, sync = true)

        // Verify only warning keyword exists
        assertFalse("Debug keyword should NOT exist", containsKeyword(logDir, keywordDebug))
        assertTrue("Warning keyword SHOULD exist", containsKeyword(logDir, keywordWarn))

        // Cleanup
        XLog.releaseInstance("level_test")
    }

    @Test
    fun getInstance_returnsExistingInstance() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val logDir = File(context.filesDir, "xlog_test/get_instance").apply { mkdirs() }

        val config = XLogConfig(logDir.absolutePath, "existing_instance")
        val handle1 = XLog.newInstance(config, XLogLevel.DEBUG)
        assertTrue("First handle should be valid", handle1 != 0L)

        // Check instance exists
        assertTrue("Instance should exist", XLog.hasInstance("existing_instance"))

        // Get existing instance
        val handle2 = XLog.getInstance("existing_instance")
        assertTrue("Second handle should be valid", handle2 != 0L)

        // They should be the same instance
        assertEquals("Handles should be equal", handle1, handle2)

        // Cleanup
        XLog.releaseInstance("existing_instance")
        assertFalse("Instance should not exist after release", XLog.hasInstance("existing_instance"))
    }

    @Test
    fun getLogPath_returnsValidPath() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val logDir = File(context.filesDir, "xlog_test/path_test").apply { mkdirs() }

        val config = XLogConfig(logDir.absolutePath, "path_test")
        val handle = XLog.newInstance(config, XLogLevel.DEBUG)
        assertTrue("Handle should be valid", handle != 0L)

        // Write a log to ensure file is created
        XLog.i(handle, "TestTag", "Test message")
        XLog.flush(handle, sync = true)

        // Get log path
        val path = XLog.getLogPath(handle)
        assertNotNull("Log path should not be null", path)
        assertTrue("Log path should not be empty", !path.isNullOrEmpty())

        // Cleanup
        XLog.releaseInstance("path_test")
    }

    @Test
    fun flushAll_flushesAllInstances() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val logDir = File(context.filesDir, "xlog_test/flush_all").apply { mkdirs() }

        val config1 = XLogConfig(logDir.absolutePath, "instance1")
        val config2 = XLogConfig(logDir.absolutePath, "instance2")

        val handle1 = XLog.newInstance(config1, XLogLevel.DEBUG)
        val handle2 = XLog.newInstance(config2, XLogLevel.DEBUG)

        assertTrue("Handle1 should be valid", handle1 != 0L)
        assertTrue("Handle2 should be valid", handle2 != 0L)

        // Write to both instances
        XLog.i(handle1, "Test", "Message from instance 1")
        XLog.i(handle2, "Test", "Message from instance 2")

        // Flush all
        XLog.flushAll(sync = true)

        // Cleanup
        XLog.releaseInstance("instance1")
        XLog.releaseInstance("instance2")
    }

    @Test
    fun setLevel_andGetLevel_matchRoundtrip() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val logDir = File(context.filesDir, "xlog_test/setlevel_${System.currentTimeMillis()}").apply { mkdirs() }

        val config = XLogConfig(logDir.absolutePath, "setlevel_test")
        val handle = XLog.newInstance(config, XLogLevel.DEBUG)
        assertTrue("Handle should be valid", handle != 0L)

        // Set each level and verify getLevel returns the same
        for (level in listOf(XLogLevel.VERBOSE, XLogLevel.INFO, XLogLevel.ERROR, XLogLevel.NONE)) {
            XLog.setLevel(handle, level)
            assertEquals("getLevel should return $level after setLevel", level, XLog.getLevel(handle))
        }

        // Cleanup
        XLog.releaseInstance("setlevel_test")
    }

    @Test
    fun setAppenderMode_sync_doesNotCrash() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val logDir = File(context.filesDir, "xlog_test/appmode_${System.currentTimeMillis()}").apply { mkdirs() }

        val config = XLogConfig(logDir.absolutePath, "appmode_test")
        val handle = XLog.newInstance(config, XLogLevel.DEBUG)
        assertTrue("Handle should be valid", handle != 0L)

        // Switch to sync mode — must not throw
        XLog.setAppenderMode(handle, XLogAppenderMode.SYNC)
        XLog.i(handle, "TestTag", "Message in sync mode")

        // Switch back to async mode — must not throw
        XLog.setAppenderMode(handle, XLogAppenderMode.ASYNC)
        XLog.i(handle, "TestTag", "Message in async mode")

        XLog.flush(handle, sync = true)

        // Cleanup
        XLog.releaseInstance("appmode_test")
    }

    @Test
    fun setConsoleLogOpen_trueAndFalse_doesNotCrash() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val logDir = File(context.filesDir, "xlog_test/console_${System.currentTimeMillis()}").apply { mkdirs() }

        val config = XLogConfig(logDir.absolutePath, "console_test")
        val handle = XLog.newInstance(config, XLogLevel.DEBUG)
        assertTrue("Handle should be valid", handle != 0L)

        // Enable console log — must not throw
        XLog.setConsoleLogOpen(handle, true)
        XLog.i(handle, "TestTag", "Message with console open")

        // Disable console log — must not throw
        XLog.setConsoleLogOpen(handle, false)
        XLog.i(handle, "TestTag", "Message with console closed")

        XLog.flush(handle, sync = true)

        // Cleanup
        XLog.releaseInstance("console_test")
    }

    @Test
    fun flush_async_doesNotCrash() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val logDir = File(context.filesDir, "xlog_test/flush_async_${System.currentTimeMillis()}").apply { mkdirs() }

        val config = XLogConfig(logDir.absolutePath, "flush_async_test")
        val handle = XLog.newInstance(config, XLogLevel.DEBUG)
        assertTrue("Handle should be valid", handle != 0L)

        XLog.i(handle, "TestTag", "Message before async flush")

        // Asynchronous flush — must not throw
        XLog.flush(handle, sync = false)

        // Give the async flush a moment then do a sync flush to ensure data is written
        Thread.sleep(200)
        XLog.flush(handle, sync = true)

        // Cleanup
        XLog.releaseInstance("flush_async_test")
    }

    @Test
    fun flushAll_async_doesNotCrash() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val logDir = File(context.filesDir, "xlog_test/flushall_async_${System.currentTimeMillis()}").apply { mkdirs() }

        val config = XLogConfig(logDir.absolutePath, "flushall_async_test")
        val handle = XLog.newInstance(config, XLogLevel.DEBUG)
        assertTrue("Handle should be valid", handle != 0L)

        XLog.i(handle, "TestTag", "Message before flushAll async")

        // Asynchronous flushAll — must not throw
        XLog.flushAll(sync = false)

        // Give the async flush a moment then do a sync flushAll to ensure data is written
        Thread.sleep(200)
        XLog.flushAll(sync = true)

        // Cleanup
        XLog.releaseInstance("flushall_async_test")
    }

    @Test
    fun getLogPath_containsNameprefix() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val nameprefix = "prefixcheck_test"
        val logDir = File(context.filesDir, "xlog_test/prefixcheck_${System.currentTimeMillis()}").apply { mkdirs() }

        val config = XLogConfig(logDir.absolutePath, nameprefix)
        val handle = XLog.newInstance(config, XLogLevel.DEBUG)
        assertTrue("Handle should be valid", handle != 0L)

        // Write and flush to ensure a log file is created
        XLog.i(handle, "TestTag", "Message for path check")
        XLog.flush(handle, sync = true)

        val path = XLog.getLogPath(handle)
        assertNotNull("Log path should not be null", path)
        assertTrue("Log path should contain nameprefix '$nameprefix'", path!!.contains(nameprefix))

        // Cleanup
        XLog.releaseInstance(nameprefix)
    }

    @Test
    fun zstdCompression_fileCreated() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val logDir = File(context.filesDir, "xlog_test/zstd_${System.currentTimeMillis()}").apply { mkdirs() }

        val config = XLogConfig(logDir.absolutePath, "zstd_test").apply {
            compress_mode = XLogCompressMode.ZSTD.value
        }
        val handle = XLog.newInstance(config, XLogLevel.DEBUG)
        assertTrue("Handle should be valid", handle != 0L)

        // Write several messages to trigger a file flush
        repeat(5) { i ->
            XLog.i(handle, "TestTag", "Zstd test message #$i")
        }
        XLog.flush(handle, sync = true)

        // At least one log file must have been created in the log directory
        val files = logDir.listFiles { f -> f.isFile && f.length() > 0 }
        assertNotNull("Log directory file listing should not be null", files)
        assertTrue("At least one non-empty log file should be created with zstd compression", files!!.isNotEmpty())

        // Cleanup
        XLog.releaseInstance("zstd_test")
    }

    @Test
    fun destroyInstance_doesNotCrash() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val logDir = File(context.filesDir, "xlog_test/destroy_${System.currentTimeMillis()}").apply { mkdirs() }

        val config = XLogConfig(logDir.absolutePath, "destroy_test")
        val handle = XLog.newInstance(config, XLogLevel.DEBUG)
        assertTrue("Handle should be valid", handle != 0L)

        XLog.i(handle, "TestTag", "Message before destroyInstance")
        XLog.flush(handle, sync = true)

        // destroyInstance via handle — must not throw
        XLog.destroyInstance(handle)
    }

    // ==================== Helper Methods ====================

    private fun containsKeyword(root: File, keyword: String): Boolean {
        return root.walkTopDown()
            .filter { it.isFile && it.length() > 0 }
            .any { file -> decodeXlogFile(file).contains(keyword) }
    }

    private fun decodeXlogFile(file: File): String {
        val data = file.readBytes()
        val out = ByteArrayOutputStream()
        var offset = 0

        while (offset < data.size) {
            val magic = data[offset].toInt() and 0xFF
            val keyLen = when (magic) {
                0x03, 0x04, 0x05 -> 4
                0x06, 0x07, 0x08, 0x09, 0x0A, 0x0B, 0x0C, 0x0D -> 64
                else -> {
                    offset += 1
                    continue
                }
            }

            val headerLen = 1 + 2 + 1 + 1 + 4 + keyLen
            if (offset + headerLen + 1 > data.size) break

            val length = readUInt32LE(data, offset + 5)
            val payloadStart = offset + headerLen
            val payloadEnd = payloadStart + length
            if (length < 0 || payloadEnd >= data.size) {
                offset += 1
                continue
            }

            if ((data[payloadEnd].toInt() and 0xFF) != 0x00) {
                offset += 1
                continue
            }

            var payload = data.copyOfRange(payloadStart, payloadEnd)
            payload = when (magic) {
                0x04, 0x09 -> inflateRaw(payload)
                else -> payload
            }

            out.write(payload)
            offset = payloadEnd + 1
        }

        return out.toByteArray().toString(Charsets.UTF_8)
    }

    private fun readUInt32LE(data: ByteArray, pos: Int): Int {
        return (data[pos].toInt() and 0xFF) or
            ((data[pos + 1].toInt() and 0xFF) shl 8) or
            ((data[pos + 2].toInt() and 0xFF) shl 16) or
            ((data[pos + 3].toInt() and 0xFF) shl 24)
    }

    private fun inflateRaw(input: ByteArray): ByteArray {
        val inflater = Inflater(true)
        return try {
            inflater.setInput(input)
            val out = ByteArrayOutputStream()
            val buf = ByteArray(4096)
            while (!inflater.finished()) {
                val count = inflater.inflate(buf)
                if (count == 0) {
                    if (inflater.needsInput()) break
                } else {
                    out.write(buf, 0, count)
                }
            }
            out.toByteArray()
        } catch (_: DataFormatException) {
            input
        } finally {
            inflater.end()
        }
    }
}
