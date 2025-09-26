#!/usr/bin/env bash
#
# deploy_ensemble.sh - Preliminary deployment script for PC/GEOS Ensemble Alpha
#
# This script downloads the latest PC/GEOS Ensemble build together with the
# matching Basebox DOSBox fork, prepares a runnable environment under
# "$HOME/geospc", and provides an Ensemble launcher within that directory that
# boots Ensemble inside Basebox. The script is designed to be idempotent:
# running it again refreshes the installation while preserving user-created
# files and redirecting configurable data into ENSEMBLE.FIX for safe updates.
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
GEOS_INSTALL_DIR="${DRIVEC_DIR}/ensemble"
GEOS_FIX_DIR="${DRIVEC_DIR}/ENSEMBLE.FIX"
GEOS_ARCHIVE_ROOT="ensemble"
BASEBOX_DIR="${INSTALL_ROOT}/basebox"
BASEBOX_BASE_CONFIG="${BASEBOX_DIR}/basebox-geos.conf"
BASEBOX_USER_CONFIG="${BASEBOX_DIR}/basebox.conf"
LOCAL_LAUNCHER="${INSTALL_ROOT}/ensemble.sh"

declare -a GEOS_EXCEPTION_RULES=(
    "geos.ini|${GEOS_FIX_DIR}|NET.INI"
    "privdata/token_da.000|${GEOS_FIX_DIR}|token_da.000"
)

DETECTED_BASEBOX_BINARY=""

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

resolve_geos_archive_root()
{
    local base_dir default_root candidate

    base_dir="$1"
    default_root="${base_dir}/${GEOS_ARCHIVE_ROOT}"

    if [ -d "${default_root}" ]; then
        printf '%s\n' "${default_root}"
        return
    fi

    candidate="$(find "${base_dir}" -maxdepth 2 -type f -iname 'geos.ini' -print -quit 2>/dev/null || true)"
    if [ -n "${candidate}" ]; then
        dirname "${candidate}"
        return
    fi

    candidate="$(find "${base_dir}" -maxdepth 1 -type d -iname 'ensemble' -print -quit 2>/dev/null || true)"
    if [ -n "${candidate}" ]; then
        printf '%s\n' "${candidate}"
        return
    fi

    printf '%s\n' ''
}

process_geos_exception_files()
{
    local source_root="$1"
    local rule src_rel dest_dir dest_name src_path dest_path

    for rule in "${GEOS_EXCEPTION_RULES[@]}"; do
        IFS='|' read -r src_rel dest_dir dest_name <<<"${rule}"
        src_path="${source_root}/${src_rel}"
        dest_path="${dest_dir}/${dest_name}"

        mkdir -p "${dest_dir}"

        if [ -f "${src_path}" ]; then
            cp -f "${src_path}" "${dest_path}"
        else
            log "Warning: expected exception file '${src_rel}' not found in archive"
        fi
    done
}

