"""Tests for lock_common.bzl helpers."""

load("@rules_testing//lib:analysis_test.bzl", "analysis_test", "test_suite")
load("@rules_testing//lib:truth.bzl", "matching")
load("@rules_testing//lib:util.bzl", "util")

# buildifier: disable=bzl-visibility
load("//pycross/private:lock_common.bzl", "process_workspaces", "read_toml_cached", "resolve_member_project_file", "sibling_project_file")

# buildifier: disable=unused-variable
def _test_member_project_files_impl(env, target):
    cases = [
        # Lock at a package root: members resolve within the same package, so member
        # directories don't need BUILD files.
        ("//:uv.lock", "apps/app-a", "//:apps/app-a/pyproject.toml"),
        ("//:uv.lock", "./apps/app-a", "//:apps/app-a/pyproject.toml"),
        ("//:uv.lock", ".", "//:pyproject.toml"),
        ("//:uv.lock", "", "//:pyproject.toml"),
        ("//py:uv.lock", "libs/common", "//py:libs/common/pyproject.toml"),
        # Lock in a subdirectory of its package: paths are relative to the lock's directory.
        ("//:project/uv.lock", "apps/app-a", "//:project/apps/app-a/pyproject.toml"),
        ("//:project/uv.lock", "", "//:project/pyproject.toml"),
        ("//:project/uv.lock", "apps/../libs/common", "//:project/libs/common/pyproject.toml"),
        # Members outside the lock's package resolve from the repository root.
        ("//py:uv.lock", "../other", "//:other/pyproject.toml"),
    ]
    for lock, member, expected in cases:
        actual = resolve_member_project_file(Label(lock), member)
        env.expect.where(lock = lock, member = member).that_str(str(actual)).equals(str(Label(expected)))

    env.expect.that_str(str(sibling_project_file(Label("//:project/uv.lock")))).equals(str(Label("//:project/pyproject.toml")))
    env.expect.that_str(str(sibling_project_file(Label("//py:uv.lock")))).equals(str(Label("//py:pyproject.toml")))

def _test_member_project_files(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_member_project_files_impl)

# buildifier: disable=unused-variable
def _test_read_toml_cached_impl(env, target):
    reads = []
    paths = []

    def fake_path(label):
        paths.append(str(label))
        return struct(exists = (label.name != "missing.toml"), label = label)

    def fake_read(path):
        reads.append(str(path.label))
        return '[project]\nname = "demo"\n'

    ctx = struct(path = fake_path, read = fake_read)
    cache = {}
    lbl = Label("//:pyproject.toml")
    first = read_toml_cached(ctx, lbl, cache)
    second = read_toml_cached(ctx, lbl, cache)
    env.expect.that_str(first["project"]["name"]).equals("demo")
    env.expect.that_str(second["project"]["name"]).equals("demo")
    env.expect.that_int(len(reads)).equals(1)
    env.expect.that_int(len(paths)).equals(1)

    missing = Label("//:missing.toml")
    env.expect.that_bool(read_toml_cached(ctx, missing, cache) == None).equals(True)
    env.expect.that_bool(read_toml_cached(ctx, missing, cache) == None).equals(True)
    env.expect.that_int(len(reads)).equals(1)
    env.expect.that_int(len(paths)).equals(2)

def _test_read_toml_cached(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_read_toml_cached_impl)

