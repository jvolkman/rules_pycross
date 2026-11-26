"""Starlark implementation of the raw lock resolver."""

load("@pypackaging.bzl", "pypackaging")
load(
    ":util.bzl",
    "base_package_key",
    "canonicalize_package_key",
    "format_package_key",
    "parse_package_key",
    "resolution_marker_constraint_name",
)
load(":variant_util.bzl", "variant_item_qname")

# Declarative spec for package() annotation fields passed through to resolved packages:
#   field_name -> (default, mode)
# where `mode` controls tag-to-dict conversion and resolver post-processing:
#   "plain": pass value through unchanged
#   "label": stringify scalar Label during tag conversion
#   "label_list": stringify each Label in a list during tag conversion
#   "dedup": deduplicate list entries while preserving order
# Note: fields consumed by package_repo / lock_render must also be listed in
# package_repo.bzl:_PACKAGE_REPO_PKG_FIELDS.
PASSTHROUGH_PACKAGE_ATTRS = {
    "build_backend": (None, "plain"),
    "build_target": (None, "label"),
    "build_mode": ("auto", "plain"),
    "build_tools_repo": (None, "plain"),
    "install_exclude_globs": ([], "dedup"),
    "post_install_patches": ([], "label_list"),
    "pre_build_patches": ([], "label_list"),
    "site_hooks": ([], "plain"),
    "site_paths": ([], "plain"),
    "bin_paths": ([], "plain"),
    "data_paths": ([], "plain"),
    "include_paths": ([], "plain"),
    "wheel_library_tags": ([], "plain"),
    "precompile": ("", "plain"),
}

def _default_value(default):
    return list(default) if type(default) == "list" else default

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

def _package_source(raw_pkg):
    """Return the human-readable source identifier for a raw lock package, or ''."""
    if raw_pkg.get("source"):
        return raw_pkg["source"]
    for f in raw_pkg.get("files", []):
        if f.get("index"):
            return f["index"]
    for f in raw_pkg.get("files", []):
        urls = f.get("urls", [])
        if urls:
            url = urls[0]
            return url[4:] if url.startswith("git+") else url
    return ""

def _build_pkg_index(all_package_keys):
    """Build lookup indices over locked package keys for annotation and dependency resolution."""
    versions_by_name = {}
    keys_by_name_version = {}
    canonical_to_key = {}
    source_by_key = {}
    locked_versions_by_simple_name = {}
    for pkg_key, raw_pkg in all_package_keys.items():
        parts = parse_package_key(pkg_key)

        if parts.name not in locked_versions_by_simple_name:
            locked_versions_by_simple_name[parts.name] = []
        if parts.version not in locked_versions_by_simple_name[parts.name]:
            locked_versions_by_simple_name[parts.name].append(parts.version)

        canon = canonicalize_package_key(pkg_key)
        canonical_to_key[canon.canonical] = pkg_key
        dep_name = format_package_key(canon.name, extra = canon.extra)
        dep_nv = format_package_key(canon.name, canon.version, extra = canon.extra)
        versions_by_name.setdefault(dep_name, []).append(pkg_key)
        keys_by_name_version.setdefault(dep_nv, []).append(pkg_key)
        src = _package_source(raw_pkg)
        if src:
            source_by_key[pkg_key] = src

    return struct(
        versions_by_name = versions_by_name,
        keys_by_name_version = keys_by_name_version,
        canonical_to_key = canonical_to_key,
        source_by_key = source_by_key,
        all_package_keys = all_package_keys,
        locked_versions_by_simple_name = locked_versions_by_simple_name,
    )

def _lookup_pkg_keys(pkg_index, spec):
    """Canonicalize `spec` and return `(canonical, matching_keys)` from `pkg_index`."""
    parsed = canonicalize_package_key(spec)
    if parsed.has_tag:
        resolved = pkg_index.canonical_to_key.get(parsed.canonical)
        options = [resolved] if resolved else []
    elif parsed.has_version:
        options = list(pkg_index.keys_by_name_version.get(parsed.canonical, []))
    else:
        options = list(pkg_index.versions_by_name.get(parsed.canonical, []))
    return parsed.canonical, options

def _dep_is_ignored(dep_key, ignore_deps):
    """Return True if `dep_key` matches any canonical entry in `ignore_deps`."""
    if not ignore_deps:
        return False
    canon = canonicalize_package_key(dep_key)
    canon_name = format_package_key(canon.name, extra = canon.extra)
    canon_nv = format_package_key(canon.name, canon.version, extra = canon.extra)
    return canon_name in ignore_deps or canon_nv in ignore_deps or canon.canonical in ignore_deps

