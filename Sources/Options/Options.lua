-- imports
local WIM = WIM;
local _G = _G;
local CreateFrame = CreateFrame;
local table = table;
local type = type;
local math = math;
local select = select;

-- set namespace
setfenv(1, WIM);

options = {}; -- reference to the options interface

local Categories = {};
local categorySelected = 1;
local subCategorySelected = 1;

local function getMaxLevel(obj)
    local maxLevel = obj:GetFrameLevel();
    if(type(obj.GetChildren) == "function") then
        for i=1, select("#", obj:GetChildren()) do
            maxLevel = math.max(maxLevel, getMaxLevel(select(i, obj:GetChildren())));
        end
    end
    return maxLevel;
end

local function getCategoryIndexByName(cat)
    for i=1, #Categories do
        if(Categories[i].title == cat) then
            return i;
        end
    end
    return nil;
end

local function createOptionsFrame()
    -- create frame object - changes to Patch 9.0.1 - Shadowlands, retail and classic
	options.frame = CreateFrame("Frame", "WIM3_Options", _G.UIParent, "BackdropTemplate");
    local win = options.frame;
    win:Hide(); -- hide initially, scripts aren't loaded yet.

    -- set size and position
    win:SetWidth(600);
    win:SetHeight(500);
    win:SetPoint("CENTER");

    -- set backdrop - changes to Patch 9.0.1 - Shadowlands, retail and classic
    win.backdropInfo = {bgFile = "Interface\\AddOns\\"..addonTocName.."\\Sources\\Options\\Textures\\Frame_Background",
        edgeFile = "Interface\\AddOns\\"..addonTocName.."\\Sources\\Options\\Textures\\Frame",
        tile = true, tileSize = 64, edgeSize = 64,
        insets = { left = 64, right = 64, top = 64, bottom = 64 }};

	win:ApplyBackdrop();

    -- set basic frame properties
    win:SetClampedToScreen(true);
    win:SetFrameStrata("DIALOG");
    win:SetMovable(true);
    win:SetToplevel(true);
    win:EnableMouse(true);
    win:RegisterForDrag("LeftButton");

    -- set script events
    win:SetScript("OnShow", function(self) _G.PlaySound(850); options.OnShow(self); end);
    win:SetScript("OnHide", function(self) _G.PlaySound(851); options.OnHide(self); end);
    win:SetScript("OnDragStart", function(self) self:StartMoving(); end);
    win:SetScript("OnDragStop", function(self) self:StopMovingOrSizing(); end);

    -- create and set title bar text
    win.title = win:CreateFontString(win:GetName().."Title", "OVERLAY", "ChatFontNormal");
    win.title:SetPoint("TOPLEFT", 50 , -20);
    local font = win.title:GetFont();
    win.title:SetFont(font, 16, "");
    win.title:SetText(L["WIM (WoW Instant Messenger)"].." v"..version);

    -- create close button
    win.close = CreateFrame("Button", win:GetName().."Close", win);
    win.close:SetWidth(18); win.close:SetHeight(18);
    win.close:SetPoint("TOPRIGHT", -24, -20);
    win.close:SetNormalTexture("Interface\\AddOns\\"..addonTocName.."\\Sources\\Options\\Textures\\blipRed");
    win.close:SetHighlightTexture("Interface\\AddOns\\"..addonTocName.."\\Sources\\Options\\Textures\\close", "BLEND");
    win.close:SetScript("OnClick", function(self)
            self:GetParent():Hide();
        end);


    -- create navigation menu
    win.nav = CreateFrame("Frame", win:GetName().."Nav", win);
    win.nav.bg = win.nav:CreateTexture(win.nav:GetName().."BG", "BACKGROUND");
    win.nav.bg:SetColorTexture(1, 1, 1, .25);
    win.nav.bg:SetPoint("TOPRIGHT");
    win.nav.bg:SetPoint("BOTTOMRIGHT");
    win.nav.bg:SetWidth(1);
    win.nav:SetPoint("TOPLEFT", 18, -47);
    win.nav:SetPoint("BOTTOMLEFT", 18, 18);
    win.nav:SetWidth(150);
    win.nav:SetScript("OnShow", function(self) options.UpdateCategories(self); end);
    win.nav.category = {};
    win.nav.sub = CreateFrame("Frame", win.nav:GetName().."Sub", win.nav);
    win.nav.sub:Hide();
    win.nav.sub.buttons = {};
    win.nav.sub:SetScript("OnShow", function(self) options.UpdateSubCategories(self); end);

    -- create container frame
    win.container = CreateFrame("Frame", win:GetName().."Container", win);
    win.container.bg = win.container:CreateTexture(win.container:GetName().."BG", "BACKGROUND");
    win.container.bg:SetAllPoints();
    -- win.container.bg:SetColorTexture(1, 1, 1, .25); -- for testing only to see bounds.
    win.container:SetPoint("TOPLEFT", win.nav, "TOPRIGHT", 10, -2);
    win.container:SetPoint("BOTTOMLEFT", win.nav, "BOTTOMRIGHT", 10, 2);
    win.container:SetPoint("RIGHT", win, -25, 0);

    win.Enable = function(self)
        self:SetAlpha(1);
        self.disableFrame:Hide();
        win:SetToplevel(true);
        win:SetFrameStrata("DIALOG");
        win.disableFrame:SetFrameStrata("DIALOG");
    end

    win.Disable = function(self)
        self:SetAlpha(.5);
        self.disableFrame:Show();
        self.disableFrame:SetFrameLevel(getMaxLevel(self.container)+1);
        win:SetToplevel(false);
        win:SetFrameStrata("LOW");
        win.disableFrame:SetFrameStrata("LOW");
    end

    -- create disableFrame
    win.disableFrame = CreateFrame("Frame", nil, win);
    win.disableFrame:SetAllPoints();
    win.disableFrame:EnableMouse(true);
    win.disableFrame:Hide();
    win.disableFrame:SetFrameStrata("DIALOG");

    -- allow this window to close when escape is pressed.
    table.insert(_G.UISpecialFrames,win:GetName());
    dPrint("Options frame created.");
