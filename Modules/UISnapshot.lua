--[[
    UISnapshot.lua

    Development aid: /wim snap serializes the live widget state of the frames
    being styled -- every region's resolved rectangle, anchors, texture/atlas,
    texcoords, colors and fonts -- into a SavedVariable, and captures a
    screenshot of the same moment. Comparing the dump of a WIM frame against
    the dump of the native frame it is modeled on turns skin work into a
    numeric diff instead of a visual guess.

    /wim snap                 - print the available arguments.
    /wim snap all             - snapshot everything WIM styles: every
                                message window (shown or hidden), the
                                History Viewer, the classic options
                                window and the native reference
                                widgets, so nothing is missing from
                                the captured state.
    /wim snap <Dot.Path>      - snapshot one frame by global dot-path,
                                e.g. /wim snap SettingsPanel.Bg

    The data lands in WIM3_Snapshots (per character) and is written to disk
    on /reload or logout, like any SavedVariable. The screenshot is written
    immediately to the game's Screenshots folder.
]]

local _G = getfenv(0);
local pairs, ipairs = pairs, ipairs;
local type, tostring = type, tostring;
local pcall = pcall;
local table, string, math = table, string, math;

setfenv(1, WIM);

-- The fixed targets of /wim snap all: the styled panels, plus the
-- native widgets the styles are modeled on (the Settings panel's list
-- scrollbar, corner close button, and search box).
local fixedTargets = {
    "WIM3_HistoryFrame",
    "WIM3_Options",
    "WIM3Menu",
    "WIM_LastModernMenu",
    "LibDBIcon10_WIM",
    "SettingsPanel.Container.SettingsList.ScrollBar",
    "SettingsPanel.ClosePanelButton",
    "SettingsPanel.SearchBox",
};

-- Everything /wim snap all captures: every live message window of
-- every type, shown or hidden, with its whole widget tree, then the
-- fixed list above.
local function collectAllTargets()
    local list = {};
    for _, winType in ipairs({ "whisper", "chat", "w2w" }) do
        local set = windows.active[winType];
        if(type(set) == "table") then
            for _, win in pairs(set) do
                if(type(win) == "table" and win.GetName and win:GetName()) then
                    table.insert(list, win:GetName());
                end
            end
        end
    end
    for i=1, #fixedTargets do
        table.insert(list, fixedTargets[i]);
    end
    return list;
end

local MAX_DEPTH = 15;
local MAX_NODES = 4000;
local KEPT_SNAPSHOTS = 3;

local function rnd(v)
    if (type(v) ~= "number") then return v; end
    return math.floor(v * 100 + 0.5) / 100;
end

-- Resolves "SettingsPanel.Container.SettingsList.ScrollBar" from _G.
local function resolvePath(path)
    local obj = _G;
    for key in string.gmatch(path, "[^%.]+") do
        local ok, value = pcall(function() return obj[key]; end);
        if (not ok or value == nil) then
            return nil;
        end
        obj = value;
    end
    return obj;
end

-- Best available identifier for a region: global name, or the field name it
-- occupies on its parent (its parentKey), or just its type.
local function describeRegion(obj, parent)
    local ok, name = pcall(obj.GetName, obj);
    if (ok and name) then return name; end
    if (parent) then
        local found;
        pcall(function()
            for k, v in pairs(parent) do
                if (v == obj and type(k) == "string") then
                    found = "."..k;
                    return;
                end
            end
        end);
        if (found) then return found; end
    end
    local okT, objType = pcall(obj.GetObjectType, obj);
    return "<"..(okT and objType or "?")..">";
end

local function grabAnchors(obj)
    local anchors = {};
    local ok, count = pcall(obj.GetNumPoints, obj);
    if (not ok or not count) then return anchors; end
    for i = 1, count do
        local okP, point, relativeTo, relativePoint, x, y = pcall(obj.GetPoint, obj, i);
        if (okP and point) then
            local relName;
            if (relativeTo) then
                local okN, n = pcall(relativeTo.GetName, relativeTo);
                relName = (okN and n) or describeRegion(relativeTo);
            end
            table.insert(anchors, {
                point = point, relTo = relName, relPoint = relativePoint,
                x = rnd(x), y = rnd(y),
            });
        end
    end
    return anchors;
end

