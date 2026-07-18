"""Tests for the Starlark Pylock translator."""

load("@rules_testing//lib:analysis_test.bzl", "analysis_test", "test_suite")
load("@rules_testing//lib:util.bzl", "util")

# buildifier: disable=bzl-visibility
load("//pycross/private:pylock_lock_model.bzl", "translate_pylock")

def _lock_model(
        projects = ["*"],
        dependency_groups = ["default"]):
    return struct(
        projects = projects,
        dependency_groups = dependency_groups,
    )

def _whl(name, sha256, url = None, hashes = None):
    """Build a wheel entry for a pylock package."""
    w = {"file": name}
    if hashes:
        w["hashes"] = hashes
    elif sha256:
        w["hash"] = "sha256:" + sha256
    if url:
        w["url"] = url
    return w

def _sdist(name, sha256, url = None):
    s = {"file": name, "hash": "sha256:" + sha256}
    if url:
        s["url"] = url
    return s

def _dep(name, marker = None):
    d = {"name": name}
    if marker:
        d["marker"] = marker
    return d

# Shared fixtures

_LOCK_WITH_GROUPS = {
    "lock-version": "1.0",
    "requires-python": ">=3.8",
    "package": [
        {
            "name": "requests",
            "version": "2.31.0",
            "dependencies": [_dep("urllib3")],
            "wheels": [_whl("requests-2.31.0-py3-none-any.whl", "req")],
        },
        {
            "name": "urllib3",
            "version": "2.0.0",
            "wheels": [_whl("urllib3-2.0.0-py3-none-any.whl", "url")],
        },
        {
            "name": "pytest",
            "version": "7.4.0",
            "dependencies": [_dep("pluggy")],
            "wheels": [_whl("pytest-7.4.0-py3-none-any.whl", "pyt")],
        },
        {
            "name": "pluggy",
            "version": "1.2.0",
            "wheels": [_whl("pluggy-1.2.0-py3-none-any.whl", "plg")],
        },
        {
            "name": "mypy",
            "version": "1.5.0",
            "wheels": [_whl("mypy-1.5.0-py3-none-any.whl", "myp")],
        },
        {
            "name": "ruff",
            "version": "0.1.0",
            "wheels": [_whl("ruff-0.1.0-py3-none-any.whl", "ruf")],
        },
        {
            "name": "typing-extensions",
            "version": "4.7.0",
            "wheels": [_whl("typing_extensions-4.7.0-py3-none-any.whl", "tex")],
        },
    ],
}

_PROJECT_WITH_GROUPS = {
    "project": {
        "name": "my-project",
        "version": "1.0.0",
        "dependencies": ["requests>=2.0"],
        "optional-dependencies": {
            "test": ["pytest>=7.0"],
            "lint": ["ruff>=0.1"],
        },
    },
    "dependency-groups": {
        "dev": ["mypy>=1.0"],
        "typing": ["typing-extensions>=4.0"],
        "all": ["ruff", {"include-group": "typing"}],
    },
}

def _pkg_names(result):
    """Extract package names from a translate result."""
    return [result["packages"][k]["name"] for k in result["packages"]]

# --- test_minimal_lock ---

# buildifier: disable=unused-variable
def _test_pylock_minimal_lock_impl(env, target):
    lock = {
        "lock-version": "1.0",
        "requires-python": ">=3.8",
        "package": [
            {
                "name": "my-app",
                "version": "0.1.0",
                "wheels": [_whl("my_app-0.1.0-py3-none-any.whl", "abc")],
                "dependencies": [_dep("requests")],
            },
            {
                "name": "requests",
                "version": "2.31.0",
                "wheels": [_whl("requests-2.31.0-py3-none-any.whl", "1234567890abcdef")],
            },
        ],
    }
    result = translate_pylock(lock, None, _lock_model())
    env.expect.that_collection(result["packages"].keys()).contains("requests@2.31.0")
    pkg = result["packages"]["requests@2.31.0"]
    env.expect.that_str(pkg["files"][0]["sha256"]).equals("1234567890abcdef")
    env.expect.that_str(pkg["files"][0]["package_name"]).equals("requests")
    env.expect.that_str(pkg["files"][0]["package_version"]).equals("2.31.0")

def _test_pylock_minimal_lock(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_pylock_minimal_lock_impl)

# --- test_dependencies ---

