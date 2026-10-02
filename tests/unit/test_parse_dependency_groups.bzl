"""Tests for parse_dependency_group_entries in lock_common.bzl."""

load("@rules_testing//lib:analysis_test.bzl", "analysis_test", "test_suite")
load("@rules_testing//lib:util.bzl", "util")

# buildifier: disable=bzl-visibility
load("//pycross/private:lock_common.bzl", "discover_uv_all_members", "parse_dependency_group_entries")

# buildifier: disable=bzl-visibility
load("//pycross/private:translator_common.bzl", "read_toml_cached", "select_project_file")

# buildifier: disable=bzl-visibility
load("//pycross/private:uv_lock_model.bzl", "repo_create_uv_model")

# --- test: basic testonly group ---

# buildifier: disable=unused-variable
def _test_parse_basic_testonly_impl(env, target):
    """['default', 'group:dev;testonly'] -> group:dev is testonly."""
    result = parse_dependency_group_entries(["default", "group:dev;testonly"])

    env.expect.that_collection(result.dependency_groups).contains_exactly(["default", "group:dev"])
    env.expect.that_collection(result.testonly_groups).contains_exactly(["group:dev"])
    env.expect.that_collection(result.non_testonly_groups).contains_exactly(["default"])
    env.expect.that_bool(result.wildcard_testonly).equals(False)

def _test_parse_basic_testonly(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_parse_basic_testonly_impl)

# --- test: wildcard then specific testonly ---

# buildifier: disable=unused-variable
def _test_parse_wildcard_then_specific_testonly_impl(env, target):
    """['*', 'group:dev;testonly'] -> wildcard not testonly, group:dev overrides to testonly."""
    result = parse_dependency_group_entries(["*", "group:dev;testonly"])

    env.expect.that_bool(result.wildcard_testonly).equals(False)
    env.expect.that_collection(result.testonly_groups).contains_exactly(["group:dev"])
    env.expect.that_collection(result.non_testonly_groups).has_size(0)

def _test_parse_wildcard_then_specific_testonly(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_parse_wildcard_then_specific_testonly_impl)

# --- test: specific testonly then wildcard resets ---

# buildifier: disable=unused-variable
def _test_parse_specific_testonly_then_wildcard_impl(env, target):
    """['group:dev;testonly', '*'] -> * comes last, resets group:dev's testonly."""
    result = parse_dependency_group_entries(["group:dev;testonly", "*"])

    env.expect.that_bool(result.wildcard_testonly).equals(False)
    env.expect.that_collection(result.testonly_groups).has_size(0)
    env.expect.that_collection(result.non_testonly_groups).has_size(0)

def _test_parse_specific_testonly_then_wildcard(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_parse_specific_testonly_then_wildcard_impl)

# --- test: wildcard testonly with specific override ---

# buildifier: disable=unused-variable
def _test_parse_wildcard_testonly_with_override_impl(env, target):
    """['*;testonly', 'group:dev'] -> everything testonly except group:dev."""
    result = parse_dependency_group_entries(["*;testonly", "group:dev"])

    env.expect.that_bool(result.wildcard_testonly).equals(True)
    env.expect.that_collection(result.testonly_groups).has_size(0)
    env.expect.that_collection(result.non_testonly_groups).contains_exactly(["group:dev"])

def _test_parse_wildcard_testonly_with_override(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_parse_wildcard_testonly_with_override_impl)

# --- test: wildcard testonly alone ---

# buildifier: disable=unused-variable
def _test_parse_wildcard_testonly_alone_impl(env, target):
    """['*;testonly'] -> everything testonly, no overrides."""
    result = parse_dependency_group_entries(["*;testonly"])

    env.expect.that_bool(result.wildcard_testonly).equals(True)
    env.expect.that_collection(result.testonly_groups).has_size(0)
    env.expect.that_collection(result.non_testonly_groups).has_size(0)

def _test_parse_wildcard_testonly_alone(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_parse_wildcard_testonly_alone_impl)

# --- test: no testonly at all ---

# buildifier: disable=unused-variable
def _test_parse_no_testonly_impl(env, target):
    """['default', 'group:dev'] -> nothing testonly."""
    result = parse_dependency_group_entries(["default", "group:dev"])

    env.expect.that_bool(result.wildcard_testonly).equals(False)
    env.expect.that_collection(result.testonly_groups).has_size(0)
    env.expect.that_collection(result.non_testonly_groups).contains_exactly(["default", "group:dev"])

def _test_parse_no_testonly(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_parse_no_testonly_impl)

# --- test: transitive with testonly ---

# buildifier: disable=unused-variable
def _test_parse_transitive_testonly_impl(env, target):
    """['default', 'group:dev;testonly', 'transitive;testonly'] -> transitive_testonly is True."""
    result = parse_dependency_group_entries(["default", "group:dev;testonly", "transitive;testonly"])

    env.expect.that_bool(result.include_transitive).equals(True)
    env.expect.that_bool(result.transitive_testonly).equals(True)
    env.expect.that_collection(result.testonly_groups).contains_exactly(["group:dev"])

    # "transitive" should NOT appear in dependency_groups
    env.expect.that_collection(result.dependency_groups).contains_exactly(["default", "group:dev"])

def _test_parse_transitive_testonly(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_parse_transitive_testonly_impl)

# --- test: double wildcard, last wins ---

