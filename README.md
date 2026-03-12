# pkgproxy
Utility to use Docker to download packages for a target OS, and (optionally) SCP them to a remote host that does not have internet access. (Largely vibecoded lol)

Usage: pkgproxy --target=<distro> [options] <package1> [package2 ...]

Options:
-  `--target=<distro>      ` Specify the target OS (Required)
-  `--output=<path>        ` Local directory for downloads (Default: ./packages)
-  `--prerun=<path>        `  Local script to run inside container before download
-  `--remotelocation=<loc> ` Remote destination (e.g., user@ip:/path)
-  `--remotekey=<path>     `  Path to SSH private key for remote transfer/install
-  `--remoteinstall        ` Trigger installation on the remote host after transfer (requires presence of --remotelocation)
-  `--listonly             ` Show dependencies without downloading
-  `--help                 ` Display this help message

Supported Targets:
  rocky8, rocky9, rocky10, rhel8, rhel9, rhel10, oracle9, ubuntu20, ubuntu22, ubuntu24

Example:
  getpkgs `--target=rocky10 --remotelocation=root@192.168.3.5:/root --remoteinstall --prerun=add_repos.sh epel-release htop`
