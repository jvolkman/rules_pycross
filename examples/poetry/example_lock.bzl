load("@bazel_tools//tools/build_defs/repo:http.bzl", "http_file")
load("@bazel_tools//tools/build_defs/repo:utils.bzl", "maybe")
load("@jvolkman_rules_pycross//pycross:defs.bzl", "pycross_wheel_build", "pycross_wheel_library", "pypi_file")

PINS = {
    "appnope": "appnope_0.1.3",
    "asttokens": "asttokens_2.0.8",
    "attrs": "attrs_22.1.0",
    "aws_sam_translator": "aws_sam_translator_1.51.0",
    "aws_xray_sdk": "aws_xray_sdk_2.10.0",
    "backcall": "backcall_0.2.0",
    "boto3": "boto3_1.24.73",
    "botocore": "botocore_1.27.73",
    "certifi": "certifi_2022.9.14",
    "cffi": "cffi_1.15.1",
    "cfn_lint": "cfn_lint_0.65.0",
    "charset_normalizer": "charset_normalizer_2.1.1",
    "click": "click_8.1.3",
    "cognitojwt": "cognitojwt_1.4.1",
    "cryptography": "cryptography_38.0.1",
    "cython": "cython_0.29.32",
    "decorator": "decorator_5.1.1",
    "docker": "docker_6.0.0",
    "ecdsa": "ecdsa_0.18.0",
    "executing": "executing_1.0.0",
    "flask": "flask_2.2.2",
    "flask_cors": "flask_cors_3.0.10",
    "future": "future_0.18.2",
    "graphql_core": "graphql_core_3.2.1",
    "greenlet": "greenlet_1.1.3",
    "idna": "idna_3.4",
    "importlib_metadata": "importlib_metadata_4.12.0",
    "ipython": "ipython_8.5.0",
    "itsdangerous": "itsdangerous_2.1.2",
    "jaraco_classes": "jaraco_classes_3.2.2",
    "jedi": "jedi_0.18.1",
    "jeepney": "jeepney_0.8.0",
    "jinja2": "jinja2_3.1.2",
    "jmespath": "jmespath_1.0.1",
    "jschema_to_python": "jschema_to_python_1.2.3",
    "jsondiff": "jsondiff_2.0.0",
    "jsonpatch": "jsonpatch_1.32",
    "jsonpickle": "jsonpickle_2.2.0",
    "jsonpointer": "jsonpointer_2.3",
    "jsonschema": "jsonschema_3.2.0",
    "junit_xml": "junit_xml_1.9",
    "keyring": "keyring_23.9.1",
    "markupsafe": "markupsafe_2.1.1",
    "matplotlib_inline": "matplotlib_inline_0.1.6",
    "more_itertools": "more_itertools_8.14.0",
    "moto": "moto_3.1.1",
    "networkx": "networkx_2.8.6",
    "numpy": "numpy_1.22.3",
    "opencv_python": "opencv_python_4.6.0.66",
    "packaging": "packaging_21.3",
    "parso": "parso_0.8.3",
    "pbr": "pbr_5.10.0",
    "pexpect": "pexpect_4.8.0",
    "pickleshare": "pickleshare_0.7.5",
    "prompt_toolkit": "prompt_toolkit_3.0.31",
    "ptyprocess": "ptyprocess_0.7.0",
    "pure_eval": "pure_eval_0.2.2",
    "pyasn1": "pyasn1_0.4.8",
    "pycparser": "pycparser_2.21",
    "pygments": "pygments_2.13.0",
    "pyparsing": "pyparsing_3.0.9",
    "pyrsistent": "pyrsistent_0.18.1",
    "python_dateutil": "python_dateutil_2.8.2",
    "python_jose": "python_jose_3.1.0",
    "pytz": "pytz_2022.2.1",
    "pyyaml": "pyyaml_6.0",
    "requests": "requests_2.28.1",
    "responses": "responses_0.21.0",
    "rsa": "rsa_4.9",
    "s3transfer": "s3transfer_0.6.0",
    "sarif_om": "sarif_om_1.0.4",
    "secretstorage": "secretstorage_3.3.3",
    "setproctitle": "setproctitle_1.2.2",
    "setuptools": "setuptools_59.2.0",
    "six": "six_1.16.0",
    "sqlalchemy": "sqlalchemy_1.4.41",
    "sqlalchemy_utils": "sqlalchemy_utils_0.38.2",
    "sshpubkeys": "sshpubkeys_3.3.1",
    "stack_data": "stack_data_0.5.0",
    "traitlets": "traitlets_5.4.0",
    "tree_sitter": "tree_sitter_0.20.0",
    "urllib3": "urllib3_1.26.12",
    "wcwidth": "wcwidth_0.2.5",
    "websocket_client": "websocket_client_1.4.1",
    "werkzeug": "werkzeug_2.2.2",
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

    _asttokens_2_0_8_deps = [
        ":six_1.16.0",
    ]

    pycross_wheel_library(
        name = "asttokens_2.0.8",
        deps = _asttokens_2_0_8_deps,
        wheel = "@example_lock_wheel_asttokens_2.0.8_py2.py3_none_any//file",
    )

    pycross_wheel_library(
        name = "attrs_22.1.0",
        wheel = "@example_lock_wheel_attrs_22.1.0_py2.py3_none_any//file",
    )

    _aws_sam_translator_1_51_0_deps = [
        ":boto3_1.24.73",
        ":jsonschema_3.2.0",
    ]

    pycross_wheel_library(
        name = "aws_sam_translator_1.51.0",
        deps = _aws_sam_translator_1_51_0_deps,
        wheel = "@example_lock_wheel_aws_sam_translator_1.51.0_py3_none_any//file",
    )

    _aws_xray_sdk_2_10_0_deps = [
        ":botocore_1.27.73",
        ":wrapt_1.14.1",
    ]

    pycross_wheel_library(
        name = "aws_xray_sdk_2.10.0",
        deps = _aws_xray_sdk_2_10_0_deps,
        wheel = "@example_lock_wheel_aws_xray_sdk_2.10.0_py2.py3_none_any//file",
    )

    pycross_wheel_library(
        name = "backcall_0.2.0",
        wheel = "@example_lock_wheel_backcall_0.2.0_py2.py3_none_any//file",
    )

    _boto3_1_24_73_deps = [
        ":botocore_1.27.73",
        ":jmespath_1.0.1",
        ":s3transfer_0.6.0",
    ]

    pycross_wheel_library(
        name = "boto3_1.24.73",
        deps = _boto3_1_24_73_deps,
        wheel = "@example_lock_wheel_boto3_1.24.73_py3_none_any//file",
    )

    _botocore_1_27_73_deps = [
        ":jmespath_1.0.1",
        ":python_dateutil_2.8.2",
        ":urllib3_1.26.12",
    ]

    pycross_wheel_library(
        name = "botocore_1.27.73",
        deps = _botocore_1_27_73_deps,
        wheel = "@example_lock_wheel_botocore_1.27.73_py3_none_any//file",
    )

    pycross_wheel_library(
        name = "certifi_2022.9.14",
        wheel = "@example_lock_wheel_certifi_2022.9.14_py3_none_any//file",
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

    _cfn_lint_0_65_0_deps = [
        ":aws_sam_translator_1.51.0",
        ":jschema_to_python_1.2.3",
        ":jsonpatch_1.32",
        ":jsonschema_3.2.0",
        ":junit_xml_1.9",
        ":networkx_2.8.6",
        ":pyyaml_6.0",
        ":sarif_om_1.0.4",
    ]

    pycross_wheel_library(
        name = "cfn_lint_0.65.0",
        deps = _cfn_lint_0_65_0_deps,
        wheel = "@example_lock_wheel_cfn_lint_0.65.0_py3_none_any//file",
    )

    pycross_wheel_library(
        name = "charset_normalizer_2.1.1",
        wheel = "@example_lock_wheel_charset_normalizer_2.1.1_py3_none_any//file",
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

    _cryptography_38_0_1_deps = [
        ":cffi_1.15.1",
    ]

    pycross_wheel_library(
        name = "cryptography_38.0.1",
        deps = _cryptography_38_0_1_deps,
        wheel = select({
            ":_env_python_darwin_arm64": "@example_lock_wheel_cryptography_38.0.1_cp36_abi3_macosx_10_10_universal2//file",
            ":_env_python_darwin_x86_64": "@example_lock_wheel_cryptography_38.0.1_cp36_abi3_macosx_10_10_x86_64//file",
            ":_env_python_linux_x86_64": "@example_lock_wheel_cryptography_38.0.1_cp36_abi3_manylinux_2_17_x86_64.manylinux2014_x86_64//file",
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

    _docker_6_0_0_deps = [
        ":packaging_21.3",
        ":requests_2.28.1",
        ":urllib3_1.26.12",
        ":websocket_client_1.4.1",
    ]

    pycross_wheel_library(
        name = "docker_6.0.0",
        deps = _docker_6_0_0_deps,
        wheel = "@example_lock_wheel_docker_6.0.0_py3_none_any//file",
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
        name = "executing_1.0.0",
        wheel = "@example_lock_wheel_executing_1.0.0_py2.py3_none_any//file",
    )

    _flask_2_2_2_deps = [
        ":click_8.1.3",
        ":importlib_metadata_4.12.0",
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

    pycross_wheel_library(
        name = "future_0.18.2",
        wheel = "@//deps:overridden_future_0.18.2",
    )

    pycross_wheel_library(
        name = "graphql_core_3.2.1",
        wheel = "@example_lock_wheel_graphql_core_3.2.1_py3_none_any//file",
    )

    _greenlet_1_1_3_build_deps = [
        ":setuptools_59.2.0",
        ":wheel_0.37.0",
    ]

    pycross_wheel_build(
        name = "_build_greenlet_1.1.3",
        sdist = "@example_lock_sdist_greenlet_1.1.3//file",
        target_environment = _target,
        deps = _greenlet_1_1_3_build_deps,
        tags = ["manual"],
    )

    pycross_wheel_library(
        name = "greenlet_1.1.3",
        wheel = select({
            ":_env_python_darwin_arm64": ":_build_greenlet_1.1.3",
            ":_env_python_darwin_x86_64": "@example_lock_wheel_greenlet_1.1.3_cp39_cp39_macosx_10_15_x86_64//file",
            ":_env_python_linux_x86_64": "@example_lock_wheel_greenlet_1.1.3_cp39_cp39_manylinux_2_17_x86_64.manylinux2014_x86_64//file",
        }),
    )

    pycross_wheel_library(
        name = "idna_3.4",
        wheel = "@example_lock_wheel_idna_3.4_py3_none_any//file",
    )

    _importlib_metadata_4_12_0_deps = [
        ":zipp_3.8.1",
    ]

    pycross_wheel_library(
        name = "importlib_metadata_4.12.0",
        deps = _importlib_metadata_4_12_0_deps,
        wheel = "@example_lock_wheel_importlib_metadata_4.12.0_py3_none_any//file",
    )

    _ipython_8_5_0_deps = [
        ":backcall_0.2.0",
        ":decorator_5.1.1",
        ":jedi_0.18.1",
        ":matplotlib_inline_0.1.6",
        ":pexpect_4.8.0",
        ":pickleshare_0.7.5",
        ":prompt_toolkit_3.0.31",
        ":pygments_2.13.0",
        ":stack_data_0.5.0",
        ":traitlets_5.4.0",
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
        name = "ipython_8.5.0",
        deps = _ipython_8_5_0_deps,
        wheel = "@example_lock_wheel_ipython_8.5.0_py3_none_any//file",
    )

    pycross_wheel_library(
        name = "itsdangerous_2.1.2",
        wheel = "@example_lock_wheel_itsdangerous_2.1.2_py3_none_any//file",
    )

    _jaraco_classes_3_2_2_deps = [
        ":more_itertools_8.14.0",
    ]

    pycross_wheel_library(
        name = "jaraco_classes_3.2.2",
        deps = _jaraco_classes_3_2_2_deps,
        wheel = "@example_lock_wheel_jaraco.classes_3.2.2_py3_none_any//file",
    )

    _jedi_0_18_1_deps = [
        ":parso_0.8.3",
    ]

    pycross_wheel_library(
        name = "jedi_0.18.1",
        deps = _jedi_0_18_1_deps,
        wheel = "@example_lock_wheel_jedi_0.18.1_py2.py3_none_any//file",
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
        ":jsonpickle_2.2.0",
        ":pbr_5.10.0",
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

    _keyring_23_9_1_deps = [
        ":importlib_metadata_4.12.0",
        ":jaraco_classes_3.2.2",
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

    pycross_wheel_library(
        name = "markupsafe_2.1.1",
        wheel = select({
            ":_env_python_darwin_arm64": "@example_lock_wheel_markupsafe_2.1.1_cp39_cp39_macosx_10_9_universal2//file",
            ":_env_python_darwin_x86_64": "@example_lock_wheel_markupsafe_2.1.1_cp39_cp39_macosx_10_9_x86_64//file",
            ":_env_python_linux_x86_64": "@example_lock_wheel_markupsafe_2.1.1_cp39_cp39_manylinux_2_17_x86_64.manylinux2014_x86_64//file",
        }),
    )

    _matplotlib_inline_0_1_6_deps = [
        ":traitlets_5.4.0",
    ]

    pycross_wheel_library(
        name = "matplotlib_inline_0.1.6",
        deps = _matplotlib_inline_0_1_6_deps,
        wheel = "@example_lock_wheel_matplotlib_inline_0.1.6_py3_none_any//file",
    )

    pycross_wheel_library(
        name = "more_itertools_8.14.0",
        wheel = "@example_lock_wheel_more_itertools_8.14.0_py3_none_any//file",
    )

    _moto_3_1_1_deps = [
        ":aws_xray_sdk_2.10.0",
        ":boto3_1.24.73",
        ":botocore_1.27.73",
        ":cfn_lint_0.65.0",
        ":cryptography_38.0.1",
        ":docker_6.0.0",
        ":ecdsa_0.18.0",
        ":flask_2.2.2",
        ":flask_cors_3.0.10",
        ":graphql_core_3.2.1",
        ":idna_3.4",
        ":jinja2_3.1.2",
        ":jsondiff_2.0.0",
        ":markupsafe_2.1.1",
        ":python_dateutil_2.8.2",
        ":python_jose_3.1.0",
        ":pytz_2022.2.1",
        ":pyyaml_6.0",
        ":requests_2.28.1",
        ":responses_0.21.0",
        ":setuptools_59.2.0",
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
        name = "networkx_2.8.6",
        wheel = "@example_lock_wheel_networkx_2.8.6_py3_none_any//file",
    )

    pycross_wheel_library(
        name = "numpy_1.22.3",
        wheel = select({
            ":_env_python_darwin_arm64": "@example_lock_wheel_numpy_1.22.3_cp39_cp39_macosx_11_0_arm64//file",
            ":_env_python_darwin_x86_64": "@example_lock_wheel_numpy_1.22.3_cp39_cp39_macosx_10_14_x86_64//file",
            ":_env_python_linux_x86_64": "@example_lock_wheel_numpy_1.22.3_cp39_cp39_manylinux_2_17_x86_64.manylinux2014_x86_64//file",
        }),
    )

    _opencv_python_4_6_0_66_deps = select({
        ":_env_python_darwin_arm64": [
            ":numpy_1.22.3",
        ],
        ":_env_python_darwin_x86_64": [
            ":numpy_1.22.3",
        ],
        ":_env_python_linux_x86_64": [
            ":numpy_1.22.3",
        ],
        "//conditions:default": [],
    })

    pycross_wheel_library(
        name = "opencv_python_4.6.0.66",
        deps = _opencv_python_4_6_0_66_deps,
        wheel = select({
            ":_env_python_darwin_arm64": "@example_lock_wheel_opencv_python_4.6.0.66_cp37_abi3_macosx_11_0_arm64//file",
            ":_env_python_darwin_x86_64": "@example_lock_wheel_opencv_python_4.6.0.66_cp36_abi3_macosx_10_15_x86_64//file",
            ":_env_python_linux_x86_64": "@example_lock_wheel_opencv_python_4.6.0.66_cp36_abi3_manylinux_2_17_x86_64.manylinux2014_x86_64//file",
        }),
    )

    _packaging_21_3_deps = [
        ":pyparsing_3.0.9",
    ]

    pycross_wheel_library(
        name = "packaging_21.3",
        deps = _packaging_21_3_deps,
        wheel = "@example_lock_wheel_packaging_21.3_py3_none_any//file",
    )

    pycross_wheel_library(
        name = "parso_0.8.3",
        wheel = "@example_lock_wheel_parso_0.8.3_py2.py3_none_any//file",
    )

    _pbr_5_10_0_build_deps = [
        ":setuptools_59.2.0",
        ":wheel_0.37.0",
    ]

    pycross_wheel_build(
        name = "_build_pbr_5.10.0",
        sdist = "@example_lock_sdist_pbr_5.10.0//file",
        target_environment = _target,
        deps = _pbr_5_10_0_build_deps,
        tags = ["manual"],
    )

    pycross_wheel_library(
        name = "pbr_5.10.0",
        wheel = ":_build_pbr_5.10.0",
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

    _prompt_toolkit_3_0_31_deps = [
        ":wcwidth_0.2.5",
    ]

    pycross_wheel_library(
        name = "prompt_toolkit_3.0.31",
        deps = _prompt_toolkit_3_0_31_deps,
        wheel = "@example_lock_wheel_prompt_toolkit_3.0.31_py3_none_any//file",
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
        name = "pygments_2.13.0",
        wheel = "@example_lock_wheel_pygments_2.13.0_py3_none_any//file",
    )

    pycross_wheel_library(
        name = "pyparsing_3.0.9",
        wheel = "@example_lock_wheel_pyparsing_3.0.9_py3_none_any//file",
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
        ":cryptography_38.0.1",
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
        name = "pytz_2022.2.1",
        wheel = "@example_lock_wheel_pytz_2022.2.1_py2.py3_none_any//file",
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
        ":certifi_2022.9.14",
        ":charset_normalizer_2.1.1",
        ":idna_3.4",
        ":urllib3_1.26.12",
    ]

    pycross_wheel_library(
        name = "requests_2.28.1",
        deps = _requests_2_28_1_deps,
        wheel = "@example_lock_wheel_requests_2.28.1_py3_none_any//file",
    )

    _responses_0_21_0_deps = [
        ":requests_2.28.1",
        ":urllib3_1.26.12",
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
        ":botocore_1.27.73",
    ]

    pycross_wheel_library(
        name = "s3transfer_0.6.0",
        deps = _s3transfer_0_6_0_deps,
        wheel = "@example_lock_wheel_s3transfer_0.6.0_py3_none_any//file",
    )

    _sarif_om_1_0_4_deps = [
        ":attrs_22.1.0",
        ":pbr_5.10.0",
    ]

    pycross_wheel_library(
        name = "sarif_om_1.0.4",
        deps = _sarif_om_1_0_4_deps,
        wheel = "@example_lock_wheel_sarif_om_1.0.4_py3_none_any//file",
    )

    _secretstorage_3_3_3_deps = [
        ":cryptography_38.0.1",
        ":jeepney_0.8.0",
    ]

    pycross_wheel_library(
        name = "secretstorage_3.3.3",
        deps = _secretstorage_3_3_3_deps,
        wheel = "@example_lock_wheel_secretstorage_3.3.3_py3_none_any//file",
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

    _sqlalchemy_1_4_41_deps = [
        ":greenlet_1.1.3",
    ]

    pycross_wheel_build(
        name = "_build_sqlalchemy_1.4.41",
        sdist = "@example_lock_sdist_sqlalchemy_1.4.41//file",
        target_environment = _target,
        deps = _sqlalchemy_1_4_41_deps,
        tags = ["manual"],
    )

    pycross_wheel_library(
        name = "sqlalchemy_1.4.41",
        deps = _sqlalchemy_1_4_41_deps,
        wheel = select({
            ":_env_python_darwin_arm64": ":_build_sqlalchemy_1.4.41",
            ":_env_python_darwin_x86_64": "@example_lock_wheel_sqlalchemy_1.4.41_cp39_cp39_macosx_10_15_x86_64//file",
            ":_env_python_linux_x86_64": "@example_lock_wheel_sqlalchemy_1.4.41_cp39_cp39_manylinux_2_5_x86_64.manylinux1_x86_64.manylinux_2_17_x86_64.manylinux2014_x86_64//file",
        }),
    )

    _sqlalchemy_utils_0_38_2_deps = [
        ":six_1.16.0",
        ":sqlalchemy_1.4.41",
    ]

    pycross_wheel_library(
        name = "sqlalchemy_utils_0.38.2",
        deps = _sqlalchemy_utils_0_38_2_deps,
        wheel = "@example_lock_wheel_sqlalchemy_utils_0.38.2_py3_none_any//file",
    )

    _sshpubkeys_3_3_1_deps = [
        ":cryptography_38.0.1",
        ":ecdsa_0.18.0",
    ]

    pycross_wheel_library(
        name = "sshpubkeys_3.3.1",
        deps = _sshpubkeys_3_3_1_deps,
        wheel = "@example_lock_wheel_sshpubkeys_3.3.1_py2.py3_none_any//file",
    )

    _stack_data_0_5_0_deps = [
        ":asttokens_2.0.8",
        ":executing_1.0.0",
        ":pure_eval_0.2.2",
    ]

    pycross_wheel_library(
        name = "stack_data_0.5.0",
        deps = _stack_data_0_5_0_deps,
        wheel = "@example_lock_wheel_stack_data_0.5.0_py3_none_any//file",
    )

    pycross_wheel_library(
        name = "traitlets_5.4.0",
        wheel = "@example_lock_wheel_traitlets_5.4.0_py3_none_any//file",
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
        name = "urllib3_1.26.12",
        wheel = "@example_lock_wheel_urllib3_1.26.12_py2.py3_none_any//file",
    )

    pycross_wheel_library(
        name = "wcwidth_0.2.5",
        wheel = "@example_lock_wheel_wcwidth_0.2.5_py2.py3_none_any//file",
    )

    pycross_wheel_library(
        name = "websocket_client_1.4.1",
        wheel = "@example_lock_wheel_websocket_client_1.4.1_py3_none_any//file",
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
        name = "example_lock_sdist_greenlet_1.1.3",
        package_name = "greenlet",
        package_version = "1.1.3",
        filename = "greenlet-1.1.3.tar.gz",
        sha256 = "bcb6c6dd1d6be6d38d6db283747d07fda089ff8c559a835236560a4410340455",
        index = "https://pypi.org",
    )

    maybe(
        pypi_file,
        name = "example_lock_sdist_pbr_5.10.0",
        package_name = "pbr",
        package_version = "5.10.0",
        filename = "pbr-5.10.0.tar.gz",
        sha256 = "cfcc4ff8e698256fc17ea3ff796478b050852585aa5bae79ecd05b2ab7b39b9a",
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
        name = "example_lock_sdist_sqlalchemy_1.4.41",
        package_name = "sqlalchemy",
        package_version = "1.4.41",
        filename = "SQLAlchemy-1.4.41.tar.gz",
        sha256 = "0292f70d1797e3c54e862e6f30ae474014648bc9c723e14a2fda730adb0a9791",
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
        name = "example_lock_wheel_asttokens_2.0.8_py2.py3_none_any",
        package_name = "asttokens",
        package_version = "2.0.8",
        filename = "asttokens-2.0.8-py2.py3-none-any.whl",
        sha256 = "e3305297c744ae53ffa032c45dc347286165e4ffce6875dc662b205db0623d86",
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
        name = "example_lock_wheel_aws_sam_translator_1.51.0_py3_none_any",
        package_name = "aws-sam-translator",
        package_version = "1.51.0",
        filename = "aws_sam_translator-1.51.0-py3-none-any.whl",
        sha256 = "f0f09f95fcc0c5e699603b9b1daa86307b94920b0823c423ed2ff1eb1cac497f",
        index = "https://pypi.org",
    )

    maybe(
        pypi_file,
        name = "example_lock_wheel_aws_xray_sdk_2.10.0_py2.py3_none_any",
        package_name = "aws-xray-sdk",
        package_version = "2.10.0",
        filename = "aws_xray_sdk-2.10.0-py2.py3-none-any.whl",
        sha256 = "7551e81a796e1a5471ebe84844c40e8edf7c218db33506d046fec61f7495eda4",
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
        name = "example_lock_wheel_boto3_1.24.73_py3_none_any",
        package_name = "boto3",
        package_version = "1.24.73",
        filename = "boto3-1.24.73-py3-none-any.whl",
        sha256 = "f7ca88a76c8e31c19fef3bad2dee3c2ee0e77a0bced151fa3922cf021d55755e",
        index = "https://pypi.org",
    )

    maybe(
        pypi_file,
        name = "example_lock_wheel_botocore_1.27.73_py3_none_any",
        package_name = "botocore",
        package_version = "1.27.73",
        filename = "botocore-1.27.73-py3-none-any.whl",
        sha256 = "0b94d1e7b1435f8ff108c74a09fe03ec88aadbfafe97e940ea415dc86ba305a3",
        index = "https://pypi.org",
    )

    maybe(
        pypi_file,
        name = "example_lock_wheel_certifi_2022.9.14_py3_none_any",
        package_name = "certifi",
        package_version = "2022.9.14",
        filename = "certifi-2022.9.14-py3-none-any.whl",
        sha256 = "e232343de1ab72c2aa521b625c80f699e356830fd0e2c620b465b304b17b0516",
        index = "https://pypi.org",
    )

    maybe(
        pypi_file,
        name = "example_lock_wheel_cffi_1.15.1_cp39_cp39_macosx_10_9_x86_64",
        package_name = "cffi",
        package_version = "1.15.1",
        filename = "cffi-1.15.1-cp39-cp39-macosx_10_9_x86_64.whl",
        sha256 = "54a2db7b78338edd780e7ef7f9f6c442500fb0d41a5a4ea24fff1c929d5af585",
        index = "https://pypi.org",
    )

    maybe(
        pypi_file,
        name = "example_lock_wheel_cffi_1.15.1_cp39_cp39_macosx_11_0_arm64",
        package_name = "cffi",
        package_version = "1.15.1",
        filename = "cffi-1.15.1-cp39-cp39-macosx_11_0_arm64.whl",
        sha256 = "fcd131dd944808b5bdb38e6f5b53013c5aa4f334c5cad0c72742f6eba4b73db0",
        index = "https://pypi.org",
    )

    maybe(
        pypi_file,
        name = "example_lock_wheel_cffi_1.15.1_cp39_cp39_manylinux_2_17_x86_64.manylinux2014_x86_64",
        package_name = "cffi",
        package_version = "1.15.1",
        filename = "cffi-1.15.1-cp39-cp39-manylinux_2_17_x86_64.manylinux2014_x86_64.whl",
        sha256 = "5d598b938678ebf3c67377cdd45e09d431369c3b1a5b331058c338e201f12b27",
        index = "https://pypi.org",
    )

    maybe(
        pypi_file,
        name = "example_lock_wheel_cfn_lint_0.65.0_py3_none_any",
        package_name = "cfn-lint",
        package_version = "0.65.0",
        filename = "cfn_lint-0.65.0-py3-none-any.whl",
        sha256 = "b5992f52a86e6ef0a150fabbb4d131bbf626eddd4154ca708193c1d233a7efca",
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
        name = "example_lock_wheel_cryptography_38.0.1_cp36_abi3_macosx_10_10_universal2",
        package_name = "cryptography",
        package_version = "38.0.1",
        filename = "cryptography-38.0.1-cp36-abi3-macosx_10_10_universal2.whl",
        sha256 = "10d1f29d6292fc95acb597bacefd5b9e812099d75a6469004fd38ba5471a977f",
        index = "https://pypi.org",
    )

    maybe(
        pypi_file,
        name = "example_lock_wheel_cryptography_38.0.1_cp36_abi3_macosx_10_10_x86_64",
        package_name = "cryptography",
        package_version = "38.0.1",
        filename = "cryptography-38.0.1-cp36-abi3-macosx_10_10_x86_64.whl",
        sha256 = "3fc26e22840b77326a764ceb5f02ca2d342305fba08f002a8c1f139540cdfaad",
        index = "https://pypi.org",
    )

    maybe(
        pypi_file,
        name = "example_lock_wheel_cryptography_38.0.1_cp36_abi3_manylinux_2_17_x86_64.manylinux2014_x86_64",
        package_name = "cryptography",
        package_version = "38.0.1",
        filename = "cryptography-38.0.1-cp36-abi3-manylinux_2_17_x86_64.manylinux2014_x86_64.whl",
        sha256 = "ca9f6784ea96b55ff41708b92c3f6aeaebde4c560308e5fbbd3173fbc466e94e",
        index = "https://pypi.org",
    )

    maybe(
        pypi_file,
        name = "example_lock_wheel_cython_0.29.32_cp39_cp39_manylinux_2_17_x86_64.manylinux2014_x86_64.manylinux_2_24_x86_64",
        package_name = "cython",
        package_version = "0.29.32",
        filename = "Cython-0.29.32-cp39-cp39-manylinux_2_17_x86_64.manylinux2014_x86_64.manylinux_2_24_x86_64.whl",
        sha256 = "f3fd44cc362eee8ae569025f070d56208908916794b6ab21e139cea56470a2b3",
        index = "https://pypi.org",
    )

    maybe(
        pypi_file,
        name = "example_lock_wheel_cython_0.29.32_py2.py3_none_any",
        package_name = "cython",
        package_version = "0.29.32",
        filename = "Cython-0.29.32-py2.py3-none-any.whl",
        sha256 = "eeb475eb6f0ccf6c039035eb4f0f928eb53ead88777e0a760eccb140ad90930b",
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
        name = "example_lock_wheel_docker_6.0.0_py3_none_any",
        package_name = "docker",
        package_version = "6.0.0",
        filename = "docker-6.0.0-py3-none-any.whl",
        sha256 = "6e06ee8eca46cd88733df09b6b80c24a1a556bc5cb1e1ae54b2c239886d245cf",
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
        name = "example_lock_wheel_executing_1.0.0_py2.py3_none_any",
        package_name = "executing",
        package_version = "1.0.0",
        filename = "executing-1.0.0-py2.py3-none-any.whl",
        sha256 = "550d581b497228b572235e633599133eeee67073c65914ca346100ad56775349",
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
        name = "example_lock_wheel_graphql_core_3.2.1_py3_none_any",
        package_name = "graphql-core",
        package_version = "3.2.1",
        filename = "graphql_core-3.2.1-py3-none-any.whl",
        sha256 = "f83c658e4968998eed1923a2e3e3eddd347e005ac0315fbb7ca4d70ea9156323",
        index = "https://pypi.org",
    )

    maybe(
        pypi_file,
        name = "example_lock_wheel_greenlet_1.1.3_cp39_cp39_macosx_10_15_x86_64",
        package_name = "greenlet",
        package_version = "1.1.3",
        filename = "greenlet-1.1.3-cp39-cp39-macosx_10_15_x86_64.whl",
        sha256 = "cbc1eb55342cbac8f7ec159088d54e2cfdd5ddf61c87b8bbe682d113789331b2",
        index = "https://pypi.org",
    )

    maybe(
        pypi_file,
        name = "example_lock_wheel_greenlet_1.1.3_cp39_cp39_manylinux_2_17_x86_64.manylinux2014_x86_64",
        package_name = "greenlet",
        package_version = "1.1.3",
        filename = "greenlet-1.1.3-cp39-cp39-manylinux_2_17_x86_64.manylinux2014_x86_64.whl",
        sha256 = "2fb0aa7f6996879551fd67461d5d3ab0c3c0245da98be90c89fcb7a18d437403",
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
        name = "example_lock_wheel_importlib_metadata_4.12.0_py3_none_any",
        package_name = "importlib-metadata",
        package_version = "4.12.0",
        filename = "importlib_metadata-4.12.0-py3-none-any.whl",
        sha256 = "7401a975809ea1fdc658c3aa4f78cc2195a0e019c5cbc4c06122884e9ae80c23",
        index = "https://pypi.org",
    )

    maybe(
        pypi_file,
        name = "example_lock_wheel_ipython_8.5.0_py3_none_any",
        package_name = "ipython",
        package_version = "8.5.0",
        filename = "ipython-8.5.0-py3-none-any.whl",
        sha256 = "6f090e29ab8ef8643e521763a4f1f39dc3914db643122b1e9d3328ff2e43ada2",
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
        name = "example_lock_wheel_jaraco.classes_3.2.2_py3_none_any",
        package_name = "jaraco-classes",
        package_version = "3.2.2",
        filename = "jaraco.classes-3.2.2-py3-none-any.whl",
        sha256 = "e6ef6fd3fcf4579a7a019d87d1e56a883f4e4c35cfe925f86731abc58804e647",
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
        name = "example_lock_wheel_keyring_23.9.1_py3_none_any",
        package_name = "keyring",
        package_version = "23.9.1",
        filename = "keyring-23.9.1-py3-none-any.whl",
        sha256 = "3565b9e4ea004c96e158d2d332a49f466733d565bb24157a60fd2e49f41a0fd1",
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
        name = "example_lock_wheel_matplotlib_inline_0.1.6_py3_none_any",
        package_name = "matplotlib-inline",
        package_version = "0.1.6",
        filename = "matplotlib_inline-0.1.6-py3-none-any.whl",
        sha256 = "f1f41aab5328aa5aaea9b16d083b128102f8712542f819fe7e6a420ff581b311",
        index = "https://pypi.org",
    )

    maybe(
        pypi_file,
        name = "example_lock_wheel_more_itertools_8.14.0_py3_none_any",
        package_name = "more-itertools",
        package_version = "8.14.0",
        filename = "more_itertools-8.14.0-py3-none-any.whl",
        sha256 = "1bc4f91ee5b1b31ac7ceacc17c09befe6a40a503907baf9c839c229b5095cfd2",
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
        name = "example_lock_wheel_networkx_2.8.6_py3_none_any",
        package_name = "networkx",
        package_version = "2.8.6",
        filename = "networkx-2.8.6-py3-none-any.whl",
        sha256 = "2a30822761f34d56b9a370d96a4bf4827a535f5591a4078a453425caeba0c5bb",
        index = "https://pypi.org",
    )

    maybe(
        pypi_file,
        name = "example_lock_wheel_numpy_1.22.3_cp39_cp39_macosx_10_14_x86_64",
        package_name = "numpy",
        package_version = "1.22.3",
        filename = "numpy-1.22.3-cp39-cp39-macosx_10_14_x86_64.whl",
        sha256 = "2c10a93606e0b4b95c9b04b77dc349b398fdfbda382d2a39ba5a822f669a0123",
        index = "https://pypi.org",
    )

    maybe(
        pypi_file,
        name = "example_lock_wheel_numpy_1.22.3_cp39_cp39_macosx_11_0_arm64",
        package_name = "numpy",
        package_version = "1.22.3",
        filename = "numpy-1.22.3-cp39-cp39-macosx_11_0_arm64.whl",
        sha256 = "fade0d4f4d292b6f39951b6836d7a3c7ef5b2347f3c420cd9820a1d90d794802",
        index = "https://pypi.org",
    )

    maybe(
        pypi_file,
        name = "example_lock_wheel_numpy_1.22.3_cp39_cp39_manylinux_2_17_x86_64.manylinux2014_x86_64",
        package_name = "numpy",
        package_version = "1.22.3",
        filename = "numpy-1.22.3-cp39-cp39-manylinux_2_17_x86_64.manylinux2014_x86_64.whl",
        sha256 = "97098b95aa4e418529099c26558eeb8486e66bd1e53a6b606d684d0c3616b168",
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
        name = "example_lock_wheel_packaging_21.3_py3_none_any",
        package_name = "packaging",
        package_version = "21.3",
        filename = "packaging-21.3-py3-none-any.whl",
        sha256 = "ef103e05f519cdc783ae24ea4e2e0f508a9c99b2d4969652eed6a2e1ea5bd522",
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
        name = "example_lock_wheel_prompt_toolkit_3.0.31_py3_none_any",
        package_name = "prompt-toolkit",
        package_version = "3.0.31",
        filename = "prompt_toolkit-3.0.31-py3-none-any.whl",
        sha256 = "9696f386133df0fc8ca5af4895afe5d78f5fcfe5258111c2a79a1c3e41ffa96d",
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
        name = "example_lock_wheel_pygments_2.13.0_py3_none_any",
        package_name = "pygments",
        package_version = "2.13.0",
        filename = "Pygments-2.13.0-py3-none-any.whl",
        sha256 = "f643f331ab57ba3c9d89212ee4a2dabc6e94f117cf4eefde99a0574720d14c42",
        index = "https://pypi.org",
    )

    maybe(
        pypi_file,
        name = "example_lock_wheel_pyparsing_3.0.9_py3_none_any",
        package_name = "pyparsing",
        package_version = "3.0.9",
        filename = "pyparsing-3.0.9-py3-none-any.whl",
        sha256 = "5026bae9a10eeaefb61dab2f09052b9f4307d44aee4eda64b309723d8d206bbc",
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
        name = "example_lock_wheel_pytz_2022.2.1_py2.py3_none_any",
        package_name = "pytz",
        package_version = "2022.2.1",
        filename = "pytz-2022.2.1-py2.py3-none-any.whl",
        sha256 = "220f481bdafa09c3955dfbdddb7b57780e9a94f5127e35456a48589b9e0c0197",
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
        name = "example_lock_wheel_requests_2.28.1_py3_none_any",
        package_name = "requests",
        package_version = "2.28.1",
        filename = "requests-2.28.1-py3-none-any.whl",
        sha256 = "8fefa2a1a1365bf5520aac41836fbee479da67864514bdb821f31ce07ce65349",
        index = "https://pypi.org",
    )

    maybe(
        pypi_file,
        name = "example_lock_wheel_responses_0.21.0_py3_none_any",
        package_name = "responses",
        package_version = "0.21.0",
        filename = "responses-0.21.0-py3-none-any.whl",
        sha256 = "2dcc863ba63963c0c3d9ee3fa9507cbe36b7d7b0fccb4f0bdfd9e96c539b1487",
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
        name = "example_lock_wheel_sqlalchemy_1.4.41_cp39_cp39_macosx_10_15_x86_64",
        package_name = "sqlalchemy",
        package_version = "1.4.41",
        filename = "SQLAlchemy-1.4.41-cp39-cp39-macosx_10_15_x86_64.whl",
        sha256 = "199a73c31ac8ea59937cc0bf3dfc04392e81afe2ec8a74f26f489d268867846c",
        index = "https://pypi.org",
    )

    maybe(
        pypi_file,
        name = "example_lock_wheel_sqlalchemy_1.4.41_cp39_cp39_manylinux_2_5_x86_64.manylinux1_x86_64.manylinux_2_17_x86_64.manylinux2014_x86_64",
        package_name = "sqlalchemy",
        package_version = "1.4.41",
        filename = "SQLAlchemy-1.4.41-cp39-cp39-manylinux_2_5_x86_64.manylinux1_x86_64.manylinux_2_17_x86_64.manylinux2014_x86_64.whl",
        sha256 = "2307495d9e0ea00d0c726be97a5b96615035854972cc538f6e7eaed23a35886c",
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
        name = "example_lock_wheel_stack_data_0.5.0_py3_none_any",
        package_name = "stack-data",
        package_version = "0.5.0",
        filename = "stack_data-0.5.0-py3-none-any.whl",
        sha256 = "66d2ebd3d7f29047612ead465b6cae5371006a71f45037c7e2507d01367bce3b",
        index = "https://pypi.org",
    )

    maybe(
        pypi_file,
        name = "example_lock_wheel_traitlets_5.4.0_py3_none_any",
        package_name = "traitlets",
        package_version = "5.4.0",
        filename = "traitlets-5.4.0-py3-none-any.whl",
        sha256 = "93663cc8236093d48150e2af5e2ed30fc7904a11a6195e21bab0408af4e6d6c8",
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
        name = "example_lock_wheel_urllib3_1.26.12_py2.py3_none_any",
        package_name = "urllib3",
        package_version = "1.26.12",
        filename = "urllib3-1.26.12-py2.py3-none-any.whl",
        sha256 = "b930dd878d5a8afb066a637fbb35144fe7901e3b209d1cd4f524bd0e9deee997",
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
        name = "example_lock_wheel_websocket_client_1.4.1_py3_none_any",
        package_name = "websocket-client",
        package_version = "1.4.1",
        filename = "websocket_client-1.4.1-py3-none-any.whl",
        sha256 = "398909eb7e261f44b8f4bd474785b6ec5f5b499d4953342fe9755e01ef624090",
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
        name = "example_lock_wheel_zipp_3.8.1_py3_none_any",
        package_name = "zipp",
        package_version = "3.8.1",
        filename = "zipp-3.8.1-py3-none-any.whl",
        sha256 = "47c40d7fe183a6f21403a199b3e4192cca5774656965b0a4988ad2f8feb5f009",
        index = "https://pypi.org",
    )

