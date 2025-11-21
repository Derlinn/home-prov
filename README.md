# LINDERIS HomeLab Infrastructure

Infrastructure-as-Code for a Proxmox-based homelab. The stack relies on Terraform (with the bpg/proxmox provider), cloud-init, Ansible inventory generation, and an optional Talos/Kubernetes layer.

## What’s inside
- Terraform environments for `production` and `pre-production` under `terraform/envs/`
- Reusable modules: `terraform/modules/proxmox-vm` (VMs) and `terraform/modules/proxmox-talos` (Talos cluster bootstrap)
- Kubernetes manifests and values under `kubernetes/`
- Ansible inventories generated from Terraform outputs under `ansible/`
- Taskfile-based workflow automation and a script to build Proxmox VM templates

## Tooling & prerequisites
- Proxmox CLI tools available on the host running Terraform (`qm`, `pvesm`, `pvesh`)
- Terraform + Task (`task`) installed locally
- `virt-customize` and `wget` available on the Proxmox host for template builds (`libguestfs-tools`)
- SSH key added to your agent for Proxmox access
- Optional: [`mise`](https://github.com/jdx/mise) to load the project environment (see below)

## Environment management with mise
The repo ships `.mise.toml`, which:
- Creates a Python virtualenv in `.venv` when needed
- Exposes `NODE_ENV` (default `pre-production`) and maps `KUBECONFIG` to the matching Terraform env output: `./terraform/envs/{{env.NODE_ENV}}/output/kube-config.yaml`

Usage example:
```bash
mise shell               # activate direnv-style shell
echo $KUBECONFIG         # points to the current environment kubeconfig
```

## Automations via Taskfile
Common workflows are wrapped in `Taskfile.yml`:
- `task templates` — generate Proxmox VM templates (delegates to `scripts/templates.sh`)
- `task init|validate|fmt|plan|apply|destroy|clean` — Terraform helpers. Override `TF_DIR` to pick an environment (default `./terraform`) and `TFVARS` to target the correct tfvars file.

Examples:
```bash
# Work in pre-production
task init TF_DIR=./terraform/envs/pre-production
task plan TF_DIR=./terraform/envs/pre-production TFVARS=terraform.tfvars
task apply TF_DIR=./terraform/envs/pre-production TFVARS=terraform.tfvars
```

## Building VM templates (Proxmox)
`scripts/templates.sh` builds cloud-init ready templates on the Proxmox host. Allowed images today: `debian-13`, `ubuntu-noble`, `alpine-3.22`.

Run directly or through Task:
```bash
# direct
bash ./scripts/templates.sh debian-13 ubuntu-noble

# via task wrapper
task templates
```
The script verifies the target storage, injects `qemu-guest-agent`, resizes disks, and tags the templates (`template,cloud,<distro>`).

## Terraform layout & environments
- Each environment lives in `terraform/envs/<env>/` with its own state file and `terraform.tfvars`.
- Core VM provisioning is handled by `modules/proxmox-vm`.
- Terraform renders Ansible inventories to `ansible/inventories/<env>.yml` once IPs are known.

Workflow per environment:
```bash
export PROXMOX_VE_API_TOKEN='user@pve!token=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx'
eval "$(ssh-agent)"; ssh-add ~/.ssh/id_ed25519

cd terraform/envs/pre-production        # or production
terraform init
terraform plan -var-file=terraform.tfvars
terraform apply -var-file=terraform.tfvars
```

## Talos module
To bootstrap a Talos cluster, populate `talos_nodes` (and optional `cluster`) in the environment `terraform.tfvars`. When nodes are defined, `modules/proxmox-talos` is enabled and:
- Downloads the Talos image (version sourced from `cluster.talos_version`)
- Applies inline Cilium manifests (`kubernetes/cilium/values.yaml`)
- Emits `kube-config.yaml` into `terraform/envs/<env>/output/`

## Moving VMs between environments
See `terraform/README.md` for a step-by-step state move guide (pre-production → production) without recreating VMs.

## TODO
- Doc: SOPS / CILIUM / Flux
- Task (taskfile): Move VM from one env to another through taskfile
- Terraform: Upgrade k8s, provision MikroTik router
- Ansible: Role pterodactyl, tailscale

## Inspiration & credits
- Talos + Proxmox workflows inspired by Vegard Hagen’s article: https://gitlab.com/vehagn/blog/-/tree/main/content/articles/2024/08/talos-proxmox-tofu/resources
- Kubernetes cluster template ideas from onedr0p: https://github.com/onedr0p/cluster-template

## License
No License
