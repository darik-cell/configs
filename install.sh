#!/usr/bin/env bash
set -Eeuo pipefail

NVIM_VERSION="0.12.4"
KITTY_VERSION="0.48.2"
TREE_SITTER_VERSION="0.26.6"
FONT_VERSION="3.4.0"

usage() {
  printf 'Usage: %s [--check|--yes]\n' "$0"
}

assume_yes=false
check_only=false
case "${1-}" in
  "") ;;
  --check) check_only=true ;;
  --yes) assume_yes=true ;;
  -h|--help) usage; exit 0 ;;
  *) usage >&2; exit 2 ;;
esac

if [[ ${EUID} -eq 0 ]]; then
  printf '%s\n' 'ERROR: run this script as the desktop user, not through sudo.' >&2
  exit 1
fi
if [[ -z ${HOME:-} || ${HOME} == / ]]; then
  printf '%s\n' 'ERROR: unsafe or empty HOME.' >&2
  exit 1
fi

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
target_home="$(realpath -m -- "${HOME}")"
config_home="$(realpath -m -- "${XDG_CONFIG_HOME:-${HOME}/.config}")"
data_home="$(realpath -m -- "${XDG_DATA_HOME:-${HOME}/.local/share}")"
state_home="$(realpath -m -- "${XDG_STATE_HOME:-${HOME}/.local/state}")"
cache_home="$(realpath -m -- "${XDG_CACHE_HOME:-${HOME}/.cache}")"
local_root="$(realpath -m -- "${HOME}/.local")"
local_bin="${local_root}/bin"
local_opt="${local_root}/opt"

for managed_root in "${config_home}" "${data_home}" "${state_home}" "${cache_home}" "${local_root}"; do
  case "${managed_root}/" in
    "${target_home}/"*) ;;
    *)
      printf 'ERROR: XDG path is outside HOME, refusing destructive install: %s\n' "${managed_root}" >&2
      exit 1
      ;;
  esac
done

if [[ ! -d ${repo_root}/.git || ! -f ${repo_root}/.config/nvim/init.lua || ! -f ${repo_root}/.config/kitty/kitty.conf ]]; then
  printf 'ERROR: run from a complete Git checkout of this repository: %s\n' "${repo_root}" >&2
  exit 1
fi
if [[ -n $(git -C "${repo_root}" status --porcelain=v1 --untracked-files=all) ]]; then
  printf '%s\n' 'ERROR: repository has local changes; commit or resolve them before install.' >&2
  exit 1
fi

if [[ ! -r /etc/os-release ]]; then
  printf '%s\n' 'ERROR: cannot identify the operating system.' >&2
  exit 1
fi
# shellcheck disable=SC1091
source /etc/os-release
if [[ ${ID:-} != ubuntu || ${VERSION_ID:-} != 24.04 ]]; then
  printf 'ERROR: supported host is Ubuntu 24.04; found %s %s.\n' "${ID:-unknown}" "${VERSION_ID:-unknown}" >&2
  exit 1
fi

case "$(uname -m)" in
  x86_64)
    nvim_asset="nvim-linux-x86_64.tar.gz"
    nvim_sha="012bf3fcac5ade43914df3f174668bf64d05e049a4f032a388c027b1ebd78628"
    kitty_asset="kitty-${KITTY_VERSION}-x86_64.txz"
    kitty_sha="967a1958e7fc67b495d279c0963bcd1a0482097151817ce6506fabc822689af7"
    tree_asset="tree-sitter-linux-x64.gz"
    tree_sha="2b9595064a7d9dbe208c6f09f521d73061f8039e4ffcc2fd08979d249aeabb54"
    ;;
  aarch64|arm64)
    nvim_asset="nvim-linux-arm64.tar.gz"
    nvim_sha="ceb7e88c6b681f0515d135dcdfad54f5eb4373b25ce6172197cd9a69c758063f"
    kitty_asset="kitty-${KITTY_VERSION}-arm64.txz"
    kitty_sha="534b214d407a05e4603da75ef02fffa592ec1bbec20a413c5e0cd3f853c928cb"
    tree_asset="tree-sitter-linux-arm64.gz"
    tree_sha="7beef62e5d2683085b87188be83b1a73c59229110a125c5f12d922ae57789a7a"
    ;;
  *)
    printf 'ERROR: unsupported architecture: %s\n' "$(uname -m)" >&2
    exit 1
    ;;
esac

