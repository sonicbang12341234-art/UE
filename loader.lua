--[[
    Unnamed Enhancements — Universal Loader v4
    Rivals 전용 로더 (Volcano / 모든 실행자 호환)

    사용법:
    loadstring(game:HttpGet("https://raw.githubusercontent.com/sonicbang12341234-art/UE/main/loader.lua"))()
]]

local REPO = "https://raw.githubusercontent.com/sonicbang12341234-art/UE/main/"

print("[UE Loader] ===== Unnamed Enhancements v4 =====")

-- 실행자 확인
pcall(function()
    local name, ver = "Unknown", "?"
    if identifyexecutor then
        name, ver = identifyexecutor()
    elseif getexecutorname then
        name = getexecutorname()
    elseif syn then
        name = "Synapse"
    elseif KRNL_LOADED then
        name = "KRNL"
    elseif fluxus then
        name = "Fluxus"
    elseif Volcano then
        name = "Volcano"
    elseif Solara then
        name = "Solara"
    elseif Delta then
        name = "Delta"
    end
    print("[UE Loader] 실행자: " .. tostring(name) .. " " .. tostring(ver))
end)

-- HttpGet 호환 래퍼
local function httpGet(url)
    local result
    -- 방법 1: game:HttpGet (대부분의 실행자)
    local ok1, res1 = pcall(function()
        return game:HttpGet(url, true) -- true = 캐시 우회
    end)
    if ok1 and res1 and #res1 > 0 then return res1 end

    -- 방법 2: game:HttpGet (캐시 파라미터 없이)
    local ok2, res2 = pcall(function()
        return game:HttpGet(url)
    end)
    if ok2 and res2 and #res2 > 0 then return res2 end

    -- 방법 3: request/http_request (일부 실행자)
    local reqFn = request or http_request or httprequest or syn_request
    if reqFn then
        local ok3, res3 = pcall(function()
            local response = reqFn({
                Url = url,
                Method = "GET"
            })
            return response.Body
        end)
        if ok3 and res3 and #res3 > 0 then return res3 end
    end

    -- 방법 4: HttpService (제한적)
    local ok4, res4 = pcall(function()
        local HttpService = game:GetService("HttpService")
        return HttpService:GetAsync(url)
    end)
    if ok4 and res4 and #res4 > 0 then return res4 end

    return nil
end

-- 1단계: 안티치트 우회 모듈 로드
print("[UE Loader] [1/2] 안티치트 우회 모듈 로드 중...")
local bypassSource = httpGet(REPO .. "bypass.lua")
if not bypassSource then
    warn("[UE Loader] bypass.lua 다운로드 실패!")
    warn("[UE Loader] 인터넷 연결 또는 GitHub URL을 확인하세요")
    return
end

local bypassFn, bypassErr = loadstring(bypassSource)
if not bypassFn then
    warn("[UE Loader] bypass.lua 컴파일 실패: " .. tostring(bypassErr))
    return
end

local bypassOk, bypassResult = pcall(bypassFn)
if not bypassOk then
    warn("[UE Loader] bypass.lua 실행 오류: " .. tostring(bypassResult))
    warn("[UE Loader] 패처로 계속 시도합니다...")
end

local bypassInstalled = bypassOk and type(bypassResult) == "table" and bypassResult.installed
if bypassInstalled then
    print("[UE Loader] 안티치트 우회 설치 완료!")
else
    warn("[UE Loader] 우회 일부 기능 제한 — 계속 진행합니다")
end

-- 2단계: 패처 로드 (main.lua를 내부적으로 로드+패치)
print("[UE Loader] [2/2] 패처 + 메인 스크립트 로드 중...")
local patcherSource = httpGet(REPO .. "patcher.lua")
if not patcherSource then
    warn("[UE Loader] patcher.lua 다운로드 실패!")
    -- 폴백: main.lua를 직접 로드 (패치 없이)
    print("[UE Loader] 폴백: main.lua 직접 로드 시도...")
    local mainSource = httpGet(REPO .. "main.lua")
    if mainSource then
        local fn, err = loadstring(mainSource)
        if fn then
            pcall(fn)
        else
            warn("[UE Loader] main.lua 컴파일 실패: " .. tostring(err))
        end
    else
        warn("[UE Loader] main.lua 다운로드도 실패!")
    end
    return
end

local patcherFn, patcherErr = loadstring(patcherSource)
if not patcherFn then
    warn("[UE Loader] patcher.lua 컴파일 실패: " .. tostring(patcherErr))
    return
end

local patcherOk, patcherResult = pcall(patcherFn)
if not patcherOk then
    warn("[UE Loader] patcher.lua 실행 오류: " .. tostring(patcherResult))
    -- 폴백: main.lua 직접 로드
    print("[UE Loader] 폴백: main.lua 직접 로드 시도...")
    local mainSource = httpGet(REPO .. "main.lua")
    if mainSource then
        local fn, err = loadstring(mainSource)
        if fn then pcall(fn) end
    end
end

print("[UE Loader] ===== 로드 완료 =====")
