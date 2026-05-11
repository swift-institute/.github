/*
 * Single-platform shim header — no platform multiplexing.
 */
#include <uuid/uuid.h>
static inline int swift_uuid_parse(const char* str, unsigned char* out) {
    return uuid_parse(str, out);
}
