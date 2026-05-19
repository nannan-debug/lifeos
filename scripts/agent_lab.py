#!/usr/bin/env python3
"""
LifeOS Agent 本地实验脚本
用法：python3 scripts/agent_lab.py

功能：
1. 交互式聊天 —— 像 App 一样和 Agent 对话，实时看返回的 JSON
2. 批量测试 —— 跑一组预设用例，检查回复质量和 actionSuggestions
3. 单次调用 —— 快速测试一句话

不依赖 iOS 模拟器，秒级反馈，适合调 prompt 和调试 Worker。
"""

import requests
import json
import sys
from datetime import datetime

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
    body = {
        "mode": "chat",
        "input": input_text,
        "messages": messages or [],
        "contextSummary": context_summary or SAMPLE_CONTEXT,
        "currentDate": now_date(),
        "currentTime": now_time(),
    }
    try:
        resp = requests.post(WORKER_URL, headers=HEADERS, json=body, timeout=30)
        if not resp.ok:
            try:
                err_body = resp.json()
            except Exception:
                err_body = {"raw": resp.text[:300]}
            return {"error": f"http_{resp.status_code}", "detail": err_body}
        return resp.json()
    except requests.exceptions.Timeout:
        return {"error": "timeout", "detail": "请求超过 30 秒"}
    except requests.exceptions.RequestException as e:
        return {"error": "network", "detail": str(e)}
    except json.JSONDecodeError:
        return {"error": "invalid_json", "detail": resp.text[:200]}


# ── 核心：调 Worker 的 quick 接口 ────────────────────
def quick(input_text):
    body = {
        "mode": "quick",
        "input": input_text,
        "currentDate": now_date(),
        "currentTime": now_time(),
    }
    try:
        resp = requests.post(WORKER_URL, headers=HEADERS, json=body, timeout=15)
        if not resp.ok:
            try:
                err_body = resp.json()
            except Exception:
                err_body = {"raw": resp.text[:300]}
            return {"error": f"http_{resp.status_code}", "detail": err_body}
        return resp.json()
    except requests.exceptions.Timeout:
        return {"error": "timeout", "detail": "请求超过 15 秒"}
    except requests.exceptions.RequestException as e:
        return {"error": "network", "detail": str(e)}


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

        actions = data.get("actionSuggestions", [])
        fq = data.get("followUpQuestion")
        print(f"  结果: reply={'有' if data.get('reply') else '无'}"
              f"  followUp={'有' if fq else '无'}"
              f"  actions={len(actions)}")

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
        else:
            single_shot(" ".join(sys.argv[1:]))
    else:
        print("LifeOS Agent 实验脚本")
        print()
        print("用法:")
        print("  python3 scripts/agent_lab.py chat      # 交互式聊天（对话模式）")
        print("  python3 scripts/agent_lab.py quick      # quick vs chat 对比测试")
        print('  python3 scripts/agent_lab.py quick "文本" # 单次 quick 调用')
        print("  python3 scripts/agent_lab.py test      # 批量测试 8 个用例")
        print("  python3 scripts/agent_lab.py utility   # 测试 utility 端点")
        print('  python3 scripts/agent_lab.py "你好"     # 单次 chat 调用')
        print()
        print("快速开始：")
        print("  python3 scripts/agent_lab.py chat")


if __name__ == "__main__":
    main()
