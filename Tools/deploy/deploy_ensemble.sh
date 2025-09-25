#!/usr/bin/env bash
#
# deploy_ensemble.sh - Preliminary deployment script for PC/GEOS Ensemble Alpha
#
# This script downloads the latest PC/GEOS Ensemble build together with the
# matching Basebox DOSBox fork, prepares a runnable environment under
# "$HOME/geospc", patches configuration files, and exposes a global launch
# command that boots Ensemble inside Basebox. The script is designed to be
# idempotent: running it again refreshes the installation while preserving
# user-specific configuration inside the "user" directory.
#
# Supported environments: Debian, Fedora, and Windows Subsystem for Linux.
# The script relies only on standard Unix tooling available on these
# platforms (bash, curl/wget, unzip, python3).

set -euo pipefail

# -----------------------------------------------------------------------------
# Configuration
# -----------------------------------------------------------------------------

GEOS_RELEASE_URL="https://github.com/bluewaysw/pcgeos/releases/download/CI-latest/pcgeos-ensemble_nc.zip"
BASEBOX_RELEASE_URL="https://github.com/bluewaysw/pcgeos-basebox/releases/download/CI-latest-issue-2/pcgeos-basebox.zip"

INSTALL_ROOT="${HOME}/geospc"
DRIVEC_DIR="${INSTALL_ROOT}/drivec"
BASEBOX_DIR="${INSTALL_ROOT}/basebox"
USER_DIR="${DRIVEC_DIR}/user"
USER_DOCUMENT_DIR="${USER_DIR}/document"
USER_GEOS_INI="${USER_DIR}/geos.ini"
GEOS_INSTALL_DIR="${DRIVEC_DIR}/ensemble"
GEOS_INI_PATH="${GEOS_INSTALL_DIR}/geos.ini"
BASEBOX_CONFIG="${BASEBOX_DIR}/basebox-geos.conf"
LOCAL_LAUNCHER="${BASEBOX_DIR}/run-ensemble.sh"
GLOBAL_LAUNCHER="${HOME}/.local/bin/pcgeos-ensemble"

# Paths to merge into GEOS standard paths. Extend PATH_MAPPINGS for future
# directory mappings (e.g. "fonts", "userdata", etc.). Values must use DOS
# style paths because they are interpreted inside the DOSBox guest.
declare -A PATH_MAPPINGS=(
    [document]="C:\\USER\\DOCUMENT"
)

# Additional INI files to load through the [paths] "ini" key. The order is
# significant: user overrides are appended after existing entries.
ADDITIONAL_INIS=(
    "C:\\USER\\GEOS.INI"
)

# -----------------------------------------------------------------------------
# Utility helpers
# -----------------------------------------------------------------------------

log()
{
    printf '[deploy] %s\n' "$*"
}

fail()
{
    printf 'Error: %s\n' "$*" >&2
    exit 1
}

require_command()
{
    local cmd="$1"
    if ! command -v "$cmd" >/dev/null 2>&1; then
        fail "Required command '${cmd}' not found. Please install it and re-run the script."
    fi
}

# Download helper. Tries curl first, then wget.
download()
{
    local url="$1"
    local destination="$2"

    if command -v curl >/dev/null 2>&1; then
        curl -fL "$url" -o "$destination"
    elif command -v wget >/dev/null 2>&1; then
        wget -O "$destination" "$url"
    else
        fail "Neither curl nor wget is available to download ${url}."
    fi
}

# Return the absolute path of the provided argument without requiring
# external utilities that may not exist on every platform.
absolute_path()
{
    local target="$1"
    ( cd "$target" >/dev/null 2>&1 && pwd )
}

# Detect the best Basebox executable for the current host.
detect_basebox_binary()
{
    local uname_s
    uname_s="$(uname -s 2>/dev/null || echo Linux)"
    case "${uname_s}" in
        Linux*)
            if [ -x "${BASEBOX_DIR}/binl64/basebox" ]; then
                printf 'binl64/basebox'
                return
            elif [ -x "${BASEBOX_DIR}/binl/basebox" ]; then
                printf 'binl/basebox'
                return
            fi
            ;;
        Darwin*)
            if [ -x "${BASEBOX_DIR}/binmac/basebox" ]; then
                printf 'binmac/basebox'
                return
            fi
            ;;
        CYGWIN*|MINGW*|MSYS*)
            if [ -x "${BASEBOX_DIR}/binnt/basebox.exe" ]; then
                printf 'binnt/basebox.exe'
                return
            fi
            ;;
    esac

    # Fallback for unexpected layouts.
    if [ -x "${BASEBOX_DIR}/binl64/basebox" ]; then
        printf 'binl64/basebox'
    elif [ -x "${BASEBOX_DIR}/binnt/basebox.exe" ]; then
        printf 'binnt/basebox.exe'
    else
        printf ''
    fi
}

# -----------------------------------------------------------------------------
# Installation steps
# -----------------------------------------------------------------------------

