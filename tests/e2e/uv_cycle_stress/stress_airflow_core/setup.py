from setuptools import setup

setup(
    name="stress-airflow-core",
    version="1.0.0",
    packages=["stress_airflow_core"],
    install_requires=[
        "stress-provider-compat",
        "stress-provider-io",
        "stress-provider-sql",
        "stress-provider-smtp",
        "stress-provider-standard",
        "stress-task-sdk",
        "stress-packaging",
        "stress-jinja2",
    ],
)
