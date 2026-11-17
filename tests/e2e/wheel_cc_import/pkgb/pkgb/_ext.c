#define PY_SSIZE_T_CLEAN
#include <Python.h>
#include "foo.h"

static PyObject* ext_value(PyObject* self, PyObject* args) {
    (void)self;
    (void)args;
    return PyLong_FromLong(foo_value());
}

static PyObject* ext_inc(PyObject* self, PyObject* args) {
    (void)self;
    (void)args;
    return PyLong_FromLong(foo_inc());
}

static PyObject* ext_counter_addr(PyObject* self, PyObject* args) {
    (void)self;
    (void)args;
    return PyLong_FromVoidPtr((void*)foo_counter_addr());
}

static PyMethodDef methods[] = {
    {"value", ext_value, METH_NOARGS, NULL},
    {"inc", ext_inc, METH_NOARGS, NULL},
    {"counter_addr", ext_counter_addr, METH_NOARGS, NULL},
    {NULL, NULL, 0, NULL},
};

static struct PyModuleDef module = {
    PyModuleDef_HEAD_INIT,
    "_ext",
    NULL,
    -1,
    methods,
};

PyMODINIT_FUNC PyInit__ext(void) {
    return PyModule_Create(&module);
}
