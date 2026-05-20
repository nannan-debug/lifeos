# LifeOS Agent Trace Ingest

轻量自建 Agent trace 收集服务。它只做三件事：鉴权、及时写入 JSONL、按 `traceId` 查询。

## 部署

1. 把 `trace.dogdada.com` 的 A 记录指向服务器 `82.157.197.163`。
2. 登录服务器，安装 Docker 和 Docker Compose。
3. 上传本目录到服务器，例如 `/opt/lifeos-agent-trace-ingest`。
4. 复制环境文件并填入长随机 token：

```bash
cp .env.example .env
mkdir -p /var/lib/lifeos-traces
docker compose up -d --build
```

5. 用 Nginx 或 Caddy 把 `https://trace.dogdada.com` 反代到 `http://127.0.0.1:8787`。

## 接入

Cloudflare Worker 需要配置：

```bash
cd CloudflareWorkers/personal-ai-proxy
npx wrangler secret put TRACE_INGEST_URL
npx wrangler secret put TRACE_INGEST_TOKEN
```

iOS 需要在本地未提交的 `Sources/Services/Secrets.swift` 里填入同一个 endpoint/token；仓库里的 `Secrets.example.swift` 已给出字段模板。

## 接口

```bash
curl https://trace.dogdada.com/health
curl -H "X-LifeOS-Trace-Token: $TRACE_TOKEN" \
  "https://trace.dogdada.com/v1/traces/events?date=2026-05-20&traceId=abc"
```

## 数据

服务按天追加写入：

```text
/var/lib/lifeos-traces/YYYY-MM-DD.jsonl
```

每行是一个完整 JSON event。写入成功后才返回 `200`，方便把服务器作为唯一 trace 来源。旧日志可通过 `POST /v1/traces/gzip` 压缩为 `.gz`，不会默认删除原始 JSONL。
