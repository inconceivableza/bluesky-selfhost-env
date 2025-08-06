from setuptools import setup, find_packages

setup(
    name="selfhost_scripts",
    version="0.1.0",
    packages=find_packages(),
    python_requires=">=3.6",
    install_requires=[
        "PyYAML",
    ],
    description="Operations helper utilities for bluesky self-hosting",
)