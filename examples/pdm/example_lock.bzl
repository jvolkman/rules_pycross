load("@bazel_tools//tools/build_defs/repo:http.bzl", "http_file")
load("@bazel_tools//tools/build_defs/repo:utils.bzl", "maybe")
load("@jvolkman_rules_pycross//pycross:defs.bzl", "pycross_wheel_build", "pycross_wheel_library", "pypi_file")

PINS = {
    "appnope": "appnope_0.1.3",
    "asttokens": "asttokens_2.0.7",
    "attrs": "attrs_22.1.0",
    "aws_sam_translator": "aws_sam_translator_1.48.0",
    "aws_xray_sdk": "aws_xray_sdk_2.9.0",
    "backcall": "backcall_0.2.0",
    "black": "black_22.6.0",
    "boto3": "boto3_1.24.46",
    "botocore": "botocore_1.27.46",
    "certifi": "certifi_2022.6.15",
    "cffi": "cffi_1.15.1",
    "cfn_lint": "cfn_lint_0.61.4",
    "charset_normalizer": "charset_normalizer_2.1.0",
    "click": "click_8.1.3",
    "cognitojwt": "cognitojwt_1.4.1",
    "cowsay": "cowsay_5.0",
    "cryptography": "cryptography_37.0.4",
    "cython": "cython_0.29.32",
    "decorator": "decorator_5.1.1",
    "docker": "docker_5.0.3",
    "ecdsa": "ecdsa_0.18.0",
    "executing": "executing_0.9.1",
    "flask": "flask_2.2.1",
    "flask_cors": "flask_cors_3.0.10",
    "future": "future_0.18.2",
    "graphql_core": "graphql_core_3.2.1",
    "greenlet": "greenlet_1.1.2",
    "idna": "idna_3.3",
    "importlib_metadata": "importlib_metadata_4.12.0",
    "ipython": "ipython_8.4.0",
    "itsdangerous": "itsdangerous_2.1.2",
    "jedi": "jedi_0.18.1",
    "jinja2": "jinja2_3.1.2",
    "jmespath": "jmespath_1.0.1",
    "jschema_to_python": "jschema_to_python_1.2.3",
    "jsondiff": "jsondiff_2.0.0",
    "jsonpatch": "jsonpatch_1.32",
    "jsonpickle": "jsonpickle_2.2.0",
    "jsonpointer": "jsonpointer_2.3",
    "jsonschema": "jsonschema_3.2.0",
    "junit_xml": "junit_xml_1.9",
    "markupsafe": "markupsafe_2.1.1",
    "matplotlib_inline": "matplotlib_inline_0.1.3",
    "moto": "moto_3.1.1",
    "mypy_extensions": "mypy_extensions_0.4.3",
    "networkx": "networkx_2.8.5",
    "numpy": "numpy_1.22.3",
    "parso": "parso_0.8.3",
    "pathspec": "pathspec_0.9.0",
    "pbr": "pbr_5.9.0",
    "pexpect": "pexpect_4.8.0",
    "pickleshare": "pickleshare_0.7.5",
    "platformdirs": "platformdirs_2.5.2",
    "prompt_toolkit": "prompt_toolkit_3.0.30",
    "ptyprocess": "ptyprocess_0.7.0",
    "pure_eval": "pure_eval_0.2.2",
    "pyasn1": "pyasn1_0.4.8",
    "pycparser": "pycparser_2.21",
    "pygments": "pygments_2.12.0",
    "pyrsistent": "pyrsistent_0.18.1",
    "python_dateutil": "python_dateutil_2.8.2",
    "python_jose": "python_jose_3.1.0",
    "pytz": "pytz_2022.1",
    "pyyaml": "pyyaml_6.0",
    "requests": "requests_2.28.1",
    "responses": "responses_0.21.0",
    "rsa": "rsa_4.9",
    "s3transfer": "s3transfer_0.6.0",
    "sarif_om": "sarif_om_1.0.4",
    "setproctitle": "setproctitle_1.2.2",
    "setuptools": "setuptools_59.2.0",
    "six": "six_1.16.0",
    "sqlalchemy": "sqlalchemy_1.4.40",
    "sqlalchemy_utils": "sqlalchemy_utils_0.38.2",
    "sshpubkeys": "sshpubkeys_3.3.1",
    "stack_data": "stack_data_0.3.0",
    "tomli": "tomli_2.0.1",
    "traitlets": "traitlets_5.3.0",
    "tree_sitter": "tree_sitter_0.20.0",
    "typing_extensions": "typing_extensions_4.3.0",
    "urllib3": "urllib3_1.26.11",
    "wcwidth": "wcwidth_0.2.5",
    "websocket_client": "websocket_client_1.3.3",
    "werkzeug": "werkzeug_2.2.1",
    "wheel": "wheel_0.37.0",
    "wrapt": "wrapt_1.14.1",
    "xmltodict": "xmltodict_0.13.0",
    "zipp": "zipp_3.8.1",
}

