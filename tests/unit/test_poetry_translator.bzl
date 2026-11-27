"""Tests for the Starlark Poetry translator."""

load("@rules_testing//lib:analysis_test.bzl", "analysis_test", "test_suite")
load("@rules_testing//lib:util.bzl", "util")

# buildifier: disable=bzl-visibility
load("//pycross/private:poetry_lock_model.bzl", "translate_poetry")

def _lock_model(
        projects = ["*"],
        dependency_groups = ["default"]):
    return struct(
        projects = projects,
        dependency_groups = dependency_groups,
    )

def _whl(name, sha256 = "1234"):
    return {"file": name, "hash": "sha256:" + sha256}

def _pkg(name, version, files = None, deps = None, optional = False, extras = None, source = None, markers = None):
    """Build a Poetry lock package entry."""
    p = {
        "name": name,
        "version": version,
        "description": "",
        "optional": optional,
        "python-versions": "*",
    }
    if files != None:
        p["files"] = files
    if deps != None:
        p["dependencies"] = deps
    if extras != None:
        p["extras"] = extras
    if source != None:
        p["source"] = source
    if markers != None:
        p["markers"] = markers
    return p

# --- test_minimal_lock ---

# buildifier: disable=unused-variable
def _test_poetry_minimal_lock_impl(env, target):
    project = {
        "tool": {"poetry": {
            "name": "my-app",
            "version": "0.1.0",
            "dependencies": {"python": "^3.8", "requests": "2.31.0"},
        }},
    }
    lock = {
        "metadata": {"lock-version": "2.1"},
        "package": [
            _pkg("requests", "2.31.0", files = [_whl("requests-2.31.0-py3-none-any.whl", "12345")]),
        ],
    }
    result = translate_poetry(project, lock, _lock_model())
    env.expect.that_collection(result["packages"].keys()).contains_exactly(["requests@2.31.0"])
    pkg = result["packages"]["requests@2.31.0"]

    files = pkg["files"]
    env.expect.that_collection(files).has_size(1)
    env.expect.that_str(files[0]["package_name"]).equals("requests")
    env.expect.that_str(files[0]["package_version"]).equals("2.31.0")

def _test_poetry_minimal_lock(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_poetry_minimal_lock_impl)

# --- test_lock_version_check ---

# buildifier: disable=unused-variable
def _test_poetry_lock_version_impl(env, target):
    project = {"tool": {"poetry": {"dependencies": {"python": "^3.8", "a": "1.0"}}}}
    lock = {
        "metadata": {"lock-version": "2.1"},
        "package": [
            _pkg("a", "1.0", files = [_whl("a-1.0-py3-none-any.whl", "a")]),
        ],
    }
    result = translate_poetry(project, lock, _lock_model())
    env.expect.that_int(len(result["packages"])).equals(1)

def _test_poetry_lock_version(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_poetry_lock_version_impl)

# --- test_package_with_extras ---

# buildifier: disable=unused-variable
def _test_poetry_package_with_extras_impl(env, target):
    project = {"tool": {"poetry": {"dependencies": {"python": "^3.8", "a": "1.0"}}}}
    lock = {
        "metadata": {"lock-version": "2.1"},
        "package": [
            _pkg(
                "a",
                "1.0",
                files = [_whl("a-1.0-py3-none-any.whl", "a")],
                deps = {"b": "==2.0"},
                extras = {"testing": ["pytest (>=7.0)"]},
            ),
            _pkg("b", "2.0", files = [_whl("b-2.0-py3-none-any.whl", "b")]),
        ],
    }
    result = translate_poetry(project, lock, _lock_model())
    pkg_a = result["packages"]["a@1.0"]
    env.expect.that_int(len(pkg_a["dependencies"])).equals(1)
    env.expect.that_str(pkg_a["dependencies"][0]["name"]).equals("b")

def _test_poetry_package_with_extras(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_poetry_package_with_extras_impl)

# --- test_source_directory ---

# buildifier: disable=unused-variable
def _test_poetry_source_directory_impl(env, target):
    project = {"tool": {"poetry": {"dependencies": {"python": "^3.8", "a": "1.0"}}}}
    lock = {
        "metadata": {"lock-version": "2.1"},
        "package": [
            _pkg("a", "1.0", source = {"type": "directory", "url": "..."}),
        ],
    }
    result = translate_poetry(project, lock, _lock_model())
    env.expect.that_collection(result["packages"].keys()).has_size(0)

def _test_poetry_source_directory(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_poetry_source_directory_impl)

# --- test_source_git ---

# buildifier: disable=unused-variable
def _test_poetry_source_git_impl(env, target):
    project = {"tool": {"poetry": {"dependencies": {"python": "^3.8", "a": "1.0"}}}}
    lock = {
        "metadata": {"lock-version": "2.1"},
        "package": [
            _pkg("a", "1.0", source = {"type": "git", "url": "https://github.com/user/a.git", "resolved_reference": "abcdef123456"}),
        ],
    }
    result = translate_poetry(project, lock, _lock_model())
    env.expect.that_collection(result["packages"].keys()).contains_exactly(["a@1.0"])

    pkg = result["packages"]["a@1.0"]
    env.expect.that_collection(pkg["files"]).has_size(1)
    env.expect.that_collection(pkg["files"][0]["urls"]).contains_exactly(["git+https://github.com/user/a.git#abcdef123456"])

