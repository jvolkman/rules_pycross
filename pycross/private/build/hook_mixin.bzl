"""Rule for wrapping an executable as a pre-build hook mixin."""

load("//pycross/private:providers.bzl", "PycrossBuildMixinInfo")

def _hook_mixin_impl(ctx):
    hook_exe = ctx.executable.hook

    # Build the hook configuration
    hook_config = {
        "type": "pre_build_hook",
        "executable": hook_exe.path,
    }

    if ctx.attr.env:
        expanded_env = {}
        for key, value in ctx.attr.env.items():
            expanded_env[key] = ctx.expand_location(value, ctx.attr.data)
        hook_config["env"] = expanded_env

    config_json = ctx.actions.declare_file(ctx.label.name + "_config.json")
    ctx.actions.write(config_json, json.encode(hook_config))

    # Collect all files: the hook executable + data deps
    transitive_files = [ctx.attr.hook[DefaultInfo].files]
    for data_dep in ctx.attr.data:
        transitive_files.append(data_dep[DefaultInfo].files)

    return [
        PycrossBuildMixinInfo(
            config_json = config_json,
            files = depset([config_json], transitive = transitive_files),
        ),
    ]

pycross_hook_mixin = rule(
    implementation = _hook_mixin_impl,
    attrs = {
        "hook": attr.label(
            doc = "The executable to run as a pre-build hook.",
            mandatory = True,
            executable = True,
            cfg = "exec",
        ),
        "env": attr.string_dict(
            doc = (
                "Environment variables passed to the hook. " +
                "Values are subject to location expansion against data deps."
            ),
        ),
        "data": attr.label_list(
            doc = "Additional data dependencies available to the hook.",
            allow_files = True,
        ),
    },
)
