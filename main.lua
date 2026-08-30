--[[
    Roblox Exploit Scanner - Modern UI Edition
    Self-contained mostly ai like the ui but its wtv the base was mine.
]]

local SEVERITY = { CRITICAL = "CRITICAL", HIGH = "HIGH", MEDIUM = "MEDIUM", LOW = "LOW", SAFE = "SAFE" }

local CoreScanner = {}
local ServicesToScan = {
    "ReplicatedStorage", "Workspace", "Players", "StarterGui",
    "StarterPlayer", "Lighting", "ServerScriptService", "ServerStorage"
}
CoreScanner.FoundEvents = {}
CoreScanner.FoundFunctions = {}
CoreScanner.ScanResults = { TotalEvents = 0, TotalFunctions = 0, ScanTime = 0 }

local function ScanContainer(container, path, depth)
    if depth > 10 then return end
    local success, children = pcall(function()
        return container:GetChildren()
    end)
    if not success then return end
    for _, child in ipairs(children) do
        local currentPath = path .. "." .. child.Name
        if child:IsA("RemoteEvent") then
            table.insert(CoreScanner.FoundEvents, {
                Name = child.Name,
                Path = currentPath,
                Instance = child,
                Parent = container.Name,
                ClassName = "RemoteEvent"
            })
            CoreScanner.ScanResults.TotalEvents = CoreScanner.ScanResults.TotalEvents + 1
        end
        if child:IsA("RemoteFunction") then
            table.insert(CoreScanner.FoundFunctions, {
                Name = child.Name,
                Path = currentPath,
                Instance = child,
                Parent = container.Name,
                ClassName = "RemoteFunction"
            })
            CoreScanner.ScanResults.TotalFunctions = CoreScanner.ScanResults.TotalFunctions + 1
        end
        ScanContainer(child, currentPath, depth + 1)
    end
end

function CoreScanner.ScanAllRemotes()
    CoreScanner.FoundEvents = {}
    CoreScanner.FoundFunctions = {}
    CoreScanner.ScanResults = { TotalEvents = 0, TotalFunctions = 0, ScanTime = 0 }
    local startTime = tick()
    for _, serviceName in ipairs(ServicesToScan) do
        local success, service = pcall(function()
            return game:GetService(serviceName)
        end)
        if success and service then
            ScanContainer(service, serviceName, 0)
        end
    end
    CoreScanner.ScanResults.ScanTime = tick() - startTime
    return {
        Events = CoreScanner.FoundEvents,
        Functions = CoreScanner.FoundFunctions,
        Results = CoreScanner.ScanResults
    }
end

function CoreScanner.PrintSummary()
    print("RemoteEvents found: " .. CoreScanner.ScanResults.TotalEvents)
    print("RemoteFunctions found: " .. CoreScanner.ScanResults.TotalFunctions)
    print("Scan time: " .. string.format("%.2f", CoreScanner.ScanResults.ScanTime) .. "s")
    if CoreScanner.ScanResults.TotalEvents > 0 then
        print("RemoteEvents:")
        for i, event in ipairs(CoreScanner.FoundEvents) do
            print("  [" .. i .. "] " .. event.Path)
        end
    end
end

local TestsBasic = {}

function TestsBasic.TestDirectBypass(remoteEvent)
    local result = { TestName = "Direct Bypass", EventPath = remoteEvent.Path, Severity = nil, Success = false, Details = "" }
    local success, err = pcall(function()
        remoteEvent.Instance:FireServer()
    end)
    if success then
        result.Success = true
        result.Severity = SEVERITY.CRITICAL
        result.Details = "CRITICAL: RemoteEvent accepts calls without arguments! Server may not validate requests."
    else
        result.Success = false
        result.Severity = SEVERITY.SAFE
        result.Details = "SAFE: Direct bypass blocked - " .. tostring(err)
    end
    return result
end

function TestsBasic.TestRateLimit(remoteEvent, spamCount)
    spamCount = spamCount or 50
    local result = { TestName = "Rate Limit Test", EventPath = remoteEvent.Path, Severity = nil, Success = false, Details = "" }
    local startTime = tick()
    local successCount = 0
    for i = 1, spamCount do
        local success = pcall(function()
            remoteEvent.Instance:FireServer("spam_test_" .. i)
        end)
        if success then
            successCount = successCount + 1
        end
    end
    local elapsed = tick() - startTime
    if elapsed == 0 then elapsed = 0.001 end
    local rps = successCount / elapsed
    if successCount >= spamCount * 0.9 then
        if rps > 20 then
            result.Success = true
            result.Severity = SEVERITY.CRITICAL
            result.Details = "CRITICAL: No rate limiting! Sent " .. successCount .. " requests in " .. string.format("%.2f", elapsed) .. "s (" .. math.floor(rps) .. " req/s)"
        else
            result.Success = true
            result.Severity = SEVERITY.HIGH
            result.Details = "HIGH: Weak rate limiting. Sent " .. successCount .. " requests in " .. string.format("%.2f", elapsed) .. "s (" .. math.floor(rps) .. " req/s)"
        end
    else
        result.Success = false
        result.Severity = SEVERITY.SAFE
        result.Details = "SAFE: Rate limiting active. Only " .. successCount .. "/" .. spamCount .. " succeeded."
    end
    return result
