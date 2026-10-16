/* Local physical wheel translation; LGPL-2.1-or-later, like winemac.drv. */
#ifndef MACDRV_WHEEL_RAW_H
#define MACDRV_WHEEL_RAW_H
#include <stdbool.h>
#include <stdint.h>
static inline bool macdrv_hid_wheel_delta(unsigned int page, unsigned int usage,
                                         bool relative, int64_t value, int *x, int *y)
{
    *x = *y = 0;
    if (!relative) return false;
    if (page == 1 && usage == 0x38) *y = value * 120;
    else if (page == 0x0c && usage == 0x238) *x = value * 120;
    else return false;
    return true;
}
static inline bool macdrv_drop_native_wheel(unsigned int devices, unsigned int phase, unsigned int momentum)
{
    return devices && !phase && !momentum;
}
#endif
