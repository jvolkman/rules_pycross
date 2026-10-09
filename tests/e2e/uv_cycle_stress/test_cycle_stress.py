import importlib

EXPECTED_MODULES = (
    "stress_airflow",
    "stress_airflow_core",
    "stress_attrs",
    "stress_jinja2",
    "stress_packaging",
    "stress_provider_compat",
    "stress_provider_io",
    "stress_provider_smtp",
    "stress_provider_sql",
    "stress_provider_standard",
    "stress_task_sdk",
)

for mod in EXPECTED_MODULES:
    importlib.import_module(mod)
