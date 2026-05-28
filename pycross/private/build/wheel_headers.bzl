"""Rule for extracting C/C++ headers from a pycross_wheel_library target."""

load("@rules_cc//cc/common:cc_common.bzl", "cc_common")
load("@rules_cc//cc/common:cc_info.bzl", "CcInfo")
load(
    "//pycross/private:cc_toolchain_util.bzl",
    "absolutize_path_in_str",
)

def _pycross_wheel_headers_impl(ctx):
    wheel_dir = ctx.attr.wheel[DefaultInfo].files.to_list()[0]
    include_dir_path = wheel_dir.path + "/site-packages/" + ctx.attr.include_dir

    compilation_context = cc_common.create_compilation_context(
        headers = depset([wheel_dir]),
        includes = depset([include_dir_path]),
    )

    providers = [
        DefaultInfo(files = depset([wheel_dir])),
        CcInfo(compilation_context = compilation_context),
    ]

    if ctx.attr.make_variable:
        # Double-escape $$ so the value survives ctx.expand_make_variables()
        # in cc_mixin.bzl (which collapses $$ → $). After expansion the value
        # will contain $$EXT_BUILD_ROOT$$ for replace_placeholder().
        value = absolutize_path_in_str(
            ctx.workspace_name,
            "$$$$EXT_BUILD_ROOT$$$$/",
            include_dir_path,
        )
        providers.append(platform_common.TemplateVariableInfo({ctx.attr.make_variable: value}))

    return providers

pycross_wheel_headers = rule(
    implementation = _pycross_wheel_headers_impl,
    doc = """Extracts C/C++ headers from an installed wheel library.

Given a pycross_wheel_library target, this rule exposes the headers found at
a specified include directory within the wheel's site-packages tree as CcInfo,
so that downstream C/C++ compilation can find them. Optionally exports a Make
variable pointing to the absolute include path for use in build system
configuration (e.g., Meson cross files).
""",
    attrs = {
        "wheel": attr.label(
            doc = "A pycross_wheel_library target containing the headers.",
            mandatory = True,
        ),
        "include_dir": attr.string(
            doc = "Relative path within the wheel's site-packages to the include directory (e.g. 'numpy/_core/include').",
            mandatory = True,
        ),
        "make_variable": attr.string(
            doc = "If set, export a TemplateVariableInfo with this name mapped to the absolutized include path.",
        ),
    },
)
