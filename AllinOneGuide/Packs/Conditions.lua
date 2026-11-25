-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 gettic
-- The condition grammar (packs-src\FORMAT.md section 5). Data, never Lua: parsed once, cached, and
-- evaluated while playing against a context table. Shared with the pack checker; depends on nothing in ns.
--   expr := term {"or" term};  term := factor {"and" factor};  factor := "not" factor | "(" expr ")" | atom
--   atom := key "=" value{,value}  |  key (">=" | "<=" | ">" | "<") number
-- An unknown key makes the whole condition "not applicable" (so newer packs keep working).
local _, ns = ...
local Cd = { cache = {}, cacheSize = 0, CACHE_MAX = 512 }
ns.Conditions = Cd

-- Keys for "who is this for" conditions, and goal words (override goals and checker goals).
Cd.KEYS = { level = "number", class = "set", race = "set", faction = "set", sex = "set", prof = "true",
    flag = "set", spec = "true", role = "true" }
Cd.GOALS = { done = "id", inlog = "id", ready = "id", item = "item" }
-- keys whose answer can change while playing (everything else is cached per character)
Cd.DYNAMIC = { level = true, flag = true, done = true, inlog = true, ready = true, item = true }

local function Tokens(s)
    local t, i, n = {}, 1, #s
    while i <= n do
        local c = s:sub(i, i)
        if c:match("%s") then
            i = i + 1
        elseif c == "(" or c == ")" then
            t[#t + 1] = c
            i = i + 1
        else
            local w = s:match("^[^%s()]+", i)
            t[#t + 1] = w
            i = i + #w
        end
    end
    return t
end

local function Atom(word, goals)
    local key, rest = word:match("^(%a+)(.*)$")
    if not key then return nil, "bad condition word '" .. word .. "'" end
    local op = rest:match("^([<>]=?)") or rest:match("^(=)")
    if not op then return nil, "no operator in '" .. word .. "'" end
    local value = rest:sub(#op + 1)
    if value == "" then return nil, "no value in '" .. word .. "'" end
    local a = { op = "atom", key = key, cmp = op }
    local kind = Cd.KEYS[key] or (goals and Cd.GOALS[key])
    if not kind then
        a.unknown = true
        return a
    end
    if kind == "number" then
        a.num = tonumber(value)
        if not a.num then return nil, "not a number in '" .. word .. "'" end
    else
        if op ~= "=" then return nil, "only '=' works with " .. key end
        a.values = {}
        for v in value:gmatch("[^,]+") do a.values[#a.values + 1] = v end
        if kind == "id" or kind == "item" then
            for i, v in ipairs(a.values) do
                local id, count = v:match("^(%d+):?(%d*)$")
                if not id then return nil, "not an id in '" .. word .. "'" end
                a.values[i] = { tonumber(id), tonumber(count) or 1 }
            end
        end
    end
    a.kind = kind
    return a
end

-- Parses a condition string. goals = true allows done / inlog / ready / item.
-- Returns ast or nil, error. ast.unknown lists unknown keys; ast.dynamic is true when it can change in play.
function Cd.Parse(s, goals)
    if type(s) ~= "string" then return nil, "not a string" end
    local toks = Tokens(s)
    local pos = 1
    local info = { unknown = {}, dynamic = false }
    local Expr
    local function Factor()
        local t = toks[pos]
        if t == nil then return nil, "condition ends too early" end
        if t == "not" then
            pos = pos + 1
            local x, err = Factor()
            if not x then return nil, err end
            return { op = "not", x }
        elseif t == "(" then
            pos = pos + 1
            local x, err = Expr()
            if not x then return nil, err end
            if toks[pos] ~= ")" then return nil, "missing ')'" end
            pos = pos + 1
            return x
        elseif t == ")" or t == "and" or t == "or" then
            return nil, "unexpected '" .. t .. "'"
        end
        pos = pos + 1
        local a, err = Atom(t, goals)
        if not a then return nil, err end
        if a.unknown then info.unknown[#info.unknown + 1] = a.key end
        if Cd.DYNAMIC[a.key] then info.dynamic = true end
        return a
    end
    local function Term()
        local x, err = Factor()
        if not x then return nil, err end
        while toks[pos] == "and" do
            pos = pos + 1
            local y
            y, err = Factor()
            if not y then return nil, err end
            x = { op = "and", x, y }
        end
        return x
    end
    Expr = function()
        local x, err = Term()
        if not x then return nil, err end
        while toks[pos] == "or" do
            pos = pos + 1
            local y
            y, err = Term()
            if not y then return nil, err end
            x = { op = "or", x, y }
        end
        return x
    end
    if #toks == 0 then return nil, "empty condition" end
    local ast, err = Expr()
    if not ast then return nil, err end
    if pos <= #toks then return nil, "unexpected '" .. tostring(toks[pos]) .. "'" end
    ast.info = info
    return ast
end

-- Cached parse (the same strings repeat on many steps).
function Cd.Get(s, goals)
    local key = (goals and "g:" or "c:") .. s
    local hit = Cd.cache[key]
    if hit ~= nil then return hit or nil end
    local ast = Cd.Parse(s, goals)
    if Cd.cacheSize >= Cd.CACHE_MAX then Cd.cache, Cd.cacheSize = {}, 0 end
    Cd.cache[key] = ast or false
    Cd.cacheSize = Cd.cacheSize + 1
    return ast
end

local SEX = { male = 2, female = 3 }

local function In(values, v)
    for _, x in ipairs(values) do if x == v then return true end end
    return false
end

local function Eval(a, ctx)
    local op = a.op
    if op == "and" then return Eval(a[1], ctx) and Eval(a[2], ctx) end
    if op == "or" then return Eval(a[1], ctx) or Eval(a[2], ctx) end
    if op == "not" then return not Eval(a[1], ctx) end
    local key = a.key
    if a.kind == "true" then return true end
    if key == "level" then
        local lv = ctx.level
        if not lv then return false end
        local n, c = a.num, a.cmp
        if c == "=" then return lv == n elseif c == ">=" then return lv >= n elseif c == "<=" then return lv <= n
        elseif c == ">" then return lv > n else return lv < n end
    elseif key == "sex" then
        for _, v in ipairs(a.values) do if SEX[v:lower()] == ctx.sex then return true end end
        return false
    elseif key == "flag" then
        for _, v in ipairs(a.values) do if ctx.flags and ctx.flags[v] then return true end end
        return false
    elseif a.kind == "set" then
        return In(a.values, ctx[key])
    elseif a.kind == "id" then
        local f = ctx[key]
        if not f then return false end
        for _, v in ipairs(a.values) do if f(v[1]) then return true end end
        return false
    elseif a.kind == "item" then
        local f = ctx.itemCount
        if not f then return false end
        for _, v in ipairs(a.values) do if f(v[1]) >= v[2] then return true end end
        return false
    end
    return false
end

-- true / false; a condition with an unknown word is never true ("not applicable").
function Cd.Check(ast, ctx)
    if not ast then return false end
    if #ast.info.unknown > 0 then return false end
    return Eval(ast, ctx) == true
end
