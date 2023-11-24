import json
import operator
import os
import textwrap
from collections import defaultdict
from dataclasses import dataclass
from dataclasses import field
from pathlib import Path
from typing import AbstractSet
from typing import Any
from typing import Dict
from typing import Iterator
from typing import List
from typing import Optional
from typing import Set
from urllib.parse import urlparse

from absl import app
from absl.flags import argparse_flags
from packaging.markers import Marker
from packaging.specifiers import SpecifierSet
from packaging.utils import parse_wheel_filename
from pip._internal.index.package_finder import CandidateEvaluator
from pip._internal.index.package_finder import LinkEvaluator
from pip._internal.index.package_finder import LinkType
from pip._internal.models.candidate import InstallationCandidate
from pip._internal.models.link import Link

from pycross.private.tools.lock_model import LockSet
from pycross.private.tools.lock_model import Package
from pycross.private.tools.lock_model import PackageDependency
from pycross.private.tools.lock_model import PackageFile
from pycross.private.tools.lock_model import PackageKey
from pycross.private.tools.lock_model import is_wheel
from pycross.private.tools.lock_model import package_canonical_name
from pycross.private.tools.target_environment import TargetEnv

# For downloads: https://github.com/pypa/warehouse/issues/1944
WAREHOUSE_HOST = "https://files.pythonhosted.org"


def ind(text: str, tabs=1):
    """Indent text with the given number of tabs."""
    return textwrap.indent(text, "    " * tabs)


@dataclass(frozen=True)
class PackageSource:
    label: Optional[str] = None
    file: Optional[PackageFile] = None

    def needs_build(self) -> bool:
        return self.file is not None and self.file.is_sdist

    def __post_init__(self):
        assert (
            sum(
                [
                    int(self.label is not None),
                    int(self.file is not None),
                ]
            )
            == 1
        ), "Exactly one of label or file must be specified."


@dataclass
class LabelAndTargetEnv:
    label: str
    target_environment: TargetEnv


class Naming:
    def __init__(
        self,
        package_prefix: Optional[str],
        build_prefix: Optional[str],
        environment_prefix: Optional[str],
        repo_prefix: Optional[str],
    ):
        self.package_prefix = package_prefix
        self.build_prefix = build_prefix
        self.environment_prefix = environment_prefix
        self.repo_prefix = repo_prefix

    @staticmethod
    def _sanitize(name: str) -> str:
        return name.lower().replace("-", "_").replace("@", "_").replace("+", "_")

    @staticmethod
    def _prefixed(name: str, prefix: Optional[str]):
        if not prefix:
            return name
        # Strip any trailing underscores from the provided prefix, first, then add one of our own.
        return prefix.rstrip("_") + "_" + name

    def pin_target(self, package_name: str) -> str:
        return self._prefixed(self._sanitize(package_name), self.package_prefix)

    def package_target(self, package_key: PackageKey) -> str:
        return self._prefixed(self._sanitize(str(package_key)), self.package_prefix)

    def package_label(self, package_key: PackageKey) -> str:
        return f":{self.package_target(package_key)}"

    def environment_target(self, environment_name: str) -> str:
        return self._prefixed(self._sanitize(environment_name), self.environment_prefix)

    def environment_label(self, environment_name: str) -> str:
        return f":{self.environment_target(environment_name)}"

    def wheel_build_target(self, package_key: PackageKey) -> str:
        return self._prefixed(self._sanitize(str(package_key)), self.build_prefix)

    def wheel_build_label(self, package_key: PackageKey):
        return f":{self.wheel_build_target(package_key)}"

    def sdist_repo(self, file: PackageFile) -> str:
        assert file.name.endswith(".tar.gz") or file.name.endswith(".zip")
        if file.name.endswith(".tar.gz"):
            name = file.name[:-7]
        else:
            name = file.name[:-4]

        return f"{self.repo_prefix}_sdist_{self._sanitize(name)}"

    def sdist_label(self, file: PackageFile) -> str:
        assert not file.is_wheel
        return f"@{self.sdist_repo(file)}//file"

    def wheel_repo(self, file: PackageFile) -> str:
        assert file.is_wheel
        normalized_name = (
            file.name[:-4]
            .lower()
            .replace("-", "_")
            .replace("+", "_")
            .replace("%2b", "_")
        )
        return f"{self.repo_prefix}_wheel_{normalized_name}"

    def wheel_label(self, file: PackageFile):
        assert file.is_wheel
        return f"@{self.wheel_repo(file)}//file"


