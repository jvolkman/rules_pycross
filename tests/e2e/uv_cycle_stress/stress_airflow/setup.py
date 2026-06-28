from setuptools import setup

setup(
    name="stress-airflow",
    version="1.0.0",
    packages=["stress_airflow"],
    install_requires=["stress-airflow-core", "stress-task-sdk"],
)
