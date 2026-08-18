local WIM = WIM;

-- imports
local _G = _G;
local table = table;
local pairs = pairs;
local string = string;
local math = math;
local debugstack = debugstack;
local type = type;
local unpack = unpack;
local setmetatable = setmetatable;
local getmetatable = getmetatable;
local rawget = rawget;
local CreateFrame = CreateFrame;
local pcall = pcall;

-- Defined before the setfenv. C_Texture.GetAtlasInfo looks up
-- Vector2DMixin in the calling function's environment, so namespaced
-- code must not call it directly.
local function getAtlasInfo(name)
    if (C_Texture and C_Texture.GetAtlasInfo) then
        return C_Texture.GetAtlasInfo(name);
    end
end

-- set namespace
setfenv(1, WIM);

db_defaults.skin = {
    selected = "WIM Classic",
    font = "ChatFontNormal",
    font_outline = "",
    suggest = true,
};

-- Modern Theme: backgrounds and cut-out behavior for the surfaces
-- modern-only skins dress in the game's own panel art (the History
-- Viewer's chrome and the message windows).
db_defaults.modernTheme = {
    frame = "rock",
    panels = "darkmarble",
    content = "darkmarble",
    cutout = false,
    chatFrame = "rock",
    chatPanel = "darkmarble",
    chatCutout = false,
    -- Which roleplay profile fields replace the stock display on
    -- whisper windows; empty means the stock display, untouched.
    rpFields = {},
};

-- The panel art offered by the Modern Theme background pickers: the
-- game's own backgrounds, plus flat translucent fills.
local CHROME_BACKGROUNDS = {
    { key = "none", label = "None (fully clear)", color = {0, 0, 0, 0} },
    { key = "transparent", label = "Transparent", color = {0, 0, 0, .55} },
    { key = "rock", label = "Rock",
      file = "Interface\\FrameGeneral\\UI-Background-Rock", tile = true },
    { key = "marble", label = "Marble",
      file = "Interface\\FrameGeneral\\UI-Background-Marble", tile = true },
    { key = "darkmarble", label = "Dark Marble",
      file = "Interface\\FrameGeneral\\UI-Background-Marble", tile = true, tint = .45 },
    { key = "dialog", label = "Dialog",
      file = "Interface\\DialogFrame\\UI-DialogBox-Background", tile = true },
    { key = "bank", label = "Bank",
      file = "Interface\\BankFrame\\Bank-Background", tile = true },
    { key = "vault", label = "Guild Vault",
      file = "Interface\\GuildBankFrame\\GuildVaultBG", tile = true },
    { key = "sandstone", label = "Dark Sandstone",
      file = "Interface\\HELPFRAME\\DarkSandstone-Tile", tile = true },
    { key = "parchmenttile", label = "Parchment (Tileable)",
      file = "Interface\\HELPFRAME\\Tileable-Parchment", tile = true },
    { key = "question", label = "Quest Parchment",
      file = "Interface\\QuestionFrame\\question-background", tile = true },
    { key = "raidgroup", label = "Raid Frame",
      file = "Interface\\RAIDFRAME\\UI-RaidFrame-GroupBg", tile = false },
    { key = "endscreen", label = "Destiny",
      file = "Interface\\Destiny\\EndscreenBG", tile = false },
    { key = "stationeryauction", label = "Stationery (Auction)",
      file = "Interface\\Stationery\\AuctionStationery1", tile = false },
    { key = "stationeryill", label = "Stationery (Illustrated)",
      file = "Interface\\Stationery\\Stationery_ill1", tile = false },
    { key = "stationeryog", label = "Stationery (Orgrimmar)",
      file = "Interface\\Stationery\\Stationery_OG1", tile = false },
    { key = "stationerytb", label = "Stationery (Thunder Bluff)",
      file = "Interface\\Stationery\\Stationery_TB1", tile = false },
    { key = "stationeryuc", label = "Stationery (Undercity)",
      file = "Interface\\Stationery\\Stationery_UC1", tile = false },
    { key = "stationeryplain", label = "Stationery (Plain)",
      file = "Interface\\Stationery\\StationeryTest1", tile = false },
    { key = "worldmap1", label = "World Map 1",
      file = "Interface\\WorldMap\\UI-WorldMap-Middle1", tile = false },
    { key = "worldmap2", label = "World Map 2",
      file = "Interface\\WorldMap\\UI-WorldMap-Middle2", tile = false },
    { key = "achievement", label = "Achievement Stats",
      file = "Interface\\ACHIEVEMENTFRAME\\UI-Achievement-StatsBackground", tile = false },
    { key = "adventuremap", label = "Adventure Map Parchment",
      file = "Interface\\AdventureMap\\AdventureMapParchmentTile", tile = true },
    { key = "collections", label = "Collections",
      file = "Interface\\Collections\\CollectionsBackgroundTile", tile = true },
    { key = "framealliance", label = "Frame: Alliance",
      file = "Interface\\FrameGeneral\\UIFrameAllianceBackground", tile = true },
    { key = "framehorde", label = "Frame: Horde",
      file = "Interface\\FrameGeneral\\UIFrameHordeBackground", tile = true },
    { key = "frameneutral", label = "Frame: Neutral",
      file = "Interface\\FrameGeneral\\UIFrameNeutralBackground", tile = true },
    { key = "framemarine", label = "Frame: Marine",
      file = "Interface\\FrameGeneral\\UIFrameMarineBackground", tile = true },
    { key = "framemechagon", label = "Frame: Mechagon",
      file = "Interface\\FrameGeneral\\UIFrameMechagonBackground", tile = true },
    { key = "framekyrian", label = "Frame: Kyrian",
      file = "Interface\\FrameGeneral\\UIFrameKyrianBackground", tile = true },
    { key = "framenecrolord", label = "Frame: Necrolord",
      file = "Interface\\FrameGeneral\\UIFrameNecrolordBackground", tile = true },
    { key = "framenightfae", label = "Frame: Night Fae",
      file = "Interface\\FrameGeneral\\UIFrameNightFaeBackground", tile = true },
    { key = "frameventhyr", label = "Frame: Venthyr",
      file = "Interface\\FrameGeneral\\UIFrameVenthyrBackground", tile = true },
    { key = "frameoribos", label = "Frame: Oribos",
      file = "Interface\\FrameGeneral\\UIFrameOribosBackground", tile = true },
    { key = "framedragonflight", label = "Frame: Dragonflight",
      file = "Interface\\FrameGeneral\\UIFrameDragonflightBackground", tile = true },
    { key = "framewarwithin", label = "Frame: The War Within",
      file = "Interface\\FrameGeneral\\UIFrameTheWarWithinBackground", tile = true },
    { key = "classhall", label = "Class Hall",
      file = "Interface\\Garrison\\ClassHallBackground", tile = true },
    { key = "classhallinternal", label = "Class Hall (Internal)",
      file = "Interface\\Garrison\\ClassHallInternalBackground", tile = true },
    { key = "garrisonlanding", label = "Garrison Landing Page",
      file = "Interface\\Garrison\\GarrisonLandingPageMiddleTile", tile = true },
    { key = "garrisonmission", label = "Garrison Mission",
      file = "Interface\\Garrison\\GarrisonMissionUIInfoBoxBackgroundTile", tile = true },
    { key = "garrisonship", label = "Ship Mission Parchment",
      file = "Interface\\Garrison\\GarrisonShipMissionParchment", tile = true },
    { key = "garrisonui", label = "Garrison UI",
      file = "Interface\\Garrison\\GarrisonUIBackground", tile = true },
    { key = "garrisonui2", label = "Garrison UI 2",
      file = "Interface\\Garrison\\GarrisonUIBackground2", tile = true },
    { key = "creditsclassic", label = "Credits: Classic",
      file = "Interface\\Credits\\CreditsScreenBackground0WoW", tile = true },
    { key = "creditsbc", label = "Credits: Burning Crusade",
      file = "Interface\\Credits\\CreditsScreenBackground1BC", tile = true },
    { key = "creditswotlk", label = "Credits: Wrath",
      file = "Interface\\Credits\\CreditsScreenBackground2WotLK", tile = true },
    { key = "creditscata", label = "Credits: Cataclysm",
      file = "Interface\\Credits\\CreditsScreenBackground3Cataclysm", tile = true },
    { key = "creditsmop", label = "Credits: Mists of Pandaria",
      file = "Interface\\Credits\\CreditsScreenBackground4MoP", tile = true },
    { key = "creditswod", label = "Credits: Warlords",
      file = "Interface\\Credits\\CreditsScreenBackground5WoD", tile = true },
    { key = "creditslegion", label = "Credits: Legion",
      file = "Interface\\Credits\\CreditsScreenBackground6Legion", tile = true },
    { key = "creditsbfa", label = "Credits: Battle for Azeroth",
      file = "Interface\\Credits\\CreditsScreenBackground7BfA", tile = true },
};

