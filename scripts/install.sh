#!/bin/bash
## Do not modify this file. You will lose the ability to install and auto-update!

set -e # Exit immediately if a command exits with a non-zero status
## $1 could be empty, so we need to disable this check
#set -u # Treat unset variables as an error and exit
set -o pipefail # Cause a pipeline to return the status of the last command that exited with a non-zero status

VERSION="1.2.0"
DOCKER_VERSION="24.0"

CDN="https://cdn.coollabs.io/coolify"
OS_TYPE=$(grep -w "ID" /etc/os-release | cut -d "=" -f 2 | tr -d '"')

if [ "$OS_TYPE" = "arch" ]; then
    OS_VERSION="rolling"
else
    OS_VERSION=$(grep -w "VERSION_ID" /etc/os-release | cut -d "=" -f 2 | tr -d '"')
fi

LATEST_VERSION=$(curl --silent $CDN/versions.json | grep -i version | sed -n '2p' | xargs | awk '{print $2}' | tr -d ',')
DATE=$(date +"%Y%m%d-%H%M%S")

if [ $EUID != 0 ]; then
    echo "Please run as root"
    exit
fi

case "$OS_TYPE" in
    arch | ubuntu | debian | raspbian | centos | fedora | rhel | ol | rocky | sles | opensuse-leap | opensuse-tumbleweed) ;;
    *)
        echo "This script only supports Debian, Redhat, Arch Linux, or SLES based operating systems for now."
        exit
        ;;
esac

# Overwrite LATEST_VERSION if user pass a version number
if [ "$1" != "" ]; then
    LATEST_VERSION=$1
    LATEST_VERSION="${LATEST_VERSION,,}"
    LATEST_VERSION="${LATEST_VERSION#v}"
fi

echo -e "-------------"
echo -e "Welcome to Coolify v4 beta installer!"
echo -e "This script will install everything for you."
echo -e "(Source code: https://github.com/coollabsio/coolify/blob/main/scripts/install.sh)\n"
echo -e "-------------"

echo "OS: $OS_TYPE $OS_VERSION"
echo "Coolify version: $LATEST_VERSION"

echo -e "-------------"
echo "Installing required packages..."

case "$OS_TYPE" in
    arch)
        pacman -Sy >/dev/null 2>&1 || true
        if ! pacman -Q curl wget git jq >/dev/null 2>&1; then
            pacman -S --noconfirm curl wget git jq >/dev/null 2>&1 || true
        fi
        ;;
    ubuntu | debian | raspbian)
        apt update -y >/dev/null 2>&1
            apt install -y curl wget git jq >/dev/null 2>&1
        ;;
    centos | fedora | rhel | ol | rocky)
        dnf install -y curl wget git jq >/dev/null 2>&1
        ;;
    sles | opensuse-leap | opensuse-tumbleweed)
        zypper refresh >/dev/null 2>&1
        zypper install -y curl wget git jq >/dev/null 2>&1
        ;;
    *)
        echo "This script only supports Debian, Redhat, Arch Linux, or SLES based operating systems for now."
        exit
        ;;
esac

# Detect OpenSSH server
SSH_DETECTED=false
if [ -x "$(command -v systemctl)" ]; then
    if systemctl status sshd >/dev/null 2>&1; then
        echo "OpenSSH server is installed."
        SSH_DETECTED=true
    fi
    if systemctl status ssh >/dev/null 2>&1; then
        echo "OpenSSH server is installed."
        SSH_DETECTED=true
    fi
elif [ -x "$(command -v service)" ]; then
    if service sshd status >/dev/null 2>&1; then
        echo "OpenSSH server is installed."
        SSH_DETECTED=true
    fi
    if service ssh status >/dev/null 2>&1; then
        echo "OpenSSH server is installed."
        SSH_DETECTED=true
    fi
