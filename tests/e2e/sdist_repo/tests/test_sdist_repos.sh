#!/bin/bash
set -euo pipefail

REPO_BASIC_BUILD=$1
REPO_PYPROJECT_BUILD=$2
REPO_SETUPTOOLS_BUILD=$3
REPO_LEGACY_BUILD=$4

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

echo "Checking with_pyproject repo..."
check_content "$REPO_PYPROJECT_BUILD" "pep517_build("
check_content "$REPO_PYPROJECT_BUILD" '"@dummy_lock_repo//:hatchling"'

echo "Checking with_setuptools repo..."
check_content "$REPO_SETUPTOOLS_BUILD" "setuptools_build("
check_content "$REPO_SETUPTOOLS_BUILD" '"@dummy_lock_repo//:setuptools"'
check_not_content "$REPO_SETUPTOOLS_BUILD" "unknown_dep"

echo "Checking legacy repo..."
check_content "$REPO_LEGACY_BUILD" "setuptools_build("
