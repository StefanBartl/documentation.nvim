/**
 * @file c.c
 * @brief Parity fixture — C.
 *
 * One documented external function, one static helper, an include, a call,
 * a file-scope constant and a marker.
 */

#include "other.h"

static const int MAX = 10;

/**
 * @brief Double a value.
 * @param n how much
 * @return the doubled value
 */
static int double_(int n) {
    return n * 2;
}

/**
 * @brief Widen a value.
 * @param n how much
 * @return the widened value
 */
int widen(int n) {
    /* TODO: cap at MAX */
    return double_(n) + bump(MAX);
}
