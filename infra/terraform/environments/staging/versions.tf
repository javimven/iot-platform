terraform {
  required_version = ">= 1.9"

  required_providers {
    hcloud = {
      source  = "hetznercloud/hcloud"
      version = "~> 1.68"
    }
    digitalocean = {
      source  = "digitalocean/digitalocean"
      version = "~> 2.96"
    }
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 5.22"
    }
  }

  # Estado local — ver infra/terraform/README.md sobre cuándo migrar a
  # remoto (mismo criterio que infra/terraform/dns-zone/versions.tf).
  backend "local" {
    path = "terraform.tfstate"
  }
}

provider "hcloud" {
  # HCLOUD_TOKEN en el entorno.
}

provider "digitalocean" {
  # DIGITALOCEAN_TOKEN en el entorno.
}

provider "cloudflare" {
  # CLOUDFLARE_API_TOKEN en el entorno.
}
