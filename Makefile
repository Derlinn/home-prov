# Terraform Makefile – simplifie les commandes de base
# Utilise terraform.tfvars.example par défaut, surcharge avec TFVARS=<fichier>

TFVARS ?= terraform.tfvars

templates:
	/bin/bash ./templates.sh debian-13 ubuntu-noble alpine-3.22

init:
	terraform init

validate:
	terraform validate

fmt:
	terraform fmt -recursive

plan:
	terraform plan -var-file=$(TFVARS)

apply:
	terraform apply -var-file=$(TFVARS) -auto-approve

destroy:
	terraform destroy -var-file=$(TFVARS) -auto-approve

clean:
	rm -rf .terraform *.tfstate* .terraform.lock.hcl
