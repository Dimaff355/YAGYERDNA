variable "vm_name"       { type = string }
variable "vm_id"         { type = number }
variable "target_node"   { type = string }
variable "vm_template_id" { type = number }
variable "datastore"     { type = string }
variable "cores"         { type = number, default = 4 }
variable "memory_mb"     { type = number, default = 8192 }
variable "disk_gb"       { type = number, default = 60 }
variable "bridge"        { type = string, default = "vmbr0" }
variable "ip_address"    { type = string }  # напр. "10.10.30.11/24"
variable "gateway"       { type = string, default = "10.10.30.1" }
variable "dns_servers"   { type = list(string), default = ["10.10.30.11", "77.88.8.8"] }
variable "ssh_public_key" { type = string }
variable "tags"          { type = list(string), default = [] }
