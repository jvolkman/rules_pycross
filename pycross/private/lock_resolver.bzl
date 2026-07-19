"""Starlark implementation of the raw lock resolver."""

load("@pypackaging.bzl", "pypackaging")
load(":util.bzl", "parse_package_key")

def _file_key(f):
    if not f.get("sha256"):
        fail("PackageFile missing sha256: " + str(f))
    key = "{}/{}".format(f["name"], f["sha256"][:8])
    extra = ""
    if f.get("urls"):
        extra += ",".join(f["urls"])
    if f.get("index"):
        extra += "|" + f["index"]
    if extra:
        h = hash(extra)
        key += "/%x" % (h & 0xffffffff)
    return key

def _resolve_single_version(name, versions_by_name, all_versions, attr_name):
    if "@" in name:
        parts = parse_package_key(name)
        canonical_key = "{}@{}".format(parts.name, parts.version)
        if parts.extra:
            canonical_key = "{}[{}]@{}".format(parts.name, parts.extra, parts.version)

        if canonical_key not in all_versions:
            fail('{} entry "{}" matches no packages'.format(attr_name, name))
        return canonical_key

    parts = parse_package_key(name)
    dep_name = parts.name
    if parts.extra:
        dep_name = "{}[{}]".format(parts.name, parts.extra)

    options = versions_by_name.get(dep_name, [])
    if not options:
        fail('{} entry "{}" matches no packages'.format(attr_name, name))

    if len(options) > 1:
        fail('{} entry "{}" matches multiple packages (choose one): {}'.format(attr_name, name, sorted(options)))

    return options[0]

def _apply_annotation(ann, versions_by_name, all_package_keys):
    build_deps = None
    if "extra_build_tools" in ann:
        build_deps = []
        for dep in ann["extra_build_tools"]:
            resolved_dep = _resolve_single_version(
                dep,
                versions_by_name,
                all_package_keys,
                "extra_build_tools",
            )
            build_deps.append(resolved_dep)

    ignore_deps = {}
    for dep in ann.get("ignore_dependencies", []):
        parts = parse_package_key(dep)
        dep_name = parts.name
        if parts.extra:
            dep_name = "{}[{}]".format(parts.name, parts.extra)
        if dep_name not in versions_by_name and dep not in all_package_keys:
            fail('package_ignore_dependencies entry "{}" matches no packages'.format(dep))
        ignore_deps[dep] = True

    return struct(
        extra_build_tools = build_deps,
        build_tools_repo = ann.get("build_tools_repo"),
        build_target = ann.get("build_target"),
        always_build = ann.get("always_build", False),
        ignore_dependencies = ignore_deps,
        install_exclude_globs = {g: True for g in ann.get("install_exclude_globs", [])},
        post_install_patches = ann.get("post_install_patches", []),
        pre_build_patches = ann.get("pre_build_patches", []),
        site_hooks = ann.get("site_hooks", []),
        build_backend = ann.get("build_backend"),
        site_paths = ann.get("site_paths", []),
        bin_paths = ann.get("bin_paths", []),
        data_paths = ann.get("data_paths", []),
        include_paths = ann.get("include_paths", []),
        wheel_library_tags = ann.get("wheel_library_tags", []),
    )

def _collect_package_annotations(annotations_data, versions_by_name, all_package_keys):
    annotations = {}

    wildcard_annotation = annotations_data.get("*")
    specific_annotations = {}
    for k, v in annotations_data.items():
        if k != "*":
            specific_annotations[k] = v

    specific_keys = {}
    for pkg, ann in specific_annotations.items():
        resolved_pkg = _resolve_single_version(
            pkg,
            versions_by_name,
            all_package_keys,
            "annotations",
        )
        annotations[resolved_pkg] = _apply_annotation(ann, versions_by_name, all_package_keys)
        specific_keys[resolved_pkg] = True

    wildcard_only_keys = {}
    if wildcard_annotation:
        for pkg_key in all_package_keys:
            if pkg_key not in specific_keys:
                annotations[pkg_key] = _apply_annotation(wildcard_annotation, versions_by_name, all_package_keys)
                wildcard_only_keys[pkg_key] = True

    return annotations, wildcard_only_keys