prepare_environment()
{
    log "Checking prerequisites"
    require_command unzip
    require_command python3

    if ! command -v curl >/dev/null 2>&1 && ! command -v wget >/dev/null 2>&1; then
        fail "Either curl or wget must be installed to download release archives."
    fi

    log "Preparing installation directories under ${INSTALL_ROOT}"
    mkdir -p "${INSTALL_ROOT}"
    mkdir -p "${DRIVEC_DIR}"
    mkdir -p "${USER_DOCUMENT_DIR}"

    # Preserve the user tree but refresh everything else for a clean update.
    find "${INSTALL_ROOT}" -mindepth 1 -maxdepth 1 -not -name "drivec" -exec rm -rf {} +
    find "${DRIVEC_DIR}" -mindepth 1 -maxdepth 1 -not -name "user" -exec rm -rf {} +
}

extract_archives()
{
    local temp_dir geos_zip basebox_zip
    temp_dir="$(mktemp -d)"
    geos_zip="${temp_dir}/pcgeos-ensemble.zip"
    basebox_zip="${temp_dir}/pcgeos-basebox.zip"

    log "Downloading PC/GEOS Ensemble build"
    download "${GEOS_RELEASE_URL}" "${geos_zip}"

    log "Downloading Basebox DOSBox fork"
    download "${BASEBOX_RELEASE_URL}" "${basebox_zip}"

    log "Extracting Ensemble archive"
    unzip -q "${geos_zip}" -d "${temp_dir}/ensemble"

    log "Extracting Basebox archive"
    unzip -q "${basebox_zip}" -d "${temp_dir}/basebox"

    log "Installing Ensemble into ${GEOS_INSTALL_DIR}"
    rm -rf "${GEOS_INSTALL_DIR}"
    mkdir -p "${GEOS_INSTALL_DIR}"
    cp -a "${temp_dir}/ensemble/ensemble/." "${GEOS_INSTALL_DIR}/"

    log "Installing Basebox into ${BASEBOX_DIR}"
    rm -rf "${BASEBOX_DIR}"
    mkdir -p "${BASEBOX_DIR}"
    cp -a "${temp_dir}/basebox/pcgeos-basebox/." "${BASEBOX_DIR}/"

    log "Ensuring Basebox executables are marked executable"
    find "${BASEBOX_DIR}" -type f \( -name 'basebox' -o -name 'basebox.exe' -o -name '*.sh' \) -exec chmod +x {} +

    local detected_binary
    detected_binary="$(detect_basebox_binary)"
    if [ -z "${detected_binary}" ]; then
        fail "Unable to locate the Basebox executable inside ${BASEBOX_DIR}."
    fi

    rm -rf "${temp_dir}"
}

ensure_user_state()
{
    log "Preserving user configuration"
    mkdir -p "${USER_DOCUMENT_DIR}"
    if [ ! -f "${USER_GEOS_INI}" ]; then
        cat >"${USER_GEOS_INI}" <<'EOC'
; User-specific GEOS settings are stored here. This file is merged via
; the [paths] ini directive added by the deployment script. Feel free to
; customize it without worrying about future deployments overwriting it.

EOC
    fi
}

patch_geos_ini()
{
    if [ ! -f "${GEOS_INI_PATH}" ]; then
        fail "Expected GEOS.INI at ${GEOS_INI_PATH} not found."
    fi

    log "Patching Ensemble geos.ini"

    local paths_payload ini_payload key
    paths_payload=""
    for key in "${!PATH_MAPPINGS[@]}"; do
        paths_payload+="${key}=${PATH_MAPPINGS[$key]}\n"
    done

    ini_payload=""
    if [ "${#ADDITIONAL_INIS[@]}" -gt 0 ]; then
        ini_payload="$(printf '%s\n' "${ADDITIONAL_INIS[@]}")"
    fi

    GEOS_PATH_MAPPINGS="${paths_payload}" \
    GEOS_INI_FILES="${ini_payload}" \
    GEOS_INI_TARGET="${GEOS_INI_PATH}" \
    python3 <<'PY'
import os
import pathlib

geos_ini_path = pathlib.Path(os.environ['GEOS_INI_TARGET'])
paths_env = os.environ.get('GEOS_PATH_MAPPINGS', '')
ini_env = os.environ.get('GEOS_INI_FILES', '')

path_mappings = {}
for line in paths_env.splitlines():
    if not line.strip() or '=' not in line:
        continue
    key, value = line.split('=', 1)
    path_mappings[key.strip()] = value.strip()

ini_files = [entry.strip() for entry in ini_env.splitlines() if entry.strip()]

text = geos_ini_path.read_text()
newline = '\r\n' if '\r\n' in text else '\n'
lines = text.replace('\r\n', '\n').split('\n')

if lines and lines[-1] != '':
    lines.append('')

paths_start = None
for idx, line in enumerate(lines):
    if line.strip().lower() == '[paths]':
        paths_start = idx
        break

if paths_start is None:
    if lines and lines[-1] != '':
        lines.append('')
    paths_start = len(lines)
    lines.append('[paths]')
    for key, value in path_mappings.items():
        lines.append(f"{key} = {value}")
    if ini_files:
        lines.append('ini = ' + ' '.join(ini_files))
    if lines[-1] != '':
        lines.append('')
else:
    paths_end = len(lines)
    for idx in range(paths_start + 1, len(lines)):
        if lines[idx].startswith('[') and lines[idx].strip().endswith(']'):
            paths_end = idx
            break

    def set_or_update(key, value):
        nonlocal paths_end
        key_lower = key.lower()
        for i in range(paths_start + 1, paths_end):
            if '=' not in lines[i]:
                continue
            existing_key, _ = lines[i].split('=', 1)
            if existing_key.strip().lower() == key_lower:
                lines[i] = f"{key} = {value}"
                return
        lines.insert(paths_end, f"{key} = {value}")
        paths_end += 1

    for key, value in path_mappings.items():
        set_or_update(key, value)

    if ini_files:
        existing_files = []
        ini_line_index = None
        for i in range(paths_start + 1, paths_end):
            if '=' not in lines[i]:
                continue
            existing_key, existing_value = lines[i].split('=', 1)
            if existing_key.strip().lower() == 'ini':
                ini_line_index = i
                existing_files = existing_value.strip().split()
                break
        for filename in ini_files:
            if filename not in existing_files:
                existing_files.append(filename)
        if existing_files:
            new_line = 'ini = ' + ' '.join(existing_files)
            if ini_line_index is not None:
                lines[ini_line_index] = new_line
            else:
                lines.insert(paths_end, new_line)
                paths_end += 1

    if lines and lines[-1] != '':
        lines.append('')

output = '\n'.join(lines)
if newline == '\r\n':
    output = output.replace('\n', '\r\n')

geos_ini_path.write_text(output)
PY
}

