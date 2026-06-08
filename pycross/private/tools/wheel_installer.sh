#!/usr/bin/env bash
# Fast wheel installer — replaces the Python-based wheel_installer.py.
# A wheel is just a ZIP file; this script extracts it using native `unzip`
# and handles namespace packages and entry_points in bash.

set -euo pipefail

# Parse arguments (supports --flagfile for param files)
WHEEL=""
WHEELHOUSE=""
DIRECTORY=""
ENTRY_POINTS_OUTPUT=""
ENABLE_IMPLICIT_NAMESPACE_PKGS=false
INSTALL_EXCLUDE_GLOBS=()
PATCHES=()

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --flagfile=*)
                # Read args from flagfile
                local flagfile="${1#--flagfile=}"
                local file_args=()
                while IFS= read -r line; do
                    [[ -z "$line" || "$line" == \#* ]] && continue
                    file_args+=("$line")
                done < "$flagfile"
                parse_args "${file_args[@]}"
                return
                ;;
            --wheel)
                WHEEL="$2"; shift 2 ;;
            --wheelhouse)
                WHEELHOUSE="$2"; shift 2 ;;
            --directory)
                DIRECTORY="$2"; shift 2 ;;
            --entry-points-output)
                ENTRY_POINTS_OUTPUT="$2"; shift 2 ;;
            --enable-implicit-namespace-pkgs)
                ENABLE_IMPLICIT_NAMESPACE_PKGS=true; shift ;;
            --install-exclude-glob)
                INSTALL_EXCLUDE_GLOBS+=("$2"); shift 2 ;;
            --patch)
                PATCHES+=("$2"); shift 2 ;;
            --patch=*)
                PATCHES+=("${1#--patch=}"); shift ;;
            --wheel-name-file)
                shift 2 ;;  # Ignored — we don't need it
            *)
                echo "Unknown argument: $1" >&2; exit 1 ;;
        esac
    done
}

parse_args "$@"

# Resolve wheel path
if [[ -n "$WHEELHOUSE" ]]; then
    WHEEL_PATH=$(find "$WHEELHOUSE" -maxdepth 1 -name '*.whl' -type f | head -1)
    if [[ -z "$WHEEL_PATH" ]]; then
        echo "ERROR: No .whl file found in wheelhouse: $WHEELHOUSE" >&2
        exit 1
    fi
    WHEEL_COUNT=$(find "$WHEELHOUSE" -maxdepth 1 -name '*.whl' -type f | wc -l)
    if [[ "$WHEEL_COUNT" -ne 1 ]]; then
        echo "ERROR: Expected 1 wheel in wheelhouse, found $WHEEL_COUNT" >&2
        exit 1
    fi
elif [[ -n "$WHEEL" ]]; then
    WHEEL_PATH="$WHEEL"
else
    echo "ERROR: Either --wheel or --wheelhouse is required" >&2
    exit 1
fi

LIB_DIR="$DIRECTORY/site-packages"
mkdir -p "$LIB_DIR"

# Extract wheel — this is the hot path.
# Build exclude pattern args for unzip if we have globs.
UNZIP_EXCLUDES=()
for glob in "${INSTALL_EXCLUDE_GLOBS[@]+"${INSTALL_EXCLUDE_GLOBS[@]}"}"; do
    UNZIP_EXCLUDES+=(-x "$glob")
done

# unzip is native C and significantly faster than Python's zipfile module.
# -o: overwrite without prompting
# -q: quiet
unzip -o -q "$WHEEL_PATH" -d "$LIB_DIR" "${UNZIP_EXCLUDES[@]+"${UNZIP_EXCLUDES[@]}"}"

# Write INSTALLER metadata into the dist-info directory.
DIST_INFO_DIR=$(find "$LIB_DIR" -maxdepth 1 -name '*.dist-info' -type d | head -1)
if [[ -n "$DIST_INFO_DIR" ]]; then
    echo "https://github.com/jvolkman/rules_pycross" > "$DIST_INFO_DIR/INSTALLER"
fi

# Handle namespace packages: find directories that contain .py/.so/.pyd files
# (or are parents of packages) but have no __init__.py, and create one.
if [[ "$ENABLE_IMPLICIT_NAMESPACE_PKGS" != "true" ]]; then
    # Walk bottom-up: find all directories with Python modules but no __init__.py
    # Skip .dist-info directories and bin/
    while IFS= read -r -d '' dir; do
        # Skip dist-info, bin, data, include directories
        case "$dir" in
            *.dist-info*|*/bin|*/bin/*|*/data|*/data/*|*/include|*/include/*) continue ;;
        esac

        # Skip the root lib dir itself
        [[ "$dir" == "$LIB_DIR" ]] && continue

        # If __init__.py already exists, skip
        [[ -f "$dir/__init__.py" ]] && continue

        # Check if this directory contains Python modules or is a parent of a package
        has_modules=false
        has_child_packages=false

        # Check for Python module files
        for f in "$dir"/*.py "$dir"/*.pyc "$dir"/*.so "$dir"/*.pyd; do
            if [[ -f "$f" ]]; then
                has_modules=true
                break
            fi
        done

        # Check for child packages (directories with __init__.py)
        if [[ "$has_modules" != "true" ]]; then
            for child in "$dir"/*/; do
                if [[ -d "$child" ]] && [[ -f "$child/__init__.py" || -f "$child/__init__.pyc" ]]; then
                    has_child_packages=true
                    break
                fi
            done
            # Also check if any child is a known namespace package (has our marker)
            if [[ "$has_child_packages" != "true" ]]; then
                for child in "$dir"/*/; do
                    if [[ -d "$child" ]] && [[ -f "$child/__init__.py" ]] && \
                       grep -q "pkgutil" "$child/__init__.py" 2>/dev/null; then
                        has_child_packages=true
                        break
                    fi
                done
            fi
        fi

        if [[ "$has_modules" == "true" || "$has_child_packages" == "true" ]]; then
            cat > "$dir/__init__.py" << 'NSPKG'
# __path__ manipulation added by bazelbuild/rules_python to support namespace pkgs.
__path__ = __import__('pkgutil').extend_path(__path__, __name__)
NSPKG
        fi
    done < <(find "$LIB_DIR" -type d -print0 | sort -rz)
fi

# Apply patches
for patch_file in "${PATCHES[@]+"${PATCHES[@]}"}"; do
    patch -d "$LIB_DIR" -p1 < "$patch_file" || {
        echo "ERROR: Failed to apply patch: $patch_file" >&2
        exit 1
    }
done

# Extract entry_points.txt
if [[ -n "$ENTRY_POINTS_OUTPUT" ]]; then
    mkdir -p "$(dirname "$ENTRY_POINTS_OUTPUT")"
    if [[ -n "$DIST_INFO_DIR" ]] && [[ -f "$DIST_INFO_DIR/entry_points.txt" ]]; then
        cp "$DIST_INFO_DIR/entry_points.txt" "$ENTRY_POINTS_OUTPUT"
    else
        touch "$ENTRY_POINTS_OUTPUT"
    fi
fi