def _create_package_resolver(pkg_key, pkg, ann, default_extra_build_tools, context):
    parts = parse_package_key(pkg_key)
    pkg_name = parts.name
    pkg_version = parts.version
    pkg_extra = parts.extra

    package_sources = {}
    for f in pkg.get("files", []):
        existing = package_sources.get(f["name"])
        if existing != None and "file" in existing:
            existing_file = existing["file"]

            # Two files sharing a name but not a hash cannot be silently
            # collapsed: keeping whichever entry is seen last makes wheel
            # selection non-deterministic and is a supply-chain hazard. This
            # commonly happens when a package is listed under more than one
            # index. Fail and require the user to disambiguate. Multiple sdists
            # with the same name are left unhandled.
            if existing_file["name"].endswith(".whl") and existing_file.get("sha256") != f.get("sha256"):
                fail(
                    ("package {name}=={version} has multiple distinct files named {filename} " +
                     "(sha256 {existing_sha} vs {new_sha}). This usually means the package is " +
                     "listed under more than one index with different content; pin the package " +
                     "to a single index to resolve the ambiguity.").format(
                        name = pkg_name,
                        version = pkg_version,
                        filename = repr(f["name"]),
                        existing_sha = existing_file.get("sha256"),
                        new_sha = f.get("sha256"),
                    ),
                )
        package_sources[f["name"]] = {"file": f}

    pkg_key_no_extra = "{}@{}".format(pkg_name, pkg_version)
    for filename, f in context.remote_wheels.get(pkg_key_no_extra, {}).items():
        package_sources[filename] = {"file": f}

    for filename, label in context.local_wheels.get(pkg_key_no_extra, {}).items():
        package_sources[filename] = {"label": label}

    wheel_candidates = []
    wheel_candidate_files = {}
    for filename, source in sorted(package_sources.items()):
        if not filename.endswith(".whl"):
            continue

        file_ref = None
        if "label" in source:
            file_ref = {"label": source["label"]}
        elif "file" in source:
            f = source["file"]
            fk = _file_key(f)
            file_ref = {"key": fk}
            wheel_candidate_files[fk] = f

        wheel_candidates.append({
            "filename": filename,
            "file_reference": file_ref,
        })

    sdist_file = None
    sdist_file_obj = None
    for f in pkg.get("files", []):
        if not f["name"].endswith(".whl"):
            sdist_file = {"key": _file_key(f)}
            sdist_file_obj = f
            break

    extra_build_tools = []
    all_dependency_keys = []
    ann_build_deps = ann.extra_build_tools if ann else None
    ann_ignore_deps = ann.ignore_dependencies if ann else {}

    normal_deps = {"{}@{}".format(d["name"], d["version"]): True for d in pkg.get("dependencies", [])}

    if ann_build_deps != None:
        for dep_key in ann_build_deps:
            if dep_key not in normal_deps:
                extra_build_tools.append(dep_key)
                all_dependency_keys.append(dep_key)
    else:
        for dep_key in default_extra_build_tools:
            parts = parse_package_key(dep_key)
            dep_name = parts.name
            if parts.extra:
                dep_name = "{}[{}]".format(parts.name, parts.extra)
            if dep_name not in ann_ignore_deps and dep_key not in normal_deps:
                extra_build_tools.append(dep_key)
                all_dependency_keys.append(dep_key)

    dependencies = []
    marker_dependencies = []
    for dep in pkg.get("dependencies", []):
        dep_key = "{}@{}".format(dep["name"], dep["version"])
        parts = parse_package_key(dep_key)
        dep_name = parts.name
        if parts.extra:
            dep_name = "{}[{}]".format(parts.name, parts.extra)
        if dep_name not in ann_ignore_deps:
            dependencies.append(dep)
            marker_dependencies.append({
                "key": dep_key,
                "marker": dep.get("marker", ""),
            })
            all_dependency_keys.append(dep_key)

    always_build = ann.always_build if ann else False
    build_target = ann.build_target if ann else None
    uses_sdist = always_build or (context.always_include_sdist and sdist_file != None) or not wheel_candidates

    if not pkg_extra and not wheel_candidates and sdist_file == None and not build_target:
        fail("Package {} has no compatible wheels and no sdist found.".format(pkg_key))

    # When always_build or build_target is set, the user explicitly wants the
    # sdist/build_target used rather than pre-built wheels from the registry.
    # Clear wheel_candidates so the renderer aliases directly to the sdist target
    # instead of rendering a wheel chooser that would prefer matching PyPI wheels.
    if always_build or build_target:
        wheel_candidates = []

    resolved_pkg = {
        "key": pkg_key,
        "name": pkg_name,
        "version": pkg_version,
        "extra": pkg_extra,
        "python_versions": pkg.get("python_versions", ""),
        "dependencies": dependencies,
        "marker_dependencies": marker_dependencies,
        "files": pkg.get("files", []),
        "sdist_file": sdist_file,
        "build_target": build_target,
        "build_tools_repo": ann.build_tools_repo if ann else None,
        "always_build": always_build,
        "extra_build_tools": extra_build_tools,
        "install_exclude_globs": list(ann.install_exclude_globs.keys()) if ann else [],
        "post_install_patches": ann.post_install_patches if ann else [],
        "pre_build_patches": ann.pre_build_patches if ann else [],
        "site_hooks": ann.site_hooks if ann else [],
        "build_backend": ann.build_backend if ann else None,
        "site_paths": ann.site_paths if ann else [],
        "bin_paths": ann.bin_paths if ann else [],
        "data_paths": ann.data_paths if ann else [],
        "include_paths": ann.include_paths if ann else [],
        "wheel_library_tags": ann.wheel_library_tags if ann else [],
        "wheel_candidates": wheel_candidates,
        "uses_sdist": uses_sdist,
    }

    return struct(
        resolved_package = resolved_pkg,
        all_dependency_keys = all_dependency_keys,
        wheel_candidate_files = wheel_candidate_files,
        sdist_file_obj = sdist_file_obj,
        uses_sdist = uses_sdist,
        key = pkg_key,
    )

