local WIM = WIM;

--------------------------------------
--      Verbose Event Tracing       --
--------------------------------------
-- Debug level 2 ("/wim debug 2") attaches a passive listener to every chat
-- event WIM manages and writes each one, with its arguments, to the on-disk
-- debug log.
--
-- The point is to record what the CLIENT actually delivers, independently of
-- what WIM does with it and independently of what any chat frame renders.
-- Those three had been conflated during the community send investigation: the
-- captures showed WIM's CHAT_MSG_COMMUNITIES_CHANNEL message filter never
-- running, which was read as "the event never fired". That inference is not
-- sound -- an AddMessageEventFilter callback only runs when some chat frame is
-- registered for the event and dispatches it through
-- ChatFrame_MessageEventHandler, so "no filter ran" and "no event fired" are
-- different statements. This frame is registered by WIM alone and answers the
-- second question directly.
--
-- Cost: nothing at level 0 or 1. The frame registers no events until level 2 is
-- set, so a normal session pays only this file's load.

local ARG_LIMIT = 12;   -- chat events carry 11-17 args; the tail is rarely useful
local STR_LIMIT = 90;   -- per-argument truncation, well under the per-line cap

-- Events worth tracing, grouped the way WIM's modules group them. An event
-- the client does not know is skipped at registration instead of raising an
-- error, because the TOC also covers Classic clients where several of these
-- events do not exist.
local TRACE_EVENTS = {
    -- Say / emote
    "CHAT_MSG_SAY", "CHAT_MSG_EMOTE", "CHAT_MSG_TEXT_EMOTE",
    -- Guild / officer
    "CHAT_MSG_GUILD", "CHAT_MSG_GUILD_ACHIEVEMENT", "CHAT_MSG_OFFICER",
    -- Group
    "CHAT_MSG_PARTY", "CHAT_MSG_PARTY_LEADER",
    "CHAT_MSG_RAID", "CHAT_MSG_RAID_LEADER", "CHAT_MSG_RAID_WARNING",
    "CHAT_MSG_INSTANCE_CHAT", "CHAT_MSG_INSTANCE_CHAT_LEADER",
    -- Numbered channels (world / custom / community-backed)
    "CHAT_MSG_CHANNEL", "CHAT_MSG_CHANNEL_JOIN", "CHAT_MSG_CHANNEL_LEAVE",
    "CHAT_MSG_CHANNEL_NOTICE", "CHAT_MSG_CHANNEL_NOTICE_USER",
    "CHAT_MSG_COMMUNITIES_CHANNEL",
    -- Whispers
    "CHAT_MSG_WHISPER", "CHAT_MSG_WHISPER_INFORM",
    "CHAT_MSG_BN_WHISPER", "CHAT_MSG_BN_WHISPER_INFORM",
    -- Club plumbing behind the community chat type
    "CLUB_MESSAGE_ADDED", "CLUB_STREAM_SUBSCRIBED", "CLUB_STREAM_UNSUBSCRIBED",
    "CLUB_STREAMS_LOADED", "CLUB_ADDED", "CLUB_REMOVED",
    -- Channel list churn, which the stream focus pass keys off
    "CHANNEL_UI_UPDATE", "CHANNEL_COUNT_UPDATE",
};

local function fmtArg(v)
    if (v == nil) then
        return "nil";
    end
    -- Never concatenate a secret value: on a 12.x client that errors outright.
    if (WIM.IsSecretValue and WIM.IsSecretValue(v)) then
        return "<secret>";
    end

    local t = type(v);
    if (t == "string") then
        if (#v > STR_LIMIT) then
            return "'"..string.sub(v, 1, STR_LIMIT).."~'";
        end
        return "'"..v.."'";
    elseif (t == "table") then
        return "<table>";
    elseif (t == "function") then
        return "<function>";
    end
    return tostring(v);
end

local traceFrame = CreateFrame("Frame", "WIM_DebugTraceFrame");

traceFrame:SetScript("OnEvent", function(self, event, ...)
    if ((WIM.debugLevel or 0) < 2) then
        return;
    end

    local count = select("#", ...);
    local shown = count < ARG_LIMIT and count or ARG_LIMIT;
    local line = "TRACE "..event;
    for i = 1, shown do
        line = line.." a"..i.."="..fmtArg((select(i, ...)));
    end
    if (count > shown) then
        line = line.." (+"..(count - shown).." more)";
    end

    WIM.LogLine(line);
end);

function WIM.StartEventTrace()
    if (traceFrame.tracing) then
        return;
    end

    local skipped = {};
    for i = 1, #TRACE_EVENTS do
        local event = TRACE_EVENTS[i];
        if (not pcall(traceFrame.RegisterEvent, traceFrame, event)) then
            skipped[#skipped + 1] = event;
        end
    end
    traceFrame.tracing = true;

    WIM.LogLine("TRACE: started, "..(#TRACE_EVENTS - #skipped).." of "..#TRACE_EVENTS.." events registered."
        ..(#skipped > 0 and (" Unavailable on this client: "..table.concat(skipped, ", ")) or ""));
end

function WIM.StopEventTrace()
    if (not traceFrame.tracing) then
        return;
    end
    traceFrame:UnregisterAllEvents();
    traceFrame.tracing = false;
    WIM.LogLine("TRACE: stopped.");
end
