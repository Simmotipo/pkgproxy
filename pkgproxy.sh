#!/bin/bash

# --- Default Values ---
TARGET_OS=""
OUTPUT_DIR="./packages"
REMOTE_LOC=""
REMOTE_INSTALL="no"
REMOTE_KEY=""
LIST_ONLY="no"
PRERUN_SCRIPT=""
PACKAGES=""
KEEP_LOCAL="no" # New default
SUPPORTED_TARGETS="rocky8, rocky9, rocky10, rhel8, rhel9, rhel10, oracle9, ubuntu20, ubuntu22, ubuntu24"

# --- Help Function ---
show_help() {
    echo "Usage: pkgproxy --target=<distro> [options] <package1> [package2 ...]"
    echo ""
    echo "Options:"
    echo "  --target=<distro>        Specify the target OS (Required)"
    echo "  --output=<path>          Local directory for downloads (Default: ./packages)"
    echo "  --remotelocation=<loc>   Remote destination (e.g., user@ip:/path)"
    echo "  --remotekey=<path>       Path to SSH private key for remote transfer/install"
    echo "  --remoteinstall          Trigger installation on the remote host after transfer (requires --remotelocation to be specified)"
    echo "  --keeplocal              Keep downloaded packages locally after remote install (Default: delete if remoteinstall used)"
    echo "  --listonly               Show dependencies without downloading"
    echo "  --prerun=<path>          Local script to run inside container before download"
    echo "  --help                   Display this help message"
    echo ""
    echo "Supported Targets:"
    echo "  $SUPPORTED_TARGETS"
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
        --remotekey=*) REMOTE_KEY="${1#*=}"; shift ;;
        --remoteinstall) REMOTE_INSTALL="yes"; shift ;;
        --keeplocal) KEEP_LOCAL="yes"; shift ;; # Parse new flag
        --listonly) LIST_ONLY="yes"; shift ;;
        --prerun=*) PRERUN_SCRIPT="${1#*=}"; shift ;;
        -*) echo "Unknown option: $1. Use --help for usage."; exit 1 ;;
        *) PACKAGES="$PACKAGES $1"; shift ;;
    esac
done

# Validation
if [[ -z "$TARGET_OS" || -z "$PACKAGES" ]]; then
    echo "Error: Missing required arguments. Use --help for full syntax."
    exit 1
fi

if [[ -n "$REMOTE_KEY" && ! -f "$REMOTE_KEY" ]]; then
    echo "Error: SSH key not found at $REMOTE_KEY"
    exit 1
fi

if [[ -n "$PRERUN_SCRIPT" && ! -f "$PRERUN_SCRIPT" ]]; then
    echo "Error: Prerun script not found at $PRERUN_SCRIPT"
    exit 1
fi

TARGET_OS=$(echo "$TARGET_OS" | tr '[:upper:]' '[:lower:]')

# --- 2. SSH Option Prep ---
SSH_OPTS=""
if [[ -n "$REMOTE_KEY" ]]; then
    SSH_OPTS="-i $REMOTE_KEY"
fi

# --- 3. Docker Check & Auto-Install ---
if ! command -v docker &> /dev/null; then
    echo "Docker not found. Installing..."
    curl -fsSL https://get.docker.com -o get-docker.sh
    sudo sh get-docker.sh && rm get-docker.sh
    DOCKER_CMD="sudo docker"
else
    DOCKER_CMD="docker"
fi

# --- 4. Prep Docker Execution Command ---
DOCKER_VOLUMES="-v $(realpath "$OUTPUT_DIR"):/download"
PRERUN_CMD=""

if [[ -n "$PRERUN_SCRIPT" ]]; then
    DOCKER_VOLUMES="$DOCKER_VOLUMES -v $(realpath "$PRERUN_SCRIPT"):/prerun.sh:ro"
    PRERUN_CMD="bash /prerun.sh && "
fi

