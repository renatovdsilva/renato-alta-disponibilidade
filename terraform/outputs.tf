# =============================================================================
#  Outputs — o que fica a saber-se depois do apply.
# =============================================================================

output "cluster_name" {
  description = "Nome do cluster criado."
  value       = var.cluster_name
}

output "kube_context" {
  description = "Contexto a usar no kubectl."
  value       = "k3d-${var.cluster_name}"
}

output "namespaces_criados" {
  description = "Namespaces geridos por este Terraform."
  value       = [for ns in kubernetes_namespace.apps : ns.metadata[0].name]
}

output "proximos_passos" {
  description = "O que fazer a seguir ao apply."
  value       = <<-EOT
    1. kubectl config use-context k3d-${var.cluster_name}
    2. Criar os Secrets que NÃO estão no Git (ver k8s/examples/)
    3. Construir e importar as imagens: ./scripts/build-images.sh
    4. Aplicar as Applications do ArgoCD: kubectl apply -f argocd/
    5. Password inicial do ArgoCD:
       kubectl -n argocd get secret argocd-initial-admin-secret \
         -o jsonpath="{.data.password}" | base64 -d
  EOT
}
