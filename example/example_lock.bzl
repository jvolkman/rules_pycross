load("@bazel_tools//tools/build_defs/repo:http.bzl", "http_file")
load("@bazel_tools//tools/build_defs/repo:utils.bzl", "maybe")
load("@aspect_rules_py//py:defs.bzl", "py_wheel", "py_library")
load("@jvolkman_rules_pycross//pycross:defs.bzl", "pycross_wheel_build")

PINS = {
    "appnope": "appnope_0.1.3",
    "asttokens": "asttokens_2.0.5",
    "attrs": "attrs_21.4.0",
    "aws-sam-translator": "aws_sam_translator_1.45.0",
    "aws-xray-sdk": "aws_xray_sdk_2.9.0",
    "backcall": "backcall_0.2.0",
    "boto3": "boto3_1.22.3",
    "botocore": "botocore_1.25.3",
    "certifi": "certifi_2021.10.8",
    "cffi": "cffi_1.15.0",
    "cfn-lint": "cfn_lint_0.59.0",
    "charset-normalizer": "charset_normalizer_2.0.12",
    "click": "click_8.1.3",
    "cognitojwt": "cognitojwt_1.4.1",
    "cryptography": "cryptography_37.0.1",
    "decorator": "decorator_5.1.1",
    "docker": "docker_5.0.3",
    "ecdsa": "ecdsa_0.17.0",
    "executing": "executing_0.8.3",
    "flask": "flask_2.1.2",
    "flask-cors": "flask_cors_3.0.10",
    "future": "future_0.18.2",
    "graphql-core": "graphql_core_3.2.1",
    "greenlet": "greenlet_1.1.2",
    "idna": "idna_3.3",
    "importlib-metadata": "importlib_metadata_4.11.3",
    "ipython": "ipython_8.2.0",
    "itsdangerous": "itsdangerous_2.1.2",
    "jedi": "jedi_0.18.1",
    "jinja2": "jinja2_3.1.2",
    "jmespath": "jmespath_1.0.0",
    "jschema-to-python": "jschema_to_python_1.2.3",
    "jsondiff": "jsondiff_2.0.0",
    "jsonpatch": "jsonpatch_1.32",
    "jsonpickle": "jsonpickle_2.1.0",
    "jsonpointer": "jsonpointer_2.3",
    "jsonschema": "jsonschema_3.2.0",
    "junit-xml": "junit_xml_1.9",
    "markupsafe": "markupsafe_2.1.1",
    "matplotlib-inline": "matplotlib_inline_0.1.3",
    "moto": "moto_3.1.1",
    "networkx": "networkx_2.8",
    "parso": "parso_0.8.3",
    "pbr": "pbr_5.8.1",
    "pexpect": "pexpect_4.8.0",
    "pickleshare": "pickleshare_0.7.5",
    "prompt-toolkit": "prompt_toolkit_3.0.29",
    "ptyprocess": "ptyprocess_0.7.0",
    "pure-eval": "pure_eval_0.2.2",
    "pyasn1": "pyasn1_0.4.8",
    "pycparser": "pycparser_2.21",
    "pygments": "pygments_2.12.0",
    "pyrsistent": "pyrsistent_0.18.1",
    "python-dateutil": "python_dateutil_2.8.2",
    "python-jose": "python_jose_3.1.0",
    "pytz": "pytz_2022.1",
    "pyyaml": "pyyaml_6.0",
    "requests": "requests_2.27.1",
    "responses": "responses_0.20.0",
    "rsa": "rsa_4.8",
    "s3transfer": "s3transfer_0.5.2",
    "sarif-om": "sarif_om_1.0.4",
    "six": "six_1.16.0",
    "sqlalchemy": "sqlalchemy_1.4.36",
    "sqlalchemy-utils": "sqlalchemy_utils_0.38.2",
    "sshpubkeys": "sshpubkeys_3.3.1",
    "stack-data": "stack_data_0.2.0",
    "traitlets": "traitlets_5.1.1",
    "urllib3": "urllib3_1.26.9",
    "wcwidth": "wcwidth_0.2.5",
    "websocket-client": "websocket_client_1.3.2",
    "werkzeug": "werkzeug_2.1.2",
    "wrapt": "wrapt_1.14.0",
    "xmltodict": "xmltodict_0.12.0",
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

    py_wheel(
        name = "appnope_0.1.3_whl",
        src = "@example_lock_wheel_appnope_0.1.3_py2.py3_none_any//file",
    )

    py_library(
        name = "appnope_0.1.3",
        deps = [":appnope_0.1.3_whl"],
    )

    _asttokens_2_0_5_deps = [
        ":six_1.16.0",
    ]

    py_wheel(
        name = "asttokens_2.0.5_whl",
        src = "@example_lock_wheel_asttokens_2.0.5_py2.py3_none_any//file",
    )

    py_library(
        name = "asttokens_2.0.5",
        deps = [":asttokens_2.0.5_whl"] + _asttokens_2_0_5_deps,
    )

    py_wheel(
        name = "attrs_21.4.0_whl",
        src = "@example_lock_wheel_attrs_21.4.0_py2.py3_none_any//file",
    )

    py_library(
        name = "attrs_21.4.0",
        deps = [":attrs_21.4.0_whl"],
    )

    _aws_sam_translator_1_45_0_deps = [
        ":boto3_1.22.3",
        ":jsonschema_3.2.0",
    ]

    py_wheel(
        name = "aws_sam_translator_1.45.0_whl",
        src = "@example_lock_wheel_aws_sam_translator_1.45.0_py3_none_any//file",
    )

    py_library(
        name = "aws_sam_translator_1.45.0",
        deps = [":aws_sam_translator_1.45.0_whl"] + _aws_sam_translator_1_45_0_deps,
    )

    _aws_xray_sdk_2_9_0_deps = [
        ":botocore_1.25.3",
        ":future_0.18.2",
        ":wrapt_1.14.0",
    ]

    py_wheel(
        name = "aws_xray_sdk_2.9.0_whl",
        src = "@example_lock_wheel_aws_xray_sdk_2.9.0_py2.py3_none_any//file",
    )

    py_library(
        name = "aws_xray_sdk_2.9.0",
        deps = [":aws_xray_sdk_2.9.0_whl"] + _aws_xray_sdk_2_9_0_deps,
    )

    py_wheel(
        name = "backcall_0.2.0_whl",
        src = "@example_lock_wheel_backcall_0.2.0_py2.py3_none_any//file",
    )

    py_library(
        name = "backcall_0.2.0",
        deps = [":backcall_0.2.0_whl"],
    )

    _boto3_1_22_3_deps = [
        ":botocore_1.25.3",
        ":jmespath_1.0.0",
        ":s3transfer_0.5.2",
    ]

    py_wheel(
        name = "boto3_1.22.3_whl",
        src = "@example_lock_wheel_boto3_1.22.3_py3_none_any//file",
    )

    py_library(
        name = "boto3_1.22.3",
        deps = [":boto3_1.22.3_whl"] + _boto3_1_22_3_deps,
    )

    _botocore_1_25_3_deps = [
        ":jmespath_1.0.0",
        ":python_dateutil_2.8.2",
        ":urllib3_1.26.9",
    ]

    py_wheel(
        name = "botocore_1.25.3_whl",
        src = "@example_lock_wheel_botocore_1.25.3_py3_none_any//file",
    )

    py_library(
        name = "botocore_1.25.3",
        deps = [":botocore_1.25.3_whl"] + _botocore_1_25_3_deps,
    )

    py_wheel(
        name = "certifi_2021.10.8_whl",
        src = "@example_lock_wheel_certifi_2021.10.8_py2.py3_none_any//file",
    )

    py_library(
        name = "certifi_2021.10.8",
        deps = [":certifi_2021.10.8_whl"],
    )

    _cffi_1_15_0_deps = [
        ":pycparser_2.21",
    ]

    py_wheel(
        name = "cffi_1.15.0_whl",
        src = select({
            ":_env_python_darwin_arm64": "@example_lock_wheel_cffi_1.15.0_cp39_cp39_macosx_11_0_arm64//file",
            ":_env_python_darwin_x86_64": "@example_lock_wheel_cffi_1.15.0_cp39_cp39_macosx_10_9_x86_64//file",
            ":_env_python_linux_x86_64": "@example_lock_wheel_cffi_1.15.0_cp39_cp39_manylinux_2_12_x86_64.manylinux2010_x86_64//file",
        }),
    )

    py_library(
        name = "cffi_1.15.0",
        deps = [":cffi_1.15.0_whl"] + _cffi_1_15_0_deps,
    )

    _cfn_lint_0_59_0_deps = [
        ":aws_sam_translator_1.45.0",
        ":jschema_to_python_1.2.3",
        ":jsonpatch_1.32",
        ":jsonschema_3.2.0",
        ":junit_xml_1.9",
        ":networkx_2.8",
        ":pyyaml_6.0",
        ":sarif_om_1.0.4",
    ]

    py_wheel(
        name = "cfn_lint_0.59.0_whl",
        src = "@example_lock_wheel_cfn_lint_0.59.0_py3_none_any//file",
    )

    py_library(
        name = "cfn_lint_0.59.0",
        deps = [":cfn_lint_0.59.0_whl"] + _cfn_lint_0_59_0_deps,
    )

    py_wheel(
        name = "charset_normalizer_2.0.12_whl",
        src = "@example_lock_wheel_charset_normalizer_2.0.12_py3_none_any//file",
    )

    py_library(
        name = "charset_normalizer_2.0.12",
        deps = [":charset_normalizer_2.0.12_whl"],
    )

    py_wheel(
        name = "click_8.1.3_whl",
        src = "@example_lock_wheel_click_8.1.3_py3_none_any//file",
    )

    py_library(
        name = "click_8.1.3",
        deps = [":click_8.1.3_whl"],
    )

    _cognitojwt_1_4_1_deps = [
        ":python_jose_3.1.0",
    ]

    py_wheel(
        name = "cognitojwt_1.4.1_whl",
        src = "@example_lock_wheel_cognitojwt_1.4.1_py3_none_any//file",
    )

    py_library(
        name = "cognitojwt_1.4.1",
        deps = [":cognitojwt_1.4.1_whl"] + _cognitojwt_1_4_1_deps,
    )

    _cryptography_37_0_1_deps = [
        ":cffi_1.15.0",
    ]

    py_wheel(
        name = "cryptography_37.0.1_whl",
        src = select({
            ":_env_python_darwin_arm64": "@example_lock_wheel_cryptography_37.0.1_cp36_abi3_macosx_10_10_universal2//file",
            ":_env_python_darwin_x86_64": "@example_lock_wheel_cryptography_37.0.1_cp36_abi3_macosx_10_10_x86_64//file",
            ":_env_python_linux_x86_64": "@example_lock_wheel_cryptography_37.0.1_cp36_abi3_manylinux_2_17_x86_64.manylinux2014_x86_64//file",
        }),
    )

    py_library(
        name = "cryptography_37.0.1",
        deps = [":cryptography_37.0.1_whl"] + _cryptography_37_0_1_deps,
    )

    py_wheel(
        name = "decorator_5.1.1_whl",
        src = "@example_lock_wheel_decorator_5.1.1_py3_none_any//file",
    )

    py_library(
        name = "decorator_5.1.1",
        deps = [":decorator_5.1.1_whl"],
    )

    _docker_5_0_3_deps = [
        ":requests_2.27.1",
        ":websocket_client_1.3.2",
    ]

    py_wheel(
        name = "docker_5.0.3_whl",
        src = "@example_lock_wheel_docker_5.0.3_py2.py3_none_any//file",
    )

    py_library(
        name = "docker_5.0.3",
        deps = [":docker_5.0.3_whl"] + _docker_5_0_3_deps,
    )

    _ecdsa_0_17_0_deps = [
        ":six_1.16.0",
    ]

    py_wheel(
        name = "ecdsa_0.17.0_whl",
        src = "@example_lock_wheel_ecdsa_0.17.0_py2.py3_none_any//file",
    )

    py_library(
        name = "ecdsa_0.17.0",
        deps = [":ecdsa_0.17.0_whl"] + _ecdsa_0_17_0_deps,
    )

    py_wheel(
        name = "executing_0.8.3_whl",
        src = "@example_lock_wheel_executing_0.8.3_py2.py3_none_any//file",
    )

    py_library(
        name = "executing_0.8.3",
        deps = [":executing_0.8.3_whl"],
    )

    _flask_2_1_2_deps = [
        ":click_8.1.3",
        ":importlib_metadata_4.11.3",
        ":itsdangerous_2.1.2",
        ":jinja2_3.1.2",
        ":werkzeug_2.1.2",
    ]

    py_wheel(
        name = "flask_2.1.2_whl",
        src = "@example_lock_wheel_flask_2.1.2_py3_none_any//file",
    )

    py_library(
        name = "flask_2.1.2",
        deps = [":flask_2.1.2_whl"] + _flask_2_1_2_deps,
    )

    _flask_cors_3_0_10_deps = [
        ":flask_2.1.2",
        ":six_1.16.0",
    ]

    py_wheel(
        name = "flask_cors_3.0.10_whl",
        src = "@example_lock_wheel_flask_cors_3.0.10_py2.py3_none_any//file",
    )

    py_library(
        name = "flask_cors_3.0.10",
        deps = [":flask_cors_3.0.10_whl"] + _flask_cors_3_0_10_deps,
    )

    py_wheel(
        name = "future_0.18.2_whl",
        src = "@//deps:overridden_future_0.18.2",
    )

    py_library(
        name = "future_0.18.2",
        deps = [":future_0.18.2_whl"],
    )

    py_wheel(
        name = "graphql_core_3.2.1_whl",
        src = "@example_lock_wheel_graphql_core_3.2.1_py3_none_any//file",
    )

    py_library(
        name = "graphql_core_3.2.1",
        deps = [":graphql_core_3.2.1_whl"],
    )

    pycross_wheel_build(
        name = "_build_greenlet_1.1.2",
        sdist = "@example_lock_sdist_greenlet_1.1.2//file",
        tags = ["manual"],
    )

    py_wheel(
        name = "greenlet_1.1.2_whl",
        src = select({
            ":_env_python_darwin_arm64": ":_build_greenlet_1.1.2",
            ":_env_python_darwin_x86_64": "@example_lock_wheel_greenlet_1.1.2_cp39_cp39_macosx_10_14_x86_64//file",
            ":_env_python_linux_x86_64": "@example_lock_wheel_greenlet_1.1.2_cp39_cp39_manylinux_2_17_x86_64.manylinux2014_x86_64//file",
        }),
    )

    py_library(
        name = "greenlet_1.1.2",
        deps = [":greenlet_1.1.2_whl"],
    )

    py_wheel(
        name = "idna_3.3_whl",
        src = "@example_lock_wheel_idna_3.3_py3_none_any//file",
    )

    py_library(
        name = "idna_3.3",
        deps = [":idna_3.3_whl"],
    )

    _importlib_metadata_4_11_3_deps = [
        ":zipp_3.8.0",
    ]

    py_wheel(
        name = "importlib_metadata_4.11.3_whl",
        src = "@example_lock_wheel_importlib_metadata_4.11.3_py3_none_any//file",
    )

    py_library(
        name = "importlib_metadata_4.11.3",
        deps = [":importlib_metadata_4.11.3_whl"] + _importlib_metadata_4_11_3_deps,
    )

    _ipython_8_2_0_deps = [
        ":backcall_0.2.0",
        ":decorator_5.1.1",
        ":jedi_0.18.1",
        ":matplotlib_inline_0.1.3",
        ":pexpect_4.8.0",
        ":pickleshare_0.7.5",
        ":prompt_toolkit_3.0.29",
        ":pygments_2.12.0",
        ":stack_data_0.2.0",
        ":traitlets_5.1.1",
    ] + select({
        ":_env_python_darwin_arm64": [
            ":appnope_0.1.3",
        ],
        ":_env_python_darwin_x86_64": [
            ":appnope_0.1.3",
        ],
        "//conditions:default": [],
    })

    py_wheel(
        name = "ipython_8.2.0_whl",
        src = "@example_lock_wheel_ipython_8.2.0_py3_none_any//file",
    )

    py_library(
        name = "ipython_8.2.0",
        deps = [":ipython_8.2.0_whl"] + _ipython_8_2_0_deps,
    )

    py_wheel(
        name = "itsdangerous_2.1.2_whl",
        src = "@example_lock_wheel_itsdangerous_2.1.2_py3_none_any//file",
    )

    py_library(
        name = "itsdangerous_2.1.2",
        deps = [":itsdangerous_2.1.2_whl"],
    )

    _jedi_0_18_1_deps = [
        ":parso_0.8.3",
    ]

    py_wheel(
        name = "jedi_0.18.1_whl",
        src = "@example_lock_wheel_jedi_0.18.1_py2.py3_none_any//file",
    )

    py_library(
        name = "jedi_0.18.1",
        deps = [":jedi_0.18.1_whl"] + _jedi_0_18_1_deps,
    )

    _jinja2_3_1_2_deps = [
        ":markupsafe_2.1.1",
    ]

    py_wheel(
        name = "jinja2_3.1.2_whl",
        src = "@example_lock_wheel_jinja2_3.1.2_py3_none_any//file",
    )

    py_library(
        name = "jinja2_3.1.2",
        deps = [":jinja2_3.1.2_whl"] + _jinja2_3_1_2_deps,
    )

    py_wheel(
        name = "jmespath_1.0.0_whl",
        src = "@example_lock_wheel_jmespath_1.0.0_py3_none_any//file",
    )

    py_library(
        name = "jmespath_1.0.0",
        deps = [":jmespath_1.0.0_whl"],
    )

    _jschema_to_python_1_2_3_deps = [
        ":attrs_21.4.0",
        ":jsonpickle_2.1.0",
        ":pbr_5.8.1",
    ]

    py_wheel(
        name = "jschema_to_python_1.2.3_whl",
        src = "@example_lock_wheel_jschema_to_python_1.2.3_py3_none_any//file",
    )

    py_library(
        name = "jschema_to_python_1.2.3",
        deps = [":jschema_to_python_1.2.3_whl"] + _jschema_to_python_1_2_3_deps,
    )

    py_wheel(
        name = "jsondiff_2.0.0_whl",
        src = "@example_lock_wheel_jsondiff_2.0.0_py3_none_any//file",
    )

    py_library(
        name = "jsondiff_2.0.0",
        deps = [":jsondiff_2.0.0_whl"],
    )

    _jsonpatch_1_32_deps = [
        ":jsonpointer_2.3",
    ]

    py_wheel(
        name = "jsonpatch_1.32_whl",
        src = "@example_lock_wheel_jsonpatch_1.32_py2.py3_none_any//file",
    )

    py_library(
        name = "jsonpatch_1.32",
        deps = [":jsonpatch_1.32_whl"] + _jsonpatch_1_32_deps,
    )

    py_wheel(
        name = "jsonpickle_2.1.0_whl",
        src = "@example_lock_wheel_jsonpickle_2.1.0_py2.py3_none_any//file",
    )

    py_library(
        name = "jsonpickle_2.1.0",
        deps = [":jsonpickle_2.1.0_whl"],
    )

    py_wheel(
        name = "jsonpointer_2.3_whl",
        src = "@example_lock_wheel_jsonpointer_2.3_py2.py3_none_any//file",
    )

    py_library(
        name = "jsonpointer_2.3",
        deps = [":jsonpointer_2.3_whl"],
    )

    _jsonschema_3_2_0_deps = [
        ":attrs_21.4.0",
        ":pyrsistent_0.18.1",
        ":six_1.16.0",
    ]

    py_wheel(
        name = "jsonschema_3.2.0_whl",
        src = "@example_lock_wheel_jsonschema_3.2.0_py2.py3_none_any//file",
    )

    py_library(
        name = "jsonschema_3.2.0",
        deps = [":jsonschema_3.2.0_whl"] + _jsonschema_3_2_0_deps,
    )

    _junit_xml_1_9_deps = [
        ":six_1.16.0",
    ]

    py_wheel(
        name = "junit_xml_1.9_whl",
        src = "@example_lock_wheel_junit_xml_1.9_py2.py3_none_any//file",
    )

    py_library(
        name = "junit_xml_1.9",
        deps = [":junit_xml_1.9_whl"] + _junit_xml_1_9_deps,
    )

    py_wheel(
        name = "markupsafe_2.1.1_whl",
        src = select({
            ":_env_python_darwin_arm64": "@example_lock_wheel_markupsafe_2.1.1_cp39_cp39_macosx_10_9_universal2//file",
            ":_env_python_darwin_x86_64": "@example_lock_wheel_markupsafe_2.1.1_cp39_cp39_macosx_10_9_x86_64//file",
            ":_env_python_linux_x86_64": "@example_lock_wheel_markupsafe_2.1.1_cp39_cp39_manylinux_2_17_x86_64.manylinux2014_x86_64//file",
        }),
    )

    py_library(
        name = "markupsafe_2.1.1",
        deps = [":markupsafe_2.1.1_whl"],
    )

    _matplotlib_inline_0_1_3_deps = [
        ":traitlets_5.1.1",
    ]

    py_wheel(
        name = "matplotlib_inline_0.1.3_whl",
        src = "@example_lock_wheel_matplotlib_inline_0.1.3_py3_none_any//file",
    )

    py_library(
        name = "matplotlib_inline_0.1.3",
        deps = [":matplotlib_inline_0.1.3_whl"] + _matplotlib_inline_0_1_3_deps,
    )

    _moto_3_1_1_deps = [
        ":aws_xray_sdk_2.9.0",
        ":boto3_1.22.3",
        ":botocore_1.25.3",
        ":cfn_lint_0.59.0",
        ":cryptography_37.0.1",
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
        ":sshpubkeys_3.3.1",
        ":werkzeug_2.1.2",
        ":xmltodict_0.12.0",
    ]

    py_wheel(
        name = "moto_3.1.1_whl",
        src = "@example_lock_wheel_moto_3.1.1_py2.py3_none_any//file",
    )

    py_library(
        name = "moto_3.1.1",
        deps = [":moto_3.1.1_whl"] + _moto_3_1_1_deps,
    )

    py_wheel(
        name = "networkx_2.8_whl",
        src = "@example_lock_wheel_networkx_2.8_py3_none_any//file",
    )

    py_library(
        name = "networkx_2.8",
        deps = [":networkx_2.8_whl"],
    )

    py_wheel(
        name = "parso_0.8.3_whl",
        src = "@example_lock_wheel_parso_0.8.3_py2.py3_none_any//file",
    )

    py_library(
        name = "parso_0.8.3",
        deps = [":parso_0.8.3_whl"],
    )

    pycross_wheel_build(
        name = "_build_pbr_5.8.1",
        sdist = "@example_lock_sdist_pbr_5.8.1//file",
        tags = ["manual"],
    )

    py_wheel(
        name = "pbr_5.8.1_whl",
        src = ":_build_pbr_5.8.1",
    )

    py_library(
        name = "pbr_5.8.1",
        deps = [":pbr_5.8.1_whl"],
    )

    _pexpect_4_8_0_deps = [
        ":ptyprocess_0.7.0",
    ]

    py_wheel(
        name = "pexpect_4.8.0_whl",
        src = "@example_lock_wheel_pexpect_4.8.0_py2.py3_none_any//file",
    )

    py_library(
        name = "pexpect_4.8.0",
        deps = [":pexpect_4.8.0_whl"] + _pexpect_4_8_0_deps,
    )

    py_wheel(
        name = "pickleshare_0.7.5_whl",
        src = "@example_lock_wheel_pickleshare_0.7.5_py2.py3_none_any//file",
    )

    py_library(
        name = "pickleshare_0.7.5",
        deps = [":pickleshare_0.7.5_whl"],
    )

    _prompt_toolkit_3_0_29_deps = [
        ":wcwidth_0.2.5",
    ]

    py_wheel(
        name = "prompt_toolkit_3.0.29_whl",
        src = "@example_lock_wheel_prompt_toolkit_3.0.29_py3_none_any//file",
    )

    py_library(
        name = "prompt_toolkit_3.0.29",
        deps = [":prompt_toolkit_3.0.29_whl"] + _prompt_toolkit_3_0_29_deps,
    )

    py_wheel(
        name = "ptyprocess_0.7.0_whl",
        src = "@example_lock_wheel_ptyprocess_0.7.0_py2.py3_none_any//file",
    )

    py_library(
        name = "ptyprocess_0.7.0",
        deps = [":ptyprocess_0.7.0_whl"],
    )

    py_wheel(
        name = "pure_eval_0.2.2_whl",
        src = "@example_lock_wheel_pure_eval_0.2.2_py3_none_any//file",
    )

    py_library(
        name = "pure_eval_0.2.2",
        deps = [":pure_eval_0.2.2_whl"],
    )

    py_wheel(
        name = "pyasn1_0.4.8_whl",
        src = "@example_lock_wheel_pyasn1_0.4.8_py2.py3_none_any//file",
    )

    py_library(
        name = "pyasn1_0.4.8",
        deps = [":pyasn1_0.4.8_whl"],
    )

    py_wheel(
        name = "pycparser_2.21_whl",
        src = "@example_lock_wheel_pycparser_2.21_py2.py3_none_any//file",
    )

    py_library(
        name = "pycparser_2.21",
        deps = [":pycparser_2.21_whl"],
    )

    py_wheel(
        name = "pygments_2.12.0_whl",
        src = "@example_lock_wheel_pygments_2.12.0_py3_none_any//file",
    )

    py_library(
        name = "pygments_2.12.0",
        deps = [":pygments_2.12.0_whl"],
    )

    py_wheel(
        name = "pyrsistent_0.18.1_whl",
        src = select({
            ":_env_python_darwin_arm64": "@example_lock_wheel_pyrsistent_0.18.1_cp39_cp39_macosx_10_9_universal2//file",
            ":_env_python_darwin_x86_64": "@example_lock_wheel_pyrsistent_0.18.1_cp39_cp39_macosx_10_9_universal2//file",
            ":_env_python_linux_x86_64": "@example_lock_wheel_pyrsistent_0.18.1_cp39_cp39_manylinux_2_17_x86_64.manylinux2014_x86_64//file",
        }),
    )

    py_library(
        name = "pyrsistent_0.18.1",
        deps = [":pyrsistent_0.18.1_whl"],
    )

    _python_dateutil_2_8_2_deps = [
        ":six_1.16.0",
    ]

    py_wheel(
        name = "python_dateutil_2.8.2_whl",
        src = "@example_lock_wheel_python_dateutil_2.8.2_py2.py3_none_any//file",
    )

    py_library(
        name = "python_dateutil_2.8.2",
        deps = [":python_dateutil_2.8.2_whl"] + _python_dateutil_2_8_2_deps,
    )

    _python_jose_3_1_0_deps = [
        ":cryptography_37.0.1",
        ":ecdsa_0.17.0",
        ":pyasn1_0.4.8",
        ":rsa_4.8",
        ":six_1.16.0",
    ]

    py_wheel(
        name = "python_jose_3.1.0_whl",
        src = "@example_lock_wheel_python_jose_3.1.0_py2.py3_none_any//file",
    )

    py_library(
        name = "python_jose_3.1.0",
        deps = [":python_jose_3.1.0_whl"] + _python_jose_3_1_0_deps,
    )

    py_wheel(
        name = "pytz_2022.1_whl",
        src = "@example_lock_wheel_pytz_2022.1_py2.py3_none_any//file",
    )

    py_library(
        name = "pytz_2022.1",
        deps = [":pytz_2022.1_whl"],
    )

    py_wheel(
        name = "pyyaml_6.0_whl",
        src = select({
            ":_env_python_darwin_arm64": "@example_lock_wheel_pyyaml_6.0_cp39_cp39_macosx_11_0_arm64//file",
            ":_env_python_darwin_x86_64": "@example_lock_wheel_pyyaml_6.0_cp39_cp39_macosx_10_9_x86_64//file",
            ":_env_python_linux_x86_64": "@example_lock_wheel_pyyaml_6.0_cp39_cp39_manylinux_2_5_x86_64.manylinux1_x86_64.manylinux_2_12_x86_64.manylinux2010_x86_64//file",
        }),
    )

    py_library(
        name = "pyyaml_6.0",
        deps = [":pyyaml_6.0_whl"],
    )

    _requests_2_27_1_deps = [
        ":certifi_2021.10.8",
        ":charset_normalizer_2.0.12",
        ":idna_3.3",
        ":urllib3_1.26.9",
    ]

    py_wheel(
        name = "requests_2.27.1_whl",
        src = "@example_lock_wheel_requests_2.27.1_py2.py3_none_any//file",
    )

    py_library(
        name = "requests_2.27.1",
        deps = [":requests_2.27.1_whl"] + _requests_2_27_1_deps,
    )

    _responses_0_20_0_deps = [
        ":requests_2.27.1",
        ":urllib3_1.26.9",
    ]

    py_wheel(
        name = "responses_0.20.0_whl",
        src = "@example_lock_wheel_responses_0.20.0_py3_none_any//file",
    )

    py_library(
        name = "responses_0.20.0",
        deps = [":responses_0.20.0_whl"] + _responses_0_20_0_deps,
    )

    _rsa_4_8_deps = [
        ":pyasn1_0.4.8",
    ]

    py_wheel(
        name = "rsa_4.8_whl",
        src = "@example_lock_wheel_rsa_4.8_py3_none_any//file",
    )

    py_library(
        name = "rsa_4.8",
        deps = [":rsa_4.8_whl"] + _rsa_4_8_deps,
    )

    _s3transfer_0_5_2_deps = [
        ":botocore_1.25.3",
    ]

    py_wheel(
        name = "s3transfer_0.5.2_whl",
        src = "@example_lock_wheel_s3transfer_0.5.2_py3_none_any//file",
    )

    py_library(
        name = "s3transfer_0.5.2",
        deps = [":s3transfer_0.5.2_whl"] + _s3transfer_0_5_2_deps,
    )

    _sarif_om_1_0_4_deps = [
        ":attrs_21.4.0",
        ":pbr_5.8.1",
    ]

    py_wheel(
        name = "sarif_om_1.0.4_whl",
        src = "@example_lock_wheel_sarif_om_1.0.4_py3_none_any//file",
    )

    py_library(
        name = "sarif_om_1.0.4",
        deps = [":sarif_om_1.0.4_whl"] + _sarif_om_1_0_4_deps,
    )

    py_wheel(
        name = "six_1.16.0_whl",
        src = "@example_lock_wheel_six_1.16.0_py2.py3_none_any//file",
    )

    py_library(
        name = "six_1.16.0",
        deps = [":six_1.16.0_whl"],
    )

    _sqlalchemy_1_4_36_deps = [
        ":greenlet_1.1.2",
    ]

    pycross_wheel_build(
        name = "_build_sqlalchemy_1.4.36",
        sdist = "@example_lock_sdist_sqlalchemy_1.4.36//file",
        deps = _sqlalchemy_1_4_36_deps,
        tags = ["manual"],
    )

    py_wheel(
        name = "sqlalchemy_1.4.36_whl",
        src = select({
            ":_env_python_darwin_arm64": ":_build_sqlalchemy_1.4.36",
            ":_env_python_darwin_x86_64": "@example_lock_wheel_sqlalchemy_1.4.36_cp39_cp39_macosx_10_15_x86_64//file",
            ":_env_python_linux_x86_64": "@example_lock_wheel_sqlalchemy_1.4.36_cp39_cp39_manylinux_2_5_x86_64.manylinux1_x86_64.manylinux_2_17_x86_64.manylinux2014_x86_64//file",
        }),
    )

    py_library(
        name = "sqlalchemy_1.4.36",
        deps = [":sqlalchemy_1.4.36_whl"] + _sqlalchemy_1_4_36_deps,
    )

    _sqlalchemy_utils_0_38_2_deps = [
        ":six_1.16.0",
        ":sqlalchemy_1.4.36",
    ]

    py_wheel(
        name = "sqlalchemy_utils_0.38.2_whl",
        src = "@example_lock_wheel_sqlalchemy_utils_0.38.2_py3_none_any//file",
    )

    py_library(
        name = "sqlalchemy_utils_0.38.2",
        deps = [":sqlalchemy_utils_0.38.2_whl"] + _sqlalchemy_utils_0_38_2_deps,
    )

    _sshpubkeys_3_3_1_deps = [
        ":cryptography_37.0.1",
        ":ecdsa_0.17.0",
    ]

    py_wheel(
        name = "sshpubkeys_3.3.1_whl",
        src = "@example_lock_wheel_sshpubkeys_3.3.1_py2.py3_none_any//file",
    )

    py_library(
        name = "sshpubkeys_3.3.1",
        deps = [":sshpubkeys_3.3.1_whl"] + _sshpubkeys_3_3_1_deps,
    )

    _stack_data_0_2_0_deps = [
        ":asttokens_2.0.5",
        ":executing_0.8.3",
        ":pure_eval_0.2.2",
    ]

    py_wheel(
        name = "stack_data_0.2.0_whl",
        src = "@example_lock_wheel_stack_data_0.2.0_py3_none_any//file",
    )

    py_library(
        name = "stack_data_0.2.0",
        deps = [":stack_data_0.2.0_whl"] + _stack_data_0_2_0_deps,
    )

    py_wheel(
        name = "traitlets_5.1.1_whl",
        src = "@example_lock_wheel_traitlets_5.1.1_py3_none_any//file",
    )

    py_library(
        name = "traitlets_5.1.1",
        deps = [":traitlets_5.1.1_whl"],
    )

    py_wheel(
        name = "urllib3_1.26.9_whl",
        src = "@example_lock_wheel_urllib3_1.26.9_py2.py3_none_any//file",
    )

    py_library(
        name = "urllib3_1.26.9",
        deps = [":urllib3_1.26.9_whl"],
    )

    py_wheel(
        name = "wcwidth_0.2.5_whl",
        src = "@example_lock_wheel_wcwidth_0.2.5_py2.py3_none_any//file",
    )

    py_library(
        name = "wcwidth_0.2.5",
        deps = [":wcwidth_0.2.5_whl"],
    )

    py_wheel(
        name = "websocket_client_1.3.2_whl",
        src = "@example_lock_wheel_websocket_client_1.3.2_py3_none_any//file",
    )

    py_library(
        name = "websocket_client_1.3.2",
        deps = [":websocket_client_1.3.2_whl"],
    )

    py_wheel(
        name = "werkzeug_2.1.2_whl",
        src = "@example_lock_wheel_werkzeug_2.1.2_py3_none_any//file",
    )

    py_library(
        name = "werkzeug_2.1.2",
        deps = [":werkzeug_2.1.2_whl"],
    )

    py_wheel(
        name = "wrapt_1.14.0_whl",
        src = select({
            ":_env_python_darwin_arm64": "@example_lock_wheel_wrapt_1.14.0_cp39_cp39_macosx_11_0_arm64//file",
            ":_env_python_darwin_x86_64": "@example_lock_wheel_wrapt_1.14.0_cp39_cp39_macosx_10_9_x86_64//file",
            ":_env_python_linux_x86_64": "@example_lock_wheel_wrapt_1.14.0_cp39_cp39_manylinux_2_5_x86_64.manylinux1_x86_64.manylinux_2_17_x86_64.manylinux2014_x86_64//file",
        }),
    )

    py_library(
        name = "wrapt_1.14.0",
        deps = [":wrapt_1.14.0_whl"],
    )

    py_wheel(
        name = "xmltodict_0.12.0_whl",
        src = "@example_lock_wheel_xmltodict_0.12.0_py2.py3_none_any//file",
    )

    py_library(
        name = "xmltodict_0.12.0",
        deps = [":xmltodict_0.12.0_whl"],
    )

    py_wheel(
        name = "zipp_3.8.0_whl",
        src = "@example_lock_wheel_zipp_3.8.0_py3_none_any//file",
    )

    py_library(
        name = "zipp_3.8.0",
        deps = [":zipp_3.8.0_whl"],
    )

def repositories():
    maybe(
        http_file,
        name = "example_lock_sdist_future_0.18.2",
        urls = [
            "https://files.pythonhosted.org/packages/source/f/future/future-0.18.2.tar.gz"
        ],
        sha256 = "b1bead90b70cf6ec3f0710ae53a525360fa360d306a86583adc6bf83a4db537d",
        downloaded_file_path = "future-0.18.2.tar.gz",
    )

    maybe(
        http_file,
        name = "example_lock_sdist_greenlet_1.1.2",
        urls = [
            "https://files.pythonhosted.org/packages/source/g/greenlet/greenlet-1.1.2.tar.gz"
        ],
        sha256 = "e30f5ea4ae2346e62cedde8794a56858a67b878dd79f7df76a0767e356b1744a",
        downloaded_file_path = "greenlet-1.1.2.tar.gz",
    )

    maybe(
        http_file,
        name = "example_lock_sdist_pbr_5.8.1",
        urls = [
            "https://files.pythonhosted.org/packages/source/p/pbr/pbr-5.8.1.tar.gz"
        ],
        sha256 = "66bc5a34912f408bb3925bf21231cb6f59206267b7f63f3503ef865c1a292e25",
        downloaded_file_path = "pbr-5.8.1.tar.gz",
    )

    maybe(
        http_file,
        name = "example_lock_sdist_sqlalchemy_1.4.36",
        urls = [
            "https://files.pythonhosted.org/packages/source/S/SQLAlchemy/SQLAlchemy-1.4.36.tar.gz"
        ],
        sha256 = "64678ac321d64a45901ef2e24725ec5e783f1f4a588305e196431447e7ace243",
        downloaded_file_path = "SQLAlchemy-1.4.36.tar.gz",
    )

    maybe(
        http_file,
        name = "example_lock_wheel_appnope_0.1.3_py2.py3_none_any",
        urls = [
            "https://files.pythonhosted.org/packages/py2.py3/a/appnope/appnope-0.1.3-py2.py3-none-any.whl"
        ],
        sha256 = "265a455292d0bd8a72453494fa24df5a11eb18373a60c7c0430889f22548605e",
        downloaded_file_path = "appnope-0.1.3-py2.py3-none-any.whl",
    )

    maybe(
        http_file,
        name = "example_lock_wheel_asttokens_2.0.5_py2.py3_none_any",
        urls = [
            "https://files.pythonhosted.org/packages/py2.py3/a/asttokens/asttokens-2.0.5-py2.py3-none-any.whl"
        ],
        sha256 = "0844691e88552595a6f4a4281a9f7f79b8dd45ca4ccea82e5e05b4bbdb76705c",
        downloaded_file_path = "asttokens-2.0.5-py2.py3-none-any.whl",
    )

    maybe(
        http_file,
        name = "example_lock_wheel_attrs_21.4.0_py2.py3_none_any",
        urls = [
            "https://files.pythonhosted.org/packages/py2.py3/a/attrs/attrs-21.4.0-py2.py3-none-any.whl"
        ],
        sha256 = "2d27e3784d7a565d36ab851fe94887c5eccd6a463168875832a1be79c82828b4",
        downloaded_file_path = "attrs-21.4.0-py2.py3-none-any.whl",
    )

    maybe(
        http_file,
        name = "example_lock_wheel_aws_sam_translator_1.45.0_py3_none_any",
        urls = [
            "https://files.pythonhosted.org/packages/py3/a/aws_sam_translator/aws_sam_translator-1.45.0-py3-none-any.whl"
        ],
        sha256 = "40a6dd5a0aba32c7b38b0f5c54470396acdcd75e4b64251b015abdf922a18b5f",
        downloaded_file_path = "aws_sam_translator-1.45.0-py3-none-any.whl",
    )

    maybe(
        http_file,
        name = "example_lock_wheel_aws_xray_sdk_2.9.0_py2.py3_none_any",
        urls = [
            "https://files.pythonhosted.org/packages/py2.py3/a/aws_xray_sdk/aws_xray_sdk-2.9.0-py2.py3-none-any.whl"
        ],
        sha256 = "98216b3ac8281b51b59a8703f8ec561c460807d9d0679838f5c0179d381d7e58",
        downloaded_file_path = "aws_xray_sdk-2.9.0-py2.py3-none-any.whl",
    )

    maybe(
        http_file,
        name = "example_lock_wheel_backcall_0.2.0_py2.py3_none_any",
        urls = [
            "https://files.pythonhosted.org/packages/py2.py3/b/backcall/backcall-0.2.0-py2.py3-none-any.whl"
        ],
        sha256 = "fbbce6a29f263178a1f7915c1940bde0ec2b2a967566fe1c65c1dfb7422bd255",
        downloaded_file_path = "backcall-0.2.0-py2.py3-none-any.whl",
    )

    maybe(
        http_file,
        name = "example_lock_wheel_boto3_1.22.3_py3_none_any",
        urls = [
            "https://files.pythonhosted.org/packages/py3/b/boto3/boto3-1.22.3-py3-none-any.whl"
        ],
        sha256 = "b291e9b8057158c4ee75a7df8ab22079b4ab915f032af59bcae22677f2a6ceda",
        downloaded_file_path = "boto3-1.22.3-py3-none-any.whl",
    )

    maybe(
        http_file,
        name = "example_lock_wheel_botocore_1.25.3_py3_none_any",
        urls = [
            "https://files.pythonhosted.org/packages/py3/b/botocore/botocore-1.25.3-py3-none-any.whl"
        ],
        sha256 = "b63343736f1e778f9a658736afd9773ea38b3605d96556fb5585fc0c04a0d1e1",
        downloaded_file_path = "botocore-1.25.3-py3-none-any.whl",
    )

    maybe(
        http_file,
        name = "example_lock_wheel_certifi_2021.10.8_py2.py3_none_any",
        urls = [
            "https://files.pythonhosted.org/packages/py2.py3/c/certifi/certifi-2021.10.8-py2.py3-none-any.whl"
        ],
        sha256 = "d62a0163eb4c2344ac042ab2bdf75399a71a2d8c7d47eac2e2ee91b9d6339569",
        downloaded_file_path = "certifi-2021.10.8-py2.py3-none-any.whl",
    )

    maybe(
        http_file,
        name = "example_lock_wheel_cffi_1.15.0_cp39_cp39_macosx_10_9_x86_64",
        urls = [
            "https://files.pythonhosted.org/packages/cp39/c/cffi/cffi-1.15.0-cp39-cp39-macosx_10_9_x86_64.whl"
        ],
        sha256 = "45e8636704eacc432a206ac7345a5d3d2c62d95a507ec70d62f23cd91770482a",
        downloaded_file_path = "cffi-1.15.0-cp39-cp39-macosx_10_9_x86_64.whl",
    )

    maybe(
        http_file,
        name = "example_lock_wheel_cffi_1.15.0_cp39_cp39_macosx_11_0_arm64",
        urls = [
            "https://files.pythonhosted.org/packages/cp39/c/cffi/cffi-1.15.0-cp39-cp39-macosx_11_0_arm64.whl"
        ],
        sha256 = "31fb708d9d7c3f49a60f04cf5b119aeefe5644daba1cd2a0fe389b674fd1de37",
        downloaded_file_path = "cffi-1.15.0-cp39-cp39-macosx_11_0_arm64.whl",
    )

    maybe(
        http_file,
        name = "example_lock_wheel_cffi_1.15.0_cp39_cp39_manylinux_2_12_x86_64.manylinux2010_x86_64",
        urls = [
            "https://files.pythonhosted.org/packages/cp39/c/cffi/cffi-1.15.0-cp39-cp39-manylinux_2_12_x86_64.manylinux2010_x86_64.whl"
        ],
        sha256 = "74fdfdbfdc48d3f47148976f49fab3251e550a8720bebc99bf1483f5bfb5db3e",
        downloaded_file_path = "cffi-1.15.0-cp39-cp39-manylinux_2_12_x86_64.manylinux2010_x86_64.whl",
    )

    maybe(
        http_file,
        name = "example_lock_wheel_cfn_lint_0.59.0_py3_none_any",
        urls = [
            "https://files.pythonhosted.org/packages/py3/c/cfn_lint/cfn_lint-0.59.0-py3-none-any.whl"
        ],
        sha256 = "e5e98712cb162ee70eedd0fd8eae8d45d6420d43502e6120ad768f00ff1eec05",
        downloaded_file_path = "cfn_lint-0.59.0-py3-none-any.whl",
    )

    maybe(
        http_file,
        name = "example_lock_wheel_charset_normalizer_2.0.12_py3_none_any",
        urls = [
            "https://files.pythonhosted.org/packages/py3/c/charset_normalizer/charset_normalizer-2.0.12-py3-none-any.whl"
        ],
        sha256 = "6881edbebdb17b39b4eaaa821b438bf6eddffb4468cf344f09f89def34a8b1df",
        downloaded_file_path = "charset_normalizer-2.0.12-py3-none-any.whl",
    )

    maybe(
        http_file,
        name = "example_lock_wheel_click_8.1.3_py3_none_any",
        urls = [
            "https://files.pythonhosted.org/packages/py3/c/click/click-8.1.3-py3-none-any.whl"
        ],
        sha256 = "bb4d8133cb15a609f44e8213d9b391b0809795062913b383c62be0ee95b1db48",
        downloaded_file_path = "click-8.1.3-py3-none-any.whl",
    )

    maybe(
        http_file,
        name = "example_lock_wheel_cognitojwt_1.4.1_py3_none_any",
        urls = [
            "https://files.pythonhosted.org/packages/py3/c/cognitojwt/cognitojwt-1.4.1-py3-none-any.whl"
        ],
        sha256 = "8ee189f82289d140dc750c91e8772436b64b94d071507ace42efc22c525f42ce",
        downloaded_file_path = "cognitojwt-1.4.1-py3-none-any.whl",
    )

    maybe(
        http_file,
        name = "example_lock_wheel_cryptography_37.0.1_cp36_abi3_macosx_10_10_universal2",
        urls = [
            "https://files.pythonhosted.org/packages/cp36/c/cryptography/cryptography-37.0.1-cp36-abi3-macosx_10_10_universal2.whl"
        ],
        sha256 = "74b55f67f4cf026cb84da7a1b04fc2a1d260193d4ad0ea5e9897c8b74c1e76ac",
        downloaded_file_path = "cryptography-37.0.1-cp36-abi3-macosx_10_10_universal2.whl",
    )

    maybe(
        http_file,
        name = "example_lock_wheel_cryptography_37.0.1_cp36_abi3_macosx_10_10_x86_64",
        urls = [
            "https://files.pythonhosted.org/packages/cp36/c/cryptography/cryptography-37.0.1-cp36-abi3-macosx_10_10_x86_64.whl"
        ],
        sha256 = "0db5cf21bd7d092baacb576482b0245102cea2d3cf09f09271ce9f69624ecb6f",
        downloaded_file_path = "cryptography-37.0.1-cp36-abi3-macosx_10_10_x86_64.whl",
    )

    maybe(
        http_file,
        name = "example_lock_wheel_cryptography_37.0.1_cp36_abi3_manylinux_2_17_x86_64.manylinux2014_x86_64",
        urls = [
            "https://files.pythonhosted.org/packages/cp36/c/cryptography/cryptography-37.0.1-cp36-abi3-manylinux_2_17_x86_64.manylinux2014_x86_64.whl"
        ],
        sha256 = "6d4daf890e674d191757d8d7d60dc3a29c58c72c7a76a05f1c0a326013f47e8b",
        downloaded_file_path = "cryptography-37.0.1-cp36-abi3-manylinux_2_17_x86_64.manylinux2014_x86_64.whl",
    )

    maybe(
        http_file,
        name = "example_lock_wheel_decorator_5.1.1_py3_none_any",
        urls = [
            "https://files.pythonhosted.org/packages/py3/d/decorator/decorator-5.1.1-py3-none-any.whl"
        ],
        sha256 = "b8c3f85900b9dc423225913c5aace94729fe1fa9763b38939a95226f02d37186",
        downloaded_file_path = "decorator-5.1.1-py3-none-any.whl",
    )

    maybe(
        http_file,
        name = "example_lock_wheel_docker_5.0.3_py2.py3_none_any",
        urls = [
            "https://files.pythonhosted.org/packages/py2.py3/d/docker/docker-5.0.3-py2.py3-none-any.whl"
        ],
        sha256 = "7a79bb439e3df59d0a72621775d600bc8bc8b422d285824cb37103eab91d1ce0",
        downloaded_file_path = "docker-5.0.3-py2.py3-none-any.whl",
    )

    maybe(
        http_file,
        name = "example_lock_wheel_ecdsa_0.17.0_py2.py3_none_any",
        urls = [
            "https://files.pythonhosted.org/packages/py2.py3/e/ecdsa/ecdsa-0.17.0-py2.py3-none-any.whl"
        ],
        sha256 = "5cf31d5b33743abe0dfc28999036c849a69d548f994b535e527ee3cb7f3ef676",
        downloaded_file_path = "ecdsa-0.17.0-py2.py3-none-any.whl",
    )

    maybe(
        http_file,
        name = "example_lock_wheel_executing_0.8.3_py2.py3_none_any",
        urls = [
            "https://files.pythonhosted.org/packages/py2.py3/e/executing/executing-0.8.3-py2.py3-none-any.whl"
        ],
        sha256 = "d1eef132db1b83649a3905ca6dd8897f71ac6f8cac79a7e58a1a09cf137546c9",
        downloaded_file_path = "executing-0.8.3-py2.py3-none-any.whl",
    )

    maybe(
        http_file,
        name = "example_lock_wheel_flask_2.1.2_py3_none_any",
        urls = [
            "https://files.pythonhosted.org/packages/py3/F/Flask/Flask-2.1.2-py3-none-any.whl"
        ],
        sha256 = "fad5b446feb0d6db6aec0c3184d16a8c1f6c3e464b511649c8918a9be100b4fe",
        downloaded_file_path = "Flask-2.1.2-py3-none-any.whl",
    )

    maybe(
        http_file,
        name = "example_lock_wheel_flask_cors_3.0.10_py2.py3_none_any",
        urls = [
            "https://files.pythonhosted.org/packages/py2.py3/F/Flask_Cors/Flask_Cors-3.0.10-py2.py3-none-any.whl"
        ],
        sha256 = "74efc975af1194fc7891ff5cd85b0f7478be4f7f59fe158102e91abb72bb4438",
        downloaded_file_path = "Flask_Cors-3.0.10-py2.py3-none-any.whl",
    )

    maybe(
        http_file,
        name = "example_lock_wheel_graphql_core_3.2.1_py3_none_any",
        urls = [
            "https://files.pythonhosted.org/packages/py3/g/graphql_core/graphql_core-3.2.1-py3-none-any.whl"
        ],
        sha256 = "f83c658e4968998eed1923a2e3e3eddd347e005ac0315fbb7ca4d70ea9156323",
        downloaded_file_path = "graphql_core-3.2.1-py3-none-any.whl",
    )

    maybe(
        http_file,
        name = "example_lock_wheel_greenlet_1.1.2_cp39_cp39_macosx_10_14_x86_64",
        urls = [
            "https://files.pythonhosted.org/packages/cp39/g/greenlet/greenlet-1.1.2-cp39-cp39-macosx_10_14_x86_64.whl"
        ],
        sha256 = "166eac03e48784a6a6e0e5f041cfebb1ab400b394db188c48b3a84737f505b67",
        downloaded_file_path = "greenlet-1.1.2-cp39-cp39-macosx_10_14_x86_64.whl",
    )

    maybe(
        http_file,
        name = "example_lock_wheel_greenlet_1.1.2_cp39_cp39_manylinux_2_17_x86_64.manylinux2014_x86_64",
        urls = [
            "https://files.pythonhosted.org/packages/cp39/g/greenlet/greenlet-1.1.2-cp39-cp39-manylinux_2_17_x86_64.manylinux2014_x86_64.whl"
        ],
        sha256 = "7ff61ff178250f9bb3cd89752df0f1dd0e27316a8bd1465351652b1b4a4cdfd3",
        downloaded_file_path = "greenlet-1.1.2-cp39-cp39-manylinux_2_17_x86_64.manylinux2014_x86_64.whl",
    )

    maybe(
        http_file,
        name = "example_lock_wheel_idna_3.3_py3_none_any",
        urls = [
            "https://files.pythonhosted.org/packages/py3/i/idna/idna-3.3-py3-none-any.whl"
        ],
        sha256 = "84d9dd047ffa80596e0f246e2eab0b391788b0503584e8945f2368256d2735ff",
        downloaded_file_path = "idna-3.3-py3-none-any.whl",
    )

    maybe(
        http_file,
        name = "example_lock_wheel_importlib_metadata_4.11.3_py3_none_any",
        urls = [
            "https://files.pythonhosted.org/packages/py3/i/importlib_metadata/importlib_metadata-4.11.3-py3-none-any.whl"
        ],
        sha256 = "1208431ca90a8cca1a6b8af391bb53c1a2db74e5d1cef6ddced95d4b2062edc6",
        downloaded_file_path = "importlib_metadata-4.11.3-py3-none-any.whl",
    )

    maybe(
        http_file,
        name = "example_lock_wheel_ipython_8.2.0_py3_none_any",
        urls = [
            "https://files.pythonhosted.org/packages/py3/i/ipython/ipython-8.2.0-py3-none-any.whl"
        ],
        sha256 = "1b672bfd7a48d87ab203d9af8727a3b0174a4566b4091e9447c22fb63ea32857",
        downloaded_file_path = "ipython-8.2.0-py3-none-any.whl",
    )

    maybe(
        http_file,
        name = "example_lock_wheel_itsdangerous_2.1.2_py3_none_any",
        urls = [
            "https://files.pythonhosted.org/packages/py3/i/itsdangerous/itsdangerous-2.1.2-py3-none-any.whl"
        ],
        sha256 = "2c2349112351b88699d8d4b6b075022c0808887cb7ad10069318a8b0bc88db44",
        downloaded_file_path = "itsdangerous-2.1.2-py3-none-any.whl",
    )

    maybe(
        http_file,
        name = "example_lock_wheel_jedi_0.18.1_py2.py3_none_any",
        urls = [
            "https://files.pythonhosted.org/packages/py2.py3/j/jedi/jedi-0.18.1-py2.py3-none-any.whl"
        ],
        sha256 = "637c9635fcf47945ceb91cd7f320234a7be540ded6f3e99a50cb6febdfd1ba8d",
        downloaded_file_path = "jedi-0.18.1-py2.py3-none-any.whl",
    )

    maybe(
        http_file,
        name = "example_lock_wheel_jinja2_3.1.2_py3_none_any",
        urls = [
            "https://files.pythonhosted.org/packages/py3/J/Jinja2/Jinja2-3.1.2-py3-none-any.whl"
        ],
        sha256 = "6088930bfe239f0e6710546ab9c19c9ef35e29792895fed6e6e31a023a182a61",
        downloaded_file_path = "Jinja2-3.1.2-py3-none-any.whl",
    )

    maybe(
        http_file,
        name = "example_lock_wheel_jmespath_1.0.0_py3_none_any",
        urls = [
            "https://files.pythonhosted.org/packages/py3/j/jmespath/jmespath-1.0.0-py3-none-any.whl"
        ],
        sha256 = "e8dcd576ed616f14ec02eed0005c85973b5890083313860136657e24784e4c04",
        downloaded_file_path = "jmespath-1.0.0-py3-none-any.whl",
    )

    maybe(
        http_file,
        name = "example_lock_wheel_jschema_to_python_1.2.3_py3_none_any",
        urls = [
            "https://files.pythonhosted.org/packages/py3/j/jschema_to_python/jschema_to_python-1.2.3-py3-none-any.whl"
        ],
        sha256 = "8a703ca7604d42d74b2815eecf99a33359a8dccbb80806cce386d5e2dd992b05",
        downloaded_file_path = "jschema_to_python-1.2.3-py3-none-any.whl",
    )

    maybe(
        http_file,
        name = "example_lock_wheel_jsondiff_2.0.0_py3_none_any",
        urls = [
            "https://files.pythonhosted.org/packages/py3/j/jsondiff/jsondiff-2.0.0-py3-none-any.whl"
        ],
        sha256 = "689841d66273fc88fc79f7d33f4c074774f4f214b6466e3aff0e5adaf889d1e0",
        downloaded_file_path = "jsondiff-2.0.0-py3-none-any.whl",
    )

    maybe(
        http_file,
        name = "example_lock_wheel_jsonpatch_1.32_py2.py3_none_any",
        urls = [
            "https://files.pythonhosted.org/packages/py2.py3/j/jsonpatch/jsonpatch-1.32-py2.py3-none-any.whl"
        ],
        sha256 = "26ac385719ac9f54df8a2f0827bb8253aa3ea8ab7b3368457bcdb8c14595a397",
        downloaded_file_path = "jsonpatch-1.32-py2.py3-none-any.whl",
    )

    maybe(
        http_file,
        name = "example_lock_wheel_jsonpickle_2.1.0_py2.py3_none_any",
        urls = [
            "https://files.pythonhosted.org/packages/py2.py3/j/jsonpickle/jsonpickle-2.1.0-py2.py3-none-any.whl"
        ],
        sha256 = "1dee77ddc5d652dfdabc33d33cff9d7e131d428007007da4fd6f7071ae774b0f",
        downloaded_file_path = "jsonpickle-2.1.0-py2.py3-none-any.whl",
    )

    maybe(
        http_file,
        name = "example_lock_wheel_jsonpointer_2.3_py2.py3_none_any",
        urls = [
            "https://files.pythonhosted.org/packages/py2.py3/j/jsonpointer/jsonpointer-2.3-py2.py3-none-any.whl"
        ],
        sha256 = "51801e558539b4e9cd268638c078c6c5746c9ac96bc38152d443400e4f3793e9",
        downloaded_file_path = "jsonpointer-2.3-py2.py3-none-any.whl",
    )

    maybe(
        http_file,
        name = "example_lock_wheel_jsonschema_3.2.0_py2.py3_none_any",
        urls = [
            "https://files.pythonhosted.org/packages/py2.py3/j/jsonschema/jsonschema-3.2.0-py2.py3-none-any.whl"
        ],
        sha256 = "4e5b3cf8216f577bee9ce139cbe72eca3ea4f292ec60928ff24758ce626cd163",
        downloaded_file_path = "jsonschema-3.2.0-py2.py3-none-any.whl",
    )

    maybe(
        http_file,
        name = "example_lock_wheel_junit_xml_1.9_py2.py3_none_any",
        urls = [
            "https://files.pythonhosted.org/packages/py2.py3/j/junit_xml/junit_xml-1.9-py2.py3-none-any.whl"
        ],
        sha256 = "ec5ca1a55aefdd76d28fcc0b135251d156c7106fa979686a4b48d62b761b4732",
        downloaded_file_path = "junit_xml-1.9-py2.py3-none-any.whl",
    )

    maybe(
        http_file,
        name = "example_lock_wheel_markupsafe_2.1.1_cp39_cp39_macosx_10_9_universal2",
        urls = [
            "https://files.pythonhosted.org/packages/cp39/M/MarkupSafe/MarkupSafe-2.1.1-cp39-cp39-macosx_10_9_universal2.whl"
        ],
        sha256 = "e04e26803c9c3851c931eac40c695602c6295b8d432cbe78609649ad9bd2da8a",
        downloaded_file_path = "MarkupSafe-2.1.1-cp39-cp39-macosx_10_9_universal2.whl",
    )

    maybe(
        http_file,
        name = "example_lock_wheel_markupsafe_2.1.1_cp39_cp39_macosx_10_9_x86_64",
        urls = [
            "https://files.pythonhosted.org/packages/cp39/M/MarkupSafe/MarkupSafe-2.1.1-cp39-cp39-macosx_10_9_x86_64.whl"
        ],
        sha256 = "b87db4360013327109564f0e591bd2a3b318547bcef31b468a92ee504d07ae4f",
        downloaded_file_path = "MarkupSafe-2.1.1-cp39-cp39-macosx_10_9_x86_64.whl",
    )

    maybe(
        http_file,
        name = "example_lock_wheel_markupsafe_2.1.1_cp39_cp39_manylinux_2_17_x86_64.manylinux2014_x86_64",
        urls = [
            "https://files.pythonhosted.org/packages/cp39/M/MarkupSafe/MarkupSafe-2.1.1-cp39-cp39-manylinux_2_17_x86_64.manylinux2014_x86_64.whl"
        ],
        sha256 = "56442863ed2b06d19c37f94d999035e15ee982988920e12a5b4ba29b62ad1f77",
        downloaded_file_path = "MarkupSafe-2.1.1-cp39-cp39-manylinux_2_17_x86_64.manylinux2014_x86_64.whl",
    )

    maybe(
        http_file,
        name = "example_lock_wheel_matplotlib_inline_0.1.3_py3_none_any",
        urls = [
            "https://files.pythonhosted.org/packages/py3/m/matplotlib_inline/matplotlib_inline-0.1.3-py3-none-any.whl"
        ],
        sha256 = "aed605ba3b72462d64d475a21a9296f400a19c4f74a31b59103d2a99ffd5aa5c",
        downloaded_file_path = "matplotlib_inline-0.1.3-py3-none-any.whl",
    )

    maybe(
        http_file,
        name = "example_lock_wheel_moto_3.1.1_py2.py3_none_any",
        urls = [
            "https://files.pythonhosted.org/packages/py2.py3/m/moto/moto-3.1.1-py2.py3-none-any.whl"
        ],
        sha256 = "462495563847134ea8ef4135a229731a598a8e7b6b10a74f8d745815aa20a25b",
        downloaded_file_path = "moto-3.1.1-py2.py3-none-any.whl",
    )

    maybe(
        http_file,
        name = "example_lock_wheel_networkx_2.8_py3_none_any",
        urls = [
            "https://files.pythonhosted.org/packages/py3/n/networkx/networkx-2.8-py3-none-any.whl"
        ],
        sha256 = "1a1e8fe052cc1b4e0339b998f6795099562a264a13a5af7a32cad45ab9d4e126",
        downloaded_file_path = "networkx-2.8-py3-none-any.whl",
    )

    maybe(
        http_file,
        name = "example_lock_wheel_parso_0.8.3_py2.py3_none_any",
        urls = [
            "https://files.pythonhosted.org/packages/py2.py3/p/parso/parso-0.8.3-py2.py3-none-any.whl"
        ],
        sha256 = "c001d4636cd3aecdaf33cbb40aebb59b094be2a74c556778ef5576c175e19e75",
        downloaded_file_path = "parso-0.8.3-py2.py3-none-any.whl",
    )

    maybe(
        http_file,
        name = "example_lock_wheel_pexpect_4.8.0_py2.py3_none_any",
        urls = [
            "https://files.pythonhosted.org/packages/py2.py3/p/pexpect/pexpect-4.8.0-py2.py3-none-any.whl"
        ],
        sha256 = "0b48a55dcb3c05f3329815901ea4fc1537514d6ba867a152b581d69ae3710937",
        downloaded_file_path = "pexpect-4.8.0-py2.py3-none-any.whl",
    )

    maybe(
        http_file,
        name = "example_lock_wheel_pickleshare_0.7.5_py2.py3_none_any",
        urls = [
            "https://files.pythonhosted.org/packages/py2.py3/p/pickleshare/pickleshare-0.7.5-py2.py3-none-any.whl"
        ],
        sha256 = "9649af414d74d4df115d5d718f82acb59c9d418196b7b4290ed47a12ce62df56",
        downloaded_file_path = "pickleshare-0.7.5-py2.py3-none-any.whl",
    )

    maybe(
        http_file,
        name = "example_lock_wheel_prompt_toolkit_3.0.29_py3_none_any",
        urls = [
            "https://files.pythonhosted.org/packages/py3/p/prompt_toolkit/prompt_toolkit-3.0.29-py3-none-any.whl"
        ],
        sha256 = "62291dad495e665fca0bda814e342c69952086afb0f4094d0893d357e5c78752",
        downloaded_file_path = "prompt_toolkit-3.0.29-py3-none-any.whl",
    )

    maybe(
        http_file,
        name = "example_lock_wheel_ptyprocess_0.7.0_py2.py3_none_any",
        urls = [
            "https://files.pythonhosted.org/packages/py2.py3/p/ptyprocess/ptyprocess-0.7.0-py2.py3-none-any.whl"
        ],
        sha256 = "4b41f3967fce3af57cc7e94b888626c18bf37a083e3651ca8feeb66d492fef35",
        downloaded_file_path = "ptyprocess-0.7.0-py2.py3-none-any.whl",
    )

    maybe(
        http_file,
        name = "example_lock_wheel_pure_eval_0.2.2_py3_none_any",
        urls = [
            "https://files.pythonhosted.org/packages/py3/p/pure_eval/pure_eval-0.2.2-py3-none-any.whl"
        ],
        sha256 = "01eaab343580944bc56080ebe0a674b39ec44a945e6d09ba7db3cb8cec289350",
        downloaded_file_path = "pure_eval-0.2.2-py3-none-any.whl",
    )

    maybe(
        http_file,
        name = "example_lock_wheel_pyasn1_0.4.8_py2.py3_none_any",
        urls = [
            "https://files.pythonhosted.org/packages/py2.py3/p/pyasn1/pyasn1-0.4.8-py2.py3-none-any.whl"
        ],
        sha256 = "39c7e2ec30515947ff4e87fb6f456dfc6e84857d34be479c9d4a4ba4bf46aa5d",
        downloaded_file_path = "pyasn1-0.4.8-py2.py3-none-any.whl",
    )

    maybe(
        http_file,
        name = "example_lock_wheel_pycparser_2.21_py2.py3_none_any",
        urls = [
            "https://files.pythonhosted.org/packages/py2.py3/p/pycparser/pycparser-2.21-py2.py3-none-any.whl"
        ],
        sha256 = "8ee45429555515e1f6b185e78100aea234072576aa43ab53aefcae078162fca9",
        downloaded_file_path = "pycparser-2.21-py2.py3-none-any.whl",
    )

    maybe(
        http_file,
        name = "example_lock_wheel_pygments_2.12.0_py3_none_any",
        urls = [
            "https://files.pythonhosted.org/packages/py3/P/Pygments/Pygments-2.12.0-py3-none-any.whl"
        ],
        sha256 = "dc9c10fb40944260f6ed4c688ece0cd2048414940f1cea51b8b226318411c519",
        downloaded_file_path = "Pygments-2.12.0-py3-none-any.whl",
    )

    maybe(
        http_file,
        name = "example_lock_wheel_pyrsistent_0.18.1_cp39_cp39_macosx_10_9_universal2",
        urls = [
            "https://files.pythonhosted.org/packages/cp39/p/pyrsistent/pyrsistent-0.18.1-cp39-cp39-macosx_10_9_universal2.whl"
        ],
        sha256 = "f87cc2863ef33c709e237d4b5f4502a62a00fab450c9e020892e8e2ede5847f5",
        downloaded_file_path = "pyrsistent-0.18.1-cp39-cp39-macosx_10_9_universal2.whl",
    )

    maybe(
        http_file,
        name = "example_lock_wheel_pyrsistent_0.18.1_cp39_cp39_manylinux_2_17_x86_64.manylinux2014_x86_64",
        urls = [
            "https://files.pythonhosted.org/packages/cp39/p/pyrsistent/pyrsistent-0.18.1-cp39-cp39-manylinux_2_17_x86_64.manylinux2014_x86_64.whl"
        ],
        sha256 = "6bc66318fb7ee012071b2792024564973ecc80e9522842eb4e17743604b5e045",
        downloaded_file_path = "pyrsistent-0.18.1-cp39-cp39-manylinux_2_17_x86_64.manylinux2014_x86_64.whl",
    )

    maybe(
        http_file,
        name = "example_lock_wheel_python_dateutil_2.8.2_py2.py3_none_any",
        urls = [
            "https://files.pythonhosted.org/packages/py2.py3/p/python_dateutil/python_dateutil-2.8.2-py2.py3-none-any.whl"
        ],
        sha256 = "961d03dc3453ebbc59dbdea9e4e11c5651520a876d0f4db161e8674aae935da9",
        downloaded_file_path = "python_dateutil-2.8.2-py2.py3-none-any.whl",
    )

    maybe(
        http_file,
        name = "example_lock_wheel_python_jose_3.1.0_py2.py3_none_any",
        urls = [
            "https://files.pythonhosted.org/packages/py2.py3/p/python_jose/python_jose-3.1.0-py2.py3-none-any.whl"
        ],
        sha256 = "1ac4caf4bfebd5a70cf5bd82702ed850db69b0b6e1d0ae7368e5f99ac01c9571",
        downloaded_file_path = "python_jose-3.1.0-py2.py3-none-any.whl",
    )

    maybe(
        http_file,
        name = "example_lock_wheel_pytz_2022.1_py2.py3_none_any",
        urls = [
            "https://files.pythonhosted.org/packages/py2.py3/p/pytz/pytz-2022.1-py2.py3-none-any.whl"
        ],
        sha256 = "e68985985296d9a66a881eb3193b0906246245294a881e7c8afe623866ac6a5c",
        downloaded_file_path = "pytz-2022.1-py2.py3-none-any.whl",
    )

    maybe(
        http_file,
        name = "example_lock_wheel_pyyaml_6.0_cp39_cp39_macosx_10_9_x86_64",
        urls = [
            "https://files.pythonhosted.org/packages/cp39/P/PyYAML/PyYAML-6.0-cp39-cp39-macosx_10_9_x86_64.whl"
        ],
        sha256 = "055d937d65826939cb044fc8c9b08889e8c743fdc6a32b33e2390f66013e449b",
        downloaded_file_path = "PyYAML-6.0-cp39-cp39-macosx_10_9_x86_64.whl",
    )

    maybe(
        http_file,
        name = "example_lock_wheel_pyyaml_6.0_cp39_cp39_macosx_11_0_arm64",
        urls = [
            "https://files.pythonhosted.org/packages/cp39/P/PyYAML/PyYAML-6.0-cp39-cp39-macosx_11_0_arm64.whl"
        ],
        sha256 = "e61ceaab6f49fb8bdfaa0f92c4b57bcfbea54c09277b1b4f7ac376bfb7a7c174",
        downloaded_file_path = "PyYAML-6.0-cp39-cp39-macosx_11_0_arm64.whl",
    )

    maybe(
        http_file,
        name = "example_lock_wheel_pyyaml_6.0_cp39_cp39_manylinux_2_5_x86_64.manylinux1_x86_64.manylinux_2_12_x86_64.manylinux2010_x86_64",
        urls = [
            "https://files.pythonhosted.org/packages/cp39/P/PyYAML/PyYAML-6.0-cp39-cp39-manylinux_2_5_x86_64.manylinux1_x86_64.manylinux_2_12_x86_64.manylinux2010_x86_64.whl"
        ],
        sha256 = "40527857252b61eacd1d9af500c3337ba8deb8fc298940291486c465c8b46ec0",
        downloaded_file_path = "PyYAML-6.0-cp39-cp39-manylinux_2_5_x86_64.manylinux1_x86_64.manylinux_2_12_x86_64.manylinux2010_x86_64.whl",
    )

    maybe(
        http_file,
        name = "example_lock_wheel_requests_2.27.1_py2.py3_none_any",
        urls = [
            "https://files.pythonhosted.org/packages/py2.py3/r/requests/requests-2.27.1-py2.py3-none-any.whl"
        ],
        sha256 = "f22fa1e554c9ddfd16e6e41ac79759e17be9e492b3587efa038054674760e72d",
        downloaded_file_path = "requests-2.27.1-py2.py3-none-any.whl",
    )

    maybe(
        http_file,
        name = "example_lock_wheel_responses_0.20.0_py3_none_any",
        urls = [
            "https://files.pythonhosted.org/packages/py3/r/responses/responses-0.20.0-py3-none-any.whl"
        ],
        sha256 = "18831bc2d72443b67664d98038374a6fa1f27eaaff4dd9a7d7613723416fea3c",
        downloaded_file_path = "responses-0.20.0-py3-none-any.whl",
    )

    maybe(
        http_file,
        name = "example_lock_wheel_rsa_4.8_py3_none_any",
        urls = [
            "https://files.pythonhosted.org/packages/py3/r/rsa/rsa-4.8-py3-none-any.whl"
        ],
        sha256 = "95c5d300c4e879ee69708c428ba566c59478fd653cc3a22243eeb8ed846950bb",
        downloaded_file_path = "rsa-4.8-py3-none-any.whl",
    )

    maybe(
        http_file,
        name = "example_lock_wheel_s3transfer_0.5.2_py3_none_any",
        urls = [
            "https://files.pythonhosted.org/packages/py3/s/s3transfer/s3transfer-0.5.2-py3-none-any.whl"
        ],
        sha256 = "7a6f4c4d1fdb9a2b640244008e142cbc2cd3ae34b386584ef044dd0f27101971",
        downloaded_file_path = "s3transfer-0.5.2-py3-none-any.whl",
    )

    maybe(
        http_file,
        name = "example_lock_wheel_sarif_om_1.0.4_py3_none_any",
        urls = [
            "https://files.pythonhosted.org/packages/py3/s/sarif_om/sarif_om-1.0.4-py3-none-any.whl"
        ],
        sha256 = "539ef47a662329b1c8502388ad92457425e95dc0aaaf995fe46f4984c4771911",
        downloaded_file_path = "sarif_om-1.0.4-py3-none-any.whl",
    )

    maybe(
        http_file,
        name = "example_lock_wheel_six_1.16.0_py2.py3_none_any",
        urls = [
            "https://files.pythonhosted.org/packages/py2.py3/s/six/six-1.16.0-py2.py3-none-any.whl"
        ],
        sha256 = "8abb2f1d86890a2dfb989f9a77cfcfd3e47c2a354b01111771326f8aa26e0254",
        downloaded_file_path = "six-1.16.0-py2.py3-none-any.whl",
    )

    maybe(
        http_file,
        name = "example_lock_wheel_sqlalchemy_1.4.36_cp39_cp39_macosx_10_15_x86_64",
        urls = [
            "https://files.pythonhosted.org/packages/cp39/S/SQLAlchemy/SQLAlchemy-1.4.36-cp39-cp39-macosx_10_15_x86_64.whl"
        ],
        sha256 = "f522214f6749bc073262529c056f7dfd660f3b5ec4180c5354d985eb7219801e",
        downloaded_file_path = "SQLAlchemy-1.4.36-cp39-cp39-macosx_10_15_x86_64.whl",
    )

    maybe(
        http_file,
        name = "example_lock_wheel_sqlalchemy_1.4.36_cp39_cp39_manylinux_2_5_x86_64.manylinux1_x86_64.manylinux_2_17_x86_64.manylinux2014_x86_64",
        urls = [
            "https://files.pythonhosted.org/packages/cp39/S/SQLAlchemy/SQLAlchemy-1.4.36-cp39-cp39-manylinux_2_5_x86_64.manylinux1_x86_64.manylinux_2_17_x86_64.manylinux2014_x86_64.whl"
        ],
        sha256 = "2ec89bf98cc6a0f5d1e28e3ad28e9be6f3b4bdbd521a4053c7ae8d5e1289a8a1",
        downloaded_file_path = "SQLAlchemy-1.4.36-cp39-cp39-manylinux_2_5_x86_64.manylinux1_x86_64.manylinux_2_17_x86_64.manylinux2014_x86_64.whl",
    )

    maybe(
        http_file,
        name = "example_lock_wheel_sqlalchemy_utils_0.38.2_py3_none_any",
        urls = [
            "https://files.pythonhosted.org/packages/py3/S/SQLAlchemy_Utils/SQLAlchemy_Utils-0.38.2-py3-none-any.whl"
        ],
        sha256 = "622235b1598f97300e4d08820ab024f5219c9a6309937a8b908093f487b4ba54",
        downloaded_file_path = "SQLAlchemy_Utils-0.38.2-py3-none-any.whl",
    )

    maybe(
        http_file,
        name = "example_lock_wheel_sshpubkeys_3.3.1_py2.py3_none_any",
        urls = [
            "https://files.pythonhosted.org/packages/py2.py3/s/sshpubkeys/sshpubkeys-3.3.1-py2.py3-none-any.whl"
        ],
        sha256 = "946f76b8fe86704b0e7c56a00d80294e39bc2305999844f079a217885060b1ac",
        downloaded_file_path = "sshpubkeys-3.3.1-py2.py3-none-any.whl",
    )

    maybe(
        http_file,
        name = "example_lock_wheel_stack_data_0.2.0_py3_none_any",
        urls = [
            "https://files.pythonhosted.org/packages/py3/s/stack_data/stack_data-0.2.0-py3-none-any.whl"
        ],
        sha256 = "999762f9c3132308789affa03e9271bbbe947bf78311851f4d485d8402ed858e",
        downloaded_file_path = "stack_data-0.2.0-py3-none-any.whl",
    )

    maybe(
        http_file,
        name = "example_lock_wheel_traitlets_5.1.1_py3_none_any",
        urls = [
            "https://files.pythonhosted.org/packages/py3/t/traitlets/traitlets-5.1.1-py3-none-any.whl"
        ],
        sha256 = "2d313cc50a42cd6c277e7d7dc8d4d7fedd06a2c215f78766ae7b1a66277e0033",
        downloaded_file_path = "traitlets-5.1.1-py3-none-any.whl",
    )

    maybe(
        http_file,
        name = "example_lock_wheel_urllib3_1.26.9_py2.py3_none_any",
        urls = [
            "https://files.pythonhosted.org/packages/py2.py3/u/urllib3/urllib3-1.26.9-py2.py3-none-any.whl"
        ],
        sha256 = "44ece4d53fb1706f667c9bd1c648f5469a2ec925fcf3a776667042d645472c14",
        downloaded_file_path = "urllib3-1.26.9-py2.py3-none-any.whl",
    )

    maybe(
        http_file,
        name = "example_lock_wheel_wcwidth_0.2.5_py2.py3_none_any",
        urls = [
            "https://files.pythonhosted.org/packages/py2.py3/w/wcwidth/wcwidth-0.2.5-py2.py3-none-any.whl"
        ],
        sha256 = "beb4802a9cebb9144e99086eff703a642a13d6a0052920003a230f3294bbe784",
        downloaded_file_path = "wcwidth-0.2.5-py2.py3-none-any.whl",
    )

    maybe(
        http_file,
        name = "example_lock_wheel_websocket_client_1.3.2_py3_none_any",
        urls = [
            "https://files.pythonhosted.org/packages/py3/w/websocket_client/websocket_client-1.3.2-py3-none-any.whl"
        ],
        sha256 = "722b171be00f2b90e1d4fb2f2b53146a536ca38db1da8ff49c972a4e1365d0ef",
        downloaded_file_path = "websocket_client-1.3.2-py3-none-any.whl",
    )

    maybe(
        http_file,
        name = "example_lock_wheel_werkzeug_2.1.2_py3_none_any",
        urls = [
            "https://files.pythonhosted.org/packages/py3/W/Werkzeug/Werkzeug-2.1.2-py3-none-any.whl"
        ],
        sha256 = "72a4b735692dd3135217911cbeaa1be5fa3f62bffb8745c5215420a03dc55255",
        downloaded_file_path = "Werkzeug-2.1.2-py3-none-any.whl",
    )

    maybe(
        http_file,
        name = "example_lock_wheel_wrapt_1.14.0_cp39_cp39_macosx_10_9_x86_64",
        urls = [
            "https://files.pythonhosted.org/packages/cp39/w/wrapt/wrapt-1.14.0-cp39-cp39-macosx_10_9_x86_64.whl"
        ],
        sha256 = "b3f7e671fb19734c872566e57ce7fc235fa953d7c181bb4ef138e17d607dc8a1",
        downloaded_file_path = "wrapt-1.14.0-cp39-cp39-macosx_10_9_x86_64.whl",
    )

    maybe(
        http_file,
        name = "example_lock_wheel_wrapt_1.14.0_cp39_cp39_macosx_11_0_arm64",
        urls = [
            "https://files.pythonhosted.org/packages/cp39/w/wrapt/wrapt-1.14.0-cp39-cp39-macosx_11_0_arm64.whl"
        ],
        sha256 = "87fa943e8bbe40c8c1ba4086971a6fefbf75e9991217c55ed1bcb2f1985bd3d4",
        downloaded_file_path = "wrapt-1.14.0-cp39-cp39-macosx_11_0_arm64.whl",
    )

    maybe(
        http_file,
        name = "example_lock_wheel_wrapt_1.14.0_cp39_cp39_manylinux_2_5_x86_64.manylinux1_x86_64.manylinux_2_17_x86_64.manylinux2014_x86_64",
        urls = [
            "https://files.pythonhosted.org/packages/cp39/w/wrapt/wrapt-1.14.0-cp39-cp39-manylinux_2_5_x86_64.manylinux1_x86_64.manylinux_2_17_x86_64.manylinux2014_x86_64.whl"
        ],
        sha256 = "00108411e0f34c52ce16f81f1d308a571df7784932cc7491d1e94be2ee93374b",
        downloaded_file_path = "wrapt-1.14.0-cp39-cp39-manylinux_2_5_x86_64.manylinux1_x86_64.manylinux_2_17_x86_64.manylinux2014_x86_64.whl",
    )

    maybe(
        http_file,
        name = "example_lock_wheel_xmltodict_0.12.0_py2.py3_none_any",
        urls = [
            "https://files.pythonhosted.org/packages/3.7/x/xmltodict/xmltodict-0.12.0-py2.py3-none-any.whl"
        ],
        sha256 = "8bbcb45cc982f48b2ca8fe7e7827c5d792f217ecf1792626f808bf41c3b86051",
        downloaded_file_path = "xmltodict-0.12.0-py2.py3-none-any.whl",
    )

    maybe(
        http_file,
        name = "example_lock_wheel_zipp_3.8.0_py3_none_any",
        urls = [
            "https://files.pythonhosted.org/packages/py3/z/zipp/zipp-3.8.0-py3-none-any.whl"
        ],
        sha256 = "c4f6e5bbf48e74f7a38e7cc5b0480ff42b0ae5178957d564d18932525d5cf099",
        downloaded_file_path = "zipp-3.8.0-py3-none-any.whl",
    )

