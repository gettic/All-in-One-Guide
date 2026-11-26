-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 gettic
-- v0.2 M5: the Hub's "Report a mistake" page. The player picks what is wrong and which step (the current
-- one or one of the last 3), may add a note (200 characters), may remove their location or add the NPC
-- they target and sees the exact string. The easy way is Send: it saves the report in the outbox and the
-- Addon Manager sends it when the game is closed. Without the Addon Manager: copy it and paste it on the web
-- page (HR.WEB_URL), or into a GitHub issue. The addon itself never sends anything. Opened from the title
-- menu, the Hub nav and /aog report.
--   ns.HubReport.opts (the current choices), .Update(), .String(), .Send(), .Copy(), .WaitingText(), .page
local _, ns = ...
local Th, K = ns.Theme, ns.UIKit
-- COL_MIN: the narrowest type column (look review #4); PREVIEW_LINES: the preview's fixed height in lines
local HR = { opts = { about = "coords" }, typeButtons = {}, stepButtons = {}, COL_MIN = 180, PREVIEW_LINES = 8 }
ns.HubReport = HR

local function L() return ns.L end
HR.URL = "github.com/gettic/All-in-One-Guide/issues"
-- the report web page: NOT live yet, so no text shows it ("coming soon"); kept for when it is (report_worker in the Addon Manager project; links can't be clicked in game, so short)
HR.WEB_URL = "aog-report.gtd-relay.workers.dev"

local TYPE_ICON = { coords = "report.coords", order = "report.order", missing = "report.missing",
    notick = "report.notick", text = "report.text", danger = "notice.danger", other = "report.other" }

-- A choice row (UIKit): radio = pick one (the type, the step), else a tick box (look review #5).
local function Choice(parent, text, onClick, radio)
    return K.Choice(parent, text, onClick, radio, "report")
end

local function Head(parent, y, text)
    local fs = K.Text(parent, "header", "zone")
    fs:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -y)
    fs:SetText(text)
    return y + Th.LineHeight("header") + 4
end

local function Para(parent, y, width, text, color)
    local fs = K.Text(parent, "goal", color or "text.dim")
    fs:SetWordWrap(true)
    fs:SetWidth(width)
    fs:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -y)
    fs:SetText(text)
    local h = math.max(Th.LineHeight("goal"), fs:GetStringHeight() or 0)
    return y + h + 6, fs
end

local function SmallButton(parent, text, fn, primary)
    return K.Button(parent, text, function() fn() end, { primary = primary, feature = "report" })
end

-- The steps on offer (current + last 3) with a readable line each.
local function StepLine(entry)
    local g = ns.Engine.Focused()
    local text
    if g then
        local top = g:Top()
        local i = top:IndexOf(entry.id)
        local step = i and top:Step(i)
        if step then text = top:Text(step) end
    end
    text = ns.U.Plain(text or entry.id)
    if entry.current then return ns.U.Fill(L().REPORT_STEP_NOW, { text = text }) end
    return ns.U.Fill(L().REPORT_STEP_EARLIER, { text = text, how = L()["REPORT_HOW_" .. tostring(entry.how):upper()] or entry.how })
end

-- A step's line that can never stop the page: a step whose text can't be made shows its id (beta.7 bug:
-- an error here left the four rows empty, their rings drawn over the "no guide is open" line).
local function SafeStepLine(entry)
    local ok, text = pcall(StepLine, entry)
    if ok and type(text) == "string" and text ~= "" then return text end
    return ns.U.Plain(tostring(entry.id or "?"))
end

-- The "no step" line: no guide open, or a guide open with no step to pick (finished, waiting).
local function NoStepText()
    if ns.Engine.Focused() then return L().REPORT_NO_STEP_GUIDE end
    return L().REPORT_NO_STEP
end

function HR.String()
    return ns.Report.Build(HR.opts)
end

-- HR.page is only set once Build has made every part (see Build), but the parts are still checked one by
-- one: a page that failed half-way in game must never turn each click into a second error.
-- The step rows come first: either the rows or the "no step" line, never both (they share a spot).
function HR.Update()
    local p = HR.page
    if not p then return end
    local steps = ns.Report.Steps()
    if p.noStep then
        p.noStep:SetShown(#steps == 0)
        if #steps == 0 then p.noStep:SetText(NoStepText()) end
    end
    if not HR.opts.stepId and steps[1] then HR.opts.stepId = steps[1].id end
    for i, b in ipairs(HR.stepButtons) do
        local e = steps[i]
        if e then
            b.value = e.id
            b.text:SetText(SafeStepLine(e))
            b:Set(e.id == HR.opts.stepId)
            b:Show()
        else
            b:Hide()
        end
    end
    for _, b in ipairs(HR.typeButtons) do b:Set(b.value == HR.opts.about) end
    if p.noloc then p.noloc:Set(HR.opts.noloc) end
    if p.evidence then p.evidence:Set(HR.opts.evidence) end
    local s, f = HR.String()
    HR.last, HR.lastFields = s, f
    if p.preview then p.preview:SetText(s) end
    if p.title then p.title:SetText(ns.Report.Title(f)) end
    if p.count then p.count:SetText(ns.U.Fill(L().REPORT_LENGTH, { n = #s, max = ns.Report.MAX_LEN })) end
end

-- The parts Update and the buttons need (the self-test and the offline tests check them all).
HR.PARTS = { "noStep", "note", "noloc", "evidence", "preview", "count", "title", "send", "status", "waiting", "copy" }

-- The line under Send: how many reports from this session wait for the Addon Manager.
function HR.WaitingText()
    local n = ns.Report.queued or 0
    if n > 0 then return ns.U.Fill(L().REPORT_WAITING, { n = n }) end
    if #ns.Report.Outbox() > 0 then return L().REPORT_WAITING_OLD end
    return L().REPORT_WAITING_NONE
end

local function ShowStatus(text, color)
    local p = HR.page
    if not (p and p.status and p.waiting) then return end
    p.status:SetText(text or "")
    K.Color(p.status, color or "quest")
    p.waiting:SetText(HR.WaitingText())
end

-- The easy way: "Send" saves it for the Addon Manager (it sends it when the game is closed). A new report
-- id after a send, so the next report is a new one; a second click with nothing changed isn't queued twice.
function HR.Send()
    local s = HR.String()
    local how, dropped = ns.Report.Queue(s)
    if how == "added" then
        ns.Report.NewId()
        HR.Update()
        if dropped and dropped > 0 then
            -- never silently: older reports (from an earlier session) left the outbox to make room
            ShowStatus(L().REPORT_SENT .. " " .. ns.U.Fill(L().REPORT_OUTBOX_ROLLED, { n = dropped }), "notice.useitem")
        else
            ShowStatus(L().REPORT_SENT, "quest")
        end
    elseif how == "same" then
        ShowStatus(L().REPORT_SENT_SAME, "quest")
    elseif how == "full" then
        ShowStatus(ns.U.Fill(L().REPORT_OUTBOX_FULL, { n = ns.Report.queued or 0 }), "notice.danger")
    else
        ShowStatus(L().REPORT_SEND_FAIL, "notice.danger")
    end
    return how, s
end

-- No Addon Manager: copy the line and paste it on the web page (the address is shown in the copy box).
function HR.Copy()
    local s = HR.String()
    ns.Report.Keep(s)
    ns.Popups.Copy(L().REPORT_COPY_TITLE, s, ns.U.Fill(L().REPORT_WEB_WHERE, { url = HR.URL }))
    return s
end

-- Builds into local tables and makes them the page (HR.page, .typeButtons, .stepButtons) only at the end:
-- a build that stops half-way (the Hub shows the error) leaves no half page behind for the clicks to use.
local function Build(parent, width)
    local p = { parent = parent, width = width }
    local typeButtons, stepButtons = {}, {}
    local y = 0
    y = Para(parent, y, width, L().REPORT_INTRO2, "text")
    y = Head(parent, y + 4, L().REPORT_WHAT)
    -- two columns when each gets at least COL_MIN units, else one (the Hub's minimum width)
    local cols = math.floor(width / 2) >= HR.COL_MIN and 2 or 1
    local colW = math.floor(width / cols)
    HR.cols = cols
    local rowH = Th.LineHeight("step") + 4
    for i, t in ipairs(ns.Report.TYPES) do
        local b = Choice(parent, L()["REPORT_TYPE_" .. t:upper()], function(self)
            HR.opts.about = self.value
            HR.Update()
        end, true)
        b.value = t
        -- the type icon sits left, after the box; the text runs from it to the row's right edge
        b.icon = K.Glyph(b, TYPE_ICON[t], Th.Size("box") + 4, "button")
        b.icon:SetPoint("LEFT", b.box, "RIGHT", 4, 0)
        b.text:ClearAllPoints()
        b.text:SetPoint("LEFT", b.icon, "RIGHT", 4, 0)
        b.text:SetPoint("RIGHT", b, "RIGHT", 0, 0)
        local col, row = (i - 1) % cols, math.floor((i - 1) / cols)
        b:SetPoint("TOPLEFT", parent, "TOPLEFT", col * colW, -(y + row * rowH))
        b:SetWidth(colW - 8)
        typeButtons[i] = b
    end
    y = y + math.ceil(#ns.Report.TYPES / cols) * rowH + 6
    y = Head(parent, y, L().REPORT_WHICH)
    for i = 1, 4 do
        local b = Choice(parent, "", function(self)
            HR.opts.stepId = self.value
            HR.Update()
        end, true)
        b:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -(y + (i - 1) * rowH))
        b:SetWidth(width)
        b:Hide()                 -- shown by Update, filled in (never an empty ring on the page)
        stepButtons[i] = b
    end
    -- same spot as the first row: Update shows either the rows or this line
    p.noStep = K.Text(parent, "goal", "text.dim")
    p.noStep:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -y)
    p.noStep:SetWidth(width)
    p.noStep:SetText(L().REPORT_NO_STEP)
    p.noStep:Hide()
    y = y + 4 * rowH + 6
    y = Head(parent, y, L().REPORT_NOTE)
    local e = CreateFrame("EditBox", nil, parent)
    e:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -y)
    e:SetSize(width, Th.LineHeight("step") + 8)
    e:SetAutoFocus(false)
    e:SetMaxLetters(ns.Report.NOTE_MAX)
    Th.Font(e, "step")
    e:SetTextColor(Th.Color("text"))
    K.Fill(e, "BACKGROUND", "barTrack"):SetAllPoints()
    e:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    e:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    e:SetScript("OnTextChanged", function(self)
        HR.opts.note = self:GetText()
        ns.Errors.Call("report", HR.Update)
    end)
    p.note = e
    K.searchBoxes[#K.searchBoxes + 1] = e   -- lets go of the keyboard when combat starts (tos-beta3)
    y = y + Th.LineHeight("step") + 14
    p.noloc = Choice(parent, L().REPORT_NOLOC, function()
        HR.opts.noloc = not HR.opts.noloc
        HR.Update()
    end)
    p.noloc:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -y)
    p.noloc:SetWidth(width)
    y = y + rowH
    p.evidence = Choice(parent, L().REPORT_EVIDENCE, function()
        HR.opts.evidence = not HR.opts.evidence
        HR.Update()
    end)
    p.evidence:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -y)
    p.evidence:SetWidth(width)
    y = y + rowH + 6
    y = Head(parent, y, L().REPORT_PREVIEW)
    -- fixed height: a full 1,500-character line is cut after PREVIEW_LINES ("..."), never over the rest
    -- (the copy box always holds the whole line)
    local previewH = Th.LineHeight("small") * HR.PREVIEW_LINES
    p.preview = K.Text(parent, "small", "text")
    p.preview:SetWordWrap(true)
    p.preview:SetWidth(width)
    p.preview:SetHeight(previewH)
    p.preview:SetJustifyV("TOP")
    if p.preview.SetMaxLines then p.preview:SetMaxLines(HR.PREVIEW_LINES) end
    p.preview:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -y)
    y = y + previewH + 4
    p.count = K.Text(parent, "small", "text.dim")
    p.count:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -y)
    y = y + Th.LineHeight("small") + 4
    p.title = K.Text(parent, "goal", "quest")
    p.title:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -y)
    p.title:SetWidth(width)
    y = y + Th.LineHeight("goal") + 8
    -- the easy way first: Send (the Addon Manager sends it), then what happened and how many wait
    y = Para(parent, y, width, L().REPORT_PUBLIC2, "notice.danger")
    p.send = SmallButton(parent, L().REPORT_SEND, HR.Send, true)
    p.send:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -y)
    y = y + Th.LineHeight("step") + 14
    local statusH = Th.LineHeight("goal") * 2
    p.status = K.Text(parent, "goal", "quest")
    p.status:SetWordWrap(true)
    p.status:SetWidth(width)
    p.status:SetHeight(statusH)
    p.status:SetJustifyV("TOP")
    p.status:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -y)
    p.status:SetText("")
    y = y + statusH + 2
    -- fixed room (two lines): the waiting line changes after a send
    p.waiting = K.Text(parent, "goal", "text.dim")
    p.waiting:SetWordWrap(true)
    p.waiting:SetWidth(width)
    p.waiting:SetHeight(statusH)
    p.waiting:SetJustifyV("TOP")
    p.waiting:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -y)
    p.waiting:SetText(HR.WaitingText())
    y = y + statusH + 6
    y = Para(parent, y, width, L().REPORT_GRANT2)
    -- the other way, smaller: copy the line and paste it on the web page
    y = Head(parent, y + 6, L().REPORT_WEB_HEAD)
    y = Para(parent, y, width, L().REPORT_WEB_INTRO)
    p.copy = SmallButton(parent, L().REPORT_WEB_BUTTON, HR.Copy)
    p.copy:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -y)
    -- never wider than the page (a long translation at the Hub's minimum width)
    for _, b in ipairs({ p.send, p.copy }) do
        if b:GetWidth() > width then b:SetWidth(width) end
    end
    y = y + Th.LineHeight("step") + 14
    y = Para(parent, y, width, ns.U.Fill(L().REPORT_GITHUB, { url = HR.URL }))
    -- every part is there: now it is the page
    HR.page, HR.typeButtons, HR.stepButtons = p, typeButtons, stepButtons
    -- a rebuilt page (new look) keeps the note typed so far (set last: OnTextChanged updates the page)
    if HR.opts.note and HR.opts.note ~= "" then p.note:SetText(HR.opts.note) end
    -- filled in right away: the page is right even when the Hub's refresh doesn't run after the build
    ns.Errors.Call("report", HR.Update)
    return y + 8
end

ns.Hub.AddPage("report", { title = "HUB_REPORT", icon = "hub.report", order = 57, build = Build, refresh = function()
    ns.Report.NewId()
    HR.opts.stepId = nil
    -- a pre-filled report (HR.Prefill: the quest giver check's "Report this"): type + note only; the player's
    -- choices (leave out my location, NPC evidence) stay as they are, nothing is sent until Send / Copy
    local pf = HR.prefill
    HR.prefill = nil
    if type(pf) == "table" then
        if pf.about then HR.opts.about = pf.about end
        if type(pf.note) == "string" then
            HR.opts.note = pf.note
            if HR.page and HR.page.note then HR.page.note:SetText(pf.note) end
        end
    end
    HR.Update()
    -- a fresh page: no "Saved." from last time, the current waiting count
    if HR.page and HR.page.status then
        HR.page.status:SetText("")
        HR.page.waiting:SetText(HR.WaitingText())
    end
end })

-- Self-test: once the Report page was built, every part (HR.PARTS) and choice row is there, Send (primary) and the web-page button are there and fit the
-- page, the status / waiting lines exist and the web address is set.
ns.SelfChecks[#ns.SelfChecks + 1] = { label = "report page", fn = function(h)
    h.Count()
    if type(HR.WEB_URL) ~= "string" or not HR.WEB_URL:find("%.") then h.Problem("report page: no web address") end
    local p = HR.page
    if not p then h.Info("report page: not opened yet") return end
    for _, k in ipairs(HR.PARTS) do
        if not p[k] then h.Problem("report page: part " .. k .. " missing") return end
    end
    if #HR.typeButtons ~= #ns.Report.TYPES or #HR.stepButtons ~= 4 then h.Problem("report page: choice rows missing") return end
    if not p.send.primary then h.Problem("report page: Send isn't the main button") end
    -- the step rows: shown ones are filled in, and never together with the "no step" line (beta.7 bug)
    local shown = 0
    for _, b in ipairs(HR.stepButtons) do
        if b:IsShown() then
            shown = shown + 1
            if (b.text:GetText() or "") == "" then h.Problem("report page: an empty step row") end
        end
    end
    if shown > 0 and p.noStep:IsShown() then h.Problem("report page: step rows over the no-step line") end
    local pw = p.width or 0
    for _, b in ipairs({ p.send, p.copy }) do
        local w = b:GetWidth() or 0
        if w < 1 or (pw > 0 and w > pw + 1) then h.Problem(("report page: a button is %d wide (page %d)"):format(w, pw)) end
    end
end }

-- Opens the Report page (title menu, /aog report).
function HR.Open()
    return ns.Hub.Open("report")
end

-- Opens the Report page filled in: opts = { about (a Report.TYPES value), note }. Only fills the page.
function HR.Prefill(opts)
    if type(opts) ~= "table" then return false end
    HR.prefill = { about = opts.about, note = opts.note and ns.U.Utf8Cut(tostring(opts.note), ns.Report.NOTE_MAX) or nil }
    return HR.Open()
end
ns.Slash.Add("report", function() HR.Open() end, "HELP_REPORT", { main = true })
