from __future__ import annotations

import dataclasses
import json
from dataclasses import dataclass
from dataclasses import field
from functools import cached_property
from json import JSONEncoder
from typing import Any
from typing import Dict
from typing import Iterator
from typing import List
from typing import Optional
from typing import Tuple

from dacite.config import Config
from dacite.core import from_dict
from packaging.utils import canonicalize_name
from packaging.utils import NormalizedName
from packaging.utils import parse_sdist_filename
from packaging.utils import parse_wheel_filename
from packaging.version import Version

from pycross.private.tools.target_environment import TargetEnv


class _Encoder(JSONEncoder):
    def default(self, o):
        def _is_empty(val):
            if val is None:
                return True
            if isinstance(val, (list, dict)):
                return len(val) == 0
            return False

        if isinstance(o, (FileKey, PackageKey, Version)):
            return str(o)
        if dataclasses.is_dataclass(o):
            # Omit None values from serialized output.
            return {k: v for k, v in o.__dict__.items() if not _is_empty(v)}
        return super().default(o)


def _stringify_keys(original: Dict[Any, Any]) -> Dict[str, Any]:
    """
    Return original with keys stringified.

    The json module's encoder does not support complex key types, such as
    PackageKey and FileKey. We stringify these values before passing them to
    json.
    """
    return {str(key): val for key, val in original.items()}


def _dataclass_items(dc) -> Iterator[Tuple[str, Any]]:
    for item in dataclasses.fields(dc):
        yield item.name, getattr(dc, item.name)


@dataclass(frozen=True, order=True)
class PackageKey:
    name: NormalizedName
    version: Version

    def __init__(self, val) -> None:
        name, version = val.split("@", maxsplit=1)
        object.__setattr__(self, "name", package_canonical_name(name))
        object.__setattr__(self, "version", Version(version))

    @staticmethod
    def from_parts(name: NormalizedName, version: Version) -> PackageKey:
        return PackageKey(f"{name}@{version}")

    def __str__(self) -> str:
        return f"{self.name}@{self.version}"


@dataclass(frozen=True, order=True)
class FileKey:
    name: str
    hash_prefix: str

    def __init__(self, val: str) -> None:
        name, hash_prefix = val.split("/", maxsplit=1)
        object.__setattr__(self, "name", name)
        object.__setattr__(self, "hash_prefix", hash_prefix)

    @staticmethod
    def from_parts(name: str, hash_prefix: str) -> FileKey:
        return FileKey(f"{name}/{hash_prefix}")

    @property
    def is_wheel(self) -> bool:
        return is_wheel(self.name)

    @property
    def is_sdist(self) -> bool:
        return not self.is_wheel

    def __str__(self) -> str:
        return f"{self.name}/{self.hash_prefix}"


@dataclass(frozen=True)
class FileReference:
    label: Optional[str] = None
    key: Optional[FileKey] = None

    def __post_init__(self):
        assert (
            int(self.label is not None) + int(self.key is not None) == 1
        ), "Exactly one of label or key must be specified."


@dataclass
class ConfigSetting:
    constraint_values: List[str] = field(default_factory=list)
    flag_values: Dict[str, str] = field(default_factory=dict)


@dataclass(frozen=True)
class EnvironmentReference:
    environment_label: str
    config_setting: Optional[ConfigSetting] = None
    config_setting_label: Optional[str] = None

    def __post_init__(self):
        assert (
            int(self.config_setting is not None) + int(self.config_setting_label is not None) == 1
        ), "Exactly one of config_setting or config_setting_label must be specified."

    @classmethod
    def from_target_env(cls, environment_label: str, target_env: TargetEnv) -> EnvironmentReference:
        if target_env.config_setting_target:
            return cls(
                environment_label=environment_label,
                config_setting_label=target_env.config_setting_target,
            )
        else:
            return cls(
                environment_label=environment_label,
                config_setting=ConfigSetting(
                    constraint_values=target_env.python_compatible_with,
                    flag_values=target_env.flag_values,
                ),
            )