def _resolve_matching_keys(name, pkg_index, attr_name, source = "", allow_multiple_sources = False):
    """Resolve a package spec (and optional `source`) to one or more locked package keys."""
    _, options = _lookup_pkg_keys(pkg_index, name)

    if not options:
        fail('{} entry "{}" matches no packages'.format(attr_name, name))

    source_by_key = pkg_index.source_by_key
    if source and source != "*":
        filtered = [k for k in options if source_by_key.get(k, "") == source]
        if not filtered:
            available = sorted({source_by_key[k]: True for k in options if source_by_key.get(k)}.keys())
            fail('{} entry "{}" with source "{}" matches no packages (available sources: {})'.format(
                attr_name,
                name,
                source,
                available,
            ))
        options = filtered

    if len(options) > 1:
        unique_versions = {(parse_package_key(k).name, parse_package_key(k).version): True for k in options}
        if allow_multiple_sources and source == "*" and len(unique_versions) == 1:
            return sorted(options)
        if allow_multiple_sources and len(unique_versions) == 1:
            formatted = []
            for k in sorted(options):
                parts = parse_package_key(k)
                display = format_package_key(parts.name, parts.version, extra = parts.extra)
                if source_by_key.get(k):
                    formatted.append('{} (source = "{}")'.format(display, source_by_key[k]))
                else:
                    formatted.append(k)
            fail('{} entry "{}" matches multiple sources (set `source` to choose one, or `source = "*"` for all): {}'.format(attr_name, name, ", ".join(formatted)))
        if any([parse_package_key(k).tag for k in options]):
            formatted = [
                '{} (source = "{}")'.format(k, source_by_key[k]) if source_by_key.get(k) else k
                for k in sorted(options)
            ]
            fail('{} entry "{}" matches multiple packages (choose one): {}'.format(attr_name, name, ", ".join(formatted)))
        fail('{} entry "{}" matches multiple packages (choose one): {}'.format(attr_name, name, sorted(options)))

    return options

def _resolve_single_version(name, pkg_index, attr_name, source = ""):
    return _resolve_matching_keys(
        name,
        pkg_index,
        attr_name,
        source = source,
    )[0]

def _apply_annotation(ann, pkg_index):
    build_deps = [
        _resolve_single_version(dep, pkg_index, "extra_build_tools")
        for dep in ann.get("extra_build_tools", [])
    ]

    ignore_deps = {}
    for dep in ann.get("ignore_dependencies", []):
        canonical, matches = _lookup_pkg_keys(pkg_index, dep)
        if not matches:
            fail('ignore_dependencies entry "{}" matches no packages'.format(dep))
        ignore_deps[canonical] = True

    extra_deps = [
        _resolve_single_version(dep, pkg_index, "extra_dependencies")
        for dep in ann.get("extra_dependencies", [])
    ]

    passthrough = {}
    for field, (default, mode) in PASSTHROUGH_PACKAGE_ATTRS.items():
        val = ann.get(field)
        if not val:
            passthrough[field] = _default_value(default)
        elif mode == "dedup":
            passthrough[field] = list({g: True for g in val}.keys())
        else:
            passthrough[field] = val

    return struct(
        extra_build_tools = build_deps,
        ignore_dependencies = ignore_deps,
        extra_dependencies = extra_deps,
        passthrough = passthrough,
    )

def _collect_package_annotations(annotations_data, pkg_index):
    annotations = {}

    wildcard_annotation = annotations_data.get("*")
    specific_annotations = {k: v for k, v in annotations_data.items() if k != "*"}

    specific_keys = {}
    for pkg, ann in specific_annotations.items():
        pkg_spec = pkg[0] if type(pkg) == "tuple" else pkg
        pkg_source = pkg[1] if type(pkg) == "tuple" else ann.get("source", "")
        resolved_pkgs = _resolve_matching_keys(
            pkg_spec,
            pkg_index,
            "annotations",
            source = pkg_source,
            allow_multiple_sources = True,
        )
        if wildcard_annotation:
            merged = dict(wildcard_annotation)
            merged.update(ann)
        else:
            merged = ann
        applied = _apply_annotation(merged, pkg_index)
        for resolved_pkg in resolved_pkgs:
            if resolved_pkg in specific_keys:
                fail('Multiple annotations match package "{}"'.format(resolved_pkg))
            annotations[resolved_pkg] = applied
            specific_keys[resolved_pkg] = True

    wildcard_only_keys = {}
    if wildcard_annotation:
        resolved_wildcard = None
        for pkg_key in pkg_index.all_package_keys:
            if pkg_key not in specific_keys:
                if resolved_wildcard == None:
                    resolved_wildcard = _apply_annotation(wildcard_annotation, pkg_index)
                annotations[pkg_key] = resolved_wildcard
                wildcard_only_keys[pkg_key] = True

    return annotations, wildcard_only_keys

