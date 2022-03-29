load("@bazel_tools//tools/build_defs/repo:http.bzl", "http_file")
load("@rules_python//python:defs.bzl", "py_library")
load("@jvolkman_rules_pycross//pycross:defs.bzl", "pycross_wheel_build", "pycross_wheel_library")

def targets():
    native.config_setting(
        name = "example_lock_env_python_darwin_arm64",
        constraint_values = [
            "@platforms//os:osx",
            "@platforms//cpu:arm64",
        ],
    )

    native.config_setting(
        name = "example_lock_env_python_darwin_x86_64",
        constraint_values = [
            "@platforms//os:osx",
            "@platforms//cpu:x86_64",
        ],
    )

    native.config_setting(
        name = "example_lock_env_python_linux_x86_64",
        constraint_values = [
            "@platforms//os:linux",
            "@platforms//cpu:x86_64",
        ],
    )

    pycross_wheel_library(
        name = "example_lock_pkg_appnope",
        wheel = "@example_lock_wheel_appnope_0.1.2_py2.py3_none_any//file",
    )

    py_library(
        name = "example_lock_deps_asttokens",
        deps = [
            ":example_lock_pkg_six",
        ],
    )

    pycross_wheel_library(
        name = "example_lock_pkg_asttokens",
        deps = [":example_lock_deps_asttokens"],
        wheel = "@example_lock_wheel_asttokens_2.0.5_py2.py3_none_any//file",
    )

    pycross_wheel_library(
        name = "example_lock_pkg_attrs",
        wheel = "@example_lock_wheel_attrs_21.4.0_py2.py3_none_any//file",
    )

    py_library(
        name = "example_lock_deps_aws_sam_translator",
        deps = [
            ":example_lock_pkg_boto3",
            ":example_lock_pkg_jsonschema",
        ],
    )

    pycross_wheel_library(
        name = "example_lock_pkg_aws_sam_translator",
        deps = [":example_lock_deps_aws_sam_translator"],
        wheel = "@example_lock_wheel_aws_sam_translator_1.44.0_py3_none_any//file",
    )

    py_library(
        name = "example_lock_deps_aws_xray_sdk",
        deps = [
            ":example_lock_pkg_botocore",
            ":example_lock_pkg_future",
            ":example_lock_pkg_wrapt",
        ],
    )

    pycross_wheel_library(
        name = "example_lock_pkg_aws_xray_sdk",
        deps = [":example_lock_deps_aws_xray_sdk"],
        wheel = "@example_lock_wheel_aws_xray_sdk_2.9.0_py2.py3_none_any//file",
    )

    pycross_wheel_library(
        name = "example_lock_pkg_backcall",
        wheel = "@example_lock_wheel_backcall_0.2.0_py2.py3_none_any//file",
    )

    py_library(
        name = "example_lock_deps_boto3",
        deps = [
            ":example_lock_pkg_botocore",
            ":example_lock_pkg_jmespath",
            ":example_lock_pkg_s3transfer",
        ],
    )

    pycross_wheel_library(
        name = "example_lock_pkg_boto3",
        deps = [":example_lock_deps_boto3"],
        wheel = "@example_lock_wheel_boto3_1.21.28_py3_none_any//file",
    )

    py_library(
        name = "example_lock_deps_botocore",
        deps = [
            ":example_lock_pkg_jmespath",
            ":example_lock_pkg_python_dateutil",
            ":example_lock_pkg_urllib3",
        ],
    )

    pycross_wheel_library(
        name = "example_lock_pkg_botocore",
        deps = [":example_lock_deps_botocore"],
        wheel = "@example_lock_wheel_botocore_1.24.28_py3_none_any//file",
    )

    pycross_wheel_library(
        name = "example_lock_pkg_certifi",
        wheel = "@example_lock_wheel_certifi_2021.10.8_py2.py3_none_any//file",
    )

    py_library(
        name = "example_lock_deps_cffi",
        deps = [
            ":example_lock_pkg_pycparser",
        ],
    )

    pycross_wheel_library(
        name = "example_lock_pkg_cffi",
        deps = [":example_lock_deps_cffi"],
        wheel = select({
            ":example_lock_env_python_darwin_x86_64": "@example_lock_wheel_cffi_1.15.0_cp39_cp39_macosx_10_9_x86_64//file",
            ":example_lock_env_python_darwin_arm64": "@example_lock_wheel_cffi_1.15.0_cp39_cp39_macosx_11_0_arm64//file",
            ":example_lock_env_python_linux_x86_64": "@example_lock_wheel_cffi_1.15.0_cp39_cp39_manylinux_2_12_x86_64.manylinux2010_x86_64//file",
        }),
    )

    py_library(
        name = "example_lock_deps_cfn_lint",
        deps = [
            ":example_lock_pkg_aws_sam_translator",
            ":example_lock_pkg_jschema_to_python",
            ":example_lock_pkg_jsonpatch",
            ":example_lock_pkg_jsonschema",
            ":example_lock_pkg_junit_xml",
            ":example_lock_pkg_networkx",
            ":example_lock_pkg_pyyaml",
            ":example_lock_pkg_sarif_om",
            ":example_lock_pkg_six",
        ],
    )

    pycross_wheel_library(
        name = "example_lock_pkg_cfn_lint",
        deps = [":example_lock_deps_cfn_lint"],
        wheel = "@example_lock_wheel_cfn_lint_0.58.4_py3_none_any//file",
    )

    pycross_wheel_library(
        name = "example_lock_pkg_charset_normalizer",
        wheel = "@example_lock_wheel_charset_normalizer_2.0.12_py3_none_any//file",
    )

    pycross_wheel_library(
        name = "example_lock_pkg_click",
        wheel = "@example_lock_wheel_click_8.1.0_py3_none_any//file",
    )

    py_library(
        name = "example_lock_deps_cognitojwt",
        deps = [
            ":example_lock_pkg_python_jose",
        ],
    )

    pycross_wheel_library(
        name = "example_lock_pkg_cognitojwt",
        deps = [":example_lock_deps_cognitojwt"],
        wheel = "@example_lock_wheel_cognitojwt_1.4.1_py3_none_any//file",
    )

    py_library(
        name = "example_lock_deps_cryptography",
        deps = [
            ":example_lock_pkg_cffi",
        ],
    )

    pycross_wheel_library(
        name = "example_lock_pkg_cryptography",
        deps = [":example_lock_deps_cryptography"],
        wheel = select({
            ":example_lock_env_python_darwin_x86_64": "@example_lock_wheel_cryptography_36.0.2_cp36_abi3_macosx_10_10_x86_64//file",
            ":example_lock_env_python_darwin_arm64": "@example_lock_wheel_cryptography_36.0.2_cp36_abi3_macosx_10_10_universal2//file",
            ":example_lock_env_python_linux_x86_64": "@example_lock_wheel_cryptography_36.0.2_cp36_abi3_manylinux_2_17_x86_64.manylinux2014_x86_64//file",
        }),
    )

    pycross_wheel_library(
        name = "example_lock_pkg_decorator",
        wheel = "@example_lock_wheel_decorator_5.1.1_py3_none_any//file",
    )

    py_library(
        name = "example_lock_deps_docker",
        deps = [
            ":example_lock_pkg_requests",
            ":example_lock_pkg_websocket_client",
        ],
    )

    pycross_wheel_library(
        name = "example_lock_pkg_docker",
        deps = [":example_lock_deps_docker"],
        wheel = "@example_lock_wheel_docker_5.0.3_py2.py3_none_any//file",
    )

    py_library(
        name = "example_lock_deps_ecdsa",
        deps = [
            ":example_lock_pkg_six",
        ],
    )

    pycross_wheel_library(
        name = "example_lock_pkg_ecdsa",
        deps = [":example_lock_deps_ecdsa"],
        wheel = "@example_lock_wheel_ecdsa_0.17.0_py2.py3_none_any//file",
    )

    pycross_wheel_library(
        name = "example_lock_pkg_executing",
        wheel = "@example_lock_wheel_executing_0.8.3_py2.py3_none_any//file",
    )

    py_library(
        name = "example_lock_deps_flask",
        deps = [
            ":example_lock_pkg_click",
            ":example_lock_pkg_importlib_metadata",
            ":example_lock_pkg_itsdangerous",
            ":example_lock_pkg_jinja2",
            ":example_lock_pkg_werkzeug",
        ],
    )

    pycross_wheel_library(
        name = "example_lock_pkg_flask",
        deps = [":example_lock_deps_flask"],
        wheel = "@example_lock_wheel_flask_2.1.0_py3_none_any//file",
    )

    py_library(
        name = "example_lock_deps_flask_cors",
        deps = [
            ":example_lock_pkg_flask",
            ":example_lock_pkg_six",
        ],
    )

    pycross_wheel_library(
        name = "example_lock_pkg_flask_cors",
        deps = [":example_lock_deps_flask_cors"],
        wheel = "@example_lock_wheel_flask_cors_3.0.10_py2.py3_none_any//file",
    )

    pycross_wheel_build(
        name = "example_lock_build_future",
        sdist = "@example_lock_sdist_future_0.18.2//file",
        tags = ["manual"],
    )

    pycross_wheel_library(
        name = "example_lock_pkg_future",
        wheel = ":example_lock_build_future",
    )

    pycross_wheel_library(
        name = "example_lock_pkg_graphql_core",
        wheel = "@example_lock_wheel_graphql_core_3.2.0_py3_none_any//file",
    )

    pycross_wheel_build(
        name = "example_lock_build_greenlet",
        sdist = "@example_lock_sdist_greenlet_1.1.2//file",
        tags = ["manual"],
    )

    pycross_wheel_library(
        name = "example_lock_pkg_greenlet",
        wheel = select({
            ":example_lock_env_python_darwin_x86_64": "@example_lock_wheel_greenlet_1.1.2_cp39_cp39_macosx_10_14_x86_64//file",
            ":example_lock_env_python_darwin_arm64": ":example_lock_build_greenlet",
            ":example_lock_env_python_linux_x86_64": "@example_lock_wheel_greenlet_1.1.2_cp39_cp39_manylinux_2_17_x86_64.manylinux2014_x86_64//file",
        }),
    )

    pycross_wheel_library(
        name = "example_lock_pkg_idna",
        wheel = "@example_lock_wheel_idna_3.3_py3_none_any//file",
    )

    py_library(
        name = "example_lock_deps_importlib_metadata",
        deps = [
            ":example_lock_pkg_zipp",
        ],
    )

    pycross_wheel_library(
        name = "example_lock_pkg_importlib_metadata",
        deps = [":example_lock_deps_importlib_metadata"],
        wheel = "@example_lock_wheel_importlib_metadata_4.11.3_py3_none_any//file",
    )

    py_library(
        name = "example_lock_deps_ipython",
        deps = [
            ":example_lock_pkg_backcall",
            ":example_lock_pkg_decorator",
            ":example_lock_pkg_jedi",
            ":example_lock_pkg_matplotlib_inline",
            ":example_lock_pkg_pexpect",
            ":example_lock_pkg_pickleshare",
            ":example_lock_pkg_prompt_toolkit",
            ":example_lock_pkg_pygments",
            ":example_lock_pkg_stack_data",
            ":example_lock_pkg_traitlets",
        ] + select({
            ":example_lock_env_python_darwin_arm64": [
                ":example_lock_pkg_appnope",
            ],
            ":example_lock_env_python_darwin_x86_64": [
                ":example_lock_pkg_appnope",
            ],
            "//conditions:default": [],
        }),
    )

    pycross_wheel_library(
        name = "example_lock_pkg_ipython",
        deps = [":example_lock_deps_ipython"],
        wheel = "@example_lock_wheel_ipython_8.2.0_py3_none_any//file",
    )

    pycross_wheel_library(
        name = "example_lock_pkg_itsdangerous",
        wheel = "@example_lock_wheel_itsdangerous_2.1.2_py3_none_any//file",
    )

    py_library(
        name = "example_lock_deps_jedi",
        deps = [
            ":example_lock_pkg_parso",
        ],
    )

    pycross_wheel_library(
        name = "example_lock_pkg_jedi",
        deps = [":example_lock_deps_jedi"],
        wheel = "@example_lock_wheel_jedi_0.18.1_py2.py3_none_any//file",
    )

    py_library(
        name = "example_lock_deps_jinja2",
        deps = [
            ":example_lock_pkg_markupsafe",
        ],
    )

    pycross_wheel_library(
        name = "example_lock_pkg_jinja2",
        deps = [":example_lock_deps_jinja2"],
        wheel = "@example_lock_wheel_jinja2_3.1.1_py3_none_any//file",
    )

    pycross_wheel_library(
        name = "example_lock_pkg_jmespath",
        wheel = "@example_lock_wheel_jmespath_1.0.0_py3_none_any//file",
    )

    py_library(
        name = "example_lock_deps_jschema_to_python",
        deps = [
            ":example_lock_pkg_attrs",
            ":example_lock_pkg_jsonpickle",
            ":example_lock_pkg_pbr",
        ],
    )

    pycross_wheel_library(
        name = "example_lock_pkg_jschema_to_python",
        deps = [":example_lock_deps_jschema_to_python"],
        wheel = "@example_lock_wheel_jschema_to_python_1.2.3_py3_none_any//file",
    )

    pycross_wheel_build(
        name = "example_lock_build_jsondiff",
        sdist = "@example_lock_sdist_jsondiff_1.3.1//file",
        tags = ["manual"],
    )

    pycross_wheel_library(
        name = "example_lock_pkg_jsondiff",
        wheel = ":example_lock_build_jsondiff",
    )

    py_library(
        name = "example_lock_deps_jsonpatch",
        deps = [
            ":example_lock_pkg_jsonpointer",
        ],
    )

    pycross_wheel_library(
        name = "example_lock_pkg_jsonpatch",
        deps = [":example_lock_deps_jsonpatch"],
        wheel = "@example_lock_wheel_jsonpatch_1.32_py2.py3_none_any//file",
    )

    pycross_wheel_library(
        name = "example_lock_pkg_jsonpickle",
        wheel = "@example_lock_wheel_jsonpickle_2.1.0_py2.py3_none_any//file",
    )

    pycross_wheel_library(
        name = "example_lock_pkg_jsonpointer",
        wheel = "@example_lock_wheel_jsonpointer_2.2_py2.py3_none_any//file",
    )

    py_library(
        name = "example_lock_deps_jsonschema",
        deps = [
            ":example_lock_pkg_attrs",
            ":example_lock_pkg_pyrsistent",
            ":example_lock_pkg_six",
        ],
    )

    pycross_wheel_library(
        name = "example_lock_pkg_jsonschema",
        deps = [":example_lock_deps_jsonschema"],
        wheel = "@example_lock_wheel_jsonschema_3.2.0_py2.py3_none_any//file",
    )

    py_library(
        name = "example_lock_deps_junit_xml",
        deps = [
            ":example_lock_pkg_six",
        ],
    )

    pycross_wheel_library(
        name = "example_lock_pkg_junit_xml",
        deps = [":example_lock_deps_junit_xml"],
        wheel = "@example_lock_wheel_junit_xml_1.9_py2.py3_none_any//file",
    )

    pycross_wheel_library(
        name = "example_lock_pkg_markupsafe",
        wheel = select({
            ":example_lock_env_python_darwin_x86_64": "@example_lock_wheel_markupsafe_2.1.1_cp39_cp39_macosx_10_9_x86_64//file",
            ":example_lock_env_python_darwin_arm64": "@example_lock_wheel_markupsafe_2.1.1_cp39_cp39_macosx_10_9_universal2//file",
            ":example_lock_env_python_linux_x86_64": "@example_lock_wheel_markupsafe_2.1.1_cp39_cp39_manylinux_2_17_x86_64.manylinux2014_x86_64//file",
        }),
    )

    py_library(
        name = "example_lock_deps_matplotlib_inline",
        deps = [
            ":example_lock_pkg_traitlets",
        ],
    )

    pycross_wheel_library(
        name = "example_lock_pkg_matplotlib_inline",
        deps = [":example_lock_deps_matplotlib_inline"],
        wheel = "@example_lock_wheel_matplotlib_inline_0.1.3_py3_none_any//file",
    )

    py_library(
        name = "example_lock_deps_moto",
        deps = [
            ":example_lock_pkg_aws_xray_sdk",
            ":example_lock_pkg_boto3",
            ":example_lock_pkg_botocore",
            ":example_lock_pkg_cfn_lint",
            ":example_lock_pkg_cryptography",
            ":example_lock_pkg_docker",
            ":example_lock_pkg_ecdsa",
            ":example_lock_pkg_flask",
            ":example_lock_pkg_flask_cors",
            ":example_lock_pkg_graphql_core",
            ":example_lock_pkg_idna",
            ":example_lock_pkg_jinja2",
            ":example_lock_pkg_jsondiff",
            ":example_lock_pkg_markupsafe",
            ":example_lock_pkg_python_dateutil",
            ":example_lock_pkg_python_jose",
            ":example_lock_pkg_pytz",
            ":example_lock_pkg_pyyaml",
            ":example_lock_pkg_requests",
            ":example_lock_pkg_responses",
            ":example_lock_pkg_sshpubkeys",
            ":example_lock_pkg_werkzeug",
            ":example_lock_pkg_xmltodict",
        ],
    )

    pycross_wheel_library(
        name = "example_lock_pkg_moto",
        deps = [":example_lock_deps_moto"],
        wheel = "@example_lock_wheel_moto_3.1.1_py2.py3_none_any//file",
    )

    pycross_wheel_library(
        name = "example_lock_pkg_networkx",
        wheel = "@example_lock_wheel_networkx_2.7.1_py3_none_any//file",
    )

    pycross_wheel_library(
        name = "example_lock_pkg_parso",
        wheel = "@example_lock_wheel_parso_0.8.3_py2.py3_none_any//file",
    )

    pycross_wheel_library(
        name = "example_lock_pkg_pbr",
        wheel = "@example_lock_wheel_pbr_5.8.1_py2.py3_none_any//file",
    )

    py_library(
        name = "example_lock_deps_pexpect",
        deps = [
            ":example_lock_pkg_ptyprocess",
        ],
    )

    pycross_wheel_library(
        name = "example_lock_pkg_pexpect",
        deps = [":example_lock_deps_pexpect"],
        wheel = "@example_lock_wheel_pexpect_4.8.0_py2.py3_none_any//file",
    )

    pycross_wheel_library(
        name = "example_lock_pkg_pickleshare",
        wheel = "@example_lock_wheel_pickleshare_0.7.5_py2.py3_none_any//file",
    )

    py_library(
        name = "example_lock_deps_prompt_toolkit",
        deps = [
            ":example_lock_pkg_wcwidth",
        ],
    )

    pycross_wheel_library(
        name = "example_lock_pkg_prompt_toolkit",
        deps = [":example_lock_deps_prompt_toolkit"],
        wheel = "@example_lock_wheel_prompt_toolkit_3.0.28_py3_none_any//file",
    )

    pycross_wheel_library(
        name = "example_lock_pkg_ptyprocess",
        wheel = "@example_lock_wheel_ptyprocess_0.7.0_py2.py3_none_any//file",
    )

    pycross_wheel_library(
        name = "example_lock_pkg_pure_eval",
        wheel = "@example_lock_wheel_pure_eval_0.2.2_py3_none_any//file",
    )

    pycross_wheel_library(
        name = "example_lock_pkg_pyasn1",
        wheel = "@example_lock_wheel_pyasn1_0.4.8_py2.py3_none_any//file",
    )

    pycross_wheel_library(
        name = "example_lock_pkg_pycparser",
        wheel = "@example_lock_wheel_pycparser_2.21_py2.py3_none_any//file",
    )

    pycross_wheel_library(
        name = "example_lock_pkg_pygments",
        wheel = "@example_lock_wheel_pygments_2.11.2_py3_none_any//file",
    )

    pycross_wheel_library(
        name = "example_lock_pkg_pyrsistent",
        wheel = select({
            ":example_lock_env_python_darwin_x86_64": "@example_lock_wheel_pyrsistent_0.18.1_cp39_cp39_macosx_10_9_universal2//file",
            ":example_lock_env_python_darwin_arm64": "@example_lock_wheel_pyrsistent_0.18.1_cp39_cp39_macosx_10_9_universal2//file",
            ":example_lock_env_python_linux_x86_64": "@example_lock_wheel_pyrsistent_0.18.1_cp39_cp39_manylinux_2_17_x86_64.manylinux2014_x86_64//file",
        }),
    )

    py_library(
        name = "example_lock_deps_python_dateutil",
        deps = [
            ":example_lock_pkg_six",
        ],
    )

    pycross_wheel_library(
        name = "example_lock_pkg_python_dateutil",
        deps = [":example_lock_deps_python_dateutil"],
        wheel = "@example_lock_wheel_python_dateutil_2.8.2_py2.py3_none_any//file",
    )

    py_library(
        name = "example_lock_deps_python_jose",
        deps = [
            ":example_lock_pkg_cryptography",
            ":example_lock_pkg_ecdsa",
            ":example_lock_pkg_pyasn1",
            ":example_lock_pkg_rsa",
            ":example_lock_pkg_six",
        ],
    )

    pycross_wheel_library(
        name = "example_lock_pkg_python_jose",
        deps = [":example_lock_deps_python_jose"],
        wheel = "@example_lock_wheel_python_jose_3.1.0_py2.py3_none_any//file",
    )

    pycross_wheel_library(
        name = "example_lock_pkg_pytz",
        wheel = "@example_lock_wheel_pytz_2022.1_py2.py3_none_any//file",
    )

    pycross_wheel_library(
        name = "example_lock_pkg_pyyaml",
        wheel = select({
            ":example_lock_env_python_darwin_x86_64": "@example_lock_wheel_pyyaml_6.0_cp39_cp39_macosx_10_9_x86_64//file",
            ":example_lock_env_python_darwin_arm64": "@example_lock_wheel_pyyaml_6.0_cp39_cp39_macosx_11_0_arm64//file",
            ":example_lock_env_python_linux_x86_64": "@example_lock_wheel_pyyaml_6.0_cp39_cp39_manylinux_2_5_x86_64.manylinux1_x86_64.manylinux_2_12_x86_64.manylinux2010_x86_64//file",
        }),
    )

    py_library(
        name = "example_lock_deps_requests",
        deps = [
            ":example_lock_pkg_certifi",
            ":example_lock_pkg_charset_normalizer",
            ":example_lock_pkg_idna",
            ":example_lock_pkg_urllib3",
        ],
    )

    pycross_wheel_library(
        name = "example_lock_pkg_requests",
        deps = [":example_lock_deps_requests"],
        wheel = "@example_lock_wheel_requests_2.27.1_py2.py3_none_any//file",
    )

    py_library(
        name = "example_lock_deps_responses",
        deps = [
            ":example_lock_pkg_requests",
            ":example_lock_pkg_urllib3",
        ],
    )

    pycross_wheel_library(
        name = "example_lock_pkg_responses",
        deps = [":example_lock_deps_responses"],
        wheel = "@example_lock_wheel_responses_0.20.0_py3_none_any//file",
    )

    py_library(
        name = "example_lock_deps_rsa",
        deps = [
            ":example_lock_pkg_pyasn1",
        ],
    )

    pycross_wheel_library(
        name = "example_lock_pkg_rsa",
        deps = [":example_lock_deps_rsa"],
        wheel = "@example_lock_wheel_rsa_4.8_py3_none_any//file",
    )

    py_library(
        name = "example_lock_deps_s3transfer",
        deps = [
            ":example_lock_pkg_botocore",
        ],
    )

    pycross_wheel_library(
        name = "example_lock_pkg_s3transfer",
        deps = [":example_lock_deps_s3transfer"],
        wheel = "@example_lock_wheel_s3transfer_0.5.2_py3_none_any//file",
    )

    py_library(
        name = "example_lock_deps_sarif_om",
        deps = [
            ":example_lock_pkg_attrs",
            ":example_lock_pkg_pbr",
        ],
    )

    pycross_wheel_library(
        name = "example_lock_pkg_sarif_om",
        deps = [":example_lock_deps_sarif_om"],
        wheel = "@example_lock_wheel_sarif_om_1.0.4_py3_none_any//file",
    )

    pycross_wheel_library(
        name = "example_lock_pkg_six",
        wheel = "@example_lock_wheel_six_1.16.0_py2.py3_none_any//file",
    )

    py_library(
        name = "example_lock_deps_sqlalchemy",
        deps = [
            ":example_lock_pkg_greenlet",
        ],
    )

    pycross_wheel_build(
        name = "example_lock_build_sqlalchemy",
        sdist = "@example_lock_sdist_sqlalchemy_1.4.32//file",
        deps = [":example_lock_deps_sqlalchemy"],
        tags = ["manual"],
    )

    pycross_wheel_library(
        name = "example_lock_pkg_sqlalchemy",
        deps = [":example_lock_deps_sqlalchemy"],
        wheel = select({
            ":example_lock_env_python_darwin_x86_64": "@example_lock_wheel_sqlalchemy_1.4.32_cp39_cp39_macosx_10_15_x86_64//file",
            ":example_lock_env_python_darwin_arm64": ":example_lock_build_sqlalchemy",
            ":example_lock_env_python_linux_x86_64": "@example_lock_wheel_sqlalchemy_1.4.32_cp39_cp39_manylinux_2_5_x86_64.manylinux1_x86_64.manylinux_2_17_x86_64.manylinux2014_x86_64//file",
        }),
    )

    py_library(
        name = "example_lock_deps_sqlalchemy_utils",
        deps = [
            ":example_lock_pkg_six",
            ":example_lock_pkg_sqlalchemy",
        ],
    )

    pycross_wheel_library(
        name = "example_lock_pkg_sqlalchemy_utils",
        deps = [":example_lock_deps_sqlalchemy_utils"],
        wheel = "@example_lock_wheel_sqlalchemy_utils_0.38.2_py3_none_any//file",
    )

    py_library(
        name = "example_lock_deps_sshpubkeys",
        deps = [
            ":example_lock_pkg_cryptography",
            ":example_lock_pkg_ecdsa",
        ],
    )

    pycross_wheel_library(
        name = "example_lock_pkg_sshpubkeys",
        deps = [":example_lock_deps_sshpubkeys"],
        wheel = "@example_lock_wheel_sshpubkeys_3.3.1_py2.py3_none_any//file",
    )

    py_library(
        name = "example_lock_deps_stack_data",
        deps = [
            ":example_lock_pkg_asttokens",
            ":example_lock_pkg_executing",
            ":example_lock_pkg_pure_eval",
        ],
    )

    pycross_wheel_library(
        name = "example_lock_pkg_stack_data",
        deps = [":example_lock_deps_stack_data"],
        wheel = "@example_lock_wheel_stack_data_0.2.0_py3_none_any//file",
    )

    pycross_wheel_library(
        name = "example_lock_pkg_traitlets",
        wheel = "@example_lock_wheel_traitlets_5.1.1_py3_none_any//file",
    )

    pycross_wheel_library(
        name = "example_lock_pkg_urllib3",
        wheel = "@example_lock_wheel_urllib3_1.26.9_py2.py3_none_any//file",
    )

    pycross_wheel_library(
        name = "example_lock_pkg_wcwidth",
        wheel = "@example_lock_wheel_wcwidth_0.2.5_py2.py3_none_any//file",
    )

    pycross_wheel_library(
        name = "example_lock_pkg_websocket_client",
        wheel = "@example_lock_wheel_websocket_client_1.3.1_py3_none_any//file",
    )

    pycross_wheel_library(
        name = "example_lock_pkg_werkzeug",
        wheel = "@example_lock_wheel_werkzeug_2.1.0_py3_none_any//file",
    )

    pycross_wheel_library(
        name = "example_lock_pkg_wrapt",
        wheel = select({
            ":example_lock_env_python_darwin_x86_64": "@example_lock_wheel_wrapt_1.14.0_cp39_cp39_macosx_10_9_x86_64//file",
            ":example_lock_env_python_darwin_arm64": "@example_lock_wheel_wrapt_1.14.0_cp39_cp39_macosx_11_0_arm64//file",
            ":example_lock_env_python_linux_x86_64": "@example_lock_wheel_wrapt_1.14.0_cp39_cp39_manylinux_2_5_x86_64.manylinux1_x86_64.manylinux_2_17_x86_64.manylinux2014_x86_64//file",
        }),
    )

    pycross_wheel_library(
        name = "example_lock_pkg_xmltodict",
        wheel = "@example_lock_wheel_xmltodict_0.12.0_py2.py3_none_any//file",
    )

    pycross_wheel_library(
        name = "example_lock_pkg_zipp",
        wheel = "@example_lock_wheel_zipp_3.7.0_py3_none_any//file",
    )