end

local function createCategory(index)
    local cat = CreateFrame("Button", options.frame.nav:GetName().."Cat"..index, options.frame.nav, "OptionsListButtonTemplate");

    cat:RegisterForClicks("LeftButtonUp", "RightButtonUp");
    cat.info = Categories[index];
    cat.catIndex = index;
    cat.bg = cat:CreateTexture(nil, "BACKGROUND");
    cat.bg:SetAllPoints();
    cat.bg:SetColorTexture(1, 1, 1);
    cat.bg:SetGradient("VERTICAL", getGradientFromColor("658daa"));
    cat.text = _G.getglobal(cat:GetName().."Text");
    cat.text:ClearAllPoints();
    cat.text:SetPoint("CENTER");
    local font, _, _ = _G.ChatFontNormal:GetFont();
    cat.text:SetFont(font, 14, "");
    cat.text:SetText("|cffffffff"..cat.info.title.."|r");
    cat:SetHeight(28);
    cat:SetWidth(options.frame.nav:GetWidth()-2);
    cat:Show();
    cat:SetScript("OnClick", function(self, button)
            _G.PlaySound(856);
            categorySelected = self.catIndex;
            subCategorySelected = 1;
            options.UpdateCategories();
        end);
    return cat;
end

local function createSubCategory(index)
    local sub = CreateFrame("Button", options.frame.nav.sub:GetName().."Button"..index, options.frame.nav.sub, "OptionsListButtonTemplate");

    sub:SetWidth(sub:GetParent():GetWidth());
    sub:SetHeight(20);
    sub.text = _G.getglobal(sub:GetName().."Text");
    sub.text:SetJustifyH("LEFT");
    sub.text:ClearAllPoints();
    sub.text:SetPoint("TOPLEFT", 10, 0);
    sub.text:SetPoint("BOTTOMRIGHT", -2, 0);
    local font, _, _ = _G.ChatFontNormal:GetFont();
    sub.text:SetFont(font, 14, "");
    sub:SetScript("OnClick", function(self, button)
            _G.PlaySound(856);
            subCategorySelected = self.subIndex;
            local cat = options.frame.nav.sub.category[self.subIndex];
            if(type(cat.frame) == "function") then
                -- function was passed, execute it now.
                cat.frame = cat.frame();
            end
            options.UpdateSubCategories();
            if(options.frame.container.frame) then
                options.frame.container.frame:Hide();
            end
            options.frame.container.frame = cat.frame;
            cat.frame:SetParent(options.frame.container);
            cat.frame:ClearAllPoints();
            cat.frame:SetPoint("TOPLEFT");
            cat.frame:SetPoint("BOTTOMRIGHT");
            cat.frame:Show();
        end);
    return sub;
