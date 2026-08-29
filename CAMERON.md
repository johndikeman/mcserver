# Instructions for Cameron

Thanks for hosting! This walks you through: (1) giving John SSH access,
(2) locking down SSH, and (3) opening ports on your router so John can
administer the machine and friends can reach the Minecraft server.

After this, John will remotely wipe Ubuntu and install NixOS on the box
with `nixos-anywhere` — **anything currently on the disk will be erased**,
so copy off anything you care about first.

---

## 1. Add John's SSH key and disable password logins

SSH into the server (from your LAN: `ssh <youruser>@<server-ip>`), then:

```bash
# Give John's key access to YOUR account (we'll set up his NixOS user later)
mkdir -p ~/.ssh && chmod 700 ~/.ssh
echo "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPSviMIGIHceQvktPkuIWUdQlpeAhNOLq+7i6Bmc/qSF jrobdikeman@gmail.com" >> ~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys
```

**Before locking down SSH**, open a *second* terminal and confirm John's
key actually works (`ssh <youruser>@<server-ip>` from John's machine).
Never close your working session until you've verified new auth works.

Then edit the sshd config:

```bash
sudo nano /etc/ssh/sshd_config
```

Find/set these lines:

```
PasswordAuthentication no
KbdInteractiveAuthentication no
ChallengeResponseAuthentication no
PubkeyAuthentication yes
PermitRootLogin prohibit-password
```

Then restart sshd:

```bash
sudo systemctl restart ssh
```

Re-test login from the other terminal (and that you can still get in).
⚠️ If you get locked out, most distros keep `sshd_config.d/` overrides —
check `sudo grep -r PasswordAuthentication /etc/ssh/sshd_config.d/` too.

## 2. Finding the name of the disk

The installer is going to wipe exactly one disk, so we need its device
name. SSH into the server and run:

```bash
lsblk -o NAME,SIZE,MODEL,TYPE,MOUNTPOINTS
```

You'll see something like:

```
NAME        SIZE MODEL            TYPE MOUNTPOINTS
nvme0n1   476.9G Samsung SSD 970  disk
├─nvme0n1p1   1G                  part /boot/efi
├─nvme0n1p2 100G                  part /
└─nvme0n1p3 375G                  part /home
sda         931.5G WDC WD10EZEX     disk
```

The disk we want is the line with `TYPE = disk` that **has the root
(`/`) partition under it** — in the example above that's `nvme0n1` (not
`sda`, which is a spare data drive, and not the `part` lines, which are
partitions *on* the disk).

Note down:
- the **name** (`nvme0n1` or `sda` — NVMe drives start with `nvme`, SATA drives are `sda`, `sdb`, ...)
- the **size and model**, so we can sanity-check it's the right drive

If it's ambiguous (multiple disks, or nothing mounted at `/`), send John
the full `lsblk` output plus:

```bash
ls -l /dev/disk/by-id/ | grep -v part
```

Those `by-id` names (e.g. `nvme-Samsung_SSD_970_ABC123`) include the
serial number — that's what we'll actually put in the config, since it
points at one specific physical drive and can't be confused with another.

**John will confirm the disk with you before wiping anything.**

## 3. Port forwarding on the router (Spectrum)

Spectrum home internet puts you behind CGNAT-ish gear, but with their
router (or your own router on a Spectrum connection):

1. Find the server's LAN IP: `ip addr` — note it, e.g. `192.168.1.50`.
   Better: reserve it as a static DHCP lease in the router admin panel.
2. Log into the router admin page — usually `http://192.168.1.1`
   (Spectrum/Charter routers often use `admin` / the password printed on
   the router sticker).
3. Find **Port Forwarding** (sometimes under Advanced / NAT / Gaming).
4. Add two rules:

| Name        | External port | Internal IP    | Internal port | Protocol |
|-------------|---------------|----------------|---------------|----------|
| SSH         | 22            | 192.168.1.50   | 22            | TCP      |
| Minecraft   | 25565         | 192.168.1.50   | 25565         | TCP      |

(Use the server's actual LAN IP in place of 192.168.1.50. Feel free to
pick a different *external* port for SSH, e.g. 2222 → 22, if you'd rather
not expose 22 — just tell John which one.)

5. Some Spectrum routers have an option like "WiFi Router Mode / Bridge
   mode" — leave normal routing mode on; bridge mode would disable
   port forwarding.

Once forwarded, test from a phone on cellular: try connecting to your
public IP (whatismyip.com) on port 22 / the MC port.

## 4. What happens next

John will run `nixos-anywhere` over SSH, which **wipes the disk and
installs NixOS** with the Minecraft server config. After that:

- SSH access is via John's key baked into the NixOS config (your account
  config above becomes irrelevant; John will make sure you still have
  access on the NixOS side if you want it — send him a public key).
- The Minecraft server runs as a systemd service, auto-restarts, and
  backs up the world hourly.
- A Github Action will re-deploy the server on push to the github repo johndikeman/mcserver.
  

One thing John needs from you:

- [ ] server's LAN IP 
- [ ] which external SSH port you chose (if not 22)
- [ ] your public IP 
- [ ] the disk the OS should go on (see below)

