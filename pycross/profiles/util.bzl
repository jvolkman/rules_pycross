"""Utility functions for rules_pycross build profiles."""

def glean_repo_name(sdist_label):
    """Extracts the repository name (apparent or canonical) from a target.

    Args:
        sdist_label: A string or Label object representing the sdist target.

    Returns:
        str: The repository name, or None if it's a relative/local target.
    """
    if not sdist_label:
        return None

    # Convert to a string to normalize both Label objects and string formats.
    label_str = str(sdist_label)

    # Local/main workspace targets (e.g. "//deps:numpy_sdist", ":numpy_sdist") do not start with '@'
    if not label_str.startswith("@"):
        return None

    # Targets explicitly referring to the local/main workspace via '@//' or '@@//'
    if label_str.startswith("@@//") or label_str.startswith("@//"):
        return None

    # Find the double slash '//' that separates repository name from the package path
    double_slash_idx = label_str.find("//")
    if double_slash_idx == -1:
        return None

    # Extract repo name between the '@' (or '@@') prefix and the '//' delimiter
    if label_str.startswith("@@"):
        repo_part = label_str[2:double_slash_idx]
    else:
        repo_part = label_str[1:double_slash_idx]

    if not repo_part:
        return None

    return repo_part
