--[[
    UE Anti-Cheat Bypass Module v4 — Universal Executor Compatible
    Rivals 안티치트 완전 우회

    호환 실행자: Synapse X, Script-Ware, KRNL, Fluxus, Solara, Delta,
                 Arceus X, Volcano, Hydrogen, Electron, Wave, JJSploit,
                 Codex, Evon, 기타 Luau 지원 실행자

    이전 v3 대비 변경:
    - 모든 실행자 함수에 다단계 폴백 추가
    - task 라이브러리 폴리필
    - getnamecallmethod 폴리필
    - 모든 후킹을 pcall로 안전하게 래핑
    - Volcano 실행자 호환 레이어 추가
    - 후킹 실패 시 graceful degradation
]]

--------------------------------------------------------------------------------
-- 0. Universal Executor Compatibility Layer
--------------------------------------------------------------------------------

-- task 라이브러리 폴리필 (일부 실행자에서 누락)
if not task then
    local RunSvc = game:GetService("RunService")
    task = {}
    task.wait = wait or function(t)
        t = t or 0
        local start = tick()
        if t <= 0 then
            RunSvc.Heartbeat:Wait()
        else
            repeat RunSvc.Heartbeat:Wait() until tick() - start >= t
        end
        return tick() - start
    end
    task.spawn = spawn or function(f, ...)
        local args = {n = select("#", ...), ...}
        local co = coroutine.create(function()
            f(unpack(args, 1, args.n))
        end)
        coroutine.resume(co)
        return co
    end
    task.delay = delay or function(t, f, ...)
        local args = {n = select("#", ...), ...}
        task.spawn(function()
            task.wait(t)
            f(unpack(args, 1, args.n))
        end)
    end
    task.defer = task.spawn
end

-- getnamecallmethod 폴리필
if not getnamecallmethod then
    getnamecallmethod = function() return "" end
end

-- typeof 폴리필
if not typeof then
    typeof = function(v)
        local t = type(v)
        if t == "userdata" then
            local ok, cls = pcall(function() return v.ClassName end)
            if ok and cls then return "Instance" end
            local ok2, _ = pcall(function() return v.X end)
            if ok2 then return "Vector3" end
        end
        return t
    end
end

--------------------------------------------------------------------------------
-- Services
--------------------------------------------------------------------------------
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local CoreGui

pcall(function()
    CoreGui = game:GetService("CoreGui")
end)
if not CoreGui then
    pcall(function()
        CoreGui = (gethui and gethui()) or game:FindFirstChild("CoreGui")
    end)
end

local LocalPlayer = Players.LocalPlayer

--------------------------------------------------------------------------------
-- 1. 실행자 함수 캐싱 (최대 호환 폴백 체인)
--------------------------------------------------------------------------------
local ENV = (getgenv and getgenv()) or _G

-- hookfunction: 함수 후킹
local hookfn = hookfunction or replaceclosure or detour_function or (Volcano and Volcano.hookfunction)
-- hookmetamethod: 메타테이블 후킹
local hookmm = hookmetamethod or (Volcano and Volcano.hookmetamethod)
-- newcclosure: C 클로저 래핑
local newc = newcclosure or CClosure or (Volcano and Volcano.newcclosure) or function(f) return f end
-- clonefunction: 함수 복제
local clonefn = clonefunction or (Volcano and Volcano.clonefunction) or function(f) return f end
-- getrawmetatable: 원시 메타테이블
local getrawmt = getrawmetatable or debug.getmetatable or (Volcano and Volcano.getrawmetatable)
-- setreadonly: 읽기 전용 토글
local setro = setreadonly or (make_writeable and function(t, r)
    if r then make_readonly(t) else make_writeable(t) end
end) or (Volcano and Volcano.setreadonly)
-- checkcaller: 호출자 확인
local checkc = checkcaller or is_executor_caller or (Volcano and Volcano.checkcaller) or function() return false end
-- getcallingscript: 호출 스크립트 확인
local getcscript = getcallingscript or GETCALLINGSCRIPT or (Volcano and Volcano.getcallingscript)
-- getconnections: 시그널 커넥션
local getcons = getconnections or (Volcano and Volcano.getconnections)
-- isexecutorclosure: 실행자 클로저 판별
local isexec = isexecutorclosure or is_synapse_function or isourclosure or is_protosmasher_closure
    or (Volcano and Volcano.isexecutorclosure) or function() return false end
