# Notiflex Platform

B2B notification SaaS platform. This repo is primarily a **hands-on project for building and operating a production-grade Kubernetes environment**.

## Stack
- **Language:** Go, standard library only (no third-party frameworks unless explicitly approved)
- **Base image:** `scratch` — binaries must be **statically linked** (`CGO_ENABLED=0`)
- **Cluster:** GKE (Standard) on GCP — **Gateway API** enabled (`channel=standard`, i.e. `networkConfig.gatewayApiConfig.channel=CHANNEL_STANDARD`)
- **GitOps:** GitHub Actions builds/pushes images and commits the updated tag back to `k8s/`; **ArgoCD** syncs from there via a `root` Application (app-of-apps, see `k8s/apps/`)
- **Manifests:** plain Kubernetes YAML + `kubectl kustomize` (no separate `kustomize` binary)

## Repository Layout
```
app/                  # Go service(s)
k8s/                  # Kubernetes manifests, synced by ArgoCD
k8s/api/              # notiflex-api service manifests (Rollout + active/preview Services + Namespace) — blue/green via Argo Rollouts
k8s/gateway/          # Gateway API resources (Gateway + HTTPRoute + HealthCheckPolicy) — regional external LB, same namespace
k8s/monitoring/       # kube-prometheus-stack Helm values (chart is an ArgoCD multi-source Application, not vendored)
k8s/logging/          # Loki (single-binary) + Fluent Bit Helm values, same pattern as k8s/monitoring
k8s/bootstrap/        # ArgoCD controller install (Kustomize + upstream install.yaml + argocd-cm-rollout patch) — NOT GitOps-managed, applied by hand
k8s/bootstrap/rollouts/  # Argo Rollouts controller install (same hand-applied pattern as k8s/bootstrap)
k8s/apps/             # app-of-apps registry — root Application + child Applications (this IS what ArgoCD watches)
terraform/iam/        # WIF pool/provider, CI service account, IAM — independent of cluster lifecycle
terraform/cluster/    # GKE cluster + proxy-only subnet (for the regional external Gateway LB) — destroy/apply freely (Spot, ephemeral)
.github/workflows/    # CI: build, push image (all logic lives in the workflow YAML), update manifest tag
```

