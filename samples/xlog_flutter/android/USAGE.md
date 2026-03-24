# XLog Android Kotlin API 使用说明

## 简介

xlog_flutter 插件为 Android 平台提供了 **Kotlin API**，使用 **JNA** 直接绑定 C API，无需编写 JNI 代码。

## 依赖

插件已自动添加 JNA 依赖，无需额外配置。

```gradle
dependencies {
    implementation 'net.java.dev.jna:jna:5.13.0@aar'
}
```

## 使用方法

### 1. 创建日志实例

```kotlin
import com.codexgao.xlog_flutter.XLog
import com.codexgao.xlog_flutter.XLogConfig
import com.codexgao.xlog_flutter.XLogLevel
import com.codexgao.xlog_flutter.XLogAppenderMode
import com.codexgao.xlog_flutter.XLogCompressMode
import java.io.File

// 创建配置
val config = XLogConfig().apply {
    logdir = File(filesDir, "xlog").absolutePath  // 日志目录（必需）
    nameprefix = "myapp"                           // 实例名称前缀（必需）
    mode = XLogAppenderMode.ASYNC.value            // 0=异步, 1=同步
    compress_mode = XLogCompressMode.ZLIB.value    // 0=zlib, 1=zstd
    compress_level = 6                             // 压缩级别 0-9
}

// 创建实例
val instance = XLog.newInstance(config, XLogLevel.DEBUG)
```

### 2. 写入日志

```kotlin
// 使用便捷方法
XLog.v(instance, "TAG", "Verbose message")
XLog.d(instance, "TAG", "Debug message")
XLog.i(instance, "TAG", "Info message")
XLog.w(instance, "TAG", "Warning message")
XLog.e(instance, "TAG", "Error message")
XLog.f(instance, "TAG", "Fatal message")

// 或使用原生方法（可以指定文件名、行号等）
XLog.write(
    instance, 
    XLogLevel.INFO,
    "TAG", 
    "Application started",
    filename = "MainActivity.kt",
    funcname = "onCreate",
    line = 25
)
```

### 3. 控制日志级别

```kotlin
// 检查日志级别是否启用
val enabled = XLog.isEnabledFor(instance, XLogLevel.INFO)

// 获取当前日志级别
val currentLevel = XLog.getLevel(instance)

// 设置日志级别
XLog.setLevel(instance, XLogLevel.WARN)
```

### 4. 刷新和关闭

```kotlin
// 刷新日志缓冲区（同步）
XLog.flush(instance, sync = true)

// 刷新所有实例
XLog.flushAll(sync = true)

// 获取当前日志文件路径
val logPath = XLog.getLogPath(instance)

// 关闭实例
XLog.releaseInstance("myapp")
// 或
XLog.destroyInstance(instance)
```

### 5. 获取已有实例

```kotlin
// 检查实例是否存在
if (XLog.hasInstance("myapp")) {
    // 获取已有实例
    val existingInstance = XLog.getInstance("myapp")
}
```

## 完整示例

```kotlin
class MainActivity : AppCompatActivity() {
    private var xlogInstance: Long = 0

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // 初始化日志
        val logDir = File(filesDir, "xlog").apply { mkdirs() }
        
        val config = XLogConfig(logDir.absolutePath, "myapp")
        xlogInstance = XLog.newInstance(config, XLogLevel.DEBUG)

        XLog.i(xlogInstance, "MainActivity", "onCreate called")
    }

    override fun onDestroy() {
        // 刷新并关闭日志
        XLog.flush(xlogInstance, sync = true)
        XLog.releaseInstance("myapp")
        super.onDestroy()
    }
}
```

## API 对应关系

| Kotlin API | C API (xlog_capi.h) |
|------------|---------------------|
| `XLog.newInstance()` | `xlog_new_instance()` |
| `XLog.getInstance()` | `xlog_get_instance()` |
| `XLog.hasInstance()` | `xlog_has_instance()` |
| `XLog.releaseInstance()` | `xlog_release_instance()` |
| `XLog.destroyInstance()` | `xlog_destroy_instance()` |
| `XLog.write()` | `xlog_write()` |
| `XLog.isEnabledFor()` | `xlog_is_enabled_for()` |
| `XLog.getLevel()` | `xlog_get_level()` |
| `XLog.setLevel()` | `xlog_set_level()` |
| `XLog.setAppenderMode()` | `xlog_set_appender_mode()` |
| `XLog.setConsoleLogOpen()` | `xlog_set_console_log_open()` |
| `XLog.flush()` | `xlog_flush()` |
| `XLog.flushAll()` | `xlog_flush_all()` |
| `XLog.getLogPath()` | `xlog_get_log_path()` |

## 注意事项

1. **权限**: 确保应用有写入外部存储的权限（如果使用外部存储目录）
2. **库加载**: Kotlin API 会自动加载 `libxlog.so`，无需手动调用 `System.loadLibrary()`
3. **线程安全**: xlog 是线程安全的，可以在多线程环境中使用
4. **资源释放**: 应用退出前建议调用 `flush()` 和 `releaseInstance()` 确保日志写入完整
5. **JNA 依赖**: 插件已包含 JNA 依赖，约增加 1-2MB 包体积

## 技术说明

本实现使用 **JNA (Java Native Access)** 直接绑定 C API，相比传统 JNI 方案：

- ✅ 无需编写 C++ JNI 代码
- ✅ 与 Dart FFI 架构一致
- ✅ 维护更简单，修改 C API 时只需更新 Kotlin 接口
- ⚠️ 性能略低于原生 JNI