end

function TestsBasic.TestNilArguments(remoteEvent)
    local result = { TestName = "Nil Arguments", EventPath = remoteEvent.Path, Severity = nil, Success = false, Details = "" }
    local unpackFunc = table.unpack or unpack
    local testCases = {
        {args = {nil}, desc = "Single nil"},
        {args = {nil, nil, nil}, desc = "Multiple nils"},
        {args = {}, desc = "No arguments"},
        {args = {""}, desc = "Empty string"}
    }
    local vulnerableCount = 0
    for _, test in ipairs(testCases) do
        local success = pcall(function()
            remoteEvent.Instance:FireServer(unpackFunc(test.args))
        end)
        if success then
            vulnerableCount = vulnerableCount + 1
        end
    end
    if vulnerableCount >= 3 then
        result.Success = true
        result.Severity = SEVERITY.HIGH
        result.Details = "HIGH: Accepts " .. vulnerableCount .. "/4 nil/empty argument patterns"
    elseif vulnerableCount > 0 then
        result.Success = true
        result.Severity = SEVERITY.MEDIUM
        result.Details = "MEDIUM: Accepts " .. vulnerableCount .. "/4 nil/empty patterns"
    else
        result.Success = false
        result.Severity = SEVERITY.SAFE
        result.Details = "SAFE: Rejects nil/empty arguments"
    end
    return result
end

function TestsBasic.TestBooleanConfusion(remoteEvent)
    local result = { TestName = "Boolean Confusion", EventPath = remoteEvent.Path, Severity = nil, Success = false, Details = "" }
    local testValues = {true, false, "true", "false", 1, 0}
    local successCount = 0
    for _, value in ipairs(testValues) do
        local success = pcall(function()
            remoteEvent.Instance:FireServer(value)
        end)
        if success then
            successCount = successCount + 1
        end
    end
    if successCount == #testValues then
        result.Success = true
        result.Severity = SEVERITY.MEDIUM
        result.Details = "MEDIUM: Accepts all boolean-like values without type validation"
    else
        result.Success = false
        result.Severity = SEVERITY.LOW
        result.Details = "LOW: Some type validation present (" .. successCount .. "/" .. #testValues .. " accepted)"
    end
    return result
end

function TestsBasic.RunAllTests(remoteEvent, onProgress)
    local allResults = {}
    if onProgress then onProgress("Testing direct bypass...") end
    table.insert(allResults, TestsBasic.TestDirectBypass(remoteEvent))
    wait(0.5)
    if onProgress then onProgress("Testing rate limits...") end
    table.insert(allResults, TestsBasic.TestRateLimit(remoteEvent, 50))
    wait(0.5)
    if onProgress then onProgress("Testing nil arguments...") end
    table.insert(allResults, TestsBasic.TestNilArguments(remoteEvent))
    wait(0.5)
    if onProgress then onProgress("Testing type confusion...") end
    table.insert(allResults, TestsBasic.TestBooleanConfusion(remoteEvent))
    wait(0.5)
    return allResults
end

local TestsAdvanced = {}

function TestsAdvanced.TestNegativeValues(remoteEvent)
    local result = { TestName = "Negative Value Exploit", EventPath = remoteEvent.Path, Severity = nil, Success = false, Details = "" }
    local negativeTests = {-1, -100, -999999, {amount = -500}, {price = -1000, quantity = -10}}
    local successCount = 0
    for _, testValue in ipairs(negativeTests) do
        local success = pcall(function()
            remoteEvent.Instance:FireServer(testValue)
        end)
        if success then
            successCount = successCount + 1
        end
    end
    if successCount >= 4 then
        result.Success = true
        result.Severity = SEVERITY.CRITICAL
        result.Details = "CRITICAL: Accepts negative values! Possible economy exploit (negative prices/amounts)"
    elseif successCount > 0 then
        result.Success = true
        result.Severity = SEVERITY.HIGH
        result.Details = "HIGH: Accepts some negative values (" .. successCount .. "/5)"
    else
        result.Success = false
        result.Severity = SEVERITY.SAFE
        result.Details = "SAFE: Negative values rejected"
    end
    return result