missing_packages=()
need_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    missing_packages+=("$2")
  fi
}
need_command curl curl
need_command git git
need_command tar tar
need_command gzip gzip
need_command xz xz-utils
need_command unzip unzip
need_command cc build-essential
need_command make build-essential
need_command rg ripgrep
need_command fzf fzf
need_command python3 python3
need_command node nodejs
need_command npm npm
need_command fc-cache fontconfig
need_command fc-match fontconfig
need_command xdg-open xdg-utils
need_command desktop-file-validate desktop-file-utils
need_command update-desktop-database desktop-file-utils
need_command wl-copy wl-clipboard
need_command wl-paste wl-clipboard
need_command xclip xclip
if [[ ! -r /etc/ssl/certs/ca-certificates.crt ]]; then
  missing_packages+=(ca-certificates)
fi
if command -v python3 >/dev/null 2>&1 && ! python3 -c 'import ensurepip, venv' >/dev/null 2>&1; then
  missing_packages+=(python3-venv)
fi
if command -v node >/dev/null 2>&1; then
  node_major="$(node --version | sed -E 's/^v([0-9]+).*/\1/')"
  if [[ ! ${node_major} =~ ^[0-9]+$ || ${node_major} -lt 18 ]]; then
    missing_packages+=(nodejs)
  fi
fi

if ((${#missing_packages[@]})); then
  mapfile -t missing_packages < <(printf '%s\n' "${missing_packages[@]}" | LC_ALL=C sort -u)
  printf '%s\n' 'Missing Ubuntu packages. Nothing was removed.'
  printf 'Run this command, then start install.sh again:\n  sudo apt-get update && sudo apt-get install -y --no-install-recommends'
  printf ' %q' "${missing_packages[@]}"
  printf '\n'
  exit 20
fi

delete_targets=(
  "${config_home}/nvim"
  "${config_home}/kitty"
  "${data_home}/nvim"
  "${state_home}/nvim"
  "${cache_home}/nvim"
  "${state_home}/kitty"
  "${cache_home}/kitty"
  "${data_home}/configs-mdview-venv"
  "${data_home}/fonts/FiraCodeNerdFont"
  "${local_root}/kitty.app"
  "${local_opt}/nvim-${NVIM_VERSION}"
  "${local_opt}/tree-sitter-${TREE_SITTER_VERSION}"
  "${local_bin}/nvim"
  "${local_bin}/kitty"
  "${local_bin}/kitten"
  "${local_bin}/tree-sitter"
  "${local_bin}/mdview"
  "${data_home}/applications/kitty.desktop"
)

for target in "${delete_targets[@]}"; do
  target_parent="$(realpath -m -- "$(dirname -- "${target}")")"
  case "${target_parent}/" in
    "${target_home}/"*) ;;
    *)
      printf 'ERROR: managed parent resolves outside HOME: %s -> %s\n' \
        "$(dirname -- "${target}")" "${target_parent}" >&2
      exit 1
      ;;
  esac
  case "${repo_root}/" in
    "${target}/"*)
      printf 'ERROR: repository is inside a path scheduled for deletion: %s\n' "${target}" >&2
      exit 1
      ;;
  esac
  case "${target}/" in
    "${repo_root}/"*)
      printf 'ERROR: a path scheduled for deletion is inside the repository: %s\n' "${target}" >&2
      exit 1
      ;;
  esac
done

printf '%s\n' 'This is a clean reinstall. These exact paths will be removed:'
printf '  %s\n' "${delete_targets[@]}"
if [[ ${check_only} == true ]]; then
  printf '%s\n' 'CHECK_OK: host and dependencies are ready. Nothing was removed.'
  exit 0
fi
if [[ ${assume_yes} != true ]]; then
  printf '%s' 'Type DELETE to continue: '
  read -r answer
  if [[ ${answer} != DELETE ]]; then
    printf '%s\n' 'Cancelled. Nothing was removed.'
    exit 0
  fi
fi

temporary_dir="$(mktemp -d "${TMPDIR:-/tmp}/configs-bootstrap.XXXXXXXX")"
cleanup() {
  if [[ -n ${temporary_dir:-} && -d ${temporary_dir} ]]; then
    rm -rf -- "${temporary_dir}"
  fi
}
trap cleanup EXIT

download() {
  local url=$1
  local sha=$2
  local output=$3
  printf 'Downloading %s\n' "${url}"
  curl --fail --location --proto '=https' --tlsv1.2 --retry 3 --output "${output}" "${url}"
  printf '%s  %s\n' "${sha}" "${output}" | sha256sum --check --status
}

