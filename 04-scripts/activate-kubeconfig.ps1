# Ajusta esta ruta si tu kubeconfig tiene otro nombre.
$KubeConfigPath = "$env:USERPROFILE\.kube\con-warroom-lab.yaml"

if (!(Test-Path $KubeConfigPath)) {
    Write-Host "No existe kubeconfig en: $KubeConfigPath" -ForegroundColor Red
    exit 1
}

$env:KUBECONFIG = $KubeConfigPath
Write-Host "KUBECONFIG activo: $env:KUBECONFIG" -ForegroundColor Green

kubectl config get-contexts
kubectl get namespaces
