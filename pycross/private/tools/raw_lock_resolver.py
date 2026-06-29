import hashlib
import json
import os
import re
from argparse import ArgumentParser
from collections import defaultdict
from dataclasses import dataclass
from dataclasses import field
from functools import cached_property
from pathlib import Path
from typing import AbstractSet
from typing import Any
from typing import Dict
from typing import List
from typing import Optional
from typing import Set
from typing import Tuple
from urllib.parse import urlparse

from packaging.markers import Marker as PkgMarker
from packaging.markers import Value
from packaging.markers import Variable
from packaging.utils import NormalizedName
from packaging.utils import parse_wheel_filename
from packaging.version import Version
from pycross.private.tools.args import FlagFileArgumentParser
from pycross.private.tools.lock_model import DependencyName
from pycross.private.tools.lock_model import FileKey
from pycross.private.tools.lock_model import FileReference
from pycross.private.tools.lock_model import MarkerDependency
from pycross.private.tools.lock_model import PackageDependency
from pycross.private.tools.lock_model import PackageFile
from pycross.private.tools.lock_model import PackageKey
from pycross.private.tools.lock_model import RawLockSet
from pycross.private.tools.lock_model import RawPackage
from pycross.private.tools.lock_model import ResolvedLockSet
from pycross.private.tools.lock_model import ResolvedPackage
from pycross.private.tools.lock_model import WheelCandidate
from pycross.private.tools.lock_model import is_wheel
from pycross.private.tools.lock_model import package_canonical_name

EXTRA_PATTERN = re.compile(r"extra\s*==\s*['\"]([^'\"]+)['\"]")


def _format_marker_node(node) -> str:
    """Format a single marker node (Variable, Value, or Op) back to string."""
    if isinstance(node, Variable):
        return str(node)
    if isinstance(node, Value):
        return '"' + str(node) + '"'
    return str(node)


def _format_markers(markers) -> str:
    """Reconstruct a PEP 508 marker string from packaging's internal list."""
    if isinstance(markers, tuple) and len(markers) == 3:
        return " ".join(_format_marker_node(x) for x in markers)
    if isinstance(markers, list):
        if len(markers) == 1:
            return _format_markers(markers[0])
        parts = []
        for item in markers:
            if isinstance(item, str):
                parts.append(item)
            else:
                parts.append(_format_markers(item))
        return " ".join(parts)
    return str(markers)


def _strip_extra_markers(marker_str: str) -> str:
    """Remove 'extra == ...' clauses from a marker string.

    Extras are handled by virtual extra nodes in the dependency graph,
    not by runtime marker evaluation. We strip them so the evaluator
    only sees platform/version markers.
    """
    if "extra" not in marker_str:
        return marker_str

    try:
        marker = PkgMarker(marker_str)
    except Exception:
        return marker_str

    filtered = _filter_extra_nodes(marker._markers)
    if not filtered:
        return ""

    return _format_markers(filtered)


def _filter_extra_nodes(markers) -> list:
    """Recursively remove extra == ... comparisons from the marker tree."""
    if isinstance(markers, tuple) and len(markers) == 3:
        lhs, op, rhs = markers
        # Check if this is an 'extra' comparison
        if (isinstance(lhs, Variable) and str(lhs) == "extra") or (isinstance(rhs, Variable) and str(rhs) == "extra"):
            return []
        return [markers]

    if isinstance(markers, list):
        result = []
        for item in markers:
            if isinstance(item, str):  # 'and' or 'or'
                result.append(item)
            else:
                filtered = _filter_extra_nodes(item)
                result.extend(filtered)

        # Clean up: remove leading/trailing/consecutive operators
        cleaned = []
        for item in result:
            if isinstance(item, str):
                if not cleaned or isinstance(cleaned[-1], str):
                    continue  # skip leading or consecutive operators
                cleaned.append(item)
            else:
                cleaned.append(item)

        # Remove trailing operator
        if cleaned and isinstance(cleaned[-1], str):
            cleaned.pop()

        return cleaned

    return [markers]