end

function TestsAdvanced.TestTypeConfusion(remoteEvent)
    local result = { TestName = "Type Confusion", EventPath = remoteEvent.Path, Severity = nil, Success = false, Details = "" }
    local typeTests = {
        {expected = "string", sent = 12345},
        {expected = "number", sent = "12345"},
        {expected = "table", sent = "not_a_table"},
        {expected = "boolean", sent = "true"},
        {expected = "Instance", sent = "Instance"}
    }
    local vulnerableCount = 0
    for _, test in ipairs(typeTests) do
        local success = pcall(function()
            remoteEvent.Instance:FireServer(test.sent)
        end)
        if success then
            vulnerableCount = vulnerableCount + 1
        end
    end
    if vulnerableCount >= 4 then
        result.Success = true
        result.Severity = SEVERITY.HIGH
        result.Details = "HIGH: No type validation - accepts any data type"
    elseif vulnerableCount > 2 then
        result.Success = true
        result.Severity = SEVERITY.MEDIUM
        result.Details = "MEDIUM: Weak type validation (" .. vulnerableCount .. "/5 wrong types accepted)"
    else
        result.Success = false
        result.Severity = SEVERITY.LOW
        result.Details = "LOW: Type validation present"
    end
    return result
end

function TestsAdvanced.TestStringOverflow(remoteEvent)
    local result = { TestName = "String Overflow", EventPath = remoteEvent.Path, Severity = nil, Success = false, Details = "" }
    local smallString = string.rep("A", 1000)
    local mediumString = string.rep("B", 10000)
    local largeString = string.rep("C", 50000)
    local success1 = pcall(function()
        remoteEvent.Instance:FireServer(smallString)
    end)
    local success2 = pcall(function()
        remoteEvent.Instance:FireServer(mediumString)
    end)
    local success3 = pcall(function()
        remoteEvent.Instance:FireServer(largeString)
    end)
    if success1 and success2 and success3 then
        result.Success = true
        result.Severity = SEVERITY.CRITICAL
        result.Details = "CRITICAL: No string length validation! Accepts 50KB+ strings (DoS risk)"
    elseif success1 and success2 then
        result.Success = true
        result.Severity = SEVERITY.MEDIUM
        result.Details = "MEDIUM: Accepts strings up to 10KB (potential DoS)"
    elseif success1 then
        result.Success = false
        result.Severity = SEVERITY.LOW
        result.Details = "LOW: Loose length limit (accepts 1KB strings)"
    else
        result.Success = false
        result.Severity = SEVERITY.SAFE
        result.Details = "SAFE: String length validated"
    end
    return result
end

function TestsAdvanced.TestTableInjection(remoteEvent)
    local result = { TestName = "Table Injection", EventPath = remoteEvent.Path, Severity = nil, Success = false, Details = "" }
    local maliciousTables = {
        {__index = function() end},
        {data = string.rep("x", 10000)},
        {nested = {nested = {nested = {nested = {}}}}},
    }
    local successCount = 0
    for _, malTable in ipairs(maliciousTables) do
        local success = pcall(function()
            remoteEvent.Instance:FireServer(malTable)
        end)
        if success then
            successCount = successCount + 1
        end
    end
    if successCount >= 2 then
        result.Success = true
        result.Severity = SEVERITY.HIGH
        result.Details = "HIGH: Accepts malformed tables without validation"
    elseif successCount > 0 then
        result.Success = true
        result.Severity = SEVERITY.MEDIUM
        result.Details = "MEDIUM: Some table validation present"
    else
        result.Success = false
        result.Severity = SEVERITY.SAFE
        result.Details = "SAFE: Table validation working"
    end
    return result
end

function TestsAdvanced.RunAllTests(remoteEvent, onProgress)
    local allResults = {}
    if onProgress then onProgress("Testing negative value exploit...") end
    table.insert(allResults, TestsAdvanced.TestNegativeValues(remoteEvent))
    wait(0.5)
    if onProgress then onProgress("Testing type confusion...") end
    table.insert(allResults, TestsAdvanced.TestTypeConfusion(remoteEvent))
    wait(0.5)
    if onProgress then onProgress("Testing string overflow...") end
    table.insert(allResults, TestsAdvanced.TestStringOverflow(remoteEvent))
    wait(0.5)
    if onProgress then onProgress("Testing table injection...") end
    table.insert(allResults, TestsAdvanced.TestTableInjection(remoteEvent))
    wait(0.5)
    return allResults
end