-- getnamecallmethod (already polyfilled above)
local getnm = getnamecallmethod

-- 원본 함수 백업
local orig_rawget = rawget
local orig_rawset = rawset
local orig_getfenv = getfenv
local orig_type = type
local orig_typeof = typeof
local orig_pcall = pcall
local orig_select = select
local orig_unpack = unpack
local orig_next = next
local orig_pairs = pairs
local orig_ipairs = ipairs
local orig_tostring = tostring
local orig_setmetatable = setmetatable

-- 안전한 더미 함수
local DUMMY = newc(function() end)
local DUMMY_RET_NIL = newc(function() return nil end)
local DUMMY_RET_FALSE = newc(function() return false end)
local DUMMY_RET_TABLE = newc(function() return {} end)

-- 상태 추적
local installStatus = {}

--------------------------------------------------------------------------------
-- 2. 호출자 판별 시스템 (다층 검증)
--------------------------------------------------------------------------------
local function isGameCaller()
    -- 레벨 1: checkcaller
    if orig_type(checkc) == "function" then
        local ok, result = orig_pcall(checkc)
        if ok and result == true then
            return false -- 실행자가 호출
        end
    end

    -- 레벨 2: getcallingscript
    if orig_type(getcscript) == "function" then
        local ok, scr = orig_pcall(getcscript)
        if ok and orig_typeof(scr) == "Instance" then
            return true -- 게임 스크립트가 호출
        end
        if ok and scr == nil then
            return false -- 실행자가 호출 (스크립트 없음)
        end
    end

    -- 기본: 게임으로 가정 (안전 방향)
    return true
end

--------------------------------------------------------------------------------
-- 3. 실행자 함수 마커 (은폐 대상)
--------------------------------------------------------------------------------
local EXECUTOR_MARKERS = {}
do
    local names = {
        -- 핵심 후킹/메타테이블
        "hookfunction", "hookmetamethod", "newcclosure", "clonefunction",
        "replaceclosure", "restorefunction", "detour_function",
        "checkcaller", "getnamecallmethod", "setnamecallmethod",
        "getcallingscript", "isexecutorclosure", "isourclosure",
        "iscclosure", "islclosure", "is_synapse_function",
        "is_protosmasher_closure", "is_executor_caller",
        -- GC/레지스트리
        "getgc", "getreg", "getrawmetatable", "setrawmetatable",
        "setreadonly", "isreadonly", "make_writeable", "make_readonly",
        -- 커넥션/시그널
        "getconnections", "getcallbackvalue", "setcallbackvalue",
        "getscriptclosure", "getscriptbytecode", "getscripthash",
        "getsenv", "getmenv", "getloadedmodules",
        "getscripts", "getrunningscripts",
        -- 디버그/업밸류
        "getconstants", "getconstant", "setconstant",
        "getupvalues", "getupvalue", "setupvalue",
        "getprotos", "getproto", "setproto",
        "getstack", "setstack", "getthread",
        -- 환경/식별
        "getgenv", "getrenv", "gettenv",
        "identifyexecutor", "getexecutorname",
        -- 실행자 식별 플래그
        "syn", "KRNL_LOADED", "fluxus", "SENTINEL_LOADED",
        "Solara", "Delta", "Arceus", "Volcano", "VOLCANO_LOADED",
        "Hydrogen", "Electron", "Wave", "Codex", "Evon",
        -- 파일시스템
        "readfile", "writefile", "appendfile", "loadfile",
        "listfiles", "makefolder", "delfile", "delfolder",
        "isfile", "isfolder",
        -- 네트워크/클립보드
        "setclipboard", "toclipboard",
        "request", "http_request", "httprequest", "syn_request",
        "WebSocket", "WebSocket_connect",
        -- 인스턴스/시그널 헬퍼
        "gethui", "protect_gui", "unprotect_gui",
        "cloneref", "compareinstances",
        "fireclickdetector", "fireproximityprompt",
        "firetouchinterest", "firesignal",
        "gethiddenproperty", "sethiddenproperty",
        "setscriptable",
        -- 렌더링/텔레포트
        "Drawing", "cleardrawcache",
        "queue_on_teleport", "queueonteleport",
        -- UE 전용 플래그
        "UE_LOADED",
        -- CClosure (일부 실행자)
        "CClosure",
    }
    for i = 1, #names do
        EXECUTOR_MARKERS[names[i]] = true
    end
