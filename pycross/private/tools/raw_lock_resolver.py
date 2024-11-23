import json
import operator
import os
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
from urllib.parse import urlparse

from packaging.markers import Marker
from packaging.specifiers import SpecifierSet
from packaging.utils import NormalizedName
from packaging.utils import parse_wheel_filename
from packaging.version import Version
from pip._internal.index.package_finder import CandidateEvaluator
from pip._internal.index.package_finder import LinkEvaluator
from pip._internal.index.package_finder import LinkType
from pip._internal.models.candidate import InstallationCandidate
from pip._internal.models.link import Link

from pycross.private.tools.args import FlagFileArgumentParser
from pycross.private.tools.lock_model import EnvironmentReference
from pycross.private.tools.lock_model import FileKey
from pycross.private.tools.lock_model import FileReference
from pycross.private.tools.lock_model import is_wheel
from pycross.private.tools.lock_model import package_canonical_name
from pycross.private.tools.lock_model import PackageFile
from pycross.private.tools.lock_model import PackageKey
from pycross.private.tools.lock_model import RawLockSet
from pycross.private.tools.lock_model import RawPackage
from pycross.private.tools.lock_model import ResolvedLockSet
from pycross.private.tools.lock_model import ResolvedPackage
from pycross.private.tools.target_environment import TargetEnv


@dataclass(frozen=True)
class PackageSource:
    label: Optional[str] = None
    file: Optional[PackageFile] = None

    def __post_init__(self):
        assert (
            int(self.label is not None) + int(self.file is not None) == 1
        ), "Exactly one of label or file must be specified."

    @property
    def file_reference(self) -> FileReference:
        return FileReference(
            label=self.label,
            key=self.file.key if self.file is not None else None,
        )


@dataclass
class LabelAndTargetEnv:
    label: str
    target_environment: TargetEnv

    def to_environment_reference(self) -> EnvironmentReference:
        return EnvironmentReference.from_target_env(self.label, self.target_environment)


class GenerationContext:
    def __init__(
        self,
        target_environments: List[TargetEnv],
        local_wheels: Dict[str, str],
        remote_wheels: Dict[str, PackageFile],
        always_include_sdist: bool,
    ):
        self.target_environments = target_environments
        self.local_wheels = local_wheels
        self.remote_wheels = remote_wheels
        self.target_environments_by_name = {tenv.name: tenv for tenv in target_environments}
        self.always_include_sdist = always_include_sdist

    def check_package_compatibility(self, package: RawPackage) -> None:
        """Sanity check to make sure the requires_python attribute on each package matches our environments."""
        spec = SpecifierSet(package.python_versions or "")
        for environment in self.target_environments:
            if not spec.contains(environment.version):
                raise Exception(
                    f"Package {package.name} does not support Python version {environment.version} "
                    f"in environment {environment.name}"
                )

    def get_dependencies_by_environment(
        self, package: RawPackage, ignore_dependency_names: Set[str]
    ) -> Dict[Optional[str], Set[PackageKey]]:
        env_deps = defaultdict(set)
        # We sort deps by version in descending order. In case the list of dependencies
        # has multiple entries for the same name that match an environment, we prefer the
        # latest version.
        ordered_deps = sorted(package.dependencies, key=operator.attrgetter("version"), reverse=True)
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
                    env_deps[target.name].add(dep.key)
                    added_for_target.add(dep.name)

                # Otherwise, only add dependencies whose markers evaluate to the current target.
                else:
                    marker = Marker(dep.marker)
                    if marker.evaluate(target.markers):
                        env_deps[target.name].add(dep.key)
                        added_for_target.add(dep.name)

        if env_deps:
            # Pull out deps common to all environments
            common_deps = set.intersection(*env_deps.values())
            env_deps_deduped = {}
            for env, deps in env_deps.items():
                deps = deps - common_deps
                if deps:
                    env_deps_deduped[env] = deps

            env_deps_deduped[None] = common_deps
            return env_deps_deduped

        return {}

    def get_package_sources_by_environment(
        self, package: RawPackage, source_only: bool = False
    ) -> Dict[str, PackageSource]:
        formats = frozenset(["source"]) if source_only else frozenset(["source", "binary"])
        environment_sources = {}
        for environment in sorted(self.target_environments, key=lambda tenv: tenv.name.lower()):
            link_evaluator = LinkEvaluator(
                project_name=package.name,
                canonical_name=package.name,
                formats=formats,
                target_python=environment.target_python,
                allow_yanked=True,
                ignore_requires_python=True,
            )

            package_sources: Dict[str, PackageSource] = {}

            # FIXME: Link for LinkEvaluator is for pip path - so github archive does not work
            # Therefore use the first url (if any) over other candidates.
            # I'm not sure this works for non-poetry examples though
            from_url = None

            # Start with the files defined in the input lock model
            for file in package.files:
                package_sources[file.name] = PackageSource(file=file)

                if file.urls:
                    from_url = package_sources[file.name]


            if from_url:
                environment_sources[environment.name] = from_url
                continue

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
                candidate = InstallationCandidate(package.name, str(package.version), Link(filename))
                candidates_to_package_sources[candidate] = package_source

            candidates = []
            for candidate in candidates_to_package_sources:
                link_type, _ = link_evaluator.evaluate_link(candidate.link)
                if link_type == LinkType.candidate:
                    candidates.append(candidate)

            candidate_evaluator = CandidateEvaluator.create(package.name, environment.target_python)
            compute_result = candidate_evaluator.compute_best_candidate(candidates)
            if compute_result.best_candidate:
                environment_sources[environment.name] = candidates_to_package_sources[compute_result.best_candidate]

        return environment_sources


