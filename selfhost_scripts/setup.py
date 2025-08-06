from setuptools import setup

setup(
    name="selfhost_scripts",
    version="0.1.0",
    py_modules=["env_utils", "secret_types", "gen_secrets"],
    python_requires=">=3.6",
    install_requires=[
        "PyYAML",
    ],
    description="Operations helper utilities for bluesky self-hosting",
)
