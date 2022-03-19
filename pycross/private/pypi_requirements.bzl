load("@rules_python//python/pip_install:pip_repository.bzl", "whl_library")

all_requirements = ["@rules_pycross_pypi_deps_blinker//:pkg", "@rules_pycross_pypi_deps_click//:pkg", "@rules_pycross_pypi_deps_findpython//:pkg", "@rules_pycross_pypi_deps_installer//:pkg", "@rules_pycross_pypi_deps_packaging//:pkg", "@rules_pycross_pypi_deps_pdm_pep517//:pkg", "@rules_pycross_pypi_deps_pdm//:pkg", "@rules_pycross_pypi_deps_pep517//:pkg", "@rules_pycross_pypi_deps_platformdirs//:pkg", "@rules_pycross_pypi_deps_pyparsing//:pkg", "@rules_pycross_pypi_deps_python_dotenv//:pkg", "@rules_pycross_pypi_deps_resolvelib//:pkg", "@rules_pycross_pypi_deps_shellingham//:pkg", "@rules_pycross_pypi_deps_tomli//:pkg", "@rules_pycross_pypi_deps_tomlkit//:pkg", "@rules_pycross_pypi_deps_wheel//:pkg", "@rules_pycross_pypi_deps_pip//:pkg"]

all_whl_requirements = ["@rules_pycross_pypi_deps_blinker//:whl", "@rules_pycross_pypi_deps_click//:whl", "@rules_pycross_pypi_deps_findpython//:whl", "@rules_pycross_pypi_deps_installer//:whl", "@rules_pycross_pypi_deps_packaging//:whl", "@rules_pycross_pypi_deps_pdm_pep517//:whl", "@rules_pycross_pypi_deps_pdm//:whl", "@rules_pycross_pypi_deps_pep517//:whl", "@rules_pycross_pypi_deps_platformdirs//:whl", "@rules_pycross_pypi_deps_pyparsing//:whl", "@rules_pycross_pypi_deps_python_dotenv//:whl", "@rules_pycross_pypi_deps_resolvelib//:whl", "@rules_pycross_pypi_deps_shellingham//:whl", "@rules_pycross_pypi_deps_tomli//:whl", "@rules_pycross_pypi_deps_tomlkit//:whl", "@rules_pycross_pypi_deps_wheel//:whl", "@rules_pycross_pypi_deps_pip//:whl"]