def targets():
    for pin_name, pin_target in PINS.items():
        native.alias(
            name = pin_name,
            actual = ":" + pin_target,
        )

    native.config_setting(
        name = "_env_python_darwin_arm64",
        constraint_values = [
            "@platforms//os:osx",
            "@platforms//cpu:arm64",
        ],
    )

    native.config_setting(
        name = "_env_python_darwin_x86_64",
        constraint_values = [
            "@platforms//os:osx",
            "@platforms//cpu:x86_64",
        ],
    )

    native.config_setting(
        name = "_env_python_linux_x86_64",
        constraint_values = [
            "@platforms//os:linux",
            "@platforms//cpu:x86_64",
        ],
    )

    _target = select({
        ":_env_python_darwin_arm64": "@//:python_darwin_arm64",
        ":_env_python_darwin_x86_64": "@//:python_darwin_x86_64",
        ":_env_python_linux_x86_64": "@//:python_linux_x86_64",
    })

    pycross_wheel_library(
        name = "appnope_0.1.3",
        wheel = "@example_lock_wheel_appnope_0.1.3_py2.py3_none_any//file",
    )

    _asttokens_2_0_7_deps = [
        ":six_1.16.0",
    ]

    pycross_wheel_library(
        name = "asttokens_2.0.7",
        deps = _asttokens_2_0_7_deps,
        wheel = "@example_lock_wheel_asttokens_2.0.7_py2.py3_none_any//file",
    )

    pycross_wheel_library(
        name = "attrs_22.1.0",
        wheel = "@example_lock_wheel_attrs_22.1.0_py2.py3_none_any//file",
    )

    _aws_sam_translator_1_48_0_deps = [
        ":boto3_1.24.46",
        ":jsonschema_3.2.0",
    ]

    pycross_wheel_library(
        name = "aws_sam_translator_1.48.0",
        deps = _aws_sam_translator_1_48_0_deps,
        wheel = "@example_lock_wheel_aws_sam_translator_1.48.0_py3_none_any//file",
    )

    _aws_xray_sdk_2_9_0_deps = [
        ":botocore_1.27.46",
        ":future_0.18.2",
        ":wrapt_1.14.1",
    ]

    pycross_wheel_library(
        name = "aws_xray_sdk_2.9.0",
        deps = _aws_xray_sdk_2_9_0_deps,
        wheel = "@example_lock_wheel_aws_xray_sdk_2.9.0_py2.py3_none_any//file",
    )

    pycross_wheel_library(
        name = "backcall_0.2.0",
        wheel = "@example_lock_wheel_backcall_0.2.0_py2.py3_none_any//file",
    )

    _black_22_6_0_deps = [
        ":click_8.1.3",
        ":mypy_extensions_0.4.3",
        ":pathspec_0.9.0",
        ":platformdirs_2.5.2",
        ":tomli_2.0.1",
        ":typing_extensions_4.3.0",
    ]

    pycross_wheel_library(
        name = "black_22.6.0",
        deps = _black_22_6_0_deps,
        wheel = select({
            ":_env_python_darwin_arm64": "@example_lock_wheel_black_22.6.0_cp39_cp39_macosx_11_0_arm64//file",
            ":_env_python_darwin_x86_64": "@example_lock_wheel_black_22.6.0_cp39_cp39_macosx_10_9_x86_64//file",
            ":_env_python_linux_x86_64": "@example_lock_wheel_black_22.6.0_cp39_cp39_manylinux_2_17_x86_64.manylinux2014_x86_64//file",
        }),
    )

    _boto3_1_24_46_deps = [
        ":botocore_1.27.46",
        ":jmespath_1.0.1",
        ":s3transfer_0.6.0",
    ]

    pycross_wheel_library(
        name = "boto3_1.24.46",
        deps = _boto3_1_24_46_deps,
        wheel = "@example_lock_wheel_boto3_1.24.46_py3_none_any//file",
    )

    _botocore_1_27_46_deps = [
        ":jmespath_1.0.1",
        ":python_dateutil_2.8.2",
        ":urllib3_1.26.11",
    ]

    pycross_wheel_library(
        name = "botocore_1.27.46",
        deps = _botocore_1_27_46_deps,
        wheel = "@example_lock_wheel_botocore_1.27.46_py3_none_any//file",
    )

    pycross_wheel_library(
        name = "certifi_2022.6.15",
        wheel = "@example_lock_wheel_certifi_2022.6.15_py3_none_any//file",
    )

    _cffi_1_15_1_deps = [
        ":pycparser_2.21",
    ]

    pycross_wheel_library(
        name = "cffi_1.15.1",
        deps = _cffi_1_15_1_deps,
        wheel = select({
            ":_env_python_darwin_arm64": "@example_lock_wheel_cffi_1.15.1_cp39_cp39_macosx_11_0_arm64//file",
            ":_env_python_darwin_x86_64": "@example_lock_wheel_cffi_1.15.1_cp39_cp39_macosx_10_9_x86_64//file",
            ":_env_python_linux_x86_64": "@example_lock_wheel_cffi_1.15.1_cp39_cp39_manylinux_2_17_x86_64.manylinux2014_x86_64//file",
        }),
    )

    _cfn_lint_0_61_4_deps = [
        ":aws_sam_translator_1.48.0",
        ":jschema_to_python_1.2.3",
        ":jsonpatch_1.32",
        ":jsonschema_3.2.0",
        ":junit_xml_1.9",
        ":networkx_2.8.5",
        ":pyyaml_6.0",
        ":sarif_om_1.0.4",
    ]

    pycross_wheel_library(
        name = "cfn_lint_0.61.4",
        deps = _cfn_lint_0_61_4_deps,
        wheel = "@example_lock_wheel_cfn_lint_0.61.4_py3_none_any//file",
    )

    pycross_wheel_library(
        name = "charset_normalizer_2.1.0",
        wheel = "@example_lock_wheel_charset_normalizer_2.1.0_py3_none_any//file",
    )

    pycross_wheel_library(
        name = "click_8.1.3",
        wheel = "@example_lock_wheel_click_8.1.3_py3_none_any//file",
    )

    _cognitojwt_1_4_1_deps = [
        ":python_jose_3.1.0",
    ]

    pycross_wheel_library(
        name = "cognitojwt_1.4.1",
        deps = _cognitojwt_1_4_1_deps,
        wheel = "@example_lock_wheel_cognitojwt_1.4.1_py3_none_any//file",
    )

    _cowsay_5_0_build_deps = [
        ":setuptools_59.2.0",
        ":wheel_0.37.0",
    ]

    pycross_wheel_build(
        name = "_build_cowsay_5.0",
        sdist = "@example_lock_sdist_cowsay_5.0//file",
        target_environment = _target,
        deps = _cowsay_5_0_build_deps,
        tags = ["manual"],
    )

    pycross_wheel_library(
        name = "cowsay_5.0",
        wheel = ":_build_cowsay_5.0",
    )

    _cryptography_37_0_4_deps = [
        ":cffi_1.15.1",
    ]

    pycross_wheel_library(
        name = "cryptography_37.0.4",
        deps = _cryptography_37_0_4_deps,
        wheel = select({
            ":_env_python_darwin_arm64": "@example_lock_wheel_cryptography_37.0.4_cp36_abi3_macosx_10_10_universal2//file",
            ":_env_python_darwin_x86_64": "@example_lock_wheel_cryptography_37.0.4_cp36_abi3_macosx_10_10_x86_64//file",
            ":_env_python_linux_x86_64": "@example_lock_wheel_cryptography_37.0.4_cp36_abi3_manylinux_2_17_x86_64.manylinux2014_x86_64//file",
        }),
    )

    pycross_wheel_library(
        name = "cython_0.29.32",
        wheel = select({
            ":_env_python_darwin_arm64": "@example_lock_wheel_cython_0.29.32_py2.py3_none_any//file",
            ":_env_python_darwin_x86_64": "@example_lock_wheel_cython_0.29.32_py2.py3_none_any//file",
            ":_env_python_linux_x86_64": "@example_lock_wheel_cython_0.29.32_cp39_cp39_manylinux_2_17_x86_64.manylinux2014_x86_64.manylinux_2_24_x86_64//file",
        }),
    )

    pycross_wheel_library(
        name = "decorator_5.1.1",
        wheel = "@example_lock_wheel_decorator_5.1.1_py3_none_any//file",
    )

    _docker_5_0_3_deps = [
        ":requests_2.28.1",
        ":websocket_client_1.3.3",
    ]

    pycross_wheel_library(
        name = "docker_5.0.3",
        deps = _docker_5_0_3_deps,
        wheel = "@example_lock_wheel_docker_5.0.3_py2.py3_none_any//file",
    )

    _ecdsa_0_18_0_deps = [
        ":six_1.16.0",
    ]

    pycross_wheel_library(
        name = "ecdsa_0.18.0",
        deps = _ecdsa_0_18_0_deps,
        wheel = "@example_lock_wheel_ecdsa_0.18.0_py2.py3_none_any//file",
    )

    pycross_wheel_library(
        name = "executing_0.9.1",
        wheel = "@example_lock_wheel_executing_0.9.1_py2.py3_none_any//file",
    )

    _flask_2_2_1_deps = [
        ":click_8.1.3",
        ":importlib_metadata_4.12.0",
        ":itsdangerous_2.1.2",
        ":jinja2_3.1.2",
        ":werkzeug_2.2.1",
    ]

    pycross_wheel_library(
        name = "flask_2.2.1",
        deps = _flask_2_2_1_deps,
        wheel = "@example_lock_wheel_flask_2.2.1_py3_none_any//file",
    )

    _flask_cors_3_0_10_deps = [
        ":flask_2.2.1",
        ":six_1.16.0",
    ]

    pycross_wheel_library(
        name = "flask_cors_3.0.10",
        deps = _flask_cors_3_0_10_deps,
        wheel = "@example_lock_wheel_flask_cors_3.0.10_py2.py3_none_any//file",
    )

    pycross_wheel_library(
        name = "future_0.18.2",
        wheel = "@//deps:overridden_future_0.18.2",
    )

    pycross_wheel_library(
        name = "graphql_core_3.2.1",
        wheel = "@example_lock_wheel_graphql_core_3.2.1_py3_none_any//file",
    )

    pycross_wheel_build(
        name = "_build_greenlet_1.1.2",
        sdist = "@example_lock_sdist_greenlet_1.1.2//file",
        target_environment = _target,
        tags = ["manual"],
    )

    pycross_wheel_library(
        name = "greenlet_1.1.2",
        wheel = select({
            ":_env_python_darwin_arm64": ":_build_greenlet_1.1.2",
            ":_env_python_darwin_x86_64": "@example_lock_wheel_greenlet_1.1.2_cp39_cp39_macosx_10_14_x86_64//file",
            ":_env_python_linux_x86_64": "@example_lock_wheel_greenlet_1.1.2_cp39_cp39_manylinux_2_17_x86_64.manylinux2014_x86_64//file",
        }),
    )

    pycross_wheel_library(
        name = "idna_3.3",
        wheel = "@example_lock_wheel_idna_3.3_py3_none_any//file",
    )

    _importlib_metadata_4_12_0_deps = [
        ":zipp_3.8.1",
    ]

    pycross_wheel_library(
        name = "importlib_metadata_4.12.0",
        deps = _importlib_metadata_4_12_0_deps,
        wheel = "@example_lock_wheel_importlib_metadata_4.12.0_py3_none_any//file",
    )

    _ipython_8_4_0_deps = [
        ":backcall_0.2.0",
        ":decorator_5.1.1",
        ":jedi_0.18.1",
        ":matplotlib_inline_0.1.3",
        ":pexpect_4.8.0",
        ":pickleshare_0.7.5",
        ":prompt_toolkit_3.0.30",
        ":pygments_2.12.0",
        ":setuptools_59.2.0",
        ":stack_data_0.3.0",
        ":traitlets_5.3.0",
    ] + select({
        ":_env_python_darwin_arm64": [
            ":appnope_0.1.3",
        ],
        ":_env_python_darwin_x86_64": [
            ":appnope_0.1.3",
        ],
        "//conditions:default": [],
    })

    pycross_wheel_library(
        name = "ipython_8.4.0",
        deps = _ipython_8_4_0_deps,
        wheel = "@example_lock_wheel_ipython_8.4.0_py3_none_any//file",
    )

    pycross_wheel_library(
        name = "itsdangerous_2.1.2",
        wheel = "@example_lock_wheel_itsdangerous_2.1.2_py3_none_any//file",
    )

    _jedi_0_18_1_deps = [
        ":parso_0.8.3",
    ]

    pycross_wheel_library(
        name = "jedi_0.18.1",
        deps = _jedi_0_18_1_deps,
        wheel = "@example_lock_wheel_jedi_0.18.1_py2.py3_none_any//file",
    )

    _jinja2_3_1_2_deps = [
        ":markupsafe_2.1.1",
    ]

    pycross_wheel_library(
        name = "jinja2_3.1.2",
        deps = _jinja2_3_1_2_deps,
        wheel = "@example_lock_wheel_jinja2_3.1.2_py3_none_any//file",
    )

    pycross_wheel_library(
        name = "jmespath_1.0.1",
        wheel = "@example_lock_wheel_jmespath_1.0.1_py3_none_any//file",
    )

    _jschema_to_python_1_2_3_deps = [
        ":attrs_22.1.0",
        ":jsonpickle_2.2.0",
        ":pbr_5.9.0",
    ]

    pycross_wheel_library(
        name = "jschema_to_python_1.2.3",
        deps = _jschema_to_python_1_2_3_deps,
        wheel = "@example_lock_wheel_jschema_to_python_1.2.3_py3_none_any//file",
    )

    pycross_wheel_library(
        name = "jsondiff_2.0.0",
        wheel = "@example_lock_wheel_jsondiff_2.0.0_py3_none_any//file",
    )

    _jsonpatch_1_32_deps = [
        ":jsonpointer_2.3",
    ]

    pycross_wheel_library(
        name = "jsonpatch_1.32",
        deps = _jsonpatch_1_32_deps,
        wheel = "@example_lock_wheel_jsonpatch_1.32_py2.py3_none_any//file",
    )

    pycross_wheel_library(
        name = "jsonpickle_2.2.0",
        wheel = "@example_lock_wheel_jsonpickle_2.2.0_py2.py3_none_any//file",
    )

    pycross_wheel_library(
        name = "jsonpointer_2.3",
        wheel = "@example_lock_wheel_jsonpointer_2.3_py2.py3_none_any//file",
    )

    _jsonschema_3_2_0_deps = [
        ":attrs_22.1.0",
        ":pyrsistent_0.18.1",
        ":setuptools_59.2.0",
        ":six_1.16.0",
    ]

    pycross_wheel_library(
        name = "jsonschema_3.2.0",
        deps = _jsonschema_3_2_0_deps,
        wheel = "@example_lock_wheel_jsonschema_3.2.0_py2.py3_none_any//file",
    )

    _junit_xml_1_9_deps = [
        ":six_1.16.0",
    ]

    pycross_wheel_library(
        name = "junit_xml_1.9",
        deps = _junit_xml_1_9_deps,
        wheel = "@example_lock_wheel_junit_xml_1.9_py2.py3_none_any//file",
    )

    pycross_wheel_library(
        name = "markupsafe_2.1.1",
        wheel = select({
            ":_env_python_darwin_arm64": "@example_lock_wheel_markupsafe_2.1.1_cp39_cp39_macosx_10_9_universal2//file",
            ":_env_python_darwin_x86_64": "@example_lock_wheel_markupsafe_2.1.1_cp39_cp39_macosx_10_9_x86_64//file",
            ":_env_python_linux_x86_64": "@example_lock_wheel_markupsafe_2.1.1_cp39_cp39_manylinux_2_17_x86_64.manylinux2014_x86_64//file",
        }),
    )

    _matplotlib_inline_0_1_3_deps = [
        ":traitlets_5.3.0",
    ]

    pycross_wheel_library(
        name = "matplotlib_inline_0.1.3",
        deps = _matplotlib_inline_0_1_3_deps,
        wheel = "@example_lock_wheel_matplotlib_inline_0.1.3_py3_none_any//file",
    )

    _moto_3_1_1_deps = [
        ":aws_xray_sdk_2.9.0",
        ":boto3_1.24.46",
        ":botocore_1.27.46",
        ":cfn_lint_0.61.4",
        ":cryptography_37.0.4",
        ":docker_5.0.3",
        ":ecdsa_0.18.0",
        ":flask_2.2.1",
        ":flask_cors_3.0.10",
        ":graphql_core_3.2.1",
        ":idna_3.3",
        ":jinja2_3.1.2",
        ":jsondiff_2.0.0",
        ":markupsafe_2.1.1",
        ":python_dateutil_2.8.2",
        ":python_jose_3.1.0",
        ":pytz_2022.1",
        ":pyyaml_6.0",
        ":requests_2.28.1",
        ":responses_0.21.0",
        ":setuptools_59.2.0",
        ":sshpubkeys_3.3.1",
        ":werkzeug_2.2.1",
        ":xmltodict_0.13.0",
    ]

    pycross_wheel_library(
        name = "moto_3.1.1",
        deps = _moto_3_1_1_deps,
        wheel = "@example_lock_wheel_moto_3.1.1_py2.py3_none_any//file",
    )

    pycross_wheel_library(
        name = "mypy_extensions_0.4.3",
        wheel = "@example_lock_wheel_mypy_extensions_0.4.3_py2.py3_none_any//file",
    )

    pycross_wheel_library(
        name = "networkx_2.8.5",
        wheel = "@example_lock_wheel_networkx_2.8.5_py3_none_any//file",
    )

    _numpy_1_22_3_build_deps = [
        ":cython_0.29.32",
        ":setuptools_59.2.0",
        ":wheel_0.37.0",
    ]

    pycross_wheel_library(
        name = "numpy_1.22.3",
        wheel = select({
            ":_env_python_darwin_arm64": "@example_lock_wheel_numpy_1.22.3_cp39_cp39_macosx_11_0_arm64//file",
            ":_env_python_darwin_x86_64": "@example_lock_wheel_numpy_1.22.3_cp39_cp39_macosx_10_14_x86_64//file",
            ":_env_python_linux_x86_64": "@example_lock_wheel_numpy_1.22.3_cp39_cp39_manylinux_2_17_x86_64.manylinux2014_x86_64//file",
        }),
    )

    pycross_wheel_library(
        name = "parso_0.8.3",
        wheel = "@example_lock_wheel_parso_0.8.3_py2.py3_none_any//file",
    )

    pycross_wheel_library(
        name = "pathspec_0.9.0",
        wheel = "@example_lock_wheel_pathspec_0.9.0_py2.py3_none_any//file",
    )

    _pbr_5_9_0_build_deps = [
        ":setuptools_59.2.0",
        ":wheel_0.37.0",
    ]

    pycross_wheel_build(
        name = "_build_pbr_5.9.0",
        sdist = "@example_lock_sdist_pbr_5.9.0//file",
        target_environment = _target,
        deps = _pbr_5_9_0_build_deps,
        tags = ["manual"],
    )

    pycross_wheel_library(
        name = "pbr_5.9.0",
        wheel = ":_build_pbr_5.9.0",
    )

    _pexpect_4_8_0_deps = [
        ":ptyprocess_0.7.0",
    ]

    pycross_wheel_library(
        name = "pexpect_4.8.0",
        deps = _pexpect_4_8_0_deps,
        wheel = "@example_lock_wheel_pexpect_4.8.0_py2.py3_none_any//file",
    )

    pycross_wheel_library(
        name = "pickleshare_0.7.5",
        wheel = "@example_lock_wheel_pickleshare_0.7.5_py2.py3_none_any//file",
    )

    pycross_wheel_library(
        name = "platformdirs_2.5.2",
        wheel = "@example_lock_wheel_platformdirs_2.5.2_py3_none_any//file",
    )

    _prompt_toolkit_3_0_30_deps = [
        ":wcwidth_0.2.5",
    ]

    pycross_wheel_library(
        name = "prompt_toolkit_3.0.30",
        deps = _prompt_toolkit_3_0_30_deps,
        wheel = "@example_lock_wheel_prompt_toolkit_3.0.30_py3_none_any//file",
    )

    pycross_wheel_library(
        name = "ptyprocess_0.7.0",
        wheel = "@example_lock_wheel_ptyprocess_0.7.0_py2.py3_none_any//file",
    )

    pycross_wheel_library(
        name = "pure_eval_0.2.2",
        wheel = "@example_lock_wheel_pure_eval_0.2.2_py3_none_any//file",
    )

    pycross_wheel_library(
        name = "pyasn1_0.4.8",
        wheel = "@example_lock_wheel_pyasn1_0.4.8_py2.py3_none_any//file",
    )

    pycross_wheel_library(
        name = "pycparser_2.21",
        wheel = "@example_lock_wheel_pycparser_2.21_py2.py3_none_any//file",
    )

    pycross_wheel_library(
        name = "pygments_2.12.0",
        wheel = "@example_lock_wheel_pygments_2.12.0_py3_none_any//file",
    )

    pycross_wheel_library(
        name = "pyrsistent_0.18.1",
        wheel = select({
            ":_env_python_darwin_arm64": "@example_lock_wheel_pyrsistent_0.18.1_cp39_cp39_macosx_10_9_universal2//file",
            ":_env_python_darwin_x86_64": "@example_lock_wheel_pyrsistent_0.18.1_cp39_cp39_macosx_10_9_universal2//file",
            ":_env_python_linux_x86_64": "@example_lock_wheel_pyrsistent_0.18.1_cp39_cp39_manylinux_2_17_x86_64.manylinux2014_x86_64//file",
        }),
    )

    _python_dateutil_2_8_2_deps = [
        ":six_1.16.0",
    ]

    pycross_wheel_library(
        name = "python_dateutil_2.8.2",
        deps = _python_dateutil_2_8_2_deps,
        wheel = "@example_lock_wheel_python_dateutil_2.8.2_py2.py3_none_any//file",
    )

    _python_jose_3_1_0_deps = [
        ":cryptography_37.0.4",
        ":ecdsa_0.18.0",
        ":pyasn1_0.4.8",
        ":rsa_4.9",
        ":six_1.16.0",
    ]

    pycross_wheel_library(
        name = "python_jose_3.1.0",
        deps = _python_jose_3_1_0_deps,
        wheel = "@example_lock_wheel_python_jose_3.1.0_py2.py3_none_any//file",
    )

    pycross_wheel_library(
        name = "pytz_2022.1",
        wheel = "@example_lock_wheel_pytz_2022.1_py2.py3_none_any//file",
    )

    pycross_wheel_library(
        name = "pyyaml_6.0",
        wheel = select({
            ":_env_python_darwin_arm64": "@example_lock_wheel_pyyaml_6.0_cp39_cp39_macosx_11_0_arm64//file",
            ":_env_python_darwin_x86_64": "@example_lock_wheel_pyyaml_6.0_cp39_cp39_macosx_10_9_x86_64//file",
            ":_env_python_linux_x86_64": "@example_lock_wheel_pyyaml_6.0_cp39_cp39_manylinux_2_5_x86_64.manylinux1_x86_64.manylinux_2_12_x86_64.manylinux2010_x86_64//file",
        }),
    )

    _requests_2_28_1_deps = [
        ":certifi_2022.6.15",
        ":charset_normalizer_2.1.0",
        ":idna_3.3",
        ":urllib3_1.26.11",
    ]

    pycross_wheel_library(
        name = "requests_2.28.1",
        deps = _requests_2_28_1_deps,
        wheel = "@example_lock_wheel_requests_2.28.1_py3_none_any//file",
    )

    _responses_0_21_0_deps = [
        ":requests_2.28.1",
        ":urllib3_1.26.11",
    ]

    pycross_wheel_library(
        name = "responses_0.21.0",
        deps = _responses_0_21_0_deps,
        wheel = "@example_lock_wheel_responses_0.21.0_py3_none_any//file",
    )

    _rsa_4_9_deps = [
        ":pyasn1_0.4.8",
    ]

    pycross_wheel_library(
        name = "rsa_4.9",
        deps = _rsa_4_9_deps,
        wheel = "@example_lock_wheel_rsa_4.9_py3_none_any//file",
    )

    _s3transfer_0_6_0_deps = [
        ":botocore_1.27.46",
    ]

    pycross_wheel_library(
        name = "s3transfer_0.6.0",
        deps = _s3transfer_0_6_0_deps,
        wheel = "@example_lock_wheel_s3transfer_0.6.0_py3_none_any//file",
    )

    _sarif_om_1_0_4_deps = [
        ":attrs_22.1.0",
        ":pbr_5.9.0",
    ]

    pycross_wheel_library(
        name = "sarif_om_1.0.4",
        deps = _sarif_om_1_0_4_deps,
        wheel = "@example_lock_wheel_sarif_om_1.0.4_py3_none_any//file",
    )

    _setproctitle_1_2_2_build_deps = [
        ":setuptools_59.2.0",
        ":wheel_0.37.0",
    ]

    pycross_wheel_build(
        name = "_build_setproctitle_1.2.2",
        sdist = "@example_lock_sdist_setproctitle_1.2.2//file",
        target_environment = _target,
        deps = _setproctitle_1_2_2_build_deps,
        tags = ["manual"],
    )

    pycross_wheel_library(
        name = "setproctitle_1.2.2",
        wheel = ":_build_setproctitle_1.2.2",
    )

    pycross_wheel_library(
        name = "setuptools_59.2.0",
        wheel = "@example_lock_wheel_setuptools_59.2.0_py3_none_any//file",
    )

    pycross_wheel_library(
        name = "six_1.16.0",
        wheel = "@example_lock_wheel_six_1.16.0_py2.py3_none_any//file",
    )

    _sqlalchemy_1_4_40_deps = [
        ":greenlet_1.1.2",
    ]

    pycross_wheel_build(
        name = "_build_sqlalchemy_1.4.40",
        sdist = "@example_lock_sdist_sqlalchemy_1.4.40//file",
        target_environment = _target,
        deps = _sqlalchemy_1_4_40_deps,
        tags = ["manual"],
    )

    pycross_wheel_library(
        name = "sqlalchemy_1.4.40",
        deps = _sqlalchemy_1_4_40_deps,
        wheel = select({
            ":_env_python_darwin_arm64": ":_build_sqlalchemy_1.4.40",
            ":_env_python_darwin_x86_64": "@example_lock_wheel_sqlalchemy_1.4.40_cp39_cp39_macosx_10_15_x86_64//file",
            ":_env_python_linux_x86_64": "@example_lock_wheel_sqlalchemy_1.4.40_cp39_cp39_manylinux_2_5_x86_64.manylinux1_x86_64.manylinux_2_17_x86_64.manylinux2014_x86_64//file",
        }),
    )

    _sqlalchemy_utils_0_38_2_deps = [
        ":six_1.16.0",
        ":sqlalchemy_1.4.40",
    ]

    pycross_wheel_library(
        name = "sqlalchemy_utils_0.38.2",
        deps = _sqlalchemy_utils_0_38_2_deps,
        wheel = "@example_lock_wheel_sqlalchemy_utils_0.38.2_py3_none_any//file",
    )

    _sshpubkeys_3_3_1_deps = [
        ":cryptography_37.0.4",
        ":ecdsa_0.18.0",
    ]

    pycross_wheel_library(
        name = "sshpubkeys_3.3.1",
        deps = _sshpubkeys_3_3_1_deps,
        wheel = "@example_lock_wheel_sshpubkeys_3.3.1_py2.py3_none_any//file",
    )

    _stack_data_0_3_0_deps = [
        ":asttokens_2.0.7",
        ":executing_0.9.1",
        ":pure_eval_0.2.2",
    ]

    pycross_wheel_library(
        name = "stack_data_0.3.0",
        deps = _stack_data_0_3_0_deps,
        wheel = "@example_lock_wheel_stack_data_0.3.0_py3_none_any//file",
    )

    pycross_wheel_library(
        name = "tomli_2.0.1",
        wheel = "@example_lock_wheel_tomli_2.0.1_py3_none_any//file",
    )

    pycross_wheel_library(
        name = "traitlets_5.3.0",
        wheel = "@example_lock_wheel_traitlets_5.3.0_py3_none_any//file",
    )

    _tree_sitter_0_20_0_build_deps = [
        ":setuptools_59.2.0",
        ":wheel_0.37.0",
    ]

    pycross_wheel_build(
        name = "_build_tree_sitter_0.20.0",
        sdist = "@example_lock_sdist_tree_sitter_0.20.0//file",
        target_environment = _target,
        deps = _tree_sitter_0_20_0_build_deps,
        tags = ["manual"],
    )

    pycross_wheel_library(
        name = "tree_sitter_0.20.0",
        wheel = select({
            ":_env_python_darwin_arm64": "@example_lock_wheel_tree_sitter_0.20.0_cp39_cp39_macosx_12_0_arm64//file",
            ":_env_python_darwin_x86_64": ":_build_tree_sitter_0.20.0",
            ":_env_python_linux_x86_64": ":_build_tree_sitter_0.20.0",
        }),
    )

    pycross_wheel_library(
        name = "typing_extensions_4.3.0",
        wheel = "@example_lock_wheel_typing_extensions_4.3.0_py3_none_any//file",
    )

    pycross_wheel_library(
        name = "urllib3_1.26.11",
        wheel = "@example_lock_wheel_urllib3_1.26.11_py2.py3_none_any//file",
    )

    pycross_wheel_library(
        name = "wcwidth_0.2.5",
        wheel = "@example_lock_wheel_wcwidth_0.2.5_py2.py3_none_any//file",
    )

    pycross_wheel_library(
        name = "websocket_client_1.3.3",
        wheel = "@example_lock_wheel_websocket_client_1.3.3_py3_none_any//file",
    )

    _werkzeug_2_2_1_deps = [
        ":markupsafe_2.1.1",
    ]

    pycross_wheel_library(
        name = "werkzeug_2.2.1",
        deps = _werkzeug_2_2_1_deps,
        wheel = "@example_lock_wheel_werkzeug_2.2.1_py3_none_any//file",
    )

    pycross_wheel_library(
        name = "wheel_0.37.0",
        wheel = "@example_lock_wheel_wheel_0.37.0_py2.py3_none_any//file",
    )

    pycross_wheel_library(
        name = "wrapt_1.14.1",
        wheel = select({
            ":_env_python_darwin_arm64": "@example_lock_wheel_wrapt_1.14.1_cp39_cp39_macosx_11_0_arm64//file",
            ":_env_python_darwin_x86_64": "@example_lock_wheel_wrapt_1.14.1_cp39_cp39_macosx_10_9_x86_64//file",
            ":_env_python_linux_x86_64": "@example_lock_wheel_wrapt_1.14.1_cp39_cp39_manylinux_2_5_x86_64.manylinux1_x86_64.manylinux_2_17_x86_64.manylinux2014_x86_64//file",
        }),
    )

    pycross_wheel_library(
        name = "xmltodict_0.13.0",
        wheel = "@example_lock_wheel_xmltodict_0.13.0_py2.py3_none_any//file",
    )

    pycross_wheel_library(
        name = "zipp_3.8.1",
        wheel = "@example_lock_wheel_zipp_3.8.1_py3_none_any//file",
    )

