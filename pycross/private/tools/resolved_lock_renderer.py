import json
import os
import textwrap
from argparse import ArgumentParser
from collections import defaultdict
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


class Naming:
    def __init__(
        self,
        package_prefix: Optional[str],
        build_prefix: Optional[str],
        environment_prefix: Optional[str],
        repo_prefix: Optional[str],
        target_environment_select: str,
    ):
        self.package_prefix = package_prefix
        self.build_prefix = build_prefix
        self.environment_prefix = environment_prefix
        self.repo_prefix = repo_prefix
        self.target_environment_select = target_environment_select

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
        normalized_name = file.name[:-4].lower().replace("-", "_").replace("+", "_").replace("%2b", "_")
        return f"{self.repo_prefix}_wheel_{normalized_name}"

    def wheel_label(self, file: PackageFile):
        assert file.is_wheel
        return f"@{self.wheel_repo(file)}//file"


class EnvTarget:
    def __init__(self, environment_name: str, setting: ConfigSetting, naming: Naming):
        self.naming = naming
        self.environment_name = environment_name
        self.setting = setting

    def render(self) -> str:
        lines = [
            "native.config_setting(",
            ind(f'name = "{self.naming.environment_target(self.environment_name)}",'),
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
            ind(f"name = {quoted_str(self.naming.environment_target(self.environment_name))},"),
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
        for f in self.package.environment_files.values():
            key = f.key
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

    @property
    def imports(self) -> Set[str]:
        if self._has_sdist and not self.package.build_target:
            return {"pycross_wheel_build", "pycross_wheel_library"}
        else:
            return {"pycross_wheel_library"}

    def _common_entries(self, deps: List[PackageKey], indent: int) -> Iterator[str]:
        for dep in deps:
            yield ind(f'"{self.naming.package_label(dep)}",', indent)

    def _select_entries(self, env_deps: Dict[str, List[PackageKey]], indent) -> Iterator[str]:
        for env_name, deps in env_deps.items():
            yield ind(f'"{self.naming.environment_label(env_name)}": [', indent)
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
        for dep in sorted(self.package.build_dependencies, key=lambda k: self.naming.package_label(k)):
            lines.append(ind(f'"{self.naming.package_label(dep)}",', 1))
        lines.append("]")

        return "\n".join(lines)

    def _render_build(self) -> str:
        sdist_label = self._sdist_label
        assert sdist_label is not None

        lines = [
            "pycross_wheel_build(",
            ind(f'name = "{self.naming.wheel_build_target(self.package.key)}",'),
            ind(f'sdist = "{sdist_label}",'),
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

    def _render_pkg(self) -> str:
        lines = [
            "pycross_wheel_library(",
            ind(f'name = "{self.naming.package_target(self.package.key)}",'),
        ]
        if self._has_runtime_deps:
            lines.append(ind(f"deps = {self._deps_name},"))

        # Add the wheel attribute.
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
                return self.naming.wheel_build_label(self.package.key)

        distinct_file_refs = set(self.package.environment_files.values())
        if len(distinct_file_refs) == 1:
            source = next(iter(distinct_file_refs))
            lines.append(ind(f'wheel = "{wheel_target(source)}",'))
        else:
            lines.append(ind("wheel = select({"))
            for env_name, ref in self.package.environment_files.items():
                lines.append(
                    ind(
                        f'"{self.naming.environment_label(env_name)}": "{wheel_target(ref)}",',
                        2,
                    )
                )
            lines.append(ind("}),"))

        lines.append(")")

        return "\n".join(lines)

    def render(self) -> str:
        parts = []
        if self._has_runtime_deps:
            parts.append(self._render_runtime_deps())
            parts.append("")
        if self._has_sdist and not self.package.build_target:
            if self.package.build_dependencies:
                parts.append(self._render_build_deps())
                parts.append("")
            parts.append(self._render_build())
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


class PypiWheelRepoTarget(PypiFileRepoTarget):
    def __init__(
        self,
        file: PackageFile,
        pypi_index: Optional[str],
        naming: Naming,
    ):
        super().__init__(naming.wheel_repo(file), file, pypi_index)


class PypiSdistRepoTarget(PypiFileRepoTarget):
    def __init__(
        self,
        file: PackageFile,
        pypi_index: Optional[str],
        naming: Naming,
    ):
        super().__init__(naming.sdist_repo(file), file, pypi_index)


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
    sorted_files = sorted(load_statement_groups, key=lambda f: (0 if f.startswith("@") else 1, f))

    lines = []
    for file in sorted_files:
        file_imports = load_statement_groups[file]
        lines.append(f"load({quoted_str(file)}, {', '.join(quoted_str(i) for i in sorted(file_imports))})")

    return lines


def render(resolved_lock: ResolvedLockSet, args: Any, output: TextIO) -> None:
    naming = Naming(
        repo_prefix=args.repo_prefix,
        package_prefix=args.package_prefix,
        build_prefix=args.build_prefix,
        environment_prefix=args.environment_prefix,
        target_environment_select="_target",
    )

    pypi_index = args.pypi_index or None

    repo_labels = {FileKey(key): label for key, label in (args.repo or [])}
    repo_targets: List[Union[PypiFileRepoTarget, UrlRepoTarget]] = []

    for file_key, file in resolved_lock.remote_files.items():
        if file_key in repo_labels:
            continue

        if file.is_wheel:
            name = naming.wheel_repo(file)
            repo_labels[file_key] = naming.wheel_label(file)
        else:
            name = naming.sdist_repo(file)
            repo_labels[file_key] = naming.sdist_label(file)

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

    # pin aliases are normalized package names with underscores rather than hashes.
    def pin_name(name: str) -> str:
        normal_name = package_canonical_name(name)
        return normal_name.lower().replace("-", "_")

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
    if pins:
        w("PINS = {")
        for pinned_package_name in sorted(pins.keys()):
            pinned_package_key = pins[pinned_package_name]
            w(ind(f"{quoted_str(pinned_package_name)}: {quoted_str(naming.package_target(pinned_package_key))},"))
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
                w(ind(f"{quoted_str(repo.file.name)}: {quoted_str(label)},"))
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
                f'"{naming.environment_label(env_name)}": "{env_ref.environment_label}",',
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
        help="Our own repo name",
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
    # When under `bazel run`, change to the actual working dir.
    if "BUILD_WORKING_DIRECTORY" in os.environ:
        os.chdir(os.environ["BUILD_WORKING_DIRECTORY"])

    main(parse_flags())
