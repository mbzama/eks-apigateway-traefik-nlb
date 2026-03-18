# ─────────────────────────────────────────────────────────────────────────────
# Namespace – mock-api
# ─────────────────────────────────────────────────────────────────────────────
resource "kubernetes_namespace" "mock_api" {
  metadata {
    name = var.app_namespace
    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
    }
  }

  depends_on = [aws_eks_node_group.main]
}

# ─────────────────────────────────────────────────────────────────────────────
# Deployment – NestJS mock-api
#
# The app listens on port 3000 and exposes:
#   GET /api/users
#   GET /api/products
#   (full CRUD on both resources)
# ─────────────────────────────────────────────────────────────────────────────
resource "kubernetes_deployment" "mock_api" {
  metadata {
    name      = "mock-api"
    namespace = kubernetes_namespace.mock_api.metadata[0].name
    labels = {
      app = "mock-api"
    }
  }

  spec {
    replicas = var.app_replicas

    selector {
      match_labels = {
        app = "mock-api"
      }
    }

    template {
      metadata {
        labels = {
          app = "mock-api"
        }
      }

      spec {
        container {
          name  = "mock-api"
          image = var.app_image

          port {
            container_port = 3000
            protocol       = "TCP"
          }

          resources {
            requests = {
              cpu    = "100m"
              memory = "128Mi"
            }
            limits = {
              cpu    = "250m"
              memory = "256Mi"
            }
          }

          # Liveness: TCP check confirms the process is alive without hitting a data endpoint
          liveness_probe {
            tcp_socket {
              port = 3000
            }
            initial_delay_seconds = 15
            period_seconds        = 20
          }

          # Readiness: HTTP check confirms the app can serve requests
          readiness_probe {
            http_get {
              path = "/api/users"
              port = 3000
            }
            initial_delay_seconds = 5
            period_seconds        = 10
          }
        }
      }
    }
  }

  depends_on = [kubernetes_namespace.mock_api]
}

# ─────────────────────────────────────────────────────────────────────────────
# Service – ClusterIP
# Port 80 → targetPort 3000 (matches the NestJS container port)
# Traefik routes to this service via the IngressRoute below.
# ─────────────────────────────────────────────────────────────────────────────
resource "kubernetes_service" "mock_api" {
  metadata {
    name      = "mock-api"
    namespace = kubernetes_namespace.mock_api.metadata[0].name
    labels = {
      app = "mock-api"
    }
  }

  spec {
    type = "ClusterIP"

    selector = {
      app = "mock-api"
    }

    port {
      name        = "http"
      port        = 80
      target_port = 3000
      protocol    = "TCP"
    }
  }

  depends_on = [kubernetes_namespace.mock_api]
}

# ─────────────────────────────────────────────────────────────────────────────
# IngressRoute – Traefik CRD
#
# Routes traffic that arrives at Traefik with:
#   Host: <app_host>  AND  PathPrefix: /api
#
# Flow:
#   API Gateway /mock/{proxy+}
#     → VPC Link → Traefik NLB
#       → Traefik (matches Host header + path prefix)
#         → mock-api service:80
#           → pod:3000
#
# NOTE: kubernetes_manifest requires the IngressRoute CRD to exist at
# plan-time.  On a fresh workspace run:
#   terraform apply -target=helm_release.traefik
# before running a full `terraform apply`.
# ─────────────────────────────────────────────────────────────────────────────
resource "kubernetes_manifest" "mock_api_ingress_route" {
  manifest = {
    apiVersion = "traefik.io/v1alpha1"
    kind       = "IngressRoute"
    metadata = {
      name      = "mock-api"
      namespace = kubernetes_namespace.mock_api.metadata[0].name
    }
    spec = {
      entryPoints = ["web"]
      routes = [{
        match = "Host(`${var.app_host}`) && PathPrefix(`/api`)"
        kind  = "Rule"
        services = [{
          name      = kubernetes_service.mock_api.metadata[0].name
          namespace = kubernetes_namespace.mock_api.metadata[0].name
          port      = 80
        }]
      }]
    }
  }

  depends_on = [
    helm_release.traefik,
    kubernetes_service.mock_api,
  ]
}
