# platform-healthcheck

A small Flask service that exposes a health endpoint and Prometheus metrics, packaged with Docker, deployed to Kubernetes with Terraform, and checked by a GitHub Actions pipeline.

Built as a hands-on exercise in the platform-engineering loop: code, container, infrastructure as code, CI, and observability.

## Endpoints

| Path | Port | Purpose |
|------|------|---------|
| `/health` | 8080 | Returns `{"status": "healthy"}`. Used as the Kubernetes liveness probe. |
| `/metrics` | 8080 | Prometheus-format metrics from `prometheus_client`. |

## Project layout


app.py                      Flask app (/health, /metrics)
requirements.txt            Pinned dependencies
Dockerfile                  Multi-stage build (python:3.11-slim)
terraform/main.tf           Kubernetes namespace, Deployment (2 replicas), NodePort Service
.github/workflows/ci.yml    Test, Bandit scan, Docker build, Trivy scan


## Run locally


python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt
python app.py


In a second terminal:


curl localhost:8080/health
curl localhost:8080/metrics | head


## Run in Docker


docker build -t platform-healthcheck:v1 .
docker run --rm -p 8080:8080 platform-healthcheck:v1


The Dockerfile is multi-stage: dependencies are installed in a builder stage and only the installed packages and `app.py` are copied into the final image. Requirements are copied before source code so the dependency layer stays cached when only code changes.

## Deploy to a local Kubernetes cluster (kind + Terraform)

Requires Docker, kind, kubectl and Terraform.


kind create cluster --name platform-demo
docker build -t platform-healthcheck:v1 .
kind load docker-image platform-healthcheck:v1 --name platform-demo
cd terraform
terraform init
terraform apply -auto-approve
cd ..
kubectl get all -n platform-tools


Terraform creates:

- Namespace `platform-tools`
- Deployment `healthcheck` with 2 replicas, CPU/memory requests and limits, and an HTTP liveness probe on `/health`
- NodePort Service `healthcheck-svc` (port 80 to container port 8080)

Reach the service:


kubectl port-forward -n platform-tools svc/healthcheck-svc 8080:80
curl localhost:8080/health


Try self-healing: delete a pod and watch Kubernetes replace it.


kubectl delete pod -n platform-tools -l app=healthcheck --wait=false
kubectl get pods -n platform-tools -w


Clean up:


cd terraform && terraform destroy -auto-approve && cd ..
kind delete cluster --name platform-demo


## CI pipeline

GitHub Actions runs on every push and pull request to `main`:

1. Install pinned dependencies
2. Smoke test: Flask test client calls `/health` and asserts a 200 response and `"healthy"` status
3. Bandit static security scan
4. Docker image build, tagged with the commit SHA
5. Trivy image scan (CRITICAL and HIGH)

## Design notes

- **Bind to `0.0.0.0`:** the app must listen on all interfaces inside the container, otherwise the Kubernetes Service cannot reach it. Bandit flags this as B104, so the line carries a narrow `# nosec B104` annotation with the reason, instead of weakening the scanner for the whole repository.
- **Pinned dependencies:** `Flask` and `prometheus-client` are pinned for reproducible builds.
- **Resource limits and liveness probe:** set in Terraform so a stuck or runaway container is restarted and cannot starve the node.

## Known limitations and next steps

- Uses Flask's development server. A production setup would use gunicorn.
- Only a liveness probe is defined. A readiness probe would keep a pod out of the Service until it can take traffic.
- Testing is a single smoke test, not a full pytest suite.
- The Trivy step is informational (`exit-code: 0`): it reports findings but does not fail the build. It could be tightened once the baseline is clean.
- `/metrics` exposes only default Python process metrics. No custom application metrics, and no Prometheus server is deployed here.
- The CI runner uses Python 3.12 while the Docker image uses 3.11. These should be aligned.
- The Terraform image reference is a local tag loaded into kind. A real deployment would push to a registry such as ECR.
