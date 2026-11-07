--[[
    Unnamed Enhancements - Loader
    Rivals 전용 로더

    사용법:
    loadstring(game:HttpGet("https://raw.githubusercontent.com/YOUR_USERNAME/UE/main/loader.lua"))()

    YOUR_USERNAME을 본인 GitHub 계정으로 변경하세요.
]]

local REPO = "https://raw.githubusercontent.com/YOUR_USERNAME/UE/main/"

-- 1단계: 안티치트 우회 모듈 로드
local bypassResult = loadstring(game:HttpGet(REPO .. "bypass.lua"))()

if bypassResult and bypassResult.installed then
    -- 2단계: 런타임 패처 로드
    loadstring(game:HttpGet(REPO .. "patcher.lua"))()

    -- 3단계: UE 메인 스크립트 로드
    loadstring(game:HttpGet(REPO .. "main.lua"))()
else
    warn("[UE] Bypass failed to install")
end
