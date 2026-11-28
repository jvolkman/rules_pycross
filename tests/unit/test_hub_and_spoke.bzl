"""Unit tests for state_repo, spoke_repo, and cross-spoke tristate reset_plan."""

load("@rules_testing//lib:analysis_test.bzl", "analysis_test", "test_suite")
load("@rules_testing//lib:util.bzl", "util")

# buildifier: disable=bzl-visibility
load(
    "//pycross/private:lock_contract.bzl",
    "slot_key_id",
)

# buildifier: disable=bzl-visibility
load(
    "//pycross/private:repo_slots.bzl",
    "assign_fork_slots",
)

# buildifier: disable=bzl-visibility
load(
    "//pycross/private:spoke_repo.bzl",
    "build_spoke_payloads",
    "render_spoke_build",
    "render_spoke_hook_files",
)

# buildifier: disable=bzl-visibility
load(
    "//pycross/private:state_repo.bzl",
    "backend_tool_deps_labels",
    "merge_workspace_locks",
    "normalize_workspace_variants",
    "render_backend_macro_bzl",
    "render_state_build",
    "slim_member_lock",
)

# buildifier: disable=bzl-visibility
load("//pycross/private:util.bzl", "marker_evaluator_name")

# buildifier: disable=bzl-visibility
load("//pycross/private/lock_render:cycle_plan.bzl", "plan_cycle_member_deps")

# buildifier: disable=bzl-visibility
load(
    "//pycross/private/lock_render:reset_plan.bzl",
    "compute_workspace_reset_states",
    "conflict_pairs",
    "render_state_reset_bzl",
)

# buildifier: disable=bzl-visibility
load("//pycross/private/thin_repo:markers.bzl", "render_member_markers_build")

# buildifier: disable=bzl-visibility
load("//pycross/private/thin_repo:modules_mapping_deps.bzl", "modules_mapping_deps")

def _wheel(filename, key):
    return {"filename": filename, "file_reference": {"key": key}}

# buildifier: disable=unused-variable
def _test_state_repo_rendering_impl(env, target):
    """state_repo renders variant state, cross-spoke reset.bzl, and version-free _backend macros."""
    variant_items = {
        "extra_app_cpu": True,
        "extra_app_gpu": True,
        "extra_app_tpu": True,
    }
    variant_sets = [
        {
            "qnames": ["extra_app_cpu", "extra_app_gpu"],
            "flags": {
                "@app//_variants:extra_cpu": ["extra_app_cpu"],
                "@app//_variants:extra_gpu": ["extra_app_gpu"],
            },
            "member_flags": {"app": {"extra_cpu": ["extra_app_cpu"], "extra_gpu": ["extra_app_gpu"]}},
        },
        {
            "qnames": ["extra_app_cpu", "extra_app_tpu"],
            "flags": {
                "@app//_variants:extra_cpu": ["extra_app_cpu"],
                "@app//_variants:extra_tpu": ["extra_app_tpu"],
            },
            "member_flags": {"app": {"extra_cpu": ["extra_app_cpu"], "extra_tpu": ["extra_app_tpu"]}},
        },
    ]
    norm = normalize_workspace_variants(variant_sets)
    build = render_state_build(variant_items, norm, {"app": {"extra_cpu": True}})
    env.expect.that_str(build).contains('exports_files(["reset.bzl"])')
    env.expect.that_str(build).contains('name = "_state",')
    env.expect.that_str(build).contains('name = "_variant_state",')
    env.expect.that_str(build).contains('name = "_item_extra_app_cpu",')
    env.expect.that_str(build).contains('name = "is_extra_app_gpu",')

    reset_bzl = render_state_reset_bzl(
        norm.all_flags.keys(),
        string_flag_labels = ["@app//_variants:_variants"],
    )
    env.expect.that_str(reset_bzl).contains('str(Label("//:_state")): "",')
    env.expect.that_str(reset_bzl).contains('str(Label("@app//_variants:extra_cpu")): False,')
    env.expect.that_str(reset_bzl).contains('str(Label("@app//_variants:_variants")): "",')

    labels = backend_tool_deps_labels(["setuptools", "wheel", "missing"], ["Setuptools", "wheel"], "ws__build")
    env.expect.that_collection(labels).contains_exactly(["@ws__build//setuptools:pkg", "@ws__build//wheel:pkg"]).in_order()
    macro = render_backend_macro_bzl("setuptools_build", "@rules_pycross//rules:setuptools.bzl", labels)
    env.expect.that_str(macro).contains('Label("@ws__build//setuptools:pkg"),')

