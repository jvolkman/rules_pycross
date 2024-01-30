#!/bin/sh
set -e

pdm lock
bazel run :update_pycross_deps
