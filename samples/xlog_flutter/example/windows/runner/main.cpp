#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>
#include <shlobj.h>

#include <cstdio>
#include <string>

#include "flutter_window.h"
#include "utils.h"
#include "xlog/xlog_capi.h"

// ---------------------------------------------------------------------------
// xlog native test: initialize, write logs, flush, print path, release.
// Called before Flutter engine starts to verify xlog.dll works from C++ side.
// ---------------------------------------------------------------------------
static void RunXlogNativeTest() {
    // 1. Build log directory in LocalAppData.
    char appdata_path[MAX_PATH] = {};
    if (FAILED(::SHGetFolderPathA(nullptr, CSIDL_LOCAL_APPDATA, nullptr, 0, appdata_path))) {
        std::fprintf(stderr, "[xlog-test] FAILED: SHGetFolderPathA returned error\n");
        return;
    }

    std::string log_dir = std::string(appdata_path) + "\\xlog_runner_test";

    // Create directory (best-effort; CreateDirectory returns 0 on failure, non-zero on success).
    ::CreateDirectoryA(log_dir.c_str(), nullptr);

    // 2. Configure xlog instance.
    xlog_config_t config = {};
    config.mode = XLOG_APPENDER_SYNC;            // Sync mode for immediate test output.
    config.logdir = log_dir.c_str();
    config.nameprefix = "runner";
    config.pub_key = nullptr;                     // No encryption.
    config.compress_mode = XLOG_COMPRESS_ZSTD;
    config.compress_level = 0;                    // Default compression level.
    config.cachedir = nullptr;
    config.cache_days = 0;

    uintptr_t inst = xlog_new_instance(&config, XLOG_LEVEL_VERBOSE);
    if (inst == 0) {
        std::fprintf(stderr, "[xlog-test] FAILED: xlog_new_instance returned 0\n");
        return;
    }
    std::fprintf(stdout, "[xlog-test] xlog instance created: 0x%zx\n", inst);

    // 3. Enable console log output so we can see the logs in the terminal.
    xlog_set_console_log_open(inst, 1);

    // 4. Write test logs at different levels.
    xlog_write(inst, XLOG_LEVEL_DEBUG, "RunnerTest", __FILE__, __FUNCTION__, __LINE__,
               "This is a DEBUG message from Windows runner.");
    xlog_write(inst, XLOG_LEVEL_INFO, "RunnerTest", __FILE__, __FUNCTION__, __LINE__,
               "This is an INFO message from Windows runner.");
    xlog_write(inst, XLOG_LEVEL_WARN, "RunnerTest", __FILE__, __FUNCTION__, __LINE__,
               "This is a WARN message from Windows runner.");
    xlog_write(inst, XLOG_LEVEL_ERROR, "RunnerTest", __FILE__, __FUNCTION__, __LINE__,
               "This is an ERROR message from Windows runner.");

    // 5. Flush synchronously to ensure all logs are written.
    xlog_flush(inst, /*is_sync=*/1);

    // 6. Query and print log file path.
    char path_buf[MAX_PATH] = {};
    if (xlog_get_log_path(inst, path_buf, sizeof(path_buf))) {
        std::fprintf(stdout, "[xlog-test] Log file path: %s\n", path_buf);
    } else {
        std::fprintf(stdout, "[xlog-test] Log file path: (unavailable)\n");
    }

    // 7. Release the instance.
    xlog_release_instance("runner");
    std::fprintf(stdout, "[xlog-test] xlog instance released.\n");
}

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // --- Run xlog native test (before Flutter engine starts) ---
  RunXlogNativeTest();

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 720);
  if (!window.Create(L"xlog_flutter_example", origin, size)) {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  return EXIT_SUCCESS;
}