end

--------------------------------------------------------------------------------
-- 4. 환경 복제 (실행자 함수 제거)
--------------------------------------------------------------------------------
local function sanitizeEnv(src)
    if orig_type(src) ~= "table" then return src end

    local clean = {}
    for k, v in orig_next, src do
        if not (orig_type(k) == "string" and EXECUTOR_MARKERS[k]) then
            clean[k] = v
        end
    end

    -- _G 자기참조 유지
    if orig_rawget(clean, "_G") == nil and orig_rawget(src, "_G") == src then
        clean._G = clean
    end

    return clean
end

--------------------------------------------------------------------------------
-- 5. shared.r 무력화 (Rivals AC의 핵심 탐지 벡터)
--------------------------------------------------------------------------------
do
    local function secureDummy()
        return newc(function() end)
    end

    local r_meta = {
        __index = function(_, k)
            return secureDummy()
        end,
        __newindex = function(t, k, v)
            orig_rawset(t, k, secureDummy())
        end,
        __len = function() return 0 end,
        __pairs = function(t) return function() return nil end, t, nil end,
        __metatable = "locked",
    }

    local function secureTable(tbl)
        if orig_type(tbl) ~= "table" then return end
        for k in orig_next, tbl do
            orig_rawset(tbl, k, secureDummy())
        end
        for i = 1, 128 do
            orig_rawset(tbl, i, secureDummy())
        end
        orig_pcall(orig_setmetatable, tbl, r_meta)
    end

    -- shared.r 초기화
    orig_pcall(function()
        if orig_type(shared) == "table" then
            if orig_type(orig_rawget(shared, "r")) == "table" then
                secureTable(shared.r)
            else
                local r = orig_setmetatable({}, r_meta)
                for i = 1, 128 do orig_rawset(r, i, secureDummy()) end
                orig_rawset(shared, "r", r)
            end

            -- shared 메타테이블 보호
            local smt = (getrawmt and getrawmt(shared)) or {}
            local old_ni = smt.__newindex
            if setro then orig_pcall(setro, smt, false) end
            smt.__newindex = newc(function(t, k, v)
                if k == "r" and orig_type(v) == "table" then
                    secureTable(v)
                    return orig_rawset(t, k, v)
                end
                if old_ni then return old_ni(t, k, v) end
                return orig_rawset(t, k, v)
            end)
            if setro then orig_pcall(setro, smt, true) end
        end
    end)

    installStatus.shared_r = orig_type(shared) == "table"

    -- 폴링 방어 (0.1초마다 검증)
    task.spawn(function()
        while true do
            orig_pcall(function()
                if orig_type(shared) == "table" then
                    local r = orig_rawget(shared, "r")
                    if orig_type(r) == "table" then
                        for i = 1, 64 do
                            local v = orig_rawget(r, i)
                            if v ~= nil and not (orig_type(v) == "function") then
                                orig_rawset(r, i, secureDummy())
                            end
                        end
                    else
                        local newR = orig_setmetatable({}, r_meta)
                        for i = 1, 128 do orig_rawset(newR, i, secureDummy()) end
                        orig_rawset(shared, "r", newR)
                    end
                end
            end)
            task.wait(0.1)
        end
    end)
