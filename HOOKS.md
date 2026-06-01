# Claude Code / Codex Hook 接线

把桌宠接到你的 Claude Code 或 Codex 工作流。前提:`swift run` 已经跑着,桌宠在桌面上。

## 接口规格

桌宠会在 `http://127.0.0.1:7777` 监听以下接口:

| 接口 | 方法 | body | 行为 |
|---|---|---|---|
| `/state` | POST | `{"state": "thinking"}` | 桌宠切到积蓄火焰状态 |
| `/state` | POST | `{"state": "done"}` | 桌宠大拇指庆祝(4 秒后自动回 idle) |
| `/state` | POST | `{"state": "idle"}` | 立即回 idle |
| `/task` | POST | `{"task": "任务描述"}` | 头顶气泡显示文字 6 秒 |
| `/prompt` | POST | `{"prompt":"用户输入","session_id":"...","source":"Codex"}` | 记录一个可 hover 切换的 agent 任务 |
| `/session_done` | POST | `{"session_id":"...","source":"Codex"}` | 把对应 agent 任务标记为完成 |
| `/health` | GET | — | 返回 ok,用来探活 |

## 手工测一下(确认服务在跑)

```bash
# 探活
curl http://localhost:7777/health
# → ok

# 让桌宠开始积蓄火焰
curl -X POST http://localhost:7777/state \
  -H "Content-Type: application/json" \
  -d '{"state":"thinking"}'

# 让桌宠庆祝
curl -X POST http://localhost:7777/state \
  -H "Content-Type: application/json" \
  -d '{"state":"done"}'

# 头顶显示任务气泡
curl -X POST http://localhost:7777/task \
  -H "Content-Type: application/json" \
  -d '{"task":"修复登录页面 bug"}'
```

## Codex 接线

这台机器已经装了全局 Codex hooks:

```text
~/.codex/hooks.json
.codex/hooks/deskpet.py
```

Codex 会自动发现 `~/.codex/hooks.json`。重启/重新打开 Codex 会话后,运行 `/hooks` 审核并信任这组 hook。

这些 hook 会把 Codex 生命周期转成桌宠事件:

| Hook | 触发时机 | 桌宠反应 |
|---|---|---|
| `UserPromptSubmit` | 你发消息给 Codex 那一刻 | 切到 thinking,并把 prompt 记进 hover 任务列表 |
| `Stop` | Codex 一轮回应结束 | 庆祝 4 秒后回 idle,任务列表里该 session 变绿 |
| `SubagentStart` | Codex 启动子 agent | 头顶气泡显示子 agent 开始 |
| `SubagentStop` | Codex 子 agent 结束 | 头顶气泡显示子 agent 完成 |

全局配置内容如下:

```json
{
  "hooks": {
    "UserPromptSubmit": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "/usr/bin/python3 ~/Desktop/deskpet/.codex/hooks/deskpet.py",
            "timeout": 5
          }
        ]
      }
    ],
    "Stop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "/usr/bin/python3 ~/Desktop/deskpet/.codex/hooks/deskpet.py",
            "timeout": 5
          }
        ]
      }
    ],
    "SubagentStart": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "/usr/bin/python3 ~/Desktop/deskpet/.codex/hooks/deskpet.py",
            "timeout": 5
          }
        ]
      }
    ],
    "SubagentStop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "/usr/bin/python3 ~/Desktop/deskpet/.codex/hooks/deskpet.py",
            "timeout": 5
          }
        ]
      }
    ]
  }
}
```

Codex hooks 当前会被要求 review/trust;如果改了 `hooks.json` 或脚本,需要再跑一次 `/hooks` 信任新版本。

## Claude Code settings.json 接线

打开 `~/.claude/settings.json`(全局)或项目里的 `.claude/settings.json`(项目级),把下面 hooks 块合进 `"hooks"` 字段:

```json
{
  "hooks": {
    "UserPromptSubmit": [
      {
        "matcher": "*",
        "hooks": [
          {
            "type": "command",
            "command": "curl -s -X POST http://127.0.0.1:7777/state -H 'Content-Type: application/json' -d '{\"state\":\"thinking\"}' > /dev/null 2>&1 &"
          }
        ]
      }
    ],
    "Stop": [
      {
        "matcher": "*",
        "hooks": [
          {
            "type": "command",
            "command": "curl -s -X POST http://127.0.0.1:7777/state -H 'Content-Type: application/json' -d '{\"state\":\"done\"}' > /dev/null 2>&1 &"
          }
        ]
      }
    ],
    "PreToolUse": [
      {
        "matcher": "TaskCreate",
        "hooks": [
          {
            "type": "command",
            "command": "cat | jq -r '.tool_input.subject // .tool_input.description // \"新任务\"' | xargs -I{} curl -s -X POST http://127.0.0.1:7777/task -H 'Content-Type: application/json' -d '{\"task\":\"{}\"}' > /dev/null 2>&1 &"
          }
        ]
      }
    ]
  }
}
```

### 这些 hook 做了什么

| Hook | 触发时机 | 桌宠反应 |
|---|---|---|
| `UserPromptSubmit` | 你发消息给 Claude 那一刻 | 切到 thinking(火焰起伏) |
| `Stop` | Claude 一轮回应结束 | 庆祝 4 秒后回 idle |
| `PreToolUse: TaskCreate` | Claude 创建新任务 | 头顶气泡显示任务标题 |

所有 curl 都加了 `> /dev/null 2>&1 &` —— 不阻塞 Claude Code 主流程,失败也无所谓。

### 如果桌宠没开,Claude Code / Codex 会怎样?

Claude 的 curl 会后台失败;Codex 的 Python hook 会吞掉连接错误。你随时关桌宠,agent 照常工作。

## 验证流程

1. `swift run` 启动桌宠
2. `curl http://localhost:7777/health` 应该返回 `ok`
3. 把上面的 hooks 块加到 `~/.claude/settings.json`
4. 重启 Claude Code(如果在运行)
5. 让 Claude 做任何事——比如说"列一下当前目录的文件"
6. **应该看到**:你回车那一刻桌宠进入 thinking(火焰起伏),Claude 回答完成那一刻桌宠大拇指庆祝
7. 如果 Claude 用了 TaskCreate,头顶会冒出任务气泡

Codex 验证:

1. `swift run` 启动桌宠
2. 重启/打开 Codex
3. 运行 `/hooks`,信任 `~/.codex/hooks.json`
4. 让 Codex 做任何事
5. **应该看到**:你发消息时桌宠 thinking,完成时庆祝;hover 桌宠会看到 `Codex` 任务

## 进阶:自定义任务气泡来源

如果你想气泡显示其他东西(比如当前在改哪个文件),自己写 hook 调用 `/task` 接口就行。比如 PostToolUse 监听文件写入:

```json
"PostToolUse": [{
  "matcher": "Write|Edit",
  "hooks": [{
    "type": "command",
    "command": "cat | jq -r '.tool_input.file_path' | xargs -I{} basename {} | xargs -I{} curl -s -X POST http://127.0.0.1:7777/task -H 'Content-Type: application/json' -d '{\"task\":\"刚改了 {}\"}' > /dev/null 2>&1 &"
  }]
}]
```
