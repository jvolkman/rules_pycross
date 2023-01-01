from importlib import reload
from pathlib import Path
from typing import List

def init_policies_for_machine(machine: str) -> None:
    import platform
    orig_machine_fn = platform.machine
    try:
        platform.machine = lambda: machine
        import auditwheel.policy
        reload(auditwheel.policy)
    finally:
        platform.machine = orig_machine_fn


def patch_load_ld_paths(lib_paths: List[Path]) -> None:
    import auditwheel.lddtree

    def load_ld_paths(root: str = "/", prefix: str = "") -> dict[str, list[str]]:
        ld_library_path = ":".join(map(str, lib_paths))
        return {
            "env": auditwheel.lddtree.parse_ld_paths(ld_library_path, path=""),
            "conf": [],
            "interp": [],
        }

    auditwheel.lddtree.load_ld_paths = load_ld_paths


def apply_auditwheel_patches(target_machine: str, lib_paths: List[Path]) -> None:
    init_policies_for_machine(target_machine)
    patch_load_ld_paths(lib_paths)