@dataclass(frozen=True)
class PackageSource:
    label: Optional[str] = None
    file: Optional[PackageFile] = None

    def __post_init__(self):
        assert int(self.label is not None) + int(self.file is not None) == 1, (
            "Exactly one of label or file must be specified."
        )

    @property
    def file_reference(self) -> FileReference:
        return FileReference(
            label=self.label,
            key=self.file.key if self.file is not None else None,
        )


class GenerationContext:
    def __init__(
        self,
        local_wheels: Dict[str, str],
        remote_wheels: Dict[str, PackageFile],
        always_include_sdist: bool,
        lock_package_keys: Optional[AbstractSet[PackageKey]] = None,
    ):
        self.local_wheels = local_wheels
        self.remote_wheels = remote_wheels
        self.always_include_sdist = always_include_sdist
        self.lock_package_keys = lock_package_keys

        self.local_wheels_by_pkg = defaultdict(list)
        for filename, label in local_wheels.items():
            name, version, _, _ = parse_wheel_filename(filename)
            self.local_wheels_by_pkg[(name, version)].append((filename, label))

        self.remote_wheels_by_pkg = defaultdict(list)
        for filename, remote_file in remote_wheels.items():
            name, version, _, _ = parse_wheel_filename(filename)
            self.remote_wheels_by_pkg[(name, version)].append((filename, remote_file))


@dataclass
class PackageAnnotations:
    build_dependencies: List[PackageKey] = field(default_factory=list)
    build_repo: Optional[str] = None
    build_target: Optional[str] = None
    always_build: bool = False
    ignore_dependencies: Set[str] = field(default_factory=set)
    install_exclude_globs: Set[str] = field(default_factory=set)
    post_install_patches: List[str] = field(default_factory=list)
    pre_build_patches: List[str] = field(default_factory=list)
    site_hooks: List[str] = field(default_factory=list)
    build_backend: Optional[str] = None
    site_paths: List[str] = field(default_factory=list)
    bin_paths: List[str] = field(default_factory=list)
    data_paths: List[str] = field(default_factory=list)
    include_paths: List[str] = field(default_factory=list)


