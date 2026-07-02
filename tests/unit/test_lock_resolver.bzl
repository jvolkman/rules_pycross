"""Tests for lock_resolver"""

load("@rules_testing//lib:analysis_test.bzl", "analysis_test", "test_suite")
load("@rules_testing//lib:truth.bzl", "matching")
load("@rules_testing//lib:util.bzl", "util")

# buildifier: disable=bzl-visibility
load("//pycross/private:lock_resolver.bzl", "resolve")

def _make_file(name, sha256 = "1234"):
    return {"name": name, "sha256": sha256}

def _make_dep(name, version, marker = ""):
    return {"name": name, "version": version, "marker": marker}

def _make_pkg(name, version, files, deps = None, python_versions = ">=3.8"):
    return {
        "name": name,
        "version": version,
        "python_versions": python_versions,
        "dependencies": deps or [],
        "files": files,
    }

def _resolve_failure_subject_impl(ctx):
    lock_model_data = json.decode(ctx.attr.lock_model_data)
    annotations_data = json.decode(ctx.attr.annotations_data) if ctx.attr.annotations_data else None

    resolve(
        lock_model_data = lock_model_data,
        annotations_data = annotations_data,
    )
    return []

_resolve_failure_subject = rule(
    implementation = _resolve_failure_subject_impl,
    attrs = {
        "lock_model_data": attr.string(),
        "annotations_data": attr.string(default = ""),
    },
)

# buildifier: disable=unused-variable
def _test_basic_resolution_impl(env, target):
    lock_model_data = {
        "packages": {
            "foo@1.0": {
                "name": "foo",
                "version": "1.0",
                "dependencies": [],
                "files": [
                    {
                        "name": "foo-1.0.tar.gz",
                        "sha256": "12345",
                        "package_name": "foo",
                        "package_version": "1.0",
                    },
                ],
            },
        },
        "pins": {
            "foo": "foo@1.0",
        },
    }

    res = resolve(lock_model_data)

    env.expect.that_collection(res.pins.keys()).contains_exactly(["foo"])
    env.expect.that_collection(res.packages.keys()).contains_exactly(["foo@1.0"])

    # Verify file metadata is preserved in remote_files
    file_key = "foo-1.0.tar.gz/12345"
    env.expect.that_collection(res.remote_files.keys()).contains_exactly([file_key])
    f = res.remote_files[file_key]
    env.expect.that_str(f["package_name"]).equals("foo")
    env.expect.that_str(f["package_version"]).equals("1.0")

def _test_basic_resolution(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_basic_resolution_impl)

# buildifier: disable=unused-variable
def _test_default_alias_single_version_with_extras_impl(env, target):
    lock_model_data = {
        "packages": {
            "selenium@1.0": {
                "name": "selenium",
                "version": "1.0",
                "dependencies": [
                    {"name": "urllib3[socks]", "version": "2.2.3"},
                ],
                "files": [{"name": "selenium-1.0.tar.gz", "sha256": "selenium123"}],
            },
            "urllib3@2.2.3": {
                "name": "urllib3",
                "version": "2.2.3",
                "dependencies": [],
                "files": [{"name": "urllib3-2.2.3.tar.gz", "sha256": "123"}],
            },
        },
        "pins": {
            "selenium": "selenium@1.0",
        },
    }

    res = resolve(lock_model_data, default_alias_single_version = True)

    # Should have alias for urllib3 because it is resolved (transitively) and has only one version.
    env.expect.that_collection(res.pins.keys()).contains_exactly(["selenium", "urllib3"])
    env.expect.that_dict(res.pins["urllib3"]).contains_exactly({"": "urllib3@2.2.3"})

def _test_default_alias_single_version_with_extras(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_default_alias_single_version_with_extras_impl)

# buildifier: disable=unused-variable
def _test_build_dependencies_override_impl(env, target):
    lock_model_data = {
        "packages": {
            "foo@1.0": {
                "name": "foo",
                "version": "1.0",
                "dependencies": [],
                "files": [{"name": "foo-1.0.tar.gz", "sha256": "123"}],
            },
            "bar@1.0": {
                "name": "bar",
                "version": "1.0",
                "dependencies": [],
                "files": [{"name": "bar-1.0.tar.gz", "sha256": "456"}],
            },
            "baz@1.0": {
                "name": "baz",
                "version": "1.0",
                "dependencies": [],
                "files": [{"name": "baz-1.0.tar.gz", "sha256": "789"}],
            },
        },
        "pins": {
            "foo": "foo@1.0",
        },
    }

    annotations_data = {
        "foo": {
            "build_dependencies": ["bar@1.0"],
        },
    }

    res = resolve(
        lock_model_data,
        annotations_data = annotations_data,
        default_build_dependencies_args = ["baz@1.0"],  # This should be ignored for foo
    )

    foo_pkg = res.packages["foo@1.0"]
    env.expect.that_collection(foo_pkg["build_dependencies"]).contains_exactly(["bar@1.0"])

def _test_build_dependencies_override(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_build_dependencies_override_impl)

# buildifier: disable=unused-variable
def _test_synthesized_deps_impl(env, target):
    lock_model_data = {
        "packages": {
            "foo@1.0": {
                "name": "foo",
                "version": "1.0",
                "dependencies": [],
                "files": [{"name": "foo-1.0.tar.gz", "sha256": "123"}],
            },
        },
        "pins": {
            "foo[extra]": "foo[extra]@1.0",
        },
    }

    # foo[extra]@1.0 is NOT in packages, so it should be synthesized.
    res = resolve(lock_model_data)

    env.expect.that_collection(res.packages.keys()).contains_exactly(["foo@1.0", "foo[extra]@1.0"])

    extra_pkg = res.packages["foo[extra]@1.0"]

    # It should depend on the base package
    env.expect.that_collection([d["name"] for d in extra_pkg["dependencies"]]).contains("foo")

def _test_synthesized_deps(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_synthesized_deps_impl)

# buildifier: disable=unused-variable
def _test_cycle_two_nodes_impl(env, target):
    lock_model_data = {
        "packages": {
            "a@1.0": {
                "name": "a",
                "version": "1.0",
                "dependencies": [{"name": "b", "version": "1.0"}],
                "files": [{"name": "a-1.0.tar.gz", "sha256": "a123"}],
            },
            "b@1.0": {
                "name": "b",
                "version": "1.0",
                "dependencies": [{"name": "a", "version": "1.0"}],
                "files": [{"name": "b-1.0.tar.gz", "sha256": "b123"}],
            },
        },
        "pins": {
            "a": "a@1.0",
        },
    }

    res = resolve(lock_model_data)

    env.expect.that_collection(res.cycle_groups.keys()).has_size(1)
    group_name = res.cycle_groups.keys()[0]
    env.expect.that_collection(res.cycle_groups[group_name]).contains_exactly(["a@1.0", "b@1.0"])

def _test_cycle_two_nodes(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_cycle_two_nodes_impl)

# buildifier: disable=unused-variable
def _test_cycle_via_extra_impl(env, target):
    lock_model_data = {
        "packages": {
            "foo@1.0": _make_pkg("foo", "1.0", [_make_file("foo-1.0.tar.gz")], deps = [_make_dep("depA[test]", "1.0")]),
            "depA@1.0": _make_pkg("depA", "1.0", [_make_file("depA-1.0.tar.gz")], deps = [_make_dep("depB", "1.0", marker = "extra == 'test'")]),
            "depB@1.0": _make_pkg("depB", "1.0", [_make_file("depB-1.0.tar.gz")], deps = [_make_dep("depA[test]", "1.0")]),
        },
        "pins": {
            "foo": "foo@1.0",
        },
    }

    res = resolve(lock_model_data)

    # We expect a cycle involving depA[test]@1.0, depB@1.0, and depA@1.0
    # Let's see what we get.
    env.expect.that_collection(res.cycle_groups.keys()).has_size(1)
    if len(res.cycle_groups.keys()) > 0:
        group_name = res.cycle_groups.keys()[0]

        # In Python, the cycle members were the keys.
        # Let's see if depA[test]@1.0 is in it.
        env.expect.that_collection(res.cycle_groups[group_name]).contains("depA[test]@1.0")

def _test_cycle_via_extra(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_cycle_via_extra_impl)

