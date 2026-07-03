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

def _pkg(name, version, files = None, deps = None, optional = False, python_versions = "*", extras = None, source = None):
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
        "metadata": {"lock-version": "2.0"},
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
        "metadata": {"lock-version": "2.0"},
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
        "metadata": {"lock-version": "2.0"},
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
        "metadata": {"lock-version": "2.0"},
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
        "metadata": {"lock-version": "2.0"},
        "package": [
            _pkg("a", "1.0", source = {"type": "git", "url": "..."}),
        ],
    }
    result = translate_poetry(project, lock, _lock_model())
    env.expect.that_collection(result["packages"].keys()).has_size(0)

def _test_poetry_source_git(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_poetry_source_git_impl)

# --- test_python_constraint ---

# buildifier: disable=unused-variable
def _test_poetry_python_constraint_impl(env, target):
    project = {"tool": {"poetry": {"dependencies": {"python": "^3.8", "a": "1.0"}}}}
    lock = {
        "metadata": {"lock-version": "2.0"},
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

# --- test_optional_dependency ---

# buildifier: disable=unused-variable
def _test_poetry_optional_dependency_impl(env, target):
    project = {"tool": {"poetry": {"dependencies": {"python": "^3.8", "a": "1.0"}}}}
    lock = {
        "metadata": {"lock-version": "2.0"},
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
            _test_poetry_optional_dependency,
        ],
    )
