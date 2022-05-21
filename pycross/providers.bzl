"""Pycross providers."""

PycrossWheelInfo = provider(
    doc = "Information about a Python wheel.",
    fields = {
        "name_file": "File: A file containing the canonical name of the wheel.",
        "wheel_file": "File: The wheel file itself.",
    },
)
