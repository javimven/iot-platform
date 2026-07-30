terraform {
  required_version = ">= 1.9"

  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 5.22"
    }
  }

  # Estado local a propósito (equipo de 3-6 personas, un solo operador de
  # infraestructura a la vez, DEPLOYMENT.md filosofía "sin complejidad sin
  # necesidad medida") — migrar a un backend remoto (p. ej. este mismo
  # Hetzner Object Storage, ver infra/terraform/README.md) en cuanto haya
  # más de una persona aplicando Terraform con regularidad.
  backend "local" {
    path = "terraform.tfstate"
  }
}

provider "cloudflare" {
  # CLOUDFLARE_API_TOKEN en el entorno — nunca en un archivo versionado.
}
