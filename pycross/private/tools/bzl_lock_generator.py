import argparse
import json
import os
import sys
import textwrap
from collections import defaultdict
from dataclasses import dataclass
from typing import Dict
from typing import Iterator
from typing import List
from typing import Optional
from typing import Set
from typing import Tuple
from urllib.parse import urlparse

from packaging.markers import Marker
from packaging.specifiers import SpecifierSet
from packaging.utils import parse_wheel_filename
from pip._internal.index.package_finder import CandidateEvaluator
from pip._internal.index.package_finder import LinkEvaluator
from pip._internal.models.candidate import InstallationCandidate
from pip._internal.models.link import Link

from pycross.private.tools.lock_model import LockSet
from pycross.private.tools.lock_model import Package
from pycross.private.tools.lock_model import PackageDependency
from pycross.private.tools.lock_model import is_wheel
from pycross.private.tools.target_environment import TargetEnv


# For downloads: https://github.com/pypa/warehouse/issues/1944
WAREHOUSE_HOST = "https://files.pythonhosted.org"


def ind(text: str, tabs=1):
    """Indent text with the given number of tabs."""
    return textwrap.indent(text, "    " * tabs)


@dataclass(frozen=True)
class RemoteFile:
    filename: str
    urls: Tuple[str]
    sha256: str

    def __post_init__(self):
        assert self.filename, "The filename field must be specified."
        assert self.urls, "The urls field must be specified."
        assert self.sha256, "The sha256 field must be specified."

    @property
    def is_wheel(self) -> bool:
        return is_wheel(self.filename)


@dataclass(frozen=True)
class PackageSource:
    label: Optional[str] = None
    remote_wheel: Optional[RemoteFile] = None
    remote_sdist: Optional[RemoteFile] = None

    def needs_build(self) -> bool:
        return self.remote_sdist is not None

    def __post_init__(self):
        assert not (
            (self.label is None)
            ^ (self.remote_wheel is None)
            ^ (self.remote_sdist is None)
        ), "Exactly one of label, remote_wheel, remote_sdist or must be specified."


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
        return name.lower().replace("-", "_")

    @staticmethod
    def _prefixed(name: str, prefix: Optional[str]):
        if not prefix:
            return name
        # Strip any trailing underscores from the provided prefix, first, then add one of our own.
        return prefix.rstrip("_") + "_" + name

    def pin_target(self, package_name: str) -> str:
        return self._prefixed(self._sanitize(package_name), self.package_prefix)

    def package_target(self, package_key: str) -> str:
        return self._prefixed(self._sanitize(package_key), self.package_prefix)

    def package_label(self, package_key: str) -> str:
        return f":{self.package_target(package_key)}"

    def environment_target(self, environment_name: str) -> str:
        return self._prefixed(self._sanitize(environment_name), self.environment_prefix)

    def environment_label(self, environment_name: str) -> str:
        return f":{self.environment_target(environment_name)}"

    def wheel_build_target(self, package_key: str) -> str:
        return self._prefixed(self._sanitize(package_key), self.build_prefix)

    def wheel_build_label(self, package_key: str):
        return f":{self.wheel_build_target(package_key)}"

    def sdist_repo(self, file: RemoteFile) -> str:
        assert file.filename.endswith(".tar.gz")
        name = file.filename[:-7]
        return f"{self.repo_prefix}_sdist_{self._sanitize(name)}"

    def sdist_label(self, file: RemoteFile) -> str:
        assert not file.is_wheel
        return f"@{self.sdist_repo(file)}//file"

    def wheel_repo(self, file: RemoteFile) -> str:
        assert file.is_wheel
        normalized_name = file.filename[:-4].lower().replace("-", "_")
        return f"{self.repo_prefix}_wheel_{normalized_name}"

    def wheel_label(self, file: RemoteFile):
        assert file.is_wheel
        return f"@{self.wheel_repo(file)}//file"