# buildifier: disable=unused-variable
def _test_cycle_three_nodes_impl(env, target):
    lock_model_data = {
        "packages": {
            "a@1.0": _make_pkg("a", "1.0", [_make_file("a-1.0.tar.gz")], deps = [_make_dep("b", "1.0")]),
            "b@1.0": _make_pkg("b", "1.0", [_make_file("b-1.0.tar.gz")], deps = [_make_dep("c", "1.0")]),
            "c@1.0": _make_pkg("c", "1.0", [_make_file("c-1.0.tar.gz")], deps = [_make_dep("a", "1.0")]),
        },
        "pins": {
            "a": "a@1.0",
            "b": "b@1.0",
            "c": "c@1.0",
        },
    }

    res = resolve(lock_model_data)

    pkg_a = res.packages["a@1.0"]
    pkg_b = res.packages["b@1.0"]
    pkg_c = res.packages["c@1.0"]

    env.expect.that_bool(pkg_a["cycle_group"] != None).equals(True)
    group = pkg_a["cycle_group"]

    env.expect.that_str(pkg_b["cycle_group"]).equals(group)
    env.expect.that_str(pkg_c["cycle_group"]).equals(group)

    env.expect.that_collection(res.cycle_groups[group]).has_size(3)
    env.expect.that_collection(res.cycle_groups[group]).contains_exactly(["a@1.0", "b@1.0", "c@1.0"])

def _test_cycle_three_nodes(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_cycle_three_nodes_impl)

# buildifier: disable=unused-variable
def _test_no_cycles_impl(env, target):
    lock_model_data = {
        "packages": {
            "a@1.0": _make_pkg("a", "1.0", [_make_file("a-1.0.tar.gz")], deps = [_make_dep("b", "1.0")]),
            "b@1.0": _make_pkg("b", "1.0", [_make_file("b-1.0.tar.gz")], deps = [_make_dep("c", "1.0")]),
            "c@1.0": _make_pkg("c", "1.0", [_make_file("c-1.0.tar.gz")]),
        },
        "pins": {
            "a": "a@1.0",
        },
    }

    res = resolve(lock_model_data)

    for pkg in res.packages.values():
        env.expect.that_bool(pkg.get("cycle_group") == None).equals(True)

    env.expect.that_collection(res.cycle_groups.keys()).has_size(0)

def _test_no_cycles(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_no_cycles_impl)

# buildifier: disable=unused-variable
def _test_cycle_group_naming_stable_impl(env, target):
    lock_model_data = {
        "packages": {
            "a@1.0": _make_pkg("a", "1.0", [_make_file("a-1.0.tar.gz")], deps = [_make_dep("b", "1.0")]),
            "b@1.0": _make_pkg("b", "1.0", [_make_file("b-1.0.tar.gz")], deps = [_make_dep("a", "1.0")]),
        },
        "pins": {
            "a": "a@1.0",
            "b": "b@1.0",
        },
    }

    res1 = resolve(lock_model_data)
    res2 = resolve(lock_model_data)

    group1 = res1.packages["a@1.0"]["cycle_group"]
    group2 = res2.packages["a@1.0"]["cycle_group"]

    env.expect.that_str(group1).equals(group2)
    env.expect.that_str(group1).contains("group_")

def _test_cycle_group_naming_stable(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_cycle_group_naming_stable_impl)

# buildifier: disable=unused-variable
def _test_multiple_disconnected_cycles_impl(env, target):
    lock_model_data = {
        "packages": {
            "a@1.0": _make_pkg("a", "1.0", [_make_file("a-1.0.tar.gz")], deps = [_make_dep("b", "1.0")]),
            "b@1.0": _make_pkg("b", "1.0", [_make_file("b-1.0.tar.gz")], deps = [_make_dep("a", "1.0")]),
            "x@1.0": _make_pkg("x", "1.0", [_make_file("x-1.0.tar.gz")], deps = [_make_dep("y", "1.0")]),
            "y@1.0": _make_pkg("y", "1.0", [_make_file("y-1.0.tar.gz")], deps = [_make_dep("x", "1.0")]),
        },
        "pins": {
            "a": "a@1.0",
            "b": "b@1.0",
            "x": "x@1.0",
            "y": "y@1.0",
        },
    }

    res = resolve(lock_model_data)

    pkg_a = res.packages["a@1.0"]
    pkg_x = res.packages["x@1.0"]

    group_ab = pkg_a["cycle_group"]
    group_xy = pkg_x["cycle_group"]

    env.expect.that_bool(group_ab != None).equals(True)
    env.expect.that_bool(group_xy != None).equals(True)

    env.expect.that_bool(group_ab == group_xy).equals(False)

    env.expect.that_collection(res.cycle_groups.keys()).has_size(2)

def _test_multiple_disconnected_cycles(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_multiple_disconnected_cycles_impl)

# buildifier: disable=unused-variable
def _test_cycle_eight_member_hub_and_spoke_impl(env, target):
    lock_model_data = {
        "packages": {
            "packaging@1.0": _make_pkg("packaging", "1.0", [_make_file("packaging-1.0.tar.gz")]),
            "jinja2@1.0": _make_pkg("jinja2", "1.0", [_make_file("jinja2-1.0.tar.gz")]),
            "attrs@1.0": _make_pkg("attrs", "1.0", [_make_file("attrs-1.0.tar.gz")]),
            "airflow@2.0": _make_pkg(
                "airflow",
                "2.0",
                [_make_file("airflow-2.0.tar.gz")],
                deps = [_make_dep("airflow-core", "2.0"), _make_dep("task-sdk", "2.0")],
            ),
            "airflow-core@2.0": _make_pkg(
                "airflow-core",
                "2.0",
                [_make_file("airflow_core-2.0.tar.gz")],
                deps = [
                    _make_dep("provider-compat", "2.0"),
                    _make_dep("provider-io", "2.0"),
                    _make_dep("provider-sql", "2.0"),
                    _make_dep("provider-smtp", "2.0"),
                    _make_dep("provider-standard", "2.0"),
                    _make_dep("task-sdk", "2.0"),
                    _make_dep("packaging", "1.0"),
                    _make_dep("jinja2", "1.0"),
                ],
            ),
            "task-sdk@2.0": _make_pkg(
                "task-sdk",
                "2.0",
                [_make_file("task_sdk-2.0.tar.gz")],
                deps = [_make_dep("airflow-core", "2.0"), _make_dep("attrs", "1.0")],
            ),
            "provider-compat@2.0": _make_pkg(
                "provider-compat",
                "2.0",
                [_make_file("provider_compat-2.0.tar.gz")],
                deps = [_make_dep("airflow", "2.0")],
            ),
            "provider-io@2.0": _make_pkg(
                "provider-io",
                "2.0",
                [_make_file("provider_io-2.0.tar.gz")],
                deps = [_make_dep("airflow", "2.0")],
            ),
            "provider-sql@2.0": _make_pkg(
                "provider-sql",
                "2.0",
                [_make_file("provider_sql-2.0.tar.gz")],
                deps = [_make_dep("airflow", "2.0")],
            ),
            "provider-smtp@2.0": _make_pkg(
                "provider-smtp",
                "2.0",
                [_make_file("provider_smtp-2.0.tar.gz")],
                deps = [_make_dep("airflow", "2.0"), _make_dep("provider-compat", "2.0")],
            ),
            "provider-standard@2.0": _make_pkg(
                "provider-standard",
                "2.0",
                [_make_file("provider_standard-2.0.tar.gz")],
                deps = [_make_dep("airflow", "2.0")],
            ),
        },
        "pins": {
            "airflow": "airflow@2.0",
        },
    }

    res = resolve(lock_model_data)

    cycle_members = [
        "airflow@2.0",
        "airflow-core@2.0",
        "task-sdk@2.0",
        "provider-compat@2.0",
        "provider-io@2.0",
        "provider-sql@2.0",
        "provider-smtp@2.0",
        "provider-standard@2.0",
    ]

    pkg_airflow = res.packages["airflow@2.0"]
    group = pkg_airflow["cycle_group"]
    env.expect.that_bool(group != None).equals(True)

    for member in cycle_members:
        pkg = res.packages[member]
        env.expect.that_str(pkg["cycle_group"]).equals(group)

    env.expect.that_collection(res.cycle_groups[group]).has_size(8)

    for leaf in ["packaging@1.0", "jinja2@1.0", "attrs@1.0"]:
        pkg = res.packages[leaf]
        env.expect.that_bool(pkg.get("cycle_group") == None).equals(True)

def _test_cycle_eight_member_hub_and_spoke(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_cycle_eight_member_hub_and_spoke_impl)

