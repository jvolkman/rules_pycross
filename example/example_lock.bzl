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
        name = "example_lock_pkg_aws_xray_sdk",
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

    pycross_wheel_library(
        name = "example_lock_pkg_cffi",
        wheel = select({
            ":example_lock_env_python_darwin_x86_64": "@example_lock_wheel_cffi_1.15.0_cp39_cp39_macosx_10_9_x86_64//file",
            ":example_lock_env_python_darwin_arm64": "@example_lock_wheel_cffi_1.15.0_cp39_cp39_macosx_11_0_arm64//file",
            ":example_lock_env_python_linux_x86_64": "@example_lock_wheel_cffi_1.15.0_cp39_cp39_manylinux_2_12_x86_64.manylinux2010_x86_64//file",
        }),
    )

    pycross_wheel_library(
        name = "example_lock_pkg_cfn_lint",
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

    pycross_wheel_library(
        name = "example_lock_pkg_flask_cors",
        wheel = "@example_lock_wheel_flask_cors_3.0.10_py2.py3_none_any//file",
    )

    pycross_wheel_library(
        name = "example_lock_pkg_graphql_core",
        wheel = "@example_lock_wheel_graphql_core_3.2.0_py3_none_any//file",
    )

    pycross_wheel_build(
        name = "example_lock_pkg_greenlet",
        sdist = "@example_lock_sdist_greenlet_1.1.2//file",
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

    pycross_wheel_build(
        name = "example_lock_pkg_jsondiff",
        sdist = "@example_lock_sdist_jsondiff_1.3.1//file",
    )

    pycross_wheel_library(
        name = "example_lock_pkg_jsondiff",
        wheel = ":example_lock_build_jsondiff",
    )

    pycross_wheel_library(
        name = "example_lock_pkg_markupsafe",
        wheel = select({
            ":example_lock_env_python_darwin_x86_64": "@example_lock_wheel_markupsafe_2.1.1_cp39_cp39_macosx_10_9_x86_64//file",
            ":example_lock_env_python_darwin_arm64": "@example_lock_wheel_markupsafe_2.1.1_cp39_cp39_macosx_10_9_universal2//file",
            ":example_lock_env_python_linux_x86_64": "@example_lock_wheel_markupsafe_2.1.1_cp39_cp39_manylinux_2_17_x86_64.manylinux2014_x86_64//file",
        }),
    )

    pycross_wheel_library(
        name = "example_lock_pkg_matplotlib_inline",
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
        name = "example_lock_pkg_parso",
        wheel = "@example_lock_wheel_parso_0.8.3_py2.py3_none_any//file",
    )

    pycross_wheel_library(
        name = "example_lock_pkg_pexpect",
        wheel = "@example_lock_wheel_pexpect_4.8.0_py2.py3_none_any//file",
    )

    pycross_wheel_library(
        name = "example_lock_pkg_pickleshare",
        wheel = "@example_lock_wheel_pickleshare_0.7.5_py2.py3_none_any//file",
    )

    pycross_wheel_library(
        name = "example_lock_pkg_prompt_toolkit",
        wheel = "@example_lock_wheel_prompt_toolkit_3.0.28_py3_none_any//file",
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
        name = "example_lock_pkg_pygments",
        wheel = "@example_lock_wheel_pygments_2.11.2_py3_none_any//file",
    )

    pycross_wheel_library(
        name = "example_lock_pkg_python_dateutil",
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

    pycross_wheel_library(
        name = "example_lock_pkg_rsa",
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
        name = "example_lock_pkg_sqlalchemy",
        sdist = "@example_lock_sdist_sqlalchemy_1.4.32//file",
        deps = [":example_lock_deps_sqlalchemy"],
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
        name = "example_lock_pkg_websocket_client",
        wheel = "@example_lock_wheel_websocket_client_1.3.1_py3_none_any//file",
    )

    pycross_wheel_library(
        name = "example_lock_pkg_werkzeug",
        wheel = "@example_lock_wheel_werkzeug_2.1.0_py3_none_any//file",
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
        name = "example_lock_sdist_greenlet_1.1.2",
        urls = ["https://files.pythonhosted.org/packages/source/g/greenlet/greenlet-1.1.2.tar.gz"],
        sha256 = "e30f5ea4ae2346e62cedde8794a56858a67b878dd79f7df76a0767e356b1744a",
    )

    http_file(
        name = "example_lock_sdist_jsondiff_1.3.1",
        urls = ["https://files.pythonhosted.org/packages/source/j/jsondiff/jsondiff-1.3.1.tar.gz"],
        sha256 = "04cfaebd4a5e5738948ab615710dc3ee98efbdf851255fd3977c4c2ee59e7312",
    )

    http_file(
        name = "example_lock_sdist_sqlalchemy_1.4.32",
        urls = ["https://files.pythonhosted.org/packages/source/S/SQLAlchemy/SQLAlchemy-1.4.32.tar.gz"],
        sha256 = "6fdd2dc5931daab778c2b65b03df6ae68376e028a3098eb624d0909d999885bc",
    )

    http_file(
        name = "example_lock_wheel_appnope_0.1.2_py2.py3_none_any",
        urls = ["https://files.pythonhosted.org/packages/py2.py3/a/appnope/appnope-0.1.2-py2.py3-none-any.whl"],
        sha256 = "93aa393e9d6c54c5cd570ccadd8edad61ea0c4b9ea7a01409020c9aa019eb442",
    )

    http_file(
        name = "example_lock_wheel_asttokens_2.0.5_py2.py3_none_any",
        urls = ["https://files.pythonhosted.org/packages/py2.py3/a/asttokens/asttokens-2.0.5-py2.py3-none-any.whl"],
        sha256 = "0844691e88552595a6f4a4281a9f7f79b8dd45ca4ccea82e5e05b4bbdb76705c",
    )

    http_file(
        name = "example_lock_wheel_aws_xray_sdk_2.9.0_py2.py3_none_any",
        urls = ["https://files.pythonhosted.org/packages/py2.py3/a/aws_xray_sdk/aws_xray_sdk-2.9.0-py2.py3-none-any.whl"],
        sha256 = "98216b3ac8281b51b59a8703f8ec561c460807d9d0679838f5c0179d381d7e58",
    )

    http_file(
        name = "example_lock_wheel_backcall_0.2.0_py2.py3_none_any",
        urls = ["https://files.pythonhosted.org/packages/py2.py3/b/backcall/backcall-0.2.0-py2.py3-none-any.whl"],
        sha256 = "fbbce6a29f263178a1f7915c1940bde0ec2b2a967566fe1c65c1dfb7422bd255",
    )

    http_file(
        name = "example_lock_wheel_boto3_1.21.28_py3_none_any",
        urls = ["https://files.pythonhosted.org/packages/py3/b/boto3/boto3-1.21.28-py3-none-any.whl"],
        sha256 = "ca37b9b4ade72f6d4fa2b7bee584dd5b1c7585f07f22ff1edbc9ecc0c4173b1f",
    )

    http_file(
        name = "example_lock_wheel_botocore_1.24.28_py3_none_any",
        urls = ["https://files.pythonhosted.org/packages/py3/b/botocore/botocore-1.24.28-py3-none-any.whl"],
        sha256 = "03c41d26d1e765380b8175d4b136d3144aa051f17a86eebfdf9a885a5a9a6a72",
    )

    http_file(
        name = "example_lock_wheel_certifi_2021.10.8_py2.py3_none_any",
        urls = ["https://files.pythonhosted.org/packages/py2.py3/c/certifi/certifi-2021.10.8-py2.py3-none-any.whl"],
        sha256 = "d62a0163eb4c2344ac042ab2bdf75399a71a2d8c7d47eac2e2ee91b9d6339569",
    )

    http_file(
        name = "example_lock_wheel_cffi_1.15.0_cp39_cp39_macosx_10_9_x86_64",
        urls = ["https://files.pythonhosted.org/packages/cp39/c/cffi/cffi-1.15.0-cp39-cp39-macosx_10_9_x86_64.whl"],
        sha256 = "45e8636704eacc432a206ac7345a5d3d2c62d95a507ec70d62f23cd91770482a",
    )

    http_file(
        name = "example_lock_wheel_cffi_1.15.0_cp39_cp39_macosx_11_0_arm64",
        urls = ["https://files.pythonhosted.org/packages/cp39/c/cffi/cffi-1.15.0-cp39-cp39-macosx_11_0_arm64.whl"],
        sha256 = "31fb708d9d7c3f49a60f04cf5b119aeefe5644daba1cd2a0fe389b674fd1de37",
    )

    http_file(
        name = "example_lock_wheel_cffi_1.15.0_cp39_cp39_manylinux_2_12_x86_64.manylinux2010_x86_64",
        urls = ["https://files.pythonhosted.org/packages/cp39/c/cffi/cffi-1.15.0-cp39-cp39-manylinux_2_12_x86_64.manylinux2010_x86_64.whl"],
        sha256 = "74fdfdbfdc48d3f47148976f49fab3251e550a8720bebc99bf1483f5bfb5db3e",
    )

    http_file(
        name = "example_lock_wheel_cfn_lint_0.58.4_py3_none_any",
        urls = ["https://files.pythonhosted.org/packages/py3/c/cfn_lint/cfn_lint-0.58.4-py3-none-any.whl"],
        sha256 = "c21a4ea369e54501dc1bd6c294bb083bcd1731f4374f2fb1e87228ed720781f3",
    )

    http_file(
        name = "example_lock_wheel_charset_normalizer_2.0.12_py3_none_any",
        urls = ["https://files.pythonhosted.org/packages/py3/c/charset_normalizer/charset_normalizer-2.0.12-py3-none-any.whl"],
        sha256 = "6881edbebdb17b39b4eaaa821b438bf6eddffb4468cf344f09f89def34a8b1df",
    )

    http_file(
        name = "example_lock_wheel_click_8.1.0_py3_none_any",
        urls = ["https://files.pythonhosted.org/packages/py3/c/click/click-8.1.0-py3-none-any.whl"],
        sha256 = "19a4baa64da924c5e0cd889aba8e947f280309f1a2ce0947a3e3a7bcb7cc72d6",
    )

    http_file(
        name = "example_lock_wheel_cognitojwt_1.4.1_py3_none_any",
        urls = ["https://files.pythonhosted.org/packages/py3/c/cognitojwt/cognitojwt-1.4.1-py3-none-any.whl"],
        sha256 = "8ee189f82289d140dc750c91e8772436b64b94d071507ace42efc22c525f42ce",
    )

    http_file(
        name = "example_lock_wheel_cryptography_36.0.2_cp36_abi3_macosx_10_10_universal2",
        urls = ["https://files.pythonhosted.org/packages/cp36/c/cryptography/cryptography-36.0.2-cp36-abi3-macosx_10_10_universal2.whl"],
        sha256 = "4e2dddd38a5ba733be6a025a1475a9f45e4e41139d1321f412c6b360b19070b6",
    )

    http_file(
        name = "example_lock_wheel_cryptography_36.0.2_cp36_abi3_macosx_10_10_x86_64",
        urls = ["https://files.pythonhosted.org/packages/cp36/c/cryptography/cryptography-36.0.2-cp36-abi3-macosx_10_10_x86_64.whl"],
        sha256 = "4881d09298cd0b669bb15b9cfe6166f16fc1277b4ed0d04a22f3d6430cb30f1d",
    )

    http_file(
        name = "example_lock_wheel_cryptography_36.0.2_cp36_abi3_manylinux_2_17_x86_64.manylinux2014_x86_64",
        urls = ["https://files.pythonhosted.org/packages/cp36/c/cryptography/cryptography-36.0.2-cp36-abi3-manylinux_2_17_x86_64.manylinux2014_x86_64.whl"],
        sha256 = "7b2d54e787a884ffc6e187262823b6feb06c338084bbe80d45166a1cb1c6c5bf",
    )

    http_file(
        name = "example_lock_wheel_decorator_5.1.1_py3_none_any",
        urls = ["https://files.pythonhosted.org/packages/py3/d/decorator/decorator-5.1.1-py3-none-any.whl"],
        sha256 = "b8c3f85900b9dc423225913c5aace94729fe1fa9763b38939a95226f02d37186",
    )

    http_file(
        name = "example_lock_wheel_docker_5.0.3_py2.py3_none_any",
        urls = ["https://files.pythonhosted.org/packages/py2.py3/d/docker/docker-5.0.3-py2.py3-none-any.whl"],
        sha256 = "7a79bb439e3df59d0a72621775d600bc8bc8b422d285824cb37103eab91d1ce0",
    )

    http_file(
        name = "example_lock_wheel_ecdsa_0.17.0_py2.py3_none_any",
        urls = ["https://files.pythonhosted.org/packages/py2.py3/e/ecdsa/ecdsa-0.17.0-py2.py3-none-any.whl"],
        sha256 = "5cf31d5b33743abe0dfc28999036c849a69d548f994b535e527ee3cb7f3ef676",
    )

    http_file(
        name = "example_lock_wheel_executing_0.8.3_py2.py3_none_any",
        urls = ["https://files.pythonhosted.org/packages/py2.py3/e/executing/executing-0.8.3-py2.py3-none-any.whl"],
        sha256 = "d1eef132db1b83649a3905ca6dd8897f71ac6f8cac79a7e58a1a09cf137546c9",
    )

    http_file(
        name = "example_lock_wheel_flask_2.1.0_py3_none_any",
        urls = ["https://files.pythonhosted.org/packages/py3/F/Flask/Flask-2.1.0-py3-none-any.whl"],
        sha256 = "e4c69910f6a096cc57e4ee45b7ba9afafdcad4cc571db6eb97d5bd01b95422ea",
    )

    http_file(
        name = "example_lock_wheel_flask_cors_3.0.10_py2.py3_none_any",
        urls = ["https://files.pythonhosted.org/packages/py2.py3/F/Flask_Cors/Flask_Cors-3.0.10-py2.py3-none-any.whl"],
        sha256 = "74efc975af1194fc7891ff5cd85b0f7478be4f7f59fe158102e91abb72bb4438",
    )

    http_file(
        name = "example_lock_wheel_graphql_core_3.2.0_py3_none_any",
        urls = ["https://files.pythonhosted.org/packages/py3/g/graphql_core/graphql_core-3.2.0-py3-none-any.whl"],
        sha256 = "0dda7e63676f119bb3d814621190fedad72fda07a8e9ab780bedd9f1957c6dc6",
    )

    http_file(
        name = "example_lock_wheel_greenlet_1.1.2_cp39_cp39_macosx_10_14_x86_64",
        urls = ["https://files.pythonhosted.org/packages/cp39/g/greenlet/greenlet-1.1.2-cp39-cp39-macosx_10_14_x86_64.whl"],
        sha256 = "166eac03e48784a6a6e0e5f041cfebb1ab400b394db188c48b3a84737f505b67",
    )

    http_file(
        name = "example_lock_wheel_greenlet_1.1.2_cp39_cp39_manylinux_2_17_x86_64.manylinux2014_x86_64",
        urls = ["https://files.pythonhosted.org/packages/cp39/g/greenlet/greenlet-1.1.2-cp39-cp39-manylinux_2_17_x86_64.manylinux2014_x86_64.whl"],
        sha256 = "7ff61ff178250f9bb3cd89752df0f1dd0e27316a8bd1465351652b1b4a4cdfd3",
    )

    http_file(
        name = "example_lock_wheel_idna_3.3_py3_none_any",
        urls = ["https://files.pythonhosted.org/packages/py3/i/idna/idna-3.3-py3-none-any.whl"],
        sha256 = "84d9dd047ffa80596e0f246e2eab0b391788b0503584e8945f2368256d2735ff",
    )

    http_file(
        name = "example_lock_wheel_importlib_metadata_4.11.3_py3_none_any",
        urls = ["https://files.pythonhosted.org/packages/py3/i/importlib_metadata/importlib_metadata-4.11.3-py3-none-any.whl"],
        sha256 = "1208431ca90a8cca1a6b8af391bb53c1a2db74e5d1cef6ddced95d4b2062edc6",
    )

    http_file(
        name = "example_lock_wheel_ipython_8.2.0_py3_none_any",
        urls = ["https://files.pythonhosted.org/packages/py3/i/ipython/ipython-8.2.0-py3-none-any.whl"],
        sha256 = "1b672bfd7a48d87ab203d9af8727a3b0174a4566b4091e9447c22fb63ea32857",
    )

    http_file(
        name = "example_lock_wheel_itsdangerous_2.1.2_py3_none_any",
        urls = ["https://files.pythonhosted.org/packages/py3/i/itsdangerous/itsdangerous-2.1.2-py3-none-any.whl"],
        sha256 = "2c2349112351b88699d8d4b6b075022c0808887cb7ad10069318a8b0bc88db44",
    )

    http_file(
        name = "example_lock_wheel_jedi_0.18.1_py2.py3_none_any",
        urls = ["https://files.pythonhosted.org/packages/py2.py3/j/jedi/jedi-0.18.1-py2.py3-none-any.whl"],
        sha256 = "637c9635fcf47945ceb91cd7f320234a7be540ded6f3e99a50cb6febdfd1ba8d",
    )

    http_file(
        name = "example_lock_wheel_jinja2_3.1.1_py3_none_any",
        urls = ["https://files.pythonhosted.org/packages/py3/J/Jinja2/Jinja2-3.1.1-py3-none-any.whl"],
        sha256 = "539835f51a74a69f41b848a9645dbdc35b4f20a3b601e2d9a7e22947b15ff119",
    )

    http_file(
        name = "example_lock_wheel_jmespath_1.0.0_py3_none_any",
        urls = ["https://files.pythonhosted.org/packages/py3/j/jmespath/jmespath-1.0.0-py3-none-any.whl"],
        sha256 = "e8dcd576ed616f14ec02eed0005c85973b5890083313860136657e24784e4c04",
    )

    http_file(
        name = "example_lock_wheel_markupsafe_2.1.1_cp39_cp39_macosx_10_9_universal2",
        urls = ["https://files.pythonhosted.org/packages/cp39/M/MarkupSafe/MarkupSafe-2.1.1-cp39-cp39-macosx_10_9_universal2.whl"],
        sha256 = "e04e26803c9c3851c931eac40c695602c6295b8d432cbe78609649ad9bd2da8a",
    )

    http_file(
        name = "example_lock_wheel_markupsafe_2.1.1_cp39_cp39_macosx_10_9_x86_64",
        urls = ["https://files.pythonhosted.org/packages/cp39/M/MarkupSafe/MarkupSafe-2.1.1-cp39-cp39-macosx_10_9_x86_64.whl"],
        sha256 = "b87db4360013327109564f0e591bd2a3b318547bcef31b468a92ee504d07ae4f",
    )

    http_file(
        name = "example_lock_wheel_markupsafe_2.1.1_cp39_cp39_manylinux_2_17_x86_64.manylinux2014_x86_64",
        urls = ["https://files.pythonhosted.org/packages/cp39/M/MarkupSafe/MarkupSafe-2.1.1-cp39-cp39-manylinux_2_17_x86_64.manylinux2014_x86_64.whl"],
        sha256 = "56442863ed2b06d19c37f94d999035e15ee982988920e12a5b4ba29b62ad1f77",
    )

    http_file(
        name = "example_lock_wheel_matplotlib_inline_0.1.3_py3_none_any",
        urls = ["https://files.pythonhosted.org/packages/py3/m/matplotlib_inline/matplotlib_inline-0.1.3-py3-none-any.whl"],
        sha256 = "aed605ba3b72462d64d475a21a9296f400a19c4f74a31b59103d2a99ffd5aa5c",
    )

    http_file(
        name = "example_lock_wheel_moto_3.1.1_py2.py3_none_any",
        urls = ["https://files.pythonhosted.org/packages/py2.py3/m/moto/moto-3.1.1-py2.py3-none-any.whl"],
        sha256 = "462495563847134ea8ef4135a229731a598a8e7b6b10a74f8d745815aa20a25b",
    )

    http_file(
        name = "example_lock_wheel_parso_0.8.3_py2.py3_none_any",
        urls = ["https://files.pythonhosted.org/packages/py2.py3/p/parso/parso-0.8.3-py2.py3-none-any.whl"],
        sha256 = "c001d4636cd3aecdaf33cbb40aebb59b094be2a74c556778ef5576c175e19e75",
    )

    http_file(
        name = "example_lock_wheel_pexpect_4.8.0_py2.py3_none_any",
        urls = ["https://files.pythonhosted.org/packages/py2.py3/p/pexpect/pexpect-4.8.0-py2.py3-none-any.whl"],
        sha256 = "0b48a55dcb3c05f3329815901ea4fc1537514d6ba867a152b581d69ae3710937",
    )

    http_file(
        name = "example_lock_wheel_pickleshare_0.7.5_py2.py3_none_any",
        urls = ["https://files.pythonhosted.org/packages/py2.py3/p/pickleshare/pickleshare-0.7.5-py2.py3-none-any.whl"],
        sha256 = "9649af414d74d4df115d5d718f82acb59c9d418196b7b4290ed47a12ce62df56",
    )

    http_file(
        name = "example_lock_wheel_prompt_toolkit_3.0.28_py3_none_any",
        urls = ["https://files.pythonhosted.org/packages/py3/p/prompt_toolkit/prompt_toolkit-3.0.28-py3-none-any.whl"],
        sha256 = "30129d870dcb0b3b6a53efdc9d0a83ea96162ffd28ffe077e94215b233dc670c",
    )

    http_file(
        name = "example_lock_wheel_pure_eval_0.2.2_py3_none_any",
        urls = ["https://files.pythonhosted.org/packages/py3/p/pure_eval/pure_eval-0.2.2-py3-none-any.whl"],
        sha256 = "01eaab343580944bc56080ebe0a674b39ec44a945e6d09ba7db3cb8cec289350",
    )

    http_file(
        name = "example_lock_wheel_pyasn1_0.4.8_py2.py3_none_any",
        urls = ["https://files.pythonhosted.org/packages/py2.py3/p/pyasn1/pyasn1-0.4.8-py2.py3-none-any.whl"],
        sha256 = "39c7e2ec30515947ff4e87fb6f456dfc6e84857d34be479c9d4a4ba4bf46aa5d",
    )

    http_file(
        name = "example_lock_wheel_pygments_2.11.2_py3_none_any",
        urls = ["https://files.pythonhosted.org/packages/py3/P/Pygments/Pygments-2.11.2-py3-none-any.whl"],
        sha256 = "44238f1b60a76d78fc8ca0528ee429702aae011c265fe6a8dd8b63049ae41c65",
    )

    http_file(
        name = "example_lock_wheel_python_dateutil_2.8.2_py2.py3_none_any",
        urls = ["https://files.pythonhosted.org/packages/py2.py3/p/python_dateutil/python_dateutil-2.8.2-py2.py3-none-any.whl"],
        sha256 = "961d03dc3453ebbc59dbdea9e4e11c5651520a876d0f4db161e8674aae935da9",
    )

    http_file(
        name = "example_lock_wheel_python_jose_3.1.0_py2.py3_none_any",
        urls = ["https://files.pythonhosted.org/packages/py2.py3/p/python_jose/python_jose-3.1.0-py2.py3-none-any.whl"],
        sha256 = "1ac4caf4bfebd5a70cf5bd82702ed850db69b0b6e1d0ae7368e5f99ac01c9571",
    )

    http_file(
        name = "example_lock_wheel_pytz_2022.1_py2.py3_none_any",
        urls = ["https://files.pythonhosted.org/packages/py2.py3/p/pytz/pytz-2022.1-py2.py3-none-any.whl"],
        sha256 = "e68985985296d9a66a881eb3193b0906246245294a881e7c8afe623866ac6a5c",
    )

    http_file(
        name = "example_lock_wheel_pyyaml_6.0_cp39_cp39_macosx_10_9_x86_64",
        urls = ["https://files.pythonhosted.org/packages/cp39/P/PyYAML/PyYAML-6.0-cp39-cp39-macosx_10_9_x86_64.whl"],
        sha256 = "055d937d65826939cb044fc8c9b08889e8c743fdc6a32b33e2390f66013e449b",
    )

    http_file(
        name = "example_lock_wheel_pyyaml_6.0_cp39_cp39_macosx_11_0_arm64",
        urls = ["https://files.pythonhosted.org/packages/cp39/P/PyYAML/PyYAML-6.0-cp39-cp39-macosx_11_0_arm64.whl"],
        sha256 = "e61ceaab6f49fb8bdfaa0f92c4b57bcfbea54c09277b1b4f7ac376bfb7a7c174",
    )

    http_file(
        name = "example_lock_wheel_pyyaml_6.0_cp39_cp39_manylinux_2_5_x86_64.manylinux1_x86_64.manylinux_2_12_x86_64.manylinux2010_x86_64",
        urls = ["https://files.pythonhosted.org/packages/cp39/P/PyYAML/PyYAML-6.0-cp39-cp39-manylinux_2_5_x86_64.manylinux1_x86_64.manylinux_2_12_x86_64.manylinux2010_x86_64.whl"],
        sha256 = "40527857252b61eacd1d9af500c3337ba8deb8fc298940291486c465c8b46ec0",
    )

    http_file(
        name = "example_lock_wheel_requests_2.27.1_py2.py3_none_any",
        urls = ["https://files.pythonhosted.org/packages/py2.py3/r/requests/requests-2.27.1-py2.py3-none-any.whl"],
        sha256 = "f22fa1e554c9ddfd16e6e41ac79759e17be9e492b3587efa038054674760e72d",
    )

    http_file(
        name = "example_lock_wheel_responses_0.20.0_py3_none_any",
        urls = ["https://files.pythonhosted.org/packages/py3/r/responses/responses-0.20.0-py3-none-any.whl"],
        sha256 = "18831bc2d72443b67664d98038374a6fa1f27eaaff4dd9a7d7613723416fea3c",
    )

    http_file(
        name = "example_lock_wheel_rsa_4.8_py3_none_any",
        urls = ["https://files.pythonhosted.org/packages/py3/r/rsa/rsa-4.8-py3-none-any.whl"],
        sha256 = "95c5d300c4e879ee69708c428ba566c59478fd653cc3a22243eeb8ed846950bb",
    )

    http_file(
        name = "example_lock_wheel_s3transfer_0.5.2_py3_none_any",
        urls = ["https://files.pythonhosted.org/packages/py3/s/s3transfer/s3transfer-0.5.2-py3-none-any.whl"],
        sha256 = "7a6f4c4d1fdb9a2b640244008e142cbc2cd3ae34b386584ef044dd0f27101971",
    )

    http_file(
        name = "example_lock_wheel_six_1.16.0_py2.py3_none_any",
        urls = ["https://files.pythonhosted.org/packages/py2.py3/s/six/six-1.16.0-py2.py3-none-any.whl"],
        sha256 = "8abb2f1d86890a2dfb989f9a77cfcfd3e47c2a354b01111771326f8aa26e0254",
    )

    http_file(
        name = "example_lock_wheel_sqlalchemy_1.4.32_cp39_cp39_macosx_10_15_x86_64",
        urls = ["https://files.pythonhosted.org/packages/cp39/S/SQLAlchemy/SQLAlchemy-1.4.32-cp39-cp39-macosx_10_15_x86_64.whl"],
        sha256 = "5dc9801ae9884e822ba942ca493642fb50f049c06b6dbe3178691fce48ceb089",
    )

    http_file(
        name = "example_lock_wheel_sqlalchemy_1.4.32_cp39_cp39_manylinux_2_5_x86_64.manylinux1_x86_64.manylinux_2_17_x86_64.manylinux2014_x86_64",
        urls = ["https://files.pythonhosted.org/packages/cp39/S/SQLAlchemy/SQLAlchemy-1.4.32-cp39-cp39-manylinux_2_5_x86_64.manylinux1_x86_64.manylinux_2_17_x86_64.manylinux2014_x86_64.whl"],
        sha256 = "290cbdf19129ae520d4bdce392648c6fcdbee763bc8f750b53a5ab51880cb9c9",
    )

    http_file(
        name = "example_lock_wheel_sqlalchemy_utils_0.38.2_py3_none_any",
        urls = ["https://files.pythonhosted.org/packages/py3/S/SQLAlchemy_Utils/SQLAlchemy_Utils-0.38.2-py3-none-any.whl"],
        sha256 = "622235b1598f97300e4d08820ab024f5219c9a6309937a8b908093f487b4ba54",
    )

    http_file(
        name = "example_lock_wheel_sshpubkeys_3.3.1_py2.py3_none_any",
        urls = ["https://files.pythonhosted.org/packages/py2.py3/s/sshpubkeys/sshpubkeys-3.3.1-py2.py3-none-any.whl"],
        sha256 = "946f76b8fe86704b0e7c56a00d80294e39bc2305999844f079a217885060b1ac",
    )

    http_file(
        name = "example_lock_wheel_stack_data_0.2.0_py3_none_any",
        urls = ["https://files.pythonhosted.org/packages/py3/s/stack_data/stack_data-0.2.0-py3-none-any.whl"],
        sha256 = "999762f9c3132308789affa03e9271bbbe947bf78311851f4d485d8402ed858e",
    )

    http_file(
        name = "example_lock_wheel_traitlets_5.1.1_py3_none_any",
        urls = ["https://files.pythonhosted.org/packages/py3/t/traitlets/traitlets-5.1.1-py3-none-any.whl"],
        sha256 = "2d313cc50a42cd6c277e7d7dc8d4d7fedd06a2c215f78766ae7b1a66277e0033",
    )

    http_file(
        name = "example_lock_wheel_urllib3_1.26.9_py2.py3_none_any",
        urls = ["https://files.pythonhosted.org/packages/py2.py3/u/urllib3/urllib3-1.26.9-py2.py3-none-any.whl"],
        sha256 = "44ece4d53fb1706f667c9bd1c648f5469a2ec925fcf3a776667042d645472c14",
    )

    http_file(
        name = "example_lock_wheel_websocket_client_1.3.1_py3_none_any",
        urls = ["https://files.pythonhosted.org/packages/py3/w/websocket_client/websocket_client-1.3.1-py3-none-any.whl"],
        sha256 = "074e2ed575e7c822fc0940d31c3ac9bb2b1142c303eafcf3e304e6ce035522e8",
    )

    http_file(
        name = "example_lock_wheel_werkzeug_2.1.0_py3_none_any",
        urls = ["https://files.pythonhosted.org/packages/py3/W/Werkzeug/Werkzeug-2.1.0-py3-none-any.whl"],
        sha256 = "094ecfc981948f228b30ee09dbfe250e474823b69b9b1292658301b5894bbf08",
    )

    http_file(
        name = "example_lock_wheel_xmltodict_0.12.0_py2.py3_none_any",
        urls = ["https://files.pythonhosted.org/packages/3.7/x/xmltodict/xmltodict-0.12.0-py2.py3-none-any.whl"],
        sha256 = "8bbcb45cc982f48b2ca8fe7e7827c5d792f217ecf1792626f808bf41c3b86051",
    )

    http_file(
        name = "example_lock_wheel_zipp_3.7.0_py3_none_any",
        urls = ["https://files.pythonhosted.org/packages/py3/z/zipp/zipp-3.7.0-py3-none-any.whl"],
        sha256 = "b47250dd24f92b7dd6a0a8fc5244da14608f3ca90a5efcd37a3b1642fac9a375",
    )