def _create_package_resolver(pkg_key, pkg, ann, context):
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

    pkg_key_no_extra = base_package_key(pkg_key)
    pkg_name_ver = "{}@{}".format(pkg_name, pkg_version)
    for filename, label in context.local_wheels.get(pkg_name_ver, {}).items():
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
    ann_build_deps = ann.extra_build_tools if ann else []
    ann_ignore_deps = ann.ignore_dependencies if ann else {}

    normal_deps = {d.get("key") or "{}@{}".format(d["name"], d["version"]): True for d in pkg.get("dependencies", [])}

    for dep_key in ann_build_deps:
        if base_package_key(dep_key) == pkg_key_no_extra:
            continue
        if dep_key not in normal_deps:
            extra_build_tools.append(dep_key)
            all_dependency_keys.append(dep_key)

    marker_dependencies = []
    for dep in pkg.get("dependencies", []):
        dep_key = dep.get("key") or "{}@{}".format(dep["name"], dep["version"])
        if _dep_is_ignored(dep_key, ann_ignore_deps):
            continue
        marker_dependencies.append({
            "key": dep_key,
            "marker": dep.get("marker", ""),
        })
        all_dependency_keys.append(dep_key)

    ann_extra_deps = ann.extra_dependencies if ann else []
    for dep_key in ann_extra_deps:
        if base_package_key(dep_key) == pkg_key_no_extra:
            continue
        if dep_key not in normal_deps:
            marker_dependencies.append({
                "key": dep_key,
                "marker": "",
            })
            all_dependency_keys.append(dep_key)

    passthrough = ann.passthrough if ann else None
    build_mode = passthrough["build_mode"] if passthrough else "auto"
    always_build = build_mode == "always"
    build_target = passthrough["build_target"] if passthrough else None

    if not pkg_extra and not wheel_candidates and sdist_file == None and not build_target:
        fail("Package {} has no compatible wheels and no sdist found.".format(pkg_key))

    # When build_mode = "always" or build_target is set, the user explicitly wants the
    # sdist/build_target used rather than pre-built wheels from the registry.
    # Clear wheel_candidates and wheel_candidate_files so the renderer aliases
    # directly to the sdist/build_target and lock_repo_creation does not
    # instantiate unused pycross_wheel_file repos or leak dead entries into
    # package_repo.repo_map.
    if always_build or build_target:
        wheel_candidates = []
        wheel_candidate_files = {}

    if not pkg_extra and always_build and sdist_file == None and not build_target:
        fail("Package {} has build_mode = \"always\" but no sdist to build from.".format(pkg_key))

    # Markers under which the root projects request this exact pin; see
    # record_root_marker in translator_common.bzl for the semantics.
    root_pin_name = pkg_name
    if pkg_extra:
        root_pin_name = "{}[{}]".format(pkg_name, pkg_extra)
    availability_markers = context.root_dependency_markers.get(root_pin_name, [])

    resolved_pkg = {
        "name": pkg_name,
        "version": pkg_version,
        "marker_dependencies": marker_dependencies,
        "sdist_file": sdist_file,
        "extra_build_tools": extra_build_tools,
        "wheel_candidates": wheel_candidates,
        "availability_markers": availability_markers,
    }
    for field, (default, _) in PASSTHROUGH_PACKAGE_ATTRS.items():
        resolved_pkg[field] = passthrough[field] if passthrough else _default_value(default)
    if pkg.get("source_dir"):
        resolved_pkg["source_dir"] = pkg["source_dir"]

    return struct(
        resolved_package = resolved_pkg,
        all_dependency_keys = all_dependency_keys,
        wheel_candidate_files = wheel_candidate_files,
        sdist_file_obj = sdist_file_obj,
        key = pkg_key,
    )