# buildifier: disable=unused-variable
def _test_cycle_with_non_cycle_tail_impl(env, target):
    lock_model_data = {
        "packages": {
            "a@1.0": _make_pkg("a", "1.0", [_make_file("a-1.0.tar.gz")], deps = [_make_dep("b", "1.0")]),
            "b@1.0": _make_pkg("b", "1.0", [_make_file("b-1.0.tar.gz")], deps = [_make_dep("c", "1.0")]),
            "c@1.0": _make_pkg(
                "c",
                "1.0",
                [_make_file("c-1.0.tar.gz")],
                deps = [_make_dep("a", "1.0"), _make_dep("d", "1.0")],
            ),
            "d@1.0": _make_pkg("d", "1.0", [_make_file("d-1.0.tar.gz")], deps = [_make_dep("e", "1.0")]),
            "e@1.0": _make_pkg("e", "1.0", [_make_file("e-1.0.tar.gz")], deps = [_make_dep("f", "1.0")]),
            "f@1.0": _make_pkg("f", "1.0", [_make_file("f-1.0.tar.gz")], deps = [_make_dep("g", "1.0")]),
            "g@1.0": _make_pkg("g", "1.0", [_make_file("g-1.0.tar.gz")]),
        },
        "pins": {
            "a": "a@1.0",
        },
    }

    res = resolve(lock_model_data)

    pkg_a = res.packages["a@1.0"]
    group = pkg_a["cycle_group"]
    env.expect.that_bool(group != None).equals(True)

    env.expect.that_str(res.packages["b@1.0"]["cycle_group"]).equals(group)
    env.expect.that_str(res.packages["c@1.0"]["cycle_group"]).equals(group)

    env.expect.that_collection(res.cycle_groups[group]).has_size(3)

    for tail in ["d@1.0", "e@1.0", "f@1.0", "g@1.0"]:
        pkg = res.packages[tail]
        env.expect.that_bool(pkg.get("cycle_group") == None).equals(True)

def _test_cycle_with_non_cycle_tail(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_cycle_with_non_cycle_tail_impl)

# buildifier: disable=unused-variable
def _test_conditional_cycle_union_semantics_impl(env, target):
    lock_model_data = {
        "packages": {
            "a@1.0": _make_pkg("a", "1.0", [_make_file("a-1.0.tar.gz")], deps = [_make_dep("b", "1.0")]),
            "b@1.0": _make_pkg(
                "b",
                "1.0",
                [_make_file("b-1.0.tar.gz")],
                deps = [_make_dep("a", "1.0", marker = "sys_platform == 'linux'")],
            ),
        },
        "pins": {
            "a": "a@1.0",
            "b": "b@1.0",
        },
    }

    res = resolve(lock_model_data)

    pkg_a = res.packages["a@1.0"]
    group = pkg_a["cycle_group"]
    env.expect.that_bool(group != None).equals(True)

    env.expect.that_str(res.packages["b@1.0"]["cycle_group"]).equals(group)

def _test_conditional_cycle_union_semantics(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_conditional_cycle_union_semantics_impl)

# buildifier: disable=unused-variable
def _test_interconnected_cycles_impl(env, target):
    lock_model_data = {
        "packages": {
            "a@1.0": _make_pkg("a", "1.0", [_make_file("a-1.0.tar.gz")], deps = [_make_dep("b", "1.0")]),
            "b@1.0": _make_pkg(
                "b",
                "1.0",
                [_make_file("b-1.0.tar.gz")],
                deps = [_make_dep("c", "1.0"), _make_dep("e", "1.0")],
            ),
            "c@1.0": _make_pkg("c", "1.0", [_make_file("c-1.0.tar.gz")], deps = [_make_dep("d", "1.0")]),
            "d@1.0": _make_pkg("d", "1.0", [_make_file("d-1.0.tar.gz")], deps = [_make_dep("b", "1.0")]),
            "e@1.0": _make_pkg("e", "1.0", [_make_file("e-1.0.tar.gz")], deps = [_make_dep("f", "1.0")]),
            "f@1.0": _make_pkg(
                "f",
                "1.0",
                [_make_file("f-1.0.tar.gz")],
                deps = [_make_dep("e", "1.0"), _make_dep("g", "1.0")],
            ),
            "g@1.0": _make_pkg("g", "1.0", [_make_file("g-1.0.tar.gz")]),
        },
        "pins": {
            "a": "a@1.0",
        },
    }

    res = resolve(lock_model_data)

    pkg_b = res.packages["b@1.0"]
    group_bcd = pkg_b["cycle_group"]
    env.expect.that_bool(group_bcd != None).equals(True)

    env.expect.that_str(res.packages["c@1.0"]["cycle_group"]).equals(group_bcd)
    env.expect.that_str(res.packages["d@1.0"]["cycle_group"]).equals(group_bcd)

    pkg_e = res.packages["e@1.0"]
    group_ef = pkg_e["cycle_group"]
    env.expect.that_bool(group_ef != None).equals(True)

    env.expect.that_str(res.packages["f@1.0"]["cycle_group"]).equals(group_ef)

    env.expect.that_bool(group_bcd == group_ef).equals(False)

    env.expect.that_bool(res.packages["a@1.0"].get("cycle_group") == None).equals(True)
    env.expect.that_bool(res.packages["g@1.0"].get("cycle_group") == None).equals(True)

def _test_interconnected_cycles(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_interconnected_cycles_impl)

# buildifier: disable=unused-variable
def _test_no_cycles_diamond_impl(env, target):
    lock_model_data = {
        "packages": {
            "a@1.0": _make_pkg(
                "a",
                "1.0",
                [_make_file("a-1.0.tar.gz")],
                deps = [_make_dep("b", "1.0"), _make_dep("c", "1.0")],
            ),
            "b@1.0": _make_pkg("b", "1.0", [_make_file("b-1.0.tar.gz")], deps = [_make_dep("d", "1.0")]),
            "c@1.0": _make_pkg("c", "1.0", [_make_file("c-1.0.tar.gz")], deps = [_make_dep("d", "1.0")]),
            "d@1.0": _make_pkg("d", "1.0", [_make_file("d-1.0.tar.gz")]),
        },
        "pins": {
            "a": "a@1.0",
        },
    }

    res = resolve(lock_model_data)

    for pkg in res.packages.values():
        env.expect.that_bool(pkg.get("cycle_group") == None).equals(True)

    env.expect.that_collection(res.cycle_groups.keys()).has_size(0)

def _test_no_cycles_diamond(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_no_cycles_diamond_impl)

# buildifier: disable=unused-variable
def _test_self_loop_impl(env, target):
    lock_model_data = {
        "packages": {
            "a@1.0": _make_pkg("a", "1.0", [_make_file("a-1.0.tar.gz")], deps = [_make_dep("a", "1.0")]),
        },
        "pins": {
            "a": "a@1.0",
        },
    }

    res = resolve(lock_model_data)

    pkg_a = res.packages["a@1.0"]
    env.expect.that_bool(pkg_a.get("cycle_group") == None).equals(True)
    env.expect.that_collection(res.cycle_groups.keys()).has_size(0)

def _test_self_loop(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_self_loop_impl)

# buildifier: disable=unused-variable
def _test_unpinned_cycle_still_emitted_impl(env, target):
    lock_model_data = {
        "packages": {
            "a@1.0": _make_pkg("a", "1.0", [_make_file("a-1.0.tar.gz")]),
            "x@1.0": _make_pkg("x", "1.0", [_make_file("x-1.0.tar.gz")], deps = [_make_dep("y", "1.0")]),
            "y@1.0": _make_pkg("y", "1.0", [_make_file("y-1.0.tar.gz")], deps = [_make_dep("z", "1.0")]),
            "z@1.0": _make_pkg("z", "1.0", [_make_file("z-1.0.tar.gz")], deps = [_make_dep("x", "1.0")]),
        },
        "pins": {
            "a": "a@1.0",
        },
    }

    res = resolve(lock_model_data)

    env.expect.that_collection(res.packages.keys()).contains("a@1.0")
    env.expect.that_collection(res.packages.keys()).contains_at_least(["x@1.0", "y@1.0", "z@1.0"])

    env.expect.that_collection(res.cycle_groups.keys()).has_size(1)

    for pkg_key, pkg in res.packages.items():
        if pkg_key in ["x@1.0", "y@1.0", "z@1.0"]:
            env.expect.that_bool(pkg.get("cycle_group") != None).equals(True)
        else:
            env.expect.that_bool(pkg.get("cycle_group") == None).equals(True)

def _test_unpinned_cycle_still_emitted(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_unpinned_cycle_still_emitted_impl)

