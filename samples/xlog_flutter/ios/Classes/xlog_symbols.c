/**
 * @file xlog_symbols.c
 * @brief Force linker to include xlog C API symbols.
 *
 * iOS static libraries: symbols from .a archives are only included in the final
 * executable if they are directly referenced. Since Flutter FFI uses dlsym()
 * at runtime (via DynamicLibrary.process()), there are no compile-time references
 * to these symbols from the app code.
 *
 * This file creates explicit references to all xlog C API functions, which:
 * 1. Forces the linker to include the object files containing these symbols
 * 2. Ensures the symbols appear in the executable's symbol table
 * 3. Makes them discoverable by dlsym(RTLD_DEFAULT, ...)
 *
 * The __attribute__((used)) prevents the compiler from optimizing away these
 * references as "dead code".
 */

#include <stdint.h>

/* ---- Declare xlog C API functions (matches xlog_capi.h) ---- */

/* Forward declarations - these are defined in the xlog static library */
extern uintptr_t xlog_new_instance(const void* config, int level);
extern uintptr_t xlog_get_instance(const char* nameprefix);
extern int xlog_has_instance(const char* nameprefix);
extern void xlog_release_instance(const char* nameprefix);
extern void xlog_destroy_instance(uintptr_t instance);
extern void xlog_write(uintptr_t instance, int level,
                       const char* tag, const char* filename,
                       const char* funcname, int line,
                       const char* log);
extern int xlog_is_enabled_for(uintptr_t instance, int level);
extern int xlog_get_level(uintptr_t instance);
extern void xlog_set_level(uintptr_t instance, int level);
extern void xlog_set_appender_mode(uintptr_t instance, int mode);
extern void xlog_set_console_log_open(uintptr_t instance, int is_open);
extern void xlog_flush(uintptr_t instance, int is_sync);
extern void xlog_flush_all(int is_sync);
extern int xlog_get_log_path(uintptr_t instance, char* buf, unsigned int buf_len);

/* ---- Force symbol references ---- */

/**
 * Array of function pointers that references all xlog C API symbols.
 * __attribute__((used)) ensures the compiler won't remove this as dead code.
 * __attribute__((visibility("default"))) ensures symbols are exported.
 */
__attribute__((used, visibility("default")))
static void* _xlog_force_link_symbols[] = {
    (void*)&xlog_new_instance,
    (void*)&xlog_get_instance,
    (void*)&xlog_has_instance,
    (void*)&xlog_release_instance,
    (void*)&xlog_destroy_instance,
    (void*)&xlog_write,
    (void*)&xlog_is_enabled_for,
    (void*)&xlog_get_level,
    (void*)&xlog_set_level,
    (void*)&xlog_set_appender_mode,
    (void*)&xlog_set_console_log_open,
    (void*)&xlog_flush,
    (void*)&xlog_flush_all,
    (void*)&xlog_get_log_path,
};