# buildifier: disable=unused-variable
def _test_pylock_dependencies_impl(env, target):
    lock = {
        "lock-version": "1.0",
        "requires-python": ">=3.8",
        "package": [
            {
                "name": "my-app",
                "version": "0.1.0",
                "wheels": [_whl("my_app-0.1.0-py3-none-any.whl", "abc")],
                "dependencies": [_dep("a")],
            },
            {
                "name": "a",
                "version": "1.0",
                "dependencies": [_dep("b")],
                "wheels": [_whl("a-1.0-py3-none-any.whl", "a")],
            },
            {
                "name": "b",
                "version": "2.0",
                "wheels": [_whl("b-2.0-py3-none-any.whl", "b")],
            },
        ],
    }
    result = translate_pylock(lock, None, _lock_model())
    env.expect.that_int(len(result["packages"])).equals(3)
    pkg_a = result["packages"]["a@1.0"]
    env.expect.that_int(len(pkg_a["dependencies"])).equals(1)
    env.expect.that_str(pkg_a["dependencies"][0]["name"]).equals("b")

def _test_pylock_dependencies(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_pylock_dependencies_impl)

# --- test_platform_specific_deps ---

# buildifier: disable=unused-variable
def _test_pylock_platform_specific_deps_impl(env, target):
    lock = {
        "lock-version": "1.0",
        "requires-python": ">=3.8",
        "package": [
            {
                "name": "my-app",
                "version": "0.1.0",
                "wheels": [_whl("my_app-0.1.0-py3-none-any.whl", "abc")],
                "dependencies": [_dep("a")],
            },
            {
                "name": "a",
                "version": "1.0",
                "wheels": [_whl("a-1.0-py3-none-any.whl", "a")],
                "dependencies": [_dep("b", marker = "sys_platform == 'linux'")],
            },
            {
                "name": "b",
                "version": "2.0",
                "wheels": [_whl("b-2.0-py3-none-any.whl", "b")],
            },
        ],
    }
    result = translate_pylock(lock, None, _lock_model())
    pkg_a = result["packages"]["a@1.0"]
    dep_b = pkg_a["dependencies"][0]
    env.expect.that_str(dep_b["marker"]).equals("sys_platform == 'linux'")

def _test_pylock_platform_specific_deps(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_pylock_platform_specific_deps_impl)

# --- test_wheels_with_urls ---

# buildifier: disable=unused-variable
def _test_pylock_wheels_with_urls_impl(env, target):
    lock = {
        "lock-version": "1.0",
        "requires-python": ">=3.8",
        "package": [
            {
                "name": "my-app",
                "version": "0.1.0",
                "wheels": [_whl("my_app-0.1.0-py3-none-any.whl", "abc")],
                "dependencies": [_dep("a")],
            },
            {
                "name": "a",
                "version": "1.0",
                "wheels": [_whl("a-1.0-py3-none-any.whl", "a", url = "https://example.com/a-1.0-py3-none-any.whl")],
            },
        ],
    }
    result = translate_pylock(lock, None, _lock_model())
    pkg = result["packages"]["a@1.0"]
    env.expect.that_collection(pkg["files"][0]["urls"]).contains("https://example.com/a-1.0-py3-none-any.whl")

def _test_pylock_wheels_with_urls(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_pylock_wheels_with_urls_impl)

# --- test_wheel_hashes_table ---

# buildifier: disable=unused-variable
def _test_pylock_wheel_hashes_table_impl(env, target):
    lock = {
        "lock-version": "1.0",
        "requires-python": ">=3.8",
        "package": [{
            "name": "a",
            "version": "1.0",
            "wheels": [_whl("a-1.0-py3-none-any.whl", None, hashes = {"sha256": "deadbeef"})],
        }],
    }
    result = translate_pylock(lock, None, _lock_model())
    pkg = result["packages"]["a@1.0"]
    env.expect.that_str(pkg["files"][0]["sha256"]).equals("deadbeef")

def _test_pylock_wheel_hashes_table(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_pylock_wheel_hashes_table_impl)

# --- test_no_default ---

# buildifier: disable=unused-variable
def _test_pylock_no_default_impl(env, target):
    result = translate_pylock(_LOCK_WITH_GROUPS, _PROJECT_WITH_GROUPS, _lock_model(dependency_groups = []))
    env.expect.that_int(len(result["packages"])).equals(0)
    env.expect.that_int(len(result["pins"])).equals(0)

def _test_pylock_no_default(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_pylock_no_default_impl)

# --- test_optional_group ---

# buildifier: disable=unused-variable
def _test_pylock_optional_group_impl(env, target):
    result = translate_pylock(
        _LOCK_WITH_GROUPS,
        _PROJECT_WITH_GROUPS,
        _lock_model(dependency_groups = ["optional:test"]),
    )
    names = _pkg_names(result)
    env.expect.that_collection(names).contains_at_least(["pytest", "pluggy"])
    env.expect.that_collection(names).contains_none_of(["requests", "urllib3"])
    env.expect.that_int(len(result["packages"])).equals(2)