# buildifier: disable=unused-variable
def _test_partially_pinned_cycle_impl(env, target):
    lock_model_data = {
        "packages": {
            "a@1.0": _make_pkg("a", "1.0", [_make_file("a-1.0.tar.gz")], deps = [_make_dep("b", "1.0")]),
            "b@1.0": _make_pkg("b", "1.0", [_make_file("b-1.0.tar.gz")], deps = [_make_dep("c", "1.0")]),
            "c@1.0": _make_pkg("c", "1.0", [_make_file("c-1.0.tar.gz")], deps = [_make_dep("d", "1.0")]),
            "d@1.0": _make_pkg("d", "1.0", [_make_file("d-1.0.tar.gz")], deps = [_make_dep("a", "1.0")]),
        },
        "pins": {
            "a": "a@1.0",
        },
    }

    res = resolve(lock_model_data)

    pkg_a = res.packages["a@1.0"]
    group = pkg_a["cycle_group"]
    env.expect.that_bool(group != None).equals(True)

    for member in ["b@1.0", "c@1.0", "d@1.0"]:
        pkg = res.packages[member]
        env.expect.that_str(pkg["cycle_group"]).equals(group)

    env.expect.that_collection(res.cycle_groups[group]).has_size(4)

def _test_partially_pinned_cycle(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_partially_pinned_cycle_impl)

# buildifier: disable=unused-variable
def _test_version_isolation_impl(env, target):
    lock_model_data = {
        "packages": {
            "foo@1.0": _make_pkg("foo", "1.0", [_make_file("foo-1.0.tar.gz")], deps = [_make_dep("bar", "1.0")]),
            "bar@1.0": _make_pkg("bar", "1.0", [_make_file("bar-1.0.tar.gz")], deps = [_make_dep("foo", "1.0")]),
            "foo@2.0": _make_pkg("foo", "2.0", [_make_file("foo-2.0.tar.gz")], deps = [_make_dep("baz", "1.0")]),
            "baz@1.0": _make_pkg("baz", "1.0", [_make_file("baz-1.0.tar.gz")]),
        },
        "pins": {
            "foo": "foo@1.0",  # In Starlark pins might be simple or dictionary, let's see how we handle multiple versions.
            # The python test had pins = {"foo": {"": "foo@1.0", "v2": "foo@2.0"}}
            # Let's see if we can just pin both as separate keys if needed, or if resolve supports multiple versions of same pin name.
            # In Starlark `res.pins` keys are package names.
            # Let's try to pin both versions.
        },
    }

    # Wait, how does Starlark resolve handle pins dictionary?
    # Let's check test_default_alias_single_version_with_extras_impl
    # "pins": {"selenium": "selenium@1.0"}
    # Let's look at python test_version_isolation again.
    # pins = {canonicalize_name("foo"): {"": PackageKey.from_parts(...), "v2": PackageKey.from_parts(...)}}
    # In Starlark lock_model_data pins can be dictionary of package_name -> version_key OR package_name -> {extra -> version_key}
    # Let's try to simulate this.
    lock_model_data = {
        "packages": {
            "foo@1.0": _make_pkg("foo", "1.0", [_make_file("foo-1.0.tar.gz")], deps = [_make_dep("bar", "1.0")]),
            "bar@1.0": _make_pkg("bar", "1.0", [_make_file("bar-1.0.tar.gz")], deps = [_make_dep("foo", "1.0")]),
            "foo@2.0": _make_pkg("foo", "2.0", [_make_file("foo-2.0.tar.gz")], deps = [_make_dep("baz", "1.0")]),
            "baz@1.0": _make_pkg("baz", "1.0", [_make_file("baz-1.0.tar.gz")]),
        },
        "pins": {
            "foo": {
                "": "foo@1.0",
                "v2": "foo@2.0",
            },
        },
    }

    res = resolve(lock_model_data)

    pkg_foo1 = res.packages["foo@1.0"]
    group = pkg_foo1["cycle_group"]
    env.expect.that_bool(group != None).equals(True)

    env.expect.that_str(res.packages["bar@1.0"]["cycle_group"]).equals(group)

    pkg_foo2 = res.packages["foo@2.0"]
    env.expect.that_bool(pkg_foo2.get("cycle_group") == None).equals(True)

    env.expect.that_bool(res.packages["baz@1.0"].get("cycle_group") == None).equals(True)

def _test_version_isolation(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_version_isolation_impl)

# buildifier: disable=unused-variable
def _test_cross_platform_marker_cycle_impl(env, target):
    lock_model_data = {
        "packages": {
            "a@1.0": _make_pkg(
                "a",
                "1.0",
                [_make_file("a-1.0.tar.gz")],
                deps = [_make_dep("b", "1.0", marker = "sys_platform == 'linux'")],
            ),
            "b@1.0": _make_pkg(
                "b",
                "1.0",
                [_make_file("b-1.0.tar.gz")],
                deps = [_make_dep("a", "1.0", marker = "sys_platform == 'win32'")],
            ),
        },
        "pins": {
            "a": "a@1.0",
            "b": "b@1.0",
        },
    }

    res = resolve(lock_model_data)

    pkg_a = res.packages["a@1.0"]
    group = pkg_a["cycle_group"]
    env.expect.that_bool(group != None).equals(True)

    env.expect.that_str(res.packages["b@1.0"]["cycle_group"]).equals(group)

def _test_cross_platform_marker_cycle(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_cross_platform_marker_cycle_impl)

# buildifier: disable=unused-variable
def _test_extras_basic_impl(env, target):
    lock_model_data = {
        "packages": {
            "foo[test]@1.0": _make_pkg(
                "foo[test]",
                "1.0",
                [_make_file("foo-1.0.tar.gz")],
                deps = [
                    _make_dep("depA", "1.0"),
                    _make_dep("depB", "1.0", marker = "extra == 'test'"),
                ],
            ),
            "depA@1.0": _make_pkg("depA", "1.0", [_make_file("depA-1.0.tar.gz")]),
            "depB@1.0": _make_pkg("depB", "1.0", [_make_file("depB-1.0.tar.gz")]),
        },
        "pins": {
            "foo[test]": "foo[test]@1.0",
        },
    }

    res = resolve(lock_model_data)
    pkg = res.packages["foo[test]@1.0"]

    env.expect.that_collection(pkg["marker_dependencies"]).has_size(2)
    keys = [md["key"] for md in pkg["marker_dependencies"]]
    env.expect.that_collection(keys).contains("depA@1.0")
    env.expect.that_collection(keys).contains("depB@1.0")

def _test_extras_basic(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_extras_basic_impl)

# buildifier: disable=unused-variable
def _test_extras_with_env_markers_impl(env, target):
    lock_model_data = {
        "packages": {
            "foo[test]@1.0": _make_pkg(
                "foo[test]",
                "1.0",
                [_make_file("foo-1.0.tar.gz")],
                deps = [
                    _make_dep("depC", "1.0", marker = "extra == 'test' and sys_platform == 'linux'"),
                ],
            ),
            "depC@1.0": _make_pkg("depC", "1.0", [_make_file("depC-1.0.tar.gz")]),
        },
        "pins": {
            "foo[test]": "foo[test]@1.0",
        },
    }

    res = resolve(lock_model_data)
    pkg = res.packages["foo[test]@1.0"]

    env.expect.that_collection(pkg["marker_dependencies"]).has_size(1)
    md = pkg["marker_dependencies"][0]
    env.expect.that_str(md["key"]).equals("depC@1.0")
    env.expect.that_str(md["marker"]).contains("sys_platform")
    env.expect.that_str(md["marker"]).contains("extra == 'test'")

def _test_extras_with_env_markers(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_extras_with_env_markers_impl)

# buildifier: disable=unused-variable
def _test_extras_no_extras_impl(env, target):
    lock_model_data = {
        "packages": {
            "foo@1.0": _make_pkg(
                "foo",
                "1.0",
                [_make_file("foo-1.0.tar.gz")],
                deps = [_make_dep("depA", "1.0")],
            ),
            "depA@1.0": _make_pkg("depA", "1.0", [_make_file("depA-1.0.tar.gz")]),
        },
        "pins": {
            "foo": "foo@1.0",
        },
    }

    res = resolve(lock_model_data)
    pkg = res.packages["foo@1.0"]

    env.expect.that_collection(pkg["marker_dependencies"]).has_size(1)
    env.expect.that_str(pkg["marker_dependencies"][0]["key"]).equals("depA@1.0")
    env.expect.that_bool(pkg["marker_dependencies"][0].get("marker") == "").equals(True)  # Starlark uses empty string for no marker?
    # Let's check _make_dep default marker is ""
    # In Starlark `resolve`, if marker is empty it might be omitted or empty string.
    # Let's check test_unconditional_and_conditional_deps_impl
    # "unconditional = [md for md in pkg["marker_dependencies"] if not md["marker"]]"
    # So it might be empty or None.

def _test_extras_no_extras(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_extras_no_extras_impl)