def _test_state_repo_rendering(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_state_repo_rendering_impl)

# buildifier: disable=unused-variable
def _test_workspace_reset_states_parity_impl(env, target):
    """compute_workspace_reset_states matches compute_reset_plan across wheels, sdists, cycles, and variants."""
    cp = conflict_pairs([["extra_app_cpu", "extra_app_gpu"]])
    packages = {
        "pure@1.0": {
            "wheel_candidates": [_wheel("pure-1.0-py3-none-any.whl", "k_pure")],
        },
        "sdist-capable@1.0": {
            "wheel_candidates": [_wheel("sdist_capable-1.0-cp312-cp312-manylinux_2_17_x86_64.whl", "k_sc")],
            "sdist_file": {"key": "s_sc"},
        },
        "sdist-univ@1.0": {
            "wheel_candidates": [_wheel("sdist_univ-1.0-py3-none-any.whl", "k_su")],
            "sdist_file": {"key": "s_su"},
        },
        "patched@1.0": {
            "wheel_candidates": [_wheel("patched-1.0-py3-none-any.whl", "k_pat")],
            "post_install_patches": ["@@//:p.patch"],
        },
        "variant-edge@1.0": {
            "wheel_candidates": [_wheel("variant_edge-1.0-py3-none-any.whl", "k_ve")],
            "marker_dependencies": [{"key": "pure@1.0", "marker": "extra == '__variant_extra_app_cpu'"}],
        },
        "cond-never@1.0": {
            "wheel_candidates": [_wheel("cond_never-1.0-py3-none-any.whl", "k_cn")],
            "marker_dependencies": [{"key": "patched@1.0", "marker": "sys_platform == 'win32'"}],
        },
        "above-gated@1.0": {
            "wheel_candidates": [_wheel("above_gated-1.0-py3-none-any.whl", "k_ag")],
            "marker_dependencies": [{"key": "sdist-capable@1.0", "marker": "sys_platform == 'linux'"}],
        },
        "cyc-a@1.0": {
            "cycle_group": "cg_gated",
            "wheel_candidates": [_wheel("cyc_a-1.0-py3-none-any.whl", "k_ca")],
            "marker_dependencies": [{"key": "cyc-b@1.0", "marker": None}],
        },
        "cyc-b@1.0": {
            "cycle_group": "cg_gated",
            "wheel_candidates": [_wheel("cyc_b-1.0-cp312-cp312-manylinux_2_17_x86_64.whl", "k_cb")],
            "sdist_file": {"key": "s_cb"},
            "marker_dependencies": [{"key": "cyc-a@1.0", "marker": None}],
        },
        "cyc-caller@1.0": {
            "wheel_candidates": [_wheel("cyc_caller-1.0-py3-none-any.whl", "k_cc")],
            "marker_dependencies": [{"key": "cyc-a@1.0", "marker": None}],
        },
        "mix-a@1.0": {
            "cycle_group": "cg_mix",
            "wheel_candidates": [_wheel("mix_a-1.0-py3-none-any.whl", "k_ma")],
            "marker_dependencies": [
                {"key": "mix-b@1.0", "marker": None},
                {"key": "patched@1.0", "marker": None},
            ],
        },
        "mix-b@1.0": {
            "cycle_group": "cg_mix",
            "wheel_candidates": [_wheel("mix_b-1.0-py3-none-any.whl", "k_mb")],
            "marker_dependencies": [{"key": "mix-a@1.0", "marker": None}],
        },
        "mix-caller@1.0": {
            "wheel_candidates": [_wheel("mix_caller-1.0-py3-none-any.whl", "k_mc")],
            "marker_dependencies": [{"key": "mix-b@1.0", "marker": None}],
        },
    }
    repo_map = {
        k: "@ws__whl_{}//:wheel".format(k)
        for k in ("k_pure", "k_sc", "k_su", "k_pat", "k_ve", "k_cn", "k_ag", "k_ca", "k_cb", "k_cc", "k_ma", "k_mb", "k_mc")
    }
    repo_map["s_sc"] = "@ws__sdist_file_sc//file:sc.tar.gz"
    repo_map["s_su"] = "@ws__sdist_file_su//file:su.tar.gz"
    repo_map["s_cb"] = "@ws__sdist_file_cb//file:cb.tar.gz"

    slots = assign_fork_slots(packages)
    ws_states = compute_workspace_reset_states(packages, repo_map, cp, "ws", slots)

    expected_raw = {
        "pure@1.0": "always",
        "sdist-capable@1.0": "gated",
        "sdist-univ@1.0": "always",
        "patched@1.0": "never",
        "variant-edge@1.0": "never",
        "cond-never@1.0": "gated",
        "above-gated@1.0": "gated",
        "cyc-a@1.0": "always",
        "cyc-b@1.0": "gated",
        "cyc-caller@1.0": "gated",
        "mix-a@1.0": "never",
        "mix-b@1.0": "always",
        "mix-caller@1.0": "never",
    }
    env.expect.that_dict(ws_states.raw_status).contains_exactly(expected_raw)

    # Check caller-facing SCC status & deterministic leader.
    env.expect.that_str(ws_states.raw_status["cyc-a@1.0"]).equals("always")
    env.expect.that_str(ws_states.raw_status["cyc-b@1.0"]).equals("gated")
    env.expect.that_str(ws_states.caller_status["cyc-a@1.0"]).equals("gated")
    env.expect.that_str(ws_states.caller_status["cyc-caller@1.0"]).equals("gated")
    env.expect.that_str(ws_states.scc_info["cg_gated"].leader_spoke).equals("ws__pkg_cyc_a")
    env.expect.that_collection(ws_states.scc_info["cg_gated"].gated_member_gates).contains_exactly([
        ("ws__pkg_cyc_b", "_raw_reset_gate"),
    ])

    # Mixed cycle: mix-b resets independently, but caller sees "never".
    env.expect.that_str(ws_states.raw_status["mix-b@1.0"]).equals("always")
    env.expect.that_str(ws_states.raw_status["mix-a@1.0"]).equals("never")
    env.expect.that_str(ws_states.caller_status["mix-b@1.0"]).equals("never")
    env.expect.that_str(ws_states.caller_status["mix-caller@1.0"]).equals("never")