nvim_archive="${temporary_dir}/${nvim_asset}"
kitty_archive="${temporary_dir}/${kitty_asset}"
tree_archive="${temporary_dir}/${tree_asset}"
font_archive="${temporary_dir}/FiraCode-${FONT_VERSION}.tar.xz"
download "https://github.com/neovim/neovim/releases/download/v${NVIM_VERSION}/${nvim_asset}" "${nvim_sha}" "${nvim_archive}"
download "https://github.com/kovidgoyal/kitty/releases/download/v${KITTY_VERSION}/${kitty_asset}" "${kitty_sha}" "${kitty_archive}"
download "https://github.com/tree-sitter/tree-sitter/releases/download/v${TREE_SITTER_VERSION}/${tree_asset}" "${tree_sha}" "${tree_archive}"
download "https://github.com/ryanoasis/nerd-fonts/releases/download/v${FONT_VERSION}/FiraCode.tar.xz" \
  "d83fb093e0e05a531cd6f19886a6ceb884a4fa5ea3b53cf099fc1f30c5b3e47d" "${font_archive}"

nvim_stage="${temporary_dir}/nvim"
kitty_stage="${temporary_dir}/kitty"
tree_stage="${temporary_dir}/tree-sitter"
font_stage="${temporary_dir}/font"
mkdir -p "${nvim_stage}" "${kitty_stage}" "${tree_stage}/bin" "${font_stage}"
tar -xzf "${nvim_archive}" --strip-components=1 -C "${nvim_stage}"
tar -xJf "${kitty_archive}" -C "${kitty_stage}"
gzip -dc "${tree_archive}" > "${tree_stage}/bin/tree-sitter"
chmod 755 "${tree_stage}/bin/tree-sitter"
tar -xJf "${font_archive}" -C "${font_stage}"
"${nvim_stage}/bin/nvim" --version | head -n 1
"${kitty_stage}/bin/kitty" --version
"${tree_stage}/bin/tree-sitter" --version

for target in "${delete_targets[@]}"; do
  rm -rf -- "${target}"
done

mkdir -p "${config_home}" "${data_home}" "${state_home}" "${cache_home}" \
  "${local_bin}" "${local_opt}" "${data_home}/fonts" "${data_home}/applications"
cp -a "${nvim_stage}" "${local_opt}/nvim-${NVIM_VERSION}"
cp -a "${kitty_stage}" "${local_root}/kitty.app"
cp -a "${tree_stage}" "${local_opt}/tree-sitter-${TREE_SITTER_VERSION}"
cp -a "${font_stage}" "${data_home}/fonts/FiraCodeNerdFont"

ln -s "${repo_root}/.config/nvim" "${config_home}/nvim"
ln -s "${repo_root}/.config/kitty" "${config_home}/kitty"
ln -s "${local_opt}/nvim-${NVIM_VERSION}/bin/nvim" "${local_bin}/nvim"
ln -s "${local_root}/kitty.app/bin/kitty" "${local_bin}/kitty"
ln -s "${local_root}/kitty.app/bin/kitten" "${local_bin}/kitten"
ln -s "${local_opt}/tree-sitter-${TREE_SITTER_VERSION}/bin/tree-sitter" "${local_bin}/tree-sitter"

if [[ -f ${local_root}/kitty.app/share/applications/kitty.desktop ]]; then
  cp "${local_root}/kitty.app/share/applications/kitty.desktop" "${data_home}/applications/kitty.desktop"
  sed -i \
    -e "s|^Exec=kitty|Exec=${local_root}/kitty.app/bin/kitty|" \
    -e "s|^TryExec=kitty|TryExec=${local_root}/kitty.app/bin/kitty|" \
    -e "s|^Icon=kitty$|Icon=${local_root}/kitty.app/share/icons/hicolor/256x256/apps/kitty.png|" \
    "${data_home}/applications/kitty.desktop"
  desktop-file-validate "${data_home}/applications/kitty.desktop"
  update-desktop-database "${data_home}/applications"
fi
fc-cache -f "${data_home}/fonts"

python3 -m venv "${data_home}/configs-mdview-venv"
"${data_home}/configs-mdview-venv/bin/python" -m pip install --disable-pip-version-check \
  -r "${repo_root}/requirements/mdview.lock"
printf '#!/bin/sh\nexec %q %q "$@"\n' \
  "${data_home}/configs-mdview-venv/bin/python" "${repo_root}/bin/mdview" > "${local_bin}/mdview"
chmod 755 "${local_bin}/mdview"

export PATH="${local_bin}:${PATH}"
"${local_bin}/nvim" --headless -i NONE '+Lazy! restore' '+qa'
"${local_bin}/nvim" --headless -i NONE "+lua dofile([[${repo_root}/scripts/nvim/bootstrap.lua]])" '+qa'

"${repo_root}/verify.sh"
printf '\nInstallation finished. Open a new login shell so ~/.local/bin is first in PATH.\n'
