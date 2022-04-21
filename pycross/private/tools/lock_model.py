from __future__ import annotations

import dataclasses
from dataclasses import dataclass
from typing import Any
from typing import Dict
from typing import List

from packaging.utils import NormalizedName, canonicalize_name

import dacite


@dataclass(frozen=True)
class PackageFile:
    name: str
    sha256: str

    def __post_init__(self):
        assert self.name, "The name field must be specified."
        assert self.sha256, "The sha256 field must be specified."

    @property
    def is_wheel(self) -> bool:
        return is_wheel(self.name)


@dataclass(frozen=True)
class PackageDependency:
    key: str
    marker: str

    def __post_init__(self):
        assert self.key, "The key field must be specified."
        assert (
            self.marker is not None
        ), "The marker field must be specified, or an empty string."


@dataclass(frozen=True)
class Package:
    name: NormalizedName
    version: str
    python_versions: str
    dependencies: List[PackageDependency]
    files: List[PackageFile]

    def __post_init__(self):
        normalized_name = package_canonical_name(self.name)
        assert str(self.name) == str(normalized_name), "The name field should be normalized per PEP 503."
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
    def key(self):
        return f"{self.name}-{self.version}"


@dataclass(frozen=True)
class LockSet:
    packages: Dict[str, Package]
    pins: Dict[str, str]

    def __post_init__(self):
        assert self.packages is not None, "The packages field must be specified."
        assert self.pins is not None, "The pins field must be specified."

    def to_dict(self) -> Dict[str, Any]:
        return dataclasses.asdict(self)

    @staticmethod
    def from_dict(data: Dict[str, Any]) -> LockSet:
        return dacite.from_dict(LockSet, data)


def package_canonical_name(name: str) -> NormalizedName:
    return canonicalize_name(name)


def is_wheel(filename: str) -> bool:
    return filename.lower().endswith(".whl")
