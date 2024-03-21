#!/bin/bash

##
# Author: evil7@deepwn
#
# This script is used to prepare binary and secrets for warpod container.
# It will download gost binary and create secrets if not exists.
# Then it will build warpod image and print base command.
#
# Usage: ./autorun.sh [options]
# Options:
#   -h, --help      Print this help message
#   -c, --command   Set container runtime command (default: auto select from docker or podman)
#   -t, --tag       Set image tag for warp image (default: warpod:latest)
#   -g, --gost      Download gost binary from specified url (default: from github)
#   -r, --run       Run warpod container after build. it will force renew network and container (default: false)
#   -q, --quiet     Quiet mode (only build image, no input required, and force skip -r option)
#
# Additional:
#   (If need run after build. you can add more options)
#   -n, --hostname  Set hostname and container name (it will register to Zero Trust's Device ID)
#   -p, --ports     Set ports expose (e.g.: -p 1080-1082:1080-1082, to expose to host server)
#   -e, --envs      Set ENV for container (e.g.: -e WARP_LISTEN_PORT=41080 SOME_ENV=VALUE ...)
#
# Example (run after build):
#   ./autorun.sh -t beta-1 -c podman -r -n warpod-beta -p 2080-2082:1080-1082 -e WARP_LISTEN_PORT=21080 --secret WARP_LICENSE=LICENSE
##

set -e

# default values
image_tag="latest"
gost_url=""
quiet_mode=false
pod_run=false
pod_hostname="warpod"
pod_ports="1080-1082:1080-1082"
pod_envs=()

# parse options
while [[ $# -gt 0 ]]; do
    case "$1" in
    -h | --help)
        echo "Usage: ./autorun.sh [options]"
        echo "Options:"
        echo "  -h, --help      Print this help message"
        echo "  -c, --command   Set container runtime command (default: auto select from docker or podman)"
        echo "  -t, --tag       Set image tag for warp image (default: warpod:latest)"
        echo "  -g, --gost      Download gost binary from specified url (default: from github)"
        echo "  -r, --run       Run warpod container after build. it will force renew network and container (default: false)"
        echo "  -q, --quiet     Quiet mode (only build image, no input required, and force skip -r option)"
        echo ""
        echo "Additional:"
        echo "  (If need run after build. you can add more options)"
        echo "  -n, --hostname  Set hostname and container name (it will register to Zero Trust's Device ID)"
        echo "  -p, --ports     Set ports expose (e.g.: -p 1080-1082:1080-1082, to expose to host server)"
        echo "  -e, --envs      Set ENV for container (e.g.: -e WARP_LISTEN_PORT=41080 SOME_ENV=VALUE ...)"
        echo ""
        echo "Example (run after build):"
        echo "  ./autorun.sh -t beta-1 -c podman -r -n warpod-beta -p 2080-2082:1080-1082 -e WARP_LISTEN_PORT=21080 --secret WARP_LICENSE=LICENSE"
        echo ""
        exit 0
        ;;
    -c | --command)
        pod_cmd="$2"
        shift 2
        ;;
    -t | --tag)
        image_tag="$2"
        shift 2
        ;;
    -g | --gost)
        gost_url="$2"
        shift 2
        ;;
    -q | --quiet)
        quiet_mode=true
        shift
        ;;
    -r | --run)
        pod_run=true
        shift
        ;;
    -n | --hostname)
        pod_hostname="$2"
        shift 2
        ;;
    -p | --ports)
        pod_ports="$2"
        shift 2
        ;;
    -e | --envs)
        pod_envs+=("$2")
        shift 2
        ;;
    *)
        echo "[!] Error: Invalid option $1"
        exit 1
        ;;
    esac
done

# if no gost.tar.gz
if [ ! -f gost.tar.gz ]; then
    # check curl wget and jq
    if ! command -v curl &>/dev/null; then
        echo "[!] Error: curl not found! please install curl or download gost.tar.gz manually."
        exit 1
    fi
    if ! command -v wget &>/dev/null; then
        echo "[!] Error: wget not found! please install wget or download gost.tar.gz manually."
        exit 1
    fi
    if ! command -v jq &>/dev/null; then
        echo "[!] Error: jq not found! please install jq or download gost.tar.gz manually."
        exit 1
    fi

    # download gost.tar.gz
    if [ -z "${gost_url}" ]; then
        # from github
        echo "[*] Downloading gost from github ..."
        curl -fsSL https://api.github.com/repos/go-gost/gost/releases | jq -r '.[0].assets[] | select(.name | test("linux_amd64.tar.gz")) | .browser_download_url' | xargs -n 1 wget -q --show-progress -O gost.tar.gz
    else
        # download from specified url
        echo "[*] Downloading gost from specified url ..."
        echo "    ${gost_url}"
        wget -q --show-progress -O gost.tar.gz "${gost_url}"
    fi
else
    echo "[*] Skip download. Using local gost.tar.gz ..."
fi

