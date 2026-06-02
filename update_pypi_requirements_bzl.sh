#!/bin/sh
set -e

uv lock
bazel run //pycross/private:update_pycross_deps
