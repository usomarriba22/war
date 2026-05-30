kubectl apply -f .\01-kubernetes\00-namespaces\namespace-con-warroom.yaml
kubectl apply -f .\01-kubernetes\10-hello\hello-deployment.yaml
kubectl apply -f .\01-kubernetes\10-hello\hello-service.yaml

kubectl -n con-warroom get pods
kubectl -n con-warroom get svc
