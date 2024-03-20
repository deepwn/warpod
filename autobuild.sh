#!/bin/bash
#
# Author: evil7@deepwn
#
# This script is used to prepare binary and secrets for warpod container.
# It will download gost binary and create secrets if not exists.
# Then it will build warpod image and print base command.
#
# Usage: ./autobuild.sh [proxy] [image_tag]
#
# proxy: proxy address if needed for download gost.tar.gz
# image_tag: image tag for warpod, default is 'warpod:latest'
#
# You can add -e to set ENV and -p expose port if needed when run the container.

set -e

curl_cmd="curl -fsSL"

# add -x if need proxy pass with $1
if [ -n "$1" ]; then
    echo "[*] Use proxy: $1"
    curl_cmd="curl -x $1 -fsSL"
fi

# tag for warp image
image_tag=${2:-'warpod:latest'}

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
    # download gost to gost.tar.gz
    echo "[*] Downloading gost binary to gost.tar.gz"
    curl -sSL https://api.github.com/repos/go-gost/gost/releases | jq -r '.[0].assets[] | select(.name | test("linux_amd64.tar.gz")) | .browser_download_url' | xargs -n 1 wget -q --show-progress -O gost.tar.gz
else
    echo "[*] gost.tar.gz found. skip download."
fi

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

# select docker or podman
if [ ${#pod_handle[@]} -eq 1 ]; then
    pod_cmd=${pod_handle[0]}
else
    echo "[*] Multiple container runtime found: ${pod_handle[@]}"
    echo -n "[?] Use docker or podman? "
    read -r pod_cmd
    if [[ ! " ${pod_handle[@]} " =~ " ${pod_cmd} " ]]; then
        echo "[!] Error: Invalid input!"
        exit 1
    fi
fi

# create secrets if not exists
secrets=()
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
    if [ -n "$($pod_cmd secret ls | grep $secret_name)" ]; then
        secrets+=("--secret=${secret_name}")
    fi
done

# renew network
echo "[*] Create network 'warpod_network'"
if [ -n "$($pod_cmd network ls | grep warpod_network)" ]; then
    $pod_cmd network rm warpod_network >/dev/null 2>&1
fi
$pod_cmd network create warpod_network >/dev/null 2>&1

# build image
echo "[*] Build warp image to ${image_tag} (debug: build.log)"
$pod_cmd build -t "${image_tag}" . | tee build.log

# generate base command
base_cmd=("${pod_cmd}" run -itd --name warpod --network warpod_network --restart=unless-stopped "${secrets[@]} ${image_tag}")

# print when done
echo -e "[*] Base run command:\n    ${base_cmd[@]}"
echo -e "[*] Secrets created :\n    ${secrets[@]}"
echo "[!] Notes:"
echo "    You can add -e to set ENV and -p expose port if needed. E.g.: -e WARP_LISTEN_PORT=41080 -p 1080-1082:1080-1082"
echo "    Secret value will replace ENV if name in: WARP_LICENSE WARP_ORG_ID WARP_AUTH_CLIENT_ID WARP_AUTH_CLIENT_SECRET PROXY_AUTH"
echo "    For more security, you shoud set in secret and remove the ENV for 'token' or 'password' in production purpose."
