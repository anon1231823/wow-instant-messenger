-- handles slash commands for clearing various data such as history and filters.

local L = WIM.L;
local CommandListRaw = {"history", "filters"};

local function clearFun(sub)
    sub = string.trim(string.lower(sub));
    if(sub == "history") then
        StaticPopupDialogs["WIM_CLEAR_HISTORY"] = {
        	preferredIndex = STATICPOPUP_NUMDIALOGS,
            text = L["You are about to clear all of WIM's history!"].."\n"..L["This action will reload your user interface."].."\n"..L["Do you want to continue?"],
            button1 = _G.YES,
            button2 = _G.NO,
            OnAccept = function()
                -- History now lives in several places -- the account-wide
                -- blob archive, this character's own per-character file, and the
                -- legacy holding pen. All of them must go, or the archive (or a
                -- leftover legacy table) would repopulate the viewer on reload.
                WIM3_History = nil;
                WIM3_HistoryArchive = nil;
                WIM3_HistorySchema = nil;
                -- pre-rename name, in case it was adopted this session and is
                -- still resident in memory:
                WIM3_History = nil;
                ReloadUI();
            end,
            timeout = 0,
            whileDead = 1,
            hideOnEscape = 1
        };
        StaticPopup_Show ("WIM_CLEAR_HISTORY");
    elseif(sub == "filters") then
        StaticPopupDialogs["WIM_CLEAR_FILTERS"] = {
        	preferredIndex = STATICPOPUP_NUMDIALOGS,
            text = L["You are about to restore WIM's filters to it's default settings!"].."\n"..L["This action will reload your user interface."].."\n"..L["Do you want to continue?"],
            button1 = _G.YES,
            button2 = _G.NO,
            OnAccept = function()
                WIM3_Filters = nil;
                WIM3_Filters = nil;   -- pre-rename name
                ReloadUI();
            end,
            timeout = 0,
            whileDead = 1,
            hideOnEscape = 1
        };
        StaticPopup_Show ("WIM_CLEAR_FILTERS");
    else
        DEFAULT_CHAT_FRAME:AddMessage("|cff69ccf0"..L["Usage"]..":|r  ".."/wim clear {"..string.lower(table.concat(CommandListRaw, " | ")).."}");
    end
end

WIM.RegisterSlashCommand("clear", clearFun, L["Clear various WIM data."])
