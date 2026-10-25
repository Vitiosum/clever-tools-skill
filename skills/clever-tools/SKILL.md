---
name: clever-tools
description: Use when deploying, configuring, scaling or debugging an application on Clever Cloud with the clever-tools CLI (`clever` command) — creating an app or add-on (PostgreSQL, MySQL, Redis, Cellar), moving a Dockerfile to a native runtime, setting environment variables, reading build or runtime logs, or when a deploy fails with "not listening on 8080", "Killed", or a health check error. Also "déployer sur Clever Cloud", "mon déploiement Clever échoue".
---

# clever-tools

## Overview

Clever Cloud deploys a **git commit** onto a native runtime (Node, Python, PHP, Go, Java, Rust, .NET, static, Docker…). The `clever` CLI drives everything. Most failures come from four things: the app not listening on `0.0.0.0:8080`, an env var the code expects, too little memory for the flavor, or uncommitted changes.

## Agent rules (the CLI is interactive by default)

| Command | Problem for an agent | Do instead |
|---|---|---|
| `clever login` | opens a browser | run `clever profile` first; if not logged in, ask the user to run `clever login` (or export `CLEVER_TOKEN` + `CLEVER_SECRET`) |
| `clever logs` | streams forever, never returns | always bound it: `clever logs --since 15m --until now` |
| `clever addon create` (paid plan) | waits for confirmation | add `--yes`, after the user agreed on the plan |
| `clever open` / `clever console` | opens the **Console**, not the app | get the URL with `clever domain`, then `curl -i https://<domain>/` |
| `clever deploy` | pushes **HEAD only** | `git status` clean and changes committed before deploying |
| `clever delete`, `clever addon delete` | irreversible | never without explicit user confirmation |

Never print secret values: use `clever env | grep -oE '^[A-Za-z_][A-Za-z0-9_]*='` to list names (a `sed` on `=` would print the following lines of a multi-line value). A real secret comes from the user; a test value can be generated inline: `clever env set API_KEY "$(openssl rand -hex 24)" >/dev/null`.

**Which app?** Commands target the app in `.clever.json`. Not linked: `clever link <app-id|name> --org <org>`. Several apps: `clever applications`, then `--app <id>` (or `--alias`). Org IDs: `clever curl https://api.clever-cloud.com/v2/organisations`.

## Deploy from scratch

```bash
clever profile                                   # logged in? which user?
clever create --type node my-app --org <org-id-or-name> --region par   # writes .clever.json
clever addon create postgresql-addon my-db --plan xxs_tny --region par \
  --org <org> --option encryption=true --link my-app   # paid: add --yes only after the user agreed on plan and price; injects POSTGRESQL_ADDON_*
clever env set CC_POST_BUILD_HOOK "npm run build"   # if package.json has a build step (Next.js, Vite, TypeScript…)
git status --short                               # review what would be committed (no .env, no secrets)
git add <the files you changed> && git commit -m "Deploy to Clever Cloud"
clever deploy                                    # streams build + deploy logs, exits at the end
clever domain                                    # → app-xxxx.cleverapps.io
curl -i https://<domain>/
```

- Before the first commit, check `git rev-parse --show-toplevel` is the app folder: a parent repo (e.g. the home directory) would swallow the commit. If not, `git init`, and a `.gitignore` with `node_modules` (no trailing slash, it also covers a symlink) before the first commit. `clever deploy` refuses linked git worktrees: deploy another branch with `--branch <name>`.
- Regions: `par` (Paris), `parhds` / `rbxhds` / `grahds` (health data, HDS), others in `clever create --help`. Plans per add-on: `clever addon providers show postgresql-addon`.
- Region and org must be the same for app and add-on. Encryption at rest is chosen **only at creation**.
- PostgreSQL plans: `dev` = shared, 5 connections, no backups (tests only); `xxs_tny` (the smallest) and up = dedicated, 45+ connections, daily backups. Size the DB pool below the plan limit × instances.
- Read the add-on variables (`POSTGRESQL_ADDON_URI`, `MYSQL_ADDON_URI`, `REDIS_URL`, `CELLAR_ADDON_*`) **in the code** (`process.env.DATABASE_URL || process.env.POSTGRESQL_ADDON_URI`). Copying the value into another variable freezes it.
- Check the injected variables: `clever env | grep -oE '^[A-Za-z_][A-Za-z0-9_]*='`.
- Env changes need `clever restart`. `clever deploy` and `clever restart` stream logs and return once the deployment ends (OK or FAIL). Same commit again → `clever restart` or `clever deploy --same-commit-policy restart`.

## Code requirements

