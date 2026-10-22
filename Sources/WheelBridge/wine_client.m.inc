/* Physical wheel access belongs to the separately authorized, retained reader.
 * Wine never requests global input permission. All state is per process. */
static const struct cx_wheel_bridge *cx_wheel_shared;
static CFRunLoopTimerRef cx_wheel_timer, cx_wheel_client_timer;
static uint64_t cx_wheel_client_birth;
static uint64_t cx_wheel_cursor, cx_wheel_delivered;
static uint32_t cx_wheel_reader_pid;
static int cx_wheel_last_state = -1;
static uint64_t cx_wheel_last_open, cx_wheel_focus_generation;

/* Registration is independent of focus; switching windows must not end a game.
 * The low-frequency ping also recovers a reader that quit unexpectedly. */
static void cx_wheel_release_client(void)
{
    if (cx_wheel_client_birth) cx_wheel_send_request(CX_WHEEL_DETACH, getpid(), cx_wheel_client_birth);
}
static void cx_wheel_client_ping(CFRunLoopTimerRef timer, void *context)
{
    cx_wheel_send_request(CX_WHEEL_ATTACH, getpid(), cx_wheel_client_birth);
}
static void cx_begin_wheel_client(void)
{
    struct cx_tuner_settings tuning = cx_tuner_read();
    const char *mode = tuning.loaded ? (tuning.wheel ? "hid" : "off") : getenv("CX_WHEEL_INPUT");
    if (cx_wheel_client_timer || !mode || strcmp(mode, "hid") || !cx_wheel_game_program(getprogname())) return;
    if (!(cx_wheel_client_birth = cx_wheel_process_birth(getpid()))) return;
    cx_wheel_client_ping(NULL, NULL);
    atexit(cx_wheel_release_client);
    cx_wheel_client_timer = CFRunLoopTimerCreate(NULL, CFAbsoluteTimeGetCurrent() + 2, 2, 0, 0, cx_wheel_client_ping, NULL);
    CFRunLoopAddTimer(CFRunLoopGetMain(), cx_wheel_client_timer, kCFRunLoopCommonModes);
}

static bool cx_wheel_open_bridge(void)
{
    char path[4096];
    struct stat st;
    const char *home = getenv("HOME");
    int fd;
    if (cx_wheel_shared) return true;
    if (!home) return false;
    uint64_t now = cx_wheel_now();
    if (now - cx_wheel_last_open < CX_WHEEL_LEASE_NS) return false;
    cx_wheel_last_open = now;
    snprintf(path, sizeof(path), "%s/Library/Application Support/CrossOver/CustomRuntimes/.tuner-support/Wheel/wheel-v1.bin", home);
    fd = open(path, O_RDONLY | O_NOFOLLOW);
    if (fd < 0) return false;
    if (fstat(fd, &st) || !S_ISREG(st.st_mode) || st.st_uid != getuid() ||
        st.st_size != sizeof(struct cx_wheel_bridge) || (st.st_mode & 077))
    { close(fd); return false; }
    void *mapping = mmap(NULL, sizeof(struct cx_wheel_bridge), PROT_READ, MAP_SHARED, fd, 0);
    close(fd);
    if (mapping == MAP_FAILED) return false;
    cx_wheel_shared = mapping;
    cx_wheel_cursor = __atomic_load_n(&cx_wheel_shared->sequence, __ATOMIC_ACQUIRE);
    return true;
}

static bool cx_wheel_drain(void)
{
    uint64_t now = cx_wheel_now();
    bool live = cx_wheel_open_bridge() && cx_wheel_live(cx_wheel_shared, now);
    int state = live ? 1 : 0;
    if (state != cx_wheel_last_state)
    {
        fprintf(stderr, "[CXWheelBridge] reader=%s pid=%d; native fallback=%s\n",
            live ? "ready" : "unavailable", getpid(), live ? "on missed physical delivery" : "active");
        cx_wheel_last_state = state;
    }
    if (!live) { cx_wheel_delivered = 0; return false; }
    if (cx_wheel_reader_pid != cx_wheel_shared->pid)
    {
        cx_wheel_reader_pid = cx_wheel_shared->pid;
        cx_wheel_delivered = 0;
        cx_wheel_cursor = 0;
    }
    if (![NSApp isActive]) return false;
    struct cx_wheel_event e;
    while (cx_wheel_next(cx_wheel_shared, &cx_wheel_cursor, getpid(), now, &e))
    {
        if ([[WineApplicationController sharedController] postRawWheelX:e.x y:e.y])
        {
            bool first = !cx_wheel_delivered;
            cx_wheel_delivered = e.time_ns;
            if (first) fprintf(stderr, "[CXWheelBridge] physical delivery confirmed pid=%d delta=%d,%d\n",getpid(),e.x,e.y);
        }
    }
    return true;
}
static void cx_wheel_tick(CFRunLoopTimerRef timer, void *context) { cx_wheel_drain(); }
static void cx_stop_raw_wheel(void)
{
    if (cx_wheel_timer) { CFRunLoopTimerInvalidate(cx_wheel_timer); CFRelease(cx_wheel_timer); cx_wheel_timer = NULL; }
    ++cx_wheel_focus_generation;
    if (cx_wheel_shared) cx_wheel_cursor = __atomic_load_n(&cx_wheel_shared->sequence, __ATOMIC_ACQUIRE);
}
static void cx_start_raw_wheel(void)
{
    struct cx_tuner_settings tuning = cx_tuner_read();
    const char *mode = tuning.loaded ? (tuning.wheel ? "hid" : "off") : getenv("CX_WHEEL_INPUT");
    if (!mode || strcmp(mode, "hid")) { cx_wheel_delivered = 0; cx_stop_raw_wheel(); return; }
    cx_begin_wheel_client();
    if (!cx_wheel_client_timer || cx_wheel_timer) return;
    ++cx_wheel_focus_generation;
    if (cx_wheel_now() - cx_wheel_delivered >= CX_WHEEL_TAIL_NS) cx_wheel_delivered = 0;
    cx_wheel_open_bridge();
    if (cx_wheel_shared) cx_wheel_cursor = __atomic_load_n(&cx_wheel_shared->sequence, __ATOMIC_ACQUIRE);
    cx_wheel_timer = CFRunLoopTimerCreate(NULL, CFAbsoluteTimeGetCurrent(), 0.002, 0, 0, cx_wheel_tick, NULL);
    CFRunLoopAddTimer(CFRunLoopGetMain(), cx_wheel_timer, kCFRunLoopCommonModes);
}
