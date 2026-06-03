# LifeOS Agent Trace Ingest

轻量自建 Agent trace 收集服务。它负责鉴权、及时写入 JSONL、按条件查询 trace，并提供一个受保护的浏览器 Dashboard。

## 部署

1. 把 `trace.dogdada.com` 的 A 记录指向服务器 `82.157.197.163`。
2. 登录服务器，安装 Docker 和 Docker Compose。
3. 上传本目录到服务器，例如 `/opt/lifeos-agent-trace-ingest`。
4. 复制环境文件并填入长随机 token 和 Dashboard 登录信息：

```bash
cp .env.example .env
mkdir -p /var/lib/lifeos-traces
mkdir -p /var/lib/lifeos-growth
docker compose up -d --build
```

`.env` 字段：

```text
PORT=8787
TRACE_DIR=/var/lib/lifeos-traces
GROWTH_DIR=/var/lib/lifeos-growth
TRACE_TOKEN=App 和 Worker 上传 trace 使用的共享 token
DASHBOARD_USER=Dashboard 登录账户
DASHBOARD_PASSWORD=Dashboard 登录密码
DASHBOARD_SESSION_SECRET=Dashboard cookie 签名密钥，建议使用另一串长随机值
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

## Dashboard

浏览器打开：

```text
https://trace.dogdada.com/dashboard
```

功能：

- 账户/密码登录，登录会话存 HttpOnly Cookie。
- 按日期、`traceId`、关键词、来源、错误状态过滤。
- 左侧按最新 trace 倒序展示摘要，中间展示单条 trace 时间线，右侧展示格式化 JSON。
- `Growth Ops` tab 管理小红书日更运营流：参考帖、选题、草稿、发布包和复盘。
- Dashboard API 不使用 `TRACE_TOKEN` 暴露给浏览器，只依赖登录 cookie。
- `Growth Ops` API 读写 `GROWTH_DIR`；本地开发默认读仓库 `docs/operations/growth/xiaohongshu`，线上建议挂载 `/var/lib/lifeos-growth`。

如果服务器使用 systemd 部署，更新代码和 `.env` 后重启：

```bash
sudo systemctl restart lifeos-agent-trace
sudo systemctl status lifeos-agent-trace --no-pager
```

## 数据

服务按天追加写入：

```text
/var/lib/lifeos-traces/YYYY-MM-DD.jsonl
```

每行是一个完整 JSON event。写入成功后才返回 `200`，方便把服务器作为唯一 trace 来源。旧日志可通过 `POST /v1/traces/gzip` 压缩为 `.gz`，不会默认删除原始 JSONL。
