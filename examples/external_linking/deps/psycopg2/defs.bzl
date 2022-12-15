"""
Postgresql helpers.
"""

load(":repositories.bzl", "PLATFORM_CONSTRAINTS", "VERSIONS", "pg_repo")

PostgresqlInfo = provider(
    "Postgresql information.",
    fields = ["version"],
)

def _postgresql_version_impl(ctx):
    configured_version = ctx.build_setting_value
    if configured_version not in VERSIONS:
        fail(str(ctx.label) + " build setting allowed to take values {" +
             ", ".join(VERSIONS) + "} but was set to unallowed value " +
             configured_version)

    return [
        PostgresqlInfo(version = configured_version),
    ]

postgresql_version = rule(
    implementation = _postgresql_version_impl,
    build_setting = config.string(flag = True),
)

def postgresql_config(name, default_version = "14"):
    """
    A macro that creates postgresql-related targets and configuration. Creates the following targets:
    {name}_version
        A config variable that specifies the numeric version of postgresql to use. Can be specified
        at runtime: bazel test //tst/... --//tst:postgresql_version=12
    {name}
        A filegroup containing all of the files of the selected postgresql release
    {name}_binpath
        A text file containing the binary path for the selected postgresql release, relative to the workspace runtime
        area root)
    Args:
        name: the generated target name prefix.
        default_version: the default postgres version.
    """
    postgresql_version(
        name = name + "_version",
        build_setting_default = default_version,
    )

    files_selects = {}
    pg_ctl_selects = {}
    for ver in VERSIONS:
        for platform, constraints in PLATFORM_CONSTRAINTS.items():
            opt_name = "_%s_opt_postgresql_%s_%s" % (name, ver, platform)
            native.config_setting(
                name = opt_name,
                flag_values = {
                    ":%s_version" % name: ver,
                },
                constraint_values = constraints,
            )
            files_selects[opt_name] = ["@%s//:files" % pg_repo(ver, platform)]
            pg_ctl_selects[opt_name] = "@%s//:bin/pg_ctl" % pg_repo(ver, platform)

    pg_files_name = name
    pg_ctl_name = "_" + name + "_pg_ctl"

    # A private alias to the bin/pg_ctl tool for the selected version
    native.alias(
        name = pg_ctl_name,
        actual = select(pg_ctl_selects),
    )

    native.filegroup(
        name = pg_files_name,
        srcs = select(files_selects),
    )

    native.genrule(
        name = name + "_binpath",
        srcs = [
            ":" + pg_files_name,
            ":" + pg_ctl_name,
        ],
        outs = [name + "_binpath.txt"],
        cmd = "dirname $(location :" + pg_ctl_name + ") > $@",
    )