end

--------------------------------------------------------------------------------
-- 6. rawget 후킹 (환경 스캔 차단)
--------------------------------------------------------------------------------
if hookfn then
    local ok, err = orig_pcall(function()
        local old_rawget
        old_rawget = hookfn(rawget, newc(function(t, k)
            if isGameCaller() and orig_type(k) == "string" and EXECUTOR_MARKERS[k] then
                return nil
            end
            return old_rawget(t, k)
        end))
    end)
    installStatus.rawget_hook = ok
    if not ok then
        warn("[UE Bypass] rawget 후킹 스킵: " .. tostring(err))
    end
end

--------------------------------------------------------------------------------
-- 7. getfenv 후킹 (환경 은폐)
--------------------------------------------------------------------------------
if hookfn then
    local ok, err = orig_pcall(function()
        local old_getfenv
        old_getfenv = hookfn(getfenv, newc(function(target)
            local query = target
            if orig_type(target) == "number" then
                query = target + 1
            elseif target == nil then
                query = 2
            end

            local env = old_getfenv(query)

            if isGameCaller() and orig_type(env) == "table" then
                return sanitizeEnv(env)
            end

            return env
        end))
    end)
    installStatus.getfenv_hook = ok
end

--------------------------------------------------------------------------------
-- 8. getgenv / getrenv 후킹
--------------------------------------------------------------------------------
if hookfn then
    orig_pcall(function()
        local origGetgenv = orig_rawget(ENV, "getgenv")
        if orig_type(origGetgenv) == "function" then
            local old_getgenv
            old_getgenv = hookfn(origGetgenv, newc(function(...)
                local env = old_getgenv(...)
                if isGameCaller() and orig_type(env) == "table" then
                    return sanitizeEnv(env)
                end
                return env
            end))
        end
    end)

    orig_pcall(function()
        local origGetrenv = orig_rawget(ENV, "getrenv")
        if orig_type(origGetrenv) == "function" then
            local old_getrenv
            old_getrenv = hookfn(origGetrenv, newc(function(...)
                local env = old_getrenv(...)
                if isGameCaller() and orig_type(env) == "table" then
                    return sanitizeEnv(env)
                end
                return env
            end))
        end
    end)
    installStatus.env_hooks = true
end

--------------------------------------------------------------------------------
-- 9. debug.info 후킹 (스택 트레이스 은폐)
--------------------------------------------------------------------------------
local hookedFunctions = setmetatable({}, { __mode = "k" })