# buildifier: disable=unused-variable
def _test_process_workspaces_impl(env, target):
    """Verify structured workspace descriptors, dev_dependency routing, build repo flags, and native Label preservation."""
    root_mod = struct(name = "root", is_root = True)
    dep_mod = struct(name = "dep", is_root = False)
    fake_mctx = struct(path = lambda _lbl: struct(exists = True))

    ws_tag = struct(
        name = "ws",
        lock_file = Label("//:uv.lock"),
        local_wheels = [],
        pypi_indexes = ["https://example.com/simple"],
        extra_project_files = [],
    )
    res = process_workspaces(
        fake_mctx,
        [struct(tag = ws_tag, module = root_mod, is_dev_dependency = False)],
        [
            struct(tag = struct(workspace = "ws", name = "prod_repo", projects = ["app"], dependency_groups = ["default"]), module = root_mod, is_dev_dependency = False),
            struct(tag = struct(workspace = "ws", name = "dev_repo", projects = ["app"], dependency_groups = ["default"]), module = root_mod, is_dev_dependency = True),
            struct(tag = struct(workspace = "ws", name = "dep_repo", projects = ["app"], dependency_groups = ["default"]), module = dep_mod, is_dev_dependency = True),
        ],
        lambda _mctx, _lock, _cache: [struct(name = "app", path = "apps/app")],
    )

    env.expect.that_collection(res.root_direct_deps).contains_exactly(["prod_repo"])
    env.expect.that_collection(res.root_direct_dev_deps).contains_exactly(["dev_repo"])

    ws = res.workspaces["ws"]
    env.expect.that_collection(ws.pypi_indexes).contains_exactly(["https://example.com/simple"])
    repos_by_name = {r.name: r for r in ws.repos}
    env.expect.that_collection(repos_by_name.keys()).contains_exactly(["prod_repo", "dev_repo", "dep_repo", "ws__build"])

    # Auto-generated <ws>__build sets both is_auto_build_repo and is_build_tools_repo.
    auto_build = repos_by_name["ws__build"]
    env.expect.that_bool(auto_build.is_auto_build_repo).equals(True)
    env.expect.that_bool(auto_build.is_build_tools_repo).equals(True)
    env.expect.that_bool(auto_build.lock_model.is_build_tools_repo).equals(True)

    # Native Labels are preserved on lock_model, with sibling pyproject.toml first.
    prod_model = repos_by_name["prod_repo"].lock_model
    env.expect.that_str(type(prod_model.lock_file)).equals("Label")
    env.expect.that_str(type(prod_model.extra_project_files[0])).equals("Label")
    env.expect.that_collection([str(f) for f in prod_model.extra_project_files]).contains_exactly([
        str(Label("//:pyproject.toml")),
        str(Label("//:apps/app/pyproject.toml")),
    ]).in_order()

    # User-declared <ws>__build shadows auto-generated <ws>__build:
    # is_build_tools_repo is True, is_auto_build_repo is False, and it stays a root direct dep.
    ws_custom = struct(name = "custom", lock_file = Label("//:uv.lock"), local_wheels = [])
    custom_res = process_workspaces(
        fake_mctx,
        [struct(tag = ws_custom, module = root_mod, is_dev_dependency = False)],
        [struct(tag = struct(workspace = "custom", name = "custom__build", projects = ["app"], dependency_groups = ["*"]), module = root_mod, is_dev_dependency = False)],
        lambda _mctx, _lock, _cache: [struct(name = "app", path = "")],
    )
    env.expect.that_collection(custom_res.root_direct_deps).contains_exactly(["custom__build"])
    env.expect.that_int(len(custom_res.workspaces["custom"].repos)).equals(1)
    custom_build = custom_res.workspaces["custom"].repos[0]
    env.expect.that_bool(custom_build.is_build_tools_repo).equals(True)
    env.expect.that_bool(custom_build.lock_model.is_build_tools_repo).equals(True)
    env.expect.that_bool(custom_build.is_auto_build_repo).equals(False)

    # process_workspaces propagates is_dev_dependency from a single-project workspace to its implicit repo.
    dev_ws_tag = struct(name = "dev_ws", lock_file = Label("//:uv.lock"), local_wheels = [])
    dev_res = process_workspaces(
        fake_mctx,
        [struct(tag = dev_ws_tag, module = root_mod, is_dev_dependency = True)],
        [],
        lambda _mctx, _lock, _cache: [struct(name = "app", path = "")],
    )
    env.expect.that_collection(dev_res.root_direct_deps).contains_exactly([])
    env.expect.that_collection(dev_res.root_direct_dev_deps).contains_exactly(["dev_ws"])

def _test_process_workspaces(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_process_workspaces_impl)

def _duplicate_repo_subject_impl(_ctx):
    mod_a = struct(name = "mod_a", is_root = True)
    mod_b = struct(name = "mod_b", is_root = False)
    fake_mctx = struct(path = lambda _lbl: struct(exists = True))
    ws_tag = struct(name = "ws", lock_file = Label("//:uv.lock"), local_wheels = [])
    process_workspaces(
        fake_mctx,
        [struct(tag = ws_tag, module = mod_a, is_dev_dependency = False)],
        [
            struct(tag = struct(workspace = "ws", name = "ws__build", projects = ["app"], dependency_groups = ["*"]), module = mod_a),
            struct(tag = struct(workspace = "ws", name = "ws__build", projects = ["app"], dependency_groups = ["*"]), module = mod_b),
        ],
        lambda _mctx, _lock, _cache: [struct(name = "app", path = "")],
    )
    return []

_duplicate_repo_subject = rule(implementation = _duplicate_repo_subject_impl)

def _test_duplicate_repo_fails_impl(env, target):
    env.expect.that_target(target).failures().contains_predicate(
        matching.contains("lock repo 'ws__build' wanted by module 'mod_b' already created by module 'mod_a'"),
    )

def _test_duplicate_repo_fails(name):
    util.helper_target(_duplicate_repo_subject, name = name + "_subject")
    analysis_test(
        name = name,
        target = name + "_subject",
        expect_failure = True,
        impl = _test_duplicate_repo_fails_impl,
    )

def lock_common_test_suite(name):
    test_suite(
        name = name,
        tests = [
            _test_member_project_files,
            _test_read_toml_cached,
            _test_process_workspaces,
            _test_duplicate_repo_fails,
        ],
    )