def _synthesize_extra_package(next_package_key, lock_model_packages, synthesized_packages):
    parts = parse_package_key(next_package_key)
    if not parts.extra:
        fail("Missing package {}".format(next_package_key))

    base_key = base_package_key(next_package_key)
    base_package = lock_model_packages.get(base_key) or synthesized_packages.get(base_key)
    if not base_package:
        fail("Missing base package {} for extra {}".format(base_key, next_package_key))

    base_deps = base_package.get("dependencies", [])
    base_self_dep = {
        "name": parts.name,
        "version": parts.version,
        "marker": "",
    }
    if parts.tag:
        base_self_dep["key"] = base_key
    synthesized_deps = list(base_deps) + [base_self_dep]
    raw_pkg = {
        "name": parts.name,
        "version": parts.version,
        "dependencies": synthesized_deps,
        "files": [],
    }
    if base_package.get("source"):
        raw_pkg["source"] = base_package["source"]
    synthesized_packages[next_package_key] = raw_pkg
    return raw_pkg

def _resolve_packages(
        lock_model_packages,
        pins,
        context,
        annotations,
        wildcard_only_keys):
    work_set = {k: True for k in lock_model_packages.keys()}
    for pin_dict in pins.values():
        for pkg_key in pin_dict.values():
            work_set[pkg_key] = True
    enqueued = dict(work_set)
    work = work_set.keys()

    packages_by_package_key = {}
    synthesized_packages = {}

    # Starlark has no while loops, so we simulate one with for+range+break.
    # Because `enqueued` prevents pushing any package key more than once, each
    # iteration pops a distinct key. The total number of distinct keys is
    # bounded by initial keys + all distinct dep keys referenced by lock
    # packages and annotations.
    extra_refs = 0
    for pkg in lock_model_packages.values():
        extra_refs += len(pkg.get("dependencies", []))
    for ann in annotations.values():
        extra_refs += len(ann.extra_dependencies) + len(ann.extra_build_tools)
    max_iters = len(work) + extra_refs + 1

    for _ in range(max_iters):
        if len(work) == 0:
            break
        next_package_key = work.pop()
        if next_package_key in packages_by_package_key:
            continue

        raw_pkg = lock_model_packages.get(next_package_key) or synthesized_packages.get(next_package_key)
        if not raw_pkg:
            raw_pkg = _synthesize_extra_package(
                next_package_key,
                lock_model_packages,
                synthesized_packages,
            )

        ann = annotations.pop(next_package_key, None)
        entry = _create_package_resolver(
            next_package_key,
            raw_pkg,
            ann,
            context,
        )
        packages_by_package_key[next_package_key] = entry
        for dep_key in entry.all_dependency_keys:
            if dep_key not in enqueued:
                enqueued[dep_key] = True
                work.append(dep_key)

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

def _compute_cycle_groups(resolved_packages_dict):
    """Detect strongly connected components on resolved marker_dependencies."""
    graph = {}
    for pkg_key, pkg in resolved_packages_dict.items():
        deps = []
        seen = {}
        for md in pkg.get("marker_dependencies", []):
            dep_key = md["key"]
            if dep_key in resolved_packages_dict and dep_key not in seen:
                seen[dep_key] = True
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
                continue

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

def _add_ungated_fallbacks(pins, lock_model_data):
    """Add an unconditional ("") branch to pins whose branches are all conflict-variant gated.

    The `<ws>__build` repo serves sdist builds from every repo of the workspace, so a tool
    that the lock only pins under one variant (e.g. a direct dependency of one of two
    conflicting projects) must still resolve when another variant, or none, is selected.
    The fallback is the pin's single version, or its highest one.
    """
    variant_qnames = {}
    for variant_set in lock_model_data.get("variants", []):
        for item in variant_set["items"]:
            variant_qnames[variant_item_qname(item)] = True
    exprs = lock_model_data.get("resolution_marker_exprs", {})

    def is_gated(constraint):
        if constraint in variant_qnames:
            return True
        expr = exprs.get(constraint)
        return type(expr) == "dict" or (type(expr) == "string" and "__variant_" in expr)

    for pin_name, pin in pins.items():
        if type(pin) != "dict" or not pin or [c for c in pin.keys() if not is_gated(c)]:
            continue
        keys = {key: True for key in pin.values()}.keys()
        if len(keys) == 1:
            fallback = keys[0]
        else:
            versioned = [(pypackaging.version.parse(parse_package_key(k).version).key, k) for k in keys]
            fallback = sorted(versioned)[-1][1]

        # Copy: the pin dict can be shared with the caller's lock model data.
        new_pin = dict(pin)
        new_pin[""] = fallback
        pins[pin_name] = new_pin