def _test_poetry_source_git(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_poetry_source_git_impl)

# buildifier: disable=unused-variable
def _test_poetry_optional_dependency_impl(env, target):
    project = {"tool": {"poetry": {"dependencies": {"python": "^3.8", "a": "1.0"}}}}
    lock = {
        "metadata": {"lock-version": "2.1"},
        "package": [
            _pkg(
                "a",
                "1.0",
                files = [_whl("a-1.0-py3-none-any.whl", "a")],
                deps = {"b": {"version": "==2.0", "markers": "extra == 'testing'"}},
            ),
            _pkg("b", "2.0", files = [_whl("b-2.0-py3-none-any.whl", "b")], optional = True),
        ],
    }
    result = translate_poetry(project, lock, _lock_model())
    pkg_a = result["packages"]["a@1.0"]
    env.expect.that_int(len(pkg_a["dependencies"])).equals(1)
    dep_b = pkg_a["dependencies"][0]
    env.expect.that_str(dep_b["name"]).equals("b")
    env.expect.that_str(dep_b["marker"]).contains("extra")

def _test_poetry_optional_dependency(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_poetry_optional_dependency_impl)

# --- test_poetry_forks ---

# buildifier: disable=unused-variable
def _test_poetry_forks_impl(env, target):
    project = {
        "tool": {
            "poetry": {
                "dependencies": {
                    "python": "^3.9",
                    "greenlet": [
                        {"version": ">=2.0,<3.3", "python": "~3.9"},
                        {"version": ">=3.5", "python": ">=3.10"},
                    ],
                },
            },
        },
    }
    lock = {
        "metadata": {"lock-version": "2.1"},
        "package": [
            _pkg("greenlet", "3.2.5", files = [_whl("greenlet-3.2.5-py3-none-any.whl", "1")], markers = "python_version == \"3.9\""),
            _pkg("greenlet", "3.5.3", files = [_whl("greenlet-3.5.3-py3-none-any.whl", "2")], markers = "python_version >= \"3.10\""),
        ],
    }
    result = translate_poetry(project, lock, _lock_model())

    # Check resolution_marker_exprs
    res_exprs = result.get("resolution_marker_exprs", {})
    env.expect.that_bool("res_greenlet_3_2_5" in res_exprs).equals(True)
    env.expect.that_bool("res_greenlet_3_5_3" in res_exprs).equals(True)
    env.expect.that_str(res_exprs["res_greenlet_3_2_5"]).equals('python_version == "3.9"')
    env.expect.that_str(res_exprs["res_greenlet_3_5_3"]).equals('python_version >= "3.10"')

    # Check pinned specs resolved conditionally
    pins = result["pins"]["greenlet"]
    env.expect.that_str(pins["res_greenlet_3_2_5"]).equals("greenlet@3.2.5")
    env.expect.that_str(pins["res_greenlet_3_5_3"]).equals("greenlet@3.5.3")

def _test_poetry_forks(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_poetry_forks_impl)

# --- test_poetry_url_source ---

# buildifier: disable=unused-variable
def _test_poetry_url_source_impl(env, target):
    project = {"tool": {"poetry": {"dependencies": {"python": "^3.9", "torch": "1.12.1"}}}}
    lock = {
        "metadata": {"lock-version": "2.1"},
        "package": [
            _pkg(
                "torch",
                "1.12.1",
                source = {"type": "url", "url": "https://example.com/torch-1.12.1-whl"},
                files = [_whl("torch-1.12.1-py3-none-any.whl", "12345")],
            ),
        ],
    }
    result = translate_poetry(project, lock, _lock_model())
    env.expect.that_collection(result["packages"].keys()).contains_exactly(["torch@1.12.1"])
    pkg = result["packages"]["torch@1.12.1"]
    env.expect.that_collection(pkg["files"][0]["urls"]).contains_exactly(["https://example.com/torch-1.12.1-whl"])

def _test_poetry_url_source(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_poetry_url_source_impl)

# --- Issue #117: URL without version ---

# buildifier: disable=unused-variable
def _test_poetry_issue_117_impl(env, target):
    project = {
        "tool": {
            "poetry": {
                "dependencies": {
                    "python": "^3.9",
                    "boto3": {"url": "https://github.com/boto/boto3/archive/31a8a3d7bcd021aadceba63d6f207a3a61c58aac.zip"},
                },
            },
        },
    }
    lock = {
        "metadata": {"lock-version": "2.1"},
        "package": [
            _pkg(
                "boto3",
                "1.35.13",
                source = {"type": "url", "url": "https://github.com/boto/boto3/archive/31a8a3d7bcd021aadceba63d6f207a3a61c58aac.zip"},
                files = [_whl("31a8a3d7bcd021aadceba63d6f207a3a61c58aac.zip", "12345")],
            ),
        ],
    }

    # This should NOT crash with KeyError: 'version'
    result = translate_poetry(project, lock, _lock_model())

    env.expect.that_collection(result["packages"].keys()).contains_exactly(["boto3@1.35.13"])
    pkg = result["packages"]["boto3@1.35.13"]
    env.expect.that_collection(pkg["files"][0]["urls"]).contains_exactly(["https://github.com/boto/boto3/archive/31a8a3d7bcd021aadceba63d6f207a3a61c58aac.zip"])

