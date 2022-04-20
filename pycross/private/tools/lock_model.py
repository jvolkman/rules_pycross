from __future__ import annotations

import dataclasses
from dataclasses import dataclass
from typing import Any
from typing import Dict
from typing import List

import dacite


@dataclass
class PackageFile:
    name: str
    sha256: str


@dataclass
class PackageDependency:
    key: str
    marker: str


@dataclass
class Package:
    name: str
    version: str
    python_versions: str
    dependencies: List[PackageDependency]
    files: List[PackageFile]

    @property
    def key(self):
        return f"{self.name}-{self.version}"


@dataclass
class LockSet:
    packages: Dict[str, Package]
    pins: Dict[str, str]

    def to_dict(self) -> Dict[str, Any]:
        return dataclasses.asdict(self)

    @staticmethod
    def from_dict(data: Dict[str, Any]) -> LockSet:
        return dacite.from_dict(LockSet, data)


def package_canonical_name(name: str) -> str:
    # Canonical package names are lower-cased with dashes, not underscores.
    return name.lower().replace("_", "-")
