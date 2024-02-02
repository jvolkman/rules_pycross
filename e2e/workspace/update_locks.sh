#!/bin/sh

pdm lock --static-urls
poetry lock
bazel run //pdm:update_lock
bazel run //poetry:update_lock
