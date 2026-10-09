import importlib
import importlib.util
import sys

import stress_provider_sql

assert stress_provider_sql is not None

# stress_provider_sql's sole outgoing edge is `stress-airflow; sys_platform == 'linux'`.
OTHER_MODULES = (
    "stress_airflow",
    "stress_airflow_core",
    "stress_attrs",
    "stress_jinja2",
    "stress_packaging",
    "stress_provider_compat",
    "stress_provider_io",
    "stress_provider_smtp",
    "stress_provider_standard",
    "stress_task_sdk",
)

if sys.platform == "linux":
    for mod in OTHER_MODULES:
        importlib.import_module(mod)
else:
    for mod in OTHER_MODULES:
        assert importlib.util.find_spec(mod) is None, f"Unexpectedly found {mod} on {sys.platform}"
