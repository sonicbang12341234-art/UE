--[[
    Unnamed Enhancements — Local Runner (Volcano 호환)
    ==================================================
    사용법:
    1. 이 파일(UE_Run.lua)과 main.lua를 Volcano의 workspace 폴더에 넣기
    2. Volcano에서 이 파일 실행 또는 아래 명령어 입력:
       loadstring(readfile("UE_Run.lua"))()

    GitHub가 Public이면 이것도 가능:
    loadstring(game:HttpGet("https://raw.githubusercontent.com/sonicbang12341234-art/UE/main/UE_Run.lua"))()
]]

--------------------------------------------------------------------------------
-- 0. Universal Executor Compatibility Layer
--------------------------------------------------------------------------------

-- task 라이브러리 폴리필
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

if not getnamecallmethod then
    getnamecallmethod = function() return "" end
end

if not typeof then
    typeof = function(v)
        local t = type(v)
        if t == "userdata" then
            local ok, cls = pcall(function() return v.ClassName end)
            if ok and cls then return "Instance" end
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
pcall(function() CoreGui = game:GetService("CoreGui") end)
if not CoreGui then
    pcall(function() CoreGui = (gethui and gethui()) or game:FindFirstChild("CoreGui") end)
end
local LocalPlayer = Players.LocalPlayer

--------------------------------------------------------------------------------
-- 1. 실행자 함수 캐싱
--------------------------------------------------------------------------------
local ENV = (getgenv and getgenv()) or _G

local hookfn = hookfunction or replaceclosure or detour_function
local hookmm = hookmetamethod
local newc = newcclosure or CClosure or function(f) return f end
local clonefn = clonefunction or function(f) return f end
local getrawmt = getrawmetatable or debug.getmetatable
local setro = setreadonly or (make_writeable and function(t, r)
    if r then make_readonly(t) else make_writeable(t) end
end)
local checkc = checkcaller or function() return false end
local getcscript = getcallingscript
local getcons = getconnections
local isexec = isexecutorclosure or is_synapse_function or isourclosure or function() return false end
local getnm = getnamecallmethod

local orig_rawget = rawget
local orig_rawset = rawset
local orig_getfenv = getfenv
local orig_type = type
local orig_typeof = typeof
local orig_pcall = pcall
local orig_unpack = unpack
local orig_next = next
local orig_setmetatable = setmetatable

local DUMMY = newc(function() end)
local installStatus = {}

--------------------------------------------------------------------------------
-- 2. 호출자 판별
--------------------------------------------------------------------------------
local function isGameCaller()
    if orig_type(checkc) == "function" then
        local ok, result = orig_pcall(checkc)
        if ok and result == true then return false end
    end
    if orig_type(getcscript) == "function" then
        local ok, scr = orig_pcall(getcscript)
        if ok and orig_typeof(scr) == "Instance" then return true end
        if ok and scr == nil then return false end
    end
    return true
end

--------------------------------------------------------------------------------
-- 3. 실행자 함수 마커
--------------------------------------------------------------------------------
local EXECUTOR_MARKERS = {}
do
    local names = {
        "hookfunction","hookmetamethod","newcclosure","clonefunction",
        "replaceclosure","restorefunction","detour_function",
        "checkcaller","getnamecallmethod","setnamecallmethod",
        "getcallingscript","isexecutorclosure","isourclosure",
        "iscclosure","islclosure","is_synapse_function",
        "getgc","getreg","getrawmetatable","setrawmetatable",
        "setreadonly","isreadonly","make_writeable","make_readonly",
        "getconnections","getcallbackvalue","setcallbackvalue",
        "getscriptclosure","getscriptbytecode","getscripthash",
        "getsenv","getmenv","getloadedmodules","getscripts","getrunningscripts",
        "getconstants","getconstant","setconstant",
        "getupvalues","getupvalue","setupvalue",
        "getprotos","getproto","setproto","getstack","setstack","getthread",
        "getgenv","getrenv","gettenv",
        "identifyexecutor","getexecutorname",
        "syn","KRNL_LOADED","fluxus","SENTINEL_LOADED",
        "Solara","Delta","Arceus","Volcano","VOLCANO_LOADED",
        "Hydrogen","Electron","Wave","Codex","Evon",
        "readfile","writefile","appendfile","loadfile",
        "listfiles","makefolder","delfile","delfolder","isfile","isfolder",
        "setclipboard","toclipboard",
        "request","http_request","httprequest","syn_request",
        "WebSocket","WebSocket_connect",
        "gethui","protect_gui","unprotect_gui",
        "cloneref","compareinstances",
        "fireclickdetector","fireproximityprompt","firetouchinterest","firesignal",
        "gethiddenproperty","sethiddenproperty","setscriptable",
        "Drawing","cleardrawcache",
        "queue_on_teleport","queueonteleport",
        "UE_LOADED","CClosure",
    }
    for i = 1, #names do EXECUTOR_MARKERS[names[i]] = true end