# check command
if [ -z "${pod_cmd}" ]; then
    pod_handle=()
    # add docker if exists
    if command -v docker &>/dev/null; then
        pod_handle+=("docker")
    fi
    # add podman if exists
    if command -v podman &>/dev/null; then
        pod_handle+=("podman")
    fi

    if [ ${#pod_handle[@]} -eq 0 ]; then
        echo "[!] Error: No container runtime found! please install docker or podman"
        exit 1
    fi
else
    # custom command with -c
    pod_handle=("${pod_cmd}")
fi

# select docker or podman
if [ ${#pod_handle[@]} -eq 1 ]; then
    pod_cmd=${pod_handle[0]}
else
    if [ "${quiet_mode}" = true ]; then
        pod_cmd=${pod_handle[0]}
    fi
    echo "[*] Multiple container runtime found: ${pod_handle[@]}"
    echo -n "[?] Use docker or podman? "
    read -r pod_cmd
    if [[ ! " ${pod_handle[@]} " =~ " ${pod_cmd} " ]]; then
        echo "[!] Error: Invalid input!"
        exit 1
    fi
fi

# build image
echo "[*] Build warpod image with tag: ${image_tag} (debug: build.log)"
rm -f build.log
$pod_cmd build -t "warpod:${image_tag}" . | tee build.log

# check build result
if [ -z "$($pod_cmd images | grep "warpod" | grep "${image_tag}")" ]; then
    echo "[!] Error: Build image failed! please check build.log for more information."
    exit 1
else
    echo "[+] Build image success!"
fi

# quit here if quiet mode
if [ "${quiet_mode}" = true ]; then
    exit 0
fi

# check secrets
secrets=()
pod_env_params=()

for secret_name in WARP_ORG_ID WARP_AUTH_CLIENT_ID WARP_AUTH_CLIENT_SECRET WARP_LICENSE PROXY_AUTH; do
    # if file exists, create secret with file content
    if [ -f "./.secrets/${secret_name}" ] && [ -s "./.secrets/${secret_name}" ]; then
        echo -n "Create secret ${secret_name} from file..."
        ${pod_cmd} secret rm "${secret_name}" >/dev/null 2>&1
        ${pod_cmd} secret create "${secret_name}" "./.secrets/${secret_name}"
    fi
    # if secrets not in pod_cmd
    if [ -z "$($pod_cmd secret ls | grep $secret_name)" ]; then
        echo -n "[?] Enter ${secret_name}: "
        read -r secret_value
        if [ -n "${secret_value}" ]; then
            echo "[+] Create secret ${secret_name} from input..."
            ${pod_cmd} secret rm "${secret_name}" >/dev/null 2>&1
            echo -n "${secret_value}" | ${pod_cmd} secret create "${secret_name}" -
        fi
    fi
    # secret to params
    if [ -n "$($pod_cmd secret ls | grep $secret_name)" ]; then
        secrets+=("--secret ${secret_name}")
    fi
done

# envs to params
for pod_env in "${pod_envs[@]}"; do
    pod_env_params+=("-e ${pod_env}")
done

# renew network
echo "[*] Create network 'warpod_network'"
${pod_cmd} network rm warpod_network >/dev/null 2>&1 &&
    ${pod_cmd} network create warpod_network >/dev/null 2>&1

# generate base command
base_cmd=(
    "${pod_cmd}" run -itd
    --name "${pod_hostname}"
    --hostname "${pod_hostname}"
    --network warpod_network
    --restart unless-stopped
    -p "${pod_ports}"
    "${secrets[@]}"
    "${pod_env_params[@]}"
    warpod:"${image_tag}"
)

# print when done
echo -e "[*] Image built     :\n    warpod:${image_tag}"
echo -e "[*] Secrets created :\n    ${secrets[@]}"
echo -e "[*] Network created :\n    warpod_network"
echo -e "[*] ENVs created    :\n    ${pod_env_params[@]}"
echo ""
echo -e "[*] Base run command:\n    ${base_cmd[@]}"
echo ""
echo "[!] Notes:"
echo "    You can add -e to set ENV and -p expose port if needed. E.g.: -e WARP_LISTEN_PORT=41080 -p 1080-1082:1080-1082"
echo "    Secret value will replace ENV if name in: WARP_LICENSE WARP_ORG_ID WARP_AUTH_CLIENT_ID WARP_AUTH_CLIENT_SECRET PROXY_AUTH"
echo "    For more security, you shoud set in secret and remove the ENV for 'token' or 'password' in production purpose."

# run container
if [ "${pod_run}" = true ]; then
    echo "[*] Run warpod container with base command..."
    ${base_cmd[@]}
elif [ "${quiet_mode}" = false ]; then
    echo -n "[?] Run warpod container now? (y/N) "
    read -r run_now
    if [ "${run_now}" = "y" ] || [ "${run_now}" = "Y" ]; then
        echo "[*] Run warpod container with base command..."
        ${base_cmd[@]}
    fi
fi
