load("@bazel_tools//tools/build_defs/repo:http.bzl", "http_file")
load("@bazel_tools//tools/build_defs/repo:utils.bzl", "maybe")
load("@jvolkman_rules_pycross//pycross:defs.bzl", "pycross_wheel_build", "pycross_wheel_library", "pypi_file")

PINS = {
    "appnope": "appnope_0.1.3",
    "asgiref": "asgiref_3.5.2",
    "asttokens": "asttokens_2.0.8",
    "attrs": "attrs_22.1.0",
    "aws_sam_translator": "aws_sam_translator_1.53.0",
    "aws_xray_sdk": "aws_xray_sdk_2.9.0",
    "backcall": "backcall_0.2.0",
    "black": "black_22.10.0",
    "boto3": "boto3_1.24.89",
    "botocore": "botocore_1.27.89",
    "certifi": "certifi_2022.9.24",
    "cffi": "cffi_1.15.1",
    "cfn_lint": "cfn_lint_0.67.0",
    "charset_normalizer": "charset_normalizer_2.1.1",
    "click": "click_8.1.3",
    "cognitojwt": "cognitojwt_1.4.1",
    "cowsay": "cowsay_5.0",
    "cryptography": "cryptography_38.0.1",
    "cython": "cython_0.29.32",
    "decorator": "decorator_5.1.1",
    "defusedxml": "defusedxml_0.7.1",
    "django": "django_4.1.2",
    "django_allauth": "django_allauth_0.51.0",
    "docker": "docker_6.0.0",
    "ecdsa": "ecdsa_0.18.0",
    "executing": "executing_1.1.1",
    "flask": "flask_2.2.2",
    "flask_cors": "flask_cors_3.0.10",
    "future": "future_0.18.2",
    "graphql_core": "graphql_core_3.2.3",
    "greenlet": "greenlet_1.1.3.post0",
    "idna": "idna_3.4",
    "importlib_metadata": "importlib_metadata_5.0.0",
    "ipython": "ipython_8.5.0",
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
    "matplotlib_inline": "matplotlib_inline_0.1.6",
    "moto": "moto_3.1.1",
    "mypy_extensions": "mypy_extensions_0.4.3",
    "networkx": "networkx_2.8.7",
    "numpy": "numpy_1.22.3",
    "oauthlib": "oauthlib_3.2.1",
    "packaging": "packaging_21.3",
    "parso": "parso_0.8.3",
    "pathspec": "pathspec_0.10.1",
    "pbr": "pbr_5.10.0",
    "pexpect": "pexpect_4.8.0",
    "pickleshare": "pickleshare_0.7.5",
    "platformdirs": "platformdirs_2.5.2",
    "prompt_toolkit": "prompt_toolkit_3.0.31",
    "ptyprocess": "ptyprocess_0.7.0",
    "pure_eval": "pure_eval_0.2.2",
    "pyasn1": "pyasn1_0.4.8",
    "pycparser": "pycparser_2.21",
    "pygments": "pygments_2.13.0",
    "pyjwt": "pyjwt_2.5.0",
    "pyparsing": "pyparsing_3.0.9",
    "pyrsistent": "pyrsistent_0.18.1",
    "python3_openid": "python3_openid_3.2.0",
    "python_dateutil": "python_dateutil_2.8.2",
    "python_jose": "python_jose_3.1.0",
    "pytz": "pytz_2022.4",
    "pyyaml": "pyyaml_6.0",
    "requests": "requests_2.28.1",
    "requests_oauthlib": "requests_oauthlib_1.3.1",
    "responses": "responses_0.22.0",
    "rsa": "rsa_4.9",
    "s3transfer": "s3transfer_0.6.0",
    "sarif_om": "sarif_om_1.0.4",
    "setproctitle": "setproctitle_1.2.2",
    "setuptools": "setuptools_59.2.0",
    "six": "six_1.16.0",
    "sqlalchemy": "sqlalchemy_1.4.41",
    "sqlalchemy_utils": "sqlalchemy_utils_0.38.2",
    "sqlparse": "sqlparse_0.4.3",
    "sshpubkeys": "sshpubkeys_3.3.1",
    "stack_data": "stack_data_0.5.1",
    "toml": "toml_0.10.2",
    "tomli": "tomli_2.0.1",
    "traitlets": "traitlets_5.4.0",
    "tree_sitter": "tree_sitter_0.20.0",
    "types_cryptography": "types_cryptography_3.3.23",
    "types_toml": "types_toml_0.10.8",
    "typing_extensions": "typing_extensions_4.4.0",
    "urllib3": "urllib3_1.26.12",
    "wcwidth": "wcwidth_0.2.5",
    "websocket_client": "websocket_client_1.4.1",
    "werkzeug": "werkzeug_2.2.2",
    "wheel": "wheel_0.37.0",
    "wrapt": "wrapt_1.14.1",
    "xmltodict": "xmltodict_0.13.0",
    "zipp": "zipp_3.9.0",
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
        name = "asgiref_3.5.2",
        wheel = "@example_lock_wheel_asgiref_3.5.2_py3_none_any//file",
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

    _aws_sam_translator_1_53_0_deps = [
        ":boto3_1.24.89",
        ":jsonschema_3.2.0",
    ]

    pycross_wheel_library(
        name = "aws_sam_translator_1.53.0",
        deps = _aws_sam_translator_1_53_0_deps,
        wheel = "@example_lock_wheel_aws_sam_translator_1.53.0_py3_none_any//file",
    )

    _aws_xray_sdk_2_9_0_deps = [
        ":botocore_1.27.89",
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

    _black_22_10_0_deps = [
        ":click_8.1.3",
        ":mypy_extensions_0.4.3",
        ":pathspec_0.10.1",
        ":platformdirs_2.5.2",
        ":tomli_2.0.1",
        ":typing_extensions_4.4.0",
    ]

    pycross_wheel_library(
        name = "black_22.10.0",
        deps = _black_22_10_0_deps,
        wheel = select({
            ":_env_python_darwin_arm64": "@example_lock_wheel_black_22.10.0_cp39_cp39_macosx_11_0_arm64//file",
            ":_env_python_darwin_x86_64": "@example_lock_wheel_black_22.10.0_1fixedarch_cp39_cp39_macosx_11_0_x86_64//file",
            ":_env_python_linux_x86_64": "@example_lock_wheel_black_22.10.0_cp39_cp39_manylinux_2_17_x86_64.manylinux2014_x86_64//file",
        }),
    )

    _boto3_1_24_89_deps = [
        ":botocore_1.27.89",
        ":jmespath_1.0.1",
        ":s3transfer_0.6.0",
    ]

    pycross_wheel_library(
        name = "boto3_1.24.89",
        deps = _boto3_1_24_89_deps,
        wheel = "@example_lock_wheel_boto3_1.24.89_py3_none_any//file",
    )

    _botocore_1_27_89_deps = [
        ":jmespath_1.0.1",
        ":python_dateutil_2.8.2",
        ":urllib3_1.26.12",
    ]

    pycross_wheel_library(
        name = "botocore_1.27.89",
        deps = _botocore_1_27_89_deps,
        wheel = "@example_lock_wheel_botocore_1.27.89_py3_none_any//file",
    )

    pycross_wheel_library(
        name = "certifi_2022.9.24",
        wheel = "@example_lock_wheel_certifi_2022.9.24_py3_none_any//file",
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

    _cfn_lint_0_67_0_deps = [
        ":aws_sam_translator_1.53.0",
        ":jschema_to_python_1.2.3",
        ":jsonpatch_1.32",
        ":jsonschema_3.2.0",
        ":junit_xml_1.9",
        ":networkx_2.8.7",
        ":pyyaml_6.0",
        ":sarif_om_1.0.4",
    ]

    pycross_wheel_library(
        name = "cfn_lint_0.67.0",
        deps = _cfn_lint_0_67_0_deps,
        wheel = "@example_lock_wheel_cfn_lint_0.67.0_py3_none_any//file",
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

    pycross_wheel_library(
        name = "defusedxml_0.7.1",
        wheel = "@example_lock_wheel_defusedxml_0.7.1_py2.py3_none_any//file",
    )

    _django_4_1_2_deps = [
        ":asgiref_3.5.2",
        ":sqlparse_0.4.3",
    ]

    pycross_wheel_library(
        name = "django_4.1.2",
        deps = _django_4_1_2_deps,
        wheel = "@example_lock_wheel_django_4.1.2_py3_none_any//file",
    )

    _django_allauth_0_51_0_deps = [
        ":django_4.1.2",
        ":pyjwt_2.5.0",
        ":python3_openid_3.2.0",
        ":requests_2.28.1",
        ":requests_oauthlib_1.3.1",
    ]

    _django_allauth_0_51_0_build_deps = [
        ":setuptools_59.2.0",
        ":wheel_0.37.0",
    ]

    pycross_wheel_build(
        name = "_build_django_allauth_0.51.0",
        sdist = "@example_lock_sdist_django_allauth_0.51.0//file",
        target_environment = _target,
        deps = _django_allauth_0_51_0_deps + _django_allauth_0_51_0_build_deps,
        tags = ["manual"],
    )

    pycross_wheel_library(
        name = "django_allauth_0.51.0",
        deps = _django_allauth_0_51_0_deps,
        wheel = ":_build_django_allauth_0.51.0",
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
        name = "executing_1.1.1",
        wheel = "@example_lock_wheel_executing_1.1.1_py2.py3_none_any//file",
    )

    _flask_2_2_2_deps = [
        ":click_8.1.3",
        ":importlib_metadata_5.0.0",
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
        name = "graphql_core_3.2.3",
        wheel = "@example_lock_wheel_graphql_core_3.2.3_py3_none_any//file",
    )

    _greenlet_1_1_3_post0_build_deps = [
        ":setuptools_59.2.0",
        ":wheel_0.37.0",
    ]

    pycross_wheel_build(
        name = "_build_greenlet_1.1.3.post0",
        sdist = "@example_lock_sdist_greenlet_1.1.3.post0//file",
        target_environment = _target,
        deps = _greenlet_1_1_3_post0_build_deps,
        tags = ["manual"],
    )

    pycross_wheel_library(
        name = "greenlet_1.1.3.post0",
        wheel = select({
            ":_env_python_darwin_arm64": ":_build_greenlet_1.1.3.post0",
            ":_env_python_darwin_x86_64": "@example_lock_wheel_greenlet_1.1.3.post0_cp39_cp39_macosx_10_15_x86_64//file",
            ":_env_python_linux_x86_64": "@example_lock_wheel_greenlet_1.1.3.post0_cp39_cp39_manylinux_2_17_x86_64.manylinux2014_x86_64//file",
        }),
    )

    pycross_wheel_library(
        name = "idna_3.4",
        wheel = "@example_lock_wheel_idna_3.4_py3_none_any//file",
    )

    _importlib_metadata_5_0_0_deps = [
        ":zipp_3.9.0",
    ]

    pycross_wheel_library(
        name = "importlib_metadata_5.0.0",
        deps = _importlib_metadata_5_0_0_deps,
        wheel = "@example_lock_wheel_importlib_metadata_5.0.0_py3_none_any//file",
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
        ":stack_data_0.5.1",
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

    _moto_3_1_1_deps = [
        ":aws_xray_sdk_2.9.0",
        ":boto3_1.24.89",
        ":botocore_1.27.89",
        ":cfn_lint_0.67.0",
        ":cryptography_38.0.1",
        ":docker_6.0.0",
        ":ecdsa_0.18.0",
        ":flask_2.2.2",
        ":flask_cors_3.0.10",
        ":graphql_core_3.2.3",
        ":idna_3.4",
        ":jinja2_3.1.2",
        ":jsondiff_2.0.0",
        ":markupsafe_2.1.1",
        ":python_dateutil_2.8.2",
        ":python_jose_3.1.0",
        ":pytz_2022.4",
        ":pyyaml_6.0",
        ":requests_2.28.1",
        ":responses_0.22.0",
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
        name = "mypy_extensions_0.4.3",
        wheel = "@example_lock_wheel_mypy_extensions_0.4.3_py2.py3_none_any//file",
    )

    pycross_wheel_library(
        name = "networkx_2.8.7",
        wheel = "@example_lock_wheel_networkx_2.8.7_py3_none_any//file",
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
        name = "oauthlib_3.2.1",
        wheel = "@example_lock_wheel_oauthlib_3.2.1_py3_none_any//file",
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

    pycross_wheel_library(
        name = "pathspec_0.10.1",
        wheel = "@example_lock_wheel_pathspec_0.10.1_py3_none_any//file",
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

    pycross_wheel_library(
        name = "platformdirs_2.5.2",
        wheel = "@example_lock_wheel_platformdirs_2.5.2_py3_none_any//file",
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

    _pyjwt_2_5_0_deps = [
        ":cryptography_38.0.1",
        ":types_cryptography_3.3.23",
    ]

    pycross_wheel_library(
        name = "pyjwt_2.5.0",
        deps = _pyjwt_2_5_0_deps,
        wheel = "@example_lock_wheel_pyjwt_2.5.0_py3_none_any//file",
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

    _python3_openid_3_2_0_deps = [
        ":defusedxml_0.7.1",
    ]

    pycross_wheel_library(
        name = "python3_openid_3.2.0",
        deps = _python3_openid_3_2_0_deps,
        wheel = "@example_lock_wheel_python3_openid_3.2.0_py3_none_any//file",
    )

    pycross_wheel_library(
        name = "pytz_2022.4",
        wheel = "@example_lock_wheel_pytz_2022.4_py2.py3_none_any//file",
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
        ":certifi_2022.9.24",
        ":charset_normalizer_2.1.1",
        ":idna_3.4",
        ":urllib3_1.26.12",
    ]

    pycross_wheel_library(
        name = "requests_2.28.1",
        deps = _requests_2_28_1_deps,
        wheel = "@example_lock_wheel_requests_2.28.1_py3_none_any//file",
    )

    _requests_oauthlib_1_3_1_deps = [
        ":oauthlib_3.2.1",
        ":requests_2.28.1",
    ]

    pycross_wheel_library(
        name = "requests_oauthlib_1.3.1",
        deps = _requests_oauthlib_1_3_1_deps,
        wheel = "@example_lock_wheel_requests_oauthlib_1.3.1_py2.py3_none_any//file",
    )

    _responses_0_22_0_deps = [
        ":requests_2.28.1",
        ":toml_0.10.2",
        ":types_toml_0.10.8",
        ":urllib3_1.26.12",
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
        ":botocore_1.27.89",
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
        ":greenlet_1.1.3.post0",
    ]

    _sqlalchemy_1_4_41_build_deps = [
        ":setuptools_59.2.0",
        ":wheel_0.37.0",
    ]

    pycross_wheel_build(
        name = "_build_sqlalchemy_1.4.41",
        sdist = "@example_lock_sdist_sqlalchemy_1.4.41//file",
        target_environment = _target,
        deps = _sqlalchemy_1_4_41_deps + _sqlalchemy_1_4_41_build_deps,
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

    pycross_wheel_library(
        name = "sqlparse_0.4.3",
        wheel = "@example_lock_wheel_sqlparse_0.4.3_py3_none_any//file",
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

    _stack_data_0_5_1_deps = [
        ":asttokens_2.0.8",
        ":executing_1.1.1",
        ":pure_eval_0.2.2",
    ]

    pycross_wheel_library(
        name = "stack_data_0.5.1",
        deps = _stack_data_0_5_1_deps,
        wheel = "@example_lock_wheel_stack_data_0.5.1_py3_none_any//file",
    )

    pycross_wheel_library(
        name = "toml_0.10.2",
        wheel = "@example_lock_wheel_toml_0.10.2_py2.py3_none_any//file",
    )

    pycross_wheel_library(
        name = "tomli_2.0.1",
        wheel = "@example_lock_wheel_tomli_2.0.1_py3_none_any//file",
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
        name = "types_cryptography_3.3.23",
        wheel = "@example_lock_wheel_types_cryptography_3.3.23_py3_none_any//file",
    )

    pycross_wheel_library(
        name = "types_toml_0.10.8",
        wheel = "@example_lock_wheel_types_toml_0.10.8_py3_none_any//file",
    )

    pycross_wheel_library(
        name = "typing_extensions_4.4.0",
        wheel = "@example_lock_wheel_typing_extensions_4.4.0_py3_none_any//file",
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
        name = "zipp_3.9.0",
        wheel = "@example_lock_wheel_zipp_3.9.0_py3_none_any//file",
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
        name = "example_lock_sdist_django_allauth_0.51.0",
        urls = [
            "https://files.pythonhosted.org/packages/44/cf/ef0354010b6621b0d2053dc25ddce0132635fb0cbcfebf32a947877fb78e/django-allauth-0.51.0.tar.gz"
        ],
        sha256 = "ca1622733b6faa591580ccd3984042f12d8c79ade93438212de249b7ffb6f91f",
        downloaded_file_path = "django-allauth-0.51.0.tar.gz",
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
        name = "example_lock_sdist_greenlet_1.1.3.post0",
        urls = [
            "https://files.pythonhosted.org/packages/ea/37/e54ce453b298e890f59dba3db32461579328a07d5b65e3eabf80f971c099/greenlet-1.1.3.post0.tar.gz"
        ],
        sha256 = "f5e09dc5c6e1796969fd4b775ea1417d70e49a5df29aaa8e5d10675d9e11872c",
        downloaded_file_path = "greenlet-1.1.3.post0.tar.gz",
    )

    maybe(
        http_file,
        name = "example_lock_sdist_pbr_5.10.0",
        urls = [
            "https://files.pythonhosted.org/packages/b4/40/4c5d3681b141a10c24c890c28345fac915dd67f34b8c910df7b81ac5c7b3/pbr-5.10.0.tar.gz"
        ],
        sha256 = "cfcc4ff8e698256fc17ea3ff796478b050852585aa5bae79ecd05b2ab7b39b9a",
        downloaded_file_path = "pbr-5.10.0.tar.gz",
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
        name = "example_lock_sdist_sqlalchemy_1.4.41",
        urls = [
            "https://files.pythonhosted.org/packages/67/a0/97da2cb07e013fd6c37fd896a86b374aa726e4161cafd57185e8418d59aa/SQLAlchemy-1.4.41.tar.gz"
        ],
        sha256 = "0292f70d1797e3c54e862e6f30ae474014648bc9c723e14a2fda730adb0a9791",
        downloaded_file_path = "SQLAlchemy-1.4.41.tar.gz",
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
        name = "example_lock_wheel_asgiref_3.5.2_py3_none_any",
        urls = [
            "https://files.pythonhosted.org/packages/af/6d/ea3a5c3027c3f14b0321cd4f7e594c776ebe64e4b927432ca6917512a4f7/asgiref-3.5.2-py3-none-any.whl"
        ],
        sha256 = "1d2880b792ae8757289136f1db2b7b99100ce959b2aa57fd69dab783d05afac4",
        downloaded_file_path = "asgiref-3.5.2-py3-none-any.whl",
    )

    maybe(
        http_file,
        name = "example_lock_wheel_asttokens_2.0.8_py2.py3_none_any",
        urls = [
            "https://files.pythonhosted.org/packages/2d/1b/fdbdf82b86e07ca90985740ac160a1dd4ab09cb81071ec12d71c701e1138/asttokens-2.0.8-py2.py3-none-any.whl"
        ],
        sha256 = "e3305297c744ae53ffa032c45dc347286165e4ffce6875dc662b205db0623d86",
        downloaded_file_path = "asttokens-2.0.8-py2.py3-none-any.whl",
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
        name = "example_lock_wheel_aws_sam_translator_1.53.0_py3_none_any",
        urls = [
            "https://files.pythonhosted.org/packages/11/c3/544208b4230572bf4146e2ab284c45132c8e280352d539408352785863e9/aws_sam_translator-1.53.0-py3-none-any.whl"
        ],
        sha256 = "84d780ad82f1a176e2f5d4c397749d1e71214cc97ee7cccd50f823fd7c7e7cdf",
        downloaded_file_path = "aws_sam_translator-1.53.0-py3-none-any.whl",
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
        name = "example_lock_wheel_black_22.10.0_1fixedarch_cp39_cp39_macosx_11_0_x86_64",
        urls = [
            "https://files.pythonhosted.org/packages/f2/23/f4278377cabf882298b4766e977fd04377f288d1ccef706953076a1e0598/black-22.10.0-1fixedarch-cp39-cp39-macosx_11_0_x86_64.whl"
        ],
        sha256 = "e41a86c6c650bcecc6633ee3180d80a025db041a8e2398dcc059b3afa8382cd4",
        downloaded_file_path = "black-22.10.0-1fixedarch-cp39-cp39-macosx_11_0_x86_64.whl",
    )

    maybe(
        http_file,
        name = "example_lock_wheel_black_22.10.0_cp39_cp39_macosx_11_0_arm64",
        urls = [
            "https://files.pythonhosted.org/packages/69/84/903cdf41514088d5a716538cb189c471ab34e56ae9a1c2da6b8bfe8e4dbf/black-22.10.0-cp39-cp39-macosx_11_0_arm64.whl"
        ],
        sha256 = "974308c58d057a651d182208a484ce80a26dac0caef2895836a92dd6ebd725e0",
        downloaded_file_path = "black-22.10.0-cp39-cp39-macosx_11_0_arm64.whl",
    )

    maybe(
        http_file,
        name = "example_lock_wheel_black_22.10.0_cp39_cp39_manylinux_2_17_x86_64.manylinux2014_x86_64",
        urls = [
            "https://files.pythonhosted.org/packages/b9/51/403b0b0eb9fb412ca02b79dc38472469f2f88c9aacc6bb5262143e4ff0bc/black-22.10.0-cp39-cp39-manylinux_2_17_x86_64.manylinux2014_x86_64.whl"
        ],
        sha256 = "72ef3925f30e12a184889aac03d77d031056860ccae8a1e519f6cbb742736383",
        downloaded_file_path = "black-22.10.0-cp39-cp39-manylinux_2_17_x86_64.manylinux2014_x86_64.whl",
    )

    maybe(
        http_file,
        name = "example_lock_wheel_boto3_1.24.89_py3_none_any",
        urls = [
            "https://files.pythonhosted.org/packages/d7/5f/30a665d913e8ba1d04aec3a5326f1fae6e25490ee4543d3f15e18e57c4bb/boto3-1.24.89-py3-none-any.whl"
        ],
        sha256 = "346f8f0d101a4261dac146a959df18d024feda6431e1d9d84f94efd24d086cae",
        downloaded_file_path = "boto3-1.24.89-py3-none-any.whl",
    )

    maybe(
        http_file,
        name = "example_lock_wheel_botocore_1.27.89_py3_none_any",
        urls = [
            "https://files.pythonhosted.org/packages/28/33/5013ab7409efcbb580bc0420920abd2649337712790a648eb30a897c9fce/botocore-1.27.89-py3-none-any.whl"
        ],
        sha256 = "238f1dfdb8d8d017c2aea082609a3764f3161d32745900f41bcdcf290d95a048",
        downloaded_file_path = "botocore-1.27.89-py3-none-any.whl",
    )

    maybe(
        http_file,
        name = "example_lock_wheel_certifi_2022.9.24_py3_none_any",
        urls = [
            "https://files.pythonhosted.org/packages/1d/38/fa96a426e0c0e68aabc68e896584b83ad1eec779265a028e156ce509630e/certifi-2022.9.24-py3-none-any.whl"
        ],
        sha256 = "90c1a32f1d68f940488354e36370f6cca89f0f106db09518524c88d6ed83f382",
        downloaded_file_path = "certifi-2022.9.24-py3-none-any.whl",
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
        name = "example_lock_wheel_cfn_lint_0.67.0_py3_none_any",
        urls = [
            "https://files.pythonhosted.org/packages/15/95/f5ff03005ae70d95e8ffc359ad463893bec4361f477445a7c1090f816098/cfn_lint-0.67.0-py3-none-any.whl"
        ],
        sha256 = "3526213b91f1740231cac894652046daa77409a0c0ca755589ab21d5faab8fd1",
        downloaded_file_path = "cfn_lint-0.67.0-py3-none-any.whl",
    )

    maybe(
        http_file,
        name = "example_lock_wheel_charset_normalizer_2.1.1_py3_none_any",
        urls = [
            "https://files.pythonhosted.org/packages/db/51/a507c856293ab05cdc1db77ff4bc1268ddd39f29e7dc4919aa497f0adbec/charset_normalizer-2.1.1-py3-none-any.whl"
        ],
        sha256 = "83e9a75d1911279afd89352c68b45348559d1fc0506b054b346651b5e7fee29f",
        downloaded_file_path = "charset_normalizer-2.1.1-py3-none-any.whl",
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
        name = "example_lock_wheel_cryptography_38.0.1_cp36_abi3_macosx_10_10_universal2",
        urls = [
            "https://files.pythonhosted.org/packages/c2/f5/5ca3e00f8131b2d6d70cd5fc54079c7e5c3a2c28f863bd3980bf4d6b970f/cryptography-38.0.1-cp36-abi3-macosx_10_10_universal2.whl"
        ],
        sha256 = "10d1f29d6292fc95acb597bacefd5b9e812099d75a6469004fd38ba5471a977f",
        downloaded_file_path = "cryptography-38.0.1-cp36-abi3-macosx_10_10_universal2.whl",
    )

    maybe(
        http_file,
        name = "example_lock_wheel_cryptography_38.0.1_cp36_abi3_macosx_10_10_x86_64",
        urls = [
            "https://files.pythonhosted.org/packages/4b/25/c995d4269baceab3288c89f74cb08788a973f8f293758934387ebacdef08/cryptography-38.0.1-cp36-abi3-macosx_10_10_x86_64.whl"
        ],
        sha256 = "3fc26e22840b77326a764ceb5f02ca2d342305fba08f002a8c1f139540cdfaad",
        downloaded_file_path = "cryptography-38.0.1-cp36-abi3-macosx_10_10_x86_64.whl",
    )

    maybe(
        http_file,
        name = "example_lock_wheel_cryptography_38.0.1_cp36_abi3_manylinux_2_17_x86_64.manylinux2014_x86_64",
        urls = [
            "https://files.pythonhosted.org/packages/1c/e5/1deb15c5c38bf0826c85e480cc05402553427663db9ae45e63ee3b06ba4d/cryptography-38.0.1-cp36-abi3-manylinux_2_17_x86_64.manylinux2014_x86_64.whl"
        ],
        sha256 = "ca9f6784ea96b55ff41708b92c3f6aeaebde4c560308e5fbbd3173fbc466e94e",
        downloaded_file_path = "cryptography-38.0.1-cp36-abi3-manylinux_2_17_x86_64.manylinux2014_x86_64.whl",
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
        name = "example_lock_wheel_defusedxml_0.7.1_py2.py3_none_any",
        urls = [
            "https://files.pythonhosted.org/packages/07/6c/aa3f2f849e01cb6a001cd8554a88d4c77c5c1a31c95bdf1cf9301e6d9ef4/defusedxml-0.7.1-py2.py3-none-any.whl"
        ],
        sha256 = "a352e7e428770286cc899e2542b6cdaedb2b4953ff269a210103ec58f6198a61",
        downloaded_file_path = "defusedxml-0.7.1-py2.py3-none-any.whl",
    )

    maybe(
        http_file,
        name = "example_lock_wheel_django_4.1.2_py3_none_any",
        urls = [
            "https://files.pythonhosted.org/packages/91/02/786ced9f0b9980670f46f7563f9c5494a24e3dd1920cc7be6cc7ac377389/Django-4.1.2-py3-none-any.whl"
        ],
        sha256 = "26dc24f99c8956374a054bcbf58aab8dc0cad2e6ac82b0fe036b752c00eee793",
        downloaded_file_path = "Django-4.1.2-py3-none-any.whl",
    )

    maybe(
        http_file,
        name = "example_lock_wheel_docker_6.0.0_py3_none_any",
        urls = [
            "https://files.pythonhosted.org/packages/57/16/71275ff97da8d2b3b1895655182eb18692d234860bfb42366aaf511389af/docker-6.0.0-py3-none-any.whl"
        ],
        sha256 = "6e06ee8eca46cd88733df09b6b80c24a1a556bc5cb1e1ae54b2c239886d245cf",
        downloaded_file_path = "docker-6.0.0-py3-none-any.whl",
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
        name = "example_lock_wheel_executing_1.1.1_py2.py3_none_any",
        urls = [
            "https://files.pythonhosted.org/packages/72/ac/593502a97a0bf7968a2c958a25f5f697ef738f6cd9fcc94d0d6a1493e080/executing-1.1.1-py2.py3-none-any.whl"
        ],
        sha256 = "236ea5f059a38781714a8bfba46a70fad3479c2f552abee3bbafadc57ed111b8",
        downloaded_file_path = "executing-1.1.1-py2.py3-none-any.whl",
    )

    maybe(
        http_file,
        name = "example_lock_wheel_flask_2.2.2_py3_none_any",
        urls = [
            "https://files.pythonhosted.org/packages/0f/43/15f4f9ab225b0b25352412e8daa3d0e3d135fcf5e127070c74c3632c8b4c/Flask-2.2.2-py3-none-any.whl"
        ],
        sha256 = "b9c46cc36662a7949f34b52d8ec7bb59c0d74ba08ba6cb9ce9adc1d8676d9526",
        downloaded_file_path = "Flask-2.2.2-py3-none-any.whl",
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
        name = "example_lock_wheel_graphql_core_3.2.3_py3_none_any",
        urls = [
            "https://files.pythonhosted.org/packages/f8/39/e5143e7ec70939d2076c1165ae9d4a3815597019c4d797b7f959cf778600/graphql_core-3.2.3-py3-none-any.whl"
        ],
        sha256 = "5766780452bd5ec8ba133f8bf287dc92713e3868ddd83aee4faab9fc3e303dc3",
        downloaded_file_path = "graphql_core-3.2.3-py3-none-any.whl",
    )

    maybe(
        http_file,
        name = "example_lock_wheel_greenlet_1.1.3.post0_cp39_cp39_macosx_10_15_x86_64",
        urls = [
            "https://files.pythonhosted.org/packages/c6/ff/4824bda7f85046296a59570040d5c77ef7b71fcf7577844efcfc9a4a0196/greenlet-1.1.3.post0-cp39-cp39-macosx_10_15_x86_64.whl"
        ],
        sha256 = "c8c9301e3274276d3d20ab6335aa7c5d9e5da2009cccb01127bddb5c951f8870",
        downloaded_file_path = "greenlet-1.1.3.post0-cp39-cp39-macosx_10_15_x86_64.whl",
    )

    maybe(
        http_file,
        name = "example_lock_wheel_greenlet_1.1.3.post0_cp39_cp39_manylinux_2_17_x86_64.manylinux2014_x86_64",
        urls = [
            "https://files.pythonhosted.org/packages/8b/e2/07206a72c1660ce801d2f1635c1314a3706592d35564e4f75d27c4c426eb/greenlet-1.1.3.post0-cp39-cp39-manylinux_2_17_x86_64.manylinux2014_x86_64.whl"
        ],
        sha256 = "7cf37343e43404699d58808e51f347f57efd3010cc7cee134cdb9141bd1ad9ea",
        downloaded_file_path = "greenlet-1.1.3.post0-cp39-cp39-manylinux_2_17_x86_64.manylinux2014_x86_64.whl",
    )

    maybe(
        http_file,
        name = "example_lock_wheel_idna_3.4_py3_none_any",
        urls = [
            "https://files.pythonhosted.org/packages/fc/34/3030de6f1370931b9dbb4dad48f6ab1015ab1d32447850b9fc94e60097be/idna-3.4-py3-none-any.whl"
        ],
        sha256 = "90b77e79eaa3eba6de819a0c442c0b4ceefc341a7a2ab77d7562bf49f425c5c2",
        downloaded_file_path = "idna-3.4-py3-none-any.whl",
    )

    maybe(
        http_file,
        name = "example_lock_wheel_importlib_metadata_5.0.0_py3_none_any",
        urls = [
            "https://files.pythonhosted.org/packages/b5/64/ef29a63cf08f047bb7fb22ab0f1f774b87eed0bb46d067a5a524798a4af8/importlib_metadata-5.0.0-py3-none-any.whl"
        ],
        sha256 = "ddb0e35065e8938f867ed4928d0ae5bf2a53b7773871bfe6bcc7e4fcdc7dea43",
        downloaded_file_path = "importlib_metadata-5.0.0-py3-none-any.whl",
    )

    maybe(
        http_file,
        name = "example_lock_wheel_ipython_8.5.0_py3_none_any",
        urls = [
            "https://files.pythonhosted.org/packages/13/0d/ad3266203acb01189588aac9c1fc4dc982b58b0512ddb3cd4bea3cc26e22/ipython-8.5.0-py3-none-any.whl"
        ],
        sha256 = "6f090e29ab8ef8643e521763a4f1f39dc3914db643122b1e9d3328ff2e43ada2",
        downloaded_file_path = "ipython-8.5.0-py3-none-any.whl",
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
        name = "example_lock_wheel_matplotlib_inline_0.1.6_py3_none_any",
        urls = [
            "https://files.pythonhosted.org/packages/f2/51/c34d7a1d528efaae3d8ddb18ef45a41f284eacf9e514523b191b7d0872cc/matplotlib_inline-0.1.6-py3-none-any.whl"
        ],
        sha256 = "f1f41aab5328aa5aaea9b16d083b128102f8712542f819fe7e6a420ff581b311",
        downloaded_file_path = "matplotlib_inline-0.1.6-py3-none-any.whl",
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
        name = "example_lock_wheel_networkx_2.8.7_py3_none_any",
        urls = [
            "https://files.pythonhosted.org/packages/d0/00/1713dd6735d5a646cabdd99ff750e969795134d7d33f462ad71dfd07fa76/networkx-2.8.7-py3-none-any.whl"
        ],
        sha256 = "15cdf7f7c157637107ea690cabbc488018f8256fa28242aed0fb24c93c03a06d",
        downloaded_file_path = "networkx-2.8.7-py3-none-any.whl",
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
        name = "example_lock_wheel_oauthlib_3.2.1_py3_none_any",
        urls = [
            "https://files.pythonhosted.org/packages/92/bb/d669baf53d4ffe081dab80aad93c5c79f84eeac885dd31507c8c055a98d5/oauthlib-3.2.1-py3-none-any.whl"
        ],
        sha256 = "88e912ca1ad915e1dcc1c06fc9259d19de8deacd6fd17cc2df266decc2e49066",
        downloaded_file_path = "oauthlib-3.2.1-py3-none-any.whl",
    )

    maybe(
        http_file,
        name = "example_lock_wheel_packaging_21.3_py3_none_any",
        urls = [
            "https://files.pythonhosted.org/packages/05/8e/8de486cbd03baba4deef4142bd643a3e7bbe954a784dc1bb17142572d127/packaging-21.3-py3-none-any.whl"
        ],
        sha256 = "ef103e05f519cdc783ae24ea4e2e0f508a9c99b2d4969652eed6a2e1ea5bd522",
        downloaded_file_path = "packaging-21.3-py3-none-any.whl",
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
        name = "example_lock_wheel_pathspec_0.10.1_py3_none_any",
        urls = [
            "https://files.pythonhosted.org/packages/63/82/2179fdc39bc1bb43296f638ae1dfe2581ec2617b4e87c28b0d23d44b997f/pathspec-0.10.1-py3-none-any.whl"
        ],
        sha256 = "46846318467efc4556ccfd27816e004270a9eeeeb4d062ce5e6fc7a87c573f93",
        downloaded_file_path = "pathspec-0.10.1-py3-none-any.whl",
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
        name = "example_lock_wheel_prompt_toolkit_3.0.31_py3_none_any",
        urls = [
            "https://files.pythonhosted.org/packages/26/ec/2ebddd1f0584fec4a6d4b5dc57627254070c3db310f00981bc5de03dd5ab/prompt_toolkit-3.0.31-py3-none-any.whl"
        ],
        sha256 = "9696f386133df0fc8ca5af4895afe5d78f5fcfe5258111c2a79a1c3e41ffa96d",
        downloaded_file_path = "prompt_toolkit-3.0.31-py3-none-any.whl",
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
        name = "example_lock_wheel_pygments_2.13.0_py3_none_any",
        urls = [
            "https://files.pythonhosted.org/packages/4f/82/672cd382e5b39ab1cd422a672382f08a1fb3d08d9e0c0f3707f33a52063b/Pygments-2.13.0-py3-none-any.whl"
        ],
        sha256 = "f643f331ab57ba3c9d89212ee4a2dabc6e94f117cf4eefde99a0574720d14c42",
        downloaded_file_path = "Pygments-2.13.0-py3-none-any.whl",
    )

    maybe(
        http_file,
        name = "example_lock_wheel_pyjwt_2.5.0_py3_none_any",
        urls = [
            "https://files.pythonhosted.org/packages/37/82/43382713811f0ddd9fff1ed778af6818cc2080ccd425e3eba540be690fb6/PyJWT-2.5.0-py3-none-any.whl"
        ],
        sha256 = "8d82e7087868e94dd8d7d418e5088ce64f7daab4b36db654cbaedb46f9d1ca80",
        downloaded_file_path = "PyJWT-2.5.0-py3-none-any.whl",
    )

    maybe(
        http_file,
        name = "example_lock_wheel_pyparsing_3.0.9_py3_none_any",
        urls = [
            "https://files.pythonhosted.org/packages/6c/10/a7d0fa5baea8fe7b50f448ab742f26f52b80bfca85ac2be9d35cdd9a3246/pyparsing-3.0.9-py3-none-any.whl"
        ],
        sha256 = "5026bae9a10eeaefb61dab2f09052b9f4307d44aee4eda64b309723d8d206bbc",
        downloaded_file_path = "pyparsing-3.0.9-py3-none-any.whl",
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
        name = "example_lock_wheel_python3_openid_3.2.0_py3_none_any",
        urls = [
            "https://files.pythonhosted.org/packages/e0/a5/c6ba13860bdf5525f1ab01e01cc667578d6f1efc8a1dba355700fb04c29b/python3_openid-3.2.0-py3-none-any.whl"
        ],
        sha256 = "6626f771e0417486701e0b4daff762e7212e820ca5b29fcc0d05f6f8736dfa6b",
        downloaded_file_path = "python3_openid-3.2.0-py3-none-any.whl",
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
        name = "example_lock_wheel_pytz_2022.4_py2.py3_none_any",
        urls = [
            "https://files.pythonhosted.org/packages/d8/66/309545413162bc8271c73e622499a41cdc37217b499febe26155ff9f93ed/pytz-2022.4-py2.py3-none-any.whl"
        ],
        sha256 = "2c0784747071402c6e99f0bafdb7da0fa22645f06554c7ae06bf6358897e9c91",
        downloaded_file_path = "pytz-2022.4-py2.py3-none-any.whl",
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
        name = "example_lock_wheel_requests_oauthlib_1.3.1_py2.py3_none_any",
        urls = [
            "https://files.pythonhosted.org/packages/6f/bb/5deac77a9af870143c684ab46a7934038a53eb4aa975bc0687ed6ca2c610/requests_oauthlib-1.3.1-py2.py3-none-any.whl"
        ],
        sha256 = "2577c501a2fb8d05a304c09d090d6e47c306fef15809d102b327cf8364bddab5",
        downloaded_file_path = "requests_oauthlib-1.3.1-py2.py3-none-any.whl",
    )

    maybe(
        http_file,
        name = "example_lock_wheel_responses_0.22.0_py3_none_any",
        urls = [
            "https://files.pythonhosted.org/packages/a4/d0/2b9030eedf7061ac60828fcd92a4b04dc9a7dd07f316300f2841c41421a0/responses-0.22.0-py3-none-any.whl"
        ],
        sha256 = "dcf294d204d14c436fddcc74caefdbc5764795a40ff4e6a7740ed8ddbf3294be",
        downloaded_file_path = "responses-0.22.0-py3-none-any.whl",
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
        name = "example_lock_wheel_sqlalchemy_1.4.41_cp39_cp39_macosx_10_15_x86_64",
        urls = [
            "https://files.pythonhosted.org/packages/bc/a9/f9eb3d4952bfa67f7489732af8db2c31b2e99b6b2f70f786fb6d92b18ebb/SQLAlchemy-1.4.41-cp39-cp39-macosx_10_15_x86_64.whl"
        ],
        sha256 = "199a73c31ac8ea59937cc0bf3dfc04392e81afe2ec8a74f26f489d268867846c",
        downloaded_file_path = "SQLAlchemy-1.4.41-cp39-cp39-macosx_10_15_x86_64.whl",
    )

    maybe(
        http_file,
        name = "example_lock_wheel_sqlalchemy_1.4.41_cp39_cp39_manylinux_2_5_x86_64.manylinux1_x86_64.manylinux_2_17_x86_64.manylinux2014_x86_64",
        urls = [
            "https://files.pythonhosted.org/packages/ce/b7/1b65516236b36b55624768f7923c9a8d55ca4ba239b795ea84cb82086718/SQLAlchemy-1.4.41-cp39-cp39-manylinux_2_5_x86_64.manylinux1_x86_64.manylinux_2_17_x86_64.manylinux2014_x86_64.whl"
        ],
        sha256 = "2307495d9e0ea00d0c726be97a5b96615035854972cc538f6e7eaed23a35886c",
        downloaded_file_path = "SQLAlchemy-1.4.41-cp39-cp39-manylinux_2_5_x86_64.manylinux1_x86_64.manylinux_2_17_x86_64.manylinux2014_x86_64.whl",
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
        name = "example_lock_wheel_sqlparse_0.4.3_py3_none_any",
        urls = [
            "https://files.pythonhosted.org/packages/97/d3/31dd2c3e48fc2060819f4acb0686248250a0f2326356306b38a42e059144/sqlparse-0.4.3-py3-none-any.whl"
        ],
        sha256 = "0323c0ec29cd52bceabc1b4d9d579e311f3e4961b98d174201d5622a23b85e34",
        downloaded_file_path = "sqlparse-0.4.3-py3-none-any.whl",
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
        name = "example_lock_wheel_stack_data_0.5.1_py3_none_any",
        urls = [
            "https://files.pythonhosted.org/packages/57/dc/9367ef8074e2331706fbad14d749157341fbffd21339c43820e07664ec94/stack_data-0.5.1-py3-none-any.whl"
        ],
        sha256 = "5120731a18ba4c82cefcf84a945f6f3e62319ef413bfc210e32aca3a69310ba2",
        downloaded_file_path = "stack_data-0.5.1-py3-none-any.whl",
    )

    maybe(
        http_file,
        name = "example_lock_wheel_toml_0.10.2_py2.py3_none_any",
        urls = [
            "https://files.pythonhosted.org/packages/44/6f/7120676b6d73228c96e17f1f794d8ab046fc910d781c8d151120c3f1569e/toml-0.10.2-py2.py3-none-any.whl"
        ],
        sha256 = "806143ae5bfb6a3c6e736a764057db0e6a0e05e338b5630894a5f779cabb4f9b",
        downloaded_file_path = "toml-0.10.2-py2.py3-none-any.whl",
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
        name = "example_lock_wheel_traitlets_5.4.0_py3_none_any",
        urls = [
            "https://files.pythonhosted.org/packages/7d/28/8f4757d68ee7c46e0733dda81595f1bd107fda7bc0c6a577912387e87d86/traitlets-5.4.0-py3-none-any.whl"
        ],
        sha256 = "93663cc8236093d48150e2af5e2ed30fc7904a11a6195e21bab0408af4e6d6c8",
        downloaded_file_path = "traitlets-5.4.0-py3-none-any.whl",
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
        name = "example_lock_wheel_types_cryptography_3.3.23_py3_none_any",
        urls = [
            "https://files.pythonhosted.org/packages/61/a0/fba2c191b4a0741b037032d2ce99afb959be84fa758ef185b450fa594c1a/types_cryptography-3.3.23-py3-none-any.whl"
        ],
        sha256 = "913b3e66a502edbf4bfc3bb45e33ab476040c56942164a7ff37bd1f0ef8ef783",
        downloaded_file_path = "types_cryptography-3.3.23-py3-none-any.whl",
    )

    maybe(
        http_file,
        name = "example_lock_wheel_types_toml_0.10.8_py3_none_any",
        urls = [
            "https://files.pythonhosted.org/packages/ae/2c/a642f8cfa7f9e67c29316bf04b7675db292d006275c67ec07f0c0069cf91/types_toml-0.10.8-py3-none-any.whl"
        ],
        sha256 = "8300fd093e5829eb9c1fba69cee38130347d4b74ddf32d0a7df650ae55c2b599",
        downloaded_file_path = "types_toml-0.10.8-py3-none-any.whl",
    )

    maybe(
        http_file,
        name = "example_lock_wheel_typing_extensions_4.4.0_py3_none_any",
        urls = [
            "https://files.pythonhosted.org/packages/0b/8e/f1a0a5a76cfef77e1eb6004cb49e5f8d72634da638420b9ea492ce8305e8/typing_extensions-4.4.0-py3-none-any.whl"
        ],
        sha256 = "16fa4864408f655d35ec496218b85f79b3437c829e93320c7c9215ccfd92489e",
        downloaded_file_path = "typing_extensions-4.4.0-py3-none-any.whl",
    )

    maybe(
        http_file,
        name = "example_lock_wheel_urllib3_1.26.12_py2.py3_none_any",
        urls = [
            "https://files.pythonhosted.org/packages/6f/de/5be2e3eed8426f871b170663333a0f627fc2924cc386cd41be065e7ea870/urllib3-1.26.12-py2.py3-none-any.whl"
        ],
        sha256 = "b930dd878d5a8afb066a637fbb35144fe7901e3b209d1cd4f524bd0e9deee997",
        downloaded_file_path = "urllib3-1.26.12-py2.py3-none-any.whl",
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
        name = "example_lock_wheel_websocket_client_1.4.1_py3_none_any",
        urls = [
            "https://files.pythonhosted.org/packages/83/b8/95c2512818d6ddb9b97f4163e915b2afe2db42b620270aa59c5ee0b47245/websocket_client-1.4.1-py3-none-any.whl"
        ],
        sha256 = "398909eb7e261f44b8f4bd474785b6ec5f5b499d4953342fe9755e01ef624090",
        downloaded_file_path = "websocket_client-1.4.1-py3-none-any.whl",
    )

    maybe(
        http_file,
        name = "example_lock_wheel_werkzeug_2.2.2_py3_none_any",
        urls = [
            "https://files.pythonhosted.org/packages/c8/27/be6ddbcf60115305205de79c29004a0c6bc53cec814f733467b1bb89386d/Werkzeug-2.2.2-py3-none-any.whl"
        ],
        sha256 = "f979ab81f58d7318e064e99c4506445d60135ac5cd2e177a2de0089bfd4c9bd5",
        downloaded_file_path = "Werkzeug-2.2.2-py3-none-any.whl",
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
        name = "example_lock_wheel_zipp_3.9.0_py3_none_any",
        urls = [
            "https://files.pythonhosted.org/packages/09/85/302c153615db93e9197f13e02f448b3f95d7d786948f2fb3d6d5830a481b/zipp-3.9.0-py3-none-any.whl"
        ],
        sha256 = "972cfa31bc2fedd3fa838a51e9bc7e64b7fb725a8c00e7431554311f180e9980",
        downloaded_file_path = "zipp-3.9.0-py3-none-any.whl",
    )

