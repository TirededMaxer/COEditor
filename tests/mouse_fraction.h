/* Fractional motion preservation for the local CX mouse-input backport.
 * Distributed under the GNU LGPL, version 2.1 or later, like winemac.drv.
 */
#ifndef MACDRV_MOUSE_FRACTION_H
#define MACDRV_MOUSE_FRACTION_H

static inline int macdrv_take_fraction(double *remainder, double delta)
{
    int whole;
    *remainder += delta;
    whole = (int)*remainder;
    *remainder -= whole;
    return whole;
}

#endif
