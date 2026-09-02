# =============================================================================
#  Variáveis.
#
#  Ter isto separado é o que permite criar um cluster de teste sem tocar no
#  principal: `terraform apply -var="cluster_name=teste"`.
# =============================================================================

variable "cluster_name" {
  description = "Nome do cluster k3d."
  type        = string
  default     = "alta-disponibilidade"
}

variable "servers" {
  description = "Número de nós de control plane."
  type        = number
  default     = 1
}

variable "agents" {
  description = "Número de nós de trabalho."
  type        = number
  default     = 2

  validation {
    condition     = var.agents >= 1
    error_message = "É preciso pelo menos um agente para as réplicas terem onde correr."
  }
}

# Parametrizados para se poder criar um cluster de teste em paralelo com o
# principal. Dois clusters não podem disputar as mesmas portas do host.
variable "http_port" {
  description = "Porta do host mapeada para a 80 do load balancer."
  type        = number
  default     = 80
}

variable "https_port" {
  description = "Porta do host mapeada para a 443 do load balancer."
  type        = number
  default     = 443
}

variable "kubeconfig_path" {
  description = "Caminho do kubeconfig. O k3d escreve aqui ao criar o cluster."
  type        = string
  default     = "~/.kube/config"
}

variable "namespaces" {
  description = "Namespaces das aplicações geridas por GitOps."
  type        = list(string)
  default     = ["quinta", "renatotrack", "fitness", "monitoring"]
}
