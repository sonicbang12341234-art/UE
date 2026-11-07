--[[
    Unnamed Enhancements — Complete Source
    Roblox LuaU Cheat Script for Rivals

    Components:
    1. Custom Drawing Library (Frame-based: Line, Square, Text, Circle, Image)
    2. ESP System (Box, Fill, Name, Weapon, Distance, Skeleton, Healthbar)
    3. Gradient System (ColorSequence-based animated gradients)
    4. Visual Effects (Bloom, ColorCorrection, Atmosphere, SunRays)
    5. Crosshair & HUD System
    6. Beam Tracer System
    7. Combat System (Aimbot, Triggerbot, Anti-Aim, No Spread, Silent Aim)
    8. ThemeManager with 13 Built-in Themes
    9. SaveManager for Config Persistence
    10. Character Customization & Effects
    11. Window Toggle (RightControl/Insert)
]]

--------------------------------------------------------------------------------
-- LinoriaLib Loading
--------------------------------------------------------------------------------
local Library = loadstring(game:HttpGet('https://raw.githubusercontent.com/violin-suzutsuki/LinoriaLib/refs/heads/main/Library.lua'))()
local SaveManager = loadstring(game:HttpGet('https://raw.githubusercontent.com/violin-suzutsuki/LinoriaLib/refs/heads/main/addons/SaveManager.lua'))()
local ThemeManager = loadstring(game:HttpGet('https://raw.githubusercontent.com/violin-suzutsuki/LinoriaLib/refs/heads/main/addons/ThemeManager.lua'))()

