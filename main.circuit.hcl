locals {
  # Pi-hole reads any pihole.toml setting from an FTLCONF_section_setting
  # variable, with arrays joined by semicolons. A setting given this way is
  # read-only in the web interface, so the values here can't drift.
  environment = merge(
    {
      FTLCONF_dns_upstreams     = join(";", var.upstream_dns)
      FTLCONF_dns_listeningMode = var.listening_mode
      # Pi-hole's own NTP server and clock sync are on by default. With host
      # networking that would answer NTP for anyone who can reach port 123,
      # and the sync can't set the clock from inside a container anyway.
      FTLCONF_ntp_ipv4_active = "false"
      FTLCONF_ntp_ipv6_active = "false"
      FTLCONF_ntp_sync_active = "false"
    },
    var.interface == null ? {} : { FTLCONF_dns_interface = var.interface },
    var.web_port == null ? {} : { FTLCONF_webserver_port = var.web_port },
    length(var.local_dns_records) == 0 ? {} : {
      FTLCONF_dns_hosts = join(";", [for name, ip in var.local_dns_records : "${ip} ${name}"])
    },
  )

  # Blocklists the circuit added carry this comment, so it only ever removes
  # its own and leaves lists added in the web interface alone.
  list_comment = "Managed by Conn3x"
  blocklists   = sort(distinct(var.blocklists))
  gravity_sql  = "podman exec pihole pihole-FTL sqlite3 /etc/pihole/gravity.db"
  quoted_lists = join(", ", [for u in local.blocklists : "'${u}'"])

  # The domains gravity took from a list point at it, so they go before the
  # list itself, as when Pi-hole deletes one. SQLite takes an empty IN ().
  stale_lists = "SELECT id FROM adlist WHERE comment = '${local.list_comment}' AND address NOT IN (${local.quoted_lists})"
  sync_sql = join(" ", concat(
    [
      "DELETE FROM gravity WHERE adlist_id IN (${local.stale_lists});",
      "DELETE FROM antigravity WHERE adlist_id IN (${local.stale_lists});",
      "DELETE FROM adlist WHERE id IN (${local.stale_lists});",
    ],
    length(local.blocklists) == 0 ? [] : [
      "INSERT INTO adlist (address, comment) VALUES ${join(", ", [for u in local.blocklists : "('${u}', '${local.list_comment}')"])}",
      "ON CONFLICT(address, type) DO UPDATE SET comment = excluded.comment;",
    ],
  ))
}

# Ubuntu, Fedora and Debian 13 cloud images run systemd-resolved, whose stub
# listener holds port 53 on 127.0.0.53 and 127.0.0.54, and Pi-hole can't
# start next to it. The drop-in turns the stub off and leaves the rest of
# resolved running. On a host without resolved it sits unused.
circuit "resolver" {
  hosts = var.hosts

  ssh {
    user             = var.ssh_user
    port             = var.ssh_port
    private_key_file = var.ssh_private_key_file
    known_hosts_file = var.ssh_known_hosts_file
    become           = var.ssh_become
  }

  step "stub_off" {
    file {
      path    = "/etc/systemd/resolved.conf.d/conn3x-pihole.conf"
      content = "# Written by Conn3x so Pi-hole can listen on port 53.\n[Resolve]\nDNSStubListener=no\n"
    }
  }

  step "restart" {
    command {
      command  = "! systemctl is-active -q systemd-resolved || systemctl restart systemd-resolved"
      triggers = conn3x_file.resolver__stub_off[each.key].revision
    }
  }

  # With the stub gone, a resolv.conf pointing at 127.0.0.53 leaves the host
  # without DNS, including for pulling Pi-hole's image. resolved keeps the
  # real upstream servers in a file of its own.
  step "resolv_conf" {
    command {
      command = "ln -sf /run/systemd/resolve/resolv.conf /etc/resolv.conf"
      unless  = "! readlink /etc/resolv.conf | grep -q stub-resolv.conf"
    }
  }
}

# Pi-hole runs from its official image as a Quadlet unit, on the host's
# network so it sees each client's own address and listening_mode means the
# host's interfaces. Gravity, the query log and the settings it writes live
# in the pihole volume and survive a new image.
module "podman" {
  source = "github.com/conn3xorg/circuit-podman?ref=v0.1.0"

  depends_on = [conn3x_command.resolver__resolv_conf]

  hosts                = var.hosts
  ssh_user             = var.ssh_user
  ssh_port             = var.ssh_port
  ssh_private_key_file = var.ssh_private_key_file
  ssh_known_hosts_file = var.ssh_known_hosts_file
  ssh_become           = var.ssh_become

  containers = {
    pihole = {
      image       = "docker.io/pihole/pihole:${var.pihole_version}"
      volumes     = ["pihole:/etc/pihole"]
      environment = local.environment
      extra       = ["Network=host"]
    }
  }
  secrets = {
    pihole = { FTLCONF_webserver_api_password = var.web_password }
  }
}

circuit "pihole" {
  hosts = var.hosts

  ssh {
    user             = var.ssh_user
    port             = var.ssh_port
    private_key_file = var.ssh_private_key_file
    known_hosts_file = var.ssh_known_hosts_file
    become           = var.ssh_become
  }

  # On its first start the container builds gravity from the default list
  # before it opens port 53, so a list added any earlier would be lost.
  step "ready" {
    depends_on = [module.podman]
    wait_for {
      port    = 53
      timeout = "10m"
    }
  }

  # Adds the lists in blocklists, removes the ones this circuit added before
  # that aren't any more, then rebuilds gravity. A list that was already
  # there from the web interface becomes the circuit's.
  step "blocklists" {
    command {
      command = "${local.gravity_sql} \"${local.sync_sql}\" && podman exec pihole pihole -g"
      unless  = "[ \"$(${local.gravity_sql} \"SELECT group_concat(address, ' ') FROM (SELECT address FROM adlist WHERE comment = '${local.list_comment}' ORDER BY address)\")\" = '${join(" ", local.blocklists)}' ]"
    }
  }
}
