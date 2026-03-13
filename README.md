# pkgproxy
Utility to use Docker to download packages for a target OS, and (optionally) SCP them to a remote host that does not have internet access. (Largely vibecoded lol, bash scares me)

Usage: pkgproxy --target=<distro> [options] <package1> [package2 ...]

Options:
-  `--target=<distro>      ` Specify the target OS (Required)
-  `--output=<path>        ` Local directory for downloads (Default: ./packages)
-  `--prerun=<path>        `  Local script to run inside container before download
-  `--remotelocation=<loc> ` Remote destination (e.g., user@ip:/path)
-  `--remotekey=<path>     `  Path to SSH private key for remote transfer/install
-  `--remoteinstall        ` Trigger installation on the remote host after transfer (requires presence of --remotelocation)
-  `--keeplocal            ` Used in conjunction with --remoteinstall: if present, will keep the locally downloaded files after successful remote installation, otherwise, defaults to deleting them.
-  `--listonly             ` Show dependencies without downloading
-  `--installonly          ` Treat the list of packages as paths to package files to transfer and install (rather than re-downloading them)
-  `--help                 ` Display this help message

Supported Targets:
  rocky8, rocky9, rocky10, rhel8, rhel9, rhel10, oracle9, ubuntu20, ubuntu22, ubuntu24

Example, download and install epel-release and htop:
  `pkgproxy --target=rocky9 --remotelocation=root@192.168.3.5:/root --remoteinstall --prerun=add_repos.sh epel-release htop`

Example commands to download once, then install nano across multiple servers...

1. `pkgproxy --target=rocky9 --remotelocation=root@192.168.3.5:/tmp/nano_pkgs/ --remoteinstall --keeplocal --output=./nano_pkgs/ nano`
2. `pkgproxy --target=rocky9 --remotelocation=root@192.168.6.18:/tmp/nano_pkgs/ --remoteinstall --installonly ./nano_pkgs/*`
4. Repeat 2. for as many servers as required!