# --- 5. Execution Logic ---
case "$TARGET_OS" in
    rocky8|rocky9|rocky10|rhel8|rhel9|rhel10|oracle9)
        if [[ "$TARGET_OS" == "oracle9" ]]; then IMAGE="oraclelinux:9"
        else IMAGE="rockylinux:${TARGET_OS//[!0-9]/}"; fi

        EPEL_PREP=""
        if [[ $PACKAGES == *"epel-release"* ]]; then EPEL_PREP="dnf install -y epel-release && "; fi

        if [[ "$LIST_ONLY" == "yes" ]]; then
            echo "--> Listing dependencies for $PACKAGES on $TARGET_OS..."
            $DOCKER_CMD run --rm $DOCKER_VOLUMES "$IMAGE" bash -c "${PRERUN_CMD}${EPEL_PREP}dnf install -y dnf-plugins-core &>/dev/null && dnf repoquery --requires --resolve --recursive $PACKAGES"
            exit 0
        fi

        mkdir -p "$OUTPUT_DIR"
        echo "--> Fetching RPMs for $TARGET_OS..."
        $DOCKER_CMD run --rm $DOCKER_VOLUMES "$IMAGE" bash -c \
            "${PRERUN_CMD}${EPEL_PREP}dnf install -y dnf-plugins-core && dnf download --resolve --destdir=/download $PACKAGES"
        ;;
    ubuntu20|ubuntu22|ubuntu24)
        VERSION="${TARGET_OS//[!0-9]/}.04"
        IMAGE="ubuntu:$VERSION"

        if [[ "$LIST_ONLY" == "yes" ]]; then
            echo "--> Listing dependencies for $PACKAGES on $TARGET_OS ($VERSION)..."
            $DOCKER_CMD run --rm $DOCKER_VOLUMES "$IMAGE" bash -c "${PRERUN_CMD}apt-get update &>/dev/null && apt-get install --simulate $PACKAGES | grep '^Inst'"
            exit 0
        fi

        mkdir -p "$OUTPUT_DIR"
        echo "--> Fetching DEBs for $TARGET_OS ($VERSION)..."
        $DOCKER_CMD run --rm $DOCKER_VOLUMES "$IMAGE" bash -c \
            "${PRERUN_CMD}apt-get update && apt-get install -y --download-only $PACKAGES && cp /var/cache/apt/archives/*.deb /download/"
        ;;
    *)
        echo "Error: Supported targets are $SUPPORTED_TARGETS"
        exit 1
        ;;
esac

# --- 6. Permissions & Empty Check ---
sudo chown -R $USER:$USER "$OUTPUT_DIR"

if [ -z "$(ls -A "$OUTPUT_DIR")" ]; then
    echo "Error: No packages were downloaded."
    exit 1
fi

# --- 7. Transfer & Remote Installation ---
INSTALL_SUCCESS="no"
if [[ -n "$REMOTE_LOC" ]]; then
    echo "--> Transferring packages to $REMOTE_LOC..."
    REMOTE_HOST=$(echo "$REMOTE_LOC" | cut -d: -f1)
    REMOTE_PATH=$(echo "$REMOTE_LOC" | cut -d: -f2)

    ssh $SSH_OPTS "$REMOTE_HOST" "mkdir -p $REMOTE_PATH"
    scp $SSH_OPTS -r "$OUTPUT_DIR"/* "$REMOTE_LOC"

    if [[ "$REMOTE_INSTALL" == "yes" ]]; then
        echo "--> Triggering remote installation..."
        if [[ "$TARGET_OS" == *"ubuntu"* ]]; then
             ssh $SSH_OPTS -t "$REMOTE_HOST" "sudo dpkg -i $REMOTE_PATH/*.deb || sudo apt-get install -f -y" && INSTALL_SUCCESS="yes"
        else
             ssh $SSH_OPTS -t "$REMOTE_HOST" "sudo dnf localinstall -y --disablerepo='*' $REMOTE_PATH/epel-release*.rpm 2>/dev/null; sudo dnf localinstall -y --disablerepo='*' $REMOTE_PATH/*.rpm" && INSTALL_SUCCESS="yes"
        fi
    fi
fi

# --- 8. Cleanup ---
if [[ "$REMOTE_INSTALL" == "yes" && "$INSTALL_SUCCESS" == "yes" && "$KEEP_LOCAL" == "no" ]]; then
    echo "--> Cleaning up local packages in $OUTPUT_DIR..."
    rm -rf "$OUTPUT_DIR"
    echo "Done! Local files removed (use --keeplocal to prevent this)."
else
    echo "Done! Local files are in: $OUTPUT_DIR"
fi
