"""Custom Bazel rules for Julia projects.

Julia is a JIT-compiled language -- there is no traditional compilation step
that produces a binary artifact. These rules wrap the Julia interpreter for:
  - Precompilation (Pkg.instantiate + Pkg.precompile)
  - Testing (julia --project=. test/runtests.jl)
  - Running scripts (julia --project=. examples/foo.jl)
"""

def _julia_precompile_impl(ctx):
    project_toml = ctx.file.project_toml
    manifest_toml = ctx.file.manifest_toml
    srcs = ctx.files.srcs
    marker = ctx.actions.declare_file(ctx.label.name + ".precompiled")

    ctx.actions.run_shell(
        inputs = [project_toml, manifest_toml] + srcs,
        outputs = [marker],
        command = """
            export JULIA_PROJECT="{project_dir}"
            {julia} -e '
                using Pkg
                Pkg.instantiate()
                Pkg.precompile()
            '
            touch {marker}
        """.format(
            project_dir = project_toml.dirname,
            julia = ctx.attr.julia_bin,
            marker = marker.path,
        ),
        use_default_shell_env = True,
    )
    return [DefaultInfo(files = depset([marker]))]

julia_precompile = rule(
    implementation = _julia_precompile_impl,
    attrs = {
        "project_toml": attr.label(allow_single_file = True, mandatory = True),
        "manifest_toml": attr.label(allow_single_file = True, mandatory = True),
        "srcs": attr.label_list(allow_files = [".jl"]),
        "julia_bin": attr.string(default = "julia"),
    },
)

def _julia_test_impl(ctx):
    test_file = ctx.file.src
    project_toml = ctx.file.project_toml
    srcs = ctx.files.srcs
    data = ctx.files.data

    runner = ctx.actions.declare_file(ctx.label.name + "_runner.sh")
    ctx.actions.write(
        output = runner,
        content = """#!/bin/bash
set -e

# Resolve the real workspace directory.
# Julia's package depot is tied to the original source tree path,
# so we must point Julia at the real workspace, not Bazel's runfiles copy.
if [[ -n "${{BUILD_WORKSPACE_DIRECTORY}}" ]]; then
    PROJECT_DIR="${{BUILD_WORKSPACE_DIRECTORY}}"
elif [[ -n "${{TEST_SRCDIR}}" ]]; then
    # Resolve the Project.toml symlink to find the real workspace root
    REAL_TOML="$(readlink -f "${{TEST_SRCDIR}}/_main/{project_toml}")"
    PROJECT_DIR="$(dirname "${{REAL_TOML}}")"
else
    SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
    PROJECT_DIR="${{SCRIPT_DIR}}/{project_dir}"
fi

# Forward DISPLAY/WAYLAND_DISPLAY for tests that load GPU/windowing libraries
export DISPLAY="${{DISPLAY:-:0}}"
if [[ -n "${{WAYLAND_DISPLAY}}" ]]; then
    export WAYLAND_DISPLAY
fi

export JULIA_PROJECT="${{PROJECT_DIR}}"
{julia} --project="${{PROJECT_DIR}}" "${{PROJECT_DIR}}/{test_file}"
""".format(
            project_dir = project_toml.dirname if project_toml.dirname else ".",
            project_toml = project_toml.short_path,
            julia = ctx.attr.julia_bin,
            test_file = test_file.short_path,
        ),
        is_executable = True,
    )

    runfiles = ctx.runfiles(files = [project_toml, test_file] + srcs + data)
    return [DefaultInfo(executable = runner, runfiles = runfiles)]

julia_test = rule(
    implementation = _julia_test_impl,
    test = True,
    attrs = {
        "src": attr.label(allow_single_file = [".jl"], mandatory = True),
        "project_toml": attr.label(allow_single_file = True, mandatory = True),
        "srcs": attr.label_list(allow_files = [".jl"]),
        "data": attr.label_list(allow_files = True),
        "julia_bin": attr.string(default = "julia"),
    },
)

def _julia_run_impl(ctx):
    script = ctx.file.src
    project_toml = ctx.file.project_toml
    srcs = ctx.files.srcs
    data = ctx.files.data

    runner = ctx.actions.declare_file(ctx.label.name + "_runner.sh")
    ctx.actions.write(
        output = runner,
        content = """#!/bin/bash
set -e
export JULIA_PROJECT="{project_dir}"
{julia} --project="{project_dir}" "{script}"
""".format(
            project_dir = project_toml.dirname,
            julia = ctx.attr.julia_bin,
            script = script.short_path,
        ),
        is_executable = True,
    )

    runfiles = ctx.runfiles(files = [project_toml, script] + srcs + data)
    return [DefaultInfo(executable = runner, runfiles = runfiles)]

julia_run = rule(
    implementation = _julia_run_impl,
    executable = True,
    attrs = {
        "src": attr.label(allow_single_file = [".jl"], mandatory = True),
        "project_toml": attr.label(allow_single_file = True, mandatory = True),
        "srcs": attr.label_list(allow_files = [".jl"]),
        "data": attr.label_list(allow_files = True),
        "julia_bin": attr.string(default = "julia"),
    },
)
