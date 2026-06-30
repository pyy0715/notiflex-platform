# Notiflex Platform

B2B notification SaaS platform. This repo is primarily a **hands-on project for building and operating a production-grade Kubernetes environment**.

## Stack
- **Language:** Go, standard library only (no third-party frameworks unless explicitly approved)
- **Base image:** `scratch` — binaries must be **statically linked** (`CGO_ENABLED=0`)
- **Cluster:** GKE (Standard), on GCP
- **GitOps:** GitHub Actions builds/pushes images; **ArgoCD** syncs manifests from this repo
- **Manifests:** plain Kubernetes YAML + `kubectl kustomize` (no separate `kustomize` binary)

> Tooling note: `gcloud` and `go` are **not yet installed** on this machine. Install both before GKE or build work.

## Repository Layout
```
app/                  # Go service(s)
k8s/                  # Kubernetes manifests, synced by ArgoCD
k8s/smb/              # SMB storage manifests
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

## Local Commands
- Validate manifests: `kubectl kustomize k8s/ | kubectl apply --dry-run=client -f -`
- ArgoCD CLI: `argocd app sync <app>` (only when GitOps flow is bypassed intentionally)