function GetChromeBackgrounds()
    return CHROME_BACKGROUNDS;
end

-- Paints one catalog choice onto a texture. Unknown keys fall back
-- to Rock, never to the flat fills.
function ApplyChromeBackgroundChoice(texture, key)
    local entry, fallback;
    for i=1, #CHROME_BACKGROUNDS do
        if(CHROME_BACKGROUNDS[i].key == key) then
            entry = CHROME_BACKGROUNDS[i];
            break;
        end
        if(CHROME_BACKGROUNDS[i].key == "rock") then
            fallback = CHROME_BACKGROUNDS[i];
        end
    end
    entry = entry or fallback or CHROME_BACKGROUNDS[1];
    if(entry.color) then
        texture:SetColorTexture(entry.color[1], entry.color[2],
            entry.color[3], entry.color[4]);
        return;
    end
    local tile = entry.tile and true or false;
    texture:SetTexture(entry.file, tile, tile);
    texture:SetHorizTile(tile);
    texture:SetVertTile(tile);
    texture:SetTexCoord(0, 1, 0, 1);
    local tint = entry.tint or 1;
    texture:SetVertexColor(tint, tint, tint, 1);
end

local SelectedSkin;

local SKIN_DEBUG = "";

local SkinTable = {};
local fontTable = {};

local prematureRegisters = {};

local WindowSoupBowl = WIM:GetWindowSoupBowl();

local function normalizeFont(font)
	if (type(font) == "table" and font.GetFont) then
		local fontPath, fontHeight, fontFlags = font:GetFont();
		return fontPath;

	elseif (type(font) == "string") then

		if (type(_G[font]) == "table") then
			return normalizeFont(_G[font]);
		end
		-- The string is not the name of a global font object. Keep it
		-- unchanged so SetWidgetFont's other branches can resolve
		-- LibSharedMedia names and font file paths.
		return font;
	end

	return font
end

local fontPaths = {
	"root.message_window.widgets.from.font",
	"root.message_window.widgets.char_info.font",
	"root.message_window.widgets.chat_display.font",
	"root.message_window.widgets.msg_box.font",
	"root.menu.title.font",
	"root.menu.button.font",
};

local function linkSkinTable(src, dest)
        if(type(src) == "table") then
                if(type(dest) ~= "table") then dest = {}; end
                --clear current meta table if there is one.
                setmetatable(dest, nil);
                for k, v in pairs(src) do
                        if(not (k == "points" and type(dest[k]) == "table") and type(v) == "table") then
                            linkSkinTable(v, dest[k]);
                        end
                end
                --setmetatable
                setmetatable(dest, {__index = src});
        end
end


local function setPointsToObj(obj, pointsTable)
    obj:ClearAllPoints();
    for i=1, #pointsTable do
        local point, relativeTo, relativePoint, offx, offy = unpack(pointsTable[i]);
        -- first we need to convert the string representation of objects into actual objects.
        if(relativeTo and type(relativeTo) == "string") then
            if(string.lower(relativeTo) == "window") then
                relativeTo = obj.parentWindow;
            else
                relativeTo = obj.parentWindow.widgets[relativeTo];
            end
            relativeTo = relativeTo or UIPanel;
        end
        -- set the actual points
        obj:SetPoint(point, relativeTo, relativePoint, offx, offy);
    end
end