if hookfn and debug and debug.info then
    local ok, err = orig_pcall(function()
        local old_debug_info
        old_debug_info = hookfn(debug.info, newc(function(...)
            local args = { ... }
            local target = args[1]
            local specs = args[2]

            -- 함수 대상 + "f" 스펙 포함 시 → 후킹 여부 체크
            if orig_type(target) == "function" and orig_type(specs) == "string" then
                if string.find(specs, "f") then
                    if isGameCaller() then
                        local isHooked = hookedFunctions[target]
                        local isExec = false
                        orig_pcall(function()
                            if isexec and isexec(target) then
                                isExec = true
                            end
                        end)

                        if isHooked or isExec then
                            local results = { old_debug_info(target, specs) }
                            local idx = 0
                            for i = 1, #specs do
                                local c = string.sub(specs, i, i)
                                if c == "s" or c == "l" or c == "f" or c == "n" or c == "a" then
                                    idx = idx + 1
                                    if c == "f" then
                                        results[idx] = DUMMY
                                        break
                                    end
                                end
                            end
                            return orig_unpack(results)
                        end
                    end
                end

                -- 이름 기반 방어
                if isGameCaller() and string.find(specs, "n") then
                    local name = old_debug_info(target, "n")
                    if name and EXECUTOR_MARKERS[name] then
                        local results = { old_debug_info(target, specs) }
                        for i = 1, #specs do
                            local c = string.sub(specs, i, i)
                            if c == "n" then
                                results[i] = ""
                            elseif c == "f" then
                                results[i] = DUMMY
                            end
                        end
                        return orig_unpack(results)
                    end
                end
            end

            -- 숫자 스택 레벨 방어
            if orig_type(target) == "number" and isGameCaller() then
                if target <= 5 and specs == "f" then
                    local caller = getcscript and getcscript()
                    if caller and orig_typeof(caller) == "Instance" then
                        local n = caller.Name
                        if n == "ClientFighter" or n == "EmoteSoundLogic" or n == "AntiCheat" then
                            return DUMMY
                        end
                    end
                end
            end

            return old_debug_info(...)
        end))
    end)
    installStatus.debug_info_hook = ok
end

