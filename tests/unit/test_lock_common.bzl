"""Tests for lock_common.bzl helpers."""

load("@rules_testing//lib:analysis_test.bzl", "analysis_test", "test_suite")
load("@rules_testing//lib:util.bzl", "util")

# buildifier: disable=bzl-visibility
load("//pycross/private:lock_common.bzl", "process_workspaces", "read_toml_cached", "register_workspace_repo", "resolve_member_project_file", "sibling_project_file")

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
def _test_register_workspace_repo_dev_dependency_impl(env, target):
    """Verify dev_dependency = True tags route to root_direct_dev_deps while non-dev route to root_direct_deps."""
    lock_owners = {}
    lock_repos = {}
    lock_model_structs = {}
    root_direct_deps = []
    root_direct_dev_deps = []
    ws_tag = struct(lock_file = Label("//:uv.lock"), local_wheels = [])
    root_mod = struct(name = "root", is_root = True)
    dep_mod = struct(name = "dep", is_root = False)
    transition = dict(flags = [], settings = {}, constraint_values = [], platform = None)

    register_workspace_repo(
        lock_owners,
        lock_repos,
        lock_model_structs,
        root_direct_deps,
        ws_tag,
        "ws",
        "prod_repo",
        ["app"],
        ["default"],
        transition,
        root_mod,
        [],
        root_direct_dev_deps = root_direct_dev_deps,
        is_dev_dependency = False,
    )
    register_workspace_repo(
        lock_owners,
        lock_repos,
        lock_model_structs,
        root_direct_deps,
        ws_tag,
        "ws",
        "dev_repo",
        ["app"],
        ["default"],
        transition,
        root_mod,
        [],
        root_direct_dev_deps = root_direct_dev_deps,
        is_dev_dependency = True,
    )
    register_workspace_repo(
        lock_owners,
        lock_repos,
        lock_model_structs,
        root_direct_deps,
        ws_tag,
        "ws",
        "dep_repo",
        ["app"],
        ["default"],
        transition,
        dep_mod,
        [],
        root_direct_dev_deps = root_direct_dev_deps,
        is_dev_dependency = True,
    )

    env.expect.that_collection(root_direct_deps).contains_exactly(["prod_repo"])
    env.expect.that_collection(root_direct_dev_deps).contains_exactly(["dev_repo"])

    # process_workspaces propagates is_dev_dependency from a single-project workspace to its implicit repo.
    ws_direct = []
    ws_dev = []
    fake_mctx = struct(path = lambda _lbl: struct(exists = True))
    process_workspaces(
        fake_mctx,
        {},
        {},
        {},
        [struct(tag = ws_tag, module = root_mod, ws_name = "dev_ws", is_dev_dependency = True)],
        [],
        lambda _mctx, _lock, _cache: [struct(name = "app", path = "")],
        ws_direct,
        root_direct_dev_deps = ws_dev,
    )
    env.expect.that_collection(ws_direct).contains_exactly([])
    env.expect.that_collection(ws_dev).contains_exactly(["dev_ws"])

def _test_register_workspace_repo_dev_dependency(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_register_workspace_repo_dev_dependency_impl)

def lock_common_test_suite(name):
    test_suite(
        name = name,
        tests = [
            _test_member_project_files,
            _test_read_toml_cached,
            _test_register_workspace_repo_dev_dependency,
        ],
    )