local function grabRect(obj, node)
    local ok, left, bottom, width, height = pcall(obj.GetRect, obj);
    if (ok and left) then
        node.rect = { left = rnd(left), bottom = rnd(bottom), w = rnd(width), h = rnd(height) };
    end
    -- GetScaledRect resolves to screen coordinates (UIParent space), which is
    -- what makes rects from differently-scaled frames directly comparable.
    local okS, sLeft, sBottom, sWidth, sHeight = pcall(obj.GetScaledRect, obj);
    if (okS and sLeft) then
        node.scaledRect = { left = rnd(sLeft), bottom = rnd(sBottom), w = rnd(sWidth), h = rnd(sHeight) };
    end
    local okE, scale = pcall(obj.GetEffectiveScale, obj);
    if (okE and scale) then node.effScale = rnd(scale); end
end

local function grabTexture(obj, node)
    local ok, atlas = pcall(obj.GetAtlas, obj);
    if (ok and atlas) then node.atlas = atlas; end
    local okT, tex = pcall(obj.GetTexture, obj);
    if (okT and tex ~= nil) then node.texture = tostring(tex); end
    local okC, ULx, ULy, LLx, LLy, URx, URy, LRx, LRy = pcall(obj.GetTexCoord, obj);
    if (okC and ULx) then
        node.texCoord = { rnd(ULx), rnd(ULy), rnd(LLx), rnd(LLy), rnd(URx), rnd(URy), rnd(LRx), rnd(LRy) };
    end
    local okV, r, g, b, a = pcall(obj.GetVertexColor, obj);
    if (okV and r) then node.vertexColor = { rnd(r), rnd(g), rnd(b), rnd(a) }; end
    local okB, blend = pcall(obj.GetBlendMode, obj);
    if (okB and blend and blend ~= "BLEND") then node.blendMode = blend; end
    local okD, desat = pcall(obj.GetDesaturation, obj);
    if (okD and desat and desat > 0) then node.desaturation = rnd(desat); end
    local okL, layer, subLevel = pcall(obj.GetDrawLayer, obj);
    if (okL and layer) then node.drawLayer = layer.."/"..tostring(subLevel); end
    if (obj.GetNumMaskTextures) then
        local okM, masks = pcall(obj.GetNumMaskTextures, obj);
        if (okM and masks and masks > 0) then node.maskTextures = masks; end
    end
end

local function grabFontString(obj, node)
    local ok, fontPath, fontHeight, fontFlags = pcall(obj.GetFont, obj);
    if (ok and fontPath) then
        node.font = { path = tostring(fontPath), height = rnd(fontHeight), flags = fontFlags or "" };
    end
    local okT, text = pcall(obj.GetText, obj);
    if (okT and text and text ~= "") then node.text = string.sub(text, 1, 60); end
    local okC, r, g, b, a = pcall(obj.GetTextColor, obj);
    if (okC and r) then node.textColor = { rnd(r), rnd(g), rnd(b), rnd(a) }; end
end

local function grabSlider(obj, node)
    local ok, minVal, maxVal = pcall(obj.GetMinMaxValues, obj);
    if (ok and minVal) then node.sliderRange = { rnd(minVal), rnd(maxVal) }; end
    local okV, value = pcall(obj.GetValue, obj);
    if (okV and value) then node.sliderValue = rnd(value); end
end

