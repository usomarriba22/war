# CON War Room — Kubernetes Starter

Estructura inicial para aprender Kubernetes con VS Code y desplegar el futuro CON War Room.

## Objetivo

1. Conectarse al cluster Cloudfleet con `kubectl`.
2. Crear namespace `con-warroom`.
3. Desplegar una app de prueba `hello-warroom`.
4. Exponerla solo por `port-forward` para no crear Load Balancer ni costes innecesarios.
5. Dejar preparada la estructura del proyecto real.

## Orden de uso

```powershell
cd C:\Labs\con-warroom
code .
```

Después sigue `00-docs/01-paso-a-paso.md`.

## Seguridad

No subas a GitHub:
- kubeconfig
- tokens de Cloudfleet
- tokens de Hetzner
- claves de Supabase
- `.env`
