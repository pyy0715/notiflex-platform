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
terraform/iam/        # WIF pool/provider, CI service account, IAM — project-level, apply once
terraform/cluster/    # GKE cluster + ArgoCD Helm release — destroy/apply freely (Spot, ephemeral)
.github/workflows/    # CI: test, build, push image (all logic lives in the workflow YAML), update manifest tag
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
- **GKE cluster + ArgoCD**: `cd terraform/cluster && terraform apply` / `terraform destroy`. Ephemeral by design — this project tears the cluster down and rebuilds it often for learning, so both live in Terraform for reproducibility. After `apply`, run `kubectl apply -f k8s/argocd` to register the Application CRs (kept as plain manifests, not folded into Terraform, since ArgoCD itself already manages them via GitOps once installed).
- **WIF/IAM**: `terraform/iam`, a separate root module — **never merge it into `terraform/cluster`**. GCP soft-deletes a Workload Identity Pool for 30 days and won't let you recreate the same pool ID until that window passes, so if WIF shared state with the cluster, a routine cluster teardown would break CI for up to a month. Apply once, leave alone.
- Terraform state is local and gitignored (`terraform/**/*.tfstate`) — no remote backend.
- **Image build/push** happens only in CI (`.github/workflows/build-and-push.yml`) — there's no local build script anymore. It reads `VERSION`, builds for `linux/amd64` (must match the GKE node arch — building on Apple Silicon without pinning platform produces an arm64 image GKE can't pull), injects `VERSION`/`COMMIT` via build args, and pushes the git-short-SHA + `:latest` tags.
- **Image tag = git short SHA** — manifests in `k8s/` reference the SHA (or `@sha256:` digest), **never `:latest`**. CI updates `k8s/smb/deployment.yaml`'s tag and commits it automatically (as `github-actions[bot]`) after a successful push — that commit only touches `k8s/smb/`, which isn't in this workflow's trigger paths, so it doesn't retrigger the build.