def repositories():
    maybe(
        http_file,
        name = "example_lock_sdist_cowsay_5.0",
        urls = [
            "https://files.pythonhosted.org/packages/6b/b8/9f497fd045d74fe21d91cbe8debae0b451229989e35b539d218547d79fc6/cowsay-5.0.tar.gz"
        ],
        sha256 = "c00e02444f5bc7332826686bd44d963caabbaba9a804a63153822edce62bbbf3",
        downloaded_file_path = "cowsay-5.0.tar.gz",
    )

    maybe(
        http_file,
        name = "example_lock_sdist_future_0.18.2",
        urls = [
            "https://files.pythonhosted.org/packages/45/0b/38b06fd9b92dc2b68d58b75f900e97884c45bedd2ff83203d933cf5851c9/future-0.18.2.tar.gz"
        ],
        sha256 = "b1bead90b70cf6ec3f0710ae53a525360fa360d306a86583adc6bf83a4db537d",
        downloaded_file_path = "future-0.18.2.tar.gz",
    )

    maybe(
        http_file,
        name = "example_lock_sdist_greenlet_1.1.2",
        urls = [
            "https://files.pythonhosted.org/packages/0c/10/754e21b5bea89d0e73f99d60c83754df7cc64db74f47d98ab187669ce341/greenlet-1.1.2.tar.gz"
        ],
        sha256 = "e30f5ea4ae2346e62cedde8794a56858a67b878dd79f7df76a0767e356b1744a",
        downloaded_file_path = "greenlet-1.1.2.tar.gz",
    )

    maybe(
        http_file,
        name = "example_lock_sdist_pbr_5.9.0",
        urls = [
            "https://files.pythonhosted.org/packages/96/9f/f4bc832eeb4ae723b86372277da56a5643b0ad472a95314e8f516a571bb0/pbr-5.9.0.tar.gz"
        ],
        sha256 = "e8dca2f4b43560edef58813969f52a56cef023146cbb8931626db80e6c1c4308",
        downloaded_file_path = "pbr-5.9.0.tar.gz",
    )

    maybe(
        http_file,
        name = "example_lock_sdist_setproctitle_1.2.2",
        urls = [
            "https://files.pythonhosted.org/packages/a1/7f/a1d4f4c7b66f0fc02f35dc5c85f45a8b4e4a7988357a29e61c14e725ef86/setproctitle-1.2.2.tar.gz"
        ],
        sha256 = "7dfb472c8852403d34007e01d6e3c68c57eb66433fb8a5c77b13b89a160d97df",
        downloaded_file_path = "setproctitle-1.2.2.tar.gz",
    )

    maybe(
        http_file,
        name = "example_lock_sdist_sqlalchemy_1.4.40",
        urls = [
            "https://files.pythonhosted.org/packages/4e/72/e36fa6563c45f8e1f2a5781f43f096500c1bca4963a34e72e8d3d8002d77/SQLAlchemy-1.4.40.tar.gz"
        ],
        sha256 = "44a660506080cc975e1dfa5776fe5f6315ddc626a77b50bf0eee18b0389ea265",
        downloaded_file_path = "SQLAlchemy-1.4.40.tar.gz",
    )

    maybe(
        http_file,
        name = "example_lock_sdist_tree_sitter_0.20.0",
        urls = [
            "https://files.pythonhosted.org/packages/10/19/434f796441f739cb0a980b76ac71bdeeff64ea75ff9ace3a8a2b18be3aeb/tree_sitter-0.20.0.tar.gz"
        ],
        sha256 = "1940f64be1e8c9c3c0e34a2258f1e4c324207534d5b1eefc5ab2960a9d98f668",
        downloaded_file_path = "tree_sitter-0.20.0.tar.gz",
    )

    maybe(
        http_file,
        name = "example_lock_wheel_appnope_0.1.3_py2.py3_none_any",
        urls = [
            "https://files.pythonhosted.org/packages/41/4a/381783f26df413dde4c70c734163d88ca0550a1361cb74a1c68f47550619/appnope-0.1.3-py2.py3-none-any.whl"
        ],
        sha256 = "265a455292d0bd8a72453494fa24df5a11eb18373a60c7c0430889f22548605e",
        downloaded_file_path = "appnope-0.1.3-py2.py3-none-any.whl",
    )

    maybe(
        http_file,
        name = "example_lock_wheel_asttokens_2.0.7_py2.py3_none_any",
        urls = [
            "https://files.pythonhosted.org/packages/ad/a8/1f7eed0f3f775937025dc3813fa5b8f1e00ddfacc6084bc48debb885ee7b/asttokens-2.0.7-py2.py3-none-any.whl"
        ],
        sha256 = "f5589ef8518f73dd82c15e1c19f795d8a62c133485e557c04443d4a1a730cf9f",
        downloaded_file_path = "asttokens-2.0.7-py2.py3-none-any.whl",
    )

    maybe(
        http_file,
        name = "example_lock_wheel_attrs_22.1.0_py2.py3_none_any",
        urls = [
            "https://files.pythonhosted.org/packages/f2/bc/d817287d1aa01878af07c19505fafd1165cd6a119e9d0821ca1d1c20312d/attrs-22.1.0-py2.py3-none-any.whl"
        ],
        sha256 = "86efa402f67bf2df34f51a335487cf46b1ec130d02b8d39fd248abfd30da551c",
        downloaded_file_path = "attrs-22.1.0-py2.py3-none-any.whl",
    )

    maybe(
        http_file,
        name = "example_lock_wheel_aws_sam_translator_1.48.0_py3_none_any",
        urls = [
            "https://files.pythonhosted.org/packages/55/e5/2d3fb8024c7acc76d8685443a03892970f30baea93cccfef6d7abdb74260/aws_sam_translator-1.48.0-py3-none-any.whl"
        ],
        sha256 = "ca4f8f9910d7713aeaba59346775bfb3198f6acb47c6704572f9bd3fc0fb5bf0",
        downloaded_file_path = "aws_sam_translator-1.48.0-py3-none-any.whl",
    )

    maybe(
        http_file,
        name = "example_lock_wheel_aws_xray_sdk_2.9.0_py2.py3_none_any",
        urls = [
            "https://files.pythonhosted.org/packages/52/4b/4e0b47146a3fdca48b00774b7280e35c48c48aa9960010c6fc4a3f7f49ad/aws_xray_sdk-2.9.0-py2.py3-none-any.whl"
        ],
        sha256 = "98216b3ac8281b51b59a8703f8ec561c460807d9d0679838f5c0179d381d7e58",
        downloaded_file_path = "aws_xray_sdk-2.9.0-py2.py3-none-any.whl",
    )

    maybe(
        http_file,
        name = "example_lock_wheel_backcall_0.2.0_py2.py3_none_any",
        urls = [
            "https://files.pythonhosted.org/packages/4c/1c/ff6546b6c12603d8dd1070aa3c3d273ad4c07f5771689a7b69a550e8c951/backcall-0.2.0-py2.py3-none-any.whl"
        ],
        sha256 = "fbbce6a29f263178a1f7915c1940bde0ec2b2a967566fe1c65c1dfb7422bd255",
        downloaded_file_path = "backcall-0.2.0-py2.py3-none-any.whl",
    )

    maybe(
        http_file,
        name = "example_lock_wheel_black_22.6.0_cp39_cp39_macosx_10_9_x86_64",
        urls = [
            "https://files.pythonhosted.org/packages/9b/22/ff6d904dcb6f92bd7c20b178ed0aa9e6814ae6452df6c573806dbc465b85/black-22.6.0-cp39-cp39-macosx_10_9_x86_64.whl"
        ],
        sha256 = "a3db5b6409b96d9bd543323b23ef32a1a2b06416d525d27e0f67e74f1446c8f2",
        downloaded_file_path = "black-22.6.0-cp39-cp39-macosx_10_9_x86_64.whl",
    )

    maybe(
        http_file,
        name = "example_lock_wheel_black_22.6.0_cp39_cp39_macosx_11_0_arm64",
        urls = [
            "https://files.pythonhosted.org/packages/19/b0/13864fd5f3090ca5379f3dcf6034f1e4f02b59620e7b8b5c6f0c85622c0b/black-22.6.0-cp39-cp39-macosx_11_0_arm64.whl"
        ],
        sha256 = "560558527e52ce8afba936fcce93a7411ab40c7d5fe8c2463e279e843c0328ee",
        downloaded_file_path = "black-22.6.0-cp39-cp39-macosx_11_0_arm64.whl",
    )

    maybe(
        http_file,
        name = "example_lock_wheel_black_22.6.0_cp39_cp39_manylinux_2_17_x86_64.manylinux2014_x86_64",
        urls = [
            "https://files.pythonhosted.org/packages/2b/d9/7331e50dad8d5149a9e2285766960ac6b732ae9b3b9796e10916ad88ff61/black-22.6.0-cp39-cp39-manylinux_2_17_x86_64.manylinux2014_x86_64.whl"
        ],
        sha256 = "b154e6bbde1e79ea3260c4b40c0b7b3109ffcdf7bc4ebf8859169a6af72cd70b",
        downloaded_file_path = "black-22.6.0-cp39-cp39-manylinux_2_17_x86_64.manylinux2014_x86_64.whl",
    )

    maybe(
        http_file,
        name = "example_lock_wheel_boto3_1.24.46_py3_none_any",
        urls = [
            "https://files.pythonhosted.org/packages/72/b4/9e6351865cf680528e4e5bc8fe26daaee51577b548256c2143e921c1a464/boto3-1.24.46-py3-none-any.whl"
        ],
        sha256 = "44026e44549148dbc5b261ead5f6b339e785680c350ef621bf85f7e2fca05b49",
        downloaded_file_path = "boto3-1.24.46-py3-none-any.whl",
    )

    maybe(
        http_file,
        name = "example_lock_wheel_botocore_1.27.46_py3_none_any",
        urls = [
            "https://files.pythonhosted.org/packages/62/e5/d9e3426e309ad69967ae775c87e0d80d2446217bd1971b83bd0d92d02c2a/botocore-1.27.46-py3-none-any.whl"
        ],
        sha256 = "747b7e94aef41498f063fc0be79c5af102d940beea713965179e1ead89c7e9ec",
        downloaded_file_path = "botocore-1.27.46-py3-none-any.whl",
    )

    maybe(
        http_file,
        name = "example_lock_wheel_certifi_2022.6.15_py3_none_any",
        urls = [
            "https://files.pythonhosted.org/packages/e9/06/d3d367b7af6305b16f0d28ae2aaeb86154fa91f144f036c2d5002a5a202b/certifi-2022.6.15-py3-none-any.whl"
        ],
        sha256 = "fe86415d55e84719d75f8b69414f6438ac3547d2078ab91b67e779ef69378412",
        downloaded_file_path = "certifi-2022.6.15-py3-none-any.whl",
    )

    maybe(
        http_file,
        name = "example_lock_wheel_cffi_1.15.1_cp39_cp39_macosx_10_9_x86_64",
        urls = [
            "https://files.pythonhosted.org/packages/18/8f/5ff70c7458d61fa8a9752e5ee9c9984c601b0060aae0c619316a1e1f1ee5/cffi-1.15.1-cp39-cp39-macosx_10_9_x86_64.whl"
        ],
        sha256 = "54a2db7b78338edd780e7ef7f9f6c442500fb0d41a5a4ea24fff1c929d5af585",
        downloaded_file_path = "cffi-1.15.1-cp39-cp39-macosx_10_9_x86_64.whl",
    )

    maybe(
        http_file,
        name = "example_lock_wheel_cffi_1.15.1_cp39_cp39_macosx_11_0_arm64",
        urls = [
            "https://files.pythonhosted.org/packages/3a/75/a162315adeaf47e94a3b7f886a8e31d77b9e525a387eef2d6f0efc96a7c8/cffi-1.15.1-cp39-cp39-macosx_11_0_arm64.whl"
        ],
        sha256 = "fcd131dd944808b5bdb38e6f5b53013c5aa4f334c5cad0c72742f6eba4b73db0",
        downloaded_file_path = "cffi-1.15.1-cp39-cp39-macosx_11_0_arm64.whl",
    )

    maybe(
        http_file,
        name = "example_lock_wheel_cffi_1.15.1_cp39_cp39_manylinux_2_17_x86_64.manylinux2014_x86_64",
        urls = [
            "https://files.pythonhosted.org/packages/2d/86/3ca57cddfa0419f6a95d1c8478f8f622ba597e3581fd501bbb915b20eb75/cffi-1.15.1-cp39-cp39-manylinux_2_17_x86_64.manylinux2014_x86_64.whl"
        ],
        sha256 = "5d598b938678ebf3c67377cdd45e09d431369c3b1a5b331058c338e201f12b27",
        downloaded_file_path = "cffi-1.15.1-cp39-cp39-manylinux_2_17_x86_64.manylinux2014_x86_64.whl",
    )

    maybe(
        http_file,
        name = "example_lock_wheel_cfn_lint_0.61.4_py3_none_any",
        urls = [
            "https://files.pythonhosted.org/packages/4f/3c/1fd0d34089208f88efbaa38e59e09f9c2a86bdb05660a0d04fad24077417/cfn_lint-0.61.4-py3-none-any.whl"
        ],
        sha256 = "1f4d87bbb1f763598c9b76d3b80f35fd67cf66351fc629d6c56e0e89d8d5356d",
        downloaded_file_path = "cfn_lint-0.61.4-py3-none-any.whl",
    )

    maybe(
        http_file,
        name = "example_lock_wheel_charset_normalizer_2.1.0_py3_none_any",
        urls = [
            "https://files.pythonhosted.org/packages/94/69/64b11e8c2fb21f08634468caef885112e682b0ebe2908e74d3616eb1c113/charset_normalizer-2.1.0-py3-none-any.whl"
        ],
        sha256 = "5189b6f22b01957427f35b6a08d9a0bc45b46d3788ef5a92e978433c7a35f8a5",
        downloaded_file_path = "charset_normalizer-2.1.0-py3-none-any.whl",
    )

    maybe(
        http_file,
        name = "example_lock_wheel_click_8.1.3_py3_none_any",
        urls = [
            "https://files.pythonhosted.org/packages/c2/f1/df59e28c642d583f7dacffb1e0965d0e00b218e0186d7858ac5233dce840/click-8.1.3-py3-none-any.whl"
        ],
        sha256 = "bb4d8133cb15a609f44e8213d9b391b0809795062913b383c62be0ee95b1db48",
        downloaded_file_path = "click-8.1.3-py3-none-any.whl",
    )

    maybe(
        http_file,
        name = "example_lock_wheel_cognitojwt_1.4.1_py3_none_any",
        urls = [
            "https://files.pythonhosted.org/packages/a5/69/97faafdc4f1900fa1b525cedae0f98aa30b0bb086d076f8d66c68a18b1b2/cognitojwt-1.4.1-py3-none-any.whl"
        ],
        sha256 = "8ee189f82289d140dc750c91e8772436b64b94d071507ace42efc22c525f42ce",
        downloaded_file_path = "cognitojwt-1.4.1-py3-none-any.whl",
    )

    maybe(
        http_file,
        name = "example_lock_wheel_cryptography_37.0.4_cp36_abi3_macosx_10_10_universal2",
        urls = [
            "https://files.pythonhosted.org/packages/eb/f0/8bc2246a422eb5cd1fe7cfc2ed522e4e3e0fd6f1c828193c0860c7030ca6/cryptography-37.0.4-cp36-abi3-macosx_10_10_universal2.whl"
        ],
        sha256 = "549153378611c0cca1042f20fd9c5030d37a72f634c9326e225c9f666d472884",
        downloaded_file_path = "cryptography-37.0.4-cp36-abi3-macosx_10_10_universal2.whl",
    )

    maybe(
        http_file,
        name = "example_lock_wheel_cryptography_37.0.4_cp36_abi3_macosx_10_10_x86_64",
        urls = [
            "https://files.pythonhosted.org/packages/c5/93/23f1cc4a39cee6ca0dc75550dc204e5af71e8bf3012d23feb1bd5b06edea/cryptography-37.0.4-cp36-abi3-macosx_10_10_x86_64.whl"
        ],
        sha256 = "a958c52505c8adf0d3822703078580d2c0456dd1d27fabfb6f76fe63d2971cd6",
        downloaded_file_path = "cryptography-37.0.4-cp36-abi3-macosx_10_10_x86_64.whl",
    )

    maybe(
        http_file,
        name = "example_lock_wheel_cryptography_37.0.4_cp36_abi3_manylinux_2_17_x86_64.manylinux2014_x86_64",
        urls = [
            "https://files.pythonhosted.org/packages/20/8b/66600f5851ec7893ace9b74445d7eaf3499571b347e339d18c76c876b0f9/cryptography-37.0.4-cp36-abi3-manylinux_2_17_x86_64.manylinux2014_x86_64.whl"
        ],
        sha256 = "f2dcb0b3b63afb6df7fd94ec6fbddac81b5492513f7b0436210d390c14d46ee8",
        downloaded_file_path = "cryptography-37.0.4-cp36-abi3-manylinux_2_17_x86_64.manylinux2014_x86_64.whl",
    )

    maybe(
        http_file,
        name = "example_lock_wheel_cython_0.29.32_cp39_cp39_manylinux_2_17_x86_64.manylinux2014_x86_64.manylinux_2_24_x86_64",
        urls = [
            "https://files.pythonhosted.org/packages/c3/8f/bb0a7182dc081fbc6608e98a8184970e7d903acfc1ec58680d46f5c915ce/Cython-0.29.32-cp39-cp39-manylinux_2_17_x86_64.manylinux2014_x86_64.manylinux_2_24_x86_64.whl"
        ],
        sha256 = "f3fd44cc362eee8ae569025f070d56208908916794b6ab21e139cea56470a2b3",
        downloaded_file_path = "Cython-0.29.32-cp39-cp39-manylinux_2_17_x86_64.manylinux2014_x86_64.manylinux_2_24_x86_64.whl",
    )

    maybe(
        http_file,
        name = "example_lock_wheel_cython_0.29.32_py2.py3_none_any",
        urls = [
            "https://files.pythonhosted.org/packages/1c/24/e3935e545b128a90146e743212703420287ed35885074a9f36b21f3bb68d/Cython-0.29.32-py2.py3-none-any.whl"
        ],
        sha256 = "eeb475eb6f0ccf6c039035eb4f0f928eb53ead88777e0a760eccb140ad90930b",
        downloaded_file_path = "Cython-0.29.32-py2.py3-none-any.whl",
    )

    maybe(
        http_file,
        name = "example_lock_wheel_decorator_5.1.1_py3_none_any",
        urls = [
            "https://files.pythonhosted.org/packages/d5/50/83c593b07763e1161326b3b8c6686f0f4b0f24d5526546bee538c89837d6/decorator-5.1.1-py3-none-any.whl"
        ],
        sha256 = "b8c3f85900b9dc423225913c5aace94729fe1fa9763b38939a95226f02d37186",
        downloaded_file_path = "decorator-5.1.1-py3-none-any.whl",
    )

    maybe(
        http_file,
        name = "example_lock_wheel_docker_5.0.3_py2.py3_none_any",
        urls = [
            "https://files.pythonhosted.org/packages/54/f3/7af47ead249fbb798d64a0438bad5c26f17ef6ac5cd324d802038eb10d90/docker-5.0.3-py2.py3-none-any.whl"
        ],
        sha256 = "7a79bb439e3df59d0a72621775d600bc8bc8b422d285824cb37103eab91d1ce0",
        downloaded_file_path = "docker-5.0.3-py2.py3-none-any.whl",
    )

    maybe(
        http_file,
        name = "example_lock_wheel_ecdsa_0.18.0_py2.py3_none_any",
        urls = [
            "https://files.pythonhosted.org/packages/09/d4/4f05f5d16a4863b30ba96c23b23e942da8889abfa1cdbabf2a0df12a4532/ecdsa-0.18.0-py2.py3-none-any.whl"
        ],
        sha256 = "80600258e7ed2f16b9aa1d7c295bd70194109ad5a30fdee0eaeefef1d4c559dd",
        downloaded_file_path = "ecdsa-0.18.0-py2.py3-none-any.whl",
    )

    maybe(
        http_file,
        name = "example_lock_wheel_executing_0.9.1_py2.py3_none_any",
        urls = [
            "https://files.pythonhosted.org/packages/29/5d/a571d62d4bf71f14ab944eb0613ba71d9b1a892643dba0a05c4c84d8f50b/executing-0.9.1-py2.py3-none-any.whl"
        ],
        sha256 = "4ce4d6082d99361c0231fc31ac1a0f56979363cc6819de0b1410784f99e49105",
        downloaded_file_path = "executing-0.9.1-py2.py3-none-any.whl",
    )

    maybe(
        http_file,
        name = "example_lock_wheel_flask_2.2.1_py3_none_any",
        urls = [
            "https://files.pythonhosted.org/packages/3c/96/6c896f80f466b7f5e2cfd6d632fe5b0464dcb412757c595a663e59589a93/Flask-2.2.1-py3-none-any.whl"
        ],
        sha256 = "3c604c48c3d5b4c63e72134044c0b4fe90ff01ef65280b9fe2d38c8860d99fe5",
        downloaded_file_path = "Flask-2.2.1-py3-none-any.whl",
    )

    maybe(
        http_file,
        name = "example_lock_wheel_flask_cors_3.0.10_py2.py3_none_any",
        urls = [
            "https://files.pythonhosted.org/packages/db/84/901e700de86604b1c4ef4b57110d4e947c218b9997adf5d38fa7da493bce/Flask_Cors-3.0.10-py2.py3-none-any.whl"
        ],
        sha256 = "74efc975af1194fc7891ff5cd85b0f7478be4f7f59fe158102e91abb72bb4438",
        downloaded_file_path = "Flask_Cors-3.0.10-py2.py3-none-any.whl",
    )

    maybe(
        http_file,
        name = "example_lock_wheel_graphql_core_3.2.1_py3_none_any",
        urls = [
            "https://files.pythonhosted.org/packages/14/28/c308fc9a5914b9a2333a546f4976d96e0d95230f16593223d727cbc19d52/graphql_core-3.2.1-py3-none-any.whl"
        ],
        sha256 = "f83c658e4968998eed1923a2e3e3eddd347e005ac0315fbb7ca4d70ea9156323",
        downloaded_file_path = "graphql_core-3.2.1-py3-none-any.whl",
    )

    maybe(
        http_file,
        name = "example_lock_wheel_greenlet_1.1.2_cp39_cp39_macosx_10_14_x86_64",
        urls = [
            "https://files.pythonhosted.org/packages/d9/e1/37db23293372c8b077675832b2f6a4ff3168a451c40bd329588825aa02dd/greenlet-1.1.2-cp39-cp39-macosx_10_14_x86_64.whl"
        ],
        sha256 = "166eac03e48784a6a6e0e5f041cfebb1ab400b394db188c48b3a84737f505b67",
        downloaded_file_path = "greenlet-1.1.2-cp39-cp39-macosx_10_14_x86_64.whl",
    )

    maybe(
        http_file,
        name = "example_lock_wheel_greenlet_1.1.2_cp39_cp39_manylinux_2_17_x86_64.manylinux2014_x86_64",
        urls = [
            "https://files.pythonhosted.org/packages/af/55/e60bc4c2bd7cad081a29f2e046f1e28e45e8529025c07ce725a84d235312/greenlet-1.1.2-cp39-cp39-manylinux_2_17_x86_64.manylinux2014_x86_64.whl"
        ],
        sha256 = "7ff61ff178250f9bb3cd89752df0f1dd0e27316a8bd1465351652b1b4a4cdfd3",
        downloaded_file_path = "greenlet-1.1.2-cp39-cp39-manylinux_2_17_x86_64.manylinux2014_x86_64.whl",
    )

    maybe(
        http_file,
        name = "example_lock_wheel_idna_3.3_py3_none_any",
        urls = [
            "https://files.pythonhosted.org/packages/04/a2/d918dcd22354d8958fe113e1a3630137e0fc8b44859ade3063982eacd2a4/idna-3.3-py3-none-any.whl"
        ],
        sha256 = "84d9dd047ffa80596e0f246e2eab0b391788b0503584e8945f2368256d2735ff",
        downloaded_file_path = "idna-3.3-py3-none-any.whl",
    )

    maybe(
        http_file,
        name = "example_lock_wheel_importlib_metadata_4.12.0_py3_none_any",
        urls = [
            "https://files.pythonhosted.org/packages/d2/a2/8c239dc898138f208dd14b441b196e7b3032b94d3137d9d8453e186967fc/importlib_metadata-4.12.0-py3-none-any.whl"
        ],
        sha256 = "7401a975809ea1fdc658c3aa4f78cc2195a0e019c5cbc4c06122884e9ae80c23",
        downloaded_file_path = "importlib_metadata-4.12.0-py3-none-any.whl",
    )

    maybe(
        http_file,
        name = "example_lock_wheel_ipython_8.4.0_py3_none_any",
        urls = [
            "https://files.pythonhosted.org/packages/fe/10/0a5925e6e8e4c948b195b4c776cae0d9d7bc6382008a0f7ed2d293bf1cfb/ipython-8.4.0-py3-none-any.whl"
        ],
        sha256 = "7ca74052a38fa25fe9bedf52da0be7d3fdd2fb027c3b778ea78dfe8c212937d1",
        downloaded_file_path = "ipython-8.4.0-py3-none-any.whl",
    )

    maybe(
        http_file,
        name = "example_lock_wheel_itsdangerous_2.1.2_py3_none_any",
        urls = [
            "https://files.pythonhosted.org/packages/68/5f/447e04e828f47465eeab35b5d408b7ebaaaee207f48b7136c5a7267a30ae/itsdangerous-2.1.2-py3-none-any.whl"
        ],
        sha256 = "2c2349112351b88699d8d4b6b075022c0808887cb7ad10069318a8b0bc88db44",
        downloaded_file_path = "itsdangerous-2.1.2-py3-none-any.whl",
    )

    maybe(
        http_file,
        name = "example_lock_wheel_jedi_0.18.1_py2.py3_none_any",
        urls = [
            "https://files.pythonhosted.org/packages/b3/0e/836f12ec50075161e365131f13f5758451645af75c2becf61c6351ecec39/jedi-0.18.1-py2.py3-none-any.whl"
        ],
        sha256 = "637c9635fcf47945ceb91cd7f320234a7be540ded6f3e99a50cb6febdfd1ba8d",
        downloaded_file_path = "jedi-0.18.1-py2.py3-none-any.whl",
    )

    maybe(
        http_file,
        name = "example_lock_wheel_jinja2_3.1.2_py3_none_any",
        urls = [
            "https://files.pythonhosted.org/packages/bc/c3/f068337a370801f372f2f8f6bad74a5c140f6fda3d9de154052708dd3c65/Jinja2-3.1.2-py3-none-any.whl"
        ],
        sha256 = "6088930bfe239f0e6710546ab9c19c9ef35e29792895fed6e6e31a023a182a61",
        downloaded_file_path = "Jinja2-3.1.2-py3-none-any.whl",
    )

    maybe(
        http_file,
        name = "example_lock_wheel_jmespath_1.0.1_py3_none_any",
        urls = [
            "https://files.pythonhosted.org/packages/31/b4/b9b800c45527aadd64d5b442f9b932b00648617eb5d63d2c7a6587b7cafc/jmespath-1.0.1-py3-none-any.whl"
        ],
        sha256 = "02e2e4cc71b5bcab88332eebf907519190dd9e6e82107fa7f83b1003a6252980",
        downloaded_file_path = "jmespath-1.0.1-py3-none-any.whl",
    )

    maybe(
        http_file,
        name = "example_lock_wheel_jschema_to_python_1.2.3_py3_none_any",
        urls = [
            "https://files.pythonhosted.org/packages/31/9e/1b6819a87c3f59170406163ba17bc55b0abe18ae552f53d2b0a2025f9c63/jschema_to_python-1.2.3-py3-none-any.whl"
        ],
        sha256 = "8a703ca7604d42d74b2815eecf99a33359a8dccbb80806cce386d5e2dd992b05",
        downloaded_file_path = "jschema_to_python-1.2.3-py3-none-any.whl",
    )

    maybe(
        http_file,
        name = "example_lock_wheel_jsondiff_2.0.0_py3_none_any",
        urls = [
            "https://files.pythonhosted.org/packages/db/15/0d33d6e8114901a7b2a56d4190e3dc1803a195495ee4f9696c630e046c9e/jsondiff-2.0.0-py3-none-any.whl"
        ],
        sha256 = "689841d66273fc88fc79f7d33f4c074774f4f214b6466e3aff0e5adaf889d1e0",
        downloaded_file_path = "jsondiff-2.0.0-py3-none-any.whl",
    )

    maybe(
        http_file,
        name = "example_lock_wheel_jsonpatch_1.32_py2.py3_none_any",
        urls = [
            "https://files.pythonhosted.org/packages/a3/55/f7c93bae36d869292aedfbcbae8b091386194874f16390d680136edd2b28/jsonpatch-1.32-py2.py3-none-any.whl"
        ],
        sha256 = "26ac385719ac9f54df8a2f0827bb8253aa3ea8ab7b3368457bcdb8c14595a397",
        downloaded_file_path = "jsonpatch-1.32-py2.py3-none-any.whl",
    )

    maybe(
        http_file,
        name = "example_lock_wheel_jsonpickle_2.2.0_py2.py3_none_any",
        urls = [
            "https://files.pythonhosted.org/packages/c6/85/b4920d8087ef480eed4e7b6b0d46c90674e923e59b22e7929fd17aba5030/jsonpickle-2.2.0-py2.py3-none-any.whl"
        ],
        sha256 = "de7f2613818aa4f234138ca11243d6359ff83ae528b2185efdd474f62bcf9ae1",
        downloaded_file_path = "jsonpickle-2.2.0-py2.py3-none-any.whl",
    )

    maybe(
        http_file,
        name = "example_lock_wheel_jsonpointer_2.3_py2.py3_none_any",
        urls = [
            "https://files.pythonhosted.org/packages/a3/be/8dc9d31b50e38172c8020c40f497ce8debdb721545ddb9fcb7cca89ea9e6/jsonpointer-2.3-py2.py3-none-any.whl"
        ],
        sha256 = "51801e558539b4e9cd268638c078c6c5746c9ac96bc38152d443400e4f3793e9",
        downloaded_file_path = "jsonpointer-2.3-py2.py3-none-any.whl",
    )

    maybe(
        http_file,
        name = "example_lock_wheel_jsonschema_3.2.0_py2.py3_none_any",
        urls = [
            "https://files.pythonhosted.org/packages/c5/8f/51e89ce52a085483359217bc72cdbf6e75ee595d5b1d4b5ade40c7e018b8/jsonschema-3.2.0-py2.py3-none-any.whl"
        ],
        sha256 = "4e5b3cf8216f577bee9ce139cbe72eca3ea4f292ec60928ff24758ce626cd163",
        downloaded_file_path = "jsonschema-3.2.0-py2.py3-none-any.whl",
    )

    maybe(
        http_file,
        name = "example_lock_wheel_junit_xml_1.9_py2.py3_none_any",
        urls = [
            "https://files.pythonhosted.org/packages/2a/93/2d896b5fd3d79b4cadd8882c06650e66d003f465c9d12c488d92853dff78/junit_xml-1.9-py2.py3-none-any.whl"
        ],
        sha256 = "ec5ca1a55aefdd76d28fcc0b135251d156c7106fa979686a4b48d62b761b4732",
        downloaded_file_path = "junit_xml-1.9-py2.py3-none-any.whl",
    )

    maybe(
        http_file,
        name = "example_lock_wheel_markupsafe_2.1.1_cp39_cp39_macosx_10_9_universal2",
        urls = [
            "https://files.pythonhosted.org/packages/06/7f/d5e46d7464360b6ac39c5b0b604770dba937e3d7cab485d2f3298454717b/MarkupSafe-2.1.1-cp39-cp39-macosx_10_9_universal2.whl"
        ],
        sha256 = "e04e26803c9c3851c931eac40c695602c6295b8d432cbe78609649ad9bd2da8a",
        downloaded_file_path = "MarkupSafe-2.1.1-cp39-cp39-macosx_10_9_universal2.whl",
    )

    maybe(
        http_file,
        name = "example_lock_wheel_markupsafe_2.1.1_cp39_cp39_macosx_10_9_x86_64",
        urls = [
            "https://files.pythonhosted.org/packages/26/03/2c11ba1a8b2327adea3f59f1c9c9ee9c59e86023925f929e63c4f028b10a/MarkupSafe-2.1.1-cp39-cp39-macosx_10_9_x86_64.whl"
        ],
        sha256 = "b87db4360013327109564f0e591bd2a3b318547bcef31b468a92ee504d07ae4f",
        downloaded_file_path = "MarkupSafe-2.1.1-cp39-cp39-macosx_10_9_x86_64.whl",
    )

    maybe(
        http_file,
        name = "example_lock_wheel_markupsafe_2.1.1_cp39_cp39_manylinux_2_17_x86_64.manylinux2014_x86_64",
        urls = [
            "https://files.pythonhosted.org/packages/df/06/c515c5bc43b90462e753bc768e6798193c6520c9c7eb2054c7466779a9db/MarkupSafe-2.1.1-cp39-cp39-manylinux_2_17_x86_64.manylinux2014_x86_64.whl"
        ],
        sha256 = "56442863ed2b06d19c37f94d999035e15ee982988920e12a5b4ba29b62ad1f77",
        downloaded_file_path = "MarkupSafe-2.1.1-cp39-cp39-manylinux_2_17_x86_64.manylinux2014_x86_64.whl",
    )

    maybe(
        http_file,
        name = "example_lock_wheel_matplotlib_inline_0.1.3_py3_none_any",
        urls = [
            "https://files.pythonhosted.org/packages/a6/2d/2230afd570c70074e80fd06857ba2bdc5f10c055bd9125665fe276fadb67/matplotlib_inline-0.1.3-py3-none-any.whl"
        ],
        sha256 = "aed605ba3b72462d64d475a21a9296f400a19c4f74a31b59103d2a99ffd5aa5c",
        downloaded_file_path = "matplotlib_inline-0.1.3-py3-none-any.whl",
    )

    maybe(
        http_file,
        name = "example_lock_wheel_moto_3.1.1_py2.py3_none_any",
        urls = [
            "https://files.pythonhosted.org/packages/c4/f6/d65e8cf5fddb70e83bb00b6b2d08a73afcd13e26a5bf1c1ce9d737f39f5b/moto-3.1.1-py2.py3-none-any.whl"
        ],
        sha256 = "462495563847134ea8ef4135a229731a598a8e7b6b10a74f8d745815aa20a25b",
        downloaded_file_path = "moto-3.1.1-py2.py3-none-any.whl",
    )

    maybe(
        http_file,
        name = "example_lock_wheel_mypy_extensions_0.4.3_py2.py3_none_any",
        urls = [
            "https://files.pythonhosted.org/packages/5c/eb/975c7c080f3223a5cdaff09612f3a5221e4ba534f7039db34c35d95fa6a5/mypy_extensions-0.4.3-py2.py3-none-any.whl"
        ],
        sha256 = "090fedd75945a69ae91ce1303b5824f428daf5a028d2f6ab8a299250a846f15d",
        downloaded_file_path = "mypy_extensions-0.4.3-py2.py3-none-any.whl",
    )

    maybe(
        http_file,
        name = "example_lock_wheel_networkx_2.8.5_py3_none_any",
        urls = [
            "https://files.pythonhosted.org/packages/95/1b/14b5b17c52f7329b875e4ad2dcad23c808778b42ef6d250a7223d4dc378a/networkx-2.8.5-py3-none-any.whl"
        ],
        sha256 = "a762f4b385692d9c3a6f2912d058d76d29a827deaedf9e63ed14d397b8030687",
        downloaded_file_path = "networkx-2.8.5-py3-none-any.whl",
    )

    maybe(
        http_file,
        name = "example_lock_wheel_numpy_1.22.3_cp39_cp39_macosx_10_14_x86_64",
        urls = [
            "https://files.pythonhosted.org/packages/58/55/6fef1ef16124066b96d5b5cb107c8e0af20b2007b79ba8f7e52ca2e1b2b7/numpy-1.22.3-cp39-cp39-macosx_10_14_x86_64.whl"
        ],
        sha256 = "2c10a93606e0b4b95c9b04b77dc349b398fdfbda382d2a39ba5a822f669a0123",
        downloaded_file_path = "numpy-1.22.3-cp39-cp39-macosx_10_14_x86_64.whl",
    )

    maybe(
        http_file,
        name = "example_lock_wheel_numpy_1.22.3_cp39_cp39_macosx_11_0_arm64",
        urls = [
            "https://files.pythonhosted.org/packages/22/66/95849d4d0116eef22d42355f1e8b67b43b0799093914fce369551bcc9d2f/numpy-1.22.3-cp39-cp39-macosx_11_0_arm64.whl"
        ],
        sha256 = "fade0d4f4d292b6f39951b6836d7a3c7ef5b2347f3c420cd9820a1d90d794802",
        downloaded_file_path = "numpy-1.22.3-cp39-cp39-macosx_11_0_arm64.whl",
    )

    maybe(
        http_file,
        name = "example_lock_wheel_numpy_1.22.3_cp39_cp39_manylinux_2_17_x86_64.manylinux2014_x86_64",
        urls = [
            "https://files.pythonhosted.org/packages/25/2f/811ad95effd790cd13cdea494e1cd7520ebc3bf049c3e88c3ca4ba8175c5/numpy-1.22.3-cp39-cp39-manylinux_2_17_x86_64.manylinux2014_x86_64.whl"
        ],
        sha256 = "97098b95aa4e418529099c26558eeb8486e66bd1e53a6b606d684d0c3616b168",
        downloaded_file_path = "numpy-1.22.3-cp39-cp39-manylinux_2_17_x86_64.manylinux2014_x86_64.whl",
    )

    maybe(
        http_file,
        name = "example_lock_wheel_parso_0.8.3_py2.py3_none_any",
        urls = [
            "https://files.pythonhosted.org/packages/05/63/8011bd08a4111858f79d2b09aad86638490d62fbf881c44e434a6dfca87b/parso-0.8.3-py2.py3-none-any.whl"
        ],
        sha256 = "c001d4636cd3aecdaf33cbb40aebb59b094be2a74c556778ef5576c175e19e75",
        downloaded_file_path = "parso-0.8.3-py2.py3-none-any.whl",
    )

    maybe(
        http_file,
        name = "example_lock_wheel_pathspec_0.9.0_py2.py3_none_any",
        urls = [
            "https://files.pythonhosted.org/packages/42/ba/a9d64c7bcbc7e3e8e5f93a52721b377e994c22d16196e2b0f1236774353a/pathspec-0.9.0-py2.py3-none-any.whl"
        ],
        sha256 = "7d15c4ddb0b5c802d161efc417ec1a2558ea2653c2e8ad9c19098201dc1c993a",
        downloaded_file_path = "pathspec-0.9.0-py2.py3-none-any.whl",
    )

    maybe(
        http_file,
        name = "example_lock_wheel_pexpect_4.8.0_py2.py3_none_any",
        urls = [
            "https://files.pythonhosted.org/packages/39/7b/88dbb785881c28a102619d46423cb853b46dbccc70d3ac362d99773a78ce/pexpect-4.8.0-py2.py3-none-any.whl"
        ],
        sha256 = "0b48a55dcb3c05f3329815901ea4fc1537514d6ba867a152b581d69ae3710937",
        downloaded_file_path = "pexpect-4.8.0-py2.py3-none-any.whl",
    )

    maybe(
        http_file,
        name = "example_lock_wheel_pickleshare_0.7.5_py2.py3_none_any",
        urls = [
            "https://files.pythonhosted.org/packages/9a/41/220f49aaea88bc6fa6cba8d05ecf24676326156c23b991e80b3f2fc24c77/pickleshare-0.7.5-py2.py3-none-any.whl"
        ],
        sha256 = "9649af414d74d4df115d5d718f82acb59c9d418196b7b4290ed47a12ce62df56",
        downloaded_file_path = "pickleshare-0.7.5-py2.py3-none-any.whl",
    )

    maybe(
        http_file,
        name = "example_lock_wheel_platformdirs_2.5.2_py3_none_any",
        urls = [
            "https://files.pythonhosted.org/packages/ed/22/967181c94c3a4063fe64e15331b4cb366bdd7dfbf46fcb8ad89650026fec/platformdirs-2.5.2-py3-none-any.whl"
        ],
        sha256 = "027d8e83a2d7de06bbac4e5ef7e023c02b863d7ea5d079477e722bb41ab25788",
        downloaded_file_path = "platformdirs-2.5.2-py3-none-any.whl",
    )

    maybe(
        http_file,
        name = "example_lock_wheel_prompt_toolkit_3.0.30_py3_none_any",
        urls = [
            "https://files.pythonhosted.org/packages/b0/8f/09a88160539a1164de562809f8b1d0a36dc1f9d8c6473f4b71ebed17b953/prompt_toolkit-3.0.30-py3-none-any.whl"
        ],
        sha256 = "d8916d3f62a7b67ab353a952ce4ced6a1d2587dfe9ef8ebc30dd7c386751f289",
        downloaded_file_path = "prompt_toolkit-3.0.30-py3-none-any.whl",
    )

    maybe(
        http_file,
        name = "example_lock_wheel_ptyprocess_0.7.0_py2.py3_none_any",
        urls = [
            "https://files.pythonhosted.org/packages/22/a6/858897256d0deac81a172289110f31629fc4cee19b6f01283303e18c8db3/ptyprocess-0.7.0-py2.py3-none-any.whl"
        ],
        sha256 = "4b41f3967fce3af57cc7e94b888626c18bf37a083e3651ca8feeb66d492fef35",
        downloaded_file_path = "ptyprocess-0.7.0-py2.py3-none-any.whl",
    )

    maybe(
        http_file,
        name = "example_lock_wheel_pure_eval_0.2.2_py3_none_any",
        urls = [
            "https://files.pythonhosted.org/packages/2b/27/77f9d5684e6bce929f5cfe18d6cfbe5133013c06cb2fbf5933670e60761d/pure_eval-0.2.2-py3-none-any.whl"
        ],
        sha256 = "01eaab343580944bc56080ebe0a674b39ec44a945e6d09ba7db3cb8cec289350",
        downloaded_file_path = "pure_eval-0.2.2-py3-none-any.whl",
    )

    maybe(
        http_file,
        name = "example_lock_wheel_pyasn1_0.4.8_py2.py3_none_any",
        urls = [
            "https://files.pythonhosted.org/packages/62/1e/a94a8d635fa3ce4cfc7f506003548d0a2447ae76fd5ca53932970fe3053f/pyasn1-0.4.8-py2.py3-none-any.whl"
        ],
        sha256 = "39c7e2ec30515947ff4e87fb6f456dfc6e84857d34be479c9d4a4ba4bf46aa5d",
        downloaded_file_path = "pyasn1-0.4.8-py2.py3-none-any.whl",
    )

    maybe(
        http_file,
        name = "example_lock_wheel_pycparser_2.21_py2.py3_none_any",
        urls = [
            "https://files.pythonhosted.org/packages/62/d5/5f610ebe421e85889f2e55e33b7f9a6795bd982198517d912eb1c76e1a53/pycparser-2.21-py2.py3-none-any.whl"
        ],
        sha256 = "8ee45429555515e1f6b185e78100aea234072576aa43ab53aefcae078162fca9",
        downloaded_file_path = "pycparser-2.21-py2.py3-none-any.whl",
    )

    maybe(
        http_file,
        name = "example_lock_wheel_pygments_2.12.0_py3_none_any",
        urls = [
            "https://files.pythonhosted.org/packages/5c/8e/1d9017950034297fffa336c72e693a5b51bbf85141b24a763882cf1977b5/Pygments-2.12.0-py3-none-any.whl"
        ],
        sha256 = "dc9c10fb40944260f6ed4c688ece0cd2048414940f1cea51b8b226318411c519",
        downloaded_file_path = "Pygments-2.12.0-py3-none-any.whl",
    )

    maybe(
        http_file,
        name = "example_lock_wheel_pyrsistent_0.18.1_cp39_cp39_macosx_10_9_universal2",
        urls = [
            "https://files.pythonhosted.org/packages/15/fa/64ed4c29d36df26906f03a1fb360056e3cbc063b00446f3663252bdd175a/pyrsistent-0.18.1-cp39-cp39-macosx_10_9_universal2.whl"
        ],
        sha256 = "f87cc2863ef33c709e237d4b5f4502a62a00fab450c9e020892e8e2ede5847f5",
        downloaded_file_path = "pyrsistent-0.18.1-cp39-cp39-macosx_10_9_universal2.whl",
    )

    maybe(
        http_file,
        name = "example_lock_wheel_pyrsistent_0.18.1_cp39_cp39_manylinux_2_17_x86_64.manylinux2014_x86_64",
        urls = [
            "https://files.pythonhosted.org/packages/41/cb/733dc14ca2ca17768ea28254b95dbc98f398e46dbf4dba94d4fac491af6e/pyrsistent-0.18.1-cp39-cp39-manylinux_2_17_x86_64.manylinux2014_x86_64.whl"
        ],
        sha256 = "6bc66318fb7ee012071b2792024564973ecc80e9522842eb4e17743604b5e045",
        downloaded_file_path = "pyrsistent-0.18.1-cp39-cp39-manylinux_2_17_x86_64.manylinux2014_x86_64.whl",
    )

    maybe(
        http_file,
        name = "example_lock_wheel_python_dateutil_2.8.2_py2.py3_none_any",
        urls = [
            "https://files.pythonhosted.org/packages/36/7a/87837f39d0296e723bb9b62bbb257d0355c7f6128853c78955f57342a56d/python_dateutil-2.8.2-py2.py3-none-any.whl"
        ],
        sha256 = "961d03dc3453ebbc59dbdea9e4e11c5651520a876d0f4db161e8674aae935da9",
        downloaded_file_path = "python_dateutil-2.8.2-py2.py3-none-any.whl",
    )

    maybe(
        http_file,
        name = "example_lock_wheel_python_jose_3.1.0_py2.py3_none_any",
        urls = [
            "https://files.pythonhosted.org/packages/6c/80/5bdf2543fe002dc74429e9360148deb4d9e0b453acdc2b5c6fb1617f4f9d/python_jose-3.1.0-py2.py3-none-any.whl"
        ],
        sha256 = "1ac4caf4bfebd5a70cf5bd82702ed850db69b0b6e1d0ae7368e5f99ac01c9571",
        downloaded_file_path = "python_jose-3.1.0-py2.py3-none-any.whl",
    )

    maybe(
        http_file,
        name = "example_lock_wheel_pytz_2022.1_py2.py3_none_any",
        urls = [
            "https://files.pythonhosted.org/packages/60/2e/dec1cc18c51b8df33c7c4d0a321b084cf38e1733b98f9d15018880fb4970/pytz-2022.1-py2.py3-none-any.whl"
        ],
        sha256 = "e68985985296d9a66a881eb3193b0906246245294a881e7c8afe623866ac6a5c",
        downloaded_file_path = "pytz-2022.1-py2.py3-none-any.whl",
    )

    maybe(
        http_file,
        name = "example_lock_wheel_pyyaml_6.0_cp39_cp39_macosx_10_9_x86_64",
        urls = [
            "https://files.pythonhosted.org/packages/f5/6f/b8b4515346af7c33d3b07cd8ca8ea0700ca72e8d7a750b2b87ac0268ca4e/PyYAML-6.0-cp39-cp39-macosx_10_9_x86_64.whl"
        ],
        sha256 = "055d937d65826939cb044fc8c9b08889e8c743fdc6a32b33e2390f66013e449b",
        downloaded_file_path = "PyYAML-6.0-cp39-cp39-macosx_10_9_x86_64.whl",
    )

    maybe(
        http_file,
        name = "example_lock_wheel_pyyaml_6.0_cp39_cp39_macosx_11_0_arm64",
        urls = [
            "https://files.pythonhosted.org/packages/67/d4/b95266228a25ef5bd70984c08b4efce2c035a4baa5ccafa827b266e3dc36/PyYAML-6.0-cp39-cp39-macosx_11_0_arm64.whl"
        ],
        sha256 = "e61ceaab6f49fb8bdfaa0f92c4b57bcfbea54c09277b1b4f7ac376bfb7a7c174",
        downloaded_file_path = "PyYAML-6.0-cp39-cp39-macosx_11_0_arm64.whl",
    )

    maybe(
        http_file,
        name = "example_lock_wheel_pyyaml_6.0_cp39_cp39_manylinux_2_5_x86_64.manylinux1_x86_64.manylinux_2_12_x86_64.manylinux2010_x86_64",
        urls = [
            "https://files.pythonhosted.org/packages/12/fc/a4d5a7554e0067677823f7265cb3ae22aed8a238560b5133b58cda252dad/PyYAML-6.0-cp39-cp39-manylinux_2_5_x86_64.manylinux1_x86_64.manylinux_2_12_x86_64.manylinux2010_x86_64.whl"
        ],
        sha256 = "40527857252b61eacd1d9af500c3337ba8deb8fc298940291486c465c8b46ec0",
        downloaded_file_path = "PyYAML-6.0-cp39-cp39-manylinux_2_5_x86_64.manylinux1_x86_64.manylinux_2_12_x86_64.manylinux2010_x86_64.whl",
    )

    maybe(
        http_file,
        name = "example_lock_wheel_requests_2.28.1_py3_none_any",
        urls = [
            "https://files.pythonhosted.org/packages/ca/91/6d9b8ccacd0412c08820f72cebaa4f0c0441b5cda699c90f618b6f8a1b42/requests-2.28.1-py3-none-any.whl"
        ],
        sha256 = "8fefa2a1a1365bf5520aac41836fbee479da67864514bdb821f31ce07ce65349",
        downloaded_file_path = "requests-2.28.1-py3-none-any.whl",
    )

    maybe(
        http_file,
        name = "example_lock_wheel_responses_0.21.0_py3_none_any",
        urls = [
            "https://files.pythonhosted.org/packages/bb/ad/fdd56219f0e320293c513ef0b3cdd018802a1bcfdb29ed9bc0c3bcb97f31/responses-0.21.0-py3-none-any.whl"
        ],
        sha256 = "2dcc863ba63963c0c3d9ee3fa9507cbe36b7d7b0fccb4f0bdfd9e96c539b1487",
        downloaded_file_path = "responses-0.21.0-py3-none-any.whl",
    )

    maybe(
        http_file,
        name = "example_lock_wheel_rsa_4.9_py3_none_any",
        urls = [
            "https://files.pythonhosted.org/packages/49/97/fa78e3d2f65c02c8e1268b9aba606569fe97f6c8f7c2d74394553347c145/rsa-4.9-py3-none-any.whl"
        ],
        sha256 = "90260d9058e514786967344d0ef75fa8727eed8a7d2e43ce9f4bcf1b536174f7",
        downloaded_file_path = "rsa-4.9-py3-none-any.whl",
    )

    maybe(
        http_file,
        name = "example_lock_wheel_s3transfer_0.6.0_py3_none_any",
        urls = [
            "https://files.pythonhosted.org/packages/5e/c6/af903b5fab3f9b5b1e883f49a770066314c6dcceb589cf938d48c89556c1/s3transfer-0.6.0-py3-none-any.whl"
        ],
        sha256 = "06176b74f3a15f61f1b4f25a1fc29a4429040b7647133a463da8fa5bd28d5ecd",
        downloaded_file_path = "s3transfer-0.6.0-py3-none-any.whl",
    )

    maybe(
        http_file,
        name = "example_lock_wheel_sarif_om_1.0.4_py3_none_any",
        urls = [
            "https://files.pythonhosted.org/packages/82/7c/1d3d0467565aa8b3e77ab8712042a09dd1158056826f45783f3d2b34adf1/sarif_om-1.0.4-py3-none-any.whl"
        ],
        sha256 = "539ef47a662329b1c8502388ad92457425e95dc0aaaf995fe46f4984c4771911",
        downloaded_file_path = "sarif_om-1.0.4-py3-none-any.whl",
    )

    maybe(
        http_file,
        name = "example_lock_wheel_setuptools_59.2.0_py3_none_any",
        urls = [
            "https://files.pythonhosted.org/packages/18/ad/ec41343a49a0371ea40daf37b1ba2c11333cdd121cb378161635d14b9750/setuptools-59.2.0-py3-none-any.whl"
        ],
        sha256 = "4adde3d1e1c89bde1c643c64d89cdd94cbfd8c75252ee459d4500bccb9c7d05d",
        downloaded_file_path = "setuptools-59.2.0-py3-none-any.whl",
    )

    maybe(
        http_file,
        name = "example_lock_wheel_six_1.16.0_py2.py3_none_any",
        urls = [
            "https://files.pythonhosted.org/packages/d9/5a/e7c31adbe875f2abbb91bd84cf2dc52d792b5a01506781dbcf25c91daf11/six-1.16.0-py2.py3-none-any.whl"
        ],
        sha256 = "8abb2f1d86890a2dfb989f9a77cfcfd3e47c2a354b01111771326f8aa26e0254",
        downloaded_file_path = "six-1.16.0-py2.py3-none-any.whl",
    )

    maybe(
        http_file,
        name = "example_lock_wheel_sqlalchemy_1.4.40_cp39_cp39_macosx_10_15_x86_64",
        urls = [
            "https://files.pythonhosted.org/packages/07/5a/6b8e0925240df8602a27189d08edd279aa45a27177be8867634e13814f40/SQLAlchemy-1.4.40-cp39-cp39-macosx_10_15_x86_64.whl"
        ],
        sha256 = "0992f3cc640ec0f88f721e426da884c34ff0a60eb73d3d64172e23dfadfc8a0b",
        downloaded_file_path = "SQLAlchemy-1.4.40-cp39-cp39-macosx_10_15_x86_64.whl",
    )

    maybe(
        http_file,
        name = "example_lock_wheel_sqlalchemy_1.4.40_cp39_cp39_manylinux_2_5_x86_64.manylinux1_x86_64.manylinux_2_17_x86_64.manylinux2014_x86_64",
        urls = [
            "https://files.pythonhosted.org/packages/76/02/1aca0e9250c2ff2d72bdc4ce2bd9ecf8df40ed0bcd82123def5db99ed687/SQLAlchemy-1.4.40-cp39-cp39-manylinux_2_5_x86_64.manylinux1_x86_64.manylinux_2_17_x86_64.manylinux2014_x86_64.whl"
        ],
        sha256 = "0c956a5d1adb49a35d78ef0fae26717afc48a36262359bb5b0cbd7a3a247c26f",
        downloaded_file_path = "SQLAlchemy-1.4.40-cp39-cp39-manylinux_2_5_x86_64.manylinux1_x86_64.manylinux_2_17_x86_64.manylinux2014_x86_64.whl",
    )

    maybe(
        http_file,
        name = "example_lock_wheel_sqlalchemy_utils_0.38.2_py3_none_any",
        urls = [
            "https://files.pythonhosted.org/packages/b1/f9/7fdb5a12d63f1d059530dd807e696f16062fa0630fac6b4ce1c74c4056f5/SQLAlchemy_Utils-0.38.2-py3-none-any.whl"
        ],
        sha256 = "622235b1598f97300e4d08820ab024f5219c9a6309937a8b908093f487b4ba54",
        downloaded_file_path = "SQLAlchemy_Utils-0.38.2-py3-none-any.whl",
    )

    maybe(
        http_file,
        name = "example_lock_wheel_sshpubkeys_3.3.1_py2.py3_none_any",
        urls = [
            "https://files.pythonhosted.org/packages/e3/76/bc71db2f6830196554e5a197331ad668c049a12fb331075f4f579ff73cb4/sshpubkeys-3.3.1-py2.py3-none-any.whl"
        ],
        sha256 = "946f76b8fe86704b0e7c56a00d80294e39bc2305999844f079a217885060b1ac",
        downloaded_file_path = "sshpubkeys-3.3.1-py2.py3-none-any.whl",
    )

    maybe(
        http_file,
        name = "example_lock_wheel_stack_data_0.3.0_py3_none_any",
        urls = [
            "https://files.pythonhosted.org/packages/f3/99/9e6a7eea1618eecf8767dc7970722003761403893fa978fa30be6f3846eb/stack_data-0.3.0-py3-none-any.whl"
        ],
        sha256 = "aa1d52d14d09c7a9a12bb740e6bdfffe0f5e8f4f9218d85e7c73a8c37f7ae38d",
        downloaded_file_path = "stack_data-0.3.0-py3-none-any.whl",
    )

    maybe(
        http_file,
        name = "example_lock_wheel_tomli_2.0.1_py3_none_any",
        urls = [
            "https://files.pythonhosted.org/packages/97/75/10a9ebee3fd790d20926a90a2547f0bf78f371b2f13aa822c759680ca7b9/tomli-2.0.1-py3-none-any.whl"
        ],
        sha256 = "939de3e7a6161af0c887ef91b7d41a53e7c5a1ca976325f429cb46ea9bc30ecc",
        downloaded_file_path = "tomli-2.0.1-py3-none-any.whl",
    )

    maybe(
        http_file,
        name = "example_lock_wheel_traitlets_5.3.0_py3_none_any",
        urls = [
            "https://files.pythonhosted.org/packages/83/a9/1059771062cb80901c34a4dea020e76269412e69300b4ba12e3356865ad8/traitlets-5.3.0-py3-none-any.whl"
        ],
        sha256 = "65fa18961659635933100db8ca120ef6220555286949774b9cfc106f941d1c7a",
        downloaded_file_path = "traitlets-5.3.0-py3-none-any.whl",
    )

    maybe(
        http_file,
        name = "example_lock_wheel_tree_sitter_0.20.0_cp39_cp39_macosx_12_0_arm64",
        urls = [
            "https://files.pythonhosted.org/packages/c0/6a/c36db85f3cb408f8cdf1329902ebfd88546c04b9224f952e99855092390b/tree_sitter-0.20.0-cp39-cp39-macosx_12_0_arm64.whl"
        ],
        sha256 = "51a609a7c1bd9d9e75d92ee128c12c7852ae70a482900fbbccf3d13a79e0378c",
        downloaded_file_path = "tree_sitter-0.20.0-cp39-cp39-macosx_12_0_arm64.whl",
    )

    maybe(
        http_file,
        name = "example_lock_wheel_typing_extensions_4.3.0_py3_none_any",
        urls = [
            "https://files.pythonhosted.org/packages/ed/d6/2afc375a8d55b8be879d6b4986d4f69f01115e795e36827fd3a40166028b/typing_extensions-4.3.0-py3-none-any.whl"
        ],
        sha256 = "25642c956049920a5aa49edcdd6ab1e06d7e5d467fc00e0506c44ac86fbfca02",
        downloaded_file_path = "typing_extensions-4.3.0-py3-none-any.whl",
    )

    maybe(
        http_file,
        name = "example_lock_wheel_urllib3_1.26.11_py2.py3_none_any",
        urls = [
            "https://files.pythonhosted.org/packages/d1/cb/4783c8f1a90f89e260dbf72ebbcf25931f3a28f8f80e2e90f8a589941b19/urllib3-1.26.11-py2.py3-none-any.whl"
        ],
        sha256 = "c33ccba33c819596124764c23a97d25f32b28433ba0dedeb77d873a38722c9bc",
        downloaded_file_path = "urllib3-1.26.11-py2.py3-none-any.whl",
    )

    maybe(
        http_file,
        name = "example_lock_wheel_wcwidth_0.2.5_py2.py3_none_any",
        urls = [
            "https://files.pythonhosted.org/packages/59/7c/e39aca596badaf1b78e8f547c807b04dae603a433d3e7a7e04d67f2ef3e5/wcwidth-0.2.5-py2.py3-none-any.whl"
        ],
        sha256 = "beb4802a9cebb9144e99086eff703a642a13d6a0052920003a230f3294bbe784",
        downloaded_file_path = "wcwidth-0.2.5-py2.py3-none-any.whl",
    )

    maybe(
        http_file,
        name = "example_lock_wheel_websocket_client_1.3.3_py3_none_any",
        urls = [
            "https://files.pythonhosted.org/packages/67/b4/91683d7d5f66393e8877492fe4763304f82dbe308658a8db98f7a9e20baf/websocket_client-1.3.3-py3-none-any.whl"
        ],
        sha256 = "5d55652dc1d0b3c734f044337d929aaf83f4f9138816ec680c1aefefb4dc4877",
        downloaded_file_path = "websocket_client-1.3.3-py3-none-any.whl",
    )

    maybe(
        http_file,
        name = "example_lock_wheel_werkzeug_2.2.1_py3_none_any",
        urls = [
            "https://files.pythonhosted.org/packages/c0/93/d6d60870e47162ea6a1bbdd787649eea776b2a70618dd66ed87cb2238543/Werkzeug-2.2.1-py3-none-any.whl"
        ],
        sha256 = "7e1db6a5ba6b9a8be061e47e900456355b8714c0f238b0313f53afce1a55a79a",
        downloaded_file_path = "Werkzeug-2.2.1-py3-none-any.whl",
    )

    maybe(
        http_file,
        name = "example_lock_wheel_wheel_0.37.0_py2.py3_none_any",
        urls = [
            "https://files.pythonhosted.org/packages/04/80/cad93b40262f5d09f6de82adbee452fd43cdff60830b56a74c5930f7e277/wheel-0.37.0-py2.py3-none-any.whl"
        ],
        sha256 = "21014b2bd93c6d0034b6ba5d35e4eb284340e09d63c59aef6fc14b0f346146fd",
        downloaded_file_path = "wheel-0.37.0-py2.py3-none-any.whl",
    )

    maybe(
        http_file,
        name = "example_lock_wheel_wrapt_1.14.1_cp39_cp39_macosx_10_9_x86_64",
        urls = [
            "https://files.pythonhosted.org/packages/d9/ab/3ba5816dd466ffd7242913708771d258569825ab76fd29d7fd85b9361311/wrapt-1.14.1-cp39-cp39-macosx_10_9_x86_64.whl"
        ],
        sha256 = "3232822c7d98d23895ccc443bbdf57c7412c5a65996c30442ebe6ed3df335383",
        downloaded_file_path = "wrapt-1.14.1-cp39-cp39-macosx_10_9_x86_64.whl",
    )

    maybe(
        http_file,
        name = "example_lock_wheel_wrapt_1.14.1_cp39_cp39_macosx_11_0_arm64",
        urls = [
            "https://files.pythonhosted.org/packages/bb/70/73c54e24ea69a8b06ae9649e61d5e64f2b4bdfc6f202fc7794abeac1ed20/wrapt-1.14.1-cp39-cp39-macosx_11_0_arm64.whl"
        ],
        sha256 = "988635d122aaf2bdcef9e795435662bcd65b02f4f4c1ae37fbee7401c440b3a7",
        downloaded_file_path = "wrapt-1.14.1-cp39-cp39-macosx_11_0_arm64.whl",
    )

    maybe(
        http_file,
        name = "example_lock_wheel_wrapt_1.14.1_cp39_cp39_manylinux_2_5_x86_64.manylinux1_x86_64.manylinux_2_17_x86_64.manylinux2014_x86_64",
        urls = [
            "https://files.pythonhosted.org/packages/e0/6a/3c660fa34c8106aa9719f2a6636c1c3ea7afd5931ae665eb197fdf4def84/wrapt-1.14.1-cp39-cp39-manylinux_2_5_x86_64.manylinux1_x86_64.manylinux_2_17_x86_64.manylinux2014_x86_64.whl"
        ],
        sha256 = "40e7bc81c9e2b2734ea4bc1aceb8a8f0ceaac7c5299bc5d69e37c44d9081d43b",
        downloaded_file_path = "wrapt-1.14.1-cp39-cp39-manylinux_2_5_x86_64.manylinux1_x86_64.manylinux_2_17_x86_64.manylinux2014_x86_64.whl",
    )

    maybe(
        http_file,
        name = "example_lock_wheel_xmltodict_0.13.0_py2.py3_none_any",
        urls = [
            "https://files.pythonhosted.org/packages/94/db/fd0326e331726f07ff7f40675cd86aa804bfd2e5016c727fa761c934990e/xmltodict-0.13.0-py2.py3-none-any.whl"
        ],
        sha256 = "aa89e8fd76320154a40d19a0df04a4695fb9dc5ba977cbb68ab3e4eb225e7852",
        downloaded_file_path = "xmltodict-0.13.0-py2.py3-none-any.whl",
    )

    maybe(
        http_file,
        name = "example_lock_wheel_zipp_3.8.1_py3_none_any",
        urls = [
            "https://files.pythonhosted.org/packages/f0/36/639d6742bcc3ffdce8b85c31d79fcfae7bb04b95f0e5c4c6f8b206a038cc/zipp-3.8.1-py3-none-any.whl"
        ],
        sha256 = "47c40d7fe183a6f21403a199b3e4192cca5774656965b0a4988ad2f8feb5f009",
        downloaded_file_path = "zipp-3.8.1-py3-none-any.whl",
    )

