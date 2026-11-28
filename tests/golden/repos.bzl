"""Dev-only module extension generating golden snapshots of state_repo, spoke_repo, and thin_package_repo outputs."""

load("@pypackaging.bzl", "pypackaging")

# buildifier: disable=bzl-visibility
load("//pycross/private:lock_contract.bzl", "state_repo_name")

# buildifier: disable=bzl-visibility
load("//pycross/private:repo_slots.bzl", "assign_fork_slots", "sdist_slot_repo_name")

# buildifier: disable=bzl-visibility
load("//pycross/private:spoke_repo.bzl", "build_spoke_payloads", "spoke_repo")

# buildifier: disable=bzl-visibility
load(
    "//pycross/private:state_repo.bzl",
    "merge_workspace_locks",
    "normalize_workspace_variants",
    "slim_member_lock",
    "state_repo",
)

# buildifier: disable=bzl-visibility
load("//pycross/private:thin_package_repo.bzl", "thin_package_repo")

# buildifier: disable=bzl-visibility
load("//pycross/private:util.bzl", "parse_package_key", "sdist_builds_disallowed", "underscore_name")

# buildifier: disable=bzl-visibility
load("//pycross/private/lock_render:reset_plan.bzl", "compute_workspace_reset_states", "conflict_pairs")

_SAMPLE_BACKEND_NAMES = [
    "pep517_build",
    "setuptools_build",
]

def _build_repo_map(lock_data):
    """Build a deterministic fake repo_map covering every wheel and sdist in `lock_data`."""
    repo_map = {}
    for pkg in lock_data.get("packages", {}).values():
        for cand in pkg.get("wheel_candidates", []):
            key = cand.get("file_reference", {}).get("key")
            if key and key not in repo_map:
                repo_map[key] = "@fake_{}//:wheel".format(key)
        sdist_file = pkg.get("sdist_file")
        if sdist_file and sdist_file.get("key"):
            key = sdist_file["key"]
            if key not in repo_map:
                repo_map[key] = "@fake_{}//file:{}.tar.gz".format(key, key)
    return repo_map

def _golden_snapshot_repo_impl(rctx):
    """Collect generated files from state_repo, spoke_repo, and thin_package_repo instances into a snapshot repo."""

    # Build (canonical_repo_name, apparent_repo_name) pairs, longest canonical first
    # so e.g. `golden_plain__state` is replaced before `golden_plain`.
    normalizations = []
    for repo_label, prefix in rctx.attr.repo_roots.items():
        apparent = rctx.attr.apparent_names[prefix]
        canonical = repo_label.repo_name
        if canonical and canonical != apparent:
            normalizations.append((canonical, apparent))
    normalizations = sorted(normalizations, key = lambda pair: (-len(pair[0]), pair[0]))

    rules_pycross_canonical = Label("@rules_pycross//:MODULE.bazel").repo_name

    manifest = []
    for repo_label, prefix in sorted(rctx.attr.repo_roots.items(), key = lambda item: item[1]):
        root_dir = rctx.path(repo_label).dirname
        stack = [(root_dir, "")]
        for _ in range(1 << 16):
            if not stack:
                break
            cur_dir, rel_dir = stack.pop()
            entries = sorted(cur_dir.readdir(), key = lambda p: p.basename, reverse = True)
            for entry in entries:
                name = entry.basename
                if name.startswith("."):
                    continue
                rel_path = "{}/{}".format(rel_dir, name) if rel_dir else name
                if entry.is_dir:
                    stack.append((entry, rel_path))
                else:
                    if rel_path == "REPO.bazel":
                        continue
                    content = rctx.read(entry)
                    for canonical, apparent in normalizations:
                        content = content.replace("@@" + canonical, "@@" + apparent)
                    content = content.replace("@@" + rules_pycross_canonical + "//pycross/", "@rules_pycross//pycross/")
                    dest = "{}/{}.golden".format(prefix, rel_path)
                    rctx.file(dest, content, executable = False)
                    manifest.append(dest)

    manifest = sorted(manifest)
    rctx.file("manifest.txt", "\n".join(manifest) + "\n", executable = False)

    exported = ["manifest.txt"] + manifest
    build_lines = [
        'package(default_visibility = ["//visibility:public"])',
        "",
        "exports_files([",
    ]
    for path in exported:
        build_lines.append("    {},".format(json.encode(path)))
    build_lines.extend([
        "])",
        "",
        "filegroup(",
        '    name = "all_goldens",',
        "    srcs = [",
    ])
    for path in exported:
        build_lines.append("        {},".format(json.encode(path)))
    build_lines.extend([
        "    ],",
        ")",
        "",
    ])
    rctx.file("BUILD.bazel", "\n".join(build_lines), executable = False)

    if hasattr(rctx, "repo_metadata"):
        return rctx.repo_metadata(reproducible = True)
    return None