local function snapRegion(obj, parent, depth, budget)
    if (depth > MAX_DEPTH or budget.nodes <= 0) then
        budget.truncated = true;
        return nil;
    end
    budget.nodes = budget.nodes - 1;

    local okF, forbidden = pcall(obj.IsForbidden, obj);
    if (okF and forbidden) then
        return { id = "<forbidden>" };
    end

    local node = { id = describeRegion(obj, parent) };
    local okT, objType = pcall(obj.GetObjectType, obj);
    if (okT) then node.type = objType; end

    local okS, shown = pcall(obj.IsShown, obj);
    if (okS) then node.shown = shown and true or false; end
    local okV, visible = pcall(obj.IsVisible, obj);
    if (okV and shown and not visible) then node.hiddenByParent = true; end
    local okA, alpha = pcall(obj.GetAlpha, obj);
    if (okA and alpha and alpha < 1) then node.alpha = rnd(alpha); end

    grabRect(obj, node);
    node.anchors = grabAnchors(obj);

    if (objType == "Texture" or objType == "MaskTexture" or objType == "Line") then
        grabTexture(obj, node);
    elseif (objType == "FontString") then
        grabFontString(obj, node);
    elseif (objType == "Slider") then
        grabSlider(obj, node);
    end

    if (obj.DoesClipChildren) then
        local okCC, clips = pcall(obj.DoesClipChildren, obj);
        if (okCC and clips) then node.clipsChildren = true; end
    end
    if (obj.GetFrameLevel) then
        local okL, level = pcall(obj.GetFrameLevel, obj);
        if (okL) then node.frameLevel = level; end
    end

    -- Layered regions (textures, fontstrings), then child frames.
    if (obj.GetRegions) then
        local okR, regions = pcall(function() return { obj:GetRegions() }; end);
        if (okR) then
            for _, region in ipairs(regions) do
                local child = snapRegion(region, obj, depth + 1, budget);
                if (child) then
                    node.regions = node.regions or {};
                    table.insert(node.regions, child);
                end
            end
        end
    end
    if (obj.GetChildren) then
        local okC, children = pcall(function() return { obj:GetChildren() }; end);
        if (okC) then
            for _, childFrame in ipairs(children) do
                local child = snapRegion(childFrame, obj, depth + 1, budget);
                if (child) then
                    node.children = node.children or {};
                    table.insert(node.children, child);
                end
            end
        end
    end

    return node;
end

