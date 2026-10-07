"""Helpers for deferring failures from analysis to execution.

Targets that cannot produce their outputs for the selected target environment
(an sdist build with missing build requirements, or - when
`//pycross/settings:unavailable_package_mode=fail_at_execution` is set - a
package with no compatible wheel or no matching fork/variant branch) analyze
successfully and instead register an action that fails when executed. This lets
aspects and other analysis-only consumers traverse the dependency graph without
tripping over packages they never actually build.
"""

def register_failure_action(ctx, outputs, message, mnemonic, progress_message):
    """Registers an action that prints `message` to stderr and fails.

    Args:
        ctx: The rule context.
        outputs: List of declared Files (or directories) the action "produces".
        message: The error message to print.
        mnemonic: The action mnemonic.
        progress_message: The action progress message.
    """
    ctx.actions.run_shell(
        outputs = outputs,
        # Pass the message through the environment to avoid shell quoting issues.
        command = 'printf "%s\\n" "$PYCROSS_ERROR" >&2; exit 1',
        env = {"PYCROSS_ERROR": message},
        mnemonic = mnemonic,
        progress_message = progress_message,
    )

def unsupported_wheel_message(package):
    """Returns the standard error message for a package without a compatible wheel.

    Args:
        package: A human-readable package identifier (e.g. "numpy@1.26.0"), or None.

    Returns:
        str
    """
    if package:
        return "No compatible wheel is available for {} in the selected target environment.".format(package)
    return "No compatible wheel is available for the selected target environment."
