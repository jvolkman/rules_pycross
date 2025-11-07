from __future__ import annotations

import json
import textwrap
from argparse import ArgumentParser
from collections import defaultdict
from dataclasses import dataclass
from functools import cached_property
from pathlib import Path
from typing import Any
from typing import Dict
from typing import Iterator
from typing import List
from typing import Optional
from typing import Set
from typing import TextIO
from typing import Union

from pycross.private.tools.args import FlagFileArgumentParser
from pycross.private.tools.lock_model import ConfigSetting
from pycross.private.tools.lock_model import FileKey
from pycross.private.tools.lock_model import FileReference
from pycross.private.tools.lock_model import package_canonical_name
from pycross.private.tools.lock_model import PackageFile
from pycross.private.tools.lock_model import PackageKey
from pycross.private.tools.lock_model import ResolvedLockSet
from pycross.private.tools.lock_model import ResolvedPackage


def ind(text: str, tabs=1):
    """Indent text with the given number of tabs."""
    return textwrap.indent(text, "    " * tabs)


def quoted_str(text: str) -> str:
    """Return text wrapped in double quotes."""
    return json.dumps(text)


def sanitized(name: str) -> str:
    return name.lower().replace("-", "_").replace("@", "_").replace("+", "_")


def prefixed(name: str, prefix: Optional[str]):
    if not prefix:
        return name
    # Strip any trailing underscores from the provided prefix, first, then add one of our own.
    return prefix.rstrip("_") + "_" + name


@dataclass(frozen=True)
class TargetRef:
    """A reference to a target, able to generate a label."""

    target: str
    package: Optional[str] = None
    repo: Optional[str] = None

    def __post_init__(self):
        if self.repo is not None:
            if self.package is None:
                raise ValueError("package must be specified with repo")

    @cached_property
    def label(self):
        repo_part = f"@{self.repo}" if self.repo is not None else ""
        package_part = f"//{self.package}" if self.package is not None else ""
        target_part = f":{self.target}"
        # Handle special case target shorthand
        if package_part:
            _, last_component = package_part.rsplit("/", 1)
            if last_component == self.target:
                target_part = ""

        return repo_part + package_part + target_part


@dataclass(frozen=True)
class QualifiedTargetRef(TargetRef):
    """A TargetRef where all components are required."""

    package: str
    repo: str


class Naming:
    def __init__(
        self,
        repo_prefix: Optional[str],
        target_environment_select: str,
    ):
        self.repo_prefix = repo_prefix
        self.target_environment_select = target_environment_select

    def package(self, package_key: PackageKey) -> TargetRef:
        return TargetRef(str(package_key))

    def environment(self, environment_name: str) -> TargetRef:
        return TargetRef(prefixed(environment_name, "_env"))

    def wheel_build(self, package_key: PackageKey) -> TargetRef:
        return TargetRef(prefixed(str(package_key), "_build"))

    def wheel(self, package_key: PackageKey) -> TargetRef:
        return TargetRef(prefixed(str(package_key), "_wheel"))

    def sdist(self, package_key: PackageKey) -> TargetRef:
        return TargetRef(prefixed(str(package_key), "_sdist"))

    def repo_file(self, file: PackageFile) -> QualifiedTargetRef:
        name = file.name
        for extension in [".tar.gz", ".zip", ".whl"]:
            if name.endswith(extension):
                name = name[: -len(extension)]
                break
        typ = "sdist" if file.is_sdist else "wheel"
        repo = f"{self.repo_prefix}_{typ}_{sanitized(name)}"
        return QualifiedTargetRef(repo=repo, package="file", target="file")