class GenerationContext:
    def __init__(
        self,
        target_environments: List[TargetEnv],
        file_url_overrides: Dict[str, str],
        local_wheels: Dict[str, str],
        remote_wheels: Dict[str, RemoteFile],
        naming: Naming,
    ):
        self.target_environments = target_environments
        self.file_url_overrides = file_url_overrides
        self.local_wheels = local_wheels
        self.remote_wheels = remote_wheels
        self.naming = naming

    def pypi_url(self, filename: str) -> str:
        """Returns the pypi URL for fetching this file."""
        if filename in self.file_url_overrides:
            return self.file_url_overrides[filename]

        # See:
        # https://github.com/pypa/warehouse/issues/1239
        # https://github.com/pypa/warehouse/issues/1944

        filename_parts = filename.split("-")
        name = filename_parts[0]
        if is_wheel(filename):
            area = filename_parts[-3]  # python_tag
        else:
            area = "source"

        return f"{WAREHOUSE_HOST}/packages/{area}/{name[0]}/{name}/{filename}"

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
        self, package: Package
    ) -> Dict[Optional[str], Set[PackageDependency]]:
        env_deps = defaultdict(list)
        for dep in package.dependencies:
            for target in self.target_environments:

                # If the dependency has no marker, just add it for each environment.
                if not dep.marker:
                    env_deps[target.name].append(dep)

                # Otherwise, if no extras, just evaluate the markers normally.
                else:
                    marker = Marker(dep.marker)
                    if marker.evaluate(target.markers):
                        env_deps[target.name].append(dep)

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
            evaluator = LinkEvaluator(
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
                remote_file = RemoteFile(
                    filename=file.name,
                    urls=(self.pypi_url(file.name),),
                    sha256=file.sha256,
                )
                if file.is_wheel:
                    package_sources[file.name] = PackageSource(remote_wheel=remote_file)
                else:
                    package_sources[file.name] = PackageSource(remote_sdist=remote_file)

            # Override per-file with given remote wheel URLs
            for filename, remote_file in self.remote_wheels.items():
                name, version, _, _ = parse_wheel_filename(filename)
                if (package.name, package.version) == (name, version):
                    package_sources[filename] = remote_file

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
                valid, _ = evaluator.evaluate_link(candidate.link)
                if valid:
                    candidates.append(candidate)

            evaluator = CandidateEvaluator.create(
                package.name, environment.target_python
            )
            compute_result = evaluator.compute_best_candidate(candidates)
            environment_sources[environment.name] = candidates_to_package_sources[
                compute_result.best_candidate
            ]

        return environment_sources


class EnvTarget:
    def __init__(self, environment_name: str, constraints: List[str], naming: Naming):
        self.naming = naming
        self.environment_name = environment_name
        self.constraints = constraints

    def render(self) -> str:
        lines = [
            "native.config_setting(",
            ind(f'name = "{self.naming.environment_target(self.environment_name)}",'),
            ind(f"constraint_values = ["),
        ]
        for cv in self.constraints:
            lines.append(ind(f'"{cv}",', 2))
        lines.extend([ind("],"), ")"])

        return "\n".join(lines)


class PackageTarget:
    def __init__(
        self,
        package: Package,
        context: GenerationContext,
        build_target_override: Optional[str],
        always_build: bool,
    ):
        self.package = package
        self.context = context
        self.common_deps: Set[PackageDependency] = set()
        self.env_deps: Dict[str, Set[PackageDependency]] = {}

        deps_by_env = context.get_dependencies_by_environment(package)
        self.common_deps = deps_by_env.get(None, set())
        self.env_deps = {k: v for k, v in deps_by_env.items() if k is not None}

        self.package_sources_by_env = context.get_package_sources_by_environment(
            self.package, always_build
        )
        self.distinct_package_sources = set(self.package_sources_by_env.values())
        self.build_target_override = build_target_override
        self.always_build = always_build

    @property
    def all_dependency_keys(self) -> Set[str]:
        """Returns all package keys (name-version) that this target depends on, including platform-specific."""
        keys = set(d.key for d in self.common_deps)
        for env_deps in self.env_deps.values():
            keys |= set(d.key for d in env_deps)
        return keys

    @property
    def source_file(self) -> Optional[RemoteFile]:
        for f in self.distinct_package_sources:
            if f.remote_sdist:
                return f.remote_sdist

    @property
    def has_deps(self) -> bool:
        return bool(self.common_deps or self.env_deps)

    @property
    def has_source(self) -> bool:
        return self.source_file is not None

    def _common_entries(
        self, deps: Set[PackageDependency], indent: int
    ) -> Iterator[str]:
        for d in sorted(deps, key=lambda x: x.key):
            yield ind(f'"{self.context.naming.package_label(d.key)}",', indent)

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
        sanitized = self.package.key.replace("-", "_").replace(".", "_")
        return f"_{sanitized}_deps"

    def render_deps(self) -> str:
        assert self.has_deps
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

    def render_build(self) -> str:
        source_file = self.source_file
        assert source_file is not None

        lines = [
            "pycross_wheel_build(",
            ind(
                f'name = "{self.context.naming.wheel_build_target(self.package.key)}",'
            ),
            ind(f'sdist = "{self.context.naming.sdist_label(source_file)}",'),
        ]
        if self.has_deps:
            lines.append(ind(f"deps = {self._deps_name},"))
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
        if self.has_deps:
            lines.append(ind(f"deps = {self._deps_name},"))

        # Add the wheel attribute.
        # If all environments use the same wheel, don't use select.

        def wheel_target(pkg_source: PackageSource) -> str:
            if pkg_source.label:
                return pkg_source.label
            elif pkg_source.remote_wheel:
                return self.context.naming.wheel_label(pkg_source.remote_wheel)
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
        if self.has_deps:
            parts.append(self.render_deps())
            parts.append("")
        if self.has_source and not self.build_target_override:
            parts.append(self.render_build())
            parts.append("")
        parts.append(self.render_pkg())
        return "\n".join(parts)


class FileRepoTarget:
    def __init__(self, name: str, file: RemoteFile, context: GenerationContext):
        self.name = name
        self.file = file
        self.context = context

    def render(self) -> str:
        lines = (
            [
                "maybe(",
                ind("http_file,"),
                ind(f'name = "{self.name}",'),
                ind(f"urls = ["),
            ]
            + [ind(f'"{url}"', 2) for url in sorted(self.file.urls)]
            + [
                ind(f"],"),
                ind(f'sha256 = "{self.file.sha256}",'),
                ind(f'downloaded_file_path = "{self.file.filename}",'),
                ")",
            ]
        )

        return "\n".join(lines)


class WheelRepoTarget(FileRepoTarget):
    def __init__(self, file: RemoteFile, context: GenerationContext):
        super().__init__(context.naming.wheel_repo(file), file, context)


class SdistRepoTarget(FileRepoTarget):
    def __init__(self, file: RemoteFile, context: GenerationContext):
        super().__init__(context.naming.sdist_repo(file), file, context)


def url_wheel_name(url: str) -> str:
    # Returns the wheel filename given a url. No magic here; just take the last component of the URL path.
    parsed = urlparse(url)
    filename = os.path.basename(parsed.path)
    assert filename, f"Could not determine wheel filename from url: {url}"
    assert is_wheel(filename), f"Filename is not a wheel: {url}"
    return filename


def main():
    parser = make_parser()
    args = parser.parse_args()
    output = args.output
    environments = []
    for target_file in args.target_environment_file or []:
        with open(target_file, "r") as f:
            environments.append(TargetEnv.from_dict(json.load(f)))

    # TODO: Make this a file instead
    url_overrides = {}
    for url_override in args.file_url_override or []:
        filename, url = url_override.split("=", maxsplit=1)
        url_overrides[filename] = url

    local_wheels = {}
    for local_wheel in args.local_wheel or []:
        filename, label = local_wheel.split("=", maxsplit=1)
        assert is_wheel(filename), f"Local label is not a wheel: {label}"
        local_wheels[filename] = label

    remote_wheels = {}
    for remote_wheel in args.remote_wheel or []:
        url, sha256 = remote_wheel.rsplit(
            "=", maxsplit=1
        )  # rsplit because we know the sha256 contains no '='
        filename = url_wheel_name(url)
        remote_wheels[filename] = RemoteFile(
            filename=filename, urls=(url,), sha256=sha256
        )

    build_target_overrides = {}
    for build_target_override in args.build_target_override or []:
        key, target = build_target_override.split("=", maxsplit=1)
        build_target_overrides[key] = target

    always_build_packages = set(args.always_build_package or [])

    naming = Naming(
        repo_prefix=args.repo_prefix,
        package_prefix=args.package_prefix,
        build_prefix=args.build_prefix,
        environment_prefix=args.environment_prefix,
    )
    context = GenerationContext(
        target_environments=environments,
        file_url_overrides=url_overrides,
        local_wheels=local_wheels,
        remote_wheels=remote_wheels,
        naming=naming,
    )

    with open(args.lock_model_file, "r") as f:
        data = f.read()
    lock_model = LockSet.from_json(data)

    # First we walk the dependency graph starting from the set if pinned packages (in pyproject.toml), computing the
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
            build_target_overrides.get(package.key),
            package.key in always_build_packages,
        )
        package_targets_by_package_key[next_package_key] = entry
        work.extend(entry.all_dependency_keys)

    package_targets = sorted(
        package_targets_by_package_key.values(), key=lambda x: x.package.name
    )

    unused_build_target_overrides = set(build_target_overrides.keys()) - set(
        package_targets_by_package_key
    )
    if unused_build_target_overrides:
        raise Exception(
            f"Build target overrides specified for non-existent packages: {unused_build_target_overrides}"
        )

    unused_always_build_packages = always_build_packages - set(
        package_targets_by_package_key
    )
    if unused_always_build_packages:
        raise Exception(
            f"Always build specified for non-existent packages: {unused_always_build_packages}"
        )

    repos = []
    for package in package_targets:
        for source in package.distinct_package_sources:
            if source.remote_wheel:
                repos.append(WheelRepoTarget(source.remote_wheel, context))
            elif source.remote_sdist:
                repos.append(SdistRepoTarget(source.remote_sdist, context))

    repos.sort(key=lambda ft: ft.name)

    pins = dict(lock_model.pins)
    if args.default_pin_latest:
        packages_by_name = defaultdict(list)
        for package in lock_model.packages.values():
            packages_by_name[package.name].append(package)

        for package_name, packages in packages_by_name.items():
            if package_name in pins:
                continue
            latest = max(packages, key=lambda p: p.version)
            pins[package_name] = latest.key

    with open(output, "w") as f:

        def w(*text):
            if not text:
                text = [""]
            for t in text:
                print(t, file=f)

        # Header stuff
        w(
            'load("@bazel_tools//tools/build_defs/repo:http.bzl", "http_file")',
            'load("@bazel_tools//tools/build_defs/repo:utils.bzl", "maybe")',
            'load("@jvolkman_rules_pycross//pycross:defs.bzl", "pycross_wheel_build", "pycross_wheel_library")',
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

        for environment in sorted(environments, key=lambda x: x.name.lower()):
            env_target = EnvTarget(
                environment.name, environment.python_compatible_with, naming
            )
            w(ind(env_target.render()))
            w()

        for e in package_targets:
            w(ind(e.render()))
            w()

        # Repos
        w("def repositories():")
        for r in repos:
            w(ind(r.render()))
            w()


def make_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Generate pycross dependency bzl file."
    )

    parser.add_argument(
        "--repo-prefix",
        type=str,
        required=False,
        default="",
        help="The prefix to apply to repository targets.",
    )

    parser.add_argument(
        "--package-prefix",
        type=str,
        required=False,
        default="",
        help="The prefix to apply to packages targets.",
    )

    parser.add_argument(
        "--build-prefix",
        type=str,
        required=False,
        default="",
        help="The prefix to apply to package build targets.",
    )

    parser.add_argument(
        "--environment-prefix",
        type=str,
        required=False,
        default="",
        help="The prefix to apply to packages environment targets.",
    )

    parser.add_argument(
        "--lock-model-file",
        type=str,
        required=True,
        help="The path to the lock model JSON file.",
    )

    parser.add_argument(
        "--target-environment-file",
        type=str,
        action="append",
        help="A pycross_target_environment output file.",
    )

    parser.add_argument(
        "--file-url-override",
        type=str,
        action="append",
        help="A file=url parameter that sets the URL for the given wheel or sdist file.",
    )

    parser.add_argument(
        "--local-wheel",
        type=str,
        action="append",
        help="A file=label parameter that points to a wheel file in the local repository.",
    )

    parser.add_argument(
        "--remote-wheel",
        type=str,
        action="append",
        help="A url=sha256 parameter that points to a remote wheel.",
    )

    parser.add_argument(
        "--default-pin-latest",
        action="store_true",
        help="Generate aliases for the latest versions of packages not covered by the lock model's pins.",
    )

    parser.add_argument(
        "--build-target-override",
        type=str,
        action="append",
        help="A key=target parameter that specifies the existing pycross_wheel_build target for a package key.",
    )

    parser.add_argument(
        "--always-build-package",
        type=str,
        action="append",
        help="A package key that should always be built from source.",
    )

    parser.add_argument(
        "--output",
        type=str,
        required=True,
        help="The path to the output bzl file.",
    )

    return parser


if __name__ == "__main__":
    # When under `bazel run`, change to the actual working dir.
    if "BUILD_WORKING_DIRECTORY" in os.environ:
        os.chdir(os.environ["BUILD_WORKING_DIRECTORY"])

    sys.exit(main())