def repositories():
    http_file(
        name = "example_lock_sdist_future_0.18.2",
        urls = ["https://files.pythonhosted.org/packages/source/f/future/future-0.18.2.tar.gz"],
        sha256 = "b1bead90b70cf6ec3f0710ae53a525360fa360d306a86583adc6bf83a4db537d",
        downloaded_file_path = "future-0.18.2.tar.gz",
    )

    http_file(
        name = "example_lock_sdist_greenlet_1.1.2",
        urls = ["https://files.pythonhosted.org/packages/source/g/greenlet/greenlet-1.1.2.tar.gz"],
        sha256 = "e30f5ea4ae2346e62cedde8794a56858a67b878dd79f7df76a0767e356b1744a",
        downloaded_file_path = "greenlet-1.1.2.tar.gz",
    )

    http_file(
        name = "example_lock_sdist_jsondiff_1.3.1",
        urls = ["https://files.pythonhosted.org/packages/source/j/jsondiff/jsondiff-1.3.1.tar.gz"],
        sha256 = "04cfaebd4a5e5738948ab615710dc3ee98efbdf851255fd3977c4c2ee59e7312",
        downloaded_file_path = "jsondiff-1.3.1.tar.gz",
    )

    http_file(
        name = "example_lock_sdist_sqlalchemy_1.4.32",
        urls = ["https://files.pythonhosted.org/packages/source/S/SQLAlchemy/SQLAlchemy-1.4.32.tar.gz"],
        sha256 = "6fdd2dc5931daab778c2b65b03df6ae68376e028a3098eb624d0909d999885bc",
        downloaded_file_path = "SQLAlchemy-1.4.32.tar.gz",
    )

    http_file(
        name = "example_lock_wheel_appnope_0.1.2_py2.py3_none_any",
        urls = ["https://files.pythonhosted.org/packages/py2.py3/a/appnope/appnope-0.1.2-py2.py3-none-any.whl"],
        sha256 = "93aa393e9d6c54c5cd570ccadd8edad61ea0c4b9ea7a01409020c9aa019eb442",
        downloaded_file_path = "appnope-0.1.2-py2.py3-none-any.whl",
    )

    http_file(
        name = "example_lock_wheel_asttokens_2.0.5_py2.py3_none_any",
        urls = ["https://files.pythonhosted.org/packages/py2.py3/a/asttokens/asttokens-2.0.5-py2.py3-none-any.whl"],
        sha256 = "0844691e88552595a6f4a4281a9f7f79b8dd45ca4ccea82e5e05b4bbdb76705c",
        downloaded_file_path = "asttokens-2.0.5-py2.py3-none-any.whl",
    )

    http_file(
        name = "example_lock_wheel_attrs_21.4.0_py2.py3_none_any",
        urls = ["https://files.pythonhosted.org/packages/py2.py3/a/attrs/attrs-21.4.0-py2.py3-none-any.whl"],
        sha256 = "2d27e3784d7a565d36ab851fe94887c5eccd6a463168875832a1be79c82828b4",
        downloaded_file_path = "attrs-21.4.0-py2.py3-none-any.whl",
    )

    http_file(
        name = "example_lock_wheel_aws_sam_translator_1.44.0_py3_none_any",
        urls = ["https://files.pythonhosted.org/packages/py3/a/aws_sam_translator/aws_sam_translator-1.44.0-py3-none-any.whl"],
        sha256 = "77be965487f20303528c9febd17bbe0bad6a980be2762486d090a7c5e07b4187",
        downloaded_file_path = "aws_sam_translator-1.44.0-py3-none-any.whl",
    )

    http_file(
        name = "example_lock_wheel_aws_xray_sdk_2.9.0_py2.py3_none_any",
        urls = ["https://files.pythonhosted.org/packages/py2.py3/a/aws_xray_sdk/aws_xray_sdk-2.9.0-py2.py3-none-any.whl"],
        sha256 = "98216b3ac8281b51b59a8703f8ec561c460807d9d0679838f5c0179d381d7e58",
        downloaded_file_path = "aws_xray_sdk-2.9.0-py2.py3-none-any.whl",
    )

    http_file(
        name = "example_lock_wheel_backcall_0.2.0_py2.py3_none_any",
        urls = ["https://files.pythonhosted.org/packages/py2.py3/b/backcall/backcall-0.2.0-py2.py3-none-any.whl"],
        sha256 = "fbbce6a29f263178a1f7915c1940bde0ec2b2a967566fe1c65c1dfb7422bd255",
        downloaded_file_path = "backcall-0.2.0-py2.py3-none-any.whl",
    )

    http_file(
        name = "example_lock_wheel_boto3_1.21.28_py3_none_any",
        urls = ["https://files.pythonhosted.org/packages/py3/b/boto3/boto3-1.21.28-py3-none-any.whl"],
        sha256 = "ca37b9b4ade72f6d4fa2b7bee584dd5b1c7585f07f22ff1edbc9ecc0c4173b1f",
        downloaded_file_path = "boto3-1.21.28-py3-none-any.whl",
    )

    http_file(
        name = "example_lock_wheel_botocore_1.24.28_py3_none_any",
        urls = ["https://files.pythonhosted.org/packages/py3/b/botocore/botocore-1.24.28-py3-none-any.whl"],
        sha256 = "03c41d26d1e765380b8175d4b136d3144aa051f17a86eebfdf9a885a5a9a6a72",
        downloaded_file_path = "botocore-1.24.28-py3-none-any.whl",
    )

    http_file(
        name = "example_lock_wheel_certifi_2021.10.8_py2.py3_none_any",
        urls = ["https://files.pythonhosted.org/packages/py2.py3/c/certifi/certifi-2021.10.8-py2.py3-none-any.whl"],
        sha256 = "d62a0163eb4c2344ac042ab2bdf75399a71a2d8c7d47eac2e2ee91b9d6339569",
        downloaded_file_path = "certifi-2021.10.8-py2.py3-none-any.whl",
    )

    http_file(
        name = "example_lock_wheel_cffi_1.15.0_cp39_cp39_macosx_10_9_x86_64",
        urls = ["https://files.pythonhosted.org/packages/cp39/c/cffi/cffi-1.15.0-cp39-cp39-macosx_10_9_x86_64.whl"],
        sha256 = "45e8636704eacc432a206ac7345a5d3d2c62d95a507ec70d62f23cd91770482a",
        downloaded_file_path = "cffi-1.15.0-cp39-cp39-macosx_10_9_x86_64.whl",
    )

    http_file(
        name = "example_lock_wheel_cffi_1.15.0_cp39_cp39_macosx_11_0_arm64",
        urls = ["https://files.pythonhosted.org/packages/cp39/c/cffi/cffi-1.15.0-cp39-cp39-macosx_11_0_arm64.whl"],
        sha256 = "31fb708d9d7c3f49a60f04cf5b119aeefe5644daba1cd2a0fe389b674fd1de37",
        downloaded_file_path = "cffi-1.15.0-cp39-cp39-macosx_11_0_arm64.whl",
    )

    http_file(
        name = "example_lock_wheel_cffi_1.15.0_cp39_cp39_manylinux_2_12_x86_64.manylinux2010_x86_64",
        urls = ["https://files.pythonhosted.org/packages/cp39/c/cffi/cffi-1.15.0-cp39-cp39-manylinux_2_12_x86_64.manylinux2010_x86_64.whl"],
        sha256 = "74fdfdbfdc48d3f47148976f49fab3251e550a8720bebc99bf1483f5bfb5db3e",
        downloaded_file_path = "cffi-1.15.0-cp39-cp39-manylinux_2_12_x86_64.manylinux2010_x86_64.whl",
    )

    http_file(
        name = "example_lock_wheel_cfn_lint_0.58.4_py3_none_any",
        urls = ["https://files.pythonhosted.org/packages/py3/c/cfn_lint/cfn_lint-0.58.4-py3-none-any.whl"],
        sha256 = "c21a4ea369e54501dc1bd6c294bb083bcd1731f4374f2fb1e87228ed720781f3",
        downloaded_file_path = "cfn_lint-0.58.4-py3-none-any.whl",
    )

    http_file(
        name = "example_lock_wheel_charset_normalizer_2.0.12_py3_none_any",
        urls = ["https://files.pythonhosted.org/packages/py3/c/charset_normalizer/charset_normalizer-2.0.12-py3-none-any.whl"],
        sha256 = "6881edbebdb17b39b4eaaa821b438bf6eddffb4468cf344f09f89def34a8b1df",
        downloaded_file_path = "charset_normalizer-2.0.12-py3-none-any.whl",
    )

    http_file(
        name = "example_lock_wheel_click_8.1.0_py3_none_any",
        urls = ["https://files.pythonhosted.org/packages/py3/c/click/click-8.1.0-py3-none-any.whl"],
        sha256 = "19a4baa64da924c5e0cd889aba8e947f280309f1a2ce0947a3e3a7bcb7cc72d6",
        downloaded_file_path = "click-8.1.0-py3-none-any.whl",
    )

    http_file(
        name = "example_lock_wheel_cognitojwt_1.4.1_py3_none_any",
        urls = ["https://files.pythonhosted.org/packages/py3/c/cognitojwt/cognitojwt-1.4.1-py3-none-any.whl"],
        sha256 = "8ee189f82289d140dc750c91e8772436b64b94d071507ace42efc22c525f42ce",
        downloaded_file_path = "cognitojwt-1.4.1-py3-none-any.whl",
    )

    http_file(
        name = "example_lock_wheel_cryptography_36.0.2_cp36_abi3_macosx_10_10_universal2",
        urls = ["https://files.pythonhosted.org/packages/cp36/c/cryptography/cryptography-36.0.2-cp36-abi3-macosx_10_10_universal2.whl"],
        sha256 = "4e2dddd38a5ba733be6a025a1475a9f45e4e41139d1321f412c6b360b19070b6",
        downloaded_file_path = "cryptography-36.0.2-cp36-abi3-macosx_10_10_universal2.whl",
    )

    http_file(
        name = "example_lock_wheel_cryptography_36.0.2_cp36_abi3_macosx_10_10_x86_64",
        urls = ["https://files.pythonhosted.org/packages/cp36/c/cryptography/cryptography-36.0.2-cp36-abi3-macosx_10_10_x86_64.whl"],
        sha256 = "4881d09298cd0b669bb15b9cfe6166f16fc1277b4ed0d04a22f3d6430cb30f1d",
        downloaded_file_path = "cryptography-36.0.2-cp36-abi3-macosx_10_10_x86_64.whl",
    )

    http_file(
        name = "example_lock_wheel_cryptography_36.0.2_cp36_abi3_manylinux_2_17_x86_64.manylinux2014_x86_64",
        urls = ["https://files.pythonhosted.org/packages/cp36/c/cryptography/cryptography-36.0.2-cp36-abi3-manylinux_2_17_x86_64.manylinux2014_x86_64.whl"],
        sha256 = "7b2d54e787a884ffc6e187262823b6feb06c338084bbe80d45166a1cb1c6c5bf",
        downloaded_file_path = "cryptography-36.0.2-cp36-abi3-manylinux_2_17_x86_64.manylinux2014_x86_64.whl",
    )

    http_file(
        name = "example_lock_wheel_decorator_5.1.1_py3_none_any",
        urls = ["https://files.pythonhosted.org/packages/py3/d/decorator/decorator-5.1.1-py3-none-any.whl"],
        sha256 = "b8c3f85900b9dc423225913c5aace94729fe1fa9763b38939a95226f02d37186",
        downloaded_file_path = "decorator-5.1.1-py3-none-any.whl",
    )

    http_file(
        name = "example_lock_wheel_docker_5.0.3_py2.py3_none_any",
        urls = ["https://files.pythonhosted.org/packages/py2.py3/d/docker/docker-5.0.3-py2.py3-none-any.whl"],
        sha256 = "7a79bb439e3df59d0a72621775d600bc8bc8b422d285824cb37103eab91d1ce0",
        downloaded_file_path = "docker-5.0.3-py2.py3-none-any.whl",
    )

    http_file(
        name = "example_lock_wheel_ecdsa_0.17.0_py2.py3_none_any",
        urls = ["https://files.pythonhosted.org/packages/py2.py3/e/ecdsa/ecdsa-0.17.0-py2.py3-none-any.whl"],
        sha256 = "5cf31d5b33743abe0dfc28999036c849a69d548f994b535e527ee3cb7f3ef676",
        downloaded_file_path = "ecdsa-0.17.0-py2.py3-none-any.whl",
    )

    http_file(
        name = "example_lock_wheel_executing_0.8.3_py2.py3_none_any",
        urls = ["https://files.pythonhosted.org/packages/py2.py3/e/executing/executing-0.8.3-py2.py3-none-any.whl"],
        sha256 = "d1eef132db1b83649a3905ca6dd8897f71ac6f8cac79a7e58a1a09cf137546c9",
        downloaded_file_path = "executing-0.8.3-py2.py3-none-any.whl",
    )

    http_file(
        name = "example_lock_wheel_flask_2.1.0_py3_none_any",
        urls = ["https://files.pythonhosted.org/packages/py3/F/Flask/Flask-2.1.0-py3-none-any.whl"],
        sha256 = "e4c69910f6a096cc57e4ee45b7ba9afafdcad4cc571db6eb97d5bd01b95422ea",
        downloaded_file_path = "Flask-2.1.0-py3-none-any.whl",
    )

    http_file(
        name = "example_lock_wheel_flask_cors_3.0.10_py2.py3_none_any",
        urls = ["https://files.pythonhosted.org/packages/py2.py3/F/Flask_Cors/Flask_Cors-3.0.10-py2.py3-none-any.whl"],
        sha256 = "74efc975af1194fc7891ff5cd85b0f7478be4f7f59fe158102e91abb72bb4438",
        downloaded_file_path = "Flask_Cors-3.0.10-py2.py3-none-any.whl",
    )

    http_file(
        name = "example_lock_wheel_graphql_core_3.2.0_py3_none_any",
        urls = ["https://files.pythonhosted.org/packages/py3/g/graphql_core/graphql_core-3.2.0-py3-none-any.whl"],
        sha256 = "0dda7e63676f119bb3d814621190fedad72fda07a8e9ab780bedd9f1957c6dc6",
        downloaded_file_path = "graphql_core-3.2.0-py3-none-any.whl",
    )

    http_file(
        name = "example_lock_wheel_greenlet_1.1.2_cp39_cp39_macosx_10_14_x86_64",
        urls = ["https://files.pythonhosted.org/packages/cp39/g/greenlet/greenlet-1.1.2-cp39-cp39-macosx_10_14_x86_64.whl"],
        sha256 = "166eac03e48784a6a6e0e5f041cfebb1ab400b394db188c48b3a84737f505b67",
        downloaded_file_path = "greenlet-1.1.2-cp39-cp39-macosx_10_14_x86_64.whl",
    )

    http_file(
        name = "example_lock_wheel_greenlet_1.1.2_cp39_cp39_manylinux_2_17_x86_64.manylinux2014_x86_64",
        urls = ["https://files.pythonhosted.org/packages/cp39/g/greenlet/greenlet-1.1.2-cp39-cp39-manylinux_2_17_x86_64.manylinux2014_x86_64.whl"],
        sha256 = "7ff61ff178250f9bb3cd89752df0f1dd0e27316a8bd1465351652b1b4a4cdfd3",
        downloaded_file_path = "greenlet-1.1.2-cp39-cp39-manylinux_2_17_x86_64.manylinux2014_x86_64.whl",
    )

    http_file(
        name = "example_lock_wheel_idna_3.3_py3_none_any",
        urls = ["https://files.pythonhosted.org/packages/py3/i/idna/idna-3.3-py3-none-any.whl"],
        sha256 = "84d9dd047ffa80596e0f246e2eab0b391788b0503584e8945f2368256d2735ff",
        downloaded_file_path = "idna-3.3-py3-none-any.whl",
    )

    http_file(
        name = "example_lock_wheel_importlib_metadata_4.11.3_py3_none_any",
        urls = ["https://files.pythonhosted.org/packages/py3/i/importlib_metadata/importlib_metadata-4.11.3-py3-none-any.whl"],
        sha256 = "1208431ca90a8cca1a6b8af391bb53c1a2db74e5d1cef6ddced95d4b2062edc6",
        downloaded_file_path = "importlib_metadata-4.11.3-py3-none-any.whl",
    )

    http_file(
        name = "example_lock_wheel_ipython_8.2.0_py3_none_any",
        urls = ["https://files.pythonhosted.org/packages/py3/i/ipython/ipython-8.2.0-py3-none-any.whl"],
        sha256 = "1b672bfd7a48d87ab203d9af8727a3b0174a4566b4091e9447c22fb63ea32857",
        downloaded_file_path = "ipython-8.2.0-py3-none-any.whl",
    )

    http_file(
        name = "example_lock_wheel_itsdangerous_2.1.2_py3_none_any",
        urls = ["https://files.pythonhosted.org/packages/py3/i/itsdangerous/itsdangerous-2.1.2-py3-none-any.whl"],
        sha256 = "2c2349112351b88699d8d4b6b075022c0808887cb7ad10069318a8b0bc88db44",
        downloaded_file_path = "itsdangerous-2.1.2-py3-none-any.whl",
    )

    http_file(
        name = "example_lock_wheel_jedi_0.18.1_py2.py3_none_any",
        urls = ["https://files.pythonhosted.org/packages/py2.py3/j/jedi/jedi-0.18.1-py2.py3-none-any.whl"],
        sha256 = "637c9635fcf47945ceb91cd7f320234a7be540ded6f3e99a50cb6febdfd1ba8d",
        downloaded_file_path = "jedi-0.18.1-py2.py3-none-any.whl",
    )

    http_file(
        name = "example_lock_wheel_jinja2_3.1.1_py3_none_any",
        urls = ["https://files.pythonhosted.org/packages/py3/J/Jinja2/Jinja2-3.1.1-py3-none-any.whl"],
        sha256 = "539835f51a74a69f41b848a9645dbdc35b4f20a3b601e2d9a7e22947b15ff119",
        downloaded_file_path = "Jinja2-3.1.1-py3-none-any.whl",
    )

    http_file(
        name = "example_lock_wheel_jmespath_1.0.0_py3_none_any",
        urls = ["https://files.pythonhosted.org/packages/py3/j/jmespath/jmespath-1.0.0-py3-none-any.whl"],
        sha256 = "e8dcd576ed616f14ec02eed0005c85973b5890083313860136657e24784e4c04",
        downloaded_file_path = "jmespath-1.0.0-py3-none-any.whl",
    )

    http_file(
        name = "example_lock_wheel_jschema_to_python_1.2.3_py3_none_any",
        urls = ["https://files.pythonhosted.org/packages/py3/j/jschema_to_python/jschema_to_python-1.2.3-py3-none-any.whl"],
        sha256 = "8a703ca7604d42d74b2815eecf99a33359a8dccbb80806cce386d5e2dd992b05",
        downloaded_file_path = "jschema_to_python-1.2.3-py3-none-any.whl",
    )

    http_file(
        name = "example_lock_wheel_jsonpatch_1.32_py2.py3_none_any",
        urls = ["https://files.pythonhosted.org/packages/py2.py3/j/jsonpatch/jsonpatch-1.32-py2.py3-none-any.whl"],
        sha256 = "26ac385719ac9f54df8a2f0827bb8253aa3ea8ab7b3368457bcdb8c14595a397",
        downloaded_file_path = "jsonpatch-1.32-py2.py3-none-any.whl",
    )

    http_file(
        name = "example_lock_wheel_jsonpickle_2.1.0_py2.py3_none_any",
        urls = ["https://files.pythonhosted.org/packages/py2.py3/j/jsonpickle/jsonpickle-2.1.0-py2.py3-none-any.whl"],
        sha256 = "1dee77ddc5d652dfdabc33d33cff9d7e131d428007007da4fd6f7071ae774b0f",
        downloaded_file_path = "jsonpickle-2.1.0-py2.py3-none-any.whl",
    )

    http_file(
        name = "example_lock_wheel_jsonpointer_2.2_py2.py3_none_any",
        urls = ["https://files.pythonhosted.org/packages/py2.py3/j/jsonpointer/jsonpointer-2.2-py2.py3-none-any.whl"],
        sha256 = "26d9a47a72d4dc3e3ae72c4c6cd432afd73c680164cd2540772eab53cb3823b6",
        downloaded_file_path = "jsonpointer-2.2-py2.py3-none-any.whl",
    )

    http_file(
        name = "example_lock_wheel_jsonschema_3.2.0_py2.py3_none_any",
        urls = ["https://files.pythonhosted.org/packages/py2.py3/j/jsonschema/jsonschema-3.2.0-py2.py3-none-any.whl"],
        sha256 = "4e5b3cf8216f577bee9ce139cbe72eca3ea4f292ec60928ff24758ce626cd163",
        downloaded_file_path = "jsonschema-3.2.0-py2.py3-none-any.whl",
    )

    http_file(
        name = "example_lock_wheel_junit_xml_1.9_py2.py3_none_any",
        urls = ["https://files.pythonhosted.org/packages/py2.py3/j/junit_xml/junit_xml-1.9-py2.py3-none-any.whl"],
        sha256 = "ec5ca1a55aefdd76d28fcc0b135251d156c7106fa979686a4b48d62b761b4732",
        downloaded_file_path = "junit_xml-1.9-py2.py3-none-any.whl",
    )

    http_file(
        name = "example_lock_wheel_markupsafe_2.1.1_cp39_cp39_macosx_10_9_universal2",
        urls = ["https://files.pythonhosted.org/packages/cp39/M/MarkupSafe/MarkupSafe-2.1.1-cp39-cp39-macosx_10_9_universal2.whl"],
        sha256 = "e04e26803c9c3851c931eac40c695602c6295b8d432cbe78609649ad9bd2da8a",
        downloaded_file_path = "MarkupSafe-2.1.1-cp39-cp39-macosx_10_9_universal2.whl",
    )

    http_file(
        name = "example_lock_wheel_markupsafe_2.1.1_cp39_cp39_macosx_10_9_x86_64",
        urls = ["https://files.pythonhosted.org/packages/cp39/M/MarkupSafe/MarkupSafe-2.1.1-cp39-cp39-macosx_10_9_x86_64.whl"],
        sha256 = "b87db4360013327109564f0e591bd2a3b318547bcef31b468a92ee504d07ae4f",
        downloaded_file_path = "MarkupSafe-2.1.1-cp39-cp39-macosx_10_9_x86_64.whl",
    )

    http_file(
        name = "example_lock_wheel_markupsafe_2.1.1_cp39_cp39_manylinux_2_17_x86_64.manylinux2014_x86_64",
        urls = ["https://files.pythonhosted.org/packages/cp39/M/MarkupSafe/MarkupSafe-2.1.1-cp39-cp39-manylinux_2_17_x86_64.manylinux2014_x86_64.whl"],
        sha256 = "56442863ed2b06d19c37f94d999035e15ee982988920e12a5b4ba29b62ad1f77",
        downloaded_file_path = "MarkupSafe-2.1.1-cp39-cp39-manylinux_2_17_x86_64.manylinux2014_x86_64.whl",
    )

    http_file(
        name = "example_lock_wheel_matplotlib_inline_0.1.3_py3_none_any",
        urls = ["https://files.pythonhosted.org/packages/py3/m/matplotlib_inline/matplotlib_inline-0.1.3-py3-none-any.whl"],
        sha256 = "aed605ba3b72462d64d475a21a9296f400a19c4f74a31b59103d2a99ffd5aa5c",
        downloaded_file_path = "matplotlib_inline-0.1.3-py3-none-any.whl",
    )

    http_file(
        name = "example_lock_wheel_moto_3.1.1_py2.py3_none_any",
        urls = ["https://files.pythonhosted.org/packages/py2.py3/m/moto/moto-3.1.1-py2.py3-none-any.whl"],
        sha256 = "462495563847134ea8ef4135a229731a598a8e7b6b10a74f8d745815aa20a25b",
        downloaded_file_path = "moto-3.1.1-py2.py3-none-any.whl",
    )

    http_file(
        name = "example_lock_wheel_networkx_2.7.1_py3_none_any",
        urls = ["https://files.pythonhosted.org/packages/py3/n/networkx/networkx-2.7.1-py3-none-any.whl"],
        sha256 = "011e85d277c89681e8fa661cf5ff0743443445049b0b68789ad55ef09340c6e0",
        downloaded_file_path = "networkx-2.7.1-py3-none-any.whl",
    )

    http_file(
        name = "example_lock_wheel_parso_0.8.3_py2.py3_none_any",
        urls = ["https://files.pythonhosted.org/packages/py2.py3/p/parso/parso-0.8.3-py2.py3-none-any.whl"],
        sha256 = "c001d4636cd3aecdaf33cbb40aebb59b094be2a74c556778ef5576c175e19e75",
        downloaded_file_path = "parso-0.8.3-py2.py3-none-any.whl",
    )

    http_file(
        name = "example_lock_wheel_pbr_5.8.1_py2.py3_none_any",
        urls = ["https://files.pythonhosted.org/packages/py2.py3/p/pbr/pbr-5.8.1-py2.py3-none-any.whl"],
        sha256 = "27108648368782d07bbf1cb468ad2e2eeef29086affd14087a6d04b7de8af4ec",
        downloaded_file_path = "pbr-5.8.1-py2.py3-none-any.whl",
    )

    http_file(
        name = "example_lock_wheel_pexpect_4.8.0_py2.py3_none_any",
        urls = ["https://files.pythonhosted.org/packages/py2.py3/p/pexpect/pexpect-4.8.0-py2.py3-none-any.whl"],
        sha256 = "0b48a55dcb3c05f3329815901ea4fc1537514d6ba867a152b581d69ae3710937",
        downloaded_file_path = "pexpect-4.8.0-py2.py3-none-any.whl",
    )

    http_file(
        name = "example_lock_wheel_pickleshare_0.7.5_py2.py3_none_any",
        urls = ["https://files.pythonhosted.org/packages/py2.py3/p/pickleshare/pickleshare-0.7.5-py2.py3-none-any.whl"],
        sha256 = "9649af414d74d4df115d5d718f82acb59c9d418196b7b4290ed47a12ce62df56",
        downloaded_file_path = "pickleshare-0.7.5-py2.py3-none-any.whl",
    )

    http_file(
        name = "example_lock_wheel_prompt_toolkit_3.0.28_py3_none_any",
        urls = ["https://files.pythonhosted.org/packages/py3/p/prompt_toolkit/prompt_toolkit-3.0.28-py3-none-any.whl"],
        sha256 = "30129d870dcb0b3b6a53efdc9d0a83ea96162ffd28ffe077e94215b233dc670c",
        downloaded_file_path = "prompt_toolkit-3.0.28-py3-none-any.whl",
    )

    http_file(
        name = "example_lock_wheel_ptyprocess_0.7.0_py2.py3_none_any",
        urls = ["https://files.pythonhosted.org/packages/py2.py3/p/ptyprocess/ptyprocess-0.7.0-py2.py3-none-any.whl"],
        sha256 = "4b41f3967fce3af57cc7e94b888626c18bf37a083e3651ca8feeb66d492fef35",
        downloaded_file_path = "ptyprocess-0.7.0-py2.py3-none-any.whl",
    )

    http_file(
        name = "example_lock_wheel_pure_eval_0.2.2_py3_none_any",
        urls = ["https://files.pythonhosted.org/packages/py3/p/pure_eval/pure_eval-0.2.2-py3-none-any.whl"],
        sha256 = "01eaab343580944bc56080ebe0a674b39ec44a945e6d09ba7db3cb8cec289350",
        downloaded_file_path = "pure_eval-0.2.2-py3-none-any.whl",
    )

    http_file(
        name = "example_lock_wheel_pyasn1_0.4.8_py2.py3_none_any",
        urls = ["https://files.pythonhosted.org/packages/py2.py3/p/pyasn1/pyasn1-0.4.8-py2.py3-none-any.whl"],
        sha256 = "39c7e2ec30515947ff4e87fb6f456dfc6e84857d34be479c9d4a4ba4bf46aa5d",
        downloaded_file_path = "pyasn1-0.4.8-py2.py3-none-any.whl",
    )

    http_file(
        name = "example_lock_wheel_pycparser_2.21_py2.py3_none_any",
        urls = ["https://files.pythonhosted.org/packages/py2.py3/p/pycparser/pycparser-2.21-py2.py3-none-any.whl"],
        sha256 = "8ee45429555515e1f6b185e78100aea234072576aa43ab53aefcae078162fca9",
        downloaded_file_path = "pycparser-2.21-py2.py3-none-any.whl",
    )

    http_file(
        name = "example_lock_wheel_pygments_2.11.2_py3_none_any",
        urls = ["https://files.pythonhosted.org/packages/py3/P/Pygments/Pygments-2.11.2-py3-none-any.whl"],
        sha256 = "44238f1b60a76d78fc8ca0528ee429702aae011c265fe6a8dd8b63049ae41c65",
        downloaded_file_path = "Pygments-2.11.2-py3-none-any.whl",
    )

    http_file(
        name = "example_lock_wheel_pyrsistent_0.18.1_cp39_cp39_macosx_10_9_universal2",
        urls = ["https://files.pythonhosted.org/packages/cp39/p/pyrsistent/pyrsistent-0.18.1-cp39-cp39-macosx_10_9_universal2.whl"],
        sha256 = "f87cc2863ef33c709e237d4b5f4502a62a00fab450c9e020892e8e2ede5847f5",
        downloaded_file_path = "pyrsistent-0.18.1-cp39-cp39-macosx_10_9_universal2.whl",
    )

    http_file(
        name = "example_lock_wheel_pyrsistent_0.18.1_cp39_cp39_manylinux_2_17_x86_64.manylinux2014_x86_64",
        urls = ["https://files.pythonhosted.org/packages/cp39/p/pyrsistent/pyrsistent-0.18.1-cp39-cp39-manylinux_2_17_x86_64.manylinux2014_x86_64.whl"],
        sha256 = "6bc66318fb7ee012071b2792024564973ecc80e9522842eb4e17743604b5e045",
        downloaded_file_path = "pyrsistent-0.18.1-cp39-cp39-manylinux_2_17_x86_64.manylinux2014_x86_64.whl",
    )

    http_file(
        name = "example_lock_wheel_python_dateutil_2.8.2_py2.py3_none_any",
        urls = ["https://files.pythonhosted.org/packages/py2.py3/p/python_dateutil/python_dateutil-2.8.2-py2.py3-none-any.whl"],
        sha256 = "961d03dc3453ebbc59dbdea9e4e11c5651520a876d0f4db161e8674aae935da9",
        downloaded_file_path = "python_dateutil-2.8.2-py2.py3-none-any.whl",
    )

    http_file(
        name = "example_lock_wheel_python_jose_3.1.0_py2.py3_none_any",
        urls = ["https://files.pythonhosted.org/packages/py2.py3/p/python_jose/python_jose-3.1.0-py2.py3-none-any.whl"],
        sha256 = "1ac4caf4bfebd5a70cf5bd82702ed850db69b0b6e1d0ae7368e5f99ac01c9571",
        downloaded_file_path = "python_jose-3.1.0-py2.py3-none-any.whl",
    )

    http_file(
        name = "example_lock_wheel_pytz_2022.1_py2.py3_none_any",
        urls = ["https://files.pythonhosted.org/packages/py2.py3/p/pytz/pytz-2022.1-py2.py3-none-any.whl"],
        sha256 = "e68985985296d9a66a881eb3193b0906246245294a881e7c8afe623866ac6a5c",
        downloaded_file_path = "pytz-2022.1-py2.py3-none-any.whl",
    )

    http_file(
        name = "example_lock_wheel_pyyaml_6.0_cp39_cp39_macosx_10_9_x86_64",
        urls = ["https://files.pythonhosted.org/packages/cp39/P/PyYAML/PyYAML-6.0-cp39-cp39-macosx_10_9_x86_64.whl"],
        sha256 = "055d937d65826939cb044fc8c9b08889e8c743fdc6a32b33e2390f66013e449b",
        downloaded_file_path = "PyYAML-6.0-cp39-cp39-macosx_10_9_x86_64.whl",
    )

    http_file(
        name = "example_lock_wheel_pyyaml_6.0_cp39_cp39_macosx_11_0_arm64",
        urls = ["https://files.pythonhosted.org/packages/cp39/P/PyYAML/PyYAML-6.0-cp39-cp39-macosx_11_0_arm64.whl"],
        sha256 = "e61ceaab6f49fb8bdfaa0f92c4b57bcfbea54c09277b1b4f7ac376bfb7a7c174",
        downloaded_file_path = "PyYAML-6.0-cp39-cp39-macosx_11_0_arm64.whl",
    )

    http_file(
        name = "example_lock_wheel_pyyaml_6.0_cp39_cp39_manylinux_2_5_x86_64.manylinux1_x86_64.manylinux_2_12_x86_64.manylinux2010_x86_64",
        urls = ["https://files.pythonhosted.org/packages/cp39/P/PyYAML/PyYAML-6.0-cp39-cp39-manylinux_2_5_x86_64.manylinux1_x86_64.manylinux_2_12_x86_64.manylinux2010_x86_64.whl"],
        sha256 = "40527857252b61eacd1d9af500c3337ba8deb8fc298940291486c465c8b46ec0",
        downloaded_file_path = "PyYAML-6.0-cp39-cp39-manylinux_2_5_x86_64.manylinux1_x86_64.manylinux_2_12_x86_64.manylinux2010_x86_64.whl",
    )

    http_file(
        name = "example_lock_wheel_requests_2.27.1_py2.py3_none_any",
        urls = ["https://files.pythonhosted.org/packages/py2.py3/r/requests/requests-2.27.1-py2.py3-none-any.whl"],
        sha256 = "f22fa1e554c9ddfd16e6e41ac79759e17be9e492b3587efa038054674760e72d",
        downloaded_file_path = "requests-2.27.1-py2.py3-none-any.whl",
    )

    http_file(
        name = "example_lock_wheel_responses_0.20.0_py3_none_any",
        urls = ["https://files.pythonhosted.org/packages/py3/r/responses/responses-0.20.0-py3-none-any.whl"],
        sha256 = "18831bc2d72443b67664d98038374a6fa1f27eaaff4dd9a7d7613723416fea3c",
        downloaded_file_path = "responses-0.20.0-py3-none-any.whl",
    )

    http_file(
        name = "example_lock_wheel_rsa_4.8_py3_none_any",
        urls = ["https://files.pythonhosted.org/packages/py3/r/rsa/rsa-4.8-py3-none-any.whl"],
        sha256 = "95c5d300c4e879ee69708c428ba566c59478fd653cc3a22243eeb8ed846950bb",
        downloaded_file_path = "rsa-4.8-py3-none-any.whl",
    )

    http_file(
        name = "example_lock_wheel_s3transfer_0.5.2_py3_none_any",
        urls = ["https://files.pythonhosted.org/packages/py3/s/s3transfer/s3transfer-0.5.2-py3-none-any.whl"],
        sha256 = "7a6f4c4d1fdb9a2b640244008e142cbc2cd3ae34b386584ef044dd0f27101971",
        downloaded_file_path = "s3transfer-0.5.2-py3-none-any.whl",
    )

    http_file(
        name = "example_lock_wheel_sarif_om_1.0.4_py3_none_any",
        urls = ["https://files.pythonhosted.org/packages/py3/s/sarif_om/sarif_om-1.0.4-py3-none-any.whl"],
        sha256 = "539ef47a662329b1c8502388ad92457425e95dc0aaaf995fe46f4984c4771911",
        downloaded_file_path = "sarif_om-1.0.4-py3-none-any.whl",
    )

    http_file(
        name = "example_lock_wheel_six_1.16.0_py2.py3_none_any",
        urls = ["https://files.pythonhosted.org/packages/py2.py3/s/six/six-1.16.0-py2.py3-none-any.whl"],
        sha256 = "8abb2f1d86890a2dfb989f9a77cfcfd3e47c2a354b01111771326f8aa26e0254",
        downloaded_file_path = "six-1.16.0-py2.py3-none-any.whl",
    )

    http_file(
        name = "example_lock_wheel_sqlalchemy_1.4.32_cp39_cp39_macosx_10_15_x86_64",
        urls = ["https://files.pythonhosted.org/packages/cp39/S/SQLAlchemy/SQLAlchemy-1.4.32-cp39-cp39-macosx_10_15_x86_64.whl"],
        sha256 = "5dc9801ae9884e822ba942ca493642fb50f049c06b6dbe3178691fce48ceb089",
        downloaded_file_path = "SQLAlchemy-1.4.32-cp39-cp39-macosx_10_15_x86_64.whl",
    )

    http_file(
        name = "example_lock_wheel_sqlalchemy_1.4.32_cp39_cp39_manylinux_2_5_x86_64.manylinux1_x86_64.manylinux_2_17_x86_64.manylinux2014_x86_64",
        urls = ["https://files.pythonhosted.org/packages/cp39/S/SQLAlchemy/SQLAlchemy-1.4.32-cp39-cp39-manylinux_2_5_x86_64.manylinux1_x86_64.manylinux_2_17_x86_64.manylinux2014_x86_64.whl"],
        sha256 = "290cbdf19129ae520d4bdce392648c6fcdbee763bc8f750b53a5ab51880cb9c9",
        downloaded_file_path = "SQLAlchemy-1.4.32-cp39-cp39-manylinux_2_5_x86_64.manylinux1_x86_64.manylinux_2_17_x86_64.manylinux2014_x86_64.whl",
    )

    http_file(
        name = "example_lock_wheel_sqlalchemy_utils_0.38.2_py3_none_any",
        urls = ["https://files.pythonhosted.org/packages/py3/S/SQLAlchemy_Utils/SQLAlchemy_Utils-0.38.2-py3-none-any.whl"],
        sha256 = "622235b1598f97300e4d08820ab024f5219c9a6309937a8b908093f487b4ba54",
        downloaded_file_path = "SQLAlchemy_Utils-0.38.2-py3-none-any.whl",
    )

    http_file(
        name = "example_lock_wheel_sshpubkeys_3.3.1_py2.py3_none_any",
        urls = ["https://files.pythonhosted.org/packages/py2.py3/s/sshpubkeys/sshpubkeys-3.3.1-py2.py3-none-any.whl"],
        sha256 = "946f76b8fe86704b0e7c56a00d80294e39bc2305999844f079a217885060b1ac",
        downloaded_file_path = "sshpubkeys-3.3.1-py2.py3-none-any.whl",
    )

    http_file(
        name = "example_lock_wheel_stack_data_0.2.0_py3_none_any",
        urls = ["https://files.pythonhosted.org/packages/py3/s/stack_data/stack_data-0.2.0-py3-none-any.whl"],
        sha256 = "999762f9c3132308789affa03e9271bbbe947bf78311851f4d485d8402ed858e",
        downloaded_file_path = "stack_data-0.2.0-py3-none-any.whl",
    )

    http_file(
        name = "example_lock_wheel_traitlets_5.1.1_py3_none_any",
        urls = ["https://files.pythonhosted.org/packages/py3/t/traitlets/traitlets-5.1.1-py3-none-any.whl"],
        sha256 = "2d313cc50a42cd6c277e7d7dc8d4d7fedd06a2c215f78766ae7b1a66277e0033",
        downloaded_file_path = "traitlets-5.1.1-py3-none-any.whl",
    )

    http_file(
        name = "example_lock_wheel_urllib3_1.26.9_py2.py3_none_any",
        urls = ["https://files.pythonhosted.org/packages/py2.py3/u/urllib3/urllib3-1.26.9-py2.py3-none-any.whl"],
        sha256 = "44ece4d53fb1706f667c9bd1c648f5469a2ec925fcf3a776667042d645472c14",
        downloaded_file_path = "urllib3-1.26.9-py2.py3-none-any.whl",
    )

    http_file(
        name = "example_lock_wheel_wcwidth_0.2.5_py2.py3_none_any",
        urls = ["https://files.pythonhosted.org/packages/py2.py3/w/wcwidth/wcwidth-0.2.5-py2.py3-none-any.whl"],
        sha256 = "beb4802a9cebb9144e99086eff703a642a13d6a0052920003a230f3294bbe784",
        downloaded_file_path = "wcwidth-0.2.5-py2.py3-none-any.whl",
    )

    http_file(
        name = "example_lock_wheel_websocket_client_1.3.1_py3_none_any",
        urls = ["https://files.pythonhosted.org/packages/py3/w/websocket_client/websocket_client-1.3.1-py3-none-any.whl"],
        sha256 = "074e2ed575e7c822fc0940d31c3ac9bb2b1142c303eafcf3e304e6ce035522e8",
        downloaded_file_path = "websocket_client-1.3.1-py3-none-any.whl",
    )

    http_file(
        name = "example_lock_wheel_werkzeug_2.1.0_py3_none_any",
        urls = ["https://files.pythonhosted.org/packages/py3/W/Werkzeug/Werkzeug-2.1.0-py3-none-any.whl"],
        sha256 = "094ecfc981948f228b30ee09dbfe250e474823b69b9b1292658301b5894bbf08",
        downloaded_file_path = "Werkzeug-2.1.0-py3-none-any.whl",
    )

    http_file(
        name = "example_lock_wheel_wrapt_1.14.0_cp39_cp39_macosx_10_9_x86_64",
        urls = ["https://files.pythonhosted.org/packages/cp39/w/wrapt/wrapt-1.14.0-cp39-cp39-macosx_10_9_x86_64.whl"],
        sha256 = "b3f7e671fb19734c872566e57ce7fc235fa953d7c181bb4ef138e17d607dc8a1",
        downloaded_file_path = "wrapt-1.14.0-cp39-cp39-macosx_10_9_x86_64.whl",
    )

    http_file(
        name = "example_lock_wheel_wrapt_1.14.0_cp39_cp39_macosx_11_0_arm64",
        urls = ["https://files.pythonhosted.org/packages/cp39/w/wrapt/wrapt-1.14.0-cp39-cp39-macosx_11_0_arm64.whl"],
        sha256 = "87fa943e8bbe40c8c1ba4086971a6fefbf75e9991217c55ed1bcb2f1985bd3d4",
        downloaded_file_path = "wrapt-1.14.0-cp39-cp39-macosx_11_0_arm64.whl",
    )

    http_file(
        name = "example_lock_wheel_wrapt_1.14.0_cp39_cp39_manylinux_2_5_x86_64.manylinux1_x86_64.manylinux_2_17_x86_64.manylinux2014_x86_64",
        urls = ["https://files.pythonhosted.org/packages/cp39/w/wrapt/wrapt-1.14.0-cp39-cp39-manylinux_2_5_x86_64.manylinux1_x86_64.manylinux_2_17_x86_64.manylinux2014_x86_64.whl"],
        sha256 = "00108411e0f34c52ce16f81f1d308a571df7784932cc7491d1e94be2ee93374b",
        downloaded_file_path = "wrapt-1.14.0-cp39-cp39-manylinux_2_5_x86_64.manylinux1_x86_64.manylinux_2_17_x86_64.manylinux2014_x86_64.whl",
    )

    http_file(
        name = "example_lock_wheel_xmltodict_0.12.0_py2.py3_none_any",
        urls = ["https://files.pythonhosted.org/packages/3.7/x/xmltodict/xmltodict-0.12.0-py2.py3-none-any.whl"],
        sha256 = "8bbcb45cc982f48b2ca8fe7e7827c5d792f217ecf1792626f808bf41c3b86051",
        downloaded_file_path = "xmltodict-0.12.0-py2.py3-none-any.whl",
    )

    http_file(
        name = "example_lock_wheel_zipp_3.7.0_py3_none_any",
        urls = ["https://files.pythonhosted.org/packages/py3/z/zipp/zipp-3.7.0-py3-none-any.whl"],
        sha256 = "b47250dd24f92b7dd6a0a8fc5244da14608f3ca90a5efcd37a3b1642fac9a375",
        downloaded_file_path = "zipp-3.7.0-py3-none-any.whl",
    )