def _test_workspace_reset_states_parity(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_workspace_reset_states_parity_impl)

# buildifier: disable=unused-variable
def _test_spoke_version_invariance_and_cycles_impl(env, target):
    """Bumping a downstream dependency's version produces a byte-identical upstream spoke BUILD.bazel."""
    cp = conflict_pairs([["extra_app_cpu", "extra_app_gpu"]])

    def _build_pair(dep_ver):
        pkgs = {
            "app@1.0.0": {
                "wheel_candidates": [_wheel("app-1.0.0-py3-none-any.whl", "k_app")],
                "marker_dependencies": [
                    {"key": "leaf@{}".format(dep_ver), "marker": "sys_platform == 'linux'"},
                ],
            },
            "leaf@{}".format(dep_ver): {
                "wheel_candidates": [_wheel("leaf-{}-cp312-cp312-manylinux_2_17_x86_64.whl".format(dep_ver), "k_leaf")],
                "sdist_file": {"key": "s_leaf"},
            },
            "cyc-a@1.0": {
                "cycle_group": "cg1",
                "wheel_candidates": [_wheel("cyc_a-1.0-py3-none-any.whl", "k_ca")],
                "marker_dependencies": [{"key": "cyc-b@{}".format(dep_ver), "marker": None}],
            },
            "cyc-b@{}".format(dep_ver): {
                "cycle_group": "cg1",
                "wheel_candidates": [_wheel("cyc_b-{}-py3-none-any.whl".format(dep_ver), "k_cb")],
                "marker_dependencies": [{"key": "cyc-c@1.0", "marker": "sys_platform == 'darwin'"}],
            },
            "cyc-c@1.0": {
                "cycle_group": "cg1",
                "wheel_candidates": [_wheel("cyc_c-1.0-py3-none-any.whl", "k_cc")],
                "marker_dependencies": [{"key": "cyc-a@1.0", "marker": None}],
            },
        }
        rmap = {
            "k_app": "@ws__whl_app_py3_none_any//:wheel",
            "k_leaf": "@ws__whl_leaf_cp312_cp312_manylinux_2_17_x86_64//:wheel",
            "s_leaf": "@ws__sdist_file_leaf//file:leaf-{}.tar.gz".format(dep_ver),
            "k_ca": "@ws__whl_cyc_a_py3_none_any//:wheel",
            "k_cb": "@ws__whl_cyc_b_py3_none_any//:wheel",
            "k_cc": "@ws__whl_cyc_c_py3_none_any//:wheel",
        }
        sdist_map = {"leaf@{}".format(dep_ver): "@ws__sdist_leaf//:wheel"}
        slots = assign_fork_slots(pkgs)
        reset_states = compute_workspace_reset_states(pkgs, rmap, cp, "ws", slots)
        spokes = build_spoke_payloads(
            "ws",
            "ws__state",
            pkgs,
            rmap,
            sdist_map,
            slots,
            cycle_groups = {"cg1": ["cyc-a@1.0", "cyc-b@{}".format(dep_ver), "cyc-c@1.0"]},
            has_variants = True,
            reset_states = reset_states,
        )
        return spokes

    spokes_v1 = _build_pair("2.0.0")
    spokes_v2 = _build_pair("2.1.0")

    # Upstream app spoke payload and rendered BUILD.bazel are byte-identical when leaf bumps 2.0.0 -> 2.1.0.
    env.expect.that_str(json.encode(spokes_v1["app"].payload)).equals(json.encode(spokes_v2["app"].payload))
    app_build = render_spoke_build(spokes_v1["app"].payload)
    env.expect.that_str(app_build).contains('name = "_raw",\n    actual = ":pkg",')
    env.expect.that_str(app_build).contains('package = "app@1.0.0",')
    env.expect.that_str(app_build).contains('"@ws__pkg_leaf//:pkg"')
    env.expect.that_str(app_build).contains('"@ws__pkg_leaf//:_reset_gate"')
    env.expect.that_str(app_build).contains('load("@ws__state//:reset.bzl", "pycross_resettable_wheel_library")')

    # Cycle member cyc-a is also byte-identical when cyc-b bumps 2.0.0 -> 2.1.0,
    # AND cyc-a emits the local evaluator for 1-hop marker `sys_platform == 'darwin'` from cyc-b -> cyc-c.
    env.expect.that_str(json.encode(spokes_v1["cyc-a"].payload)).equals(json.encode(spokes_v2["cyc-a"].payload))
    ca_build = render_spoke_build(spokes_v1["cyc-a"].payload)
    darwin_eval = marker_evaluator_name("sys_platform == 'darwin'")
    env.expect.that_str(ca_build).contains('name = "{}",'.format(darwin_eval))
    env.expect.that_str(ca_build).contains('":' + darwin_eval + '_match": ["@ws__pkg_cyc_c//:_raw"]')
    env.expect.that_bool("_cycle_needed_" in ca_build).equals(False)

