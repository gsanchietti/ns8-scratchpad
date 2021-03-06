#!/bin/bash

set -e

distro=$(awk -F = '/^ID=/ { print $2 }' /etc/os-release)

if [[ ! -f /usr/local/etc/registry.json ]] ; then
    echo "[ERROR] missing the registry access configuration. Copy it to /usr/local/etc/registry.json"
    exit 1
fi

echo "Registry auth found."
export REGISTRY_AUTH_FILE=/usr/local/etc/registry.json
chmod -c 644 ${REGISTRY_AUTH_FILE}

echo "Set kernel parameters:"
sysctl -w net.ipv4.ip_unprivileged_port_start=23 -w user.max_user_namespaces=28633 | tee /etc/sysctl.d/80-nethserver.conf
if [[ ${distro} == "debian" ]]; then
    sysctl -w kernel.unprivileged_userns_clone=1 | tee -a /etc/sysctl.d/80-nethserver.conf
fi

echo "Install dependencies:"
if [[ ${distro} == "fedora" ]]; then
    dnf install -y wireguard-tools podman jq
elif [[ ${distro} == "debian" ]]; then
    apt-get -y install gnupg2 python3-venv
    echo 'deb http://deb.debian.org/debian buster-backports main' >> /etc/apt/sources.list
    echo 'deb https://download.opensuse.org/repositories/devel:/kubic:/libcontainers:/stable/Debian_10/ /' > /etc/apt/sources.list.d/devel:kubic:libcontainers:stable.list
    wget -O - https://download.opensuse.org/repositories/devel:/kubic:/libcontainers:/stable/Debian_10/Release.key | apt-key add -
    apt-get update
    apt-get -y -t buster-backports install libseccomp2 podman
fi

installdir="/usr/local/share"
agentdir="${installdir}/agent"
cplanedir="${installdir}/cplane"

echo "Extracting control plane sources:"
podman pull ghcr.io/nethserver/control-plane:latest
cid=$(podman create ghcr.io/nethserver/control-plane:latest)
podman export ${cid} | tar -C ${installdir} -x -v -f -
podman rm -f ${cid}

cp -f ${agentdir}/node-agent.service      /etc/systemd/system/node-agent.service
cp -f ${agentdir}/module-agent.service    /etc/systemd/user/module-agent.service
cp -f ${agentdir}/module-init.service     /etc/systemd/user/module-init.service

echo "Setup agent:"
python3 -mvenv ${agentdir}
${agentdir}/bin/pip3 install redis

echo "Starting control plane:"
useradd -m -k ${cplanedir}/skel cplane
loginctl enable-linger cplane

echo "NODE_PREFIX=$(hostname -s)" > /usr/local/etc/node-agent.env
systemctl enable --now node-agent.service

if [[ ! -f ~/.ssh/id_rsa.pub ]] ; then
    ssh-keygen -t rsa -N '' -f ~/.ssh/id_rsa
fi

echo "Adding id_rsa.pub to data plane home skeleton dir:"
install -d -m 700 /usr/local/share/dplane/skel/.ssh
install -m 600 -T ~/.ssh/id_rsa.pub /usr/local/share/dplane/skel/.ssh/authorized_keys