class GenerationContext:
    def __init__(
        self,
        target_environments: List[TargetEnv],
        local_wheels: Dict[str, str],
        remote_wheels: Dict[str, PackageFile],
        naming: Naming,
        target_environment_select: str,
    ):
        self.target_environments = target_environments
        self.local_wheels = local_wheels
        self.remote_wheels = remote_wheels
        self.naming = naming
        self.target_environment_select = target_environment_select

    def check_package_compatibility(self, package: Package) -> None:
        """Sanity check to make sure the requires_python attribute on each package matches our environments."""
        spec = SpecifierSet(package.python_versions or "")
        for environment in self.target_environments:
            if not spec.contains(environment.version):
                raise Exception(
                    f"Package {package.name} does not support Python version {environment.version} "
                    f"in environment {environment.name}"
                )

    def get_dependencies_by_environment(
        self, package: Package, ignore_dependency_names: Set[str]
    ) -> Dict[Optional[str], Set[PackageDependency]]:
        env_deps = defaultdict(list)
        # We sort deps by version in descending order. In case the list of dependencies
        # has multiple entries for the same name that match an environment, we prefer the
        # latest version.
        ordered_deps = sorted(
            package.dependencies, key=operator.attrgetter("version"), reverse=True
        )
        # Filter out dependencies that we've been told to ignore
        if ignore_dependency_names:
            ordered_deps = [d for d in ordered_deps if d.name not in ignore_dependency_names]

        for target in self.target_environments:
            added_for_target = set()
            for dep in ordered_deps:
                # Only add each dependency once per target.
                if dep.name in added_for_target:
                    continue
                # If the dependency has no marker, just add it for each environment.
                if not dep.marker:
                    env_deps[target.name].append(dep)
                    added_for_target.add(dep.name)

                # Otherwise, only add dependencies whose markers evaluate to the current target.
                else:
                    marker = Marker(dep.marker)
                    if marker.evaluate(target.markers):
                        env_deps[target.name].append(dep)
                        added_for_target.add(dep.name)

        if env_deps:
            # Pull out deps common to all environments
            common_deps = set.intersection(*(set(v) for v in env_deps.values()))
            env_deps_deduped = {}
            for env, deps in env_deps.items():
                deps = set(deps) - common_deps
                if deps:
                    env_deps_deduped[env] = deps

            env_deps_deduped[None] = common_deps
            return env_deps_deduped

        return {}

    def get_package_sources_by_environment(
        self, package: Package, source_only: bool = False
    ) -> Dict[str, PackageSource]:
        formats = (
            frozenset(["source"]) if source_only else frozenset(["source", "binary"])
        )
        environment_sources = {}
        for environment in sorted(
            self.target_environments, key=lambda te: te.name.lower()
        ):
            link_evaluator = LinkEvaluator(
                project_name=package.name,
                canonical_name=package.name,
                formats=formats,
                target_python=environment.target_python,
                allow_yanked=True,
                ignore_requires_python=True,
            )

            package_sources = {}

            # Start with the files defined in the input lock model
            for file in package.files:
                package_sources[file.name] = PackageSource(file=file)

            # Override per-file with given remote wheel URLs
            for filename, remote_file in self.remote_wheels.items():
                name, version, _, _ = parse_wheel_filename(filename)
                if (package.name, package.version) == (name, version):
                    package_sources[filename] = PackageSource(file=remote_file)

            # Override per-file with given local wheel labels
            for filename, local_label in self.local_wheels.items():
                name, version, _, _ = parse_wheel_filename(filename)
                if (package.name, package.version) == (name, version):
                    package_sources[filename] = PackageSource(label=local_label)

            candidates_to_package_sources = {}
            for filename, package_source in package_sources.items():
                candidate = InstallationCandidate(
                    package.name, str(package.version), Link(filename)
                )
                candidates_to_package_sources[candidate] = package_source

            candidates = []
            for candidate in candidates_to_package_sources:
                link_type, _ = link_evaluator.evaluate_link(candidate.link)
                if link_type == LinkType.candidate:
                    candidates.append(candidate)

            candidate_evaluator = CandidateEvaluator.create(
                package.name, environment.target_python
            )
            compute_result = candidate_evaluator.compute_best_candidate(candidates)
            if compute_result.best_candidate:
                environment_sources[environment.name] = candidates_to_package_sources[
                    compute_result.best_candidate
                ]

        return environment_sources


