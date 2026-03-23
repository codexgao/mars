#include <jni.h>

#include <android/log.h>
#include <cstdint>

#include "xlog_capi.h"

namespace {
constexpr const char* kNativeLogTag = "xlog_native_bridge";
}

extern "C" JNIEXPORT jlong JNICALL
Java_com_codexgao_xlog_1flutter_1example_XlogNativeBridge_nativeInit(
    JNIEnv* env,
    jobject /*thiz*/,
    jstring logDir,
    jstring cacheDir,
    jstring namePrefix) {
    if (logDir == nullptr || cacheDir == nullptr || namePrefix == nullptr) {
        __android_log_print(ANDROID_LOG_ERROR, kNativeLogTag,
                            "nativeInit failed: null args logDir=%p cacheDir=%p namePrefix=%p",
                            logDir, cacheDir, namePrefix);
        return 0;
    }

    const char* log_dir_cstr = env->GetStringUTFChars(logDir, nullptr);
    const char* cache_dir_cstr = env->GetStringUTFChars(cacheDir, nullptr);
    const char* name_prefix_cstr = env->GetStringUTFChars(namePrefix, nullptr);

    if (log_dir_cstr == nullptr || cache_dir_cstr == nullptr || name_prefix_cstr == nullptr) {
        __android_log_print(ANDROID_LOG_ERROR, kNativeLogTag,
                            "nativeInit failed: GetStringUTFChars returned null");
        if (log_dir_cstr != nullptr) {
            env->ReleaseStringUTFChars(logDir, log_dir_cstr);
        }
        if (cache_dir_cstr != nullptr) {
            env->ReleaseStringUTFChars(cacheDir, cache_dir_cstr);
        }
        if (name_prefix_cstr != nullptr) {
            env->ReleaseStringUTFChars(namePrefix, name_prefix_cstr);
        }
        return 0;
    }

    xlog_config_t cfg = {};
    cfg.mode = XLOG_APPENDER_SYNC;
    cfg.logdir = log_dir_cstr;
    cfg.nameprefix = name_prefix_cstr;
    cfg.pub_key = nullptr;
    cfg.compress_mode = XLOG_COMPRESS_ZLIB;
    cfg.compress_level = 0;
    cfg.cachedir = cache_dir_cstr;
    cfg.cache_days = 0;

    uintptr_t handle = xlog_new_instance(&cfg, XLOG_LEVEL_VERBOSE);
    if (handle == 0) {
        __android_log_print(ANDROID_LOG_ERROR, kNativeLogTag,
                            "nativeInit failed: xlog_new_instance returned 0");
    }

    env->ReleaseStringUTFChars(logDir, log_dir_cstr);
    env->ReleaseStringUTFChars(cacheDir, cache_dir_cstr);
    env->ReleaseStringUTFChars(namePrefix, name_prefix_cstr);

    return static_cast<jlong>(handle);
}

extern "C" JNIEXPORT jint JNICALL
Java_com_codexgao_xlog_1flutter_1example_XlogNativeBridge_nativeWrite(
    JNIEnv* env,
    jobject /*thiz*/,
    jlong handle,
    jint level,
    jstring tag,
    jstring message) {
    if (handle == 0 || message == nullptr) {
        __android_log_print(ANDROID_LOG_ERROR, kNativeLogTag,
                            "nativeWrite failed: invalid args handle=%lld message=%p",
                            static_cast<long long>(handle), message);
        return -1;
    }

    const char* message_cstr = env->GetStringUTFChars(message, nullptr);
    if (message_cstr == nullptr) {
        __android_log_print(ANDROID_LOG_ERROR, kNativeLogTag,
                            "nativeWrite failed: message GetStringUTFChars returned null");
        return -1;
    }

    const char* tag_cstr = "";
    if (tag != nullptr) {
        tag_cstr = env->GetStringUTFChars(tag, nullptr);
        if (tag_cstr == nullptr) {
            __android_log_print(ANDROID_LOG_ERROR, kNativeLogTag,
                                "nativeWrite failed: tag GetStringUTFChars returned null");
            env->ReleaseStringUTFChars(message, message_cstr);
            return -1;
        }
    }

    xlog_write(static_cast<uintptr_t>(handle), static_cast<xlog_level_t>(level), tag_cstr,
               "", "", 0, message_cstr);

    if (tag != nullptr) {
        env->ReleaseStringUTFChars(tag, tag_cstr);
    }
    env->ReleaseStringUTFChars(message, message_cstr);

    return 0;
}

extern "C" JNIEXPORT jint JNICALL
Java_com_codexgao_xlog_1flutter_1example_XlogNativeBridge_nativeFlush(
    JNIEnv* /*env*/,
    jobject /*thiz*/,
    jlong handle,
    jboolean isSync) {
    if (handle == 0) {
        __android_log_print(ANDROID_LOG_ERROR, kNativeLogTag,
                            "nativeFlush failed: invalid handle=0");
        return -1;
    }

    xlog_flush(static_cast<uintptr_t>(handle), isSync ? 1 : 0);
    return 0;
}

extern "C" JNIEXPORT jint JNICALL
Java_com_codexgao_xlog_1flutter_1example_XlogNativeBridge_nativeRelease(
    JNIEnv* /*env*/,
    jobject /*thiz*/,
    jlong handle) {
    if (handle == 0) {
        __android_log_print(ANDROID_LOG_ERROR, kNativeLogTag,
                            "nativeRelease failed: invalid handle=0");
        return -1;
    }

    xlog_destroy_instance(static_cast<uintptr_t>(handle));
    return 0;
}