class PackageResolver:
    def __init__(
        self,
        package: RawPackage,
        context: GenerationContext,
        annotations: Optional[PackageAnnotations],
        default_build_dependencies: List[PackageKey],
    ):
        annotations = annotations or PackageAnnotations()  # Default to an empty set

        self.key = package.key
        self.package_name = package.name
        self.uses_sdist = False
        self.source_dir = package.source_dir

        build_dependencies = annotations.build_dependencies or default_build_dependencies

        # Filter out any dependencies that are already in the package's dependencies
        self._build_deps = [dep for dep in build_dependencies if dep not in (p.key for p in package.dependencies)]

        self._build_repo = annotations.build_repo
        self._build_target = annotations.build_target
        self._install_exclude_globs = annotations.install_exclude_globs
        self._post_install_patches = annotations.post_install_patches
        self._pre_build_patches = annotations.pre_build_patches
        self._site_hooks = annotations.site_hooks
        self._build_backend = annotations.build_backend
        self._site_paths = annotations.site_paths
        self._bin_paths = annotations.bin_paths
        self._data_paths = annotations.data_paths
        self._include_paths = annotations.include_paths

        self._marker_deps = self._build_marker_dependencies(package, annotations.ignore_dependencies, context)

        # Build wheel candidates from all available wheel files.
        self._wheel_candidates, self._wheel_candidate_files = self._build_wheel_candidates(package, context)

        # Find sdist file directly from package files.
        sdist_file_key = None
        self._sdist_file_obj = None
        for file in package.files:
            if file.is_sdist:
                sdist_file_key = file.key
                self._sdist_file_obj = file
                break

        self.sdist_file = FileReference(key=sdist_file_key) if sdist_file_key else None

        if context.always_include_sdist or annotations.always_build:
            if self.sdist_file:
                self.uses_sdist = True
        elif not self.key.name.extra and not self._wheel_candidates:
            if self.sdist_file:
                self.uses_sdist = True
            else:
                raise Exception(f"Package {self.key} has no compatible wheels and no sdist found.")

    @cached_property
    def all_dependency_keys(self) -> Set[PackageKey]:
        """Returns all package keys (name-version) that this target depends on,
        including marker-annotated and build dependencies."""
        keys = set(self._build_deps)
        for md in self._marker_deps:
            keys.add(md.key)
        return keys

    def to_resolved_package(self) -> ResolvedPackage:
        return ResolvedPackage(
            key=self.key,
            build_dependencies=sorted(self._build_deps),
            build_repo=self._build_repo,
            build_target=self._build_target,
            sdist_file=self.sdist_file,
            install_exclude_globs=list(self._install_exclude_globs),
            post_install_patches=self._post_install_patches,
            pre_build_patches=self._pre_build_patches,
            site_hooks=self._site_hooks,
            build_backend=self._build_backend,
            site_paths=self._site_paths,
            bin_paths=self._bin_paths,
            data_paths=self._data_paths,
            include_paths=self._include_paths,
            source_dir=self.source_dir,
            marker_dependencies=self._marker_deps,
            wheel_candidates=self._wheel_candidates,
        )

    @staticmethod
    def _build_marker_dependencies(
        package: RawPackage,
        ignore_dependency_names: Set[str],
        context: GenerationContext,
    ) -> List[MarkerDependency]:
        """Build marker-annotated dependency list preserving raw PEP 508 markers.

        Instead of evaluating markers per-environment, this preserves the original
        marker strings so the Starlark evaluator can resolve them at analysis time.
        """
        result = []
        seen_names = set()
        ordered_deps = sorted(package.dependencies, key=lambda d: d.version, reverse=True)
        if ignore_dependency_names:
            ordered_deps = [d for d in ordered_deps if d.name.package not in ignore_dependency_names]

        # The package's own extra (if any), e.g. "test" for "foo[test]".
        package_extra = package.name.extra

        for dep in ordered_deps:
            dep_base_key = PackageKey.from_parts(DependencyName(dep.name.package), dep.version)
            if context.lock_package_keys is not None and dep_base_key not in context.lock_package_keys:
                continue
            dep_key = dep.key
            if dep_key in seen_names:
                continue
            seen_names.add(dep_key)

            marker_str = dep.marker
            if marker_str:
                # Check if the dep requires a specific extra.
                extra_match = EXTRA_PATTERN.search(marker_str)
                if extra_match:
                    dep_extra = extra_match.group(1)
                    # Only include this dep if the package's extra matches.
                    if package_extra != dep_extra:
                        continue

                # Strip extra markers — those are handled by virtual extra nodes.
                marker_str = _strip_extra_markers(marker_str)

            result.append(
                MarkerDependency(
                    key=dep.key,
                    marker=marker_str if marker_str else None,
                )
            )

        return result

    @staticmethod
    def _build_wheel_candidates(
        package: RawPackage,
        context: GenerationContext,
    ) -> Tuple[List[WheelCandidate], Dict]:
        """Build a list of all wheel candidates with pre-parsed tags.

        Includes both local and remote wheels. Each candidate carries its
        filename, file reference, and parsed PEP 425 compatibility tags.

        Returns:
            A tuple of (candidates, candidate_files) where candidate_files
            maps FileKey -> PackageFile for all candidate wheel files.
        """
        candidates = []
        candidate_files: Dict = {}

        # Collect all available wheel files (same sources as get_package_sources_by_environment).
        package_sources: Dict[str, PackageSource] = {}
        for file in package.files:
            package_sources[file.name] = PackageSource(file=file)
        for filename, remote_file in context.remote_wheels_by_pkg.get((package.name, package.version), []):
            package_sources[filename] = PackageSource(file=remote_file)
        for filename, local_label in context.local_wheels_by_pkg.get((package.name, package.version), []):
            package_sources[filename] = PackageSource(label=local_label)

        for filename, source in sorted(package_sources.items()):
            if not is_wheel(filename):
                continue
            try:
                _, _, _build_tag, file_tags = parse_wheel_filename(filename)
            except Exception:
                continue

            # Track the file for remote_files registration.
            if source.file:
                candidate_files[source.file.key] = source.file

            candidates.append(
                WheelCandidate(
                    filename=filename,
                    file_reference=source.file_reference,
                )
            )

        return candidates, candidate_files


