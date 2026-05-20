#!/usr/bin/env python3
"""
LifeOS Agent 本地实验脚本
用法：python3 scripts/agent_lab.py

功能：
1. 交互式聊天 —— 像 App 一样和 Agent 对话，实时看返回的 JSON
2. 批量测试 —— 跑一组预设用例，检查回复质量和 actionSuggestions
3. 单次调用 —— 快速测试一句话
4. 执行追踪 —— 自动记录每次调用的 token、延迟、上下文，支持 review 和评分

不依赖 iOS 模拟器，秒级反馈，适合调 prompt 和调试 Worker。
"""

import requests
import json
import sys
import os
import time
import uuid
from datetime import datetime

# ── Trace 追踪系统 ──────────────────────────────────────
TRACE_DIR = os.path.join(os.path.dirname(__file__), "traces")


def _ensure_trace_dir():
    os.makedirs(TRACE_DIR, exist_ok=True)


def _trace_file(date_str=None):
    """返回当天的 trace JSONL 文件路径"""
    date_str = date_str or datetime.now().strftime("%Y-%m-%d")
    return os.path.join(TRACE_DIR, f"{date_str}.jsonl")


def save_trace(trace):
    """追加一条 trace 到当天的 JSONL 文件"""
    _ensure_trace_dir()
    with open(_trace_file(), "a", encoding="utf-8") as f:
        f.write(json.dumps(trace, ensure_ascii=False) + "\n")