def _test_poetry_issue_117(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_poetry_issue_117_impl)

# --- Issue #34: List of dicts with URLs ---

# buildifier: disable=unused-variable
def _test_poetry_issue_34_impl(env, target):
    project = {
        "tool": {
            "poetry": {
                "dependencies": {
                    "python": "^3.9",
                    "torch": [
                        {"markers": "platform_machine == 'aarch64'", "url": "https://download.pytorch.org/whl/torch-1.12.1-cp39-cp39-manylinux2014_aarch64.whl"},
                        {"markers": "platform_machine == 'x86_64'", "url": "https://download.pytorch.org/whl/cpu/torch-1.12.1%2Bcpu-cp39-cp39-linux_x86_64.whl"},
                    ],
                },
            },
        },
    }

    # In Poetry 2.1+, these would have markers in the lock file if they are forks.
    lock = {
        "metadata": {"lock-version": "2.1"},
        "package": [
            _pkg(
                "torch",
                "1.12.1",
                source = {"type": "url", "url": "https://download.pytorch.org/whl/torch-1.12.1-cp39-cp39-manylinux2014_aarch64.whl"},
                files = [_whl("torch-1.12.1-cp39-cp39-manylinux2014_aarch64.whl", "aaaa")],
                markers = "platform_machine == \"aarch64\"",
            ),
            _pkg(
                "torch",
                "1.12.1+cpu",
                source = {"type": "url", "url": "https://download.pytorch.org/whl/cpu/torch-1.12.1%2Bcpu-cp39-cp39-linux_x86_64.whl"},
                files = [_whl("torch-1.12.1%2Bcpu-cp39-cp39-linux_x86_64.whl", "bbbb")],
                markers = "platform_machine == \"x86_64\"",
            ),
        ],
    }

    result = translate_poetry(project, lock, _lock_model())

    # Verify both versions are captured
    env.expect.that_collection(result["packages"].keys()).contains_exactly(["torch@1.12.1", "torch@1.12.1+cpu"])

    # Verify forks are detected
    res_exprs = result.get("resolution_marker_exprs", {})
    env.expect.that_bool("res_torch_1_12_1" in res_exprs).equals(True)
    env.expect.that_bool("res_torch_1_12_1_cpu" in res_exprs).equals(True)

def _test_poetry_issue_34(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_poetry_issue_34_impl)

# --- || Constraint Translation ---

# buildifier: disable=unused-variable
def _test_poetry_or_constraint_translations_impl(env, target):
    project = {
        "tool": {
            "poetry": {
                "dependencies": {
                    "python": "^3.9",
                    "pkg-a": "1.0.0",
                },
            },
        },
    }

    lock = {
        "metadata": {"lock-version": "2.1"},
        "package": [
            _pkg(
                "pkg-a",
                "1.0.0",
                deps = {
                    "dep-simple-exclude": "<2.2.0 || >2.2.0",
                    "dep-complex-exclude": ">=1.25.4,<2.2.0 || >2.2.0,<3",
                    "dep-inclusive-bound": "<=2.2.0 || >2.2.0",
                    "dep-caret-union": "^1.0 || ^2.0",
                    "dep-multi-exclude": ">=1.0,<2.0 || >2.0,<2.1 || >2.1,<3.0",
                },
                files = [_whl("pkg_a-1.0.0-py3-none-any.whl", "aaaa")],
            ),
            # 2.2.0 is excluded by `<2.2.0 || >2.2.0`, so resolution must skip 2.2.0 and pick 2.1.0.
            _pkg("dep-simple-exclude", "2.2.0", files = [_whl("dep_simple-2.2.0-py3-none-any.whl", "bbb0")]),
            _pkg("dep-simple-exclude", "2.1.0", files = [_whl("dep_simple-2.1.0-py3-none-any.whl", "bbbb")]),
            _pkg("dep-complex-exclude", "2.2.0", files = [_whl("dep_complex-2.2.0-py3-none-any.whl", "ccc0")]),
            _pkg("dep-complex-exclude", "2.1.0", files = [_whl("dep_complex-2.1.0-py3-none-any.whl", "cccc")]),
            # 2.2.0 is included by `<=2.2.0 || >2.2.0` (issue #361), so resolution must pick 2.2.0 over 2.1.0.
            _pkg("dep-inclusive-bound", "2.2.0", files = [_whl("dep_incl-2.2.0-py3-none-any.whl", "ddd0")]),
            _pkg("dep-inclusive-bound", "2.1.0", files = [_whl("dep_incl-2.1.0-py3-none-any.whl", "dddd")]),
            # 2.1.0 matches only the second branch of `^1.0 || ^2.0`.
            _pkg("dep-caret-union", "2.1.0", files = [_whl("dep_union-2.1.0-py3-none-any.whl", "eeee")]),
            # 2.2.0 matches only the third branch of `>=1.0,<2.0 || >2.0,<2.1 || >2.1,<3.0`.
            _pkg("dep-multi-exclude", "2.2.0", files = [_whl("dep_multi-2.2.0-py3-none-any.whl", "ffff")]),
        ],
    }

    result = translate_poetry(project, lock, _lock_model())
    pkgs = result["packages"]
    pkg_a_deps = [d["name"] + "@" + d["version"] for d in pkgs["pkg-a@1.0.0"]["dependencies"]]

    env.expect.that_collection(pkg_a_deps).contains_exactly([
        "dep-caret-union@2.1.0",
        "dep-complex-exclude@2.1.0",
        "dep-inclusive-bound@2.2.0",
        "dep-multi-exclude@2.2.0",
        "dep-simple-exclude@2.1.0",
    ])