def url_wheel_name(url: str) -> str:
    # Returns the wheel filename given a url. No magic here; just take the last component of the URL path.
    parsed = urlparse(url)
    filename = os.path.basename(parsed.path)
    assert filename, f"Could not determine wheel filename from url: {url}"
    assert is_wheel(filename), f"Filename is not a wheel: {url}"
    return filename


def resolve_single_version(
    name: str,
    versions_by_name: Dict[DependencyName, List[PackageKey]],
    all_versions: AbstractSet[PackageKey],
    attr_name: str,
) -> PackageKey:
    # Handle the case of an exact version being specified.
    if "@" in name:
        name_part, version_part = name.split("@", maxsplit=1)
        key = PackageKey.from_parts(DependencyName(name_part), Version(version_part))
        if key not in all_versions:
            raise Exception(f'{attr_name} entry "{name}" matches no packages')
        return key

    options = versions_by_name.get(DependencyName(name))
    if not options:
        raise Exception(f'{attr_name} entry "{name}" matches no packages')

    if len(options) > 1:
        raise Exception(f'{attr_name} entry "{name}" matches multiple packages (choose one): {sorted(options)}')

    return options[0]


def collect_package_annotations(
    args: Any, lock_model: RawLockSet
) -> Tuple[Dict[PackageKey, PackageAnnotations], Set[PackageKey]]:
    """Collect package annotations from the annotations file.

    Returns:
        A tuple of (annotations_dict, wildcard_only_keys). wildcard_only_keys
        contains package keys that were created solely by wildcard expansion
        and have no specific override. These should be silently ignored if
        they go unconsumed during resolution.
    """
    if not args.annotations_file:
        return {}, set()

    annotations: Dict[PackageKey, PackageAnnotations] = defaultdict(PackageAnnotations)
    all_package_keys_by_canonical_name: Dict[DependencyName, List[PackageKey]] = defaultdict(list)
    for package in lock_model.packages.values():
        all_package_keys_by_canonical_name[package.name].append(package.key)

    with open(args.annotations_file, "r") as f:
        annotations_data = json.load(f)

    def apply_annotation(pkg_key: PackageKey, annotation: Dict[str, Any]):
        for dep in annotation.get("build_dependencies", []):
            resolved_dep = resolve_single_version(
                dep,
                all_package_keys_by_canonical_name,
                lock_model.packages.keys(),
                "build_dependencies",
            )
            annotations[pkg_key].build_dependencies.append(resolved_dep)

        if "build_repo" in annotation:
            annotations[pkg_key].build_repo = annotation["build_repo"]

        if "build_target" in annotation:
            annotations[pkg_key].build_target = annotation["build_target"]

        if "always_build" in annotation:
            annotations[pkg_key].always_build = annotation["always_build"]

        for dep in annotation.get("ignore_dependencies", []):
            if dep not in all_package_keys_by_canonical_name and dep not in lock_model.packages.keys():
                raise Exception(f'package_ignore_dependencies entry "{dep}" matches no packages')
            annotations[pkg_key].ignore_dependencies.add(dep)

        for glob in annotation.get("install_exclude_globs", []):
            annotations[pkg_key].install_exclude_globs.add(glob)

        for patch in annotation.get("post_install_patches", []):
            annotations[pkg_key].post_install_patches.append(patch)

        for patch in annotation.get("pre_build_patches", []):
            annotations[pkg_key].pre_build_patches.append(patch)

        for hook in annotation.get("site_hooks", []):
            annotations[pkg_key].site_hooks.append(hook)

        if "build_backend" in annotation:
            annotations[pkg_key].build_backend = annotation["build_backend"]

        if "site_paths" in annotation:
            annotations[pkg_key].site_paths.extend(annotation["site_paths"])
        if "bin_paths" in annotation:
            annotations[pkg_key].bin_paths.extend(annotation["bin_paths"])
        if "data_paths" in annotation:
            annotations[pkg_key].data_paths.extend(annotation["data_paths"])
        if "include_paths" in annotation:
            annotations[pkg_key].include_paths.extend(annotation["include_paths"])

    wildcard_only_keys: Set[PackageKey] = set()
    wildcard_annotation = annotations_data.pop("*", None)

    # Apply specific annotations first.
    specific_keys: Set[PackageKey] = set()
    for pkg, annotation in annotations_data.items():
        resolved_pkg = resolve_single_version(
            pkg,
            all_package_keys_by_canonical_name,
            lock_model.packages.keys(),
            "annotations",
        )
        apply_annotation(resolved_pkg, annotation)
        specific_keys.add(resolved_pkg)

    # Apply wildcard only to packages that don't have a specific annotation.
    # A specific annotation fully replaces the wildcard for that package.
    if wildcard_annotation:
        for pkg_key in lock_model.packages.keys():
            if pkg_key not in specific_keys:
                apply_annotation(pkg_key, wildcard_annotation)
                wildcard_only_keys.add(pkg_key)

    # Return as a non-default dict
    return dict(annotations), wildcard_only_keys


