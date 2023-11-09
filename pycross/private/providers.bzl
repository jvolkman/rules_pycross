"""Pycross providers."""

PycrossTargetEnvironmentInfo = provider(
    doc = "A target environment description.",
    fields = {
        "python_compatible_with": "A list of constraints used to select this platform.",
        "file": "The JSON file containing target environment information.",
    },
)