def _test_poetry_or_constraint_translations(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_poetry_or_constraint_translations_impl)

# --- Unary Constraint Operators ---

# buildifier: disable=unused-variable
def _test_poetry_unary_constraint_operators_impl(env, target):
    project = {
        "tool": {
            "poetry": {
                "dependencies": {
                    "python": "^3.9",
                    "pkg-a": "1.0.0",
                },
            },
        },
    }

    lock = {
        "metadata": {"lock-version": "2.1"},
        "package": [
            _pkg(
                "pkg-a",
                "1.0.0",
                deps = {
                    "dep-lt": "<2.0.0",
                    "dep-le": "<=2.0.0",
                    "dep-gt": ">1.0.0",
                    "dep-ge": ">=1.0.0",
                    "dep-eq": "==1.5.0",
                    "dep-single-eq": "=1.5.0",
                    "dep-bare": "1.5.0",
                    "dep-ne": "!=2.0.0",
                    "dep-compat": "~=1.2.1",
                    "dep-tilde-patch": "~1.2.1",
                    "dep-tilde-minor": "~1.2",
                    "dep-caret-major": "^1.2.3",
                    "dep-caret-zero-major": "^0.2.3",
                    "dep-caret-zero-minor": "^0.0.3",
                    "dep-wildcard": "*",
                },
                files = [_whl("pkg_a-1.0.0-py3-none-any.whl", "aaaa")],
            ),
            # `<2.0.0` must skip 2.0.0 and pick 1.9.0.
            _pkg("dep-lt", "2.0.0", files = [_whl("dep_lt-2.0.0-py3-none-any.whl", "1")]),
            _pkg("dep-lt", "1.9.0", files = [_whl("dep_lt-1.9.0-py3-none-any.whl", "2")]),
            # `<=2.0.0` must skip 2.1.0 and include 2.0.0.
            _pkg("dep-le", "2.1.0", files = [_whl("dep_le-2.1.0-py3-none-any.whl", "3")]),
            _pkg("dep-le", "2.0.0", files = [_whl("dep_le-2.0.0-py3-none-any.whl", "4")]),
            # `>1.0.0` matches 1.0.1; `>=1.0.0` matches 1.0.0.
            _pkg("dep-gt", "1.0.1", files = [_whl("dep_gt-1.0.1-py3-none-any.whl", "5")]),
            _pkg("dep-ge", "1.0.0", files = [_whl("dep_ge-1.0.0-py3-none-any.whl", "6")]),
            # `==1.5.0`, `=1.5.0`, and bare `1.5.0` must skip 2.0.0 and pick 1.5.0.
            _pkg("dep-eq", "2.0.0", files = [_whl("dep_eq-2.0.0-py3-none-any.whl", "7")]),
            _pkg("dep-eq", "1.5.0", files = [_whl("dep_eq-1.5.0-py3-none-any.whl", "8")]),
            _pkg("dep-single-eq", "2.0.0", files = [_whl("dep_seq-2.0.0-py3-none-any.whl", "9")]),
            _pkg("dep-single-eq", "1.5.0", files = [_whl("dep_seq-1.5.0-py3-none-any.whl", "10")]),
            _pkg("dep-bare", "2.0.0", files = [_whl("dep_bare-2.0.0-py3-none-any.whl", "11")]),
            _pkg("dep-bare", "1.5.0", files = [_whl("dep_bare-1.5.0-py3-none-any.whl", "12")]),
            # `!=2.0.0` must skip 2.0.0 and pick 1.9.0.
            _pkg("dep-ne", "2.0.0", files = [_whl("dep_ne-2.0.0-py3-none-any.whl", "13")]),
            _pkg("dep-ne", "1.9.0", files = [_whl("dep_ne-1.9.0-py3-none-any.whl", "14")]),
            # `~=1.2.1`, `~1.2.1`, and `~1.2` must skip 1.3.0 and pick 1.2.5.
            _pkg("dep-compat", "1.3.0", files = [_whl("dep_compat-1.3.0-py3-none-any.whl", "15")]),
            _pkg("dep-compat", "1.2.5", files = [_whl("dep_compat-1.2.5-py3-none-any.whl", "16")]),
            _pkg("dep-tilde-patch", "1.3.0", files = [_whl("dep_tp-1.3.0-py3-none-any.whl", "17")]),
            _pkg("dep-tilde-patch", "1.2.5", files = [_whl("dep_tp-1.2.5-py3-none-any.whl", "18")]),
            _pkg("dep-tilde-minor", "1.3.0", files = [_whl("dep_tm-1.3.0-py3-none-any.whl", "19")]),
            _pkg("dep-tilde-minor", "1.2.5", files = [_whl("dep_tm-1.2.5-py3-none-any.whl", "20")]),
            # `^1.2.3`, `^0.2.3`, and `^0.0.3` must skip their upper bounds and pick the in-range version.
            _pkg("dep-caret-major", "2.0.0", files = [_whl("dep_cm-2.0.0-py3-none-any.whl", "21")]),
            _pkg("dep-caret-major", "1.9.0", files = [_whl("dep_cm-1.9.0-py3-none-any.whl", "22")]),
            _pkg("dep-caret-zero-major", "0.3.0", files = [_whl("dep_czm-0.3.0-py3-none-any.whl", "23")]),
            _pkg("dep-caret-zero-major", "0.2.5", files = [_whl("dep_czm-0.2.5-py3-none-any.whl", "24")]),
            _pkg("dep-caret-zero-minor", "0.0.4", files = [_whl("dep_czmin-0.0.4-py3-none-any.whl", "25")]),
            _pkg("dep-caret-zero-minor", "0.0.3", files = [_whl("dep_czmin-0.0.3-py3-none-any.whl", "26")]),
            # `*` matches all versions.
            _pkg("dep-wildcard", "2.0.0", files = [_whl("dep_wc-2.0.0-py3-none-any.whl", "27")]),
        ],
    }

    result = translate_poetry(project, lock, _lock_model())
    pkgs = result["packages"]
    pkg_a_deps = [d["name"] + "@" + d["version"] for d in pkgs["pkg-a@1.0.0"]["dependencies"]]

    env.expect.that_collection(pkg_a_deps).contains_exactly([
        "dep-bare@1.5.0",
        "dep-caret-major@1.9.0",
        "dep-caret-zero-major@0.2.5",
        "dep-caret-zero-minor@0.0.3",
        "dep-compat@1.2.5",
        "dep-eq@1.5.0",
        "dep-ge@1.0.0",
        "dep-gt@1.0.1",
        "dep-le@2.0.0",
        "dep-lt@1.9.0",
        "dep-ne@1.9.0",
        "dep-single-eq@1.5.0",
        "dep-tilde-minor@1.2.5",
        "dep-tilde-patch@1.2.5",
        "dep-wildcard@2.0.0",
    ])