def _resolve_packages(
        lock_model_packages,
        pins,
        context,
        annotations,
        default_extra_build_tools,
        wildcard_only_keys):
    work_set = {k: True for k in lock_model_packages.keys()}
    for pin_dict in pins.values():
        for pkg_key in pin_dict.values():
            work_set[pkg_key] = True
    work = work_set.keys()

    packages_by_package_key = {}
    synthesized_packages = {}

    # Starlark has no while loops, so we simulate one with for+range+break.
    # Each package key is processed at most once; duplicates are skipped.
    # Total iterations = initial worklist items + edges traversed.
    # Synthesized extra packages duplicate their base package's edges,
    # so the graph traversal portion can be up to 2 * (V + E).
    num_edges = 0
    for pkg in lock_model_packages.values():
        num_edges += len(pkg.get("dependencies", []))
    max_iters = len(work) + 2 * (len(lock_model_packages) + num_edges)

    for _ in range(max_iters):
        if len(work) == 0:
            break
        next_package_key = work.pop()
        if next_package_key in packages_by_package_key:
            continue

        raw_pkg = lock_model_packages.get(next_package_key) or synthesized_packages.get(next_package_key)
        if not raw_pkg:
            parts = parse_package_key(next_package_key)
            if parts.extra:
                base_key = "{}@{}".format(parts.name, parts.version)
                base_package = lock_model_packages.get(base_key) or synthesized_packages.get(base_key)
                if not base_package:
                    fail("Missing base package {} for extra {}".format(base_key, next_package_key))

                base_deps = base_package.get("dependencies", [])
                synthesized_deps = list(base_deps) + [{
                    "name": parts.name,
                    "version": parts.version,
                    "marker": "",
                }]
                raw_pkg = {
                    "name": parts.name,
                    "version": parts.version,
                    "python_versions": base_package.get("python_versions", ""),
                    "dependencies": synthesized_deps,
                    "files": [],
                }
                synthesized_packages[next_package_key] = raw_pkg
            else:
                fail("Missing package {}".format(next_package_key))

        ann = annotations.pop(next_package_key, None)
        entry = _create_package_resolver(
            next_package_key,
            raw_pkg,
            ann,
            default_extra_build_tools,
            context,
        )
        packages_by_package_key[next_package_key] = entry
        work.extend(entry.all_dependency_keys)

    if len(work) > 0:
        fail("Package resolution exceeded max iterations. Remaining work: {}".format(work))

    for key in wildcard_only_keys.keys():
        annotations.pop(key, None)

    if annotations:
        fail("Annotations specified for packages that are not part of the locked set: {}".format(
            ", ".join(sorted(annotations.keys())),
        ))

    for k, v in synthesized_packages.items():
        lock_model_packages[k] = v

    return packages_by_package_key

