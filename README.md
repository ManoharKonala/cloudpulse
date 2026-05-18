# CloudPulse — Industrial-Grade DevOps Project

A microservices-based **Product & Order Management** platform demonstrating the full DevOps toolchain end-to-end: Git → GitHub → Jenkins → Docker → DockerHub → Terraform → AWS EC2 → Prometheus → Grafana.

---

## Architecture

```
                          ┌─────────────────────────────────────────┐
                          │            CloudPulse Stack              │
                          │                                          │
  Browser  ──── HTTP ──▶  │  Nginx (port 80)                        │
                          │     │                                    │
                          │     ├──▶ product-service :5001 (Flask)  │
                          │     └──▶ order-service   :5002 (Flask)  │
                          │                │                         │
                          │         prometheus :9090                 │
                          │         grafana    :3000                 │
                          │         node-exporter :9100              │
                          └─────────────────────────────────────────┘

  CI/CD:   GitHub Push → Webhook → Jenkins → DockerHub → SSH → EC2
  IaC:     Terraform → AWS VPC + Subnet + IGW + SG + 2× EC2
```

---

## Tech Stack

| Tool | Role |
|---|---|
| **Git / GitHub** | Source control, branching, webhook trigger |
| **Docker** | Containerises all 3 services (non-root images) |
| **Docker Compose** | Runs full stack locally and on EC2 |
| **DockerHub** | Image registry — Jenkins pushes versioned tags |
| **Jenkins** | 6-stage CI/CD pipeline (parallel builds, SSH deploy) |
| **Terraform** | Provisions VPC, subnets, security groups, 2× EC2 |
| **AWS EC2** | App server + Jenkins server (Ubuntu 22.04, t2.micro) |
| **Python Flask** | Microservices backend with `/metrics` endpoint |
| **Nginx** | Serves frontend SPA, reverse-proxies `/api/*` |
| **Prometheus** | Scrapes `/metrics` every 15s |
| **Grafana** | 8-panel auto-provisioned dashboard |
| **node-exporter** | Host CPU/memory metrics |
| **GitHub Actions** | PR lint check (parallel to Jenkins) |

---

## What's Running Where

```
LOCAL (right now, no AWS needed)          CLOUD (after terraform apply)
──────────────────────────────            ─────────────────────────────────────
Your Mac via Docker Compose               AWS EC2: cloudpulse-app-server
  ├── frontend      (port 80)               ├── frontend      (port 80)
  ├── product-svc   (port 5001)             ├── product-svc   (port 5001)
  ├── order-svc     (port 5002)             ├── order-svc     (port 5002)
  ├── prometheus    (port 9090)             ├── prometheus    (port 9090)
  ├── grafana       (port 3000)             └── grafana       (port 3000)
  └── node-exporter (port 9100)
                                          AWS EC2: cloudpulse-jenkins-server
                                            └── Jenkins       (port 8080)
```

---

## OPTION A — Run Locally (No AWS, No Cost)

**Prerequisites:** Docker Desktop, Git

```bash
# 1. Clone
git clone https://github.com/manoharkonala/cloudpulse.git
cd cloudpulse

# 2. Start everything
docker-compose up --build -d

# 3. Open in browser
open http://localhost           # Frontend dashboard
open http://localhost:9090      # Prometheus
open http://localhost:3000      # Grafana (admin / admin123)
```

---

## OPTION B — Full Cloud Deployment (AWS + Jenkins CI/CD)

### Credentials you need before starting

| Credential | Where to get it | Used by |
|---|---|---|
| AWS Access Key ID | AWS Console → IAM → Users → Security credentials | Terraform |
| AWS Secret Access Key | Same as above | Terraform |
| DockerHub username | hub.docker.com (your username: `manohar122`) | Jenkinsfile |
| DockerHub password/token | hub.docker.com → Account Settings → Security → New Access Token | Jenkins |
| SSH private key | Already on your machine: `~/.ssh/id_ed25519` | Jenkins + Terraform |
| GitHub repo URL | `https://github.com/manoharkonala/cloudpulse` | Jenkins webhook |

---

### Step 1 — Configure AWS credentials

```bash
aws configure
```

Enter when prompted:
```
AWS Access Key ID:     <your-access-key-id>
AWS Secret Access Key: <your-secret-access-key>
Default region name:   us-east-1
Default output format: json
```

Verify it works:
```bash
aws sts get-caller-identity
# Should print your AWS account ID and username
```

---