# buildifier: disable=unused-variable
def _test_extras_multiple_impl(env, target):
    deps = [
        _make_dep("depA", "1.0"),
        _make_dep("pytest", "7.0", marker = "extra == 'test'"),
        _make_dep("black", "22.0", marker = "extra == 'dev'"),
    ]

    lock_model_data = {
        "packages": {
            "foo[test]@1.0": _make_pkg("foo[test]", "1.0", [_make_file("foo-1.0.tar.gz")], deps = deps),
            "foo[dev]@1.0": _make_pkg("foo[dev]", "1.0", [_make_file("foo-1.0.tar.gz")], deps = deps),
            "depA@1.0": _make_pkg("depA", "1.0", [_make_file("depA-1.0.tar.gz")]),
            "pytest@7.0": _make_pkg("pytest", "7.0", [_make_file("pytest-7.0.tar.gz")]),
            "black@22.0": _make_pkg("black", "22.0", [_make_file("black-22.0.tar.gz")]),
        },
        "pins": {
            "foo": {
                "test": "foo[test]@1.0",
                "dev": "foo[dev]@1.0",
            },
        },
    }

    res = resolve(lock_model_data)

    for pkg_key in ["foo[test]@1.0", "foo[dev]@1.0"]:
        pkg = res.packages[pkg_key]
        env.expect.that_collection(pkg["marker_dependencies"]).has_size(3)

        test_markers = {md["key"]: md.get("marker", "") for md in pkg["marker_dependencies"]}

        env.expect.that_str(test_markers.get("depA@1.0", "missing")).equals("")
        env.expect.that_str(test_markers.get("pytest@7.0", "missing")).equals("extra == 'test'")
        env.expect.that_str(test_markers.get("black@22.0", "missing")).equals("extra == 'dev'")

def _test_extras_multiple(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_extras_multiple_impl)

# buildifier: disable=unused-variable
def _test_single_package_single_env_impl(env, target):
    lock_model_data = {
        "packages": {
            "foo@1.0": _make_pkg("foo", "1.0", [_make_file("foo-1.0-cp310-cp310-manylinux_2_17_x86_64.whl")]),
        },
        "pins": {
            "foo": "foo@1.0",
        },
    }
    res = resolve(lock_model_data)
    pkg = res.packages["foo@1.0"]

    env.expect.that_collection(pkg["wheel_candidates"]).has_size(1)
    env.expect.that_str(pkg["wheel_candidates"][0]["filename"]).equals("foo-1.0-cp310-cp310-manylinux_2_17_x86_64.whl")

def _test_single_package_single_env(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_single_package_single_env_impl)

# buildifier: disable=unused-variable
def _test_wheel_candidates_include_all_wheels_impl(env, target):
    lock_model_data = {
        "packages": {
            "foo@1.0": _make_pkg(
                "foo",
                "1.0",
                [
                    _make_file("foo-1.0-cp310-cp310-manylinux2014_x86_64.whl"),
                    _make_file("foo-1.0-cp310-cp310-manylinux_2_17_x86_64.whl"),
                ],
            ),
        },
        "pins": {
            "foo": "foo@1.0",
        },
    }
    res = resolve(lock_model_data)
    pkg = res.packages["foo@1.0"]

    env.expect.that_collection(pkg["wheel_candidates"]).has_size(2)
    filenames = [c["filename"] for c in pkg["wheel_candidates"]]
    env.expect.that_collection(filenames).contains("foo-1.0-cp310-cp310-manylinux2014_x86_64.whl")
    env.expect.that_collection(filenames).contains("foo-1.0-cp310-cp310-manylinux_2_17_x86_64.whl")

def _test_wheel_candidates_include_all_wheels(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_wheel_candidates_include_all_wheels_impl)

# buildifier: disable=unused-variable
def _test_wheel_candidates_with_build_tags_impl(env, target):
    lock_model_data = {
        "packages": {
            "foo@1.0": _make_pkg(
                "foo",
                "1.0",
                [
                    _make_file("foo-1.0-1-cp310-cp310-manylinux_2_17_x86_64.whl"),
                    _make_file("foo-1.0-2-cp310-cp310-manylinux_2_17_x86_64.whl"),
                    _make_file("foo-1.0-cp310-cp310-manylinux_2_17_x86_64.whl"),
                ],
            ),
        },
        "pins": {
            "foo": "foo@1.0",
        },
    }
    res = resolve(lock_model_data)
    pkg = res.packages["foo@1.0"]

    env.expect.that_collection(pkg["wheel_candidates"]).has_size(3)
    filenames = [c["filename"] for c in pkg["wheel_candidates"]]
    env.expect.that_collection(filenames).contains("foo-1.0-2-cp310-cp310-manylinux_2_17_x86_64.whl")

def _test_wheel_candidates_with_build_tags(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_wheel_candidates_with_build_tags_impl)

# buildifier: disable=unused-variable
def _test_wheel_preferred_over_sdist_impl(env, target):
    lock_model_data = {
        "packages": {
            "foo@1.0": _make_pkg(
                "foo",
                "1.0",
                [
                    _make_file("foo-1.0-cp310-cp310-manylinux_2_17_x86_64.whl"),
                    _make_file("foo-1.0.tar.gz"),
                ],
            ),
        },
        "pins": {
            "foo": "foo@1.0",
        },
    }
    res = resolve(lock_model_data)
    pkg = res.packages["foo@1.0"]

    env.expect.that_collection(pkg["wheel_candidates"]).has_size(1)
    env.expect.that_str(pkg["wheel_candidates"][0]["filename"]).equals("foo-1.0-cp310-cp310-manylinux_2_17_x86_64.whl")
    env.expect.that_bool(pkg["uses_sdist"]).equals(False)

def _test_wheel_preferred_over_sdist(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_wheel_preferred_over_sdist_impl)

# buildifier: disable=unused-variable
def _test_all_wheels_become_candidates_impl(env, target):
    lock_model_data = {
        "packages": {
            "foo@1.0": _make_pkg(
                "foo",
                "1.0",
                [
                    _make_file("foo-1.0-cp310-cp310-macosx_10_9_x86_64.whl"),
                    _make_file("foo-1.0.tar.gz"),
                ],
            ),
        },
        "pins": {
            "foo": "foo@1.0",
        },
    }
    res = resolve(lock_model_data)
    pkg = res.packages["foo@1.0"]

    env.expect.that_collection(pkg["wheel_candidates"]).has_size(1)
    env.expect.that_str(pkg["wheel_candidates"][0]["filename"]).equals("foo-1.0-cp310-cp310-macosx_10_9_x86_64.whl")

def _test_all_wheels_become_candidates(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_all_wheels_become_candidates_impl)

# buildifier: disable=unused-variable
def _test_always_include_sdist_flag_impl(env, target):
    lock_model_data = {
        "packages": {
            "foo@1.0": _make_pkg(
                "foo",
                "1.0",
                [
                    _make_file("foo-1.0-cp310-cp310-manylinux_2_17_x86_64.whl"),
                    _make_file("foo-1.0.tar.gz"),
                ],
            ),
        },
        "pins": {
            "foo": "foo@1.0",
        },
    }
    res = resolve(lock_model_data, always_include_sdist = True)
    pkg = res.packages["foo@1.0"]

    env.expect.that_collection(pkg["wheel_candidates"]).has_size(1)
    env.expect.that_bool(pkg["uses_sdist"]).equals(True)
    env.expect.that_str(pkg["sdist_file"]["key"]).contains("foo-1.0.tar.gz")

def _test_always_include_sdist_flag(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_always_include_sdist_flag_impl)

# buildifier: disable=unused-variable
def _test_wheel_only_no_sdist_impl(env, target):
    lock_model_data = {
        "packages": {
            "foo@1.0": _make_pkg(
                "foo",
                "1.0",
                [_make_file("foo-1.0-cp310-cp310-macosx_10_9_x86_64.whl")],
            ),
        },
        "pins": {
            "foo": "foo@1.0",
        },
    }
    res = resolve(lock_model_data)
    pkg = res.packages["foo@1.0"]

    env.expect.that_collection(pkg["wheel_candidates"]).has_size(1)
    env.expect.that_bool(pkg["sdist_file"] == None).equals(True)

def _test_wheel_only_no_sdist(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_wheel_only_no_sdist_impl)

# buildifier: disable=unused-variable
def _test_pure_python_wheel_is_candidate_impl(env, target):
    lock_model_data = {
        "packages": {
            "foo@1.0": _make_pkg(
                "foo",
                "1.0",
                [_make_file("foo-1.0-py3-none-any.whl")],
            ),
        },
        "pins": {
            "foo": "foo@1.0",
        },
    }
    res = resolve(lock_model_data)
    pkg = res.packages["foo@1.0"]

    env.expect.that_collection(pkg["wheel_candidates"]).has_size(1)
    env.expect.that_str(pkg["wheel_candidates"][0]["filename"]).equals("foo-1.0-py3-none-any.whl")

