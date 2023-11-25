#!/bin/sh
set -e

pdm lock
bazel run //pycross/private:update_pycross_deps