fi
if [ "$SSH_DETECTED" = "false" ]; then
    echo "###############################################################################"
    echo "WARNING: Could not detect if OpenSSH server is installed and running - this does not mean that it is not installed, just that we could not detect it."
    echo -e "Please make sure it is set, otherwise Coolify cannot connect to the host system. \n"
    echo "###############################################################################"
fi

# Detect SSH PermitRootLogin
SSH_PERMIT_ROOT_LOGIN=false
SSH_PERMIT_ROOT_LOGIN_CONFIG=$(grep "^PermitRootLogin" /etc/ssh/sshd_config | awk '{print $2}') || SSH_PERMIT_ROOT_LOGIN_CONFIG="N/A (commented out or not found at all)"
if [ "$SSH_PERMIT_ROOT_LOGIN_CONFIG" = "prohibit-password" ] || [ "$SSH_PERMIT_ROOT_LOGIN_CONFIG" = "yes" ] || [ "$SSH_PERMIT_ROOT_LOGIN_CONFIG" = "without-password" ]; then
    echo "PermitRootLogin is enabled."
    SSH_PERMIT_ROOT_LOGIN=true
fi


if [ "$SSH_PERMIT_ROOT_LOGIN" != "true" ]; then
    echo "###############################################################################"
    echo "WARNING: PermitRootLogin is not enabled in /etc/ssh/sshd_config."
    echo -e "It is set to $SSH_PERMIT_ROOT_LOGIN_CONFIG. Should be prohibit-password, yes or without-password.\n"
    echo -e "Please make sure it is set, otherwise Coolify cannot connect to the host system. \n"
    echo "(Currently we only support root user to login via SSH, this will be changed in the future.)"
    echo "###############################################################################"
fi

if ! [ -x "$(command -v docker)" ]; then
    echo "Docker is not installed. Installing Docker."
    if [ "$OS_TYPE" = "arch" ]; then
        pacman -Sy docker docker-compose --noconfirm
        systemctl enable docker.service
        if [ -x "$(command -v docker)" ]; then
            echo "Docker installed successfully."
        else
            echo "Failed to install Docker with pacman. Try to install it manually."
            echo "Please visit https://wiki.archlinux.org/title/docker for more information."
            exit
        fi
    else
        curl https://releases.rancher.com/install-docker/${DOCKER_VERSION}.sh | sh
        if [ -x "$(command -v docker)" ]; then
            echo "Docker installed successfully."
        else
            echo "Docker installation failed with Rancher script. Trying with official script."
            curl https://get.docker.com | sh -s -- --version ${DOCKER_VERSION}
            if [ -x "$(command -v docker)" ]; then
                echo "Docker installed successfully."
            else
                echo "Docker installation failed with official script."
                echo "Maybe your OS is not supported?"
                echo "Please visit https://docs.docker.com/engine/install/ and install Docker manually to continue."
                exit 1
            fi
        fi
    fi
fi

echo -e "-------------"
echo -e "Check Docker Configuration..."
mkdir -p /etc/docker
# shellcheck disable=SC2015
test -s /etc/docker/daemon.json && cp /etc/docker/daemon.json /etc/docker/daemon.json.original-"$DATE" || cat >/etc/docker/daemon.json <<EOL
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  }
}
EOL
cat >/etc/docker/daemon.json.coolify <<EOL
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  }
}
EOL
TEMP_FILE=$(mktemp)
if ! jq -s '.[0] * .[1]' /etc/docker/daemon.json /etc/docker/daemon.json.coolify >"$TEMP_FILE"; then
    echo "Error merging JSON files"
    exit 1
fi
mv "$TEMP_FILE" /etc/docker/daemon.json

if [ -s /etc/docker/daemon.json.original-"$DATE" ]; then
    DIFF=$(diff <(jq --sort-keys . /etc/docker/daemon.json) <(jq --sort-keys . /etc/docker/daemon.json.original-"$DATE"))
    if [ "$DIFF" != "" ]; then
        echo "Docker configuration updated, restart docker daemon..."
        systemctl restart docker
    else
        echo "Docker configuration is up to date."
    fi
