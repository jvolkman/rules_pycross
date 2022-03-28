load("@rules_python//python/pip_install:pip_repository.bzl", "whl_library")

all_requirements = ["@rules_pycross_pypi_deps_packaging//:pkg", "@rules_pycross_pypi_deps_pkginfo//:pkg", "@rules_pycross_pypi_deps_pyparsing//:pkg", "@rules_pycross_pypi_deps_tomli//:pkg"]

all_whl_requirements = ["@rules_pycross_pypi_deps_packaging//:whl", "@rules_pycross_pypi_deps_pkginfo//:whl", "@rules_pycross_pypi_deps_pyparsing//:whl", "@rules_pycross_pypi_deps_tomli//:whl"]

_packages = [('rules_pycross_pypi_deps_packaging', 'packaging==21.3     --hash=sha256:dd47c42927d89ab911e606518907cc2d3a1f38bbd026385970643f9c5b8ecfeb     --hash=sha256:ef103e05f519cdc783ae24ea4e2e0f508a9c99b2d4969652eed6a2e1ea5bd522'), ('rules_pycross_pypi_deps_pkginfo', 'pkginfo==1.8.2     --hash=sha256:542e0d0b6750e2e21c20179803e40ab50598d8066d51097a0e382cba9eb02bff     --hash=sha256:c24c487c6a7f72c66e816ab1796b96ac6c3d14d49338293d2141664330b55ffc'), ('rules_pycross_pypi_deps_pyparsing', 'pyparsing==3.0.7     --hash=sha256:18ee9022775d270c55187733956460083db60b37d0d0fb357445f3094eed3eea     --hash=sha256:a6c06a88f252e6c322f65faf8f418b16213b51bdfaece0524c1c1bc30c63c484'), ('rules_pycross_pypi_deps_tomli', 'tomli==2.0.1     --hash=sha256:939de3e7a6161af0c887ef91b7d41a53e7c5a1ca976325f429cb46ea9bc30ecc     --hash=sha256:de526c12914f0c550d15924c62d72abc48d6fe7364aa87328337a31007fe8a4f')]
_config = {'python_interpreter': 'python3', 'python_interpreter_target': None, 'quiet': True, 'timeout': 600, 'repo': 'rules_pycross_pypi_deps', 'isolated': True, 'extra_pip_args': [], 'pip_data_exclude': [], 'enable_implicit_namespace_pkgs': False, 'environment': {}, 'repo_prefix': 'rules_pycross_pypi_deps_'}
_annotations = {}

def _clean_name(name):
    return name.replace("-", "_").replace(".", "_").lower()

def requirement(name):
   return "@rules_pycross_pypi_deps_" + _clean_name(name) + "//:pkg"

def whl_requirement(name):
   return "@rules_pycross_pypi_deps_" + _clean_name(name) + "//:whl"

def data_requirement(name):
    return "@rules_pycross_pypi_deps_" + _clean_name(name) + "//:data"

def dist_info_requirement(name):
    return "@rules_pycross_pypi_deps_" + _clean_name(name) + "//:dist_info"

def entry_point(pkg, script = None):
    if not script:
        script = pkg
    return "@rules_pycross_pypi_deps_" + _clean_name(pkg) + "//:rules_python_wheel_entry_point_" + script

def _get_annotation(requirement):
    # This expects to parse `setuptools==58.2.0     --hash=sha256:2551203ae6955b9876741a26ab3e767bb3242dafe86a32a749ea0d78b6792f11`
    # down wo `setuptools`.
    name = requirement.split(" ")[0].split("=")[0]
    return _annotations.get(name)

def install_deps():
    for name, requirement in _packages:
        whl_library(
            name = name,
            requirement = requirement,
            annotation = _get_annotation(requirement),
            **_config,
        )
