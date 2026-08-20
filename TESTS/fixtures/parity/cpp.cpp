/**
 * @file cpp.cpp
 * @brief Parity fixture — C++.
 *
 * One documented public member, one private helper, an include, a call,
 * a namespace-scope constant and a marker.
 */

#include "other.hpp"

namespace parity {

const int MAX = 10;

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
int Widget::widen(int n) {
    // TODO: cap at MAX
    return double_(n) + other::bump(MAX);
}

}
