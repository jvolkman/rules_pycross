load("@bazel_tools//tools/build_defs/repo:http.bzl", "http_file")
load("@bazel_tools//tools/build_defs/repo:utils.bzl", "maybe")
load("@jvolkman_rules_pycross//pycross:defs.bzl", "pycross_wheel_build", "pycross_wheel_library", "pypi_file")

PINS = {
    "appnope": "appnope_0.1.3",
    "asttokens": "asttokens_2.0.5",
    "attrs": "attrs_21.4.0",
    "aws_sam_translator": "aws_sam_translator_1.45.0",
    "aws_xray_sdk": "aws_xray_sdk_2.9.0",
    "backcall": "backcall_0.2.0",
    "boto3": "boto3_1.23.4",
    "botocore": "botocore_1.26.4",
    "certifi": "certifi_2022.5.18.1",
    "cffi": "cffi_1.15.0",
    "cfn_lint": "cfn_lint_0.60.1",
    "charset_normalizer": "charset_normalizer_2.0.12",
    "click": "click_8.1.3",
    "cognitojwt": "cognitojwt_1.4.1",
    "cryptography": "cryptography_37.0.2",
    "cython": "cython_0.29.30",
    "decorator": "decorator_5.1.1",
    "docker": "docker_5.0.3",
    "ecdsa": "ecdsa_0.17.0",
    "executing": "executing_0.8.3",
    "flask": "flask_2.1.2",
    "flask_cors": "flask_cors_3.0.10",
    "future": "future_0.18.2",
    "graphql_core": "graphql_core_3.2.1",
    "greenlet": "greenlet_1.1.2",
    "idna": "idna_3.3",
    "importlib_metadata": "importlib_metadata_4.11.3",
    "ipython": "ipython_8.3.0",
    "itsdangerous": "itsdangerous_2.1.2",
    "jedi": "jedi_0.18.1",
    "jinja2": "jinja2_3.1.2",
    "jmespath": "jmespath_1.0.0",
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
    "networkx": "networkx_2.8.1",
    "numpy": "numpy_1.22.3",
    "parso": "parso_0.8.3",
    "pbr": "pbr_5.9.0",
    "pexpect": "pexpect_4.8.0",
    "pickleshare": "pickleshare_0.7.5",
    "prompt_toolkit": "prompt_toolkit_3.0.29",
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
    "requests": "requests_2.27.1",
    "responses": "responses_0.20.0",
    "rsa": "rsa_4.8",
    "s3transfer": "s3transfer_0.5.2",
    "sarif_om": "sarif_om_1.0.4",
    "setproctitle": "setproctitle_1.2.2",
    "setuptools": "setuptools_59.2.0",
    "six": "six_1.16.0",
    "sqlalchemy": "sqlalchemy_1.4.36",
    "sqlalchemy_utils": "sqlalchemy_utils_0.38.2",
    "sshpubkeys": "sshpubkeys_3.3.1",
    "stack_data": "stack_data_0.2.0",
    "traitlets": "traitlets_5.2.1.post0",
    "tree_sitter": "tree_sitter_0.20.0",
    "urllib3": "urllib3_1.26.9",
    "wcwidth": "wcwidth_0.2.5",
    "websocket_client": "websocket_client_1.3.2",
    "werkzeug": "werkzeug_2.1.2",
    "wheel": "wheel_0.37.0",
    "wrapt": "wrapt_1.14.1",
    "xmltodict": "xmltodict_0.13.0",
    "zipp": "zipp_3.8.0",
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

    _asttokens_2_0_5_deps = [
        ":six_1.16.0",
    ]

    pycross_wheel_library(
        name = "asttokens_2.0.5",
        deps = _asttokens_2_0_5_deps,
        wheel = "@example_lock_wheel_asttokens_2.0.5_py2.py3_none_any//file",
    )

    pycross_wheel_library(
        name = "attrs_21.4.0",
        wheel = "@example_lock_wheel_attrs_21.4.0_py2.py3_none_any//file",
    )

    _aws_sam_translator_1_45_0_deps = [
        ":boto3_1.23.4",
        ":jsonschema_3.2.0",
    ]

    pycross_wheel_library(
        name = "aws_sam_translator_1.45.0",
        deps = _aws_sam_translator_1_45_0_deps,
        wheel = "@example_lock_wheel_aws_sam_translator_1.45.0_py3_none_any//file",
    )

    _aws_xray_sdk_2_9_0_deps = [
        ":botocore_1.26.4",
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

    _boto3_1_23_4_deps = [
        ":botocore_1.26.4",
        ":jmespath_1.0.0",
        ":s3transfer_0.5.2",
    ]

    pycross_wheel_library(
        name = "boto3_1.23.4",
        deps = _boto3_1_23_4_deps,
        wheel = "@example_lock_wheel_boto3_1.23.4_py3_none_any//file",
    )

    _botocore_1_26_4_deps = [
        ":jmespath_1.0.0",
        ":python_dateutil_2.8.2",
        ":urllib3_1.26.9",
    ]

    pycross_wheel_library(
        name = "botocore_1.26.4",
        deps = _botocore_1_26_4_deps,
        wheel = "@example_lock_wheel_botocore_1.26.4_py3_none_any//file",
    )

    pycross_wheel_library(
        name = "certifi_2022.5.18.1",
        wheel = "@example_lock_wheel_certifi_2022.5.18.1_py3_none_any//file",
    )

    _cffi_1_15_0_deps = [
        ":pycparser_2.21",
    ]

    pycross_wheel_library(
        name = "cffi_1.15.0",
        deps = _cffi_1_15_0_deps,
        wheel = select({
            ":_env_python_darwin_arm64": "@example_lock_wheel_cffi_1.15.0_cp39_cp39_macosx_11_0_arm64//file",
            ":_env_python_darwin_x86_64": "@example_lock_wheel_cffi_1.15.0_cp39_cp39_macosx_10_9_x86_64//file",
            ":_env_python_linux_x86_64": "@example_lock_wheel_cffi_1.15.0_cp39_cp39_manylinux_2_12_x86_64.manylinux2010_x86_64//file",
        }),
    )

    _cfn_lint_0_60_1_deps = [
        ":aws_sam_translator_1.45.0",
        ":jschema_to_python_1.2.3",
        ":jsonpatch_1.32",
        ":jsonschema_3.2.0",
        ":junit_xml_1.9",
        ":networkx_2.8.1",
        ":pyyaml_6.0",
        ":sarif_om_1.0.4",
    ]

    pycross_wheel_library(
        name = "cfn_lint_0.60.1",
        deps = _cfn_lint_0_60_1_deps,
        wheel = "@example_lock_wheel_cfn_lint_0.60.1_py3_none_any//file",
    )

    pycross_wheel_library(
        name = "charset_normalizer_2.0.12",
        wheel = "@example_lock_wheel_charset_normalizer_2.0.12_py3_none_any//file",
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

    _cryptography_37_0_2_deps = [
        ":cffi_1.15.0",
    ]

    pycross_wheel_library(
        name = "cryptography_37.0.2",
        deps = _cryptography_37_0_2_deps,
        wheel = select({
            ":_env_python_darwin_arm64": "@example_lock_wheel_cryptography_37.0.2_cp36_abi3_macosx_10_10_universal2//file",
            ":_env_python_darwin_x86_64": "@example_lock_wheel_cryptography_37.0.2_cp36_abi3_macosx_10_10_x86_64//file",
            ":_env_python_linux_x86_64": "@example_lock_wheel_cryptography_37.0.2_cp36_abi3_manylinux_2_17_x86_64.manylinux2014_x86_64//file",
        }),
    )

    pycross_wheel_library(
        name = "cython_0.29.30",
        wheel = select({
            ":_env_python_darwin_arm64": "@example_lock_wheel_cython_0.29.30_py2.py3_none_any//file",
            ":_env_python_darwin_x86_64": "@example_lock_wheel_cython_0.29.30_py2.py3_none_any//file",
            ":_env_python_linux_x86_64": "@example_lock_wheel_cython_0.29.30_cp39_cp39_manylinux_2_17_x86_64.manylinux2014_x86_64.manylinux_2_24_x86_64//file",
        }),
    )

    pycross_wheel_library(
        name = "decorator_5.1.1",
        wheel = "@example_lock_wheel_decorator_5.1.1_py3_none_any//file",
    )

    _docker_5_0_3_deps = [
        ":requests_2.27.1",
        ":websocket_client_1.3.2",
    ]

    pycross_wheel_library(
        name = "docker_5.0.3",
        deps = _docker_5_0_3_deps,
        wheel = "@example_lock_wheel_docker_5.0.3_py2.py3_none_any//file",
    )

    _ecdsa_0_17_0_deps = [
        ":six_1.16.0",
    ]

    pycross_wheel_library(
        name = "ecdsa_0.17.0",
        deps = _ecdsa_0_17_0_deps,
        wheel = "@example_lock_wheel_ecdsa_0.17.0_py2.py3_none_any//file",
    )

    pycross_wheel_library(
        name = "executing_0.8.3",
        wheel = "@example_lock_wheel_executing_0.8.3_py2.py3_none_any//file",
    )

    _flask_2_1_2_deps = [
        ":click_8.1.3",
        ":importlib_metadata_4.11.3",
        ":itsdangerous_2.1.2",
        ":jinja2_3.1.2",
        ":werkzeug_2.1.2",
    ]

    pycross_wheel_library(
        name = "flask_2.1.2",
        deps = _flask_2_1_2_deps,
        wheel = "@example_lock_wheel_flask_2.1.2_py3_none_any//file",
    )

    _flask_cors_3_0_10_deps = [
        ":flask_2.1.2",
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

    _importlib_metadata_4_11_3_deps = [
        ":zipp_3.8.0",
    ]

    pycross_wheel_library(
        name = "importlib_metadata_4.11.3",
        deps = _importlib_metadata_4_11_3_deps,
        wheel = "@example_lock_wheel_importlib_metadata_4.11.3_py3_none_any//file",
    )

    _ipython_8_3_0_deps = [
        ":backcall_0.2.0",
        ":decorator_5.1.1",
        ":jedi_0.18.1",
        ":matplotlib_inline_0.1.3",
        ":pexpect_4.8.0",
        ":pickleshare_0.7.5",
        ":prompt_toolkit_3.0.29",
        ":pygments_2.12.0",
        ":setuptools_59.2.0",
        ":stack_data_0.2.0",
        ":traitlets_5.2.1.post0",
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
        name = "ipython_8.3.0",
        deps = _ipython_8_3_0_deps,
        wheel = "@example_lock_wheel_ipython_8.3.0_py3_none_any//file",
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
        name = "jmespath_1.0.0",
        wheel = "@example_lock_wheel_jmespath_1.0.0_py3_none_any//file",
    )

    _jschema_to_python_1_2_3_deps = [
        ":attrs_21.4.0",
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
        ":attrs_21.4.0",
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
        ":traitlets_5.2.1.post0",
    ]

    pycross_wheel_library(
        name = "matplotlib_inline_0.1.3",
        deps = _matplotlib_inline_0_1_3_deps,
        wheel = "@example_lock_wheel_matplotlib_inline_0.1.3_py3_none_any//file",
    )

    _moto_3_1_1_deps = [
        ":aws_xray_sdk_2.9.0",
        ":boto3_1.23.4",
        ":botocore_1.26.4",
        ":cfn_lint_0.60.1",
        ":cryptography_37.0.2",
        ":docker_5.0.3",
        ":ecdsa_0.17.0",
        ":flask_2.1.2",
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
        ":requests_2.27.1",
        ":responses_0.20.0",
        ":setuptools_59.2.0",
        ":sshpubkeys_3.3.1",
        ":werkzeug_2.1.2",
        ":xmltodict_0.13.0",
    ]

    pycross_wheel_library(
        name = "moto_3.1.1",
        deps = _moto_3_1_1_deps,
        wheel = "@example_lock_wheel_moto_3.1.1_py2.py3_none_any//file",
    )

    pycross_wheel_library(
        name = "networkx_2.8.1",
        wheel = "@example_lock_wheel_networkx_2.8.1_py3_none_any//file",
    )

    _numpy_1_22_3_build_deps = [
        ":cython_0.29.30",
        ":setuptools_59.2.0",
        ":wheel_0.37.0",
    ]

    pycross_wheel_build(
        name = "_build_numpy_1.22.3",
        sdist = "@example_lock_sdist_numpy_1.22.3//file",
        target_environment = _target,
        deps = _numpy_1_22_3_build_deps,
        tags = ["manual"],
    )

    pycross_wheel_library(
        name = "numpy_1.22.3",
        wheel = ":_build_numpy_1.22.3",
    )

    pycross_wheel_library(
        name = "parso_0.8.3",
        wheel = "@example_lock_wheel_parso_0.8.3_py2.py3_none_any//file",
    )

    pycross_wheel_build(
        name = "_build_pbr_5.9.0",
        sdist = "@example_lock_sdist_pbr_5.9.0//file",
        target_environment = _target,
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

    _prompt_toolkit_3_0_29_deps = [
        ":wcwidth_0.2.5",
    ]

    pycross_wheel_library(
        name = "prompt_toolkit_3.0.29",
        deps = _prompt_toolkit_3_0_29_deps,
        wheel = "@example_lock_wheel_prompt_toolkit_3.0.29_py3_none_any//file",
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
        ":cryptography_37.0.2",
        ":ecdsa_0.17.0",
        ":pyasn1_0.4.8",
        ":rsa_4.8",
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

    _requests_2_27_1_deps = [
        ":certifi_2022.5.18.1",
        ":charset_normalizer_2.0.12",
        ":idna_3.3",
        ":urllib3_1.26.9",
    ]

    pycross_wheel_library(
        name = "requests_2.27.1",
        deps = _requests_2_27_1_deps,
        wheel = "@example_lock_wheel_requests_2.27.1_py2.py3_none_any//file",
    )

    _responses_0_20_0_deps = [
        ":requests_2.27.1",
        ":urllib3_1.26.9",
    ]

    pycross_wheel_library(
        name = "responses_0.20.0",
        deps = _responses_0_20_0_deps,
        wheel = "@example_lock_wheel_responses_0.20.0_py3_none_any//file",
    )

    _rsa_4_8_deps = [
        ":pyasn1_0.4.8",
    ]

    pycross_wheel_library(
        name = "rsa_4.8",
        deps = _rsa_4_8_deps,
        wheel = "@example_lock_wheel_rsa_4.8_py3_none_any//file",
    )

    _s3transfer_0_5_2_deps = [
        ":botocore_1.26.4",
    ]

    pycross_wheel_library(
        name = "s3transfer_0.5.2",
        deps = _s3transfer_0_5_2_deps,
        wheel = "@example_lock_wheel_s3transfer_0.5.2_py3_none_any//file",
    )

    _sarif_om_1_0_4_deps = [
        ":attrs_21.4.0",
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

    _sqlalchemy_1_4_36_deps = [
        ":greenlet_1.1.2",
    ]

    pycross_wheel_build(
        name = "_build_sqlalchemy_1.4.36",
        sdist = "@example_lock_sdist_sqlalchemy_1.4.36//file",
        target_environment = _target,
        deps = _sqlalchemy_1_4_36_deps,
        tags = ["manual"],
    )

    pycross_wheel_library(
        name = "sqlalchemy_1.4.36",
        deps = _sqlalchemy_1_4_36_deps,
        wheel = select({
            ":_env_python_darwin_arm64": ":_build_sqlalchemy_1.4.36",
            ":_env_python_darwin_x86_64": "@example_lock_wheel_sqlalchemy_1.4.36_cp39_cp39_macosx_10_15_x86_64//file",
            ":_env_python_linux_x86_64": "@example_lock_wheel_sqlalchemy_1.4.36_cp39_cp39_manylinux_2_5_x86_64.manylinux1_x86_64.manylinux_2_17_x86_64.manylinux2014_x86_64//file",
        }),
    )

    _sqlalchemy_utils_0_38_2_deps = [
        ":six_1.16.0",
        ":sqlalchemy_1.4.36",
    ]

    pycross_wheel_library(
        name = "sqlalchemy_utils_0.38.2",
        deps = _sqlalchemy_utils_0_38_2_deps,
        wheel = "@example_lock_wheel_sqlalchemy_utils_0.38.2_py3_none_any//file",
    )

    _sshpubkeys_3_3_1_deps = [
        ":cryptography_37.0.2",
        ":ecdsa_0.17.0",
    ]

    pycross_wheel_library(
        name = "sshpubkeys_3.3.1",
        deps = _sshpubkeys_3_3_1_deps,
        wheel = "@example_lock_wheel_sshpubkeys_3.3.1_py2.py3_none_any//file",
    )

    _stack_data_0_2_0_deps = [
        ":asttokens_2.0.5",
        ":executing_0.8.3",
        ":pure_eval_0.2.2",
    ]

    pycross_wheel_library(
        name = "stack_data_0.2.0",
        deps = _stack_data_0_2_0_deps,
        wheel = "@example_lock_wheel_stack_data_0.2.0_py3_none_any//file",
    )

    pycross_wheel_library(
        name = "traitlets_5.2.1.post0",
        wheel = "@example_lock_wheel_traitlets_5.2.1.post0_py3_none_any//file",
    )

    pycross_wheel_build(
        name = "_build_tree_sitter_0.20.0",
        sdist = "@example_lock_sdist_tree_sitter_0.20.0//file",
        target_environment = _target,
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
        name = "urllib3_1.26.9",
        wheel = "@example_lock_wheel_urllib3_1.26.9_py2.py3_none_any//file",
    )

    pycross_wheel_library(
        name = "wcwidth_0.2.5",
        wheel = "@example_lock_wheel_wcwidth_0.2.5_py2.py3_none_any//file",
    )

    pycross_wheel_library(
        name = "websocket_client_1.3.2",
        wheel = "@example_lock_wheel_websocket_client_1.3.2_py3_none_any//file",
    )

    pycross_wheel_library(
        name = "werkzeug_2.1.2",
        wheel = "@example_lock_wheel_werkzeug_2.1.2_py3_none_any//file",
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
        name = "zipp_3.8.0",
        wheel = "@example_lock_wheel_zipp_3.8.0_py3_none_any//file",
    )

def repositories():
    maybe(
        pypi_file,
        name = "example_lock_sdist_future_0.18.2",
        package_name = "future",
        package_version = "0.18.2",
        filename = "future-0.18.2.tar.gz",
        sha256 = "b1bead90b70cf6ec3f0710ae53a525360fa360d306a86583adc6bf83a4db537d",
        index = "https://pypi.org",
    )

    maybe(
        pypi_file,
        name = "example_lock_sdist_greenlet_1.1.2",
        package_name = "greenlet",
        package_version = "1.1.2",
        filename = "greenlet-1.1.2.tar.gz",
        sha256 = "e30f5ea4ae2346e62cedde8794a56858a67b878dd79f7df76a0767e356b1744a",
        index = "https://pypi.org",
    )

    maybe(
        pypi_file,
        name = "example_lock_sdist_numpy_1.22.3",
        package_name = "numpy",
        package_version = "1.22.3",
        filename = "numpy-1.22.3.zip",
        sha256 = "dbc7601a3b7472d559dc7b933b18b4b66f9aa7452c120e87dfb33d02008c8a18",
        index = "https://pypi.org",
    )

    maybe(
        pypi_file,
        name = "example_lock_sdist_pbr_5.9.0",
        package_name = "pbr",
        package_version = "5.9.0",
        filename = "pbr-5.9.0.tar.gz",
        sha256 = "e8dca2f4b43560edef58813969f52a56cef023146cbb8931626db80e6c1c4308",
        index = "https://pypi.org",
    )

    maybe(
        pypi_file,
        name = "example_lock_sdist_setproctitle_1.2.2",
        package_name = "setproctitle",
        package_version = "1.2.2",
        filename = "setproctitle-1.2.2.tar.gz",
        sha256 = "7dfb472c8852403d34007e01d6e3c68c57eb66433fb8a5c77b13b89a160d97df",
        index = "https://pypi.org",
    )

    maybe(
        pypi_file,
        name = "example_lock_sdist_sqlalchemy_1.4.36",
        package_name = "sqlalchemy",
        package_version = "1.4.36",
        filename = "SQLAlchemy-1.4.36.tar.gz",
        sha256 = "64678ac321d64a45901ef2e24725ec5e783f1f4a588305e196431447e7ace243",
        index = "https://pypi.org",
    )

    maybe(
        pypi_file,
        name = "example_lock_sdist_tree_sitter_0.20.0",
        package_name = "tree-sitter",
        package_version = "0.20.0",
        filename = "tree_sitter-0.20.0.tar.gz",
        sha256 = "1940f64be1e8c9c3c0e34a2258f1e4c324207534d5b1eefc5ab2960a9d98f668",
        index = "https://pypi.org",
    )

    maybe(
        pypi_file,
        name = "example_lock_wheel_appnope_0.1.3_py2.py3_none_any",
        package_name = "appnope",
        package_version = "0.1.3",
        filename = "appnope-0.1.3-py2.py3-none-any.whl",
        sha256 = "265a455292d0bd8a72453494fa24df5a11eb18373a60c7c0430889f22548605e",
        index = "https://pypi.org",
    )

    maybe(
        pypi_file,
        name = "example_lock_wheel_asttokens_2.0.5_py2.py3_none_any",
        package_name = "asttokens",
        package_version = "2.0.5",
        filename = "asttokens-2.0.5-py2.py3-none-any.whl",
        sha256 = "0844691e88552595a6f4a4281a9f7f79b8dd45ca4ccea82e5e05b4bbdb76705c",
        index = "https://pypi.org",
    )

    maybe(
        pypi_file,
        name = "example_lock_wheel_attrs_21.4.0_py2.py3_none_any",
        package_name = "attrs",
        package_version = "21.4.0",
        filename = "attrs-21.4.0-py2.py3-none-any.whl",
        sha256 = "2d27e3784d7a565d36ab851fe94887c5eccd6a463168875832a1be79c82828b4",
        index = "https://pypi.org",
    )

    maybe(
        pypi_file,
        name = "example_lock_wheel_aws_sam_translator_1.45.0_py3_none_any",
        package_name = "aws-sam-translator",
        package_version = "1.45.0",
        filename = "aws_sam_translator-1.45.0-py3-none-any.whl",
        sha256 = "40a6dd5a0aba32c7b38b0f5c54470396acdcd75e4b64251b015abdf922a18b5f",
        index = "https://pypi.org",
    )

    maybe(
        pypi_file,
        name = "example_lock_wheel_aws_xray_sdk_2.9.0_py2.py3_none_any",
        package_name = "aws-xray-sdk",
        package_version = "2.9.0",
        filename = "aws_xray_sdk-2.9.0-py2.py3-none-any.whl",
        sha256 = "98216b3ac8281b51b59a8703f8ec561c460807d9d0679838f5c0179d381d7e58",
        index = "https://pypi.org",
    )

    maybe(
        pypi_file,
        name = "example_lock_wheel_backcall_0.2.0_py2.py3_none_any",
        package_name = "backcall",
        package_version = "0.2.0",
        filename = "backcall-0.2.0-py2.py3-none-any.whl",
        sha256 = "fbbce6a29f263178a1f7915c1940bde0ec2b2a967566fe1c65c1dfb7422bd255",
        index = "https://pypi.org",
    )

    maybe(
        pypi_file,
        name = "example_lock_wheel_boto3_1.23.4_py3_none_any",
        package_name = "boto3",
        package_version = "1.23.4",
        filename = "boto3-1.23.4-py3-none-any.whl",
        sha256 = "cef1730f607939da45b9c3c413f8b93f7c445bd74e24be7cbcdd817ebbf58fbc",
        index = "https://pypi.org",
    )

    maybe(
        pypi_file,
        name = "example_lock_wheel_botocore_1.26.4_py3_none_any",
        package_name = "botocore",
        package_version = "1.26.4",
        filename = "botocore-1.26.4-py3-none-any.whl",
        sha256 = "bd436455310f8876dfab1a27760afffa5e34dced24b4ea6a9f6b20fec082e47e",
        index = "https://pypi.org",
    )

    maybe(
        pypi_file,
        name = "example_lock_wheel_certifi_2022.5.18.1_py3_none_any",
        package_name = "certifi",
        package_version = "2022.5.18.1",
        filename = "certifi-2022.5.18.1-py3-none-any.whl",
        sha256 = "f1d53542ee8cbedbe2118b5686372fb33c297fcd6379b050cca0ef13a597382a",
        index = "https://pypi.org",
    )

    maybe(
        pypi_file,
        name = "example_lock_wheel_cffi_1.15.0_cp39_cp39_macosx_10_9_x86_64",
        package_name = "cffi",
        package_version = "1.15.0",
        filename = "cffi-1.15.0-cp39-cp39-macosx_10_9_x86_64.whl",
        sha256 = "45e8636704eacc432a206ac7345a5d3d2c62d95a507ec70d62f23cd91770482a",
        index = "https://pypi.org",
    )

    maybe(
        pypi_file,
        name = "example_lock_wheel_cffi_1.15.0_cp39_cp39_macosx_11_0_arm64",
        package_name = "cffi",
        package_version = "1.15.0",
        filename = "cffi-1.15.0-cp39-cp39-macosx_11_0_arm64.whl",
        sha256 = "31fb708d9d7c3f49a60f04cf5b119aeefe5644daba1cd2a0fe389b674fd1de37",
        index = "https://pypi.org",
    )

    maybe(
        pypi_file,
        name = "example_lock_wheel_cffi_1.15.0_cp39_cp39_manylinux_2_12_x86_64.manylinux2010_x86_64",
        package_name = "cffi",
        package_version = "1.15.0",
        filename = "cffi-1.15.0-cp39-cp39-manylinux_2_12_x86_64.manylinux2010_x86_64.whl",
        sha256 = "74fdfdbfdc48d3f47148976f49fab3251e550a8720bebc99bf1483f5bfb5db3e",
        index = "https://pypi.org",
    )

    maybe(
        pypi_file,
        name = "example_lock_wheel_cfn_lint_0.60.1_py3_none_any",
        package_name = "cfn-lint",
        package_version = "0.60.1",
        filename = "cfn_lint-0.60.1-py3-none-any.whl",
        sha256 = "af36b2afa5d23595eb5ef105c29e6193850ec43834fa02df591bae6cfb7cb117",
        index = "https://pypi.org",
    )

    maybe(
        pypi_file,
        name = "example_lock_wheel_charset_normalizer_2.0.12_py3_none_any",
        package_name = "charset-normalizer",
        package_version = "2.0.12",
        filename = "charset_normalizer-2.0.12-py3-none-any.whl",
        sha256 = "6881edbebdb17b39b4eaaa821b438bf6eddffb4468cf344f09f89def34a8b1df",
        index = "https://pypi.org",
    )

    maybe(
        pypi_file,
        name = "example_lock_wheel_click_8.1.3_py3_none_any",
        package_name = "click",
        package_version = "8.1.3",
        filename = "click-8.1.3-py3-none-any.whl",
        sha256 = "bb4d8133cb15a609f44e8213d9b391b0809795062913b383c62be0ee95b1db48",
        index = "https://pypi.org",
    )

    maybe(
        pypi_file,
        name = "example_lock_wheel_cognitojwt_1.4.1_py3_none_any",
        package_name = "cognitojwt",
        package_version = "1.4.1",
        filename = "cognitojwt-1.4.1-py3-none-any.whl",
        sha256 = "8ee189f82289d140dc750c91e8772436b64b94d071507ace42efc22c525f42ce",
        index = "https://pypi.org",
    )

    maybe(
        pypi_file,
        name = "example_lock_wheel_cryptography_37.0.2_cp36_abi3_macosx_10_10_universal2",
        package_name = "cryptography",
        package_version = "37.0.2",
        filename = "cryptography-37.0.2-cp36-abi3-macosx_10_10_universal2.whl",
        sha256 = "ef15c2df7656763b4ff20a9bc4381d8352e6640cfeb95c2972c38ef508e75181",
        index = "https://pypi.org",
    )

    maybe(
        pypi_file,
        name = "example_lock_wheel_cryptography_37.0.2_cp36_abi3_macosx_10_10_x86_64",
        package_name = "cryptography",
        package_version = "37.0.2",
        filename = "cryptography-37.0.2-cp36-abi3-macosx_10_10_x86_64.whl",
        sha256 = "3c81599befb4d4f3d7648ed3217e00d21a9341a9a688ecdd615ff72ffbed7336",
        index = "https://pypi.org",
    )

    maybe(
        pypi_file,
        name = "example_lock_wheel_cryptography_37.0.2_cp36_abi3_manylinux_2_17_x86_64.manylinux2014_x86_64",
        package_name = "cryptography",
        package_version = "37.0.2",
        filename = "cryptography-37.0.2-cp36-abi3-manylinux_2_17_x86_64.manylinux2014_x86_64.whl",
        sha256 = "59b281eab51e1b6b6afa525af2bd93c16d49358404f814fe2c2410058623928c",
        index = "https://pypi.org",
    )

    maybe(
        pypi_file,
        name = "example_lock_wheel_cython_0.29.30_cp39_cp39_manylinux_2_17_x86_64.manylinux2014_x86_64.manylinux_2_24_x86_64",
        package_name = "cython",
        package_version = "0.29.30",
        filename = "Cython-0.29.30-cp39-cp39-manylinux_2_17_x86_64.manylinux2014_x86_64.manylinux_2_24_x86_64.whl",
        sha256 = "60d370c33d56077d30e5f425026e58c2559e93b4784106f61581cf54071f6270",
        index = "https://pypi.org",
    )

    maybe(
        pypi_file,
        name = "example_lock_wheel_cython_0.29.30_py2.py3_none_any",
        package_name = "cython",
        package_version = "0.29.30",
        filename = "Cython-0.29.30-py2.py3-none-any.whl",
        sha256 = "acb72e0b42079862cf2f894964b41f261e941e75677e902c5f4304b3eb00af33",
        index = "https://pypi.org",
    )

    maybe(
        pypi_file,
        name = "example_lock_wheel_decorator_5.1.1_py3_none_any",
        package_name = "decorator",
        package_version = "5.1.1",
        filename = "decorator-5.1.1-py3-none-any.whl",
        sha256 = "b8c3f85900b9dc423225913c5aace94729fe1fa9763b38939a95226f02d37186",
        index = "https://pypi.org",
    )

    maybe(
        pypi_file,
        name = "example_lock_wheel_docker_5.0.3_py2.py3_none_any",
        package_name = "docker",
        package_version = "5.0.3",
        filename = "docker-5.0.3-py2.py3-none-any.whl",
        sha256 = "7a79bb439e3df59d0a72621775d600bc8bc8b422d285824cb37103eab91d1ce0",
        index = "https://pypi.org",
    )

    maybe(
        pypi_file,
        name = "example_lock_wheel_ecdsa_0.17.0_py2.py3_none_any",
        package_name = "ecdsa",
        package_version = "0.17.0",
        filename = "ecdsa-0.17.0-py2.py3-none-any.whl",
        sha256 = "5cf31d5b33743abe0dfc28999036c849a69d548f994b535e527ee3cb7f3ef676",
        index = "https://pypi.org",
    )

    maybe(
        pypi_file,
        name = "example_lock_wheel_executing_0.8.3_py2.py3_none_any",
        package_name = "executing",
        package_version = "0.8.3",
        filename = "executing-0.8.3-py2.py3-none-any.whl",
        sha256 = "d1eef132db1b83649a3905ca6dd8897f71ac6f8cac79a7e58a1a09cf137546c9",
        index = "https://pypi.org",
    )

    maybe(
        pypi_file,
        name = "example_lock_wheel_flask_2.1.2_py3_none_any",
        package_name = "flask",
        package_version = "2.1.2",
        filename = "Flask-2.1.2-py3-none-any.whl",
        sha256 = "fad5b446feb0d6db6aec0c3184d16a8c1f6c3e464b511649c8918a9be100b4fe",
        index = "https://pypi.org",
    )

    maybe(
        pypi_file,
        name = "example_lock_wheel_flask_cors_3.0.10_py2.py3_none_any",
        package_name = "flask-cors",
        package_version = "3.0.10",
        filename = "Flask_Cors-3.0.10-py2.py3-none-any.whl",
        sha256 = "74efc975af1194fc7891ff5cd85b0f7478be4f7f59fe158102e91abb72bb4438",
        index = "https://pypi.org",
    )

    maybe(
        pypi_file,
        name = "example_lock_wheel_graphql_core_3.2.1_py3_none_any",
        package_name = "graphql-core",
        package_version = "3.2.1",
        filename = "graphql_core-3.2.1-py3-none-any.whl",
        sha256 = "f83c658e4968998eed1923a2e3e3eddd347e005ac0315fbb7ca4d70ea9156323",
        index = "https://pypi.org",
    )

    maybe(
        pypi_file,
        name = "example_lock_wheel_greenlet_1.1.2_cp39_cp39_macosx_10_14_x86_64",
        package_name = "greenlet",
        package_version = "1.1.2",
        filename = "greenlet-1.1.2-cp39-cp39-macosx_10_14_x86_64.whl",
        sha256 = "166eac03e48784a6a6e0e5f041cfebb1ab400b394db188c48b3a84737f505b67",
        index = "https://pypi.org",
    )

    maybe(
        pypi_file,
        name = "example_lock_wheel_greenlet_1.1.2_cp39_cp39_manylinux_2_17_x86_64.manylinux2014_x86_64",
        package_name = "greenlet",
        package_version = "1.1.2",
        filename = "greenlet-1.1.2-cp39-cp39-manylinux_2_17_x86_64.manylinux2014_x86_64.whl",
        sha256 = "7ff61ff178250f9bb3cd89752df0f1dd0e27316a8bd1465351652b1b4a4cdfd3",
        index = "https://pypi.org",
    )

    maybe(
        pypi_file,
        name = "example_lock_wheel_idna_3.3_py3_none_any",
        package_name = "idna",
        package_version = "3.3",
        filename = "idna-3.3-py3-none-any.whl",
        sha256 = "84d9dd047ffa80596e0f246e2eab0b391788b0503584e8945f2368256d2735ff",
        index = "https://pypi.org",
    )

    maybe(
        pypi_file,
        name = "example_lock_wheel_importlib_metadata_4.11.3_py3_none_any",
        package_name = "importlib-metadata",
        package_version = "4.11.3",
        filename = "importlib_metadata-4.11.3-py3-none-any.whl",
        sha256 = "1208431ca90a8cca1a6b8af391bb53c1a2db74e5d1cef6ddced95d4b2062edc6",
        index = "https://pypi.org",
    )

    maybe(
        pypi_file,
        name = "example_lock_wheel_ipython_8.3.0_py3_none_any",
        package_name = "ipython",
        package_version = "8.3.0",
        filename = "ipython-8.3.0-py3-none-any.whl",
        sha256 = "341456643a764c28f670409bbd5d2518f9b82c013441084ff2c2fc999698f83b",
        index = "https://pypi.org",
    )

    maybe(
        pypi_file,
        name = "example_lock_wheel_itsdangerous_2.1.2_py3_none_any",
        package_name = "itsdangerous",
        package_version = "2.1.2",
        filename = "itsdangerous-2.1.2-py3-none-any.whl",
        sha256 = "2c2349112351b88699d8d4b6b075022c0808887cb7ad10069318a8b0bc88db44",
        index = "https://pypi.org",
    )

    maybe(
        pypi_file,
        name = "example_lock_wheel_jedi_0.18.1_py2.py3_none_any",
        package_name = "jedi",
        package_version = "0.18.1",
        filename = "jedi-0.18.1-py2.py3-none-any.whl",
        sha256 = "637c9635fcf47945ceb91cd7f320234a7be540ded6f3e99a50cb6febdfd1ba8d",
        index = "https://pypi.org",
    )

    maybe(
        pypi_file,
        name = "example_lock_wheel_jinja2_3.1.2_py3_none_any",
        package_name = "jinja2",
        package_version = "3.1.2",
        filename = "Jinja2-3.1.2-py3-none-any.whl",
        sha256 = "6088930bfe239f0e6710546ab9c19c9ef35e29792895fed6e6e31a023a182a61",
        index = "https://pypi.org",
    )

    maybe(
        pypi_file,
        name = "example_lock_wheel_jmespath_1.0.0_py3_none_any",
        package_name = "jmespath",
        package_version = "1.0.0",
        filename = "jmespath-1.0.0-py3-none-any.whl",
        sha256 = "e8dcd576ed616f14ec02eed0005c85973b5890083313860136657e24784e4c04",
        index = "https://pypi.org",
    )

    maybe(
        pypi_file,
        name = "example_lock_wheel_jschema_to_python_1.2.3_py3_none_any",
        package_name = "jschema-to-python",
        package_version = "1.2.3",
        filename = "jschema_to_python-1.2.3-py3-none-any.whl",
        sha256 = "8a703ca7604d42d74b2815eecf99a33359a8dccbb80806cce386d5e2dd992b05",
        index = "https://pypi.org",
    )

    maybe(
        pypi_file,
        name = "example_lock_wheel_jsondiff_2.0.0_py3_none_any",
        package_name = "jsondiff",
        package_version = "2.0.0",
        filename = "jsondiff-2.0.0-py3-none-any.whl",
        sha256 = "689841d66273fc88fc79f7d33f4c074774f4f214b6466e3aff0e5adaf889d1e0",
        index = "https://pypi.org",
    )

    maybe(
        pypi_file,
        name = "example_lock_wheel_jsonpatch_1.32_py2.py3_none_any",
        package_name = "jsonpatch",
        package_version = "1.32",
        filename = "jsonpatch-1.32-py2.py3-none-any.whl",
        sha256 = "26ac385719ac9f54df8a2f0827bb8253aa3ea8ab7b3368457bcdb8c14595a397",
        index = "https://pypi.org",
    )

    maybe(
        pypi_file,
        name = "example_lock_wheel_jsonpickle_2.2.0_py2.py3_none_any",
        package_name = "jsonpickle",
        package_version = "2.2.0",
        filename = "jsonpickle-2.2.0-py2.py3-none-any.whl",
        sha256 = "de7f2613818aa4f234138ca11243d6359ff83ae528b2185efdd474f62bcf9ae1",
        index = "https://pypi.org",
    )

    maybe(
        pypi_file,
        name = "example_lock_wheel_jsonpointer_2.3_py2.py3_none_any",
        package_name = "jsonpointer",
        package_version = "2.3",
        filename = "jsonpointer-2.3-py2.py3-none-any.whl",
        sha256 = "51801e558539b4e9cd268638c078c6c5746c9ac96bc38152d443400e4f3793e9",
        index = "https://pypi.org",
    )

    maybe(
        pypi_file,
        name = "example_lock_wheel_jsonschema_3.2.0_py2.py3_none_any",
        package_name = "jsonschema",
        package_version = "3.2.0",
        filename = "jsonschema-3.2.0-py2.py3-none-any.whl",
        sha256 = "4e5b3cf8216f577bee9ce139cbe72eca3ea4f292ec60928ff24758ce626cd163",
        index = "https://pypi.org",
    )

    maybe(
        pypi_file,
        name = "example_lock_wheel_junit_xml_1.9_py2.py3_none_any",
        package_name = "junit-xml",
        package_version = "1.9",
        filename = "junit_xml-1.9-py2.py3-none-any.whl",
        sha256 = "ec5ca1a55aefdd76d28fcc0b135251d156c7106fa979686a4b48d62b761b4732",
        index = "https://pypi.org",
    )

    maybe(
        pypi_file,
        name = "example_lock_wheel_markupsafe_2.1.1_cp39_cp39_macosx_10_9_universal2",
        package_name = "markupsafe",
        package_version = "2.1.1",
        filename = "MarkupSafe-2.1.1-cp39-cp39-macosx_10_9_universal2.whl",
        sha256 = "e04e26803c9c3851c931eac40c695602c6295b8d432cbe78609649ad9bd2da8a",
        index = "https://pypi.org",
    )

    maybe(
        pypi_file,
        name = "example_lock_wheel_markupsafe_2.1.1_cp39_cp39_macosx_10_9_x86_64",
        package_name = "markupsafe",
        package_version = "2.1.1",
        filename = "MarkupSafe-2.1.1-cp39-cp39-macosx_10_9_x86_64.whl",
        sha256 = "b87db4360013327109564f0e591bd2a3b318547bcef31b468a92ee504d07ae4f",
        index = "https://pypi.org",
    )

    maybe(
        pypi_file,
        name = "example_lock_wheel_markupsafe_2.1.1_cp39_cp39_manylinux_2_17_x86_64.manylinux2014_x86_64",
        package_name = "markupsafe",
        package_version = "2.1.1",
        filename = "MarkupSafe-2.1.1-cp39-cp39-manylinux_2_17_x86_64.manylinux2014_x86_64.whl",
        sha256 = "56442863ed2b06d19c37f94d999035e15ee982988920e12a5b4ba29b62ad1f77",
        index = "https://pypi.org",
    )

    maybe(
        pypi_file,
        name = "example_lock_wheel_matplotlib_inline_0.1.3_py3_none_any",
        package_name = "matplotlib-inline",
        package_version = "0.1.3",
        filename = "matplotlib_inline-0.1.3-py3-none-any.whl",
        sha256 = "aed605ba3b72462d64d475a21a9296f400a19c4f74a31b59103d2a99ffd5aa5c",
        index = "https://pypi.org",
    )

    maybe(
        pypi_file,
        name = "example_lock_wheel_moto_3.1.1_py2.py3_none_any",
        package_name = "moto",
        package_version = "3.1.1",
        filename = "moto-3.1.1-py2.py3-none-any.whl",
        sha256 = "462495563847134ea8ef4135a229731a598a8e7b6b10a74f8d745815aa20a25b",
        index = "https://pypi.org",
    )

    maybe(
        pypi_file,
        name = "example_lock_wheel_networkx_2.8.1_py3_none_any",
        package_name = "networkx",
        package_version = "2.8.1",
        filename = "networkx-2.8.1-py3-none-any.whl",
        sha256 = "07b89bb42483d385ae31f110b3da873b98639ae00b7dbc05bf0da706e2d10459",
        index = "https://pypi.org",
    )

    maybe(
        pypi_file,
        name = "example_lock_wheel_parso_0.8.3_py2.py3_none_any",
        package_name = "parso",
        package_version = "0.8.3",
        filename = "parso-0.8.3-py2.py3-none-any.whl",
        sha256 = "c001d4636cd3aecdaf33cbb40aebb59b094be2a74c556778ef5576c175e19e75",
        index = "https://pypi.org",
    )

    maybe(
        pypi_file,
        name = "example_lock_wheel_pexpect_4.8.0_py2.py3_none_any",
        package_name = "pexpect",
        package_version = "4.8.0",
        filename = "pexpect-4.8.0-py2.py3-none-any.whl",
        sha256 = "0b48a55dcb3c05f3329815901ea4fc1537514d6ba867a152b581d69ae3710937",
        index = "https://pypi.org",
    )

    maybe(
        pypi_file,
        name = "example_lock_wheel_pickleshare_0.7.5_py2.py3_none_any",
        package_name = "pickleshare",
        package_version = "0.7.5",
        filename = "pickleshare-0.7.5-py2.py3-none-any.whl",
        sha256 = "9649af414d74d4df115d5d718f82acb59c9d418196b7b4290ed47a12ce62df56",
        index = "https://pypi.org",
    )

    maybe(
        pypi_file,
        name = "example_lock_wheel_prompt_toolkit_3.0.29_py3_none_any",
        package_name = "prompt-toolkit",
        package_version = "3.0.29",
        filename = "prompt_toolkit-3.0.29-py3-none-any.whl",
        sha256 = "62291dad495e665fca0bda814e342c69952086afb0f4094d0893d357e5c78752",
        index = "https://pypi.org",
    )

    maybe(
        pypi_file,
        name = "example_lock_wheel_ptyprocess_0.7.0_py2.py3_none_any",
        package_name = "ptyprocess",
        package_version = "0.7.0",
        filename = "ptyprocess-0.7.0-py2.py3-none-any.whl",
        sha256 = "4b41f3967fce3af57cc7e94b888626c18bf37a083e3651ca8feeb66d492fef35",
        index = "https://pypi.org",
    )

    maybe(
        pypi_file,
        name = "example_lock_wheel_pure_eval_0.2.2_py3_none_any",
        package_name = "pure-eval",
        package_version = "0.2.2",
        filename = "pure_eval-0.2.2-py3-none-any.whl",
        sha256 = "01eaab343580944bc56080ebe0a674b39ec44a945e6d09ba7db3cb8cec289350",
        index = "https://pypi.org",
    )

    maybe(
        pypi_file,
        name = "example_lock_wheel_pyasn1_0.4.8_py2.py3_none_any",
        package_name = "pyasn1",
        package_version = "0.4.8",
        filename = "pyasn1-0.4.8-py2.py3-none-any.whl",
        sha256 = "39c7e2ec30515947ff4e87fb6f456dfc6e84857d34be479c9d4a4ba4bf46aa5d",
        index = "https://pypi.org",
    )

    maybe(
        pypi_file,
        name = "example_lock_wheel_pycparser_2.21_py2.py3_none_any",
        package_name = "pycparser",
        package_version = "2.21",
        filename = "pycparser-2.21-py2.py3-none-any.whl",
        sha256 = "8ee45429555515e1f6b185e78100aea234072576aa43ab53aefcae078162fca9",
        index = "https://pypi.org",
    )

    maybe(
        pypi_file,
        name = "example_lock_wheel_pygments_2.12.0_py3_none_any",
        package_name = "pygments",
        package_version = "2.12.0",
        filename = "Pygments-2.12.0-py3-none-any.whl",
        sha256 = "dc9c10fb40944260f6ed4c688ece0cd2048414940f1cea51b8b226318411c519",
        index = "https://pypi.org",
    )

    maybe(
        pypi_file,
        name = "example_lock_wheel_pyrsistent_0.18.1_cp39_cp39_macosx_10_9_universal2",
        package_name = "pyrsistent",
        package_version = "0.18.1",
        filename = "pyrsistent-0.18.1-cp39-cp39-macosx_10_9_universal2.whl",
        sha256 = "f87cc2863ef33c709e237d4b5f4502a62a00fab450c9e020892e8e2ede5847f5",
        index = "https://pypi.org",
    )

    maybe(
        pypi_file,
        name = "example_lock_wheel_pyrsistent_0.18.1_cp39_cp39_manylinux_2_17_x86_64.manylinux2014_x86_64",
        package_name = "pyrsistent",
        package_version = "0.18.1",
        filename = "pyrsistent-0.18.1-cp39-cp39-manylinux_2_17_x86_64.manylinux2014_x86_64.whl",
        sha256 = "6bc66318fb7ee012071b2792024564973ecc80e9522842eb4e17743604b5e045",
        index = "https://pypi.org",
    )

    maybe(
        pypi_file,
        name = "example_lock_wheel_python_dateutil_2.8.2_py2.py3_none_any",
        package_name = "python-dateutil",
        package_version = "2.8.2",
        filename = "python_dateutil-2.8.2-py2.py3-none-any.whl",
        sha256 = "961d03dc3453ebbc59dbdea9e4e11c5651520a876d0f4db161e8674aae935da9",
        index = "https://pypi.org",
    )

    maybe(
        pypi_file,
        name = "example_lock_wheel_python_jose_3.1.0_py2.py3_none_any",
        package_name = "python-jose",
        package_version = "3.1.0",
        filename = "python_jose-3.1.0-py2.py3-none-any.whl",
        sha256 = "1ac4caf4bfebd5a70cf5bd82702ed850db69b0b6e1d0ae7368e5f99ac01c9571",
        index = "https://pypi.org",
    )

    maybe(
        pypi_file,
        name = "example_lock_wheel_pytz_2022.1_py2.py3_none_any",
        package_name = "pytz",
        package_version = "2022.1",
        filename = "pytz-2022.1-py2.py3-none-any.whl",
        sha256 = "e68985985296d9a66a881eb3193b0906246245294a881e7c8afe623866ac6a5c",
        index = "https://pypi.org",
    )

    maybe(
        pypi_file,
        name = "example_lock_wheel_pyyaml_6.0_cp39_cp39_macosx_10_9_x86_64",
        package_name = "pyyaml",
        package_version = "6.0",
        filename = "PyYAML-6.0-cp39-cp39-macosx_10_9_x86_64.whl",
        sha256 = "055d937d65826939cb044fc8c9b08889e8c743fdc6a32b33e2390f66013e449b",
        index = "https://pypi.org",
    )

    maybe(
        pypi_file,
        name = "example_lock_wheel_pyyaml_6.0_cp39_cp39_macosx_11_0_arm64",
        package_name = "pyyaml",
        package_version = "6.0",
        filename = "PyYAML-6.0-cp39-cp39-macosx_11_0_arm64.whl",
        sha256 = "e61ceaab6f49fb8bdfaa0f92c4b57bcfbea54c09277b1b4f7ac376bfb7a7c174",
        index = "https://pypi.org",
    )

    maybe(
        pypi_file,
        name = "example_lock_wheel_pyyaml_6.0_cp39_cp39_manylinux_2_5_x86_64.manylinux1_x86_64.manylinux_2_12_x86_64.manylinux2010_x86_64",
        package_name = "pyyaml",
        package_version = "6.0",
        filename = "PyYAML-6.0-cp39-cp39-manylinux_2_5_x86_64.manylinux1_x86_64.manylinux_2_12_x86_64.manylinux2010_x86_64.whl",
        sha256 = "40527857252b61eacd1d9af500c3337ba8deb8fc298940291486c465c8b46ec0",
        index = "https://pypi.org",
    )

    maybe(
        pypi_file,
        name = "example_lock_wheel_requests_2.27.1_py2.py3_none_any",
        package_name = "requests",
        package_version = "2.27.1",
        filename = "requests-2.27.1-py2.py3-none-any.whl",
        sha256 = "f22fa1e554c9ddfd16e6e41ac79759e17be9e492b3587efa038054674760e72d",
        index = "https://pypi.org",
    )

    maybe(
        pypi_file,
        name = "example_lock_wheel_responses_0.20.0_py3_none_any",
        package_name = "responses",
        package_version = "0.20.0",
        filename = "responses-0.20.0-py3-none-any.whl",
        sha256 = "18831bc2d72443b67664d98038374a6fa1f27eaaff4dd9a7d7613723416fea3c",
        index = "https://pypi.org",
    )

    maybe(
        pypi_file,
        name = "example_lock_wheel_rsa_4.8_py3_none_any",
        package_name = "rsa",
        package_version = "4.8",
        filename = "rsa-4.8-py3-none-any.whl",
        sha256 = "95c5d300c4e879ee69708c428ba566c59478fd653cc3a22243eeb8ed846950bb",
        index = "https://pypi.org",
    )

    maybe(
        pypi_file,
        name = "example_lock_wheel_s3transfer_0.5.2_py3_none_any",
        package_name = "s3transfer",
        package_version = "0.5.2",
        filename = "s3transfer-0.5.2-py3-none-any.whl",
        sha256 = "7a6f4c4d1fdb9a2b640244008e142cbc2cd3ae34b386584ef044dd0f27101971",
        index = "https://pypi.org",
    )

    maybe(
        pypi_file,
        name = "example_lock_wheel_sarif_om_1.0.4_py3_none_any",
        package_name = "sarif-om",
        package_version = "1.0.4",
        filename = "sarif_om-1.0.4-py3-none-any.whl",
        sha256 = "539ef47a662329b1c8502388ad92457425e95dc0aaaf995fe46f4984c4771911",
        index = "https://pypi.org",
    )

    maybe(
        pypi_file,
        name = "example_lock_wheel_setuptools_59.2.0_py3_none_any",
        package_name = "setuptools",
        package_version = "59.2.0",
        filename = "setuptools-59.2.0-py3-none-any.whl",
        sha256 = "4adde3d1e1c89bde1c643c64d89cdd94cbfd8c75252ee459d4500bccb9c7d05d",
        index = "https://pypi.org",
    )

    maybe(
        pypi_file,
        name = "example_lock_wheel_six_1.16.0_py2.py3_none_any",
        package_name = "six",
        package_version = "1.16.0",
        filename = "six-1.16.0-py2.py3-none-any.whl",
        sha256 = "8abb2f1d86890a2dfb989f9a77cfcfd3e47c2a354b01111771326f8aa26e0254",
        index = "https://pypi.org",
    )

    maybe(
        pypi_file,
        name = "example_lock_wheel_sqlalchemy_1.4.36_cp39_cp39_macosx_10_15_x86_64",
        package_name = "sqlalchemy",
        package_version = "1.4.36",
        filename = "SQLAlchemy-1.4.36-cp39-cp39-macosx_10_15_x86_64.whl",
        sha256 = "f522214f6749bc073262529c056f7dfd660f3b5ec4180c5354d985eb7219801e",
        index = "https://pypi.org",
    )

    maybe(
        pypi_file,
        name = "example_lock_wheel_sqlalchemy_1.4.36_cp39_cp39_manylinux_2_5_x86_64.manylinux1_x86_64.manylinux_2_17_x86_64.manylinux2014_x86_64",
        package_name = "sqlalchemy",
        package_version = "1.4.36",
        filename = "SQLAlchemy-1.4.36-cp39-cp39-manylinux_2_5_x86_64.manylinux1_x86_64.manylinux_2_17_x86_64.manylinux2014_x86_64.whl",
        sha256 = "2ec89bf98cc6a0f5d1e28e3ad28e9be6f3b4bdbd521a4053c7ae8d5e1289a8a1",
        index = "https://pypi.org",
    )

    maybe(
        pypi_file,
        name = "example_lock_wheel_sqlalchemy_utils_0.38.2_py3_none_any",
        package_name = "sqlalchemy-utils",
        package_version = "0.38.2",
        filename = "SQLAlchemy_Utils-0.38.2-py3-none-any.whl",
        sha256 = "622235b1598f97300e4d08820ab024f5219c9a6309937a8b908093f487b4ba54",
        index = "https://pypi.org",
    )

    maybe(
        pypi_file,
        name = "example_lock_wheel_sshpubkeys_3.3.1_py2.py3_none_any",
        package_name = "sshpubkeys",
        package_version = "3.3.1",
        filename = "sshpubkeys-3.3.1-py2.py3-none-any.whl",
        sha256 = "946f76b8fe86704b0e7c56a00d80294e39bc2305999844f079a217885060b1ac",
        index = "https://pypi.org",
    )

    maybe(
        pypi_file,
        name = "example_lock_wheel_stack_data_0.2.0_py3_none_any",
        package_name = "stack-data",
        package_version = "0.2.0",
        filename = "stack_data-0.2.0-py3-none-any.whl",
        sha256 = "999762f9c3132308789affa03e9271bbbe947bf78311851f4d485d8402ed858e",
        index = "https://pypi.org",
    )

    maybe(
        pypi_file,
        name = "example_lock_wheel_traitlets_5.2.1.post0_py3_none_any",
        package_name = "traitlets",
        package_version = "5.2.1.post0",
        filename = "traitlets-5.2.1.post0-py3-none-any.whl",
        sha256 = "f44b708d33d98b0addb40c29d148a761f44af740603a8fd0e2f8b5b27cf0f087",
        index = "https://pypi.org",
    )

    maybe(
        pypi_file,
        name = "example_lock_wheel_tree_sitter_0.20.0_cp39_cp39_macosx_12_0_arm64",
        package_name = "tree-sitter",
        package_version = "0.20.0",
        filename = "tree_sitter-0.20.0-cp39-cp39-macosx_12_0_arm64.whl",
        sha256 = "51a609a7c1bd9d9e75d92ee128c12c7852ae70a482900fbbccf3d13a79e0378c",
        index = "https://pypi.org",
    )

    maybe(
        pypi_file,
        name = "example_lock_wheel_urllib3_1.26.9_py2.py3_none_any",
        package_name = "urllib3",
        package_version = "1.26.9",
        filename = "urllib3-1.26.9-py2.py3-none-any.whl",
        sha256 = "44ece4d53fb1706f667c9bd1c648f5469a2ec925fcf3a776667042d645472c14",
        index = "https://pypi.org",
    )

    maybe(
        pypi_file,
        name = "example_lock_wheel_wcwidth_0.2.5_py2.py3_none_any",
        package_name = "wcwidth",
        package_version = "0.2.5",
        filename = "wcwidth-0.2.5-py2.py3-none-any.whl",
        sha256 = "beb4802a9cebb9144e99086eff703a642a13d6a0052920003a230f3294bbe784",
        index = "https://pypi.org",
    )

    maybe(
        pypi_file,
        name = "example_lock_wheel_websocket_client_1.3.2_py3_none_any",
        package_name = "websocket-client",
        package_version = "1.3.2",
        filename = "websocket_client-1.3.2-py3-none-any.whl",
        sha256 = "722b171be00f2b90e1d4fb2f2b53146a536ca38db1da8ff49c972a4e1365d0ef",
        index = "https://pypi.org",
    )

    maybe(
        pypi_file,
        name = "example_lock_wheel_werkzeug_2.1.2_py3_none_any",
        package_name = "werkzeug",
        package_version = "2.1.2",
        filename = "Werkzeug-2.1.2-py3-none-any.whl",
        sha256 = "72a4b735692dd3135217911cbeaa1be5fa3f62bffb8745c5215420a03dc55255",
        index = "https://pypi.org",
    )

    maybe(
        pypi_file,
        name = "example_lock_wheel_wheel_0.37.0_py2.py3_none_any",
        package_name = "wheel",
        package_version = "0.37.0",
        filename = "wheel-0.37.0-py2.py3-none-any.whl",
        sha256 = "21014b2bd93c6d0034b6ba5d35e4eb284340e09d63c59aef6fc14b0f346146fd",
        index = "https://pypi.org",
    )

    maybe(
        pypi_file,
        name = "example_lock_wheel_wrapt_1.14.1_cp39_cp39_macosx_10_9_x86_64",
        package_name = "wrapt",
        package_version = "1.14.1",
        filename = "wrapt-1.14.1-cp39-cp39-macosx_10_9_x86_64.whl",
        sha256 = "3232822c7d98d23895ccc443bbdf57c7412c5a65996c30442ebe6ed3df335383",
        index = "https://pypi.org",
    )

    maybe(
        pypi_file,
        name = "example_lock_wheel_wrapt_1.14.1_cp39_cp39_macosx_11_0_arm64",
        package_name = "wrapt",
        package_version = "1.14.1",
        filename = "wrapt-1.14.1-cp39-cp39-macosx_11_0_arm64.whl",
        sha256 = "988635d122aaf2bdcef9e795435662bcd65b02f4f4c1ae37fbee7401c440b3a7",
        index = "https://pypi.org",
    )

    maybe(
        pypi_file,
        name = "example_lock_wheel_wrapt_1.14.1_cp39_cp39_manylinux_2_5_x86_64.manylinux1_x86_64.manylinux_2_17_x86_64.manylinux2014_x86_64",
        package_name = "wrapt",
        package_version = "1.14.1",
        filename = "wrapt-1.14.1-cp39-cp39-manylinux_2_5_x86_64.manylinux1_x86_64.manylinux_2_17_x86_64.manylinux2014_x86_64.whl",
        sha256 = "40e7bc81c9e2b2734ea4bc1aceb8a8f0ceaac7c5299bc5d69e37c44d9081d43b",
        index = "https://pypi.org",
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
        pypi_file,
        name = "example_lock_wheel_zipp_3.8.0_py3_none_any",
        package_name = "zipp",
        package_version = "3.8.0",
        filename = "zipp-3.8.0-py3-none-any.whl",
        sha256 = "c4f6e5bbf48e74f7a38e7cc5b0480ff42b0ae5178957d564d18932525d5cf099",
        index = "https://pypi.org",
    )