- Listen on `process.env.PORT` (8080) and host `0.0.0.0`, never `localhost`/`127.0.0.1` or a hard-coded port.
- Pin the runtime version the native way (Node: `"engines": { "node": "22" }` in `package.json`).
- The Node runtime runs `npm install`, not `npm run build`: set `CC_POST_BUILD_HOOK`. Do not set `NODE_ENV=production` before the build if a devDependency is needed to build.
- Start command from the runtime convention (`npm start` / `package.json` `scripts.start` for Node), or `CC_RUN_COMMAND`. Build steps: `CC_PRE_BUILD_HOOK`, `CC_POST_BUILD_HOOK`; migrations: `CC_PRE_RUN_HOOK`.
- Filesystem is ephemeral: files go to Cellar (S3) or a FS Bucket.

## Diagnose a failed deploy

```bash
clever activity                                  # last deployments, OK/FAIL
clever logs --since 30m --until now              # bounded: build + run logs
clever logs --deployment-id <id> --until now     # one deployment
clever status                                    # flavor, instances, state
```

**"Your application is not listening on 8080" is a symptom, not a cause.** Read the lines *above* it:

| Line above the error | Cause | Fix |
|---|---|---|
| `Killed  npm start` (no stack trace) | out of memory at runtime (OOM killer) | `clever scale --flavor XS` (or reduce memory at boot) |
| `JavaScript heap out of memory` | Node heap limit, set per flavor by Clever (`--max-old-space-size`) | bigger flavor; do not raise `NODE_OPTIONS` above the flavor RAM |
| `listening on localhost:3000` (or any other port/host) | wrong bind | `0.0.0.0` + `process.env.PORT` |
| stack trace with `undefined` (`key`, `url`, `connectionString`…) | missing env var | find the variable in the code at the trace line, `clever env set NAME value`, `clever restart` |
| starts fine, then a stack trace right after (health check calls `/`) | crash on the first request, often a missing env var | read the trace, fix, then test the route with `curl` |
| `ECONNREFUSED` / auth failure to DB | add-on not linked, or wrong variable name | `clever service link-addon <addon>`, read `*_ADDON_*` vars |

A `503` for ~20 s right after a successful deploy is routing propagation: retry `curl` before diagnosing. A failed health check takes about 4 minutes: once the cause is visible in the logs, fix it without waiting. The build runs on a separate build instance (`clever scale --build-flavor M` if the **build** itself is killed).

## From a Dockerfile to a native runtime

The runtime is fixed by `clever create --type` (`docker` or `node`, `python`…): a native app ignores the Dockerfile, no need to delete it. Try both side by side from the same repo: `clever create --type node <name> --alias native`, then `clever deploy --alias native`.

| Dockerfile | Native equivalent |
|---|---|
| `FROM node:22` / `python:3.13` | `--type node` + `engines` / `--type python` + `CC_PYTHON_VERSION` |
| `RUN npm ci` / `pip install` | automatic at build |
| `RUN npm run build` | `CC_POST_BUILD_HOOK="npm run build"` (the Node runtime does not run `scripts.build` by itself) |
| `CMD …` | `scripts.start` / `CC_RUN_COMMAND` |
| `ENV X=…` | `clever env set X …` |
| `EXPOSE 3000` / `ENV PORT=3000` | ignored: Clever sets `PORT=8080`, in Docker too |
| `RUN apk/apt install <pkg>` | see below |

System packages: native images already ship many tools (verified: `ffmpeg`, ImageMagick `convert`/`magick`, `chromium`, `libreoffice`, `tesseract`, `gs`, `pdftotext`, `wkhtmltopdf`, `gdal`, `exiftool`, `vips`, `rsvg-convert`; absent: `pandoc`, `qpdf`). Never guess: list them with a hook and read the restart logs (`clever ssh --command` needs a terminal: it failed from a non-interactive agent shell on the Docker runtime):
`clever env set CC_PRE_RUN_HOOK 'for b in convert pandoc; do command -v $b >/dev/null && echo "TOOL ok $b" || echo "TOOL missing $b"; done'`, `clever restart`, then `clever env rm CC_PRE_RUN_HOOK`.

Missing tool with a static Linux binary: download it in `CC_PRE_BUILD_HOOK` into the app folder (network is allowed at build, files persist to runtime), point the code at it with an env var (`./bin/pandoc`), then `clever restart --without-cache`. No static binary, or many native libraries: stay on the Docker runtime, it is fully supported.

The health check only calls `/`: `curl` **every** route that uses a system tool before concluding.

## Scale and cost

```bash
clever scale --flavor nano                      # fixed size: pico nano XS S M L XL
clever scale --min-flavor nano --max-flavor XS --min-instances 1 --max-instances 2
clever stop                                     # stops compute billing (add-ons still billed)
```

Lowering `--min-flavor` does not shrink a running instance: set `--flavor <small>`, `clever restart`, then set the range again.

## Common mistakes

- Deploying with uncommitted changes and wondering why nothing changed.
- Trusting the health-check message instead of the log line above it.
- Running `clever logs` without `--until` in a non-interactive shell.
- Using the `dev` PostgreSQL plan for a demo with several instances (5 connections).
- Reporting success without `curl` on the app domain.