update_geos_ini_paths()
{
    local geos_ini
    geos_ini="${GEOS_INSTALL_DIR}/GEOS.INI"

    if [ ! -f "${geos_ini}" ]; then
        {
            printf '[paths]\r\n'
            printf 'ini=C:\\ENSEMBLE.FIX\\NET.INI\r\n'
            printf 'sharedTokenDatabase=C:\\ENSEMBLE.FIX\r\n'
        } >"${geos_ini}"
        return
    fi

    local tmp_file
    tmp_file="$(mktemp)"

    local ini_line token_line
    ini_line='ini=C:\\ENSEMBLE.FIX\\NET.INI'
    token_line='sharedTokenDatabase=C:\\ENSEMBLE.FIX'

    LC_ALL=C awk -v ini_line="${ini_line}" -v token_line="${token_line}" '
    function emit(text) {
        printf "%s\r\n", text
    }

    function flush_pending() {
        if (in_paths) {
            if (!have_ini) {
                emit(ini_line)
                have_ini = 1
            }
            if (!have_token) {
                emit(token_line)
                have_token = 1
            }
        }
    }

    {
        raw = $0
        sub(/\r$/, "", raw)

        ctrl_z_pos = index(raw, "\032")
        if (ctrl_z_pos) {
            line = substr(raw, 1, ctrl_z_pos - 1)
            exit_after = 1
        } else {
            line = raw
            exit_after = 0
        }

        lower = tolower(line)
        should_emit = 1

        if (lower ~ /^[[:space:]]*\[paths\][[:space:]]*$/) {
            if (in_paths) {
                flush_pending()
            }
            in_paths = 1
            have_ini = 0
            have_token = 0
            seen_paths = 1
            emit(line)
            if (exit_after) {
                exit
            }
            next
        }

        if (lower ~ /^[[:space:]]*\[/) {
            if (in_paths) {
                flush_pending()
                in_paths = 0
            }
            emit(line)
            if (exit_after) {
                exit
            }
            next
        }

        if (in_paths) {
            if (lower ~ /^[[:space:]]*ini[[:space:]]*=/) {
                have_ini = 1
            }
            if (lower ~ /^[[:space:]]*sharedtokendatabase[[:space:]]*=/) {
                have_token = 1
            }
        }

        if (ctrl_z_pos == 1 && length(line) == 0) {
            should_emit = 0
        }

        if (should_emit) {
            emit(line)
        }

        if (exit_after) {
            exit
        }
    }

    END {
        if (in_paths) {
            flush_pending()
            in_paths = 0
            seen_paths = 1
        }

        if (!seen_paths) {
            emit("[paths]")
            emit(ini_line)
            emit(token_line)
        }
    }
    ' "${geos_ini}" >"${tmp_file}"

    mv "${tmp_file}" "${geos_ini}"
}

# -----------------------------------------------------------------------------
# Installation steps
# -----------------------------------------------------------------------------

prepare_environment()
{
    log "Checking prerequisites"
    require_command unzip
    require_command rsync

    if ! command -v curl >/dev/null 2>&1 && ! command -v wget >/dev/null 2>&1; then
        fail "Either curl or wget must be installed to download release archives."
    fi

    log "Preparing installation directories under ${INSTALL_ROOT}"
    mkdir -p "${INSTALL_ROOT}"
    mkdir -p "${DRIVEC_DIR}"
    mkdir -p "${GEOS_INSTALL_DIR}"
    mkdir -p "${GEOS_FIX_DIR}"
    mkdir -p "${BASEBOX_DIR}"
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
    local geos_source
    geos_source="$(resolve_geos_archive_root "${temp_dir}/ensemble")"

    if [ -z "${geos_source}" ] || [ ! -d "${geos_source}" ]; then
        rm -rf "${temp_dir}"
        fail "Unable to locate Ensemble archive root inside ${temp_dir}/ensemble."
    fi

    local -a rsync_args
    rsync_args=("-a" "--update")
    local rule src_rel
    for rule in "${GEOS_EXCEPTION_RULES[@]}"; do
        src_rel="${rule%%|*}"
        rsync_args+=("--exclude=${src_rel}")
    done

    rsync "${rsync_args[@]}" "${geos_source}/" "${GEOS_INSTALL_DIR}/"

    process_geos_exception_files "${geos_source}"
    update_geos_ini_paths

    log "Installing Basebox into ${BASEBOX_DIR}"
    rsync -a --update "${temp_dir}/basebox/pcgeos-basebox/" "${BASEBOX_DIR}/"

    log "Ensuring Basebox executables are marked executable"
    find "${BASEBOX_DIR}" -type f \( -name 'basebox' -o -name 'basebox.exe' -o -name '*.sh' \) -exec chmod +x {} +

    local detected_binary
    detected_binary="$(detect_basebox_binary)"
    if [ -z "${detected_binary}" ]; then
        fail "Unable to locate the Basebox executable inside ${BASEBOX_DIR}."
    fi

    DETECTED_BASEBOX_BINARY="${detected_binary}"

    rm -rf "${temp_dir}"

    if [ -n "${previous_exit_trap}" ]; then
        eval "${previous_exit_trap}"
    else
        trap - EXIT
    fi
}

create_basebox_config()
{
    local drivec_abs_path basebox_binary_rel basebox_binary xdg_root config_output config_line config_path config_dir tmp_conf autoexec_file

    drivec_abs_path="$(absolute_path "${DRIVEC_DIR}")"

    basebox_binary_rel="${DETECTED_BASEBOX_BINARY}"
    if [ -z "${basebox_binary_rel}" ]; then
        basebox_binary_rel="$(detect_basebox_binary)"
    fi

    if [ -z "${basebox_binary_rel}" ]; then
        fail "Unable to locate the Basebox executable for configuration generation."
    fi

    basebox_binary="${BASEBOX_DIR}/${basebox_binary_rel}"

    log "Generating Basebox configuration from ${basebox_binary_rel}"

    xdg_root="$(mktemp -d)"
    mkdir -p "${xdg_root}/config"

    config_output="$(XDG_CONFIG_HOME="${xdg_root}/config" "${basebox_binary}" --printconf 2>/dev/null || true)"
    config_line="$(printf '%s\n' "${config_output}" | awk 'NF { last=$0 } END { print last }')"
    config_line="${config_line%$'\r'}"

    if [ -z "${config_line}" ]; then
        rm -rf "${xdg_root}"
        fail "Failed to determine the Basebox configuration path via --printconf."
    fi

    if [[ "${config_line}" == *:* ]]; then
        config_path="${config_line##*:}"
    else
        config_path="${config_line}"
    fi

    config_path="$(printf '%s' "${config_path}" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"

    if [ -z "${config_path}" ]; then
        rm -rf "${xdg_root}"
        fail "Unable to parse the Basebox configuration path from --printconf output."
    fi

    config_dir="$(dirname "${config_path}")"
    mkdir -p "${config_dir}"
    rm -f "${config_path}"

    local generated_config="false"

    if [ -z "${DISPLAY:-}" ] && [ -z "${WAYLAND_DISPLAY:-}" ]; then
        if SDL_VIDEODRIVER=dummy SDL_AUDIODRIVER=dummy \
            XDG_CONFIG_HOME="${xdg_root}/config" "${basebox_binary}" -c exit >/dev/null 2>&1; then
            generated_config="true"
        else
            log "Warning: Basebox failed with SDL_VIDEODRIVER=dummy, retrying with host display"
        fi
    fi

    if [ "${generated_config}" != "true" ]; then
        if ! XDG_CONFIG_HOME="${xdg_root}/config" "${basebox_binary}" -c exit >/dev/null 2>&1; then
            rm -rf "${xdg_root}"
            fail "Basebox failed to generate its default configuration."
        fi
    fi

    if [ ! -f "${config_path}" ]; then
        rm -rf "${xdg_root}"
        fail "Basebox did not create a configuration file at ${config_path}."
    fi

    tmp_conf="$(mktemp)"
    cp "${config_path}" "${tmp_conf}"

    autoexec_file="$(mktemp)"
    printf '%s\n' \
        "@echo off" \
        "mount c \"${drivec_abs_path}\" -t dir" \
        "c:" \
        "cd ensemble" \
        "loader" \
        "exit" >"${autoexec_file}"

    sed -n "
/^[[:space:]]*\[autoexec\][[:space:]]*\$/I{
    p
    r ${autoexec_file}
    n
    :skip
    /^[[:space:]]*\[/I{
        p
        b
    }
    n
    b skip
}
p
" "${tmp_conf}" >"${BASEBOX_BASE_CONFIG}"

    rm -f "${tmp_conf}" "${autoexec_file}"
    rm -rf "${xdg_root}"

    if [ ! -f "${BASEBOX_USER_CONFIG}" ]; then
        : >"${BASEBOX_USER_CONFIG}"
    fi
}

create_launcher()
{
    log "Creating Ensemble launcher at ${LOCAL_LAUNCHER}"
    cat >"${LOCAL_LAUNCHER}" <<'LAUNCH'
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASEBOX_DIR="${SCRIPT_DIR}/basebox"

select_basebox_binary()
{
    local candidate
    if [ -x "${BASEBOX_DIR}/binl64/basebox" ]; then
        candidate="${BASEBOX_DIR}/binl64/basebox"
    elif [ -x "${BASEBOX_DIR}/binl/basebox" ]; then
        candidate="${BASEBOX_DIR}/binl/basebox"
    elif [ -x "${BASEBOX_DIR}/binmac/basebox" ]; then
        candidate="${BASEBOX_DIR}/binmac/basebox"
    elif [ -x "${BASEBOX_DIR}/binnt/basebox.exe" ]; then
        candidate="${BASEBOX_DIR}/binnt/basebox.exe"
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
BASE_CONFIG_FILE="${BASEBOX_DIR}/basebox-geos.conf"
USER_CONFIG_FILE="${BASEBOX_DIR}/basebox.conf"

if [ ! -f "$BASE_CONFIG_FILE" ]; then
    printf 'Error: Missing Basebox configuration at %s\n' "$BASE_CONFIG_FILE" >&2
    exit 1
fi

if [ ! -f "$USER_CONFIG_FILE" ]; then
    : >"$USER_CONFIG_FILE"
fi

exec "$BASEBOX_EXEC" -conf "$BASE_CONFIG_FILE" -conf "$USER_CONFIG_FILE" "$@"
LAUNCH
    chmod +x "${LOCAL_LAUNCHER}"
}

main()
{
    prepare_environment
    extract_archives
    create_basebox_config
    create_launcher

    log "Deployment complete. Run '${LOCAL_LAUNCHER}' to start Ensemble in Basebox."
}

main "$@"