def _test_pure_python_wheel_is_candidate(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_pure_python_wheel_is_candidate_impl)

# buildifier: disable=unused-variable
def _test_multi_platform_wheels_all_candidates_impl(env, target):
    lock_model_data = {
        "packages": {
            "foo@1.0": _make_pkg(
                "foo",
                "1.0",
                [
                    _make_file("foo-1.0-cp310-cp310-manylinux_2_17_x86_64.whl"),
                    _make_file("foo-1.0-cp310-cp310-macosx_10_9_x86_64.whl"),
                ],
            ),
        },
        "pins": {
            "foo": "foo@1.0",
        },
    }
    res = resolve(lock_model_data)
    pkg = res.packages["foo@1.0"]

    env.expect.that_collection(pkg["wheel_candidates"]).has_size(2)
    filenames = [c["filename"] for c in pkg["wheel_candidates"]]
    env.expect.that_collection(filenames).contains("foo-1.0-cp310-cp310-manylinux_2_17_x86_64.whl")
    env.expect.that_collection(filenames).contains("foo-1.0-cp310-cp310-macosx_10_9_x86_64.whl")

def _test_multi_platform_wheels_all_candidates(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_multi_platform_wheels_all_candidates_impl)

# buildifier: disable=unused-variable
def _test_unconditional_and_conditional_deps_impl(env, target):
    lock_model_data = {
        "packages": {
            "foo@1.0": _make_pkg(
                "foo",
                "1.0",
                [_make_file("foo-1.0.tar.gz")],
                deps = [
                    _make_dep("depA", "1.0"),
                    _make_dep("depB", "1.0", marker = "sys_platform == 'linux'"),
                ],
            ),
            "depA@1.0": _make_pkg("depA", "1.0", [_make_file("depA-1.0.tar.gz")]),
            "depB@1.0": _make_pkg("depB", "1.0", [_make_file("depB-1.0.tar.gz")]),
        },
        "pins": {
            "foo": "foo@1.0",
        },
    }
    res = resolve(lock_model_data)
    pkg = res.packages["foo@1.0"]

    env.expect.that_collection(pkg["marker_dependencies"]).has_size(2)

    unconditional = [md for md in pkg["marker_dependencies"] if not md["marker"]]
    conditional = [md for md in pkg["marker_dependencies"] if md["marker"]]

    env.expect.that_collection(unconditional).has_size(1)
    env.expect.that_str(unconditional[0]["key"]).equals("depA@1.0")

    env.expect.that_collection(conditional).has_size(1)
    env.expect.that_str(conditional[0]["key"]).equals("depB@1.0")
    env.expect.that_str(conditional[0]["marker"]).contains("sys_platform")

def _test_unconditional_and_conditional_deps(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_unconditional_and_conditional_deps_impl)

# buildifier: disable=unused-variable
def _test_marker_preserved_impl(env, target):
    lock_model_data = {
        "packages": {
            "foo@1.0": _make_pkg(
                "foo",
                "1.0",
                [_make_file("foo-1.0.tar.gz")],
                deps = [_make_dep("depA", "1.0", marker = "sys_platform == 'linux'")],
            ),
            "depA@1.0": _make_pkg("depA", "1.0", [_make_file("depA-1.0.tar.gz")]),
        },
        "pins": {
            "foo": "foo@1.0",
        },
    }
    res = resolve(lock_model_data)
    pkg = res.packages["foo@1.0"]

    env.expect.that_collection(pkg["marker_dependencies"]).has_size(1)
    env.expect.that_str(pkg["marker_dependencies"][0]["key"]).equals("depA@1.0")
    env.expect.that_str(pkg["marker_dependencies"][0]["marker"]).contains("sys_platform")

def _test_marker_preserved(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_marker_preserved_impl)

# buildifier: disable=unused-variable
def _test_ignore_dependencies_impl(env, target):
    lock_model_data = {
        "packages": {
            "foo@1.0": _make_pkg("foo", "1.0", [_make_file("foo-1.0.tar.gz")], deps = [_make_dep("depA", "1.0")]),
            "depA@1.0": _make_pkg("depA", "1.0", [_make_file("depA-1.0.tar.gz")]),
        },
        "pins": {
            "foo": "foo@1.0",
        },
    }

    annotations_data = {
        "foo": {
            "ignore_dependencies": ["depA"],
        },
    }

    res = resolve(lock_model_data, annotations_data = annotations_data)
    pkg = res.packages["foo@1.0"]

    env.expect.that_collection(pkg["marker_dependencies"]).has_size(0)

def _test_ignore_dependencies(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_ignore_dependencies_impl)

# buildifier: disable=unused-variable
def _test_multi_version_dep_resolution_impl(env, target):
    lock_model_data = {
        "packages": {
            "foo@1.0": _make_pkg(
                "foo",
                "1.0",
                [_make_file("foo-1.0.tar.gz")],
                deps = [
                    _make_dep("depA", "1.0", marker = "sys_platform == 'linux'"),
                    _make_dep("depA", "2.0", marker = "sys_platform == 'darwin'"),
                ],
            ),
            "depA@1.0": _make_pkg("depA", "1.0", [_make_file("depA-1.0.tar.gz")]),
            "depA@2.0": _make_pkg("depA", "2.0", [_make_file("depA-2.0.tar.gz")]),
        },
        "pins": {
            "foo": "foo@1.0",
        },
    }
    res = resolve(lock_model_data)
    pkg = res.packages["foo@1.0"]

    env.expect.that_collection(pkg["marker_dependencies"]).has_size(2)
    keys = [md["key"] for md in pkg["marker_dependencies"]]
    env.expect.that_collection(keys).contains("depA@1.0")
    env.expect.that_collection(keys).contains("depA@2.0")

def _test_multi_version_dep_resolution(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_multi_version_dep_resolution_impl)

# buildifier: disable=unused-variable
def _test_build_dependencies_impl(env, target):
    lock_model_data = {
        "packages": {
            "foo@1.0": _make_pkg("foo", "1.0", [_make_file("foo-1.0.tar.gz")]),
            "setuptools@60.0": _make_pkg("setuptools", "60.0", [_make_file("setuptools-60.0.tar.gz")]),
        },
        "pins": {
            "foo": "foo@1.0",
        },
    }

    res = resolve(lock_model_data, default_build_dependencies_args = ["setuptools@60.0"])
    pkg = res.packages["foo@1.0"]

    env.expect.that_collection(pkg["build_dependencies"]).has_size(1)
    env.expect.that_str(pkg["build_dependencies"][0]).equals("setuptools@60.0")

def _test_build_dependencies(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_build_dependencies_impl)

# buildifier: disable=unused-variable
def _test_build_deps_not_duplicated_impl(env, target):
    lock_model_data = {
        "packages": {
            "foo@1.0": _make_pkg(
                "foo",
                "1.0",
                [_make_file("foo-1.0.tar.gz")],
                deps = [_make_dep("setuptools", "60.0")],
            ),
            "setuptools@60.0": _make_pkg("setuptools", "60.0", [_make_file("setuptools-60.0.tar.gz")]),
        },
        "pins": {
            "foo": "foo@1.0",
        },
    }

    res = resolve(lock_model_data, default_build_dependencies_args = ["setuptools@60.0"])
    pkg = res.packages["foo@1.0"]

    env.expect.that_collection(pkg["build_dependencies"]).has_size(0)

def _test_build_deps_not_duplicated(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_build_deps_not_duplicated_impl)

# buildifier: disable=unused-variable
def _test_local_wheel_override_impl(env, target):
    lock_model_data = {
        "packages": {
            "foo@1.0": _make_pkg("foo", "1.0", [_make_file("foo-1.0-cp310-cp310-manylinux_2_17_x86_64.whl")]),
        },
        "pins": {"foo": "foo@1.0"},
    }
    local_wheels = {"foo-1.0-cp310-cp310-manylinux_2_17_x86_64.whl": "@//path:wheel"}

    res = resolve(lock_model_data, local_wheels = local_wheels)
    pkg = res.packages["foo@1.0"]

    env.expect.that_collection(pkg["wheel_candidates"]).has_size(1)
    env.expect.that_str(pkg["wheel_candidates"][0]["file_reference"]["label"]).equals("@//path:wheel")

def _test_local_wheel_override(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_local_wheel_override_impl)

