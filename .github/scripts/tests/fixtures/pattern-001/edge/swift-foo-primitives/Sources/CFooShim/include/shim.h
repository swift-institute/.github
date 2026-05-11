/*
 * Single-platform guard (Apple-only). This is legitimate single-platform
 * foresight — not multiplexing — so [PATTERN-001] should not fire.
 */
#if defined(__APPLE__)
#include <uuid/uuid.h>
static inline int swift_uuid_parse(const char* str, unsigned char* out) {
    return uuid_parse(str, out);
}
#endif
