/* COEditor wheel bridge protocol 1. Shared by arm64 reader and x86_64 Wine.
 * A private, fixed-size ring carries wheel events only; no keyboard or movement.
 * Keep the wire layout stable. One writer, lock-free release/acquire publication. */
#ifndef CX_WHEEL_BRIDGE_H
#define CX_WHEEL_BRIDGE_H
#include <stdint.h>
#include <stdbool.h>
#include <time.h>
#define CX_WHEEL_MAGIC UINT64_C(0x4358574845454c31)
#define CX_WHEEL_CAPACITY 256
#define CX_WHEEL_LEASE_NS UINT64_C(250000000)
#define CX_WHEEL_TAIL_NS UINT64_C(1000000000)
enum { CX_WHEEL_DENIED, CX_WHEEL_READY, CX_WHEEL_NO_DEVICE, CX_WHEEL_ERROR };
struct cx_wheel_event { uint64_t sequence, time_ns; int32_t pid, x, y, reserved; };
struct cx_wheel_bridge {
    uint64_t magic, heartbeat_ns, sequence;
    uint32_t version, state, devices, pid;
    struct cx_wheel_event events[CX_WHEEL_CAPACITY];
};
static inline uint64_t cx_wheel_now(void) {
    struct timespec t; clock_gettime(CLOCK_MONOTONIC, &t);
    return (uint64_t)t.tv_sec * UINT64_C(1000000000) + t.tv_nsec;
}
static inline bool cx_wheel_live(const struct cx_wheel_bridge *b, uint64_t now) {
    uint64_t tick;
    if (!b || __atomic_load_n(&b->magic, __ATOMIC_ACQUIRE) != CX_WHEEL_MAGIC || b->version != 1) return false;
    tick = __atomic_load_n(&b->heartbeat_ns, __ATOMIC_ACQUIRE);
    return tick && now >= tick && now - tick < CX_WHEEL_LEASE_NS &&
        __atomic_load_n(&b->state, __ATOMIC_ACQUIRE) == CX_WHEEL_READY && b->devices;
}
static inline void cx_wheel_publish(struct cx_wheel_bridge *b, int pid, int x, int y, uint64_t now) {
    uint64_t seq = __atomic_load_n(&b->sequence, __ATOMIC_RELAXED) + 1;
    struct cx_wheel_event *e = &b->events[seq % CX_WHEEL_CAPACITY];
    __atomic_store_n(&e->sequence, 0, __ATOMIC_RELEASE);
    e->time_ns = now; e->pid = pid; e->x = x; e->y = y; e->reserved = 0;
    __atomic_store_n(&e->sequence, seq, __ATOMIC_RELEASE);
    __atomic_store_n(&b->sequence, seq, __ATOMIC_RELEASE);
}
/* Cursor is advanced even for another PID; focus changes explicitly discard old events. */
static inline bool cx_wheel_next(const struct cx_wheel_bridge *b, uint64_t *cursor,
                                int pid, uint64_t now, struct cx_wheel_event *out) {
    uint64_t end = __atomic_load_n(&b->sequence, __ATOMIC_ACQUIRE);
    if (end < *cursor) *cursor = end; /* helper restarted */
    if (end - *cursor > CX_WHEEL_CAPACITY) *cursor = end - CX_WHEEL_CAPACITY;
    while (*cursor < end) {
        uint64_t seq = ++*cursor;
        const struct cx_wheel_event *e = &b->events[seq % CX_WHEEL_CAPACITY];
        if (__atomic_load_n(&e->sequence, __ATOMIC_ACQUIRE) != seq) continue;
        *out = *e;
        if (__atomic_load_n(&e->sequence, __ATOMIC_ACQUIRE) != seq) continue;
        if (out->pid == pid && out->time_ns <= now && now - out->time_ns < CX_WHEEL_LEASE_NS) return true;
    }
    return false;
}
static inline bool cx_wheel_claimed(uint64_t delivered, uint64_t event_ns, uint64_t now) {
    return delivered && delivered <= now && now - delivered < CX_WHEEL_TAIL_NS &&
        (delivered >= event_ns || event_ns - delivered < CX_WHEEL_TAIL_NS);
}
#endif
