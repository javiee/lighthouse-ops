{ config, pkgs, ... }:
## Bootstrap fluxcd 

let
    fluxOwner = "javiee";
    fluxRepo = "lighthouse-ops";
    fluxBranch = "main";
    fluxPath = "gitops/lighthouse-cluster";
in

{
    age.secrets.github-token.file = ../../secrets/github-token.age;
    environment.systemPackages = with pkgs; [ fluxcd ]; 
    systemd.services.flux-bootstrap = {
        description = "Bootstrap FluxCD on this machine after kubernetes installation";
        wantedBy = [ "multi-user.target" ];
        after = ["k3s.service" "network-online.target"];
        wants = [ "network-online.target" ];
        unitConfig.ConditionPathExists = "!/var/lib/flux/.bootstrapped";
        serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
            StateDirectory = "flux";  
       };
       path = with pkgs; [ fluxcd kubectl coreutils ];
        script = ''
          set -euo pipefail
          export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

          for i in $(seq 1 60); do
            if kubectl get --raw=/readyz >/dev/null 2>&1; then
              echo "Kubernetes API is available after $((i * 5)) seconds"
              break
            fi
            sleep 5
          done

          export GITHUB_TOKEN=$(cat ${config.age.secrets.github-token.path})
          flux bootstrap github \
            --owner=${fluxOwner} \
            --repository=${fluxRepo} \
            --branch=${fluxBranch} \
            --path=${fluxPath} \
            --personal

          touch /var/lib/flux/.bootstrapped
        '';
    };

}