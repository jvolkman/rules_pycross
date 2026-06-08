"""Pycross providers."""

PycrossWheelInfo = provider(
    doc = "Information about a built or downloaded Python wheel.",
    fields = {
        "wheelhouse": "File (TreeArtifact): A directory containing exactly one .whl file with its proper name.",
    },
)

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
    },
)
