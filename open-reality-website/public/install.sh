#!/bin/sh
# OpenReality CLI installer
# Usage: curl -fsSL https://open-reality.com/install.sh | sh

set -eu

REPO="sinisterMage/Open-Reality"
INSTALL_DIR="${OPENREALITY_INSTALL_DIR:-$HOME/.openreality/bin}"
BINARY_NAME="orcli"

main() {
    detect_platform
    fetch_latest_tag
    download_and_install
    setup_path
    echo
    echo "  ${BINARY_NAME} ${TAG} installed to ${INSTALL_DIR}/${BINARY_NAME}"
    echo
}

detect_platform() {
    OS="$(uname -s)"
    ARCH="$(uname -m)"

    case "${OS}" in
        Linux)
            case "${ARCH}" in
                x86_64)  ARCHIVE="${BINARY_NAME}-x86_64-linux.tar.gz" ;;
                *)       error "Unsupported Linux architecture: ${ARCH}" ;;
            esac
            ;;
        Darwin)
            case "${ARCH}" in
                arm64)   ARCHIVE="${BINARY_NAME}-aarch64-macos.tar.gz" ;;
                x86_64)  ARCHIVE="${BINARY_NAME}-aarch64-macos.tar.gz" ;;
                *)       error "Unsupported macOS architecture: ${ARCH}" ;;
            esac
            ;;
        *)
            error "Unsupported OS: ${OS}. Use install.ps1 for Windows."
            ;;
    esac

    echo "  Detected platform: ${OS} ${ARCH}"
}

fetch_latest_tag() {
    echo "  Fetching latest release..."
    TAG=$(curl -fsSL "https://api.github.com/repos/${REPO}/releases/latest" \
        | grep '"tag_name"' | head -1 | cut -d '"' -f 4)

    if [ -z "${TAG}" ]; then
        error "Could not determine the latest release tag."
    fi

    echo "  Latest release: ${TAG}"
}

download_and_install() {
    URL="https://github.com/${REPO}/releases/download/${TAG}/${ARCHIVE}"
    TMPDIR="$(mktemp -d)"
    trap 'rm -rf "${TMPDIR}"' EXIT

    echo "  Downloading ${ARCHIVE}..."
    curl -fsSL "${URL}" -o "${TMPDIR}/${ARCHIVE}"

    echo "  Extracting..."
    tar xzf "${TMPDIR}/${ARCHIVE}" -C "${TMPDIR}"

    mkdir -p "${INSTALL_DIR}"
    mv "${TMPDIR}/${BINARY_NAME}" "${INSTALL_DIR}/${BINARY_NAME}"
    chmod +x "${INSTALL_DIR}/${BINARY_NAME}"
}

setup_path() {
    case ":${PATH}:" in
        *":${INSTALL_DIR}:"*)
            return
            ;;
    esac

    SHELL_NAME="$(basename "${SHELL:-/bin/sh}")"
    case "${SHELL_NAME}" in
        zsh)   RC_FILE="${HOME}/.zshrc" ;;
        bash)  RC_FILE="${HOME}/.bashrc" ;;
        fish)  RC_FILE="${HOME}/.config/fish/config.fish" ;;
        *)     RC_FILE="${HOME}/.profile" ;;
    esac

    EXPORT_LINE="export PATH=\"${INSTALL_DIR}:\$PATH\""

    if [ "${SHELL_NAME}" = "fish" ]; then
        EXPORT_LINE="set -gx PATH ${INSTALL_DIR} \$PATH"
    fi

    if [ -f "${RC_FILE}" ] && grep -qF "${INSTALL_DIR}" "${RC_FILE}" 2>/dev/null; then
        return
    fi

    echo "" >> "${RC_FILE}"
    echo "# OpenReality CLI" >> "${RC_FILE}"
    echo "${EXPORT_LINE}" >> "${RC_FILE}"

    echo "  Added ${INSTALL_DIR} to PATH in ${RC_FILE}"
    echo "  Run 'source ${RC_FILE}' or restart your shell to use ${BINARY_NAME}."
}

error() {
    echo "Error: $1" >&2
    exit 1
}

main