-- load selected skin
function ApplySkinToWindow(obj)
    local fName = obj:GetName();

    local SelectedSkin = WIM:GetSelectedSkin();

	if obj.SetResizeBounds then -- WoW 10.0
		obj:SetResizeBounds(SelectedSkin.message_window.min_width, SelectedSkin.message_window.min_height);
	else
    	obj:SetMinResize(SelectedSkin.message_window.min_width, SelectedSkin.message_window.min_height);
    end

    --set backdrop edges and background textures.
    local tl = obj.widgets.Backdrop.tl;
    tl:SetTexture(SelectedSkin.message_window.texture);
    tl:SetTexCoord(unpack(SelectedSkin.message_window.backdrop.top_left.texture_coord));
    tl:ClearAllPoints();
    tl:SetPoint("TOPLEFT", fName.."Backdrop", "TOPLEFT", unpack(SelectedSkin.message_window.backdrop.top_left.offset));
    tl:SetWidth(SelectedSkin.message_window.backdrop.top_left.width);
    tl:SetHeight(SelectedSkin.message_window.backdrop.top_left.height);
    local tr = obj.widgets.Backdrop.tr;
    tr:SetTexture(SelectedSkin.message_window.texture);
    tr:SetTexCoord(unpack(SelectedSkin.message_window.backdrop.top_right.texture_coord));
    tr:ClearAllPoints();
    tr:SetPoint("TOPRIGHT", fName.."Backdrop", "TOPRIGHT", unpack(SelectedSkin.message_window.backdrop.top_right.offset));
    tr:SetWidth(SelectedSkin.message_window.backdrop.top_right.width);
    tr:SetHeight(SelectedSkin.message_window.backdrop.top_right.height);
    local bl = obj.widgets.Backdrop.bl;
    bl:SetTexture(SelectedSkin.message_window.texture);
    bl:SetTexCoord(unpack(SelectedSkin.message_window.backdrop.bottom_left.texture_coord));
    bl:ClearAllPoints();
    bl:SetPoint("BOTTOMLEFT", fName.."Backdrop", "BOTTOMLEFT", unpack(SelectedSkin.message_window.backdrop.bottom_left.offset));
    bl:SetWidth(SelectedSkin.message_window.backdrop.bottom_left.width);
    bl:SetHeight(SelectedSkin.message_window.backdrop.bottom_left.height);
    local br = obj.widgets.Backdrop.br;
    br:SetTexture(SelectedSkin.message_window.texture);
    br:SetTexCoord(unpack(SelectedSkin.message_window.backdrop.bottom_right.texture_coord));
    br:ClearAllPoints();
    br:SetPoint("BOTTOMRIGHT", fName.."Backdrop", "BOTTOMRIGHT", unpack(SelectedSkin.message_window.backdrop.bottom_right.offset));
    br:SetWidth(SelectedSkin.message_window.backdrop.bottom_right.width);
    br:SetHeight(SelectedSkin.message_window.backdrop.bottom_right.height);
    local t = obj.widgets.Backdrop.t;
    t:SetTexture(SelectedSkin.message_window.texture, SelectedSkin.message_window.backdrop.top.tile or nil);
    t:SetTexCoord(unpack(SelectedSkin.message_window.backdrop.top.texture_coord));
    t:ClearAllPoints();
    t:SetPoint("TOPLEFT", fName.."Backdrop_TL", "TOPRIGHT", 0, 0);
    t:SetPoint("BOTTOMRIGHT", fName.."Backdrop_TR", "BOTTOMLEFT", 0, 0);
    local b = obj.widgets.Backdrop.b;
    b:SetTexture(SelectedSkin.message_window.texture, SelectedSkin.message_window.backdrop.bottom.tile or nil);
    b:SetTexCoord(unpack(SelectedSkin.message_window.backdrop.bottom.texture_coord));
    b:ClearAllPoints();
    b:SetPoint("TOPLEFT", fName.."Backdrop_BL", "TOPRIGHT", 0, 0);
    b:SetPoint("BOTTOMRIGHT", fName.."Backdrop_BR", "BOTTOMLEFT", 0, 0);
    local l = obj.widgets.Backdrop.l;
    l:SetTexture(SelectedSkin.message_window.texture, SelectedSkin.message_window.backdrop.left.tile or nil);
    l:SetTexCoord(unpack(SelectedSkin.message_window.backdrop.left.texture_coord));
    l:ClearAllPoints();
    l:SetPoint("TOPLEFT", fName.."Backdrop_TL", "BOTTOMLEFT", 0, 0);
    l:SetPoint("BOTTOMRIGHT", fName.."Backdrop_BL", "TOPRIGHT", 0, 0);
    local r = obj.widgets.Backdrop.r;
    r:SetTexture(SelectedSkin.message_window.texture, SelectedSkin.message_window.backdrop.right.tile or nil);
    r:SetTexCoord(unpack(SelectedSkin.message_window.backdrop.right.texture_coord));
    r:ClearAllPoints();
    r:SetPoint("TOPLEFT", fName.."Backdrop_TR", "BOTTOMLEFT", 0, 0);
    r:SetPoint("BOTTOMRIGHT", fName.."Backdrop_BR", "TOPRIGHT", 0, 0);
    local bg = obj.widgets.Backdrop.bg;
    bg:SetTexture(SelectedSkin.message_window.texture, SelectedSkin.message_window.backdrop.background.tile or nil);
    bg:SetTexCoord(unpack(SelectedSkin.message_window.backdrop.background.texture_coord));
    bg:ClearAllPoints();
    bg:SetPoint("TOPLEFT", fName.."Backdrop_TL", "BOTTOMRIGHT", 0, 0);
    bg:SetPoint("BOTTOMRIGHT", fName.."Backdrop_BR", "TOPLEFT", 0, 0);

    --set class icon
    local class_icon = obj.widgets.class_icon;
    ApplySkinToWidget(class_icon);
    class_icon:SetTexture(SelectedSkin.message_window.widgets.class_icon.texture);
    --WIM_UpdateMessageWindowClassIcon(obj);

    --set from font
    local from = obj.widgets.from;
    ApplySkinToWidget(from);

    --set character details font
    local char_info = obj.widgets.char_info;
    ApplySkinToWidget(char_info);

    --close button
    local close = obj.widgets.close;
    ApplySkinToWidget(close);
    -- close button is a special case... so do the following extra work.
    if(close.curTextureIndex == 1) then
        close:SetNormalTexture(SelectedSkin.message_window.widgets.close.state_hide.NormalTexture);
        close:SetPushedTexture(SelectedSkin.message_window.widgets.close.state_hide.PushedTexture);
        close:SetHighlightTexture(SelectedSkin.message_window.widgets.close.state_hide.HighlightTexture, SelectedSkin.message_window.widgets.close.state_hide.HighlightAlphaMode);
    else
        close:SetNormalTexture(SelectedSkin.message_window.widgets.close.state_close.NormalTexture);
        close:SetPushedTexture(SelectedSkin.message_window.widgets.close.state_close.PushedTexture);
        close:SetHighlightTexture(SelectedSkin.message_window.widgets.close.state_close.HighlightTexture, SelectedSkin.message_window.widgets.close.state_close.HighlightAlphaMode);
    end

    --scroll_up button
    local scroll_up = obj.widgets.scroll_up;
    ApplySkinToWidget(scroll_up);

    --scroll_down button
    local scroll_down = obj.widgets.scroll_down;
    ApplySkinToWidget(scroll_down);

    --chat display
    local chat_display = obj.widgets.chat_display;
	chat_display._font_flags = db.skin.font_outline;
    ApplySkinToWidget(chat_display);

    --msg_box
    local msg_box = obj.widgets.msg_box;
	msg_box._font_flags = db.skin.font_outline;
    ApplySkinToWidget(msg_box);

    --apply skin to registered widgets
    for widget, _ in pairs(windows.widgets) do
        if(obj.widgets[widget] and SelectedSkin.message_window.widgets[widget]) then
            dPrint("Applying skin to '"..widget.."'.");
            ApplySkinToWidget(obj.widgets[widget]);
        end
    end

    obj:UpdateProps();
    obj:UpdateIcon();
    obj:UpdateCharDetails();

    -- Runs last so nothing above it (UpdateIcon re-showing the class
    -- icon, property refreshes) undoes the theme's visibility choices.
    ApplyModernThemeToWindow(obj);
end

