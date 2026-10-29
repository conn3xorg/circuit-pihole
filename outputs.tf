output "service" {
  description = "The systemd service that runs Pi-hole on each host."
  value       = "pihole.service"
}

output "image" {
  description = "The Pi-hole image the hosts run."
  value       = "docker.io/pihole/pihole:${var.pihole_version}"
}