end

--------------------------------------------------------------------------------
-- 4. 환경 복제
--------------------------------------------------------------------------------
local function sanitizeEnv(src)
    if orig_type(src) ~= "table" then return src end
    local clean = {}
    for k, v in orig_next, src do
        if not (orig_type(k) == "string" and EXECUTOR_MARKERS[k]) then
            clean[k] = v
        end
    end
    if orig_rawget(clean, "_G") == nil and orig_rawget(src, "_G") == src then
        clean._G = clean
    end
    return clean
end

--------------------------------------------------------------------------------
-- 5. shared.r 무력화
--------------------------------------------------------------------------------
do
    local function secureDummy() return newc(function() end) end
    local r_meta = {
        __index = function() return secureDummy() end,
        __newindex = function(t, k, v) orig_rawset(t, k, secureDummy()) end,
        __len = function() return 0 end,
        __pairs = function(t) return function() return nil end, t, nil end,
        __metatable = "locked",
    }
    local function secureTable(tbl)
        if orig_type(tbl) ~= "table" then return end
        for k in orig_next, tbl do orig_rawset(tbl, k, secureDummy()) end
        for i = 1, 128 do orig_rawset(tbl, i, secureDummy()) end
        orig_pcall(orig_setmetatable, tbl, r_meta)
    end

    orig_pcall(function()
        if orig_type(shared) == "table" then
            if orig_type(orig_rawget(shared, "r")) == "table" then
                secureTable(shared.r)
            else
                local r = orig_setmetatable({}, r_meta)
                for i = 1, 128 do orig_rawset(r, i, secureDummy()) end
                orig_rawset(shared, "r", r)
            end
            local smt = (getrawmt and getrawmt(shared)) or {}
            local old_ni = smt.__newindex
            if setro then orig_pcall(setro, smt, false) end
            smt.__newindex = newc(function(t, k, v)
                if k == "r" and orig_type(v) == "table" then
                    secureTable(v); return orig_rawset(t, k, v)
                end
                if old_ni then return old_ni(t, k, v) end
                return orig_rawset(t, k, v)
            end)
            if setro then orig_pcall(setro, smt, true) end
        end
    end)

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
-- 6~9. 후킹 (모두 pcall 래핑)
--------------------------------------------------------------------------------
-- rawget 후킹
if hookfn then
    orig_pcall(function()
        local old_rawget
        old_rawget = hookfn(rawget, newc(function(t, k)
            if isGameCaller() and orig_type(k) == "string" and EXECUTOR_MARKERS[k] then return nil end
            return old_rawget(t, k)
        end))
        installStatus.rawget = true
    end)
end

-- getfenv 후킹
if hookfn then
    orig_pcall(function()
        local old_getfenv
        old_getfenv = hookfn(getfenv, newc(function(target)
            local query = target
            if orig_type(target) == "number" then query = target + 1
            elseif target == nil then query = 2 end
            local env = old_getfenv(query)
            if isGameCaller() and orig_type(env) == "table" then return sanitizeEnv(env) end
            return env
        end))
        installStatus.getfenv = true
    end)
end

-- getgenv/getrenv 후킹
if hookfn then
    orig_pcall(function()
        local origGg = orig_rawget(ENV, "getgenv")
        if orig_type(origGg) == "function" then
            local old_gg
            old_gg = hookfn(origGg, newc(function(...)
                local env = old_gg(...)
                if isGameCaller() and orig_type(env) == "table" then return sanitizeEnv(env) end
                return env
            end))
        end
    end)
    orig_pcall(function()
        local origGr = orig_rawget(ENV, "getrenv")
        if orig_type(origGr) == "function" then
            local old_gr
            old_gr = hookfn(origGr, newc(function(...)
                local env = old_gr(...)
                if isGameCaller() and orig_type(env) == "table" then return sanitizeEnv(env) end
                return env
            end))
        end
    end)