def _test_pylock_optional_group(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_pylock_optional_group_impl)

# --- test_all_optional_groups ---

# buildifier: disable=unused-variable
def _test_pylock_all_optional_groups_impl(env, target):
    result = translate_pylock(
        _LOCK_WITH_GROUPS,
        _PROJECT_WITH_GROUPS,
        _lock_model(dependency_groups = ["optional:*"]),
    )
    names = _pkg_names(result)
    env.expect.that_collection(names).contains_at_least(["pytest", "pluggy", "ruff"])
    env.expect.that_collection(names).contains_none_of(["requests"])

def _test_pylock_all_optional_groups(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_pylock_all_optional_groups_impl)

# --- test_development_group ---

# buildifier: disable=unused-variable
def _test_pylock_development_group_impl(env, target):
    result = translate_pylock(
        _LOCK_WITH_GROUPS,
        _PROJECT_WITH_GROUPS,
        _lock_model(dependency_groups = ["group:dev"]),
    )
    names = _pkg_names(result)
    env.expect.that_collection(names).contains_exactly(["mypy"])

def _test_pylock_development_group(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_pylock_development_group_impl)

# --- test_all_development_groups ---

# buildifier: disable=unused-variable
def _test_pylock_all_development_groups_impl(env, target):
    result = translate_pylock(
        _LOCK_WITH_GROUPS,
        _PROJECT_WITH_GROUPS,
        _lock_model(dependency_groups = ["group:*"]),
    )
    names = _pkg_names(result)
    env.expect.that_collection(names).contains_at_least(["mypy", "typing-extensions", "ruff"])

def _test_pylock_all_development_groups(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_pylock_all_development_groups_impl)

# --- test_include_group ---

# buildifier: disable=unused-variable
def _test_pylock_include_group_impl(env, target):
    result = translate_pylock(
        _LOCK_WITH_GROUPS,
        _PROJECT_WITH_GROUPS,
        _lock_model(dependency_groups = ["group:all"]),
    )
    names = _pkg_names(result)
    env.expect.that_collection(names).contains_at_least(["ruff", "typing-extensions"])
    env.expect.that_collection(names).contains_none_of(["mypy"])

def _test_pylock_include_group(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_pylock_include_group_impl)

# --- test_graph_traversal ---

# buildifier: disable=unused-variable
def _test_pylock_graph_traversal_impl(env, target):
    result = translate_pylock(
        _LOCK_WITH_GROUPS,
        _PROJECT_WITH_GROUPS,
        _lock_model(dependency_groups = ["default", "optional:test"]),
    )
    names = _pkg_names(result)

    # From default: requests -> urllib3
    env.expect.that_collection(names).contains_at_least(["requests", "urllib3"])

    # From test: pytest -> pluggy
    env.expect.that_collection(names).contains_at_least(["pytest", "pluggy"])

    # Not reachable
    env.expect.that_collection(names).contains_none_of(["mypy", "ruff", "typing-extensions"])
    env.expect.that_int(len(result["packages"])).equals(4)

    # Pins: direct roots only, not transitive deps
    env.expect.that_collection(result["pins"].keys()).contains_at_least(["requests", "pytest"])
    env.expect.that_collection(result["pins"].keys()).contains_none_of(["urllib3", "pluggy"])

def _test_pylock_graph_traversal(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_pylock_graph_traversal_impl)

# --- test_sdist_parsing ---

# buildifier: disable=unused-variable
def _test_pylock_sdist_parsing_impl(env, target):
    lock = {
        "lock-version": "1.0",
        "requires-python": ">=3.8",
        "package": [{
            "name": "foo",
            "version": "1.0.0",
            "wheels": [_whl("foo-1.0.0-py3-none-any.whl", "whlhash")],
            "sdists": [_sdist("foo-1.0.0.tar.gz", "sdsthash", url = "https://files.example.com/foo-1.0.0.tar.gz")],
        }],
    }
    result = translate_pylock(lock, None, _lock_model())
    pkg = result["packages"]["foo@1.0.0"]
    env.expect.that_int(len(pkg["files"])).equals(2)

    file_names = [f["name"] for f in pkg["files"]]
    env.expect.that_collection(file_names).contains_at_least(["foo-1.0.0-py3-none-any.whl", "foo-1.0.0.tar.gz"])

    sdist_files = [f for f in pkg["files"] if f["name"] == "foo-1.0.0.tar.gz"]
    env.expect.that_str(sdist_files[0]["sha256"]).equals("sdsthash")
    env.expect.that_collection(sdist_files[0]["urls"]).contains("https://files.example.com/foo-1.0.0.tar.gz")