-- Modern Theme on the message windows: while a modern-only skin is
-- selected, each window wears the History Viewer's construction in
-- miniature -- the standard metal nine-slice frame with a title band
-- (the conversation name in gold), the message area as a recessed
-- inset well whose fill follows the theme's message-area choice, the
-- input box in the native search-box border, and the standard red
-- corner X. Cut-out mode draws the frame fill only around the message
-- well, so a clear well background looks through to the world.
local function buildWindowChrome(obj)
    local apply = _G.NineSliceUtil and _G.NineSliceUtil.ApplyLayoutByName;
    if(not apply) then return false; end
    local display = obj.widgets.chat_display;
    local msg_box = obj.widgets.msg_box;

    local chrome = CreateFrame("Frame", nil, obj);
    chrome:SetAllPoints();
    chrome:SetFrameLevel(obj:GetFrameLevel());

    -- Apply the layout first. The portrait variant's left pieces sit
    -- 13px outside the frame, 5px further than the plain layout's, which
    -- puts the left rail at about -1..+4. The fill's left inset must
    -- follow the applied layout or a gap opens against the rail.
    chrome.hasPortrait = pcall(apply, chrome, "PortraitFrameTemplate")
        or pcall(apply, chrome, "ButtonFrameTemplate");
    if(not chrome.hasPortrait) then
        if(not pcall(apply, chrome, "ButtonFrameTemplateNoPortrait")) then
            chrome:Hide();
            return false;
        end
    end
    local bgLeft = chrome.hasPortrait and 2 or 7;

    -- Otherwise the fill matches the History Viewer: native panel
    -- insets at top and bottom, and it runs under the asymmetric right
    -- rail to the frame edge.
    chrome.bg = chrome:CreateTexture(nil, "BACKGROUND", nil, -8);
    chrome.bg:SetPoint("TOPLEFT", bgLeft, -18);
    chrome.bg:SetPoint("BOTTOMRIGHT", 0, 3);

    -- Cut-out strips: the fill drawn only around the message well.
    local function strip()
        local tex = chrome:CreateTexture(nil, "BACKGROUND", nil, -8);
        tex:Hide();
        return tex;
    end
    local stripTop = strip();
    stripTop:SetPoint("TOPLEFT", chrome, "TOPLEFT", bgLeft, -18);
    stripTop:SetPoint("RIGHT", chrome, "RIGHT", 0, 0);
    stripTop:SetPoint("BOTTOM", display, "TOP", 0, 6);
    local stripBottom = strip();
    stripBottom:SetPoint("BOTTOMLEFT", chrome, "BOTTOMLEFT", bgLeft, 3);
    stripBottom:SetPoint("RIGHT", chrome, "RIGHT", 0, 0);
    stripBottom:SetPoint("TOP", display, "BOTTOM", 0, -6);
    local stripLeft = strip();
    stripLeft:SetPoint("LEFT", chrome, "LEFT", bgLeft, 0);
    stripLeft:SetPoint("RIGHT", display, "LEFT", -6, 0);
    stripLeft:SetPoint("TOP", display, "TOP", 0, 6);
    stripLeft:SetPoint("BOTTOM", display, "BOTTOM", 0, -6);
    local stripRight = strip();
    stripRight:SetPoint("RIGHT", chrome, "RIGHT", 0, 0);
    stripRight:SetPoint("LEFT", display, "RIGHT", 24, 0);
    stripRight:SetPoint("TOP", display, "TOP", 0, 6);
    stripRight:SetPoint("BOTTOM", display, "BOTTOM", 0, -6);
    chrome.strips = { stripTop, stripBottom, stripLeft, stripRight };

    -- Cut the frame fill out behind the circled portrait. An inverse
    -- circular mask (white field, clear circle) covers the portrait's
    -- footprint on the fill and on the cut-out strips. Without it, a
    -- translucent window shows the fill's edge crossing the circle
    -- behind the icon.
    if(chrome.hasPortrait and chrome.bg.AddMaskTexture) then
        local hole = chrome:CreateMaskTexture();
        -- PNG textures resolve only with their extension spelled out.
        hole:SetTexture("Interface\\AddOns\\"..addonTocName.."\\Skins\\Modern\\portrait_hole_mask.png",
            "CLAMPTOWHITE", "CLAMPTOWHITE");
        hole:SetPoint("CENTER", obj, "TOPLEFT", 25.5, -22);
        hole:SetSize(56, 56);
        chrome.bg:AddMaskTexture(hole);
        for i = 1, #chrome.strips do
            chrome.strips[i]:AddMaskTexture(hole);
        end
        chrome.portraitHole = hole;
    end

    -- Message well: a recessed inset around the display area. The well
    -- extends 24px past the display on the right. The theme pulls the
    -- display's right edge in by 18px; the well keeps its original
    -- footprint, and the scrollbar sits in the freed gutter.
    local well = CreateFrame("Frame", nil, obj);
    well:SetPoint("TOPLEFT", display, "TOPLEFT", -6, 6);
    well:SetPoint("BOTTOMRIGHT", display, "BOTTOMRIGHT", 24, -6);
    well:SetFrameLevel(obj:GetFrameLevel());
    well.bg = well:CreateTexture(nil, "BACKGROUND", nil, -7);
    well.bg:SetPoint("TOPLEFT", 2, -2);
    well.bg:SetPoint("BOTTOMRIGHT", -2, 2);
    chrome.well = well;

    -- Input border: the native search box's end caps and middle piece
    -- around the message box.
    if(msg_box) then
        local input = CreateFrame("Frame", nil, obj);
        input:SetPoint("TOPLEFT", msg_box, "TOPLEFT", 0, 0);
        input:SetPoint("BOTTOMRIGHT", msg_box, "BOTTOMRIGHT", 0, 0);
        input:SetFrameLevel(obj:GetFrameLevel());
        local left = input:CreateTexture(nil, "BACKGROUND");
        left:SetAtlas("common-search-border-left");
        left:SetSize(8, 20);
        left:SetPoint("LEFT", -5, 0);
        local right = input:CreateTexture(nil, "BACKGROUND");
        right:SetAtlas("common-search-border-right");
        right:SetSize(8, 20);
        right:SetPoint("RIGHT", 0, 0);
        local middle = input:CreateTexture(nil, "BACKGROUND");
        middle:SetAtlas("common-search-border-middle");
        middle:SetPoint("TOPLEFT", left, "TOPRIGHT");
        middle:SetPoint("BOTTOMRIGHT", right, "BOTTOMLEFT");
        chrome.input = input;
    end

    if(not pcall(apply, well, "InsetFrameTemplate")) then
        chrome:Hide();
        well:Hide();
        if(chrome.input) then chrome.input:Hide(); end
        return false;
    end

    -- Minimal scrollbar inside the message well, in the gutter that the
    -- display's pulled-in right edge leaves free. This matches the
    -- History Viewer. The window's scroll buttons act as its steppers.
    if(display.GetMaxScrollRange and display.GetScrollOffset) then
        local bar = CreateFrame("Slider", nil, obj);
        bar:SetOrientation("VERTICAL");
        bar:SetWidth(16);
        bar:SetFrameLevel(obj:GetFrameLevel() + 2);
        bar:SetPoint("TOPRIGHT", display, "TOPRIGHT", 18, -19);
        bar:SetPoint("BOTTOMRIGHT", display, "BOTTOMRIGHT", 18, 19);
        bar:SetMinMaxValues(0, 0);
        bar:SetValueStep(1);
        bar:SetValue(0);
        local thumb = bar:CreateTexture(nil, "OVERLAY");
        bar:SetThumbTexture(thumb);
        thumb:SetAlpha(0);
        local capTop = bar:CreateTexture(nil, "ARTWORK");
        capTop:SetAtlas("minimal-scrollbar-small-thumb-top", true);
        capTop:SetPoint("TOP", thumb, "TOP");
        local capBottom = bar:CreateTexture(nil, "ARTWORK");
        capBottom:SetAtlas("minimal-scrollbar-small-thumb-bottom", true);
        capBottom:SetPoint("BOTTOM", thumb, "BOTTOM");
        local body = bar:CreateTexture(nil, "ARTWORK");
        body:SetAtlas("minimal-scrollbar-small-thumb-middle");
        body:SetPoint("TOPLEFT", capTop, "BOTTOMLEFT");
        body:SetPoint("BOTTOMRIGHT", capBottom, "TOPRIGHT");
        local trackTop = bar:CreateTexture(nil, "BACKGROUND");
        trackTop:SetAtlas("minimal-scrollbar-track-top", true);
        trackTop:SetPoint("TOP");
        local trackBottom = bar:CreateTexture(nil, "BACKGROUND");
        trackBottom:SetAtlas("minimal-scrollbar-track-bottom", true);
        trackBottom:SetPoint("BOTTOM");
        local trackMiddle = bar:CreateTexture(nil, "BACKGROUND");
        trackMiddle:SetAtlas("!minimal-scrollbar-track-middle");
        trackMiddle:SetPoint("TOPLEFT", trackTop, "BOTTOMLEFT");
        trackMiddle:SetPoint("BOTTOMRIGHT", trackBottom, "TOPRIGHT");
        -- Size the thumb after the track has settled. A thumb almost as
        -- long as the track leaves almost no drag travel.
        local function sizeThumb()
            local info = getAtlasInfo("minimal-scrollbar-small-thumb-middle");
            local trackHeight = bar:GetHeight() or 0;
            local thumbHeight = 56;
            if(trackHeight > 0) then
                local cap = _G.math.floor(trackHeight * 0.6);
                if(cap < 20) then cap = 20; end
                if(thumbHeight > cap) then thumbHeight = cap; end
            end
            thumb:SetSize(8, thumbHeight);
            if(info and info.height and info.height > 0) then
                local extent = (thumbHeight - 16) / info.height;
                if(extent > 1) then extent = 1; end
                body:SetTexCoord(0, 1, 0, extent);
            end
        end
        bar:HookScript("OnSizeChanged", sizeThumb);
        sizeThumb();
        bar.wimMaxRange = 0;
        bar:SetScript("OnValueChanged", function(self, value)
            if(self.wimSyncing) then return; end
            display:SetScrollOffset(self.wimMaxRange - _G.math.floor(value + 0.5));
        end);
        bar.wimElapsed = 1;
        bar:SetScript("OnUpdate", function(self, elapsed)
            self.wimElapsed = self.wimElapsed + elapsed;
            if(self.wimElapsed < 0.1) then return; end
            self.wimElapsed = 0;
            local maxRange = display:GetMaxScrollRange();
            self.wimSyncing = true;
            if(maxRange ~= self.wimMaxRange) then
                self.wimMaxRange = maxRange;
                self:SetMinMaxValues(0, maxRange);
            end
            self:SetValue(maxRange - display:GetScrollOffset());
            self.wimSyncing = false;
        end);
        bar:Hide();
        chrome.scrollBar = bar;
    end

    -- The fade logic keeps a window solid only while the mouse-focus
    -- frame is the window or is tagged with it. The slider receives
    -- mouse input, so every chrome piece carries the tag.
    chrome.parentWindow = obj;
    well.parentWindow = obj;
    if(chrome.input) then chrome.input.parentWindow = obj; end
    if(chrome.scrollBar) then chrome.scrollBar.parentWindow = obj; end

    obj.wimChrome = chrome;
    return true;