local function CreateModernGUI()
    local screenGui = Instance.new("ScreenGui")
    screenGui.Name = "ScannerGUI"
    screenGui.ResetOnSpawn = false
    screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

    local mainFrame = Instance.new("Frame")
    mainFrame.Size = UDim2.new(0, 480, 0, 420)
    mainFrame.Position = UDim2.new(0.5, -240, 0.5, -210)
    mainFrame.BackgroundColor3 = Color3.fromRGB(15, 23, 42)
    mainFrame.BorderSizePixel = 0
    mainFrame.ClipsDescendants = true
    mainFrame.Parent = screenGui

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 12)
    corner.Parent = mainFrame

    local shadow = Instance.new("Frame")
    shadow.Size = UDim2.new(1, 0, 1, 0)
    shadow.Position = UDim2.new(0, 0, 0, 0)
    shadow.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
    shadow.BackgroundTransparency = 0.85
    shadow.BorderSizePixel = 0
    shadow.ZIndex = -1
    shadow.Parent = mainFrame

    local header = Instance.new("Frame")
    header.Size = UDim2.new(1, 0, 0, 50)
    header.BackgroundColor3 = Color3.fromRGB(30, 41, 59)
    header.BorderSizePixel = 0
    header.Active = true
    header.Parent = mainFrame

    local headerCorner = Instance.new("UICorner")
    headerCorner.CornerRadius = UDim.new(0, 12)
    headerCorner.Parent = header

    local dragging = false
    local mousePos, framePos

    header.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            local target = game:GetService("Players").LocalPlayer:GetMouse().Target
            if target and (target:IsA("TextButton") or (target.Parent and target.Parent:IsA("TextButton"))) then
                return
            end
            dragging = true
            mousePos = input.Position
            framePos = mainFrame.Position
        end
    end)

    header.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging = false
        end
    end)

    game:GetService("UserInputService").InputChanged:Connect(function(input)
        if dragging and input.UserInputType == Enum.UserInputType.MouseMovement then
            local delta = input.Position - mousePos
            mainFrame.Position = UDim2.new(framePos.X.Scale, framePos.X.Offset + delta.X, framePos.Y.Scale, framePos.Y.Offset + delta.Y)
        end
    end)

    local icon = Instance.new("TextLabel")
    icon.Size = UDim2.new(0, 40, 1, 0)
    icon.Position = UDim2.new(0, 10, 0, 0)
    icon.BackgroundTransparency = 1
    icon.Text = "🛡️"
    icon.TextColor3 = Color3.fromRGB(96, 165, 250)
    icon.TextSize = 22
    icon.Font = Enum.Font.GothamBold
    icon.TextXAlignment = Enum.TextXAlignment.Center
    icon.Parent = header

    local title = Instance.new("TextLabel")
    title.Size = UDim2.new(1, -130, 1, 0)
    title.Position = UDim2.new(0, 55, 0, 0)
    title.BackgroundTransparency = 1
    title.Text = "Security Scanner"
    title.TextColor3 = Color3.fromRGB(241, 245, 249)
    title.TextSize = 17
    title.Font = Enum.Font.GothamBold
    title.TextXAlignment = Enum.TextXAlignment.Left
    title.Parent = header

    local versionLabel = Instance.new("TextLabel")
    versionLabel.Size = UDim2.new(0, 50, 0, 16)
    versionLabel.Position = UDim2.new(0, 55, 0, 28)
    versionLabel.BackgroundTransparency = 1
    versionLabel.Text = "v2.0"
    versionLabel.TextColor3 = Color3.fromRGB(148, 163, 184)
    versionLabel.TextSize = 10
    versionLabel.Font = Enum.Font.Gotham
    versionLabel.TextXAlignment = Enum.TextXAlignment.Left
    versionLabel.Parent = header

    local minimizeBtn = Instance.new("TextButton")
    minimizeBtn.Size = UDim2.new(0, 32, 0, 32)
    minimizeBtn.Position = UDim2.new(1, -74, 0, 9)
    minimizeBtn.BackgroundColor3 = Color3.fromRGB(30, 41, 59)
    minimizeBtn.Text = "−"
    minimizeBtn.TextColor3 = Color3.fromRGB(148, 163, 184)
    minimizeBtn.TextSize = 20
    minimizeBtn.Font = Enum.Font.GothamBold
    minimizeBtn.Parent = header

    local isMinimized = false

    minimizeBtn.MouseButton1Click:Connect(function()
        isMinimized = not isMinimized
        if isMinimized then
            mainFrame:TweenSize(UDim2.new(0, 480, 0, 50), Enum.EasingDirection.Out, Enum.EasingStyle.Quad, 0.2, true)
            minimizeBtn.Text = "+"
        else
            mainFrame:TweenSize(UDim2.new(0, 480, 0, 420), Enum.EasingDirection.Out, Enum.EasingStyle.Quad, 0.2, true)
            minimizeBtn.Text = "−"
        end
    end)

    local closeBtn = Instance.new("TextButton")
    closeBtn.Size = UDim2.new(0, 32, 0, 32)
    closeBtn.Position = UDim2.new(1, -38, 0, 9)
    closeBtn.BackgroundColor3 = Color3.fromRGB(30, 41, 59)
    closeBtn.Text = "✕"
    closeBtn.TextColor3 = Color3.fromRGB(148, 163, 184)
    closeBtn.TextSize = 16
    closeBtn.Font = Enum.Font.GothamBold
    closeBtn.Parent = header
    closeBtn.MouseButton1Click:Connect(function()
        screenGui:Destroy()
    end)

    local contentContainer = Instance.new("Frame")
    contentContainer.Name = "ContentContainer"
    contentContainer.Size = UDim2.new(1, 0, 1, -50)
    contentContainer.Position = UDim2.new(0, 0, 0, 50)
    contentContainer.BackgroundTransparency = 1
    contentContainer.Parent = mainFrame

    local statsPanel = Instance.new("Frame")
    statsPanel.Size = UDim2.new(1, -24, 0, 56)
    statsPanel.Position = UDim2.new(0, 12, 0, 12)
    statsPanel.BackgroundColor3 = Color3.fromRGB(30, 41, 59)
    statsPanel.BorderSizePixel = 0
    statsPanel.Parent = contentContainer

    local statsCorner = Instance.new("UICorner")
    statsCorner.CornerRadius = UDim.new(0, 8)
    statsCorner.Parent = statsPanel

    local statLabels = {"Critical", "High", "Medium", "Low", "Safe"}
    local statColors = {
        Color3.fromRGB(239, 68, 68),
        Color3.fromRGB(251, 146, 60),
        Color3.fromRGB(250, 204, 21),
        Color3.fromRGB(132, 204, 22),
        Color3.fromRGB(34, 197, 94)
    }
    local statIcons = {"🔴", "🟠", "🟡", "🟢", "✅"}

    for i, label in ipairs(statLabels) do
        local statFrame = Instance.new("Frame")
        statFrame.Name = label .. "Stat"
        statFrame.Size = UDim2.new(0.2, -4, 1, -8)
        statFrame.Position = UDim2.new((i-1) * 0.2, 2, 0, 4)
        statFrame.BackgroundColor3 = Color3.fromRGB(15, 23, 42)
        statFrame.BorderSizePixel = 0
        statFrame.Parent = statsPanel

        local statCorner = Instance.new("UICorner")
        statCorner.CornerRadius = UDim.new(0, 6)
        statCorner.Parent = statFrame

        local statCount = Instance.new("TextLabel")
        statCount.Name = "Count"
        statCount.Size = UDim2.new(1, 0, 0.5, -2)
        statCount.Position = UDim2.new(0, 0, 0, 2)
        statCount.BackgroundTransparency = 1
        statCount.Text = "0"
        statCount.TextColor3 = statColors[i]
        statCount.TextSize = 18
        statCount.Font = Enum.Font.GothamBold
        statCount.Parent = statFrame

        local statLabel = Instance.new("TextLabel")
        statLabel.Size = UDim2.new(1, 0, 0.5, -2)
        statLabel.Position = UDim2.new(0, 0, 0.5, 0)
        statLabel.BackgroundTransparency = 1
        statLabel.Text = statIcons[i] .. " " .. label
        statLabel.TextColor3 = Color3.fromRGB(148, 163, 184)
        statLabel.TextSize = 9
        statLabel.Font = Enum.Font.Gotham
        statLabel.Parent = statFrame
    end

    local progressContainer = Instance.new("Frame")
    progressContainer.Size = UDim2.new(1, -24, 0, 28)
    progressContainer.Position = UDim2.new(0, 12, 0, 78)
    progressContainer.BackgroundColor3 = Color3.fromRGB(30, 41, 59)
    progressContainer.BorderSizePixel = 0
    progressContainer.Parent = contentContainer

    local progressCorner = Instance.new("UICorner")
    progressCorner.CornerRadius = UDim.new(0, 8)
    progressCorner.Parent = progressContainer

    local progressBar = Instance.new("Frame")
    progressBar.Size = UDim2.new(0, 0, 1, 0)
    progressBar.BackgroundColor3 = Color3.fromRGB(96, 165, 250)
    progressBar.BorderSizePixel = 0
    progressBar.Parent = progressContainer

    local progressBarCorner = Instance.new("UICorner")
    progressBarCorner.CornerRadius = UDim.new(0, 8)
    progressBarCorner.Parent = progressBar

    local progressText = Instance.new("TextLabel")
    progressText.Size = UDim2.new(1, 0, 1, 0)
    progressText.BackgroundTransparency = 1
    progressText.Text = "Ready"
    progressText.TextColor3 = Color3.fromRGB(241, 245, 249)
    progressText.TextSize = 11
    progressText.Font = Enum.Font.GothamBold
    progressText.ZIndex = 2
    progressText.Parent = progressContainer

    local statusIcon = Instance.new("TextLabel")
    statusIcon.Size = UDim2.new(0, 24, 1, 0)
    statusIcon.Position = UDim2.new(0, 10, 0, 0)
    statusIcon.BackgroundTransparency = 1
    statusIcon.Text = "●"
    statusIcon.TextColor3 = Color3.fromRGB(96, 165, 250)
    statusIcon.TextSize = 10
    statusIcon.Font = Enum.Font.GothamBold
    statusIcon.Parent = contentContainer

    local statusLabel = Instance.new("TextLabel")
    statusLabel.Size = UDim2.new(1, -40, 0, 22)
    statusLabel.Position = UDim2.new(0, 38, 0, 118)
    statusLabel.BackgroundTransparency = 1
    statusLabel.Text = "Click START SCAN to begin"
    statusLabel.TextColor3 = Color3.fromRGB(148, 163, 184)
    statusLabel.TextSize = 12
    statusLabel.Font = Enum.Font.Gotham
    statusLabel.TextXAlignment = Enum.TextXAlignment.Left
    statusLabel.Parent = contentContainer

    local resultsFrame = Instance.new("ScrollingFrame")
    resultsFrame.Size = UDim2.new(1, -24, 1, -215)
    resultsFrame.Position = UDim2.new(0, 12, 0, 150)
    resultsFrame.BackgroundColor3 = Color3.fromRGB(30, 41, 59)
    resultsFrame.BorderSizePixel = 0
    resultsFrame.ScrollBarThickness = 5
    resultsFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
    resultsFrame.Parent = contentContainer

    local resultsCorner = Instance.new("UICorner")
    resultsCorner.CornerRadius = UDim.new(0, 8)
    resultsCorner.Parent = resultsFrame

    local buttonPanel = Instance.new("Frame")
    buttonPanel.Size = UDim2.new(1, -24, 0, 44)
    buttonPanel.Position = UDim2.new(0, 12, 1, -54)
    buttonPanel.BackgroundTransparency = 1
    buttonPanel.Parent = contentContainer

    local startBtn = Instance.new("TextButton")
    startBtn.Size = UDim2.new(0.6, -6, 1, 0)
    startBtn.Position = UDim2.new(0, 0, 0, 0)
    startBtn.BackgroundColor3 = Color3.fromRGB(96, 165, 250)
    startBtn.Text = "▶ START SCAN"
    startBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
    startBtn.TextSize = 14
    startBtn.Font = Enum.Font.GothamBold
    startBtn.Parent = buttonPanel

    local startCorner = Instance.new("UICorner")
    startCorner.CornerRadius = UDim.new(0, 8)
    startCorner.Parent = startBtn

    local exportBtn = Instance.new("TextButton")
    exportBtn.Size = UDim2.new(0.4, -6, 1, 0)
    exportBtn.Position = UDim2.new(0.6, 6, 0, 0)
    exportBtn.BackgroundColor3 = Color3.fromRGB(51, 65, 85)
    exportBtn.Text = "📋 EXPORT"
    exportBtn.TextColor3 = Color3.fromRGB(241, 245, 249)
    exportBtn.TextSize = 13
    exportBtn.Font = Enum.Font.GothamBold
    exportBtn.Parent = buttonPanel

    local exportCorner = Instance.new("UICorner")
    exportCorner.CornerRadius = UDim.new(0, 8)
    exportCorner.Parent = exportBtn

    screenGui.Parent = game:GetService("CoreGui")
    if not screenGui.Parent then
        local Players = game:GetService("Players")
        if Players.LocalPlayer then
            screenGui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
        end
    end

    return {
        ScreenGui = screenGui,
        MainFrame = mainFrame,
        StatusLabel = statusLabel,
        ResultsFrame = resultsFrame,
        StartButton = startBtn,
        ExportButton = exportBtn,
        ProgressBar = progressBar,
        ProgressText = progressText,
        StatsPanel = statsPanel,
        StatusIcon = statusIcon,
        ContentContainer = contentContainer,
        MinimizeBtn = minimizeBtn,
        isMinimized = isMinimized
    }