def _test_pylock_sdist_parsing(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_pylock_sdist_parsing_impl)

# --- test_no_default_no_groups_empty ---

# buildifier: disable=unused-variable
def _test_pylock_no_default_no_groups_empty_impl(env, target):
    lock = {
        "lock-version": "1.0",
        "requires-python": ">=3.8",
        "package": [
            {
                "name": "requests",
                "version": "2.31.0",
                "wheels": [_whl("requests-2.31.0-py3-none-any.whl", "req")],
            },
            {
                "name": "pytest",
                "version": "7.4.0",
                "wheels": [_whl("pytest-7.4.0-py3-none-any.whl", "pyt")],
            },
        ],
    }
    project = {
        "project": {
            "name": "my-project",
            "version": "1.0.0",
            "dependencies": ["requests"],
            "optional-dependencies": {"test": ["pytest"]},
        },
    }
    result = translate_pylock(lock, project, _lock_model(dependency_groups = []))
    env.expect.that_int(len(result["packages"])).equals(0)
    env.expect.that_int(len(result["pins"])).equals(0)

def _test_pylock_no_default_no_groups_empty(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_pylock_no_default_no_groups_empty_impl)

# --- test_pylock_resolution_forks ---

# buildifier: disable=unused-variable
def _test_pylock_resolution_forks_impl(env, target):
    """Test pylock files with multiple versions of the same package (multi-target forks)."""
    lock = {
        "lock-version": "1.0",
        "requires-python": ">=3.9",
        "environments": [
            'python_version < "3.10" and python_version >= "3.9"',
            'python_version >= "3.10"',
        ],
        "package": [
            {
                "name": "greenlet",
                "version": "3.2.5",
                "requires-python": ">=3.9",
                "marker": 'python_version < "3.10" and python_version >= "3.9" and "default" in dependency_groups',
                "wheels": [_whl("greenlet-3.2.5-cp39-cp39-manylinux2014_x86_64.whl", "aaaa")],
            },
            {
                "name": "greenlet",
                "version": "3.5.3",
                "requires-python": ">=3.10",
                "marker": 'python_version >= "3.10" and "default" in dependency_groups',
                "wheels": [_whl("greenlet-3.5.3-cp310-cp310-manylinux_2_24_x86_64.whl", "bbbb")],
            },
        ],
    }
    result = translate_pylock(lock, None, _lock_model())

    # Both versions should be present as separate packages
    env.expect.that_collection(result["packages"].keys()).contains_exactly(["greenlet@3.2.5", "greenlet@3.5.3"])

    # Resolution marker expressions should be generated (with PDM selection markers stripped)
    res_exprs = result.get("resolution_marker_exprs", {})
    env.expect.that_bool("res_greenlet_3_2_5" in res_exprs).equals(True)
    env.expect.that_bool("res_greenlet_3_5_3" in res_exprs).equals(True)

    env.expect.that_str(res_exprs["res_greenlet_3_2_5"]).equals('python_version < "3.10" and python_version >= "3.9"')
    env.expect.that_str(res_exprs["res_greenlet_3_5_3"]).equals('python_version >= "3.10"')

    # Pinned specs should be conditional
    pins = result["pins"]["greenlet"]
    env.expect.that_str(pins["res_greenlet_3_2_5"]).equals("greenlet@3.2.5")
    env.expect.that_str(pins["res_greenlet_3_5_3"]).equals("greenlet@3.5.3")

def _test_pylock_resolution_forks(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_pylock_resolution_forks_impl)

# --- Test suite ---

def pylock_translator_test_suite(name):
    test_suite(
        name = name,
        tests = [
            _test_pylock_minimal_lock,
            _test_pylock_dependencies,
            _test_pylock_platform_specific_deps,
            _test_pylock_wheels_with_urls,
            _test_pylock_wheel_hashes_table,
            _test_pylock_no_default,
            _test_pylock_optional_group,
            _test_pylock_all_optional_groups,
            _test_pylock_development_group,
            _test_pylock_all_development_groups,
            _test_pylock_include_group,
            _test_pylock_graph_traversal,
            _test_pylock_sdist_parsing,
            _test_pylock_no_default_no_groups_empty,
            _test_pylock_resolution_forks,
        ],
    )