def resolve(
        lock_model_data,
        local_wheels = None,
        annotations_data = None,
        include_transitive = False,
        transitive_testonly = False,
        ungated_fallback = False):
    """Resolves dependencies from lock model data.

    Args:
        lock_model_data: The lock model data.
        local_wheels: Dictionary of local wheels.
        annotations_data: Annotations data.
        include_transitive: Whether to include transitive dependencies.
        transitive_testonly: Whether to perform reachability analysis to assign testonly status.
        ungated_fallback: Give every pin that only has uv conflict-variant branches an
            unconditional fallback (for the workspace's `<ws>__build` repo: sdist builds
            need their tools whichever variant, if any, is selected).

    Returns:
        Dictionary of resolved packages.
    """
    local_wheels = local_wheels or {}
    if type(local_wheels) != "dict":
        fail("local_wheels must be a dict (filename -> label), got {}".format(type(local_wheels)))
    local_wheels_by_pkg = {}
    for filename, label in local_wheels.items():
        parsed = pypackaging.utils.parse_wheel_filename(filename)
        name = parsed.name
        version = pypackaging.version.to_string(parsed.version)
        pkg_key = "{}@{}".format(name, version)
        if pkg_key not in local_wheels_by_pkg:
            local_wheels_by_pkg[pkg_key] = {}
        local_wheels_by_pkg[pkg_key][filename] = label

    context = struct(
        local_wheels = local_wheels_by_pkg,
        root_dependency_markers = lock_model_data.get("root_dependency_markers", {}),
    )

    lock_model_packages = lock_model_data.get("packages", {})
    pkg_index = _build_pkg_index(lock_model_packages)
    locked_versions_by_simple_name = pkg_index.locked_versions_by_simple_name

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
            pkg_index,
        )

    raw_pins = lock_model_data.get("pins", {})
    pins = {}
    for k, v in raw_pins.items():
        parts = parse_package_key(k)

        if parts.extra:
            name = "{}[{}]".format(parts.name, parts.extra)
        else:
            name = parts.name
        if type(v) == "string":
            pins[name] = {"": v}
        else:
            pins[name] = v

    packages_by_package_key = _resolve_packages(
        lock_model_packages,
        pins,
        context,
        annotations,
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

        # With transitive_testonly, a transitive pin is testonly only if it is
        # not reachable from any non-testonly root pin.
        non_testonly_reachable_keys = {}
        if transitive_testonly:
            non_testonly_reachable_keys = _compute_reachable_keys(
                {name: v for name, v in pins.items() if parse_package_key(name).name not in testonly_pins_set},
                packages_by_package_key,
            )
        resolved_keys_by_name = {}
        for entry in resolved_packages:
            if entry.key not in reachable_keys:
                continue
            pkg_name = entry.resolved_package["name"]
            base_key = base_package_key(entry.key)
            if base_key in packages_by_package_key:
                resolved_keys_by_name.setdefault(pkg_name, {})[base_key] = True

        resolution_marker_exprs = lock_model_data.get("resolution_marker_exprs", {})
        for package_pin_name, keys_dict in resolved_keys_by_name.items():
            if package_pin_name in pins:
                continue
            is_testonly = transitive_testonly and not [
                k
                for k in keys_dict.keys()
                if k in non_testonly_reachable_keys
            ]
            fork_targets = {}
            for base_key in sorted(keys_dict.keys()):
                parts = parse_package_key(base_key)
                cname = resolution_marker_constraint_name(package_pin_name, parts.version, parts.tag)
                if cname in resolution_marker_exprs:
                    fork_targets[cname] = base_key
            if fork_targets and len(fork_targets) == len(keys_dict):
                pins[package_pin_name] = fork_targets
            else:
                if len(keys_dict) > 1:
                    version_tuples = [
                        (pypackaging.version.parse(parse_package_key(k).version).key, k)
                        for k in keys_dict.keys()
                    ]
                    chosen_key = sorted(version_tuples)[-1][1]

                    # buildifier: disable=print
                    print("WARNING: Multiple versions of {} found in transitive dependencies. Aliasing to latest: {}".format(package_pin_name, chosen_key))
                else:
                    chosen_key = keys_dict.keys()[0]
                pins[package_pin_name] = {"": chosen_key}
            if is_testonly and package_pin_name in pins:
                testonly_pins_set[package_pin_name] = True

    if ungated_fallback:
        _add_ungated_fallbacks(pins, lock_model_data)

    testonly_pin_names = sorted(testonly_pins_set.keys())

    resolved_packages_dict = {pkg.key: pkg.resolved_package for pkg in resolved_packages}
    cycle_groups = _compute_cycle_groups(resolved_packages_dict)
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
