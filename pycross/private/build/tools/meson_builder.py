"""Meson PEP 517 builder."""

import sys

from pycross.private.build.tools.meson_utils import generate_cross_ini
from pycross.private.build.tools.utils.context import load_layers
from pycross.private.build.tools.utils.lifecycle import BackendStrategy
from pycross.private.build.tools.utils.lifecycle import run_standard_build_lifecycle
from pycross.private.build.tools.utils.venv_utils import build_standard_venv

# A template for generating a Python site hook that spoofs the platform.
# Without this spoofing, mesonpy and packaging.tags would read the host
# platform from sys.platform and sysconfig.get_platform() during cross-compilation
# and incorrectly tag the output wheel.
_SPOOF_PLATFORM_TEMPLATE = """\
import sys
import sysconfig

class SysWrapper(object):
    def __init__(self, real_sys):
        self.__dict__["_real_sys"] = real_sys
    def __getattr__(self, name):
        return getattr(self._real_sys, name)
    def __setattr__(self, name, value):
        setattr(self._real_sys, name, value)
    @property
    def platform(self):
        try:
            f = sys._getframe(1)
            while f:
                if "packaging/tags" in f.f_code.co_filename or "mesonpy" in f.f_code.co_filename:
                    return %s
                f = f.f_back
        except Exception:
            pass
        return self._real_sys.platform

sys.modules["sys"] = SysWrapper(sys)

_real_get_platform = sysconfig.get_platform
def _get_platform():
    import sys as _sys
    try:
        f = _sys._getframe(1)
        while f:
            if "packaging/tags" in f.f_code.co_filename or "mesonpy" in f.f_code.co_filename:
                return %s
            f = f.f_back
    except Exception:
        pass
    return _real_get_platform()

sysconfig.get_platform = _get_platform
"""


def setup_venv(ctx):
    target_sys_platform = ctx.sysconfig_vars.get("MACHDEP")
    from pycross.private.build.tools.utils.sysconfig_utils import derive_platform_overrides

    target_platform, _ = derive_platform_overrides(ctx.sysconfig_vars)

    ctx.site_hooks.append(_SPOOF_PLATFORM_TEMPLATE % (repr(target_sys_platform), repr(target_platform)))

    build_standard_venv(ctx)


def pre_build(ctx):
    cc_layer_config = next((m for m in load_layers(ctx) if "CC" in m), None)
    generate_cross_ini(ctx, cc_layer_config)


def prepare_env(ctx):
    ctx.build_env["MESON_FORCE_BACKTRACE"] = "1"
    for key in ["CC", "CXX", "CFLAGS", "CXXFLAGS", "LDFLAGS", "LDSHAREDFLAGS", "AR", "ARFLAGS"]:
        ctx.build_env.pop(key, None)


def main():
    strategy = BackendStrategy(
        setup_venv=setup_venv,
        pre_build=pre_build,
        prepare_env=prepare_env,
    )
    run_standard_build_lifecycle(sys.argv[1], strategy)


if __name__ == "__main__":
    main()
