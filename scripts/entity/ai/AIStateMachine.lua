-- ====================================================================
-- entity/ai/AIStateMachine.lua
-- 通用 AI 状态机（Design.md「AI机制」：IDLE / WANDERING / CHASING / ATTACKING）
--
-- 职责只做「状态的登记、切换、逐帧分发」，不掺任何生物逻辑：
--   - addState(name, { enter, exit, update })
--   - setState(name) 会自动调用旧状态的 exit、新状态的 enter
--   - update(dt, ...) 分发到当前状态的 update
-- 生物具体行为由 AIController 提供，并通过构造时传入的 context 回调。
--
-- 关键点：状态切换时借 enter/exit 清理旧状态的路径/计时器/移动目标，
-- 避免多个行为同时控制生物（Design.md §七）。
-- ====================================================================

---@class AIStateMachine
---@field states table<string, table>
---@field current string|nil
---@field context any
local AIStateMachine = {}
AIStateMachine.__index = AIStateMachine

---创建状态机
---@param context any 传给各状态 handler 的上下文（通常是 AIController）
---@return AIStateMachine
function AIStateMachine.new(context)
    return setmetatable({
        states = {},
        current = nil,
        context = context,
    }, AIStateMachine)
end

---登记一个状态
---@param name string
---@param handlers { enter: fun(context: any)|nil, exit: fun(context: any)|nil, update: fun(context: any, dt: number, ...: any): ... }
function AIStateMachine:addState(name, handlers)
    self.states[name] = handlers or {}
end

---切换状态（同名不重复触发；自动调用 exit / enter）
---@param name string
function AIStateMachine:setState(name)
    if name == self.current then
        return
    end
    local old = self.states[self.current]
    if old and old.exit then
        old.exit(self.context)
    end
    self.current = name
    local new = self.states[name]
    if new and new.enter then
        new.enter(self.context)
    end
end

---当前状态名
---@return string|nil
function AIStateMachine:getState()
    return self.current
end

---逐帧更新：分发到当前状态的 update
---@param dt number
---@vararg any 透传给状态 update 的参数
function AIStateMachine:update(dt, ...)
    local h = self.states[self.current]
    if h and h.update then
        return h.update(self.context, dt, ...)
    end
end

return AIStateMachine