# buildifier: disable=unused-variable
def _test_remote_wheel_override_impl(env, target):
    lock_model_data = {
        "packages": {
            "foo@1.0": _make_pkg("foo", "1.0", [_make_file("foo-1.0-cp310-cp310-manylinux_2_17_x86_64.whl")]),
        },
        "pins": {"foo": "foo@1.0"},
    }
    remote_wheels = {"https://remote.com/foo-1.0-cp310-cp310-manylinux_2_17_x86_64.whl": "remote_sha"}

    res = resolve(lock_model_data, remote_wheels = remote_wheels)
    pkg = res.packages["foo@1.0"]

    env.expect.that_collection(pkg["wheel_candidates"]).has_size(1)
    expected_key = "foo-1.0-cp310-cp310-manylinux_2_17_x86_64.whl/remote_sha/edfe9b3e"
    env.expect.that_str(pkg["wheel_candidates"][0]["file_reference"]["key"]).equals(expected_key)

def _test_remote_wheel_override(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_remote_wheel_override_impl)

# buildifier: disable=unused-variable
def _test_always_build_annotation_impl(env, target):
    lock_model_data = {
        "packages": {
            "foo@1.0": _make_pkg(
                "foo",
                "1.0",
                [
                    _make_file("foo-1.0-cp310-cp310-manylinux_2_17_x86_64.whl"),
                    _make_file("foo-1.0.tar.gz"),
                ],
            ),
        },
        "pins": {"foo": "foo@1.0"},
    }
    annotations_data = {
        "foo": {
            "always_build": True,
        },
    }

    res = resolve(lock_model_data, annotations_data = annotations_data, always_include_sdist = False)
    pkg = res.packages["foo@1.0"]

    env.expect.that_bool(pkg["uses_sdist"]).equals(True)
    env.expect.that_bool(pkg["sdist_file"] != None).equals(True)
    env.expect.that_str(pkg["sdist_file"]["key"]).contains("foo-1.0.tar.gz")

def _test_always_build_annotation(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_always_build_annotation_impl)

# buildifier: disable=unused-variable
def _test_build_target_override_impl(env, target):
    lock_model_data = {
        "packages": {
            "foo@1.0": _make_pkg("foo", "1.0", [_make_file("foo-1.0.tar.gz")]),
        },
        "pins": {"foo": "foo@1.0"},
    }
    annotations_data = {
        "foo": {
            "build_target": "@//custom:build",
        },
    }

    res = resolve(lock_model_data, annotations_data = annotations_data)
    pkg = res.packages["foo@1.0"]

    env.expect.that_str(pkg["build_target"]).equals("@//custom:build")

def _test_build_target_override(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_build_target_override_impl)

# buildifier: disable=unused-variable
def _test_install_exclude_globs_impl(env, target):
    lock_model_data = {
        "packages": {
            "foo@1.0": _make_pkg("foo", "1.0", [_make_file("foo-1.0.tar.gz")]),
        },
        "pins": {"foo": "foo@1.0"},
    }
    annotations_data = {
        "foo": {
            "install_exclude_globs": ["tests/**"],
        },
    }

    res = resolve(lock_model_data, annotations_data = annotations_data)
    pkg = res.packages["foo@1.0"]

    env.expect.that_collection(pkg["install_exclude_globs"]).contains("tests/**")

def _test_install_exclude_globs(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_install_exclude_globs_impl)

# buildifier: disable=unused-variable
def _test_pre_post_install_patches_impl(env, target):
    lock_model_data = {
        "packages": {
            "foo@1.0": _make_pkg("foo", "1.0", [_make_file("foo-1.0.tar.gz")]),
        },
        "pins": {"foo": "foo@1.0"},
    }
    annotations_data = {
        "foo": {
            "pre_build_patches": ["@//:pre.patch"],
            "post_install_patches": ["@//:post.patch"],
        },
    }

    res = resolve(lock_model_data, annotations_data = annotations_data)
    pkg = res.packages["foo@1.0"]

    env.expect.that_collection(pkg["pre_build_patches"]).contains_exactly(["@//:pre.patch"])
    env.expect.that_collection(pkg["post_install_patches"]).contains_exactly(["@//:post.patch"])

def _test_pre_post_install_patches(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_pre_post_install_patches_impl)

# buildifier: disable=unused-variable
def _test_multi_tag_wheel_candidates_impl(env, target):
    lock_model_data = {
        "packages": {
            "numpy@1.26.4": _make_pkg(
                "numpy",
                "1.26.4",
                [_make_file("numpy-1.26.4-cp310.cp311-cp310.cp311-manylinux_2_17_x86_64.manylinux2014_x86_64.whl")],
            ),
        },
        "pins": {"numpy": "numpy@1.26.4"},
    }

    res = resolve(lock_model_data)
    pkg = res.packages["numpy@1.26.4"]

    env.expect.that_collection(pkg["wheel_candidates"]).has_size(1)

def _test_multi_tag_wheel_candidates(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_multi_tag_wheel_candidates_impl)

# buildifier: disable=unused-variable
def _test_sdist_only_package_impl(env, target):
    lock_model_data = {
        "packages": {
            "mylib@1.0": _make_pkg("mylib", "1.0", [_make_file("mylib-1.0.tar.gz")]),
        },
        "pins": {"mylib": "mylib@1.0"},
    }

    res = resolve(lock_model_data)
    pkg = res.packages["mylib@1.0"]

    env.expect.that_bool(pkg["uses_sdist"]).equals(True)
    env.expect.that_collection(pkg["wheel_candidates"]).has_size(0)
    env.expect.that_bool(pkg["sdist_file"] != None).equals(True)

def _test_sdist_only_package(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_sdist_only_package_impl)

def _test_no_files_raises_error_impl(env, target):
    env.expect.that_target(target).failures().contains_predicate(
        matching.contains("has no compatible wheels and no sdist found"),
    )

def _test_no_files_raises_error(name):
    lock_model_data = {
        "packages": {
            "mylib@1.0": _make_pkg("mylib", "1.0", []),
        },
        "pins": {"mylib": "mylib@1.0"},
    }

    util.helper_target(
        _resolve_failure_subject,
        name = name + "_subject",
        lock_model_data = json.encode(lock_model_data),
    )

    analysis_test(
        name = name,
        target = name + "_subject",
        impl = _test_no_files_raises_error_impl,
        expect_failure = True,
    )

# buildifier: disable=unused-variable
def _test_empty_lock_impl(env, target):
    lock_model_data = {
        "packages": {},
        "pins": {},
    }
    res = resolve(lock_model_data)
    env.expect.that_collection(res.packages.keys()).has_size(0)
    env.expect.that_collection(res.pins.keys()).has_size(0)

def _test_empty_lock(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_empty_lock_impl)

def _test_pinned_package_not_in_packages_impl(env, target):
    env.expect.that_target(target).failures().contains_predicate(
        matching.contains("Missing package foo@1.0"),
    )

def _test_pinned_package_not_in_packages(name):
    lock_model_data = {
        "packages": {},
        "pins": {"foo": "foo@1.0"},
    }

    util.helper_target(
        _resolve_failure_subject,
        name = name + "_subject",
        lock_model_data = json.encode(lock_model_data),
    )

    analysis_test(
        name = name,
        target = name + "_subject",
        impl = _test_pinned_package_not_in_packages_impl,
        expect_failure = True,
    )

# buildifier: disable=unused-variable
def _test_wildcard_always_build_end_to_end_impl(env, target):
    lock_model_data = {
        "packages": {
            "foo@1.0": _make_pkg(
                "foo",
                "1.0",
                [
                    _make_file("foo-1.0-cp310-cp310-manylinux_2_17_x86_64.whl"),
                    _make_file("foo-1.0.tar.gz"),
                ],
            ),
        },
        "pins": {"foo": "foo@1.0"},
    }
    annotations_data = {
        "*": {
            "always_build": True,
        },
    }

    res = resolve(lock_model_data, annotations_data = annotations_data, always_include_sdist = False)
    pkg = res.packages["foo@1.0"]

    env.expect.that_bool(pkg["uses_sdist"]).equals(True)
    env.expect.that_bool(pkg["sdist_file"] != None).equals(True)
    env.expect.that_str(pkg["sdist_file"]["key"]).contains("foo-1.0.tar.gz")

def _test_wildcard_always_build_end_to_end(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_wildcard_always_build_end_to_end_impl)

