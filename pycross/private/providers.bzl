"""Pycross providers."""

PycrossExtractedWheelInfo = provider(
    doc = "Information about an extracted (installed) Python wheel.",
    fields = {
        "site_packages": "File (TreeArtifact): The unzipped site-packages directory containing the wheel's installed files.",
    },
)

PycrossPackageInfo = provider(
    doc = "Information about a Python package (e.g. from a lockfile).",
    fields = {
        "package_name": "string: The normalized package name.",
        "package_version": "string: The package version.",
        "site_paths": "list of strings: The site-packages paths provided by this package.",
        "bin_paths": "list of strings: The bin paths provided by this package.",
        "data_paths": "list of strings: The data paths provided by this package.",
        "include_paths": "list of strings: The include paths provided by this package.",
    },
)

PycrossPathToolInfo = provider(
    doc = "Information about a tool placed on PATH with a custom name.",
    fields = {
        "executable": "File: The executable file.",
        "name": "string: The name to use on PATH.",
    },
)
