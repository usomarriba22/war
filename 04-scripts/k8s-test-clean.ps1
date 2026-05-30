kubectl delete -f .\01-kubernetes\10-hello\hello-service.yaml --ignore-not-found
kubectl delete -f .\01-kubernetes\10-hello\hello-deployment.yaml --ignore-not-found

kubectl -n con-warroom get pods
kubectl get nodes