class EnvTarget:
    def __init__(self, environment_name: str, constraints: List[str], flag_values: Dict[str, str], naming: Naming):
        self.naming = naming
        self.environment_name = environment_name
        self.constraints = constraints
        self.flag_values = flag_values

    def render(self) -> str:
        lines = [
            "native.config_setting(",
            ind(f'name = "{self.naming.environment_target(self.environment_name)}",'),
        ]
        if self.constraints:
            lines.append(ind(f"constraint_values = ["))
            for cv in self.constraints:
                lines.append(ind(f'"{cv}",', 2))
            lines.append(ind("],"))
        if self.flag_values:
            lines.append(ind("flag_values = {"),)
            for flag, value in self.flag_values:
                lines.append(ind(repr(flag) + ": " + repr(value) + ",", 2))
            lines.append(ind("}"))
        lines.append(")")

        return "\n".join(lines)


@dataclass
class PackageAnnotations:
    build_dependencies: List[str] = field(default_factory=list)
    build_target_override: Optional[str] = None
    always_build: bool = False
    ignore_dependencies: Set[str] = field(default_factory=set)


class PackageTarget:
    def __init__(
        self,
        package: Package,
        context: GenerationContext,
        annotations: Optional[PackageAnnotations],
    ):
        annotations = annotations or PackageAnnotations()  # Default to an empty set
        self.package = package
        self.context = context

        self.build_deps = annotations.build_dependencies
        self.build_target_override = annotations.build_target_override

        deps_by_env = context.get_dependencies_by_environment(
            package,
            annotations.ignore_dependencies,
        )
        self.common_deps = deps_by_env.get(None, set())
        self.env_deps = {k: v for k, v in deps_by_env.items() if k is not None}

        self.package_sources_by_env = self.context.get_package_sources_by_environment(
            package,
            annotations.always_build,
        )

    @property
    def distinct_package_sources(self) -> Set[PackageSource]:
        return set(self.package_sources_by_env.values())

    @property
    def all_dependency_keys(self) -> Set[str]:
        """Returns all package keys (name-version) that this target depends on, 
        including platform-specific and build dependencies."""
        keys = set(str(d.key) for d in self.common_deps)
        for env_deps in self.env_deps.values():
            keys |= set(str(d.key) for d in env_deps)
        keys |= set(self.build_deps)
        return keys

    @property
    def source_file(self) -> Optional[PackageFile]:
        for f in self.distinct_package_sources:
            if f.file and f.file.is_sdist:
                return f.file

    @property
    def has_runtime_deps(self) -> bool:
        return bool(self.common_deps or self.env_deps)

    @property
    def has_source(self) -> bool:
        return self.source_file is not None

    def _common_entries(
        self, deps: Set[PackageDependency], indent: int
    ) -> Iterator[str]:
        package_labels = set([self.context.naming.package_label(d.key) for d in deps])
        for package_label in sorted(package_labels):
            yield ind(f'"{package_label}",', indent)

    def _select_entries(
        self, env_deps: Dict[str, Set[PackageDependency]], indent
    ) -> Iterator[str]:
        for env_name, deps in sorted(env_deps.items(), key=lambda x: x[0].lower()):
            yield ind(f'"{self.context.naming.environment_label(env_name)}": [', indent)
            yield from self._common_entries(deps, indent + 1)
            yield ind("],", indent)
        yield ind('"//conditions:default": [],', indent)

    @property
    def _deps_name(self):
        key_str = str(self.package.key)
        sanitized = (
            key_str.replace("-", "_")
            .replace(".", "_")
            .replace("@", "_")
            .replace("+", "_")
        )
        return f"_{sanitized}_deps"

    @property
    def _build_deps_name(self):
        key_str = str(self.package.key)
        sanitized = (
            key_str.replace("-", "_")
            .replace(".", "_")
            .replace("@", "_")
            .replace("+", "_")
        )
        return f"_{sanitized}_build_deps"

    def render_runtime_deps(self) -> str:
        assert self.has_runtime_deps
        lines = []

        if self.common_deps and self.env_deps:
            lines.append(f"{self._deps_name} = [")
            lines.extend(self._common_entries(self.common_deps, 1))
            lines.append("] + select({")
            lines.extend(self._select_entries(self.env_deps, 1))
            lines.append("})")

        elif self.common_deps:
            lines.append(f"{self._deps_name} = [")
            lines.extend(self._common_entries(self.common_deps, 1))
            lines.append("]")

        elif self.env_deps:
            lines.append(self._deps_name + " = select({")
            lines.extend(self._select_entries(self.env_deps, 1))
            lines.append("})")

        return "\n".join(lines)

    def render_build_deps(self) -> str:
        assert self.build_deps

        lines = [f"{self._build_deps_name} = ["]
        for dep in sorted(
            self.build_deps, key=lambda k: self.context.naming.package_label(k)
        ):
            lines.append(ind(f'"{self.context.naming.package_label(dep)}",', 1))
        lines.append("]")

        return "\n".join(lines)

    def render_build(self) -> str:
        source_file = self.source_file
        assert source_file is not None

        lines = [
            "pycross_wheel_build(",
            ind(
                f'name = "{self.context.naming.wheel_build_target(self.package.key)}",'
            ),
            ind(f'sdist = "{self.context.naming.sdist_label(source_file)}",'),
            ind(f"target_environment = {self.context.target_environment_select},"),
        ]

        dep_names = []
        if self.has_runtime_deps:
            dep_names.append(self._deps_name)
        if self.build_deps:
            dep_names.append(self._build_deps_name)

        if dep_names:
            lines.append(ind(f"deps = {' + '.join(dep_names)},"))
        lines.extend(
            [
                ind('tags = ["manual"],'),
                ")",
            ]
        )

        return "\n".join(lines)

    def render_pkg(self) -> str:
        lines = [
            "pycross_wheel_library(",
            ind(f'name = "{self.context.naming.package_target(self.package.key)}",'),
        ]
        if self.has_runtime_deps:
            lines.append(ind(f"deps = {self._deps_name},"))

        # Add the wheel attribute.
        # If all environments use the same wheel, don't use select.

        def wheel_target(pkg_source: PackageSource) -> str:
            if pkg_source.label:
                return pkg_source.label
            elif pkg_source.file and pkg_source.file.is_wheel:
                return self.context.naming.wheel_label(pkg_source.file)
            elif self.build_target_override:
                return self.build_target_override
            else:
                return self.context.naming.wheel_build_label(self.package.key)

        if len(self.distinct_package_sources) == 1:
            source = next(iter(self.distinct_package_sources))
            lines.append(ind(f'wheel = "{wheel_target(source)}",'))
        else:
            lines.append(ind("wheel = select({"))
            naming = self.context.naming
            for env_name, source in self.package_sources_by_env.items():
                lines.append(
                    ind(
                        f'"{naming.environment_label(env_name)}": "{wheel_target(source)}",',
                        2,
                    )
                )
            lines.append(ind("}),"))

        lines.append(")")

        return "\n".join(lines)

    def render(self) -> str:
        parts = []
        if self.has_runtime_deps:
            parts.append(self.render_runtime_deps())
            parts.append("")
        if self.build_deps:
            parts.append(self.render_build_deps())
            parts.append("")
        if self.has_source and not self.build_target_override:
            parts.append(self.render_build())
            parts.append("")
        parts.append(self.render_pkg())
        return "\n".join(parts)