def collect_default_build_dependencies(lock_model: RawLockSet, build_dependencies: list[str]) -> list[PackageKey]:
    all_package_keys_by_canonical_name: Dict[DependencyName, List[PackageKey]] = defaultdict(list)
    resolved_build_dependencies = []
    for package in lock_model.packages.values():
        all_package_keys_by_canonical_name[package.name].append(package.key)

    for dep in build_dependencies:
        resolved_dep = resolve_single_version(
            dep,
            all_package_keys_by_canonical_name,
            lock_model.packages.keys(),
            "build_dependencies",
        )
        resolved_build_dependencies.append(resolved_dep)

    return resolved_build_dependencies


def _parse_wheels(
    local_wheel_args: Optional[List[Any]], remote_wheel_args: Optional[List[Any]]
) -> Tuple[Dict[str, str], Dict[str, PackageFile]]:
    local_wheels = {}
    for local_wheel in local_wheel_args or []:
        filename, label = local_wheel
        assert is_wheel(filename), f"Local label is not a wheel: {label}"
        local_wheels[filename] = label

    remote_wheels = {}
    for remote_wheel in remote_wheel_args or []:
        url, sha256 = remote_wheel
        filename = url_wheel_name(url)
        remote_wheels[filename] = PackageFile(name=filename, sha256=sha256, urls=(url,))

    return local_wheels, remote_wheels


def _resolve_packages(
    lock_model: RawLockSet,
    context: GenerationContext,
    annotations: Dict[PackageKey, PackageAnnotations],
    default_build_dependencies: List[PackageKey],
    wildcard_only_keys: Set[PackageKey] = frozenset(),
) -> Dict[PackageKey, PackageResolver]:
    work = []
    for pin_dict in lock_model.pins.values():
        work.extend(pin_dict.values())
    packages_by_package_key: Dict[PackageKey, PackageResolver] = {}

    while work:
        next_package_key = work.pop()
        if next_package_key in packages_by_package_key:
            continue

        if next_package_key not in lock_model.packages:
            if next_package_key.name.extra:
                base_key = PackageKey.from_parts(
                    DependencyName(next_package_key.name.package), next_package_key.version
                )
                if base_key not in lock_model.packages:
                    raise KeyError(f"Missing base package {base_key} for extra {next_package_key}")
                base_package = lock_model.packages[base_key]
                package = RawPackage(
                    name=next_package_key.name,
                    version=next_package_key.version,
                    python_versions=base_package.python_versions,
                    dependencies=list(base_package.dependencies)
                    + [
                        PackageDependency(
                            name=DependencyName(next_package_key.name.package),
                            version=next_package_key.version,
                            marker="",
                        )
                    ],
                    files=[],
                )
                lock_model.packages[next_package_key] = package
            else:
                raise KeyError(f"Missing package {next_package_key}")
        else:
            package = lock_model.packages[next_package_key]

        entry = PackageResolver(
            package,
            context,
            annotations.pop(next_package_key, None),
            default_build_dependencies,
        )
        packages_by_package_key[next_package_key] = entry
        work.extend(entry.all_dependency_keys)

    # Discard any remaining annotations that came purely from wildcard expansion.
    # These are packages in the lock model that aren't in the transitive closure
    # of pins — it's expected that wildcards touch them and they go unconsumed.
    for key in wildcard_only_keys:
        annotations.pop(key, None)

    # The annotations dict should be empty now; if not, annotations were specified
    # for packages that are not actually part of our final set.
    if annotations:
        raise Exception(
            f"Annotations specified for packages that are not part of the locked set: "
            f"{', '.join([str(key) for key in sorted(annotations.keys())])}"
        )

    return packages_by_package_key