def _test_poetry_unary_constraint_operators(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_poetry_unary_constraint_operators_impl)

# --- test_poetry_root_dependency_markers ---

# buildifier: disable=unused-variable
def _test_poetry_root_dependency_markers_impl(env, target):
    project = {
        "tool": {"poetry": {
            "name": "my-app",
            "version": "0.1.0",
            "dependencies": {
                "python": "^3.8",
                "foo": {"version": "1.0", "markers": "sys_platform == 'linux'"},
                "bar": {"version": "2.0", "platform": "darwin"},
                "baz": "3.0",
            },
        }},
    }
    lock = {
        "metadata": {"lock-version": "2.1"},
        "package": [
            _pkg("foo", "1.0", files = [_whl("foo-1.0-py3-none-any.whl")]),
            _pkg("bar", "2.0", files = [_whl("bar-2.0-py3-none-any.whl")]),
            _pkg("baz", "3.0", files = [_whl("baz-3.0-py3-none-any.whl")]),
        ],
    }
    result = translate_poetry(project, lock, _lock_model())

    markers = result["root_dependency_markers"]
    env.expect.that_collection(markers.keys()).contains("foo")
    env.expect.that_collection(markers.keys()).contains("bar")
    env.expect.that_collection(markers.keys()).contains_none_of(["baz"])
    env.expect.that_str(markers["foo"][0]).equals("sys_platform == 'linux'")
    env.expect.that_str(markers["bar"][0]).equals('sys_platform == "darwin"')

def _test_poetry_root_dependency_markers(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_poetry_root_dependency_markers_impl)

# --- test_poetry_dependency_extras ---

# buildifier: disable=unused-variable
def _test_poetry_dependency_extras_impl(env, target):
    project = {"project": {"name": "my-app", "dependencies": ["pytest-cov>=5", "requests[socks]>=2"]}}
    lock = {
        "metadata": {"lock-version": "2.1"},
        "package": [
            _pkg(
                "pytest-cov",
                "5.0.0",
                files = [_whl("pytest_cov-5.0.0-py3-none-any.whl")],
                deps = {"coverage": {"version": ">=5.2.1", "extras": ["toml"]}},
            ),
            _pkg(
                "coverage",
                "7.6.1",
                files = [_whl("coverage-7.6.1-py3-none-any.whl")],
                deps = {"tomli": {"version": "*", "optional": True, "markers": "extra == \"toml\""}},
                extras = {"toml": ["tomli ; python_full_version <= \"3.11.0a6\""]},
            ),
            _pkg("tomli", "2.0.1", files = [_whl("tomli-2.0.1-py3-none-any.whl")]),
            _pkg(
                "requests",
                "2.32.3",
                files = [_whl("requests-2.32.3-py3-none-any.whl")],
                deps = {"PySocks": {"version": ">=1.5.6", "optional": True, "markers": "extra == \"socks\""}},
                extras = {"socks": ["PySocks (>=1.5.6)"], "use-chardet-on-py3": ["chardet"]},
            ),
            _pkg("pysocks", "1.7.1", files = [_whl("PySocks-1.7.1-py3-none-any.whl")]),
        ],
    }
    result = translate_poetry(project, lock, _lock_model())

    cov_deps = result["packages"]["pytest-cov@5.0.0"]["dependencies"]
    env.expect.that_collection([d["name"] for d in cov_deps]).contains_exactly(["coverage[toml]"])
    env.expect.that_str(result["pins"]["requests[socks]"]).equals("requests[socks]@2.32.3")
    env.expect.that_str(result["pins"]["requests"]).equals("requests@2.32.3")