class EnvTarget:
    def __init__(self, environment_name: str, setting: ConfigSetting, naming: Naming):
        self.naming = naming
        self.environment_name = environment_name
        self.setting = setting

    def render(self) -> str:
        lines = [
            "native.config_setting(",
            ind(f'name = "{self.naming.environment(self.environment_name).target}",'),
        ]
        if self.setting.constraint_values:
            lines.append(ind("constraint_values = ["))
            for cv in self.setting.constraint_values:
                lines.append(ind(f"{quoted_str(cv)},", 2))
            lines.append(ind("],"))
        if self.setting.flag_values:
            lines.append(
                ind("flag_values = {"),
            )
            for flag, value in self.setting.flag_values.items():
                lines.append(ind(f"{quoted_str(flag)}: {quoted_str(value)},", 2))
            lines.append(ind("},"))
        lines.append(")")

        return "\n".join(lines)


class EnvAliasTarget:
    def __init__(self, environment_name: str, config_setting_target: str, naming: Naming):
        self.naming = naming
        self.environment_name = environment_name
        self.config_setting_target = config_setting_target

    def render(self) -> str:
        lines = [
            "native.alias(",
            ind(f"name = {quoted_str(self.naming.environment(self.environment_name).target)},"),
            ind(f"actual = {quoted_str(self.config_setting_target)},"),
            ")",
        ]
        return "\n".join(lines)


