let
  # ---------------------------------------------------------------------------
  # Replace these placeholders before running `agenix -e <file>.age`.
  #
  # Your personal age key (lets YOU edit secrets):
  #   age-keygen -o ~/.config/age/keys.txt
  #   age-keygen -y ~/.config/age/keys.txt   # prints the public key
  #
  # Host keys (let each node DECRYPT secrets at activation time).
  # Use the host's existing SSH ed25519 host pubkey — agenix accepts it directly:
  #   ssh-keyscan -t ed25519 <host-or-tailscale-name>
  # ---------------------------------------------------------------------------
  javier = "age12ah4v9zs84xsrkgfv4al0ks3n3f5ggaqvdpzmgtz7pfqwptea5yqdfu3ql";

  lh-satellite = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINYYH9wRSABfQ8nCD3oqY8J3o+ItjX4oL3jTCv7Fi5Ny root@nixos";
  # lh-node-2 = "ssh-ed25519 AAAA...";
  # lh-node-3 = "ssh-ed25519 AAAA...";

  allHosts = [ lh-satellite ];
  allUsers = [ javier ];
in
{
  "k3s-token.age".publicKeys = allUsers ++ allHosts;
  "github-token.age".publicKeys = allUsers ++ allHosts;
}
