# Notiflex Platform

B2B notification SaaS platform. This repo is primarily a **hands-on project for building and operating a production-grade Kubernetes environment**.

## Stack
- **Language:** Go, standard library only (no third-party frameworks unless explicitly approved)
- **Base image:** `scratch` — binaries must be **statically linked** (`CGO_ENABLED=0`)
- **Cluster:** GKE (Standard) on GCP — **Gateway API** enabled (`channel=standard`, i.e. `networkConfig.gatewayApiConfig.channel=CHANNEL_STANDARD`)
- **GitOps:** GitHub Actions builds/pushes images; **ArgoCD** syncs manifests from this repo
- **Manifests:** plain Kubernetes YAML + `kubectl kustomize` (no separate `kustomize` binary)

## Repository Layout
```
app/                  # Go service(s)
k8s/                  # Kubernetes manifests, synced by ArgoCD
k8s/smb/              # SMB storage manifests
k8s/argocd/           # ArgoCD Application CRs + namespace (apply after terraform/cluster is up)
scripts/              # cluster create/delete shell scripts (legacy, bash+gcloud)
terraform/persistent/ # WIF pool/provider, CI service account, IAM — project-level, rarely touched
terraform/cluster/    # GKE cluster + ArgoCD Helm release — destroy/apply freely (Spot, ephemeral)
.github/workflows/    # CI: build, test, push image
```

## Working Principles (always follow)
- **Inspect before acting.** Before running a command, check current state first (e.g. `kubectl get`, `git status`). Before editing a file, **read its current contents first**.
- **Analyze errors before fixing.** On failure: identify root cause → propose a fix → proceed only after it's clear. Do not blindly retry.
- **Assess blast radius before create/delete.** Before creating or deleting any resource, state what it affects (cluster, namespace, data, other services) first.
- **GitOps discipline.** `k8s/` is the source of truth. Change manifests via Git; let ArgoCD apply them. Do **not** `kubectl apply` directly to the cluster except for investigation.

## Naming Conventions
- Every manifest **must set `metadata.namespace` explicitly**. Never rely on the `default` namespace.
- Resource names: lowercase, hyphenated, DNS-subdomain compliant (`notiflex-api`, not `NotiflexApi`).
- Use the standard Kubernetes recommended labels on every workload:
  ```yaml
  metadata:
    namespace: notiflex
    labels:
      app.kubernetes.io/name: notiflex-api
      app.kubernetes.io/component: api
      app.kubernetes.io/part-of: notiflex
  ```

## Environment
- **GCP project:** `bubbly-subject-501015-t9` · **region/zone:** `us-central1` / `us-central1-a`
- **Artifact Registry:** `us-central1-docker.pkg.dev/bubbly-subject-501015-t9/containers`
- **Cluster:** `notiflex` (Spot — check live state with `make cluster-status`)

## Security (hard rules)
- **Never hardcode secrets** — tokens, API keys, passwords — in code or in manifests.
  - In-cluster: read from `Secret` resources (env var refs or volume mounts), sourced from a secret manager.
  - In Go: read from environment variables, never literals.
- **Pin every image tag explicitly.** No `:latest`. Use an immutable version tag or a `@sha256:` digest. (The runtime base is `scratch`; this rule applies to the built application images and any sidecars.)

## Go Build Constraints
Because the base image is `scratch`:
- Build with `CGO_ENABLED=0` and `-ldflags="-s -w"` for a static, stripped binary.
- Target `GOOS=linux GOARCH=amd64` (or the cluster's arch).
- No OS packages, no shell inside the container — logs to stdout/stderr only.

## Automation
Cluster lifecycle and image build/push live in `scripts/` + `Makefile`. **Run `make help`** for targets; each `scripts/*.sh` header documents its env-var overrides. Two rules to remember:
- **Cluster is Spot** — ephemeral; recreate freely with `make cluster-delete` / `make cluster-create`.
- **Image tag = git short SHA** — manifests in `k8s/` reference the SHA (or `@sha256:` digest), **never `:latest`**.

- **GKE cluster + ArgoCD are managed via Terraform** (`cd terraform/cluster && terraform apply` / `terraform destroy`) so they're reproducible across the frequent teardown/rebuild cycles this project uses for learning.
- **WIF/IAM stays in a separate root module** (`terraform/persistent`), applied once and left alone — **do not fold it into `terraform/cluster`**. GCP soft-deletes a Workload Identity Pool for 30 days and won't let you recreate the same pool ID until that window passes, so if WIF lived in the same state as the cluster, a routine `terraform destroy` on the cluster would break CI for up to 30 days. State is local (`terraform/**/*.tfstate`, gitignored). After `terraform apply` in `terraform/cluster`, run `kubectl apply -f k8s/argocd` to register the Application CRs.