class UrlRepoTarget:
    def __init__(self, name: str, file: PackageFile):
        assert (
            file.urls
        ), "UrlWheelRepoTarget requires a PackageFile with one or more URLs"
        self.name = name
        self.file = file

    def render(self) -> str:
        parts = []
        parts.extend(
            [
                "maybe(",
                ind("http_file,"),
                ind(f'name = "{self.name}",'),
                ind(f"urls = ["),
            ]
        )

        urls = sorted(self.file.urls)
        for url in urls[:-1]:
            parts.append(ind(f'"{url}",', 2))
        parts.append(ind(f'"{urls[-1]}"', 2))

        parts.extend(
            [
                ind(f"],"),
                ind(f'sha256 = "{self.file.sha256}",'),
                ind(f'downloaded_file_path = "{self.file.name}",'),
                ")",
            ]
        )

        return "\n".join(parts)


class PypiFileRepoTarget:
    def __init__(
        self, name: str, package: Package, file: PackageFile, pypi_index: Optional[str]
    ):
        self.name = name
        self.package = package
        self.file = file
        self.pypi_index = pypi_index

    def render(self) -> str:
        lines = [
            "maybe(",
            ind("pypi_file,"),
            ind(f'name = "{self.name}",'),
            ind(f'package_name = "{self.package.name}",'),
            ind(f'package_version = "{self.package.version}",'),
            ind(f'filename = "{self.file.name}",'),
            ind(f'sha256 = "{self.file.sha256}",'),
        ]

        if self.pypi_index:
            lines.append(ind(f'index = "{self.pypi_index}",'))

        lines.append(")")

        return "\n".join(lines)


