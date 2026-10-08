"""Tests for the Starlark Pylock translator."""

load("@rules_testing//lib:analysis_test.bzl", "analysis_test", "test_suite")
load("@rules_testing//lib:util.bzl", "util")

# buildifier: disable=bzl-visibility
load("//pycross/private:lock_resolver.bzl", "resolve")

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

# --- test_pylock_root_dependency_markers ---

# buildifier: disable=unused-variable
def _test_pylock_root_dependency_markers_impl(env, target):
    project = {
        "project": {
            "name": "my-project",
            "dependencies": [
                "foo==1.0 ; sys_platform == \"linux\"",
                "bar==2.0",
            ],
        },
    }
    lock = {
        "lock-version": "1.0",
        "requires-python": ">=3.8",
        "package": [
            {
                "name": "foo",
                "version": "1.0",
                "wheels": [_whl("foo-1.0-py3-none-any.whl", "foo")],
            },
            {
                "name": "bar",
                "version": "2.0",
                "wheels": [_whl("bar-2.0-py3-none-any.whl", "bar")],
            },
        ],
    }
    result = translate_pylock(lock, project, _lock_model())

    markers = result.get("root_dependency_markers", {})
    env.expect.that_collection(markers.keys()).contains("foo")
    env.expect.that_collection(markers.keys()).contains_none_of(["bar"])
    env.expect.that_str(markers["foo"][0]).equals("sys_platform == \"linux\"")

def _test_pylock_root_dependency_markers(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_pylock_root_dependency_markers_impl)

# --- test_pylock_pdm_tool_dependencies ---

# buildifier: disable=unused-variable
def _test_pylock_pdm_tool_dependencies_impl(env, target):
    """PDM's exporter writes the graph under [packages.tool.pdm].dependencies."""
    project = {"project": {"name": "my-project", "dependencies": ["requests"]}}
    lock = {
        "lock-version": "1.0",
        "packages": [
            {
                "name": "requests",
                "version": "2.32.3",
                "wheels": [_whl("requests-2.32.3-py3-none-any.whl", "req")],
                "tool": {"pdm": {"dependencies": ["urllib3<3,>=1.21.1", "PySocks!=1.5.7,>=1.5.6; extra == \"socks\""]}},
            },
            {
                "name": "urllib3",
                "version": "2.2.0",
                "wheels": [_whl("urllib3-2.2.0-py3-none-any.whl", "url")],
                "tool": {"pdm": {"dependencies": []}},
            },
            {
                "name": "pysocks",
                "version": "1.7.1",
                "wheels": [_whl("PySocks-1.7.1-py3-none-any.whl", "soc")],
            },
        ],
    }
    result = translate_pylock(lock, project, _lock_model())
    env.expect.that_collection(_pkg_names(result)).contains_exactly(["requests", "urllib3", "pysocks"])
    deps = result["packages"]["requests@2.32.3"]["dependencies"]
    env.expect.that_collection([d["name"] for d in deps]).contains_exactly(["pysocks", "urllib3"])
    env.expect.that_str([d for d in deps if d["name"] == "pysocks"][0]["marker"]).equals('extra == "socks"')

def _test_pylock_pdm_tool_dependencies(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_pylock_pdm_tool_dependencies_impl)

# --- test_pylock_source_kinds ---

# buildifier: disable=unused-variable
def _test_pylock_source_kinds_impl(env, target):
    lock = {
        "lock-version": "1.0",
        "packages": [
            {
                "name": "torch",
                "version": "2.5.1+cpu",
                "wheels": [{
                    "url": "https://download.pytorch.org/whl/cpu/torch-2.5.1%2Bcpu-cp312-cp312-linux_x86_64.whl",
                    "hashes": {"sha256": "abc"},
                }],
            },
            {
                "name": "mono",
                "version": "0.1.0",
                "vcs": {"type": "git", "url": "https://github.com/example/mono", "commit-id": "0123456789abcdef", "subdirectory": "pkgs/mono"},
            },
            {
                "name": "boto3",
                "version": "1.35.13",
                "archive": {"url": "https://github.com/boto/boto3/archive/refs/tags/1.35.13.zip", "hashes": {"sha256": "def"}},
            },
            {"name": "subpkg", "directory": {"path": "sub", "editable": False}},
        ],
    }
    result = translate_pylock(lock, None, _lock_model())
    env.expect.that_collection(result["packages"].keys()).contains_exactly(["torch@2.5.1+cpu", "mono@0.1.0", "boto3@1.35.13"])
    env.expect.that_str(result["packages"]["torch@2.5.1+cpu"]["files"][0]["name"]).equals("torch-2.5.1+cpu-cp312-cp312-linux_x86_64.whl")

    mono = result["packages"]["mono@0.1.0"]
    env.expect.that_str(mono["source_dir"]).equals("pkgs/mono")
    env.expect.that_collection(mono["files"][0]["urls"]).contains_exactly(["git+https://github.com/example/mono#0123456789abcdef"])

    boto3 = result["packages"]["boto3@1.35.13"]["files"][0]
    env.expect.that_str(boto3["name"]).equals("boto3-1.35.13.zip")
    env.expect.that_str(boto3["sha256"]).equals("def")

