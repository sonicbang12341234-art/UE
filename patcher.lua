--[[
    UE Patched Loader v3
    =====================
    이 스크립트 하나만 실행하면 됩니다.

    1. 안티치트 우회 모듈 로드 (환경 은폐, shared.r 무력화, 후킹 방어 등)
    2. UE 스크립트의 탐지 취약점을 런타임 패치
    3. 패치된 UE 스크립트 실행

    사용법:
        loadstring(이_스크립트)()

    또는 executor에서 직접 실행
]]

----------------------------------------------------------------
-- PHASE 1: 안티치트 우회 모듈
----------------------------------------------------------------
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local CoreGui = game:GetService("CoreGui")
local HttpService = game:GetService("HttpService")
local LocalPlayer = Players.LocalPlayer

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

-- 호출자 판별
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

-- 실행자 마커
local MARKERS = {}
do
    local names = {
        "hookfunction","hookmetamethod","newcclosure","clonefunction","replaceclosure","restorefunction",
        "checkcaller","getnamecallmethod","setnamecallmethod","getcallingscript",
        "isexecutorclosure","isourclosure","iscclosure","islclosure",
        "getgc","getreg","getrawmetatable","setrawmetatable","setreadonly","isreadonly",
        "make_writeable","make_readonly","getconnections","getcallbackvalue","setcallbackvalue",
        "getscriptclosure","getscriptbytecode","getscripthash","getsenv","getmenv",
        "getloadedmodules","getscripts","getrunningscripts",
        "getconstants","getconstant","setconstant","getupvalues","getupvalue","setupvalue",
        "getprotos","getproto","setproto","getstack","setstack","getthread",
        "getgenv","getrenv","getmenv","gettenv","identifyexecutor","getexecutorname",
        "syn","KRNL_LOADED","fluxus","SENTINEL_LOADED","Solara","Delta","Arceus",
        "readfile","writefile","appendfile","loadfile","listfiles","makefolder",
        "delfile","delfolder","isfile","isfolder",
        "setclipboard","toclipboard","request","http_request","httprequest","syn_request",
        "WebSocket","WebSocket_connect",
        "gethui","protect_gui","unprotect_gui","cloneref","compareinstances",
        "fireclickdetector","fireproximityprompt","firetouchinterest","firesignal",
        "gethiddenproperty","sethiddenproperty","setscriptable",
        "Drawing","cleardrawcache","queue_on_teleport","queueonteleport",
        "UE_LOADED",
    }
    for _, n in names do MARKERS[n] = true end
end

local function sanitizeEnv(src)
    if orig_type(src) ~= "table" then return src end
    local clean = {}
    for k, v in orig_next, src do
        if not (orig_type(k) == "string" and MARKERS[k]) then
            clean[k] = v
        end
    end
    if orig_rawget(clean, "_G") == nil and orig_rawget(src, "_G") == src then
        clean._G = clean
    end
    return clean
end

-- shared.r 무력화
do
    local function secureDummy() return newc(function() end) end
    local r_meta = {
        __index = function() return secureDummy() end,
        __newindex = function(t, k, v) orig_rawset(t, k, secureDummy()) end,
        __len = function() return 0 end,
        __metatable = "locked",
    }
    local function secureTable(tbl)
        if orig_type(tbl) ~= "table" then return end
        for k in orig_next, tbl do orig_rawset(tbl, k, secureDummy()) end
        for i = 1, 128 do orig_rawset(tbl, i, secureDummy()) end
        orig_pcall(orig_setmetatable, tbl, r_meta)
    end

    if orig_type(shared) == "table" then
        if orig_type(orig_rawget(shared, "r")) == "table" then
            secureTable(shared.r)
        else
            local r = orig_setmetatable({}, r_meta)
            for i = 1, 128 do orig_rawset(r, i, secureDummy()) end
            orig_rawset(shared, "r", r)
        end
        local smt = getrawmt and getrawmt(shared) or {}
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
                end
            end
            task.wait(0.1)
        end
    end)