### Step 2 — Provision AWS infrastructure with Terraform

```bash
cd infrastructure/terraform

# Download AWS provider
terraform init

# Preview what will be created (no cost, no changes)
terraform plan

# Create everything on AWS (~3 minutes)
terraform apply
# Type: yes when prompted
```

Terraform creates:
- VPC `10.0.0.0/16` with public subnet
- Internet Gateway + route table
- Security group (ports: 22, 80, 3000, 5001, 5002, 8080, 9090)
- **cloudpulse-app-server** — EC2 t2.micro with Docker pre-installed
- **cloudpulse-jenkins-server** — EC2 t2.micro with Jenkins pre-installed

At the end you will see:
```
app_server_public_ip    = "X.X.X.X"
jenkins_server_public_ip = "Y.Y.Y.Y"
jenkins_url             = "http://Y.Y.Y.Y:8080"
app_url                 = "http://X.X.X.X"
```

Save these IPs — you will need them in the next steps.

---

### Step 3 — Start the app on EC2

```bash
# SSH into app server (replace with your actual IP from terraform output)
ssh -i ~/.ssh/id_ed25519 ubuntu@<APP_SERVER_IP>

# Inside the EC2 — bootstrap the app
bash <(curl -s https://raw.githubusercontent.com/manoharkonala/cloudpulse/main/scripts/setup-ec2.sh)
```

This script:
- Installs Docker + Docker Compose (if not already done)
- Clones the repo to `/opt/cloudpulse`
- Runs `docker-compose up -d`
- Prints all access URLs

After it finishes, open in browser:
```
http://<APP_SERVER_IP>          ← CloudPulse dashboard
http://<APP_SERVER_IP>:9090     ← Prometheus
http://<APP_SERVER_IP>:3000     ← Grafana (admin / admin123)
```

---

### Step 4 — Set up Jenkins

**4a. Get the initial admin password**

```bash
# SSH into Jenkins server
ssh -i ~/.ssh/id_ed25519 ubuntu@<JENKINS_SERVER_IP>

# Print the unlock password
sudo cat /var/lib/jenkins/secrets/initialAdminPassword
```

Copy that password.

**4b. Open Jenkins in browser**

Go to: `http://<JENKINS_SERVER_IP>:8080`

1. Paste the admin password → click **Continue**
2. Click **Install suggested plugins** → wait ~2 minutes
3. Create admin user:
   - Username: `admin`
   - Password: `admin123`
   - Full name: `CloudPulse Admin`
   - Email: your email
4. Click **Save and Finish** → **Start using Jenkins**

**4c. Install additional required plugins**

Go to: `Manage Jenkins → Plugins → Available plugins`

Search and install each:
- `Docker Pipeline`
- `SSH Agent`

Click **Install** → tick **Restart Jenkins when installation is complete**

**4d. Add credentials**

Go to: `Manage Jenkins → Credentials → System → Global credentials → Add Credentials`

Add these 3 credentials exactly:

| Kind | ID | What to enter |
|---|---|---|
| Username with password | `dockerhub-credentials` | Username: `manohar122` / Password: your DockerHub password or access token |
| Secret text | `APP_SERVER_IP` | The app server public IP from terraform output |
| SSH Username with private key | `APP_SERVER_SSH_KEY` | Username: `ubuntu` / Private key: paste contents of `~/.ssh/id_ed25519` |

To get your private key content:
```bash
cat ~/.ssh/id_ed25519
# Copy everything including -----BEGIN and -----END lines
```

**4e. Create the pipeline job**

1. Click **New Item**
2. Name: `CloudPulse`
3. Select **Pipeline** → click **OK**
4. Under **Build Triggers**: tick **GitHub hook trigger for GITScm polling**
5. Under **Pipeline**:
   - Definition: `Pipeline script from SCM`
   - SCM: `Git`
   - Repository URL: `https://github.com/manoharkonala/cloudpulse.git`
   - Branch: `*/main`
   - Script Path: `Jenkinsfile`
6. Click **Save**

---

### Step 5 — Add GitHub Webhook