golden_snapshot_repo = repository_rule(
    implementation = _golden_snapshot_repo_impl,
    attrs = {
        "repo_roots": attr.label_keyed_string_dict(
            mandatory = True,
            doc = "Maps each source repo's REPO.bazel label to its snapshot destination prefix.",
        ),
        "apparent_names": attr.string_dict(
            mandatory = True,
            doc = "Maps each snapshot destination prefix to the source repo's apparent name.",
        ),
    },
)

def _register_case(
        module_ctx,
        repo_roots,
        apparent_names,
        case_name,
        members,
        build_repo = None,
        backend_names = None,
        skip_variant_members = None):
    """Instantiate state_repo + spoke_repo(s) + thin_package_repo(s) for one golden case."""
    workspace_name = "golden_{}".format(case_name)
    ws_state_repo = state_repo_name(workspace_name)
    merged_repo_map = {}
    member_locks = []
    member_locks_by_name = {}

    for member in members:
        member_name = member["repo_name"]
        lock_label_str = member["lock_file"]
        raw = module_ctx.read(module_ctx.path(Label(lock_label_str)))
        lock_data = json.decode(raw)
        merged_repo_map.update(_build_repo_map(lock_data))
        member_locks.append((member_name, lock_data))
        member_locks_by_name[member_name] = lock_data

    merged_lock = merge_workspace_locks(
        member_locks,
        skip_variant_members = skip_variant_members,
    )
    merged_packages = merged_lock["packages"]
    fork_slots = assign_fork_slots(merged_packages)

    sdist_repo_map = {}
    for pkg_key, pkg in sorted(merged_packages.items()):
        if pkg.get("build_target") or sdist_builds_disallowed(pkg):
            continue
        if not pkg.get("sdist_file"):
            continue
        slot = fork_slots.get(pkg_key, "")
        sdist_repo_map[pkg_key] = "@{}//:wheel".format(sdist_slot_repo_name(workspace_name, pkg_key, slot))

    variant_sets = merged_lock.get("variant_sets", [])
    norm_variants = normalize_workspace_variants(variant_sets)
    has_variants = bool(norm_variants.sets_by_suffix)
    state_payload = {}
    for field in ("variant_items", "variant_sets", "member_variant_flags"):
        val = merged_lock.get(field)
        if val:
            state_payload[field] = val
    known_base_packages = sorted({
        pypackaging.utils.canonicalize_name(parse_package_key(k).name): True
        for k in merged_packages.keys()
        if not parse_package_key(k).extra
    }.keys())

    state_attrs = dict(
        name = ws_state_repo,
        build_repo = build_repo or "golden_{}__build".format(case_name),
        known_base_packages = known_base_packages,
    )
    if backend_names:
        state_attrs["backend_names"] = backend_names
    if state_payload:
        state_attrs["state_data"] = json.encode(state_payload)
    state_repo(**state_attrs)

    state_prefix = "{}/state".format(case_name)
    repo_roots["@{}//:REPO.bazel".format(ws_state_repo)] = state_prefix
    apparent_names[state_prefix] = ws_state_repo

    reset_states = (
        compute_workspace_reset_states(
            merged_packages,
            merged_repo_map,
            conflict_pairs(norm_variants.sets_by_suffix.values()),
            workspace_name,
            fork_slots,
        ) if has_variants else None
    )
    spokes = build_spoke_payloads(
        workspace_name,
        ws_state_repo,
        merged_packages,
        merged_repo_map,
        sdist_repo_map,
        fork_slots,
        cycle_groups = merged_lock.get("cycle_groups"),
        has_variants = has_variants,
        reset_states = reset_states,
    )
    for canon_name, spoke in spokes.items():
        spoke_repo(
            name = spoke.spoke_repo,
            spoke_data = json.encode(spoke.payload),
        )
        spoke_prefix = "{}/pkg_{}".format(case_name, underscore_name(canon_name))
        repo_roots["@{}//:REPO.bazel".format(spoke.spoke_repo)] = spoke_prefix
        apparent_names[spoke_prefix] = spoke.spoke_repo

    for member in members:
        member_name = member["repo_name"]
        thin_attrs = dict(
            name = member_name,
            lock_data = json.encode(slim_member_lock(
                member_locks_by_name[member_name],
                merged_packages,
                fork_slots = fork_slots,
            )),
            workspace_name = workspace_name,
            member_name = member_name,
        )
        if member.get("backend_names"):
            thin_attrs["backend_names"] = member["backend_names"]
        if member.get("flags"):
            thin_attrs["flags"] = member["flags"]
        if member.get("settings"):
            thin_attrs["settings"] = member["settings"]
        if member.get("constraint_values"):
            thin_attrs["constraint_values"] = member["constraint_values"]
        if member.get("platform"):
            thin_attrs["platform"] = member["platform"]
        if member.get("variant_pins"):
            thin_attrs["variant_pins"] = member["variant_pins"]
        if "expose_variant_flags" in member:
            thin_attrs["expose_variant_flags"] = member["expose_variant_flags"]
        thin_package_repo(**thin_attrs)

        thin_prefix = "{}/{}".format(case_name, member["snapshot_dir"])
        repo_roots["@{}//:REPO.bazel".format(member_name)] = thin_prefix
        apparent_names[thin_prefix] = member_name

