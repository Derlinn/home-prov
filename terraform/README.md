## Moving a VM Between Environments (preprod → prod)

# Talos module is made with this repository https://gitlab.com/vehagn/blog/-/tree/main/content/articles/2024/08/talos-proxmox-tofu by Vegard Hagen

This project keeps one Terraform state per environment.
To move an existing VM from preprod to prod without recreating it, follow this procedure.

1) Move the VM state

Run this from the Terraform root directory:

```bash
terraform state mv \
  -state=envs/preprod-vms/terraform.tfstate \
  -state-out=envs/prod-vms/terraform.tfstate \
  'module.vm["my-vm-name"]' \
  'module.vm["my-vm-name"]'
```

```bash
VM="test";  RESOURCES=(data.proxmox_virtual_environment_vms.template proxmox_virtual_environment_file.cloud_meta_config proxmox_virtual_environment_file.cloud_user_config proxmox_virtual_environment_vm.this); for res_type in "${RESOURCES[@]}"; do terraform state mv -state=envs/preprod-vms/terraform.tfstate -state-out=envs/prod-vms/terraform.tfstate "module.vm.$res_type[\"$VM\"]" "module.vm.$res_type[\"$VM\"]"; done
```

This moves the VM’s Terraform state without touching the real VM in Proxmox.

2) Verify the move

Preprod (old environment):
```bash
cd envs/preprod-vms
terraform state list | grep my-vm-name
```
(no result expected)

Prod (new environment):
```bash
cd envs/prod-vms
terraform state list | grep my-vm-name
```
The VM should now appear here.

3) Remove VM vars from the previous environment

Edit: envs/preprod-vms/terraform.tfvars
Remove the VM block entirely:

```hcl
vms = {
  # remove: "my-vm-name" = { ... }
}
```

4) Add VM vars to the new environment

Edit: envs/prod-vms/terraform.tfvars
Add the VM block with the same vm_id:

```hcl
vms = {
  "my-vm-name" = {
    cpu           = 1
    mem_mb        = 1024
    disk_gb       = 50
    vm_id         = 1000     # same Proxmox VM ID
    domain        = "linderis.fr"
    ci_user       = "ansible"
    ip_cidr       = "dhcp"
    gw_ip         = null
    ssh_pubkey    = null
    tags          = ["terraform", "prod"]
    template_tags = ["template", "debian-13"]
  }
}
```

5) Sync the new environment

```bash
cd envs/prod-vms
terraform plan
terraform apply
```

Terraform will recreate snippet files if needed and fully adopt the VM in the new environment.

Result:
The VM is now managed by the prod environment without being destroyed or recreated.