@dataclass
class PackageAnnotations:
    build_dependencies: List[PackageKey] = field(default_factory=list)
    build_target: Optional[str] = None
    always_build: bool = False
    ignore_dependencies: Set[str] = field(default_factory=set)
    install_exclude_globs: Set[str] = field(default_factory=set)


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

        build_dependencies = annotations.build_dependencies or default_build_dependencies

        # Filter out any dependencies that are already in the package's dependencies
        self._build_deps = [dep for dep in build_dependencies if dep not in (p.key for p in package.dependencies)]

        self._build_target = annotations.build_target
        self._install_exclude_globs = annotations.install_exclude_globs

        deps_by_env = context.get_dependencies_by_environment(
            package,
            annotations.ignore_dependencies,
        )
        self._common_deps = deps_by_env.get(None, set())
        self._env_deps = {k: v for k, v in deps_by_env.items() if k is not None}

        self._package_sources_by_env = context.get_package_sources_by_environment(
            package,
            annotations.always_build,
        )

        used_package_sources = set(self._package_sources_by_env.values())

        # Figure out if environments require an sdist (build from source).
        sdist_file_key = None
        for package_source in used_package_sources:
            if package_source.file and package_source.file.is_sdist:
                sdist_file_key = package_source.file.key
                self.uses_sdist = True
                break

        # If we didn't find an sdist in environment sources but
        # always_include_sdist is enabled, search all of the package's files.
        if not sdist_file_key and context.always_include_sdist:
            for file in package.files:
                if file.is_sdist:
                    sdist_file_key = file.key
                    used_package_sources.add(PackageSource(file=file))

        self.sdist_file = FileReference(key=sdist_file_key) if sdist_file_key else None
        self.package_sources = frozenset(used_package_sources)

    @cached_property
    def all_dependency_keys(self) -> Set[PackageKey]:
        """Returns all package keys (name-version) that this target depends on,
        including platform-specific and build dependencies."""
        keys = set(self._common_deps)
        for env_deps in self._env_deps.values():
            keys |= env_deps
        keys |= set(self._build_deps)
        return keys

    def to_resolved_package(self) -> ResolvedPackage:
        return ResolvedPackage(
            key=self.key,
            build_dependencies=sorted(self._build_deps),
            common_dependencies=sorted(self._common_deps),
            environment_dependencies={env: sorted(deps) for env, deps in sorted(self._env_deps.items())},
            environment_files={env: ps.file_reference for env, ps in sorted(self._package_sources_by_env.items())},
            build_target=self._build_target,
            sdist_file=self.sdist_file,
            install_exclude_globs=list(self._install_exclude_globs),
        )


def url_wheel_name(url: str) -> str:
    # Returns the wheel filename given a url. No magic here; just take the last component of the URL path.
    parsed = urlparse(url)
    filename = os.path.basename(parsed.path)
    assert filename, f"Could not determine wheel filename from url: {url}"
    assert is_wheel(filename), f"Filename is not a wheel: {url}"
    return filename


def resolve_single_version(
    name: str,
    versions_by_name: Dict[NormalizedName, List[PackageKey]],
    all_versions: AbstractSet[PackageKey],
    attr_name: str,
) -> PackageKey:
    # Handle the case of an exact version being specified.
    if "@" in name:
        name_part, version_part = name.split("@", maxsplit=1)
        key = PackageKey.from_parts(package_canonical_name(name_part), Version(version_part))
        if key not in all_versions:
            raise Exception(f'{attr_name} entry "{name}" matches no packages')
        return key

    options = versions_by_name.get(package_canonical_name(name))
    if not options:
        raise Exception(f'{attr_name} entry "{name}" matches no packages')

    if len(options) > 1:
        raise Exception(f'{attr_name} entry "{name}" matches multiple packages (choose one): {sorted(options)}')

    return options[0]


