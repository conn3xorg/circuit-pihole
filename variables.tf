variable "hosts" {
  type        = any
  description = "Hosts to configure: a map of names to addresses, or to host objects with an address and optional host_key, user, port, private_key_file or jump_hosts."
}

variable "ssh_user" {
  type        = string
  default     = "root"
  description = "User to log in as."
}

variable "ssh_port" {
  type        = number
  default     = 22
  description = "SSH port."
}

variable "ssh_private_key_file" {
  type        = string
  default     = null
  description = "Path to a private key. When null, Conn3x uses the SSH agent."
}

variable "ssh_known_hosts_file" {
  type        = string
  default     = null
  description = "known_hosts file to check host keys against. When null, ~/.ssh/known_hosts."
}

variable "ssh_become" {
  type        = bool
  default     = false
  description = "Run commands as root through sudo."
}
variable "pihole_version" {
  type        = string
  default     = "2026.10.0"
  description = "Tag of the docker.io/pihole/pihole image, such as \"2026.10.0\". Each tag pins Pi-hole's core, web interface and FTL together."

  validation {
    condition     = can(regex("^[A-Za-z0-9_][A-Za-z0-9_.-]*$", var.pihole_version))
    error_message = "pihole_version must be an image tag, such as \"2026.10.0\"."
  }
}

variable "web_password" {
  type        = string
  ephemeral   = true
  sensitive   = true
  description = "Password for the web interface and the API. It reaches the host in a root-only file and never the plan or state."

  validation {
    condition     = length(var.web_password) >= 8 && !strcontains(var.web_password, "\n")
    error_message = "web_password must be at least 8 characters on one line."
  }
}

variable "upstream_dns" {
  type        = list(string)
  default     = ["9.9.9.9", "149.112.112.112"]
  description = "DNS servers Pi-hole forwards allowed queries to, as addresses, optionally with #port, such as [\"192.168.1.1\", \"127.0.0.1#5335\"]. The default is Quad9."

  validation {
    condition = length(var.upstream_dns) > 0 && alltrue([for s in var.upstream_dns : can(regex("^[^#]+(#[0-9]{1,5})?$", s)) && can(cidrhost(
      "${split("#", s)[0]}/${strcontains(s, ":") ? 128 : 32}", 0
    ))])
    error_message = "Each of upstream_dns must be an IPv4 or IPv6 address, optionally with #port, such as \"1.1.1.1\" or \"127.0.0.1#5335\"."
  }
}

variable "listening_mode" {
  type        = string
  default     = "LOCAL"
  description = "Which queries Pi-hole answers: LOCAL (devices on the host's own subnets), SINGLE (only those arriving on interface), BIND (binds to interface only), ALL (anyone who can reach port 53) or NONE."

  validation {
    condition     = contains(["LOCAL", "SINGLE", "BIND", "ALL", "NONE"], var.listening_mode)
    error_message = "listening_mode must be one of LOCAL, SINGLE, BIND, ALL or NONE."
  }
}

variable "interface" {
  type        = string
  default     = null
  description = "Network interface for SINGLE and BIND, such as \"eth0\". When null, Pi-hole picks the interface of the default route."

  validation {
    condition     = var.interface == null || can(regex("^[A-Za-z0-9_.@-]{1,15}$", coalesce(var.interface, "-")))
    error_message = "interface must be a network interface name, such as \"eth0\"."
  }
}

variable "blocklists" {
  type        = list(string)
  default     = []
  description = "Blocklist URLs to add next to Pi-hole's default list, such as [\"https://big.oisd.nl\"]."

  validation {
    condition     = alltrue([for u in var.blocklists : can(regex("^https?://[^\\s'\"`$\\\\]+$", u))])
    error_message = "Each of blocklists must be an http or https URL without spaces, quotes, backticks, $ or backslashes."
  }
}

variable "local_dns_records" {
  type        = map(string)
  default     = {}
  description = "Local DNS records, names to IP addresses, such as { \"nas.home.arpa\" = \"192.168.1.20\" }."

  validation {
    condition     = alltrue([for name in keys(var.local_dns_records) : can(regex("^[A-Za-z0-9]([A-Za-z0-9.-]*[A-Za-z0-9])?$", name))])
    error_message = "Each name in local_dns_records must be a host name, such as \"nas.home.arpa\"."
  }

  validation {
    condition     = alltrue([for ip in values(var.local_dns_records) : can(cidrhost("${ip}/${strcontains(ip, ":") ? 128 : 32}", 0))])
    error_message = "Each value in local_dns_records must be an IPv4 or IPv6 address."
  }
}

variable "web_port" {
  type        = string
  default     = null
  description = "Where the web interface listens, in Pi-hole's webserver.port syntax, such as \"8080\" or \"127.0.0.1:8080\". When null, Pi-hole's default: 80 and 443 with a self-signed certificate."

  validation {
    condition     = var.web_port == null || can(regex("^[A-Za-z0-9.:,\\[\\]+]+$", coalesce(var.web_port, "-")))
    error_message = "web_port takes Pi-hole's webserver.port syntax, such as \"8080\", \"127.0.0.1:8080\" or \"80o,443os\"."
  }
}