class PackageTarget:
    def __init__(
        self,
        package: ResolvedPackage,
        file_labels: Dict[FileKey, str],
        naming: Naming,
    ):
        self.package = package
        self.file_labels = file_labels
        self.naming = naming

    @cached_property
    def _sdist_label(self) -> Optional[str]:
        if self.package.sdist_file:
            key = self.package.sdist_file.key
            if key is not None and key.is_sdist:
                return self.file_labels[key]

    @property
    def _has_runtime_deps(self) -> bool:
        return bool(self.package.common_dependencies or self.package.environment_dependencies)

    @property
    def _has_build_deps(self) -> bool:
        return bool(self.package.build_dependencies)

    @property
    def _has_sdist(self) -> bool:
        return self._sdist_label is not None

    @cached_property
    def _needs_generated_build_target(self) -> bool:
        if self.package.build_target:
            return False
        for f in self.package.environment_files.values():
            if f.key and f.key.is_sdist:
                return True
        return False

    @property
    def imports(self) -> Set[str]:
        if self._has_sdist and not self.package.build_target:
            return {"pycross_wheel_build", "pycross_wheel_library"}
        else:
            return {"pycross_wheel_library"}

    def _common_entries(self, deps: List[PackageKey], indent: int) -> Iterator[str]:
        for dep in deps:
            yield ind(f'"{self.naming.package(dep).label}",', indent)

    def _select_entries(self, env_deps: Dict[str, List[PackageKey]], indent) -> Iterator[str]:
        for env_name, deps in env_deps.items():
            yield ind(f'"{self.naming.environment(env_name).label}": [', indent)
            yield from self._common_entries(deps, indent + 1)
            yield ind("],", indent)
        yield ind('"//conditions:default": [],', indent)

    @cached_property
    def _deps_name(self):
        key_str = str(self.package.key)
        sanitized = key_str.replace("-", "_").replace(".", "_").replace("@", "_").replace("+", "_")
        return f"_{sanitized}_deps"

    @cached_property
    def _build_deps_name(self):
        key_str = str(self.package.key)
        sanitized = key_str.replace("-", "_").replace(".", "_").replace("@", "_").replace("+", "_")
        return f"_{sanitized}_build_deps"

    def _render_runtime_deps(self) -> str:
        lines = []

        if self.package.common_dependencies and self.package.environment_dependencies:
            lines.append(f"{self._deps_name} = [")
            lines.extend(self._common_entries(self.package.common_dependencies, 1))
            lines.append("] + select({")
            lines.extend(self._select_entries(self.package.environment_dependencies, 1))
            lines.append("})")

        elif self.package.common_dependencies:
            lines.append(f"{self._deps_name} = [")
            lines.extend(self._common_entries(self.package.common_dependencies, 1))
            lines.append("]")

        elif self.package.environment_dependencies:
            lines.append(self._deps_name + " = select({")
            lines.extend(self._select_entries(self.package.environment_dependencies, 1))
            lines.append("})")

        return "\n".join(lines)

    def _render_build_deps(self) -> str:
        lines = [f"{self._build_deps_name} = ["]
        for dep in sorted(self.package.build_dependencies, key=lambda k: self.naming.package(k).label):
            lines.append(ind(f'"{self.naming.package(dep).label}",', 1))
        lines.append("]")

        return "\n".join(lines)

    def _render_sdist(self) -> str:
        sdist_label = self._sdist_label
        assert self._sdist_label

        lines = [
            "native.alias(",
            ind(f'name = "{self.naming.sdist(self.package.key).target}",'),
            ind(f'actual = "{sdist_label}",'),
            ")",
        ]

        return "\n".join(lines)

    def _render_build(self) -> str:
        assert self._has_sdist

        lines = [
            "pycross_wheel_build(",
            ind(f'name = "{self.naming.wheel_build(self.package.key).target}",'),
            ind(f'sdist = "{self.naming.sdist(self.package.key).label}",'),
            ind(f"target_environment = {self.naming.target_environment_select},"),
        ]

        dep_names = []
        if self._has_runtime_deps:
            dep_names.append(self._deps_name)
        if self._has_build_deps:
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

    def _render_wheel(self) -> str:
        lines = [
            "native.alias(",
            ind(f'name = "{self.naming.wheel(self.package.key).target}",'),
        ]
        # Add the wheel alias target.
        # If all environments use the same wheel, don't use select.

        def wheel_target(file_ref: FileReference) -> str:
            if file_ref.label:
                return file_ref.label

            assert file_ref.key
            if file_ref.key.is_wheel:
                return self.file_labels[file_ref.key]
            elif self.package.build_target:
                return self.package.build_target
            else:
                return self.naming.wheel_build(self.package.key).label

        distinct_file_refs = set(self.package.environment_files.values())
        if len(distinct_file_refs) == 1:
            source = next(iter(distinct_file_refs))
            lines.append(ind(f'actual = "{wheel_target(source)}",'))
        else:
            lines.append(ind("actual = select({"))
            for env_name, ref in self.package.environment_files.items():
                lines.append(
                    ind(
                        f'"{self.naming.environment(env_name).label}": "{wheel_target(ref)}",',
                        2,
                    )
                )
            lines.append(ind("}),"))

        lines.append(")")

        return "\n".join(lines)

    def _render_pkg(self) -> str:
        lines = [
            "pycross_wheel_library(",
            ind(f'name = "{self.naming.package(self.package.key).target}",'),
        ]
        if self._has_runtime_deps:
            lines.append(ind(f"deps = {self._deps_name},"))

        lines.append(ind(f'wheel = "{self.naming.wheel(self.package.key).label}",'))

        if self.package.install_exclude_globs:
            lines.append(ind("install_exclude_globs = ["))
            for install_exclude_glob in self.package.install_exclude_globs:
                lines.append(ind(f'"{install_exclude_glob}",', 2))
            lines.append(ind("],"))

        if self.package.post_install_patches:
            lines.append(ind("post_install_patches = ["))
            for post_install_patch in self.package.post_install_patches:
                lines.append(ind(f'"{post_install_patch}",', 2))
            lines.append(ind("],"))

        lines.append(")")

        return "\n".join(lines)

    def render(self) -> str:
        parts = []
        if self._has_runtime_deps:
            parts.append(self._render_runtime_deps())
            parts.append("")
        if self._has_sdist:
            parts.append(self._render_sdist())
            parts.append("")
        if self._needs_generated_build_target:
            if self.package.build_dependencies:
                parts.append(self._render_build_deps())
                parts.append("")
            parts.append(self._render_build())
            parts.append("")
        parts.append(self._render_wheel())
        parts.append("")
        parts.append(self._render_pkg())
        return "\n".join(parts)


