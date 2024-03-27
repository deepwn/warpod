# Warpod

A containerized [WARP](https://developers.cloudflare.com/cloudflare-one/connections/connect-devices/warp) client with [gost](https://github.com/go-gost/gost) proxy. (ubuntu:22.04 + warp-svc + gost) for use Zero Trust and private network inside container project and k8s.

Working with `free` or `warp+` and `zero Trust` network.

- [Warpod](#warpod)
  - [Features](#features)
  - [Environment Variables](#environment-variables)
  - [Registration auto switch](#registration-auto-switch)
  - [Setting MDM in dashboard](#setting-mdm-in-dashboard)
  - [Run with ghcr.io](#run-with-ghcrio)
  - [Build image locally](#build-image-locally)
  - [Example and tips](#example-and-tips)
  - [License](#license)

## Features

Only start warp use `proxy mode` at `41080` in the contrainer (for rootless, no iptables, no systemctl, no networkManager, no dbus service)

Use `gost` to open `socks5:1080` `http:1081` `https:1082` and all forward-chain to `warp-svc` at `41080`.

It can running with `docker` or `podman` or `k8s` on linux platform.

You can use `PORXY_AUTH` to set a proxy's authentication if need.

## Environment Variables

- **WARP_ORG_ID** - WARP MDM organization ID. (E.g. `deepwn`)
- **WARP_AUTH_CLIENT_ID** - WARP MDM client ID. (E.g. `xxxxxxxxxxxxxxxxxxxxxxxxxx.access`)
- **WARP_AUTH_CLIENT_SECRET** - WARP MDM client secret. (E.g. `xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx`)
- **WARP_UNIQUE_CLIENT_ID** - WARP MDM unique client ID. (E.g. `12345678-1234-1234-1234-123456789abc`)
- **WARP_LICENSE** - WARP MDM license key. (E.g. `xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx`)
- **WARP_LISTEN_PORT** - warp-svc listen port. (default: `41080`)
- ~~**WARP_LISTEN_ADDR** - warp-svc listen address. (service not support yet, hardcode to `localhost`)~~
- **SOCK_PORT** - local socks5 listen port. (default: `1080`)
- **HTTP_PORT** - local http listen port. (default: `1081`)
- **HTTPS_PORT** - local https listen port. (default: `1082`)
- **PROXY_AUTH** - local proxy's authentication. (E.g. `user:password`)

## Registration auto switch

- `free` mode is default if no `ID` or `LICENSE` be set. it will register new account (free network)

- `mdm` mode auto be using when `WARP_ORG_ID` `WARP_AUTH_CLIENT_ID` `WARP_AUTH_CLIENT_SECRET` set. (zero Trust network)

- `warp+` mode auto be using when `WARP_LICENSE` set. (warp+ network)

For some reason, highly recommend you use `mdm` mode with `WARP_ORG_ID` `WARP_AUTH_CLIENT_ID` `WARP_AUTH_CLIENT_SECRET` set.

And do set a policy of proxy from cloudflare Zero Trust dashboard, or use `warp+` mode with `WARP_LICENSE` set.

> if you need add other organization in `mdm` mode, or write more custom settings, you can modify this example file add a `<dict>` part.

cloudflare MDM document [here](https://developers.cloudflare.com/cloudflare-one/connections/connect-devices/warp/deployment/mdm-deployment/). cloudflare MDM parameters document [here](https://developers.cloudflare.com/cloudflare-one/connections/connect-devices/warp/deployment/mdm-deployment/parameters/#service_mode).

but for not break the `entrypoint.sh` flow. plase do **NOT** change this part:

```xml
<array>
  # don't modify this part
  <dict>
    <key>organization</key>
    <string>ORGANIZATION</string>
    <key>display_name</key>
    <string>ORGANIZATION</string>
    <key>auth_client_id</key>
    <string>AUTH_CLIENT_ID</string>
    <key>auth_client_secret</key>
    <string>AUTH_CLIENT_SECRET</string>
    <key>unique_client_id</key>
    <string>UNIQUE_CLIENT_ID</string>
    <key>onboarding</key>
    <false />
  </dict>
  # add your custom part down here
</array>
```

## Setting MDM in dashboard

1. go cloudflare Zero Trust dashboard.
1. create your org team in words range: `[a-zA-Z0-9-]` and remember your `ORGANIZATION` (set org name to ./secrets).
1. create a `Access -> Service Authentication -> Service Token` and get `AUTH_CLIENT_ID` and `AUTH_CLIENT_SECRET` from dashboard. (set to ./secrets)
1. goto `Settings -> Warp Client -> Device settings` and add a new policy (E.g.: named "mdmPolicy").
1. into the policy config page, add a rule to let `email` - `is` - `non_identity@[your_org_name].cloudflareaccess.com` in expression. (Or filter by device uuid)
1. go down and find `Service mode` to set `proxy` mode and port `41080`. [why must set proxy mode in policy?](https://developers.cloudflare.com/cloudflare-one/connections/connect-devices/warp/deployment/mdm-deployment/parameters/#service_mode)
1. modify other settings if your want.
1. then save it.

## Run with ghcr.io

```sh
docker pull ghcr.io/deepwn/warpod:latest
```

then follow the [Environment Variables](#environment-variables) to run it.

```sh
docker run -d --name warpod --hostname warpod --network warpod \
  -e WARP_ORG_ID=WARP_ORG_ID \
  -e WARP_AUTH_CLIENT_ID=WARP_AUTH_CLIENT_ID \
  -e WARP_AUTH_CLIENT_SECRET=WARP_AUTH_CLIENT_SECRET \
  -p 1080-1082:1080-1082 \
  ghcr.io/deepwn/warpod:latest
```

to testing to set `WARP_ORG_ID` `WARP_AUTH_CLIENT_ID` `WARP_AUTH_CLIENT_SECRET` in your environment.

but you'd better use `docker secret create` to set it in production.


## Build image locally

script: [autorun.sh](./autorun.sh) required `curl` `wget` `jq` commands, and container runtime `docker` or `podman`.

full auto build image with docker or podman just need you run:

```sh
./autorun.sh -q (quite mode, only build image)
```

or you can download `gost.tar.gz` from other source at first. but carefully, you need choose the right `linux_amd64` platform for Dockerfile's base image `ubuntu:22.04`

and you can use `-h` to see more help. and you can use `-r` to run container after build.

```text
./autorun.sh -h
Usage: ./autorun.sh [options]
Options:
  -h, --help      Print this help message
  -c, --command   Set container runtime command (default: auto select from docker or podman)
  -t, --tag       Set image tag for warp image (default: warpod:latest)
  -g, --gost      Download gost binary from specified url (default: from github)
  -r, --run       Run warpod container after build. it will force renew network and container (default: false)
  -q, --quiet     Quiet mode (only build image, no input required, and force skip -r option)

Additional:
  (If need run after build. you can add more options)
  -n, --hostname  Set hostname and container name (it will register to Zero Trust's Device ID)
  -p, --ports     Set ports expose (e.g.: -p 1080-1082:1080-1082, to expose to host server)
  -e, --envs      Set ENV for container (e.g.: -e WARP_LISTEN_PORT=41080 SOME_ENV=VALUE ...)

Example (run after build):
  ./autorun.sh -t beta-1 -c podman -r -n warpod-beta -p 2080-2082:1080-1082 -e WARP_LISTEN_PORT=21080 --secret WARP_LICENSE=LICENSE
```

## Example and tips

test run with podman on rockylinux 8.9:

```text
# build a test image
./autorun.sh -q >/dev/null 2>&1

# Or download from ghcr.io
# podman pull ghcr.io/deepwn/warpod:latest

# check image
podman image ls 
REPOSITORY                       TAG         IMAGE ID      CREATED       SIZE
localhost/warpod                 latest      91f2fb3774ab  1 second ago  642 MB

# use env just for test, you can set it in ./secrets
export WARP_ORG_ID=deepwn
export WARP_AUTH_CLIENT_ID=xxxxxxxxxxxxxxxxxxxxxxxxxx.access
export WARP_AUTH_CLIENT_SECRET=xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx

podman run -d --name warpod --hostname warpod --network warpod \
  -e WARP_ORG_ID=WARP_ORG_ID \
  -e WARP_AUTH_CLIENT_ID=WARP_AUTH_CLIENT_ID \
  -e WARP_AUTH_CLIENT_SECRET=WARP_AUTH_CLIENT_SECRET \
  -p 1080-1082:1080-1082 \
  warpod:latest
  
# test in container for warp
podman exec -it warpod curl -x socks5://127.0.0.1:41080 http://cloudflare.com/cdn-cgi/trace

# test out container for gost
curl -x socks5://127.0.0.1:1080 http://ip-api.com/json
```

and you can see the output like this:

```text
[+] Starting dbus...
[+] Bypassing warp's TOS...
[+] Starting warp-svc...
[+] Registering mdm save to: /var/lib/cloudflare-warp/mdm.xml
[+] you should set policy from Zero Trust dashboard.
    documents: https://developers.cloudflare.com/cloudflare-one/connections/connect-devices/warp/deployment/mdm-deployment/
[!] Careful: New service modes such as Proxy only are not supported as a value and must be configured in Zero Trust.
    (https://developers.cloudflare.com/cloudflare-one/connections/connect-devices/warp/deployment/mdm-deployment/parameters/#service_mode)
[+] Set warp mode to proxy ... Success
[+] Set proxy listen to 41080 ... Success
[+] Turn ON warp ... Success
[+] Waiting for warp to connect...
[+] warp connected!
gost config generated: /var/lib/cloudflare-warp/gost.yaml
[+] All services started!
---
warp-svc config: /var/lib/cloudflare-warp/conf.json
gost config: /var/lib/cloudflare-warp/gost.yaml
---
[+] warp status: Status update: Connected

[+] You can check it with warp local proxy in container:
    Or use gost proxy at 1080, 1081, 1082 with auth if set
    E.g.:
      curl -x socks5://127.0.0.1:41080 https://cloudflare.com/cdn-cgi/trace (inside container)
      curl -x http://<auth:pass>@<container_ip>:<gost_port> https://ip-api.com/json (outside container)
```

> [!TIP]
> you can use `ADD sources.list /etc/apt/sources.list` from Dockerfile if you need a apt source mirror by *.edu.cn.
> 
> and you can download another version of `gost.tar.gz` by yourself, and put it in the same directory with Dockerfile.
> 
> At last, you can modify the `entrypoint.sh` to add more `gost` listen port or args. for example, add a local dns server or local network proxy.

## License

[MIT](./LICENSE)