end

-- Steppers use the minimal arrow atlases, 16px wide to align with the
-- 8px tube. SetTexCoord applies within an atlas member, so the
-- coordinates are reset on every state change.
local function styleWindowStepper(button, up)
    local prefix = up and "minimal-scrollbar-arrow-top"
                   or "minimal-scrollbar-arrow-bottom";
    local states = {
        button:GetNormalTexture(), button:GetPushedTexture(),
        button:GetDisabledTexture(), button:GetHighlightTexture(),
    };
    local atlases = { prefix, prefix.."-down", prefix, prefix.."-over" };
    for i=1, #states do
        if(states[i]) then
            states[i]:SetAtlas(atlases[i]);
            states[i]:SetTexCoord(0, 1, 0, 1);
        end
    end
    local highlight = button:GetHighlightTexture();
    if(highlight) then highlight:SetBlendMode("BLEND"); end
    button:SetSize(16, 11);
end

-- The class-icon cells contain transparent padding, which makes the
-- emblem look small inside the portrait ring. Zoom the current cell's
-- texture coordinates inward so the emblem fills the circle. This runs
-- after every UpdateIcon (which resets the cell), so repeated runs are
-- safe.
function ZoomPortraitIcon(obj)
    local icon = obj.widgets and obj.widgets.class_icon;
    if(not icon) then return; end
    -- Roleplay profile portraits are full-frame images, not emblem
    -- cells. Their crop is applied where they are painted.
    if(obj.wimRPIcon) then return; end
    local ulx, uly, _, lly, urx = icon:GetTexCoord();
    local left, right, top, bottom = ulx, urx, uly, lly;
    local w, h = right - left, bottom - top;
    if(w <= 0 or h <= 0) then return; end
    -- Measured from the class-icon sheet: the emblem fills only the
    -- middle ~58% of its cell, with a ~20% transparent inset on each
    -- side. The zoom inset is slightly larger than that margin so the
    -- emblem spans the full circle instead of floating inside it. The
    -- circular mask hides the small overshoot at the edges.
    local ix, iy = w * 0.22, h * 0.22;
    icon:SetTexCoord(left + ix, right - ix, top + iy, bottom - iy);
end

-- Themed header layout. The title text runs between the circled
-- portrait and the corner button. The details text runs between the
-- portrait and the frame edge. The message well starts below whichever
-- needs more room. Text keeps its skin font size and shrinks to fit
-- long content, down to a minimum size. Past that minimum, a
-- single-line string truncates, and the details text word-wraps
-- (centered) and pushes the well down instead of overflowing into it.
-- The layout reruns on resize and on text changes, always from the
-- skin baseline the theme pass captured.
local HEADER_MIN_FONT = 10;

local function fitHeaderLine(fs, base, avail, wraps)
    if(not (fs and base) or not avail or avail <= 0) then return; end
    fs:SetFont(base.path, base.size, base.flags);
    local width = fs.GetUnboundedStringWidth
        and fs:GetUnboundedStringWidth() or fs:GetStringWidth();
    if(width and width > avail) then
        local size = math.floor(base.size * avail / width);
        if(size >= HEADER_MIN_FONT) then
            fs:SetFont(base.path, size, base.flags);
        elseif(not wraps) then
            fs:SetFont(base.path, HEADER_MIN_FONT, base.flags);
        end
        -- A wrapping string keeps the skin font size and wraps when
        -- even the minimum size cannot fit its longest line.
    end
end