class PypiWheelRepoTarget(PypiFileRepoTarget):
    def __init__(
        self,
        package: Package,
        file: PackageFile,
        pypi_index: Optional[str],
        context: GenerationContext,
    ):
        super().__init__(context.naming.wheel_repo(file), package, file, pypi_index)


class PypiSdistRepoTarget(PypiFileRepoTarget):
    def __init__(
        self,
        package: Package,
        file: PackageFile,
        pypi_index: Optional[str],
        context: GenerationContext,
    ):
        super().__init__(context.naming.sdist_repo(file), package, file, pypi_index)


def url_wheel_name(url: str) -> str:
    # Returns the wheel filename given a url. No magic here; just take the last component of the URL path.
    parsed = urlparse(url)
    filename = os.path.basename(parsed.path)
    assert filename, f"Could not determine wheel filename from url: {url}"
    assert is_wheel(filename), f"Filename is not a wheel: {url}"
    return filename


def resolve_single_version(
    name: str,
    versions_by_name: Dict[str, List[str]],
    all_versions: AbstractSet[str],
    attr_name: str,
):
    # Handle the case of an exact version being specified.
    if "@" in name:
        if name not in all_versions:
            raise Exception(f'{attr_name} entry "{name}" matches no packages')
        return name

    options = versions_by_name.get(name)
    if not options:
        raise Exception(f'{attr_name} entry "{name}" matches no packages')

    if len(options) > 1:
        raise Exception(
            f'{attr_name} entry "{name}" matches multiple packages (choose one): {sorted(options)}'
        )

    return options[0]


def collect_package_annotations(args: Any, lock_model: LockSet) -> Dict[str, PackageAnnotations]:
    annotations = defaultdict(PackageAnnotations)
    all_package_keys_by_canonical_name = defaultdict(list)
    for package in lock_model.packages.values():
        all_package_keys_by_canonical_name[package.name].append(package.key)

    for build_dependency in args.build_dependency or []:
        pkg, dep = build_dependency
        resolved_pkg = resolve_single_version(
            pkg,
            all_package_keys_by_canonical_name,
            lock_model.packages.keys(),
            "package_build_dependencies",
        )
        resolved_dep = resolve_single_version(
            dep,
            all_package_keys_by_canonical_name,
            lock_model.packages.keys(),
            "package_build_dependencies",
        )
        annotations[resolved_pkg].build_dependencies.append(resolved_dep)

    build_target_overrides_used = set()
    for build_target_override in args.build_target_override or []:
        pkg, target = build_target_override
        resolved_pkg = resolve_single_version(
            pkg,
            all_package_keys_by_canonical_name,
            lock_model.packages.keys(),
            "build_target_overrides",
        )
        if resolved_pkg in build_target_overrides_used:
            raise Exception(
                f'build_target_overrides entry "{resolved_pkg}" listed multiple times'
            )
        build_target_overrides_used.add(resolved_pkg)
        annotations[resolved_pkg].build_target_override = target

    for always_build_package in args.always_build_package or []:
        resolved_pkg = resolve_single_version(
            always_build_package,
            all_package_keys_by_canonical_name,
            lock_model.packages.keys(),
            "always_build_packages",
        )
        annotations[resolved_pkg].always_build = True

    for ignore_dependency in args.ignore_dependency or []:
        pkg, dep = ignore_dependency
        resolved_pkg = resolve_single_version(
            pkg,
            all_package_keys_by_canonical_name,
            lock_model.packages.keys(),
            "package_ignore_dependencies",
        )
        if dep not in all_package_keys_by_canonical_name and dep not in lock_model.packages.keys():
            raise Exception(f'package_ignore_dependencies entry "{dep}" matches no packages')

        # This dependency will be resolved to a single version later
        annotations[resolved_pkg].ignore_dependencies.add(dep)

    # Return as a non-default dict
    return dict(annotations)


