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
from typing import Union

from dacite.config import Config
from dacite.core import from_dict
from packaging.specifiers import SpecifierSet
from packaging.utils import NormalizedName
from packaging.utils import canonicalize_name
from packaging.utils import parse_sdist_filename
from packaging.utils import parse_wheel_filename
from packaging.version import Version


class _Encoder(JSONEncoder):
    def default(self, o):
        def _is_empty(val):
            if val is None:
                return True
            if isinstance(val, (list, dict)):
                return len(val) == 0
            return False

        if isinstance(o, (DependencyName, FileKey, PackageKey, SpecifierSet, Version)):
            return str(o)
        if isinstance(o, VariantItem):
            result = {"package": o.package, "kind": o.kind}
            if o.name:
                result["name"] = o.name
            if o.default:
                result["default"] = o.default
            return result
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


def _simplify_pins(pins: Dict[Any, Any]) -> Dict[str, Any]:
    """Simplify pins for serialization.

    Internally, pins always use {"":key} for unconditional entries.
    This is equivalent to a bare PackageKey and is simplified here.
    Conflicting pins (multiple constraint keys) remain as dicts.
    """
    result = {}
    for name, value in pins.items():
        if isinstance(value, dict) and list(value.keys()) == [""]:
            result[str(name)] = value[""]
        else:
            result[str(name)] = value
    return result


def _dataclass_items(dc) -> Iterator[Tuple[str, Any]]:
    for item in dataclasses.fields(dc):
        yield item.name, getattr(dc, item.name)


@dataclass(frozen=True)
class DependencyName:
    package: NormalizedName
    extra: Optional[NormalizedName]

    def __init__(self, val: Union[str, DependencyName]) -> None:
        val = str(val)
        package_name, bracket, extra_name = val.partition("[")

        if bracket:
            if not extra_name.endswith("]"):
                raise ValueError(f"Invalid format for package with extra: {val}")
            extra_name = extra_name[:-1]
            object.__setattr__(self, "extra", canonicalize_name(extra_name))
        else:
            object.__setattr__(self, "extra", None)

        object.__setattr__(self, "package", canonicalize_name(package_name))

    @staticmethod
    def from_parts(package: str, extra: Optional[str] = None) -> DependencyName:
        if extra:
            return DependencyName(f"{package}[{extra}]")
        else:
            return DependencyName(package)

    def __str__(self) -> str:
        if self.extra:
            return f"{self.package}[{self.extra}]"
        else:
            return str(self.package)

    def __eq__(self, other: Any) -> bool:
        if isinstance(other, str):
            return str(self) == other
        if isinstance(other, DependencyName):
            return self.package == other.package and self.extra == other.extra
        return False

    def __lt__(self, other: Any) -> bool:
        if not isinstance(other, DependencyName):
            return NotImplemented
        if self.package != other.package:
            return self.package < other.package
        if self.extra == other.extra:
            return False
        if self.extra is None:
            return True
        if other.extra is None:
            return False
        return self.extra < other.extra

    def __hash__(self) -> int:
        return hash(str(self))


@dataclass(frozen=True, order=True)
class PackageKey:
    name: DependencyName
    version: Version

    def __init__(self, val) -> None:
        if isinstance(val, PackageKey):
            object.__setattr__(self, "name", val.name)
            object.__setattr__(self, "version", val.version)
            return
        name, version = val.split("@", maxsplit=1)
        object.__setattr__(self, "name", package_canonical_name(name))
        object.__setattr__(self, "version", Version(version))

    @staticmethod
    def from_parts(name: Union[str, DependencyName], version: Version) -> "PackageKey":
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
class VariantItem:
    """A single item in a variant set.

    Each variant item identifies a specific dependency source that
    participates in a mutually exclusive variant set.

    Attributes:
        package: The workspace member name this variant belongs to.
        kind: One of "extra", "group", or "project".
        name: The extra or group name. Empty for project-level variants.
        default: True if this item is a default selection (e.g. from
            uv's default-groups). The Bazel select() maps
            //conditions:default to the target for the default item.
    """

    package: str
    kind: str  # "extra", "group", "project"
    name: str = ""
    default: bool = False

    @property
    def qualified_name(self) -> str:
        """A unique, Bazel-target-safe name for this variant item."""
        if self.kind == "project":
            return f"package_{self.package}"
        return f"{self.kind}_{self.name}"