end

-- debug.info 후킹
local hookedFunctions = setmetatable({}, { __mode = "k" })
if hookfn and debug and debug.info then
    orig_pcall(function()
        local old_dinfo
        old_dinfo = hookfn(debug.info, newc(function(...)
            local args = { ... }
            local target = args[1]
            local specs = args[2]
            if orig_type(target) == "function" and orig_type(specs) == "string" then
                if string.find(specs, "f") and isGameCaller() then
                    local isHooked = hookedFunctions[target]
                    local isExec = false
                    orig_pcall(function() if isexec and isexec(target) then isExec = true end end)
                    if isHooked or isExec then
                        local results = { old_dinfo(target, specs) }
                        local idx = 0
                        for i = 1, #specs do
                            local c = string.sub(specs, i, i)
                            if c == "s" or c == "l" or c == "f" or c == "n" or c == "a" then
                                idx = idx + 1
                                if c == "f" then results[idx] = DUMMY; break end
                            end
                        end
                        return orig_unpack(results)
                    end
                end
                if isGameCaller() and string.find(specs, "n") then
                    local name = old_dinfo(target, "n")
                    if name and EXECUTOR_MARKERS[name] then
                        local results = { old_dinfo(target, specs) }
                        for i = 1, #specs do
                            local c = string.sub(specs, i, i)
                            if c == "n" then results[i] = ""
                            elseif c == "f" then results[i] = DUMMY end
                        end
                        return orig_unpack(results)
                    end
                end
            end
            if orig_type(target) == "number" and isGameCaller() and target <= 5 and specs == "f" then
                local caller = getcscript and getcscript()
                if caller and orig_typeof(caller) == "Instance" then
                    local n = caller.Name
                    if n == "ClientFighter" or n == "EmoteSoundLogic" or n == "AntiCheat" then
                        return DUMMY
                    end
                end
            end
            return old_dinfo(...)
        end))
        installStatus.debug_info = true
    end)
end

