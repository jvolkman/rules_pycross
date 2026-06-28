from setuptools import setup

setup(
    name="stress-provider-io",
    version="1.0.0",
    packages=["stress_provider_io"],
    install_requires=["stress-airflow;", "python_version", ">=", "'3.11'"],
)
