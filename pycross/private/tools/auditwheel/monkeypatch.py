def init_policies_for_machine(machine: str) -> None:
    import platform
    orig_machine_fn = platform.machine
    try:
        platform.machine = lambda: machine
        import auditwheel.policy
    finally:
        platform.machine = orig_machine_fn


def patch_load_ld_paths() -> None:
    import auditwheel.lddtree
    orig_load_ld_paths_fn = auditwheel.lddtree.load_ld_paths

    def load_ld_paths(root: str = "/", prefix: str = "") -> dict[str, list[str]]:
        paths = orig_load_ld_paths_fn(root=root, prefix=prefix)
        # All we want to return is the LD_LIBRARY_PATH paths
        return {
            "env": paths["env"],
            "conf": [],
            "interp": [],
        }

    auditwheel.lddtree.load_ld_paths = load_ld_paths


def apply_auditwheel_patches(target_machine: str) -> None:
    init_policies_for_machine(target_machine)
    # patch_load_ld_paths()
