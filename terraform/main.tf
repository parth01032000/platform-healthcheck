terraform {
  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.30"
    }
  }
}

provider "kubernetes" {
  config_path = "~/.kube/config"
}

resource "kubernetes_namespace" "platform" {
  metadata {
    name = "platform-tools"
  }
}

resource "kubernetes_deployment" "healthcheck" {
  metadata {
    name      = "healthcheck"
    namespace = kubernetes_namespace.platform.metadata[0].name
    labels    = { app = "healthcheck" }
  }

  spec {
    replicas = 2

    selector {
      match_labels = { app = "healthcheck" }
    }

    template {
      metadata {
        labels = { app = "healthcheck" }
      }

      spec {
        container {
          name               = "healthcheck"
          image              = "platform-healthcheck:v1"
          image_pull_policy  = "IfNotPresent"

          port {
            container_port = 8080
          }

          resources {
            requests = { cpu = "50m", memory = "64Mi" }
            limits   = { cpu = "200m", memory = "128Mi" }
          }

          liveness_probe {
            http_get {
              path = "/health"
              port = 8080
            }
            initial_delay_seconds = 3
            period_seconds        = 5
          }
        }
      }
    }
  }
}

resource "kubernetes_service" "healthcheck" {
  metadata {
    name      = "healthcheck-svc"
    namespace = kubernetes_namespace.platform.metadata[0].name
  }

  spec {
    selector = { app = "healthcheck" }

    port {
      port        = 80
      target_port = 8080
    }

    type = "NodePort"
  }
}

output "namespace" {
  value = kubernetes_namespace.platform.metadata[0].name
}

output "service_name" {
  value = kubernetes_service.healthcheck.metadata[0].name
}