end

local gui = CreateModernGUI()
local isScanning = false
local currentResults = {}
local statsCounters = {Critical = 0, High = 0, Medium = 0, Low = 0, Safe = 0}

local function UpdateStatus(text)
    gui.StatusLabel.Text = text
end

local function UpdateProgress(current, total, text)
    local percentage = math.floor((current / total) * 100)
    gui.ProgressBar:TweenSize(UDim2.new(percentage / 100, 0, 1, 0), Enum.EasingDirection.Out, Enum.EasingStyle.Quad, 0.4, true)
    gui.ProgressText.Text = text or string.format("%d%% (%d/%d)", percentage, current, total)
end

local function UpdateStats(severity)
    if statsCounters[severity] then
        statsCounters[severity] = statsCounters[severity] + 1
        local statFrame = gui.StatsPanel:FindFirstChild(severity .. "Stat")
        if statFrame then
            local countLabel = statFrame:FindFirstChild("Count")
            if countLabel then
                countLabel.Text = tostring(statsCounters[severity])
            end
        end
    end
end

local function ResetStats()
    for key in pairs(statsCounters) do
        statsCounters[key] = 0
    end
    for _, child in ipairs(gui.StatsPanel:GetChildren()) do
        if child:IsA("Frame") then
            local countLabel = child:FindFirstChild("Count")
            if countLabel then
                countLabel.Text = "0"
            end
        end
    end