def _compute_cycle_groups(packages):
    graph = {}
    for pkg_key, pkg in packages.items():
        deps = []
        for dep in pkg.get("dependencies", []):
            dep_key = "{}@{}".format(dep["name"], dep["version"])
            if dep_key in packages:
                deps.append(dep_key)
        graph[pkg_key] = deps

    index_counter = 0
    indices = {}
    lowlink = {}
    on_stack = {}
    stack = []
    sccs = []

    # Starlark has no while loops, so we simulate one with for+range+break.
    # Each iteration either advances an edge index or pops a finished node,
    # so the maximum iterations per DFS traversal is V + E.
    num_edges = 0
    for deps in graph.values():
        num_edges += len(deps)
    max_iters = 2 * len(graph) + num_edges

    for root in graph.keys():
        if root in indices:
            continue

        work_stack = [[root, graph.get(root, []), 0]]
        indices[root] = index_counter
        lowlink[root] = index_counter
        index_counter += 1
        stack.append(root)
        on_stack[root] = True

        for _ in range(max_iters):
            if len(work_stack) == 0:
                break
            frame = work_stack[-1]
            v = frame[0]
            neighbors = frame[1]
            idx = frame[2]

            if idx < len(neighbors):
                w = neighbors[idx]
                frame[2] = idx + 1

                if w not in indices:
                    indices[w] = index_counter
                    lowlink[w] = index_counter
                    index_counter += 1
                    stack.append(w)
                    on_stack[w] = True
                    work_stack.append([w, graph.get(w, []), 0])
                elif w in on_stack:
                    lowlink[v] = min(lowlink[v], indices[w])
            else:
                if lowlink[v] == indices[v]:
                    scc = []

                    # We also need to simulate this while True loop
                    # It runs at most len(stack) times.
                    for _ in range(len(stack) + 1):
                        w = stack.pop()
                        on_stack.pop(w)
                        scc.append(w)
                        if w == v:
                            break
                    sccs.append(scc)

                work_stack.pop()
                if len(work_stack) > 0:
                    parent = work_stack[-1][0]
                    lowlink[parent] = min(lowlink[parent], lowlink[v])

        if len(work_stack) > 0:
            fail("DFS traversal for SCC exceeded max iterations. Remaining stack: {}".format(work_stack))

    cycle_groups = {}
    for scc in sccs:
        if len(scc) <= 1:
            continue
        members = sorted(scc)
        h = hash("\n".join(members))
        group_name = "group_%x" % (h & 0xffffffff)
        cycle_groups[group_name] = members

    return cycle_groups

def _compute_reachable_keys(pins, packages_by_package_key):
    """Compute the set of package keys transitively reachable from pins."""
    work = []
    for pin_dict in pins.values():
        work.extend(pin_dict.values())

    num_edges = 0
    for entry in packages_by_package_key.values():
        num_edges += len(entry.all_dependency_keys)

    max_iters = len(work) + num_edges + len(packages_by_package_key)

    reachable = {}
    for _ in range(max_iters):
        if not work:
            break
        key = work.pop()
        if key in reachable:
            continue
        reachable[key] = True
        entry = packages_by_package_key.get(key)
        if entry:
            work.extend(entry.all_dependency_keys)

    if len(work) > 0:
        fail("Reachable keys traversal exceeded max iterations. Remaining work: {}".format(work))

    return reachable

