load("@bazel_tools//tools/build_defs/repo:http.bzl", "http_file")
load("@bazel_tools//tools/build_defs/repo:utils.bzl", "maybe")
load("@jvolkman_rules_pycross//pycross:defs.bzl", "pycross_wheel_build", "pycross_wheel_library", "pypi_file")

PINS = {
    "appnope": "appnope_0.1.3",
    "attrs": "attrs_22.1.0",
    "aws_sam_translator": "aws_sam_translator_1.55.0",
    "aws_xray_sdk": "aws_xray_sdk_2.11.0",
    "backcall": "backcall_0.2.0",
    "boto3": "boto3_1.26.30",
    "botocore": "botocore_1.29.30",
    "certifi": "certifi_2022.12.7",
    "cffi": "cffi_1.15.1",
    "cfn_lint": "cfn_lint_0.72.3",
    "charset_normalizer": "charset_normalizer_2.1.1",
    "click": "click_8.1.3",
    "cognitojwt": "cognitojwt_1.4.1",
    "cryptography": "cryptography_38.0.4",
    "decorator": "decorator_5.1.1",
    "docker": "docker_6.0.1",
    "ecdsa": "ecdsa_0.18.0",
    "flask": "flask_2.2.2",
    "flask_cors": "flask_cors_3.0.10",
    "future": "future_0.18.2",
    "graphql_core": "graphql_core_3.2.3",
    "greenlet": "greenlet_2.0.1",
    "idna": "idna_3.4",
    "importlib_metadata": "importlib_metadata_5.1.0",
    "ipython": "ipython_7.34.0",
    "itsdangerous": "itsdangerous_2.1.2",
    "jaraco_classes": "jaraco_classes_3.2.3",
    "jedi": "jedi_0.18.2",
    "jeepney": "jeepney_0.8.0",
    "jinja2": "jinja2_3.1.2",
    "jmespath": "jmespath_1.0.1",
    "jschema_to_python": "jschema_to_python_1.2.3",
    "jsondiff": "jsondiff_2.0.0",
    "jsonpatch": "jsonpatch_1.32",
    "jsonpickle": "jsonpickle_3.0.0",
    "jsonpointer": "jsonpointer_2.3",
    "jsonschema": "jsonschema_3.2.0",
    "junit_xml": "junit_xml_1.9",
    "keyring": "keyring_23.9.1",
    "markupsafe": "markupsafe_2.1.1",
    "matplotlib_inline": "matplotlib_inline_0.1.6",
    "more_itertools": "more_itertools_9.0.0",
    "moto": "moto_3.1.1",
    "networkx": "networkx_2.6.3",
    "numpy": "numpy_1.21.1",
    "opencv_python": "opencv_python_4.6.0.66",
    "packaging": "packaging_22.0",
    "parso": "parso_0.8.3",
    "pbr": "pbr_5.11.0",
    "pexpect": "pexpect_4.8.0",
    "pickleshare": "pickleshare_0.7.5",
    "prompt_toolkit": "prompt_toolkit_3.0.36",
    "ptyprocess": "ptyprocess_0.7.0",
    "pyasn1": "pyasn1_0.4.8",
    "pycparser": "pycparser_2.21",
    "pygments": "pygments_2.13.0",
    "pyrsistent": "pyrsistent_0.19.2",
    "python_dateutil": "python_dateutil_2.8.2",
    "python_jose": "python_jose_3.3.0",
    "pytz": "pytz_2022.6",
    "pyyaml": "pyyaml_6.0",
    "requests": "requests_2.28.1",
    "responses": "responses_0.22.0",
    "rsa": "rsa_4.9",
    "s3transfer": "s3transfer_0.6.0",
    "sarif_om": "sarif_om_1.0.4",
    "secretstorage": "secretstorage_3.3.3",
    "setproctitle": "setproctitle_1.2.2",
    "setuptools": "setuptools_58.5.3",
    "six": "six_1.16.0",
    "sqlalchemy": "sqlalchemy_1.4.45",
    "sqlalchemy_utils": "sqlalchemy_utils_0.38.2",
    "sshpubkeys": "sshpubkeys_3.3.1",
    "toml": "toml_0.10.2",
    "traitlets": "traitlets_5.7.1",
    "tree_sitter": "tree_sitter_0.20.0",
    "types_toml": "types_toml_0.10.8.1",
    "typing_extensions": "typing_extensions_4.4.0",
    "urllib3": "urllib3_1.26.13",
    "wcwidth": "wcwidth_0.2.5",
    "websocket_client": "websocket_client_1.4.2",
    "werkzeug": "werkzeug_2.2.2",
    "wheel": "wheel_0.37.1",
    "wrapt": "wrapt_1.14.1",
    "xmltodict": "xmltodict_0.13.0",
    "zipp": "zipp_3.11.0",
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

    pycross_wheel_library(
        name = "attrs_22.1.0",
        wheel = "@example_lock_wheel_attrs_22.1.0_py2.py3_none_any//file",
    )

    _aws_sam_translator_1_55_0_deps = [
        ":boto3_1.26.30",
        ":jsonschema_3.2.0",
    ]

    pycross_wheel_library(
        name = "aws_sam_translator_1.55.0",
        deps = _aws_sam_translator_1_55_0_deps,
        wheel = "@example_lock_wheel_aws_sam_translator_1.55.0_py3_none_any//file",
    )

    _aws_xray_sdk_2_11_0_deps = [
        ":botocore_1.29.30",
        ":wrapt_1.14.1",
    ]

    pycross_wheel_library(
        name = "aws_xray_sdk_2.11.0",
        deps = _aws_xray_sdk_2_11_0_deps,
        wheel = "@example_lock_wheel_aws_xray_sdk_2.11.0_py2.py3_none_any//file",
    )

    pycross_wheel_library(
        name = "backcall_0.2.0",
        wheel = "@example_lock_wheel_backcall_0.2.0_py2.py3_none_any//file",
    )

    _boto3_1_26_30_deps = [
        ":botocore_1.29.30",
        ":jmespath_1.0.1",
        ":s3transfer_0.6.0",
    ]

    pycross_wheel_library(
        name = "boto3_1.26.30",
        deps = _boto3_1_26_30_deps,
        wheel = "@example_lock_wheel_boto3_1.26.30_py3_none_any//file",
    )

    _botocore_1_29_30_deps = [
        ":jmespath_1.0.1",
        ":python_dateutil_2.8.2",
        ":urllib3_1.26.13",
    ]

    pycross_wheel_library(
        name = "botocore_1.29.30",
        deps = _botocore_1_29_30_deps,
        wheel = "@example_lock_wheel_botocore_1.29.30_py3_none_any//file",
    )

    pycross_wheel_library(
        name = "certifi_2022.12.7",
        wheel = "@example_lock_wheel_certifi_2022.12.7_py3_none_any//file",
    )

    _cffi_1_15_1_deps = [
        ":pycparser_2.21",
    ]

    pycross_wheel_build(
        name = "_build_cffi_1.15.1",
        sdist = "@example_lock_sdist_cffi_1.15.1//file",
        target_environment = _target,
        deps = _cffi_1_15_1_deps,
        tags = ["manual"],
    )

    pycross_wheel_library(
        name = "cffi_1.15.1",
        deps = _cffi_1_15_1_deps,
        wheel = ":_build_cffi_1.15.1",
    )

    _cfn_lint_0_72_3_deps = [
        ":aws_sam_translator_1.55.0",
        ":jschema_to_python_1.2.3",
        ":jsonpatch_1.32",
        ":jsonschema_3.2.0",
        ":junit_xml_1.9",
        ":networkx_2.6.3",
        ":pyyaml_6.0",
        ":sarif_om_1.0.4",
    ]

    pycross_wheel_library(
        name = "cfn_lint_0.72.3",
        deps = _cfn_lint_0_72_3_deps,
        wheel = "@example_lock_wheel_cfn_lint_0.72.3_py3_none_any//file",
    )

    pycross_wheel_library(
        name = "charset_normalizer_2.1.1",
        wheel = "@example_lock_wheel_charset_normalizer_2.1.1_py3_none_any//file",
    )

    _click_8_1_3_deps = [
        ":importlib_metadata_5.1.0",
    ]

    pycross_wheel_library(
        name = "click_8.1.3",
        deps = _click_8_1_3_deps,
        wheel = "@example_lock_wheel_click_8.1.3_py3_none_any//file",
    )

    _cognitojwt_1_4_1_deps = [
        ":python_jose_3.3.0",
    ]

    pycross_wheel_library(
        name = "cognitojwt_1.4.1",
        deps = _cognitojwt_1_4_1_deps,
        wheel = "@example_lock_wheel_cognitojwt_1.4.1_py3_none_any//file",
    )

    _cryptography_38_0_4_deps = [
        ":cffi_1.15.1",
    ]

    pycross_wheel_library(
        name = "cryptography_38.0.4",
        deps = _cryptography_38_0_4_deps,
        wheel = select({
            ":_env_python_darwin_arm64": "@example_lock_wheel_cryptography_38.0.4_cp36_abi3_macosx_10_10_universal2//file",
            ":_env_python_darwin_x86_64": "@example_lock_wheel_cryptography_38.0.4_cp36_abi3_macosx_10_10_x86_64//file",
            ":_env_python_linux_x86_64": "@example_lock_wheel_cryptography_38.0.4_cp36_abi3_manylinux_2_17_x86_64.manylinux2014_x86_64//file",
        }),
    )

    pycross_wheel_library(
        name = "decorator_5.1.1",
        wheel = "@example_lock_wheel_decorator_5.1.1_py3_none_any//file",
    )

    _docker_6_0_1_deps = [
        ":packaging_22.0",
        ":requests_2.28.1",
        ":urllib3_1.26.13",
        ":websocket_client_1.4.2",
    ]

    pycross_wheel_library(
        name = "docker_6.0.1",
        deps = _docker_6_0_1_deps,
        wheel = "@example_lock_wheel_docker_6.0.1_py3_none_any//file",
    )

    _ecdsa_0_18_0_deps = [
        ":six_1.16.0",
    ]

    pycross_wheel_library(
        name = "ecdsa_0.18.0",
        deps = _ecdsa_0_18_0_deps,
        wheel = "@example_lock_wheel_ecdsa_0.18.0_py2.py3_none_any//file",
    )

    _flask_2_2_2_deps = [
        ":click_8.1.3",
        ":importlib_metadata_5.1.0",
        ":itsdangerous_2.1.2",
        ":jinja2_3.1.2",
        ":werkzeug_2.2.2",
    ]

    pycross_wheel_library(
        name = "flask_2.2.2",
        deps = _flask_2_2_2_deps,
        wheel = "@example_lock_wheel_flask_2.2.2_py3_none_any//file",
    )

    _flask_cors_3_0_10_deps = [
        ":flask_2.2.2",
        ":six_1.16.0",
    ]

    pycross_wheel_library(
        name = "flask_cors_3.0.10",
        deps = _flask_cors_3_0_10_deps,
        wheel = "@example_lock_wheel_flask_cors_3.0.10_py2.py3_none_any//file",
    )

    pycross_wheel_build(
        name = "_build_future_0.18.2",
        sdist = "@example_lock_sdist_future_0.18.2//file",
        target_environment = _target,
        tags = ["manual"],
    )

    pycross_wheel_library(
        name = "future_0.18.2",
        wheel = ":_build_future_0.18.2",
    )

    _graphql_core_3_2_3_deps = [
        ":typing_extensions_4.4.0",
    ]

    pycross_wheel_library(
        name = "graphql_core_3.2.3",
        deps = _graphql_core_3_2_3_deps,
        wheel = "@example_lock_wheel_graphql_core_3.2.3_py3_none_any//file",
    )

    _greenlet_2_0_1_build_deps = [
        ":setuptools_58.5.3",
        ":wheel_0.37.1",
    ]

    pycross_wheel_build(
        name = "_build_greenlet_2.0.1",
        sdist = "@example_lock_sdist_greenlet_2.0.1//file",
        target_environment = _target,
        deps = _greenlet_2_0_1_build_deps,
        tags = ["manual"],
    )

    pycross_wheel_library(
        name = "greenlet_2.0.1",
        wheel = ":_build_greenlet_2.0.1",
    )

    pycross_wheel_library(
        name = "idna_3.4",
        wheel = "@example_lock_wheel_idna_3.4_py3_none_any//file",
    )

    _importlib_metadata_5_1_0_deps = [
        ":typing_extensions_4.4.0",
        ":zipp_3.11.0",
    ]

    pycross_wheel_library(
        name = "importlib_metadata_5.1.0",
        deps = _importlib_metadata_5_1_0_deps,
        wheel = "@example_lock_wheel_importlib_metadata_5.1.0_py3_none_any//file",
    )

    _ipython_7_34_0_deps = [
        ":backcall_0.2.0",
        ":decorator_5.1.1",
        ":jedi_0.18.2",
        ":matplotlib_inline_0.1.6",
        ":pexpect_4.8.0",
        ":pickleshare_0.7.5",
        ":prompt_toolkit_3.0.36",
        ":pygments_2.13.0",
        ":setuptools_58.5.3",
        ":traitlets_5.7.1",
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
        name = "ipython_7.34.0",
        deps = _ipython_7_34_0_deps,
        wheel = "@example_lock_wheel_ipython_7.34.0_py3_none_any//file",
    )

    pycross_wheel_library(
        name = "itsdangerous_2.1.2",
        wheel = "@example_lock_wheel_itsdangerous_2.1.2_py3_none_any//file",
    )

    _jaraco_classes_3_2_3_deps = [
        ":more_itertools_9.0.0",
    ]

    pycross_wheel_library(
        name = "jaraco_classes_3.2.3",
        deps = _jaraco_classes_3_2_3_deps,
        wheel = "@example_lock_wheel_jaraco.classes_3.2.3_py3_none_any//file",
    )

    _jedi_0_18_2_deps = [
        ":parso_0.8.3",
    ]

    pycross_wheel_library(
        name = "jedi_0.18.2",
        deps = _jedi_0_18_2_deps,
        wheel = "@example_lock_wheel_jedi_0.18.2_py2.py3_none_any//file",
    )

    pycross_wheel_library(
        name = "jeepney_0.8.0",
        wheel = "@example_lock_wheel_jeepney_0.8.0_py3_none_any//file",
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
        ":jsonpickle_3.0.0",
        ":pbr_5.11.0",
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

    _jsonpickle_3_0_0_deps = [
        ":importlib_metadata_5.1.0",
    ]

    pycross_wheel_library(
        name = "jsonpickle_3.0.0",
        deps = _jsonpickle_3_0_0_deps,
        wheel = "@example_lock_wheel_jsonpickle_3.0.0_py2.py3_none_any//file",
    )

    pycross_wheel_library(
        name = "jsonpointer_2.3",
        wheel = "@example_lock_wheel_jsonpointer_2.3_py2.py3_none_any//file",
    )

    _jsonschema_3_2_0_deps = [
        ":attrs_22.1.0",
        ":importlib_metadata_5.1.0",
        ":pyrsistent_0.19.2",
        ":setuptools_58.5.3",
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

    _keyring_23_9_1_deps = [
        ":importlib_metadata_5.1.0",
        ":jaraco_classes_3.2.3",
    ] + select({
        ":_env_python_linux_x86_64": [
            ":jeepney_0.8.0",
            ":secretstorage_3.3.3",
        ],
        "//conditions:default": [],
    })

    pycross_wheel_library(
        name = "keyring_23.9.1",
        deps = _keyring_23_9_1_deps,
        wheel = "@example_lock_wheel_keyring_23.9.1_py3_none_any//file",
    )

    pycross_wheel_build(
        name = "_build_markupsafe_2.1.1",
        sdist = "@example_lock_sdist_markupsafe_2.1.1//file",
        target_environment = _target,
        tags = ["manual"],
    )

    pycross_wheel_library(
        name = "markupsafe_2.1.1",
        wheel = ":_build_markupsafe_2.1.1",
    )

    _matplotlib_inline_0_1_6_deps = [
        ":traitlets_5.7.1",
    ]

    pycross_wheel_library(
        name = "matplotlib_inline_0.1.6",
        deps = _matplotlib_inline_0_1_6_deps,
        wheel = "@example_lock_wheel_matplotlib_inline_0.1.6_py3_none_any//file",
    )

    pycross_wheel_library(
        name = "more_itertools_9.0.0",
        wheel = "@example_lock_wheel_more_itertools_9.0.0_py3_none_any//file",
    )

    _moto_3_1_1_deps = [
        ":aws_xray_sdk_2.11.0",
        ":boto3_1.26.30",
        ":botocore_1.29.30",
        ":cfn_lint_0.72.3",
        ":cryptography_38.0.4",
        ":docker_6.0.1",
        ":ecdsa_0.18.0",
        ":flask_2.2.2",
        ":flask_cors_3.0.10",
        ":graphql_core_3.2.3",
        ":idna_3.4",
        ":importlib_metadata_5.1.0",
        ":jinja2_3.1.2",
        ":jsondiff_2.0.0",
        ":markupsafe_2.1.1",
        ":python_dateutil_2.8.2",
        ":python_jose_3.3.0",
        ":pytz_2022.6",
        ":pyyaml_6.0",
        ":requests_2.28.1",
        ":responses_0.22.0",
        ":setuptools_58.5.3",
        ":sshpubkeys_3.3.1",
        ":werkzeug_2.2.2",
        ":xmltodict_0.13.0",
    ]

    pycross_wheel_library(
        name = "moto_3.1.1",
        deps = _moto_3_1_1_deps,
        wheel = "@example_lock_wheel_moto_3.1.1_py2.py3_none_any//file",
    )

    pycross_wheel_library(
        name = "networkx_2.6.3",
        wheel = "@example_lock_wheel_networkx_2.6.3_py3_none_any//file",
    )

    pycross_wheel_build(
        name = "_build_numpy_1.21.1",
        sdist = "@example_lock_sdist_numpy_1.21.1//file",
        target_environment = _target,
        tags = ["manual"],
    )

    pycross_wheel_library(
        name = "numpy_1.21.1",
        wheel = ":_build_numpy_1.21.1",
    )

    _opencv_python_4_6_0_66_deps = [
        ":numpy_1.21.1",
    ]

    pycross_wheel_library(
        name = "opencv_python_4.6.0.66",
        deps = _opencv_python_4_6_0_66_deps,
        wheel = select({
            ":_env_python_darwin_arm64": "@example_lock_wheel_opencv_python_4.6.0.66_cp37_abi3_macosx_11_0_arm64//file",
            ":_env_python_darwin_x86_64": "@example_lock_wheel_opencv_python_4.6.0.66_cp36_abi3_macosx_10_15_x86_64//file",
            ":_env_python_linux_x86_64": "@example_lock_wheel_opencv_python_4.6.0.66_cp36_abi3_manylinux_2_17_x86_64.manylinux2014_x86_64//file",
        }),
    )

    pycross_wheel_library(
        name = "packaging_22.0",
        wheel = "@example_lock_wheel_packaging_22.0_py3_none_any//file",
    )

    pycross_wheel_library(
        name = "parso_0.8.3",
        wheel = "@example_lock_wheel_parso_0.8.3_py2.py3_none_any//file",
    )

    _pbr_5_11_0_build_deps = [
        ":setuptools_58.5.3",
        ":wheel_0.37.1",
    ]

    pycross_wheel_build(
        name = "_build_pbr_5.11.0",
        sdist = "@example_lock_sdist_pbr_5.11.0//file",
        target_environment = _target,
        deps = _pbr_5_11_0_build_deps,
        tags = ["manual"],
    )

    pycross_wheel_library(
        name = "pbr_5.11.0",
        wheel = ":_build_pbr_5.11.0",
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

    _prompt_toolkit_3_0_36_deps = [
        ":wcwidth_0.2.5",
    ]

    pycross_wheel_library(
        name = "prompt_toolkit_3.0.36",
        deps = _prompt_toolkit_3_0_36_deps,
        wheel = "@example_lock_wheel_prompt_toolkit_3.0.36_py3_none_any//file",
    )

    pycross_wheel_library(
        name = "ptyprocess_0.7.0",
        wheel = "@example_lock_wheel_ptyprocess_0.7.0_py2.py3_none_any//file",
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
        name = "pygments_2.13.0",
        wheel = "@example_lock_wheel_pygments_2.13.0_py3_none_any//file",
    )

    pycross_wheel_library(
        name = "pyrsistent_0.19.2",
        wheel = "@example_lock_wheel_pyrsistent_0.19.2_py3_none_any//file",
    )

    _python_dateutil_2_8_2_deps = [
        ":six_1.16.0",
    ]

    pycross_wheel_library(
        name = "python_dateutil_2.8.2",
        deps = _python_dateutil_2_8_2_deps,
        wheel = "@example_lock_wheel_python_dateutil_2.8.2_py2.py3_none_any//file",
    )

    _python_jose_3_3_0_deps = [
        ":cryptography_38.0.4",
        ":ecdsa_0.18.0",
        ":pyasn1_0.4.8",
        ":rsa_4.9",
    ]

    pycross_wheel_library(
        name = "python_jose_3.3.0",
        deps = _python_jose_3_3_0_deps,
        wheel = "@example_lock_wheel_python_jose_3.3.0_py2.py3_none_any//file",
    )

    pycross_wheel_library(
        name = "pytz_2022.6",
        wheel = "@example_lock_wheel_pytz_2022.6_py2.py3_none_any//file",
    )

    pycross_wheel_build(
        name = "_build_pyyaml_6.0",
        sdist = "@example_lock_sdist_pyyaml_6.0//file",
        target_environment = _target,
        tags = ["manual"],
    )

    pycross_wheel_library(
        name = "pyyaml_6.0",
        wheel = ":_build_pyyaml_6.0",
    )

    _requests_2_28_1_deps = [
        ":certifi_2022.12.7",
        ":charset_normalizer_2.1.1",
        ":idna_3.4",
        ":urllib3_1.26.13",
    ]

    pycross_wheel_library(
        name = "requests_2.28.1",
        deps = _requests_2_28_1_deps,
        wheel = "@example_lock_wheel_requests_2.28.1_py3_none_any//file",
    )

    _responses_0_22_0_deps = [
        ":requests_2.28.1",
        ":toml_0.10.2",
        ":types_toml_0.10.8.1",
        ":typing_extensions_4.4.0",
        ":urllib3_1.26.13",
    ]

    pycross_wheel_library(
        name = "responses_0.22.0",
        deps = _responses_0_22_0_deps,
        wheel = "@example_lock_wheel_responses_0.22.0_py3_none_any//file",
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
        ":botocore_1.29.30",
    ]

    pycross_wheel_library(
        name = "s3transfer_0.6.0",
        deps = _s3transfer_0_6_0_deps,
        wheel = "@example_lock_wheel_s3transfer_0.6.0_py3_none_any//file",
    )

    _sarif_om_1_0_4_deps = [
        ":attrs_22.1.0",
        ":pbr_5.11.0",
    ]

    pycross_wheel_library(
        name = "sarif_om_1.0.4",
        deps = _sarif_om_1_0_4_deps,
        wheel = "@example_lock_wheel_sarif_om_1.0.4_py3_none_any//file",
    )

    _secretstorage_3_3_3_deps = [
        ":cryptography_38.0.4",
        ":jeepney_0.8.0",
    ]

    pycross_wheel_library(
        name = "secretstorage_3.3.3",
        deps = _secretstorage_3_3_3_deps,
        wheel = "@example_lock_wheel_secretstorage_3.3.3_py3_none_any//file",
    )

    _setproctitle_1_2_2_build_deps = [
        ":setuptools_58.5.3",
        ":wheel_0.37.1",
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
        name = "setuptools_58.5.3",
        wheel = "@example_lock_wheel_setuptools_58.5.3_py3_none_any//file",
    )

    pycross_wheel_library(
        name = "six_1.16.0",
        wheel = "@example_lock_wheel_six_1.16.0_py2.py3_none_any//file",
    )

    _sqlalchemy_1_4_45_deps = [
        ":importlib_metadata_5.1.0",
    ] + select({
        ":_env_python_darwin_x86_64": [
            ":greenlet_2.0.1",
        ],
        ":_env_python_linux_x86_64": [
            ":greenlet_2.0.1",
        ],
        "//conditions:default": [],
    })

    _sqlalchemy_1_4_45_build_deps = [
        ":setuptools_58.5.3",
        ":wheel_0.37.1",
    ]

    pycross_wheel_build(
        name = "_build_sqlalchemy_1.4.45",
        sdist = "@example_lock_sdist_sqlalchemy_1.4.45//file",
        target_environment = _target,
        deps = _sqlalchemy_1_4_45_deps + _sqlalchemy_1_4_45_build_deps,
        tags = ["manual"],
    )

    pycross_wheel_library(
        name = "sqlalchemy_1.4.45",
        deps = _sqlalchemy_1_4_45_deps,
        wheel = ":_build_sqlalchemy_1.4.45",
    )

    _sqlalchemy_utils_0_38_2_deps = [
        ":six_1.16.0",
        ":sqlalchemy_1.4.45",
    ]

    pycross_wheel_library(
        name = "sqlalchemy_utils_0.38.2",
        deps = _sqlalchemy_utils_0_38_2_deps,
        wheel = "@example_lock_wheel_sqlalchemy_utils_0.38.2_py3_none_any//file",
    )

    _sshpubkeys_3_3_1_deps = [
        ":cryptography_38.0.4",
        ":ecdsa_0.18.0",
    ]

    pycross_wheel_library(
        name = "sshpubkeys_3.3.1",
        deps = _sshpubkeys_3_3_1_deps,
        wheel = "@example_lock_wheel_sshpubkeys_3.3.1_py2.py3_none_any//file",
    )

    pycross_wheel_library(
        name = "toml_0.10.2",
        wheel = "@example_lock_wheel_toml_0.10.2_py2.py3_none_any//file",
    )

    pycross_wheel_library(
        name = "traitlets_5.7.1",
        wheel = "@example_lock_wheel_traitlets_5.7.1_py3_none_any//file",
    )

    _tree_sitter_0_20_0_build_deps = [
        ":setuptools_58.5.3",
        ":wheel_0.37.1",
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
        wheel = ":_build_tree_sitter_0.20.0",
    )

    pycross_wheel_library(
        name = "types_toml_0.10.8.1",
        wheel = "@example_lock_wheel_types_toml_0.10.8.1_py3_none_any//file",
    )

    pycross_wheel_library(
        name = "typing_extensions_4.4.0",
        wheel = "@example_lock_wheel_typing_extensions_4.4.0_py3_none_any//file",
    )

    pycross_wheel_library(
        name = "urllib3_1.26.13",
        wheel = "@example_lock_wheel_urllib3_1.26.13_py2.py3_none_any//file",
    )

    pycross_wheel_library(
        name = "wcwidth_0.2.5",
        wheel = "@example_lock_wheel_wcwidth_0.2.5_py2.py3_none_any//file",
    )

    pycross_wheel_library(
        name = "websocket_client_1.4.2",
        wheel = "@example_lock_wheel_websocket_client_1.4.2_py3_none_any//file",
    )

    _werkzeug_2_2_2_deps = [
        ":markupsafe_2.1.1",
    ]

    pycross_wheel_library(
        name = "werkzeug_2.2.2",
        deps = _werkzeug_2_2_2_deps,
        wheel = "@example_lock_wheel_werkzeug_2.2.2_py3_none_any//file",
    )

    pycross_wheel_library(
        name = "wheel_0.37.1",
        wheel = "@example_lock_wheel_wheel_0.37.1_py2.py3_none_any//file",
    )

    pycross_wheel_build(
        name = "_build_wrapt_1.14.1",
        sdist = "@example_lock_sdist_wrapt_1.14.1//file",
        target_environment = _target,
        tags = ["manual"],
    )

    pycross_wheel_library(
        name = "wrapt_1.14.1",
        wheel = ":_build_wrapt_1.14.1",
    )

    pycross_wheel_library(
        name = "xmltodict_0.13.0",
        wheel = "@example_lock_wheel_xmltodict_0.13.0_py2.py3_none_any//file",
    )

    pycross_wheel_library(
        name = "zipp_3.11.0",
        wheel = "@example_lock_wheel_zipp_3.11.0_py3_none_any//file",
    )

def repositories():
    maybe(
        pypi_file,
        name = "example_lock_sdist_cffi_1.15.1",
        package_name = "cffi",
        package_version = "1.15.1",
        filename = "cffi-1.15.1.tar.gz",
        sha256 = "d400bfb9a37b1351253cb402671cea7e89bdecc294e8016a707f6d1d8ac934f9",
        index = "https://pypi.org",
    )

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
        name = "example_lock_sdist_greenlet_2.0.1",
        package_name = "greenlet",
        package_version = "2.0.1",
        filename = "greenlet-2.0.1.tar.gz",
        sha256 = "42e602564460da0e8ee67cb6d7236363ee5e131aa15943b6670e44e5c2ed0f67",
        index = "https://pypi.org",
    )

    maybe(
        pypi_file,
        name = "example_lock_sdist_markupsafe_2.1.1",
        package_name = "markupsafe",
        package_version = "2.1.1",
        filename = "MarkupSafe-2.1.1.tar.gz",
        sha256 = "7f91197cc9e48f989d12e4e6fbc46495c446636dfc81b9ccf50bb0ec74b91d4b",
        index = "https://pypi.org",
    )

    maybe(
        pypi_file,
        name = "example_lock_sdist_numpy_1.21.1",
        package_name = "numpy",
        package_version = "1.21.1",
        filename = "numpy-1.21.1.zip",
        sha256 = "dff4af63638afcc57a3dfb9e4b26d434a7a602d225b42d746ea7fe2edf1342fd",
        index = "https://pypi.org",
    )

    maybe(
        pypi_file,
        name = "example_lock_sdist_pbr_5.11.0",
        package_name = "pbr",
        package_version = "5.11.0",
        filename = "pbr-5.11.0.tar.gz",
        sha256 = "b97bc6695b2aff02144133c2e7399d5885223d42b7912ffaec2ca3898e673bfe",
        index = "https://pypi.org",
    )

    maybe(
        pypi_file,
        name = "example_lock_sdist_pyyaml_6.0",
        package_name = "pyyaml",
        package_version = "6.0",
        filename = "PyYAML-6.0.tar.gz",
        sha256 = "68fb519c14306fec9720a2a5b45bc9f0c8d1b9c72adf45c37baedfcd949c35a2",
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
        name = "example_lock_sdist_sqlalchemy_1.4.45",
        package_name = "sqlalchemy",
        package_version = "1.4.45",
        filename = "SQLAlchemy-1.4.45.tar.gz",
        sha256 = "fd69850860093a3f69fefe0ab56d041edfdfe18510b53d9a2eaecba2f15fa795",
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
        name = "example_lock_sdist_wrapt_1.14.1",
        package_name = "wrapt",
        package_version = "1.14.1",
        filename = "wrapt-1.14.1.tar.gz",
        sha256 = "380a85cf89e0e69b7cfbe2ea9f765f004ff419f34194018a6827ac0e3edfed4d",
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
        name = "example_lock_wheel_attrs_22.1.0_py2.py3_none_any",
        package_name = "attrs",
        package_version = "22.1.0",
        filename = "attrs-22.1.0-py2.py3-none-any.whl",
        sha256 = "86efa402f67bf2df34f51a335487cf46b1ec130d02b8d39fd248abfd30da551c",
        index = "https://pypi.org",
    )

    maybe(
        pypi_file,
        name = "example_lock_wheel_aws_sam_translator_1.55.0_py3_none_any",
        package_name = "aws-sam-translator",
        package_version = "1.55.0",
        filename = "aws_sam_translator-1.55.0-py3-none-any.whl",
        sha256 = "93dc74614ab291c86be681e025679d08f4fa685ed6b55d410f62f2f235012205",
        index = "https://pypi.org",
    )

    maybe(
        pypi_file,
        name = "example_lock_wheel_aws_xray_sdk_2.11.0_py2.py3_none_any",
        package_name = "aws-xray-sdk",
        package_version = "2.11.0",
        filename = "aws_xray_sdk-2.11.0-py2.py3-none-any.whl",
        sha256 = "693fa3a4c790e131fe1e20814ede415a9eeeab5c3b7c868686d3e3c696b8524d",
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
        name = "example_lock_wheel_boto3_1.26.30_py3_none_any",
        package_name = "boto3",
        package_version = "1.26.30",
        filename = "boto3-1.26.30-py3-none-any.whl",
        sha256 = "e222714a6a841f318d3b6557d915dcc3729ff286e9aa3d03b5d26d6bfce3a3bd",
        index = "https://pypi.org",
    )

    maybe(
        pypi_file,
        name = "example_lock_wheel_botocore_1.29.30_py3_none_any",
        package_name = "botocore",
        package_version = "1.29.30",
        filename = "botocore-1.29.30-py3-none-any.whl",
        sha256 = "6bfe917c022b92c093da448aae71b18f7dcbbbc69403f57ee39ca4775b2888e6",
        index = "https://pypi.org",
    )

    maybe(
        pypi_file,
        name = "example_lock_wheel_certifi_2022.12.7_py3_none_any",
        package_name = "certifi",
        package_version = "2022.12.7",
        filename = "certifi-2022.12.7-py3-none-any.whl",
        sha256 = "4ad3232f5e926d6718ec31cfc1fcadfde020920e278684144551c91769c7bc18",
        index = "https://pypi.org",
    )

    maybe(
        pypi_file,
        name = "example_lock_wheel_cfn_lint_0.72.3_py3_none_any",
        package_name = "cfn-lint",
        package_version = "0.72.3",
        filename = "cfn_lint-0.72.3-py3-none-any.whl",
        sha256 = "b2845d7adcdd7c41bd99b9fbe36f5df58accf371ed62e63982c65aa47f55c278",
        index = "https://pypi.org",
    )

    maybe(
        pypi_file,
        name = "example_lock_wheel_charset_normalizer_2.1.1_py3_none_any",
        package_name = "charset-normalizer",
        package_version = "2.1.1",
        filename = "charset_normalizer-2.1.1-py3-none-any.whl",
        sha256 = "83e9a75d1911279afd89352c68b45348559d1fc0506b054b346651b5e7fee29f",
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
        name = "example_lock_wheel_cryptography_38.0.4_cp36_abi3_macosx_10_10_universal2",
        package_name = "cryptography",
        package_version = "38.0.4",
        filename = "cryptography-38.0.4-cp36-abi3-macosx_10_10_universal2.whl",
        sha256 = "2fa36a7b2cc0998a3a4d5af26ccb6273f3df133d61da2ba13b3286261e7efb70",
        index = "https://pypi.org",
    )

    maybe(
        pypi_file,
        name = "example_lock_wheel_cryptography_38.0.4_cp36_abi3_macosx_10_10_x86_64",
        package_name = "cryptography",
        package_version = "38.0.4",
        filename = "cryptography-38.0.4-cp36-abi3-macosx_10_10_x86_64.whl",
        sha256 = "1f13ddda26a04c06eb57119caf27a524ccae20533729f4b1e4a69b54e07035eb",
        index = "https://pypi.org",
    )

    maybe(
        pypi_file,
        name = "example_lock_wheel_cryptography_38.0.4_cp36_abi3_manylinux_2_17_x86_64.manylinux2014_x86_64",
        package_name = "cryptography",
        package_version = "38.0.4",
        filename = "cryptography-38.0.4-cp36-abi3-manylinux_2_17_x86_64.manylinux2014_x86_64.whl",
        sha256 = "a10498349d4c8eab7357a8f9aa3463791292845b79597ad1b98a543686fb1ec8",
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
        name = "example_lock_wheel_docker_6.0.1_py3_none_any",
        package_name = "docker",
        package_version = "6.0.1",
        filename = "docker-6.0.1-py3-none-any.whl",
        sha256 = "dbcb3bd2fa80dca0788ed908218bf43972772009b881ed1e20dfc29a65e49782",
        index = "https://pypi.org",
    )

    maybe(
        pypi_file,
        name = "example_lock_wheel_ecdsa_0.18.0_py2.py3_none_any",
        package_name = "ecdsa",
        package_version = "0.18.0",
        filename = "ecdsa-0.18.0-py2.py3-none-any.whl",
        sha256 = "80600258e7ed2f16b9aa1d7c295bd70194109ad5a30fdee0eaeefef1d4c559dd",
        index = "https://pypi.org",
    )

    maybe(
        pypi_file,
        name = "example_lock_wheel_flask_2.2.2_py3_none_any",
        package_name = "flask",
        package_version = "2.2.2",
        filename = "Flask-2.2.2-py3-none-any.whl",
        sha256 = "b9c46cc36662a7949f34b52d8ec7bb59c0d74ba08ba6cb9ce9adc1d8676d9526",
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
        name = "example_lock_wheel_graphql_core_3.2.3_py3_none_any",
        package_name = "graphql-core",
        package_version = "3.2.3",
        filename = "graphql_core-3.2.3-py3-none-any.whl",
        sha256 = "5766780452bd5ec8ba133f8bf287dc92713e3868ddd83aee4faab9fc3e303dc3",
        index = "https://pypi.org",
    )

    maybe(
        pypi_file,
        name = "example_lock_wheel_idna_3.4_py3_none_any",
        package_name = "idna",
        package_version = "3.4",
        filename = "idna-3.4-py3-none-any.whl",
        sha256 = "90b77e79eaa3eba6de819a0c442c0b4ceefc341a7a2ab77d7562bf49f425c5c2",
        index = "https://pypi.org",
    )

    maybe(
        pypi_file,
        name = "example_lock_wheel_importlib_metadata_5.1.0_py3_none_any",
        package_name = "importlib-metadata",
        package_version = "5.1.0",
        filename = "importlib_metadata-5.1.0-py3-none-any.whl",
        sha256 = "d84d17e21670ec07990e1044a99efe8d615d860fd176fc29ef5c306068fda313",
        index = "https://pypi.org",
    )

    maybe(
        pypi_file,
        name = "example_lock_wheel_ipython_7.34.0_py3_none_any",
        package_name = "ipython",
        package_version = "7.34.0",
        filename = "ipython-7.34.0-py3-none-any.whl",
        sha256 = "c175d2440a1caff76116eb719d40538fbb316e214eda85c5515c303aacbfb23e",
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
        name = "example_lock_wheel_jaraco.classes_3.2.3_py3_none_any",
        package_name = "jaraco-classes",
        package_version = "3.2.3",
        filename = "jaraco.classes-3.2.3-py3-none-any.whl",
        sha256 = "2353de3288bc6b82120752201c6b1c1a14b058267fa424ed5ce5984e3b922158",
        index = "https://pypi.org",
    )

    maybe(
        pypi_file,
        name = "example_lock_wheel_jedi_0.18.2_py2.py3_none_any",
        package_name = "jedi",
        package_version = "0.18.2",
        filename = "jedi-0.18.2-py2.py3-none-any.whl",
        sha256 = "203c1fd9d969ab8f2119ec0a3342e0b49910045abe6af0a3ae83a5764d54639e",
        index = "https://pypi.org",
    )

    maybe(
        pypi_file,
        name = "example_lock_wheel_jeepney_0.8.0_py3_none_any",
        package_name = "jeepney",
        package_version = "0.8.0",
        filename = "jeepney-0.8.0-py3-none-any.whl",
        sha256 = "c0a454ad016ca575060802ee4d590dd912e35c122fa04e70306de3d076cce755",
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
        name = "example_lock_wheel_jmespath_1.0.1_py3_none_any",
        package_name = "jmespath",
        package_version = "1.0.1",
        filename = "jmespath-1.0.1-py3-none-any.whl",
        sha256 = "02e2e4cc71b5bcab88332eebf907519190dd9e6e82107fa7f83b1003a6252980",
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
        name = "example_lock_wheel_jsonpickle_3.0.0_py2.py3_none_any",
        package_name = "jsonpickle",
        package_version = "3.0.0",
        filename = "jsonpickle-3.0.0-py2.py3-none-any.whl",
        sha256 = "7c4b13d595ff3520148ed870b9f5917023ebdc55c9ec0cb695688fdc16e90c3e",
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
        name = "example_lock_wheel_keyring_23.9.1_py3_none_any",
        package_name = "keyring",
        package_version = "23.9.1",
        filename = "keyring-23.9.1-py3-none-any.whl",
        sha256 = "3565b9e4ea004c96e158d2d332a49f466733d565bb24157a60fd2e49f41a0fd1",
        index = "https://pypi.org",
    )

    maybe(
        pypi_file,
        name = "example_lock_wheel_matplotlib_inline_0.1.6_py3_none_any",
        package_name = "matplotlib-inline",
        package_version = "0.1.6",
        filename = "matplotlib_inline-0.1.6-py3-none-any.whl",
        sha256 = "f1f41aab5328aa5aaea9b16d083b128102f8712542f819fe7e6a420ff581b311",
        index = "https://pypi.org",
    )

    maybe(
        pypi_file,
        name = "example_lock_wheel_more_itertools_9.0.0_py3_none_any",
        package_name = "more-itertools",
        package_version = "9.0.0",
        filename = "more_itertools-9.0.0-py3-none-any.whl",
        sha256 = "250e83d7e81d0c87ca6bd942e6aeab8cc9daa6096d12c5308f3f92fa5e5c1f41",
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
        name = "example_lock_wheel_networkx_2.6.3_py3_none_any",
        package_name = "networkx",
        package_version = "2.6.3",
        filename = "networkx-2.6.3-py3-none-any.whl",
        sha256 = "80b6b89c77d1dfb64a4c7854981b60aeea6360ac02c6d4e4913319e0a313abef",
        index = "https://pypi.org",
    )

    maybe(
        pypi_file,
        name = "example_lock_wheel_opencv_python_4.6.0.66_cp36_abi3_macosx_10_15_x86_64",
        package_name = "opencv-python",
        package_version = "4.6.0.66",
        filename = "opencv_python-4.6.0.66-cp36-abi3-macosx_10_15_x86_64.whl",
        sha256 = "e6e448b62afc95c5b58f97e87ef84699e6607fe5c58730a03301c52496005cae",
        index = "https://pypi.org",
    )

    maybe(
        pypi_file,
        name = "example_lock_wheel_opencv_python_4.6.0.66_cp36_abi3_manylinux_2_17_x86_64.manylinux2014_x86_64",
        package_name = "opencv-python",
        package_version = "4.6.0.66",
        filename = "opencv_python-4.6.0.66-cp36-abi3-manylinux_2_17_x86_64.manylinux2014_x86_64.whl",
        sha256 = "dbdc84a9b4ea2cbae33861652d25093944b9959279200b7ae0badd32439f74de",
        index = "https://pypi.org",
    )

    maybe(
        pypi_file,
        name = "example_lock_wheel_opencv_python_4.6.0.66_cp37_abi3_macosx_11_0_arm64",
        package_name = "opencv-python",
        package_version = "4.6.0.66",
        filename = "opencv_python-4.6.0.66-cp37-abi3-macosx_11_0_arm64.whl",
        sha256 = "6e32af22e3202748bd233ed8f538741876191863882eba44e332d1a34993165b",
        index = "https://pypi.org",
    )

    maybe(
        pypi_file,
        name = "example_lock_wheel_packaging_22.0_py3_none_any",
        package_name = "packaging",
        package_version = "22.0",
        filename = "packaging-22.0-py3-none-any.whl",
        sha256 = "957e2148ba0e1a3b282772e791ef1d8083648bc131c8ab0c1feba110ce1146c3",
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
        name = "example_lock_wheel_prompt_toolkit_3.0.36_py3_none_any",
        package_name = "prompt-toolkit",
        package_version = "3.0.36",
        filename = "prompt_toolkit-3.0.36-py3-none-any.whl",
        sha256 = "aa64ad242a462c5ff0363a7b9cfe696c20d55d9fc60c11fd8e632d064804d305",
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
        name = "example_lock_wheel_pygments_2.13.0_py3_none_any",
        package_name = "pygments",
        package_version = "2.13.0",
        filename = "Pygments-2.13.0-py3-none-any.whl",
        sha256 = "f643f331ab57ba3c9d89212ee4a2dabc6e94f117cf4eefde99a0574720d14c42",
        index = "https://pypi.org",
    )

    maybe(
        pypi_file,
        name = "example_lock_wheel_pyrsistent_0.19.2_py3_none_any",
        package_name = "pyrsistent",
        package_version = "0.19.2",
        filename = "pyrsistent-0.19.2-py3-none-any.whl",
        sha256 = "ea6b79a02a28550c98b6ca9c35b9f492beaa54d7c5c9e9949555893c8a9234d0",
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
        name = "example_lock_wheel_python_jose_3.3.0_py2.py3_none_any",
        package_name = "python-jose",
        package_version = "3.3.0",
        filename = "python_jose-3.3.0-py2.py3-none-any.whl",
        sha256 = "9b1376b023f8b298536eedd47ae1089bcdb848f1535ab30555cd92002d78923a",
        index = "https://pypi.org",
    )

    maybe(
        pypi_file,
        name = "example_lock_wheel_pytz_2022.6_py2.py3_none_any",
        package_name = "pytz",
        package_version = "2022.6",
        filename = "pytz-2022.6-py2.py3-none-any.whl",
        sha256 = "222439474e9c98fced559f1709d89e6c9cbf8d79c794ff3eb9f8800064291427",
        index = "https://pypi.org",
    )

    maybe(
        pypi_file,
        name = "example_lock_wheel_requests_2.28.1_py3_none_any",
        package_name = "requests",
        package_version = "2.28.1",
        filename = "requests-2.28.1-py3-none-any.whl",
        sha256 = "8fefa2a1a1365bf5520aac41836fbee479da67864514bdb821f31ce07ce65349",
        index = "https://pypi.org",
    )

    maybe(
        pypi_file,
        name = "example_lock_wheel_responses_0.22.0_py3_none_any",
        package_name = "responses",
        package_version = "0.22.0",
        filename = "responses-0.22.0-py3-none-any.whl",
        sha256 = "dcf294d204d14c436fddcc74caefdbc5764795a40ff4e6a7740ed8ddbf3294be",
        index = "https://pypi.org",
    )

    maybe(
        pypi_file,
        name = "example_lock_wheel_rsa_4.9_py3_none_any",
        package_name = "rsa",
        package_version = "4.9",
        filename = "rsa-4.9-py3-none-any.whl",
        sha256 = "90260d9058e514786967344d0ef75fa8727eed8a7d2e43ce9f4bcf1b536174f7",
        index = "https://pypi.org",
    )

    maybe(
        pypi_file,
        name = "example_lock_wheel_s3transfer_0.6.0_py3_none_any",
        package_name = "s3transfer",
        package_version = "0.6.0",
        filename = "s3transfer-0.6.0-py3-none-any.whl",
        sha256 = "06176b74f3a15f61f1b4f25a1fc29a4429040b7647133a463da8fa5bd28d5ecd",
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
        name = "example_lock_wheel_secretstorage_3.3.3_py3_none_any",
        package_name = "secretstorage",
        package_version = "3.3.3",
        filename = "SecretStorage-3.3.3-py3-none-any.whl",
        sha256 = "f356e6628222568e3af06f2eba8df495efa13b3b63081dafd4f7d9a7b7bc9f99",
        index = "https://pypi.org",
    )

    maybe(
        pypi_file,
        name = "example_lock_wheel_setuptools_58.5.3_py3_none_any",
        package_name = "setuptools",
        package_version = "58.5.3",
        filename = "setuptools-58.5.3-py3-none-any.whl",
        sha256 = "a481fbc56b33f5d8f6b33dce41482e64c68b668be44ff42922903b03872590bf",
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
        name = "example_lock_wheel_toml_0.10.2_py2.py3_none_any",
        package_name = "toml",
        package_version = "0.10.2",
        filename = "toml-0.10.2-py2.py3-none-any.whl",
        sha256 = "806143ae5bfb6a3c6e736a764057db0e6a0e05e338b5630894a5f779cabb4f9b",
        index = "https://pypi.org",
    )

    maybe(
        pypi_file,
        name = "example_lock_wheel_traitlets_5.7.1_py3_none_any",
        package_name = "traitlets",
        package_version = "5.7.1",
        filename = "traitlets-5.7.1-py3-none-any.whl",
        sha256 = "57ba2ba951632eeab9388fa45f342a5402060a5cc9f0bb942f760fafb6641581",
        index = "https://pypi.org",
    )

    maybe(
        pypi_file,
        name = "example_lock_wheel_types_toml_0.10.8.1_py3_none_any",
        package_name = "types-toml",
        package_version = "0.10.8.1",
        filename = "types_toml-0.10.8.1-py3-none-any.whl",
        sha256 = "b7b5c4977f96ab7b5ac06d8a6590d17c0bf252a96efc03b109c2711fb3e0eafd",
        index = "https://pypi.org",
    )

    maybe(
        pypi_file,
        name = "example_lock_wheel_typing_extensions_4.4.0_py3_none_any",
        package_name = "typing-extensions",
        package_version = "4.4.0",
        filename = "typing_extensions-4.4.0-py3-none-any.whl",
        sha256 = "16fa4864408f655d35ec496218b85f79b3437c829e93320c7c9215ccfd92489e",
        index = "https://pypi.org",
    )

    maybe(
        pypi_file,
        name = "example_lock_wheel_urllib3_1.26.13_py2.py3_none_any",
        package_name = "urllib3",
        package_version = "1.26.13",
        filename = "urllib3-1.26.13-py2.py3-none-any.whl",
        sha256 = "47cc05d99aaa09c9e72ed5809b60e7ba354e64b59c9c173ac3018642d8bb41fc",
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
        name = "example_lock_wheel_websocket_client_1.4.2_py3_none_any",
        package_name = "websocket-client",
        package_version = "1.4.2",
        filename = "websocket_client-1.4.2-py3-none-any.whl",
        sha256 = "d6b06432f184438d99ac1f456eaf22fe1ade524c3dd16e661142dc54e9cba574",
        index = "https://pypi.org",
    )

    maybe(
        pypi_file,
        name = "example_lock_wheel_werkzeug_2.2.2_py3_none_any",
        package_name = "werkzeug",
        package_version = "2.2.2",
        filename = "Werkzeug-2.2.2-py3-none-any.whl",
        sha256 = "f979ab81f58d7318e064e99c4506445d60135ac5cd2e177a2de0089bfd4c9bd5",
        index = "https://pypi.org",
    )

    maybe(
        pypi_file,
        name = "example_lock_wheel_wheel_0.37.1_py2.py3_none_any",
        package_name = "wheel",
        package_version = "0.37.1",
        filename = "wheel-0.37.1-py2.py3-none-any.whl",
        sha256 = "4bdcd7d840138086126cd09254dc6195fb4fc6f01c050a1d7236f2630db1d22a",
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
        name = "example_lock_wheel_zipp_3.11.0_py3_none_any",
        package_name = "zipp",
        package_version = "3.11.0",
        filename = "zipp-3.11.0-py3-none-any.whl",
        sha256 = "83a28fcb75844b5c0cdaf5aa4003c2d728c77e05f5aeabe8e95e56727005fbaa",
        index = "https://pypi.org",
    )