-- getgc 후킹
if hookfn and orig_type(orig_rawget(ENV, "getgc")) == "function" then
    orig_pcall(function()
        local old_getgc
        old_getgc = hookfn(getgc, newc(function(includeTable)
            local result = old_getgc(includeTable)
            if not isGameCaller() then return result end
            local filtered = {}
            for i = 1, #result do
                local v = result[i]
                local shouldHide = false
                if orig_type(v) == "function" then
                    orig_pcall(function() if isexec and isexec(v) then shouldHide = true end end)
                elseif orig_type(v) == "table" then
                    if orig_rawget(v, "manipulation") ~= nil and orig_rawget(v, "drawings") ~= nil then
                        shouldHide = true
                    elseif orig_rawget(v, "UE_LOADED") ~= nil then shouldHide = true end
                end
                if not shouldHide then filtered[#filtered + 1] = v end
            end
            return filtered
        end))
        installStatus.getgc = true
    end)
end

-- getconnections 후킹
if hookfn and orig_type(getcons) == "function" then
    orig_pcall(function()
        local old_getcons
        old_getcons = hookfn(getcons, newc(function(signal)
            local conns = old_getcons(signal)
            if not isGameCaller() then return conns end
            local filtered = {}
            for i = 1, #conns do
                local conn = conns[i]
                local hide = false
                orig_pcall(function() if conn.Function and isexec and isexec(conn.Function) then hide = true end end)
                if not hide then filtered[#filtered + 1] = conn end
            end
            return filtered
        end))
        installStatus.getconnections = true
    end)
end

--------------------------------------------------------------------------------
-- 10. __namecall 후킹
--------------------------------------------------------------------------------
if hookmm then
    local blocked = {
        Ban=true, Kick=true, BanPlayer=true, KickPlayer=true,
        Warn=true, Restrict=true, LockBans=true, PardonRedFlags=true,
        FlagPlayer=true, ReportCheat=true, LogSuspicious=true,
    }
    orig_pcall(function()
        local old_namecall
        old_namecall = hookmm(game, "__namecall", newc(function(self, ...)
            local method = getnm()
            if (method == "FireServer" or method == "InvokeServer") and orig_typeof(self) == "Instance" then
                if blocked[self.Name] then return nil end
                local p = self.Parent
                if p and orig_typeof(p) == "Instance" then
                    if p.Name == "Moderator" or p.Name == "PrivateServer" or p.Name == "AntiCheat" then
                        return nil
                    end
                end
            end
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
                                        if child.DisplayOrder >= 10 then hide = true end
                                    end
                                end
                            end)
                            if not hide then filtered[#filtered + 1] = child end
                        end
                        return filtered
                    end
                end
                if method == "FindFirstChild" or method == "WaitForChild" then
                    if CoreGui and self == CoreGui then
                        local args = {...}
                        local name = args[1]
                        if orig_type(name) == "string" and (name == "drawingDirectory" or name == "Linoria") then
                            return nil
                        end
                    end
                end
            end
            return old_namecall(self, ...)
        end))
        installStatus.namecall = true
    end)
    orig_pcall(function()
        local old_index
        old_index = hookmm(game, "__index", newc(function(self, key)
            if isGameCaller() and key == "Funny" then return nil end
            return old_index(self, key)
        end))
    end)
end

-- Player:Kick 무력화
if hookfn then
    orig_pcall(function()
        local ok2, km = orig_pcall(function() return LocalPlayer.Kick end)
        if ok2 and orig_type(km) == "function" then
            local old_kick
            old_kick = hookfn(km, newc(function(self, ...)
                if isGameCaller() and self == LocalPlayer then return nil end
                return old_kick(self, ...)
            end))
            installStatus.anti_kick = true
        end
    end)
end

-- require 후킹
if hookfn and require then
    orig_pcall(function()
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
end

-- 모듈 프리로드 디퓨저
task.spawn(function()
    orig_pcall(function()
        local modules = ReplicatedStorage:WaitForChild("Modules", 10)
        if modules then
            local function defuse(mod)
                if not mod then return end
                local ok, res = orig_pcall(require, mod)
                if ok and orig_type(res) == "table" and orig_type(orig_rawget(res, "Items")) == "table" then
                    orig_pcall(orig_setmetatable, res.Items, nil)
                end
            end
            defuse(modules:FindFirstChild("ItemLibrary"))
            defuse(modules:FindFirstChild("EntityLookupParams"))
        end
    end)
end)

--------------------------------------------------------------------------------
-- 11. UE 유틸리티 전역 설정
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

ENV.__UE_ACTION_NAME = ENV.__UE_RANDOM_NAME("UA_")
ENV.__UE_REGISTER_HOOK = function(fn)
    if orig_type(fn) == "function" then hookedFunctions[fn] = true end
end

if hookmm then
    ENV.__UE_HIDDEN_INSTANCES = setmetatable({}, { __mode = "v" })
    ENV.__UE_HIDE_INSTANCE = function(inst)
        if orig_typeof(inst) == "Instance" then
            ENV.__UE_HIDDEN_INSTANCES[inst] = true
        end
    end
end

ENV.__UE_BYPASS = {
    installed = true,
    version = 4,
}

-- 더블로드 방지
local _ue_key = "__ue_" .. tostring(math.random(100000, 999999))
if orig_rawget(_G, _ue_key) then return end
orig_rawset(_G, _ue_key, true)
ENV.UE_LOADED = nil

print("[UE Bypass v4] 안티치트 우회 설치 완료")

--------------------------------------------------------------------------------
-- 12. 런타임 패처 + 메인 스크립트 로드
--------------------------------------------------------------------------------
local _actionName = ENV.__UE_ACTION_NAME

local function patchAndLoad(source)
    if not source or #source < 100 then
        warn("[UE] 소스가 비어있음")
        return false
    end

    -- 패치 적용
    source = source:gsub('if getgenv%(%)%.UE_LOADED then%s+return%s+end', '-- [PATCHED]')
    source = source:gsub('Name = "drawingDirectory"', 'Name = "' .. ENV.__UE_GET_NAME("drawGui") .. '"')
    source = source:gsub('"UE_BlockInput"', '"' .. _actionName .. '"')
    source = source:gsub('getgenv%(%)%.ThemeManager = ThemeManager', '-- [PATCHED]')
    source = source:gsub('getgenv%(%)%.SaveManager = SaveManager', '-- [PATCHED]')
    source = source:gsub('getgenv%(%)%.UE_LOADED = true', '-- [PATCHED]')

    -- Volcano 호환성 패치
    -- Fix 1: CreateGroupBox가 AddLeftTabbox()를 반환 → AddLabel 없음 → 크래시
    -- AddLeftGroupbox("Themes")로 변경하면 AddLabel이 있는 groupbox 반환
    source = source:gsub('return tab:AddLeftTabbox%(%)','return tab:AddLeftGroupbox("Themes")')

    -- Fix 2: ThemeManager:ApplyToTab 안전하게 pcall 래핑
    -- 두 번째 ThemeManager 복사본에 CreateThemeManager가 없어서 크래시 가능
    source = source:gsub(
        'ThemeManager:ApplyToTab%(SettingsTab%)',
        'pcall(function() ThemeManager:ApplyToTab(SettingsTab) end)'
    )

    -- Fix 3: SaveManager 관련 호출도 pcall 래핑
    source = source:gsub(
        'SaveManager:BuildConfigSection%(SettingsTab%)',
        'pcall(function() SaveManager:BuildConfigSection(SettingsTab) end)'
    )
    source = source:gsub(
        'SaveManager:LoadAutoloadConfig%(%)',
        'pcall(SaveManager.LoadAutoloadConfig, SaveManager)'
    )

    -- Fix 4: initialize(Library) 중복 실행 방지
    -- main.lua에 initialize 함수와 호출이 2개씩 있음 → 두 번째는 스킵
    source = "local __ue_init_done = false\n" .. source
    source = source:gsub(
        'initialize%(Library%)',
        'if not __ue_init_done then __ue_init_done = true; initialize(Library) end'
    )

    local fn, err = loadstring(source)
    if not fn then
        warn("[UE] 컴파일 실패: " .. tostring(err))
        return false
    end

    local ok, runErr = pcall(fn)
    if not ok then
        warn("[UE] 실행 오류: " .. tostring(runErr))
        return false
    end

    print("[UE] 스크립트 로드 완료!")
    return true
end

-- main.lua 소스 로드 (우선순위: 로컬 파일 → GitHub)
local source = nil

-- 1순위: 로컬 파일
pcall(function()
    if readfile then
        if isfile and isfile("main.lua") then
            source = readfile("main.lua")
            print("[UE] 로컬 파일 로드: main.lua")
        elseif isfile and isfile("UnnamedEnhancements.lua") then
            source = readfile("UnnamedEnhancements.lua")
            print("[UE] 로컬 파일 로드: UnnamedEnhancements.lua")
        end
    end
end)

-- 2순위: GitHub (Public 레포일 때만 작동)
if not source then
    local REPO = "https://raw.githubusercontent.com/sonicbang12341234-art/UE/main/"
    pcall(function()
        local result = game:HttpGet(REPO .. "main.lua", true)
        if result and #result > 100 then
            source = result
            print("[UE] GitHub에서 로드 성공")
        end
    end)
    -- HttpGet 방법 2
    if not source then
        pcall(function()
            local result = game:HttpGet(REPO .. "main.lua")
            if result and #result > 100 then
                source = result
                print("[UE] GitHub에서 로드 성공 (2)")
            end
        end)
    end
    -- request 함수 시도
    if not source then
        local reqFn = request or http_request or httprequest or syn_request
        if reqFn then
            pcall(function()
                local resp = reqFn({ Url = REPO .. "main.lua", Method = "GET" })
                if resp and resp.Body and #resp.Body > 100 then
                    source = resp.Body
                    print("[UE] HTTP request로 로드 성공")
                end
            end)
        end
    end
end

-- 실행
if source then
    patchAndLoad(source)
else
    warn("[UE] ========================================")
    warn("[UE] main.lua를 찾을 수 없습니다!")
    warn("[UE] ")
    warn("[UE] 해결 방법:")
    warn("[UE] 1. main.lua 파일을 executor의 workspace 폴더에 넣으세요")
    warn("[UE] 2. 또는 GitHub 레포를 Public으로 변경하세요")
    warn("[UE] ========================================")
end
