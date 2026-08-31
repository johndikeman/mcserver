# Placeholder hardware configuration, replaced by nixos-anywhere during
# installation (same pattern as the official nixos-anywhere-examples repo).
#
#   nixos-anywhere \
#     --generate-hardware-config nixos-generate-config ./hardware-configuration.nix \
#     --flake .#mcserver --target-host root@<ip>
#
# Intentionally throws: this forces you to pass --generate-hardware-config so
# the real hardware detection runs, instead of silently installing without it.
throw "Have you forgotten to run nixos-anywhere with `--generate-hardware-config nixos-generate-config ./hardware-configuration.nix`?"