else
    echo "Docker configuration updated, restart docker daemon..."
    systemctl restart docker
fi

echo -e "-------------"

mkdir -p /data/coolify/{source,ssh,applications,databases,backups,services,proxy}
mkdir -p /data/coolify/ssh/{keys,mux}
mkdir -p /data/coolify/proxy/dynamic

chown -R 9999:root /data/coolify
chmod -R 700 /data/coolify

echo "Downloading required files from CDN..."
curl -fsSL $CDN/docker-compose.yml -o /data/coolify/source/docker-compose.yml
curl -fsSL $CDN/docker-compose.prod.yml -o /data/coolify/source/docker-compose.prod.yml
curl -fsSL $CDN/.env.production -o /data/coolify/source/.env.production
curl -fsSL $CDN/upgrade.sh -o /data/coolify/source/upgrade.sh

# Copy .env.example if .env does not exist
if [ ! -f /data/coolify/source/.env ]; then
    cp /data/coolify/source/.env.production /data/coolify/source/.env
    sed -i "s|APP_ID=.*|APP_ID=$(openssl rand -hex 16)|g" /data/coolify/source/.env
    sed -i "s|APP_KEY=.*|APP_KEY=base64:$(openssl rand -base64 32)|g" /data/coolify/source/.env
    sed -i "s|DB_PASSWORD=.*|DB_PASSWORD=$(openssl rand -base64 32)|g" /data/coolify/source/.env
    sed -i "s|REDIS_PASSWORD=.*|REDIS_PASSWORD=$(openssl rand -base64 32)|g" /data/coolify/source/.env
    sed -i "s|PUSHER_APP_ID=.*|PUSHER_APP_ID=$(openssl rand -hex 32)|g" /data/coolify/source/.env
    sed -i "s|PUSHER_APP_KEY=.*|PUSHER_APP_KEY=$(openssl rand -hex 32)|g" /data/coolify/source/.env
    sed -i "s|PUSHER_APP_SECRET=.*|PUSHER_APP_SECRET=$(openssl rand -hex 32)|g" /data/coolify/source/.env
fi

# Merge .env and .env.production. New values will be added to .env
sort -u -t '=' -k 1,1 /data/coolify/source/.env /data/coolify/source/.env.production | sed '/^$/d' >/data/coolify/source/.env.temp && mv /data/coolify/source/.env.temp /data/coolify/source/.env

if [ "$AUTOUPDATE" = "false" ]; then
    if ! grep -q "AUTOUPDATE=" /data/coolify/source/.env; then
        echo "AUTOUPDATE=false" >>/data/coolify/source/.env
    else
        sed -i "s|AUTOUPDATE=.*|AUTOUPDATE=false|g" /data/coolify/source/.env
    fi
fi

# Generate an ssh key (ed25519) at /data/coolify/ssh/keys/id.root@host.docker.internal
if [ ! -f /data/coolify/ssh/keys/id.root@host.docker.internal ]; then
    ssh-keygen -t ed25519 -a 100 -f /data/coolify/ssh/keys/id.root@host.docker.internal -q -N "" -C root@coolify
    chown 9999 /data/coolify/ssh/keys/id.root@host.docker.internal
fi

addSshKey() {
    cat /data/coolify/ssh/keys/id.root@host.docker.internal.pub >>~/.ssh/authorized_keys
    chmod 600 ~/.ssh/authorized_keys
}

if [ ! -f ~/.ssh/authorized_keys ]; then
    mkdir -p ~/.ssh
    chmod 700 ~/.ssh
    touch ~/.ssh/authorized_keys
    addSshKey
fi

if ! grep -qw "root@coolify" ~/.ssh/authorized_keys; then
    addSshKey
fi

bash /data/coolify/source/upgrade.sh "${LATEST_VERSION:-latest}"

echo -e "\nCongratulations! Your Coolify instance is ready to use.\n"
echo "Please visit http://$(curl -4s https://ifconfig.io):8000 to get started."
