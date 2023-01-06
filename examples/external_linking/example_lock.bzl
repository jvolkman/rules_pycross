load("@bazel_tools//tools/build_defs/repo:http.bzl", "http_file")
load("@bazel_tools//tools/build_defs/repo:utils.bzl", "maybe")
load("@jvolkman_rules_pycross//pycross:defs.bzl", "pycross_wheel_build", "pycross_wheel_library", "pypi_file")

PINS = {
    "appnope": "appnope_0.1.3",
    "asttokens": "asttokens_2.2.1",
    "backcall": "backcall_0.2.0",
    "cython": "cython_0.29.33",
    "decorator": "decorator_5.1.1",
    "executing": "executing_1.2.0",
    "ipython": "ipython_8.8.0",
    "jedi": "jedi_0.18.2",
    "matplotlib_inline": "matplotlib_inline_0.1.6",
    "numpy": "numpy_1.23.5",
    "pandas": "pandas_1.5.2",
    "parso": "parso_0.8.3",
    "pexpect": "pexpect_4.8.0",
    "pickleshare": "pickleshare_0.7.5",
    "prompt_toolkit": "prompt_toolkit_3.0.36",
    "psycopg2": "psycopg2_2.9.5",
    "ptyprocess": "ptyprocess_0.7.0",
    "pure_eval": "pure_eval_0.2.2",
    "pygments": "pygments_2.14.0",
    "python_dateutil": "python_dateutil_2.8.2",
    "pytz": "pytz_2022.7",
    "setproctitle": "setproctitle_1.3.2",
    "setuptools": "setuptools_59.2.0",
    "six": "six_1.16.0",
    "stack_data": "stack_data_0.6.2",
    "traitlets": "traitlets_5.8.0",
    "wcwidth": "wcwidth_0.2.5",
    "wheel": "wheel_0.37.0",
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
        name = "_env_python_linux_arm64",
        constraint_values = [
            "@platforms//os:linux",
            "@platforms//cpu:arm64",
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
        ":_env_python_linux_arm64": "@//:python_linux_arm64",
        ":_env_python_linux_x86_64": "@//:python_linux_x86_64",
    })

    pycross_wheel_library(
        name = "appnope_0.1.3",
        wheel = "@example_lock_wheel_appnope_0.1.3_py2.py3_none_any//file",
    )

    _asttokens_2_2_1_deps = [
        ":six_1.16.0",
    ]

    pycross_wheel_library(
        name = "asttokens_2.2.1",
        deps = _asttokens_2_2_1_deps,
        wheel = "@example_lock_wheel_asttokens_2.2.1_py2.py3_none_any//file",
    )

    pycross_wheel_library(
        name = "backcall_0.2.0",
        wheel = "@example_lock_wheel_backcall_0.2.0_py2.py3_none_any//file",
    )

    pycross_wheel_library(
        name = "cython_0.29.33",
        wheel = select({
            ":_env_python_darwin_arm64": "@example_lock_wheel_cython_0.29.33_py2.py3_none_any//file",
            ":_env_python_darwin_x86_64": "@example_lock_wheel_cython_0.29.33_py2.py3_none_any//file",
            ":_env_python_linux_arm64": "@example_lock_wheel_cython_0.29.33_cp310_cp310_manylinux_2_17_aarch64.manylinux2014_aarch64.manylinux_2_24_aarch64//file",
            ":_env_python_linux_x86_64": "@example_lock_wheel_cython_0.29.33_cp310_cp310_manylinux_2_17_x86_64.manylinux2014_x86_64.manylinux_2_24_x86_64//file",
        }),
    )

    pycross_wheel_library(
        name = "decorator_5.1.1",
        wheel = "@example_lock_wheel_decorator_5.1.1_py3_none_any//file",
    )

    pycross_wheel_library(
        name = "executing_1.2.0",
        wheel = "@example_lock_wheel_executing_1.2.0_py2.py3_none_any//file",
    )

    _ipython_8_8_0_deps = [
        ":backcall_0.2.0",
        ":decorator_5.1.1",
        ":jedi_0.18.2",
        ":matplotlib_inline_0.1.6",
        ":pexpect_4.8.0",
        ":pickleshare_0.7.5",
        ":prompt_toolkit_3.0.36",
        ":pygments_2.14.0",
        ":stack_data_0.6.2",
        ":traitlets_5.8.0",
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
        name = "ipython_8.8.0",
        deps = _ipython_8_8_0_deps,
        wheel = "@example_lock_wheel_ipython_8.8.0_py3_none_any//file",
    )

    _jedi_0_18_2_deps = [
        ":parso_0.8.3",
    ]

    pycross_wheel_library(
        name = "jedi_0.18.2",
        deps = _jedi_0_18_2_deps,
        wheel = "@example_lock_wheel_jedi_0.18.2_py2.py3_none_any//file",
    )

    _matplotlib_inline_0_1_6_deps = [
        ":traitlets_5.8.0",
    ]

    pycross_wheel_library(
        name = "matplotlib_inline_0.1.6",
        deps = _matplotlib_inline_0_1_6_deps,
        wheel = "@example_lock_wheel_matplotlib_inline_0.1.6_py3_none_any//file",
    )

    _numpy_1_23_5_build_deps = [
        ":cython_0.29.33",
        ":setuptools_59.2.0",
        ":wheel_0.37.0",
    ]

    pycross_wheel_library(
        name = "numpy_1.23.5",
        wheel = "@//deps/numpy",
    )

    _pandas_1_5_2_deps = [
        ":numpy_1.23.5",
        ":python_dateutil_2.8.2",
        ":pytz_2022.7",
    ]

    _pandas_1_5_2_build_deps = [
        ":cython_0.29.33",
        ":setuptools_59.2.0",
        ":wheel_0.37.0",
    ]

    pycross_wheel_build(
        name = "_build_pandas_1.5.2",
        sdist = "@example_lock_sdist_pandas_1.5.2//file",
        target_environment = _target,
        deps = _pandas_1_5_2_deps + _pandas_1_5_2_build_deps,
        tags = ["manual"],
    )

    pycross_wheel_library(
        name = "pandas_1.5.2",
        deps = _pandas_1_5_2_deps,
        wheel = ":_build_pandas_1.5.2",
    )

    pycross_wheel_library(
        name = "parso_0.8.3",
        wheel = "@example_lock_wheel_parso_0.8.3_py2.py3_none_any//file",
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
        name = "psycopg2_2.9.5",
        wheel = "@//deps/psycopg2",
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
        name = "pygments_2.14.0",
        wheel = "@example_lock_wheel_pygments_2.14.0_py3_none_any//file",
    )

    _python_dateutil_2_8_2_deps = [
        ":six_1.16.0",
    ]

    pycross_wheel_library(
        name = "python_dateutil_2.8.2",
        deps = _python_dateutil_2_8_2_deps,
        wheel = "@example_lock_wheel_python_dateutil_2.8.2_py2.py3_none_any//file",
    )

    pycross_wheel_library(
        name = "pytz_2022.7",
        wheel = "@example_lock_wheel_pytz_2022.7_py2.py3_none_any//file",
    )

    pycross_wheel_build(
        name = "_build_setproctitle_1.3.2",
        sdist = "@example_lock_sdist_setproctitle_1.3.2//file",
        target_environment = _target,
        tags = ["manual"],
    )

    pycross_wheel_library(
        name = "setproctitle_1.3.2",
        wheel = ":_build_setproctitle_1.3.2",
    )

    pycross_wheel_library(
        name = "setuptools_59.2.0",
        wheel = "@example_lock_wheel_setuptools_59.2.0_py3_none_any//file",
    )

    pycross_wheel_library(
        name = "six_1.16.0",
        wheel = "@example_lock_wheel_six_1.16.0_py2.py3_none_any//file",
    )

    _stack_data_0_6_2_deps = [
        ":asttokens_2.2.1",
        ":executing_1.2.0",
        ":pure_eval_0.2.2",
    ]

    pycross_wheel_library(
        name = "stack_data_0.6.2",
        deps = _stack_data_0_6_2_deps,
        wheel = "@example_lock_wheel_stack_data_0.6.2_py3_none_any//file",
    )

    pycross_wheel_library(
        name = "traitlets_5.8.0",
        wheel = "@example_lock_wheel_traitlets_5.8.0_py3_none_any//file",
    )

    pycross_wheel_library(
        name = "wcwidth_0.2.5",
        wheel = "@example_lock_wheel_wcwidth_0.2.5_py2.py3_none_any//file",
    )

    pycross_wheel_library(
        name = "wheel_0.37.0",
        wheel = "@example_lock_wheel_wheel_0.37.0_py2.py3_none_any//file",
    )

