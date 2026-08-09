# my-network LXC

Simple Proxmox LXC installer for [my-network](https://github.com/VRB95/my-network).

It creates a Debian 13 LXC, builds myNetwork from source, configures a systemd service, and installs a one-command updater.

## Install

Run this on the **Proxmox host** as `root`:

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/VRB95/my-network-lxc/main/create.sh)"
```

The installer asks for VMID, hostname, storage, disk size, CPU, RAM, swap, and network bridge.

After installation, open:

```text
http://LXC-IP:8840
```

In myNetwork, set the scan interface to:

```text
eth0
```

## Update

Enter the LXC:

```bash
pct enter <VMID>
```

Then run:

```bash
mynetwork-update
```

or 

```bash
/usr/local/sbin/mynetwork-update
```

The updater fetches the latest `main` branch and builds the new frontend/backend while the current service is still running. The live service is stopped only after the new build succeeds.

If the new version fails to start, the previous binary is restored automatically.

## Useful commands

```bash
systemctl status mynetwork
journalctl -u mynetwork -f
systemctl restart mynetwork
```

Application data:

```text
/data/myNetwork
```

Source code:

```text
/opt/mynetwork
```

## Scripts

- `create.sh` — run on the Proxmox host; creates the LXC and launches the installer.
- `install.sh` — runs inside the new LXC; installs dependencies, builds myNetwork, and creates the systemd service.
- `update.sh` — installed inside the LXC as `mynetwork-update`.

## Requirements

- Proxmox VE
- Internet access on the Proxmox host and inside the LXC
- DHCP on the selected bridge
- Debian 13 LXC template (downloaded automatically if missing)

## Uninstall

Run on the Proxmox host:

```bash
pct stop <VMID>
pct destroy <VMID>
```

This permanently deletes the container and its data.
