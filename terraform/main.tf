# =============================================================================
#  Criação declarativa do cluster.
#
#  Substitui a parte do `scripts/bootstrap.sh` que cria o cluster à mão.
#  A diferença face ao script não é fazer o mesmo com outra sintaxe: o Terraform
#  guarda estado, portanto sabe o que já criou e consegue dizer, ANTES de agir,
#  o que vai criar, alterar ou destruir. É isso o `terraform plan`.
# =============================================================================

terraform {
  required_version = ">= 1.6"

  required_providers {
    k3d = {
      source  = "SneakyBugs/k3d"
      version = "~> 1.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.12"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.27"
    }
  }
}

# -----------------------------------------------------------------------------
#  O cluster
#
#  1 servidor + 2 agentes, igual ao que já corre. O Traefik é desativado porque
#  usamos o Ingress NGINX — deixar os dois disputa as portas 80 e 443.
# -----------------------------------------------------------------------------
#  Este provider não recebe os parâmetros um a um: recebe o ficheiro de
#  configuração do próprio k3d, no formato "Simple Config" (v1alpha5), como
#  string. É a mesma coisa que se passaria a `k3d cluster create --config`.
resource "k3d_cluster" "alta_disponibilidade" {
  name = var.cluster_name

  k3d_config = <<-YAML
    apiVersion: k3d.io/v1alpha5
    kind: Simple
    metadata:
      name: ${var.cluster_name}
    servers: ${var.servers}
    agents: ${var.agents}
    ports:
      - port: ${var.http_port}:80
        nodeFilters:
          - loadbalancer
      - port: ${var.https_port}:443
        nodeFilters:
          - loadbalancer
    options:
      k3d:
        wait: true
        timeout: "300s"
      k3s:
        extraArgs:
          # Desativado porque usamos o Ingress NGINX. Deixar os dois faz com
          # que disputem as portas 80 e 443.
          - arg: --disable=traefik
            nodeFilters:
              - server:*
  YAML
}

# -----------------------------------------------------------------------------
#  Providers que dependem do cluster
#
#  Só se ligam depois de o cluster existir — daí o depends_on implícito pela
#  referência ao recurso.
# -----------------------------------------------------------------------------
provider "kubernetes" {
  config_path    = var.kubeconfig_path
  config_context = "k3d-${var.cluster_name}"
}

provider "helm" {
  kubernetes {
    config_path    = var.kubeconfig_path
    config_context = "k3d-${var.cluster_name}"
  }
}

# -----------------------------------------------------------------------------
#  Ingress NGINX
#
#  Instalado por Helm, tal como no bootstrap.sh, mas aqui declarado.
# -----------------------------------------------------------------------------
resource "helm_release" "ingress_nginx" {
  name             = "ingress-nginx"
  repository       = "https://kubernetes.github.io/ingress-nginx"
  chart            = "ingress-nginx"
  namespace        = "ingress-nginx"
  create_namespace = true
  wait             = true
  timeout          = 300

  set {
    name  = "controller.service.type"
    value = "LoadBalancer"
  }

  depends_on = [k3d_cluster.alta_disponibilidade]
}

# -----------------------------------------------------------------------------
#  Namespaces das aplicações
#
#  Declarados aqui em vez de `kubectl apply -f 00-namespaces.yaml`, para que o
#  Terraform saiba que existem e os remova num `destroy`.
# -----------------------------------------------------------------------------
resource "kubernetes_namespace" "apps" {
  for_each = toset(var.namespaces)

  metadata {
    name = each.value

    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
    }
  }

  depends_on = [k3d_cluster.alta_disponibilidade]
}

# -----------------------------------------------------------------------------
#  ArgoCD
#
#  A partir daqui o Terraform sai de cena: quem gere as aplicações é o ArgoCD,
#  a partir do Git. O Terraform trata da plataforma, o ArgoCD trata do que corre
#  em cima dela.
# -----------------------------------------------------------------------------
resource "helm_release" "argocd" {
  name             = "argocd"
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  namespace        = "argocd"
  create_namespace = true
  wait             = true
  timeout          = 600

  # server-side apply: as CRDs do ArgoCD ultrapassam o limite de 256 KB da
  # anotação last-applied-configuration. Foi exatamente isso que rebentou o
  # applicationset-controller em agosto, com 208 reinícios.
  set {
    name  = "installCRDs"
    value = "true"
  }

  depends_on = [k3d_cluster.alta_disponibilidade]
}