def _test_pylock_source_kinds(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_pylock_source_kinds_impl)

# --- test_pylock_graphless ---

def _graphless_pkg(name, version, marker = None):
    pkg = {"name": name, "version": version, "wheels": [_whl("{}-{}-py3-none-any.whl".format(name, version), name)]}
    if marker:
        pkg["marker"] = marker
    return pkg

def _edges(result, pkg_key):
    return {
        "{}@{}".format(d["name"], d["version"]): d["marker"]
        for d in result["packages"][pkg_key]["dependencies"]
    }

# buildifier: disable=unused-variable
def _test_pylock_graphless_impl(env, target):
    """pip lock / uv export write no graph: packages are tied into one cycle via a hub."""
    project = {"project": {"name": "my-project", "dependencies": ["requests"]}}
    lock = {
        "lock-version": "1.0",
        "created-by": "pip",
        "packages": [
            _graphless_pkg("requests", "2.32.3"),
            _graphless_pkg("urllib3", "2.2.0"),
            _graphless_pkg("certifi", "2024.8.30"),
            _graphless_pkg("colorama", "0.4.6", 'sys_platform == "win32" and "dev" in dependency_groups'),
            _graphless_pkg("greenlet", "3.2.5", 'python_version < "3.10"'),
            _graphless_pkg("greenlet", "3.5.3", 'python_version >= "3.10"'),
        ],
    }
    result = translate_pylock(lock, project, _lock_model())

    # Every package is kept, but only the declared root is pinned.
    env.expect.that_collection(result["packages"].keys()).contains_exactly([
        "requests@2.32.3",
        "urllib3@2.2.0",
        "certifi@2024.8.30",
        "colorama@0.4.6",
        "greenlet@3.2.5",
        "greenlet@3.5.3",
    ])
    env.expect.that_collection(result["pins"].keys()).contains_exactly(["requests"])

    # The hub (first unconditional package) depends on everything, gated by
    # each package's environment marker; selection markers are stripped.
    env.expect.that_dict(_edges(result, "certifi@2024.8.30")).contains_exactly({
        "requests@2.32.3": "",
        "urllib3@2.2.0": "",
        "colorama@0.4.6": 'sys_platform == "win32"',
        "greenlet@3.2.5": 'python_version < "3.10"',
        "greenlet@3.5.3": 'python_version >= "3.10"',
    })

    # Every other package depends on the hub, closing the cycle.
    for key in ["requests@2.32.3", "urllib3@2.2.0", "colorama@0.4.6", "greenlet@3.2.5"]:
        env.expect.that_dict(_edges(result, key)).contains_exactly({"certifi@2024.8.30": ""})

    resolved = resolve(result)
    env.expect.that_collection(resolved.cycle_groups.values()[0]).contains_exactly(result["packages"].keys())

def _test_pylock_graphless(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_pylock_graphless_impl)

# buildifier: disable=unused-variable
def _test_pylock_graphless_all_marked_impl(env, target):
    """Without an unconditional package, every package links to every other."""
    lock = {
        "lock-version": "1.0",
        "packages": [
            _graphless_pkg("greenlet", "3.2.5", 'python_version < "3.10"'),
            _graphless_pkg("greenlet", "3.5.3", 'python_version >= "3.10"'),
        ],
    }
    result = translate_pylock(lock, None, _lock_model())
    env.expect.that_dict(_edges(result, "greenlet@3.2.5")).contains_exactly({"greenlet@3.5.3": 'python_version >= "3.10"'})
    env.expect.that_dict(_edges(result, "greenlet@3.5.3")).contains_exactly({"greenlet@3.2.5": 'python_version < "3.10"'})