def _test_spoke_version_invariance_and_cycles(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_spoke_version_invariance_and_cycles_impl)

# buildifier: disable=unused-variable
def _test_spoke_hooks_shim_and_aliases_impl(env, target):
    """Per-spoke hooks emit _sdist/BUILD.bazel shim and version-free aliases alongside hook targets."""
    payload = {
        "name": "jiter",
        "spoke_repo": "ws__pkg_jiter",
        "state_repo": "ws__state",
        "entries": [
            {
                "pkg_key": "jiter@0.5.0",
                "name": "jiter",
                "version": "0.5.0",
                "extra": "",
                "slot": "s0",
                "sdist_label": "@ws__sdist_file_jiter_s0//file:jiter-0.5.0.tar.gz",
            },
            {
                "pkg_key": "jiter@0.6.0",
                "name": "jiter",
                "version": "0.6.0",
                "extra": "",
                "slot": "s1",
                "sdist_label": "@ws__sdist_file_jiter_s1//file:jiter-0.6.0.tar.gz",
            },
        ],
    }

    def fake_cargo_hook(packages_info, override_packages):
        lines = ['package(default_visibility = ["//visibility:public"])', ""]
        for _pkg_name, info in packages_info.items():
            for v in info["versions"]:
                if v.version == "0.5.0" and "jiter@0.5.0" in override_packages:
                    lines.append('genrule(name = "{}", srcs = ["//_sdist:{}"])'.format(v.package_key, v.package_key))
        return [struct(dir = "_cargo", files = {"BUILD.bazel": "\n".join(lines)})]

    files = render_spoke_hook_files(
        payload,
        {"maturin_build": fake_cargo_hook},
        {"jiter@0.5.0": {"maturin_build": {"cargo_lock": '"//:Cargo.lock"'}}},
    )
    env.expect.that_bool("_sdist/BUILD.bazel" in files).equals(True)
    env.expect.that_str(files["_sdist/BUILD.bazel"]).contains('name = "jiter@0.5.0",\n    actual = "//:sdist_s0",')
    env.expect.that_str(files["_sdist/BUILD.bazel"]).contains('name = "jiter@0.6.0",\n    actual = "//:sdist_s1",')
    env.expect.that_str(files["_cargo/BUILD.bazel"]).contains('name = "pkg_s0",\n    actual = ":jiter@0.5.0",')
    env.expect.that_bool('name = "pkg_s1"' in files["_cargo/BUILD.bazel"]).equals(False)