def main(args: Any) -> None:
    output = args.output
    environment_pairs = []
    for target_environment in args.target_environment or []:
        target_file, target_label = target_environment
        with open(target_file, "r") as f:
            environment_pairs.append(
                LabelAndTargetEnv(
                    label=target_label,
                    target_environment=TargetEnv.from_dict(json.load(f)),
                )
            )
    environment_pairs.sort(key=lambda x: x.target_environment.name.lower())
    environments = [ep.target_environment for ep in environment_pairs]

    local_wheels = {}
    for local_wheel in args.local_wheel or []:
        filename, label = local_wheel
        assert is_wheel(filename), f"Local label is not a wheel: {label}"
        local_wheels[filename] = label

    remote_wheels = {}
    for remote_wheel in args.remote_wheel or []:
        url, sha256 = remote_wheel
        filename = url_wheel_name(url)
        remote_wheels[filename] = PackageFile(name=filename, sha256=sha256, urls=(url,))

    naming = Naming(
        repo_prefix=args.repo_prefix,
        package_prefix=args.package_prefix,
        build_prefix=args.build_prefix,
        environment_prefix=args.environment_prefix,
    )
    context = GenerationContext(
        target_environments=environments,
        local_wheels=local_wheels,
        remote_wheels=remote_wheels,
        naming=naming,
        target_environment_select="_target",
    )

    with open(args.lock_model_file, "r") as f:
        data = f.read()
    lock_model = LockSet.from_json(data)

    # Collect package "annotations"
    annotations = collect_package_annotations(args, lock_model)

    # Walk the dependency graph starting from the set if pinned packages (in pyproject.toml), computing the
    # transitive closure.
    work = list(lock_model.pins.values())
    package_targets_by_package_key = {}

    while work:
        next_package_key = work.pop()
        if next_package_key in package_targets_by_package_key:
            continue
        package = lock_model.packages[next_package_key]
        context.check_package_compatibility(package)
        entry = PackageTarget(
            package,
            context,
            annotations.pop(next_package_key, None),
        )
        package_targets_by_package_key[next_package_key] = entry
        work.extend(entry.all_dependency_keys)

    # The annotations dict should be empty now; if not, annotations were specified
    # for packages that are not actually part of our final set.
    if annotations:
        raise Exception(
            f"Annotations specified for packages that are not part of the locked set: "
            f'{", ".join(sorted(annotations.keys()))}'
        )

    package_targets = sorted(
        package_targets_by_package_key.values(), key=lambda x: x.package.name
    )

    pypi_index = args.pypi_index or None
    repos = []
    for package_target in package_targets:
        for source in package_target.distinct_package_sources:
            if not source.file:
                continue

            file = source.file

            if file.is_wheel:
                name = naming.wheel_repo(file)
            else:
                name = naming.sdist_repo(file)

            if file.urls:
                repos.append(UrlRepoTarget(name, file))
            else:
                repos.append(
                    PypiFileRepoTarget(name, package_target.package, file, pypi_index)
                )

    repos.sort(key=lambda ft: ft.name)

    # pin aliases are normalized package names with underscores rather than hashes.
    def pin_name(name: str) -> str:
        normal_name = package_canonical_name(name)
        return normal_name.lower().replace("-", "_")

    pins = {pin_name(k): v for k, v in lock_model.pins.items()}
    if args.default_alias_single_version:
        packages_by_pin_name = defaultdict(list)
        for package_target in package_targets:
            packages_by_pin_name[pin_name(package_target.package.name)].append(
                package_target.package
            )

        for package_pin_name, packages in packages_by_pin_name.items():
            if package_pin_name in pins:
                continue
            if len(packages) > 1:
                continue
            pins[package_pin_name] = packages[0].key

    with open(output, "w") as f:

        def w(*text):
            if not text:
                text = [""]
            for t in text:
                print(t, file=f)

        # Header stuff
        w(
            "# This file is generated by rules_pycross.",
            "# It is not intended for manual editing.",
            "",
            'load("@bazel_tools//tools/build_defs/repo:http.bzl", "http_file")',
            'load("@bazel_tools//tools/build_defs/repo:utils.bzl", "maybe")',
            'load("@jvolkman_rules_pycross//pycross:defs.bzl", "pycross_wheel_build", "pycross_wheel_library", "pypi_file")',
        )
        w()

        # Build PINS map
        if pins:
            w("PINS = {")
            for pinned_package_name in sorted(pins.keys()):
                pinned_package_key = pins[pinned_package_name]
                w(
                    ind(
                        f'"{pinned_package_name}": "{naming.package_target(pinned_package_key)}",'
                    )
                )
            w("}")
        else:
            w("PINS = {}")
        w()

        # Build targets
        w("def targets():")

        # Create pin aliases based on the PINS dict above.
        w(
            ind("for pin_name, pin_target in PINS.items():", 1),
            ind("native.alias(", 2),
            ind("name = pin_name,", 3),
            ind('actual = ":" + pin_target,', 3),
            ind(")", 2),
        )
        w()

        for environment in environments:
            env_target = EnvTarget(
                environment.name, environment.python_compatible_with, environment.flag_values, naming
            )
            w(ind(env_target.render()))
            w()

        w(ind(f"{context.target_environment_select} = select({{"))
        for ep in environment_pairs:
            w(
                ind(
                    f'"{naming.environment_label(ep.target_environment.name)}": "{ep.label}",',
                    2,
                )
            )
        w(ind("})"))
        w()

        for e in package_targets:
            w(ind(e.render()))
            w()

        # Repos
        w("def repositories():")
        for r in repos:
            w(ind(r.render()))
            w()


