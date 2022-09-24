import json
import sys
from email.message import EmailMessage
from email.parser import BytesParser
from io import BytesIO
from operator import attrgetter
from platform import python_version
from urllib import request
from typing import Any
from typing import Dict
from urllib.parse import urlparse
from zipfile import ZipFile

from packaging.requirements import Requirement
from packaging.specifiers import SpecifierSet
from packaging.utils import canonicalize_name
from packaging.version import InvalidVersion, Version

from resolvelib import BaseReporter, Resolver
from resolvelib.providers import AbstractProvider

PYTHON_VERSION = Version(python_version())

class Candidate:
    def __init__(self, name, version, url=None, extras=None):
        self.name = canonicalize_name(name)
        self.version = version
        self.url = url
        self.extras = extras

        self._metadata = None
        self._dependencies = None

    def __repr__(self):
        if not self.extras:
            return f"<{self.name}=={self.version}>"
        return f"<{self.name}[{','.join(self.extras)}]=={self.version}>"

    @property
    def metadata(self):
        if self._metadata is None:
            self._metadata = get_metadata_for_wheel(self.url)
        return self._metadata

    @property
    def requires_python(self):
        return self.metadata.get("Requires-Python")

    def _get_dependencies(self):
        deps = self.metadata.get_all("Requires-Dist", [])
        extras = self.extras if self.extras else [""]

        for d in deps:
            r = Requirement(d)
            if r.marker is None:
                yield r
            else:
                for e in extras:
                    if r.marker.evaluate({"extra": e}):
                        yield r

    @property
    def dependencies(self):
        if self._dependencies is None:
            self._dependencies = list(self._get_dependencies())
        return self._dependencies


def simple_api_get(url: str) -> Dict[str, Any]:
    req = request.Request(url)
    req.add_header("Accept", "application/vnd.pypi.simple.v1+json")
    with request.urlopen(req) as resp:
        data = resp.read().decode()
    return json.loads(data)


def wheel_get(url: str) -> bytes:
    req = request.Request(url)
    with request.urlopen(req) as resp:
        return resp.read()


def get_project_from_pypi(project, extras):
    """Return candidates created from the project name and extras."""
    url = "https://pypi.org/simple/{}".format(project)
    result = simple_api_get(url)
    for file in result["files"]:
        url = file["url"]
        py_req = file["requires-python"]

        # Skip items that need a different Python version
        if py_req:
            spec = SpecifierSet(py_req)
            # TODO: Replace this
            if PYTHON_VERSION not in spec:
                continue

        path = urlparse(url).path
        filename = path.rpartition("/")[-1]
        # We only handle wheels
        if not filename.endswith(".whl"):
            continue

        # TODO: Handle compatibility tags?

        # Very primitive wheel filename parsing
        name, version = filename[:-4].split("-")[:2]
        try:
            version = Version(version)
        except InvalidVersion:
            # Ignore files with invalid versions
            continue

        yield Candidate(name, version, url=url, extras=extras)


def get_metadata_for_wheel(url):
    data = wheel_get(url)
    with ZipFile(BytesIO(data)) as z:
        for n in z.namelist():
            if n.endswith(".dist-info/METADATA"):
                p = BytesParser()
                return p.parse(z.open(n), headersonly=True)

    # If we didn't find the metadata, return an empty dict
    return EmailMessage()


class ExtrasProvider(AbstractProvider):
    """A provider that handles extras."""

    def get_extras_for(self, requirement_or_candidate):
        """Given a requirement or candidate, return its extras.
        The extras should be a hashable value.
        """
        raise NotImplementedError

    def get_base_requirement(self, candidate):
        """Given a candidate, return a requirement that specifies that
        project/version.
        """
        raise NotImplementedError

    def identify(self, requirement_or_candidate):
        base = super(ExtrasProvider, self).identify(requirement_or_candidate)
        extras = self.get_extras_for(requirement_or_candidate)
        if extras:
            return (base, extras)
        else:
            return base

    def get_dependencies(self, candidate):
        deps = super(ExtrasProvider, self).get_dependencies(candidate)
        if candidate.extras:
            req = self.get_base_requirement(candidate)
            deps.append(req)
        return deps


class PyPIProvider(ExtrasProvider):
    def identify(self, requirement_or_candidate):
        return canonicalize_name(requirement_or_candidate.name)

    def get_extras_for(self, requirement_or_candidate):
        # Extras is a set, which is not hashable
        return tuple(sorted(requirement_or_candidate.extras))

    def get_base_requirement(self, candidate):
        return Requirement("{}=={}".format(candidate.name, candidate.version))

    def get_preference(self, identifier, resolutions, candidates, information, backtrack_causes):
        return sum(1 for _ in candidates[identifier])

    def find_matches(self, identifier, requirements, incompatibilities):
        requirements = list(requirements[identifier])
        assert not any(
            r.extras for r in requirements
        ), "extras not supported in this example"

        bad_versions = {c.version for c in incompatibilities[identifier]}

        # Need to pass the extras to the search, so they
        # are added to the candidate at creation - we
        # treat candidates as immutable once created.
        candidates = (
            candidate
            for candidate in get_project_from_pypi(identifier, set())
            if candidate.version not in bad_versions
               and all(candidate.version in r.specifier for r in requirements)
        )
        return sorted(candidates, key=attrgetter("version"), reverse=True)

    def is_satisfied_by(self, requirement, candidate):
        if canonicalize_name(requirement.name) != candidate.name:
            return False
        return candidate.version in requirement.specifier

    def get_dependencies(self, candidate):
        return candidate.dependencies


def display_resolution(result):
    """Print pinned candidates and dependency graph to stdout."""
    print("\n--- Pinned Candidates ---")
    for name, candidate in result.mapping.items():
        print(f"{name}: {candidate.name} {candidate.version}")

    print("\n--- Dependency Graph ---")
    for name in result.graph:
        targets = ", ".join(result.graph.iter_children(name))
        print(f"{name} -> {targets}")


def main():
    """Resolve requirements as project names on PyPI.
    The requirements are taken as command-line arguments
    and the resolution result will be printed to stdout.
    """
    if len(sys.argv) == 1:
        print("Usage:", sys.argv[0], "<PyPI project name(s)>")
        return
    # Things I want to resolve.
    reqs = sys.argv[1:]
    requirements = [Requirement(r) for r in reqs]

    # Create the (reusable) resolver.
    provider = PyPIProvider()
    reporter = BaseReporter()
    resolver = Resolver(provider, reporter)

    # Kick off the resolution process, and get the final result.
    print("Resolving", ", ".join(reqs))
    result = resolver.resolve(requirements)
    display_resolution(result)


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        print()