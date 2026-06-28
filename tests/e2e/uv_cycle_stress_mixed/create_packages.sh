#!/bin/bash
set -euo pipefail

BASE_DIR="$(cd "$(dirname "$0")" && pwd)"

# Function to create a package source dir
create_pkg() {
    local dir_name="$1"
    local pkg_name="$2"
    local module_name="$3"
    shift 3
    local deps="$*"

    local pkg_dir="$BASE_DIR/$dir_name"
    mkdir -p "$pkg_dir/$module_name"
    touch "$pkg_dir/$module_name/__init__.py"

    # Build install_requires list
    local requires=""
    if [ -n "$deps" ]; then
        local first=1
        for dep in $deps; do
            if [ $first -eq 1 ]; then
                requires="\"$dep\""
                first=0
            else
                requires="$requires, \"$dep\""
            fi
        done
    fi

    cat > "$pkg_dir/setup.py" << EOF
from setuptools import setup

setup(name="$pkg_name", version="1.0.0", packages=["$module_name"], install_requires=[$requires])
EOF
}

# Cycle members (8 packages)
create_pkg stress_airflow stress-airflow stress_airflow \
    "stress-airflow-core" "stress-task-sdk"

create_pkg stress_airflow_core stress-airflow-core stress_airflow_core \
    "stress-provider-compat" "stress-provider-io" "stress-provider-sql" "stress-provider-smtp" "stress-provider-standard" "stress-task-sdk" "stress-packaging" "stress-jinja2"

create_pkg stress_task_sdk stress-task-sdk stress_task_sdk \
    "stress-airflow-core" "stress-attrs"

create_pkg stress_provider_compat stress-provider-compat stress_provider_compat \
    "stress-airflow"

create_pkg stress_provider_io stress-provider-io stress_provider_io \
    "stress-airflow; python_version >= '3.11'"

create_pkg stress_provider_sql stress-provider-sql stress_provider_sql \
    "stress-airflow; sys_platform == 'linux'"

create_pkg stress_provider_smtp stress-provider-smtp stress_provider_smtp \
    "stress-airflow; sys_platform == 'win32'" "stress-provider-compat"

create_pkg stress_provider_standard stress-provider-standard stress_provider_standard \
    "stress-airflow"

# External (non-cycle) dependencies
create_pkg stress_packaging stress-packaging stress_packaging
create_pkg stress_jinja2 stress-jinja2 stress_jinja2
create_pkg stress_attrs stress-attrs stress_attrs

echo "All 11 package source directories created."
