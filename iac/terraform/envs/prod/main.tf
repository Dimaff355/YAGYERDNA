terraform {
  required_version = ">= 1.6.0"

  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = ">= 0.60.0"
    }
  }

  # State: local на старте; при появлении S3 — перенести (см. backend.tf.example)
}

# Токен Proxmox API — из OpenBao/ENV, не из репы:
#   export TF_VAR_proxmox_api_token="root@pam!tofu=xxxxxxxx"
provider "proxmox" {
  endpoint  = var.proxmox_endpoint
  api_token = var.proxmox_api_token
  insecure  = true # самоподписанный cert на старте; заменить на свой PKI
}

variable "proxmox_endpoint"  { type = string }
variable "proxmox_api_token" { type = string, sensitive = true }
variable "ssh_public_key"    { type = string }

# Инфраструктурные ВМ (docs/09-software-stack.md)
locals {
  infra_vms = {
    zabbix-01    = { vm_id = 111, ip = "10.10.30.11/24", cores = 4,  memory_mb = 8192,  disk_gb = 80,  tags = ["monitoring"] }
    glpi-01      = { vm_id = 112, ip = "10.10.30.12/24", cores = 4,  memory_mb = 8192,  disk_gb = 80,  tags = ["itam", "helpdesk"] }
    nextcloud-01 = { vm_id = 113, ip = "10.10.30.13/24", cores = 8,  memory_mb = 16384, disk_gb = 200, tags = ["files"] }
    keycloak-01  = { vm_id = 114, ip = "10.10.30.14/24", cores = 2,  memory_mb = 4096,  disk_gb = 40,  tags = ["sso"] }
    gitlab-01    = { vm_id = 115, ip = "10.10.30.15/24", cores = 8,  memory_mb = 16384, disk_gb = 200, tags = ["git", "ci"] }
    awx-01       = { vm_id = 116, ip = "10.10.30.16/24", cores = 4,  memory_mb = 8192,  disk_gb = 80,  tags = ["iac"] }
    mikopbx-01   = { vm_id = 117, ip = "10.10.40.11/24", cores = 4,  memory_mb = 8192,  disk_gb = 120, tags = ["voice", "ha-pair"] }
    mikopbx-02   = { vm_id = 118, ip = "10.10.40.12/24", cores = 4,  memory_mb = 8192,  disk_gb = 120, tags = ["voice", "ha-pair"] }
  }
}

module "infra_vm" {
  for_each = local.infra_vms
  source   = "../../modules/proxmox_vm"

  vm_name        = each.key
  vm_id          = each.value.vm_id
  target_node    = "pve-01" # TODO: раскидать по нодам кластера round-robin
  vm_template_id = 9000
  datastore      = "ceph-rbd"

  cores     = each.value.cores
  memory_mb = each.value.memory_mb
  disk_gb   = each.value.disk_gb
  tags      = each.value.tags

  ip_address     = each.value.ip
  gateway        = cidrhost(each.value.ip, 1)
  ssh_public_key = var.ssh_public_key
}

output "infra_vms" {
  value = { for k, m in module.infra_vm : k => m.vm_id }
}
