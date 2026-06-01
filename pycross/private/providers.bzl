"""Pycross providers."""

PycrossWheelInfo = provider(
    doc = "Information about a Python wheel.",
    fields = {
        "name_file": "File: A file containing the canonical name of the wheel.",
        "wheel_file": "File: The wheel file itself.",
        "wheel_directory": "File (TreeArtifact, optional): A directory containing the wheel file under its proper name.",
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