@dataclass(frozen=True)
class VariantSet:
    """A set of mutually exclusive variant items (uv conflicts).

    Each VariantSet maps to a single string_flag in the generated
    Bazel repo. Users must select exactly one item from each set.
    """

    items: Tuple[VariantItem, ...] = field(default_factory=tuple)

    @property
    def setting_name(self) -> str:
        """The name of the string_flag for this variant set."""
        return "variants_" + "_".join(item.qualified_name for item in self.items)


@dataclass(frozen=True)
class FileReference:
    label: Optional[str] = None
    key: Optional[FileKey] = None

    def __post_init__(self):
        assert int(self.label is not None) + int(self.key is not None) == 1, (
            "Exactly one of label or key must be specified."
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
    name: DependencyName
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
    name: DependencyName
    version: Version
    python_versions: SpecifierSet
    python_version_specifiers: List[SpecifierSet] = field(default_factory=list)
    dependencies: List[PackageDependency] = field(default_factory=list)
    files: List[PackageFile] = field(default_factory=list)
    source_dir: Optional[str] = None

    def __post_init__(self):
        normalized_name = DependencyName(self.name)
        assert str(self.name) == str(normalized_name), "The name field should be normalized per PEP 503."
        object.__setattr__(self, "name", normalized_name)

        assert self.version, "The version field must be specified."
        assert self.python_versions is not None, "The python_versions field must be specified."
        assert self.python_version_specifiers is not None, "The python_version_specifiers field must be specified."
        assert self.dependencies is not None, "The dependencies field must be specified as a list."
        if not self.name.extra:
            assert self.files, "The files field must not be empty."

    @property
    def key(self) -> PackageKey:
        return PackageKey.from_parts(self.name, self.version)


@dataclass(frozen=True)
class MarkerDependency:
    """A dependency annotated with its PEP 508 marker expression."""

    key: PackageKey
    marker: Optional[str] = None  # Raw PEP 508 marker string, None = unconditional


@dataclass(frozen=True)
class WheelCandidate:
    """A wheel file candidate with pre-parsed compatibility tags."""

    filename: str
    file_reference: FileReference


@dataclass
class ResolvedPackage:
    key: PackageKey
    build_dependencies: List[PackageKey] = field(default_factory=list)
    build_repo: Optional[str] = None
    build_target: Optional[str] = None
    sdist_file: Optional[FileReference] = None
    install_exclude_globs: List[str] = field(default_factory=list)
    post_install_patches: List[str] = field(default_factory=list)
    pre_build_patches: List[str] = field(default_factory=list)
    site_hooks: List[str] = field(default_factory=list)
    build_backend: Optional[str] = None
    site_paths: List[str] = field(default_factory=list)
    bin_paths: List[str] = field(default_factory=list)
    data_paths: List[str] = field(default_factory=list)
    include_paths: List[str] = field(default_factory=list)
    cycle_group: Optional[str] = None
    source_dir: Optional[str] = None
    marker_dependencies: List[MarkerDependency] = field(default_factory=list)
    wheel_candidates: List[WheelCandidate] = field(default_factory=list)


@dataclass(frozen=True)
class RawLockSet:
    """The raw lock model produced by a translator.

    Pins map dependency names to package versions. For unconditional
    dependencies, the pin value is ``{"":PackageKey(...)}`` internally.
    This is equivalent to a bare ``PackageKey`` and is serialized as
    a plain string. Conflicting pins use qualified constraint names
    as dict keys.
    """

    python_versions: SpecifierSet
    packages: Dict[PackageKey, RawPackage] = field(default_factory=dict)
    pins: Dict[DependencyName, Union[PackageKey, Dict[str, PackageKey]]] = field(default_factory=dict)
    variants: List[VariantSet] = field(default_factory=list)

    def __post_init__(self):
        assert self.python_versions is not None, "The python_versions field must be specified."

    @property
    def __dict__(self) -> Dict[str, Any]:
        return dict(
            _dataclass_items(self),
            packages=_stringify_keys(self.packages),
            pins=_simplify_pins(self.pins),
        )

    def to_json(self, indent=None) -> str:
        return json.dumps(self, sort_keys=True, indent=indent, cls=_Encoder) + "\n"

    @classmethod
    def from_json(cls, data: str) -> RawLockSet:
        parsed = json.loads(data)
        if "packages" in parsed:
            parsed["packages"] = {
                k if isinstance(k, PackageKey) else PackageKey(k): v for k, v in parsed["packages"].items()
            }
        if "pins" in parsed:
            parsed["pins"] = {
                (k if isinstance(k, DependencyName) else package_canonical_name(k)): (
                    {constraint: PackageKey(pkg_str) for constraint, pkg_str in v.items()}
                    if isinstance(v, dict)
                    else {"": PackageKey(v)}
                )
                for k, v in parsed["pins"].items()
            }
        if "variants" in parsed:
            parsed["variants"] = [
                VariantSet(
                    items=tuple(
                        VariantItem(
                            package=item["package"],
                            kind=item["kind"],
                            name=item.get("name", ""),
                            default=item.get("default", False),
                        )
                        for item in variant_set["items"]
                    )
                )
                for variant_set in parsed["variants"]
            ]
        return from_dict(
            RawLockSet,
            parsed,
            config=Config(
                cast=[Tuple, Version, PackageKey, SpecifierSet],
                type_hooks={DependencyName: package_canonical_name},
            ),
        )


@dataclass(frozen=True)
class ResolvedLockSet:
    packages: Dict[PackageKey, ResolvedPackage] = field(default_factory=dict)
    pins: Dict[DependencyName, Union[PackageKey, Dict[str, PackageKey]]] = field(default_factory=dict)
    remote_files: Dict[FileKey, PackageFile] = field(default_factory=dict)
    cycle_groups: Dict[str, List[PackageKey]] = field(default_factory=dict)
    variants: List[VariantSet] = field(default_factory=list)

    @property
    def __dict__(self) -> Dict[str, Any]:
        return dict(
            _dataclass_items(self),
            packages=_stringify_keys(self.packages),
            pins=_simplify_pins(self.pins),
            remote_files=_stringify_keys(self.remote_files),
        )

    def to_json(self, indent=None) -> str:
        return json.dumps(self, sort_keys=True, indent=indent, cls=_Encoder) + "\n"

    @classmethod
    def from_json(cls, data: str) -> ResolvedLockSet:
        parsed = json.loads(data)
        if "packages" in parsed:
            parsed["packages"] = {
                k if isinstance(k, PackageKey) else PackageKey(k): v for k, v in parsed["packages"].items()
            }
        if "remote_files" in parsed:
            parsed["remote_files"] = {
                k if isinstance(k, FileKey) else FileKey(k): v for k, v in parsed["remote_files"].items()
            }
        if "pins" in parsed:
            parsed["pins"] = {
                (k if isinstance(k, DependencyName) else package_canonical_name(k)): (
                    {constraint: PackageKey(pkg_str) for constraint, pkg_str in v.items()}
                    if isinstance(v, dict)
                    else {"": PackageKey(v)}
                )
                for k, v in parsed["pins"].items()
            }
        if "variants" in parsed:
            parsed["variants"] = [
                VariantSet(
                    items=tuple(
                        VariantItem(
                            package=item["package"],
                            kind=item["kind"],
                            name=item.get("name", ""),
                            default=item.get("default", False),
                        )
                        for item in variant_set["items"]
                    )
                )
                for variant_set in parsed["variants"]
            ]
        return from_dict(
            ResolvedLockSet,
            parsed,
            config=Config(
                cast=[Tuple, Version, FileKey, PackageKey],
                type_hooks={DependencyName: package_canonical_name},
            ),
        )


def package_canonical_name(name: str) -> DependencyName:
    return DependencyName(name)


def is_wheel(filename: str) -> bool:
    return filename.lower().endswith(".whl")