create_basebox_config()
{
    local drivec_abs_path
    drivec_abs_path="$(absolute_path "${DRIVEC_DIR}")"

    log "Writing Basebox configuration"
    cat >"${BASEBOX_CONFIG}" <<CONFIG
[sdl]
fullscreen=false
fulldouble=false
fullresolution=original
windowresolution=original
output=opengl
autolock=false
sensitivity=100
waitonerror=true
priority=normal,normal

[dosbox]
language=
machine=svga_s3
captures=capture
memsize=16

[render]
frameskip=0
aspect=false
scaler=none

[cpu]
core=auto
cputype=auto
cycles=max
cycleup=10
cycledown=20

[mixer]
nosound=false
rate=44100
blocksize=1024
prebuffer=20

[sblaster]
sbtype=sb16
sbbase=220
irq=7
dma=1
hdma=5
sbmixer=true
oplmode=auto
oplemu=default
oplrate=44100

[autoexec]
@echo off
mount c "${drivec_abs_path}" -t dir
c:
cd ensemble
loader
CONFIG
}

create_launchers()
{
    log "Creating Basebox launcher at ${LOCAL_LAUNCHER}"
    cat >"${LOCAL_LAUNCHER}" <<'LAUNCH'
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

select_basebox_binary()
{
    local candidate
    if [ -x "${SCRIPT_DIR}/binl64/basebox" ]; then
        candidate="${SCRIPT_DIR}/binl64/basebox"
    elif [ -x "${SCRIPT_DIR}/binl/basebox" ]; then
        candidate="${SCRIPT_DIR}/binl/basebox"
    elif [ -x "${SCRIPT_DIR}/binmac/basebox" ]; then
        candidate="${SCRIPT_DIR}/binmac/basebox"
    elif [ -x "${SCRIPT_DIR}/binnt/basebox.exe" ]; then
        candidate="${SCRIPT_DIR}/binnt/basebox.exe"
    else
        candidate=""
    fi

    if [ -z "$candidate" ]; then
        printf 'Error: Unable to locate the Basebox executable.\n' >&2
        exit 1
    fi

    printf '%s' "$candidate"
}

BASEBOX_EXEC="$(select_basebox_binary)"
CONFIG_FILE="${SCRIPT_DIR}/basebox-geos.conf"

if [ ! -f "$CONFIG_FILE" ]; then
    printf 'Error: Missing Basebox configuration at %s\n' "$CONFIG_FILE" >&2
    exit 1
fi

exec "$BASEBOX_EXEC" -conf "$CONFIG_FILE" "$@"
LAUNCH
    chmod +x "${LOCAL_LAUNCHER}"

    log "Linking global launcher ${GLOBAL_LAUNCHER}"
    mkdir -p "$(dirname "${GLOBAL_LAUNCHER}")"
    ln -sf "${LOCAL_LAUNCHER}" "${GLOBAL_LAUNCHER}"
}

main()
{
    prepare_environment
    extract_archives
    ensure_user_state
    patch_geos_ini
    create_basebox_config
    create_launchers

    log "Deployment complete. Run 'pcgeos-ensemble' to start Ensemble in Basebox."
    if ! printf '%s' "$PATH" | tr ':' '\n' | grep -Fx "${HOME}/.local/bin" >/dev/null 2>&1; then
        log "Note: ${HOME}/.local/bin is not in your PATH. Add it to access the launcher globally."
    fi
}

main "$@"