class UrlRepoTarget:
    def __init__(self, name: str, file: PackageFile):
        assert file.urls, "UrlWheelRepoTarget requires a PackageFile with one or more URLs"
        self.name = name
        self.file = file

    @property
    def imports(self) -> Set[str]:
        return {"maybe", "http_file"}

    def render(self) -> str:
        parts = []
        parts.extend(
            [
                "maybe(",
                ind("http_file,"),
                ind(f'name = "{self.name}",'),
                ind("urls = ["),
            ]
        )

        urls = sorted(self.file.urls or [])
        for url in urls:
            parts.append(ind(f'"{url}",', 2))

        parts.extend(
            [
                ind("],"),
                ind(f'sha256 = "{self.file.sha256}",'),
                ind(f'downloaded_file_path = "{self.file.name}",'),
                ")",
            ]
        )

        return "\n".join(parts)


class PypiFileRepoTarget:
    def __init__(self, name: str, file: PackageFile, pypi_index: Optional[str]):
        self.name = name
        self.file = file
        self.pypi_index = pypi_index

    @property
    def imports(self) -> Set[str]:
        return {"maybe", "pypi_file"}

    def render(self) -> str:
        lines = [
            "maybe(",
            ind("pypi_file,"),
            ind(f'name = "{self.name}",'),
            ind(f'package_name = "{self.file.package_name}",'),
            ind(f'package_version = "{self.file.package_version}",'),
            ind(f'filename = "{self.file.name}",'),
            ind(f'sha256 = "{self.file.sha256}",'),
        ]

        if self.pypi_index:
            lines.append(ind(f'index = "{self.pypi_index}",'))

        lines.append(")")

        return "\n".join(lines)


def gen_load_statements(imports: Set[str], pycross_repo: str) -> List[str]:
    possible_imports = {
        "http_file": "@bazel_tools//tools/build_defs/repo:http.bzl",
        "maybe": "@bazel_tools//tools/build_defs/repo:utils.bzl",
        "pycross_wheel_build": f"{pycross_repo}//pycross:defs.bzl",
        "pycross_wheel_library": f"{pycross_repo}//pycross:defs.bzl",
        "pypi_file": f"{pycross_repo}//pycross:defs.bzl",
    }

    load_statement_groups = defaultdict(list)
    for i in imports:
        load_statement_groups[possible_imports[i]].append(i)

    # External repo loads come before local loads.
    sorted_files = sorted(load_statement_groups, key=lambda f: (1 if f.startswith("@@") else (0 if f.startswith("@") else 2), f))

    lines = []
    for file in sorted_files:
        file_imports = load_statement_groups[file]
        lines.append(f"load({quoted_str(file)}, {', '.join(quoted_str(i) for i in sorted(file_imports))})")

    return lines