--------------------------------------------------------------------------------
-- Services
--------------------------------------------------------------------------------
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ContextActionService = game:GetService("ContextActionService")
local TweenService = game:GetService("TweenService")
local TextService = game:GetService("TextService")
local Lighting = game:GetService("Lighting")
local Teams = game:GetService("Teams")
local HttpService = game:GetService("HttpService")
local GuiService = game:GetService("GuiService")
local TextChatService = game:GetService("TextChatService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LocalPlayer = Players.LocalPlayer
local Camera = workspace.CurrentCamera

--------------------------------------------------------------------------------
-- Executor Compatibility Shims
--------------------------------------------------------------------------------
local cloneref = cloneref or function(inst) return inst end
local gethui = gethui or function()
    return (syn and syn.protect_gui and game:GetService("CoreGui")) or game:GetService("CoreGui")
end
local getsynasset = getcustomasset or getsynasset or function() return "" end
local protect_gui = (syn and syn.protect_gui) or function() end

if not getgenv then
    getgenv = function() return _G end
end

--------------------------------------------------------------------------------
-- Guard: prevent double-load
--------------------------------------------------------------------------------
if getgenv().UE_LOADED then
    return
end

--------------------------------------------------------------------------------
-- Global Toggle/Option refs (populated by LinoriaLib)
--------------------------------------------------------------------------------
if not getgenv().Toggles then
    getgenv().Toggles = {}
end
if not getgenv().Options then
    getgenv().Options = {}
end
local Toggles = getgenv().Toggles
local Options = getgenv().Options

--------------------------------------------------------------------------------
-- State object (shared across all systems)
--------------------------------------------------------------------------------
local State = {
    lua = {
        listen_for_command = {},
    },
    events = {
        gradient_option_changed   = Instance.new("BindableEvent"),
        esp_color_changed         = Instance.new("BindableEvent"),
        esp_fill_changed          = Instance.new("BindableEvent"),
        esp_effects_changed       = Instance.new("BindableEvent"),
        esp_effects_color_changed = Instance.new("BindableEvent"),
    },
    characters = {},
    customization = {
        self = {
            _data = {},
            new = function(self, tag)
                return {
                    create = function(self2, char, val, kind) end,
                    destroy = function(self2, kind) end,
                    update = function(self2, kind) end,
                }
            end,
            change = function(self, char, fn) end,
            restore = function(self, char) end,
            get = function(self, char) return nil end,
        },
    },
    effects = {
        self_effects = {
            new = function(tag)
                return {
                    create = function(self, char, val, kind) end,
                    destroy = function(self, kind) end,
                    update = function(self, kind) end,
                }
            end,
        },
    },
    gradients = {
        healthbar = {},
        fill      = {},
        box       = {},
        name      = {},
        weapon    = {},
        distance  = {},
        skeleton  = {},
    },
    running = {},
    drawings = {
        silent = {},
        aimbot = {},
    },
    manipulation = {
        active = false,
        targetPosition = nil,
    },
}

--------------------------------------------------------------------------------
-- Lighting Effect Instances
--------------------------------------------------------------------------------
local BloomEffect = Instance.new("BloomEffect")
BloomEffect.Parent = Lighting
BloomEffect.Enabled = false

local BloomDefaults = {
    Enabled = BloomEffect.Enabled,
    Size = BloomEffect.Size,
    Intensity = BloomEffect.Intensity,
    Threshold = BloomEffect.Threshold,
}

local ColorCorrectionEffect = Instance.new("ColorCorrectionEffect")
ColorCorrectionEffect.Parent = Lighting
ColorCorrectionEffect.Enabled = false

local AtmosphereEffect = Instance.new("Atmosphere")

local SunRaysEffect = Instance.new("SunRaysEffect")
SunRaysEffect.Parent = Lighting
SunRaysEffect.Enabled = false

local SunRaysDefaults = {
    Enabled = SunRaysEffect.Enabled,
    Spread = SunRaysEffect.Spread,
    Intensity = SunRaysEffect.Intensity,
}

--------------------------------------------------------------------------------
-- Utility: Proxy pattern for reactive state
--------------------------------------------------------------------------------
local function make_proxy(initial_value)
    local storage = { [1] = initial_value }
    return { [2] = 1, [3] = storage }
end

local function proxy_get(proxy)
    return proxy[3][proxy[2]]
end

local function proxy_set(proxy, value)
    proxy[3][proxy[2]] = value
end

local proxy_outline_color = make_proxy("OutlineColor")
local proxy_visibility = make_proxy(false)
local proxy_target = make_proxy(nil)
local proxy_healthbar_color = make_proxy(ColorSequence.new(Color3.new(0, 1, 0)))
local proxy_esp_enabled = make_proxy(false)

--------------------------------------------------------------------------------
-- Math shorthands
--------------------------------------------------------------------------------
local V2 = Vector2.new
local V3 = Vector3.new
local C3 = Color3.new
local UD = UDim.new
local UD2 = UDim2.new
local math_max = math.max
local math_min = math.min
local math_abs = math.abs
local math_floor = math.floor
local math_atan2 = math.atan2
local math_clamp = math.clamp
local math_lerp = math.lerp or function(a, b, t) return a + (b - a) * t end
local math_huge = math.huge
local math_pi = math.pi

--------------------------------------------------------------------------------
-- Instance creation helper
--------------------------------------------------------------------------------
local function Create(className, properties, children)
    local inst = Instance.new(className)
    if properties then
        for key, value in pairs(properties) do
            inst[key] = value
        end
    end
    if children then
        for _, child in ipairs(children) do
            child.Parent = inst
        end
    end
    return inst
end


--------------------------------------------------------------------------------
-- Custom Drawing Library
--
-- Frame-based drawing system that uses ScreenGui + Frames/TextLabels
-- instead of Roblox's Drawing API. Each drawing object wraps a GUI element
-- with UIStroke/UIGradient for styling.
--------------------------------------------------------------------------------
local Drawing = { Fonts = { UI = 0, System = 1, Plex = 2, Monospace = 3 } }

do
    -- Font mapping
    local FontMap = {
        [Drawing.Fonts.UI] = Font.new("rbxasset://fonts/families/Arial.json", Enum.FontWeight.Regular, Enum.FontStyle.Normal),
        [Drawing.Fonts.System] = Font.new("rbxasset://fonts/families/HighwayGothic.json", Enum.FontWeight.Regular, Enum.FontStyle.Normal),
        [Drawing.Fonts.Plex] = Font.new("rbxasset://fonts/families/Roboto.json", Enum.FontWeight.Regular, Enum.FontStyle.Normal),
        [Drawing.Fonts.Monospace] = Font.new("rbxasset://fonts/families/Ubuntu.json", Enum.FontWeight.Regular, Enum.FontStyle.Normal),
    }

    -- Precache fonts
    for _, font in FontMap do
        TextService:GetTextBoundsAsync(Create("GetTextBoundsParams", {
            Text = "\\",
            Size = 12,
            Font = font,
            Width = math_huge,
        }))
    end

    -- Root ScreenGui
    local DrawingGui = Create("ScreenGui", {
        DisplayOrder = 15,
        IgnoreGuiInset = true,
        Name = "drawingDirectory",
        Parent = cloneref(game:GetService("CoreGui")),
        ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
    })

    -- Helper: position/rotate a frame to represent a line from point A to B
    local function UpdateLineTransform(frame, from, to, thickness)
        local mid = (from + to) / 2
        local delta = to - from
        frame.Position = UD2.new(0, mid.X, 0, mid.Y)
        frame.Rotation = math_atan2(delta.Y, delta.X) * 180 / math_pi
        frame.Size = UD2.new(0, delta.Magnitude, 0, thickness)
    end

    local nextId = 0
    local allObjects = {}
    local ClassRegistry = {}

    ---------------------------------------------------------------------------
    -- LINE
    ---------------------------------------------------------------------------
    do
        local LineMT = {}

        function LineMT.new()
            nextId = nextId + 1
            local id = nextId
            local obj = setmetatable({
                _id = id,
                __OBJECT_EXISTS = true,
                _properties = {
                    Color = C3(),
                    From = V2(),
                    Thickness = 1,
                    To = V2(),
                    Transparency = 1,
                    Visible = false,
                    ZIndex = 0,
                },
                _frame = Create("Frame", {
                    Name = tostring(id),
                    AnchorPoint = V2(0.5, 0.5),
                    BackgroundColor3 = C3(),
                    BorderSizePixel = 0,
                    Parent = DrawingGui,
                    Position = UD2.new(),
                    Size = UD2.new(),
                    Visible = false,
                    ZIndex = 0,
                }),
            }, LineMT)
            allObjects[id] = obj
            return obj
        end

        function LineMT:__index(key)
            local val = self._properties[key]
            if val ~= nil then return val end
            return LineMT[key]
        end

        function LineMT:__newindex(key, value)
            if not self.__OBJECT_EXISTS then return end
            local props = self._properties
            if props[key] == nil or props[key] == value or typeof(props[key]) ~= typeof(value) then
                return
            end
            props[key] = value

            if key == "Color" then
                self._frame.BackgroundColor3 = value
            elseif key == "From" or key == "To" then
                self:_updatePosition()
            elseif key == "Thickness" then
                self._frame.Size = UD2.new(0, self._frame.AbsoluteSize.X, 0, math_max(value, 1))
            elseif key == "Transparency" then
                self._frame.BackgroundTransparency = math_clamp(1 - value, 0, 1)
            elseif key == "Visible" then
                self._frame.Visible = value
            elseif key == "ZIndex" then
                self._frame.ZIndex = value
            end
        end

        function LineMT:__iter() return next, self._properties end
        function LineMT:__tostring() return "Drawing" end

        function LineMT:Destroy()
            allObjects[self._id] = nil
            self.__OBJECT_EXISTS = false
            self._frame:Destroy()
        end

        function LineMT:_updatePosition()
            local p = self._properties
            UpdateLineTransform(self._frame, p.From, p.To, p.Thickness)
        end

        LineMT.Remove = LineMT.Destroy
        ClassRegistry.Line = LineMT
    end

    ---------------------------------------------------------------------------
    -- CIRCLE
    ---------------------------------------------------------------------------
    do
        local CircleMT = {}

        function CircleMT.new()
            nextId = nextId + 1
            local id = nextId
            local frame = Create("Frame", {
                Name = tostring(id),
                AnchorPoint = V2(0.5, 0.5),
                BackgroundColor3 = C3(),
                BackgroundTransparency = 1,
                BorderSizePixel = 0,
                Parent = DrawingGui,
                Position = UD2.new(),
                Size = UD2.new(),
                Visible = false,
                ZIndex = 0,
            }, {
                Create("UICorner", { Name = "_corner", CornerRadius = UD(1, 0) }),
                Create("UIStroke", { Name = "_stroke", Color = C3(), Thickness = 1 }),
            })

            local obj = setmetatable({
                _id = id,
                __OBJECT_EXISTS = true,
                _properties = {
                    Color = C3(),
                    Filled = false,
                    NumSides = 0,
                    Position = V2(),
                    Radius = 0,
                    Thickness = 1,
                    Transparency = 1,
                    Visible = false,
                    ZIndex = 0,
                },
                _frame = frame,
            }, CircleMT)
            allObjects[id] = obj
            return obj
        end

        function CircleMT:__index(key)
            local val = self._properties[key]
            if val ~= nil then return val end
            return CircleMT[key]
        end

        function CircleMT:__newindex(key, value)
            if not self.__OBJECT_EXISTS then return end
            local props = self._properties
            if props[key] == nil or props[key] == value or typeof(props[key]) ~= typeof(value) then return end
            props[key] = value

            if key == "Color" then
                self._frame.BackgroundColor3 = value
                self._frame._stroke.Color = value
            elseif key == "Filled" then
                self._frame.BackgroundTransparency = value and (1 - props.Transparency) or 1
            elseif key == "Position" then
                self._frame.Position = UD2.new(0, value.X, 0, value.Y)
            elseif key == "Radius" then
                self:_updateRadius()
            elseif key == "Thickness" then
                self._frame._stroke.Thickness = math_max(value, 1)
                self:_updateRadius()
            elseif key == "Transparency" then
                self._frame._stroke.Transparency = 1 - value
                if props.Filled then
                    self._frame.BackgroundTransparency = 1 - value
                end
            elseif key == "Visible" then
                self._frame.Visible = value
            elseif key == "ZIndex" then
                self._frame.ZIndex = value
            end
        end

        function CircleMT:__iter() return next, self._properties end
        function CircleMT:__tostring() return "Drawing" end

        function CircleMT:Destroy()
            allObjects[self._id] = nil
            self.__OBJECT_EXISTS = false
            self._frame:Destroy()
        end

        function CircleMT:_updateRadius()
            local p = self._properties
            local diameter = (p.Radius * 2) - (p.Thickness * 2)
            self._frame.Size = UD2.new(0, diameter, 0, diameter)
        end

        CircleMT.Remove = CircleMT.Destroy
        ClassRegistry.Circle = CircleMT
    end

    ---------------------------------------------------------------------------
    -- TEXT
    ---------------------------------------------------------------------------
    do
        local TextMT = {}

        function TextMT.new()
            nextId = nextId + 1
            local id = nextId
            local frame = Create("TextLabel", {
                Name = tostring(id),
                BackgroundTransparency = 1,
                FontFace = FontMap[0],
                Parent = DrawingGui,
                Position = UD2.new(),
                Size = UD2.new(),
                Text = "",
                TextColor3 = C3(),
                TextSize = 12,
                TextXAlignment = Enum.TextXAlignment.Left,
                TextYAlignment = Enum.TextYAlignment.Top,
                Visible = false,
                ZIndex = 0,
            }, {
                Create("UIStroke", {
                    Name = "_stroke",
                    Color = C3(),
                    Enabled = false,
                    Thickness = 1,
                    LineJoinMode = Enum.LineJoinMode.Miter,
                }),
            })

            local obj = setmetatable({
                _id = id,
                __OBJECT_EXISTS = true,
                _properties = {
                    Center = false,
                    RichText = false,
                    Color = C3(),
                    FontFace = FontMap[0],
                    Outline = false,
                    OutlineColor = C3(),
                    Position = V2(),
                    Size = 12,
                    TextSize = 12,
                    Text = "",
                    TextBounds = V2(),
                    Transparency = 1,
                    Visible = false,
                    ZIndex = 0,
                },
                _frame = frame,
            }, TextMT)
            allObjects[id] = obj
            return obj
        end

        function TextMT:__index(key)
            local val = self._properties[key]
            if val ~= nil then return val end
            return TextMT[key]
        end

        function TextMT:__newindex(key, value)
            if not self.__OBJECT_EXISTS then return end
            local props = self._properties
            if key == "TextBounds" or props[key] == nil or props[key] == value or typeof(props[key]) ~= typeof(value) then
                return
            end
            props[key] = value

            if key == "Position" then
                self._frame.Position = UD2.new(0, value.X, 0, value.Y)
            elseif key == "Text" then
                self._frame.Text = value
                self:_updateTextBounds()
            elseif key == "Transparency" then
                self._frame.TextTransparency = 1 - value
                self._frame._stroke.Transparency = 1 - value
            elseif key == "Size" or key == "TextSize" then
                self._frame.TextSize = value
                self:_updateTextBounds()
            elseif key == "Visible" then
                self._frame.Visible = value
            elseif key == "Center" then
                self._frame.TextXAlignment = value and Enum.TextXAlignment.Center or Enum.TextXAlignment.Left
            elseif key == "Color" then
                self._frame.TextColor3 = value
            elseif key == "Font" then
                local mapped = FontMap[value]
                self._frame.FontFace = mapped
                props.FontFace = mapped
                self:_updateTextBounds()
            elseif key == "Outline" then
                self._frame._stroke.Enabled = value
            elseif key == "OutlineColor" then
                self._frame._stroke.Color = value
            elseif key == "ZIndex" then
                self._frame.ZIndex = value
            elseif key == "FontFace" then
                self._frame.FontFace = value
                self:_updateTextBounds()
            elseif key == "RichText" then
                self._frame.RichText = value
            end
        end

        function TextMT:__iter() return next, self._properties end
        function TextMT:__tostring() return "Drawing" end

        function TextMT:Destroy()
            allObjects[self._id] = nil
            self.__OBJECT_EXISTS = false
            self._frame:Destroy()
        end

        function TextMT:_updateTextBounds()
            local p = self._properties
            p.TextBounds = TextService:GetTextBoundsAsync(Create("GetTextBoundsParams", {
                Text = p.Text,
                Size = p.Size,
                Font = p.FontFace,
                Width = math_huge,
            }))
        end

        TextMT.Remove = TextMT.Destroy
        ClassRegistry.Text = TextMT
    end

    ---------------------------------------------------------------------------
    -- SQUARE
    ---------------------------------------------------------------------------
    do
        local SquareMT = {}

        function SquareMT.new()
            nextId = nextId + 1
            local id = nextId
            local frame = Create("Frame", {
                BackgroundColor3 = C3(),
                BackgroundTransparency = 1,
                BorderSizePixel = 0,
                Parent = DrawingGui,
                Position = UD2.new(),
                Size = UD2.new(),
                Visible = false,
                ZIndex = 0,
            }, {
                Create("UIStroke", {
                    Name = "_stroke",
                    Color = C3(),
                    Thickness = 1,
                    LineJoinMode = Enum.LineJoinMode.Miter,
                }),
            })

            local obj = setmetatable({
                _id = id,
                __OBJECT_EXISTS = true,
                _properties = {
                    Color = C3(),
                    Filled = false,
                    Position = V2(),
                    Size = V2(),
                    Thickness = 1,
                    Transparency = 1,
                    Visible = false,
                    ZIndex = 0,
                },
                _frame = frame,
            }, SquareMT)
            allObjects[id] = obj
            return obj
        end

        function SquareMT:__index(key)
            local val = self._properties[key]
            if val ~= nil then return val end
            return SquareMT[key]
        end

        function SquareMT:__newindex(key, value)
            if not self.__OBJECT_EXISTS then return end
            local props = self._properties
            if props[key] == nil or props[key] == value or typeof(props[key]) ~= typeof(value) then return end
            props[key] = value

            if key == "Position" or key == "Size" then
                self:_updateScale()
            elseif key == "Color" then
                self._frame.BackgroundColor3 = value
                self._frame._stroke.Color = value
            elseif key == "Filled" then
                self._frame.BackgroundTransparency = value and (1 - props.Transparency) or 1
            elseif key == "Thickness" then
                self._frame._stroke.Thickness = value
                self:_updateScale()
            elseif key == "Transparency" then
                self._frame._stroke.Transparency = 1 - value
                if props.Filled then
                    self._frame.BackgroundTransparency = 1 - value
                end
            elseif key == "Visible" then
                self._frame.Visible = value
            elseif key == "ZIndex" then
                self._frame.ZIndex = value
            end
        end

        function SquareMT:__iter() return next, self._properties end
        function SquareMT:__tostring() return "Drawing" end

        function SquareMT:Destroy()
            allObjects[self._id] = nil
            self.__OBJECT_EXISTS = false
            self._frame:Destroy()
        end

        function SquareMT:_updateScale()
            local p = self._properties
            self._frame.Position = UD2.new(0, p.Position.X + p.Thickness, 0, p.Position.Y + p.Thickness)
            local t = p.Thickness
            self._frame.Size = UD2.new(0, p.Size.X - t * 2, 0, p.Size.Y - t * 2)
        end

        SquareMT.Remove = SquareMT.Destroy
        ClassRegistry.Square = SquareMT
    end

    ---------------------------------------------------------------------------
    -- IMAGE
    ---------------------------------------------------------------------------
    do
        local ImageMT = {}

        function ImageMT.new()
            nextId = nextId + 1
            local id = nextId
            local frame = Create("ImageLabel", {
                BackgroundTransparency = 1,
                BorderSizePixel = 0,
                Image = "",
                ImageColor3 = C3(1, 1, 1),
                Parent = DrawingGui,
                Position = UD2.new(),
                Size = UD2.new(),
                Visible = false,
                ZIndex = 0,
            }, {
                Create("UICorner", { Name = "_corner", CornerRadius = UD() }),
            })

            local obj = setmetatable({
                _id = id,
                _imageId = 0,
                __OBJECT_EXISTS = true,
                _properties = {
                    Color = C3(1, 1, 1),
                    Data = "",
                    Position = V2(),
                    Rounding = 0,
                    Size = V2(),
                    Transparency = 1,
                    Uri = "",
                    Visible = false,
                    ZIndex = 0,
                },
                _frame = frame,
            }, ImageMT)
            allObjects[id] = obj
            return obj
        end

        function ImageMT:__index(key)
            assert(key ~= "Data", string.format("Attempt to read writeonly property '%s'", key))
            if key == "Loaded" then
                return self._frame.IsLoaded
            end
            local val = self._properties[key]
            if val ~= nil then return val end
            return ImageMT[key]
        end

        function ImageMT:__newindex(key, value)
            if not self.__OBJECT_EXISTS then return end
            local props = self._properties
            if props[key] == nil or props[key] == value or typeof(props[key]) ~= typeof(value) then return end
            props[key] = value

            if key == "Color" then
                self._frame.ImageColor3 = value
            elseif key == "Data" then
                self:_newImage(value)
            elseif key == "Position" then
                self._frame.Position = UD2.new(0, value.X, 0, value.Y)
            elseif key == "Rounding" then
                self._frame._corner.CornerRadius = UD(0, value)
            elseif key == "Size" then
                self._frame.Size = UD2.new(0, value.X, 0, value.Y)
            elseif key == "Transparency" then
                self._frame.ImageTransparency = 1 - value
            elseif key == "Uri" then
                self:_newImage(value, true)
            elseif key == "Visible" then
                self._frame.Visible = value
            elseif key == "ZIndex" then
                self._frame.ZIndex = value
            end
        end

        function ImageMT:__iter() return next, self._properties end
        function ImageMT:__tostring() return "Drawing" end

        function ImageMT:Destroy()
            allObjects[self._id] = nil
            self.__OBJECT_EXISTS = false
            self._frame:Destroy()
        end

        function ImageMT:_newImage(data, isUri)
            task.spawn(function()
                self._imageId = self._imageId + 1
                local fileName = string.format("%s-%s.png", self._id, self._imageId)
                if isUri then
                    local result
                    while result == nil do
                        local ok, val = pcall(game.GetObjects, game, data, true)
                        if ok then
                            result = val
                        elseif string.find(string.lower(val), "too many requests") then
                            task.wait(3)
                        else
                            error(val, 2)
                            return
                        end
                    end
                    self._properties.Data = data
                else
                    self._properties.Uri = ""
                end
                self._frame.Image = getsynasset(fileName, data)
            end)
        end

        ImageMT.Remove = ImageMT.Destroy
        ClassRegistry.Image = ImageMT
    end

    ---------------------------------------------------------------------------
    -- Public Drawing API
    ---------------------------------------------------------------------------
    Drawing.new = newcclosure(function(drawingType)
        assert(ClassRegistry[drawingType], string.format("Invalid drawing type '%s'", drawingType))
        return ClassRegistry[drawingType].new()
    end)

    Drawing.clear = newcclosure(function()
        for _, obj in allObjects do
            if obj.__OBJECT_EXISTS then
                obj:Destroy()
            end
        end
    end)

    Drawing.cache = allObjects
    if setreadonly then
        setreadonly(Drawing, true)
    end
end


--------------------------------------------------------------------------------
-- Drawing wrapper: create a drawing with initial properties
--------------------------------------------------------------------------------
local function CreateDrawing(drawingType, properties, drawingsTable)
    local obj = Drawing.new(drawingType)
    if properties then
        for key, value in pairs(properties) do
            obj[key] = value
        end
    end
    if drawingsTable then
        table.insert(drawingsTable, obj)
    end
    return obj
end

--------------------------------------------------------------------------------
-- Font registry for ESP text
--------------------------------------------------------------------------------
local ESP_FONTS = {
    ["Code"] = { font = Font.fromEnum(Enum.Font.Code), size = 13 },
    ["Monospace"] = { font = Font.new("rbxasset://fonts/families/Ubuntu.json"), size = 13 },
    ["System"] = { font = Font.new("rbxasset://fonts/families/HighwayGothic.json"), size = 12 },
    ["UI"] = { font = Font.new("rbxasset://fonts/families/Arial.json"), size = 12 },
    ["Plex"] = { font = Font.new("rbxasset://fonts/families/Roboto.json"), size = 12 },
}

local FONT_OFFSETS = {
    ["Code"] = V2(2, -1),
    ["Monospace"] = V2(2, -1),
    ["System"] = V2(2, 0),
    ["UI"] = V2(2, 0),
    ["Plex"] = V2(2, 0),
}

--------------------------------------------------------------------------------
-- World-to-viewport helper
--------------------------------------------------------------------------------
local function WorldToViewport(position)
    local screenPos, onScreen = Camera:WorldToViewportPoint(position)
    return V2(screenPos.X, screenPos.Y), onScreen
end

--------------------------------------------------------------------------------
-- R15 Skeleton definition
--------------------------------------------------------------------------------
local SKELETON_PARTS = {
    "RightHand", "LeftLowerArm", "RightLowerArm", "LeftUpperArm",
    "RightUpperArm", "LowerTorso", "LeftLowerLeg", "LeftUpperLeg",
    "LeftFoot", "RightFoot", "RightLowerLeg", "RightUpperLeg",
    "UpperTorso", "LeftHand", "Head",
}

local SKELETON_CONNECTIONS = {
    { "LeftUpperArm",  "UpperTorso" },
    { "LeftLowerArm",  "LeftUpperArm" },
    { "LeftLowerArm",  "LeftHand" },
    { "RightUpperArm", "UpperTorso" },
    { "RightLowerArm", "RightUpperArm" },
    { "RightHand",     "RightLowerArm" },
    { "LeftUpperLeg",  "LowerTorso" },
    { "LeftLowerLeg",  "LeftUpperLeg" },
    { "LeftFoot",      "LeftLowerLeg" },
    { "RightUpperLeg", "LowerTorso" },
    { "RightLowerLeg", "RightUpperLeg" },
    { "RightFoot",     "RightLowerLeg" },
    { "LowerTorso",    "UpperTorso" },
}

--------------------------------------------------------------------------------
-- Gradient system
--------------------------------------------------------------------------------
local gradientCache = {}

local function BuildGradientSequence(optionPrefix, isTransparency)
    local cached = gradientCache[optionPrefix]
    local optionValues, count

    if not cached then
        optionValues = {}
        count = 0
        while true do
            local opt = Options[optionPrefix .. (count + 1)] or (count == 0 and Options[optionPrefix])
            if not opt then break end
            count = count + 1
            table.insert(optionValues, opt)
        end
        gradientCache[optionPrefix] = { optionValues, count }
    else
        optionValues, count = unpack(cached)
    end

    local keypoints = {}
    local KPNew = isTransparency and NumberSequenceKeypoint.new or ColorSequenceKeypoint.new
    local valueProp = isTransparency and "Transparency" or "Value"

    for i, opt in optionValues do
        table.insert(keypoints, KPNew((i - 1) / (count - 1), opt[valueProp] or 0))
    end

    return isTransparency and NumberSequence.new(keypoints) or ColorSequence.new(keypoints)
end

local function RegisterGradient(category, gradientObj)
    table.insert(State.gradients[category], gradientObj)
    return gradientObj
end

--------------------------------------------------------------------------------
-- Healthbar gradient updater
--------------------------------------------------------------------------------
local function UpdateHealthbarGradient(gradientObj, health_pct, mode, colors, rotation_speed)
    if mode == "rainbow" then
        local hue = (tick() * (rotation_speed or 1)) % 1
        gradientObj.Color = ColorSequence.new(Color3.fromHSV(hue, 1, 1))
    elseif mode == "gradient" and colors then
        gradientObj.Color = colors
    end
end

--------------------------------------------------------------------------------
-- Healthbar gradient animation system
--
-- Handles rainbow/gradient modes with animated rotation for healthbar
--------------------------------------------------------------------------------
local function SetupHealthbarGradientSystem()
    local CSKNew = ColorSequenceKeypoint.new
    local HSV = Color3.fromHSV
    local slices = 3
    local colors = {}
    local indices = {}
    local hueOffset = 0
    local lerpProgress, lerpInterval = 0, 0.25
    local healthbarType = Options.esp_healthbar_type
    local healthbarMoving = Toggles.esp_healthbar_moving
    local healthbarSpeed = Options.esp_healthbar_speed
    local currentMode = healthbarType and healthbarType.Value or "default"
    local isMoving = healthbarMoving and healthbarMoving.Value or false
    local moveSpeed = healthbarSpeed and healthbarSpeed.Value or 1
    local gradientList = State.gradients.healthbar

    local function buildColorSequence()
        local keypoints = {}
        if currentMode == "rainbow" then
            for i = 0, 19 do
                local t = i / 19
                local h = t
                if isMoving then
                    h = h + hueOffset
                    if h > 1 then h = h - 1 end
                end
                keypoints[#keypoints + 1] = CSKNew(t, HSV(h, 0.5, 1))
            end
        elseif currentMode == "gradient" then
            local total = slices - 1
            local lerpT = lerpProgress / lerpInterval
            for i = 0, total do
                local idx = indices[i + 1]
                local color = colors[idx]
                if isMoving then
                    local prevIdx = indices[i] or indices[slices]
                    color = color:Lerp(colors[prevIdx], lerpT)
                end
                keypoints[i + 1] = CSKNew(i / total, color)
            end
        else
            return colors[1] or ColorSequence.new(Color3.new(0, 1, 0))
        end
        return keypoints
    end

    local function updateAllGradients()
        local seq = ColorSequence.new(buildColorSequence())
        proxy_set(make_proxy(seq), seq)
        proxy_healthbar_color[3][proxy_healthbar_color[2]] = seq
        for _, grad in gradientList do
            grad.Color = seq
        end
    end

    State.events.gradient_option_changed.Event:Connect(function(numSlices)
        table.clear(indices)
        slices = numSlices * 3
        local startOpt = Options.esp_healthbar_color_start
        local midOpt = Options.esp_healthbar_color_middle
        local endOpt = Options.esp_healthbar_color_end
        table.clear(colors)
        if startOpt and midOpt and endOpt then
            for _ = 1, numSlices do
                table.insert(colors, startOpt.Value)
            end
            for _ = 1, numSlices do
                table.insert(colors, midOpt.Value)
            end
            for _ = 1, numSlices do
                table.insert(colors, endOpt.Value)
            end
        end
        for i = 1, slices do
            table.insert(indices, i)
        end
        updateAllGradients()
    end)

    if healthbarType then
        healthbarType:OnChanged(function(v)
            currentMode = v
            if Options.esp_healthbar_slices then
                State.events.gradient_option_changed:Fire(Options.esp_healthbar_slices.Value)
            end
        end)
    end
    if healthbarMoving then
        healthbarMoving:OnChanged(function(v)
            isMoving = v
            if Options.esp_healthbar_slices then
                State.events.gradient_option_changed:Fire(Options.esp_healthbar_slices.Value)
            end
        end)
    end
    if healthbarSpeed then
        healthbarSpeed:OnChanged(function(v)
            moveSpeed = v
            if Options.esp_healthbar_slices then
                State.events.gradient_option_changed:Fire(Options.esp_healthbar_slices.Value)
            end
        end)
    end

    if Options.esp_healthbar_slices then
        State.events.gradient_option_changed:Fire(Options.esp_healthbar_slices.Value)
    end

    RunService.RenderStepped:Connect(function(dt)
        if not isMoving or not proxy_get(proxy_esp_enabled) then
            return
        end
        dt = dt * slices / 3 * moveSpeed
        hueOffset = hueOffset + dt
        lerpProgress = lerpProgress + dt
        if hueOffset > 1 then hueOffset = 0 end
        if lerpProgress > lerpInterval then
            lerpProgress = 0
            local cloned = table.clone(indices)
            if isMoving then
                indices[1] = cloned[slices]
                for i = 2, slices do
                    indices[i] = cloned[i - 1]
                end
            else
                for i = 1, slices do
                    indices[i] = i
                end
            end
        end
        if proxy_get(proxy_esp_enabled) then
            local seq = ColorSequence.new(buildColorSequence())
            proxy_healthbar_color[3][proxy_healthbar_color[2]] = seq
            for _, grad in gradientList do
                grad.Color = seq
            end
        end
    end)
end


--------------------------------------------------------------------------------
-- ESP Initializer
--
-- Creates all ESP drawing elements for a single player and returns a
-- render function connected to RenderStepped.
--------------------------------------------------------------------------------
local function InitializeESP()
    local opt_name = Toggles.esp_name and Toggles.esp_name.Value or false
    local opt_distance = Toggles.esp_distance and Toggles.esp_distance.Value or false
    local opt_weapon = Toggles.esp_weapon and Toggles.esp_weapon.Value or false
    local opt_box = Toggles.esp_box and Toggles.esp_box.Value or false
    local opt_fill = Toggles.esp_fill and Toggles.esp_fill.Value or false
    local opt_skeleton = Toggles.esp_skeleton and Toggles.esp_skeleton.Value or false
    local opt_skeleton_outline = Toggles.esp_skeleton_outline and Toggles.esp_skeleton_outline.Value or false
    local opt_skeleton_thickness = Options.esp_skeleton_thickness and Options.esp_skeleton_thickness.Value or 1
    local opt_healthbar_resize = Toggles.esp_healthbar_resize and Toggles.esp_healthbar_resize.Value or false
    local opt_healthbar_lerp = Options.esp_healthbar_health_lerp and Options.esp_healthbar_health_lerp.Value or 0.1
    local opt_dynamic_bounds = Options.esp_bounds_type and Options.esp_bounds_type.Value == "dynamic"
    local opt_width_scale = Options.esp_bounds_width_scale and Options.esp_bounds_width_scale.Value / 100 or 1
    local opt_show_team = Toggles.esp_show_team and Toggles.esp_show_team.Value or false
    local opt_healthbar_enabled = make_proxy(false)

    local any_enabled = false
    local function recalculate_visibility()
        any_enabled = proxy_get(opt_healthbar_enabled)
            or opt_name or opt_distance or opt_weapon
            or opt_box or opt_fill or opt_skeleton
    end
    recalculate_visibility()

    if Toggles.esp_healthbar then
        Toggles.esp_healthbar:OnChanged(function(v) proxy_set(opt_healthbar_enabled, v); recalculate_visibility() end)
    end
    if Toggles.esp_name then
        Toggles.esp_name:OnChanged(function(v) opt_name = v; recalculate_visibility() end)
    end
    if Toggles.esp_distance then
        Toggles.esp_distance:OnChanged(function(v) opt_distance = v; recalculate_visibility() end)
    end
    if Toggles.esp_weapon then
        Toggles.esp_weapon:OnChanged(function(v) opt_weapon = v; recalculate_visibility() end)
    end
    if Toggles.esp_box then
        Toggles.esp_box:OnChanged(function(v) opt_box = v; recalculate_visibility() end)
    end
    if Toggles.esp_fill then
        Toggles.esp_fill:OnChanged(function(v) opt_fill = v; recalculate_visibility() end)
    end
    if Toggles.esp_skeleton then
        Toggles.esp_skeleton:OnChanged(function(v) opt_skeleton = v; recalculate_visibility() end)
    end
    if Toggles.esp_show_team then
        Toggles.esp_show_team:OnChanged(function(v)
            opt_show_team = v
            State.events.esp_color_changed:Fire()
            State.events.esp_effects_changed:Fire()
        end)
    end
    if Options.esp_bounds_width_scale then
        Options.esp_bounds_width_scale:OnChanged(function(v) opt_width_scale = v / 100 end)
    end
    if Options.esp_bounds_type then
        Options.esp_bounds_type:OnChanged(function(v) opt_dynamic_bounds = (v == "dynamic") end)
    end
    if Options.esp_skeleton_thickness then
        Options.esp_skeleton_thickness:OnChanged(function(v) opt_skeleton_thickness = v end)
    end
    if Toggles.esp_skeleton_outline then
        Toggles.esp_skeleton_outline:OnChanged(function(v) opt_skeleton_outline = v end)
    end
    if Toggles.esp_healthbar_resize then
        Toggles.esp_healthbar_resize:OnChanged(function(v) opt_healthbar_resize = v end)
    end
    if Options.esp_healthbar_health_lerp then
        Options.esp_healthbar_health_lerp:OnChanged(function(v) opt_healthbar_lerp = v end)
    end

    local camUpVector = Camera.CFrame.UpVector
    local camPosition = Camera.CFrame.Position

    -- Gradient rotation animation
    do
        local animators = {}
        local function setupGradientAnimator(category, toggle, speedOption)
            if not toggle or not speedOption then return end
            local enabled = toggle.Value
            local speed = speedOption.Value
            toggle:OnChanged(function(v) enabled = v end)
            speedOption:OnChanged(function(v) speed = v end)

            local gradientList = State.gradients[category]
            table.insert(animators, function(t)
                if enabled then
                    local rot = (t * 360 * speed) % 360
                    for _, grad in pairs(gradientList) do
                        grad.Rotation = rot
                    end
                end
            end)
        end

        for category, _ in State.gradients do
            if category ~= "healthbar" then
                setupGradientAnimator(
                    category,
                    Toggles["esp_" .. category .. "_moving"],
                    Options["esp_" .. category .. "_rotation_speed"]
                )
            end
        end

        RunService.RenderStepped:Connect(function()
            local cf = Camera.CFrame
            camPosition = cf.Position
            camUpVector = cf.UpVector
            local t = tick()
            for _, animator in pairs(animators) do
                animator(t)
            end
        end)
    end

    ---------------------------------------------------------------------------
    -- Per-player ESP initialization
    ---------------------------------------------------------------------------
    return function(player, playerData)
        local espData = {
            connections = {},
            gradients   = {},
            functions   = {},
            drawings    = {},
            squares     = {},
            text        = {},
            lines       = {},
        }

        if State.running[player] then
            warn(player, "attempted to initialize twice")
            return
        end

        local character = player.Character
        local humanoid = character and character:FindFirstChild("Humanoid")
        local rootPart = character and character:FindFirstChild("HumanoidRootPart")

        if not player.Parent then return end

        local effectsHandler = State.effects.self_effects.new("esp")

        local HEAD_OFFSET = V3(0, 2.5, 0)
        local ROOT_OFFSET = V3(0, 3.5, 0)

        local currentFont = ESP_FONTS[Options.esp_font and Options.esp_font.Value or "Code"]
        local fontMinSize = V2(5, currentFont.size - 2)
        local floor2 = Vector2.zero.Floor

        local bodyParts = {}

        -- Dynamic bounding box
        local function CalculateDynamicBounds()
            local _, onScreen = WorldToViewport(rootPart.Position)
            if not onScreen then return end

            local minX, minY = math_huge, math_huge
            local maxX, maxY = -math_huge, -math_huge
            local anyVisible = false

            for _, part in pairs(bodyParts) do
                local cf = part.CFrame
                local halfSize = part.Size * 0.5
                local hx, hy, hz = halfSize.X, halfSize.Y, halfSize.Z

                for _, corner in {
                    cf * V3(-hx, -hy, -hz), cf * V3(-hx, -hy, hz),
                    cf * V3(-hx, hy, -hz),  cf * V3(-hx, hy, hz),
                    cf * V3(hx, -hy, -hz),  cf * V3(hx, -hy, hz),
                    cf * V3(hx, hy, -hz),   cf * V3(hx, hy, hz),
                } do
                    local screenPt, vis = WorldToViewport(corner.Position)
                    if not vis then continue end
                    anyVisible = true
                    minX = math_min(minX, screenPt.X)
                    minY = math_min(minY, screenPt.Y)
                    maxX = math_max(maxX, screenPt.X)
                    maxY = math_max(maxY, screenPt.Y)
                end
            end

            if not anyVisible then return end
            local width = math_max(10, maxX - minX)
            local height = math_max(10, maxY - minY)
            local size = floor2(V2(width, height))
            local pos = floor2(V2(minX + size.X / 2, minY))
            return size, pos, rootPart.Position
        end

        -- Static bounding box
        local function CalculateStaticBounds()
            local rootPos = rootPart.Position
            local topPos = rootPos + camUpVector * 2.5
            local topScreen, topVisible = WorldToViewport(topPos)
            if not topVisible then return end

            if (rootPos - camPosition).Magnitude > 600 then
                return fontMinSize, floor2(topScreen), rootPos
            end

            local bottomPos = rootPos - camUpVector * 3.5
            local bottomScreen, bottomVisible = WorldToViewport(bottomPos)
            if not bottomVisible then return end

            local height = math_max(10, math_abs(bottomScreen.Y - topScreen.Y))
            return floor2(V2(height * opt_width_scale, height)), floor2(topScreen), rootPos
        end

        local function GetBounds()
            if opt_dynamic_bounds then return CalculateDynamicBounds() end
            return CalculateStaticBounds()
        end

        local currentHealth = humanoid and humanoid.Health or 0
        local maxHealth = humanoid and humanoid.MaxHealth or 100

        -- Character setup
        local function OnCharacterAdded(char)
            character = char
            rootPart = char:WaitForChild("HumanoidRootPart", math.huge)
            humanoid = char:WaitForChild("Humanoid", math.huge)

            table.insert(espData.connections,
                humanoid:GetPropertyChangedSignal("Health"):Connect(function()
                    currentHealth = humanoid.Health
                end)
            )
            table.insert(espData.connections,
                humanoid:GetPropertyChangedSignal("MaxHealth"):Connect(function()
                    maxHealth = humanoid.MaxHealth
                end)
            )
            currentHealth = humanoid.Health
            maxHealth = humanoid.MaxHealth

            for _, partName in SKELETON_PARTS do
                bodyParts[partName] = char:WaitForChild(partName, math_huge)
            end

            if not opt_show_team and playerData._is_ally then return end
            task.wait()

            local head = bodyParts.Head
            while task.wait(1) and head.Parent and head.Transparency > 0.5 do end
            if (not opt_show_team and playerData._is_ally) or not head.Parent then return end

            if character and Toggles.esp_override_appearance and Toggles.esp_override_appearance.Value then
                State.customization.self:change(character, function()
                    local disables = Options.esp_body_disables and Options.esp_body_disables.Value or {}
                    return
                        Toggles.esp_body_color and Toggles.esp_body_color.Value and Options.esp_body_color_value and Options.esp_body_color_value.Value,
                        1 - ((Options.esp_body_transparency and Options.esp_body_transparency.Value or 0) / 100),
                        Toggles.esp_material and Toggles.esp_material.Value and Enum.Material[Options.esp_material_value and Options.esp_material_value.Value or "SmoothPlastic"],
                        disables["decals"],
                        disables["clothing"]
                end)
            end

            for _, effectType in { "aura", "particle" } do
                if character and Toggles["esp_effects_" .. effectType] and Toggles["esp_effects_" .. effectType].Value then
                    effectsHandler:create(character, Options["esp_effects_" .. effectType .. "_value"].Value, effectType)
                else
                    effectsHandler:destroy(effectType)
                end
            end
        end

        -- Create ESP drawing elements
        for idx = 1, 7 do
            espData.squares[idx] = CreateDrawing("Square", { Visible = false, Outline = true }, espData.drawings)
        end

        for idx = 1, 26 do
            local isOutline = idx > 13
            table.insert(espData.lines, CreateDrawing("Line", {
                Visible = false,
                ZIndex = not isOutline and 2 or nil,
                Thickness = opt_skeleton_thickness + (isOutline and 2 or 0),
                Color = isOutline and C3(0, 0, 0) or C3(1, 1, 1),
            }, espData.drawings))
        end

        -- Skeleton gradient colors
        do
            local skeletonGradients = {
                ColorSequence.new(
                    Options.esp_skeleton_color2 and Options.esp_skeleton_color2.Value or C3(1,1,1),
                    Options.esp_skeleton_color3 and Options.esp_skeleton_color3.Value or C3(1,1,1)
                ),
                ColorSequence.new(
                    Options.esp_skeleton_color1 and Options.esp_skeleton_color1.Value or C3(1,1,1),
                    Options.esp_skeleton_color2 and Options.esp_skeleton_color2.Value or C3(1,1,1)
                ),
                ColorSequence.new(
                    Options.esp_skeleton_color1 and Options.esp_skeleton_color1.Value or C3(1,1,1)
                ),
            }
            for i = 1, 13 do
                local grad = Instance.new("UIGradient", espData.lines[i]._frame)
                if i == 13 then
                    grad.Color = ColorSequence.new(Options.esp_skeleton_color3 and Options.esp_skeleton_color3.Value or C3(1,1,1))
                else
                    grad.Color = skeletonGradients[((i - 1) % 3) + 1]
                end
            end
        end

        -- Text elements: [1]=name, [2]=weapon, [3]=distance
        local fontInfo = ESP_FONTS[Options.esp_font and Options.esp_font.Value or "Code"]
        for idx = 1, 3 do
            local textObj = CreateDrawing("Text", {
                Outline = true, Visible = false, Color = C3(1, 1, 1),
                Middle = true, Center = true, Size = 12,
            }, espData.drawings)
            textObj._frame.FontFace = fontInfo.font
            textObj.Size = fontInfo.size
            espData.text[idx] = textObj
        end

        -- Configure squares
        espData.squares[1].Thickness = 3
        espData.squares[2].ZIndex = 2
        espData.squares[2].Color = C3(1, 1, 1)
        espData.squares[3].ZIndex = 2
        espData.squares[3].Filled = true
        espData.squares[3].Color = C3(1, 1, 1)
        espData.squares[4].Filled = true
        espData.squares[4].Color = C3(0, 0, 0)
        espData.squares[5].ZIndex = 2
        espData.squares[5].Filled = true
        espData.squares[5].Color = C3(1, 1, 1)
        espData.squares[6].Filled = true
        espData.squares[6].Color = C3(0, 0, 0)
        espData.squares[7].Filled = true
        espData.squares[7].Color = C3(1, 1, 1)

        -- Set initial text
        local clientFighter = rawget(playerData, "ClientFighter")
        clientFighter = clientFighter and rawget(clientFighter, "EquippedItem")
        espData.text[2].Text = clientFighter and clientFighter.Name or "none"
        espData.text[1].Text = (Options.esp_name_type and Options.esp_name_type.Value == "Name")
            and player.Name or player.DisplayName
        espData.text[1]._frame.RichText = true

        -- Text gradients
        for idx, prefix in { "esp_name_", "esp_weapon_", "esp_distance_" } do
            local frame = espData.text[idx]._frame
            local grad = Instance.new("UIGradient", frame)
            frame.AnchorPoint = V2(0.5, 0)
            frame.AutomaticSize = Enum.AutomaticSize.XY
            grad.Color = BuildGradientSequence(prefix .. "color")
            grad.Rotation = Options[prefix .. "rotation"] and Options[prefix .. "rotation"].Value or 0
            RegisterGradient(prefix:split("_")[2], grad)
        end

        -- Box gradient
        do
            local boxGrad = RegisterGradient("box", Instance.new("UIGradient", espData.squares[2]._frame._stroke))
            boxGrad.Rotation = Options.esp_box_rotation and Options.esp_box_rotation.Value or 0
            espData.squares[2]._frame._stroke.UIGradient.Color = BuildGradientSequence("esp_box_color")
        end

        -- Sub-render functions
        local fontOffset = FONT_OFFSETS[Options.esp_font and Options.esp_font.Value or "Code"] or V2(2, -1)

        -- BOX
        do
            local outline = espData.squares[1]
            local inner = espData.squares[2]
            local PAD2 = V2(2, 2)
            local PAD1 = V2(1, 1)
            espData.functions.box = function(size, pos)
                if opt_box then
                    local topLeft = pos - V2(size.X / 2, 0)
                    inner.Size = size; outline.Size = size + PAD2
                    inner.Position = topLeft; outline.Position = topLeft - PAD1
                    inner.Visible = true; outline.Visible = true
                else
                    inner.Visible = false; outline.Visible = false
                end
            end
        end

        -- FILL
        do
            local fillSquare = espData.squares[7]
            local fillGrad = RegisterGradient("fill", Instance.new("UIGradient", fillSquare._frame))
            fillGrad.Color = BuildGradientSequence("esp_fill_color")
            fillGrad.Transparency = BuildGradientSequence("esp_fill_color", true)
            fillGrad.Rotation = Options.esp_fill_rotation and Options.esp_fill_rotation.Value or 0
            fillSquare._frame._stroke:Destroy()
            local PAD2 = V2(2, 2)
            espData.functions.fill = function(size, pos)
                if opt_fill then
                    fillSquare.Size = size - PAD2
                    fillSquare.Position = pos - V2(size.X / 2 - 1, -1)
                    fillSquare.Visible = true
                else
                    fillSquare.Visible = false
                end
            end
            table.insert(espData.connections,
                State.events.esp_fill_changed.Event:Connect(function()
                    fillGrad.Color = BuildGradientSequence("esp_fill_color")
                    fillGrad.Transparency = BuildGradientSequence("esp_fill_color", true)
                    fillGrad.Rotation = Options.esp_fill_rotation and Options.esp_fill_rotation.Value or 0
                end)
            )
        end

        -- NAME
        do
            local nameText = espData.text[1]
            nameText._frame.AnchorPoint = V2(0.5, 1)
            espData.functions.name = function(size, pos)
                if opt_name then
                    nameText.Position = pos - V2(0, 2)
                    nameText.Visible = true
                else
                    nameText.Visible = false
                end
            end
        end

        -- WEAPON
        do
            local weaponText = espData.text[2]
            espData.functions.weapon = function(size, pos)
                if opt_weapon then
                    weaponText.Position = pos + V2(0, size.Y + 1)
                    weaponText.Visible = true
                else
                    weaponText.Visible = false
                end
            end
        end

        -- DISTANCE
        do
            local distText = espData.text[3]
            local weaponText = espData.text[2]
            espData.functions.distance = function(size, pos, worldPos)
                if opt_distance then
                    local yOffset = (weaponText.Visible and (size.Y + distText.TextBounds.Y) or size.Y) + 2
                    distText.Position = pos + V2(0, yOffset)
                    distText.Visible = true
                    distText.Text = "[" .. math_floor((camPosition - worldPos).Magnitude) .. "]"
                else
                    distText.Visible = false
                end
            end
        end

        -- SKELETON
        do
            local bones = SKELETON_CONNECTIONS
            local lines = espData.lines
            local hidden = false

            local function HideAllBones()
                if hidden then return end
                hidden = true
                for _, line in lines do line.Visible = false end
            end

            local function GetProjectedPositions()
                local projected = {}
                local count = 0
                for name, part in pairs(bodyParts) do
                    count = count + 1
                    if name ~= "UpperTorso" then
                        projected[name] = WorldToViewport(part.Position)
                    else
                        projected[name] = WorldToViewport(part.Position + V3(0, part.Size.Y / 3, 0))
                    end
                end
                if count ~= #SKELETON_PARTS then return end
                return projected
            end

            espData.functions.skeleton = function()
                if not opt_skeleton then return HideAllBones() end
                local positions = GetProjectedPositions()
                if not positions then return HideAllBones() end
                hidden = false
                for i, bone in bones do
                    local fg = lines[i]
                    local bg = lines[i + 13]
                    local fromPos = positions[bone[1]]
                    local toPos = positions[bone[2]]
                    local dir = (fromPos - toPos).Unit
                    fg.From = fromPos + dir; fg.To = toPos - dir
                    if opt_skeleton_outline then
                        bg.From = fromPos + dir * 2; bg.To = toPos - dir * 2
                        bg.Visible = true
                    else
                        bg.Visible = false
                    end
                    fg.Visible = true
                end
            end
        end

        -- HEALTHBAR
        do
            local hbGrad = RegisterGradient("healthbar",
                Instance.new("UIGradient", espData.squares[3]._frame._stroke))
            hbGrad.Color = proxy_get(make_proxy(ColorSequence.new(C3(0, 1, 0))))
            hbGrad.Rotation = 90
            local hbFg = espData.squares[3]
            local hbBg = espData.squares[4]
            hbFg._frame.AnchorPoint = V2(0, 1)
            hbBg._frame.AnchorPoint = V2(0, 1)
            local lerpedHealth = 0
            local PAD = V2(1, -1)

            table.insert(espData.connections,
                player.CharacterAdded:Connect(function() lerpedHealth = 0 end)
            )

            espData.functions.healthbar = function(size, pos)
                if proxy_get(opt_healthbar_enabled) then
                    pos = pos - V2(0, 1)
                    size = size + V2(0, 2)
                    local barPos = pos - V2(size.X / 2 + 6, -size.Y + 1) - V2(-1, 2)
                    local healthPct = currentHealth / maxHealth
                    lerpedHealth = math_lerp(lerpedHealth, healthPct, opt_healthbar_lerp)
                    local barSize = V2(2, math_max(2, (size.Y - 2) * lerpedHealth))
                    hbFg.Size = barSize; hbFg.Position = barPos
                    hbGrad.Offset = V2(0, lerpedHealth - 1)
                    if opt_healthbar_resize then
                        hbBg.Size = V2(4, barSize.Y + 2); hbBg.Position = barPos - PAD
                    else
                        hbBg.Size = V2(4, size.Y); hbBg.Position = barPos - PAD
                    end
                    hbBg.Visible = true; hbFg.Visible = true
                else
                    hbBg.Visible = false; hbFg.Visible = false
                end
            end
        end

        -- Master visibility toggle
        local allHidden = false
        local function HideAll()
            if allHidden then return end
            allHidden = true
            for _, drawing in espData.drawings do drawing.Visible = false end
        end

        -- Event connections
        table.insert(espData.connections, player.CharacterAdded:Connect(OnCharacterAdded))
        table.insert(espData.connections,
            player.CharacterRemoving:Connect(function(char)
                if character == char then
                    character = nil; rootPart = nil; humanoid = nil
                    currentHealth = 0
                    espData.text[2].Text = "none"
                    table.clear(bodyParts)
                end
            end)
        )

        -- Color/font/appearance change handler
        local appearanceTask
        table.insert(espData.connections,
            State.events.esp_color_changed.Event:Connect(function()
                for idx, prefix in { "esp_name_", "esp_weapon_", "esp_distance_" } do
                    local grad = espData.text[idx]._frame.UIGradient
                    grad.Color = BuildGradientSequence(prefix .. "color")
                    grad.Rotation = Options[prefix .. "rotation"] and Options[prefix .. "rotation"].Value or 0
                end
                local boxGrad = espData.squares[2]._frame._stroke.UIGradient
                boxGrad.Color = BuildGradientSequence("esp_box_color")
                boxGrad.Rotation = Options.esp_box_rotation and Options.esp_box_rotation.Value or 0
                espData.text[1].Text = player[Options.esp_name_type and Options.esp_name_type.Value or "DisplayName"]
                local fi = ESP_FONTS[Options.esp_font and Options.esp_font.Value or "Code"]
                for _, textObj in espData.text do
                    textObj._frame.FontFace = fi.font; textObj.Size = fi.size
                end
                do
                    local skelGrads = {
                        ColorSequence.new(
                            Options.esp_skeleton_color2 and Options.esp_skeleton_color2.Value or C3(1,1,1),
                            Options.esp_skeleton_color3 and Options.esp_skeleton_color3.Value or C3(1,1,1)),
                        ColorSequence.new(
                            Options.esp_skeleton_color1 and Options.esp_skeleton_color1.Value or C3(1,1,1),
                            Options.esp_skeleton_color2 and Options.esp_skeleton_color2.Value or C3(1,1,1)),
                        ColorSequence.new(
                            Options.esp_skeleton_color1 and Options.esp_skeleton_color1.Value or C3(1,1,1)),
                    }
                    for i, line in espData.lines do
                        local isOutline = i > 13
                        line.Thickness = opt_skeleton_thickness + (isOutline and 2 or 0)
                        if not isOutline then
                            local grad = line._frame.UIGradient
                            if i == 13 then
                                grad.Color = ColorSequence.new(Options.esp_skeleton_color3 and Options.esp_skeleton_color3.Value or C3(1,1,1))
                            else
                                grad.Color = skelGrads[((i - 1) % 3) + 1]
                            end
                        end
                    end
                end
                local function applyAppearance()
                    if (opt_show_team or not playerData._is_ally) and character
                        and Toggles.esp_override_appearance and Toggles.esp_override_appearance.Value then
                        State.customization.self:change(character, function()
                            local disables = Options.esp_body_disables and Options.esp_body_disables.Value or {}
                            return
                                Toggles.esp_body_color and Toggles.esp_body_color.Value and Options.esp_body_color_value and Options.esp_body_color_value.Value,
                                1 - ((Options.esp_body_transparency and Options.esp_body_transparency.Value or 0) / 100),
                                Toggles.esp_material and Toggles.esp_material.Value and Enum.Material[Options.esp_material_value and Options.esp_material_value.Value or "SmoothPlastic"],
                                disables["decals"],
                                Toggles.esp_material and Toggles.esp_material.Value and Options.esp_material_value.Value ~= "ForceField" or disables["clothing"]
                        end)
                    else
                        State.customization.self:restore(character)
                    end
                end
                local head = bodyParts.Head
                if character and (State.customization.self:get(character) or (head and head.Transparency < 0.5)) then
                    applyAppearance()
                elseif character and head and Toggles.esp_override_appearance and Toggles.esp_override_appearance.Value then
                    pcall(task.cancel, appearanceTask)
                    appearanceTask = task.spawn(function()
                        while task.wait(1) and head.Parent and head.Transparency > 0.5 do end
                        if head.Parent then applyAppearance() end
                    end)
                end
                fontOffset = FONT_OFFSETS[Options.esp_font and Options.esp_font.Value or "Code"] or V2(2, -1)
                fontMinSize = V2(5, (ESP_FONTS[Options.esp_font and Options.esp_font.Value or "Code"]).size - 2)
            end)
        )

        -- Effects change handler
        table.insert(espData.connections,
            State.events.esp_effects_changed.Event:Connect(function()
                for _, effectType in { "aura", "particle" } do
                    if not opt_show_team and playerData._is_ally then
                        effectsHandler:destroy(effectType); continue
                    end
                    if character and Toggles["esp_effects_" .. effectType] and Toggles["esp_effects_" .. effectType].Value then
                        effectsHandler:create(character, Options["esp_effects_" .. effectType .. "_value"].Value, effectType)
                    else
                        effectsHandler:destroy(effectType)
                    end
                end
            end)
        )

        table.insert(espData.connections,
            State.events.esp_effects_color_changed.Event:Connect(function()
                for _, effectType in { "aura", "particle" } do
                    effectsHandler:update(effectType)
                end
            end)
        )

        -- RenderStepped: main ESP update loop
        local renderBox = espData.functions.box
        local renderFill = espData.functions.fill
        local renderName = espData.functions.name
        local renderWeapon = espData.functions.weapon
        local renderDistance = espData.functions.distance
        local renderHealthbar = espData.functions.healthbar
        local renderSkeleton = espData.functions.skeleton

        table.insert(espData.connections,
            RunService.RenderStepped:Connect(function(dt)
                if not any_enabled or not rootPart or (not opt_show_team and playerData._is_ally) then
                    return HideAll()
                end
                if currentHealth <= 0 then return HideAll() end
                local size, pos, worldPos = GetBounds()
                if not size then return HideAll() end
                allHidden = false
                renderSkeleton()
                renderBox(size, pos)
                renderName(size, pos)
                renderFill(size, pos, dt)
                renderWeapon(size, pos)
                renderDistance(size, pos, worldPos)
                renderHealthbar(size, pos, dt)
            end)
        )

        if character then task.spawn(OnCharacterAdded, character) end
        table.clear(espData.functions)
        State.running[player] = espData
    end
end

--------------------------------------------------------------------------------
-- ESP Cleanup
--------------------------------------------------------------------------------
local function CleanupESP(player)
    local data = State.running[player]
    if not data then return end
    for _, conn in data.connections do
        if typeof(conn) == "RBXScriptConnection" then conn:Disconnect() end
    end
    for _, drawing in data.drawings do drawing:Destroy() end
    State.running[player] = nil
end

--------------------------------------------------------------------------------
-- Helper: Is player alive
--------------------------------------------------------------------------------
local function is_alive(character)
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    return humanoid and humanoid.Health > 0
end

--------------------------------------------------------------------------------
-- Helper: Find nearest MeshPart (for aimbot target selection)
--------------------------------------------------------------------------------
local function find_nearest_meshpart(character, screenCenter)
    local closestPart, closestDist = nil, math_huge
    for _, part in character:GetDescendants() do
        if part:IsA("MeshPart") and part.Name ~= "HumanoidRootPart" then
            local pos, onScreen = Camera:WorldToViewportPoint(part.Position)
            if onScreen then
                local dist = (V2(pos.X, pos.Y) - screenCenter).Magnitude
                if dist < closestDist then
                    closestDist = dist
                    closestPart = part
                end
            end
        end
    end
    return closestPart
end

--------------------------------------------------------------------------------
-- Lighting Effect Updaters
--------------------------------------------------------------------------------
local function update_bloom()
    local effect = BloomEffect
    if Toggles.bloom_enabled and Toggles.bloom_enabled.Value then
        effect.Enabled = true
        effect.Intensity = Options.bloom_intensity and Options.bloom_intensity.Value or BloomDefaults.Intensity
        effect.Size = Options.bloom_size and Options.bloom_size.Value or BloomDefaults.Size
        effect.Threshold = Options.bloom_threshold and Options.bloom_threshold.Value or BloomDefaults.Threshold
    else
        effect.Enabled = BloomDefaults.Enabled
        effect.Intensity = BloomDefaults.Intensity
        effect.Size = BloomDefaults.Size
        effect.Threshold = BloomDefaults.Threshold
    end
end

local function update_color_correction()
    local effect = ColorCorrectionEffect
    if Toggles.color_correction_enabled and Toggles.color_correction_enabled.Value then
        effect.Enabled = true
        effect.Saturation = Options.color_correction_saturation and Options.color_correction_saturation.Value or 0
        effect.Contrast = Options.color_correction_contrast and Options.color_correction_contrast.Value or 0
        effect.Brightness = Options.color_correction_brightness and Options.color_correction_brightness.Value or 0
        effect.TintColor = Options.color_correction_tint and Options.color_correction_tint.Value or C3(1, 1, 1)
    else
        effect.Enabled = false
    end
end

local function update_atmosphere()
    local effect = AtmosphereEffect
    if Toggles.atmosphere_enabled and Toggles.atmosphere_enabled.Value then
        effect.Parent = Lighting
        effect.Density = Options.atmosphere_density and Options.atmosphere_density.Value or 0.3
        effect.Offset = Options.atmosphere_offset and Options.atmosphere_offset.Value or 0
        effect.Decay = Options.atmosphere_decay and Options.atmosphere_decay.Value or 0
        effect.Glare = Options.atmosphere_glare and Options.atmosphere_glare.Value or 0
        effect.Haze = Options.atmosphere_haze and Options.atmosphere_haze.Value or 0
    else
        effect.Parent = nil
    end
end

local function update_sunrays()
    local effect = SunRaysEffect
    if Toggles.sunrays_enabled and Toggles.sunrays_enabled.Value then
        effect.Enabled = true
        effect.Spread = Options.sunrays_spread and Options.sunrays_spread.Value or SunRaysDefaults.Spread
        effect.Intensity = Options.sunrays_intensity and Options.sunrays_intensity.Value or SunRaysDefaults.Intensity
    else
        effect.Enabled = SunRaysDefaults.Enabled
        effect.Spread = SunRaysDefaults.Spread
        effect.Intensity = SunRaysDefaults.Intensity
    end
end

--------------------------------------------------------------------------------
-- Chat Command System
--------------------------------------------------------------------------------
local function setup_chat_commands()
    pcall(function()
        for _, channel in TextChatService:GetDescendants() do
            if channel:IsA("TextChannel") then
                channel.MessageReceived:Connect(function(msg)
                    pcall(function()
                        local text = msg.Text
                        if text:sub(1, 1) == "!" then
                            local cmd = text:sub(2):lower()
                            for _, listener in State.lua.listen_for_command do
                                pcall(listener, cmd, msg)
                            end
                        end
                    end)
                end)
            end
        end
    end)
end

--------------------------------------------------------------------------------
-- Beam Tracer System
--------------------------------------------------------------------------------
local function create_beam_tracer(startPos, endPos, config)
    config = config or {}
    local lifetime = config.lifetime or 1
    local color1 = config.color1 or C3(1, 1, 1)
    local color2 = config.color2 or C3(1, 1, 1)
    local thickness = config.thickness or 1
    local glow = config.glow or false
    local glowThickness = config.glowThickness or 3

    local line1 = Drawing.new("Line")
    line1.From = startPos
    line1.To = startPos
    line1.Color = color1
    line1.Thickness = thickness
    line1.Visible = true

    local line2
    if glow then
        line2 = Drawing.new("Line")
        line2.From = startPos
        line2.To = startPos
        line2.Color = color2
        line2.Thickness = glowThickness
        line2.Visible = true
        line2.Transparency = 0.3
    end

    local startTime = tick()
    local conn
    conn = RunService.RenderStepped:Connect(function()
        local elapsed = tick() - startTime
        local progress = math_clamp(elapsed / lifetime, 0, 1)

        local currentEnd = startPos:Lerp(endPos, math_min(progress * 2, 1))
        local currentStart = startPos:Lerp(endPos, math_max((progress - 0.5) * 2, 0))

        if progress > 0.5 then
            line1.From = currentStart
        end
        line1.To = currentEnd

        local fadeProgress = math_clamp((elapsed) / lifetime, 0, 1)
        line1.Transparency = 1 - fadeProgress

        if line2 then
            line2.From = line1.From
            line2.To = line1.To
            line2.Transparency = (1 - fadeProgress) * 0.3
        end

        if elapsed >= lifetime then
            conn:Disconnect()
            line1:Destroy()
            if line2 then line2:Destroy() end
        end
    end)
    return line1
end

--------------------------------------------------------------------------------
-- Hit Particle Effect
--------------------------------------------------------------------------------
local function create_hit_particle(hitPart, template, colorSeq, shouldWeld)
    if not template or not hitPart then return end
    local clone = template:Clone()
    for _, desc in clone:GetDescendants() do
        if desc.Name == "MainEmitter" and colorSeq then
            desc.Color = colorSeq
        end
        if desc.ClassName == "ParticleEmitter" then
            desc:Emit(5)
        end
    end
    clone.Parent = workspace
    clone.Position = hitPart.Position
    if shouldWeld then
        clone.Anchored = false
        local weld = Instance.new("WeldConstraint", clone)
        weld.Part0 = hitPart
        weld.Part1 = clone
    end
    task.delay(1, clone.Destroy, clone)
end

--------------------------------------------------------------------------------
-- Window Toggle System (RightControl/Insert keybind)
--------------------------------------------------------------------------------
local function setup_window_toggle(lib)
    local toggled = true
    local cursorLine1 = Drawing.new("Line")
    cursorLine1.Visible = false
    cursorLine1.Thickness = 1
    cursorLine1.Color = C3(1, 1, 1)

    local cursorLine2 = Drawing.new("Line")
    cursorLine2.Visible = false
    cursorLine2.Thickness = 1
    cursorLine2.Color = C3(1, 1, 1)

    local function updateCursor()
        local mousePos = UserInputService:GetMouseLocation()
        cursorLine1.From = V2(mousePos.X - 5, mousePos.Y)
        cursorLine1.To = V2(mousePos.X + 5, mousePos.Y)
        cursorLine2.From = V2(mousePos.X, mousePos.Y - 5)
        cursorLine2.To = V2(mousePos.X, mousePos.Y + 5)
    end

    local cursorConn = nil

    local function toggleMenu()
        toggled = not toggled
        lib:Toggle()

        if toggled then
            UserInputService.MouseIconEnabled = false
            cursorLine1.Visible = true
            cursorLine2.Visible = true
            if not cursorConn then
                cursorConn = RunService.RenderStepped:Connect(updateCursor)
            end
            ContextActionService:BindAction("UE_BlockInput", function()
                return Enum.ContextActionResult.Sink
            end, false, unpack(Enum.UserInputType:GetEnumItems()))
        else
            UserInputService.MouseIconEnabled = true
            cursorLine1.Visible = false
            cursorLine2.Visible = false
            if cursorConn then cursorConn:Disconnect(); cursorConn = nil end
            ContextActionService:UnbindAction("UE_BlockInput")
        end
    end

    UserInputService.InputBegan:Connect(function(input, gpe)
        if gpe then return end
        if input.KeyCode == Enum.KeyCode.RightControl or input.KeyCode == Enum.KeyCode.Insert then
            toggleMenu()
        end
    end)
end

--------------------------------------------------------------------------------
-- ThemeManager with 13 Built-in Themes
--------------------------------------------------------------------------------
local SILENT_LOAD = false

local function setup_theme_manager()
    local Http = cloneref(game:GetService("HttpService"))

    ThemeManager.Folder = ""
    ThemeManager.Library = nil
    ThemeManager.BuiltInThemes = {
        ["Default"] = {
            1,
            Http:JSONDecode('{"FontColor":"ffffff","MainColor":"131313","AccentColor":"a2cdff","BackgroundColor":"151515","OutlineColor":"212121","RiskColor":"ff7425","ItemType":"Unnamed Enhancements","SwordColor":"ffffff","SwordTransparency":"0","SwordReflectance":"0","SwordSpeed":"0.15","SwordMaterial":"Neon","Contrast":"0","Saturation":"0","Brightness":"0","BackColor":"000000","BlurSize":"15","BackTransparency":"0.7"}'),
        },
        ["Tokyo Night"] = {
            1,
            Http:JSONDecode('{"FontColor":"ffffff","MainColor":"191925","AccentColor":"6956cb","BackgroundColor":"15151e","OutlineColor":"272727","RiskColor":"fb5f5f","ItemType":"Unnamed Enhancements","SwordColor":"ffffff","SwordTransparency":"0","SwordReflectance":"0","SwordSpeed":"0.15","SwordMaterial":"Neon","Contrast":"0","Saturation":"0","Brightness":"0","BackColor":"000000","BlurSize":"15","BackTransparency":"0.7"}'),
        },
        ["Nord"] = {
            1,
            Http:JSONDecode('{"FontColor":"ffffff","MainColor":"1c1e20","AccentColor":"9effc8","BackgroundColor":"1c1e20","OutlineColor":"24282d","RiskColor":"ff7a00","ItemType":"Unnamed Enhancements","SwordColor":"ffffff","SwordTransparency":"0","SwordReflectance":"0","SwordSpeed":"0.15","SwordMaterial":"Neon","Contrast":"0","Saturation":"0","Brightness":"0","BackColor":"000000","BlurSize":"15","BackTransparency":"0.7"}'),
        },
        ["Skeet"] = {
            1,
            Http:JSONDecode('{"FontColor":"ffffff","MainColor":"131313","AccentColor":"81ff54","BackgroundColor":"151515","OutlineColor":"2a2a2a","RiskColor":"e50000","ItemType":"Unnamed Enhancements","SwordColor":"ffffff","SwordTransparency":"0","SwordReflectance":"0","SwordSpeed":"0.15","SwordMaterial":"Neon","Contrast":"0","Saturation":"0","Brightness":"0","BackColor":"000000","BlurSize":"15","BackTransparency":"0.7"}'),
        },
        ["Fatality"] = {
            1,
            Http:JSONDecode('{"FontColor":"ffffff","MainColor":"181537","AccentColor":"ca0756","BackgroundColor":"201c46","OutlineColor":"39335a","RiskColor":"e50000","ItemType":"Unnamed Enhancements","SwordColor":"ffffff","SwordTransparency":"0","SwordReflectance":"0","SwordSpeed":"0.15","SwordMaterial":"Neon","Contrast":"0","Saturation":"0","Brightness":"0","BackColor":"000000","BlurSize":"15","BackTransparency":"0.7"}'),
        },
        ["Neverlose"] = {
            1,
            Http:JSONDecode('{"FontColor":"ffffff","MainColor":"0c1014","AccentColor":"01a3f1","BackgroundColor":"0c0f14","OutlineColor":"191919","RiskColor":"e50000","ItemType":"Unnamed Enhancements","SwordColor":"ffffff","SwordTransparency":"0","SwordReflectance":"0","SwordSpeed":"0.15","SwordMaterial":"Neon","Contrast":"0","Saturation":"0","Brightness":"0","BackColor":"000000","BlurSize":"15","BackTransparency":"0.7"}'),
        },
        ["Onetap"] = {
            1,
            Http:JSONDecode('{"FontColor":"ffffff","MainColor":"1e1d22","AccentColor":"faa614","BackgroundColor":"18181c","OutlineColor":"313033","RiskColor":"e50000","ItemType":"Unnamed Enhancements","SwordColor":"ffffff","SwordTransparency":"0","SwordReflectance":"0","SwordSpeed":"0.15","SwordMaterial":"Neon","Contrast":"0","Saturation":"0","Brightness":"0","BackColor":"000000","BlurSize":"15","BackTransparency":"0.7"}'),
        },
        ["Imgui"] = {
            1,
            Http:JSONDecode('{"FontColor":"ffffff","MainColor":"151617","AccentColor":"406ba8","BackgroundColor":"151617","OutlineColor":"242424","RiskColor":"e50000","ItemType":"Unnamed Enhancements","SwordColor":"ffffff","SwordTransparency":"0","SwordReflectance":"0","SwordSpeed":"0.15","SwordMaterial":"Neon","Contrast":"0","Saturation":"0","Brightness":"0","BackColor":"000000","BlurSize":"15","BackTransparency":"0.7"}'),
        },
        ["Iniuria"] = {
            1,
            Http:JSONDecode('{"FontColor":"ffffff","MainColor":"1e1d1e","AccentColor":"c41275","BackgroundColor":"1e1d1e","OutlineColor":"33252b","RiskColor":"e50000","ItemType":"Unnamed Enhancements","SwordColor":"ffffff","SwordTransparency":"0","SwordReflectance":"0","SwordSpeed":"0.15","SwordMaterial":"Neon","Contrast":"0","Saturation":"0","Brightness":"0","BackColor":"000000","BlurSize":"15","BackTransparency":"0.7"}'),
        },
        ["Primordial"] = {
            1,
            Http:JSONDecode('{"FontColor":"ffffff","MainColor":"181818","AccentColor":"d7a6b0","BackgroundColor":"1f1f1f","OutlineColor":"2a2a2a","RiskColor":"e50000","ItemType":"Unnamed Enhancements","SwordColor":"ffffff","SwordTransparency":"0","SwordReflectance":"0","SwordSpeed":"0.15","SwordMaterial":"Neon","Contrast":"0","Saturation":"0","Brightness":"0","BackColor":"000000","BlurSize":"15","BackTransparency":"0.7"}'),
        },
        ["Monolith"] = {
            1,
            Http:JSONDecode('{"FontColor":"ffffff","MainColor":"141115","AccentColor":"c707bd","BackgroundColor":"171417","OutlineColor":"272427","RiskColor":"e50000","ItemType":"Unnamed Enhancements","SwordColor":"ffffff","SwordTransparency":"0","SwordReflectance":"0","SwordSpeed":"0.15","SwordMaterial":"Neon","Contrast":"0","Saturation":"0","Brightness":"0","BackColor":"000000","BlurSize":"15","BackTransparency":"0.7"}'),
        },
        ["V3rmillion"] = {
            1,
            Http:JSONDecode('{"FontColor":"ffffff","MainColor":"202020","AccentColor":"cd1818","BackgroundColor":"202020","OutlineColor":"2a2a2a","RiskColor":"e50000","ItemType":"Unnamed Enhancements","SwordColor":"ffffff","SwordTransparency":"0","SwordReflectance":"0","SwordSpeed":"0.15","SwordMaterial":"Neon","Contrast":"0","Saturation":"0","Brightness":"0","BackColor":"000000","BlurSize":"15","BackTransparency":"0.7"}'),
        },
        ["Dark"] = {
            1,
            Http:JSONDecode('{"FontColor":"ffffff","MainColor":"0a0a0a","AccentColor":"5945ff","BackgroundColor":"0a0a0a","OutlineColor":"171717","RiskColor":"e50000","ItemType":"Unnamed Enhancements","SwordColor":"ffffff","SwordTransparency":"0","SwordReflectance":"0","SwordSpeed":"0.15","SwordMaterial":"Neon","Contrast":"0","Saturation":"0","Brightness":"0","BackColor":"000000","BlurSize":"15","BackTransparency":"0.7"}'),
        },
    }

    function ThemeManager:ApplyTheme(name)
        if not name then return end
        local custom = self:GetCustomTheme(name)
        local themeData = custom or self.BuiltInThemes[name]
        if not themeData then return end
        if self.Library.InnerVideoBackground ~= nil then
            self.Library.InnerVideoBackground.Visible = false
        end
        local data = themeData[2]
        for key, value in next, custom or data do
            if key:find("Color") then
                self.Library[key] = Color3.fromHex(value)
                if Options[key] then Options[key]:SetValueRGB(Color3.fromHex(value)) end
            else
                self.Library[key] = value
                if Options[key] then Options[key]:SetValue(value) end
            end
        end
        self:ThemeUpdate()
    end

    function ThemeManager:ThemeUpdate()
        if self.Library.InnerVideoBackground ~= nil then
            self.Library.InnerVideoBackground.Visible = false
        end
        local keys = {
            "Contrast", "Saturation", "Brightness", "BlurSize",
            "FontColor", "RiskColor", "MainColor", "AccentColor",
            "BackgroundColor", "OutlineColor", "SwordColor",
            "ItemType", "BackTransparency", "BackColor",
            "SwordTransparency", "SwordReflectance", "SwordMaterial", "SwordSpeed",
        }
        for _, key in next, keys do
            if Options and Options[key] then
                self.Library[key] = Options[key].Value
            end
        end
        self.Library.AccentColorDark = self.Library:GetDarkerColor(self.Library.AccentColor)
        self.Library:UpdateColorsUsingRegistry()
    end

    function ThemeManager:LoadDefault()
        local selected = "Default"
        local saved = isfile(self.Folder .. "/themes/default.txt") and readfile(self.Folder .. "/themes/default.txt")
        local isBuiltIn = true
        if saved then
            if self.BuiltInThemes[saved] then
                selected = saved
            elseif self:GetCustomTheme(saved) then
                selected = saved
                isBuiltIn = false
            end
        elseif self.BuiltInThemes[self.DefaultTheme] then
            selected = self.DefaultTheme
        end
        if isBuiltIn then
            Options.ThemeManager_ThemeList:SetValue(selected)
        else
            self:ApplyTheme(selected)
        end
    end

    function ThemeManager:SaveDefault(name)
        writefile(self.Folder .. "/themes/default.txt", name)
    end

    function ThemeManager:Delete(name)
        if not name then return false, "no config file is selected" end
        local path = self.Folder .. "/themes/" .. name
        if not isfile(path) then return false, "invalid file" end
        local ok = pcall(delfile, path)
        if not ok then return false, "delete file error" end
        return true
    end

    function ThemeManager:GetCustomTheme(name)
        if not name then return end
        local path = self.Folder .. "/themes/" .. name
        if not isfile(path) then return nil end
        local ok, data = pcall(Http.JSONDecode, Http, readfile(path))
        if not ok then return nil end
        return data
    end

    function ThemeManager:SaveCustomTheme(name)
        if not name or name:gsub(" ", "") == "" then
            return self.Library:Notify("Invalid file name for theme (empty)", 3)
        end
        local data = {}
        local keys = {
            "Contrast", "Saturation", "Brightness", "BlurSize",
            "FontColor", "RiskColor", "MainColor", "AccentColor",
            "BackgroundColor", "OutlineColor", "ItemType",
            "SwordColor", "BackTransparency", "BackColor",
            "SwordTransparency", "SwordReflectance", "SwordMaterial", "SwordSpeed",
        }
        for _, key in next, keys do
            if Options[key] then
                if not key:find("Color") then
                    data[key] = Options[key].Value
                else
                    data[key] = Options[key].Value:ToHex()
                end
            end
        end
        writefile(self.Folder .. "/themes/" .. name, Http:JSONEncode(data))
    end

    function ThemeManager:ReloadCustomThemes()
        local files = listfiles(self.Folder .. "/themes")
        local result = {}
        for i = 1, #files do
            local file = files[i]
            if file:sub(-5) == ".json" then
                local dotPos = file:find(".json", 1, true)
                local charIdx = dotPos
                local char = file:sub(dotPos, dotPos)
                while char ~= "/" and char ~= "\\" and char ~= "" do
                    charIdx = charIdx - 1
                    char = file:sub(charIdx, charIdx)
                end
                if char == "/" or char == "\\" then
                    table.insert(result, file:sub(charIdx + 1))
                end
            end
        end
        return result
    end

    function ThemeManager:SetLibrary(lib) self.Library = lib end

    function ThemeManager:BuildFolderTree()
        local parts = self.Folder:split("/")
        local paths = {}
        for i = 1, #parts do
            paths[#paths + 1] = table.concat(parts, "/", 1, i)
        end
        table.insert(paths, self.Folder .. "/themes")
        for i = 1, #paths do
            if not isfolder(paths[i]) then makefolder(paths[i]) end
        end
    end

    function ThemeManager:SetFolder(folder)
        self.Folder = folder
        self:BuildFolderTree()
    end

    function ThemeManager:CreateGroupBox(tab)
        assert(self.Library, "Must set ThemeManager.Library first!")
        return tab:AddLeftTabbox()
    end

    function ThemeManager:ApplyToTab(tab)
        assert(self.Library, "Must set ThemeManager.Library first!")
        local groupbox = self:CreateGroupBox(tab)
        self:CreateThemeManager(groupbox)
    end

    function ThemeManager:ApplyToGroupbox(groupbox)
        assert(self.Library, "Must set ThemeManager.Library first!")
        self:CreateThemeManager(groupbox)
    end

    getgenv().ThemeManager = ThemeManager
end

--------------------------------------------------------------------------------
-- SaveManager — JSON config persistence
--------------------------------------------------------------------------------
local function setup_save_manager()
    local Http = cloneref(game:GetService("HttpService"))

    SaveManager.Folder = ""
    SaveManager.Ignore = {}
    SaveManager.Parser = {
        Toggle = {
            Save = function(idx, obj)
                return { type = "Toggle", idx = idx, value = obj.Value }
            end,
            Load = function(idx, data)
                if Toggles[idx] then Toggles[idx]:SetValue(data.value) end
            end,
        },
        Slider = {
            Save = function(idx, obj)
                return { type = "Slider", idx = idx, value = tostring(obj.Value) }
            end,
            Load = function(idx, data)
                if Options[idx] then Options[idx]:SetValue(data.value) end
            end,
        },
        Dropdown = {
            Save = function(idx, obj)
                return { type = "Dropdown", idx = idx, value = obj.Value, multi = obj.Multi }
            end,
            Load = function(idx, data)
                if Options[idx] then Options[idx]:SetValue(data.value) end
            end,
        },
        ColorPicker = {
            Save = function(idx, obj)
                return { type = "ColorPicker", idx = idx, value = obj.Value:ToHex(), transparency = obj.Transparency }
            end,
            Load = function(idx, data)
                if Options[idx] then Options[idx]:SetValueRGB(Color3.fromHex(data.value), data.transparency) end
            end,
        },
        KeyPicker = {
            Save = function(idx, obj)
                return { type = "KeyPicker", idx = idx, mode = obj.Mode, key = obj.Value }
            end,
            Load = function(idx, data)
                if Options[idx] then Options[idx]:SetValue({ data.key, data.mode }) end
            end,
        },
        Input = {
            Save = function(idx, obj)
                return { type = "Input", idx = idx, text = obj.Value }
            end,
            Load = function(idx, data)
                if Options[idx] and type(data.text) == "string" then Options[idx]:SetValue(data.text) end
            end,
        },
    }

    function SaveManager:BuildFolderTree()
        local dirs = { self.Folder, self.Folder .. "/settings", self.Folder .. "/themes", self.Folder .. "/configs" }
        for i = 1, #dirs do
            if not isfolder(dirs[i]) then makefolder(dirs[i]) end
        end
    end

    function SaveManager:CheckFolderTree()
        if not isfolder(self.Folder) then
            self:BuildFolderTree()
            task.wait()
        end
    end

    function SaveManager:SetIgnoreIndexes(indexes)
        for _, idx in next, indexes do self.Ignore[idx] = true end
    end

    function SaveManager:SetFolder(folder)
        self.Folder = folder
        self:BuildFolderTree()
    end

    function SaveManager:Save(name)
        if not name then return false, "no config file is selected" end
        self:CheckFolderTree()
        local path = self.Folder .. "/settings/" .. name .. ".json"
        local saveData = { objects = {} }
        for idx, toggle in next, Toggles do
            if self.Ignore[idx] then continue end
            table.insert(saveData.objects, self.Parser[toggle.Type].Save(idx, toggle))
        end
        for idx, option in next, Options do
            if not self.Parser[option.Type] then continue end
            if self.Ignore[idx] then continue end
            table.insert(saveData.objects, self.Parser[option.Type].Save(idx, option))
        end
        local ok, encoded = pcall(Http.JSONEncode, Http, saveData)
        if not ok then return false, "failed to encode data" end
        writefile(path, encoded)
        return true
    end

    function SaveManager:Load(name)
        if not name then return false, "no config file is selected" end
        if type(name) == "table" then
            for _, obj in next, name.objects do
                if self.Parser[obj.type] then
                    task.spawn(function() self.Parser[obj.type].Load(obj.idx, obj) end)
                end
            end
            return true
        end
        self:CheckFolderTree()
        local path = self.Folder .. "/settings/" .. name .. ".json"
        if not isfile(path) then return false, "invalid file" end
        local ok, decoded = pcall(Http.JSONDecode, Http, readfile(path))
        if not ok then return false, "decode error" end
        for _, obj in next, decoded.objects do
            if self.Parser[obj.type] then
                task.spawn(function() self.Parser[obj.type].Load(obj.idx, obj) end)
            end
        end
        return true
    end

    function SaveManager:Delete(name)
        if not name then return false, "no config file is selected" end
        local path = self.Folder .. "/settings/" .. name .. ".json"
        if not isfile(path) then return false, "invalid file" end
        local ok = pcall(delfile, path)
        if not ok then return false, "delete file error" end
        return true
    end

    function SaveManager:IgnoreThemeSettings()
        self:SetIgnoreIndexes({
            "ThemeManager_ThemeList", "ThemeManager_CustomThemeList",
            "ThemeManager_CustomThemeName", "VideoLink",
            "Brightness", "Contrast", "Saturation", "BlurSize",
            "FontColor", "RiskColor", "MainColor", "AccentColor",
            "BackgroundColor", "OutlineColor", "SwordColor", "ItemType",
            "BackTransparency", "BackColor", "SwordTransparency",
            "SwordReflectance", "SwordMaterial", "SwordSpeed",
        })
    end

    function SaveManager:RefreshConfigList()
        local files = listfiles(self.Folder .. "/settings")
        local result = {}
        for i = 1, #files do
            local file = files[i]
            if file:sub(-5) == ".json" then
                local dotPos = file:find(".json", 1, true)
                local charIdx = dotPos
                local char = file:sub(dotPos, dotPos)
                while char ~= "/" and char ~= "\\" and char ~= "" do
                    charIdx = charIdx - 1
                    char = file:sub(charIdx, charIdx)
                end
                if char == "/" or char == "\\" then
                    table.insert(result, file:sub(charIdx + 1, dotPos - 1))
                end
            end
        end
        return result
    end

    function SaveManager:SetLibrary(lib) self.Library = lib end

    function SaveManager:LoadAutoloadConfig()
        self:CheckFolderTree()
        if isfile(self.Folder .. "/settings/autoload.txt") then
            local name = readfile(self.Folder .. "/settings/autoload.txt")
            local ok, err = self:Load(name)
            if not ok then
                return self.Library:Notify("Failed to load autoload config: " .. err)
            end
            if not SILENT_LOAD then
                self.Library:Notify(string.format("Auto loaded config %q", name))
            end
        end
    end

    getgenv().SaveManager = SaveManager
end

--------------------------------------------------------------------------------
-- MAIN INITIALIZE FUNCTION
--------------------------------------------------------------------------------
local function initialize(lib)
    if not lib then return end

    setup_theme_manager()
    setup_save_manager()

    local Window = lib:CreateWindow("Unnamed Enhancements")

    ---------------------------------------------------------------------------
    -- TABS
    ---------------------------------------------------------------------------
    local CombatTab = Window:AddTab("Combat")
    local VisualsTab = Window:AddTab("Visuals")
    local WorldTab = Window:AddTab("World")
    local MiscTab = Window:AddTab("Misc")
    local SettingsTab = Window:AddTab("Settings")

    ---------------------------------------------------------------------------
    -- COMBAT TAB
    ---------------------------------------------------------------------------
    local TargetingGroupbox = CombatTab:AddLeftGroupbox("Targeting")
    TargetingGroupbox:AddToggle("aimbot_toggle", { Text = "enabled", Default = false })
        :AddKeyPicker("aimbot_keybind", { Default = "MB2", Mode = "Hold", Text = "aimbot" })
    TargetingGroupbox:AddToggle("targeting_visibleonly", { Text = "visible only", Default = true })
    TargetingGroupbox:AddToggle("exploits_no_spread", { Text = "no spread", Default = true })
    TargetingGroupbox:AddToggle("exploits_full_auto", { Text = "full auto", Default = false })
    TargetingGroupbox:AddToggle("aimbot_fov_outline", { Text = "show fov", Default = false })
        :AddColorPicker("aimbot_outline_color1", { Default = Color3.new(1, 1, 1) })
    TargetingGroupbox:AddToggle("aimbot_fov_moving", { Text = "fov rotation", Default = false })
    TargetingGroupbox:AddSlider("aimbot_fov_rotation_speed", { Text = "rotation speed", Min = 0, Max = 5, Default = 1, Rounding = 2 })
    TargetingGroupbox:AddSlider("silent_radius", { Text = "radius", Min = 0, Max = 500, Default = 100, Suffix = "px", Rounding = 0 })
    TargetingGroupbox:AddSlider("silent_hitchance", { Text = "hit chance", Min = 0, Max = 100, Default = 100, Suffix = "%", Rounding = 0 })
    TargetingGroupbox:AddToggle("silent_visualize", { Text = "visualize", Default = false })
        :AddColorPicker("silent_fill_color1", { Default = Color3.new(1, 1, 1) })
        :AddColorPicker("silent_fill_color2", { Default = Color3.new(0, 0, 0) })
    TargetingGroupbox:AddToggle("silent_manipulation", { Text = "manipulation", Default = false })
    TargetingGroupbox:AddToggle("target_highlight_fill", { Text = "target highlight", Default = false })
        :AddColorPicker("target_highlight_color", { Default = Color3.new(1, 0, 0), Transparency = 0.5 })
    TargetingGroupbox:AddToggle("selected_player_view", { Text = "selected player view", Default = false })

    local RagebotGroupbox = CombatTab:AddLeftGroupbox("Ragebot")
    RagebotGroupbox:AddDropdown("ragebot_priority_targets", { Text = "priority", Values = {"Head", "Body", "Closest"}, Default = "Head" })
    RagebotGroupbox:AddSlider("ragebot_void_spam_hide", { Text = "void spam delay", Min = 0, Max = 1, Default = 0.25, Rounding = 2, Suffix = "s" })
    RagebotGroupbox:AddToggle("indicator_ragebot", { Text = "ragebot indicator", Default = false })
        :AddColorPicker("indicator_ragebot_status_color", { Default = Color3.fromRGB(255, 100, 100) })
        :AddColorPicker("indicator_ragebot_text_color", { Default = Color3.fromRGB(255, 255, 255) })

    local TriggerGroupbox = CombatTab:AddRightGroupbox("Triggerbot")
    TriggerGroupbox:AddToggle("triggerbot_enabled", { Text = "enabled", Default = false })
    TriggerGroupbox:AddDropdown("triggerbot_scoped", { Text = "mode", Values = {"always", "scoped only"}, Default = "always" })

    local AntiAimGroupbox = CombatTab:AddRightGroupbox("Anti Aim")
    AntiAimGroupbox:AddToggle("anti_aim_enabled", { Text = "enabled", Default = false })
    AntiAimGroupbox:AddSlider("anti_aim_custom_yaw", { Text = "yaw angle", Min = -180, Max = 180, Default = 0, Rounding = 0 })
    AntiAimGroupbox:AddDropdown("anti_aim_pitch_mode", { Text = "pitch mode", Values = {"none", "look down", "custom", "offset"}, Default = "none" })

    ---------------------------------------------------------------------------
    -- VISUALS TAB
    ---------------------------------------------------------------------------
    local ESPGroupbox = VisualsTab:AddLeftGroupbox("ESP")
    ESPGroupbox:AddToggle("esp_name", { Text = "name", Default = false })
    ESPGroupbox:AddToggle("esp_distance", { Text = "distance", Default = false })
    ESPGroupbox:AddToggle("esp_weapon", { Text = "weapon", Default = false })
    ESPGroupbox:AddToggle("esp_box", { Text = "box", Default = false })
    ESPGroupbox:AddToggle("esp_fill", { Text = "fill", Default = false })
    ESPGroupbox:AddToggle("esp_skeleton", { Text = "skeleton", Default = false })
    ESPGroupbox:AddToggle("esp_healthbar", { Text = "healthbar", Default = false })
    ESPGroupbox:AddToggle("esp_show_team", { Text = "show team", Default = false })
    ESPGroupbox:AddToggle("esp_chams", { Text = "chams", Default = false })
    ESPGroupbox:AddToggle("esp_skeleton_outline", { Text = "skeleton outline", Default = false })
    ESPGroupbox:AddToggle("esp_healthbar_resize", { Text = "healthbar resize", Default = false })
    ESPGroupbox:AddToggle("esp_override_appearance", { Text = "override appearance", Default = false })
    ESPGroupbox:AddToggle("esp_body_color", { Text = "body color", Default = false })
    ESPGroupbox:AddToggle("esp_material", { Text = "material", Default = false })
    ESPGroupbox:AddDropdown("esp_bounds_type", { Text = "bounds type", Values = {"dynamic", "static"}, Default = "dynamic" })
    ESPGroupbox:AddDropdown("esp_world_font", { Text = "font", Values = {"Code", "Gotham", "GothamBold"}, Default = "Code" })
    ESPGroupbox:AddSlider("esp_bounds_width_scale", { Text = "width scale", Min = 0, Max = 200, Default = 100, Suffix = "%", Rounding = 0 })
    ESPGroupbox:AddSlider("esp_skeleton_thickness", { Text = "skeleton thickness", Min = 1, Max = 5, Default = 1, Rounding = 0 })
    ESPGroupbox:AddSlider("esp_healthbar_health_lerp", { Text = "health lerp", Min = 0, Max = 1, Default = 0.1, Rounding = 2 })
    ESPGroupbox:AddSlider("esp_world_object_scale", { Text = "object scale", Min = 0.5, Max = 3, Default = 1, Rounding = 1 })

    local CrosshairGroupbox = VisualsTab:AddRightGroupbox("Crosshair")
    CrosshairGroupbox:AddDropdown("crosshair_settings", { Text = "settings", Values = {"default", "custom"}, Default = "default" })

    local IndicatorsGroupbox = VisualsTab:AddRightGroupbox("Indicators")
    IndicatorsGroupbox:AddSlider("indicator_lerp", { Text = "lerp", Min = 0, Max = 1, Default = 0.1, Rounding = 2 })

    local TracerGroupbox = VisualsTab:AddRightGroupbox("Custom Tracers")
    TracerGroupbox:AddSlider("custom_tracer_lifetime", { Text = "lifetime", Min = 0.1, Max = 5, Default = 1, Rounding = 1 })

    ---------------------------------------------------------------------------
    -- WORLD TAB
    ---------------------------------------------------------------------------
    local BloomGroupbox = WorldTab:AddLeftGroupbox("Bloom")
    BloomGroupbox:AddToggle("bloom_enabled", { Text = "enable", Default = false })
    BloomGroupbox:AddSlider("bloom_intensity", { Text = "intensity", Min = 0, Max = 3, Default = 0.4, Rounding = 2 })
    BloomGroupbox:AddSlider("bloom_size", { Text = "size", Min = 0, Max = 56, Default = 24, Rounding = 0 })
    BloomGroupbox:AddSlider("bloom_threshold", { Text = "threshold", Min = 0, Max = 2, Default = 0.95, Rounding = 2 })

    local CCGroupbox = WorldTab:AddLeftGroupbox("Color Correction")
    CCGroupbox:AddToggle("color_correction_enabled", { Text = "enable", Default = false })
        :AddColorPicker("color_correction_tint", { Default = Color3.new(1, 1, 1) })
    CCGroupbox:AddSlider("color_correction_saturation", { Text = "saturation", Min = -1, Max = 1, Default = 0, Rounding = 2 })
    CCGroupbox:AddSlider("color_correction_contrast", { Text = "contrast", Min = -1, Max = 1, Default = 0, Rounding = 2 })
    CCGroupbox:AddSlider("color_correction_brightness", { Text = "brightness", Min = -1, Max = 1, Default = 0, Rounding = 2 })

    local AtmoGroupbox = WorldTab:AddRightGroupbox("Atmosphere")
    AtmoGroupbox:AddToggle("atmosphere_enabled", { Text = "enable", Default = false })
    AtmoGroupbox:AddSlider("atmosphere_decay", { Text = "decay", Min = 0, Max = 1, Default = 0, Rounding = 2 })
    AtmoGroupbox:AddSlider("atmosphere_glare", { Text = "glare", Min = 0, Max = 1, Default = 0, Rounding = 2 })
    AtmoGroupbox:AddSlider("atmosphere_haze", { Text = "haze", Min = 0, Max = 10, Default = 0, Rounding = 1 })
    AtmoGroupbox:AddSlider("atmosphere_density", { Text = "density", Min = 0, Max = 1, Default = 0.3, Rounding = 2 })
    AtmoGroupbox:AddSlider("atmosphere_offset", { Text = "offset", Min = 0, Max = 1, Default = 0, Rounding = 2 })

    local SunGroupbox = WorldTab:AddRightGroupbox("Sun Rays")
    SunGroupbox:AddToggle("sunrays_enabled", { Text = "enable", Default = false })
    SunGroupbox:AddSlider("sunrays_spread", { Text = "spread", Min = 0, Max = 1, Default = 0.5, Rounding = 2 })
    SunGroupbox:AddSlider("sunrays_intensity", { Text = "intensity", Min = 0, Max = 1, Default = 0.25, Rounding = 2 })

    local LightingGroupbox = WorldTab:AddRightGroupbox("Lighting")
    LightingGroupbox:AddDropdown("lighting_technology", { Text = "technology", Values = {"ShadowMap", "Future", "Legacy"}, Default = "ShadowMap" })

    ---------------------------------------------------------------------------
    -- MISC TAB
    ---------------------------------------------------------------------------
    local CameraGroupbox = MiscTab:AddLeftGroupbox("Camera")
    CameraGroupbox:AddToggle("camera_fov_changer", { Text = "fov changer", Default = false })
    CameraGroupbox:AddSlider("camera_aspect_ratio_y", { Text = "ratio y", Min = 0.1, Max = 3, Default = 1, Rounding = 2 })

    local AnimGroupbox = MiscTab:AddLeftGroupbox("Animations")
    AnimGroupbox:AddDropdown("animation_player_value", { Text = "animation", Values = {"default"}, Default = "default" })

    local ViewmodelGroupbox = MiscTab:AddLeftGroupbox("Viewmodel")
    ViewmodelGroupbox:AddToggle("viewmodel_offset", { Text = "offset", Default = false })
    ViewmodelGroupbox:AddToggle("viewmodel_chams", { Text = "chams", Default = false })

    local ChatGroupbox = MiscTab:AddRightGroupbox("Chat")
    ChatGroupbox:AddToggle("chat_spam_enabled", { Text = "chat spam", Default = false })

    local ArcadeGroupbox = MiscTab:AddRightGroupbox("Arcade")
    ArcadeGroupbox:AddToggle("arcade_auto_ammo", { Text = "automatically grab drops", Default = false })

    local CosmeticsGroupbox = MiscTab:AddRightGroupbox("Cosmetics")
    CosmeticsGroupbox:AddToggle("cosmetics_changer_show", { Text = "show", Default = false })

    local SoundGroupbox = MiscTab:AddRightGroupbox("Sound")
    SoundGroupbox:AddSlider("shoot_sound_speed", { Text = "speed", Min = 0.1, Max = 5, Default = 1, Suffix = "x", Rounding = 2 })

    ---------------------------------------------------------------------------
    -- SETTINGS TAB
    ---------------------------------------------------------------------------
    local SettingsGroupbox = SettingsTab:AddLeftGroupbox("Menu")
    SettingsGroupbox:AddDropdown("Keybind Menu Mode", { Text = "keybind mode", Values = {"Always", "Toggle", "Hold"}, Default = "Always" })

    SaveManager:SetLibrary(lib)
    SaveManager:SetFolder("unnamed/rivals")
    SaveManager:IgnoreThemeSettings()
    SaveManager:BuildConfigSection(SettingsTab)

    ThemeManager:SetLibrary(lib)
    ThemeManager:SetFolder("unnamed/themes")
    ThemeManager:ApplyToTab(SettingsTab)

    ---------------------------------------------------------------------------
    -- WIRING: Chat commands
    ---------------------------------------------------------------------------
    setup_chat_commands()

    ---------------------------------------------------------------------------
    -- WIRING: Visual effect OnChanged connections
    ---------------------------------------------------------------------------
    Toggles.bloom_enabled:OnChanged(update_bloom)
    Options.bloom_intensity:OnChanged(update_bloom)
    Options.bloom_size:OnChanged(update_bloom)
    Options.bloom_threshold:OnChanged(update_bloom)

    Toggles.color_correction_enabled:OnChanged(update_color_correction)
    Options.color_correction_saturation:OnChanged(update_color_correction)
    Options.color_correction_contrast:OnChanged(update_color_correction)
    Options.color_correction_brightness:OnChanged(update_color_correction)
    Options.color_correction_tint:OnChanged(update_color_correction)

    Toggles.atmosphere_enabled:OnChanged(update_atmosphere)
    Options.atmosphere_decay:OnChanged(update_atmosphere)
    Options.atmosphere_glare:OnChanged(update_atmosphere)
    Options.atmosphere_haze:OnChanged(update_atmosphere)
    Options.atmosphere_density:OnChanged(update_atmosphere)
    Options.atmosphere_offset:OnChanged(update_atmosphere)

    Toggles.sunrays_enabled:OnChanged(update_sunrays)
    Options.sunrays_spread:OnChanged(update_sunrays)
    Options.sunrays_intensity:OnChanged(update_sunrays)

    ---------------------------------------------------------------------------
    -- WIRING: Lighting technology switcher
    ---------------------------------------------------------------------------
    Options.lighting_technology:OnChanged(function()
        pcall(function()
            local tech = Options.lighting_technology.Value
            if tech == "ShadowMap" then
                Lighting.Technology = Enum.Technology.ShadowMap
            elseif tech == "Future" then
                Lighting.Technology = Enum.Technology.Future
            elseif tech == "Legacy" then
                Lighting.Technology = Enum.Technology.Legacy
            end
        end)
    end)

    ---------------------------------------------------------------------------
    -- WIRING: Game-specific remotes & modules
    ---------------------------------------------------------------------------
    local Remotes = ReplicatedStorage:FindFirstChild("Remotes")
    local RivalsModules = {}

    local localFighter = nil
    pcall(function()
        for _, v in pairs(getgc(true)) do
            if type(v) == "table" and rawget(v, "ClientFighter") and rawget(v, "IsLocalPlayer") then
                localFighter = v
                break
            end
        end
    end)
    State.localFighter = localFighter

    pcall(function()
        local camModule = ReplicatedStorage:FindFirstChild("CameraController", true)
        if camModule then
            RivalsModules.CameraController = require(camModule)
        end
    end)

    if Remotes then State.Remotes = Remotes end

    ---------------------------------------------------------------------------
    -- WIRING: Metatable hook (__namecall for no spread / silent manipulation)
    ---------------------------------------------------------------------------
    pcall(function()
        local origMt = getrawmetatable(game)
        if not origMt then return end
        local origNamecall = origMt.__namecall

        local hookFunc = newcclosure(function(self, ...)
            local method = getnamecallmethod()
            local args = {...}

            if method == "FireServer" and self.Name and Remotes and self:IsDescendantOf(Remotes) then
                -- No Spread
                if Toggles.exploits_no_spread and Toggles.exploits_no_spread.Value then
                    pcall(function()
                        for _, arg in args do
                            if type(arg) == "table" then
                                if arg._ProjectileEffect then
                                    arg._ProjectileEffect.Spread = Vector3.zero
                                    arg._ProjectileEffect.SpreadAngle = 0
                                end
                                if arg.Spread then arg.Spread = Vector3.zero end
                                if arg.SpreadAngle then arg.SpreadAngle = 0 end
                            end
                        end
                    end)
                end

                -- Silent Manipulation
                if Toggles.silent_manipulation and Toggles.silent_manipulation.Value then
                    pcall(function()
                        if State.manipulation.targetPosition then
                            for _, arg in args do
                                if type(arg) == "table" then
                                    if arg.Direction then
                                        arg.Direction = (State.manipulation.targetPosition - workspace.CurrentCamera.CFrame.Position).Unit
                                    end
                                    if arg.Origin then
                                        arg.Origin = workspace.CurrentCamera.CFrame.Position
                                    end
                                end
                            end
                        end
                    end)
                end
            end

            return origNamecall(self, ...)
        end)

        setreadonly(origMt, false)
        origMt.__namecall = hookFunc
        setreadonly(origMt, true)
    end)

    ---------------------------------------------------------------------------
    -- WIRING: Anti-Aim (CameraController.EncodeCameraRotation hook)
    ---------------------------------------------------------------------------
    if localFighter and RivalsModules.CameraController then
        pcall(function()
            local origEncode = RivalsModules.CameraController.EncodeCameraRotation
            if origEncode then
                RivalsModules.CameraController.EncodeCameraRotation = function(self, ...)
                    if Toggles.anti_aim_enabled and Toggles.anti_aim_enabled.Value then
                        local yaw = Options.anti_aim_custom_yaw and Options.anti_aim_custom_yaw.Value or 0
                        local pitchMode = Options.anti_aim_pitch_mode and Options.anti_aim_pitch_mode.Value or "none"
                        local cf = workspace.CurrentCamera.CFrame
                        cf = cf * CFrame.Angles(0, math.rad(yaw), 0)
                        if pitchMode == "look down" then
                            cf = cf * CFrame.Angles(math.rad(89), 0, 0)
                        elseif pitchMode == "custom" then
                            local pitch = Options.anti_aim_custom_pitch and Options.anti_aim_custom_pitch.Value or 0
                            cf = cf * CFrame.Angles(math.rad(pitch), 0, 0)
                        end
                        return origEncode(self, cf)
                    end
                    return origEncode(self, ...)
                end
            end
        end)
    end

    ---------------------------------------------------------------------------
    -- WIRING: Silent aim circle + aimbot FOV circle
    ---------------------------------------------------------------------------
    local silentCircle = Drawing.new("Circle")
    silentCircle.Visible = false
    silentCircle.Radius = 100
    silentCircle.Color = C3(1, 1, 1)
    silentCircle.Thickness = 1
    silentCircle.Filled = false
    silentCircle.Transparency = 1
    State.drawings.silent.circle = silentCircle

    local aimbotCircle = Drawing.new("Circle")
    aimbotCircle.Visible = false
    aimbotCircle.Radius = 100
    aimbotCircle.Color = C3(1, 1, 1)
    aimbotCircle.Thickness = 1
    aimbotCircle.Filled = false
    aimbotCircle.Transparency = 1
    State.drawings.aimbot.circle = aimbotCircle

    Toggles.silent_visualize:OnChanged(function()
        silentCircle.Visible = Toggles.silent_visualize.Value and Toggles.aimbot_toggle.Value
    end)
    Options.silent_radius:OnChanged(function()
        silentCircle.Radius = Options.silent_radius.Value
    end)
    Options.silent_fill_color1:OnChanged(function()
        silentCircle.Color = Options.silent_fill_color1.Value
    end)
    Toggles.aimbot_fov_outline:OnChanged(function()
        aimbotCircle.Visible = Toggles.aimbot_fov_outline.Value
    end)
    Options.aimbot_outline_color1:OnChanged(function()
        aimbotCircle.Color = Options.aimbot_outline_color1.Value
    end)
    Toggles.aimbot_toggle:OnChanged(function()
        if not Toggles.aimbot_toggle.Value then
            silentCircle.Visible = false
            State.manipulation.targetPosition = nil
        end
    end)

    ---------------------------------------------------------------------------
    -- WIRING: RenderStepped aimbot loop with visibility raycast
    ---------------------------------------------------------------------------
    State.raycastParams = RaycastParams.new()
    State.raycastParams.FilterType = Enum.RaycastFilterType.Exclude
    State.raycastParams.FilterDescendantsInstances = {LocalPlayer.Character}
    LocalPlayer.CharacterAdded:Connect(function(char)
        State.raycastParams.FilterDescendantsInstances = {char}
    end)

    RunService.RenderStepped:Connect(function()
        local screenCenter = workspace.CurrentCamera.ViewportSize / 2
        silentCircle.Position = screenCenter
        aimbotCircle.Position = screenCenter

        if Toggles.aimbot_fov_moving and Toggles.aimbot_fov_moving.Value then
            aimbotCircle.NumSides = 60
        end

        if Toggles.aimbot_toggle.Value and Options.aimbot_keybind:GetState() then
            local closestPlayer = nil
            local closestDist = Options.silent_radius.Value
            local cam = workspace.CurrentCamera

            for _, player in Players:GetPlayers() do
                if player == LocalPlayer then continue end
                local char = player.Character
                if not char then continue end
                local root = char:FindFirstChild("HumanoidRootPart")
                local humanoid = char:FindFirstChild("Humanoid")
                if not root or not humanoid or humanoid.Health <= 0 then continue end

                if Toggles.targeting_visibleonly and Toggles.targeting_visibleonly.Value then
                    local ray = workspace:Raycast(
                        cam.CFrame.Position,
                        (root.Position - cam.CFrame.Position).Unit * 1000,
                        State.raycastParams
                    )
                    if ray and ray.Instance and not ray.Instance:IsDescendantOf(char) then
                        continue
                    end
                end

                local screenPos, onScreen = cam:WorldToViewportPoint(root.Position)
                if not onScreen then continue end
                local dist = (V2(screenPos.X, screenPos.Y) - screenCenter).Magnitude
                if dist < closestDist then
                    closestDist = dist
                    closestPlayer = { player = player, character = char, root = root, screenPos = screenPos }
                end
            end

            if closestPlayer then
                local hitchance = Options.silent_hitchance.Value
                if math.random(1, 100) <= hitchance then
                    State.manipulation.targetPosition = closestPlayer.root.Position
                else
                    State.manipulation.targetPosition = nil
                end
            else
                State.manipulation.targetPosition = nil
            end
        else
            State.manipulation.targetPosition = nil
        end
    end)

    ---------------------------------------------------------------------------
    -- WIRING: Triggerbot (Heartbeat-based auto-fire on mouse target)
    ---------------------------------------------------------------------------
    local triggerConn = nil
    Toggles.triggerbot_enabled:OnChanged(function()
        if triggerConn then triggerConn:Disconnect(); triggerConn = nil end
        if not Toggles.triggerbot_enabled.Value then return end

        triggerConn = RunService.Heartbeat:Connect(function()
            if not localFighter then return end
            local equipped = pcall(function() return localFighter.EquippedItem end) and localFighter.EquippedItem
            if not equipped then return end

            local scopedMode = Options.triggerbot_scoped.Value
            if scopedMode == "scoped only" then
                local isAiming = pcall(function() return localFighter.IsAiming end) and localFighter.IsAiming
                if not isAiming then return end
            end

            local mouseTarget = LocalPlayer:GetMouse().Target
            if not mouseTarget then return end
            local model = mouseTarget:FindFirstAncestorOfClass("Model")
            if not model then return end
            local humanoid = model:FindFirstChildOfClass("Humanoid")
            if not humanoid or humanoid.Health <= 0 then return end
            local player = Players:GetPlayerFromCharacter(model)
            if not player or player == LocalPlayer then return end

            pcall(function()
                if equipped.shoot then equipped:shoot() end
            end)
        end)
    end)

    ---------------------------------------------------------------------------
    -- WIRING: Full auto fire mode
    ---------------------------------------------------------------------------
    Toggles.exploits_full_auto:OnChanged(function()
        pcall(function()
            if not localFighter or not localFighter.EquippedItem then return end
            local weapon = localFighter.EquippedItem
            if weapon.Info and weapon.Info.Type == "Gun" then
                if Toggles.exploits_full_auto.Value then
                    weapon.Info.FireMode = "Auto"
                end
            end
        end)
    end)

    Toggles.silent_manipulation:OnChanged(function()
        State.manipulation.active = Toggles.silent_manipulation.Value
    end)

    ---------------------------------------------------------------------------
    -- WIRING: ESP player connections
    ---------------------------------------------------------------------------
    for _, player in Players:GetPlayers() do
        if player ~= LocalPlayer then
            task.spawn(InitializeESP, player)
        end
    end
    Players.PlayerAdded:Connect(function(player)
        task.spawn(InitializeESP, player)
    end)
    Players.PlayerRemoving:Connect(function(player)
        CleanupESP(player)
    end)

    ---------------------------------------------------------------------------
    -- FINALIZE
    ---------------------------------------------------------------------------
    SaveManager:LoadAutoloadConfig()

    setup_window_toggle(lib)
    lib:Toggle()
    return lib
end

--------------------------------------------------------------------------------
-- ENTRY POINT
--------------------------------------------------------------------------------
initialize(Library)
getgenv().UE_LOADED = true


--------------------------------------------------------------------------------
-- Visual Effects Updaters
--------------------------------------------------------------------------------
local function bloom_update()
    if Toggles.bloom_enabled.Value then
        BloomEffect.Enabled = true
        BloomEffect.Size = Options.bloom_size.Value
        BloomEffect.Intensity = Options.bloom_intensity.Value
        BloomEffect.Threshold = Options.bloom_threshold.Value
    else
        for k, v in BloomDefaults do
            BloomEffect[k] = v
        end
    end
end

local function cc_update()
    ColorCorrectionEffect.Enabled = Toggles.color_correction_enabled.Value
    if not ColorCorrectionEffect.Enabled then return end
    ColorCorrectionEffect.TintColor = Options.color_correction_tint.Value
    ColorCorrectionEffect.Saturation = Options.color_correction_saturation.Value
    ColorCorrectionEffect.Contrast = Options.color_correction_contrast.Value
    ColorCorrectionEffect.Brightness = Options.color_correction_brightness.Value
end

local function atmo_update()
    AtmosphereEffect.Parent = Toggles.atmosphere_enabled.Value and Lighting or nil
    if not AtmosphereEffect.Parent then return end
    AtmosphereEffect.Color = Options.atmosphere_color.Value
    AtmosphereEffect.Decay = Options.atmosphere_decay.Value
    AtmosphereEffect.Glare = Options.atmosphere_glare.Value
    AtmosphereEffect.Haze = Options.atmosphere_haze.Value
    AtmosphereEffect.Density = Options.atmosphere_density.Value
    AtmosphereEffect.Offset = Options.atmosphere_offset.Value
end

local function sun_update()
    if Toggles.sunrays_enabled.Value then
        SunRaysEffect.Enabled = true
        SunRaysEffect.Spread = Options.sunrays_spread.Value
        SunRaysEffect.Intensity = Options.sunrays_intensity.Value
    else
        for k, v in SunRaysDefaults do
            SunRaysEffect[k] = v
        end
    end
end

--------------------------------------------------------------------------------
-- Chat Command System
--------------------------------------------------------------------------------
local function initChatCommands()
    local function dispatch(player, text)
        local handler = State.lua.listen_for_command[text]
            or State.lua.listen_for_command[text:split(" ")[1]]
        if handler then
            for _, fn in handler do
                local parts = text:split(" ")
                task.spawn(fn, player, unpack(parts, 2, #parts))
            end
        end
    end

    game:GetService("TextChatService").MessageReceived:Connect(function(msg)
        local src = msg.TextSource
        if not src then return end
        local player = Players:GetPlayerByUserId(src.UserId)
        if not player then return end
        dispatch(player, msg.Text)
    end)
end

--------------------------------------------------------------------------------
-- Window Toggle System
--
-- Handles RightControl/Insert keybind, custom cursor rendering,
-- and input blocking via ContextActionService.
--------------------------------------------------------------------------------
local function setupWindowToggle(Window)
    local ContextActionService = game:GetService("ContextActionService")
    local UserInputService = game:GetService("UserInputService")
    local GuiService = game:GetService("GuiService")
    local toggled = false
    local busy = false

    function Window:Toggle()
        if busy then return end
        toggled = not toggled
        Window.Toggled = toggled
        proxy_set(State.drawings.menuOpen, toggled)
        Window:FireEvent("VisibilityChanged", toggled)

        if toggled then
            task.spawn(function()
                local prevIcon = UserInputService.MouseIconEnabled
                local cursor = Instance.new("ImageLabel", DrawingGui)
                cursor.Image = "http://www.roblox.com/asset/?id=4292970642"
                cursor.BackgroundTransparency = 1
                cursor.ZIndex = 125
                local shadow = Instance.new("ImageLabel", DrawingGui)
                shadow.Image = "http://www.roblox.com/asset/?id=4292970642"
                shadow.ImageColor3 = C3(0, 0, 0)
                shadow.BackgroundTransparency = 1
                shadow.ZIndex = 124
                cursor.Size = UDim2.fromOffset(17, 17)
                shadow.Size = UDim2.fromOffset(19, 19)
                cursor.Rotation = -45
                shadow.Rotation = -45

                while toggled and DrawingGui.Parent do
                    UserInputService.MouseIconEnabled = false
                    local mPos = UserInputService:GetMouseLocation()
                    local pos = UDim2.fromOffset(mPos.X, mPos.Y - GuiService:GetGuiInset().Y - 1)
                    cursor.ImageColor3 = Window.AccentColor
                    cursor.Position = pos
                    shadow.Position = pos - UDim2.fromOffset(1, 1)
                    RunService.RenderStepped:Wait()
                end

                UserInputService.MouseIconEnabled = prevIcon
                cursor:Destroy()
                shadow:Destroy()
            end)
        end

        -- Close all open popups
        for _, element in Toggles do
            task.spawn(function()
                if typeof(element) ~= "table" then return end
                if element.Type == "Dropdown" then
                    element:CloseDropdown()
                elseif element.Type == "KeyPicker" then
                    element:SetModePickerVisibility(false)
                elseif element.Type == "ColorPicker" then
                    element:Hide()
                end
            end)
        end

        -- Input blocking
        if toggled and Window.BlockInput then
            ContextActionService:BindAction("Freeze", function()
                return Enum.ContextActionResult.Sink
            end, false, table.unpack(Enum.PlayerActions:GetEnumItems()))
        else
            ContextActionService:UnbindAction("Freeze")
        end
    end

    Window:GiveSignal(UserInputService.InputBegan:Connect(function(input, gameProcessed)
        if typeof(Window.ToggleKeybind) == "table" and Window.ToggleKeybind.Type == "KeyPicker" then
            if input.UserInputType == Enum.UserInputType.Keyboard
                and input.KeyCode.Name == Window.ToggleKeybind.Value then
                task.spawn(Window.Toggle)
            end
        elseif input.KeyCode == Enum.KeyCode.RightControl
            or (input.KeyCode == Enum.KeyCode.Insert and not gameProcessed) then
            task.spawn(Window.Toggle)
        end
    end))
end

--------------------------------------------------------------------------------
-- Beam Tracer System
--
-- Creates beam attachments between two world positions with UIGradient
-- animation, tweens the end position, and fades the beam over its lifetime.
--------------------------------------------------------------------------------
local function createBeamTracer(fromPos, toPos, colorSequence)
    local TweenService = game:GetService("TweenService")
    local startAtt = Create("Attachment", workspace.Terrain)
    local endAtt = Create("Attachment", workspace.Terrain)
    startAtt.WorldPosition = fromPos
    endAtt.WorldPosition = fromPos

    local beam = Instance.new("Beam")
    local width = Options.custom_tracer_width and Options.custom_tracer_width.Value or 0.05
    beam.Width0 = width
    beam.Width1 = width
    beam.LightEmission = Options.custom_tracer_emission and Options.custom_tracer_emission.Value or 1
    beam.TextureSpeed = Options.custom_tracer_texture_speed and Options.custom_tracer_texture_speed.Value or 0
    beam.TextureLength = Options.custom_tracer_texture_length and Options.custom_tracer_texture_length.Value or 1
    beam.Parent = startAtt
    beam.Color = colorSequence
    beam.Attachment0 = startAtt
    beam.Attachment1 = endAtt

    local copies = { beam }
    local segmentCount = Options.custom_tracer_segments and Options.custom_tracer_segments.Value or 1
    for i = 1, segmentCount - 1 do
        local copy = beam:Clone()
        copy.Parent = beam.Parent
        table.insert(copies, copy)
    end

    local tweenDuration = Options.custom_tracer_speed and Options.custom_tracer_speed.Value or 0.15
    TweenService:Create(endAtt, TweenInfo.new(tweenDuration), { WorldPosition = toPos }):Play()

    local lifetime = Options.custom_tracer_lifetime and Options.custom_tracer_lifetime.Value or 1
    local fadeDuration = Options.custom_tracer_fade and Options.custom_tracer_fade.Value or 0.3
    task.delay(lifetime, function()
        local lastTween
        for _, b in copies do
            lastTween = TweenService:Create(b, TweenInfo.new(fadeDuration), { Width0 = 0, Width1 = 0 })
            lastTween:Play()
        end
        if lastTween then lastTween.Completed:Wait() end
        startAtt:Destroy()
        endAtt:Destroy()
    end)
end

--------------------------------------------------------------------------------
-- Particle Effect Function
--
-- Clones a template part, emits particles, welds to the target, and
-- destroys after 1 second.
--------------------------------------------------------------------------------
local function spawnParticleEffect(target, templatePart, colorProxy, weldProxy)
    local clone = templatePart:Clone()
    for _, child in clone:GetDescendants() do
        if child.Name == "MainEmitter" then
            child.Color = proxy_get(colorProxy)
        end
        if child.ClassName == "ParticleEmitter" then
            child:Emit(5)
        end
    end
    clone.Parent = workspace
    clone.Position = target.Position
    if proxy_get(weldProxy) then
        clone.Anchored = false
        local weld = Instance.new("WeldConstraint", clone)
        weld.Part0 = target
        weld.Part1 = clone
    end
    task.delay(1, clone.Destroy, clone)
end

--------------------------------------------------------------------------------
-- ThemeManager
--
-- 13 built-in themes with full JSON-encoded color/property sets.
-- Manages custom themes, saving/loading/deleting, and folder structure.
--------------------------------------------------------------------------------
local ThemeManager = {} do
    local HttpService = cloneref(game:GetService("HttpService"))

    ThemeManager.Folder = ""
    ThemeManager.Library = nil
    ThemeManager.BuiltInThemes = {
        ["Default"] = {
            1, HttpService:JSONDecode('{"FontColor":"ffffff","MainColor":"131313","AccentColor":"a2cdff","BackgroundColor":"151515","OutlineColor":"212121","RiskColor":"ff7425","ItemType":"Unnamed Enhancements","SwordColor":"ffffff","SwordTransparency":"0","SwordReflectance":"0","SwordSpeed":"0.15","SwordMaterial":"Neon","Contrast":"0","Saturation":"0","Brightness":"0","BackColor":"000000","BlurSize":"15","BackTransparency":"0.7"}')
        },
        ["Tokyo Night"] = {
            1, HttpService:JSONDecode('{"FontColor":"ffffff","MainColor":"191925","AccentColor":"6956cb","BackgroundColor":"15151e","OutlineColor":"272727","RiskColor":"fb5f5f","ItemType":"Unnamed Enhancements","SwordColor":"ffffff","SwordTransparency":"0","SwordReflectance":"0","SwordSpeed":"0.15","SwordMaterial":"Neon","Contrast":"0","Saturation":"0","Brightness":"0","BackColor":"000000","BlurSize":"15","BackTransparency":"0.7"}')
        },
        ["Nord"] = {
            1, HttpService:JSONDecode('{"FontColor":"ffffff","MainColor":"1c1e20","AccentColor":"9effc8","BackgroundColor":"1c1e20","OutlineColor":"24282d","RiskColor":"ff7a00","ItemType":"Unnamed Enhancements","SwordColor":"ffffff","SwordTransparency":"0","SwordReflectance":"0","SwordSpeed":"0.15","SwordMaterial":"Neon","Contrast":"0","Saturation":"0","Brightness":"0","BackColor":"000000","BlurSize":"15","BackTransparency":"0.7"}')
        },
        ["Skeet"] = {
            1, HttpService:JSONDecode('{"FontColor":"ffffff","MainColor":"131313","AccentColor":"81ff54","BackgroundColor":"151515","OutlineColor":"2a2a2a","RiskColor":"e50000","ItemType":"Unnamed Enhancements","SwordColor":"ffffff","SwordTransparency":"0","SwordReflectance":"0","SwordSpeed":"0.15","SwordMaterial":"Neon","Contrast":"0","Saturation":"0","Brightness":"0","BackColor":"000000","BlurSize":"15","BackTransparency":"0.7"}')
        },
        ["Fatality"] = {
            1, HttpService:JSONDecode('{"FontColor":"ffffff","MainColor":"181537","AccentColor":"ca0756","BackgroundColor":"201c46","OutlineColor":"39335a","RiskColor":"e50000","ItemType":"Unnamed Enhancements","SwordColor":"ffffff","SwordTransparency":"0","SwordReflectance":"0","SwordSpeed":"0.15","SwordMaterial":"Neon","Contrast":"0","Saturation":"0","Brightness":"0","BackColor":"000000","BlurSize":"15","BackTransparency":"0.7"}')
        },
        ["Neverlose"] = {
            1, HttpService:JSONDecode('{"FontColor":"ffffff","MainColor":"0c1014","AccentColor":"01a3f1","BackgroundColor":"0c0f14","OutlineColor":"191919","RiskColor":"e50000","ItemType":"Unnamed Enhancements","SwordColor":"ffffff","SwordTransparency":"0","SwordReflectance":"0","SwordSpeed":"0.15","SwordMaterial":"Neon","Contrast":"0","Saturation":"0","Brightness":"0","BackColor":"000000","BlurSize":"15","BackTransparency":"0.7"}')
        },
        ["Onetap"] = {
            1, HttpService:JSONDecode('{"FontColor":"ffffff","MainColor":"1e1d22","AccentColor":"faa614","BackgroundColor":"18181c","OutlineColor":"313033","RiskColor":"e50000","ItemType":"Unnamed Enhancements","SwordColor":"ffffff","SwordTransparency":"0","SwordReflectance":"0","SwordSpeed":"0.15","SwordMaterial":"Neon","Contrast":"0","Saturation":"0","Brightness":"0","BackColor":"000000","BlurSize":"15","BackTransparency":"0.7"}')
        },
        ["Imgui"] = {
            1, HttpService:JSONDecode('{"FontColor":"ffffff","MainColor":"151617","AccentColor":"406ba8","BackgroundColor":"151617","OutlineColor":"242424","RiskColor":"e50000","ItemType":"Unnamed Enhancements","SwordColor":"ffffff","SwordTransparency":"0","SwordReflectance":"0","SwordSpeed":"0.15","SwordMaterial":"Neon","Contrast":"0","Saturation":"0","Brightness":"0","BackColor":"000000","BlurSize":"15","BackTransparency":"0.7"}')
        },
        ["Iniuria"] = {
            1, HttpService:JSONDecode('{"FontColor":"ffffff","MainColor":"1e1d1e","AccentColor":"c41275","BackgroundColor":"1e1d1e","OutlineColor":"33252b","RiskColor":"e50000","ItemType":"Unnamed Enhancements","SwordColor":"ffffff","SwordTransparency":"0","SwordReflectance":"0","SwordSpeed":"0.15","SwordMaterial":"Neon","Contrast":"0","Saturation":"0","Brightness":"0","BackColor":"000000","BlurSize":"15","BackTransparency":"0.7"}')
        },
        ["Primordial"] = {
            1, HttpService:JSONDecode('{"FontColor":"ffffff","MainColor":"181818","AccentColor":"d7a6b0","BackgroundColor":"1f1f1f","OutlineColor":"2a2a2a","RiskColor":"e50000","ItemType":"Unnamed Enhancements","SwordColor":"ffffff","SwordTransparency":"0","SwordReflectance":"0","SwordSpeed":"0.15","SwordMaterial":"Neon","Contrast":"0","Saturation":"0","Brightness":"0","BackColor":"000000","BlurSize":"15","BackTransparency":"0.7"}')
        },
        ["Monolith"] = {
            1, HttpService:JSONDecode('{"FontColor":"ffffff","MainColor":"141115","AccentColor":"c707bd","BackgroundColor":"171417","OutlineColor":"272427","RiskColor":"e50000","ItemType":"Unnamed Enhancements","SwordColor":"ffffff","SwordTransparency":"0","SwordReflectance":"0","SwordSpeed":"0.15","SwordMaterial":"Neon","Contrast":"0","Saturation":"0","Brightness":"0","BackColor":"000000","BlurSize":"15","BackTransparency":"0.7"}')
        },
        ["V3rmillion"] = {
            1, HttpService:JSONDecode('{"FontColor":"ffffff","MainColor":"202020","AccentColor":"cd1818","BackgroundColor":"202020","OutlineColor":"2a2a2a","RiskColor":"e50000","ItemType":"Unnamed Enhancements","SwordColor":"ffffff","SwordTransparency":"0","SwordReflectance":"0","SwordSpeed":"0.15","SwordMaterial":"Neon","Contrast":"0","Saturation":"0","Brightness":"0","BackColor":"000000","BlurSize":"15","BackTransparency":"0.7"}')
        },
        ["Dark"] = {
            1, HttpService:JSONDecode('{"FontColor":"ffffff","MainColor":"0a0a0a","AccentColor":"5945ff","BackgroundColor":"0a0a0a","OutlineColor":"171717","RiskColor":"e50000","ItemType":"Unnamed Enhancements","SwordColor":"ffffff","SwordTransparency":"0","SwordReflectance":"0","SwordSpeed":"0.15","SwordMaterial":"Neon","Contrast":"0","Saturation":"0","Brightness":"0","BackColor":"000000","BlurSize":"15","BackTransparency":"0.7"}')
        },
    }

    function ThemeManager:ApplyTheme(name)
        if not name then return end
        local custom = self:GetCustomTheme(name)
        local theme = custom or self.BuiltInThemes[name]
        if not theme then return end
        if self.Library.InnerVideoBackground then
            self.Library.InnerVideoBackground.Visible = false
        end
        local data = theme[2]
        for k, v in next, custom or data do
            if k:find("Color") then
                self.Library[k] = Color3.fromHex(v)
                if Options[k] then Options[k]:SetValueRGB(Color3.fromHex(v)) end
            else
                self.Library[k] = v
                if Options[k] then Options[k]:SetValue(v) end
            end
        end
        self:ThemeUpdate()
    end

    function ThemeManager:ThemeUpdate()
        if self.Library.InnerVideoBackground then
            self.Library.InnerVideoBackground.Visible = false
        end
        local keys = {
            "Contrast", "Saturation", "Brightness", "BlurSize",
            "FontColor", "RiskColor", "MainColor", "AccentColor",
            "BackgroundColor", "OutlineColor", "SwordColor", "ItemType",
            "BackTransparency", "BackColor",
            "SwordTransparency", "SwordReflectance", "SwordMaterial", "SwordSpeed",
        }
        for _, k in keys do
            if Options and Options[k] then
                self.Library[k] = Options[k].Value
            end
        end
        self.Library.AccentColorDark = self.Library:GetDarkerColor(self.Library.AccentColor)
        self.Library:UpdateColorsUsingRegistry()
    end

    function ThemeManager:LoadDefault()
        local name = "Default"
        local saved = isfile(self.Folder .. "/themes/default.txt")
            and readfile(self.Folder .. "/themes/default.txt")
        local isBuiltIn = true
        if saved then
            if self.BuiltInThemes[saved] then
                name = saved
            elseif self:GetCustomTheme(saved) then
                name = saved
                isBuiltIn = false
            end
        elseif self.BuiltInThemes[self.DefaultTheme] then
            name = self.DefaultTheme
        end
        if isBuiltIn then
            Options.ThemeManager_ThemeList:SetValue(name)
        else
            self:ApplyTheme(name)
        end
    end

    function ThemeManager:SaveDefault(name)
        writefile(self.Folder .. "/themes/default.txt", name)
    end

    function ThemeManager:Delete(name)
        if not name then return false, "no config file is selected" end
        local path = self.Folder .. "/themes/" .. name
        if not isfile(path) then return false, "invalid file" end
        local ok, err = pcall(delfile, path)
        if not ok then return false, "delete file error" end
        return true
    end

    function ThemeManager:GetCustomTheme(name)
        if not name then return end
        local path = self.Folder .. "/themes/" .. name
        if not isfile(path) then return nil end
        local raw = readfile(path)
        local ok, data = pcall(HttpService.JSONDecode, HttpService, raw)
        if not ok then return nil end
        return data
    end

    function ThemeManager:SaveCustomTheme(name)
        if not name or name:gsub(" ", "") == "" then
            return self.Library:Notify("Invalid file name for theme (empty)", 3)
        end
        local data = {}
        local keys = {
            "Contrast", "Saturation", "Brightness", "BlurSize",
            "FontColor", "RiskColor", "MainColor", "AccentColor",
            "BackgroundColor", "OutlineColor", "ItemType", "SwordColor",
            "BackTransparency", "BackColor",
            "SwordTransparency", "SwordReflectance", "SwordMaterial", "SwordSpeed",
        }
        for _, k in keys do
            if Options[k] then
                if not k:find("Color") then
                    data[k] = Options[k].Value
                else
                    data[k] = Options[k].Value:ToHex()
                end
            end
        end
        writefile(self.Folder .. "/themes/" .. name, HttpService:JSONEncode(data))
    end

    function ThemeManager:ReloadCustomThemes()
        local files = listfiles(self.Folder .. "/themes")
        local result = {}
        for i = 1, #files do
            local f = files[i]
            if f:sub(-5) == ".json" then
                local idx = f:find(".json", 1, true)
                local c = f:sub(idx, idx)
                while c ~= "/" and c ~= "\\" and c ~= "" do
                    idx = idx - 1
                    c = f:sub(idx, idx)
                end
                if c == "/" or c == "\\" then
                    table.insert(result, f:sub(idx + 1))
                end
            end
        end
        return result
    end

    function ThemeManager:SetLibrary(lib) self.Library = lib end

    function ThemeManager:BuildFolderTree()
        local segments = {}
        local parts = self.Folder:split("/")
        for i = 1, #parts do
            segments[#segments + 1] = table.concat(parts, "/", 1, i)
        end
        table.insert(segments, self.Folder .. "/themes")
        for _, path in segments do
            if not isfolder(path) then makefolder(path) end
        end
    end

    function ThemeManager:SetFolder(folder)
        self.Folder = folder
        self:BuildFolderTree()
    end

    function ThemeManager:CreateGroupBox(tab)
        assert(self.Library, "Must set ThemeManager.Library first!")
        return tab:AddLeftTabbox()
    end

    function ThemeManager:ApplyToTab(tab)
        assert(self.Library, "Must set ThemeManager.Library first!")
        local tabbox = self:CreateGroupBox(tab)
        self:CreateThemeManager(tabbox)
    end

    function ThemeManager:ApplyToGroupbox(groupbox)
        assert(self.Library, "Must set ThemeManager.Library first!")
        self:CreateThemeManager(groupbox)
    end
end

getgenv().ThemeManager = ThemeManager


--------------------------------------------------------------------------------
-- Main Initialization
--
-- Creates the full UI using LinoriaLib:
--   5 tabs (Combat, Visuals, World, Misc, Settings)
--   All groupboxes, toggles, sliders, dropdowns, color pickers, key pickers
--   Effect change listeners, lighting technology switcher
--   Remote discovery, getgc scan, metatable hook, anti-aim hook
--   Silent aim / aimbot FOV circles, main RenderStepped loop
--   Triggerbot, full auto, raycast params
--------------------------------------------------------------------------------
local function initialize(Library)
    if not Library then return end

    ---------------------------------------------------------------------------
    -- Window & Tabs
    ---------------------------------------------------------------------------
    local Window = Library:CreateWindow("Unnamed Enhancements")

    local CombatTab   = Window:AddTab("Combat")
    local VisualsTab  = Window:AddTab("Visuals")
    local WorldTab    = Window:AddTab("World")
    local MiscTab     = Window:AddTab("Misc")
    local SettingsTab = Window:AddTab("Settings")

    ---------------------------------------------------------------------------
    -- Combat > Targeting
    ---------------------------------------------------------------------------
    local TargetingGroupbox = CombatTab:AddLeftGroupbox("Targeting")
    TargetingGroupbox:AddToggle("aimbot_toggle", { Text = "enabled", Default = false })
        :AddKeyPicker("aimbot_keybind", { Default = "MB2", Mode = "Hold", Text = "aimbot" })
    TargetingGroupbox:AddToggle("targeting_visibleonly", { Text = "visible only", Default = true })
    TargetingGroupbox:AddToggle("exploits_no_spread", { Text = "no spread", Default = true })
    TargetingGroupbox:AddToggle("exploits_full_auto", { Text = "full auto", Default = false })
    TargetingGroupbox:AddToggle("aimbot_fov_outline", { Text = "show fov", Default = false })
        :AddColorPicker("aimbot_outline_color1", { Default = C3(1, 1, 1) })
    TargetingGroupbox:AddToggle("aimbot_fov_moving", { Text = "fov rotation", Default = false })
    TargetingGroupbox:AddSlider("aimbot_fov_rotation_speed", {
        Text = "rotation speed", Min = 0, Max = 5, Default = 1, Rounding = 2
    })
    TargetingGroupbox:AddSlider("silent_radius", {
        Text = "radius", Min = 0, Max = 500, Default = 100, Suffix = "px", Rounding = 0
    })
    TargetingGroupbox:AddSlider("silent_hitchance", {
        Text = "hit chance", Min = 0, Max = 100, Default = 100, Suffix = "%", Rounding = 0
    })
    TargetingGroupbox:AddToggle("silent_visualize", { Text = "visualize", Default = false })
        :AddColorPicker("silent_fill_color1", { Default = C3(1, 1, 1) })
        :AddColorPicker("silent_fill_color2", { Default = C3(0, 0, 0) })
    TargetingGroupbox:AddToggle("silent_manipulation", { Text = "manipulation", Default = false })
    TargetingGroupbox:AddToggle("target_highlight_fill", { Text = "target highlight", Default = false })
        :AddColorPicker("target_highlight_color", { Default = C3(1, 0, 0), Transparency = 0.5 })
    TargetingGroupbox:AddToggle("selected_player_view", { Text = "selected player view", Default = false })

    ---------------------------------------------------------------------------
    -- Combat > Ragebot
    ---------------------------------------------------------------------------
    local RagebotGroupbox = CombatTab:AddLeftGroupbox("Ragebot")
    RagebotGroupbox:AddDropdown("ragebot_priority_targets", {
        Text = "priority", Values = {"Head", "Body", "Closest"}, Default = "Head"
    })
    RagebotGroupbox:AddSlider("ragebot_void_spam_hide", {
        Text = "void spam delay", Min = 0, Max = 1, Default = 0.25, Rounding = 2, Suffix = "s"
    })
    RagebotGroupbox:AddToggle("indicator_ragebot", { Text = "ragebot indicator", Default = false })
        :AddColorPicker("indicator_ragebot_status_color", { Default = Color3.fromRGB(255, 100, 100) })
        :AddColorPicker("indicator_ragebot_text_color", { Default = Color3.fromRGB(255, 255, 255) })

    ---------------------------------------------------------------------------
    -- Combat > Triggerbot
    ---------------------------------------------------------------------------
    local TriggerGroupbox = CombatTab:AddRightGroupbox("Triggerbot")
    TriggerGroupbox:AddToggle("triggerbot_enabled", { Text = "enabled", Default = false })
    TriggerGroupbox:AddDropdown("triggerbot_scoped", {
        Text = "mode", Values = {"always", "scoped only"}, Default = "always"
    })

    ---------------------------------------------------------------------------
    -- Combat > Anti Aim
    ---------------------------------------------------------------------------
    local AntiAimGroupbox = CombatTab:AddRightGroupbox("Anti Aim")
    AntiAimGroupbox:AddToggle("anti_aim_enabled", { Text = "enabled", Default = false })
    AntiAimGroupbox:AddSlider("anti_aim_custom_yaw", {
        Text = "yaw angle", Min = -180, Max = 180, Default = 0, Rounding = 0
    })
    AntiAimGroupbox:AddDropdown("anti_aim_pitch_mode", {
        Text = "pitch mode", Values = {"none", "look down", "custom", "offset"}, Default = "none"
    })

    ---------------------------------------------------------------------------
    -- Visuals > ESP
    ---------------------------------------------------------------------------
    local ESPGroupbox = VisualsTab:AddLeftGroupbox("ESP")
    ESPGroupbox:AddToggle("esp_name", { Text = "name", Default = false })
    ESPGroupbox:AddToggle("esp_distance", { Text = "distance", Default = false })
    ESPGroupbox:AddToggle("esp_weapon", { Text = "weapon", Default = false })
    ESPGroupbox:AddToggle("esp_box", { Text = "box", Default = false })
    ESPGroupbox:AddToggle("esp_fill", { Text = "fill", Default = false })
    ESPGroupbox:AddToggle("esp_skeleton", { Text = "skeleton", Default = false })
    ESPGroupbox:AddToggle("esp_healthbar", { Text = "healthbar", Default = false })
    ESPGroupbox:AddToggle("esp_show_team", { Text = "show team", Default = false })
    ESPGroupbox:AddToggle("esp_chams", { Text = "chams", Default = false })
    ESPGroupbox:AddToggle("esp_skeleton_outline", { Text = "skeleton outline", Default = false })
    ESPGroupbox:AddToggle("esp_healthbar_resize", { Text = "healthbar resize", Default = false })
    ESPGroupbox:AddToggle("esp_override_appearance", { Text = "override appearance", Default = false })
    ESPGroupbox:AddToggle("esp_body_color", { Text = "body color", Default = false })
    ESPGroupbox:AddToggle("esp_material", { Text = "material", Default = false })
    ESPGroupbox:AddDropdown("esp_bounds_type", {
        Text = "bounds type", Values = {"dynamic", "static"}, Default = "dynamic"
    })
    ESPGroupbox:AddDropdown("esp_world_font", {
        Text = "font", Values = {"Code", "Gotham", "GothamBold"}, Default = "Code"
    })
    ESPGroupbox:AddSlider("esp_bounds_width_scale", {
        Text = "width scale", Min = 0, Max = 200, Default = 100, Suffix = "%", Rounding = 0
    })
    ESPGroupbox:AddSlider("esp_skeleton_thickness", {
        Text = "skeleton thickness", Min = 1, Max = 5, Default = 1, Rounding = 0
    })
    ESPGroupbox:AddSlider("esp_healthbar_health_lerp", {
        Text = "health lerp", Min = 0, Max = 1, Default = 0.1, Rounding = 2
    })
    ESPGroupbox:AddSlider("esp_world_object_scale", {
        Text = "object scale", Min = 0.5, Max = 3, Default = 1, Rounding = 1
    })

    ---------------------------------------------------------------------------
    -- Visuals > Crosshair, Indicators, Tracers
    ---------------------------------------------------------------------------
    local CrosshairGroupbox = VisualsTab:AddRightGroupbox("Crosshair")
    CrosshairGroupbox:AddDropdown("crosshair_settings", {
        Text = "settings", Values = {"default", "custom"}, Default = "default"
    })

    local IndicatorsGroupbox = VisualsTab:AddRightGroupbox("Indicators")
    IndicatorsGroupbox:AddSlider("indicator_lerp", {
        Text = "lerp", Min = 0, Max = 1, Default = 0.1, Rounding = 2
    })

    local TracerGroupbox = VisualsTab:AddRightGroupbox("Custom Tracers")
    TracerGroupbox:AddSlider("custom_tracer_lifetime", {
        Text = "lifetime", Min = 0.1, Max = 5, Default = 1, Rounding = 1
    })

    ---------------------------------------------------------------------------
    -- World > Bloom, Color Correction, Atmosphere, Sun Rays, Lighting
    ---------------------------------------------------------------------------
    local BloomGroupbox = WorldTab:AddLeftGroupbox("Bloom")
    BloomGroupbox:AddToggle("bloom_enabled", { Text = "enable", Default = false })
    BloomGroupbox:AddSlider("bloom_intensity", {
        Text = "intensity", Min = 0, Max = 3, Default = 0.4, Rounding = 2
    })
    BloomGroupbox:AddSlider("bloom_size", {
        Text = "size", Min = 0, Max = 56, Default = 24, Rounding = 0
    })
    BloomGroupbox:AddSlider("bloom_threshold", {
        Text = "threshold", Min = 0, Max = 2, Default = 0.95, Rounding = 2
    })

    local CCGroupbox = WorldTab:AddLeftGroupbox("Color Correction")
    CCGroupbox:AddToggle("color_correction_enabled", { Text = "enable", Default = false })
        :AddColorPicker("color_correction_tint", { Default = C3(1, 1, 1) })
    CCGroupbox:AddSlider("color_correction_saturation", {
        Text = "saturation", Min = -1, Max = 1, Default = 0, Rounding = 2
    })
    CCGroupbox:AddSlider("color_correction_contrast", {
        Text = "contrast", Min = -1, Max = 1, Default = 0, Rounding = 2
    })
    CCGroupbox:AddSlider("color_correction_brightness", {
        Text = "brightness", Min = -1, Max = 1, Default = 0, Rounding = 2
    })

    local AtmoGroupbox = WorldTab:AddRightGroupbox("Atmosphere")
    AtmoGroupbox:AddToggle("atmosphere_enabled", { Text = "enable", Default = false })
    AtmoGroupbox:AddSlider("atmosphere_decay", { Text = "decay", Min = 0, Max = 1, Default = 0, Rounding = 2 })
    AtmoGroupbox:AddSlider("atmosphere_glare", { Text = "glare", Min = 0, Max = 1, Default = 0, Rounding = 2 })
    AtmoGroupbox:AddSlider("atmosphere_haze", { Text = "haze", Min = 0, Max = 10, Default = 0, Rounding = 1 })
    AtmoGroupbox:AddSlider("atmosphere_density", { Text = "density", Min = 0, Max = 1, Default = 0.3, Rounding = 2 })
    AtmoGroupbox:AddSlider("atmosphere_offset", { Text = "offset", Min = 0, Max = 1, Default = 0, Rounding = 2 })

    local SunGroupbox = WorldTab:AddRightGroupbox("Sun Rays")
    SunGroupbox:AddToggle("sunrays_enabled", { Text = "enable", Default = false })
    SunGroupbox:AddSlider("sunrays_spread", { Text = "spread", Min = 0, Max = 1, Default = 0.5, Rounding = 2 })
    SunGroupbox:AddSlider("sunrays_intensity", { Text = "intensity", Min = 0, Max = 1, Default = 0.25, Rounding = 2 })

    local LightingGroupbox = WorldTab:AddRightGroupbox("Lighting")
    LightingGroupbox:AddDropdown("lighting_technology", {
        Text = "technology", Values = {"ShadowMap", "Future", "Legacy"}, Default = "ShadowMap"
    })

    ---------------------------------------------------------------------------
    -- Misc > Camera, Animations, Viewmodel, Chat, Arcade, Cosmetics, Sound
    ---------------------------------------------------------------------------
    local CameraGroupbox = MiscTab:AddLeftGroupbox("Camera")
    CameraGroupbox:AddToggle("camera_fov_changer", { Text = "fov changer", Default = false })
    CameraGroupbox:AddSlider("camera_aspect_ratio_y", {
        Text = "ratio y", Min = 0.1, Max = 3, Default = 1, Rounding = 2
    })

    local AnimGroupbox = MiscTab:AddLeftGroupbox("Animations")
    AnimGroupbox:AddDropdown("animation_player_value", {
        Text = "animation", Values = {"default"}, Default = "default"
    })

    local ViewmodelGroupbox = MiscTab:AddLeftGroupbox("Viewmodel")
    ViewmodelGroupbox:AddToggle("viewmodel_offset", { Text = "offset", Default = false })
    ViewmodelGroupbox:AddToggle("viewmodel_chams", { Text = "chams", Default = false })

    local ChatGroupbox = MiscTab:AddRightGroupbox("Chat")
    ChatGroupbox:AddToggle("chat_spam_enabled", { Text = "chat spam", Default = false })

    local ArcadeGroupbox = MiscTab:AddRightGroupbox("Arcade")
    ArcadeGroupbox:AddToggle("arcade_auto_ammo", { Text = "automatically grab drops", Default = false })

    local CosmeticsGroupbox = MiscTab:AddRightGroupbox("Cosmetics")
    CosmeticsGroupbox:AddToggle("cosmetics_changer_show", { Text = "show", Default = false })

    local SoundGroupbox = MiscTab:AddRightGroupbox("Sound")
    SoundGroupbox:AddSlider("shoot_sound_speed", {
        Text = "speed", Min = 0.1, Max = 5, Default = 1, Suffix = "x", Rounding = 2
    })

    ---------------------------------------------------------------------------
    -- Settings > Menu + SaveManager + ThemeManager
    ---------------------------------------------------------------------------
    local SettingsGroupbox = SettingsTab:AddLeftGroupbox("Menu")
    SettingsGroupbox:AddDropdown("Keybind Menu Mode", {
        Text = "keybind mode", Values = {"Always", "Toggle", "Hold"}, Default = "Always"
    })

    SaveManager:SetLibrary(Library)
    SaveManager:SetFolder("unnamed/rivals")
    SaveManager:IgnoreThemeSettings()
    SaveManager:BuildConfigSection(SettingsTab)

    ThemeManager:SetLibrary(Library)
    ThemeManager:SetFolder("unnamed/themes")
    ThemeManager:ApplyToTab(SettingsTab)

    ---------------------------------------------------------------------------
    -- Initialize systems
    ---------------------------------------------------------------------------
    initChatCommands()

    -- Connect visual effect updaters
    Toggles.bloom_enabled:OnChanged(bloom_update)
    Options.bloom_intensity:OnChanged(bloom_update)
    Options.bloom_size:OnChanged(bloom_update)
    Options.bloom_threshold:OnChanged(bloom_update)

    Toggles.color_correction_enabled:OnChanged(cc_update)
    Options.color_correction_saturation:OnChanged(cc_update)
    Options.color_correction_contrast:OnChanged(cc_update)
    Options.color_correction_brightness:OnChanged(cc_update)
    Options.color_correction_tint:OnChanged(cc_update)

    Toggles.atmosphere_enabled:OnChanged(atmo_update)
    Options.atmosphere_decay:OnChanged(atmo_update)
    Options.atmosphere_glare:OnChanged(atmo_update)
    Options.atmosphere_haze:OnChanged(atmo_update)
    Options.atmosphere_density:OnChanged(atmo_update)
    Options.atmosphere_offset:OnChanged(atmo_update)
    if Options.atmosphere_color then
        Options.atmosphere_color:OnChanged(atmo_update)
    end

    Toggles.sunrays_enabled:OnChanged(sun_update)
    Options.sunrays_spread:OnChanged(sun_update)
    Options.sunrays_intensity:OnChanged(sun_update)

    -- Lighting technology switcher
    Options.lighting_technology:OnChanged(function()
        pcall(function()
            local tech = Options.lighting_technology.Value
            if tech == "ShadowMap" then
                Lighting.Technology = Enum.Technology.ShadowMap
            elseif tech == "Future" then
                Lighting.Technology = Enum.Technology.Future
            elseif tech == "Legacy" then
                Lighting.Technology = Enum.Technology.Legacy
            end
        end)
    end)

    ---------------------------------------------------------------------------
    -- Remote discovery & module loading
    ---------------------------------------------------------------------------
    local ReplicatedStorage = game:GetService("ReplicatedStorage")
    local Remotes = ReplicatedStorage:FindFirstChild("Remotes")
    local RivalsModules = {}

    local origGetRawMetatable = clonefunction and clonefunction(getrawmetatable) or getrawmetatable
    local origNewCClosure = newcclosure or function(f) return f end

    -- getgc() scan for localFighter
    local localFighter = nil
    pcall(function()
        for _, v in pairs(getgc(true)) do
            if type(v) == "table" and rawget(v, "ClientFighter") and rawget(v, "IsLocalPlayer") then
                localFighter = v
                break
            end
        end
    end)
    State.localFighter = localFighter

    -- Module loading
    pcall(function()
        local viewmodelsModule = ReplicatedStorage:FindFirstChild("ViewModels", true)
            or ReplicatedStorage:FindFirstChild("Shared", true)
        if viewmodelsModule then
            RivalsModules.ViewModels = cloneref(require(viewmodelsModule))
        end
    end)

    pcall(function()
        local camModule = ReplicatedStorage:FindFirstChild("CameraController", true)
        if camModule then
            RivalsModules.CameraController = require(camModule)
        end
    end)

    if Remotes then State.Remotes = Remotes end

    ---------------------------------------------------------------------------
    -- Metatable Hook (__namecall for no spread + silent manipulation)
    ---------------------------------------------------------------------------
    local function installMetatableHook()
        local origMt = origGetRawMetatable(game)
        if not origMt then return end

        local origNamecall = origMt.__namecall
        local origIndex = origMt.__index

        local proxyMt = {}
        proxyMt.__index = origIndex

        proxyMt.__namecall = origNewCClosure(function(self, ...)
            local method = getnamecallmethod()
            local args = {...}

            if method == "FireServer" and self.Name and Remotes and self:IsDescendantOf(Remotes) then
                local remoteName = self.Name

                if remoteName == "ReplicateFromServer" or remoteName == "Shoot" or remoteName == "Fire" then
                    if Toggles.exploits_no_spread and Toggles.exploits_no_spread.Value then
                        pcall(function()
                            for _, arg in args do
                                if type(arg) == "table" then
                                    if arg._ProjectileEffect then
                                        arg._ProjectileEffect.Spread = Vector3.zero
                                        arg._ProjectileEffect.SpreadAngle = 0
                                    end
                                    if arg.Spread then arg.Spread = Vector3.zero end
                                    if arg.SpreadAngle then arg.SpreadAngle = 0 end
                                end
                            end
                        end)
                    end

                    if Toggles.silent_manipulation and Toggles.silent_manipulation.Value then
                        pcall(function()
                            if State.manipulation.targetPosition then
                                for _, arg in args do
                                    if type(arg) == "table" then
                                        if arg.Direction then
                                            arg.Direction = (State.manipulation.targetPosition - Camera.CFrame.Position).Unit
                                        end
                                        if arg.Origin then
                                            arg.Origin = Camera.CFrame.Position
                                        end
                                    end
                                end
                            end
                        end)
                    end
                end
            end

            return origNamecall(self, ...)
        end)

        proxyMt.__newindex = origNewCClosure(function(self, key, value) return end)

        local setRawMt = setrawmetatable or (debug and debug.setmetatable)
        if setRawMt then setRawMt(game, proxyMt) end
    end

    pcall(installMetatableHook)

    ---------------------------------------------------------------------------
    -- Anti-Aim Hook (CameraController.EncodeCameraRotation)
    ---------------------------------------------------------------------------
    if localFighter and RivalsModules.CameraController then
        pcall(function()
            local origEncode = RivalsModules.CameraController.EncodeCameraRotation
            if origEncode then
                RivalsModules.CameraController.EncodeCameraRotation = function(self, ...)
                    if Toggles.anti_aim_enabled and Toggles.anti_aim_enabled.Value then
                        local yaw = Options.anti_aim_custom_yaw and Options.anti_aim_custom_yaw.Value or 0
                        local pitchMode = Options.anti_aim_pitch_mode and Options.anti_aim_pitch_mode.Value or "none"
                        local cf = Camera.CFrame
                        cf = cf * CFrame.Angles(0, math.rad(yaw), 0)
                        if pitchMode == "look down" then
                            cf = cf * CFrame.Angles(math.rad(89), 0, 0)
                        elseif pitchMode == "custom" then
                            local pitch = Options.anti_aim_custom_pitch and Options.anti_aim_custom_pitch.Value or 0
                            cf = cf * CFrame.Angles(math.rad(pitch), 0, 0)
                        end
                        return origEncode(self, cf)
                    end
                    return origEncode(self, ...)
                end
            end
        end)
    end

    ---------------------------------------------------------------------------
    -- Silent Aim & Aimbot FOV Circles
    ---------------------------------------------------------------------------
    local silentCircle = Drawing.new("Circle")
    silentCircle.Visible = false
    silentCircle.Radius = 100
    silentCircle.Color = C3(1, 1, 1)
    silentCircle.Thickness = 1
    silentCircle.Filled = false
    silentCircle.Transparency = 1
    State.drawings.silent = State.drawings.silent or {}
    State.drawings.silent.circle = silentCircle

    local aimbotCircle = Drawing.new("Circle")
    aimbotCircle.Visible = false
    aimbotCircle.Radius = 100
    aimbotCircle.Color = C3(1, 1, 1)
    aimbotCircle.Thickness = 1
    aimbotCircle.Filled = false
    aimbotCircle.Transparency = 1
    State.drawings.aimbot = State.drawings.aimbot or {}
    State.drawings.aimbot.circle = aimbotCircle

    Toggles.silent_visualize:OnChanged(function()
        silentCircle.Visible = Toggles.silent_visualize.Value and Toggles.aimbot_toggle.Value
    end)
    Options.silent_radius:OnChanged(function() silentCircle.Radius = Options.silent_radius.Value end)
    Options.silent_fill_color1:OnChanged(function() silentCircle.Color = Options.silent_fill_color1.Value end)
    Toggles.aimbot_fov_outline:OnChanged(function() aimbotCircle.Visible = Toggles.aimbot_fov_outline.Value end)
    Options.aimbot_outline_color1:OnChanged(function() aimbotCircle.Color = Options.aimbot_outline_color1.Value end)

    Toggles.aimbot_toggle:OnChanged(function()
        if not Toggles.aimbot_toggle.Value then
            silentCircle.Visible = false
            State.manipulation.targetPosition = nil
        end
    end)

    ---------------------------------------------------------------------------
    -- Main RenderStepped Loop (silent aim target acquisition)
    ---------------------------------------------------------------------------
    RunService.RenderStepped:Connect(function()
        local screenCenter = Camera.ViewportSize / 2
        silentCircle.Position = screenCenter
        aimbotCircle.Position = screenCenter

        if Toggles.aimbot_fov_moving.Value then
            aimbotCircle.NumSides = 60
        end

        if Toggles.aimbot_toggle.Value and Options.aimbot_keybind:GetState() then
            local closestPlayer = nil
            local closestDist = Options.silent_radius.Value

            for _, player in Players:GetPlayers() do
                if player == LocalPlayer then continue end
                local char = player.Character
                if not char then continue end
                local root = char:FindFirstChild("HumanoidRootPart")
                local humanoid = char:FindFirstChild("Humanoid")
                if not root or not humanoid or humanoid.Health <= 0 then continue end

                if Toggles.targeting_visibleonly.Value then
                    local ray = workspace:Raycast(
                        Camera.CFrame.Position,
                        (root.Position - Camera.CFrame.Position).Unit * 1000,
                        State.raycastParams
                    )
                    if ray and ray.Instance and not ray.Instance:IsDescendantOf(char) then continue end
                end

                local screenPos, onScreen = Camera:WorldToViewportPoint(root.Position)
                if not onScreen then continue end
                local dist = (V2(screenPos.X, screenPos.Y) - screenCenter).Magnitude
                if dist < closestDist then
                    closestDist = dist
                    closestPlayer = { player = player, character = char, root = root }
                end
            end

            if closestPlayer then
                if math.random(1, 100) <= Options.silent_hitchance.Value then
                    State.manipulation.targetPosition = closestPlayer.root.Position
                else
                    State.manipulation.targetPosition = nil
                end
            else
                State.manipulation.targetPosition = nil
            end
        else
            State.manipulation.targetPosition = nil
        end
    end)

    ---------------------------------------------------------------------------
    -- Triggerbot (Heartbeat auto-fire)
    ---------------------------------------------------------------------------
    local triggerConn = nil
    Toggles.triggerbot_enabled:OnChanged(function()
        if triggerConn then triggerConn:Disconnect(); triggerConn = nil end
        if not Toggles.triggerbot_enabled.Value then return end

        triggerConn = RunService.Heartbeat:Connect(function()
            if not localFighter then return end
            local equipped = pcall(function() return localFighter.EquippedItem end) and localFighter.EquippedItem
            if not equipped then return end

            if Options.triggerbot_scoped.Value == "scoped only" then
                local isAiming = pcall(function() return localFighter.IsAiming end) and localFighter.IsAiming
                if not isAiming then return end
            end

            local mouseTarget = LocalPlayer:GetMouse().Target
            if not mouseTarget then return end
            local model = mouseTarget:FindFirstAncestorOfClass("Model")
            if not model then return end
            local humanoid = model:FindFirstChildOfClass("Humanoid")
            if not humanoid or humanoid.Health <= 0 then return end
            local player = Players:GetPlayerFromCharacter(model)
            if not player or player == LocalPlayer then return end

            pcall(function()
                if equipped.shoot then equipped:shoot() end
            end)
        end)
    end)

    ---------------------------------------------------------------------------
    -- Full Auto (FireMode override)
    ---------------------------------------------------------------------------
    Toggles.exploits_full_auto:OnChanged(function()
        pcall(function()
            if not localFighter or not localFighter.EquippedItem then return end
            local weapon = localFighter.EquippedItem
            if weapon.Info and weapon.Info.Type == "Gun" then
                if Toggles.exploits_full_auto.Value then
                    weapon.Info.FireMode = "Auto"
                end
            end
        end)
    end)

    ---------------------------------------------------------------------------
    -- RaycastParams Setup
    ---------------------------------------------------------------------------
    State.manipulation = State.manipulation or {}
    State.manipulation.active = false
    State.manipulation.targetPosition = nil

    State.raycastParams = RaycastParams.new()
    State.raycastParams.FilterType = Enum.RaycastFilterType.Exclude
    State.raycastParams.FilterDescendantsInstances = { LocalPlayer.Character }
    LocalPlayer.CharacterAdded:Connect(function(char)
        State.raycastParams.FilterDescendantsInstances = { char }
    end)

    Toggles.silent_manipulation:OnChanged(function()
        State.manipulation.active = Toggles.silent_manipulation.Value
    end)

    ---------------------------------------------------------------------------
    -- Window toggle, ESP init, autoload
    ---------------------------------------------------------------------------
    setupWindowToggle(Window)

    local espInit = InitializeESP()
    for _, player in Players:GetPlayers() do
        if player ~= LocalPlayer and player.Character then
            task.spawn(espInit, player, {})
        end
    end
    Players.PlayerAdded:Connect(function(player)
        player.CharacterAdded:Connect(function()
            task.spawn(espInit, player, {})
        end)
    end)
    Players.PlayerRemoving:Connect(CleanupESP)

    SaveManager:LoadAutoloadConfig()
    Library:Toggle()

    return Library
end

--------------------------------------------------------------------------------
-- Entry Point
--------------------------------------------------------------------------------
initialize(Library)
getgenv().UE_LOADED = true
