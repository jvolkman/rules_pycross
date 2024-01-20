"""The lock_file_repo extension creates repositories for an original-style Pycross .bzl lock."""

load("@bazel_tools//tools/build_defs/repo:http.bzl", "http_file")
load("//pycross/private:internal_repo.bzl", "exec_internal_tool")
load("//pycross/private:lock_file_repo.bzl", "pycross_lock_file_repo")
load("//pycross/private:pypi_file.bzl", "pypi_file")

def _lock_file_impl(module_ctx):
    # Pre-pathify labels
    tool = module_ctx.path(Label("@rules_pycross//pycross/private/tools:extract_lock_repos.py"))
    for module in module_ctx.modules:
        for tag in module.tags.instantiate:
            module_ctx.path(tag.lock_file)

    # Create all repos for inputs
    for module in module_ctx.modules:
        for tag in module.tags.instantiate:
            path = module_ctx.path(tag.lock_file)
            result = exec_internal_tool(module_ctx, tool, [path], quiet = True)
            repos = json.decode(result.stdout)

            # Create the file repos
            for repo in repos:
                if repo["type"] == "http_file":
                    http_file(**repo["attrs"])
                elif repo["type"] == "pypi_file":
                    pypi_file(**repo["attrs"])
                else:
                    fail("Unknown repository type: " + repo["type"])

            # Create the packages repo
            pycross_lock_file_repo(name = tag.name, lock_file = tag.lock_file)

# Tag classes
_instantiate_tag = tag_class(
    doc = "Create a repo given the Pycross-generated lock file.",
    attrs = dict(
        name = attr.string(
            doc = "The repo name.",
            mandatory = True,
        ),
        lock_file = attr.label(
            doc = "The lock file created by pycross_lock_file.",
            mandatory = True,
        ),
    ),
)

lock_file = module_extension(
    implementation = _lock_file_impl,
    tag_classes = dict(
        instantiate = _instantiate_tag,
    ),
)