def _test_poetry_dependency_extras(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_poetry_dependency_extras_impl)

# --- test_poetry_tool_dependency_extras_and_python ---

# buildifier: disable=unused-variable
def _test_poetry_tool_dependency_extras_and_python_impl(env, target):
    project = {"tool": {"poetry": {"dependencies": {
        "python": "^3.8",
        "requests": {"version": "^2", "extras": ["socks"]},
        "foo": {"version": "^1", "python": "<3.9"},
        "bar": {"version": "^1", "python": "^3.8.1", "markers": "sys_platform == 'linux'"},
    }}}}
    lock = {
        "metadata": {"lock-version": "2.1"},
        "package": [
            _pkg("requests", "2.32.3", files = [_whl("requests-2.32.3-py3-none-any.whl")], extras = {"socks": ["PySocks"]}),
            _pkg("foo", "1.0", files = [_whl("foo-1.0-py3-none-any.whl")]),
            _pkg("bar", "1.0", files = [_whl("bar-1.0-py3-none-any.whl")]),
        ],
    }
    result = translate_poetry(project, lock, _lock_model())

    env.expect.that_str(result["pins"]["requests[socks]"]).equals("requests[socks]@2.32.3")
    markers = result["root_dependency_markers"]
    env.expect.that_collection(markers["foo"]).contains_exactly(['python_version < "3.9"'])
    env.expect.that_collection(markers["bar"]).contains_exactly([
        '(sys_platform == \'linux\') and (python_full_version >= "3.8.1" and python_full_version < "4.0.0")',
    ])

def _test_poetry_tool_dependency_extras_and_python(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_poetry_tool_dependency_extras_and_python_impl)

# --- test_poetry_git_subdirectory ---

# buildifier: disable=unused-variable
def _test_poetry_git_subdirectory_impl(env, target):
    project = {"project": {"name": "my-app", "dependencies": ["sub"]}}
    lock = {
        "metadata": {"lock-version": "2.1"},
        "package": [
            _pkg("sub", "0.1.0", files = [], source = {
                "type": "git",
                "url": "https://github.com/example/mono.git",
                "reference": "main",
                "resolved_reference": "abc123",
                "subdirectory": "pkgs/sub",
            }),
        ],
    }
    result = translate_poetry(project, lock, _lock_model())
    env.expect.that_str(result["packages"]["sub@0.1.0"]["source_dir"]).equals("pkgs/sub")

def _test_poetry_git_subdirectory(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_poetry_git_subdirectory_impl)

# --- test_poetry_caret_tilde_prerelease_and_epoch ---

# buildifier: disable=unused-variable
def _test_poetry_caret_tilde_prerelease_and_epoch_impl(env, target):
    project = {
        "tool": {"poetry": {"dependencies": {
            "python": "^3.9",
            "pkg-a": "1.0.0",
        }}},
    }
    lock = {
        "metadata": {"lock-version": "2.1"},
        "package": [
            _pkg(
                "pkg-a",
                "1.0.0",
                deps = {
                    "pre-caret": "^1.2.3a1",
                    "local-caret": "^1.2.3+build",
                    "epoch-caret": "^1!2.3.4",
                    "epoch-tilde": "~1!2.3.4rc1",
                },
                files = [_whl("pkg_a-1.0.0-py3-none-any.whl", "a")],
            ),
            _pkg("pre-caret", "1.2.3a1", files = [_whl("pre_caret-1.2.3a1-py3-none-any.whl", "1")]),
            _pkg("local-caret", "1.5.0", files = [_whl("local_caret-1.5.0-py3-none-any.whl", "1b")]),
            _pkg("epoch-caret", "1!3.0.0", files = [_whl("epoch_caret-1!3.0.0-py3-none-any.whl", "2")]),
            _pkg("epoch-caret", "1!2.5.0", files = [_whl("epoch_caret-1!2.5.0-py3-none-any.whl", "3")]),
            _pkg("epoch-caret", "2.5.0", files = [_whl("epoch_caret-2.5.0-py3-none-any.whl", "4")]),
            _pkg("epoch-tilde", "1!2.4.0", files = [_whl("epoch_tilde-1!2.4.0-py3-none-any.whl", "5")]),
            _pkg("epoch-tilde", "1!2.3.4rc1", files = [_whl("epoch_tilde-1!2.3.4rc1-py3-none-any.whl", "6")]),
        ],
    }
    result = translate_poetry(project, lock, _lock_model())
    pkg_a_deps = [d["name"] + "@" + d["version"] for d in result["packages"]["pkg-a@1.0.0"]["dependencies"]]
    env.expect.that_collection(pkg_a_deps).contains_exactly([
        "epoch-caret@1!2.5.0",
        "epoch-tilde@1!2.3.4rc1",
        "local-caret@1.5.0",
        "pre-caret@1.2.3a1",
    ])