end

local function AddResultToUI(eventName, testResult)
    table.insert(currentResults, {event = eventName, result = testResult})
    UpdateStats(testResult.Severity)
    
    local resultFrame = Instance.new("Frame")
    resultFrame.Size = UDim2.new(1, -10, 0, 65)
    resultFrame.BackgroundColor3 = Color3.fromRGB(15, 23, 42)
    resultFrame.BorderSizePixel = 1
    resultFrame.BorderColor3 = Color3.fromRGB(51, 65, 85)
    resultFrame.Parent = gui.ResultsFrame
    
    local resultCorner = Instance.new("UICorner")
    resultCorner.CornerRadius = UDim.new(0, 6)
    resultCorner.Parent = resultFrame
    
    local severityBar = Instance.new("Frame")
    severityBar.Size = UDim2.new(0, 4, 1, 0)
    severityBar.BorderSizePixel = 0
    severityBar.Parent = resultFrame
    
    local severityColor = Color3.fromRGB(148, 163, 184)
    if testResult.Severity == "CRITICAL" then
        severityColor = Color3.fromRGB(239, 68, 68)
    elseif testResult.Severity == "HIGH" then
        severityColor = Color3.fromRGB(251, 146, 60)
    elseif testResult.Severity == "MEDIUM" then
        severityColor = Color3.fromRGB(250, 204, 21)
    elseif testResult.Severity == "LOW" then
        severityColor = Color3.fromRGB(132, 204, 22)
    elseif testResult.Severity == "SAFE" then
        severityColor = Color3.fromRGB(34, 197, 94)
    end
    severityBar.BackgroundColor3 = severityColor
    
    local severityBarCorner = Instance.new("UICorner")
    severityBarCorner.CornerRadius = UDim.new(0, 4)
    severityBarCorner.Parent = severityBar
    
    local eventLabel = Instance.new("TextLabel")
    eventLabel.Size = UDim2.new(1, -75, 0, 20)
    eventLabel.Position = UDim2.new(0, 12, 0, 4)
    eventLabel.BackgroundTransparency = 1
    eventLabel.Text = eventName .. " • " .. testResult.TestName
    eventLabel.TextColor3 = Color3.fromRGB(241, 245, 249)
    eventLabel.TextSize = 11
    eventLabel.Font = Enum.Font.GothamBold
    eventLabel.TextXAlignment = Enum.TextXAlignment.Left
    eventLabel.Parent = resultFrame
    
    local severityBadge = Instance.new("TextLabel")
    severityBadge.Size = UDim2.new(0, 55, 0, 16)
    severityBadge.Position = UDim2.new(1, -62, 0, 5)
    severityBadge.BackgroundColor3 = severityColor
    severityBadge.Text = testResult.Severity
    severityBadge.TextColor3 = Color3.fromRGB(255, 255, 255)
    severityBadge.TextSize = 8
    severityBadge.Font = Enum.Font.GothamBold
    severityBadge.Parent = resultFrame
    
    local badgeCorner = Instance.new("UICorner")
    badgeCorner.CornerRadius = UDim.new(0, 4)
    badgeCorner.Parent = severityBadge
    
    local testLabel = Instance.new("TextLabel")
    testLabel.Size = UDim2.new(1, -15, 0, 32)
    testLabel.Position = UDim2.new(0, 12, 0, 26)
    testLabel.BackgroundTransparency = 1
    testLabel.Text = testResult.Details
    testLabel.TextColor3 = Color3.fromRGB(203, 213, 225)
    testLabel.TextSize = 9
    testLabel.Font = Enum.Font.Gotham
    testLabel.TextXAlignment = Enum.TextXAlignment.Left
    testLabel.TextYAlignment = Enum.TextYAlignment.Top
    testLabel.TextWrapped = true
    testLabel.Parent = resultFrame
    
    local listLayout = gui.ResultsFrame:FindFirstChild("UIListLayout")
    if not listLayout then
        listLayout = Instance.new("UIListLayout")
        listLayout.Padding = UDim.new(0, 6)
        listLayout.Parent = gui.ResultsFrame
    end
    gui.ResultsFrame.CanvasSize = UDim2.new(0, 0, 0, listLayout.AbsoluteContentSize.Y)
