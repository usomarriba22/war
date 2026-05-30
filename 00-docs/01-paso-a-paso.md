# Paso a paso — Cloudfleet + Kubernetes + VS Code

## 1. Instalar herramientas en Windows

Abre PowerShell como administrador:

```powershell
winget install Microsoft.VisualStudioCode
winget install Git.Git
winget install Kubernetes.kubectl
winget install Helm.Helm
```

Cierra PowerShell y abre uno nuevo.

Comprueba:

```powershell
git --version
kubectl version --client
helm version
code --version
```

## 2. Descargar kubeconfig desde Cloudfleet

En Cloudfleet:

1. Entra al cluster `con-warroom-lab`.
2. Pulsa `Configure kubectl`.
3. Descarga o copia el kubeconfig.
4. Guárdalo en:

```text
C:\Users\TU_USUARIO\.kube\con-warroom-lab.yaml
```

No pegues ese archivo en chats ni lo subas a GitHub.

## 3. Activar kubeconfig en PowerShell

Solo para la sesión actual:

```powershell
$env:KUBECONFIG="$env:USERPROFILE\.kube\con-warroom-lab.yaml"
kubectl config get-contexts
kubectl get namespaces
kubectl get nodes
```

Para dejarlo permanente en tu usuario:

```powershell
setx KUBECONFIG "$env:USERPROFILE\.kube\con-warroom-lab.yaml"
```

Luego cierra y abre PowerShell.

## 4. Abrir proyecto en VS Code

```powershell
mkdir C:\Labs
cd C:\Labs
# Descomprime este ZIP como carpeta con-warroom
cd C:\Labs\con-warroom
code .
```

## 5. Aplicar manifiestos de prueba

```powershell
kubectl apply -f 01-kubernetes/00-namespaces/namespace-con-warroom.yaml
kubectl apply -f 01-kubernetes/10-hello/hello-deployment.yaml
kubectl apply -f 01-kubernetes/10-hello/hello-service.yaml
```

Ver estado:

```powershell
kubectl -n con-warroom get pods -w
kubectl get nodes
```

## 6. Probar sin exponer a internet

```powershell
kubectl -n con-warroom port-forward svc/hello-warroom 8080:80
```

Abre:

```text
http://localhost:8080
```

## 7. Limpiar prueba para no dejar recursos activos

```powershell
kubectl delete -f 01-kubernetes/10-hello/hello-service.yaml
kubectl delete -f 01-kubernetes/10-hello/hello-deployment.yaml
```

Deja el namespace creado.

## 8. Comprobar costes/nodos

Después de borrar la prueba:

```powershell
kubectl -n con-warroom get pods
kubectl get nodes
```

En Cloudfleet/Hetzner revisa que no queden nodos innecesarios si no hay workloads.