def _test_poetry_caret_tilde_prerelease_and_epoch(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_poetry_caret_tilde_prerelease_and_epoch_impl)

# --- test_poetry_transitive_include_group_and_extras ---

# buildifier: disable=unused-variable
def _test_poetry_transitive_include_group_and_extras_impl(env, target):
    project = {
        "project": {
            "name": "my-app",
            "dependencies": ['foo>=1.0 ; sys_platform == "linux"'],
        },
        "dependency-groups": {
            "lint": ["ruff>=0.1"],
            "dev": [{"include-group": "lint"}],
            "all": [{"include-group": "dev"}],
        },
        "tool": {"poetry": {
            "dependencies": {
                "python": "^3.9",
                "foo": {"source": "private"},
                "psycopg2": {"version": "^2.9", "optional": True},
            },
            "extras": {
                "db": ["psycopg2"],
            },
        }},
    }
    lock = {
        "metadata": {"lock-version": "2.1"},
        "package": [
            _pkg("foo", "1.0.0", files = [_whl("foo-1.0.0-py3-none-any.whl", "1")]),
            _pkg("ruff", "0.5.0", files = [_whl("ruff-0.5.0-py3-none-any.whl", "2")]),
            _pkg("psycopg2", "2.9.9", files = [_whl("psycopg2-2.9.9-py3-none-any.whl", "3")], optional = True),
        ],
    }

    # Default only: foo keeps its root marker despite tool.poetry.dependencies enrichment, and optional psycopg2 is omitted.
    default_res = translate_poetry(project, lock, _lock_model(dependency_groups = ["default"]))
    env.expect.that_collection(default_res["pins"].keys()).contains_exactly(["foo"])
    env.expect.that_collection(default_res["root_dependency_markers"]["foo"]).contains_exactly(['sys_platform == "linux"'])

    # With optional:db and group:all: psycopg2 and transitively included ruff are pinned.
    full_res = translate_poetry(project, lock, _lock_model(dependency_groups = ["default", "optional:db", "group:all"]))
    env.expect.that_collection(full_res["pins"].keys()).contains_exactly(["foo", "psycopg2", "ruff"])

def _test_poetry_transitive_include_group_and_extras(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_poetry_transitive_include_group_and_extras_impl)

# --- test_poetry_url_decoded_filename_and_unnormalized_version ---

# buildifier: disable=unused-variable
def _test_poetry_url_decoded_filename_and_unnormalized_version_impl(env, target):
    project = {"tool": {"poetry": {"dependencies": {"python": "^3.9", "torch": "*", "alpha-pkg": "*"}}}}
    lock = {
        "metadata": {"lock-version": "2.1"},
        "package": [
            _pkg("torch", "2.0.0+cpu", files = [_whl("torch-2.0.0%2Bcpu-py3-none-any.whl", "1")]),
            _pkg("alpha-pkg", "1.0.0-alpha.1", files = [_whl("alpha_pkg-1.0.0a1-py3-none-any.whl", "2")]),
        ],
    }
    result = translate_poetry(project, lock, _lock_model())
    torch_files = result["packages"]["torch@2.0.0+cpu"]["files"]
    env.expect.that_collection([f["name"] for f in torch_files]).contains_exactly(["torch-2.0.0+cpu-py3-none-any.whl"])
    alpha_files = result["packages"]["alpha-pkg@1.0.0-alpha.1"]["files"]
    env.expect.that_collection([f["name"] for f in alpha_files]).contains_exactly(["alpha_pkg-1.0.0a1-py3-none-any.whl"])

def _test_poetry_url_decoded_filename_and_unnormalized_version(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_poetry_url_decoded_filename_and_unnormalized_version_impl)

# --- test_poetry_forked_transitive_dep ---

# buildifier: disable=unused-variable
def _test_poetry_forked_transitive_dep_impl(env, target):
    project = {"tool": {"poetry": {"dependencies": {"python": "^3.9", "app": "1.0.0"}}}}
    lock = {
        "metadata": {"lock-version": "2.1"},
        "package": [
            _pkg("app", "1.0.0", files = [_whl("app-1.0.0-py3-none-any.whl", "a")], deps = {"lib": ">=1.0"}),
            _pkg("lib", "1.5.0", files = [_whl("lib-1.5.0-py3-none-any.whl", "1")], markers = 'python_version < "3.10"'),
            _pkg("lib", "2.0.0", files = [_whl("lib-2.0.0-py3-none-any.whl", "2")], markers = 'python_version >= "3.10"'),
        ],
    }
    result = translate_poetry(project, lock, _lock_model())
    edges = {d["name"] + "@" + d["version"]: d["marker"] for d in result["packages"]["app@1.0.0"]["dependencies"]}
    env.expect.that_dict(edges).contains_exactly({
        "lib@1.5.0": 'python_version < "3.10"',
        "lib@2.0.0": 'python_version >= "3.10"',
    })