def _compute_cycle_groups(
    lock_packages: Dict[PackageKey, RawPackage],
) -> Dict[str, List[PackageKey]]:
    """Compute cycle groups over the full lock model dependency graph.

    We run Tarjan's SCC on ALL packages in the lock model and emit every
    non-trivial SCC as a cycle group.  Cycle groups are a pure property
    of the dependency graph — they do not depend on which pins are active.
    This guarantees consistent cycle group names across workspace members
    that select different optional/development groups.

    Markers are ignored when building the graph: an edge gated by a
    platform marker is included unconditionally.  This is conservative
    (more edges ⇒ superset of SCCs) and matches the union-over-
    environments semantics already used by ``runtime_dependency_keys``.

    Downstream consumers (the renderer and package_repo) are responsible
    for skipping cycle group members that fall outside the resolved set.
    """
    # Build adjacency list from raw dependencies, ignoring markers.
    graph: Dict[PackageKey, List[PackageKey]] = {}
    for pkg_key, pkg in lock_packages.items():
        deps = []
        for dep in pkg.dependencies:
            dep_key = PackageKey.from_parts(dep.name, dep.version)
            if dep_key in lock_packages:
                deps.append(dep_key)
        graph[pkg_key] = deps

    # Iterative Tarjan's SCC to avoid stack overflow on large dependency graphs
    index_counter = 0
    indices: Dict[PackageKey, int] = {}
    lowlink: Dict[PackageKey, int] = {}
    on_stack: Set[PackageKey] = set()
    stack: List[PackageKey] = []
    sccs: List[List[PackageKey]] = []

    for root in graph:
        if root in indices:
            continue
        # Each frame: (node, neighbor_iterator, is_initial_visit)
        work_stack = [(root, iter(graph.get(root, [])), True)]
        while work_stack:
            v, neighbors, initial = work_stack[-1]
            if initial:
                indices[v] = index_counter
                lowlink[v] = index_counter
                index_counter += 1
                stack.append(v)
                on_stack.add(v)
                work_stack[-1] = (v, neighbors, False)

            recurse = False
            for w in neighbors:
                if w not in indices:
                    work_stack.append((w, iter(graph.get(w, [])), True))
                    recurse = True
                    break
                elif w in on_stack:
                    lowlink[v] = min(lowlink[v], indices[w])

            if recurse:
                continue

            if lowlink[v] == indices[v]:
                scc = []
                while True:
                    w = stack.pop()
                    on_stack.remove(w)
                    scc.append(w)
                    if w == v:
                        break
                sccs.append(scc)

            work_stack.pop()
            if work_stack:
                parent = work_stack[-1][0]
                lowlink[parent] = min(lowlink[parent], lowlink[v])

    # Build cycle groups with content-based stable names.
    cycle_groups = {}
    for scc in sccs:
        if len(scc) <= 1:
            continue
        members = sorted(scc)
        # Short hash of sorted member keys for a stable, compact name
        digest = hashlib.sha256("\n".join(str(m) for m in members).encode()).hexdigest()[:8]
        group_name = f"group_{digest}"
        cycle_groups[group_name] = members

    return cycle_groups


