from setuptools import setup

setup(
    name="stress-provider-smtp",
    version="1.0.0",
    packages=["stress_provider_smtp"],
    install_requires=["stress-airflow", "stress-provider-compat"],
)
