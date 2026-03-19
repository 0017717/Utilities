-- Configuration
local PORT = 1306
local host = getgenv().EthernetIPv4 or (game:GetService("Players").LocalPlayer.PlayerGui:FindFirstChild('TouchGui') and "10.0.2.2") or "localhost"
local wsUrl = "ws://" .. host .. ":" .. PORT

-- Services
local HttpService = cloneref(game:GetService("HttpService"))
local LogService = cloneref(game:GetService("LogService"))
local wsConnect = WebSocket and WebSocket.connect or websocket and websocket.connect

if not game:IsLoaded() then game.Loaded:Wait() end

local VSExtensionWS
local isSending = false -- To prevent infinite loops when hooking print

-- Helper: Clean data for JSON encoding (handles Instances, Vectors, CFrames, etc.)
local function serialize(val)
    local t = typeof(val)
    if t == "table" then
        local newTbl = {}
        for k, v in pairs(val) do
            newTbl[tostring(k)] = serialize(v)
        end
        return newTbl
    elseif t == "Instance" or t == "userdata" or t == "Vector3" or t == "CFrame" or t == "Color3" then
        return tostring(val)
    else
        return val
    end
end

local function sendMessage(tag, data)
    if not VSExtensionWS or isSending then return end
    
    isSending = true
    local success, payload = pcall(function()
        return HttpService:JSONEncode({
            Type = "game_message",
            Tag = tag,
            Message = serialize(data)
        })
    end)
    
    if success then
        pcall(function() VSExtensionWS:Send(payload) end)
    end
    isSending = false
end

local function executeScript(source)
    task.spawn(function()
        local func, parseError = loadstring(source)
        if not func then
            sendMessage("Error", "Compilation Error: " .. tostring(parseError))
            return
        end
        
        local success, runtimeError = pcall(func)
        if not success then
            sendMessage("Error", "Runtime Error: " .. tostring(runtimeError))
        end
    end)
end

local function connect()
    local success, result = pcall(function()
        VSExtensionWS = wsConnect(wsUrl)
    end)

    if not success or not VSExtensionWS then
        task.wait(2)
        return connect()
    end

    VSExtensionWS.OnMessage:Connect(function(msg)
        -- Keep-alive / system messages check
        if msg == "Client connected" or msg == "Client disconnected" then return end

        local isJson, data = pcall(function() return HttpService:JSONDecode(msg) end)
        
        if isJson and data.Type == "execute_script" then
            executeScript(data.Script)
        else
            -- Fallback for raw string execution
            executeScript(msg)
        end
    end)

    VSExtensionWS.OnClose:Connect(function()
        VSExtensionWS = nil
        task.wait(2)
        connect()
    end)

    -- Register Player
    sendMessage("System", "Connected: " .. game.Players.LocalPlayer.Name)
end

-- Hooking Output
if getgenv().LogGameOutput then
    LogService.MessageOut:Connect(function(message, messageType)
        local tag = tostring(messageType):gsub("Enum.MessageType.", "")
        sendMessage(tag, message)
    end)
else
    -- Hook Print
    local oldPrint = print
    getgenv().print = newcclosure(function(...)
        local args = {...}
        sendMessage("Output", #args > 1 and args or args[1])
        return oldPrint(...)
    end)

    -- Hook Warn
    local oldWarn = warn
    getgenv().warn = newcclosure(function(...)
        local args = {...}
        sendMessage("Warning", #args > 1 and args or args[1])
        return oldWarn(...)
    end)
    
    -- Hook Error
    local oldError = error
    getgenv().error = newcclosure(function(...)
        local args = {...}
        sendMessage("Error", args[1] or "Unknown Error")
        return oldError(...)
    end)
end

-- Start
task.spawn(connect)
