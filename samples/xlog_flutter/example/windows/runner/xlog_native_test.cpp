// xlog_native_test.cpp - Windows C API test (TODO: verify on target platform)
// Build: cl /EHsc xlog_native_test.cpp /Fe:xlog_native_test.exe xlog.lib
// Run:   xlog_native_test.exe (xlog.dll must be in PATH)

#ifdef _WIN32

#include <windows.h>
#include <iostream>
#include <cassert>
#include <string>
#include <filesystem>

#include "../../include/xlog/xlog_capi.h"

// Simple test runner
static int g_pass = 0;
static int g_fail = 0;

#define TEST(name) void name()
#define RUN(name) do { \
  try { name(); g_pass++; std::cout << "PASS: " #name "\n"; } \
  catch (const std::exception& e) { g_fail++; std::cerr << "FAIL: " #name " - " << e.what() << "\n"; } \
} while(0)
#define ASSERT(cond) do { if (!(cond)) throw std::runtime_error("Assertion failed: " #cond); } while(0)

static std::string getTempDir() {
  char buf[MAX_PATH];
  GetTempPathA(MAX_PATH, buf);
  std::string dir = std::string(buf) + "xlog_win_test\\";
  std::filesystem::create_directories(dir);
  return dir;
}

TEST(test_new_instance_returns_valid_handle) {
  std::string logDir = getTempDir();
  xlog_config_t cfg = {};
  cfg.mode = XLOG_APPENDER_MODE_ASYNC;
  cfg.logdir = logDir.c_str();
  cfg.nameprefix = "test_new";
  cfg.compress_mode = XLOG_COMPRESS_MODE_ZLIB;
  
  xlog_handle_t h = xlog_new_instance(&cfg);
  ASSERT(h != nullptr);
  xlog_release_instance("test_new");
}

TEST(test_has_instance_after_open) {
  std::string logDir = getTempDir();
  xlog_config_t cfg = {};
  cfg.mode = XLOG_APPENDER_MODE_ASYNC;
  cfg.logdir = logDir.c_str();
  cfg.nameprefix = "test_has";
  cfg.compress_mode = XLOG_COMPRESS_MODE_ZLIB;
  
  xlog_new_instance(&cfg);
  ASSERT(xlog_has_instance("test_has") == true);
  xlog_release_instance("test_has");
  ASSERT(xlog_has_instance("test_has") == false);
}

TEST(test_write_all_levels) {
  std::string logDir = getTempDir();
  xlog_config_t cfg = {};
  cfg.mode = XLOG_APPENDER_MODE_SYNC;
  cfg.logdir = logDir.c_str();
  cfg.nameprefix = "test_write";
  cfg.compress_mode = XLOG_COMPRESS_MODE_ZLIB;
  
  xlog_handle_t h = xlog_new_instance(&cfg);
  xlog_write(h, XLOG_LEVEL_VERBOSE, "tag", __FILE__, __FUNCTION__, __LINE__, "verbose");
  xlog_write(h, XLOG_LEVEL_DEBUG, "tag", __FILE__, __FUNCTION__, __LINE__, "debug");
  xlog_write(h, XLOG_LEVEL_INFO, "tag", __FILE__, __FUNCTION__, __LINE__, "info");
  xlog_write(h, XLOG_LEVEL_WARN, "tag", __FILE__, __FUNCTION__, __LINE__, "warn");
  xlog_write(h, XLOG_LEVEL_ERROR, "tag", __FILE__, __FUNCTION__, __LINE__, "error");
  xlog_write(h, XLOG_LEVEL_FATAL, "tag", __FILE__, __FUNCTION__, __LINE__, "fatal");
  xlog_flush(h, true);
  xlog_release_instance("test_write");
}

TEST(test_get_set_level) {
  std::string logDir = getTempDir();
  xlog_config_t cfg = {};
  cfg.mode = XLOG_APPENDER_MODE_SYNC;
  cfg.logdir = logDir.c_str();
  cfg.nameprefix = "test_level";
  cfg.compress_mode = XLOG_COMPRESS_MODE_ZLIB;
  
  xlog_handle_t h = xlog_new_instance(&cfg);
  xlog_set_level(h, XLOG_LEVEL_DEBUG);
  ASSERT(xlog_get_level(h) == XLOG_LEVEL_DEBUG);
  ASSERT(xlog_is_enabled_for(h, XLOG_LEVEL_DEBUG) == true);
  ASSERT(xlog_is_enabled_for(h, XLOG_LEVEL_VERBOSE) == false);
  xlog_release_instance("test_level");
}

TEST(test_set_appender_mode) {
  std::string logDir = getTempDir();
  xlog_config_t cfg = {};
  cfg.mode = XLOG_APPENDER_MODE_ASYNC;
  cfg.logdir = logDir.c_str();
  cfg.nameprefix = "test_appender";
  cfg.compress_mode = XLOG_COMPRESS_MODE_ZLIB;
  
  xlog_handle_t h = xlog_new_instance(&cfg);
  xlog_set_appender_mode(h, XLOG_APPENDER_MODE_SYNC);
  xlog_set_appender_mode(h, XLOG_APPENDER_MODE_ASYNC);
  xlog_release_instance("test_appender");
}

TEST(test_set_console_log_open) {
  std::string logDir = getTempDir();
  xlog_config_t cfg = {};
  cfg.mode = XLOG_APPENDER_MODE_ASYNC;
  cfg.logdir = logDir.c_str();
  cfg.nameprefix = "test_console";
  cfg.compress_mode = XLOG_COMPRESS_MODE_ZLIB;
  
  xlog_handle_t h = xlog_new_instance(&cfg);
  xlog_set_console_log_open(h, true);
  xlog_set_console_log_open(h, false);
  xlog_release_instance("test_console");
}

TEST(test_flush_sync_async) {
  std::string logDir = getTempDir();
  xlog_config_t cfg = {};
  cfg.mode = XLOG_APPENDER_MODE_ASYNC;
  cfg.logdir = logDir.c_str();
  cfg.nameprefix = "test_flush";
  cfg.compress_mode = XLOG_COMPRESS_MODE_ZLIB;
  
  xlog_handle_t h = xlog_new_instance(&cfg);
  xlog_write(h, XLOG_LEVEL_INFO, "tag", __FILE__, __FUNCTION__, __LINE__, "msg");
  xlog_flush(h, false);
  Sleep(200);
  xlog_flush(h, true);
  xlog_release_instance("test_flush");
}

TEST(test_flush_all) {
  std::string logDir = getTempDir();
  xlog_config_t cfg1 = {};
  cfg1.mode = XLOG_APPENDER_MODE_ASYNC;
  cfg1.logdir = logDir.c_str();
  cfg1.nameprefix = "test_flushall_1";
  cfg1.compress_mode = XLOG_COMPRESS_MODE_ZLIB;
  
  xlog_config_t cfg2 = {};
  cfg2.mode = XLOG_APPENDER_MODE_ASYNC;
  cfg2.logdir = logDir.c_str();
  cfg2.nameprefix = "test_flushall_2";
  cfg2.compress_mode = XLOG_COMPRESS_MODE_ZLIB;
  
  xlog_handle_t h1 = xlog_new_instance(&cfg1);
  xlog_handle_t h2 = xlog_new_instance(&cfg2);
  xlog_write(h1, XLOG_LEVEL_INFO, "tag", "", "", 0, "msg1");
  xlog_write(h2, XLOG_LEVEL_INFO, "tag", "", "", 0, "msg2");
  xlog_flush_all(true);
  xlog_release_instance("test_flushall_1");
  xlog_release_instance("test_flushall_2");
}

TEST(test_get_log_path) {
  std::string logDir = getTempDir();
  xlog_config_t cfg = {};
  cfg.mode = XLOG_APPENDER_MODE_SYNC;
  cfg.logdir = logDir.c_str();
  cfg.nameprefix = "test_logpath";
  cfg.compress_mode = XLOG_COMPRESS_MODE_ZLIB;
  
  xlog_handle_t h = xlog_new_instance(&cfg);
  const char* path = xlog_get_log_path(h);
  ASSERT(path != nullptr);
  ASSERT(strlen(path) > 0);
  xlog_release_instance("test_logpath");
}

TEST(test_destroy_instance) {
  std::string logDir = getTempDir();
  xlog_config_t cfg = {};
  cfg.mode = XLOG_APPENDER_MODE_ASYNC;
  cfg.logdir = logDir.c_str();
  cfg.nameprefix = "test_destroy";
  cfg.compress_mode = XLOG_COMPRESS_MODE_ZLIB;
  
  xlog_handle_t h = xlog_new_instance(&cfg);
  ASSERT(xlog_has_instance("test_destroy"));
  xlog_destroy_instance(h);
  // No crash is sufficient
}

int main() {
  std::cout << "=== xlog Windows C API Tests ===" << std::endl;
  std::cout << "(TODO: verify on Windows target platform)" << std::endl;
  
  RUN(test_new_instance_returns_valid_handle);
  RUN(test_has_instance_after_open);
  RUN(test_write_all_levels);
  RUN(test_get_set_level);
  RUN(test_set_appender_mode);
  RUN(test_set_console_log_open);
  RUN(test_flush_sync_async);
  RUN(test_flush_all);
  RUN(test_get_log_path);
  RUN(test_destroy_instance);
  
  std::cout << "\nResults: " << g_pass << " passed, " << g_fail << " failed" << std::endl;
  return g_fail > 0 ? 1 : 0;
}

#else
#error "This test is for Windows platform only (_WIN32 must be defined)"
#endif
