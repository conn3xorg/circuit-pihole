variable "port" {
  type    = number
  default = 2222
}

variable "web_password" {
  type      = string
  default   = "correct-horse-battery"
  ephemeral = true
}

# CI sets these to install an older release first, then upgrades to the
# circuit's own pin by applying again without them.
variable "pihole_version" {
  type    = string
  default = null
}

variable "image_digest" {
  type    = string
  default = null
}

module "pihole" {
  source = "../.."

  hosts                = { box = "127.0.0.1" }
  ssh_port             = var.port
  ssh_private_key_file = "./id_ed25519"
  ssh_known_hosts_file = "./known_hosts"
  pihole_version       = var.pihole_version
  image_digest         = var.image_digest

  web_password = var.web_password
  upstream_dns = ["1.1.1.1", "9.9.9.9"]
  web_port     = "8080"

  blocklists = ["https://raw.githubusercontent.com/hagezi/dns-blocklists/main/adblock/light.txt"]
  local_dns_records = {
    "nas.home.arpa"     = "192.168.1.20"
    "printer.home.arpa" = "192.168.1.21"
  }
}
