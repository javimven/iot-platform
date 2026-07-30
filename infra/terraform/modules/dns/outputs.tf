output "api_hostname" {
  value = cloudflare_dns_record.api.name
}

output "app_hostname" {
  value = cloudflare_dns_record.app.name
}

output "mqtt_hostname" {
  value = cloudflare_dns_record.mqtt.name
}
