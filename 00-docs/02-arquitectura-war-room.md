# Arquitectura objetivo — CON War Room Pro

## Componentes

```text
Tu navegador
 ├─ Conflict of Nations
 └─ CON War Room Web

Vercel o Kubernetes
 └─ warroom-web

Cloudfleet Kubernetes
 ├─ warroom-api
 ├─ warroom-worker
 └─ jobs de procesamiento

Supabase
 ├─ games
 ├─ snapshots
 ├─ resources
 ├─ cities
 ├─ research
 ├─ fronts
 ├─ stacks
 └─ actions
```

## Fases

### Fase 1 — Kubernetes base
- namespace
- deployment de prueba
- service ClusterIP
- port-forward

### Fase 2 — Backend
- FastAPI
- `/health`
- `/api/games`
- `/api/snapshots`

### Fase 3 — Frontend
- Next.js
- dashboard militar
- recursos
- predicción de déficit
- export para ChatGPT

### Fase 4 — Captura/OCR
- captura de pestaña en memoria
- extracción de recursos
- confirmación manual
- guardado de datos estructurados

## Reglas de coste

- No usar LoadBalancer al inicio.
- No desplegar base de datos dentro del cluster al inicio.
- No crear volúmenes persistentes hasta necesitarlos.
- Usar Supabase Free para DB.
- Usar `port-forward` durante labs.