--------------------------------------------------------------------------------
-- 10. getgc 후킹 (GC 스캔 방어)
--------------------------------------------------------------------------------
if hookfn and orig_type(orig_rawget(ENV, "getgc")) == "function" then
    local ok, err = orig_pcall(function()
        local old_getgc
        old_getgc = hookfn(getgc, newc(function(includeTable)
            local result = old_getgc(includeTable)
            if not isGameCaller() then return result end

            local filtered = {}
            for i = 1, #result do
                local v = result[i]
                local shouldHide = false

                if orig_type(v) == "function" then
                    orig_pcall(function()
                        if isexec and isexec(v) then
                            shouldHide = true
                        end
                    end)
                elseif orig_type(v) == "table" then
                    if orig_rawget(v, "manipulation") ~= nil and orig_rawget(v, "drawings") ~= nil then
                        shouldHide = true
                    elseif orig_rawget(v, "UE_LOADED") ~= nil then
                        shouldHide = true
                    end
                end

                if not shouldHide then
                    filtered[#filtered + 1] = v
                end
            end

            return filtered
        end))
    end)
    installStatus.getgc_hook = ok
end

--------------------------------------------------------------------------------
-- 11. getconnections 후킹 (커넥션 수 스푸핑)
--------------------------------------------------------------------------------
if hookfn and orig_type(getcons) == "function" then
    local ok, err = orig_pcall(function()
        local old_getcons
        old_getcons = hookfn(getcons, newc(function(signal)
            local conns = old_getcons(signal)
            if not isGameCaller() then return conns end

            local filtered = {}
            for i = 1, #conns do
                local conn = conns[i]
                local hide = false
                orig_pcall(function()
                    if conn.Function and isexec and isexec(conn.Function) then
                        hide = true
                    end
                end)
                if not hide then
                    filtered[#filtered + 1] = conn
                end
            end

            return filtered
        end))
    end)
    installStatus.getconnections_hook = ok
end

--------------------------------------------------------------------------------
-- 12. __namecall 후킹 (킥/밴 리모트 차단 + CoreGui 은폐)
--     hookmetamethod이 없으면 이 섹션 전체를 건너뜀
--------------------------------------------------------------------------------
if hookmm then
    local blocked_remotes = {
        ["Ban"] = true,
        ["Kick"] = true,
        ["BanPlayer"] = true,
        ["KickPlayer"] = true,
        ["Warn"] = true,
        ["Restrict"] = true,
        ["LockBans"] = true,
        ["PardonRedFlags"] = true,
        ["FlagPlayer"] = true,
        ["ReportCheat"] = true,
        ["LogSuspicious"] = true,
    }

    local ok_nc, err_nc = orig_pcall(function()
        local old_namecall
        old_namecall = hookmm(game, "__namecall", newc(function(self, ...)
            local method = getnm()

            if (method == "FireServer" or method == "InvokeServer") and orig_typeof(self) == "Instance" then
                if blocked_remotes[self.Name] then
                    return nil
                end
                local p = self.Parent
                if p and orig_typeof(p) == "Instance" then
                    if p.Name == "Moderator" or p.Name == "PrivateServer" or p.Name == "AntiCheat" then
                        return nil
                    end
                end
            end

            -- GetChildren/GetDescendants CoreGui 인스턴스 은폐
            if isGameCaller() and orig_typeof(self) == "Instance" then
                if method == "GetChildren" or method == "GetDescendants" then
                    if CoreGui and (self == CoreGui or (self.Parent and self.Parent == CoreGui)) then
                        local results = old_namecall(self, ...)
                        local filtered = {}
                        for i = 1, #results do
                            local child = results[i]
                            local hide = false
                            orig_pcall(function()
                                if child:IsA("ScreenGui") then
                                    local n = child.Name
                                    if string.len(n) >= 20 or n == "drawingDirectory" or n == "Linoria" then
                                        if child.DisplayOrder >= 10 then
                                            hide = true
                                        end
                                    end
                                end
                            end)
                            if not hide then
                                filtered[#filtered + 1] = child
                            end
                        end
                        return filtered
                    end
                end

                if method == "FindFirstChild" or method == "WaitForChild" then
                    if CoreGui and self == CoreGui then
                        local args = {...}
                        local name = args[1]
                        if orig_type(name) == "string" then
                            if name == "drawingDirectory" or name == "Linoria" then
                                return nil
                            end
                        end
                    end
                end
            end

            return old_namecall(self, ...)
        end))
    end)
    installStatus.namecall_hook = ok_nc

    -- __index 후킹
    local ok_idx, err_idx = orig_pcall(function()
        local old_index
        old_index = hookmm(game, "__index", newc(function(self, key)
            if isGameCaller() then
                if key == "Funny" then
                    return nil
                end
            end
            return old_index(self, key)
        end))
    end)
    installStatus.index_hook = ok_idx
else
    installStatus.namecall_hook = false
    installStatus.index_hook = false
    warn("[UE Bypass] hookmetamethod 미지원 — __namecall 후킹 스킵 (일부 보호 기능 제한)")
end

--------------------------------------------------------------------------------
-- 13. Player:Kick 무력화
--------------------------------------------------------------------------------
if hookfn then
    local ok, err = orig_pcall(function()
        local kickMethod
        local ok2, km = orig_pcall(function() return LocalPlayer.Kick end)
        if ok2 and orig_type(km) == "function" then
            kickMethod = km
        end

        if kickMethod then
            local old_kick
            old_kick = hookfn(kickMethod, newc(function(self, ...)
                if isGameCaller() and self == LocalPlayer then
                    return nil
                end
                return old_kick(self, ...)
            end))
        end
    end)
    installStatus.anti_kick = ok
end

--------------------------------------------------------------------------------
-- 14. require 후킹 (모듈 디퓨저)
--------------------------------------------------------------------------------
if hookfn and require then
    local ok, err = orig_pcall(function()
        local old_require
        old_require = hookfn(require, newc(function(...)
            local target = ...
            local res = old_require(...)

            if orig_typeof(target) == "Instance" then
                local name = target.Name
                if name == "ItemLibrary" or name == "EntityLookupParams" then
                    if orig_type(res) == "table" and orig_type(orig_rawget(res, "Items")) == "table" then
                        orig_pcall(orig_setmetatable, res.Items, nil)
                    end
                end
            end

            return res
        end))
    end)
    installStatus.require_hook = ok
end

--------------------------------------------------------------------------------
-- 15. 모듈 프리로드 디퓨저
--------------------------------------------------------------------------------
task.spawn(function()
    orig_pcall(function()
        local modules = ReplicatedStorage:WaitForChild("Modules", 10)
        if modules then
            local function defuseModule(mod)
                if not mod then return end
                local ok, res = orig_pcall(require, mod)
                if ok and orig_type(res) == "table" and orig_type(orig_rawget(res, "Items")) == "table" then
                    orig_pcall(orig_setmetatable, res.Items, nil)
                end
            end
            defuseModule(modules:FindFirstChild("ItemLibrary"))
            defuseModule(modules:FindFirstChild("EntityLookupParams"))
        end
    end)
end)

--------------------------------------------------------------------------------
-- 16. CoreGui 인스턴스 은폐 유틸 (UE에서 사용)
--------------------------------------------------------------------------------
ENV.__UE_RANDOM_NAME = function(prefix)
    local chars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
    local result = prefix or ""
    for i = 1, 16 do
        local idx = math.random(1, #chars)
        result = result .. string.sub(chars, idx, idx)
    end
    return result
end

local _randomNames = {}
ENV.__UE_GET_NAME = function(key)
    if not _randomNames[key] then
        _randomNames[key] = ENV.__UE_RANDOM_NAME("")
    end
    return _randomNames[key]
end

--------------------------------------------------------------------------------
-- 17. Lighting 인스턴스 은폐 + ContextActionService 이름 난독화
--------------------------------------------------------------------------------
if hookmm then
    ENV.__UE_HIDDEN_INSTANCES = setmetatable({}, { __mode = "v" })
    ENV.__UE_HIDE_INSTANCE = function(inst)
        if orig_typeof(inst) == "Instance" then
            ENV.__UE_HIDDEN_INSTANCES[inst] = true
        end
    end
end

ENV.__UE_ACTION_NAME = ENV.__UE_RANDOM_NAME("UA_")

-- 후크 등록 함수 (UE 스크립트에서 사용)
ENV.__UE_REGISTER_HOOK = function(fn)
    if orig_type(fn) == "function" then
        hookedFunctions[fn] = true
    end
end

--------------------------------------------------------------------------------
-- 상태 리포트 출력
--------------------------------------------------------------------------------
local report = {
    installed = true,
    version = 4,
    env_cloak = hookfn ~= nil,
    rawget_cloak = installStatus.rawget_hook == true,
    shared_r_secured = installStatus.shared_r == true,
    debug_info_hooked = installStatus.debug_info_hook == true,
    getgc_hooked = installStatus.getgc_hook == true,
    getconnections_hooked = installStatus.getconnections_hook == true,
    namecall_hooked = installStatus.namecall_hook == true,
    anti_kick = installStatus.anti_kick == true,
    require_hooked = installStatus.require_hook == true,
}

ENV.__UE_BYPASS = report

print("[UE Bypass v4] ===== Universal Executor Compatible =====")
print("[UE Bypass v4] 환경 은폐: " .. (report.env_cloak and "O" or "X"))
print("[UE Bypass v4] rawget 후킹: " .. (report.rawget_cloak and "O" or "X"))
print("[UE Bypass v4] shared.r 무력화: " .. (report.shared_r_secured and "O" or "X"))
print("[UE Bypass v4] debug.info 후킹: " .. (report.debug_info_hooked and "O" or "X"))
print("[UE Bypass v4] getgc 방어: " .. (report.getgc_hooked and "O" or "X"))
print("[UE Bypass v4] 커넥션 수 스푸핑: " .. (report.getconnections_hooked and "O" or "X"))
print("[UE Bypass v4] __namecall 후킹: " .. (report.namecall_hooked and "O" or "X"))
print("[UE Bypass v4] 킥 차단: " .. (report.anti_kick and "O" or "X"))
print("[UE Bypass v4] require 후킹: " .. (report.require_hooked and "O" or "X"))
print("[UE Bypass v4] ===========================================")

return report
