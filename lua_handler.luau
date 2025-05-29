if not game:IsLoaded() then
    game.Loaded:Wait()
end


local HttpService = game.HttpService -- Not using GetService and using HttpService.JSONEncode(HttpService, ...) to call to prevent issue with getrawmetatable
local ws = WebSocket and WebSocket.connect or websocket and websocket.connect

local host = getgenv().EthernetIPv4 or game.Players.LocalPlayer.PlayerGui:FindFirstChild('TouchGui') and "10.0.2.2" or "localhost"
local wsUrl = "ws://" .. host .. ":1306"

-- Define your filter list here
local output_filter_list = {
    "cant place here!",
    "Closed Card",
    "retry",
    "Normal",
    "Normal mode",
    "GAME HAS ENDED!, SHOW POP UP GUI!",
    'Dugeon Island is not a valid member of Folder "Workspace.Island"'
    -- Add more strings to filter here
    -- "Another message to ignore", 
}

-- Helper function to check if a message should be filtered
local function shouldFilterMessage(message)
    if type(message) ~= "string" then
        message = tostring(message) -- Ensure we are working with a string
    end
    for _, filter_item in ipairs(output_filter_list) do
        if string.find(message, filter_item, 1, true) then -- plain find, case-sensitive
            return true -- Message contains a filtered item
        end
    end
    return false -- Message is okay to send
end

local function isValidJSON(str)
    local success, result = pcall(function()
        return HttpService:JSONDecode(str)
    end)
    if success and result then
        return true
    else
        return false
    end
end

local function connectWebSocket()
    getgenv().web = nil
    repeat wait() until pcall(function()
        getgenv().web = ws(wsUrl)
        if not getgenv().web then wait(2) end
    end) == true

    getgenv().web.OnMessage:Connect(function(msg)
        if msg ~= "Client connected" and msg ~= "Client disconnected"
        and (
            not string.find(msg, '"Message":') and not string.find(msg, '"Tag":')
            or not isValidJSON(msg)
        ) then
            if getgenv().web then
                -- Removed 'messageType2' as it was undefined in this scope
                getgenv().web:Send(HttpService:JSONEncode({
                    ["Tag"] = "Websocket",
                    ["Message"] = "Script executed"
                }))
            end
            
            local success, result = pcall(function()
                task.spawn(function()
                    local s, e = pcall(loadstring(msg))
                    if not s then
                        warn(e)
                    end
                end)
            end)
    
            if not success then
                warn(result)
            end
        end
    end)
    
    getgenv().web.OnClose:Connect(function()
        connectWebSocket()
    end)
end
connectWebSocket()

if getgenv().LogGameOutput then
    game:GetService("LogService").MessageOut:Connect(function(message, messageType)
        if not shouldFilterMessage(message) then -- Apply filter here
            if getgenv().web then
                local messageType2 = tostring(messageType)
                getgenv().web:Send(HttpService:JSONEncode({
                    ["Tag"] = messageType2:gsub("Enum.MessageType.Message", ""),
                    ["Message"] = tostring(message)
                }))
            end
        end
    end)
else
    local oldprint = print
    getgenv().print = function(...)
        local args = {...}
        local full_message_string = table.concat(args, " ") -- Create a single string for filtering

        if not shouldFilterMessage(full_message_string) then -- Apply filter here
            if getgenv().web then
                getgenv().web.Send(getgenv().web, HttpService.JSONEncode(HttpService, {
                    ["Tag"] = "Output",
                    ["Message"] = args -- Send original args
                }))
            end
        end
        return oldprint(...)
    end

    local oldwarn = warn
    getgenv().warn = function(...)
        local args = {...}
        local full_message_string = table.concat(args, " ")

        if not shouldFilterMessage(full_message_string) then -- Apply filter here
            if getgenv().web then
                getgenv().web.Send(getgenv().web, HttpService.JSONEncode(HttpService, {
                    ["Tag"] = "Warning",
                    ["Message"] = args
                }))
            end
        end
        return oldwarn(...)
    end

    local olderror = error -- Note: Overriding error can sometimes have unintended side effects.
                          -- Usually, errors should halt script execution if not handled by pcall.
                          -- Be cautious with this override.
    getgenv().error = function(...)
        local args = {...}
        local arg1_string = #args > 0 and tostring(args[1]) or "" -- Error usually takes one primary string argument

        if not shouldFilterMessage(arg1_string) then -- Apply filter here (often on the first arg for errors)
            if getgenv().web then
                getgenv().web.Send(getgenv().web, HttpService.JSONEncode(HttpService, {
                    ["Tag"] = "Error",
                    ["Message"] = args
                }))
            end
        end
        return olderror(...) -- This will still throw the error and potentially stop the script
    end
end