# buildifier: disable=unused-variable
def _test_parse_double_wildcard_impl(env, target):
    """['*;testonly', 'group:dev;testonly', '*', 'group:test;testonly'] -> second * resets.

    First *;testonly sets wildcard_testonly=True.
    group:dev;testonly is a specific override.
    Second * (not testonly) resets wildcard_testonly=False and clears group:dev override.
    group:test;testonly is a new specific override after the second *.
    """
    result = parse_dependency_group_entries(["*;testonly", "group:dev;testonly", "*", "group:test;testonly"])

    env.expect.that_bool(result.wildcard_testonly).equals(False)

    # group:dev;testonly was before the second *, so it's reset
    env.expect.that_collection(result.testonly_groups).contains_exactly(["group:test"])
    env.expect.that_collection(result.non_testonly_groups).has_size(0)

def _test_parse_double_wildcard(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_parse_double_wildcard_impl)

# --- test: TOML cache deduplicates file reads across discovery and translation ---

def _make_fake_rctx(files):
    """Build a fake rctx/mctx that counts reads and records written files."""
    read_counts = {}
    written_files = {}

    def _path(label):
        key = str(label)
        return struct(
            key = key,
            exists = key in files,
        )

    def _read(path_or_label):
        key = path_or_label.key if hasattr(path_or_label, "key") else str(path_or_label)
        read_counts[key] = read_counts.get(key, 0) + 1
        return files[key]

    def _file(out_path, content):
        written_files[str(out_path)] = content

    return struct(
        path = _path,
        read = _read,
        file = _file,
        read_counts = read_counts,
        written_files = written_files,
    )

# buildifier: disable=unused-variable
def _test_toml_cache_and_inline_translation_impl(env, target):
    """Verify TOML files are parsed at most once across discovery + multi-member translation, and output=None writes no file."""
    lock_label = Label("//:uv.lock")
    proj_a_label = Label("//packages/lib_a:pyproject.toml")
    proj_b_label = Label("//packages/lib_b:pyproject.toml")

    uv_lock_toml = """\
version = 1
requires-python = ">=3.11"

[[package]]
name = "lib-a"
version = "0.1.0"
source = { editable = "packages/lib_a" }
dependencies = [{ name = "requests" }]

[[package]]
name = "lib-b"
version = "0.1.0"
source = { editable = "packages/lib_b" }
dependencies = [{ name = "requests" }]

[[package]]
name = "requests"
version = "2.31.0"
source = { registry = "https://pypi.org/simple" }
wheels = [
    { file = "requests-2.31.0-py3-none-any.whl", hash = "sha256:58cd2187c01e70e6e26505bca751777aa9f2ee0b7f4300988b709f44e013003f" },
]
"""
    proj_a_toml = """\
[project]
name = "lib-a"
version = "0.1.0"
dependencies = ["requests>=2.0"]
"""
    proj_b_toml = """\
[project]
name = "lib-b"
version = "0.1.0"
dependencies = ["requests>=2.0"]
"""

    rctx = _make_fake_rctx({
        str(lock_label): uv_lock_toml,
        str(proj_a_label): proj_a_toml,
        str(proj_b_label): proj_b_toml,
    })

    toml_cache = {}
    extra_project_files = [proj_a_label, proj_b_label]

    # 1. Discover members (parses uv.lock once into toml_cache)
    members = discover_uv_all_members(rctx, lock_label, toml_cache = toml_cache)
    env.expect.that_collection([m.name for m in members]).contains_exactly(["lib-a", "lib-b"])

    # 2. Translate lib-a, lib-b, and __build inline
    for projects in [["lib-a"], ["lib-b"], ["*"]]:
        lock_model = struct(
            projects = projects,
            dependency_groups = ["default"],
            testonly_groups = [],
            non_testonly_groups = ["default"],
            wildcard_testonly = False,
        )
        raw_data = repo_create_uv_model(
            rctx,
            extra_project_files,
            lock_label,
            lock_model,
            toml_cache = toml_cache,
        )
        env.expect.that_collection(raw_data["pins"].keys()).contains_exactly(["requests"])

    # Each TOML file was read from disk at most once across all 4 operations!
    env.expect.that_int(rctx.read_counts[str(lock_label)]).equals(1)
    env.expect.that_int(rctx.read_counts[str(proj_a_label)]).equals(1)
    env.expect.that_int(rctx.read_counts[str(proj_b_label)]).equals(1)

    # No intermediate raw_lock_*.json files were written.
    env.expect.that_collection(rctx.written_files.keys()).has_size(0)

    # Missing file returns None and is also cached.
    missing_label = Label("//:nonexistent.toml")
    env.expect.that_str(str(read_toml_cached(rctx, missing_label, toml_cache = toml_cache))).equals("None")
    env.expect.that_bool(str(missing_label) in toml_cache).equals(True)

    # Verify select_project_file hits cache without re-reading.
    selected = select_project_file(rctx, extra_project_files, lock_label, ["lib-b"], toml_cache = toml_cache)
    env.expect.that_str(str(selected)).equals(str(proj_b_label))
    env.expect.that_int(rctx.read_counts[str(proj_b_label)]).equals(1)

def _test_toml_cache_and_inline_translation(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_toml_cache_and_inline_translation_impl)

# --- Test suite ---

def parse_dependency_groups_test_suite(name):
    test_suite(
        name = name,
        tests = [
            _test_parse_basic_testonly,
            _test_parse_wildcard_then_specific_testonly,
            _test_parse_specific_testonly_then_wildcard,
            _test_parse_wildcard_testonly_with_override,
            _test_parse_wildcard_testonly_alone,
            _test_parse_no_testonly,
            _test_parse_transitive_testonly,
            _test_parse_double_wildcard,
            _test_toml_cache_and_inline_translation,
        ],
    )