def _golden_snapshot_repos_impl(module_ctx):
    repo_roots = {}
    apparent_names = {}

    _register_case(
        module_ctx,
        repo_roots,
        apparent_names,
        case_name = "plain",
        backend_names = _SAMPLE_BACKEND_NAMES,
        members = [
            {
                "repo_name": "golden_plain",
                "snapshot_dir": "thin",
                "lock_file": "//tests/golden/fixtures:plain.json",
                "backend_names": _SAMPLE_BACKEND_NAMES,
            },
        ],
    )

    _register_case(
        module_ctx,
        repo_roots,
        apparent_names,
        case_name = "extras",
        members = [
            {
                "repo_name": "golden_extras",
                "snapshot_dir": "thin",
                "lock_file": "//tests/golden/fixtures:extras.json",
            },
        ],
    )

    _register_case(
        module_ctx,
        repo_roots,
        apparent_names,
        case_name = "cycle",
        members = [
            {
                "repo_name": "golden_cycle",
                "snapshot_dir": "thin",
                "lock_file": "//tests/golden/fixtures:cycle.json",
            },
        ],
    )

    _register_case(
        module_ctx,
        repo_roots,
        apparent_names,
        case_name = "forks",
        members = [
            {
                "repo_name": "golden_forks",
                "snapshot_dir": "thin",
                "lock_file": "//tests/golden/fixtures:forks.json",
                "constraint_values": [
                    "@platforms//os:linux",
                    "@platforms//cpu:x86_64",
                ],
            },
        ],
    )

    _register_case(
        module_ctx,
        repo_roots,
        apparent_names,
        case_name = "overlapping_conflicts",
        members = [
            {
                "repo_name": "golden_overlapping_conflicts",
                "snapshot_dir": "thin_default",
                "lock_file": "//tests/golden/fixtures:overlapping_conflicts_default.json",
            },
            {
                "repo_name": "golden_overlapping_conflicts_pinned",
                "snapshot_dir": "thin_pinned",
                "lock_file": "//tests/golden/fixtures:overlapping_conflicts_pinned.json",
                "flags": ["--@golden_overlapping_conflicts_pinned//_variants:group_g-b=True"],
                "variant_pins": {
                    "group_app_g-a_group_app_g-b": "group_app_g-b",
                },
            },
        ],
    )

    _register_case(
        module_ctx,
        repo_roots,
        apparent_names,
        case_name = "sdist_reset",
        build_repo = "golden_sdist_reset__build",
        backend_names = _SAMPLE_BACKEND_NAMES,
        skip_variant_members = ["golden_sdist_reset__build"],
        members = [
            {
                "repo_name": "golden_sdist_reset",
                "snapshot_dir": "thin_main",
                "lock_file": "//tests/golden/fixtures:sdist_reset_main.json",
                "backend_names": _SAMPLE_BACKEND_NAMES,
            },
            {
                "repo_name": "golden_sdist_reset__build",
                "snapshot_dir": "thin_build",
                "lock_file": "//tests/golden/fixtures:sdist_reset_build.json",
                "expose_variant_flags": False,
            },
        ],
    )

    golden_snapshot_repo(
        name = "golden_snapshots",
        repo_roots = repo_roots,
        apparent_names = apparent_names,
    )

golden_snapshot_repos = module_extension(
    implementation = _golden_snapshot_repos_impl,
)
