"""The lock_repos extension."""

load("@bazel_tools//tools/build_defs/repo:http.bzl", "http_file")
load("@lock_import_repos_hub//:locks.bzl", lock_import_locks = "locks")
load("//pycross/private:package_repo.bzl", "package_repo")
load("//pycross/private:pypi_file.bzl", "pypi_file")
load(":tag_attrs.bzl", "CREATE_REPOS_ATTRS")

# buildifier: disable=print
def _print_warn(msg):
    print("WARNING:", msg)

def _lock_repos_impl(module_ctx):
    all_locks = lock_import_locks  # Some day there may be others.
    all_remote_files = {}

    # Pre-pathify all lock files to minimize restart time.
    for lock_file in all_locks.values():
        module_ctx.path(lock_file)

    create_tag = None
    for module in module_ctx.modules:
        for tag in module.tags.create:
            if module.name != "rules_pycross" and not module.is_root:
                _print_warn("Ignoring repos.create tag from non-root, non-pycross module {}".format(module.name))
                continue

            # Root module has precedence
            if create_tag == None:
                create_tag = tag

    if create_tag == None:
        # This shouldn't happen since rules_pycross registers a default tag.
        fail("BUG: no repos.create tag found!")

    # Generate the lock repos and any remote package repos
    for repo_name, lock_file in all_locks.items():
        resolved_lock_file = module_ctx.path(lock_file)
        resolved_lock = json.decode(module_ctx.read(resolved_lock_file))

        repo_remote_files = {}
        for key, file in resolved_lock.get("remote_files", {}).items():
            if key in all_remote_files:
                # We already have an entry for this key, so use that.
                # TODO: add some preference for http entries vs. pypi_file entries.
                repo_remote_files[key] = all_remote_files[key]
                continue

            # Use the key as our repo name, but replace its / with _
            remote_file_repo = "pypi_{}".format(key.replace("/", "_"))
            remote_file_label = "@{}//file".format(remote_file_repo)

            urls = file.get("urls", [])
            if urls:
                # We have URLs so we'll use an http_file repo.
                http_file(
                    name = remote_file_repo,
                    urls = urls,
                    sha256 = file["sha256"],
                    downloaded_file_path = file["name"],
                )
            else:
                # No URLs; use a pypi_file repo.
                pypi_file_attrs = dict(
                    name = remote_file_repo,
                    package_name = file["package_name"],
                    package_version = file["package_version"],
                    filename = file["name"],
                    sha256 = file["sha256"],
                )
                if create_tag.pypi_index:
                    pypi_file_attrs["pypi_index"] = create_tag.pypi_index

                pypi_file(**pypi_file_attrs)

            repo_remote_files[key] = remote_file_label
            all_remote_files[key] = remote_file_label

        package_repo(
            name = repo_name,
            resolved_lock_file = lock_file,
            repo_map = repo_remote_files,
        )

# Tag classes
_create_tag = tag_class(
    doc = "Create declared Pycross repos.",
    attrs = CREATE_REPOS_ATTRS,
)

lock_repos = module_extension(
    implementation = _lock_repos_impl,
    tag_classes = dict(
        create = _create_tag,
    ),
)
