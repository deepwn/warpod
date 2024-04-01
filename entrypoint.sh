#!/bin/bash
set -e
warp_path="/var/lib/cloudflare-warp"

# settings from environment variables
warp_license=$WARP_LICENSE
warp_org_id=$WARP_ORG_ID
auth_client_id=$WARP_AUTH_CLIENT_ID
auth_client_secret=$WARP_AUTH_CLIENT_SECRET
unique_client_id=${WARP_UNIQUE_CLIENT_ID:-$(cat /proc/sys/kernel/random/uuid)}
warp_listen_port=${WARP_LISTEN_PORT:-41080}
sock_port=${SOCK_PORT:-1080}
http_port=${HTTP_PORT:-1081}
https_port=${HTTPS_PORT:-1082}
proxy_auth=$PROXY_AUTH

# from secret file if exists
if [ -f "/run/secrets/WARP_LICENSE" ]; then
    warp_license=$(cat /run/secrets/WARP_LICENSE)
fi
if [ -f "/run/secrets/WARP_ORG_ID" ]; then
    warp_org_id=$(cat /run/secrets/WARP_ORG_ID)
fi
if [ -f "/run/secrets/WARP_AUTH_CLIENT_ID" ]; then
    auth_client_id=$(cat /run/secrets/WARP_AUTH_CLIENT_ID)
fi
if [ -f "/run/secrets/WARP_AUTH_CLIENT_SECRET" ]; then
    auth_client_secret=$(cat /run/secrets/WARP_AUTH_CLIENT_SECRET)
fi
if [ -f "/run/secrets/PROXY_AUTH" ]; then
    proxy_auth=$(cat /run/secrets/PROXY_AUTH)
fi

# check parameters valid
if [ "$warp_license" ]; then
    if ! echo "$warp_license" | grep -qE '^[a-zA-Z0-9-]{26}$'; then
        echo "[!] Error: WARP_LICENSE invalid! (e.g.: 123456789-abcdef12-4567890a)"
        exit 1
    fi
fi
if [ "$warp_org_id" ]; then
    if ! echo "$warp_org_id" | grep -qE '^[a-z0-9-]{1,}$'; then
        echo "[!] Error: WARP_ORG_ID invalid! (e.g.: deepwn)"
        exit 1
    fi
fi
if [ "$auth_client_id" ]; then
    if ! echo "$auth_client_id" | grep -qE '^[a-z0-9]{32}.access$'; then
        echo "[!] Error: WARP_AUTH_CLIENT_ID invalid! (e.g.: 1234567890abcdef1234567890abcdef.access)"
        exit 1
    fi
fi
if [ "$auth_client_secret" ]; then
    if ! echo "$auth_client_secret" | grep -qE '^[a-z0-9]{64}$'; then
        echo "[!] Error: WARP_AUTH_CLIENT_SECRET invalid! (e.g.: 1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef)"
        exit 1
    fi
fi
if [ "$unique_client_id" ]; then
    if ! echo "$unique_client_id" | grep -qE '^[a-z0-9]{8}-[a-z0-9]{4}-[a-z0-9]{4}-[a-z0-9]{4}-[a-z0-9]{12}$'; then
        echo "[!] Error: WARP_UNIQUE_CLIENT_ID invalid! (e.g.: 12345678-1234-1234-1234-1234567890ab)"
        exit 1
    fi
fi
if [ "$proxy_auth" ]; then
    if ! echo "$proxy_auth" | grep -qE '^[a-zA-Z0-9-_.]:[a-zA-Z0-9-_.]$'; then
        echo "[!] Error: PROXY_AUTH invalid! (e.g.: username:password)"
        exit 1
    fi
fi

# check port is number and in use or out of range
if [ "$warp_listen_port" ] && ! echo "$warp_listen_port" | grep -qE '^[0-9]+$'; then
    echo "[!] Error: WARP_LISTEN_PORT is not a number!"
    exit 1
elif [ "$warp_listen_port" -lt 1024 ] || [ "$warp_listen_port" -gt 65535 ]; then
    echo "[!] Error: WARP_LISTEN_PORT out of port range 1024 < port < 65535"
    exit 1
fi

if [ "$sock_port" ] && ! echo "$sock_port" | grep -qE '^[0-9]+$'; then
    echo "[!] Error: SOCK_PORT is not a number!"
    exit 1
elif [ "$sock_port" -lt 1024 ] || [ "$sock_port" -gt 65535 ]; then
    echo "[!] Error: SOCK_PORT out of port range 1024 < port < 65535"
    exit 1
fi

if [ "$http_port" ] && ! echo "$http_port" | grep -qE '^[0-9]+$'; then
    echo "[!] Error: HTTP_PORT is not a number!"
    exit 1
elif [ "$http_port" -lt 1024 ] || [ "$http_port" -gt 65535 ]; then
    echo "[!] Error: HTTP_PORT out of port range 1024 < port < 65535"
    exit 1
fi

if [ "$https_port" ] && ! echo "$https_port" | grep -qE '^[0-9]+$'; then
    echo "[!] Error: HTTPS_PORT is not a number!"
    exit 1
elif [ "$https_port" -lt 1024 ] || [ "$https_port" -gt 65535 ]; then
    echo "[!] Error: HTTPS_PORT out of port range 1024 < port < 65535"
    exit 1
fi

# start dbus
if [ -n "$(pgrep dbus-daemon)" ]; then
    echo "[+] dbus already running!"
else
    echo "[+] Starting dbus..."
    mkdir -p /run/dbus
    dbus-daemon --config-file=/usr/share/dbus-1/system.conf
fi