## Working Principles (always follow)
- **Inspect before acting.** Before running a command, check current state first (e.g. `kubectl get`, `git status`). Before editing a file, **read its current contents first**.
- **Analyze errors before fixing.** On failure: identify root cause → propose a fix → proceed only after it's clear. Do not blindly retry.
- **Assess blast radius before create/delete.** Before creating or deleting any resource, state what it affects (cluster, namespace, data, other services) first.
- **GitOps discipline.** `k8s/` is the source of truth. Change manifests via Git (by hand, or via CI's automated tag-bump commit) and let ArgoCD apply them. Do **not** `kubectl apply` directly to the cluster except for investigation.

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
- **GKE cluster**: `cd terraform/cluster && terraform apply` / `terraform destroy`. Ephemeral by design — this project tears the cluster down and rebuilds it often for learning. Terraform's job stops at "a cluster with a working API server" — nothing Kubernetes-native lives in this module. The module also provisions a **proxy-only subnet** (`google_compute_subnetwork.proxy_only`, purpose `REGIONAL_MANAGED_PROXY`, `10.0.0.0/23`, region `us-central1`) on the default network. This is a hard prerequisite for the regional external Application Load Balancer the Gateway uses — GKE does **not** create it for you. CIDR gotcha: the default network is auto-mode, which reserves the **entire `10.128.0.0/9`** block for its own per-region subnets, so any CIDR inside `10.128.0.0/9` (including naive picks like `10.128.32.0/23`) is rejected with `cannot overlap with 10.128.0.0/9`. Pick a `/23` inside `10.0.0.0/8` but outside `10.128.0.0/9`.
- **Full bootstrap order after a fresh `terraform apply` (cluster is ephemeral, this happens often):**
  1. `gcloud container clusters get-credentials notiflex --zone us-central1-a`
  2. `kubectl create secret generic grafana-admin-credentials -n monitoring --from-literal=admin-user=admin --from-literal=admin-password=<generate one>` — **must exist before the `monitoring` Application syncs**, or the Grafana pod fails to start (`grafana.admin.existingSecret` in `k8s/monitoring/values.yaml` references it, and it's intentionally never committed — see Security). Create the `monitoring` namespace first if `kubectl create secret` complains it doesn't exist yet (`kubectl create ns monitoring`).
  3. `kubectl create ns argocd` — **must exist first**. The upstream ArgoCD `install.yaml` does NOT contain a `Namespace` resource, and `k8s/bootstrap/kustomization.yaml` sets `namespace: argocd`, so `kubectl apply -k k8s/bootstrap` fails with `namespaces "argocd" not found` if the namespace isn't created beforehand. (Same gap applies to Argo Rollouts in step 4.)
  4. `kubectl apply -k k8s/bootstrap --server-side` — installs the ArgoCD controller itself (Kustomize referencing the upstream `install.yaml` at a pinned version tag) **plus the `argocd-cm-rollout.yaml` patch** that teaches ArgoCD the Rollout CRD's `spec.template.spec` is a `core/v1.PodSpec` (without it, Rollout manifests show a permanent false OutOfSync from k8s-injected pod defaults). **Server-side apply is required**: several CRDs here (and in kube-prometheus-stack/Loki, installed later) are too large for the `last-applied-configuration` annotation used by client-side apply and fail with `metadata.annotations: Too long`.
  5. `kubectl create ns argo-rollouts && kubectl apply -k k8s/bootstrap/rollouts --server-side` — installs the **Argo Rollouts controller** (v1.9.1, pinned). Same constraints as ArgoCD: the upstream `install.yaml` has no `Namespace` resource so create `argo-rollouts` first, and server-side apply is required for the large CRDs. This controller is the peer of `k8s/bootstrap` — a cluster-scoped controller installed by hand, **not** watched by any Application (installing it via GitOps would be circular, since the Rollout CRD must exist before ArgoCD can sync `kind: Rollout` manifests). `k8s/api/deployment.yaml` is now a `kind: Rollout` (blue/green via `activeService`/`previewService`); without this controller installed, the `notiflex-api` Application can't sync it.
  6. `kubectl apply -f k8s/apps/root-app.yaml` — registers the `root` Application, which points at `k8s/apps` (a pure app-of-apps registry containing only Application manifests: `notiflex-api-app.yaml`, `notiflex-gateway-app.yaml`, `monitoring-app.yaml`, `loki-app.yaml`, `fluent-bit-app.yaml`). From then on ArgoCD manages all child Applications automatically (`selfHeal`/`prune`), each with `ServerSideApply=true` set from the start so CRD-heavy charts don't repeat the same failure.
  7. **If `monitoring`'s Alertmanager/Prometheus never materialize** (`kubectl get statefulset -n monitoring` stays empty even though the Application shows `Synced`): the prometheus-operator pod started before its own CRDs existed and cached "not installed" at boot — it doesn't re-discover CRDs registered after it started. Fix: `kubectl rollout restart deployment monitoring-kube-prometheus-operator -n monitoring`. Whether this is still needed with `ServerSideApply=true` in place from the start (rather than added after the fact, as happened once) hasn't been re-verified on a clean bootstrap.
  - **`k8s/bootstrap` is intentionally NOT watched by any Application** — ArgoCD does not manage its own controller install via GitOps. To upgrade ArgoCD's version: bump the pinned tag in `k8s/bootstrap/kustomization.yaml`, push, then re-run `kubectl apply -k k8s/bootstrap --server-side` by hand. This is a deliberate split (controller install vs. the Application registry) — it makes "what does `root` manage" answer cleanly ("child Applications only") and matches how most real ArgoCD deployments operate.
  - Do not reintroduce a `helm_release`/`kubernetes` provider for ArgoCD in Terraform — that was a prior approach and it's been replaced.
  - **`k8s/monitoring`, `k8s/logging` are Helm chart values only** — the chart itself is referenced directly from its upstream repo via an ArgoCD multi-source Application (`k8s/apps/{monitoring,loki,fluent-bit}-app.yaml`), not vendored or rendered locally. Loki and Fluent Bit share the `monitoring` namespace with kube-prometheus-stack (core observability infra, not a separate concern — Helm release-prefixed names avoid collisions).
- **WIF/IAM**: `terraform/iam`, a separate root module — **never merge it into `terraform/cluster`**. GCP soft-deletes a Workload Identity Pool for 30 days and won't let you recreate the same pool ID until that window passes, so if WIF shared state with the cluster, a routine cluster teardown would break CI for up to a month. It changes rarely, but keeping it in its own state is what makes tearing down `terraform/cluster` safe to do freely.
- Terraform state is local and gitignored (`terraform/**/*.tfstate`) — no remote backend.
- **Image build/push** happens only in CI (`.github/workflows/build-and-push.yml`) — there's no local build script anymore. It reads `VERSION`, builds for `linux/amd64` (must match the GKE node arch — building on Apple Silicon without pinning platform produces an arm64 image GKE can't pull), injects `VERSION`/`COMMIT` via build args, and pushes the git-short-SHA + `:latest` tags.
- **Image tag = git short SHA** — manifests in `k8s/` reference the SHA (or `@sha256:` digest), **never `:latest`**. CI updates `k8s/api/deployment.yaml`'s tag and commits it automatically (as `github-actions[bot]`) after a successful push — that commit only touches `k8s/api/`, which isn't in this workflow's trigger paths, so it doesn't retrigger the build.
