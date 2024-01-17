"""Implementation of the pycross_lock_repo macro."""

load(":lock_attrs.bzl", "CREATE_REPOS_ATTRS", "RESOLVE_ATTRS")
load(":package_repo.bzl", "package_repo")
load(":resolved_lock_repo.bzl", "resolved_lock_repo")

def pycross_lock_repo(*, name, lock_model, **kwargs):
    """Create a repo containing packages described by an imported lock.

    Args:
      name: the repo name.
      lock_model: the serialized lock model struct. Use `lock_repo_model_pdm` or `lock_repo_model_poetry`.
      **kwargs: additional args to pass to `resolved_lock_repo` and `package_repo`.
    """

    render_args = {}
    resolve_args = {"lock_model": lock_model}
    for arg in list(kwargs):
        if arg in CREATE_REPOS_ATTRS:
            render_args[arg] = kwargs.pop(arg)
        elif arg in RESOLVE_ATTRS:
            resolve_args[arg] = kwargs.pop(arg)

    if kwargs:
        fail("Unexpected args: {}".format(kwargs))

    resolved_repo_name = name + "_resolved"
    resolved_lock_label = "@{}//:lock.json".format(resolved_repo_name)

    resolved_lock_repo(name = resolved_repo_name, **resolve_args)
    package_repo(name = name, resolved_lock_file = resolved_lock_label, write_install_deps = True)
