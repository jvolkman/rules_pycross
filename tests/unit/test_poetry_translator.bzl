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

def _pkg(name, version, files = None, deps = None, optional = False, python_versions = "*", extras = None, source = None, markers = None):
    """Build a Poetry lock package entry."""
    p = {
        "name": name,
        "version": version,
        "description": "",
        "optional": optional,
        "python-versions": python_versions,
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

# --- test_python_constraint ---

# buildifier: disable=unused-variable
def _test_poetry_python_constraint_impl(env, target):
    project = {"tool": {"poetry": {"dependencies": {"python": "^3.8", "a": "1.0"}}}}
    lock = {
        "metadata": {"lock-version": "2.1"},
        "package": [
            _pkg("a", "1.0", files = [_whl("a-1.0-py3-none-any.whl", "a")], python_versions = ">=3.9,<3.13"),
        ],
    }
    result = translate_poetry(project, lock, _lock_model())
    pkg_a = result["packages"]["a@1.0"]
    env.expect.that_str(pkg_a["python_versions"]).contains("3.9")
    env.expect.that_str(pkg_a["python_versions"]).contains("3.13")

def _test_poetry_python_constraint(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_poetry_python_constraint_impl)

# --- test_python_caret_constraint ---

# buildifier: disable=unused-variable
def _test_poetry_python_caret_constraint_impl(env, target):
    project = {"tool": {"poetry": {"dependencies": {"python": "^3.8", "a": "1.0"}}}}
    lock = {
        "metadata": {"lock-version": "2.1"},
        "package": [
            _pkg("a", "1.0", files = [_whl("a-1.0-py3-none-any.whl", "a")], python_versions = "^3.9"),
        ],
    }
    result = translate_poetry(project, lock, _lock_model())
    pkg_a = result["packages"]["a@1.0"]

    # ^3.9 should expand to >=3.9,<4.0
    env.expect.that_str(pkg_a["python_versions"]).equals(">=3.9,<4.0")

def _test_poetry_python_caret_constraint(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_poetry_python_caret_constraint_impl)

# --- test_python_or_constraint ---

# buildifier: disable=unused-variable
def _test_poetry_python_or_constraint_impl(env, target):
    project = {"tool": {"poetry": {"dependencies": {"python": "^3.8", "a": "1.0"}}}}
    lock = {
        "metadata": {"lock-version": "2.1"},
        "package": [
            _pkg("a", "1.0", files = [_whl("a-1.0-py3-none-any.whl", "a")], python_versions = "^3.8 || ^3.10"),
        ],
    }
    result = translate_poetry(project, lock, _lock_model())
    pkg_a = result["packages"]["a@1.0"]

    # ^3.8 || ^3.10 should expand to >=3.8,<4.0,>=3.10,<4.0
    env.expect.that_str(pkg_a["python_versions"]).equals(">=3.8,<4.0,>=3.10,<4.0")

def _test_poetry_python_or_constraint(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_poetry_python_or_constraint_impl)

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
            _test_poetry_python_constraint,
            _test_poetry_python_caret_constraint,
            _test_poetry_python_or_constraint,
            _test_poetry_optional_dependency,
            _test_poetry_forks,
            _test_poetry_url_source,
            _test_poetry_issue_34,
            _test_poetry_issue_117,
        ],
    )