# bypass warp's TOS
if [ -f "/root/.local/share/warp/accepted-tos.txt" ]; then
    echo "[+] warp's TOS already accepted!"
else
    echo "[+] Bypassing warp's TOS..."
    mkdir -p /root/.local/share/warp
    echo -n 'yes' >/root/.local/share/warp/accepted-tos.txt
fi

# start warp-svc in background
if [ -n "$(pgrep warp-svc)" ]; then
    echo "[+] warp-svc already running!"
else
    echo "[+] Starting warp-svc..."
    nohup /usr/bin/warp-svc >/dev/null 2>&1 &
fi

# wait for warp-svc to start
while [ -z "$(/usr/bin/warp-cli status 2>/dev/null | grep 'Status')" ]; do
    sleep 1
done

# have warp_org_id, auth_client_id, auth_client_secret, but not registered
if [ -n "$warp_org_id" ] && [ -n "$auth_client_id" ] && [ -n "$auth_client_secret" ]; then
    # mdm file exists, but not registered
    sed -e "s/ORGANIZATION/$warp_org_id/g" \
        -e "s/AUTH_CLIENT_ID/$auth_client_id/g" \
        -e "s/AUTH_CLIENT_SECRET/$auth_client_secret/g" \
        -e "s/UNIQUE_CLIENT_ID/$unique_client_id/g" \
        $warp_path/mdm.xml.example >$warp_path/mdm.xml
    echo "[+] Registering mdm save to: $warp_path/mdm.xml"
    echo "[+] you should set policy from Zero Trust dashboard."
    echo "    documents: https://developers.cloudflare.com/cloudflare-one/connections/connect-devices/warp/deployment/mdm-deployment/"
    echo "[!] Careful: New service modes such as Proxy only are not supported as a value and must be configured in Zero Trust."
    echo "    (https://developers.cloudflare.com/cloudflare-one/connections/connect-devices/warp/deployment/mdm-deployment/parameters/#service_mode)"
else
    # license exsits, but not registered
    if [ -n "$warp_license" ]; then
        echo "[+] Set warp license to $warp_license ... $(/usr/bin/warp-cli registration license $warp_license)"
    fi
    # no license, but not registered
    echo "[+] New registration generated ... $(/usr/bin/warp-cli registration new)"

    # change the operation mode to proxy and set the port (mdm is not needed in this case, should set mode and port in Zero Trust dashboard.)
    echo "[+] Set warp mode to proxy ... $(/usr/bin/warp-cli mode proxy)"
    echo "[+] Set proxy listen to $warp_listen_port ... $(/usr/bin/warp-cli proxy port $warp_listen_port)"
fi

# wait for warp to connect
echo "[+] Turn ON warp ... $(/usr/bin/warp-cli connect)"

# wait for warp status to be connecting
echo "[+] Waiting for warp to connect..."
while [ -z "$(/usr/bin/warp-cli status 2>/dev/null | grep 'Status' | grep 'Connected')" ]; do
    echo -n "."
    sleep 5
done

echo -e "\033[2K\r[+] warp connected!"

# start the gost server when proxy test ok
warp_proxy_url="socks5://127.0.0.1:$warp_listen_port"

# check gost config
gost_conf="$warp_path/gost.yaml"
if [ -f "$gost_conf" ]; then
    echo "Using custom gost config: $gost_conf"
else
    if [ -n "$proxy_auth" ]; then
        proxy_auth="${proxy_auth}@"
    fi
    /usr/bin/gost -L "socks5://${proxy_auth}0.0.0.0:$sock_port" -L "http://${proxy_auth}0.0.0.0:$http_port" -L "https://${proxy_auth}0.0.0.0:$https_port" -F "$warp_proxy_url" -O yaml >$gost_conf
    echo "gost config generated: $gost_conf"
fi

# start gost
cd $warp_path # go to warp path to make ssl files work
nohup /usr/bin/gost -C $gost_conf >$warp_path/gost.log 2>&1 &

# logging output
echo "[+] All services started!"
echo "---"
echo "warp-svc config: $warp_path/conf.json"
echo "gost config: $gost_conf"
echo "---"
echo "[+] warp status: $(/usr/bin/warp-cli status | grep 'Status')"
echo ""
# https://cloudflare.com/cdn-cgi/trace will show the warp ip
echo "[+] You can check it with warp local proxy in container:"
echo "    Or use gost proxy at $sock_port, $http_port, $https_port with auth if set"
echo "    E.g.:"
echo "      curl -x $warp_proxy_url https://cloudflare.com/cdn-cgi/trace (inside container)"
echo "      curl -x http://<auth:pass>@<container_ip>:<gost_port> https://ip-api.com/json (outside container)"

# keep checking warp status
connect_lost=false
while true; do
    # loading print dots at same line
    if [ -z "$(/usr/bin/warp-cli status | grep 'Status' | grep 'Connected')" ]; then
        if [ "$connect_lost" = false ]; then
            #clear line and print new line
            echo -e "\033[2K\r[!] warp connection lost! retrying..."
            connect_lost=true
            /usr/bin/warp-cli registration delete >/dev/null 2>&1 &&
                /usr/bin/warp-cli registration new >/dev/null 2>&1 &&
                /usr/bin/warp-cli connect >/dev/null 2>&1
        fi
        /usr/bin/warp-cli connect >/dev/null 2>&1
        echo -n "."
    else
        if [ "$connect_lost" = true ]; then
            connect_lost=false
            echo -e "\033[2K\r[+] warp reconnected!"
            # restart gost
            cd $warp_path
            pkill -f gost &&
                nohup /usr/bin/gost -C $gost_conf >$warp_path/gost.log 2>&1 &
        fi
    fi
    sleep 5
done
