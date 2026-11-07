--[[
    UE Runtime Patcher v4 — Universal Executor Compatible
    =====================================================
    bypass.lua가 먼저 로드된 상태에서 실행됩니다.
    main.lua 소스를 GitHub에서 가져와 취약한 부분을 패치 후 실행합니다.

    주요 패치:
    1. 더블로드 방지 플래그 제거
    2. drawingDirectory 이름 랜덤화
    3. UE_BlockInput 액션 이름 랜덤화
    4. ThemeManager/SaveManager 글로벌 노출 제거
    5. UE_LOADED 플래그 설정 제거
]]

--------------------------------------------------------------------------------
-- 유틸리티
--------------------------------------------------------------------------------
local ENV = (getgenv and getgenv()) or _G

-- bypass.lua에서 제공하는 유틸 사용
local function getRandomName(key)
    if ENV.__UE_GET_NAME then
        return ENV.__UE_GET_NAME(key)
    end
    -- 폴백: 직접 생성
    local chars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ"
    local result = ""
    for i = 1, 16 do
        local idx = math.random(1, #chars)
        result = result .. string.sub(chars, idx, idx)
    end
    return result
end

local _actionName = ENV.__UE_ACTION_NAME or getRandomName("action")

-- 후크 등록 함수
local registerHook = ENV.__UE_REGISTER_HOOK or function() end

-- 더블로드 방지 (랜덤 키 사용)
local _ue_key = "__ue_" .. tostring(math.random(100000, 999999))
if rawget(_G, _ue_key) then return end
rawset(_G, _ue_key, true)

-- 기존 UE_LOADED 체크를 우회하기 위해 nil로 설정
ENV.UE_LOADED = nil

--------------------------------------------------------------------------------
-- 패치 함수
--------------------------------------------------------------------------------
local function patchAndLoad(source)
    if not source or #source < 100 then
        warn("[UE Patcher] 소스가 비어있거나 너무 짧습니다")
        return false
    end

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

    -- 패치 5: UE_LOADED 플래그 설정 제거
    source = source:gsub(
        'getgenv%(%)%.UE_LOADED = true',
        '-- [PATCHED] UE_LOADED flag removed'
    )

    -- 컴파일 및 실행
    local fn, err = loadstring(source)
    if not fn then
        warn("[UE Patcher] 스크립트 컴파일 실패: " .. tostring(err))
        return false
    end

    local ok, runErr = pcall(fn)
    if not ok then
        warn("[UE Patcher] 스크립트 실행 오류: " .. tostring(runErr))
        return false
    end

    print("[UE Patcher] 패치된 UE 스크립트 로드 완료!")
    return true
end

--------------------------------------------------------------------------------
-- main.lua 로드
--------------------------------------------------------------------------------
local REPO = "https://raw.githubusercontent.com/sonicbang12341234-art/UE/main/"

-- 방법 1: GitHub에서 로드 (우선)
local source = nil
local ok, result = pcall(function()
    return game:HttpGet(REPO .. "main.lua")
end)

if ok and result and #result > 100 then
    source = result
    print("[UE Patcher] GitHub에서 main.lua 로드 성공 (" .. #result .. " bytes)")
end

-- 방법 2: 로컬 파일 폴백
if not source then
    pcall(function()
        if isfile and isfile("UnnamedEnhancements.lua") then
            source = readfile("UnnamedEnhancements.lua")
            print("[UE Patcher] 로컬 파일에서 로드: UnnamedEnhancements.lua")
        end
    end)
end

if not source then
    pcall(function()
        if isfile and isfile("main.lua") then
            source = readfile("main.lua")
            print("[UE Patcher] 로컬 파일에서 로드: main.lua")
        end
    end)
end

-- 실행
if source then
    patchAndLoad(source)
else
    warn("[UE Patcher] main.lua를 찾을 수 없습니다!")
    warn("[UE Patcher] GitHub URL 확인 또는 로컬 파일 배치 필요")
end
