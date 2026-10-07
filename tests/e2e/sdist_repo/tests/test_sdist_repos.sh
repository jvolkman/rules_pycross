#!/bin/bash
set -euo pipefail

REPO_BASIC_BUILD=$1
REPO_PYPROJECT_BUILD=$2
REPO_SETUPTOOLS_BUILD=$3
REPO_LEGACY_BUILD=$4
REPO_EXPLICIT_BACKEND_BUILD=$5
REPO_BASIC_INSPECTION=$6
REPO_VERSION_MISMATCH_INSPECTION=$7
REPO_PATCHED_PYPROJECT_BUILD=$8

function check_content() {
    local file=$1
    local expected=$2
    if ! grep -q "$expected" "$file"; then
        echo "Error: Expected to find '$expected' in $file"
        cat "$file"
        exit 1
    fi
}

function check_not_content() {
    local file=$1
    local unexpected=$2
    if grep -q "$unexpected" "$file"; then
        echo "Error: Expected NOT to find '$unexpected' in $file"
        cat "$file"
        exit 1
    fi
}

echo "Checking basic repo..."
check_content "$REPO_BASIC_BUILD" "setuptools_build("
check_content "$REPO_BASIC_BUILD" 'sdist = "@@//sdists:basic.tar.gz"'
check_content "$REPO_BASIC_INSPECTION" '"warnings":\[\]'

echo "Checking with_pyproject repo..."
check_content "$REPO_PYPROJECT_BUILD" "pep517_build("
check_content "$REPO_PYPROJECT_BUILD" '"@dummy_lock_repo//hatchling:pkg"'
check_content "$REPO_PYPROJECT_BUILD" '"@dummy_lock_repo//setuptools:pkg"'

echo "Checking with_setuptools repo..."
check_content "$REPO_SETUPTOOLS_BUILD" "setuptools_build("
check_content "$REPO_SETUPTOOLS_BUILD" '"@dummy_lock_repo//setuptools:pkg"'
check_not_content "$REPO_SETUPTOOLS_BUILD" "unknown_dep"

echo "Checking legacy repo..."
check_content "$REPO_LEGACY_BUILD" "setuptools_build("

echo "Checking explicit_backend repo..."
check_content "$REPO_EXPLICIT_BACKEND_BUILD" "setuptools_build("
check_content "$REPO_EXPLICIT_BACKEND_BUILD" '"@dummy_lock_repo//hatchling:pkg"'

echo "Checking version_mismatch repo..."
check_content "$REPO_VERSION_MISMATCH_INSPECTION" "WARNING: The build tools repo pins 'setuptools==30.0.0', but 'basic.tar.gz' requires 'setuptools>=40.8.0' in pyproject.toml."

echo "Checking patched_pyproject repo..."
check_content "$REPO_PATCHED_PYPROJECT_BUILD" "pep517_build("
check_content "$REPO_PATCHED_PYPROJECT_BUILD" '"@dummy_lock_repo//hatchling:pkg"'
check_content "$REPO_PATCHED_PYPROJECT_BUILD" 'pre_build_patches = \["@@//:use_hatchling.patch"\]'
check_not_content "$REPO_PATCHED_PYPROJECT_BUILD" '"@dummy_lock_repo//setuptools:pkg"'
