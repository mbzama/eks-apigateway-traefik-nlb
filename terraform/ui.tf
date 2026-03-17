# ─────────────────────────────────────────────────────────────────────────────
# Namespace – mock-web
# ─────────────────────────────────────────────────────────────────────────────
resource "kubernetes_namespace" "mock_web" {
  metadata {
    name = var.ui_namespace
    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
    }
  }

  depends_on = [aws_eks_node_group.main]
}

# ─────────────────────────────────────────────────────────────────────────────
# Deployment – Next.js UI
# ─────────────────────────────────────────────────────────────────────────────
resource "kubernetes_deployment" "mock_web" {
  metadata {
    name      = "mock-web"
    namespace = kubernetes_namespace.mock_web.metadata[0].name
    labels = {
      app = "mock-web"
    }
  }

  spec {
    replicas = var.ui_replicas

    selector {
      match_labels = {
        app = "mock-web"
      }
    }

    template {
      metadata {
        labels = {
          app = "mock-web"
        }
      }

      spec {
        container {
          name  = "mock-web"
          image = var.ui_image

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

          readiness_probe {
            http_get {
              path = "/"
              port = 3000
            }
            initial_delay_seconds = 10
            period_seconds        = 10
          }

          liveness_probe {
            http_get {
              path = "/"
              port = 3000
            }
            initial_delay_seconds = 20
            period_seconds        = 20
          }
        }
      }
    }
  }

  depends_on = [kubernetes_namespace.mock_web]
}

# ─────────────────────────────────────────────────────────────────────────────
# Service – ClusterIP
# ─────────────────────────────────────────────────────────────────────────────
resource "kubernetes_service" "mock_web" {
  metadata {
    name      = "mock-web"
    namespace = kubernetes_namespace.mock_web.metadata[0].name
    labels = {
      app = "mock-web"
    }
  }

  spec {
    type = "ClusterIP"

    selector = {
      app = "mock-web"
    }

    port {
      name        = "http"
      port        = 80
      target_port = 3000
      protocol    = "TCP"
    }
  }

  depends_on = [kubernetes_namespace.mock_web]
}

# ─────────────────────────────────────────────────────────────────────────────
# IngressRoute – Traefik CRD
#
# Routes traffic arriving at Traefik with Host: <ui_host>
# Flow:
#   API Gateway /web/{proxy+}
#     → VPC Link → Traefik NLB
#       → Traefik (matches Host header)
#         → mock-web service:80
#           → pod:3000
# ─────────────────────────────────────────────────────────────────────────────
resource "kubernetes_manifest" "mock_web_ingress_route" {
  manifest = {
    apiVersion = "traefik.io/v1alpha1"
    kind       = "IngressRoute"
    metadata = {
      name      = "mock-web"
      namespace = kubernetes_namespace.mock_web.metadata[0].name
    }
    spec = {
      entryPoints = ["web"]
      routes = [{
        match = "Host(`${var.ui_host}`)"
        kind  = "Rule"
        services = [{
          name      = kubernetes_service.mock_web.metadata[0].name
          namespace = kubernetes_namespace.mock_web.metadata[0].name
          port      = 80
        }]
      }]
    }
  }

  depends_on = [
    helm_release.traefik,
    kubernetes_service.mock_web,
  ]
}
