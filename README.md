# pkgproxy
Utility to use Docker to download packages for a target OS, and (optionally) SCP them to a remote host that oes not have internet access. (Largely vibecoded lol)

Usage: pkgproxy --target=<distro> [options] <package1> [package2 ...]

Options:
  --target=<distro>        Specify the target OS (Required)
  --output=<path>          Local directory for downloads (Default: ./packages)
  --remotelocation=<loc>   Remote destination (e.g., user@ip:/path) (requires --remotelocation to be specified)
  --remoteinstall          Trigger installation on the remote host after transfer
  --listonly               Show dependencies without downloading
  --help                   Display this help message

Supported Targets:
  rocky8, rocky9, rocky10, rhel8, rhel9, rhel10, oracle9, ubuntu20, ubuntu22, ubuntu24

Example:
  getpkgs --target=rocky10 --remotelocation=root@192.168.3.5:/root --remoteinstall epel-release htop