def parse_flags(argv) -> Any:
    parser = argparse_flags.ArgumentParser(
        description="Generate pycross dependency bzl file."
    )

    parser.add_argument(
        "--repo-prefix",
        type=str,
        default="",
        help="The prefix to apply to repository targets.",
    )

    parser.add_argument(
        "--package-prefix",
        default="",
        help="The prefix to apply to packages targets.",
    )

    parser.add_argument(
        "--build-prefix",
        default="",
        help="The prefix to apply to package build targets.",
    )

    parser.add_argument(
        "--environment-prefix",
        default="",
        help="The prefix to apply to packages environment targets.",
    )

    parser.add_argument(
        "--lock-model-file",
        type=Path,
        required=True,
        help="The path to the lock model JSON file.",
    )

    parser.add_argument(
        "--target-environment",
        nargs=2,
        action="append",
        help="A (file, label) parameter that maps a pycross_target_environment label to its JSON output file.",
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
        "--build-target-override",
        nargs=2,
        action="append",
        help="A (key, label) parameter that specifies the existing pycross_wheel_build target for a package key.",
    )

    parser.add_argument(
        "--always-build-package",
        action="append",
        help="A package key that should always be built from source.",
    )

    parser.add_argument(
        "--build-dependency",
        nargs=2,
        action="append",
        help="A (key, key) parameter that specifies an additional package build dependency",
    )

    parser.add_argument(
        "--ignore-dependency",
        nargs=2,
        action="append",
        help="A (key, key) parameter that specifies a package dependency to ignore",
    )

    parser.add_argument(
        "--pypi-index",
        help="The PyPI-compatible index to use. Defaults to pypi.org.",
    )

    parser.add_argument(
        "--output",
        type=Path,
        required=True,
        help="The path to the output bzl file.",
    )

    return parser.parse_args(argv[1:])


if __name__ == "__main__":
    # When under `bazel run`, change to the actual working dir.
    if "BUILD_WORKING_DIRECTORY" in os.environ:
        os.chdir(os.environ["BUILD_WORKING_DIRECTORY"])

    app.run(main, flags_parser=parse_flags)