def collect_package_annotations(args: Any, lock_model: RawLockSet) -> Dict[PackageKey, PackageAnnotations]:
    annotations: Dict[PackageKey, PackageAnnotations] = defaultdict(PackageAnnotations)
    all_package_keys_by_canonical_name: Dict[NormalizedName, List[PackageKey]] = defaultdict(list)
    for package in lock_model.packages.values():
        all_package_keys_by_canonical_name[package.name].append(package.key)

    with open(args.annotations_file, "r") as f:
        annotations_data = json.load(f)

    for pkg, annotation in annotations_data.items():
        resolved_pkg = resolve_single_version(
            pkg,
            all_package_keys_by_canonical_name,
            lock_model.packages.keys(),
            "annotations",
        )

        for dep in annotation.get("build_dependencies", []):
            resolved_dep = resolve_single_version(
                dep,
                all_package_keys_by_canonical_name,
                lock_model.packages.keys(),
                "build_dependencies",
            )
            annotations[resolved_pkg].build_dependencies.append(resolved_dep)

        if annotation.get("build_target"):
            annotations[resolved_pkg].build_target = annotation["build_target"]

        if annotation.get("always_build"):
            annotations[resolved_pkg].always_build = True

        for dep in annotation.get("ignore_dependencies", []):
            if dep not in all_package_keys_by_canonical_name and dep not in lock_model.packages.keys():
                raise Exception(f'package_ignore_dependencies entry "{dep}" matches no packages')

            # This dependency will be resolved to a single version later
            annotations[resolved_pkg].ignore_dependencies.add(dep)

        for glob in annotation.get("install_exclude_globs", []):
            annotations[resolved_pkg].install_exclude_globs.add(glob)

    # Return as a non-default dict
    return dict(annotations)


def collect_default_build_dependencies(lock_model: RawLockSet, build_dependencies: list[str]) -> list[PackageKey]:
    all_package_keys_by_canonical_name: Dict[NormalizedName, List[PackageKey]] = defaultdict(list)
    resolved_build_penpendencies = []
    for package in lock_model.packages.values():
        all_package_keys_by_canonical_name[package.name].append(package.key)

    for dep in build_dependencies:
        resolved_dep = resolve_single_version(
            dep,
            all_package_keys_by_canonical_name,
            lock_model.packages.keys(),
            "build_dependencies",
        )
        resolved_build_penpendencies.append(resolved_dep)

    return resolved_build_penpendencies


def resolve(args: Any) -> ResolvedLockSet:
    environment_pairs: List[LabelAndTargetEnv] = []
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

    context = GenerationContext(
        target_environments=environments,
        local_wheels=local_wheels,
        remote_wheels=remote_wheels,
        always_include_sdist=args.always_include_sdist,
    )

    with open(args.lock_model_file, "r") as f:
        data = f.read()
    lock_model = RawLockSet.from_json(data)

    # Collect package "annotations"
    annotations = collect_package_annotations(args, lock_model)

    default_build_dependencies = collect_default_build_dependencies(lock_model, args.default_build_dependencies)

    # Walk the dependency graph starting from the set if pinned packages (in pyproject.toml), computing the
    # transitive closure.
    work = list(lock_model.pins.values())
    packages_by_package_key: Dict[PackageKey, PackageResolver] = {}

    while work:
        next_package_key = work.pop()
        if next_package_key in packages_by_package_key:
            continue
        package = lock_model.packages[next_package_key]
        context.check_package_compatibility(package)
        entry = PackageResolver(
            package,
            context,
            annotations.pop(next_package_key, None),
            default_build_dependencies,
        )
        packages_by_package_key[next_package_key] = entry
        work.extend(entry.all_dependency_keys)

    # The annotations dict should be empty now; if not, annotations were specified
    # for packages that are not actually part of our final set.
    if annotations:
        raise Exception(
            f"Annotations specified for packages that are not part of the locked set: "
            f'{", ".join([str(key) for key in sorted(annotations.keys())])}'
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
                f"{', '.join(builds)}"
            )

    repos: Dict[FileKey, PackageFile] = {}
    for package_target in resolved_packages:
        for source in package_target.package_sources:
            if not source.file:
                continue
            repos[source.file.key] = source.file

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
            pins[package_pin_name] = packages[0]

    resolved_environments = {env.target_environment.name: env.to_environment_reference() for env in environment_pairs}
    resolved_packages = {pkg.key: pkg.to_resolved_package() for pkg in resolved_packages}

    return ResolvedLockSet(
        environments=resolved_environments,
        packages=resolved_packages,
        pins=pins,
        remote_files=repos,
    )


def add_shared_flags(parser: ArgumentParser) -> None:
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
