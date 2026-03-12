#!/bin/bash

# --- Default Values ---
TARGET_OS=""
OUTPUT_DIR="./packages"
REMOTE_LOC=""
REMOTE_INSTALL="no"
LIST_ONLY="no"
PACKAGES=""
SUPPORTED_TARGETS="rocky8, rocky9, rocky10, rhel8, rhel9, rhel10, oracle9, ubuntu20, ubuntu22, ubuntu24"

# --- Help Function ---
show_help() {
    echo "Usage: pkgproxy --target=<distro> [options] <package1> [package2 ...]"
    echo ""
    echo "Options:"
    echo "  --target=<distro>        Specify the target OS (Required)"
    echo "  --output=<path>          Local directory for downloads (Default: ./packages)"
    echo "  --remotelocation=<loc>   Remote destination (e.g., user@ip:/path) (requires --remotelocation to be specified)"
    echo "  --remoteinstall          Trigger installation on the remote host after transfer"
    echo "  --listonly               Show dependencies without downloading"
    echo "  --help                   Display this help message"
    echo ""
    echo "Supported Targets:"
    echo "  $SUPPORTED_TARGETS"
    echo ""
    echo "Example:"
    echo "  getpkgs --target=rocky10 --remotelocation=root@192.168.3.5:/root --remoteinstall epel-release htop"
    exit 0
}

# --- 1. Argument Parsing ---
if [[ "$#" -eq 0 ]]; then show_help; fi

while [[ "$#" -gt 0 ]]; do
    case $1 in
        --help) show_help ;;
        --target=*) TARGET_OS="${1#*=}"; shift ;;
        --output=*) OUTPUT_DIR="${1#*=}"; shift ;;
        --remotelocation=*) REMOTE_LOC="${1#*=}"; shift ;;
        --remoteinstall) REMOTE_INSTALL="yes"; shift ;;
        --listonly) LIST_ONLY="yes"; shift ;;
        -*) echo "Unknown option: $1. Use --help for usage."; exit 1 ;;
        *) PACKAGES="$PACKAGES $1"; shift ;;
    esac
done

# Validation
if [[ -z "$TARGET_OS" || -z "$PACKAGES" ]]; then
    echo "Error: Missing required arguments. Use --help for full syntax."
    exit 1
fi

TARGET_OS=$(echo "$TARGET_OS" | tr '[:upper:]' '[:lower:]')

# --- 2. Docker Check & Auto-Install ---
if ! command -v docker &> /dev/null; then
    echo "Docker not found. Installing..."
    curl -fsSL https://get.docker.com -o get-docker.sh
    sudo sh get-docker.sh && rm get-docker.sh
    DOCKER_CMD="sudo docker"
else
    DOCKER_CMD="docker"
fi

# --- 3. Execution Logic ---
case "$TARGET_OS" in
    rocky8|rocky9|rocky10|rhel8|rhel9|rhel10|oracle9)
        # Handle Image Mapping
        if [[ "$TARGET_OS" == "oracle9" ]]; then
            IMAGE="oraclelinux:9"
        else
            # Extracts numbers (including 10) for rocky/rhel targets
            VERSION_NUM="${TARGET_OS//[!0-9]/}"
            IMAGE="rockylinux:${VERSION_NUM}"
        fi

        EPEL_PREP=""
        if [[ $PACKAGES == *"epel-release"* ]]; then
            EPEL_PREP="dnf install -y epel-release && "
        fi

        if [[ "$LIST_ONLY" == "yes" ]]; then
            echo "--> Listing dependencies for $PACKAGES on $TARGET_OS..."
            $DOCKER_CMD run --rm "$IMAGE" bash -c "${EPEL_PREP}dnf install -y dnf-plugins-core &>/dev/null && dnf repoquery --requires --resolve --recursive $PACKAGES"
            exit 0
        fi

        mkdir -p "$OUTPUT_DIR"
        echo "--> Fetching RPMs for $TARGET_OS..."
        $DOCKER_CMD run --rm -v "$(realpath "$OUTPUT_DIR")":/download "$IMAGE" bash -c \
            "${EPEL_PREP}dnf install -y dnf-plugins-core && dnf download --resolve --destdir=/download $PACKAGES"
        ;;
    ubuntu20|ubuntu22|ubuntu24)
        VERSION="${TARGET_OS//[!0-9]/}.04"
        IMAGE="ubuntu:$VERSION"

        if [[ "$LIST_ONLY" == "yes" ]]; then
            echo "--> Listing dependencies for $PACKAGES on $TARGET_OS ($VERSION)..."
            $DOCKER_CMD run --rm "$IMAGE" bash -c "apt-get update &>/dev/null && apt-get install --simulate $PACKAGES | grep '^Inst'"
            exit 0
        fi

        mkdir -p "$OUTPUT_DIR"
        echo "--> Fetching DEBs for $TARGET_OS ($VERSION)..."
        $DOCKER_CMD run --rm -v "$(realpath "$OUTPUT_DIR")":/download "$IMAGE" bash -c \
            "apt-get update && apt-get install -y --download-only $PACKAGES && cp /var/cache/apt/archives/*.deb /download/"
        ;;
    *)
        echo "Error: Supported targets are $SUPPORTED_TARGETS"
        exit 1
        ;;
esac

# --- 4. Permissions & Empty Check ---
sudo chown -R $USER:$USER "$OUTPUT_DIR"

if [ -z "$(ls -A "$OUTPUT_DIR")" ]; then
    echo "Error: No packages were downloaded. Check your target or package names."
    exit 1
fi

# --- 5. Transfer & Remote Installation ---
if [[ -n "$REMOTE_LOC" ]]; then
    echo "--> Transferring packages to $REMOTE_LOC..."
    REMOTE_HOST=$(echo "$REMOTE_LOC" | cut -d: -f1)
    REMOTE_PATH=$(echo "$REMOTE_LOC" | cut -d: -f2)

    ssh "$REMOTE_HOST" "mkdir -p $REMOTE_PATH"
    scp -r "$OUTPUT_DIR"/* "$REMOTE_LOC"

    if [[ "$REMOTE_INSTALL" == "yes" ]]; then
        echo "--> Triggering remote installation..."
        if [[ "$TARGET_OS" == *"ubuntu"* ]]; then
             ssh -t "$REMOTE_HOST" "sudo dpkg -i $REMOTE_PATH/*.deb || sudo apt-get install -f -y"
        else
             ssh -t "$REMOTE_HOST" "sudo dnf localinstall -y --disablerepo='*' $REMOTE_PATH/epel-release*.rpm 2>/dev/null; sudo dnf localinstall -y --disablerepo='*' $REMOTE_PATH/*.rpm"
        fi
    fi
fi

echo "Done! Local files are in: $OUTPUT_DIR"
