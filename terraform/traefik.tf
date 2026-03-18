# ─────────────────────────────────────────────────────────────────────────────
# Namespace – test-system
# ─────────────────────────────────────────────────────────────────────────────
resource "kubernetes_namespace" "traefik" {
  metadata {
    name = var.traefik_namespace
    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
    }
  }

  depends_on = [aws_eks_node_group.main]
}

# ─────────────────────────────────────────────────────────────────────────────
# Traefik – Helm Release
#
# Key design decisions:
#   • Service type LoadBalancer so the K8s cloud controller provisions an AWS NLB
#   • Annotations mark the NLB as *internal* (scheme: internal) so it is
#     reachable only inside the VPC – the API Gateway VPC Link connects to it
#   • CRD provider (kubernetesCRD) is enabled for IngressRoute resources
#   • allowCrossNamespace = true lets Traefik route to services in other
#     namespaces (e.g. mock-api)
# ─────────────────────────────────────────────────────────────────────────────
resource "helm_release" "traefik" {
  name       = "traefik"
  repository = "https://traefik.github.io/charts"
  chart      = "traefik"
  version    = var.traefik_chart_version
  namespace  = kubernetes_namespace.traefik.metadata[0].name

  # Wait until all pods are Running before Terraform considers this done
  wait    = true
  timeout = 600

  values = [
    yamlencode({
      deployment = {
        replicas = 1
      }

      # ── Service / NLB ────────────────────────────────────────────────────
      service = {
        type = "LoadBalancer"
        annotations = {
          # Use in-tree K8s NLB provisioner (no AWS Load Balancer Controller needed)
          "service.beta.kubernetes.io/aws-load-balancer-type"                            = "nlb"
          "service.beta.kubernetes.io/aws-load-balancer-internal"                        = "true"
          "service.beta.kubernetes.io/aws-load-balancer-cross-zone-load-balancing-enabled" = "true"
          # Propagate the real client IP to pods
          "service.beta.kubernetes.io/aws-load-balancer-proxy-protocol" = "*"
        }
      }

      # ── Ports ────────────────────────────────────────────────────────────
      ports = {
        web = {
          port        = 8000
          exposedPort = 80
          protocol    = "TCP"
          expose      = true
        }
        websecure = {
          expose = false # HTTPS not needed for this VPC-Link setup
        }
      }

      # ── Providers ────────────────────────────────────────────────────────
      providers = {
        kubernetesCRD = {
          enabled            = true
          allowCrossNamespace = true # Required to route to mock-api namespace
        }
        kubernetesIngress = {
          enabled = false
        }
      }

      # ── Dashboard ────────────────────────────────────────────────────────
      ingressRoute = {
        dashboard = {
          enabled = false # Disable the built-in dashboard IngressRoute
        }
      }

      # ── Resources ────────────────────────────────────────────────────────
      resources = {
        requests = { cpu = "100m", memory = "128Mi" }
        limits   = { cpu = "300m", memory = "256Mi" }
      }

      # ── Additional arguments ─────────────────────────────────────────────
      additionalArguments = [
        "--log.level=INFO",
        "--accesslog=true",
        # Trust X-Forwarded-* headers only from within the VPC (API Gateway VPC Link).
        # Using trustedIPs instead of insecure=true prevents clients outside the VPC
        # from spoofing forwarded headers.
        "--entrypoints.web.forwardedHeaders.trustedIPs=${var.vpc_cidr}",
      ]
    })
  ]

  depends_on = [kubernetes_namespace.traefik]
}

# ─────────────────────────────────────────────────────────────────────────────
# Wait for the NLB to be provisioned by the K8s cloud controller.
# The NLB is created asynchronously after the LoadBalancer Service is ready;
# we pause here so that the subsequent `data "aws_lb"` lookup succeeds.
# ─────────────────────────────────────────────────────────────────────────────
resource "time_sleep" "wait_for_nlb" {
  create_duration = "${var.nlb_wait_seconds}s"

  depends_on = [helm_release.traefik]
}

# ─────────────────────────────────────────────────────────────────────────────
# Data – Traefik NLB
# Looks up the NLB that was created by the LoadBalancer Service.  The K8s
# cloud controller tags the NLB with the cluster name and service name so we
# can identify it reliably.
# ─────────────────────────────────────────────────────────────────────────────
data "aws_lb" "traefik" {
  tags = {
    "kubernetes.io/cluster/${var.cluster_name}"     = "owned"
    "kubernetes.io/service-name"                    = "${var.traefik_namespace}/traefik"
  }

  depends_on = [time_sleep.wait_for_nlb]
}

# ─────────────────────────────────────────────────────────────────────────────
# Data – Traefik NLB Listener (port 80)
# The API Gateway VPC Link integration requires the listener ARN.
# ─────────────────────────────────────────────────────────────────────────────
data "aws_lb_listener" "traefik_http" {
  load_balancer_arn = data.aws_lb.traefik.arn
  port              = 80

  depends_on = [time_sleep.wait_for_nlb]
}