def resolve(
        lock_model_data,
        local_wheels = None,
        remote_wheels = None,
        always_include_sdist = False,
        annotations_data = None,
        default_extra_build_tools_args = None,
        include_transitive = False,
        transitive_testonly = False):
    """Resolves dependencies from lock model data.

    Args:
        lock_model_data: The lock model data.
        local_wheels: Dictionary of local wheels.
        remote_wheels: Dictionary of remote wheels.
        always_include_sdist: Whether to always include sdist.
        annotations_data: Annotations data.
        default_extra_build_tools_args: Default extra build tools args.
        include_transitive: Whether to include transitive dependencies.
        transitive_testonly: Whether to perform reachability analysis to assign testonly status.

    Returns:
        Dictionary of resolved packages.
    """
    local_wheels = local_wheels or {}
    remote_wheels = remote_wheels or {}
    if type(local_wheels) != "dict":
        fail("local_wheels must be a dict (filename -> label), got {}".format(type(local_wheels)))
    if type(remote_wheels) != "dict":
        fail("remote_wheels must be a dict (url -> sha256), got {}".format(type(remote_wheels)))
    default_extra_build_tools_args = default_extra_build_tools_args or []
    local_wheels_by_pkg = {}
    for filename, label in local_wheels.items():
        parsed = pypackaging.utils.parse_wheel_filename(filename)
        name = pypackaging.utils.canonicalize_name(parsed.name)
        version = parsed.version.version_str
        pkg_key = "{}@{}".format(name, version)
        if pkg_key not in local_wheels_by_pkg:
            local_wheels_by_pkg[pkg_key] = {}
        local_wheels_by_pkg[pkg_key][filename] = label

    remote_wheels_by_pkg = {}
    for url, sha256 in remote_wheels.items():
        filename = url.split("/")[-1]
        parsed = pypackaging.utils.parse_wheel_filename(filename)
        name = pypackaging.utils.canonicalize_name(parsed.name)
        version = parsed.version.version_str
        pkg_key = "{}@{}".format(name, version)
        if pkg_key not in remote_wheels_by_pkg:
            remote_wheels_by_pkg[pkg_key] = {}
        remote_wheels_by_pkg[pkg_key][filename] = {
            "name": filename,
            "sha256": sha256,
            "urls": [url],
        }

    context = struct(
        local_wheels = local_wheels_by_pkg,
        remote_wheels = remote_wheels_by_pkg,
        always_include_sdist = always_include_sdist,
    )

    lock_model_packages = lock_model_data.get("packages", {})
    all_package_keys = lock_model_packages.keys()

    versions_by_name = {}
    locked_versions_by_simple_name = {}
    for pkg_key in all_package_keys:
        parts = parse_package_key(pkg_key)

        if parts.name not in locked_versions_by_simple_name:
            locked_versions_by_simple_name[parts.name] = []
        if parts.version not in locked_versions_by_simple_name[parts.name]:
            locked_versions_by_simple_name[parts.name].append(parts.version)

        dep_name = parts.name
        if parts.extra:
            dep_name = "{}[{}]".format(parts.name, parts.extra)
        if dep_name not in versions_by_name:
            versions_by_name[dep_name] = []
        versions_by_name[dep_name].append(pkg_key)

    # Warn about local wheels that don't match locked packages
    for pkg_key, filenames in local_wheels_by_pkg.items():
        parts = parse_package_key(pkg_key)
        name = parts.name
        version = parts.version

        if name not in locked_versions_by_simple_name:
            for filename in filenames.keys():
                # buildifier: disable=print
                print("WARNING: Local wheel {} does not match any package in the lock file.".format(filename))
        elif version not in locked_versions_by_simple_name[name]:
            for filename in filenames.keys():
                # buildifier: disable=print
                print("WARNING: Local wheel {} matches package {} but version {} does not match locked versions: {}.".format(
                    filename,
                    name,
                    version,
                    locked_versions_by_simple_name[name],
                ))

    annotations = {}
    wildcard_only_keys = {}
    if annotations_data:
        annotations, wildcard_only_keys = _collect_package_annotations(
            annotations_data,
            versions_by_name,
            all_package_keys,
        )

    default_extra_build_tools = []
    for dep in default_extra_build_tools_args:
        resolved_dep = _resolve_single_version(
            dep,
            versions_by_name,
            all_package_keys,
            "extra_build_tools",
        )
        default_extra_build_tools.append(resolved_dep)

    raw_pins = lock_model_data.get("pins", {})
    pins = {}
    for k, v in raw_pins.items():
        name = parse_package_key(k).name
        if type(v) == "string":
            pins[name] = {"": v}
        else:
            pins[name] = v

    packages_by_package_key = _resolve_packages(
        lock_model_packages,
        pins,
        context,
        annotations,
        default_extra_build_tools,
        wildcard_only_keys,
    )

    resolved_keys = sorted(packages_by_package_key.keys())
    resolved_packages = [packages_by_package_key[k] for k in resolved_keys]

    repos = {}
    for entry in resolved_packages:
        repos.update(entry.wheel_candidate_files)
        if entry.resolved_package["sdist_file"] and entry.sdist_file_obj:
            repos[entry.resolved_package["sdist_file"]["key"]] = entry.sdist_file_obj

    sorted_repo_keys = sorted(repos.keys())
    repos = {k: repos[k] for k in sorted_repo_keys}

    testonly_pin_names = lock_model_data.get("testonly_pins", [])
    testonly_pins_set = {p: True for p in testonly_pin_names}

    if include_transitive:
        reachable_keys = _compute_reachable_keys(pins, packages_by_package_key)
        resolved_versions_by_name = {}
        for entry in resolved_packages:
            if entry.key not in reachable_keys:
                continue
            pkg_name = entry.resolved_package["name"]
            pkg_version = entry.resolved_package["version"]
            if pkg_name not in resolved_versions_by_name:
                resolved_versions_by_name[pkg_name] = {}
            resolved_versions_by_name[pkg_name][pkg_version] = True

        for package_pin_name, versions in resolved_versions_by_name.items():
            if package_pin_name in pins:
                continue
            if len(versions) > 1:
                version_tuples = [(pypackaging.version.parse(v).key, v) for v in versions.keys()]
                latest_version = sorted(version_tuples)[-1][1]

                # buildifier: disable=print
                print("WARNING: Multiple versions of {} found in transitive dependencies. Aliasing to latest: {}".format(package_pin_name, latest_version))
                base_key = "{}@{}".format(package_pin_name, latest_version)
                if base_key in packages_by_package_key:
                    pins[package_pin_name] = {"": base_key}
                    if transitive_testonly:
                        testonly_pins_set[package_pin_name] = True
                continue
            version = versions.keys()[0]
            base_key = "{}@{}".format(package_pin_name, version)
            if base_key in packages_by_package_key:
                pins[package_pin_name] = {"": base_key}
                if transitive_testonly:
                    testonly_pins_set[package_pin_name] = True

    testonly_pin_names = sorted(testonly_pins_set.keys())

    cycle_groups = _compute_cycle_groups(lock_model_packages)

    resolved_packages_dict = {pkg.key: pkg.resolved_package for pkg in resolved_packages}
    for group_name, scc in cycle_groups.items():
        for pkg_key in scc:
            if pkg_key in resolved_packages_dict:
                resolved_packages_dict[pkg_key]["cycle_group"] = group_name

    return struct(
        packages = resolved_packages_dict,
        pins = pins,
        remote_files = repos,
        cycle_groups = cycle_groups,
        variants = lock_model_data.get("variants", []),
        resolution_marker_exprs = lock_model_data.get("resolution_marker_exprs", {}),
        testonly_pins = testonly_pin_names,
    )