local function takeSnapshot(args)
    local targets;
    args = args and string.trim(args) or "";
    if (args == "") then
        local msg = _G.DEFAULT_CHAT_FRAME;
        msg:AddMessage("|cff69ccf0WIM:|r /wim snap arguments:");
        msg:AddMessage("  |cffffffffall|r - capture everything WIM styles:"
            .." every message window (shown or hidden), the History Viewer,"
            .." the classic options window, the last modern menu, the"
            .." minimap button and the native reference widgets.");
        msg:AddMessage("  |cffffffff<Frame.Dot.Path>|r - capture one frame"
            .." by global path, e.g. /wim snap WIM3_msgFrame1");
        msg:AddMessage("  Also: |cffffffff/wim snapmenu|r - capture the"
            .." next modern context menu while it is open.");
        return;
    elseif (string.lower(args) == "all") then
        targets = collectAllTargets();
    else
        targets = { args };
    end

    local snap = {
        taken = _G.date("%Y-%m-%d %H:%M:%S"),
        targets = {},
    };
    pcall(function()
        local version, build = _G.GetBuildInfo();
        snap.build = version.." ("..build..")";
    end);
    snap.addonBuild = FORK_BUILD or "unknown";
    pcall(function()
        local w, h = _G.GetPhysicalScreenSize();
        snap.screen = { w = w, h = h };
    end);
    pcall(function() snap.uiScale = rnd(_G.UIParent:GetEffectiveScale()); end);

    local found = 0;
    for _, path in ipairs(targets) do
        local obj = resolvePath(path);
        if (obj and type(obj) == "table" and obj.GetObjectType) then
            local budget = { nodes = MAX_NODES };
            local tree = snapRegion(obj, nil, 1, budget);
            if (budget.truncated) then tree.truncated = true; end
            snap.targets[path] = tree;
            found = found + 1;
        else
            snap.targets[path] = "not found";
        end
    end

    _G.WIM3_Snapshots = _G.WIM3_Snapshots or { snaps = {} };
    local snaps = _G.WIM3_Snapshots.snaps;
    table.insert(snaps, snap);
    while (#snaps > KEPT_SNAPSHOTS) do
        table.remove(snaps, 1);
    end

    -- Capture the frame before the confirmation text can appear in it.
    pcall(_G.Screenshot);
    local resolved = found;
    _G.C_Timer.After(0.25, function()
        _G.DEFAULT_CHAT_FRAME:AddMessage("|cff69ccf0WIM:|r snapshot captured ("
            ..resolved.."/"..#targets.." targets resolved) + screenshot."
            .." Build "..(FORK_BUILD or "unknown")..";"
            .." data flushes to WIM3_Snapshots on /reload or logout.");
    end);
end

-- Callable from elsewhere in the addon, for example to capture a
-- frame that only exists in full while something is open.
SnapshotTarget = takeSnapshot;

RegisterSlashCommand("snap", takeSnapshot,
    L["Snapshot UI widget state for skin development: /wim snap all | <Frame.Dot.Path> (bare /wim snap lists the arguments)."]);
-- Live probe for the themed input row: prints wheel deliveries,
-- REAL cursor moves (identical repeats are only counted, never
-- printed -- an event storm would flush everything else out of the
-- capped log) and a once-a-second state line with the fire and
-- setter counters, so input behavior is observed instead of
-- inferred. Run again to stop.
-- Probe lines land in chat AND in the snapshot SavedVariable, so a
-- /reload flushes them to disk like everything else.
local function probeSay(msg)
    _G.DEFAULT_CHAT_FRAME:AddMessage("|cff69ccf0WIM probe:|r "..msg);
    _G.WIM3_Snapshots = _G.WIM3_Snapshots or { snaps = {} };
    local log = _G.WIM3_Snapshots.probe;
    if (not log) then
        log = {};
        _G.WIM3_Snapshots.probe = log;
    end
    table.insert(log, _G.date("%H:%M:%S").." "..msg);
    while (#log > 300) do
        table.remove(log, 1);
    end
end

local function findCaret(box)
    for _, region in ipairs({ box:GetRegions() }) do
        if (region.GetObjectType and region:GetObjectType() == "Texture"
                and math.abs((region:GetWidth() or 0) - 2) < 1.5) then
            return region;
        end
    end
end

local function caretReport(box)
    local caret = findCaret(box);
    if (not caret) then
        return "caret not found";
    end
    local line = string.format("caret shown=%s pts=%d alpha=%s layer=%s",
        tostring(caret:IsShown()), caret:GetNumPoints(),
        tostring(rnd(caret:GetAlpha())),
        tostring(caret.GetDrawLayer and caret:GetDrawLayer()));
    local left, bottom = caret:GetLeft(), caret:GetBottom();
    if (left and bottom) then
        return line..string.format(" at (%.0f, %.0f)", left, bottom);
    end
    return line.." no rect";
end

-- Every-frame method traffic on the box, counted per second: a
-- nonzero steady count names whatever keeps the text layout dirty.
local tracedSetters = { "SetText", "SetWidth", "SetHeight",
    "SetTextInsets", "SetCursorPosition", "SetPoint", "SetAlpha" };
local function traceSetters(box)
    if (box.wimProbeCounts) then return; end
    box.wimProbeCounts = {};
    for i = 1, #tracedSetters do
        local name = tracedSetters[i];
        _G.hooksecurefunc(box, name, function(self)
            local counts = self.wimProbeCounts;
            counts[name] = (counts[name] or 0) + 1;
        end);
    end
end

local function setterReport(box)
    local counts = box.wimProbeCounts;
    if (not counts) then return ""; end
    local parts = {};
    for i = 1, #tracedSetters do
        local name = tracedSetters[i];
        if (counts[name] and counts[name] > 0) then
            table.insert(parts, name.."="..counts[name]);
            counts[name] = 0;
        end
    end
    if (#parts == 0) then return ""; end
    return " set["..table.concat(parts, " ").."]";
end

-- Control rig: a bare multi-line EditBox in a stock ScrollFrame with
-- default everything. If ITS caret renders and its OnCursorChanged
-- only fires on real moves, the client is fine and the delta to
-- WIM's box is the bug; if it misbehaves the same way, the client
-- itself does.
local labFrame;
local function toggleLab()
    if (labFrame) then
        if (labFrame:IsShown()) then
            labFrame:Hide();
            probeSay("lab hidden.");
        else
            labFrame:Show();
            labFrame.box:SetFocus();
        end
        return;
    end
    labFrame = _G.CreateFrame("Frame", "WIM3_InputLab", _G.UIParent);
    labFrame:SetSize(320, 76);
    labFrame:SetPoint("CENTER", 0, 220);
    labFrame:SetFrameStrata("DIALOG");
    local bg = labFrame:CreateTexture(nil, "BACKGROUND");
    bg:SetAllPoints();
    bg:SetColorTexture(0, 0, 0, 0.75);
    local scroll = _G.CreateFrame("ScrollFrame", nil, labFrame);
    scroll:SetPoint("TOPLEFT", 8, -8);
    scroll:SetPoint("BOTTOMRIGHT", -8, 8);
    local eb = _G.CreateFrame("EditBox", nil, scroll);
    eb:SetMultiLine(true);
    eb:SetFontObject(_G.ChatFontNormal);
    eb:SetWidth(304);
    eb:SetAutoFocus(false);
    eb:SetScript("OnEscapePressed", function(self) self:ClearFocus(); end);
    scroll:SetScrollChild(eb);
    labFrame.box = eb;
    labFrame.cc = 0;
    eb:HookScript("OnCursorChanged", function()
        labFrame.cc = labFrame.cc + 1;
    end);
    _G.C_Timer.NewTicker(1, function()
        if (not labFrame:IsShown()) then return; end
        probeSay(string.format("lab cc/s=%d focus=%s | %s",
            labFrame.cc, tostring(eb:HasFocus()), caretReport(eb)));
        labFrame.cc = 0;
    end);
    labFrame:Show();
    eb:SetFocus();
    probeSay("lab up: type in the floating box; /wim inputprobe lab"
        .." toggles it away.");
end

local probeTicker;
local function inputProbe(arg)
    if (type(arg) == "string" and string.lower(arg) == "lab") then
        toggleLab();
        return;
    end
    local say = probeSay;
    if (probeTicker) then
        probeTicker:Cancel();
        probeTicker = nil;
        say("off.");
        return;
    end
    local target;
    for _, win in pairs(windows.active.whisper) do
        if (win:IsShown() and win.wimChrome and win.wimChrome:IsShown()) then
            target = win;
            break;
        end
    end
    if (not target) then
        say("no themed whisper window is shown.");
        return;
    end
    local box = target.widgets.msg_box;
    local input = target.wimChrome.input;
    local viewport = input and input.scroll;
    if (viewport and not viewport.wimProbeHooked) then
        viewport.wimProbeHooked = true;
        viewport:HookScript("OnMouseWheel", function(_, delta)
            say("viewport wheel "..delta.." ofs="..tostring(target.wimInputScrollOfs));
        end);
    end
    if (box and not box.wimProbeHooked) then
        box.wimProbeHooked = true;
        box:HookScript("OnMouseWheel", function(_, delta)
            say("box wheel "..delta.." ofs="..tostring(target.wimInputScrollOfs));
        end);
        box.wimProbeCC = 0;
        box:HookScript("OnCursorChanged", function(self, x, y, _, h)
            self.wimProbeCC = (self.wimProbeCC or 0) + 1;
            local stamp = tostring(x).."|"..tostring(y).."|"..tostring(h);
            if (self.wimProbeStamp == stamp) then return; end
            self.wimProbeStamp = stamp;
            say(string.format("cursor MOVED y=%.1f h=%.1f ofs=%.1f",
                y or 0, h or 0, target.wimInputScrollOfs or 0));
        end);
        traceSetters(box);
    end
    probeTicker = _G.C_Timer.NewTicker(1, function()
        if (not (box and box.GetRegions)) then return; end
        local line = string.format("focus=%s multi=%s boxH=%s viewH=%s ofs=%s cc/s=%d",
            tostring(box:HasFocus()), tostring(box:IsMultiLine()),
            tostring(rnd(box:GetHeight())),
            tostring(viewport and rnd(viewport:GetHeight())),
            tostring(rnd(target.wimInputScrollOfs or 0)),
            box.wimProbeCC or 0);
        box.wimProbeCC = 0;
        say(line.." | "..caretReport(box)..setterReport(box));
    end);
    say("on: wheel/cursor hooks live, state line every second."
        .." Type in the box, wheel over it, then /wim inputprobe to stop."
        .." /wim inputprobe lab raises a stock control box.");
end

RegisterSlashCommand("inputprobe", inputProbe,
    L["Toggle a live probe of the themed input row (prints to chat); 'lab' toggles a stock control box."]);

RegisterSlashCommand("snapmenu", function()
        snapNextMenu = true;
        _G.DEFAULT_CHAT_FRAME:AddMessage(
            "|cff69ccf0WIM:|r the next modern context menu will be"
            .." snapshotted while open (open the minimap right-click menu).");
    end,
    L["Snapshot the next modern context menu while it is open."]);