def repositories():
    maybe(
        http_file,
        name = "example_lock_sdist_numpy_1.23.5",
        urls = [
            "https://files.pythonhosted.org/packages/42/38/775b43da55fa7473015eddc9a819571517d9a271a9f8134f68fb9be2f212/numpy-1.23.5.tar.gz"
        ],
        sha256 = "1b1766d6f397c18153d40015ddfc79ddb715cabadc04d2d228d4e5a8bc4ded1a",
        downloaded_file_path = "numpy-1.23.5.tar.gz",
    )

    maybe(
        http_file,
        name = "example_lock_sdist_pandas_1.5.2",
        urls = [
            "https://files.pythonhosted.org/packages/4d/07/c4d69e1acb7723ca49d24fc60a89aa07a914dfb8e7a07fdbb9d8646630cd/pandas-1.5.2.tar.gz"
        ],
        sha256 = "220b98d15cee0b2cd839a6358bd1f273d0356bf964c1a1aeb32d47db0215488b",
        downloaded_file_path = "pandas-1.5.2.tar.gz",
    )

    maybe(
        http_file,
        name = "example_lock_sdist_psycopg2_2.9.5",
        urls = [
            "https://files.pythonhosted.org/packages/89/d6/cd8c46417e0f7a16b4b0fc321f4ab676a59250d08fce5b64921897fb07cc/psycopg2-2.9.5.tar.gz"
        ],
        sha256 = "a5246d2e683a972e2187a8714b5c2cf8156c064629f9a9b1a873c1730d9e245a",
        downloaded_file_path = "psycopg2-2.9.5.tar.gz",
    )

    maybe(
        http_file,
        name = "example_lock_sdist_setproctitle_1.3.2",
        urls = [
            "https://files.pythonhosted.org/packages/b5/47/ac709629ddb9779fee29b7d10ae9580f60a4b37e49bce72360ddf9a79cdc/setproctitle-1.3.2.tar.gz"
        ],
        sha256 = "b9fb97907c830d260fa0658ed58afd48a86b2b88aac521135c352ff7fd3477fd",
        downloaded_file_path = "setproctitle-1.3.2.tar.gz",
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
        name = "example_lock_wheel_asttokens_2.2.1_py2.py3_none_any",
        urls = [
            "https://files.pythonhosted.org/packages/f3/e1/64679d9d0759db5b182222c81ff322c2fe2c31e156a59afd6e9208c960e5/asttokens-2.2.1-py2.py3-none-any.whl"
        ],
        sha256 = "6b0ac9e93fb0335014d382b8fa9b3afa7df546984258005da0b9e7095b3deb1c",
        downloaded_file_path = "asttokens-2.2.1-py2.py3-none-any.whl",
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
        name = "example_lock_wheel_cython_0.29.33_cp310_cp310_manylinux_2_17_aarch64.manylinux2014_aarch64.manylinux_2_24_aarch64",
        urls = [
            "https://files.pythonhosted.org/packages/be/f9/198c7b9d125b29bcedaf923f5f2c29bd4b4534d4a8dd2ee5780244337af4/Cython-0.29.33-cp310-cp310-manylinux_2_17_aarch64.manylinux2014_aarch64.manylinux_2_24_aarch64.whl"
        ],
        sha256 = "190e60b7505d3b9b60130bcc2251c01b9ef52603420829c19d3c3ede4ac2763a",
        downloaded_file_path = "Cython-0.29.33-cp310-cp310-manylinux_2_17_aarch64.manylinux2014_aarch64.manylinux_2_24_aarch64.whl",
    )

    maybe(
        http_file,
        name = "example_lock_wheel_cython_0.29.33_cp310_cp310_manylinux_2_17_x86_64.manylinux2014_x86_64.manylinux_2_24_x86_64",
        urls = [
            "https://files.pythonhosted.org/packages/21/76/ef852189cc39a33cedc08d30189de2d1e44d826ddcf101e24c82c8b8ea0c/Cython-0.29.33-cp310-cp310-manylinux_2_17_x86_64.manylinux2014_x86_64.manylinux_2_24_x86_64.whl"
        ],
        sha256 = "0168482495b75fea1c97a9641a95bac991f313e85f378003f9a4909fdeb3d454",
        downloaded_file_path = "Cython-0.29.33-cp310-cp310-manylinux_2_17_x86_64.manylinux2014_x86_64.manylinux_2_24_x86_64.whl",
    )

    maybe(
        http_file,
        name = "example_lock_wheel_cython_0.29.33_py2.py3_none_any",
        urls = [
            "https://files.pythonhosted.org/packages/56/3a/e59db3769dee48409c759a88b62cd605324e05d396e10af0a065adc956ad/Cython-0.29.33-py2.py3-none-any.whl"
        ],
        sha256 = "8b99252bde8ff51cd06a3fe4aeacd3af9b4ff4a4e6b701ac71bddc54f5da61d6",
        downloaded_file_path = "Cython-0.29.33-py2.py3-none-any.whl",
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
        name = "example_lock_wheel_executing_1.2.0_py2.py3_none_any",
        urls = [
            "https://files.pythonhosted.org/packages/28/3c/bc3819dd8b1a1588c9215a87271b6178cc5498acaa83885211f5d4d9e693/executing-1.2.0-py2.py3-none-any.whl"
        ],
        sha256 = "0314a69e37426e3608aada02473b4161d4caf5a4b244d1d0c48072b8fee7bacc",
        downloaded_file_path = "executing-1.2.0-py2.py3-none-any.whl",
    )

    maybe(
        http_file,
        name = "example_lock_wheel_ipython_8.8.0_py3_none_any",
        urls = [
            "https://files.pythonhosted.org/packages/1f/aa/a6509b4059359edd00308e3f068212dca53b7252940862cc40981a2bd713/ipython-8.8.0-py3-none-any.whl"
        ],
        sha256 = "da01e6df1501e6e7c32b5084212ddadd4ee2471602e2cf3e0190f4de6b0ea481",
        downloaded_file_path = "ipython-8.8.0-py3-none-any.whl",
    )

    maybe(
        http_file,
        name = "example_lock_wheel_jedi_0.18.2_py2.py3_none_any",
        urls = [
            "https://files.pythonhosted.org/packages/6d/60/4acda63286ef6023515eb914543ba36496b8929cb7af49ecce63afde09c6/jedi-0.18.2-py2.py3-none-any.whl"
        ],
        sha256 = "203c1fd9d969ab8f2119ec0a3342e0b49910045abe6af0a3ae83a5764d54639e",
        downloaded_file_path = "jedi-0.18.2-py2.py3-none-any.whl",
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
        name = "example_lock_wheel_parso_0.8.3_py2.py3_none_any",
        urls = [
            "https://files.pythonhosted.org/packages/05/63/8011bd08a4111858f79d2b09aad86638490d62fbf881c44e434a6dfca87b/parso-0.8.3-py2.py3-none-any.whl"
        ],
        sha256 = "c001d4636cd3aecdaf33cbb40aebb59b094be2a74c556778ef5576c175e19e75",
        downloaded_file_path = "parso-0.8.3-py2.py3-none-any.whl",
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
        name = "example_lock_wheel_prompt_toolkit_3.0.36_py3_none_any",
        urls = [
            "https://files.pythonhosted.org/packages/eb/37/791f1a6edd13c61cac85282368aa68cb0f3f164440fdf60032f2cc6ca34e/prompt_toolkit-3.0.36-py3-none-any.whl"
        ],
        sha256 = "aa64ad242a462c5ff0363a7b9cfe696c20d55d9fc60c11fd8e632d064804d305",
        downloaded_file_path = "prompt_toolkit-3.0.36-py3-none-any.whl",
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
        name = "example_lock_wheel_pygments_2.14.0_py3_none_any",
        urls = [
            "https://files.pythonhosted.org/packages/0b/42/d9d95cc461f098f204cd20c85642ae40fbff81f74c300341b8d0e0df14e0/Pygments-2.14.0-py3-none-any.whl"
        ],
        sha256 = "fa7bd7bd2771287c0de303af8bfdfc731f51bd2c6a47ab69d117138893b82717",
        downloaded_file_path = "Pygments-2.14.0-py3-none-any.whl",
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
        name = "example_lock_wheel_pytz_2022.7_py2.py3_none_any",
        urls = [
            "https://files.pythonhosted.org/packages/3d/19/4de17f0d5cf5a0d87aa67532d4c2fa75e6e7d8df13c27635ff40fa6f4b76/pytz-2022.7-py2.py3-none-any.whl"
        ],
        sha256 = "93007def75ae22f7cd991c84e02d434876818661f8df9ad5df9e950ff4e52cfd",
        downloaded_file_path = "pytz-2022.7-py2.py3-none-any.whl",
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
        name = "example_lock_wheel_stack_data_0.6.2_py3_none_any",
        urls = [
            "https://files.pythonhosted.org/packages/6a/81/aa96c25c27f78cdc444fec27d80f4c05194c591465e491a1358d8a035bc1/stack_data-0.6.2-py3-none-any.whl"
        ],
        sha256 = "cbb2a53eb64e5785878201a97ed7c7b94883f48b87bfb0bbe8b623c74679e4a8",
        downloaded_file_path = "stack_data-0.6.2-py3-none-any.whl",
    )

    maybe(
        http_file,
        name = "example_lock_wheel_traitlets_5.8.0_py3_none_any",
        urls = [
            "https://files.pythonhosted.org/packages/44/2d/76503546de9c5eaf70a5864288e9b3eb4d017c7bd7800b5fd6e93d1d4ab0/traitlets-5.8.0-py3-none-any.whl"
        ],
        sha256 = "c864831efa0ba6576d09b44884b34e41defc18c0d7e720b4a2d6698c842cab3e",
        downloaded_file_path = "traitlets-5.8.0-py3-none-any.whl",
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
        name = "example_lock_wheel_wheel_0.37.0_py2.py3_none_any",
        urls = [
            "https://files.pythonhosted.org/packages/04/80/cad93b40262f5d09f6de82adbee452fd43cdff60830b56a74c5930f7e277/wheel-0.37.0-py2.py3-none-any.whl"
        ],
        sha256 = "21014b2bd93c6d0034b6ba5d35e4eb284340e09d63c59aef6fc14b0f346146fd",
        downloaded_file_path = "wheel-0.37.0-py2.py3-none-any.whl",
    )