def load_traces(date_str=None, rating_filter=None):
    """读取指定日期的所有 trace，可按 rating 过滤"""
    path = _trace_file(date_str)
    if not os.path.exists(path):
        return []
    traces = []
    with open(path, "r", encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            t = json.loads(line)
            if rating_filter and t.get("rating") != rating_filter:
                continue
            traces.append(t)
    return traces


def update_trace_rating(trace_id, rating, note=""):
    """给指定 trace 打标（重写当天文件）"""
    path = _trace_file()
    if not os.path.exists(path):
        print(f"  [未找到今天的 trace 文件]")
        return False
    traces = []
    found = False
    with open(path, "r", encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            t = json.loads(line)
            if t.get("trace_id", "").startswith(trace_id):
                t["rating"] = rating
                t["rating_note"] = note
                found = True
            traces.append(t)
    if not found:
        print(f"  [未找到 trace_id 以 {trace_id} 开头的记录]")
        return False
    with open(path, "w", encoding="utf-8") as f:
        for t in traces:
            f.write(json.dumps(t, ensure_ascii=False) + "\n")
    return True


def trace_call(mode, input_text, data, latency_ms, context_meta=None):
    """构建并保存一条 trace 记录"""
    usage = data.get("usage") or {}
    actions = data.get("actionSuggestions", [])
    trace = {
        "trace_id": str(uuid.uuid4())[:8],
        "timestamp": datetime.now().isoformat(),
        "mode": mode,
        "input": input_text,
        "context_injected": context_meta or {},
        "response": {
            "reply_len": len(data.get("reply", "")),
            "has_followup": bool(data.get("followUpQuestion")),
            "actions_count": len(actions),
            "action_kinds": [a.get("kind") for a in actions],
            "has_error": "error" in data,
        },
        "tokens": {
            "prompt": usage.get("prompt_tokens", 0),
            "completion": usage.get("completion_tokens", 0),
            "total": usage.get("total_tokens", 0),
            "cached": usage.get("prompt_tokens_details", {}).get("cached_tokens", 0),
        },
        "latency_ms": round(latency_ms),
        "rating": None,
        "rating_note": "",
    }
    save_trace(trace)
    return trace

# ── 配置 ──────────────────────────────────────────────
WORKER_URL = "https://ai.dogdada.com"
CLIENT_SECRET = "pnsys_k7j4mL2nQ8vW5xR9tY3bH6sA1fE0dC4zU"

HEADERS = {
    "Content-Type": "application/json",
    "X-Client-Secret": CLIENT_SECRET,
}

# ── 模拟上下文（可以随意改，测试不同场景）──────────────
SAMPLE_CONTEXT = """近期随手记：
- 想法：面试官是业务小伙伴，非项目负责人，氛围轻松。
- 感受：面试感觉不符合预期，对方需要更成熟的Agent垂类经验
- 时间记录：10:00-11:00 面试普林，对方希望更成熟的Agent产品经验

当前待办：
- 提交材料（2026-05-19）
- 确定下面试目标！

今天时间记录：
- 00:19-07:39 睡觉 / 睡觉
- 10:00-11:00 pollo.ai面试-一面 / 工作
- 11:00-12:00 生数科技面试 / 工作

今日打卡：
- 吃药：留白
- 冥想：留白
- 写日记：留白"""


def now_date():
    return datetime.now().strftime("%Y-%m-%d")


def now_time():
    return datetime.now().strftime("%H:%M")


# ── 核心：调 Worker 的 chat 接口 ─────────────────────
def chat(input_text, messages=None, context_summary=None):
    """
    调用 Worker 的 chat 模式。
    messages: 历史消息列表 [{"role": "user", "content": "..."}, ...]
    context_summary: LifeOS 上下文摘要
    """
    ctx = context_summary or SAMPLE_CONTEXT
    msgs = messages or []
    body = {
        "mode": "chat",
        "input": input_text,
        "messages": msgs,
        "contextSummary": ctx,
        "currentDate": now_date(),
        "currentTime": now_time(),
    }
    t0 = time.time()
    try:
        resp = requests.post(WORKER_URL, headers=HEADERS, json=body, timeout=30)
        latency_ms = (time.time() - t0) * 1000
        if not resp.ok:
            try:
                err_body = resp.json()
            except Exception:
                err_body = {"raw": resp.text[:300]}
            data = {"error": f"http_{resp.status_code}", "detail": err_body}
        else:
            data = resp.json()
    except requests.exceptions.Timeout:
        latency_ms = (time.time() - t0) * 1000
        data = {"error": "timeout", "detail": "请求超过 30 秒"}
    except requests.exceptions.RequestException as e:
        latency_ms = (time.time() - t0) * 1000
        data = {"error": "network", "detail": str(e)}
    except json.JSONDecodeError:
        latency_ms = (time.time() - t0) * 1000
        data = {"error": "invalid_json", "detail": resp.text[:200]}

    trace = trace_call("chat", input_text, data, latency_ms, context_meta={
        "history_count": len(msgs),
        "context_summary_len": len(ctx),
    })
    data["__trace"] = trace
    return data


# ── 核心：调 Worker 的 quick 接口 ────────────────────
def quick(input_text):
    body = {
        "mode": "quick",
        "input": input_text,
        "currentDate": now_date(),
        "currentTime": now_time(),
    }
    t0 = time.time()
    try:
        resp = requests.post(WORKER_URL, headers=HEADERS, json=body, timeout=15)
        latency_ms = (time.time() - t0) * 1000
        if not resp.ok:
            try:
                err_body = resp.json()
            except Exception:
                err_body = {"raw": resp.text[:300]}
            data = {"error": f"http_{resp.status_code}", "detail": err_body}
        else:
            data = resp.json()
    except requests.exceptions.Timeout:
        latency_ms = (time.time() - t0) * 1000
        data = {"error": "timeout", "detail": "请求超过 15 秒"}
    except requests.exceptions.RequestException as e:
        latency_ms = (time.time() - t0) * 1000
        data = {"error": "network", "detail": str(e)}

    trace = trace_call("quick", input_text, data, latency_ms)
    data["__trace"] = trace
    return data


# ── 核心：调 Worker 的 utility 接口 ──────────────────
def suggest_topics(title, content):
    body = {
        "mode": "utility",
        "task": "suggest_topics",
        "title": title,
        "content": content,
    }
    resp = requests.post(WORKER_URL, headers=HEADERS, json=body, timeout=15)
    return resp.json()


def suggest_title(content):
    body = {
        "mode": "utility",
        "task": "suggest_title",
        "content": content,
    }
    resp = requests.post(WORKER_URL, headers=HEADERS, json=body, timeout=15)
    return resp.json()


# ── 格式化输出 ───────────────────────────────────────
def print_response(data):
    if "error" in data:
        print(f"\n  [ERROR] {data['error']}: {data.get('detail', '')}")
        return

    print(f"\n  reply: {data.get('reply', '(空)')}")

    fq = data.get("followUpQuestion")
    if fq:
        print(f"  followUp: {fq}")

    actions = data.get("actionSuggestions", [])
    if actions:
        print(f"  actions ({len(actions)}):")
        for i, a in enumerate(actions):
            print(f"    [{i}] {a.get('kind')} | {a.get('title')} | conf={a.get('confidence')}")
            if a.get("detail"):
                print(f"        detail: {a['detail']}")
            if a.get("date"):
                print(f"        date: {a['date']}", end="")
            if a.get("startTime"):
                print(f"  time: {a.get('startTime')}-{a.get('endTime', '?')}", end="")
            if a.get("inboxType"):
                print(f"  inboxType: {a['inboxType']}", end="")
            if a.get("mood"):
                print(f"  mood: {a['mood']}", end="")
            if a.get("feelings"):
                print(f"  feelings: {a['feelings']}", end="")
            if a.get("module"):
                print(f"  module: {a['module']}", end="")
            print()

    usage = data.get("usage")
    if usage:
        cached = usage.get("prompt_tokens_details", {}).get("cached_tokens", 0)
        print(f"  tokens: prompt={usage.get('prompt_tokens',0)}"
              f"  completion={usage.get('completion_tokens',0)}"
              f"  total={usage.get('total_tokens',0)}"
              f"  cached={cached}")

    debug = data.get("debug", {})
    if debug.get("suppressedActionsReason"):
        print(f"  [suppressed] {debug['suppressedActionsReason']}")


# ── 模式 1：交互式聊天 ───────────────────────────────
def interactive_chat():
    print("=" * 50)
    print("  LifeOS Agent 交互式聊天")
    print("  输入消息开始对话，输入 /quit 退出")
    print("  输入 /clear 清空历史")
    print("  输入 /raw 查看上一次完整 JSON")
    print("  输入 /context 修改上下文")
    print("=" * 50)

    messages = []
    last_raw = None

    while True:
        try:
            user_input = input("\n你: ").strip()
        except (EOFError, KeyboardInterrupt):
            print("\n再见!")
            break

        if not user_input:
            continue
        if user_input == "/quit":
            print("再见!")
            break
        if user_input == "/clear":
            messages = []
            print("  [历史已清空]")
            continue
        if user_input == "/raw":
            if last_raw:
                print(json.dumps(last_raw, ensure_ascii=False, indent=2))
            else:
                print("  [还没有响应数据]")
            continue
        if user_input == "/context":
            print("  当前上下文前 200 字:")
            print(f"  {SAMPLE_CONTEXT[:200]}...")
            print("  (修改请直接编辑 agent_lab.py 中的 SAMPLE_CONTEXT)")
            continue

        data = chat(user_input, messages=messages)
        last_raw = data
        print_response(data)

        messages.append({"role": "user", "content": user_input})
        reply = data.get("reply", "")
        fq = data.get("followUpQuestion", "")
        assistant_content = "\n\n".join(filter(None, [reply, fq]))
        if assistant_content:
            messages.append({"role": "assistant", "content": assistant_content})


# ── 模式 2：批量测试 ─────────────────────────────────
TEST_CASES = [
    {
        "name": "普通闲聊",
        "input": "今天天气不错",
        "expect": "reply 不为空，不应该有 actionSuggestions",
    },
    {
        "name": "表达感受",
        "input": "面试完感觉好累，有点失望",
        "expect": "reply 接住情绪，可能有 inbox action (感受)，带 mood 和 feelings",
    },
    {
        "name": "记录梦境",
        "input": "昨晚梦到了小狗，在一个很大的草坪上跑，帮我记一下",
        "expect": "inbox action，inboxType=做梦",
    },
    {
        "name": "创建待办",
        "input": "明天下午3点提醒我交材料",
        "expect": "task action，date=明天，startTime=15:00",
    },
    {
        "name": "时间记录",
        "input": "刚才 14:00-15:30 在看 agent 的论文",
        "expect": "time action，module=学习，startTime=14:00，endTime=15:30",
    },
    {
        "name": "信息不完整的待办",
        "input": "提醒我交材料",
        "expect": "应该追问日期，不生成 task card",
    },
    {
        "name": "空白/纯感叹",
        "input": "唉",
        "expect": "reply 温柔接住，不生成 action",
    },
    {
        "name": "多意图混合",
        "input": "今天10点到11点面试了pollo.ai，感觉不太行，提醒我明天整理一下面试复盘",
        "expect": "可能有 time action + inbox action 或 task action",
    },
]


def run_batch_tests():
    print("=" * 50)
    print(f"  批量测试：{len(TEST_CASES)} 个用例")
    print("=" * 50)

    for i, case in enumerate(TEST_CASES):
        print(f"\n{'─' * 40}")
        print(f"  [{i+1}/{len(TEST_CASES)}] {case['name']}")
        print(f"  输入: {case['input']}")
        print(f"  期望: {case['expect']}")

        data = chat(case["input"])
        print_response(data)

        # 把 trace 信息合并到结果行，一眼看全
        actions = data.get("actionSuggestions", [])
        fq = data.get("followUpQuestion")
        trace = data.get("__trace", {})
        tid = trace.get("trace_id", "?")
        tokens = trace.get("tokens", {})
        latency = trace.get("latency_ms", 0)

        print(f"  结果: [{tid}] reply={'有' if data.get('reply') else '无'}"
              f"  followUp={'有' if fq else '无'}"
              f"  actions={len(actions)}"
              f"  | prompt={tokens.get('prompt',0)}"
              f" comp={tokens.get('completion',0)}"
              f" cached={tokens.get('cached',0)}"
              f"  | {latency:.0f}ms")

    print(f"\n{'=' * 50}")
    print("  测试完成！检查上面的输出，看哪些不符合预期。")


# ── 模式 3：单次调用 ─────────────────────────────────
def single_shot(text):
    print(f"输入: {text}")
    data = chat(text)
    print_response(data)
    print("\n完整 JSON:")
    print(json.dumps(data, ensure_ascii=False, indent=2))


# ── 模式 4：utility 测试 ─────────────────────────────
def test_utility():
    print("=" * 50)
    print("  Utility 端点测试")
    print("=" * 50)

    print("\n--- suggest_topics ---")
    result = suggest_topics("面试复盘", "今天面了三家公司，感觉第一家最合适")
    print(json.dumps(result, ensure_ascii=False, indent=2))

    print("\n--- suggest_title ---")
    result = suggest_title("今天面了三家公司，感觉第一家最合适，他们做的是AI视频方向")
    print(json.dumps(result, ensure_ascii=False, indent=2))


# ── 模式 5：quick 对比测试 ────────────────────────────
def test_quick_vs_chat():
    import time
    cases = [
        "面试完感觉好累",
        "明天下午3点提醒我交材料",
        "刚才 14:00-15:30 在看论文",
    ]
    print("=" * 50)
    print("  Quick vs Chat 对比测试")
    print("=" * 50)
    for text in cases:
        print(f"\n  输入: {text}")

        t0 = time.time()
        q = quick(text)
        qt = time.time() - t0

        t0 = time.time()
        c = chat(text)
        ct = time.time() - t0

        qa = len(q.get("actionSuggestions", []))
        ca = len(c.get("actionSuggestions", []))
        print(f"  quick: {qt:.1f}s | reply={q.get('reply','')[:30]} | actions={qa}")
        print(f"  chat:  {ct:.1f}s | reply={c.get('reply','')[:30]} | actions={ca}")


# ── 模式 6：Trace Review ─────────────────────────────
def review_traces(date_str=None, rating_filter=None):
    """查看 trace 记录摘要"""
    date_str = date_str or datetime.now().strftime("%Y-%m-%d")
    traces = load_traces(date_str, rating_filter)

    if not traces:
        print(f"  {date_str} 没有{'符合条件的' if rating_filter else ''} trace 记录")
        if not rating_filter:
            # 列出有哪些日期的文件
            _ensure_trace_dir()
            files = sorted(f for f in os.listdir(TRACE_DIR) if f.endswith(".jsonl"))
            if files:
                print(f"  可用日期: {', '.join(f.replace('.jsonl','') for f in files[-5:])}")
        return

    print(f"{'=' * 70}")
    print(f"  Trace Review: {date_str}  ({len(traces)} 条{'，filter=' + rating_filter if rating_filter else ''})")
    print(f"{'=' * 70}")

    total_prompt = 0
    total_completion = 0
    total_latency = 0

    for t in traces:
        tid = t.get("trace_id", "?")
        mode = t.get("mode", "?")
        inp = t.get("input", "")[:30]
        tokens = t.get("tokens", {})
        prompt_t = tokens.get("prompt", 0)
        comp_t = tokens.get("completion", 0)
        cached_t = tokens.get("cached", 0)
        latency = t.get("latency_ms", 0)
        resp = t.get("response", {})
        actions_n = resp.get("actions_count", 0)
        kinds = resp.get("action_kinds", [])
        rating = t.get("rating") or "—"
        ts_raw = t.get("timestamp", "")
        ts = ts_raw[11:19] if len(ts_raw) >= 19 else ts_raw[-8:]  # HH:MM:SS

        total_prompt += prompt_t
        total_completion += comp_t
        total_latency += latency

        rating_icon = {"good": "✅", "bad": "❌", "—": "  "}.get(rating, "⚪")

        print(f"\n  {rating_icon} [{tid}] {ts} {mode:5s} | \"{inp}\"")
        print(f"     tokens: prompt={prompt_t} comp={comp_t} cached={cached_t}"
              f"  | {latency:.0f}ms | actions={actions_n} {kinds}")
        if t.get("rating_note"):
            print(f"     note: {t['rating_note']}")

    print(f"\n{'─' * 70}")
    print(f"  汇总: {len(traces)} 次调用"
          f"  | prompt 总计={total_prompt} completion 总计={total_completion}"
          f"  | 平均延迟={total_latency/len(traces):.0f}ms")


def rate_trace(trace_id_prefix, rating, note=""):
    """给 trace 打分"""
    if rating not in ("good", "bad", "neutral"):
        print(f"  rating 必须是 good / bad / neutral，你给的是: {rating}")
        return
    if update_trace_rating(trace_id_prefix, rating, note):
        print(f"  ✅ trace {trace_id_prefix}* 已标记为 {rating}" + (f" ({note})" if note else ""))


# ── 入口 ─────────────────────────────────────────────
def main():
    if len(sys.argv) > 1:
        cmd = sys.argv[1]
        if cmd == "test":
            run_batch_tests()
        elif cmd == "quick":
            if len(sys.argv) > 2:
                text = " ".join(sys.argv[2:])
                print(f"[quick] 输入: {text}")
                data = quick(text)
                print_response(data)
                print("\n完整 JSON:")
                print(json.dumps(data, ensure_ascii=False, indent=2))
            else:
                test_quick_vs_chat()
        elif cmd == "utility":
            test_utility()
        elif cmd == "chat":
            interactive_chat()
        elif cmd == "review":
            # review [日期] [--bad|--good|--neutral]
            date_arg = None
            rating_f = None
            for arg in sys.argv[2:]:
                if arg.startswith("--"):
                    rating_f = arg[2:]
                else:
                    date_arg = arg
            review_traces(date_arg, rating_f)
        elif cmd == "rate":
            # rate <trace_id_prefix> <good|bad|neutral> [note]
            if len(sys.argv) < 4:
                print("用法: python3 agent_lab.py rate <trace_id> <good|bad|neutral> [备注]")
            else:
                tid = sys.argv[2]
                r = sys.argv[3]
                note = " ".join(sys.argv[4:]) if len(sys.argv) > 4 else ""
                rate_trace(tid, r, note)
        else:
            single_shot(" ".join(sys.argv[1:]))
    else:
        print("LifeOS Agent 实验脚本")
        print()
        print("用法:")
        print("  python3 scripts/agent_lab.py chat        # 交互式聊天（对话模式）")
        print("  python3 scripts/agent_lab.py quick       # quick vs chat 对比测试")
        print('  python3 scripts/agent_lab.py quick "文本" # 单次 quick 调用')
        print("  python3 scripts/agent_lab.py test        # 批量测试 8 个用例")
        print("  python3 scripts/agent_lab.py utility     # 测试 utility 端点")
        print('  python3 scripts/agent_lab.py "你好"       # 单次 chat 调用')
        print()
        print("追踪 & 评估:")
        print("  python3 scripts/agent_lab.py review            # 查看今天的 trace")
        print("  python3 scripts/agent_lab.py review 2026-05-18 # 查看指定日期")
        print("  python3 scripts/agent_lab.py review --bad      # 只看标记为 bad 的")
        print("  python3 scripts/agent_lab.py rate <id> bad \"回复空洞\" # 给 trace 打标")
        print()
        print("快速开始：")
        print("  python3 scripts/agent_lab.py chat")


if __name__ == "__main__":
    main()
