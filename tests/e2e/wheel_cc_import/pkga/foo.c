#include "foo.h"

static int counter = 41;

int foo_value(void) {
    return 42;
}

int foo_inc(void) {
    return ++counter;
}

const void* foo_counter_addr(void) {
    return (const void*)&counter;
}
