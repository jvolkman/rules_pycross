"""Pycross providers."""

PycrossExtractedWheelInfo = provider(
    doc = "Information about an extracted (installed) Python wheel.",
    fields = {
        "site_packages": "File (TreeArtifact): The wheel installation root directory containing `site-packages/` (and any `bin/`, `data/`, or `include/` directories).",
    },
)

PycrossWheelSharedLibraryInfo = provider(
    doc = "Shared libraries that ship in another wheel. Wheel repair finds them but doesn't bundle copies.",
    fields = {
        "shared_libraries": "depset[File]: The libraries, copied out of the wheels that ship them.",
    },
)

PycrossPackageInfo = provider(
    doc = "Information about a Python package (e.g. from a lockfile).",
    fields = {
        "package_name": "string: The normalized package name.",
        "package_version": "string: The package version.",
        "site_paths": "list of strings: The site-packages paths provided by this package.",
        "site_paths_exact": "bool: Whether site_paths is exact (from wheel inspection or explicit annotation) rather than a repo-time sdist guess.",
        "bin_paths": "list of strings: The bin paths provided by this package.",
        "data_paths": "list of strings: The data paths provided by this package.",
        "include_paths": "list of strings: The include paths provided by this package.",
    },
)

PycrossPathToolInfo = provider(
    doc = "Information about a tool placed on PATH with a custom name.",
    fields = {
        "executable": "File: The executable file.",
        "files_to_run": "FilesToRunProvider: The wrapped executable's files_to_run (including runfiles).",
        "name": "string: The name to use on PATH.",
    },
)

PycrossUnsupportedWheelInfo = provider(
    doc = "Marker provider indicating a target has no compatible wheel or branch for the selected target environment.",
    fields = {
        "package": "string: Package identifier already named by a contextualized deferred failure action, or empty string for the generic `no_match_error` sentinel.",
    },
)
