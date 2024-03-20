FROM ubuntu:22.04

# apt mirror: mirrors.cernet.edu.cn (without security updates)
ADD sources.list /etc/apt/sources.list

# install deps
RUN apt-get update && apt-get -y install curl gnupg2 dbus openssl jq

# install warp
RUN curl -fsSL https://pkg.cloudflareclient.com/pubkey.gpg | gpg --yes --dearmor --output /usr/share/keyrings/cloudflare-warp-archive-keyring.gpg \
    && echo "deb [signed-by=/usr/share/keyrings/cloudflare-warp-archive-keyring.gpg] https://pkg.cloudflareclient.com/ jammy main" | tee /etc/apt/sources.list.d/cloudflare-client.list \
    && apt-get update \
    && apt-get -y upgrade \
    && apt-get -y install cloudflare-warp

# gost install
# # https://docs.github.com/rest/releases/releases#get-the-latest-release
# # select first in asset from github with filter with linux_amd64.tar.gz and download it
# RUN curl -s https://api.github.com/repos/go-gost/gost/releases | jq -r '.[0].assets[] | select(.name | test("linux_amd64.tar.gz")) | .browser_download_url' | xargs curl -fsSL -o gost.tar.gz \
#     && tar -xzf gost.tar.gz -C /usr/bin \
#     && chmod +x /usr/bin/gost \
#     && rm -f gost.tar.gz

ADD gost.tar.gz /usr/bin

# mdm.xml add
ADD mdm.xml.example /var/lib/cloudflare-warp/mdm.xml.example

RUN apt-get clean && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

ADD entrypoint.sh /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