def _test_pylock_graphless_all_marked(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_pylock_graphless_all_marked_impl)

# buildifier: disable=unused-variable
def _test_pylock_graphless_single_package_impl(env, target):
    lock = {"lock-version": "1.0", "packages": [_graphless_pkg("six", "1.16.0")]}
    result = translate_pylock(lock, None, _lock_model())
    env.expect.that_collection(result["packages"]["six@1.16.0"]["dependencies"]).has_size(0)

def _test_pylock_graphless_single_package(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_pylock_graphless_single_package_impl)

def _pdm_pkg(name, version, deps = None, marker = '"default" in dependency_groups'):
    pkg = _graphless_pkg(name, version, marker)
    if deps != None:
        pkg["tool"] = {"pdm": {"dependencies": deps}}
    return pkg

# buildifier: disable=unused-variable
def _test_pylock_pdm_orphan_impl(env, target):
    """Modeled on `pdm export -f pylock` for `requests[socks]`: the extras edge is dropped."""
    project = {"project": {"name": "my-project", "dependencies": ["requests[socks]==2.32.3"]}}
    lock = {
        "lock-version": "1.0",
        "created-by": "pdm",
        "packages": [
            _pdm_pkg("certifi", "2024.8.30", []),
            _pdm_pkg("idna", "3.10", []),
            _pdm_pkg("pysocks", "1.7.1"),
            _pdm_pkg("requests", "2.32.3", ["certifi>=2017.4.17", "idna<4,>=2.5", "urllib3<3,>=1.21.1"]),
            _pdm_pkg("urllib3", "2.2.3", []),
            _pdm_pkg("pytest", "8.3.3", [], '"dev" in dependency_groups'),
        ],
    }
    result = translate_pylock(lock, project, _lock_model())

    # pysocks is an orphan in a requested group: it joins the hub cycle. pytest
    # only selects the unrequested "dev" group, so it is still dropped.
    env.expect.that_collection(_pkg_names(result)).contains_exactly(["certifi", "idna", "pysocks", "requests", "urllib3"])
    env.expect.that_dict(_edges(result, "certifi@2024.8.30")).contains_exactly({
        "idna@3.10": "",
        "pysocks@1.7.1": "",
        "requests@2.32.3": "",
        "urllib3@2.2.3": "",
    })

    # Graph edges are kept alongside the hub edge, without duplicates.
    env.expect.that_dict(_edges(result, "requests@2.32.3")).contains_exactly({
        "certifi@2024.8.30": "",
        "idna@3.10": "",
        "urllib3@2.2.3": "",
    })
    env.expect.that_collection(result["pins"].keys()).contains_exactly(["requests"])

    resolved = resolve(result)
    env.expect.that_collection(resolved.cycle_groups.values()[0]).contains_exactly(result["packages"].keys())

def _test_pylock_pdm_orphan(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_pylock_pdm_orphan_impl)

# buildifier: disable=unused-variable
def _test_pylock_pdm_reachable_no_hub_impl(env, target):
    """A fully reachable PDM graph keeps its precise edges."""
    project = {"project": {"name": "my-project", "dependencies": ["requests==2.32.3"]}}
    lock = {
        "lock-version": "1.0",
        "packages": [
            _pdm_pkg("certifi", "2024.8.30", []),
            _pdm_pkg("requests", "2.32.3", ["certifi>=2017.4.17"]),
            _pdm_pkg("pytest", "8.3.3", [], '"dev" in dependency_groups'),
        ],
    }
    result = translate_pylock(lock, project, _lock_model())
    env.expect.that_collection(_pkg_names(result)).contains_exactly(["certifi", "requests"])
    env.expect.that_collection(result["packages"]["certifi@2024.8.30"]["dependencies"]).has_size(0)
    env.expect.that_dict(_edges(result, "requests@2.32.3")).contains_exactly({"certifi@2024.8.30": ""})

def _test_pylock_pdm_reachable_no_hub(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_pylock_pdm_reachable_no_hub_impl)

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
            _test_pylock_root_dependency_markers,
            _test_pylock_pdm_tool_dependencies,
            _test_pylock_source_kinds,
            _test_pylock_graphless,
            _test_pylock_graphless_all_marked,
            _test_pylock_graphless_single_package,
            _test_pylock_pdm_orphan,
            _test_pylock_pdm_reachable_no_hub,
        ],
    )
