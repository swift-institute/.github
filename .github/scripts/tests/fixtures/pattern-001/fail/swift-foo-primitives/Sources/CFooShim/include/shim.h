/*
 * Unified header that multiplexes platforms via __APPLE__ / __linux__.
 * VIOLATION of [PATTERN-001] — each platform's shim MUST be an independent
 * file (no shared conditional header).
 */
#if defined(__APPLE__)
#include <uuid/uuid.h>
static inline int swift_uuid_parse(const char* str, unsigned char* out) {
    return uuid_parse(str, out);
}
#elif defined(__linux__)
#include <uuid/uuid.h>
static inline int swift_uuid_parse(const char* str, unsigned char* out) {
    return uuid_parse(str, out);
}
#endif
