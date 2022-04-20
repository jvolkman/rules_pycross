load("@rules_python//python/pip_install:pip_repository.bzl", "whl_library")

all_requirements = ["@rules_pycross_pypi_deps_build//:pkg", "@rules_pycross_pypi_deps_dacite//:pkg", "@rules_pycross_pypi_deps_packaging//:pkg", "@rules_pycross_pypi_deps_pep517//:pkg", "@rules_pycross_pypi_deps_pkginfo//:pkg", "@rules_pycross_pypi_deps_poetry_core//:pkg", "@rules_pycross_pypi_deps_pyparsing//:pkg", "@rules_pycross_pypi_deps_tomli//:pkg", "@rules_pycross_pypi_deps_wheel//:pkg"]

all_whl_requirements = ["@rules_pycross_pypi_deps_build//:whl", "@rules_pycross_pypi_deps_dacite//:whl", "@rules_pycross_pypi_deps_packaging//:whl", "@rules_pycross_pypi_deps_pep517//:whl", "@rules_pycross_pypi_deps_pkginfo//:whl", "@rules_pycross_pypi_deps_poetry_core//:whl", "@rules_pycross_pypi_deps_pyparsing//:whl", "@rules_pycross_pypi_deps_tomli//:whl", "@rules_pycross_pypi_deps_wheel//:whl"]

_packages = [('rules_pycross_pypi_deps_build', 'build==0.7.0     --hash=sha256:1aaadcd69338252ade4f7ec1265e1a19184bf916d84c9b7df095f423948cb89f     --hash=sha256:21b7ebbd1b22499c4dac536abc7606696ea4d909fd755e00f09f3c0f2c05e3c8'), ('rules_pycross_pypi_deps_dacite', 'dacite==1.6.0     --hash=sha256:4331535f7aabb505c732fa4c3c094313fc0a1d5ea19907bf4726a7819a68b93f     --hash=sha256:d48125ed0a0352d3de9f493bf980038088f45f3f9d7498f090b50a847daaa6df'), ('rules_pycross_pypi_deps_packaging', 'packaging==21.3     --hash=sha256:dd47c42927d89ab911e606518907cc2d3a1f38bbd026385970643f9c5b8ecfeb     --hash=sha256:ef103e05f519cdc783ae24ea4e2e0f508a9c99b2d4969652eed6a2e1ea5bd522'), ('rules_pycross_pypi_deps_pep517', 'pep517==0.12.0     --hash=sha256:931378d93d11b298cf511dd634cf5ea4cb249a28ef84160b3247ee9afb4e8ab0     --hash=sha256:dd884c326898e2c6e11f9e0b64940606a93eb10ea022a2e067959f3a110cf161'), ('rules_pycross_pypi_deps_pkginfo', 'pkginfo==1.8.2     --hash=sha256:542e0d0b6750e2e21c20179803e40ab50598d8066d51097a0e382cba9eb02bff     --hash=sha256:c24c487c6a7f72c66e816ab1796b96ac6c3d14d49338293d2141664330b55ffc'), ('rules_pycross_pypi_deps_poetry_core', 'poetry-core==1.0.8     --hash=sha256:54b0fab6f7b313886e547a52f8bf52b8cf43e65b2633c65117f8755289061924     --hash=sha256:951fc7c1f8d710a94cb49019ee3742125039fc659675912ea614ac2aa405b118'), ('rules_pycross_pypi_deps_pyparsing', 'pyparsing==3.0.7     --hash=sha256:18ee9022775d270c55187733956460083db60b37d0d0fb357445f3094eed3eea     --hash=sha256:a6c06a88f252e6c322f65faf8f418b16213b51bdfaece0524c1c1bc30c63c484'), ('rules_pycross_pypi_deps_tomli', 'tomli==2.0.1     --hash=sha256:939de3e7a6161af0c887ef91b7d41a53e7c5a1ca976325f429cb46ea9bc30ecc     --hash=sha256:de526c12914f0c550d15924c62d72abc48d6fe7364aa87328337a31007fe8a4f'), ('rules_pycross_pypi_deps_wheel', 'wheel==0.37.1     --hash=sha256:4bdcd7d840138086126cd09254dc6195fb4fc6f01c050a1d7236f2630db1d22a     --hash=sha256:e9a504e793efbca1b8e0e9cb979a249cf4a0a7b5b8c9e8b65a5e39d49529c1c4')]
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
