"""The lock_repos extension."""

load("@bazel_features//:features.bzl", "bazel_features")
load("@bazel_tools//tools/build_defs/repo:http.bzl", "http_file")
load("@lock_import_repos_hub//:locks.bzl", lock_import_locks = "locks")
load("//pycross/private:package_repo.bzl", "package_repo")
load("//pycross/private:pypi_file.bzl", "pypi_file")
load("//pycross/private:util.bzl", "sanitize_name")
load("//pycross/private/bzlmod:sdist_repo.bzl", "pycross_sdist_repo")
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

            # Use the key as our repo name, but replace its / with _ and sanitize for Bazel
            remote_file_repo = "pypi_{}".format(sanitize_name(key.replace("/", "_")))
            remote_file_label = "@{}//file:{}".format(remote_file_repo, file["name"])

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
                    pypi_file_attrs["index"] = create_tag.pypi_index

                pypi_file(**pypi_file_attrs)

            repo_remote_files[key] = remote_file_label
            all_remote_files[key] = remote_file_label

        # Pre-calculate known packages in this lock file to filter sdist build_requires
        known_packages = [sanitize_name(key.split("@")[0]) for key in resolved_lock.get("packages", {})]

        # Instantiate sdist repos for packages requiring source builds
        for pkg_key, pkg in resolved_lock.get("packages", {}).items():
            if pkg.get("build_target"):
                # User provided a custom build target; skip auto-generating an sdist repo.
                continue

            sdist_file = pkg.get("sdist_file")
            if not sdist_file:
                continue

            sdist_file_key = sdist_file["key"]
            sdist_label = repo_remote_files[sdist_file_key]

            # For each environment where the package resolves to an sdist,
            # we must create a separate sdist repository to build it.
            for env_name, env_file_ref in pkg.get("environment_files", {}).items():
                # If the package resolves to an sdist in this environment (indicated by the sdist file key
                # being the resolved target or if it matches the sdist file key)
                if env_file_ref.get("key") != sdist_file_key:
                    # This environment uses a pre-built wheel, not the sdist.
                    continue

                # Collect dependencies for this environment
                deps = []
                for dep in pkg.get("common_dependencies", []):
                    dep_name = dep.split("@")[0]
                    deps.append("@{}//:{}".format(repo_name, sanitize_name(dep_name)))
                for dep in pkg.get("environment_dependencies", {}).get(env_name, []):
                    dep_name = dep.split("@")[0]
                    deps.append("@{}//:{}".format(repo_name, sanitize_name(dep_name)))

                sdist_repo_name = "{}_sdist_{}_{}".format(
                    repo_name,
                    sanitize_name(pkg_key),
                    sanitize_name(env_name),
                )

                sdist_repo_attrs = {
                    "name": sdist_repo_name,
                    "sdist": sdist_label,
                    "deps": deps,
                    "known_packages": known_packages,
                    "lock_repo": repo_name,
                }
                for attr_name in ("build_profile", "copts", "linkopts", "native_deps", "sdist_python_paths", "config_settings", "tool_deps", "build_dependencies"):
                    if attr_name in pkg and pkg[attr_name] != None:
                        sdist_repo_attrs[attr_name] = pkg[attr_name]
                pycross_sdist_repo(**sdist_repo_attrs)

        package_repo(
            name = repo_name,
            resolved_lock_file = lock_file,
            repo_map = repo_remote_files,
        )

    if bazel_features.external_deps.extension_metadata_has_reproducible:
        return module_ctx.extension_metadata(reproducible = True)
    return module_ctx.extension_metadata()

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