def _test_spoke_hooks_shim_and_aliases(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_spoke_hooks_shim_and_aliases_impl)

# buildifier: disable=unused-variable
def _test_member_markers_and_version_free_slim_impl(env, target):
    """Member _markers/BUILD.bazel and version-free slim_member_lock stay invariant across version bumps."""

    def _make_member(ver, extra_transitive = False):
        pkgs = {
            "app@1.0.0": {
                "wheel_candidates": [_wheel("app-1.0.0-py3-none-any.whl", "k_app")],
            },
            "leaf@{}".format(ver): {
                "wheel_candidates": [_wheel("leaf-{}-py3-none-any.whl".format(ver), "k_leaf")],
                "sdist_file": {"key": "s_leaf"},
                "availability_markers": ["sys_platform == 'linux'"],
            },
            "trans@{}".format(ver): {
                "wheel_candidates": [_wheel("trans-{}-py3-none-any.whl".format(ver), "k_trans")],
            },
        }
        if extra_transitive:
            pkgs["new-trans@9.9.9"] = {"wheel_candidates": [_wheel("new_trans-9.9.9-py3-none-any.whl", "k_nt")]}
        return {
            "packages": pkgs,
            "pins": {"app": "app@1.0.0", "leaf": "leaf@{}".format(ver)},
            "resolution_marker_exprs": {
                "res_deadbeef": "sys_platform == 'linux'",
                "extra_app_gpu_res_deadbeef": {"variant": "extra_app_gpu", "marker": "res_deadbeef"},
            },
        }

    m_v1 = _make_member("2.0.0", extra_transitive = False)
    m_v2 = _make_member("2.1.0", extra_transitive = True)
    ws_overrides = {"leaf": {"maturin_build": {"cargo_lock": '"//:Cargo.lock"'}}}
    hook_subdirs = {"maturin_build": "_cargo"}

    slim_v1 = slim_member_lock(m_v1, m_v1["packages"], ws_overrides = ws_overrides, spoke_hook_subdirs = hook_subdirs)
    slim_v2 = slim_member_lock(m_v2, m_v2["packages"], ws_overrides = ws_overrides, spoke_hook_subdirs = hook_subdirs)
    env.expect.that_str(json.encode(slim_v1)).equals(json.encode(slim_v2))
    env.expect.that_str(slim_v1["pins"]["leaf"]).equals("leaf")
    env.expect.that_bool("trans" in slim_v1["packages"]).equals(False)
    env.expect.that_collection(slim_v1["packages"]["leaf"]["hook_subdirs"]).contains_exactly(["_cargo"])

    markers_bzl = render_member_markers_build(
        slim_v1["packages"],
        {
            "res_deadbeef": "sys_platform == 'linux'",
            "extra_app_gpu_res_deadbeef": {"variant": "extra_app_gpu", "marker": "res_deadbeef"},
        },
        "ws__state",
        has_variants = True,
    )
    env.expect.that_str(markers_bzl).contains('name = "_res_eval_res_deadbeef",')
    env.expect.that_str(markers_bzl).contains('name = "is_res_deadbeef",')
    env.expect.that_str(markers_bzl).contains('"@ws__state//:is_extra_app_gpu",')
    env.expect.that_str(markers_bzl).contains('":is_res_deadbeef",')
    env.expect.that_str(markers_bzl).contains('name = "{}_match",'.format(marker_evaluator_name("sys_platform == 'linux'")))