def resolve(args: Any) -> ResolvedLockSet:
    with open(args.lock_model_file, "r") as f:
        data = f.read()
    lock_model = RawLockSet.from_json(data)

    local_wheels, remote_wheels = _parse_wheels(args.local_wheel, args.remote_wheel)

    context = GenerationContext(
        local_wheels=local_wheels,
        remote_wheels=remote_wheels,
        always_include_sdist=args.always_include_sdist,
        lock_package_keys=set(lock_model.packages.keys()),
    )

    # Collect package "annotations"
    annotations, wildcard_only_keys = collect_package_annotations(args, lock_model)

    default_build_dependencies = collect_default_build_dependencies(lock_model, args.default_build_dependencies)

    packages_by_package_key = _resolve_packages(
        lock_model,
        context,
        annotations,
        default_build_dependencies,
        wildcard_only_keys,
    )

    resolved_packages = sorted(packages_by_package_key.values(), key=lambda x: x.key)
    # If builds are disallowed, ensure that none of the targets include an sdist build
    if args.disallow_builds:
        builds = []
        for package in resolved_packages:
            if package.uses_sdist:
                builds.append(package.key)
        if builds:
            raise Exception(
                "Builds are disallowed, but the following would include pycross_wheel_build targets: "
                f"{', '.join(str(key) for key in builds)}"
            )

    repos: Dict[FileKey, PackageFile] = {}
    for package_target in resolved_packages:
        # Wheel candidates include ALL available wheels.  The wheel chooser
        # picks at analysis time, so every candidate must have a repo entry.
        repos.update(package_target._wheel_candidate_files)
        # Also include the sdist file if it exists.
        if package_target.sdist_file and package_target._sdist_file_obj:
            repos[package_target.sdist_file.key] = package_target._sdist_file_obj

    repos = dict(sorted(repos.items()))

    def pin_name(name: str) -> NormalizedName:
        return package_canonical_name(name)

    pins = {pin_name(k): v for k, v in lock_model.pins.items()}
    if args.default_alias_single_version:
        packages_by_pin_name = defaultdict(list)
        for package_target in resolved_packages:
            packages_by_pin_name[pin_name(package_target.package_name)].append(package_target.key)

        for package_pin_name, packages in packages_by_pin_name.items():
            if package_pin_name in pins:
                continue
            if len(packages) > 1:
                continue
            pins[package_pin_name] = {"": packages[0]}

    cycle_groups = _compute_cycle_groups(lock_model.packages)

    resolved_packages_dict = {pkg.key: pkg.to_resolved_package() for pkg in resolved_packages}

    for group_name, scc in cycle_groups.items():
        for pkg_key in scc:
            if pkg_key in resolved_packages_dict:
                resolved_packages_dict[pkg_key].cycle_group = group_name

    return ResolvedLockSet(
        packages=resolved_packages_dict,
        pins=pins,
        remote_files=repos,
        cycle_groups=cycle_groups,
        variants=lock_model.variants,
    )


def add_shared_flags(parser: ArgumentParser) -> None:
    parser.add_argument(
        "--lock-model-file",
        type=Path,
        required=True,
        help="The path to the lock model JSON file.",
    )

    parser.add_argument(
        "--local-wheel",
        nargs=2,
        action="append",
        help="A (file, label) parameter that points to a wheel file in the local repository.",
    )

    parser.add_argument(
        "--remote-wheel",
        nargs=2,
        action="append",
        help="A (url, sha256) parameter that points to a remote wheel.",
    )

    parser.add_argument(
        "--default-alias-single-version",
        action="store_true",
        help="Generate aliases for all packages with single versions.",
    )

    parser.add_argument(
        "--disallow-builds",
        action="store_true",
        help="If set, an error is raised if the generated lock contains wheel build targets.",
    )

    parser.add_argument(
        "--always-include-sdist",
        action="store_true",
        help="If set, always include a package's sdist if one exists.",
    )

    parser.add_argument(
        "--annotations-file",
        type=Path,
        help="The path to the annotations JSON file.",
    )
    parser.add_argument(
        "--default-build-dependencies",
        nargs="*",
        default=[],
        help="A list of default build dependencies to include in all packages.",
    )


def parse_flags() -> Any:
    parser = FlagFileArgumentParser(description="Generate a resolved lock structure.")

    add_shared_flags(parser)
    parser.add_argument(
        "--output",
        type=Path,
        required=True,
        help="The path to the output JSON file.",
    )

    return parser.parse_args()


def main(args: Any) -> None:
    result = resolve(args)
    with open(args.output, "w") as f:
        f.write(result.to_json(indent=2))


if __name__ == "__main__":
    main(parse_flags())