_packages = [('rules_pycross_pypi_deps_blinker', 'blinker==1.4     --hash=sha256:471aee25f3992bd325afa3772f1063dbdbbca947a041b8b89466dc00d606f8b6'), ('rules_pycross_pypi_deps_click', 'click==8.0.4     --hash=sha256:6a7a62563bbfabfda3a38f3023a1db4a35978c0abd76f6c9605ecd6554d6d9b1     --hash=sha256:8458d7b1287c5fb128c90e23381cf99dcde74beaf6c7ff6384ce84d6fe090adb'), ('rules_pycross_pypi_deps_findpython', 'findpython==0.1.3     --hash=sha256:b55a416b9fcf2d28721bfbea1ceb2a6cb67a00f99ec4b94a76da22c7a2002870     --hash=sha256:ec64268d4120173bf713761ae15335c811102debfd1c96d2ef782b85c2380a26'), ('rules_pycross_pypi_deps_installer', 'installer==0.3.0     --hash=sha256:d613bf6e535a01c6cb2179a96ae154dc2dbbf80f77e1622233b9ccbbf2f65161     --hash=sha256:e7dc5ec8b737fe3fa7c1872a6ebe120d7abc7cf780aa39af669c382a0fcb6de7'), ('rules_pycross_pypi_deps_packaging', 'packaging==21.3     --hash=sha256:dd47c42927d89ab911e606518907cc2d3a1f38bbd026385970643f9c5b8ecfeb     --hash=sha256:ef103e05f519cdc783ae24ea4e2e0f508a9c99b2d4969652eed6a2e1ea5bd522'), ('rules_pycross_pypi_deps_pdm_pep517', 'pdm-pep517==0.12.1     --hash=sha256:c3f9acfdc7832635628e94235320e0f6c19cbcd926eb041c454fb12463bc7504     --hash=sha256:ddce03cf5bd49201f3c89660cd3bb4b61d8f46c9f372e43b35ad2e5b52bc0e51'), ('rules_pycross_pypi_deps_pdm', 'pdm==1.13.4     --hash=sha256:5644fec425d1c0af04f135ad05b15b5a87be5a42e07f64e1706e3aac5dc89fcb     --hash=sha256:657ee4d44dfae8be2e90cb26f0abb6e8d4d320bd22de280b600ffabd4a3fc576'), ('rules_pycross_pypi_deps_pep517', 'pep517==0.12.0     --hash=sha256:931378d93d11b298cf511dd634cf5ea4cb249a28ef84160b3247ee9afb4e8ab0     --hash=sha256:dd884c326898e2c6e11f9e0b64940606a93eb10ea022a2e067959f3a110cf161'), ('rules_pycross_pypi_deps_platformdirs', 'platformdirs==2.5.1     --hash=sha256:7535e70dfa32e84d4b34996ea99c5e432fa29a708d0f4e394bbcb2a8faa4f16d     --hash=sha256:bcae7cab893c2d310a711b70b24efb93334febe65f8de776ee320b517471e227'), ('rules_pycross_pypi_deps_pyparsing', 'pyparsing==3.0.7     --hash=sha256:18ee9022775d270c55187733956460083db60b37d0d0fb357445f3094eed3eea     --hash=sha256:a6c06a88f252e6c322f65faf8f418b16213b51bdfaece0524c1c1bc30c63c484'), ('rules_pycross_pypi_deps_python_dotenv', 'python-dotenv==0.19.2     --hash=sha256:32b2bdc1873fd3a3c346da1c6db83d0053c3c62f28f1f38516070c4c8971b1d3     --hash=sha256:a5de49a31e953b45ff2d2fd434bbc2670e8db5273606c1e737cc6b93eff3655f'), ('rules_pycross_pypi_deps_resolvelib', 'resolvelib==0.8.1     --hash=sha256:c6ea56732e9fb6fca1b2acc2ccc68a0b6b8c566d8f3e78e0443310ede61dbd37     --hash=sha256:d9b7907f055c3b3a2cfc56c914ffd940122915826ff5fb5b1de0c99778f4de98'), ('rules_pycross_pypi_deps_shellingham', 'shellingham==1.4.0     --hash=sha256:4855c2458d6904829bd34c299f11fdeed7cfefbf8a2c522e4caea6cd76b3171e     --hash=sha256:536b67a0697f2e4af32ab176c00a50ac2899c5a05e0d8e2dadac8e58888283f9'), ('rules_pycross_pypi_deps_tomli', 'tomli==2.0.1     --hash=sha256:939de3e7a6161af0c887ef91b7d41a53e7c5a1ca976325f429cb46ea9bc30ecc     --hash=sha256:de526c12914f0c550d15924c62d72abc48d6fe7364aa87328337a31007fe8a4f'), ('rules_pycross_pypi_deps_tomlkit', 'tomlkit==0.10.0     --hash=sha256:cac4aeaff42f18fef6e07831c2c2689a51df76cf2ede07a6a4fa5fcb83558870     --hash=sha256:d99946c6aed3387c98b89d91fb9edff8f901bf9255901081266a84fb5604adcd'), ('rules_pycross_pypi_deps_wheel', 'wheel==0.37.1     --hash=sha256:4bdcd7d840138086126cd09254dc6195fb4fc6f01c050a1d7236f2630db1d22a     --hash=sha256:e9a504e793efbca1b8e0e9cb979a249cf4a0a7b5b8c9e8b65a5e39d49529c1c4'), ('rules_pycross_pypi_deps_pip', 'pip==22.0.4     --hash=sha256:b3a9de2c6ef801e9247d1527a4b16f92f2cc141cd1489f3fffaf6a9e96729764     --hash=sha256:c6aca0f2f081363f689f041d90dab2a07a9a07fb840284db2218117a52da800b')]
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