Go to: [github.com/manoharkonala/cloudpulse/settings/hooks](https://github.com/manoharkonala/cloudpulse/settings/hooks)

Click **Add webhook**:
```
Payload URL:   http://<JENKINS_SERVER_IP>:8080/github-webhook/
Content type:  application/json
Trigger:       Just the push event
Active:        ✅ ticked
```

Click **Add webhook**.

---

### Step 6 — Trigger your first pipeline run

```bash
# Make any small change to the code
cd /Users/lalitsingh/PROJECTS/Dev_ops/CloudPulse
# e.g. edit a product name in services/product-service/app.py

git add .
git commit -m "demo: trigger pipeline"
git push origin main
```

Then open `http://<JENKINS_SERVER_IP>:8080` — you will see the build trigger automatically within seconds and run through all 6 stages:

```
Checkout → Lint & Test → Build Images → Push DockerHub → Deploy EC2 → Health Check
```

---

## API Reference

### Product Service — port 5001

| Method | Path | Body | Description |
|---|---|---|---|
| GET | `/products` | — | List all products |
| GET | `/products/<id>` | — | Get single product |
| POST | `/products` | `{name, price, stock}` | Create product |
| GET | `/health` | — | Health check |
| GET | `/metrics` | — | Prometheus metrics |

### Order Service — port 5002

| Method | Path | Body | Description |
|---|---|---|---|
| GET | `/orders` | — | List all orders |
| GET | `/orders/<id>` | — | Get single order |
| POST | `/orders` | `{product_id, quantity}` | Create order (validates product exists) |
| GET | `/health` | — | Health check |
| GET | `/metrics` | — | Prometheus metrics |

---

## Monitoring

### Prometheus — `http://<IP>:9090`
- **Status → Targets**: all 4 jobs should show `UP`
- Try PromQL: `orders_created_total`
- Try PromQL: `rate(flask_http_request_total[1m])`

### Grafana — `http://<IP>:3000` (admin / admin123)
Dashboard **CloudPulse Operations** auto-loads with 8 panels:

| Panel | Metric |
|---|---|
| Orders Created Total | `sum(orders_created_total)` |
| Service Health Status | `up{job=~"product-service\|order-service"}` |
| Node Memory Usage % | `(node_memory_MemTotal_bytes - node_memory_MemAvailable_bytes) / node_memory_MemTotal_bytes * 100` |
| Order Processing p95 | `histogram_quantile(0.95, rate(order_processing_seconds_bucket[5m]))` |
| HTTP Requests/s | `rate(flask_http_request_total[1m])` |
| Node CPU Usage % | `100 - (avg(rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100)` |
| Order p95/p50 over time | Histogram quantiles |
| Orders/min | `rate(orders_created_total[1m]) * 60` |

---

## Git Branch Strategy

```
main      ← production; every push triggers Jenkins deploy
  └── develop     ← integration branch
        └── feature/add-products-api
        └── fix/order-validation-bug
```

```bash
# Demo branching live during presentation
git checkout -b feature/demo-change
# make a small edit
git add . && git commit -m "demo: show branching"
git push origin feature/demo-change
# open PR on GitHub → merge to main → Jenkins fires
```

---

## Presentation Demo Script

Follow this order to show every tool:

1. **GitHub** — show repo, branches, commits, webhook settings
2. **Jenkinsfile** — walk through the 6 stages, explain parallel builds
3. **Live trigger** — push a small change, watch Jenkins pick it up in real time
4. **DockerHub** — show `manohar122/cloudpulse-*` images with build number tags
5. **Terraform files** — open `infrastructure/terraform/main.tf`, run `terraform plan` to show execution plan
6. **AWS Console** — show 2 running EC2 instances, point to public IPs
7. **CloudPulse frontend** — open `http://<APP_IP>`, create a product, place an order
8. **Prometheus** — open Targets page (all green), run a live PromQL query
9. **Grafana** — open CloudPulse Operations dashboard, explain each panel
10. **docker-compose.yml** — explain `cloudpulse-net` bridge, `depends_on`, volumes, health checks

---

## Tear Down (avoid ongoing AWS charges)

```bash
cd infrastructure/terraform
terraform destroy
# Type: yes when prompted
# All EC2 instances, VPC, and security groups are deleted
```

---

## Quick Reference

```bash
# Local
docker-compose up -d            # start all services
docker-compose down             # stop all
docker-compose logs -f          # stream logs
docker-compose ps               # show status

# Terraform
cd infrastructure/terraform
terraform init
terraform plan
terraform apply
terraform output                # print IPs after apply
terraform destroy               # tear down

# SSH to EC2
ssh -i ~/.ssh/id_ed25519 ubuntu@<IP>

# Test APIs directly
curl http://localhost:5001/products
curl http://localhost:5002/orders
curl http://localhost:5001/metrics
curl http://localhost:5001/health
```