def _test_member_markers_and_version_free_slim(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_member_markers_and_version_free_slim_impl)

# buildifier: disable=unused-variable
def _test_review_edge_cases_impl(env, target):
    """Covers delimiter collisions, None marker merges, digit-boundary fork bumps, hook syntax, and gated cycle extras."""

    # 1. merge_workspace_locks handles mixed marker=None and string marker without crashing.
    merged = merge_workspace_locks([
        ("m1", {"packages": {"a@1.0": {"marker_dependencies": [{"key": "b@1.0", "marker": None}]}}}),
        ("m2", {"packages": {"a@1.0": {"marker_dependencies": [
            {"key": "b@1.0", "marker": ""},
            {"key": "b@1.0", "marker": "sys_platform == 'linux'"},
        ]}}}),
    ])
    env.expect.that_int(len(merged["packages"]["a@1.0"]["marker_dependencies"])).equals(2)

    # 2. Upstream spoke deps and cycle _CYCLE_EDGES_JSON stay byte-identical when a fork bumps 9.0 -> 10.0.
    def _fork_digit_spokes(hi_ver):
        pkgs = {
            "app@1.0": {
                "wheel_candidates": [_wheel("app-1.0-py3-none-any.whl", "k_app")],
                "marker_dependencies": [
                    {"key": "dep@2.0", "marker": "python_version < '3.12'"},
                    {"key": "dep@{}".format(hi_ver), "marker": "python_version >= '3.12'"},
                ],
            },
            "dep@2.0": {
                "cycle_group": "cg",
                "wheel_candidates": [_wheel("dep-2.0-py3-none-any.whl", "k_d0")],
                "marker_dependencies": [{"key": "peer@1.0"}],
            },
            "dep@{}".format(hi_ver): {
                "cycle_group": "cg",
                "wheel_candidates": [_wheel("dep-{}-py3-none-any.whl".format(hi_ver), "k_d1")],
                "marker_dependencies": [{"key": "peer@1.0"}],
            },
            "peer@1.0": {
                "cycle_group": "cg",
                "wheel_candidates": [_wheel("peer-1.0-py3-none-any.whl", "k_p")],
                "marker_dependencies": [
                    {"key": "dep@2.0", "marker": "python_version < '3.12'"},
                    {"key": "dep@{}".format(hi_ver), "marker": "python_version >= '3.12'"},
                ],
            },
        }
        rmap = {
            "k_app": "@ws__whl_app__t_py3_none_any//:wheel",
            "k_d0": "@ws__whl_dep__s0__t_py3_none_any//:wheel",
            "k_d1": "@ws__whl_dep__s1__t_py3_none_any//:wheel",
            "k_p": "@ws__whl_peer__t_py3_none_any//:wheel",
        }
        slots = assign_fork_slots(pkgs)
        return build_spoke_payloads(
            "ws",
            "ws__state",
            pkgs,
            rmap,
            {},
            slots,
            cycle_groups = {"cg": ["dep@2.0", "dep@{}".format(hi_ver), "peer@1.0"]},
        )

    sp_9 = _fork_digit_spokes("9.0")
    sp_10 = _fork_digit_spokes("10.0")
    env.expect.that_str(json.encode(sp_9["app"].payload)).equals(json.encode(sp_10["app"].payload))
    env.expect.that_str(json.encode(sp_9["peer"].payload)).equals(json.encode(sp_10["peer"].payload))

    # 3. slot_key_id and modules_mapping_deps keep foo@s0 and foo-s0 distinct in //__maybe:.
    env.expect.that_bool(slot_key_id("foo@s0") != slot_key_id("foo-s0")).equals(True)
    mm = modules_mapping_deps(
        {"foo": {"": "foo@s0"}, "foo_s0": {"": "foo-s0"}},
        {
            "foo@s0": {"wheel_platform_specific": True},
            "foo-s0": {"wheel_platform_specific": True},
        },
        "ws",
    )
    env.expect.that_int(len(mm.maybe_mapping_targets)).equals(2)
    env.expect.that_bool("foo__s0" in mm.maybe_mapping_targets).equals(True)
    env.expect.that_bool("foo_s0" in mm.maybe_mapping_targets).equals(True)

    # 4. cycle_plan pair_name keeps b@s0 vs b-s0 distinct.
    plan = plan_cycle_member_deps(
        "root",
        {
            "root": [{"dep": "mid", "marker": "sys_platform == 'linux'"}],
            "mid": [
                {"dep": "b@s0", "marker": "python_version < '3.12'"},
                {"dep": "b-s0", "marker": "python_version >= '3.12'"},
            ],
            "b@s0": [{"dep": "root"}],
            "b-s0": [{"dep": "root"}],
        },
    )
    pair_names = [cg.pair_name for cg in plan.conditional_groups]
    env.expect.that_int(len({p: True for p in pair_names})).equals(len(pair_names))

    # 5. render_spoke_hook_files handles compact name="..." and legacy name@version targets.
    compact_payload = {
        "name": "my-pkg",
        "spoke_repo": "ws__pkg_my_pkg",
        "state_repo": "ws__state",
        "entries": [{
            "pkg_key": "my-pkg@1.0~abcd1234",
            "name": "my-pkg",
            "version": "1.0",
            "extra": "",
            "slot": "s0",
            "sdist_label": "@ws__sdistfile_my_pkg__s0//file:my_pkg-1.0.tar.gz",
        }],
    }

    def compact_hook(_packages_info, _overrides):
        return [struct(dir = "_cargo", files = {"BUILD.bazel": 'genrule(name="my-pkg@1.0")\n'})]

    compact_files = render_spoke_hook_files(
        compact_payload,
        {"maturin_build": compact_hook},
        {"my-pkg": {"maturin_build": {"cargo_lock": '"//:Cargo.lock"'}}},
    )
    env.expect.that_str(compact_files["_cargo/BUILD.bazel"]).contains('name = "pkg_s0",\n    actual = ":my-pkg@1.0",')

    # 6. Extras proxy inside a gated cycle emits valid reset gate targets.
    cp = conflict_pairs([["v_a", "v_b"]])
    gc_pkgs = {
        "ca@1.0": {
            "cycle_group": "gcyc",
            "wheel_candidates": [_wheel("ca-1.0-cp312-cp312-manylinux_2_17_x86_64.whl", "k_ca")],
            "sdist_file": {"key": "s_ca"},
            "marker_dependencies": [{"key": "ca[ext]@1.0"}],
        },
        "ca[ext]@1.0": {
            "cycle_group": "gcyc",
            "marker_dependencies": [{"key": "cb@1.0"}],
        },
        "cb@1.0": {
            "cycle_group": "gcyc",
            "wheel_candidates": [_wheel("cb-1.0-py3-none-any.whl", "k_cb")],
            "marker_dependencies": [{"key": "ca@1.0"}],
        },
    }
    gc_rmap = {
        "k_ca": "@ws__whl_ca__t_cp312_cp312_manylinux_2_17_x86_64//:wheel",
        "s_ca": "@ws__sdistfile_ca//file:ca-1.0.tar.gz",
        "k_cb": "@ws__whl_cb__t_py3_none_any//:wheel",
    }
    gc_slots = assign_fork_slots(gc_pkgs)
    gc_reset = compute_workspace_reset_states(gc_pkgs, gc_rmap, cp, "ws", gc_slots)
    gc_spokes = build_spoke_payloads(
        "ws",
        "ws__state",
        gc_pkgs,
        gc_rmap,
        {"ca@1.0": "@ws__sdist_ca//:wheel"},
        gc_slots,
        cycle_groups = {"gcyc": ["ca@1.0", "ca[ext]@1.0", "cb@1.0"]},
        has_variants = True,
        reset_states = gc_reset,
    )
    ca_gc_build = render_spoke_build(gc_spokes["ca"].payload)
    env.expect.that_str(ca_gc_build).contains('name = "_raw_reset_gate",')
    env.expect.that_str(ca_gc_build).contains('name = "_scc_reset_gate",')
    env.expect.that_str(ca_gc_build).contains('name = "_reset_gate_[ext]",')

def _test_review_edge_cases(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_review_edge_cases_impl)

def hub_and_spoke_test_suite(name):
    test_suite(
        name = name,
        tests = [
            _test_state_repo_rendering,
            _test_workspace_reset_states_parity,
            _test_spoke_version_invariance_and_cycles,
            _test_spoke_hooks_shim_and_aliases,
            _test_member_markers_and_version_free_slim,
            _test_review_edge_cases,
        ],
    )
