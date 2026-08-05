--imports
local WIM = WIM;
local _G = _G;
local table = table;
local string = string;
local pairs = pairs;
local CreateFrame = CreateFrame;
local date = date;
local time = time;
local select = select;
local tonumber = tonumber;
-- 3.16.13: extra builtins needed by the history size guardrail. These have to
-- be captured as locals BEFORE the setfenv(1, WIM) below, otherwise they
-- resolve through the WIM table (which doesn't contain them) and come back
-- nil at runtime.
local type = type;
local next = next;
local pcall = pcall;
local ipairs = ipairs;
local math = math;
local tostring = tostring;

local DDM = WIM.libs.DropDownMenu;

--set namespace
setfenv(1, WIM);

local History = CreateModule("History", true);

-- default history settings.
db_defaults.history = {
    preview = true,
    previewCount = 25,
    maxPer = true,
    maxCount = 500,
    ageLimit = true,
    maxAge = 60*60*24*7*2,
    whispers = {
        friends = true,
        guild = true,
        all = true
    },
    chat = {
        -- 3.18.0: record Community (Club) chat. Defaults OFF, matching every
        -- other chat type here -- guild, officer, party, raid, say, world and
        -- custom are all absent from these defaults and so start nil/false.
        -- Enabled from Options > Chat > History; per-community opt-out lives in
        -- db.chat.community.channelSettings[key].noHistory.
        community = false,
        preview = true,
        previewCount = 25,
        maxPer = true,
        maxCount = 500,
        ageLimit = true,
        maxAge = 60*60*24*7*2,
    },
    -- 3.16.13/3.16.14: Guardrail. When enabled, WIM stops appending new records
    -- once the estimated unique-constant count of the per-character
    -- SavedVariables chunk approaches a configurable ceiling. The hard limit is
    -- Lua 5.1's MAXARG_Bx = 2^18 - 1 = 262,143 unique constants per chunk.
    -- Default 240 (×1000 = 240,000) leaves headroom below the hard cap.
    guardrail = {
        enabled = true,
        maxConstants = 240,
    },
};
db_defaults.displayColors.historyIn = {
    r=0.4705882352941176,
    g=0.4705882352941176,
    b=0.4705882352941176
};
db_defaults.displayColors.historyOut = {
    r=0.7058823529411764,
    g=0.7058823529411764,
    b=0.7058823529411764
};

local dDay = 60*60*24;
local dWeek = dDay*7;
local dMonth = dWeek*4;
local dYear = dMonth*12;

local tmpTable = {};

local ViewTypes = {};

local ChannelCache = {};
local CensoredCache = {};

local function clearTmpTable()
    for key, _ in pairs(tmpTable) do
        tmpTable[key] = nil;
    end
end

local function isEmptyTable(tbl)
    for k, _ in pairs(tbl) do
        if(k ~= "info") then
            return false;
        end
    end
    return true;
end


-- ----------------------------------------------------------------------------
-- 3.16.14: History constant-count guardrail.
--
-- Lua 5.1's bytecode format limits each chunk to MAXARG_Bx = 2^18 - 1 =
-- 262,143 unique constants. WoW loads each SavedVariables file as a single
-- chunk. When the per-character history file's unique string + number literals
-- exceed this ceiling the client emits "constant table overflow" and resets
-- the file. This guardrail tracks the exact metric -- unique constants -- and
-- refuses new appends before the limit is hit.
--
-- A persistent in-memory set (`constantSet`) holds every unique string and
-- number value observed in the current character's history. Its size IS the
-- constant count. On insert, new values are checked against the set in O(1).
-- On bulk deletes a full recompute reconciles the set (we cannot efficiently
-- decrement because we don't track reference counts).

local constantSet = {};
local estimatedConstantCount = 0;

local guardrailWarnedThisSession = false;

local function addConstant(value)
    local t = type(value);
    if (t ~= "string" and t ~= "number") then
        return;
    end
    if (not constantSet[value]) then
        constantSet[value] = true;
        estimatedConstantCount = estimatedConstantCount + 1;
    end
end

local function addRecordConstants(record, index)
    if (type(record) ~= "table") then return; end
    addConstant(index);
    for k, v in pairs(record) do
        addConstant(k);
        if (type(v) == "string" or type(v) == "number") then
            addConstant(v);
        elseif (type(v) == "table") then
            for k2, v2 in pairs(v) do
                addConstant(k2);
                if (type(v2) == "string" or type(v2) == "number") then
                    addConstant(v2);
                end
            end
        end
    end
end

local function recomputeConstantCount()
    table.wipe(constantSet);
    estimatedConstantCount = 0;
    if (type(history) ~= "table"
        or not history[env.realm]
        or not history[env.realm][env.character])
    then
        return 0;
    end
    local charHistory = history[env.realm][env.character];
    for convoKey, convoTable in pairs(charHistory) do
        addConstant(convoKey);
        if (type(convoTable) == "table") then
            for key, value in pairs(convoTable) do
                addConstant(key);
                if (type(value) == "string" or type(value) == "number") then
                    addConstant(value);
                elseif (type(value) == "table") then
                    for k2, v2 in pairs(value) do
                        addConstant(k2);
                        if (type(v2) == "string" or type(v2) == "number") then
                            addConstant(v2);
                        elseif (type(v2) == "table") then
                            for k3, v3 in pairs(v2) do
                                addConstant(k3);
                                if (type(v3) == "string" or type(v3) == "number") then
                                    addConstant(v3);
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    return estimatedConstantCount;
end

function RecomputeHistoryConstants()
    return recomputeConstantCount();
end

function GetEstimatedConstantCount()
    if (estimatedConstantCount == 0
        and history
        and history[env.realm]
        and history[env.realm][env.character]
        and next(history[env.realm][env.character]) ~= nil)
    then
        recomputeConstantCount();
    end
    return estimatedConstantCount;
end

local function isHistoryWriteBlocked()
    local g = db and db.history and db.history.guardrail;
    if (not g or not g.enabled) then
        return false;
    end
    local maxConstants = (g.maxConstants or 240) * 1000;
    return estimatedConstantCount >= maxConstants;
end

local function warnHistoryFull()
    if (guardrailWarnedThisSession) then
        return;
    end
    guardrailWarnedThisSession = true;
    local g = db and db.history and db.history.guardrail;
    local cap = (g and g.maxConstants or 240) * 1000;
    _G.DEFAULT_CHAT_FRAME:AddMessage(string.format(
        "|cffff4040[WIM]|r Saved history has reached the configured guardrail "
        .."limit of %d,000 unique constants (Lua limit: 262,143). To protect "
        .."the integrity of your saved data, further messages will NOT be "
        .."recorded until you free up space (use the History Viewer to delete "
        .."old conversations) or raise the limit in the WIM options under "
        .."General -> Main -> History Safety. You can also disable the "
        .."guardrail entirely from there.",
        cap / 1000
    ));
    if (_G.PlaySound) then
        pcall(_G.PlaySound, 8959, "Master");
    end
end

function ResetHistoryGuardrailWarning()
    guardrailWarnedThisSession = false;
end

local function pruneHistory(historyTable, maxCount)
    local pruned = 0;
    while (maxCount < #historyTable) do
        table.remove(historyTable, 1);
        pruned = pruned + 1;
    end
    if (pruned > 50) then
        recomputeConstantCount();
    end
end
-- ----------------------------------------------------------------------------


-- ----------------------------------------------------------------------------
-- 3.16.14: Battle.net friend consolidation.
--
-- WIM stores BN whispers keyed by the friend's BattleTag (e.g. "Friend#1234")
-- or legacy RealID email under whichever character was active at the time.
-- That means a single BN conversation with one friend is fragmented across
-- every realm/character you talked to them from. The History Viewer used to
-- only let you select a realm or a specific character, so there was no way to
-- see your full conversation with a BN friend across all your toons in one
-- place.
--
-- These helpers expose a synthetic "BN" pseudo-realm in the dropdown. Selecting
-- "BN/<BattleTag>" causes the user list, convo list, and search to walk EVERY
-- (realm, character) slot in the history tree and pull out only the records
-- whose convo key matches the chosen BattleTag.
--
-- The per-character entries that show this same BN friend are intentionally
-- preserved alongside the consolidated view (see user request: "keep
-- per-character BN entries AND add a consolidated section").

-- BN_PSEUDO_REALM is the magic top-level key used by the dropdown to flag
-- "this is a BN-friend consolidated view, not an actual realm". Picked so it
-- can never collide with a real realm name; WoW realm names cannot contain
-- the literal sequence "@BN@".
BN_PSEUDO_REALM = "@BN@";

-- 3.18.0: Community (Club) chats are recorded per-character like any other
-- channel, but they belong to the ACCOUNT rather than to a character -- the same
-- community is the same conversation whoever you were logged in as. The History
-- Viewer therefore consolidates them under a pseudo-realm, exactly as it does
-- for Battle.net friends.
--
-- Conversations are keyed by "clubId:streamId" (what upstream's ChatEngine uses
-- as the window/user name). That key is stable but unreadable, so the display
-- name is captured into the conversation's info table at record time and
-- refreshed on every message: a club can be renamed or left, and the raw key is
-- all we would otherwise have left to show.
COMMUNITY_PSEUDO_REALM = "@COMMUNITY@";

-- Returns true if `convoKey` looks like a Battle.net handle (a BattleTag like
-- "Friend#1234" or a legacy RealID like "user@example.com"). BattleTags and
-- email addresses contain characters that cannot appear in a player name or
-- channel name, which makes this detection cheap and unambiguous.
local function isBNConvoKey(convoKey)
    if (type(convoKey) ~= "string") then
        return false;
    end
    -- "#" is the BattleTag discriminator separator; "@" is the legacy RealID
    -- email form. Neither character can appear in a player name (which is
    -- letters only) or a chat channel name.
    return string.find(convoKey, "#", 1, true) ~= nil
        or string.find(convoKey, "@", 1, true) ~= nil;
end

-- Walks the entire history tree and returns a {BattleTag = true} set of every
-- BN handle that appears in any conversation, on any realm, on any character.
-- Used by the dropdown builder to enumerate the BN section.
-- Returns { [convoKey] = displayName } for every Community chat recorded
-- anywhere on the account. Like the Battle.net list this is an account-wide
-- consolidation, so everything has to be resident first.
function GetAllCommunityConvos()
    local found = {};
    if (type(history) ~= "table") then
        return found;
    end
    EnsureAllHistoryLoaded();
    for realm, characters in pairs(history) do
        if (realm ~= BN_PSEUDO_REALM and realm ~= COMMUNITY_PSEUDO_REALM
            and type(characters) == "table")
        then
            for _, convos in pairs(characters) do
                if (type(convos) == "table") then
                    for convoKey, convo in pairs(convos) do
                        if (type(convo) == "table" and type(convo.info) == "table"
                            and convo.info.community)
                        then
                            -- Prefer whichever copy carries a display name; a
                            -- character that only ever saw the club before it
                            -- was renamed may have none.
                            found[convoKey] = convo.info.displayName
                                              or found[convoKey] or convoKey;
                        end
                    end
                end
            end
        end
    end
    return found;
end

function GetAllBNConvoKeys()
    local seen = {};
    if (type(history) ~= "table") then
        return seen;
    end
    -- The Battle.net section is an account-wide consolidation, so every
    -- character must be loaded before it can be enumerated. Without this,
    -- the list silently reflects only the characters that happen to be
    -- loaded, which is the bug the blob archive exists to fix.
    EnsureAllHistoryLoaded();
    for _, characters in pairs(history) do
        if (type(characters) == "table") then
            for _, convos in pairs(characters) do
                if (type(convos) == "table") then
                    for convoKey, _ in pairs(convos) do
                        if (isBNConvoKey(convoKey)) then
                            seen[convoKey] = true;
                        end
                    end
                end
            end
        end
    end
    return seen;
end

-- Iterates every conversation (across all realms, all characters) whose key
-- matches `bnKey`. The callback receives the conversation table and the
-- (realm, character) pair it lives under, so callers can produce records
-- annotated with origin context if needed.
-- Walks every (realm, character) slot and invokes `callback` for each copy of
-- the conversation keyed by `bnKey`. Despite the name this is generic: it backs
-- both the Battle.net friend consolidation and, since 3.18.0, the Community
-- chat consolidation, which aggregate the same way.
local function forEachBNConvo(bnKey, callback)
    if (type(history) ~= "table") then
        return;
    end
    for realm, characters in pairs(history) do
        if (realm ~= BN_PSEUDO_REALM and realm ~= COMMUNITY_PSEUDO_REALM
            and type(characters) == "table") then
            for character, convos in pairs(characters) do
                if (type(convos) == "table") then
                    local convo = convos[bnKey];
                    if (type(convo) == "table") then
                        callback(convo, realm, character);
                    end
                end
            end
        end
    end
end
-- ----------------------------------------------------------------------------


local function getPlayerHistoryTable(convoName)
    if(history[env.realm] and history[env.realm][env.character] and history[env.realm][env.character][convoName]) then
        return history[env.realm][env.character][convoName];
    else
        -- this player hasn't been set up yet. Do it now.
        history[env.realm] = history[env.realm] or {};
        history[env.realm][env.character] = history[env.realm][env.character] or {};
        history[env.realm][env.character][convoName] = history[env.realm][env.character][convoName] or {info = {}};
        return history[env.realm][env.character][convoName];
    end
end


local function createWidget()
    local button = _G.CreateFrame("Button");
    button.SetHistory = function(self, isHistory)
        self.parentWindow.isHistory = isHistory;
        if(isHistory and modules.History.enabled) then
            self:SetAlpha(1);
  --          DisplayTutorial(L["WIM History Button"], _G.format(L["Clicking the %s button on the message window will show that user's history in WIM's History Viewer."],
  --                  "|T"..GetSelectedSkin().message_window.widgets.history.NormalTexture..":0:0:0:0|t"));
        else
            self:SetAlpha(0);
        end
    end
    button.UpdateProps = function(self)
        self:SetHistory(self.parentWindow.isHistory);
    end
    button:SetScript("OnEnter", function(self)
        if(db.showToolTips == true and self.parentWindow.isHistory) then
            _G.GameTooltip:SetOwner(self, "ANCHOR_TOPRIGHT");
            _G.GameTooltip:SetText(L["Click to view message history."]);
        end
    end);
    button:SetScript("OnLeave", function(self)
        _G.GameTooltip:Hide();
    end);
    button:SetScript("OnClick", function(self, button)
        if(self.parentWindow.isHistory) then
            ShowHistoryViewer(self.parentWindow.theUser);
        end
    end);
    return button;
end

-- store a cached entry if a record is cached. This will be used by History:ReplaceCensoredMessage if original message is shown.
local function cacheIfCensored (record, ...)
	local arg1, arg2, arg3, arg4, arg5, arg6, arg7, arg8, arg9, arg10, arg11, arg12, arg13, arg14, arg15, arg16, arg17 = ...;
	local lineID = arg11;

	-- lineID must be checked before the call, not just the API's existence:
	-- C_ChatInfo.IsChatLineCensored errors on a nil argument, and not every
	-- event that reaches here carries a chat line ID. CLUB_MESSAGE_ADDED
	-- (Community chat) has no arg11 at all, so recording a community message
	-- threw "bad argument #1 to '?'" before this guard.
	local isChatLineCensored = lineID and _G.C_ChatInfo and _G.C_ChatInfo.IsChatLineCensored
	                           and _G.C_ChatInfo.IsChatLineCensored(lineID);

	if (isChatLineCensored) then
		CensoredCache[lineID] = record;
		record.censored = true;

		-- filter out Show Message link
		record.msg = record.msg:gsub('|Hcensoredmessage:[^|]+|h.-|h', '');
	end

	return record;
end

-- replace a history record by lineID. Returns true is msg is updated.
function History:ReplaceCensoredMessage(lineID, msg)
	if (lineID and msg and CensoredCache[lineID]) then
		-- filter out report link
		msg = msg:gsub('|Hreportcensoredmessage:[^|]+|h.-|h', '');

		if CensoredCache[lineID].msg ~= msg then
			CensoredCache[lineID].msg = msg;
			return true
		end
	end

	return false;
end

local function safeName(user)
	return string.lower(user or "")
end

--BNet_GetValidatedCharacterName
local function recordWhisper(inbound, ...)
    local msg, from = ...;
    if not from then
	   	return
	end
    local db = db.history.whispers;
    local win = windows.active.whisper[safeName(from)] or windows.active.chat[from] or windows.active.w2w[safeName(from)];
    if (win and (lists.gm[from] or db.all or (db.friends and (lists.friends[from] or win.isBN)) or (db.guild and lists.guild[from]))) then
        win.widgets.history:SetHistory(true);
        --If realid/btag whisper, we save them under btag to avoid caching issues
        --(ie NAME is encoded and changes every session, we can't use that to save whispers, plus if user dumps cache, they all return unknown)
        local pid = _G.BNet_GetBNetIDAccount(from)
        if pid then
        	local _, _, btag, _, toonName = GetBNGetFriendInfoByID(pid)
			from = btag or toonName or from
		end

        -- 3.16.14: constant-count guardrail. If the per-character history has
        -- reached the configured constant ceiling, drop the record on the floor
        -- and warn the user once. The whisper is still displayed in the active
        -- window and the chat frame normally; we are only refusing to PERSIST it.
        if (isHistoryWriteBlocked()) then
            warnHistoryFull();
            return;
        end

        local history = getPlayerHistoryTable(from);
        history.info.gm = lists.gm[from];
        local record = cacheIfCensored({
            convo = from,
            type = 1, -- whisper
            inbound = inbound or false,
            from = inbound and from or env.character,
            msg = msg,
            time = select(29, ...) or _G.time();
        }, ...);
        table.insert(history, record);
        addConstant(from);
        addRecordConstants(record, #history);
        -- Blob archive: this conversation now differs from its archived copy.
        MarkHistoryDirty(env.realm, env.character, from);
        if(WIM.db.history.maxPer) then
            pruneHistory(history, WIM.db.history.maxCount);
        end
    end
end

function History:PostEvent_Whisper(...)
	-- check if secret value (12.00.00 + Secret Tools)
	if not IsSecretValue(select(1, ...)) then
    	recordWhisper(true, ...);
	end
end

function History:PostEvent_WhisperInform(...)
	-- check if secret value (12.00.00 + Secret Tools)
	if not IsSecretValue(select(1, ...)) then
    	recordWhisper(false, ...);
	end
end

local function deleteOldHistory(isChat)
    local historyDB = isChat and db.history.chat or db.history;
    local count = 0;
    for realm, characters in pairs(history) do
        for character, convos in pairs(characters) do
            for convo, messages in pairs(convos) do
                for i=#messages, 1, -1 do
                    if((time() - messages[i].time) > historyDB.maxAge and ((isChat and messages[i].type == 2) or (not isChat and messages[i].type == 1))) then
                        dPrint("Deleting History."..realm.."."..character.."."..convo.."["..i.."]");
                        table.remove(messages, i);
                        count = count + 1;
                        -- Blob archive: age pruning applies account-wide, so any
                        -- conversation we touch must be re-serialized at logout.
                        MarkHistoryDirty(realm, character, convo);
                    end
                end
                if(isEmptyTable(messages)) then convos[convo] = nil; end
            end
            -- Leave the active character's slot in place even when it becomes
            -- empty, so the character you are logged into always appears in the
            -- History Viewer's character list. New whispers repopulate it, and
            -- an empty slot causes its archive entry to be dropped at logout.
            if(isEmptyTable(convos)
                and not (realm == env.realm and character == env.character))
            then
                characters[character] = nil;
            end
        end
        -- Likewise, don't nil out the active realm if doing so would orphan
        -- the per-character splice.
        if(isEmptyTable(characters)
            and not (realm == env.realm
                and history[env.realm]
                and history[env.realm][env.character]))
        then
            history[realm] = nil;
        end
    end
    if(count > 0) then
        _G.DEFAULT_CHAT_FRAME:AddMessage(_G.format(L["WIM pruned %d |4message:messages; from your history."], count));
        -- 3.16.14: Recompute after bulk prune so the constant set is accurate.
        recomputeConstantCount();
        guardrailWarnedThisSession = false;
    end
end

function History:OnEnableWIM()
    -- clean up history if asked to.
    if(db.history.ageLimit) then
        deleteOldHistory();
    end
    -- 3.16.14: initial constant-count computation now that history is loaded.
    recomputeConstantCount();
end

function History:OnEnable()
    RegisterWidget("history", createWidget);
    for widget in Widgets("history") do
        local win = widget.parentWindow;
        if(win) then
            local history = history[env.realm] and history[env.realm][env.character] and history[env.realm][env.character][win.theUser] and win.type == "whisper";
            if(history) then
                widget:SetHistory(true);
            end
        end
    end
end

function History:OnDisable()
    if(db.modules.History.enabled) then
        return;
    end
    for widget in Widgets("history") do
        if(widget.parentWindow.type == "whisper") then
            widget:SetHistory(false); -- module is disabled, hide Icons.
        end
    end
end

function History:OnWindowDestroyed(win)
    win.isHistory = nil;
end

function History:OnWindowCreated(win)
    if(db.history.preview) then

		local user = win.theUser;
		local bnId = win.isBN and win.bn.id;
		if (bnId) then
			local _, _, btag, _, toonName = GetBNGetFriendInfoByID(bnId);
			user = btag or toonName or user
		end

		local history = history[env.realm] and history[env.realm][env.character] and history[env.realm][env.character][user];
		if(history) then
			local type = win.type == "whisper" and 1;
			for i=#history, 1, -1 do
				table.insert(tmpTable, 1, history[i]);
				if(#tmpTable >= db.history.previewCount) then
					break;
				end
			end
			if(#tmpTable > 0) then
				win.isHistory = true;
				win.widgets.history:SetHistory(true);
				for i=1, #tmpTable do
					local color = db.displayColors[tmpTable[i].inbound and "historyIn" or "historyOut"];
					win.nextStamp = tmpTable[i].time;
					win.nextStampColor = db.displayColors.historyOut;
					win:AddMessage(applyMessageFormatting(win.widgets.chat_display, "CHAT_MSG_WHISPER", tmpTable[i].msg, tmpTable[i].from,
									nil, nil, nil, nil, nil, nil, nil, nil, -i, "0x0300000000000000"), color.r, color.g, color.b);
				end
				win.widgets.chat_display:AddMessage(" ");
			end
			clearTmpTable();
		end
    end
end


--Chat History
local ChatHistory = CreateModule("HistoryChat");

-- synonymous functions
ChatHistory.OnWindowDestroyed = History.OnWindowDestroyed;


function ChatHistory:OnEnableWIM()
    -- clean up history if asked to.
    if(db.history.chat.ageLimit) then
        deleteOldHistory(true);
    end
end

function ChatHistory:OnEnable()
    RegisterWidget("history", createWidget);
    for widget in Widgets("history") do
        local win = widget.parentWindow;
        if(win) then
            local chatName = win.theUser
            local history = history[env.realm] and history[env.realm][env.character] and history[env.realm][env.character][chatName] and win.type == "chat";
            if(history) then
                widget:SetHistory(true);
            end
        end
    end
end

function ChatHistory:OnDisable()
    if(modules.HistoryChat.enabled) then
        return;
    end
    for widget in Widgets("history") do
        if(widget.parentWindow.type == "chat") then
            widget:SetHistory(false); -- module is disabled, hide Icons.
        end
    end
end


-- `infoFields`, when given, is merged into the conversation's info table. It is
-- how community chats record their club/stream identity and display name
-- alongside the messages. Pass nil for ordinary channels.
local function recordChannelChat(recordAs, ChannelType, infoFields, ...)
    local msg, from = ...;
    local db = db.history.whispers;
    local win = windows.active.chat[recordAs];
    if(win) then
        win.widgets.history:SetHistory(true);

        -- 3.16.14: constant-count guardrail. See recordWhisper() above.
        if (isHistoryWriteBlocked()) then
            warnHistoryFull();
            return;
        end

        local history = getPlayerHistoryTable(recordAs);
        history.info.chat = true;
        history.info.channelNumber = channelNumber;
        if (infoFields) then
            for k, v in pairs(infoFields) do
                history.info[k] = v;
            end
        end
        local record = cacheIfCensored({
            event = ChannelType,
            channelName = recordAs,
            type = 2, -- chat
            from = from,
            msg = msg,
            time = select(29, ...) or _G.time();
        }, ...);
        table.insert(history, record);
        addConstant(recordAs);
        addRecordConstants(record, #history);
        -- Blob archive: this conversation now differs from its archived copy.
        MarkHistoryDirty(env.realm, env.character, recordAs);
        if(WIM.db.history.chat.maxPer) then
            pruneHistory(history, WIM.db.history.chat.maxCount);
        end
    end
end


function ChatHistory:PostEvent_ChatMessage(event, ...)
    local arg1, arg2, arg3, arg4, arg5, arg6, arg7, arg8, arg9, arg10, arg11 = ...;

	-- check if secret value (12.00.00 + Secret Tools)
	if IsSecretValue(arg1) then
        return;
    end

    event = event:gsub("CHAT_MSG_", "");
    if(event == "CLUB_MESSAGE_ADDED") then
        -- 3.18.0: Community (Club) chat history.
        --
        -- Upstream 3.17.1 added Community chat as a WIM chat type but never
        -- recorded it: PostEvent_ChatMessage dispatches on the event name with
        -- "CHAT_MSG_" stripped, and CLUB_MESSAGE_ADDED carries no such prefix,
        -- so it matched none of the branches below and fell through silently.
        --
        -- Args (see Channel:CLUB_MESSAGE_ADDED in Modules/ChatEngine.lua):
        --   arg1 = message content   arg2 = author (already Ambiguate'd)
        --   arg3 = isSelf            arg4/arg9 = "clubId:streamId"
        local convoKey = arg4 or arg9;

        -- Refuse to record content that is an unresolved protected-string
        -- token ("|Kn6|k" and friends).
        --
        -- Club message content does not always arrive as text. The client can
        -- hand it over as a |K...|k token that is resolved at DISPLAY time
        -- against a lookup the client maintains, and that lookup does not
        -- outlive the context it was built in: the same message renders as
        -- "banana 1" in the Guild & Communities panel and as "Unknown"
        -- everywhere else once that panel is closed. Blizzard's own default
        -- chat frame shows "Unknown" for these too, so this is not something
        -- WIM can resolve -- the text is genuinely not available to us.
        --
        -- Storing the token would archive a value that is already meaningless
        -- and can never be recovered, so the message is skipped instead. An
        -- absent record is better than a permanent "Unknown".
        local content = arg1;
        local isUnresolvedToken = type(content) == "string"
                                  and string.match(content, "^|K[^|]*|k$") ~= nil;
        if (isUnresolvedToken) then
            dPrint("History: skipped a Community message whose content was an "
                   .."unresolved protected string.");
            return;
        end

        if (convoKey and db.history.chat.community) then
            local settings = db.chat.community and db.chat.community.channelSettings
                             and db.chat.community.channelSettings[convoKey];
            if (not (settings and settings.noHistory)) then
                -- Resolve the human-readable name now and refresh it on every
                -- message, so a rename is picked up and the viewer never has to
                -- fall back to the raw clubId:streamId key.
                local clubId, streamId = string.match(convoKey, "^(.-):(.*)$");
                local displayName;
                if (clubId and streamId and _G.ChatFrameUtil
                    and _G.ChatFrameUtil.GetCommunityAndStreamName) then
                    local ok, name = pcall(_G.ChatFrameUtil.GetCommunityAndStreamName,
                                           tonumber(clubId) or clubId, tonumber(streamId) or streamId);
                    if (ok and type(name) == "string" and name ~= "") then
                        displayName = name;
                    end
                end
                -- Record the event as CHANNEL, not CLUB_MESSAGE_ADDED.
                --
                -- The History Viewer replays a record by rebuilding the event
                -- name as "CHAT_MSG_"..record.event and handing it to
                -- applyMessageFormatting, which only knows the CHAT_MSG_* set --
                -- anything else renders as "Unknown event received...".
                -- CHAT_MSG_CLUB_MESSAGE_ADDED is not one of them.
                --
                -- CHANNEL is the correct choice rather than a workaround:
                -- upstream's own ChatEngine displays community messages in the
                -- chat window via AddEventMessage(..., "CHAT_MSG_CHANNEL", ...),
                -- so recording them as CHANNEL makes the history render
                -- identically to the live window.
                recordChannelChat(convoKey, "CHANNEL", {
                    community = true,
                    clubId = clubId,
                    streamId = streamId,
                    displayName = displayName,
                }, ...);
            end
        end
    elseif(event == "CHANNEL") then
        local recordAs;
        local isWorld = arg7 and arg7 > 0;
        local chatType = isWorld and "world" or "custom";
        local channelName = string.split(" - ", arg9);
        local channelNumber = arg8;
        recordAs = channelName;
        if(recordAs and ((isWorld and db.history.chat.world) or (not isWorld and db.history.chat.custom))) then
            local noHistory = db.chat[isWorld and "world" or "custom"].channelSettings[channelName] and db.chat[isWorld and "world" or "custom"].channelSettings[channelName].noHistory;
            if(not noHistory) then
                recordChannelChat(recordAs, event, nil, ...);
            end
        end
    else
        local recordAs;
        local chatType;

        if(event == "GUILD" and db.history.chat.guild) then
            recordAs = _G.GUILD;
            chatType = "guild";
        elseif(event == "OFFICER" and db.history.chat.officer) then
            recordAs = _G.GUILD_RANK1_DESC;
            chatType = "officer";
        elseif((event == "PARTY" or event == "PARTY_LEADER") and db.history.chat.party) then
            recordAs = _G.PARTY;
            chatType = "party";
        elseif((event == "RAID" or event == "RAID_LEADER" or event == "RAID_WARNING") and db.history.chat.raid) then
            recordAs = _G.RAID;
            chatType = "raid";
        elseif((event == "INSTANCE_CHAT" or event == "INSTANCE_CHAT_LEADER") and db.history.chat.battleground) then
            recordAs = _G.INSTANCE_CHAT;
            chatType = "battleground";
        elseif((event == "SAY" or event == "EMOTE" or event == "TEXT_EMOTE") and db.history.chat.say) then
            recordAs = _G.SAY;
            chatType = "say";
        end

        if(recordAs) then
            recordChannelChat(recordAs, event, nil, ...);
        end
    end
end


--------------------------------------
--          History Viewer          --
--------------------------------------

local function searchResult(msg, search)
    search = string.lower(string.trim(search));
    msg = string.lower(msg);
    local start, stop, match = string.find(search, "([^%s]+)",1);
    while(match) do
        if(not string.find(msg, match)) then
            return false;
        end
        start, stop, match = string.find(search, "([^%s]+)",stop+1);
    end
    return true;
end


local function createHistoryViewer()
	-- Changes for Patch 9.0.1 - Shadowlands, retail and classic
	local win = CreateFrame("Frame", "WIM3_HistoryFrame", _G.UIParent, "BackdropTemplate");

    win:Hide();
    win.filter = {};
    -- set size and position
    win:SetWidth(700);
    win:SetHeight(505);
    win:SetPoint("CENTER");

    -- set backdrop - changes for Patch 9.0.1 - Shadowlands
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
    if win.SetResizeBounds then -- WoW 10.0
		win:SetResizeBounds(240,240)
	else
   		win:SetMinResize(600, 400);
   	end

    -- set script events
    win:SetScript("OnDragStart", function(self) self:StartMoving(); end);
    win:SetScript("OnDragStop", function(self) self:StopMovingOrSizing(); end);

    -- create and set title bar text
    win.title = win:CreateFontString(win:GetName().."Title", "OVERLAY", "ChatFontNormal");
    win.title:SetPoint("TOPLEFT", 50 , -20);
    local font = win.title:GetFont();
    win.title:SetFont(font, 16, "");
    win.title:SetText(L["History Viewer"])

    -- create close button
    win.close = CreateFrame("Button", win:GetName().."Close", win);
    win.close:SetWidth(18); win.close:SetHeight(18);
    win.close:SetPoint("TOPRIGHT", -24, -20);
    win.close:SetNormalTexture("Interface\\AddOns\\"..addonTocName.."\\Sources\\Options\\Textures\\blipRed");
    win.close:SetHighlightTexture("Interface\\AddOns\\"..addonTocName.."\\Sources\\Options\\Textures\\close", "BLEND");
    win.close:SetScript("OnClick", function(self)
            self:GetParent():Hide();
        end);

    -- window actions
    win:SetScript("OnShow", function(self)
            _G.PlaySound(850);
            self.UpdateUserList();
        end);
    win:SetScript("OnHide", function(self) _G.PlaySound(851); end);
    table.insert(_G.UISpecialFrames,win:GetName());

    -- create nav
    win.nav = CreateFrame("Frame", nil, win);
    win.nav.border = win.nav:CreateTexture(nil, "BACKGROUND");
    win.nav.border:SetColorTexture(1,1,1,.25);
    win.nav.border:SetPoint("TOPRIGHT");
    win.nav.border:SetPoint("BOTTOMRIGHT");
    win.nav.border:SetWidth(2);
    win.nav:SetPoint("TOPLEFT", 18, -47);
    win.nav:SetPoint("BOTTOMLEFT", 18, 18);
    win.nav:SetWidth(200);
	win.nav.user = DDM.Create_DropDownMenu("WIM3_HistoryUserMenu", win.nav)
	win.nav.user:SetParent(win.nav)
    win.nav.user:SetPoint("TOPLEFT", -15, 0);
    DDM.UIDropDownMenu_SetWidth(win.nav.user, win.nav:GetWidth() - 25);

    -- ---------------------------------------------------------------------
    -- Multi-level user dropdown.
    --
    -- This was a single flat list of every realm, every character and every
    -- Battle.net friend. LibDropDownMenu sizes a list to fit ALL its buttons
    -- -- UIDropDownMenu_AddButton ends with listFrame:SetHeight(numButtons *
    -- buttonHeight + borders) and there is no cap and no scroll frame anywhere
    -- in the library -- so on an account with a few alts the menu grew past the
    -- height of the screen and simply clipped, making entries unreachable.
    --
    -- We cannot fix that in the library: .pkgmeta pulls LibDropDownMenu as an
    -- external at `tag: latest`, so any edit is overwritten at package time and
    -- anything depending on its internals can break under us on any build.
    --
    -- So the height is fixed structurally instead, using the library's public
    -- multi-level support (info.hasArrow + info.menuList, and the level passed
    -- to the initialize function):
    --
    --   Level 1   realms, then Battle.net Friends, then Community Chats
    --   Level 2   a realm's characters / the BN friends / the communities
    --   Level 3   alphabetical buckets, only for groups over MAX_FLAT_ENTRIES
    --
    -- Level 3 is the safety valve: it keeps a realm with forty alts, or a long
    -- friend list, from reintroducing the same overflow one level down.
    -- ---------------------------------------------------------------------
    local MAX_FLAT_ENTRIES = 20;
    local BUCKET_SEP = "|||";

    -- Split a sorted array into alphabetical buckets of at most
    -- MAX_FLAT_ENTRIES, labelled by the range they cover ("A - F").
    local function bucketize(sorted, labelOf)
        local buckets = {};
        local perBucket = MAX_FLAT_ENTRIES;
        for i = 1, #sorted, perBucket do
            local chunk = {};
            for j = i, math.min(i + perBucket - 1, #sorted) do
                table.insert(chunk, sorted[j]);
            end
            local first = labelOf(chunk[1]);
            local last = labelOf(chunk[#chunk]);
            table.insert(buckets, {
                label = string.upper(string.sub(first, 1, 1)).." - "
                        ..string.upper(string.sub(last, 1, 1)),
                items = chunk,
            });
        end
        return buckets;
    end

    -- Human-readable label for a stored win.USER value.
    --   "Realm"                -> "Realm"
    --   "Realm/Character"      -> "Realm/Character"
    --   "@BN@"                 -> "Battle.net Friends"
    --   "@BN@/Tag#1234"        -> "Tag#1234"
    --   "@COMMUNITY@"          -> "Community Chats"
    --   "@COMMUNITY@/12:3"     -> the club's display name
    local function describeUser(value)
        if (not value or value == "") then
            return "";
        end
        local realm, key = string.match(value, "^([^/]+)/?(.*)$");
        if (realm == BN_PSEUDO_REALM) then
            if (key == "") then return L["Battle.net Friends"]; end
            return key;
        elseif (realm == COMMUNITY_PSEUDO_REALM) then
            if (key == "") then return L["Community Chats"]; end
            local names = GetAllCommunityConvos();
            return names[key] or key;
        end
        return value;
    end

    local function selectValue(value)
        win.USER = value;
        win.CONVO = "";
        win.FILTER = "";
        win.UpdateUserList();
        -- SetSelectedValue alone is not enough here. It resolves the
        -- display text by scanning level 1 for a button whose value
        -- matches, and in a hierarchical menu the selectable entries live
        -- at levels 2 and 3, so nothing matches and the selector renders
        -- blank. Set the text directly; keep SetSelectedValue too so the
        -- radio ticks still track.
        DDM.UIDropDownMenu_SetSelectedValue(win.nav.user, value);
        DDM.UIDropDownMenu_SetText(win.nav.user, describeUser(value));
        DDM.CloseDropDownMenus();
    end
    win.nav.user.describeUser = describeUser;

    -- Builds the structured model the menu renders from.
    --
    -- CACHED PER MENU SESSION. The library calls the initialize function again
    -- for every level, so hovering into a submenu re-enters init(); rebuilding
    -- the model there would re-walk every conversation on the account on each
    -- hover. Enumerating Battle.net and Community conversations is inherently a
    -- full account-wide walk (both call EnsureAllHistoryLoaded and then scan the
    -- whole tree), so on a large account that turned menu navigation into
    -- repeated full scans. A menu session always begins at level 1, so that is
    -- where we rebuild; deeper levels reuse the snapshot.
    win.nav.user.getMenuModel = function(rebuild)
        if (not rebuild and win.nav.user._menuModel) then
            return win.nav.user._menuModel;
        end
        local model = { realms = {}, realmOrder = {}, bn = {}, community = {} };

        local function noteCharacter(realm, character)
            if (realm == BN_PSEUDO_REALM or realm == COMMUNITY_PSEUDO_REALM) then
                return;
            end
            if (not model.realms[realm]) then
                model.realms[realm] = {};
                table.insert(model.realmOrder, realm);
            end
            for i = 1, #model.realms[realm] do
                if (model.realms[realm][i] == character) then return; end
            end
            table.insert(model.realms[realm], character);
        end

        -- Union of what is live in memory and what is in the archive, so the
        -- menu is complete the instant the viewer opens even while the
        -- background rehydrator is still working.
        for realm, users in pairs(history) do
            if (_G.type(users) == "table") then
                for user in pairs(users) do noteCharacter(realm, user); end
            end
        end
        if (_G.type(_G.WIM_HistoryArchive) == "table") then
            for realm, users in pairs(_G.WIM_HistoryArchive) do
                if (_G.type(users) == "table") then
                    for user in pairs(users) do noteCharacter(realm, user); end
                end
            end
        end

        table.sort(model.realmOrder);
        for _, realm in ipairs(model.realmOrder) do
            table.sort(model.realms[realm]);
        end

        for bnKey in pairs(GetAllBNConvoKeys()) do
            table.insert(model.bn, bnKey);
        end
        table.sort(model.bn);

        for convoKey, displayName in pairs(GetAllCommunityConvos()) do
            table.insert(model.community, { key = convoKey, name = displayName });
        end
        table.sort(model.community, function(a, b) return a.name < b.name; end);

        win.nav.user._menuModel = model;
        return model;
    end

    win.nav.user.init = function(self, level, menuList)
        self = self or win.nav.user;
        level = level or 1;
        local model = win.nav.user.getMenuModel(level == 1);
        local value = DDM.UIDROPDOWNMENU_MENU_VALUE;

        local function add(info)
            info.notCheckable = info.notCheckable or info.isTitle or info.hasArrow;
            DDM.UIDropDownMenu_AddButton(info, level);
        end

        -- Adds either a flat list of entries or, when there are too many, a
        -- further level of alphabetical buckets.
        local function addGroup(entries, labelOf, valueOf, bucketTag)
            if (#entries <= MAX_FLAT_ENTRIES) then
                for i = 1, #entries do
                    local v = valueOf(entries[i]);
                    add({ text = labelOf(entries[i]), value = v,
                          func = function() selectValue(v); end });
                end
                return;
            end
            local buckets = bucketize(entries, labelOf);
            for i = 1, #buckets do
                add({ text = buckets[i].label, hasArrow = true,
                      value = bucketTag..BUCKET_SEP..i, menuList = bucketTag..BUCKET_SEP..i });
            end
        end

        if (level == 1) then
            for _, realm in ipairs(model.realmOrder) do
                -- Clicking the realm itself still selects the realm-wide view;
                -- hovering opens its characters.
                add({ text = realm, value = realm, hasArrow = true,
                      func = function() selectValue(realm); end });
            end
            if (#model.bn > 0) then
                add({ text = L["Battle.net Friends"], value = BN_PSEUDO_REALM,
                      hasArrow = true });
            end
            if (#model.community > 0) then
                add({ text = L["Community Chats"], value = COMMUNITY_PSEUDO_REALM,
                      hasArrow = true });
            end

        elseif (level == 2) then
            if (value == BN_PSEUDO_REALM) then
                addGroup(model.bn,
                         function(k) return k; end,
                         function(k) return BN_PSEUDO_REALM.."/"..k; end,
                         BN_PSEUDO_REALM);
            elseif (value == COMMUNITY_PSEUDO_REALM) then
                addGroup(model.community,
                         function(c) return c.name; end,
                         function(c) return COMMUNITY_PSEUDO_REALM.."/"..c.key; end,
                         COMMUNITY_PSEUDO_REALM);
            elseif (model.realms[value]) then
                -- No "all characters" entry here: clicking the realm itself at
                -- level 1 already selects the realm-wide view.
                local realm = value;
                addGroup(model.realms[realm],
                         function(c) return c; end,
                         function(c) return realm.."/"..c; end,
                         realm);
            end

        elseif (level == 3) then
            -- An alphabetical bucket: "<groupTag>|||<bucketIndex>".
            -- NOTE: a literal \0 cannot be used as the separator here. Lua 5.1
            -- pattern matching stops at an embedded zero in the PATTERN (it
            -- requires %z for that), so the match would silently return nil and
            -- level 3 would render empty.
            local tag, idx = string.match(tostring(value), "^(.*)|||(%d+)$");
            idx = tonumber(idx);
            if (tag and idx) then
                local entries, labelOf, valueOf;
                if (tag == BN_PSEUDO_REALM) then
                    entries = model.bn;
                    labelOf = function(k) return k; end;
                    valueOf = function(k) return BN_PSEUDO_REALM.."/"..k; end;
                elseif (tag == COMMUNITY_PSEUDO_REALM) then
                    entries = model.community;
                    labelOf = function(c) return c.name; end;
                    valueOf = function(c) return COMMUNITY_PSEUDO_REALM.."/"..c.key; end;
                elseif (model.realms[tag]) then
                    entries = model.realms[tag];
                    labelOf = function(c) return c; end;
                    valueOf = function(c) return tag.."/"..c; end;
                end
                if (entries) then
                    local buckets = bucketize(entries, labelOf);
                    local bucket = buckets[idx];
                    if (bucket) then
                        for i = 1, #bucket.items do
                            local v = valueOf(bucket.items[i]);
                            add({ text = labelOf(bucket.items[i]), value = v,
                                  func = function() selectValue(v); end });
                        end
                    end
                end
            end
        end
    end

    win.nav.user:SetScript("OnShow", function(self)
            DDM.UIDropDownMenu_Initialize(self, self.init);
            DDM.UIDropDownMenu_SetSelectedValue(self, win.USER);
            DDM.UIDropDownMenu_SetText(self, self.describeUser(win.USER));
        end);
    win.nav.filters = CreateFrame("Frame", nil, win.nav);
    win.nav.filters:SetPoint("BOTTOMLEFT");
    win.nav.filters:SetPoint("BOTTOMRIGHT", -2, 0);
    win.nav.filters:SetHeight(125);
    win.nav.filters.border = win.nav.filters:CreateTexture(nil, "BACKGROUND");
    win.nav.filters.border:SetColorTexture(1, 1, 1, .25);
    win.nav.filters.border:SetPoint("TOPLEFT");
    win.nav.filters.border:SetPoint("TOPRIGHT");
    win.nav.filters.border:SetHeight(20);
    win.nav.filters.text = win.nav.filters:CreateFontString(nil, "OVERLAY", "ChatFontNormal");
    win.nav.filters.text:SetPoint("TOPLEFT", win.nav.filters.border);
    win.nav.filters.text:SetPoint("BOTTOMRIGHT", win.nav.filters.border);
    win.nav.filters.text:SetText(L["Filters"]);
    win.nav.filters.text:SetTextColor(_G.GameFontNormal:GetTextColor());
    win.nav.filters.scroll = CreateFrame("ScrollFrame", "WIM3_HistoryFilterListScroll", win.nav.filters, "FauxScrollFrameTemplate");
    win.nav.filters.scroll:SetPoint("TOPLEFT", 0, -22);
    win.nav.filters.scroll:SetPoint("BOTTOMRIGHT", -23, 0);
    win.nav.filters.scroll.buttons = {};
    win.nav.filters.scroll.createButton = function()
            local button = CreateFrame("Button", nil, win.nav.filters);
                if(#win.nav.filters.scroll.buttons > 0) then
                    button:SetPoint("TOPLEFT", win.nav.filters.scroll.buttons[#win.nav.filters.scroll.buttons], "BOTTOMLEFT");
                    button:SetPoint("TOPRIGHT", win.nav.filters.scroll.buttons[#win.nav.filters.scroll.buttons], "BOTTOMRIGHT");
                else
                    button:SetPoint("TOPLEFT", win.nav.filters.scroll);
                    button:SetPoint("TOPRIGHT", win.nav.filters.scroll);
                end
                button:SetHeight(20);
                button:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestLogTitleHighlight" , "ADD");
                button:GetHighlightTexture():SetVertexColor(.196, .388, .5);

                button.text = button:CreateFontString(nil, "OVERLAY", "ChatFontNormal");
                -- 3.16.14: reserve 18px on the right edge of the text frame for
                -- the delete X icon (mirrors the user-list row layout above so
                -- the date label doesn't run under the X).
                button.text:SetPoint("TOPLEFT");
                button.text:SetPoint("BOTTOMRIGHT", -18, 0);
                button.text:SetJustifyH("LEFT");

                button.SetFilter = function(self, filter)
                        self.filter = filter;
                        if(_G.type(filter) == "number") then
                            self.text:SetText("     "..date(L["_DateFormat"], filter));
                            -- 3.16.14: date filter → show the delete X.
                            if (self.delete) then self.delete:Show(); end
                        else
                            self.filter = "";
                            self.text:SetText("     "..filter);
                            -- 3.16.14: "Show All" or other non-date filter →
                            -- no per-day delete affordance. Deleting a whole
                            -- conversation is the user-list row's job.
                            if (self.delete) then self.delete:Hide(); end
                        end
                    end
                button:SetScript("OnClick", function(self)
                        win.FILTER = self.filter;
                        win.nav.filters.scroll.update();
                        win.UpdateDisplay();
                    end);

                -- 3.16.14: per-date delete affordance. Removes every record
                -- from the currently-selected conversation (win.CONVO) whose
                -- timestamp falls on the clicked day, scoped to the currently-
                -- selected USER (BN consolidated view → all realms/characters;
                -- realm view → every character on that realm; character view →
                -- that one character).
                button.delete = CreateFrame("Button", nil, button);
                button.delete:SetNormalTexture("Interface\\AddOns\\"..addonTocName.."\\Modules\\Textures\\xNormal");
                button.delete:SetPushedTexture("Interface\\AddOns\\"..addonTocName.."\\Modules\\Textures\\xPressed");
                button.delete:SetWidth(16);
                button.delete:SetHeight(16);
                button.delete:SetAlpha(.5);
                button.delete:SetPoint("RIGHT");
                button.delete:Hide();
                button.delete:SetScript("OnClick", function(self)
                        local owner = self:GetParent();
                        local filterDate = owner.filter;
                        if (_G.type(filterDate) ~= "number") then
                            return;  -- defensive: should be hidden anyway
                        end
                        local dayStart = filterDate;
                        local dayEnd = filterDate + 86400;
                        local dateLabel = date(L["_DateFormat"], filterDate);
                        local _scopeRealm, _scopeChar = string.match(win.USER, "^([^/]+)/?(.*)$");
                        local _isBN = (_scopeRealm == BN_PSEUDO_REALM and _scopeChar ~= "");
                        local _isRealmView = (_scopeRealm and (not _scopeChar or _scopeChar == ""));
                        local _convoName = win.CONVO;
                        if (not _convoName or _convoName == "") then
                            return;
                        end

                        local _popupText;
                        if (_isBN) then
                            _popupText = _G.format(
                                L["Are you sure you want to delete the %s history with %s across every realm and character on this account?"],
                                "|cff69ccf0"..dateLabel.."|r",
                                "|cff69ccf0".._scopeChar.."|r"
                            );
                        elseif (_isRealmView) then
                            _popupText = _G.format(
                                L["Are you sure you want to delete the %s history for %s across every character on %s?"],
                                "|cff69ccf0"..dateLabel.."|r",
                                "|cff69ccf0".._convoName.."|r",
                                "|cff69ccf0".._scopeRealm.."|r"
                            );
                        else
                            _popupText = _G.format(
                                L["Are you sure you want to delete the %s history for %s on %s?"],
                                "|cff69ccf0"..dateLabel.."|r",
                                "|cff69ccf0".._convoName.."|r",
                                "|cff69ccf0"..win.USER.."|r"
                            );
                        end

                        -- Helper: prune dated records from a single convo
                        -- table in place. Returns the number of records
                        -- removed.
                        local function pruneConvo(convoTbl, ownerRealm, ownerChar, ownerConvo)
                            if (_G.type(convoTbl) ~= "table") then return 0; end
                            local removed = 0;
                            for i = #convoTbl, 1, -1 do
                                local rec = convoTbl[i];
                                if (_G.type(rec) == "table"
                                    and _G.type(rec.time) == "number"
                                    and rec.time >= dayStart
                                    and rec.time < dayEnd)
                                then
                                    table.remove(convoTbl, i);
                                    removed = removed + 1;
                                end
                            end
                            if (removed > 0 and ownerRealm and ownerChar) then
                                -- Blob archive: re-serialize this conversation at logout.
                                MarkHistoryDirty(ownerRealm, ownerChar, ownerConvo);
                            end
                            return removed;
                        end

                        _G.StaticPopupDialogs["WIM_DELETE_HISTORY_DATE"] = {
                            preferredIndex = STATICPOPUP_NUMDIALOGS,
                            text = _popupText,
                            button1 = L["Yes"],
                            button2 = L["No"],
                            OnAccept = function()
                                local totalRemoved = 0;
                                local realm, character = string.match(win.USER, "^([^/]+)/?(.*)$");
                                -- BN consolidated view: walk every
                                -- (realm, character) slot and prune the
                                -- matching convo on the chosen day.
                                if ((realm == BN_PSEUDO_REALM or realm == COMMUNITY_PSEUDO_REALM) and character ~= "") then
                                    local bnKey = character;
                                    forEachBNConvo(bnKey, function(convoTbl, cRealm, cChar)
                                        totalRemoved = totalRemoved + pruneConvo(convoTbl, cRealm, cChar, bnKey);
                                    end);
                                elseif (realm and character ~= "" and history[realm] and history[realm][character]) then
                                    local convoTbl = history[realm][character][_convoName];
                                    if (convoTbl) then
                                        totalRemoved = pruneConvo(convoTbl, realm, character, _convoName);
                                    end
                                elseif (realm and history[realm]) then
                                    -- Realm-wide view: every character.
                                    for rChar, convos in pairs(history[realm]) do
                                        if (_G.type(convos) == "table" and convos[_convoName]) then
                                            totalRemoved = totalRemoved + pruneConvo(convos[_convoName], realm, rChar, _convoName);
                                        end
                                    end
                                end

                                -- If the active filter was the date we just
                                -- nuked, reset to "Show All" so the display
                                -- doesn't sit on an empty filter.
                                if (win.FILTER == filterDate) then
                                    win.FILTER = "";
                                end

                                -- Clear any active search results so the
                                -- filter-list rebuild below uses the fresh
                                -- CONVOLIST. Without this, search results
                                -- (which are independent copies of the now-
                                -- deleted records) would still drive the
                                -- date-bucket list, showing the just-deleted
                                -- day as still selectable.
                                if (win.SEARCHLIST) then
                                    for k, _ in pairs(win.SEARCHLIST) do
                                        win.SEARCHLIST[k] = nil;
                                    end
                                end
                                if (win.search and win.search.text) then
                                    win.search.text:SetText("");
                                end
                                if (win.search and win.search.result) then
                                    win.search.result:Hide();
                                end

                                -- Refresh the convo, filter, and display
                                -- chain. UpdateConvoList re-reads from
                                -- history; UpdateFilterList rebuilds the
                                -- date buckets (the day we just emptied
                                -- will disappear).
                                win.UpdateConvoList();
                                win.UpdateFilterList();
                                win.nav.filters.scroll:Hide();
                                win.nav.filters.scroll:Show();
                                win.UpdateDisplay();

                                -- Maintain the running size estimate so the
                                -- guardrail readout reflects reality, and
                                -- clear the once-per-session warning latch
                                -- in case freeing this space gets us back
                                -- under the ceiling.
                                if (totalRemoved > 0) then
                                    recomputeConstantCount();
                                    guardrailWarnedThisSession = false;
                                end
                            end,
                            timeout = 0,
                            whileDead = 1,
                            hideOnEscape = 1
                        };
                        _G.StaticPopup_Show("WIM_DELETE_HISTORY_DATE");
                    end);

                table.insert(win.nav.filters.scroll.buttons, button);
            return button;
        end
    for i=1, 5 do
        win.nav.filters.scroll.createButton();
    end
    win.nav.filters.scroll.update = function()
            local self = win.nav.filters.scroll;
            local offset = _G.FauxScrollFrame_GetOffset(self);
            for i=1, #self.buttons do
                local index = i + offset;
                if(index <= #win.FILTERLIST) then
                    self.buttons[i]:SetFilter(win.FILTERLIST[index]);
                    self.buttons[i]:Show();
                    if(self.buttons[i].filter == win.FILTER) then
                        self.buttons[i]:LockHighlight();
                    else
                        self.buttons[i]:UnlockHighlight();
                    end
                else
                    self.buttons[i]:Hide();
                end
            end

            _G.FauxScrollFrame_Update(self, #win.FILTERLIST, 5, 20);
        end
    win.nav.filters.scroll:SetScript("OnShow", function(self)
            self:update();
        end);
    win.nav.filters.scroll:SetScript("OnVerticalScroll", function(self, offset)
            _G.FauxScrollFrame_OnVerticalScroll(self, offset, 20, win.nav.filters.scroll.update);
        end);

    win.nav.userList = CreateFrame("Frame", nil, win.nav);
    win.nav.userList:SetPoint("BOTTOMLEFT", win.nav.filters, "TOPLEFT", 0, 1);
    win.nav.userList:SetPoint("BOTTOMRIGHT", win.nav.filters, "TOPRIGHT", 0, 1);
    win.nav.userList:SetPoint("TOP", 0, -30);
    win.nav.userList.border = win.nav.userList:CreateTexture(nil, "BACKGROUND");
    win.nav.userList.border:SetColorTexture(1,1,1,.25);
    win.nav.userList.border:SetPoint("TOPLEFT", 0, 1);
    win.nav.userList.border:SetPoint("TOPRIGHT", 0, 1);
    win.nav.userList.border:SetHeight(1);
    win.nav.userList.scroll = CreateFrame("ScrollFrame", "WIM3_HistoryUserListScroll", win.nav.userList, "FauxScrollFrameTemplate");
    win.nav.userList.scroll:SetPoint("TOPLEFT", 0, -2);
    win.nav.userList.scroll:SetPoint("BOTTOMRIGHT", -23, 0);
    win.nav.userList.scroll.buttons = {};
    win.nav.userList.scroll.createButton = function()
            local button = CreateFrame("Button", nil, win.nav.userList);
                if(#win.nav.userList.scroll.buttons > 0) then
                    button:SetPoint("TOPLEFT", win.nav.userList.scroll.buttons[#win.nav.userList.scroll.buttons], "BOTTOMLEFT");
                    button:SetPoint("TOPRIGHT", win.nav.userList.scroll.buttons[#win.nav.userList.scroll.buttons], "BOTTOMRIGHT");
                else
                    button:SetPoint("TOPLEFT", win.nav.userList.scroll);
                    button:SetPoint("TOPRIGHT", win.nav.userList.scroll);
                end
                button:SetHeight(20);
                button:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestLogTitleHighlight" , "ADD");
                button:GetHighlightTexture():SetVertexColor(.196, .388, .5);

                button.text = button:CreateFontString(nil, "OVERLAY", "ChatFontNormal");
                button.text:SetPoint("TOPLEFT");
                button.text:SetPoint("BOTTOMRIGHT", -18, 0);
                button.text:SetJustifyH("LEFT");

                button.SetUser = function(self, user)
                        local original, extra, color = user, "";
                        local gmTag
                        user, gmTag = string.match(original, "([^*]+)(*?)$");
                        color = gmTag == "*" and constants.classes[L["Game Master"]].color or "ffffff";
                        if(string.match(original, "^*")) then
                            extra = " |TInterface\\AddOns\\WIM\\Skins\\Default\\minimap.blp:20:20:0:0|t";
                            color = "fff569";
                        end
                        if not user then
                        	_G.print("Your WIM history is damaged beyond repair and must be erased before it can be used again do to having conversation with a realid friend that has no battletag. This bug has been fixed in WIM but your history cannot be repaired")
                       		return
                        end
                        self.user = user;
                        -- Community conversations are keyed by "clubId:streamId"
                        -- because that is what upstream's ChatEngine uses as the
                        -- window name, and self.user has to stay exactly that so
                        -- the history lookup still resolves. Only the LABEL is
                        -- swapped for the readable community name -- the same
                        -- treatment the channel settings list gives them.
                        --
                        -- Resolving through the API rather than walking history
                        -- keeps this cheap: this runs per button on every list
                        -- refresh. A community you have since left will not
                        -- resolve, and falls back to the raw key.
                        local label = user;
                        if (string.find(user, "^%d+:%d+$") and _G.ChatFrameUtil
                            and _G.ChatFrameUtil.ResolveChannelName) then
                            local ok, resolved = pcall(_G.ChatFrameUtil.ResolveChannelName, user);
                            if (ok and type(resolved) == "string" and resolved ~= "") then
                                label = resolved;
                            end
                        end
                        self.text:SetText("     |cff"..color..label.."|r"..extra..(gmTag == "*" and " |TInterface\\ChatFrame\\UI-ChatIcon-Blizz.blp:0:2:0:0|t" or ""));
                        if(user == win.SELECT) then
                            self:Click();
                        end
                    end
                button:SetScript("OnClick", function(self)
                        win:SelectConvo(self.user);
                        win.nav.userList.scroll.update();
                    end);
                button.delete = CreateFrame("Button", nil, button);
                button.delete:SetNormalTexture("Interface\\AddOns\\"..addonTocName.."\\Modules\\Textures\\xNormal");
                button.delete:SetPushedTexture("Interface\\AddOns\\"..addonTocName.."\\Modules\\Textures\\xPressed");
                button.delete:SetWidth(16);
                button.delete:SetHeight(16);
                button.delete:SetAlpha(.5);
                button.delete:SetPoint("RIGHT");
                button.delete:SetScript("OnClick", function(self)
                        local _bnRealm, _bnHandle = string.match(win.USER, "^([^/]+)/?(.*)$");
                        local _isBN = (_bnRealm == BN_PSEUDO_REALM and _bnHandle ~= "");
                        local _popupText;
                        if (_isBN) then
                            -- 3.16.14: extra-explicit warning, because the
                            -- BN-friend view is a cross-realm aggregation and
                            -- the user might not realize the delete is
                            -- account-wide.
                            _popupText = _G.format(
                                L["Are you sure you want to delete ALL history saved with %s, across every realm and every character on this account?"],
                                "|cff69ccf0".._bnHandle.."|r"
                            );
                        else
                            _popupText = _G.format(L["Are you sure you want to delete all history saved for %s on %s?"],
                                "|cff69ccf0"..self:GetParent().user.."|r",
                                "|cff69ccf0"..win.USER.."|r"
                                );
                        end
                        _G.StaticPopupDialogs["WIM_DELETE_HISTORY"] = {
                        	preferredIndex = STATICPOPUP_NUMDIALOGS,
                            text = _popupText,
                            button1 = L["Yes"],
                            button2 = L["No"],
                            OnAccept = function()
                                local realm, character = string.match(win.USER, "^([^/]+)/?(.*)$");
                                -- 3.16.14: BN-friend consolidated delete.
                                -- Walks every (realm, character) slot and
                                -- nils the matching BattleTag's conversation.
                                -- The active character's splice slot is still
                                -- preserved per the 3.16.14 invariant.
                                if ((realm == BN_PSEUDO_REALM or realm == COMMUNITY_PSEUDO_REALM) and character ~= "") then
                                    local bnKey = character;
                                    -- 3.16.14: Collect the slots that will
                                    -- become empty BEFORE mutating, since
                                    -- pairs() over a table being mutated is
                                    -- only well-defined for nilling existing
                                    -- keys at the CURRENT position. To stay
                                    -- safely within the spec, we do a
                                    -- gather-then-delete two-pass walk.
                                    local emptiedChars = {};
                                    local emptiedRealms = {};
                                    for r, characters in pairs(history) do
                                        if (r ~= BN_PSEUDO_REALM and type(characters) == "table") then
                                            for ch, convos in pairs(characters) do
                                                if (type(convos) == "table" and convos[bnKey] ~= nil) then
                                                    convos[bnKey] = nil;
                                                    -- Blob archive: drop this conversation at logout.
                                                    MarkHistoryDirty(r, ch, bnKey);
                                                    if (isEmptyTable(convos)
                                                        and not (r == env.realm and ch == env.character))
                                                    then
                                                        table.insert(emptiedChars, {realm = r, char = ch});
                                                    end
                                                end
                                            end
                                        end
                                    end
                                    for i = 1, #emptiedChars do
                                        local e = emptiedChars[i];
                                        if (history[e.realm]) then
                                            history[e.realm][e.char] = nil;
                                            if (isEmptyTable(history[e.realm])
                                                and not (e.realm == env.realm
                                                    and history[env.realm]
                                                    and history[env.realm][env.character]))
                                            then
                                                table.insert(emptiedRealms, e.realm);
                                            end
                                        end
                                    end
                                    for i = 1, #emptiedRealms do
                                        history[emptiedRealms[i]] = nil;
                                    end
                                elseif(realm and character and history[realm] and history[realm][character]) then
                                    history[realm][character][self:GetParent().user] = nil;
                                    MarkHistoryDirty(realm, character, self:GetParent().user);
                                    -- 3.16.14: preserve the active character's
                                    -- splice slot even when fully emptied; see
                                    -- the matching note in deleteOldHistory().
                                    if(isEmptyTable(history[realm][character])
                                        and not (realm == env.realm and character == env.character))
                                    then
                                        history[realm][character] = nil;
                                        if(isEmptyTable(history[realm])) then
                                            history[realm] = nil;
                                        end
                                    end
                                elseif(realm and history[realm]) then
                                    for char, convos in pairs(history[realm]) do
                                        convos[self:GetParent().user] = nil;
                                        MarkHistoryDirty(realm, char, self:GetParent().user);
                                        if(isEmptyTable(convos)
                                            and not (realm == env.realm and char == env.character))
                                        then
                                            history[realm][char] = nil;
                                        end
                                    end
                                    if(isEmptyTable(history[realm])
                                        and not (realm == env.realm
                                            and history[env.realm]
                                            and history[env.realm][env.character]))
                                    then
                                        history[realm] = nil;
                                    end
                                end
                                win.nav.user:Hide();
                                win.nav.user:Show();
                                win.UpdateUserList();
                                -- 3.16.13: a manual deletion can free a lot of
                                -- bytes; recalibrate so the guardrail status
                                -- reflects reality immediately.
                                recomputeConstantCount();
                                guardrailWarnedThisSession = false;
                            end,
                            timeout = 0,
                            whileDead = 1,
                            hideOnEscape = 1
                        };
                        _G.StaticPopup_Show("WIM_DELETE_HISTORY");
                    end);

                table.insert(win.nav.userList.scroll.buttons, button);
            return button;
        end
    win.nav.userList.scroll.update = function()
            local self = win.nav.userList.scroll;
            local maxButtons = _G.math.floor(self:GetHeight()/20);
            local offset = _G.FauxScrollFrame_GetOffset(self);
            for i=1, #self.buttons do
                if(i <= maxButtons) then
                    self.buttons[i]:Show();
                    local index = i + offset;
                    if(index <= #win.USERLIST) then
                        self.buttons[i]:SetUser(win.USERLIST[index]);
                        self.buttons[i]:Show();
                        if(self.buttons[i].user == win.CONVO) then
                            self.buttons[i]:LockHighlight();
                        else
                            self.buttons[i]:UnlockHighlight();
                        end
                    else
                        self.buttons[i]:Hide();
                    end
                else
                    self.buttons[i]:Hide();
                end
            end

            _G.FauxScrollFrame_Update(self, #win.USERLIST, maxButtons, 20);
        end
    win.nav.userList.scroll:SetScript("OnShow", function(self)
            local maxButtons = _G.math.floor(self:GetHeight()/20);
            if(maxButtons > #self.buttons) then
                local toCreate = maxButtons - #self.buttons;
                for i=1, toCreate do
                    self.createButton();
                end
            end
            self:update();
        end);
    win.nav.userList.scroll:SetScript("OnVerticalScroll", function(self, offset)
            _G.FauxScrollFrame_OnVerticalScroll(self, offset, 20, win.nav.userList.scroll.update);
        end);

    --search bar
    win.search = CreateFrame("Frame", nil, win);
    win.search.bg = win.search:CreateTexture(nil, "BACKGROUND");
    win.search.bg:SetColorTexture(1,1,1,.25);
    win.search.bg:SetAllPoints();
    win.search:SetPoint("TOPLEFT", win.nav, "TOPRIGHT");
    win.search:SetPoint("RIGHT", -18, 0);
    win.search:SetHeight(30);
    win.search.clear = CreateFrame("Button", nil, win.search);
    win.search.clear:SetNormalTexture("Interface\\AddOns\\"..addonTocName.."\\Modules\\Textures\\xNormal");
    win.search.clear:SetPushedTexture("Interface\\AddOns\\"..addonTocName.."\\Modules\\Textures\\xPressed");
    win.search.clear:SetWidth(16);
    win.search.clear:SetHeight(16);
    win.search.clear:SetPoint("RIGHT", -5, 0)
    win.search.clear:SetScript("OnClick", function(self)
            win.search.text:ClearFocus();
            win.search.text:SetText("");
            for key, _ in pairs(win.SEARCHLIST) do
                win.SEARCHLIST[key] = nil;
            end
            win.search.result:Hide();
            win.UpdateFilterList();
            win.UpdateDisplay();
        end);
    win.search.text = CreateFrame("EditBox", nil, win.search);
    win.search.text:SetFontObject(_G.ChatFontNormal);
    win.search.text:SetWidth(200); win.search.text:SetHeight(15);
    win.search.text:SetPoint("RIGHT", win.search.clear, "LEFT", -5, 0);
    win.search.text:SetScript("OnEditFocusGained", function(self) self:HighlightText() end);
    win.search.text:SetScript("OnEditFocusLost", function(self) self:HighlightText(0, 0) end);
    win.search.text:SetScript("OnEnterPressed", function(self)
            for key, _ in pairs(win.SEARCHLIST) do
                win.SEARCHLIST[key] = nil;
            end
            local realm, character = string.match(win.USER, "^([^/]+)/?(.*)$");
            -- 3.16.14: BN-friend consolidated view. Search across all
            -- (realm, character) slots for records under the chosen BattleTag.
            if ((realm == BN_PSEUDO_REALM or realm == COMMUNITY_PSEUDO_REALM) and character ~= "") then
                local bnKey = character;
                local queryText = self:GetText();
                forEachBNConvo(bnKey, function(convoTbl, _, _)
                    for i = 1, #convoTbl do
                        if (searchResult(convoTbl[i].msg, queryText)) then
                            table.insert(win.SEARCHLIST, copyTable(convoTbl[i], {seq = i}));
                        end
                    end
                end);
            elseif(realm and character and history[realm] and history[realm][character]) then
                for convo, tbl in pairs(history[realm][character]) do
                    for i=1, #tbl do
                        if(searchResult(tbl[i].msg, self:GetText())) then
                            table.insert(win.SEARCHLIST, copyTable(tbl[i], {seq = i}));
                        end
                    end
                end
            elseif(realm and history[realm]) then
                for char, convos in pairs(history[realm]) do
                    for convo, tbl in pairs(convos) do
                        for i=1, #tbl do
                            if(searchResult(tbl[i].msg, self:GetText())) then
                                table.insert(win.SEARCHLIST, copyTable(tbl[i], {seq = i}));
                            end
                        end
                    end
                end
            end
            table.sort(win.SEARCHLIST, function(a, b)
				if (a.seq and b.seq) then
					return tonumber(a.time.."."..a.seq) < tonumber(b.time.."."..b.seq)
				end
                return a.time < b.time;
            end);
            if(#win.SEARCHLIST > 0) then
                win.search.result:SetText(_G.format(L["Search resulted in %d |4message:messages;."], #win.SEARCHLIST))
            else
                win.search.result:SetText("|cffff0000"..L["No results found!"].."|r");
            end
            win.search.result:Show();
            self:ClearFocus();
            win.UpdateFilterList();
            win.UpdateDisplay();
        end);
    options.AddFramedBackdrop(win.search.text);
    win.search.text:SetAutoFocus(false);
    win.search.text:SetScript("OnEscapePressed", function(self) self:ClearFocus() end);
    win.search.label = win.search:CreateFontString(nil, "OVERLAY", "ChatFontNormal");
    win.search.label:SetText(L["Search"]..":");
    win.search.label:SetTextColor(_G.GameFontNormal:GetTextColor());
    win.search.label:SetPoint("RIGHT", win.search.text, "LEFT", -5, 0);
    win.search.result = win.search:CreateFontString(nil, "OVERLAY", "ChatFontSmall");
    win.search.result:SetPoint("LEFT");
    win.search.result:SetPoint("RIGHT", win.search.label, "LEFT", -5, 0);
    win.search.result:Hide();


    --content frame
    win.content = CreateFrame("Frame", nil, win);
    win.content.border = win.content:CreateTexture(nil, "BACKGROUND");
    win.content.border:SetColorTexture(1,1,1,.25);
    win.content.border:SetPoint("BOTTOMLEFT");
    win.content.border:SetPoint("BOTTOMRIGHT");
    win.content.border:SetHeight(1);
    win.content:SetPoint("TOPLEFT", win.search, "BOTTOMLEFT");
    win.content:SetPoint("BOTTOMRIGHT", win, "BOTTOMRIGHT", -18, 40);

    win.content.tabs = {};
    win.content.createTab = function(self, index)
            local tab = CreateFrame("Button", nil, self);
            tab.index = index;
            tab.frame = ViewTypes[index].frame;
            tab:SetHeight(20);
            tab.text = tab:CreateFontString(nil, "OVERLAY", "ChatFontSmall");
            tab.text:SetAllPoints();
            tab.text:SetText(ViewTypes[index].text);
            tab.bg = tab:CreateTexture(nil, "BACKGROUND");
            tab.bg:SetColorTexture(1, 1, 1, .25);
            tab.bg:SetAllPoints();
            tab:SetWidth(tab.text:GetStringWidth() + 16);
            if(#self.tabs > 0) then
                tab:SetPoint("TOPLEFT", self.tabs[#self.tabs], "TOPRIGHT",2 ,0);
            else
                tab:SetPoint("TOPLEFT", self, "BOTTOMLEFT", 5, 0);
            end
            tab:SetScript("OnClick", function(self)
                for i=1, #win.content.tabs do
                    if(win.progressBar:IsVisible()) then
                        win.progressBar.delete:Click();
                    end
                    if(self.index == i) then
                        win.content.tabs[i]:SetAlpha(1);
                        win.TAB = self.index;
                        if(self.frame == "chatFrame") then
                            win.content.chatFrame:Show();
                            win.content.textFrame:Hide();
                        else
                            win.content.textFrame:Show();
                            win.content.chatFrame:Hide();
                        end
                    else
                        win.content.tabs[i]:SetAlpha(.5);
                    end
                end
                win:UpdateDisplay();
            end);
            table.insert(self.tabs, tab);
        end
    for i=1, #ViewTypes do
        win.content:createTab(i);
    end


    win.content.chatFrame = CreateFrame("ScrollingMessageFrame", "WIM3_HistoryChatFrame", win.content);
    win.content.chatFrame:SetPoint("TOPLEFT", 4, -4);
    win.content.chatFrame:SetPoint("BOTTOMRIGHT", -30, 4);
    win.content.chatFrame:SetFontObject("ChatFontNormal");
    win.content.chatFrame:EnableMouse(true);
    win.content.chatFrame:EnableMouseWheel(true);
    win.content.chatFrame:SetJustifyH("LEFT");
    win.content.chatFrame:SetFading(false);
    win.content.chatFrame:SetMaxLines(800);
    win.content.chatFrame.update = function(self)
            if(self:AtTop()) then
		self.up:Disable();
            else
		self.up:Enable();
            end
            if(self:AtBottom()) then
                self.down:Disable();
            else
		self.down:Enable();
            end
        end
    win.content.chatFrame:SetScript("OnShow", function(self)
            self:update();
        end);
    win.content.chatFrame:SetScript("OnMouseWheel", function(self, ...)
	    if(select(1, ...) > 0) then
		if( _G.IsControlKeyDown() ) then
		    self:ScrollToTop();
		else
		    if( _G.IsShiftKeyDown() ) then
			self:PageUp();
		    else
			self:ScrollUp();
		    end
		end
	    else
		if( _G.IsControlKeyDown() ) then
		    self:ScrollToBottom();
		else
		    if( _G.IsShiftKeyDown() ) then
	                self:PageDown();
		    else
			self:ScrollDown();
		    end
		end
	    end
	    self:update();
	end);

    win.content.chatFrame:SetScript("OnHyperlinkClick",
		_G.ChatFrameMixin and _G.ChatFrameMixin.OnHyperlinkClick or
		_G.ChatFrame_OnHyperlinkShow
	);

    win.content.chatFrame.up = CreateFrame("Button", nil, win.content.chatFrame);
    win.content.chatFrame.up:SetWidth(28); win.content.chatFrame.up:SetHeight(28);
    win.content.chatFrame.up:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIcon-ScrollUp-Up");
    win.content.chatFrame.up:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIcon-ScrollUp-Down");
    win.content.chatFrame.up:SetDisabledTexture("Interface\\ChatFrame\\UI-ChatIcon-ScrollUp-Disabled");
    win.content.chatFrame.up:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD");
    win.content.chatFrame.up:SetPoint("TOPRIGHT", 30 ,0);
    win.content.chatFrame.up:SetScript("OnClick", function(self)
            local obj = self:GetParent();
	    if( _G.IsControlKeyDown() ) then
		obj:ScrollToTop();
	    else
		if( _G.IsShiftKeyDown() ) then
		    obj:PageUp();
		else
		    obj:ScrollUp();
		end
	    end
            obj:update();
        end);
    win.content.chatFrame.down = CreateFrame("Button", nil, win.content.chatFrame);
    win.content.chatFrame.down:SetWidth(28); win.content.chatFrame.down:SetHeight(28);
    win.content.chatFrame.down:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIcon-ScrollDown-Up");
    win.content.chatFrame.down:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIcon-ScrollDown-Down");
    win.content.chatFrame.down:SetDisabledTexture("Interface\\ChatFrame\\UI-ChatIcon-ScrollDown-Disabled");
    win.content.chatFrame.down:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD");
    win.content.chatFrame.down:SetPoint("BOTTOMRIGHT", 30 ,-4);
    win.content.chatFrame.down:SetScript("OnClick", function(self)
            local obj = self:GetParent();
	    if( _G.IsControlKeyDown() ) then
		obj:ScrollToBottom();
	    else
		if( _G.IsShiftKeyDown() ) then
		    obj:PageDown();
		else
		    obj:ScrollDown();
		end
	    end
            obj:update();
        end);

    win.content.textFrame = CreateFrame("ScrollFrame", "WIM3_HistoryTextFrame", win.content, "UIPanelScrollFrameTemplate");
    win.content.textFrame:SetPoint("TOPLEFT", win.content, "TOPLEFT", 4, -4);
    win.content.textFrame:SetPoint("BOTTOMRIGHT", -25, 4);
    win.content.textFrame.text = CreateFrame("EditBox", "WIM3_HistoryTextFrameText", win.content.textFrame);
    win.content.textFrame.text:SetFontObject(_G.ChatFontNormal);
    win.content.textFrame.text:SetMultiLine(true);
    win.content.textFrame:SetScrollChild(win.content.textFrame.text);
    win.content.textFrame.text:SetWidth(win.content.textFrame:GetWidth());
    win.content.textFrame.text:SetHeight(200);
    win.content.textFrame.text:SetAutoFocus(false);
    win.content.textFrame.text:SetScript("OnEscapePressed", function(self) self:ClearFocus() end);
    win.content.textFrame.text:SetScript("OnTextChanged", function(self)
            win.content.textFrame:UpdateScrollChildRect();
        end);
    win.content.textFrame.text.AddMessage = function(self, msg, r, g, b)
            local color;
            --if(r and g and b) then
            --    color = RGBPercentToHex(r, g, b);
            --end
            msg = msg:gsub("|c[0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f]", "");
            msg = msg:gsub("|r", "");
            --self:SetText(self:GetText()..(color and "|cff"..color or "")..msg..(color and "|r" or "").."\n");
            self:SetText(self:GetText()..msg.."\n");
        end;



    --resize
    win.resize = CreateFrame("Button", nil, win);
    win.resize:SetNormalTexture("Interface\\AddOns\\"..addonTocName.."\\Skins\\Default\\resize");
    win.resize:SetHighlightTexture("Interface\\AddOns\\"..addonTocName.."\\Skins\\Default\\resize", "ADD");
    win.resize:SetWidth(20); win.resize:SetHeight(20);
    win.resize:SetPoint("BOTTOMRIGHT", -11, 11);
    win.resize:SetScript("OnMouseDown", function(self)
            self:GetParent().isSizing = true;
	    self:GetParent():SetResizable(true);
	    self:GetParent():StartSizing("BOTTOMRIGHT");
            self:SetScript("OnUpdate", function(self)
                win.nav.userList.scroll:update();
            end);
        end);
    win.resize:SetScript("OnMouseUp", function(self)
            self:SetScript("OnUpdate", nil);
            self:GetParent().isSizing = false;
	    self:GetParent():StopMovingOrSizing();
            win.nav.userList.scroll:Hide();
            win.nav.userList.scroll:Show();
        end);

    win.USER = env.realm.."/"..env.character;
    win.USERLIST = {};
    win.CONVO = "";
    win.CONVOLIST = {};
    win.FILTER = "";
    win.FILTERLIST = {};
    win.SEARCHLIST = {};

    win.SelectConvo = function(self, convo)
        win.search.text:SetText("");
        win.search.result:Hide();
        for k, _ in pairs(win.SEARCHLIST) do
            win.SEARCHLIST[k] = nil;
        end
        win.CONVO = convo;
        win.FILTER = "";
        win.UpdateConvoList();
        win.UpdateFilterList();
        win.UpdateDisplay();
    end

    win.UpdateDisplay = function(self)
        if(win.displayUpdate) then
            win.displayUpdate:Show();
        end
    end

    win.UpdateFilterList = function(self)
        for i=1, #win.FILTERLIST do
            win.FILTERLIST[i] = nil;
        end
        local theList = #win.SEARCHLIST > 0 and win.SEARCHLIST or win.CONVOLIST;
        for i=1, #theList do
            local t = theList[i].time;
            local tbl = date("*t", t);
            t = time{year=tbl.year, month=tbl.month, day=tbl.day, hour=0};
            addToTableUnique(win.FILTERLIST, t);
            win.FILTER = t;
        end
        if(#win.FILTERLIST > 0) then
            table.insert(win.FILTERLIST, 1, L["Show All"]);
        end
        win.nav.filters.scroll:Hide();
        win.nav.filters.scroll:Show();
    end

    win.UpdateConvoList = function(self)
        for i=1, #win.CONVOLIST do
            win.CONVOLIST[i] = nil;
        end
        -- Blob archive: make sure whatever the user just selected is actually
        -- resident in memory before we read it. Normally the background
        -- rehydrator has already restored everything, but selecting a character
        -- it hasn't reached yet must not show an empty list.
        local _r, _c = string.match(win.USER, "^([^/]+)/?(.*)$");
        if (_r == BN_PSEUDO_REALM or _r == COMMUNITY_PSEUDO_REALM) then
            EnsureAllHistoryLoaded();
        elseif (_r and _c and _c ~= "") then
            EnsureHistoryCharacterLoaded(_r, _c);
        elseif (_r) then
            EnsureHistoryRealmLoaded(_r);
        end
        local realm, character = string.match(win.USER, "^([^/]+)/?(.*)$");
        -- 3.16.14: BN-friend consolidated view. Walk every (realm, character)
        -- slot in history and pull out every record from the conversation
        -- keyed by this BattleTag.
        if (realm == BN_PSEUDO_REALM or realm == COMMUNITY_PSEUDO_REALM) then
            -- When a specific friend/community was selected its key is in
            -- win.USER; when the whole section was selected the key comes from
            -- whichever entry the user clicked in the list.
            local bnKey = (character ~= "" and character) or win.CONVO;
            forEachBNConvo(bnKey, function(convoTbl, _, _)
                for i = 1, #convoTbl do
                    table.insert(win.CONVOLIST, copyTable(convoTbl[i], {seq = i}));
                end
            end);
        elseif(realm and character and history[realm] and history[realm][character]) then
            local tbl = history[realm][character][win.CONVO];
            if tbl then
           	   for i=1, #tbl do
            	    table.insert(win.CONVOLIST, copyTable(tbl[i], {seq = i}));
           	   end
           	else
           		ShowHistoryViewer()
           	end
        elseif(realm and history[realm]) then
            for char, tbl in pairs(history[realm]) do
                if(tbl[win.CONVO]) then
                    for i=1, #tbl[win.CONVO] do
                        table.insert(win.CONVOLIST, copyTable(tbl[win.CONVO][i], {seq = i}));
                    end
                end
            end
        end
        table.sort(win.CONVOLIST, function(a, b)
			if (a.seq and b.seq) then
				return tonumber(a.time.."."..a.seq) < tonumber(b.time.."."..b.seq)
			end
            return a.time < b.time;
        end);
    end

    win.UpdateUserList = function(self)
        for i=1, #win.USERLIST do
            win.USERLIST[i] = nil;
        end
        -- Blob archive: make sure whatever the user just selected is actually
        -- resident in memory before we read it. Normally the background
        -- rehydrator has already restored everything, but selecting a character
        -- it hasn't reached yet must not show an empty list.
        local _r, _c = string.match(win.USER, "^([^/]+)/?(.*)$");
        if (_r == BN_PSEUDO_REALM or _r == COMMUNITY_PSEUDO_REALM) then
            EnsureAllHistoryLoaded();
        elseif (_r and _c and _c ~= "") then
            EnsureHistoryCharacterLoaded(_r, _c);
        elseif (_r) then
            EnsureHistoryRealmLoaded(_r);
        end
        local realm, character = string.match(win.USER, "^([^/]+)/?(.*)$");
        -- 3.16.14: BN-friend consolidated view. The "realm" is the BN pseudo
        -- and the "character" half is actually the BattleTag/RealID.
        if ((realm == BN_PSEUDO_REALM or realm == COMMUNITY_PSEUDO_REALM) and character == "") then
            -- The whole section was selected ("Battle.net Friends" or
            -- "Community Chats" at the top level of the menu), which is the
            -- analogue of selecting a realm: list every conversation of that
            -- kind so the user can pick one.
            if (realm == BN_PSEUDO_REALM) then
                for bnKey, _ in pairs(GetAllBNConvoKeys()) do
                    addToTableUnique(win.USERLIST, bnKey);
                end
            else
                for convoKey, _ in pairs(GetAllCommunityConvos()) do
                    addToTableUnique(win.USERLIST, convoKey);
                end
            end
        elseif ((realm == BN_PSEUDO_REALM or realm == COMMUNITY_PSEUDO_REALM) and character ~= "") then
            -- A single friend/community was selected directly. The user list
            -- collapses to that one entry; the scroll-list machinery expects a
            -- clickable entry in order to populate the convo list.
            local bnKey = character;
            addToTableUnique(win.USERLIST, bnKey);
        elseif(realm and character and history[realm] and history[realm][character]) then
            local tbl = history[realm][character];
            for convo, t in pairs(tbl) do
                ChannelCache[convo] = t.info and t.info.channelNumber or nil;
                convo = (t.info and t.info.chat and "*" or "")..convo
                addToTableUnique(win.USERLIST, convo..(t.info and t.info.gm and "*" or ""));
            end
        elseif(realm and (not character or character == "") and history[realm]) then
            for char, tbl in pairs(history[realm]) do
                for convo, t in pairs(tbl) do
                    ChannelCache[convo] = t.info and t.info.channelNumber or nil;
                    convo = (t.info and t.info.chat and "*" or "")..convo
                    addToTableUnique(win.USERLIST, convo..(t.info and t.info.gm and "*" or ""));
                end
            end
        end
        table.sort(win.USERLIST);
        win.nav.userList.scroll:Hide();
        win.nav.userList.scroll:Show();
        if(#win.USERLIST>0) then
            if(not win.SELECT) then
                win.nav.userList.scroll.buttons[1]:Click();
            else
                win.SELECT = nil;
            end
        else
            win.SELECT = nil;
            win:SelectConvo("");
        end
    end


    win.progressBar = CreateFrame("Frame", nil, win.content);
    win.progressBar:SetFrameStrata("TOOLTIP");
    win.progressBar:SetWidth(300); win.progressBar:SetHeight(65);
    win.progressBar:SetPoint("CENTER", 0, 50);
    options.AddFramedBackdrop(win.progressBar);
    win.progressBar.backdrop.bg:SetColorTexture(0, 0, 0, 1);
    win.progressBar.bar = CreateFrame("Frame", nil, win.progressBar);
    options.AddFramedBackdrop(win.progressBar.bar);
    win.progressBar.bar:SetWidth(win.progressBar:GetWidth()-50); win.progressBar.bar:SetHeight(15);
    win.progressBar.bar:SetPoint("CENTER", -10, -5);
    win.progressBar.bar.bg = win.progressBar.bar:CreateTexture(nil, "OVERLAY");
    win.progressBar.bar.bg:SetColorTexture(1,1,1, .5);
    win.progressBar.bar.bg:SetPoint("TOPLEFT");
    win.progressBar.bar.bg:SetPoint("BOTTOMLEFT");
    win.progressBar.text = win.progressBar:CreateFontString(nil, "OVERLAY", "ChatFontNormal");
    win.progressBar.text:SetPoint("BOTTOMLEFT", win.progressBar.bar, "TOPLEFT", 0, 5);
    win.progressBar.text:SetText(L["Loading History"].."...");
    win.progressBar:SetScript("OnShow", function(self)
            win.content.chatFrame:SetAlpha(.5);
            win.content.textFrame:SetAlpha(.5);
        end);
    win.progressBar:SetScript("OnHide", function(self)
            win.content.chatFrame:SetAlpha(1);
            win.content.textFrame:SetAlpha(1);
        end);
    win.progressBar.delete = CreateFrame("Button", nil, win.progressBar);
    win.progressBar.delete:SetNormalTexture("Interface\\AddOns\\"..addonTocName.."\\Modules\\Textures\\xNormal");
    win.progressBar.delete:SetPushedTexture("Interface\\AddOns\\"..addonTocName.."\\Modules\\Textures\\xPressed");
    win.progressBar.delete:SetWidth(16);
    win.progressBar.delete:SetHeight(16);
    win.progressBar.delete:SetPoint("LEFT", win.progressBar.bar, "RIGHT", 4, 0);
    win.progressBar.delete:SetScript("OnClick", function(self)
            win.displayUpdate:Hide();
        end);

    win.content.tabs[1]:Click();

    return win;
end


local HistoryViewer;
local function createDisplayUpdate()
    -- displayUpdate loads messages into the correct content frames avoiding lag from system ops.
    local displayUpdate = CreateFrame("Frame");
    displayUpdate:Hide();
    displayUpdate.firstPass = true;
    displayUpdate.tmpTable = {};
    displayUpdate.Process = function(self)
            self.i = self.i or 1;
            -- 3.16.14: this used to recurse via `self:Process()` to skip
            -- filtered-out records, which blew Lua's call stack (max depth
            -- around 200) on large datasets where many records in a row fall
            -- outside the active filter (e.g. realm-wide view with a date
            -- filter). Converted to an iterative skip loop. Functionally
            -- equivalent, but bounded by the loop budget instead of the
            -- call stack.
            while (true) do
                if (not self.curList or not self.curList[self.i]) then
                    -- End of list: final progress update, then hide.
                    if (self.curList and #self.curList > 0) then
                        HistoryViewer.progressBar.bar.bg:SetWidth(
                            HistoryViewer.progressBar.bar:GetWidth());
                    end
                    self:Hide();
                    return;
                end

                -- clear tmpTable
                for k, _ in pairs(self.tmpTable) do
                    self.tmpTable[k] = nil;
                end
                -- load tmpTable
                for k, v in pairs(self.curList[self.i]) do
                    self.tmpTable[k] = v;
                end

                if (self.filter) then
                    if (self.min <= self.tmpTable.time and self.max > self.tmpTable.time) then
                        -- Match. Emit it, advance, and yield back to OnUpdate
                        -- so the rendering pipeline can draw the line and the
                        -- progress bar can refresh.
                        ViewTypes[HistoryViewer.TAB].func(self.frame, self.tmpTable);
                        self.i = self.i + 1;
                        HistoryViewer.progressBar.bar.bg:SetWidth(
                            HistoryViewer.progressBar.bar:GetWidth() * self.i / #self.curList);
                        return;
                    else
                        -- Skip this record and check the next one. The
                        -- progress bar update is left out of the skip path
                        -- on purpose, to avoid one SetWidth call per
                        -- skipped record when many in a row are filtered
                        -- out; the next emit or hide refreshes it.
                        self.i = self.i + 1;
                        -- continue the while loop
                    end
                else
                    -- No filter active: every record is emitted, one per tick.
                    ViewTypes[HistoryViewer.TAB].func(self.frame, self.tmpTable);
                    self.i = self.i + 1;
                    HistoryViewer.progressBar.bar.bg:SetWidth(
                        HistoryViewer.progressBar.bar:GetWidth() * self.i / #self.curList);
                    return;
                end
            end
        end;
    displayUpdate:SetScript("OnUpdate", function(self, elapsed)
        if(self.firstPass) then
            HistoryViewer.content.chatFrame:Clear();
            HistoryViewer.content.chatFrame.lastDate = nil;
            HistoryViewer.content.chatFrame:SetIndentedWordWrap(db.wordwrap_indent);
            HistoryViewer.content.textFrame.text:SetText("");
            HistoryViewer.content.textFrame.text.lastDate = nil;
            self.firstPass = nil;
        end
        self:Process()
    end);
    displayUpdate:SetScript("OnHide", function(self)
        self.firstPass = true;
        self.i = 1;
        HistoryViewer.progressBar:Hide();
        HistoryViewer.content.chatFrame:update();
        local buttons = HistoryViewer.nav.userList.scroll.buttons;
        for i=1, #buttons do
            buttons[i]:Enable();
            buttons[i].delete:Enable();
        end
        buttons = HistoryViewer.nav.filters.scroll.buttons;
        for i=1, #buttons do
            buttons[i]:Enable();
        end
    end);

    displayUpdate:SetScript("OnShow", function(self)
        local buttons = HistoryViewer.nav.userList.scroll.buttons;
        for i=1, #buttons do
            buttons[i]:Disable();
            buttons[i].delete:Disable();
        end
        buttons = HistoryViewer.nav.filters.scroll.buttons;
        for i=1, #buttons do
            buttons[i]:Disable();
        end
        HistoryViewer.progressBar:Show();
        self.curList = #HistoryViewer.SEARCHLIST > 0 and HistoryViewer.SEARCHLIST or HistoryViewer.CONVOLIST;
        self.frame = ViewTypes[HistoryViewer.TAB].frame == "chatFrame" and HistoryViewer.content.chatFrame or HistoryViewer.content.textFrame.text;



        self.filter = _G.type(HistoryViewer.FILTER) == "number" or nil;
        self.min, self.max = 0, 0;
        if(self.filter) then
            local t = HistoryViewer.FILTER;
            local tbl = date("*t", t);
            t = time{year=tbl.year, month=tbl.month, day=tbl.day, hour=0};
            self.min, self.max = t, t+dDay;
        end
    end);
    return displayUpdate;
end

local colorWhite = {r=1, g=1, b=1};
local chatFrameMsgId = -1;
table.insert(ViewTypes, {
        text = L["Chat View"],
        frame = "chatFrame",
        func = function(frame, msg)
            local color;
            if(msg.type == 1) then
                color = db.displayColors[msg.inbound and "wispIn" or "wispOut"];
                nextColor.r, nextColor.g, nextColor.b = color.r, color.g, color.b;
            elseif(msg.type == 2) then
                if(msg.event == CHANNEL) then
                    color = _G.ChatTypeInfo["CHANNEL"..msg.channelNumber];
                else
                    color = _G.ChatTypeInfo[msg.event];
                end
                color = color or colorWhite;
                nextColor.r, nextColor.g, nextColor.b = color.r, color.g, color.b;
            end
                frame.nextStamp = msg.time;
                frame:AddMessage(applyStringModifiers(applyMessageFormatting(frame, "CHAT_MSG_"..(msg.event or "WHISPER"), msg.msg, msg.from,
                        nil, nil, nil, nil, 0, msg.channelName and ChannelCache[msg.channelName], msg.channelName, nil, chatFrameMsgId, "0x0300000000000000"), frame), color.r, color.g, color.b);
                chatFrameMsgId = chatFrameMsgId > -1000 and chatFrameMsgId - 1 or -1;

        end
    });
table.insert(ViewTypes, {
        text = L["Text View"],
        frame = "textFrame",
        func = function(frame, msg)
            frame.noEscapedStrings = true;
            if(msg.type == 1 or msg.type == 2) then
                local color = db.displayColors[msg.inbound and "wispIn" or "wispOut"];
                nextColor.r, nextColor.g, nextColor.b = color.r, color.g, color.b;
                frame.nextStamp = msg.time;
                frame:AddMessage(applyStringModifiers(applyMessageFormatting(frame, "CHAT_MSG_"..(msg.event or "WHISPER"), msg.msg, msg.from,
                nil, nil, nil, nil, 0, msg.channelName and ChannelCache[msg.channelName], msg.channelName, "0x0300000000000000"), frame), color.r, color.g, color.b)
            end
        end
    });

-- stewart
table.insert(ViewTypes, {
	        text = L["BBCode"],
	        frame = "textFrame",
	        func = function(frame, msg)
                    local color;
	            if(msg.type == 1) then
                        color = db.displayColors[msg.inbound and "wispIn" or "wispOut"];
                        nextColor.r, nextColor.g, nextColor.b = color.r, color.g, color.b;
                    elseif(msg.type == 2) then
                        if(msg.event == CHANNEL) then
                            color = _G.ChatTypeInfo["CHANNEL"..msg.channelNumber];
                        else
                            color = _G.ChatTypeInfo[msg.event];
                        end
                        color = color or colorWhite;
                        nextColor.r, nextColor.g, nextColor.b = color.r, color.g, color.b;
                    end
	            frame.noEscapedStrings = nil;
                    frame.noEmoticons = true;
	            frame.nextStamp = msg.time;
                    local chatColor = "[color=#"..RGBPercentToHex(color.r, color.g, color.b).."]";
                    local chatColorPattern = "%[color%=%#"..RGBPercentToHex(color.r, color.g, color.b).."%]%s*%[%/color%]";
	            msg = applyMessageFormatting(frame, "CHAT_MSG_"..(msg.event or "WHISPER"), msg.msg, msg.from)
	            msg = applyStringModifiers(msg, frame);
	            msg = msg:gsub("|c[0-9A-Fa-f][0-9A-Fa-f]([0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f])|Hwim_url:([^|]*)|h.-|h|r", "[/color][url=%2][color=#%1]%2[/color][/url]"..chatColor);
	            msg = msg:gsub("|c[0-9A-Fa-f][0-9A-Fa-f]([0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f])", "[color=#%1]");
	            msg = msg:gsub("|r", "[/color]");
	            msg = msg:gsub("(%[color%=%#[0-9A-Fa-f]+%])|Hitem:(%d+)[:%d]*|h([^|]+)|h(%[%/color%])", "[/color][url=http://www.wowhead.com/?item=%2]%1%3%4[/url]"..chatColor);
	            msg = chatColor..msg.."[/color]";
	            msg = msg:gsub("(%[color%=%#[0-9A-Fa-f]+%])(%[color%=%#[0-9A-Fa-f]+%])(.-)(%[%/color%])", "%2%3%4%1");
                    msg = msg:gsub(chatColorPattern, "");
	            frame:AddMessage(msg, color.r, color.g, color.b)
	        end
	    });

table.insert(ViewTypes, {
	        text = "HTML",
	        frame = "textFrame",
	        func = function(frame, msg)
                    local color;
	            if(msg.type == 1) then
                        color = db.displayColors[msg.inbound and "wispIn" or "wispOut"];
                        nextColor.r, nextColor.g, nextColor.b = color.r, color.g, color.b;
                    elseif(msg.type == 2) then
                        if(msg.event == CHANNEL) then
                            color = _G.ChatTypeInfo["CHANNEL"..msg.channelNumber];
                        else
                            color = _G.ChatTypeInfo[msg.event];
                        end
                        color = color or colorWhite;
                        nextColor.r, nextColor.g, nextColor.b = color.r, color.g, color.b;
                    end
	            frame.noEscapedStrings = nil;
                    frame.noEmoticons = true;
	            frame.nextStamp = msg.time;
                    local chatColor = "<font color='#"..RGBPercentToHex(color.r, color.g, color.b).."'>";
                    local chatColorPattern = "%<font color%='%#"..RGBPercentToHex(color.r, color.g, color.b).."'%>%s*%<%/font%>";
	            msg = applyMessageFormatting(frame, "CHAT_MSG_"..(msg.event or "WHISPER"), msg.msg, msg.from)
	            msg = applyStringModifiers(msg, frame);

                    -- html escapes
                    msg = msg:gsub("&", "&amp;");
                    msg = msg:gsub("<", "&lt;");
                    msg = msg:gsub(">", "&gt;");
                    msg = msg:gsub("\"", "&quot;");

                    -- color & URL handling...
	            msg = msg:gsub("|c[0-9A-Fa-f][0-9A-Fa-f]([0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f])|Hwim_url:([^|]*)|h.-|h|r", "</color><a href='%2'><font color='#%1'>%2</font></a>"..chatColor);
	            msg = msg:gsub("|c[0-9A-Fa-f][0-9A-Fa-f]([0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f])", "<font color='#%1'>");
	            msg = msg:gsub("|r", "</font>");
	            msg = msg:gsub("(%<font color%='%#[0-9A-Fa-f]+'%>)|Hitem:(%d+)[:%d]*|h([^|]+)|h(%[%/color%])", "</font><a href='http://www.wowhead.com/?item=%2'>%1%3%4</a>"..chatColor);
	            msg = chatColor..msg.."</font>";
	            msg = msg:gsub("(%<font color%='%#[0-9A-Fa-f]+'%>)(%<font color%='%#[0-9A-Fa-f]+'%>)(.-)(%<%/font%>)", "%2%3%4%1");
                    msg = "<br>"..msg:gsub(chatColorPattern, "");
	            frame:AddMessage(msg, color.r, color.g, color.b)
	        end
	    });


function ShowHistoryViewer(user)
	local exists = HistoryViewer
    if(HistoryViewer and not user and HistoryViewer:IsShown()) then
        HistoryViewer:Hide();
        return;
    end
    HistoryViewer = HistoryViewer or createHistoryViewer();
    HistoryViewer.displayUpdate = HistoryViewer.displayUpdate or createDisplayUpdate();

    if(user) then
        HistoryViewer.USER = env.realm.."/"..env.character;
        HistoryViewer.SELECT = user;
        HistoryViewer.nav:Hide();
        HistoryViewer.nav:Show();
        HistoryViewer.UpdateUserList();
        HistoryViewer:SelectConvo(user);
 --       DisplayTutorial(L["WIM History Viewer"], L["WIM History Viewer can be accessed any time by typing:"].." \n|cff69ccf0/wim history|r");
    end
    HistoryViewer:Show();
	if not exists and not user then --force update on first show without user
		HistoryViewer:Hide();
		HistoryViewer:Show();
	end
end

RegisterSlashCommand("history", function() ShowHistoryViewer(); end, L["Display history viewer."])
