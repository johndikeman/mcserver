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

## 2. Port forwarding on the router (Spectrum)

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

### Home IP changes (DDNS)

Residential IPs change every so often. Easiest fix: set up a free DDNS
hostname so John always reaches the box. Two easy options:

- Many Spectrum routers have a built-in **DDNS** page (No-IP or DynDNS) —
  create a free account at noip.com, add a hostname, enter creds in the
  router.
- Or we can handle it in NixOS after the install (a tiny `ddclient`
  service) — tell John you'd prefer that and he'll set it up.

Once forwarded, test from a phone on cellular: try connecting to your
public IP (whatismyip.com) on port 22 / the MC port.

## 3. What happens next

John will run `nixos-anywhere` over SSH, which **wipes the disk and
installs NixOS** with the Minecraft server config. After that:

- SSH access is via John's key baked into the NixOS config (your account
  config above becomes irrelevant; John will make sure you still have
  access on the NixOS side if you want it — send him a public key).
- The Minecraft server runs as a systemd service, auto-restarts, and
  backs up the world hourly.
- John deploys updates remotely with `deploy-rs`; you shouldn't need to
  touch anything.

One thing John needs from you:

- [ ] confirmation John's key works (before password auth is disabled)
- [ ] server's LAN IP (and whether you reserved it)
- [ ] which external SSH port you chose (if not 22)
- [ ] your public IP or a DDNS hostname
- [ ] the disk the OS should go on (John will confirm before wiping)