end

gui.StartButton.MouseButton1Click:Connect(function()
    if isScanning then
        return
    end
    isScanning = true
    gui.StartButton.Text = "⏳ SCANNING..."
    gui.StartButton.BackgroundColor3 = Color3.fromRGB(251, 146, 60)
    ResetStats()
    currentResults = {}
    UpdateProgress(0, 100, "Initializing...")
    for _, child in ipairs(gui.ResultsFrame:GetChildren()) do
        if child:IsA("Frame") then
            child:Destroy()
        end
    end
    UpdateStatus("Phase 1: Discovering RemoteEvents...")
    UpdateProgress(10, 100, "Scanning for remotes...")
    wait(1)
    local scanResults = CoreScanner.ScanAllRemotes()
    CoreScanner.PrintSummary()
    if scanResults.Results.TotalEvents == 0 then
        UpdateStatus("No RemoteEvents found!")
        gui.StartButton.Text = "▶ START SCAN"
        gui.StartButton.BackgroundColor3 = Color3.fromRGB(96, 165, 250)
        isScanning = false
        return
    end
    UpdateStatus("Found " .. scanResults.Results.TotalEvents .. " RemoteEvents. Running tests...")
    wait(1)
    local totalVulnerabilities = 0
    for i, remoteEvent in ipairs(scanResults.Events) do
        UpdateStatus("Testing [" .. i .. "/" .. #scanResults.Events .. "]: " .. remoteEvent.Name)
        UpdateProgress(20 + (i * 70 / #scanResults.Events), 100, "Testing " .. i .. "/" .. #scanResults.Events)
        local basicResults = TestsBasic.RunAllTests(remoteEvent, UpdateStatus)
        for _, result in ipairs(basicResults) do
            if result.Success then
                totalVulnerabilities = totalVulnerabilities + 1
            end
            AddResultToUI(remoteEvent.Name, result)
        end
        local advancedResults = TestsAdvanced.RunAllTests(remoteEvent, UpdateStatus)
        for _, result in ipairs(advancedResults) do
            if result.Success then
                totalVulnerabilities = totalVulnerabilities + 1
            end
            AddResultToUI(remoteEvent.Name, result)
        end
        wait(0.3)
    end
    UpdateProgress(100, 100, "Complete!")
    UpdateStatus("Done! Found " .. totalVulnerabilities .. " vulnerabilities in " .. scanResults.Results.TotalEvents .. " events")
    gui.StartButton.Text = "🔄 NEW SCAN"
    gui.StartButton.BackgroundColor3 = Color3.fromRGB(34, 197, 94)
    isScanning = false
end)

gui.ExportButton.MouseButton1Click:Connect(function()
    if #currentResults == 0 then
        UpdateStatus("No results to export. Run a scan first.")
        return
    end
    local report = "═══════════════════════════════════════\n"
    report = report .. "  SECURITY SCANNER - EXPORT REPORT\n"
    report = report .. "═══════════════════════════════════════\n"
    report = report .. "Generated: " .. os.date("%Y-%m-%d %H:%M:%S") .. "\n"
    report = report .. "Total Results: " .. #currentResults .. "\n"
    report = report .. "Critical: " .. statsCounters.Critical .. " | High: " .. statsCounters.High .. " | Medium: " .. statsCounters.Medium .. " | Low: " .. statsCounters.Low .. " | Safe: " .. statsCounters.Safe .. "\n"
    report = report .. "═══════════════════════════════════════\n\n"
    for i, entry in ipairs(currentResults) do
        report = report .. "[" .. i .. "] " .. entry.event .. "\n"
        report = report .. "    Test: " .. entry.result.TestName .. "\n"
        report = report .. "    Severity: " .. entry.result.Severity .. "\n"
        report = report .. "    " .. entry.result.Details .. "\n\n"
    end
    if setclipboard then
        setclipboard(report)
        UpdateStatus("Report exported to clipboard!")
    else
        UpdateStatus("Clipboard not supported. Report printed to console.")
    end
end)

print("Scanner ready! Click START SCAN")