end

-- rawget 후킹
if hookfn then
    local old_rawget
    old_rawget = hookfn(rawget, newc(function(t, k)
        if isGameCaller() and orig_type(k) == "string" and MARKERS[k] then return nil end
        return old_rawget(t, k)
    end))
end

-- getfenv 후킹
if hookfn then
    local old_getfenv
    old_getfenv = hookfn(getfenv, newc(function(target)
        local query = target
        if orig_type(target) == "number" then query = target + 1
        elseif target == nil then query = 2 end
        local env = old_getfenv(query)
        if isGameCaller() and orig_type(env) == "table" then return sanitizeEnv(env) end
        return env
    end))
end

-- getgenv / getrenv 후킹
if hookfn then
    local origGgenv = orig_rawget(ENV, "getgenv")
    if orig_type(origGgenv) == "function" then
        local old_gg
        old_gg = hookfn(origGgenv, newc(function(...)
            local env = old_gg(...)
            if isGameCaller() and orig_type(env) == "table" then return sanitizeEnv(env) end
            return env
        end))
    end
    local origGreenv = orig_rawget(ENV, "getrenv")
    if orig_type(origGreenv) == "function" and origGreenv ~= origGgenv then
        local old_gr
        old_gr = hookfn(origGreenv, newc(function(...)
            local env = old_gr(...)
            if isGameCaller() and orig_type(env) == "table" then return sanitizeEnv(env) end
            return env
        end))
    end
end