function LayoutThemedHeader(obj)
    local chrome = obj.wimChrome;
    local widgets = obj.widgets;
    if(not (chrome and chrome:IsShown() and widgets)) then return; end
    local from, info = widgets.from, widgets.char_info;

    -- Center the title text in the band. The band's optical center is
    -- y -11.5 (the History Viewer's measurement). The usable span runs
    -- from the portrait circle (x 53.5) to the corner button (left
    -- edge -23).
    if(from and obj.wimFromBaseFont) then
        from:ClearAllPoints();
        from:SetPoint("LEFT", obj, "TOPLEFT", 56, -11.5);
        from:SetPoint("RIGHT", obj, "TOPRIGHT", -27, -11.5);
        from:SetJustifyH("CENTER");
        from:SetWordWrap(false);
        fitHeaderLine(from, obj.wimFromBaseFont, from:GetWidth(), false);
    end

    local infoBottom = -28;
    if(info and obj.wimInfoBaseFont) then
        info:ClearAllPoints();
        info:SetPoint("TOPLEFT", obj, "TOPLEFT", 56, -28);
        info:SetPoint("TOPRIGHT", obj, "TOPRIGHT", -8, -28);
        info:SetJustifyH("CENTER");
        info:SetWordWrap(true);
        info:SetNonSpaceWrap(true);
        fitHeaderLine(info, obj.wimInfoBaseFont, info:GetWidth(), true);
        infoBottom = -28 - (info:GetStringHeight() or 0);
    end

    -- The well (display top +6) starts below the circle or below the
    -- details text, whichever reaches lower. It never rises above the
    -- skin's own baseline.
    local basePoints = obj.wimDisplayBasePoints;
    local display = widgets.chat_display;
    local headerHeight = 54;
    if(display and basePoints) then
        local wellTop = infoBottom - 4;
        if(chrome.hasPortrait and wellTop > -54) then wellTop = -54; end
        local baseTop = obj.wimDisplayBaseTop;
        local deltaY = 0;
        local desiredTop = wellTop - 6;
        if(baseTop) then
            if(desiredTop > baseTop) then desiredTop = baseTop; end
            deltaY = desiredTop - baseTop;
        end
        headerHeight = -desiredTop;
        display:ClearAllPoints();
        for i=1, #basePoints do
            local p = basePoints[i];
            local x = p[4] or 0;
            local y = p[5] or 0;
            -- The right edge pulls in for the in-well scrollbar.
            if(string.find(p[1], "RIGHT")) then x = x - 18; end
            if(string.find(p[1], "TOP")) then y = y + deltaY; end
            display:SetPoint(p[1], p[2], p[3], x, y);
        end
    end

    -- Dynamic minimum height: the header, the current right-side
    -- column (its buttons hang from the well's top), and the input row
    -- must all fit inside the frame.
    local column = 0;
    local history = widgets.history;
    if(history and history:IsShown()) then
        column = column + (history:GetHeight() or 0) + 4;
    end
    local shortcuts = widgets.shortcuts;
    if(shortcuts and shortcuts:IsShown()) then
        local buttons = { shortcuts:GetChildren() };
        for i=1, #buttons do
            if(buttons[i]:IsShown()) then
                column = column + (buttons[i]:GetHeight() or 0) + 2;
            end
        end
    end
    local skinWindow = GetSelectedSkin().message_window;
    local minHeight = headerHeight + math.max(column, 60) + 44;
    if(skinWindow.min_height and minHeight < skinWindow.min_height) then
        minHeight = skinWindow.min_height;
    end
    local minWidth = skinWindow.min_width or 256;
    if(obj.SetResizeBounds) then
        obj:SetResizeBounds(minWidth, minHeight);
    elseif(obj.SetMinResize) then
        obj:SetMinResize(minWidth, minHeight);
    end
    if((obj:GetHeight() or 0) < minHeight - 0.5) then
        obj:SetHeight(minHeight);
    end
end

-- The themed close button shows the minimize glyph at rest (click
-- hides the window) and swaps to the X while SHIFT is held, because
-- SHIFT-click closes the conversation. The art always shows what the
-- click will do. curTextureIndex 2 is the always-close state.
function UpdateThemedCloseArt(obj)
    local close = obj.widgets and obj.widgets.close;
    if(not (close and close.GetNormalTexture)) then return; end
    local closes = _G.IsShiftKeyDown() or close.curTextureIndex == 2;
    local normalAtlas = closes and "RedButton-Exit" or "redbutton-condense";
    local pushedAtlas = closes and "RedButton-exit-pressed" or "redbutton-condense-pressed";
    local normal = close:GetNormalTexture();
    if(normal) then
        normal:SetAtlas(normalAtlas);
        normal:SetTexCoord(0, 1, 0, 1);
    end
    local pushed = close:GetPushedTexture();
    if(pushed) then
        pushed:SetAtlas(pushedAtlas);
        pushed:SetTexCoord(0, 1, 0, 1);
    end
    local highlight = close:GetHighlightTexture();
    if(highlight) then
        highlight:SetAtlas("RedButton-Highlight");
        highlight:SetTexCoord(0, 1, 0, 1);
        highlight:SetBlendMode("ADD");
    end
    close:SetSize(24, 24);
    close:ClearAllPoints();
    close:SetPoint("TOPRIGHT", obj, "TOPRIGHT", 1, 0);
end

-- Live art swap while SHIFT is pressed or released over themed windows.
local shiftWatcher = CreateFrame("Frame");
shiftWatcher:RegisterEvent("MODIFIER_STATE_CHANGED");
shiftWatcher:SetScript("OnEvent", function(_, _, key)
    if(key ~= "LSHIFT" and key ~= "RSHIFT") then return; end
    local windowList = WindowSoupBowl.windows;
    for i=1, #windowList do
        local win = windowList[i].obj;
        if(win and win.wimChrome and win.wimChrome:IsShown()) then
            UpdateThemedCloseArt(win);
        end
    end
end);

function ApplyModernThemeToWindow(obj)
    local theme = db and db.modernTheme;
    local skin = GetSelectedSkin();
    local active = (theme and skin and skin.modernOnly) and true or false;
    local widgets = obj.widgets;
    local bd = widgets and widgets.Backdrop;
    if(not (bd and bd.bg and widgets.chat_display)) then return; end

    if(active and not obj.wimChrome and not obj.wimChromeFailed) then
        obj.wimChromeFailed = not buildWindowChrome(obj);
    end
    local chrome = active and obj.wimChrome or nil;

    -- The skin's own backdrop pieces hide while the chrome is shown.
    -- They return when the chrome goes: ApplySkinToWindow reapplies
    -- their art on each pass before this code runs.
    local skinShown = (chrome == nil);
    bd.tl:SetShown(skinShown); bd.tr:SetShown(skinShown);
    bd.bl:SetShown(skinShown); bd.br:SetShown(skinShown);
    bd.t:SetShown(skinShown); bd.b:SetShown(skinShown);
    bd.l:SetShown(skinShown); bd.r:SetShown(skinShown);
    bd.bg:SetShown(skinShown);
    -- Themed windows show the class icon only as the circled portrait
    -- (below); without the portrait layout the icon would poke outside
    -- the window's top-left over the chrome (a live dump measured it
    -- 10px past the edge).
    if(widgets.class_icon) then
        local hasPortrait = obj.wimChrome and obj.wimChrome.hasPortrait;
        widgets.class_icon:SetShown(skinShown or (chrome ~= nil and hasPortrait and true or false));
        if(skinShown and obj.wimPortraitMasked) then
            widgets.class_icon:RemoveMaskTexture(obj.wimPortraitMask);
            obj.wimPortraitMasked = nil;
        end
    end

    if(obj.wimChrome) then
        obj.wimChrome:SetShown(chrome ~= nil);
        obj.wimChrome.well:SetShown(chrome ~= nil);
        if(obj.wimChrome.input) then
            obj.wimChrome.input:SetShown(chrome ~= nil);
        end
        if(obj.wimChrome.scrollBar) then
            obj.wimChrome.scrollBar:SetShown(chrome ~= nil);
        end
    end
    if(not chrome) then
        if(obj.wimBackdropLevel) then
            bd.bg:GetParent():SetFrameLevel(obj.wimBackdropLevel);
        end
        return;
    end

    -- The class icon, name, and details live on the Backdrop host
    -- frame, which shares a level with the chrome and would draw under
    -- its rock fill. Raise it while themed; the classic path above
    -- restores it.
    local backdropHost = bd.bg:GetParent();
    if(obj.wimBackdropLevel == nil) then
        obj.wimBackdropLevel = backdropHost:GetFrameLevel();
    end
    backdropHost:SetFrameLevel(obj:GetFrameLevel() + 2);

    -- Header layout baselines: the skin re-lays the display and the
    -- header fonts each pass, so what is current here is the clean
    -- baseline LayoutThemedHeader adjusts from (repeatedly, without
    -- compounding).
    local display = widgets.chat_display;
    local displayPoints = {};
    for i=1, display:GetNumPoints() do
        displayPoints[i] = { display:GetPoint(i) };
    end
    obj.wimDisplayBasePoints = displayPoints;
    local dTop, oTop = display:GetTop(), obj:GetTop();
    if(dTop and oTop) then
        obj.wimDisplayBaseTop = dTop - oTop;
    else
        for i=1, #displayPoints do
            local p = displayPoints[i];
            if(string.find(p[1], "TOP") and p[2] == obj) then
                obj.wimDisplayBaseTop = p[5] or 0;
                break;
            end
        end
    end
    if(widgets.from) then
        -- The title band text uses the History Viewer's gold 12px
        -- style. This is the baseline size the fit shrinks from.
        local fontPath = _G.GameFontNormal:GetFont();
        widgets.from:SetTextColor(_G.GameFontNormal:GetTextColor());
        obj.wimFromBaseFont = { path = fontPath, size = 12, flags = "" };
    end
    if(widgets.char_info) then
        local path, size, flags = widgets.char_info:GetFont();
        if(path) then obj.wimInfoBaseFont = { path = path, size = size, flags = flags }; end
    end
    if(not obj.wimHeaderSizeHooked) then
        obj.wimHeaderSizeHooked = true;
        obj:HookScript("OnSizeChanged", function(self)
            if(self.wimChrome and self.wimChrome:IsShown()) then
                LayoutThemedHeader(self);
            end
        end);
    end
    if(not obj.wimCharDetailsWrapped) then
        obj.wimCharDetailsWrapped = true;
        local origUpdateCharDetails = obj.UpdateCharDetails;
        obj.UpdateCharDetails = function(self, ...)
            origUpdateCharDetails(self, ...);
            if(self.wimChrome and self.wimChrome:IsShown()) then
                LayoutThemedHeader(self);
            end
        end;
    end
    if(chrome.scrollBar) then
        local up, down = widgets.scroll_up, widgets.scroll_down;
        if(up and down) then
            styleWindowStepper(up, true);
            styleWindowStepper(down, false);
            up:ClearAllPoints();
            up:SetPoint("BOTTOM", chrome.scrollBar, "TOP", 0, 8);
            down:ClearAllPoints();
            down:SetPoint("TOP", chrome.scrollBar, "BOTTOM", 0, -8);
        end
    end

    -- The right-side column: the history shortcut at the top, the
    -- shortcut buttons stacked beneath it, all centered on one axis
    -- level with the message well's top. The shortcut container needs
    -- an explicit size; without one it collapses to zero width (its
    -- buttons span its edges) and the icons disappear.
    local history = widgets.history;
    local columnAnchor = chrome.well;
    if(history) then
        history:ClearAllPoints();
        history:SetPoint("TOP", chrome.well, "TOPRIGHT", 15, 0);
        columnAnchor = history;
    end
    if(widgets.shortcuts) then
        widgets.shortcuts:SetSize(22, 150);
        widgets.shortcuts:ClearAllPoints();
        if(columnAnchor == history) then
            widgets.shortcuts:SetPoint("TOP", history, "BOTTOM", 0, -4);
        else
            widgets.shortcuts:SetPoint("TOP", chrome.well, "TOPRIGHT", 15, 0);
        end
    end

    -- The class icon becomes the circled portrait in the carved
    -- corner, like the community icon on the Guild & Communities
    -- panel. The ring's opening is 49px across, centered at
    -- (26, -25.5) in window coordinates (measured from the corner
    -- piece's pixels). The icon draws slightly larger so it meets the
    -- ring's inner lip, and its texture cell zooms in past the cell's
    -- transparent padding so the emblem fills the circle.
    if(widgets.class_icon and chrome.hasPortrait) then
        local icon = widgets.class_icon;
        icon:ClearAllPoints();
        -- The ring's gold band has an inner diameter of about 53px,
        -- centered at (25.5, -22) in window coordinates (measured from
        -- the opaque runs along the corner piece's center row and
        -- column). The icon slightly overlaps the lip's anti-aliasing.
        icon:SetPoint("CENTER", obj, "TOPLEFT", 25.5, -22);
        icon:SetSize(56, 56);
        if(not obj.wimPortraitMask) then
            local mask = icon:GetParent():CreateMaskTexture();
            -- CircleMaskScalable's circle reaches the mask's edges
            -- (the portrait alpha-mask file bakes in padding that
            -- shrank the visible circle short of the ring). The atlas
            -- path is the reliable one -- a mask fed the file id
            -- directly reports as attached yet fails to clip in some
            -- sessions (state-dump verified both ways) -- with the
            -- file id kept as the fallback.
            local usedAtlas = mask.SetAtlas
                and pcall(mask.SetAtlas, mask, "CircleMaskScalable")
                and mask:GetAtlas() ~= nil;
            if(not usedAtlas) then
                mask:SetTexture(3605349,
                    "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE");
            end
            mask:SetAllPoints(icon);
            obj.wimPortraitMask = mask;
        end
        if(not obj.wimPortraitMasked) then
            icon:AddMaskTexture(obj.wimPortraitMask);
            obj.wimPortraitMasked = true;
        end
        if(not obj.wimUpdateIconWrapped) then
            obj.wimUpdateIconWrapped = true;
            local origUpdateIcon = obj.UpdateIcon;
            obj.UpdateIcon = function(self, ...)
                origUpdateIcon(self, ...);
                if(self.wimChrome and self.wimChrome:IsShown()
                        and self.wimChrome.hasPortrait) then
                    ZoomPortraitIcon(self);
                end
            end;
        end
        -- A full repaint, not just a zoom. The zoom multiplies the
        -- icon's current coordinates, so zooming an already-zoomed
        -- icon shrinks the emblem one step further on every settings
        -- change that reapplies the skin. The repaint resets the
        -- coordinates before the wrapper above zooms them once.
        obj:UpdateIcon();
    end


    local cutout = theme.chatCutout and true or false;
    chrome.bg:SetShown(not cutout);
    if(not cutout) then
        ApplyChromeBackgroundChoice(chrome.bg, theme.chatFrame);
    end
    for i=1, #chrome.strips do
        chrome.strips[i]:SetShown(cutout);
        if(cutout) then
            ApplyChromeBackgroundChoice(chrome.strips[i], theme.chatFrame);
        end
    end
    ApplyChromeBackgroundChoice(chrome.well.bg, theme.chatPanel);

    LayoutThemedHeader(obj);

    -- The corner button: minimize glyph at rest, the X while SHIFT
    -- is held (see UpdateThemedCloseArt).
    UpdateThemedCloseArt(obj);
end

local function deleteStyleFileEntries(theTable)
    if(type(theTable) == "table") then
        for key, _ in pairs(theTable) do
            theTable[key] = nil;
        end
    end
end

function RegisterPrematureSkins()
    for i=1,#prematureRegisters do
        RegisterSkin(prematureRegisters[i]);
    end
end

function GetSelectedSkin()
    return SelectedSkin or SkinTable["WIM Classic"];
end

-- Only the modern options UI offers modern-only skins. While one is
-- selected, the options style must not switch back to classic, because
-- the classic window could never offer the skin again. Code that
-- changes the style checks this function.
function SkinLocksOptionsStyle()
    local skin = GetSelectedSkin();
    return (skin and skin.modernOnly) and true or false;
end

-- A skin's `title` doubles as its identity: RegisterSkin stores skins as
-- SkinTable[skinTable.title], and db.skin.selected persists that same string.
-- Upstream 3.17.2 localized the four classic colour variants
-- ("WIM Classic - Blue" -> "WIM Classic - "..L["Blue"]), which silently changes
-- the key on every non-English client: the saved selection no longer matches
-- anything in SkinTable and LoadSkin falls back to the base skin, quietly
-- discarding the user's choice. (English clients are unaffected, because
-- L["Blue"] returns "Blue", which is presumably why it went unnoticed.)
--
-- Map the pre-3.17.2 English titles onto whatever those skins are called now.
-- Keyed by colour so it stays correct whatever the active locale is.
local legacySkinTitles = {
    ["WIM Classic - Blue"]   = "Blue",
    ["WIM Classic - Green"]  = "Green",
    ["WIM Classic - Red"]    = "Red",
    ["WIM Classic - Yellow"] = "Yellow",
};

local function resolveSkinName(skinName)
    if(skinName == nil) then
        return nil;
    end
    if(SkinTable[skinName]) then
        return skinName;
    end
    local colour = legacySkinTitles[skinName];
    if(colour) then
        local localized = "WIM Classic - "..L[colour];
        if(SkinTable[localized]) then
            return localized;
        end
    end
    return nil;
end

function LoadSkin(skinName, immutableDB)
    skinName = resolveSkinName(skinName) or "WIM Classic";

    SelectedSkin = SkinTable[skinName];

    if not immutableDB then
        db.skin.selected = skinName;
    end;

    SKIN_DEBUG = SKIN_DEBUG..skinName.." loaded..\n";
    -- apply skin to window objects
    local window_objects = WindowSoupBowl.windows;
    for i=1, table.getn(window_objects) do
        ApplySkinToWindow(window_objects[i].obj);
    end

    ApplySkinToTabs();

	CallModuleFunction("OnSkinLoaded", SelectedSkin);

    -- A modern-only skin requires the modern options UI (see
    -- SkinLocksOptionsStyle). Selecting one turns that UI on.
    if(SelectedSkin and SelectedSkin.modernOnly and db and not db.modernOptions
            and SetOptionsStyle) then
        SetOptionsStyle(true);
    end
end

function RegisterFont(objName, title)
    if(objName == nil or objName == "") then
        return;
    end
    if(title == nil or title == "") then
        title = objName
    end
    if(getglobal(objName)) then
        fontTable[objName] = title;
    else
        DEFAULT_CHAT_FRAME:AddMessage("WIM SKIN ERROR: Registered font object does not exist!");
    end
end


function RegisterSkin(skinTable)
    if(not isInitialized) then
        table.insert(prematureRegisters, skinTable);
        return;
    end
    local required = {"title", "author", "version"};
    local error_list = "";
    local addonName;

    local stack = {string.split("\n", debugstack())};
    if(table.getn(stack) >= 2) then
        local paths = {string.split("\\", stack[2])};
        addonName = paths[3];
    else
        addonName = "Unknown";
    end

    for i=1,table.getn(required) do
        if(skinTable[required[i]] == nil or skinTable[required[i]] == "") then error_list = error_list.."- Required field '"..required[i].."' was not defined.\n"; end
    end


    if(error_list ~= "") then
        SKIN_DEBUG = SKIN_DEBUG.."\n\n---------------------------------------------------------\nSKIN ERROR FROM: "..addonName.."\n---------------------------------------------------------\n";
        SKIN_DEBUG = SKIN_DEBUG.."Skin was not loaded for the following reason(s):\n\n"..error_list.."\n\n";
        return;
    end

	-- normalize all fonts
	for _, path in pairs(fontPaths) do
		local tbl = skinTable;
		for key in string.gmatch(path, "[^.]+") do
			if (key ~= "root") then
				if (tbl[key] == nil) then
					break;
				elseif (type(tbl[key]) == "table") then
					tbl = tbl[key];
				else
					tbl[key] = normalizeFont(tbl[key]);
					break;
				end
			end
		end
	end

    if(skinTable.title == "WIM Classic") then
        SkinTable[skinTable.title] = skinTable;
        if(skinTable.title == resolveSkinName(db.skin.selected)) then
            LoadSkin(WIM.db.skin.selected);
        end
        return; -- this is the main skin, we don't need to do anything further...
    end

    -- inherrit missing data from default skin.
    linkSkinTable(SkinTable["WIM Classic"], skinTable);

    -- finalize registration
    SkinTable[skinTable.title] = skinTable;

    -- if this is the selected skin, load it now
    if(skinTable.title == resolveSkinName(WIM.db.skin.selected)) then
        LoadSkin(WIM.db.skin.selected);
    end
end

function GetFontKeyByName(fontName)
	for key, val in pairs(fontTable) do
		if(val == fontName) then
			return key;
		end
	end
	return nil;
end


function SetWidgetFont(obj, widgetSkinTable)
    -- first check what font is being requested, height is applied here.
    if(widgetSkinTable.font) then
		local _font = (db.skin.suggest or not obj._allowCustomFont) and widgetSkinTable.font or db.skin.font or widgetSkinTable.font;

        if(_G[_font] and _G[_font].GetFont) then
            -- font is to be inherrited. The RESOLVED font must be used for
            -- both calls: taking the object from the skin and the family
            -- from ChatFontNormal would mean a custom font object never
            -- actually changes the rendered family.
            obj:SetFontObject(_G[_font]);
            local font, height, flags = _G[_font]:GetFont();
            obj:SetFont(font, widgetSkinTable.font_height or height, obj._font_flags or widgetSkinTable.font_flags or flags);
        elseif(libs.SML.MediaTable.font[_font]) then
			-- _G.DevTools_Dump({obj.widgetName ,_font, widgetSkinTable.font_height, obj._font_flags or widgetSkinTable.font_flags or ""});
            obj:SetFont(libs.SML.MediaTable.font[_font], widgetSkinTable.font_height or 12, obj._font_flags or widgetSkinTable.font_flags or "");
		elseif (type(_font) == "string" and _font:match("\\")) then
			-- font is a path to a font file
			obj:SetFont(_font, widgetSkinTable.font_height or 12, obj._font_flags or widgetSkinTable.font_flags or "");
		else
            -- can't find font, load a default font.
            local font, height, flags = _G["ChatFontNormal"]:GetFont();
            obj:SetFont(font, widgetSkinTable.font_height or 12, obj._font_flags or widgetSkinTable.font_flags or "");
        end
    end
    -- next, lets add the extra properties to it.
    if(widgetSkinTable.font_color) then
        if(type(widgetSkinTable.font_color) == "table") then
            obj:SetTextColor(unpack(widgetSkinTable.font_color));
        else
            obj:SetTextColor(RGBHexToPercent(widgetSkinTable.font_color));
        end
    end
end

function SetWidgetRect(obj, widgetSkinTable)
    if(type(widgetSkinTable) == "table") then
        if(type(widgetSkinTable.width) == "number") then
            obj:SetWidth(widgetSkinTable.width);
        end
        if(type(widgetSkinTable.height) == "number") then
            obj:SetHeight(widgetSkinTable.height);
        end
        if(widgetSkinTable.points) then
            setPointsToObj(obj, widgetSkinTable.points);
        end
    end
end

function ApplySkinToWidget(obj)
    if(obj.GetObjectType) then
        local SelectedSkin = GetSelectedSkin();
        local widgetSkin = SelectedSkin.message_window.widgets[obj.widgetName] or obj.defaultSkin;
        local oType = obj:GetObjectType();
        SetWidgetRect(obj, widgetSkin);
        if(oType == "Button" or oType == "CheckButton") then
            if(widgetSkin.NormalTexture) then obj:SetNormalTexture(widgetSkin.NormalTexture); end
            if(widgetSkin.PushedTexture) then obj:SetPushedTexture(widgetSkin.PushedTexture); end
            if(widgetSkin.DisabledTexture) then obj:SetDisabledTexture(widgetSkin.DisabledTexture); end
            if(widgetSkin.HighlightTexture) then obj:SetHighlightTexture(widgetSkin.HighlightTexture, widgetSkin.HighlightAlphaMode); end
        end
        if(oType == "FontString" or oType == "ScrollingMessageFrame" or oType == "EditBox" or (oType == "Frame" and obj.AddMessage)) then
            SetWidgetFont(obj, widgetSkin);
        end
    else
        dPrint("Invalid widget trying to be skinned.");
    end
    if(obj.UpdateSkin) then
        obj:UpdateSkin();
    end
end

function GetSkinTable(skinName)
    return SkinTable[skinName];
end

function GetRegisteredSkins(includeModernOnly)
    -- this function isn't called much so its ok to create a little garbage.
    local list = {};
    local selected = GetSelectedSkin().title;
    for skin, skinTable in pairs(SkinTable) do
        -- Skins flagged modernOnly appear only when the caller asks for
        -- them (the modern options UI). Other callers still see such a
        -- skin while it is the active selection, so their dropdown
        -- always shows the current state correctly.
        if(includeModernOnly or not skinTable.modernOnly or skin == selected) then
            table.insert(list, skin);
        end
    end
    table.sort(list);
    return list;
end
