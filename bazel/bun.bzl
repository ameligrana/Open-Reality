"""Custom Bazel rules for Bun-based JavaScript/TypeScript projects.

Wraps `bun` commands (test, build, etc.) for projects that use Bun as the
package manager and runtime. Similar in spirit to julia.bzl — these rules
run against the real workspace source tree because Bun's module resolution
requires node_modules and lockfile in-place.
"""

def _bun_test_impl(ctx):
    package_json = ctx.file.package_json
    srcs = ctx.files.srcs
    data = ctx.files.data

    runner = ctx.actions.declare_file(ctx.label.name + "_runner.sh")
    ctx.actions.write(
        output = runner,
        content = """#!/bin/bash
set -e

# Resolve the real project directory (same pattern as julia.bzl).
if [[ -n "${{BUILD_WORKSPACE_DIRECTORY}}" ]]; then
    PROJECT_DIR="${{BUILD_WORKSPACE_DIRECTORY}}/{pkg_dir}"
elif [[ -n "${{TEST_SRCDIR}}" ]]; then
    REAL_PKG="$(readlink -f "${{TEST_SRCDIR}}/_main/{pkg_json}")"
    PROJECT_DIR="$(dirname "${{REAL_PKG}}")"
else
    SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
    PROJECT_DIR="${{SCRIPT_DIR}}/{pkg_dir}"
fi

cd "${{PROJECT_DIR}}"

# Install deps if node_modules is missing
if [ ! -d node_modules ]; then
    {bun} install --frozen-lockfile
fi

{bun} {command}
""".format(
            pkg_dir = package_json.dirname if package_json.dirname else ".",
            pkg_json = package_json.short_path,
            bun = ctx.attr.bun_bin,
            command = ctx.attr.command,
        ),
        is_executable = True,
    )

    runfiles = ctx.runfiles(files = [package_json] + srcs + data)
    return [DefaultInfo(executable = runner, runfiles = runfiles)]

bun_test = rule(
    implementation = _bun_test_impl,
    test = True,
    attrs = {
        "package_json": attr.label(allow_single_file = True, mandatory = True),
        "srcs": attr.label_list(allow_files = True),
        "data": attr.label_list(allow_files = True),
        "command": attr.string(default = "test"),
        "bun_bin": attr.string(default = "bun"),
    },
)
