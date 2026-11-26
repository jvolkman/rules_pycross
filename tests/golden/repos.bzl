"""Dev-only module extension generating golden snapshots of package_repo and thin_package_repo outputs."""

# buildifier: disable=bzl-visibility
load("//pycross/private:package_repo.bzl", "package_repo")

# buildifier: disable=bzl-visibility
load("//pycross/private:thin_package_repo.bzl", "thin_package_repo")

_SAMPLE_BACKEND_CONFIGS = {
    "pep517_build": json.encode({
        "rule_bzl": "@rules_pycross//pycross/backends:pep517.bzl",
        "tool_packages": [],
    }),
    "setuptools_build": json.encode({
        "rule_bzl": "@rules_pycross//pycross/backends:setuptools.bzl",
        "tool_packages": ["setuptools", "wheel"],
    }),
}

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
    """Collect generated files from package_repo and thin_package_repo instances into a snapshot repo."""

    # Build (canonical_repo_name, apparent_repo_name) pairs, longest canonical first
    # so e.g. `golden_plain__pkgs` is replaced before `golden_plain`.
    normalizations = []
    for repo_label, prefix in rctx.attr.repo_roots.items():
        apparent = rctx.attr.apparent_names[prefix]
        canonical = repo_label.repo_name
        if canonical and canonical != apparent:
            normalizations.append((canonical, apparent))
    normalizations = sorted(normalizations, key = lambda pair: (-len(pair[0]), pair[0]))

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
        backend_configs = None,
        skip_variant_members = None):
    """Instantiate package_repo + thin_package_repo(s) for one golden case."""
    pkgs_repo = "golden_{}__pkgs".format(case_name)
    merged_repo_map = {}
    member_lock_files = {}
    member_lock_data = {}

    for member in members:
        member_name = member["repo_name"]
        lock_label_str = member["lock_file"]
        raw = module_ctx.read(module_ctx.path(Label(lock_label_str)))
        lock_data = json.decode(raw)
        merged_repo_map.update(_build_repo_map(lock_data))
        member_lock_files[member_name] = lock_label_str
        member_lock_data[member_name] = raw

    pkg_attrs = dict(
        name = pkgs_repo,
        build_repo = build_repo or "golden_{}__build".format(case_name),
        repo_map = merged_repo_map,
        member_lock_files = member_lock_files,
        member_lock_data = member_lock_data,
    )
    if backend_configs:
        pkg_attrs["backend_configs"] = backend_configs
    if skip_variant_members:
        pkg_attrs["skip_variant_members"] = skip_variant_members
    package_repo(**pkg_attrs)

    pkgs_prefix = "{}/pkgs".format(case_name)
    repo_roots["@{}//:REPO.bazel".format(pkgs_repo)] = pkgs_prefix
    apparent_names[pkgs_prefix] = pkgs_repo

    for member in members:
        member_name = member["repo_name"]
        thin_attrs = dict(
            name = member_name,
            resolved_lock_file = Label(member["lock_file"]),
            workspace_repo = pkgs_repo,
            member_name = member_name,
        )
        if member.get("backend_configs"):
            thin_attrs["backend_configs"] = member["backend_configs"]
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
        backend_configs = _SAMPLE_BACKEND_CONFIGS,
        members = [
            {
                "repo_name": "golden_plain",
                "snapshot_dir": "thin",
                "lock_file": "//tests/golden/fixtures:plain.json",
                "backend_configs": _SAMPLE_BACKEND_CONFIGS,
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
        backend_configs = _SAMPLE_BACKEND_CONFIGS,
        skip_variant_members = ["golden_sdist_reset__build"],
        members = [
            {
                "repo_name": "golden_sdist_reset",
                "snapshot_dir": "thin_main",
                "lock_file": "//tests/golden/fixtures:sdist_reset_main.json",
                "backend_configs": _SAMPLE_BACKEND_CONFIGS,
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