def render(resolved_lock: ResolvedLockSet, args: Any, output: TextIO) -> None:
    naming = Naming(
        repo_prefix=args.repo_prefix,
        target_environment_select="_target",
    )

    pypi_index = args.pypi_index or None

    repo_labels = {FileKey(key): label for key, label in (args.repo or [])}
    repo_targets: List[Union[PypiFileRepoTarget, UrlRepoTarget]] = []

    for file_key, file in resolved_lock.remote_files.items():
        if file_key in repo_labels:
            continue

        target = naming.repo_file(file)
        name = target.repo
        repo_labels[file_key] = target.label

        if file.urls:
            repo_targets.append(UrlRepoTarget(name, file))
        else:
            repo_targets.append(PypiFileRepoTarget(name, file, pypi_index))

    repo_targets.sort(key=lambda rt: rt.name)

    package_targets = [
        PackageTarget(
            package=p,
            file_labels=repo_labels,
            naming=naming,
        )
        for p in resolved_lock.packages.values()
    ]

    # pin aliases follow the standard package normalization rules.
    # https://packaging.python.org/en/latest/specifications/name-normalization/#name-normalization
    def pin_name(name: str) -> str:
        return package_canonical_name(name)

    pins = {pin_name(k): v for k, v in resolved_lock.pins.items()}

    # Figure out which load statements we need.
    imports = set()
    for p in package_targets:
        imports.update(p.imports)
    for r in repo_targets:
        imports.update(r.imports)
    load_statements = gen_load_statements(imports, args.pycross_repo_name)

    def w(*text):
        if not text:
            text = [""]
        for t in text:
            print(t, file=output)

    w(
        "# This file is generated by rules_pycross.",
        "# It is not intended for manual editing.",
        '"""Pycross-generated dependency targets."""',
        "",
    )
    if load_statements:
        w(*load_statements)
        w()

    # Build PINS map
    if not args.no_pins:
        if pins:
            w("PINS = {")
            for pinned_package_name in sorted(pins.keys()):
                pinned_package_key = pins[pinned_package_name]
                w(ind(f"{quoted_str(pinned_package_name)}: {quoted_str(naming.package(pinned_package_key).target)},"))
            w("}")
            w()
        else:
            w("PINS = {}")
            w()

    if args.generate_file_map:
        if repo_targets:
            w("FILES = {")
            for repo in repo_targets:
                label = f"@{repo.name}//file:{repo.file.name}"
                w(ind(f"{quoted_str(repo.file.name)}: Label({quoted_str(label)}),"))
            w("}")
            w()
        else:
            w("FILES = {}")
            w()

    # Build targets
    w(
        "# buildifier: disable=unnamed-macro",
        "def targets():",
        ind('"""Generated package targets."""'),
        "",
    )

    if not args.no_pins:
        # Create pin aliases based on the PINS dict above.
        w(
            ind("for pin_name, pin_target in PINS.items():", 1),
            ind("native.alias(", 2),
            ind("name = pin_name,", 3),
            ind('actual = ":" + pin_target,', 3),
            ind(")", 2),
        )
        w()

    for env_name, env_ref in resolved_lock.environments.items():
        if env_ref.config_setting_label:
            env_target = EnvAliasTarget(env_name, env_ref.config_setting_label, naming)
        else:
            assert env_ref.config_setting
            env_target = EnvTarget(env_name, env_ref.config_setting, naming)
        w(ind(env_target.render()))
        w()

    w(ind("# buildifier: disable=unused-variable"))
    w(ind(f"{naming.target_environment_select} = select({{"))
    for env_name, env_ref in resolved_lock.environments.items():
        w(
            ind(
                f'"{naming.environment(env_name).label}": "{env_ref.environment_label}",',
                2,
            )
        )
    w(ind("})"))

    for e in package_targets:
        w()
        w(ind(e.render()))

    # Repos
    w(
        "",
        "# buildifier: disable=unnamed-macro",
        "def repositories():",
        ind('"""Generated package repositories."""'),
    )
    for r in repo_targets:
        w()
        w(ind(r.render()))


def add_shared_flags(parser: ArgumentParser) -> None:
    parser.add_argument(
        "--repo",
        nargs=2,
        action="append",
        help="A (file_key, label) parameter that maps a FileKey to a label that provides it.",
    )

    parser.add_argument(
        "--repo-prefix",
        type=str,
        default="",
        help="The prefix to apply to repository targets.",
    )

    parser.add_argument(
        "--pypi-index",
        help="The PyPI-compatible index to use. Defaults to pypi.org.",
    )

    parser.add_argument(
        "--generate-file-map",
        action="store_true",
        help="Generate a FILES dict containing a mapping of filenames to repo labels.",
    )

    parser.add_argument(
        "--pycross-repo-name",
        default="@rules_pycross",
        help="Our own repo name.",
    )

    parser.add_argument(
        "--no-pins",
        action="store_true",
        help="Don't create pinned alias targets.",
    )


def parse_flags() -> Any:
    parser = FlagFileArgumentParser(description="Generate pycross dependency bzl file.")

    add_shared_flags(parser)
    parser.add_argument(
        "--resolved-lock",
        type=Path,
        required=True,
        help="The path to the resolved lock structure.",
    )
    parser.add_argument(
        "--output",
        type=Path,
        required=True,
        help="The path to the output bzl file.",
    )

    return parser.parse_args()


def main(args: Any) -> None:
    with open(args.resolved_lock, "r") as f:
        resolved_lock = ResolvedLockSet.from_json(f.read())
    with open(args.output, "w") as f:
        render(resolved_lock, args, f)


if __name__ == "__main__":
    main(parse_flags())