end

function options.UpdateCategories(self)
    self = self or options.frame.nav;
    self.sub:Hide();
    self.sub:ClearAllPoints();
    if(#Categories > 0) then
        if(#Categories > #self.category) then
            -- create new category button
            for i=#self.category+1, #Categories do
                table.insert(self.category, createCategory(i));
            end
        end

        -- position the rest to the bottom
        local prevCat = self;
        for i=#self.category, 1, -1 do
            local cat = self.category[i];
            cat:ClearAllPoints();
            if(i ~= categorySelected) then
                if(prevCat == self) then
                    cat:SetPoint("BOTTOMLEFT", prevCat, "BOTTOMLEFT", 0, 0);
                else
                    cat:SetPoint("BOTTOMLEFT", prevCat, "TOPLEFT", 0, 0);
                end
                cat.bg:SetGradient("VERTICAL", getGradientFromColor("658daa"));
                cat:Enable();
                prevCat = cat;
            else
                -- first item
                cat:Disable();
                cat.bg:SetGradient("VERTICAL", getGradientFromColor("111111"));
                cat:SetPoint("TOPLEFT", self, "TOPLEFT", 0, 0);
                self.sub:SetPoint("TOPLEFT", cat, "BOTTOMLEFT", 0, 0);
                self.sub:SetPoint("TOPRIGHT", cat, "BOTTOMRIGHT", 0, 0);
                self.sub.category = cat.info.subCategories;
            end
        end
        if(prevCat == self) then
            self.sub:SetPoint("BOTTOM", self, "BOTTOM", 0, 0);
        else
            self.sub:SetPoint("BOTTOM", prevCat, "TOP", 0, 0);
        end
        self.sub:Show();
    end
end

function options.UpdateSubCategories(self)
    self = self or options.frame.nav.sub;
    if(#self.category > #self.buttons) then
        for i=#self.buttons+1, #self.category do
            -- make sure we have enough buttons
            table.insert(self.buttons, createSubCategory(i));
        end
        -- align the buttons
        for i=1, #self.buttons do
            self.buttons[i]:ClearAllPoints();
            if(i==1) then
                self.buttons[i]:SetPoint("TOP");
            else
                self.buttons[i]:SetPoint("TOP", self.buttons[i-1], "BOTTOM");
            end
        end
    end
    -- set proper button properies for current category
    for i=1, #self.buttons do
        if(i <= #self.category) then
            self.buttons[i].subIndex = i;
            self.buttons[i].text:SetText(self.category[i].title);
            self.buttons[i]:Show();
            if(self.category[i].frame) then
                self.buttons[i]:Enable();
            else
                self.buttons[i]:Disable();
            end
            if(i == subCategorySelected) then
                self.buttons[i]:LockHighlight();
                self.buttons[i]:Click();
            else
                self.buttons[i]:UnlockHighlight();
            end
        else
            self.buttons[i]:Hide();
        end
    end
end

function options.OnShow(self)

end

function options.OnHide(self)
    if(DemoWindow) then
        DemoWindow:Hide();
    end
    options.frame:Enable();
end


function RegisterOptionFrame(Category, SubCategory, OptionFrame)
    local catIndex = getCategoryIndexByName(Category);
    if(not catIndex) then
        catIndex = #Categories + 1;
        table.insert(Categories, {
            title = Category,
            subCategories = {}
        });
    end
    table.insert(Categories[catIndex].subCategories, {
        title = SubCategory,
        description = Description,
        frame = OptionFrame
    });
end

-- Toggle the classic standalone options window.
function ShowClassicOptions()
    -- Modern-only skins carry settings the classic window has no
    -- controls for, so while one is selected the classic window stays
    -- closed (the same lock that pins the options style to modern).
    if(SkinLocksOptionsStyle and SkinLocksOptionsStyle()) then
        _G.DEFAULT_CHAT_FRAME:AddMessage(L["WIM: the selected skin (%s) is configured through the modern options UI; the classic window is unavailable while it is active."]
            :format(db and db.skin and db.skin.selected or ""));
        if(ShowModernOptions) then
            ShowModernOptions();
        end
        return;
    end
    if(not options.frame) then
        createOptionsFrame();
    end
    if(options.frame:IsShown()) then
        options.frame:Hide();
    else
        options.frame:Show();
    end
end

-- Open WIM's category in the native Settings panel (Options > AddOns).
-- Only callable when Sources/Options/ModernSettings.lua registered the
-- category; ShowOptions checks that before routing here.
function ShowModernOptions()
    if(options.frame and options.frame:IsShown()) then
        options.frame:Hide();
    end
    if(_G.InCombatLockdown()) then
        -- Settings.OpenToCategory reaches the protected OpenSettingsPanel(),
        -- which the client blocks for addon code during combat (the panel
        -- itself may be open in combat -- only the addon-initiated open is
        -- protected). Queue the open for end of combat; asking again while
        -- queued cancels, so a stray click doesn't ambush the user with a
        -- fullscreen panel after the fight.
        if(options._pendingModernOpen) then
            options._pendingModernOpen = nil;
            _G.DEFAULT_CHAT_FRAME:AddMessage("WIM: queued options open canceled.");
            return;
        end
        options._pendingModernOpen = true;
        if(not options._modernOpenWaiter) then
            local waiter = _G.CreateFrame("Frame");
            options._modernOpenWaiter = waiter;
            waiter:SetScript("OnEvent", function(self)
                self:UnregisterEvent("PLAYER_REGEN_ENABLED");
                -- Re-check both the queue and the routing: a style switch
                -- back to classic mid-combat voids the queued open.
                if(options._pendingModernOpen) then
                    options._pendingModernOpen = nil;
                    if(db and db.modernOptions) then
                        _G.Settings.OpenToCategory(options.modernCategoryID);
                    end
                end
            end);
        end
        options._modernOpenWaiter:RegisterEvent("PLAYER_REGEN_ENABLED");
        _G.DEFAULT_CHAT_FRAME:AddMessage(
            "WIM: the game's Settings panel cannot be opened during combat - it will open when combat ends.");
        return;
    end
    options._pendingModernOpen = nil;
    _G.Settings.OpenToCategory(options.modernCategoryID);
end

-- WIM.ShowOptions()
-- Single entry point used by /wim, the key binding and the minimap menu:
-- routes to whichever options style the user selected. modernCategoryID
-- doubles as the "native Settings API available" sentinel, so clients
-- without it always get the classic window regardless of the flag.
function ShowOptions()
    if(db and db.modernOptions and options.modernCategoryID) then
        ShowModernOptions();
    else
        ShowClassicOptions();
    end
end

RegisterSlashCommand("options", ShowOptions, L["Display WIM's options."]);
RegisterSlashCommand("reset", function()
                _G.StaticPopupDialogs["WIM_RESET_DEFAULTS"] = {
                	preferredIndex = STATICPOPUP_NUMDIALOGS,
                    text = L["Resetting WIM will clear all of your settings!"].."\n"..L["A reset will reload your user interface."].."\n"..L["Do you want to continue?"],
                    button1 = _G.YES,
                    button2 = _G.NO,
                    OnAccept = function()
                        _G.WIM3_Data = nil;
                        _G.WIM3_Data = nil;   -- pre-rename name
                        _G.ReloadUI();
                    end,
                    timeout = 0,
                    whileDead = 1,
                    hideOnEscape = 1
                };
                _G.StaticPopup_Show ("WIM_RESET_DEFAULTS");
            end, L["Reset all options to default."]);
