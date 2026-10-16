/* Per-bottle tuning shared by the macOS Wine driver components. */
#ifndef CX_TUNER_CONFIG_H
#define CX_TUNER_CONFIG_H
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>
struct cx_tuner_settings { int loaded, mouse, wheel, sync, drawables, queue; };
static struct cx_tuner_settings cx_tuner_read(void)
{
    struct cx_tuner_settings result = {0, -1, -1, -2, -1, -1};
    const char *prefix = getenv("WINEPREFIX"), *process = getprogname();
    char path[4096], line[512], section[256] = "";
    FILE *file;
    if (!prefix || snprintf(path, sizeof(path), "%s/drive_c/.cx-tuner.ini", prefix) >= sizeof(path)) return result;
    if (!(file = fopen(path, "r"))) return result;
    result.loaded = 1; result.mouse = result.wheel = 1;
    result.sync = -1; result.drawables = result.queue = 0;
    /* Two passes make application overrides independent of section order. */
    for (int pass = 0; pass < 2; ++pass)
    {
        rewind(file); section[0] = 0;
        while (fgets(line, sizeof(line), file))
        {
            char key[64], *end; int value;
            if (line[0] == '[') { if (sscanf(line, "[%255[^]]]", section) != 1) section[0] = 0; continue; }
            if ((pass == 0 && strcasecmp(section, "global")) ||
                (pass == 1 && (!process || strcasecmp(section, process)))) continue;
            if (sscanf(line, " %63[^=]=%d", key, &value) != 2) continue;
            end = key + strlen(key); while (end > key && (end[-1] == ' ' || end[-1] == '\t')) *--end = 0;
            if (!strcmp(key, "mouse") && (value == 0 || value == 1)) result.mouse = value;
            if (!strcmp(key, "wheel") && (value == 0 || value == 1)) result.wheel = value;
            if (!strcmp(key, "sync") && value >= -1 && value <= 1) result.sync = value;
            if (!strcmp(key, "drawables") && (value == 0 || value == 2 || value == 3)) result.drawables = value;
            if (!strcmp(key, "queue") && value >= 0 && value <= 16) result.queue = value;
        }
    }
    fclose(file);
    /* Native Sevoflurane owns Steam's UI; game defaults never tune its CEF. */
    if (process && (!strcasecmp(process, "steam.exe") || !strcasecmp(process, "steamwebhelper.exe") || !strcasecmp(process, "steamservice.exe")))
        { result.sync = -1; result.drawables = result.queue = 0; }
    return result;
}
#endif
