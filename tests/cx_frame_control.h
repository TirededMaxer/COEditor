/* COEditor frame clock. Call under the layer's lock; timestamps are monotonic. */
#ifndef CX_FRAME_CONTROL_H
#define CX_FRAME_CONTROL_H
#include <math.h>
#include <stdlib.h>
#include <string.h>
#define CX_FRAME_SAMPLES 512
struct cx_frame_clock {
    double last_start, latest, times[CX_FRAME_SAMPLES];
    unsigned count, cursor;
};
struct cx_frame_summary {
    unsigned count;
    double fps, mean_ms, p95_ms, p99_ms, low1_fps, max_ms;
    double intervals[CX_FRAME_SAMPLES];
};
static double cx_frame_deadline(const struct cx_frame_clock *s, double now, int fps)
{
    return fps > 0 && s->last_start > 0 ? fmax(now, s->last_start + 1.0 / fps) : now;
}
static void cx_frame_record(struct cx_frame_clock *s, double time)
{
    if (!isfinite(time) || time <= 0) return;
    /* Backgrounding / resizing starts a new measurement window. */
    if (s->latest && time > s->latest + 1.0) s->count = s->cursor = 0;
    s->times[s->cursor++ % CX_FRAME_SAMPLES] = time;
    if (s->count < CX_FRAME_SAMPLES) ++s->count;
    s->latest = fmax(time, s->latest);
}
static int cx_frame_compare(const void *a, const void *b)
{
    double x = *(const double *)a, y = *(const double *)b;
    return (x > y) - (x < y);
}
static struct cx_frame_summary cx_frame_summarize(const struct cx_frame_clock *s)
{
    struct cx_frame_summary out = {0};
    double times[CX_FRAME_SAMPLES], ordered[CX_FRAME_SAMPLES], sum = 0, slow = 0;
    memcpy(times, s->times, s->count * sizeof(double));
    qsort(times, s->count, sizeof(double), cx_frame_compare);
    for (unsigned i = 1; i < s->count; ++i) {
        double delta = (times[i] - times[i-1]) * 1000;
        if (delta <= 0 || delta > 1000) continue;
        out.intervals[out.count++] = delta;
        sum += delta;
    }
    if (!out.count) return out;
    memcpy(ordered, out.intervals, out.count * sizeof(double));
    qsort(ordered, out.count, sizeof(double), cx_frame_compare);
    out.mean_ms = sum / out.count; out.fps = 1000 / out.mean_ms;
    out.p95_ms = ordered[(unsigned)ceil(out.count * .95) - 1];
    out.p99_ms = ordered[(unsigned)ceil(out.count * .99) - 1];
    out.max_ms = ordered[out.count - 1];
    unsigned n = (unsigned)ceil(out.count * .01);
    for (unsigned i = out.count - n; i < out.count; ++i) slow += ordered[i];
    out.low1_fps = 1000 * n / slow;
    return out;
}
#endif
