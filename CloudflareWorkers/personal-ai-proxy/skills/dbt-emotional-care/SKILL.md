# 情绪梳理技能（DBT Emotional Care）

## 概述
基于 DBT（辩证行为疗法）框架的自我关怀练习技能。不是治疗，是帮用户理清情绪的工具。

## 触发条件（必须同时满足）
1. 用户表达了明确的**负面**情绪困扰（痛苦/焦虑/愤怒/悲伤/挫败/纠结）
2. 情绪不是一句话带过，而是用户想聊这个话题

## 绝不触发的场景
开心、满足、兴奋、平静、分享好事、闲聊、记录日常

## 提议方式
「要不要做个小练习，帮你理一理？」— 用户明确同意后才开始

## 可用技能（8 个）
| 技能 | ID | 适用场景 | 时长 |
|---|---|---|---|
| TIPP 紧急降温 | tipp | 情绪激烈/失控 | ~2min |
| STOP 冲动暂停 | stop | 冲动行为前 | ~1min |
| 检查事实 | check_the_facts | 解读偏差 | ~3min |
| 反向行动 | opposite_action | 回避/攻击冲动 | ~3min |
| 智慧心 | wise_mind | 理性与情感冲突 | ~2min |
| DEAR MAN | dear_man | 人际表达 | ~5min |
| 行为链分析 | behavior_chain_analysis | 反复问题行为 | ~5min |
| 情绪验证 | validation | 通用情绪确认 | ~2min |

## 路由逻辑
- 高痛苦（失控感）→ 痛苦耐受（tipp / stop）
- 中痛苦（能表达）→ 情绪调节（check_the_facts / opposite_action）
- 人际相关 → 人际效能（dear_man）
- 反复行为 → 行为链分析
- 通用 → 智慧心 / 情绪验证

## 引导原则
- 猫猫人格不变，不说"切换到 Coach"
- 每轮只推进一个小步骤
- 每步标注编号 如"【第1步】"
- 先验证感受，再拆解
- 不评判、不催促、不说"想开点"
- 用户中途想停就尊重

## 完成后
- 生成 brain actionSuggestion 保存到第二大脑
- kind: "brain", inboxType: "DBT练习"
- title 包含技能名，detail 记录真实练习过程

## 文件结构
```
skills/dbt-emotional-care/
├── SKILL.md              ← 你在这里
├── index.js              ← buildDBTSkillBlock() 入口
├── references/
│   ├── skills-guide.js   ← 8 个技能的完整步骤指南
│   └── step-registry.js  ← 每个技能的步骤数组
└── scripts/
    └── session.js        ← session 状态管理（normalize/reconcile/clamp）
```
