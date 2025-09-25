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
# platforms (bash, curl/wget, unzip).

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
    local temp_dir geos_zip basebox_zip previous_exit_trap

    previous_exit_trap="$(trap -p EXIT || true)"

    temp_dir="$(mktemp -d)"
    trap 'rm -rf "${temp_dir}"' EXIT

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

    if [ -n "${previous_exit_trap}" ]; then
        eval "${previous_exit_trap}"
    else
        trap - EXIT
    fi
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

    # The GEOS documentation explains that entries under [paths] map
    # directories inside the Ensemble tree to DOS paths exposed by the
    # runtime. The "ini" key lists GEOS.INI files in load order: the base
    # configuration is read first and any later entries receive user changes.
    # We merge the shipped ensemble\geos.ini with user\geos.ini so that
    # personal settings persist across deployments.

    local path_payload ini_payload newline_style tmp_ini tmp_converted key
    path_payload=""
    for key in "${!PATH_MAPPINGS[@]}"; do
        path_payload+="${key}|${PATH_MAPPINGS[$key]}\n"
    done

    ini_payload=""
    if [ "${#ADDITIONAL_INIS[@]}" -gt 0 ]; then
        ini_payload="$(printf '%s\n' "${ADDITIONAL_INIS[@]}")"
    fi

    newline_style=$'\n'
    if LC_ALL=C grep -q $'\r' "${GEOS_INI_PATH}"; then
        newline_style=$'\r\n'
    fi

    tmp_ini="$(mktemp)"
    GEOS_PATH_MAPPINGS="${path_payload}" \
    GEOS_INI_FILES="${ini_payload}" \
    awk '
BEGIN {
    pathCountRaw = split(ENVIRON["GEOS_PATH_MAPPINGS"], pathLines, "\n")
    storedPathCount = 0
    for (i = 1; i <= pathCountRaw; i++) {
        line = pathLines[i]
        if (line == "") {
            continue
        }
        split(line, pair, "|")
        keyOrig = pair[1]
        keyLower = tolower(keyOrig)
        pathKeys[++storedPathCount] = keyOrig
        pathLower[storedPathCount] = keyLower
        pathValues[keyLower] = pair[2]
    }

    iniCountRaw = split(ENVIRON["GEOS_INI_FILES"], iniLines, "\n")
    storedIniCount = 0
    for (i = 1; i <= iniCountRaw; i++) {
        entry = iniLines[i]
        if (entry == "") {
            continue
        }
        iniList[++storedIniCount] = entry
    }
}
{
    line = $0
    sub(/\r$/, "", line)
    lastLine = line

    if (match(line, /^[ \t]*\[[Pp][Aa][Tt][Hh][Ss]\][ \t]*$/)) {
        inPaths = 1
        pathsSeen = 1
        print line
        next
    }

    if (inPaths) {
        if (match(line, /^[ \t]*\[/)) {
            output_missing_paths()
            output_ini_line()
            inPaths = 0
        } else if (match(line, /^[ \t]*([^=; \t]+)[ \t]*=[ \t]*(.*)$/, matchArr)) {
            keyRaw = matchArr[1]
            keyLower = tolower(keyRaw)
            valuePart = matchArr[2]

            comment = ""
            commentPos = index(valuePart, ";")
            if (commentPos > 0) {
                comment = substr(valuePart, commentPos)
                valuePart = substr(valuePart, 1, commentPos - 1)
            }

            gsub(/^[ \t]+/, "", valuePart)
            gsub(/[ \t]+$/, "", valuePart)

            if (keyLower == "ini") {
                iniWritten = 1
                delete iniSeen
                delete iniOrder
                iniOrderCount = 0

                existingCount = split(valuePart, existingTokens, /[ \t]+/)
                for (idx = 1; idx <= existingCount; idx++) {
                    token = existingTokens[idx]
                    if (token == "") {
                        continue
                    }
                    if (!(token in iniSeen)) {
                        iniOrder[++iniOrderCount] = token
                        iniSeen[token] = 1
                    }
                }
                for (i = 1; i <= storedIniCount; i++) {
                    token = iniList[i]
                    if (!(token in iniSeen)) {
                        iniOrder[++iniOrderCount] = token
                        iniSeen[token] = 1
                    }
                }
                if (iniOrderCount > 0) {
                    iniLine = "ini ="
                    for (i = 1; i <= iniOrderCount; i++) {
                        iniLine = iniLine " " iniOrder[i]
                    }
                    if (comment != "") {
                        iniLine = iniLine " " comment
                    }
                    print iniLine
                } else if (comment != "") {
                    print "ini =" comment
                }
                next
            }

            if (keyLower in pathValues) {
                pathWritten[keyLower] = 1
                replacementKey = keyRaw
                for (idx = 1; idx <= storedPathCount; idx++) {
                    if (pathLower[idx] == keyLower) {
                        replacementKey = pathKeys[idx]
                        break
                    }
                }
                printf "%s = %s", replacementKey, pathValues[keyLower]
                if (comment != "") {
                    printf " %s", comment
                }
                printf "\n"
                next
            }
        }
    }

    print line
}

function output_missing_paths(    idx, lowerKey) {
    for (idx = 1; idx <= storedPathCount; idx++) {
        lowerKey = pathLower[idx]
        if (!(lowerKey in pathWritten)) {
            print pathKeys[idx] " = " pathValues[lowerKey]
            pathWritten[lowerKey] = 1
        }
    }
}

function output_ini_line(    idx, token, line) {
    if (storedIniCount == 0 || iniWritten) {
        return
    }
    delete iniSeen
    delete iniOrder
    iniOrderCount = 0
    for (idx = 1; idx <= storedIniCount; idx++) {
        token = iniList[idx]
        if (!(token in iniSeen)) {
            iniOrder[++iniOrderCount] = token
            iniSeen[token] = 1
        }
    }
    if (iniOrderCount > 0) {
        line = "ini ="
        for (idx = 1; idx <= iniOrderCount; idx++) {
            line = line " " iniOrder[idx]
        }
        print line
        iniWritten = 1
    }
}

END {
    if (inPaths) {
        output_missing_paths()
        output_ini_line()
    }
    if (!pathsSeen) {
        if (NR > 0 && lastLine != "") {
            print ""
        }
        print "[paths]"
        output_missing_paths()
        output_ini_line()
    }
}
' "${GEOS_INI_PATH}" >"${tmp_ini}"

    if [ "${newline_style}" = $'\r\n' ]; then
        tmp_converted="$(mktemp)"
        awk '{ printf "%s\r\n", $0 } END { if (NR == 0) { printf "\r\n" } }' "${tmp_ini}" >"${tmp_converted}"
        mv "${tmp_converted}" "${tmp_ini}"
    fi

    mv "${tmp_ini}" "${GEOS_INI_PATH}"
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
