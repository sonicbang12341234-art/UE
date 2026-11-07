--[[
    UE Anti-Cheat Bypass Module v3
    Rivals 안티치트 완전 우회 — UE 스크립트 로드 전에 실행할 것

    이전 bp.txt / message_4.txt가 탐지된 원인 분석:
    1) debug.info 후킹이 특정 함수명만 처리 → AC가 다른 함수로 프로빙
    2) checkcaller 단독 의존 → 스레드 기반 탐지에 취약
    3) rawget 후킹 패턴이 AC에 시그니처로 등록됨
    4) getgc 스캔, 커넥션 수 감시, CoreGui 스캔 미대응
    5) shared.r 처리가 정적 → AC가 동적 검증 추가

    새 우회 전략:
    - 다층 호출자 판별 (checkcaller + getcallingscript + 스택 분석)
    - 환경 은폐 레이어 강화 (rawget, getfenv, getgenv, getrenv, typeof)
    - shared.r 동적 무력화 + 폴링 방어
    - debug.info/getinfo 포괄 후킹 (함수명 기반이 아닌 클로저 기반)
    - getgc 스캔 방어 (실행자 클로저 은폐)
    - 커넥션 수 스푸핑 (getconnections 후킹)
    - 인스턴스 은폐 (CoreGui 자식 스캔 방어)
    - 킥/밴 리모트 차단 + Player:Kick 무력화
    - 모듈 디퓨저 (ItemLibrary, EntityLookupParams 무력화)
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local CoreGui = game:GetService("CoreGui")

local LocalPlayer = Players.LocalPlayer

--------------------------------------------------------------------------------
-- 실행자 함수 캐싱 (후킹 전 원본 저장)
--------------------------------------------------------------------------------
local ENV = (getgenv and getgenv()) or _G

local hookfn = hookfunction or replaceclosure
local hookmm = hookmetamethod
local newc = newcclosure or function(f) return f end
local clonefn = clonefunction or function(f) return f end
local getrawmt = getrawmetatable or debug.getmetatable
local setro = setreadonly or (make_writeable and function(t, r)
    if r then make_readonly(t) else make_writeable(t) end
end)
local checkc = checkcaller or function() return false end
local getcscript = getcallingscript
local getcons = getconnections
local isexec = isexecutorclosure or is_synapse_function or isourclosure or function() return false end

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
local orig_tostring = tostring
local orig_setmetatable = setmetatable

-- 안전한 더미 함수
local DUMMY = newc(function() end)
local DUMMY_RET_NIL = newc(function() return nil end)
local DUMMY_RET_FALSE = newc(function() return false end)
local DUMMY_RET_TABLE = newc(function() return {} end)

--------------------------------------------------------------------------------
-- 1. 호출자 판별 시스템 (다층 검증)
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
-- 2. 실행자 함수 마커 (은폐 대상)
--------------------------------------------------------------------------------
local EXECUTOR_MARKERS = {}
do
    local names = {
        -- 핵심 후킹/메타테이블
        "hookfunction", "hookmetamethod", "newcclosure", "clonefunction",
        "replaceclosure", "restorefunction",
        "checkcaller", "getnamecallmethod", "setnamecallmethod",
        "getcallingscript", "isexecutorclosure", "isourclosure",
        "iscclosure", "islclosure",
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
        "getgenv", "getrenv", "getmenv", "gettenv",
        "identifyexecutor", "getexecutorname",
        "syn", "KRNL_LOADED", "fluxus", "SENTINEL_LOADED",
        "Solara", "Delta", "Arceus",
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
    }
    for _, name in names do
        EXECUTOR_MARKERS[name] = true
    end
end

--------------------------------------------------------------------------------
-- 3. 환경 복제 (실행자 함수 제거)
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
-- 4. shared.r 무력화 (Rivals AC의 핵심 탐지 벡터)
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
    if orig_type(shared) == "table" then
        if orig_type(orig_rawget(shared, "r")) == "table" then
            secureTable(shared.r)
        else
            local r = orig_setmetatable({}, r_meta)
            for i = 1, 128 do orig_rawset(r, i, secureDummy()) end
            orig_rawset(shared, "r", r)
        end

        -- shared 메타테이블 보호
        local smt = getrawmt and getrawmt(shared) or {}
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

    -- 폴링 방어 (0.1초마다 검증)
    task.spawn(function()
        while true do
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
            task.wait(0.1)
        end
    end)
end

--------------------------------------------------------------------------------
-- 5. rawget 후킹 (환경 스캔 차단)
--------------------------------------------------------------------------------
if hookfn then
    local old_rawget
    old_rawget = hookfn(rawget, newc(function(t, k)
        if isGameCaller() and orig_type(k) == "string" and EXECUTOR_MARKERS[k] then
            return nil
        end
        return old_rawget(t, k)
    end))
end

--------------------------------------------------------------------------------
-- 6. getfenv 후킹 (환경 은폐)
--------------------------------------------------------------------------------
if hookfn then
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
end

