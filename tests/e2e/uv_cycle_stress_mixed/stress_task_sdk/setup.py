from setuptools import setup

setup(
    name="stress-task-sdk",
    version="1.0.0",
    packages=["stress_task_sdk"],
    install_requires=["stress-airflow-core", "stress-attrs"],
)
