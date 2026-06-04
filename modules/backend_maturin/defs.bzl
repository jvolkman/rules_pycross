"""Public API for rules_pycross_backend_maturin."""

load("//rules:generate_cargo_lock.bzl", _pycross_generate_cargo_lock = "pycross_generate_cargo_lock")

pycross_generate_cargo_lock = _pycross_generate_cargo_lock
