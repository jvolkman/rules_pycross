from __future__ import annotations

import dataclasses
import json
from dataclasses import dataclass
from json import JSONEncoder
from typing import Any
from typing import Dict
from typing import List
from typing import Optional
from typing import Tuple

import dacite
from packaging.utils import NormalizedName
from packaging.utils import Version
from packaging.utils import canonicalize_name


class _TypeHandlingEncoder(JSONEncoder):
    def default(self, o):
        if isinstance(o, Version):
            return str(o)
        return super().default(o)


@dataclass(frozen=True)
class PackageFile:
    name: str
    sha256: str
    urls: Optional[Tuple[str, ...]] = None

    def __post_init__(self):
        assert self.name, "The name field must be specified."
        assert self.sha256, "The sha256 field must be specified."

    @property
    def is_wheel(self) -> bool:
        return is_wheel(self.name)

    @property
    def is_sdist(self) -> bool:
        return not self.is_wheel


class PackageKey(str):
    def __init__(self, val) -> None:
        name, version = val.split("@", maxsplit=1)
        self.name = package_canonical_name(name)
        self.version = Version(version)

    @staticmethod
    def from_parts(name: NormalizedName, version: Version) -> PackageKey:
        return PackageKey(f"{name}@{version}")


@dataclass(frozen=True)
class PackageDependency:
    name: NormalizedName
    version: Version
    marker: str

    def __post_init__(self):
        assert self.name, "The name field must be specified."
        assert self.version, "The version field must be specified."
        assert (
            self.marker is not None
        ), "The marker field must be specified, or an empty string."

    @property
    def key(self) -> PackageKey:
        return PackageKey.from_parts(self.name, self.version)


@dataclass(frozen=True)
class Package:
    name: NormalizedName
    version: Version
    python_versions: str
    dependencies: List[PackageDependency]
    files: List[PackageFile]

    def __post_init__(self):
        normalized_name = package_canonical_name(self.name)
        assert str(self.name) == str(
            normalized_name
        ), "The name field should be normalized per PEP 503."
        object.__setattr__(self, "name", normalized_name)

        assert self.version, "The version field must be specified."
        assert (
            self.python_versions is not None
        ), "The python_versions field must be specified, or an empty string."
        assert (
            self.dependencies is not None
        ), "The dependencies field must be specified as a list."
        assert self.files, "The files field must not be empty."

    @property
    def key(self) -> PackageKey:
        return PackageKey.from_parts(self.name, self.version)


@dataclass(frozen=True)
class LockSet:
    packages: Dict[PackageKey, Package]
    pins: Dict[NormalizedName, PackageKey]

    def __post_init__(self):
        assert self.packages is not None, "The packages field must be specified."
        assert self.pins is not None, "The pins field must be specified."

    def to_dict(self) -> Dict[str, Any]:
        return dataclasses.asdict(self)

    def to_json(self, indent=None) -> str:
        return json.dumps(
            self.to_dict(), sort_keys=True, indent=indent, cls=_TypeHandlingEncoder
        )

    @staticmethod
    def from_dict(data: Dict[str, Any]) -> LockSet:
        return dacite.from_dict(LockSet, data, config=dacite.Config(cast=[Tuple, Version, PackageKey]))

    @classmethod
    def from_json(cls, data: str) -> LockSet:
        parsed = json.loads(data)
        return cls.from_dict(parsed)


def package_canonical_name(name: str) -> NormalizedName:
    return canonicalize_name(name)


def is_wheel(filename: str) -> bool:
    return filename.lower().endswith(".whl")