--------------------------------------------------------------------------------
-- 7. getgenv / getrenv 후킹
--------------------------------------------------------------------------------
if hookfn then
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

    local origGetrenv = orig_rawget(ENV, "getrenv")
    if orig_type(origGetrenv) == "function" and origGetrenv ~= origGetgenv then
        local old_getrenv
        old_getrenv = hookfn(origGetrenv, newc(function(...)
            local env = old_getrenv(...)
            if isGameCaller() and orig_type(env) == "table" then
                return sanitizeEnv(env)
            end
            return env
        end))
    end
end

--------------------------------------------------------------------------------
-- 8. debug.info 후킹 (스택 트레이스 은폐)
--    bp.txt는 함수명 3개만 처리해서 탐지됨 → 클로저 기반으로 전환
--------------------------------------------------------------------------------
if hookfn and debug and debug.info then
    -- 후킹된 함수 레지스트리 (나중에 UE 후크 등록용)
    local hookedFunctions = setmetatable({}, { __mode = "k" })

    local old_debug_info
    old_debug_info = hookfn(debug.info, newc(function(...)
        local args = { ... }
        local target = args[1]
        local specs = args[2]

        -- 함수 대상 + "f" 스펙 포함 시 → 후킹 여부 체크
        if orig_type(target) == "function" and orig_type(specs) == "string" then
            if string.find(specs, "f") then
                -- 실행자 클로저이면 더미 반환
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

            -- 이름 기반 방어 (AC가 특정 함수명으로 프로빙)
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

        -- 숫자 스택 레벨 + 게임 호출자 → ClientFighter/EmoteSoundLogic 방어
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

    -- 후킹 함수 등록 API (UE 스크립트에서 사용)
    ENV.__UE_REGISTER_HOOK = function(fn)
        if orig_type(fn) == "function" then
            hookedFunctions[fn] = true
        end
    end
end

--------------------------------------------------------------------------------
-- 9. getgc 후킹 (GC 스캔 방어)
--    AC가 getgc로 수상한 테이블/클로저를 찾는 것 차단
--------------------------------------------------------------------------------
if hookfn and orig_type(orig_rawget(ENV, "getgc")) == "function" then
    local old_getgc
    old_getgc = hookfn(getgc, newc(function(includeTable)
        local result = old_getgc(includeTable)
        if not isGameCaller() then return result end

        -- 게임 AC가 호출한 경우: 실행자 클로저와 UE 테이블 필터링
        local filtered = {}
        for _, v in result do
            local shouldHide = false

            if orig_type(v) == "function" then
                orig_pcall(function()
                    if isexec and isexec(v) then
                        shouldHide = true
                    end
                end)
            elseif orig_type(v) == "table" then
                -- UE State 테이블 패턴 감지 및 은폐
                if orig_rawget(v, "ClientFighter") ~= nil and orig_rawget(v, "IsLocalPlayer") ~= nil then
                    -- localFighter 테이블은 통과 (원래 게임 테이블)
                elseif orig_rawget(v, "manipulation") ~= nil and orig_rawget(v, "drawings") ~= nil then
                    shouldHide = true -- UE State 테이블
                elseif orig_rawget(v, "UE_LOADED") ~= nil then
                    shouldHide = true
                end
            end

            if not shouldHide then
                table.insert(filtered, v)
            end
        end

        return filtered
    end))
end

--------------------------------------------------------------------------------
-- 10. getconnections 후킹 (커넥션 수 스푸핑)
--     AC가 RenderStepped/Heartbeat 커넥션 수를 세서 비정상 감지
--------------------------------------------------------------------------------
if hookfn and orig_type(getcons) == "function" then
    local old_getcons
    old_getcons = hookfn(getcons, newc(function(signal)
        local conns = old_getcons(signal)
        if not isGameCaller() then return conns end

        -- 게임이 호출: 실행자 커넥션 숨기기
        local filtered = {}
        for _, conn in conns do
            local hide = false
            orig_pcall(function()
                if conn.Function and isexec and isexec(conn.Function) then
                    hide = true
                end
            end)
            if not hide then
                table.insert(filtered, conn)
            end
        end

        return filtered
    end))
end

--------------------------------------------------------------------------------
-- 11. __namecall 후킹 (킥/밴 리모트 차단)
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

    local old_namecall
    old_namecall = hookmm(game, "__namecall", newc(function(self, ...)
        local method = getnamecallmethod()

        if (method == "FireServer" or method == "InvokeServer") and orig_typeof(self) == "Instance" then
            if blocked_remotes[self.Name] then
                return nil
            end
            -- Moderator/PrivateServer 경로 차단
            local p = self.Parent
            if p and orig_typeof(p) == "Instance" then
                if p.Name == "Moderator" or p.Name == "PrivateServer" or p.Name == "AntiCheat" then
                    return nil
                end
            end
        end

        -- GetChildren/GetDescendants 호출 시 CoreGui의 UE GUI 숨기기
        if isGameCaller() and orig_typeof(self) == "Instance" then
            if method == "GetChildren" or method == "GetDescendants" then
                if self == CoreGui or (self.Parent and self.Parent == CoreGui) then
                    local results = old_namecall(self, ...)
                    local filtered = {}
                    for _, child in results do
                        local hide = false
                        orig_pcall(function()
                            if child:IsA("ScreenGui") then
                                local n = child.Name
                                -- UE의 drawingDirectory와 LinoriaLib GUI 숨기기
                                if string.len(n) >= 20 or n == "drawingDirectory" or n == "Linoria" then
                                    if child.DisplayOrder >= 10 then
                                        hide = true
                                    end
                                end
                            end
                        end)
                        if not hide then
                            table.insert(filtered, child)
                        end
                    end
                    return filtered
                end
            end

            -- FindFirstChild로 UE GUI 직접 접근 차단
            if method == "FindFirstChild" or method == "WaitForChild" then
                if self == CoreGui then
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

    -- __index 후킹 (특정 속성 숨기기)
    local old_index
    old_index = hookmm(game, "__index", newc(function(self, key)
        if isGameCaller() then
            -- "Funny" 속성 숨기기 (Rivals AC 프로브)
            if key == "Funny" then
                return nil
            end
        end
        return old_index(self, key)
    end))
end

--------------------------------------------------------------------------------
-- 12. Player:Kick 무력화
--------------------------------------------------------------------------------
if hookfn then
    local ok, kickMethod = orig_pcall(function()
        return LocalPlayer.Kick
    end)

    if ok and orig_type(kickMethod) == "function" then
        local old_kick
        old_kick = hookfn(kickMethod, newc(function(self, ...)
            if isGameCaller() and self == LocalPlayer then
                return nil
            end
            return old_kick(self, ...)
        end))
    end
end

--------------------------------------------------------------------------------
-- 13. require 후킹 (모듈 디퓨저)
--------------------------------------------------------------------------------
if hookfn and require then
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
end

--------------------------------------------------------------------------------
-- 14. 모듈 프리로드 디퓨저
--------------------------------------------------------------------------------
task.spawn(function()
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

--------------------------------------------------------------------------------
-- 15. CoreGui 인스턴스 은폐 유틸 (UE에서 사용)
--------------------------------------------------------------------------------
-- UE가 생성하는 GUI 이름을 랜덤화하는 유틸리티
ENV.__UE_RANDOM_NAME = function(prefix)
    local chars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
    local result = prefix or ""
    for i = 1, 16 do
        local idx = math.random(1, #chars)
        result = result .. string.sub(chars, idx, idx)
    end
    return result
end

-- 랜덤 인스턴스 이름 생성기 (캐시)
local _randomNames = {}
ENV.__UE_GET_NAME = function(key)
    if not _randomNames[key] then
        _randomNames[key] = ENV.__UE_RANDOM_NAME("")
    end
    return _randomNames[key]
end

--------------------------------------------------------------------------------
-- 16. Lighting 인스턴스 은폐
--     AC가 Lighting에서 비정상 PostEffect를 스캔하는 것 방어
--------------------------------------------------------------------------------
if hookmm then
    local Lighting = game:GetService("Lighting")
    -- GetChildren/GetDescendants가 Lighting에서 호출될 때 UE 이펙트 숨기기
    -- (이미 __namecall에서 CoreGui 처리했으므로 Lighting도 추가)
    -- 이 부분은 UE 스크립트에서 이펙트 생성 시 태깅하여 처리
    ENV.__UE_HIDDEN_INSTANCES = setmetatable({}, { __mode = "v" })

    ENV.__UE_HIDE_INSTANCE = function(inst)
        if orig_typeof(inst) == "Instance" then
            ENV.__UE_HIDDEN_INSTANCES[inst] = true
        end
    end
end

--------------------------------------------------------------------------------
-- 17. ContextActionService 이름 난독화
--------------------------------------------------------------------------------
ENV.__UE_ACTION_NAME = ENV.__UE_RANDOM_NAME("UA_")

--------------------------------------------------------------------------------
-- 반환값: 우회 상태 리포트
--------------------------------------------------------------------------------
local report = {
    installed = true,
    version = 3,
    env_cloak = hookfn ~= nil,
    rawget_cloak = hookfn ~= nil,
    shared_r_secured = orig_type(shared) == "table",
    debug_info_hooked = hookfn ~= nil and debug and debug.info ~= nil,
    getgc_hooked = hookfn ~= nil and orig_type(orig_rawget(ENV, "getgc")) == "function",
    getconnections_hooked = hookfn ~= nil and orig_type(getcons) == "function",
    namecall_hooked = hookmm ~= nil,
    anti_kick = hookfn ~= nil,
    require_hooked = hookfn ~= nil,
}

-- UE에서 상태 확인용
ENV.__UE_BYPASS = report

return report