@dataclass(frozen=True)
class PackageFile:
    name: str
    sha256: str
    urls: Tuple[str, ...] = field(default_factory=tuple)
    package_name: Optional[NormalizedName] = None
    package_version: Optional[Version] = None

    def __post_init__(self):
        assert self.name, "The name field must be specified."
        assert self.sha256, "The sha256 field must be specified."
        if self.package_name is None or self.package_version is None:
            # Derive package name + version from file name
            if is_wheel(self.name):
                name, version, _, _ = parse_wheel_filename(self.name)
            else:
                name, version = parse_sdist_filename(self.name)
            if self.package_name is None:
                object.__setattr__(self, "package_name", name)
            if self.package_version is None:
                object.__setattr__(self, "package_version", version)

    @property
    def is_wheel(self) -> bool:
        return is_wheel(self.name)

    @property
    def is_sdist(self) -> bool:
        return not self.is_wheel

    @cached_property
    def key(self) -> FileKey:
        return FileKey.from_parts(self.name, self.sha256[:8])


@dataclass(frozen=True)
class PackageDependency:
    name: NormalizedName
    version: Version
    marker: str

    def __post_init__(self):
        assert self.name, "The name field must be specified."
        assert self.version, "The version field must be specified."
        assert self.marker is not None, "The marker field must be specified, or an empty string."

    @property
    def key(self) -> PackageKey:
        return PackageKey.from_parts(self.name, self.version)


@dataclass(frozen=True)
class RawPackage:
    name: NormalizedName
    version: Version
    python_versions: str
    dependencies: List[PackageDependency] = field(default_factory=list)
    files: List[PackageFile] = field(default_factory=list)

    def __post_init__(self):
        normalized_name = package_canonical_name(self.name)
        assert str(self.name) == str(normalized_name), "The name field should be normalized per PEP 503."
        object.__setattr__(self, "name", normalized_name)

        assert self.version, "The version field must be specified."
        assert self.python_versions is not None, "The python_versions field must be specified, or an empty string."
        assert self.dependencies is not None, "The dependencies field must be specified as a list."
        assert self.files, "The files field must not be empty."

    @property
    def key(self) -> PackageKey:
        return PackageKey.from_parts(self.name, self.version)


@dataclass
class ResolvedPackage:
    key: PackageKey
    build_dependencies: List[PackageKey] = field(default_factory=list)
    common_dependencies: List[PackageKey] = field(default_factory=list)
    environment_dependencies: Dict[str, List[PackageKey]] = field(default_factory=dict)
    build_target: Optional[str] = None
    environment_files: Dict[str, FileReference] = field(default_factory=dict)


@dataclass(frozen=True)
class RawLockSet:
    packages: Dict[PackageKey, RawPackage] = field(default_factory=dict)
    pins: Dict[NormalizedName, PackageKey] = field(default_factory=dict)

    @property
    def __dict__(self) -> Dict[str, Any]:
        return dict(_dataclass_items(self), packages=_stringify_keys(self.packages))

    def to_json(self, indent=None) -> str:
        return json.dumps(self, sort_keys=True, indent=indent, cls=_Encoder)

    @classmethod
    def from_json(cls, data: str) -> RawLockSet:
        parsed = json.loads(data)
        return from_dict(RawLockSet, parsed, config=Config(cast=[Tuple, Version, PackageKey]))


@dataclass(frozen=True)
class ResolvedLockSet:
    environments: Dict[str, EnvironmentReference] = field(default_factory=dict)
    packages: Dict[PackageKey, ResolvedPackage] = field(default_factory=dict)
    pins: Dict[NormalizedName, PackageKey] = field(default_factory=dict)
    remote_files: Dict[FileKey, PackageFile] = field(default_factory=dict)

    @property
    def __dict__(self) -> Dict[str, Any]:
        return dict(
            _dataclass_items(self),
            packages=_stringify_keys(self.packages),
            remote_files=_stringify_keys(self.remote_files),
        )

    def to_json(self, indent=None) -> str:
        return json.dumps(self, sort_keys=True, indent=indent, cls=_Encoder)

    @classmethod
    def from_json(cls, data: str) -> ResolvedLockSet:
        parsed = json.loads(data)
        return from_dict(ResolvedLockSet, parsed, config=Config(cast=[Tuple, Version, FileKey, PackageKey]))


def package_canonical_name(name: str) -> NormalizedName:
    return canonicalize_name(name)


def is_wheel(filename: str) -> bool:
    return filename.lower().endswith(".whl")