def _test_poetry_forked_transitive_dep(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_poetry_forked_transitive_dep_impl)

# --- test_poetry_mixed_dev_group_order ---

# buildifier: disable=unused-variable
def _test_poetry_mixed_dev_group_order_impl(env, target):
    """Per-group interleaved order: legacy tool.poetry.group.g1 runs before PEP 735 group g2."""
    project = {
        "dependency-groups": {
            "g2": ["foo==2.0.0"],
        },
        "tool": {"poetry": {
            "group": {
                "g1": {"dependencies": {"foo": "==1.0.0"}},
            },
        }},
    }
    lock = {
        "metadata": {"lock-version": "2.1"},
        "package": [
            _pkg("foo", "1.0.0", files = [_whl("foo-1.0.0-py3-none-any.whl", "1")]),
            _pkg("foo", "2.0.0", files = [_whl("foo-2.0.0-py3-none-any.whl", "2")]),
        ],
    }
    result = translate_poetry(project, lock, _lock_model(dependency_groups = ["group:g1", "group:g2"]))
    env.expect.that_str(result["pins"]["foo"]).equals("foo@2.0.0")

def _test_poetry_mixed_dev_group_order(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_poetry_mixed_dev_group_order_impl)

# --- test_poetry_workspace_cache_matches_standalone ---

# buildifier: disable=unused-variable
def _test_poetry_workspace_cache_matches_standalone_impl(env, target):
    """Cached multi-repo Poetry translation matches standalone translation exactly."""
    project = {
        "project": {
            "name": "my-app",
            "dependencies": ['forked>=1.0 ; sys_platform == "linux"'],
        },
        "dependency-groups": {"test": ["pytest==8.0.0"]},
    }
    lock = {
        "metadata": {"lock-version": "2.1"},
        "package": [
            _pkg("forked", "1.0.0", files = [_whl("forked-1.0.0-py3-none-any.whl", "1")], markers = 'python_version < "3.11"'),
            _pkg("forked", "2.0.0", files = [_whl("forked-2.0.0-py3-none-any.whl", "2")], markers = 'python_version >= "3.11"'),
            _pkg("pytest", "8.0.0", files = [_whl("pytest-8.0.0-py3-none-any.whl", "3")]),
        ],
    }
    model_default = _lock_model(dependency_groups = ["default"])
    model_all = _lock_model(dependency_groups = ["default", "group:test"])

    ws_cache = {}
    cached_default = translate_poetry(project, lock, model_default, workspace_cache = ws_cache)
    cached_all = translate_poetry(project, lock, model_all, workspace_cache = ws_cache)

    env.expect.that_bool(ws_cache.get("shared_packages", False)).equals(True)
    env.expect.that_str(json.encode(cached_default)).equals(json.encode(translate_poetry(project, lock, model_default)))
    env.expect.that_str(json.encode(cached_all)).equals(json.encode(translate_poetry(project, lock, model_all)))

def _test_poetry_workspace_cache_matches_standalone(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_poetry_workspace_cache_matches_standalone_impl)

# --- test_poetry_file_missing_hash ---

# buildifier: disable=unused-variable
def _test_poetry_file_missing_hash_impl(env, target):
    project = {"project": {"name": "my-app", "dependencies": ["pkg==1.0.0"]}}
    lock = {
        "metadata": {"lock-version": "2.1"},
        "package": [
            _pkg("pkg", "1.0.0", files = [{"file": "pkg-1.0.0-py3-none-any.whl"}]),
        ],
    }
    result = translate_poetry(project, lock, _lock_model())
    files = result["packages"]["pkg@1.0.0"]["files"]
    env.expect.that_int(len(files)).equals(1)
    env.expect.that_str(files[0]["name"]).equals("pkg-1.0.0-py3-none-any.whl")
    env.expect.that_str(files[0]["sha256"]).equals("")

def _test_poetry_file_missing_hash(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_poetry_file_missing_hash_impl)

# --- Test suite ---

def poetry_translator_test_suite(name):
    test_suite(
        name = name,
        tests = [
            _test_poetry_minimal_lock,
            _test_poetry_lock_version,
            _test_poetry_package_with_extras,
            _test_poetry_source_directory,
            _test_poetry_source_git,
            _test_poetry_optional_dependency,
            _test_poetry_forks,
            _test_poetry_url_source,
            _test_poetry_issue_34,
            _test_poetry_issue_117,
            _test_poetry_or_constraint_translations,
            _test_poetry_unary_constraint_operators,
            _test_poetry_root_dependency_markers,
            _test_poetry_dependency_extras,
            _test_poetry_tool_dependency_extras_and_python,
            _test_poetry_git_subdirectory,
            _test_poetry_caret_tilde_prerelease_and_epoch,
            _test_poetry_transitive_include_group_and_extras,
            _test_poetry_url_decoded_filename_and_unnormalized_version,
            _test_poetry_forked_transitive_dep,
            _test_poetry_mixed_dev_group_order,
            _test_poetry_workspace_cache_matches_standalone,
            _test_poetry_file_missing_hash,
        ],
    )
