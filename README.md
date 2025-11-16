# LINDERIS HomeLab Infrastructure

This repository contains the Infrastructure as Code (IaC) for managing my homelab environment running on Proxmox VE. It uses Terraform with the **bpg/proxmox** provider to provision and maintain virtual machines through template cloning and cloud-init configuration.

## Infrastructure Overview

- **Host**: LIN-PRC-01 (Proxmox VE host)
- **Deployment Method**: Terraform + Cloud-Init
- **Network**: Managed through Proxmox bridges
- **Storage**: Templates and VM disks stored on configured Proxmox datastores

## VM Template Management

### Template Requirements

Templates used for VM deployment must:
- Be properly configured with cloud-init
- Have QEMU guest agent installed
- Have SSH server configured
- Use a minimal OS installation
- Support network configuration via cloud-init
- Be tagged appropriately for Terraform selection

> TODO: Document the actual template creation/management process used in this infrastructure

## Terraform Deployment

1. Prepare authentication:
```bash
export PROXMOX_VE_API_TOKEN='user@pve!token=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx'
eval "$(ssh-agent)"; ssh-add ~/.ssh/id_ed25519
```

2. Configure your VMs in terraform.tfvars:
```hcl
vms = {
  "web01" = {
    template_tags = ["ubuntu", "jammy"]
    cpu = 2
    mem_mb = 2048
    disk_gb = 32
    ip_cidr = "192.168.1.10/24"
  }
  # Add more VMs as needed
}
```

3. Apply the configuration:
```bash
terraform init
terraform plan
terraform apply
```

## Repository Structure

```
.
├── modules/
│   └── proxmox-vm/       # VM module with cloud-init support
├── templates.sh          # Template management script
├── main.tf              # Main Terraform configuration
├── variables.tf         # Variable definitions
├── terraform.tfvars     # VM configurations (gitignored)
└── outputs.tf           # Output definitions
```

## Pre-commit Hooks & Security

Install pre-commit:
```bash
pipx install pre-commit
pre-commit install
```

Security best practices:
- Keep terraform.tfvars out of git
- Use environment variables for sensitive data
- Store SSH keys securely
- Use tagged templates for consistency

## License
No License

## TO ADD TO README
terraform workspace new prod
