"""Pycross providers."""

PycrossWheelInfo = provider(
    doc = "Information about a Python wheel.",
    fields = {
        "name_file": "File: A file containing the canonical name of the wheel.",
        "wheel_file": "File: The wheel file itself.",
        "wheel_directory": "File (TreeArtifact, optional): A directory containing the wheel file under its proper name.",
    },
)

PycrossBuildMixinInfo = provider(
    doc = "Standardized representation of a compilation/execution build mixin (e.g. C++, Rust, crossenv).",
    fields = {
        "config_json": "File: A JSON file containing compiled toolchain paths, flags, and libraries.",
        "files": "depset: All physical files (headers, static libraries) that must be present in the build sandbox.",
    },
)
