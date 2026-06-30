# wger DevOps Project

Овој репозиториум содржи целосна DevOps инфраструктура за [wger](https://github.com/wger-project/wger) - апликација со отворен код за следење на фитнес активности, исхрана и тежина.

## Технологии

- **Апликација:** Django (Python), Gunicorn, PostgreSQL, Nginx, Node.js/Sass
- **Контејнеризација:** Docker (multi-stage build), Docker Compose
- **CI/CD:** GitHub Actions + ArgoCD (GitOps)
- **Оркестрација:** Kubernetes (k3d/k3s), Traefik Ingress

---

## Структура на проектот

```
wger-devops-project/
├── .github/
│   └── workflows/
│       └── ci.yml
├── docker/
│   └── entrypoint.sh
├── k8s/
│   ├── namespace.yaml
│   ├── configmap-app.yaml
│   ├── configmap-db.yaml
│   ├── configmap-nginx.yaml
│   ├── secret-app.example.yaml
│   ├── secret-db.example.yaml
│   ├── deployment.yaml
│   ├── service.yaml
│   ├── headless-service-db.yaml
│   ├── ingress.yaml
│   └── statefulset-db.yaml
├── argocd-application.yaml
├── Dockerfile
├── docker-compose.yml
├── nginx.conf
└── .env.example
```

---

## Брзо стартување (Docker Compose)

### 1. Клонирај го репозиториумот

```bash
git clone https://github.com/milabla/wger-devops-project.git
cd wger-devops-project
```

### 2. Креирај `.env` фајл

```bash
cp .env.example .env
```

Уреди го `.env` и замени ги placeholder вредностите:

```env
SECRET_KEY=replace-with-a-long-random-string
DJANGO_DB_DATABASE=wger
DJANGO_DB_USER=wger
DJANGO_DB_PASSWORD=replace-with-a-real-password
SITE_URL=http://localhost:8000
```

Генерирај SECRET_KEY:
```bash
python -c "import secrets; print(secrets.token_urlsafe(50))"
```

### 3. Стартувај

```bash
docker compose up --build -d
```

Апликацијата е достапна на [http://localhost:8000](http://localhost:8000).

---

## Архитектура (Docker Compose)

```
Browser → Nginx (:8000) → Gunicorn/Django (:8000) → PostgreSQL (:5432)
```

Три сервиси:
- **db** - PostgreSQL 16 база на податоци
- **web** - Django апликација сервирана преку Gunicorn
- **nginx** - Reverse proxy, сервира статички фајлови директно

---

## Dockerfile (Multi-stage build)

Три стејџи за оптимален финален image:

| Стејџ | Base image | Цел |
|---|---|---|
| `frontend-builder` | node:22-slim | Компајлира Sass/SCSS → CSS |
| `backend-builder` | python:3.13-slim | Инсталира Python deps, `collectstatic` |
| `runtime` | python:3.13-slim | Финален мал image за production |

---

## CI/CD Pipeline (GitHub Actions + ArgoCD)

### Автоматски тригер
При секој `push` на гранките `devops-project`, `main`, `master`.

### Job 1: `build-and-push`
- Build-ува Docker image (multi-stage)
- Push-ува на DockerHub со два тага:
  - `milablazevska/wger-devops-project:latest`
  - `milablazevska/wger-devops-project:<commit-sha>`

### Job 2: `update-manifest`
- Го ажурира `k8s/deployment.yaml` со новиот commit SHA image tag
- Commit-ува и push-нува назад во репозиториумот

### ArgoCD (GitOps CD)
ArgoCD континуирано го следи `k8s/` директориумот и автоматски ги применува промените на Kubernetes кластерот при секоја детектирана промена во Git.

```
git push → CI build & push image → CI ажурира k8s/deployment.yaml
                                              ↓
                          ArgoCD детектира промена → kubectl apply → Kubernetes
```

### Потребни GitHub Secrets

| Secret | Опис |
|---|---|
| `DOCKERHUB_USERNAME` | DockerHub корисничко име |
| `DOCKERHUB_TOKEN` | DockerHub Access Token |

---

## Kubernetes (k3d)

### Креирај кластер

```bash
k3d cluster create wger-cluster --port "80:80@loadbalancer"
```

### Примени манифести

```bash
# 1. Namespace
kubectl apply -f k8s/namespace.yaml

# 2. Secrets (не се на Git - мора рачно да се создадат)
cp k8s/secret-app.example.yaml k8s/secret-app.yaml
cp k8s/secret-db.example.yaml k8s/secret-db.yaml
# Уреди ги фајловите со вистински вредности
kubectl apply -f k8s/secret-app.yaml
kubectl apply -f k8s/secret-db.yaml

# 3. Останати манифести
kubectl apply -f k8s/
```

### Ресурси во namespace `wger-devops`

| Ресурс | Тип | Опис |
|---|---|---|
| `wger-app` | Deployment | 2 реплики (django + nginx sidecar) |
| `wger-db` | StatefulSet | PostgreSQL со PVC (1Gi) |
| `wger-service` | Service (ClusterIP) | Load balancing кон app Pods |
| `wger-db` | Service (Headless) | DNS резолуција кон PostgreSQL |
| `wger-ingress` | Ingress | `wger.local` → `wger-service` |
| `wger-app-config` | ConfigMap | Django env поставки |
| `wger-db-config` | ConfigMap | PostgreSQL env поставки |
| `wger-nginx-config` | ConfigMap | Nginx конфигурација |
| `wger-app-secret` | Secret | SECRET_KEY, DB лозинка |
| `wger-db-secret` | Secret | PostgreSQL лозинка |

### Локален пристап

Додај во `hosts` фајлот (`C:\Windows\System32\drivers\etc\hosts`):

```
127.0.0.1 wger.local
```

Апликацијата е достапна на [http://wger.local](http://wger.local).

---

## ArgoCD

### Инсталација

```bash
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
```

### Пристап до UI

```bash
kubectl port-forward svc/argocd-server -n argocd 8080:443
```

Отвори [https://localhost:8080](https://localhost:8080), логирај се со:
- **Username:** `admin`
- **Password:** 
```bash
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
```

### Примени ArgoCD Application

```bash
kubectl apply -f argocd-application.yaml
```

ArgoCD автоматски ќе ги следи и применува промените во `k8s/` директориумот.

---

## Безбедност

- Реалните `.env`, `secret-app.yaml` и `secret-db.yaml` фајлови се во `.gitignore` и **никогаш не се commit-уваат**
- На Git постојат само `.example` верзии со placeholder вредности
- Kubernetes Secrets се користат за сите чувствителни податоци
- Апликацијата работи како non-root корисник (`wger`, UID 1000)