# buildifier: disable=unused-variable
def _test_wildcard_with_specific_override_end_to_end_impl(env, target):
    lock_model_data = {
        "packages": {
            "foo@1.0": _make_pkg(
                "foo",
                "1.0",
                [
                    _make_file("foo-1.0-cp310-cp310-manylinux_2_17_x86_64.whl"),
                    _make_file("foo-1.0.tar.gz"),
                ],
            ),
            "bar@2.0": _make_pkg(
                "bar",
                "2.0",
                [
                    _make_file("bar-2.0-cp310-cp310-manylinux_2_17_x86_64.whl"),
                    _make_file("bar-2.0.tar.gz"),
                ],
            ),
        },
        "pins": {
            "foo": "foo@1.0",
            "bar": "bar@2.0",
        },
    }
    annotations_data = {
        "*": {"always_build": True},
        "foo": {"always_build": False},
    }

    res = resolve(lock_model_data, annotations_data = annotations_data, always_include_sdist = False)

    foo_pkg = res.packages["foo@1.0"]
    bar_pkg = res.packages["bar@2.0"]

    env.expect.that_collection(foo_pkg["wheel_candidates"]).has_size(1)
    env.expect.that_str(foo_pkg["wheel_candidates"][0]["filename"]).equals("foo-1.0-cp310-cp310-manylinux_2_17_x86_64.whl")
    env.expect.that_bool(foo_pkg["uses_sdist"]).equals(False)

    env.expect.that_bool(bar_pkg["uses_sdist"]).equals(True)
    env.expect.that_bool(bar_pkg["sdist_file"] != None).equals(True)
    env.expect.that_str(bar_pkg["sdist_file"]["key"]).contains("bar-2.0.tar.gz")

def _test_wildcard_with_specific_override_end_to_end(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_wildcard_with_specific_override_end_to_end_impl)

# buildifier: disable=unused-variable
def _test_unconsumed_wildcard_annotations_no_error_impl(env, target):
    lock_model_data = {
        "packages": {
            "foo@1.0": _make_pkg("foo", "1.0", [_make_file("foo-1.0.tar.gz")]),
            "unused@1.0": _make_pkg("unused", "1.0", [_make_file("unused-1.0.tar.gz")]),
        },
        "pins": {"foo": "foo@1.0"},
    }
    annotations_data = {
        "*": {"always_build": True},
    }

    res = resolve(lock_model_data, annotations_data = annotations_data)
    env.expect.that_collection(res.packages.keys()).contains("foo@1.0")

def _test_unconsumed_wildcard_annotations_no_error(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_unconsumed_wildcard_annotations_no_error_impl)

# buildifier: disable=unused-variable
def _test_build_repo_flows_to_resolved_package_impl(env, target):
    lock_model_data = {
        "packages": {
            "foo@1.0": _make_pkg("foo", "1.0", [_make_file("foo-1.0.tar.gz")]),
        },
        "pins": {"foo": "foo@1.0"},
    }
    annotations_data = {
        "foo": {"build_repo": "build_deps"},
    }

    res = resolve(lock_model_data, annotations_data = annotations_data)
    pkg = res.packages["foo@1.0"]

    env.expect.that_str(pkg["build_repo"]).equals("build_deps")

def _test_build_repo_flows_to_resolved_package(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_build_repo_flows_to_resolved_package_impl)

# buildifier: disable=unused-variable
def _test_wildcard_build_repo_flows_to_resolved_package_impl(env, target):
    lock_model_data = {
        "packages": {
            "foo@1.0": _make_pkg("foo", "1.0", [_make_file("foo-1.0.tar.gz")]),
            "bar@2.0": _make_pkg("bar", "2.0", [_make_file("bar-2.0.tar.gz")]),
        },
        "pins": {
            "foo": "foo@1.0",
            "bar": "bar@2.0",
        },
    }
    annotations_data = {
        "*": {"build_repo": "shared_build"},
    }

    res = resolve(lock_model_data, annotations_data = annotations_data)

    for pkg in res.packages.values():
        env.expect.that_str(pkg["build_repo"]).equals("shared_build")

def _test_wildcard_build_repo_flows_to_resolved_package(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_wildcard_build_repo_flows_to_resolved_package_impl)

# buildifier: disable=unused-variable
def _test_wildcard_install_exclude_globs_end_to_end_impl(env, target):
    lock_model_data = {
        "packages": {
            "foo@1.0": _make_pkg("foo", "1.0", [_make_file("foo-1.0.tar.gz")]),
        },
        "pins": {"foo": "foo@1.0"},
    }
    annotations_data = {
        "*": {"install_exclude_globs": ["*.pyc", "__pycache__/**"]},
    }

    res = resolve(lock_model_data, annotations_data = annotations_data)
    pkg = res.packages["foo@1.0"]

    env.expect.that_collection(pkg["install_exclude_globs"]).contains("*.pyc")
    env.expect.that_collection(pkg["install_exclude_globs"]).contains("__pycache__/**")

def _test_wildcard_install_exclude_globs_end_to_end(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_wildcard_install_exclude_globs_end_to_end_impl)

# buildifier: disable=unused-variable
def _test_wildcard_replace_semantics_exclude_globs_end_to_end_impl(env, target):
    lock_model_data = {
        "packages": {
            "foo@1.0": _make_pkg("foo", "1.0", [_make_file("foo-1.0.tar.gz")]),
            "bar@2.0": _make_pkg("bar", "2.0", [_make_file("bar-2.0.tar.gz")]),
        },
        "pins": {
            "foo": "foo@1.0",
            "bar": "bar@2.0",
        },
    }
    annotations_data = {
        "*": {"install_exclude_globs": ["*.pyc"]},
        "foo": {"install_exclude_globs": ["tests/**"]},
    }

    res = resolve(lock_model_data, annotations_data = annotations_data)

    foo_pkg = res.packages["foo@1.0"]
    bar_pkg = res.packages["bar@2.0"]

    env.expect.that_collection(foo_pkg["install_exclude_globs"]).contains("tests/**")
    env.expect.that_collection(foo_pkg["install_exclude_globs"]).not_contains("*.pyc")

    env.expect.that_collection(bar_pkg["install_exclude_globs"]).contains("*.pyc")

def _test_wildcard_replace_semantics_exclude_globs_end_to_end(name):
    util.helper_target(native.filegroup, name = name + "_subject", srcs = [])
    analysis_test(name = name, target = name + "_subject", impl = _test_wildcard_replace_semantics_exclude_globs_end_to_end_impl)

def lock_resolver_test_suite(name):
    test_suite(
        name = name,
        tests = [
            _test_basic_resolution,
            _test_default_alias_single_version_with_extras,
            _test_build_dependencies_override,
            _test_synthesized_deps,
            _test_cycle_two_nodes,
            _test_cycle_via_extra,
            _test_cycle_three_nodes,
            _test_no_cycles,
            _test_cycle_group_naming_stable,
            _test_multiple_disconnected_cycles,
            _test_cycle_eight_member_hub_and_spoke,
            _test_cycle_with_non_cycle_tail,
            _test_conditional_cycle_union_semantics,
            _test_interconnected_cycles,
            _test_no_cycles_diamond,
            _test_self_loop,
            _test_unpinned_cycle_still_emitted,
            _test_partially_pinned_cycle,
            _test_version_isolation,
            _test_cross_platform_marker_cycle,
            _test_extras_basic,
            _test_extras_with_env_markers,
            _test_extras_no_extras,
            _test_extras_multiple,
            _test_single_package_single_env,
            _test_wheel_candidates_include_all_wheels,
            _test_wheel_candidates_with_build_tags,
            _test_wheel_preferred_over_sdist,
            _test_all_wheels_become_candidates,
            _test_always_include_sdist_flag,
            _test_wheel_only_no_sdist,
            _test_pure_python_wheel_is_candidate,
            _test_multi_platform_wheels_all_candidates,
            _test_unconditional_and_conditional_deps,
            _test_marker_preserved,
            _test_ignore_dependencies,
            _test_multi_version_dep_resolution,
            _test_build_dependencies,
            _test_build_deps_not_duplicated,
            _test_local_wheel_override,
            _test_remote_wheel_override,
            _test_always_build_annotation,
            _test_build_target_override,
            _test_install_exclude_globs,
            _test_pre_post_install_patches,
            _test_multi_tag_wheel_candidates,
            _test_sdist_only_package,
            _test_no_files_raises_error,
            _test_empty_lock,
            _test_pinned_package_not_in_packages,
            _test_wildcard_always_build_end_to_end,
            _test_wildcard_with_specific_override_end_to_end,
            _test_unconsumed_wildcard_annotations_no_error,
            _test_build_repo_flows_to_resolved_package,
            _test_wildcard_build_repo_flows_to_resolved_package,
            _test_wildcard_install_exclude_globs_end_to_end,
            _test_wildcard_replace_semantics_exclude_globs_end_to_end,
        ],
    )