-- debug.info 후킹
local hookedFunctions = setmetatable({}, { __mode = "k" })
if hookfn and debug and debug.info then
    local old_dinfo
    old_dinfo = hookfn(debug.info, newc(function(...)
        local args = { ... }
        local target = args[1]
        local specs = args[2]

        if orig_type(target) == "function" and orig_type(specs) == "string" then
            if string.find(specs, "f") and isGameCaller() then
                local isHooked = hookedFunctions[target]
                local isExec = false
                orig_pcall(function()
                    if isexec and isexec(target) then isExec = true end
                end)
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
                if name and MARKERS[name] then
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
end

-- getgc 후킹
if hookfn and orig_type(orig_rawget(ENV, "getgc")) == "function" then
    local old_getgc
    old_getgc = hookfn(getgc, newc(function(includeTable)
        local result = old_getgc(includeTable)
        if not isGameCaller() then return result end
        local filtered = {}
        for _, v in result do
            local shouldHide = false
            if orig_type(v) == "function" then
                orig_pcall(function()
                    if isexec and isexec(v) then shouldHide = true end
                end)
            elseif orig_type(v) == "table" then
                if orig_rawget(v, "manipulation") ~= nil and orig_rawget(v, "drawings") ~= nil then
                    shouldHide = true
                elseif orig_rawget(v, "UE_LOADED") ~= nil then
                    shouldHide = true
                end
            end
            if not shouldHide then table.insert(filtered, v) end
        end
        return filtered
    end))
end

-- getconnections 후킹
if hookfn and orig_type(getcons) == "function" then
    local old_getcons
    old_getcons = hookfn(getcons, newc(function(signal)
        local conns = old_getcons(signal)
        if not isGameCaller() then return conns end
        local filtered = {}
        for _, conn in conns do
            local hide = false
            orig_pcall(function()
                if conn.Function and isexec and isexec(conn.Function) then hide = true end
            end)
            if not hide then table.insert(filtered, conn) end
        end
        return filtered
    end))
end

-- __namecall 후킹 (킥/밴 차단 + CoreGui 인스턴스 은폐)
if hookmm then
    local blocked_remotes = {
        Ban=true, Kick=true, BanPlayer=true, KickPlayer=true,
        Warn=true, Restrict=true, LockBans=true, PardonRedFlags=true,
        FlagPlayer=true, ReportCheat=true, LogSuspicious=true,
    }

    local old_namecall
    old_namecall = hookmm(game, "__namecall", newc(function(self, ...)
        local method = getnamecallmethod()

        if (method == "FireServer" or method == "InvokeServer") and orig_typeof(self) == "Instance" then
            if blocked_remotes[self.Name] then return nil end
            local p = self.Parent
            if p and orig_typeof(p) == "Instance" then
                if p.Name == "Moderator" or p.Name == "PrivateServer" or p.Name == "AntiCheat" then
                    return nil
                end
            end
        end

        if isGameCaller() and orig_typeof(self) == "Instance" then
            if method == "GetChildren" or method == "GetDescendants" then
                if self == CoreGui or (self.Parent and self.Parent == CoreGui) then
                    local results = old_namecall(self, ...)
                    local filtered = {}
                    for _, child in results do
                        local hide = false
                        orig_pcall(function()
                            if child:IsA("ScreenGui") and child.DisplayOrder >= 10 then
                                local n = child.Name
                                if string.len(n) >= 20 or n == "drawingDirectory" or n == "Linoria" then
                                    hide = true
                                end
                            end
                        end)
                        if not hide then table.insert(filtered, child) end
                    end
                    return filtered
                end
            end
            if method == "FindFirstChild" or method == "WaitForChild" then
                if self == CoreGui then
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

    local old_index
    old_index = hookmm(game, "__index", newc(function(self, key)
        if isGameCaller() and key == "Funny" then return nil end
        return old_index(self, key)
    end))
end

-- Player:Kick 무력화
if hookfn then
    local ok, kickMethod = orig_pcall(function() return LocalPlayer.Kick end)
    if ok and orig_type(kickMethod) == "function" then
        local old_kick
        old_kick = hookfn(kickMethod, newc(function(self, ...)
            if isGameCaller() and self == LocalPlayer then return nil end
            return old_kick(self, ...)
        end))
    end
end

-- require 후킹
if hookfn and require then
    local old_require
    old_require = hookfn(require, newc(function(...)
        local target = ...
        local res = old_require(...)
        if orig_typeof(target) == "Instance" then
            if target.Name == "ItemLibrary" or target.Name == "EntityLookupParams" then
                if orig_type(res) == "table" and orig_type(orig_rawget(res, "Items")) == "table" then
                    orig_pcall(orig_setmetatable, res.Items, nil)
                end
            end
        end
        return res
    end))
end

-- 모듈 프리로드 디퓨저
task.spawn(function()
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

-- 유틸리티 함수들 (UE 패치용)
local _randomCache = {}
local function getRandomName(key)
    if not _randomCache[key] then
        local chars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ"
        local result = ""
        for i = 1, 16 do
            local idx = math.random(1, #chars)
            result = result .. string.sub(chars, idx, idx)
        end
        _randomCache[key] = result
    end
    return _randomCache[key]
end

local _actionName = getRandomName("action")

-- 후크 등록 함수
local function registerHook(fn)
    if orig_type(fn) == "function" then
        hookedFunctions[fn] = true
    end
end

----------------------------------------------------------------
-- PHASE 2: UE 스크립트 런타임 패치 & 로드
----------------------------------------------------------------
-- 패치 포인트를 위한 전역 주입
ENV.__UE_GET_NAME = getRandomName
ENV.__UE_ACTION_NAME = _actionName
ENV.__UE_REGISTER_HOOK = registerHook
ENV.__UE_BYPASS = { installed = true, version = 3 }

-- 더블로드 방지 (원래 UE_LOADED 대신 랜덤 키 사용)
local _ue_key = "__ue_" .. tostring(math.random(100000, 999999))
if orig_rawget(_G, _ue_key) then return end
orig_rawset(_G, _ue_key, true)

-- 기존 UE_LOADED 체크를 우회하기 위해 false로 설정
ENV.UE_LOADED = nil

print("[UE Bypass v3] 안티치트 우회 모듈 로드 완료")
print("[UE Bypass v3] 환경 은폐: O")
print("[UE Bypass v3] shared.r 무력화: O")
print("[UE Bypass v3] debug.info 후킹: O")
print("[UE Bypass v3] getgc 방어: O")
print("[UE Bypass v3] 커넥션 수 스푸핑: O")
print("[UE Bypass v3] 킥/밴 차단: O")
print("[UE Bypass v3] CoreGui 인스턴스 은폐: O")

----------------------------------------------------------------
-- PHASE 3: 패치된 UE 스크립트 로드
-- 원본 UE 소스를 가져와서 취약한 부분을 string.gsub로 패치 후 실행
----------------------------------------------------------------

-- UE 스크립트 소스 URL (원본과 동일)
local ue_source_url = "여기에_UE_스크립트_URL_또는_pastebin_raw_URL"

--[[
    아래 두 가지 방법 중 하나를 선택하세요:

    방법 A: URL에서 로드 + 패치
        local source = game:HttpGet(ue_source_url)
        -- 아래 패치 적용 후 loadstring(source)()

    방법 B: 로컬 파일에서 로드 + 패치 (권장)
        local source = readfile("UnnamedEnhancements.lua")
        -- 아래 패치 적용 후 loadstring(source)()

    방법 C: 이 스크립트 아래에 UE 소스를 직접 붙여넣기
        -- 아래의 PATCHED_UE_SOURCE 부분에 직접 붙여넣기
]]

local function patchAndLoad(source)
    -- 패치 1: 더블로드 방지 플래그
    source = source:gsub(
        'if getgenv%(%)%.UE_LOADED then%s+return%s+end',
        '-- [PATCHED] double-load guard moved to loader'
    )

    -- 패치 2: drawingDirectory 이름 랜덤화
    source = source:gsub(
        'Name = "drawingDirectory"',
        'Name = "' .. getRandomName("drawGui") .. '"'
    )

    -- 패치 3: UE_BlockInput 액션 이름 랜덤화
    source = source:gsub(
        '"UE_BlockInput"',
        '"' .. _actionName .. '"'
    )

    -- 패치 4: ThemeManager/SaveManager 글로벌 노출 제거
    source = source:gsub(
        'getgenv%(%)%.ThemeManager = ThemeManager',
        '-- [PATCHED] ThemeManager global removed'
    )
    source = source:gsub(
        'getgenv%(%)%.SaveManager = SaveManager',
        '-- [PATCHED] SaveManager global removed'
    )

    -- 패치 5: UE_LOADED 플래그 설정 제거 (있다면)
    source = source:gsub(
        'getgenv%(%)%.UE_LOADED = true',
        '-- [PATCHED] UE_LOADED flag removed'
    )

    -- 실행
    local fn, err = loadstring(source)
    if not fn then
        warn("[UE Loader] 스크립트 컴파일 실패: " .. tostring(err))
        return
    end
    fn()

    print("[UE Loader] 패치된 UE 스크립트 로드 완료!")
end

-- ================================================================
-- 아래에서 로드 방법을 선택하세요
-- ================================================================

-- 방법 A: 파일에서 로드 (executor에 파일을 넣어둔 경우)
if isfile and isfile("UnnamedEnhancements.lua") then
    local source = readfile("UnnamedEnhancements.lua")
    patchAndLoad(source)
    return
end

-- 방법 B: URL에서 로드 (pastebin 등에 올린 경우)
-- 아래 URL을 자신의 UE 소스 URL로 변경하세요
--[[
local source = game:HttpGet("https://pastebin.com/raw/YOUR_PASTE_ID")
patchAndLoad(source)
return
]]

-- 방법 C: 직접 실행 (이 파일 아래에 UE 소스를 붙여넣은 경우)
-- patchAndLoad 대신 직접 수정된 UE를 아래에 붙여넣으세요
warn("[UE Loader] UE 소스를 찾을 수 없습니다!")
warn("[UE Loader] 방법 A: UnnamedEnhancements.lua 파일을 executor 폴더에 넣기")
warn("[UE Loader] 방법 B: 스크립트 내 URL을 설정하기")
warn("[UE Loader] 방법 C: 이 스크립트 아래에 UE 소스 붙여넣기")
