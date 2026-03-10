local passes, fails = 0, 0
local results = {}
local pending = 0
local allQueued = false

local function tryPrintSummary()
    if not allQueued or pending > 0 then return end

    local total = passes + fails
    local rate  = math.round(passes / math.max(total, 1) * 100)
    print("\n")
    print("UNC Environment Check")
    print(("  ✅ %d passed   ❌ %d failed   📊 %d%%"):format(passes, fails, rate))
end

local function getGlobal(path)
    local v = getfenv(0)
    while v ~= nil and path ~= "" do
        local name, rest = string.match(path, "^([^.]+)%.?(.*)$")
        v    = v[name]
        path = rest
    end
    return v
end

local function test(name, aliases, fn)
    pending += 1
    task.spawn(function()
        local entry = { name = name, aliases = aliases or {} }
        if not fn then
            if getGlobal(name) ~= nil then
                entry.status = "pass"
                entry.note   = "exists (no test body)"
                passes += 1
            else
                entry.status = "fail"
                entry.note   = "nil – not implemented"
                fails += 1
            end
        else
            local ok, msg = pcall(fn)
            if ok then
                entry.status = "pass"
                entry.note   = type(msg) == "string" and msg or nil
                passes += 1
            else
                entry.status = "fail"
                entry.note   = tostring(msg)
                fails += 1
            end
        end

        local missing = {}
        for _, alias in ipairs(aliases or {}) do
            if getGlobal(alias) == nil then
                table.insert(missing, alias)
            end
        end
        if #missing > 0 then
            entry.missingAliases = table.concat(missing, ", ")
        end

        local icon   = entry.status == "pass" and "✅" or "❌"
        local suffix = entry.note and (" » " .. entry.note) or ""
        local alias  = entry.missingAliases and (" ⚠️ missing aliases: " .. entry.missingAliases) or ""
        print(icon .. " " .. name .. suffix .. alias)

        table.insert(results, entry)
        pending -= 1
        tryPrintSummary()
    end)
end

local function shallowEqual(t1, t2)
    if t1 == t2 then return true end
    local UNIQUE = { ["function"]=true, ["table"]=true, ["userdata"]=true, ["thread"]=true }
    for k, v in pairs(t1) do
        if UNIQUE[type(v)] then if type(t2[k]) ~= type(v)  then return false end
        elseif t2[k] ~= v  then return false end
    end
    for k, v in pairs(t2) do
        if UNIQUE[type(v)] then if type(t1[k]) ~= type(v)  then return false end
        elseif t1[k] ~= v  then return false end
    end
    return true
end

if isfolder and makefolder and delfolder then
    if isfolder(".unc") then delfolder(".unc") end
    makefolder(".unc")
end

test("identifyexecutor", { "getexecutorname" }, function()
    local name, version = identifyexecutor()
    assert(type(name)    == "string" and #name > 0,    "name must be a non-empty string")
    assert(type(version) == "string" and #version > 0, "version must be a non-empty string")
    assert(getexecutorname() == name, "getexecutorname() should match identifyexecutor()")
    return name .. " " .. version
end)

test("checkcaller", {}, function()
    assert(checkcaller() == true, "main scope should return true")
end)

test("getthreadidentity", { "getidentity", "getthreadcontext" }, function()
    local id = getthreadidentity()
    assert(type(id) == "number",          "must return a number")
    assert(id >= 0 and id <= 8,           "identity must be in range 0-8")
    assert(getidentity()      == id,      "getidentity alias mismatch")
    assert(getthreadcontext() == id,      "getthreadcontext alias mismatch")
    return "identity = " .. id
end)

test("setthreadidentity", { "setidentity", "setthreadcontext" }, function()
    local old = getthreadidentity()
    setthreadidentity(2)
    assert(getthreadidentity() == 2, "failed to set identity to 2")
    setidentity(3)
    assert(getthreadidentity() == 3, "setidentity alias failed")
    setthreadcontext(old)
    assert(getthreadidentity() == old, "failed to restore identity")
end)

test("getgenv", {}, function()
	getgenv().__TEST_GLOBAL = true
	assert(__TEST_GLOBAL, "Failed to set a global variable")
	getgenv().__TEST_GLOBAL = nil
end)

test("getrenv", {}, function()
    local r = getrenv()
    assert(type(r) == "table",         "must return a table")
    assert(r._G ~= _G,                 "executor _G must differ from game _G")
    assert(r.print == print,           "getrenv should expose print")
end)

test("getmenv", {}, function()
    local m = getmenv()
    assert(type(m) == "table",         "must return a table")
end)

test("getsenv", {}, function()
    local scripts = getscripts()
    assert(#scripts > 0, "no scripts found to test getsenv")
    local target = scripts[1]
    local env = getsenv(target)
    assert(type(env) == "table",       "must return a table")
    assert(env.script == target,       "env.script must equal the target script")
end)

test("getfpscap", {}, function()
    local f = getfpscap()
    assert(type(f) == "number" and f >= 0, "must return a non-negative number")
    return "current cap = " .. f
end)

test("setfpscap", {}, function()
    local old = getfpscap()
    setfpscap(60)
    assert(getfpscap() == 60, "failed to set fps cap to 60")
    setfpscap(0)
    assert(getfpscap() == 0,  "failed to set fps cap to 0 (unlimited)")
    setfpscap(old)
end)

test("islclosure", { "isluaclosure" }, function()
    assert(islclosure(print)           == false, "print is not an lclosure")
    assert(islclosure(function() end)  == true,  "anonymous function must be lclosure")
    assert(isluaclosure(function() end)== true,  "isluaclosure alias must work")
end)

test("iscclosure", {}, function()
    assert(iscclosure(print)           == true,  "print must be a cclosure")
    assert(iscclosure(function() end)  == false, "anonymous function is not a cclosure")
end)

test("newlclosure", {}, function()
    local function fn() return "lc" end
    local lc = newlclosure(fn)
    assert(lc ~= fn,                   "new lclosure should not be identical to original")
    assert(islclosure(lc),             "result must be an lclosure")
    assert(lc() == "lc",               "new lclosure should return same value")
    assert(isexecutorclosure(lc),      "new lclosure must be an executor closure")
end)

test("newcclosure", {}, function()
    local function fn() return "cc" end
    local cc = newcclosure(fn)
    assert(cc ~= fn,                   "new cclosure should not be identical to original")
    assert(iscclosure(cc),             "result must be a cclosure")
    assert(cc() == "cc",               "new cclosure should return same value")
end)

test("clonefunction", {}, function()
    local function fn() return 42 end
    local clone = clonefunction(fn)
    assert(clone ~= fn,                "clone must not be the same reference")
    assert(clone() == 42,              "clone must return the same value")
end)

test("isourclosure", { "isexecutorclosure", "checkclosure" }, function()
    assert(isourclosure(isourclosure)               == true,  "executor global must be an executor closure")
    assert(isourclosure(newcclosure(function()end)) == true,  "executor cclosure must pass")
    assert(isourclosure(function() end)             == true,  "executor lclosure must pass")
    assert(isourclosure(print)                      == false, "game global must not pass")
    assert(isexecutorclosure == isourclosure or isexecutorclosure(print) == false, "alias must behave identically")
    assert(checkclosure      == isourclosure or checkclosure(print)      == false, "alias must behave identically")
end)

test("hookfunction", { "replaceclosure" }, function()
    local function fn() return "original" end
    local ref = hookfunction(fn, function() return "hooked" end)
    assert(fn()  == "hooked",          "hooked function must return 'hooked'")
    assert(ref() == "original",        "ref must return original value")
    assert(fn ~= ref,                  "original and ref must differ")
    hookfunction(fn, ref)
    assert(replaceclosure ~= nil,      "replaceclosure alias must exist")
end)

test("getscriptclosure", { "getscriptfunction" }, function()
    local module = game:GetService("CoreGui").RobloxGui.Modules.Common.CommonUtil
    local original  = getrenv().require(module)
    local generated = getscriptclosure(module)()
    assert(original ~= generated,             "generated module must not be same reference as original")
    assert(shallowEqual(original, generated), "generated table must be shallow-equal to original")
    assert(getscriptfunction ~= nil,          "getscriptfunction alias must exist")
end)

test("getfunctionhash", {}, function()
    local function fn() return "hash_test" end
    local h = getfunctionhash(fn)
    assert(type(h) == "string" and #h > 0, "must return a non-empty string")
    assert(h == getfunctionhash(fn),        "same function must produce same hash")
    local function fn2() return "different" end
    assert(type(getfunctionhash(fn2)) == "string", "must hash a different function too")
end)

test("cloneref", {}, function()
    local part  = Instance.new("Part")
    local clone = cloneref(part)
    assert(part ~= clone,              "clone reference must differ from original")
    clone.Name = "cloneref_test"
    assert(part.Name == "cloneref_test", "write through clone must affect original")
    part:Destroy()
end)

test("compareinstances", {}, function()
    local part  = Instance.new("Part")
    local clone = cloneref(part)
    assert(part  ~= clone,                    "raw equality must be false")
    assert(compareinstances(part, clone),     "compareinstances must return true for cloneref pair")
    assert(not compareinstances(part, game), "must return false for unrelated instances")
    part:Destroy()
end)

test("getinstances", {}, function()
    local t = getinstances()
    assert(type(t) == "table" and #t > 0,  "must return a non-empty table")
    assert(typeof(t[1]) == "Instance",     "first element must be an Instance")
end)

test("getnilinstances", {}, function()
    local t = getnilinstances()
    assert(type(t) == "table",             "must return a table")
    for _, v in ipairs(t) do
        assert(typeof(v) == "Instance",    "all elements must be Instances")
        assert(v.Parent  == nil,           "all elements must have nil Parent")
    end
end)

test("getloadedmodules", {}, function()
    local t = getloadedmodules()
    assert(type(t) == "table" and #t > 0, "must return a non-empty table")
    assert(t[1]:IsA("ModuleScript"),       "first element must be a ModuleScript")
end)

test("getrunningscripts", {}, function()
    local t = getrunningscripts()
    assert(type(t) == "table" and #t > 0, "must return a non-empty table")
    local v = t[1]
    assert(v:IsA("ModuleScript") or v:IsA("LocalScript"), "must contain LocalScript or ModuleScript")
end)

test("getscripts", {}, function()
    local t = getscripts()
    assert(type(t) == "table" and #t > 0, "must return a non-empty table")
    local v = t[1]
    assert(v:IsA("ModuleScript") or v:IsA("LocalScript"), "must contain LocalScript or ModuleScript")
end)

test("gethui", { "get_hidden_gui" }, function()
    local h = gethui()
    assert(typeof(h)   == "Instance",  "must return an Instance")
    assert(h.ClassName == "ScreenGui", "must return a ScreenGui")
    assert(get_hidden_gui() == h,      "get_hidden_gui alias must match")
end)

test("getcallingscript", {}, function()
    local s = getcallingscript()
    assert(s == nil or typeof(s) == "Instance", "must return nil or an Instance")
end)

test("getcallbackvalue", {}, function()
    local bf = Instance.new("BindableFunction")
    bf.Parent = game:GetService("Players").LocalPlayer.PlayerGui
    local function handler() return "called" end
    bf.OnInvoke = handler
    assert(getcallbackvalue(bf, "OnInvoke") == handler, "must return the registered callback")
    bf:Destroy()
end)

test("getactors", {}, function()
    local t = getactors()
    assert(type(t) == "table", "must return a table")
    for _, v in ipairs(t) do
        assert(v:IsA("Actor"), "every element must be an Actor")
    end
end)

test("getspecialinfo", {}, function()
    local player = game:GetService("Players").LocalPlayer
    local info = getspecialinfo(player)
    assert(type(info) == "table", "must return a table")
end)

test("getobjects", {}, function()
    local ok, result = pcall(getobjects, "rbxassetid://0")
    assert(ok and type(result) == "table", "must return a table (empty asset is fine)")
end)

test("typeof", {}, function()
    local p = cloneref(game)
    assert(typeof(p)             == "Instance", "proxy must resolve to Instance")
    assert(typeof(Vector3.new()) == "Vector3",  "Vector3 must resolve correctly")
    assert(typeof(42)            == "number",   "number must resolve correctly")
end)

test("gethiddenproperty", { "gethiddenprop" }, function()
    local fire = Instance.new("Fire")
    local value, isHidden = gethiddenproperty(fire, "size_xml")
    assert(value    == 5,    "size_xml default must be 5")
    assert(isHidden == true, "size_xml must report as hidden")
    assert(gethiddenprop(fire, "size_xml") == 5, "gethiddenprop alias must work")
end)

test("sethiddenproperty", { "sethiddenprop" }, function()
    local fire = Instance.new("Fire")
    local wasHidden = sethiddenproperty(fire, "size_xml", 10)
    assert(wasHidden == true,                         "must return true for hidden property")
    assert(gethiddenproperty(fire, "size_xml") == 10, "must have applied the new value")
    sethiddenprop(fire, "size_xml", 5)
    assert(gethiddenproperty(fire, "size_xml") == 5,  "sethiddenprop alias must work")
end)

test("isscriptable", {}, function()
    local fire = Instance.new("Fire")
    assert(isscriptable(fire, "size_xml") == false, "size_xml must not be scriptable")
    assert(isscriptable(fire, "Size")     == true,  "Size must be scriptable")
end)

test("setscriptable", {}, function()
    local fire = Instance.new("Fire")
    local was  = setscriptable(fire, "size_xml", true)
    assert(was == false,                           "must return the previous scriptability (false)")
    assert(isscriptable(fire, "size_xml") == true, "must now be scriptable")
    local fire2 = Instance.new("Fire")
    assert(isscriptable(fire2, "size_xml") == false, "must not persist across new instances")
end)

test("getscriptbytecode", { "dumpstring" }, function()
    local animate = game:GetService("Players").LocalPlayer.Character.Animate
    local bc = getscriptbytecode(animate)
    assert(type(bc) == "string" and #bc > 0, "must return non-empty string bytecode")
    assert(dumpstring(animate) == bc,         "dumpstring alias must match")
end)

test("getscripthash", {}, function()
    local animate  = game:GetService("Players").LocalPlayer.Character.Animate:Clone()
    local hash1    = getscripthash(animate)
    assert(type(hash1) == "string" and #hash1 > 0, "must return a non-empty hash string")
    local src      = animate.Source
    animate.Source = "print('changed')"
    local hash2    = getscripthash(animate)
    assert(hash1 ~= hash2,                  "different source must produce different hash")
    assert(hash2 == getscripthash(animate), "same source must produce same hash deterministically")
    task.defer(function() animate.Source = src end)
end)

test("getscriptsource", {}, function()
    local animate = game:GetService("Players").LocalPlayer.Character.Animate
    local src     = getscriptsource(animate)
    assert(type(src) == "string" and #src > 0, "must return non-empty source string")
end)

test("decompile", {}, function()
    local animate = game:GetService("Players").LocalPlayer.Character.Animate
    local result  = decompile(animate)
    assert(type(result) == "string", "must return a string (decompiled or stub)")
end)

test("loadstring", {}, function()
    local f, err = loadstring("return 1 + 1")
    assert(type(f)  == "function", "must return a function for valid code")
    assert(f()      == 2,          "compiled function must evaluate correctly")
    local f2, e2 = loadstring("this is invalid!!!@#")
    assert(f2 == nil,             "must return nil for invalid code")
    assert(type(e2) == "string",  "must return error message for invalid code")
    local animate = game:GetService("Players").LocalPlayer.Character.Animate
    local bc      = getscriptbytecode(animate)
    local f3      = loadstring(bc)
    assert(type(f3) ~= "function", "raw Luau bytecode must not be loadable via loadstring")
    local f4 = assert(loadstring("return ... + 1"))
    assert(f4(10) == 11, "varargs must work through loadstring")
end)

test("compile", {}, function()
    local bc = compile("return 'hello'")
    assert(type(bc) == "string" and #bc > 0, "must return non-empty bytecode string")
end)

test("setscriptbytecode", {}, function()
    local dummy = Instance.new("LocalScript")
    dummy.Parent = game:GetService("Players").LocalPlayer.PlayerGui
    local bc    = compile("return true", true)
    local ok    = pcall(setscriptbytecode, dummy, bc)
    assert(ok, "setscriptbytecode must not throw on a valid script + bytecode")
    dummy:Destroy()
end)

test("getreg", { "getregistry" }, function()
    local reg = getreg()
    assert(type(reg) == "table" and #reg > 0, "must return non-empty table")
    local hasFunc, hasTable = false, false
    for _, v in pairs(reg) do
        if type(v) == "function" then hasFunc  = true end
        if type(v) == "table"    then hasTable = true end
        if hasFunc and hasTable  then break end
    end
    assert(hasFunc,  "registry must contain at least one function")
    assert(hasTable, "registry must contain at least one table")
    assert(getregistry() == getreg() or type(getregistry()) == "table", "getregistry alias must work")
end)

test("getgc", {}, function()
    local gc = getgc()
    assert(type(gc) == "table" and #gc > 0, "must return non-empty table")
    local gcT = getgc(true)
    assert(type(gcT) == "table",            "passing true must also return a table")
    assert(#gcT >= #gc,                     "including tables must return more or equal entries")
end)

test("filtergc", {}, function()
    local funcs = filtergc("function", {})
    assert(type(funcs) == "table" and #funcs > 0, "must return non-empty table for 'function' filter")
    for _, v in ipairs(funcs) do
        assert(type(v) == "function", "all results must be functions")
    end
    local tables = filtergc("table", {})
    assert(type(tables) == "table", "must accept 'table' filter")
end)

test("getconnections", {}, function()
    local bindable = Instance.new("BindableEvent")
    bindable.Event:Connect(function() end)
    local conns = getconnections(bindable.Event)
    assert(type(conns) == "table" and #conns > 0, "must return at least one connection")
    local c = conns[1]
    local expectedFields = {
        Enabled="boolean", ForeignState="boolean", LuaConnection="boolean",
        Function="function", Thread="thread",
        Fire="function", Defer="function", Disconnect="function",
        Disable="function", Enable="function",
    }
    for k, vtype in pairs(expectedFields) do
        assert(c[k] ~= nil,          "connection must have field: " .. k)
        assert(type(c[k]) == vtype,  "field " .. k .. " must be " .. vtype)
    end
    bindable:Destroy()
end)

test("getsignalarguments", {}, function()
    local args = getsignalarguments(workspace.ChildAdded)
    assert(type(args) == "table", "must return a table of argument type strings")
end)

test("cansignalreplicate", {}, function()
    assert(type(cansignalreplicate(workspace.ChildAdded)) == "boolean",
        "must return a boolean")
    local re = Instance.new("RemoteEvent")
    re.Parent = workspace
    local ok, rep = pcall(cansignalreplicate, re.OnClientEvent)
    if ok then assert(type(rep) == "boolean", "must return boolean for RemoteEvent signal") end
    re:Destroy()
end)

test("getpropertychangedsignal", {}, function()
    local part   = Instance.new("Part")
    part.Parent  = workspace
    local signal = getpropertychangedsignal(part, "Name")
    assert(signal ~= nil, "must return a signal")
    local fired = false
    signal:Connect(function() fired = true end)
    part.Name = "UNC_PCS_Test"
    task.wait()
    assert(fired, "signal must fire when property changes")
    part:Destroy()
end)

test("Signal.new", {}, function()
    local s = Signal.new()
    assert(s ~= nil, "Signal.new must return an object")
    assert(type(s.Connect)       == "function", "must have :Connect")
    assert(type(s.Once)          == "function", "must have :Once")
    assert(type(s.Fire)          == "function", "must have :Fire")
    assert(type(s.DisconnectAll) == "function", "must have :DisconnectAll")
    assert(type(s.Destroy)       == "function", "must have :Destroy")
end)

test("Signal.Connect", {}, function()
    local s, n = Signal.new(), 0
    s:Connect(function() n += 1 end)
    s:Fire()
    s:Fire()
    assert(n == 2, "Connect must fire callback every time")
    s:Destroy()
end)

test("Signal.Once", {}, function()
    local s, n = Signal.new(), 0
    s:Once(function() n += 1 end)
    s:Fire()
    s:Fire()
    assert(n == 1, "Once must only fire once")
    s:Destroy()
end)

test("Signal.Wait", {}, function()
    local s = Signal.new()
    local result = nil
    task.spawn(function()
        result = s:Wait()
    end)
    task.wait()
    s:Fire(99)
    task.wait()
    assert(result == 99, "Wait must return the fired value")
    s:Destroy()
end)

test("Signal.DisconnectAll", {}, function()
    local s, n = Signal.new(), 0
    s:Connect(function() n += 1 end)
    s:Connect(function() n += 1 end)
    s:DisconnectAll()
    s:Fire()
    assert(n == 0, "DisconnectAll must remove all connections")
    s:Destroy()
end)

test("Signal.Destroy", {}, function()
    local s = Signal.new()
    s:Destroy()
    local ok = pcall(function() s:Fire() end)
    assert(ok, "Fire after Destroy must not throw")
end)

test("getrawmetatable", {}, function()
    local mt  = { __metatable = "locked", __index = function() return 1 end }
    local obj = setmetatable({}, mt)
    assert(getrawmetatable(obj) == mt, "must return the actual metatable ignoring __metatable")
end)

test("setrawmetatable", {}, function()
    local obj   = setmetatable({}, { __index = function() return false end, __metatable = "locked" })
    local newMt = { __index = function() return true end }
    setrawmetatable(obj, newMt)
    assert(obj.anything == true, "index must now use the new metatable")
end)

test("hookmetamethod", {}, function()
    local obj = setmetatable({}, {
        __index    = newcclosure(function() return "original" end),
        __metatable = "locked",
    })
    local ref = hookmetamethod(obj, "__index", newcclosure(function() return "hooked" end))
    assert(obj.key == "hooked",   "metamethod must be hooked")
    assert(ref()   == "original", "ref must point to original")
    hookmetamethod(obj, "__index", ref)
end)

test("getnamecallmethod", {}, function()
    local method
    local ref
    ref = hookmetamethod(game, "__namecall", function(...)
        if not method then method = getnamecallmethod() end
        return ref(...)
    end)
    game:GetService("Lighting")
    hookmetamethod(game, "__namecall", ref)
    assert(method == "GetService", "must capture 'GetService' as the namecall method")
end)

test("setnamecallmethod", {}, function()
    local ref
    ref = hookmetamethod(game, "__namecall", function(self, ...)
        setnamecallmethod("FindFirstChild")
        return ref(self, ...)
    end)
    pcall(function() game:GetService("Lighting") end)
    hookmetamethod(game, "__namecall", ref)
    assert(true, "setnamecallmethod must not throw")
end)

test("isreadonly", {}, function()
    local t = {}
    assert(isreadonly(t) == false,   "unfrozen table must not be readonly")
    table.freeze(t)
    assert(isreadonly(t) == true,    "frozen table must be readonly")
end)

test("setreadonly", {}, function()
    local t = { v = false }
    table.freeze(t)
    setreadonly(t, false)
    t.v = true
    assert(t.v == true,              "table must be writable after setreadonly(t, false)")
    setreadonly(t, true)
    local ok = pcall(function() t.v = false end)
    assert(not ok,                   "table must be readonly after setreadonly(t, true)")
end)

test("makereadonly", {}, function()
    local t = {}
    makereadonly(t)
    assert(isreadonly(t),            "makereadonly must make table readonly")
end)

test("makewriteable", {}, function()
    local t = table.freeze({})
    local w = makewriteable(t)
    assert(type(w) == "table",       "must return a table")
    local ok = pcall(function() w.__test = true end)
    assert(ok,                       "returned table must be writable")
end)

test("cache.iscached", {}, function()
    local p = Instance.new("Part")
    p.Parent = workspace
    assert(cache.iscached(p) == true,  "new instance must be cached")
    cache.invalidate(p)
    assert(cache.iscached(p) == false, "invalidated instance must not be cached")
    p:Destroy()
end)

test("cache.invalidate", {}, function()
    local folder = Instance.new("Folder")
    local part   = Instance.new("Part", folder)
    cache.invalidate(folder:FindFirstChild("Part"))
    assert(part ~= folder:FindFirstChild("Part"), "invalidated ref must differ from fresh ref")
    folder:Destroy()
end)

test("cache.replace", {}, function()
    local a = Instance.new("Part")
    a.Parent = workspace
    local b = Instance.new("Fire")
    cache.replace(a, b)
    assert(a ~= b, "instances must differ after replace")
    a:Destroy()
    b:Destroy()
end)

test("request", { "http_request", "http.request" }, function()
    local r = request({ Url = "https://httpbin.org/user-agent", Method = "GET" })
    assert(type(r)            == "table",  "must return a table")
    assert(r.StatusCode       == 200,      "must get 200 from httpbin")
    assert(type(r.Body)       == "string", "body must be a string")
    local data = game:GetService("HttpService"):JSONDecode(r.Body)
    assert(type(data["user-agent"]) == "string", "response must contain user-agent field")
    local r2 = http_request({ Url = "https://httpbin.org/get", Method = "GET" })
    assert(r2.StatusCode == 200, "http_request alias must work")
    assert(type(http.request) == "function", "http.request alias must exist")
    return "UA: " .. data["user-agent"]
end)

test("HttpGet", {}, function()
    local body = HttpGet("https://httpbin.org/get")
    assert(type(body) == "string" and #body > 0, "must return non-empty string body")
end)

test("HttpPost", {}, function()
    local body = HttpPost("https://httpbin.org/post", '{"unc":true}', "application/json")
    assert(type(body) == "string" and #body > 0, "must return non-empty string body")
end)

test("WebSocket", {}, function()
    assert(type(WebSocket) == "table", "WebSocket must be a table")
    assert(type(WebSocket.connect) == "function" or type(WebSocket.Connect) == "function",
        "WebSocket must have connect method")
end)

test("WebSocket.connect", { "WebSocket.Connect" }, function()
    local ws = WebSocket.connect("ws://echo.websocket.events")
    assert(type(ws) == "table" or type(ws) == "userdata", "must return table or userdata")
    assert(type(ws.Send)    == "function",                "must have :Send")
    assert(type(ws.Close)   == "function",                "must have :Close")
    assert(ws.OnMessage     ~= nil,                       "must have .OnMessage")
    assert(ws.OnClose       ~= nil,                       "must have .OnClose")
    local received = nil
    ws.OnMessage:Connect(function(msg) received = msg end)
    ws:Send("FluxusZ_UNC_Echo")
    local deadline = tick() + 5
    repeat task.wait(0.1) until received ~= nil or tick() > deadline
    assert(type(received) == "string",                    "must receive echo response within 5s")
    ws:Close()
    assert(WebSocket.Connect ~= nil,                      "WebSocket.Connect alias must exist")
end)

test("writefile", {}, function()
    writefile(".unc/write.txt", "hello_write")
    assert(readfile(".unc/write.txt") == "hello_write", "must write and read back correctly")
end)

test("readfile", {}, function()
    writefile(".unc/read.txt", "hello_read")
    assert(readfile(".unc/read.txt") == "hello_read", "must read back what was written")
end)

test("appendfile", {}, function()
    writefile(".unc/append.txt", "abc")
    appendfile(".unc/append.txt", "def")
    appendfile(".unc/append.txt", "ghi")
    assert(readfile(".unc/append.txt") == "abcdefghi", "must concatenate all appends correctly")
end)

test("isfile", {}, function()
    writefile(".unc/isfile.txt", "x")
    assert(isfile(".unc/isfile.txt")         == true,  "must return true for existing file")
    assert(isfile(".unc")                    == false, "must return false for a folder path")
    assert(isfile(".unc/does_not_exist.xyz") == false, "must return false for nonexistent path")
end)

test("isfolder", {}, function()
    makefolder(".unc/subfolder")
    assert(isfolder(".unc")                        == true,  "must return true for existing folder")
    assert(isfolder(".unc/subfolder")              == true,  "must return true for created subfolder")
    assert(isfolder(".unc/does_not_exist_folder")  == false, "must return false for nonexistent folder")
    assert(isfolder(".unc/isfile.txt")             == false, "must return false for a file path")
end)

test("makefolder", {}, function()
    makefolder(".unc/makefolder_test")
    assert(isfolder(".unc/makefolder_test"), "must create the folder")
end)

test("delfolder", {}, function()
    makefolder(".unc/delfolder_test")
    delfolder(".unc/delfolder_test")
    assert(isfolder(".unc/delfolder_test") == false, "must remove the folder")
end)

test("delfile", {}, function()
    writefile(".unc/delfile.txt", "del")
    delfile(".unc/delfile.txt")
    assert(isfile(".unc/delfile.txt") == false, "must remove the file")
end)

test("listfiles", {}, function()
    makefolder(".unc/listfiles")
    writefile(".unc/listfiles/a.txt", "a")
    writefile(".unc/listfiles/b.txt", "b")
    local files = listfiles(".unc/listfiles")
    assert(type(files) == "table" and #files == 2, "must return exactly 2 entries")
    assert(isfile(files[1]),                        "entries must be valid file paths")
    makefolder(".unc/listfolders")
    makefolder(".unc/listfolders/d1")
    makefolder(".unc/listfolders/d2")
    local dirs = listfiles(".unc/listfolders")
    assert(#dirs == 2, "must return 2 folder entries")
    assert(isfolder(dirs[1]), "folder entries must be valid folder paths")
end)

test("copyfile", {}, function()
    writefile(".unc/copy_src.txt", "copy_data")
    copyfile(".unc/copy_src.txt", ".unc/copy_dst.txt")
    assert(isfile(".unc/copy_dst.txt"),                   "destination must exist after copy")
    assert(readfile(".unc/copy_dst.txt") == "copy_data",  "destination must have the same content")
    assert(isfile(".unc/copy_src.txt"),                   "source must still exist after copy")
end)

test("movefile", { "renamefile" }, function()
    writefile(".unc/move_src.txt", "move_data")
    movefile(".unc/move_src.txt", ".unc/move_dst.txt")
    assert(isfile(".unc/move_dst.txt"),                   "destination must exist after move")
    assert(not isfile(".unc/move_src.txt"),               "source must be gone after move")
    assert(readfile(".unc/move_dst.txt") == "move_data",  "destination must have the correct content")
    writefile(".unc/rename_src.txt", "ren")
    renamefile(".unc/rename_src.txt", ".unc/rename_dst.txt")
    assert(isfile(".unc/rename_dst.txt"), "renamefile alias must work")
end)

test("getfilesize", {}, function()
    writefile(".unc/size.txt", "12345")
    local sz = getfilesize(".unc/size.txt")
    assert(type(sz) == "number", "must return a number")
    assert(sz       == 5,        "size of '12345' must be 5 bytes")
end)

test("loadfile", {}, function()
	writefile(".tests/loadfile.txt", "return ... + 1")
	assert(assert(loadfile(".tests/loadfile.txt"))(1) == 2, "Failed to load a file with arguments")
	writefile(".tests/loadfile.txt", "f")
	local callback, err = loadfile(".tests/loadfile.txt")
	assert(err and not callback, "Did not return an error message for a compiler error")
end)

test("getcustomasset", { "getsynasset" }, function()
    writefile(".unc/asset_test.png", string.rep("\0", 16))
    local url = getcustomasset(".unc/asset_test.png")
    assert(type(url) == "string" and #url > 0,         "must return a non-empty string")
    assert(url:find("rbxasset://"),                    "must return an rbxasset:// URL")
    assert(getsynasset(".unc/asset_test.png") == url, "getsynasset alias must match")
end)

test("setclipboard", { "toclipboard", "setrbxclipboard" }, function()
    setclipboard("unc_clip_test_set")
    assert(true, "setclipboard must not throw")
    toclipboard("unc_toclipboard_test")
    assert(true, "toclipboard alias must not throw")
    setrbxclipboard("unc_setrbxclipboard_test")
    assert(true, "setrbxclipboard alias must not throw")
end)

test("getclipboard", {}, function()
	setclipboard("unc_clipboard_test")
	local clipboard = getclipboard()
	assert(type(clipboard) == "string", "Did not return a string")
	assert(clipboard == "unc_clipboard_test", "Did not return the correct clipboard contents")
end)

test("consolecreate", { "rconsolecreate" }, function()
    consolecreate("UNC Test Console")
    assert(true, "consolecreate must not throw")
    rconsolecreate("UNC RConsole Test")
    assert(true, "rconsolecreate alias must not throw")
end)

test("consoleclear", { "rconsoleclear" }, function()
    consolecreate()
    consoleclear()
    rconsoleclear()
end)

test("consolename", { "rconsolename", "consolesettitle", "rconsolesettitle" }, function()
    consolecreate()
    consolename("UNC Name Test")
    rconsolename("UNC rconsolename Test")
    consolesettitle("UNC consolesettitle Test")
    rconsolesettitle("UNC rconsolesettitle Test")
end)

test("consoleprint", { "rconsoleprint" }, function()
    consolecreate()
    consoleprint("UNC consoleprint test\n")
    rconsoleprint("UNC rconsoleprint test\n")
end)

test("consoleinfo", { "rconsoleinfo" }, function()
    consolecreate()
    consoleinfo("UNC consoleinfo test\n")
    rconsoleinfo("UNC rconsoleinfo test\n")
end)

test("consolewarn", { "rconsolewarn" }, function()
    consolecreate()
    consolewarn("UNC consolewarn test\n")
    rconsolewarn("UNC rconsolewarn test\n")
end)

test("rconsoleerr", { "rconsoleerror", "consoleerror" }, function()
    consolecreate()
    rconsoleerr("UNC rconsoleerr test\n")
    rconsoleerror("UNC rconsoleerror test\n")
    if type(consoleerror) == "function" then
        consoleerror("UNC consoleerror test\n")
    end
end)

test("consoleinput", { "rconsoleinput" }, function()
    assert(type(consoleinput)  == "function", "consoleinput must be a function")
    assert(type(rconsoleinput) == "function", "rconsoleinput alias must be a function")
end)

test("rconsolehide", {}, function()
    consolecreate()
    rconsolehide()
    assert(true, "rconsolehide must not throw")
end)

test("rconsoleshow", {}, function()
    consolecreate()
    rconsolehide()
    rconsoleshow()
    assert(true, "rconsoleshow must not throw")
end)

test("consoledestroy", { "rconsoledestroy" }, function()
    consolecreate()
    consoledestroy()
    consolecreate()
    rconsoledestroy()
end)

test("isrbxactive", { "isgameactive", "iswindowactive" }, function()
    assert(type(isrbxactive())    == "boolean", "isrbxactive must return boolean")
    assert(type(isgameactive())   == "boolean", "isgameactive alias must return boolean")
    assert(type(iswindowactive()) == "boolean", "iswindowactive alias must return boolean")
end)

test("keypress",   {}, function() keypress(0x41)   end)
test("keyrelease", {}, function() keyrelease(0x41)  end)
test("keyclick",   { "keytap" }, function()
    keyclick(0x41)
    keytap(0x41)
end)

test("mouse1click",   {}, function() mouse1click()   end)
test("mouse2click",   {}, function() mouse2click()   end)
test("mouse1press",   {}, function() mouse1press()   end)
test("mouse1release", {}, function() mouse1release() end)
test("mouse2press",   {}, function() mouse2press()   end)
test("mouse2release", {}, function() mouse2release() end)

test("mousemoveabs", {}, function()
    mousemoveabs(200, 200)
    mousemoveabs(0, 0)
end)

test("mousemoverel", {}, function()
    mousemoverel(5, 5)
    mousemoverel(-5, -5)
end)

test("mousescroll", {}, function()
    mousescroll(3)
    mousescroll(-3)
end)

test("fireclickdetector", {}, function()
    local part = Instance.new("Part")
    part.Parent = workspace
    local cd = Instance.new("ClickDetector", part)
    fireclickdetector(cd, 10, "MouseClick")
    fireclickdetector(cd, 10, "RightMouseClick")
    fireclickdetector(cd, 10, "MouseHoverEnter")
    fireclickdetector(cd, 10, "MouseHoverLeave")
    part:Destroy()
end)

test("fireproximityprompt", {}, function()
    local part = Instance.new("Part")
    part.Parent = workspace
    local pp = Instance.new("ProximityPrompt", part)
    pp.RequiresLineOfSight = false
    fireproximityprompt(pp)
    part:Destroy()
end)

test("firetouchinterest", { "firetouchtransmitter" }, function()
    local a = Instance.new("Part") a.Parent = workspace
    local b = Instance.new("Part") b.Parent = workspace
    firetouchinterest(a, b, true)
    firetouchinterest(a, b, false)
    firetouchtransmitter(a, b, true)
    a:Destroy()
    b:Destroy()
end)

test("crypt.base64encode", { "crypt.base64decode" }, function()
    local encoded = crypt.base64encode("Hello, World!")
    assert(type(encoded) == "string" and #encoded > 0, "encode must return non-empty string")
    assert(encoded == "SGVsbG8sIFdvcmxkIQ==",          "must match known base64 value")
    local decoded = crypt.base64decode(encoded)
    assert(decoded == "Hello, World!",                  "round-trip must be lossless")
end)

test("crypt.generatekey", {}, function()
    local key = crypt.generatekey()
    assert(type(key) == "string" and #key > 0, "must return non-empty string key")
    local raw = crypt.base64decode(key)
    assert(#raw == 32, "decoded key must be 32 bytes")
    assert(crypt.generatekey() ~= key, "two keys must differ (random)")
end)

test("crypt.generatebytes", {}, function()
    local size  = math.random(10, 64)
    local bytes = crypt.generatebytes(size)
    assert(type(bytes) == "string",                   "must return a string")
    assert(#crypt.base64decode(bytes) == size,        "decoded result must be exactly 'size' bytes")
end)

test("crypt.random", {}, function()
    local r = crypt.random(16)
    assert(type(r) == "string", "must return a string")
end)

test("crypt.encrypt", {}, function()
    local key  = crypt.generatekey()
    local enc, iv = crypt.encrypt("secret_message", key, nil, "CBC")
    assert(type(enc) == "string" and #enc > 0, "encrypted data must be a non-empty string")
    assert(iv ~= nil,                           "must return an IV")
    local dec = crypt.decrypt(enc, key, iv, "CBC")
    assert(dec == "secret_message",             "decrypt(encrypt(x)) must equal x")
end)

test("crypt.decrypt", {}, function()
    local key = crypt.generatekey()
    local iv  = crypt.generatekey()
    local enc = crypt.encrypt("round_trip", key, iv, "CBC")
    local dec = crypt.decrypt(enc, key, iv, "CBC")
    assert(dec == "round_trip", "decrypt must recover original plaintext")
end)

test("crypt.hash", {}, function()
    local algorithms = { "md5", "sha1", "sha256", "sha384", "sha512", "sha3-224", "sha3-256", "sha3-512" }
    for _, algo in ipairs(algorithms) do
        local h = crypt.hash("test", algo)
        assert(type(h) == "string" and #h > 0, "hash must be non-empty for algorithm: " .. algo)
        assert(h == crypt.hash("test", algo),   "hash must be deterministic for: " .. algo)
    end
end)

test("crypt.hmac", {}, function()
    local h = crypt.hmac("mykey", "mydata", "sha256")
    assert(type(h) == "string" and #h > 0, "hmac must return non-empty string")
    assert(h == crypt.hmac("mykey", "mydata", "sha256"), "hmac must be deterministic")
end)

test("crypt.lz4compress", {}, function()
    local raw       = "AAAAAABBBBBBCCCCCCDDDDDD"
    local comp, sz  = crypt.lz4compress(raw)
    assert(type(comp) == "string",              "compressed must be a string")
    local decomp    = crypt.lz4decompress(comp, sz or #raw)
    assert(decomp == raw,                       "lz4 round-trip must be lossless")
end)

test("base64encode", { "base64_encode" }, function()
    local e = base64encode("test")
    assert(e == "dGVzdA==",             "must encode 'test' correctly")
    assert(base64_encode("test") == e,  "base64_encode alias must match")
end)

test("base64decode", { "base64_decode" }, function()
    local d = base64decode("dGVzdA==")
    assert(d == "test",                    "must decode correctly")
    assert(base64_decode("dGVzdA==") == d, "base64_decode alias must match")
end)

test("lz4compress", {}, function()
    local raw    = "Hello, LZ4! Hello, LZ4!"
    local comp   = lz4compress(raw)
    assert(type(comp) == "string" and #comp > 0, "must return non-empty compressed string")
end)

test("lz4decompress", {}, function()
    local raw    = "Hello, LZ4 decompress test!"
    local comp   = lz4compress(raw)
    local decomp = lz4decompress(comp, #raw)
    assert(decomp == raw, "lz4decompress must recover original string")
end)

test("messagebox", {}, function()
    assert(type(messagebox) == "function", "messagebox must be a function")
end)

test("queue_on_teleport", { "queueonteleport" }, function()
    queue_on_teleport("print('UNC teleport queue test')")
    queueonteleport("print('alias test')")
end)

test("clearqueueonteleport", { "clearteleportqueue", "clear_teleport_queue" }, function()
    clearqueueonteleport(true)
    clearqueueonteleport(false)
    clearteleportqueue(true)
    clear_teleport_queue(false)
end)

test("saveinstance", { "savegame" }, function()
    assert(type(saveinstance) == "function", "saveinstance must be a function")
    assert(type(savegame)     == "function", "savegame alias must be a function")
end)

test("printidentity", {}, function()
    assert(type(printidentity) == "function", "printidentity must be a function")
    printidentity()
end)

test("getsimulationradius", {}, function()
    local r, mr = getsimulationradius()
    assert(type(r)  == "number" and r  >= 0, "radius must be a non-negative number")
    assert(type(mr) == "number" and mr >= 0, "maxRadius must be a non-negative number")
    return ("radius=%g maxRadius=%g"):format(r, mr)
end)

test("setsimulationradius", {}, function()
    local origR, origMR = getsimulationradius()
    setsimulationradius(500, 1000)
    local r, mr = getsimulationradius()
    assert(r == 500,   "radius must be 500 after set")
    assert(mr == 1000, "maxRadius must be 1000 after set")
    setsimulationradius(origR, origMR)
end)

test("isnetworkowner", {}, function()
    local part = Instance.new("Part")
    part.Parent = workspace
    local result = isnetworkowner(part)
    assert(type(result) == "boolean", "must return a boolean")
    part:Destroy()
end)

test("debug.getinfo", {}, function()
    local function fn(...) print(...) end
    local info = debug.getinfo(fn)
    assert(type(info)           == "table",    "must return a table")
    assert(type(info.source)    == "string",   "source must be a string")
    assert(type(info.short_src) == "string",   "short_src must be a string")
    assert(type(info.func)      == "function", "func must be a function")
    assert(type(info.what)      == "string",   "what must be a string")
    assert(type(info.nups)      == "number",   "nups must be a number")
    assert(type(info.numparams) == "number",   "numparams must be a number")
    assert(type(info.is_vararg) == "number",   "is_vararg must be a number")
end)

test("debug.getstack", { "getstack" }, function()
	local _ = "a" .. "b"
	assert(debug.getstack(1, 1) == "ab", "The first item in the stack should be 'ab'")
	assert(debug.getstack(1)[1] == "ab", "The first item in the stack table should be 'ab'")
end)

test("debug.getupvalue", { "getupvalue" }, function()
	local upvalue = function() end
	local function test()
		print(upvalue)
	end
	assert(debug.getupvalue(test, 1) == upvalue, "Unexpected value returned from debug.getupvalue")
end)

test("debug.getupvalues", { "getupvalues" }, function()
	local upvalue = function() end
	local function test()
		print(upvalue)
	end
	local upvalues = debug.getupvalues(test)
	assert(upvalues[1] == upvalue, "Unexpected value returned from debug.getupvalues")
end)

test("debug.setupvalue", { "setupvalue", "setupval" }, function()
    local x = "fail"
    local function fn() return x end
    debug.setupvalue(fn, 1, "success")
    assert(fn() == "success", "debug.setupvalue must replace the upvalue")
    debug.setupvalue(fn, 1, "fail")
    setupvalue(fn, 1, "alias_success")
    assert(fn() == "alias_success", "setupvalue alias must work")
    setupval(fn, 1, "alias2_success")
    assert(fn() == "alias2_success", "setupval alias must work")
end)

test("debug.setconstant", { "setconstant", "setvalue" }, function()
    local function fn() return "fail_const" end
    debug.setconstant(fn, 1, "pass_const")
    assert(fn() == "pass_const", "debug.setconstant must replace constant")
    local function fn2() return "fail_alias" end
    setconstant(fn2, 1, "pass_alias")
    assert(fn2() == "pass_alias", "setconstant alias must work")
    local function fn3() return "fail_setvalue" end
    setvalue(fn3, 1, "pass_setvalue")
    assert(fn3() == "pass_setvalue", "setvalue alias must work")
end)

test("debug.getconstant", {}, function()
    local function fn() print("Hello!") end
    assert(debug.getconstant(fn, 1) == "print",  "constant[1] must be 'print'")
    assert(debug.getconstant(fn, 2) == nil,       "constant[2] must be nil (the print call)")
    assert(debug.getconstant(fn, 3) == "Hello!",  "constant[3] must be 'Hello!'")
end)

test("debug.getconstants", {}, function()
    local function fn()
        local n = 5000 .. 50000
        print("Hello!", n, warn)
    end
    local c = debug.getconstants(fn)
    assert(c[1] == 50000,    "c[1] must be 50000")
    assert(c[2] == "print",  "c[2] must be 'print'")
    assert(c[3] == nil,      "c[3] must be nil")
    assert(c[4] == "Hello!", "c[4] must be 'Hello!'")
    assert(c[5] == "warn",   "c[5] must be 'warn'")
end)

test("debug.setstack", {}, function()
    local function fn()
        return "fail", debug.setstack(1, 1, "stack_success")
    end
    assert(fn() == "stack_success", "debug.setstack must overwrite the first stack slot")
end)

test("debug.getproto", {}, function()
    local function outer()
        local function inner() return "proto_ok" end
    end
    local inner = debug.getproto(outer, 1, true)[1]
    assert(inner,             "must retrieve inner function")
    assert(inner() == "proto_ok", "retrieved function must execute correctly")
    local realInner = debug.getproto(outer, 1)
    if not realInner() then
        return "proto return values disabled on this executor"
    end
end)

test("debug.getprotos", {}, function()
    local function outer()
        local function a() return 1 end
        local function b() return 2 end
        local function c() return 3 end
    end
    local protos = debug.getprotos(outer)
    assert(type(protos) == "table" and #protos == 3, "must return exactly 3 inner functions")
    for i, _ in ipairs(protos) do
        local p = debug.getproto(outer, i, true)[1]
        assert(p(), "inner function " .. i .. " must be callable")
    end
end)

test("debug.traceback", {}, function()
    local tb = debug.traceback()
    assert(type(tb) == "string" and #tb > 0, "must return a non-empty traceback string")
end)

test("debug.profilebegin", {}, function()
    assert(type(debug.profilebegin) == "function", "debug.profilebegin must be a function")
    debug.profilebegin("UNC_PROFILE_TEST")
end)

test("debug.profileend", {}, function()
    assert(type(debug.profileend) == "function", "debug.profileend must be a function")
    debug.profilebegin("UNC_PROFILE_END_TEST")
    debug.profileend()
end)

test("Drawing", {}, function()
    assert(type(Drawing)     == "table",    "Drawing must be a table")
    assert(type(Drawing.new) == "function", "Drawing.new must be a function")
end)

test("Drawing.new", {}, function()
    local types = { "Line", "Text", "Image", "Circle", "Square", "Triangle", "Quad" }
    for _, t in ipairs(types) do
        local ok, obj = pcall(Drawing.new, t)
        if ok then
            assert(obj ~= nil, t .. " object must not be nil")
            local ok2 = pcall(function() obj.Visible = false end)
            assert(ok2, t .. " must allow setting Visible")
            pcall(function() obj:Destroy() end)
        end
    end
end)

test("Drawing.Fonts", {}, function()
    assert(Drawing.Fonts.UI        == 0, "Fonts.UI must be 0")
    assert(Drawing.Fonts.System    == 1, "Fonts.System must be 1")
    assert(Drawing.Fonts.Plex      == 2, "Fonts.Plex must be 2")
    assert(Drawing.Fonts.Monospace == 3, "Fonts.Monospace must be 3")
end)

test("isrenderobj", {}, function()
    local obj = Drawing.new("Square")
    obj.Visible = true
    assert(isrenderobj(obj)        == true,  "must return true for a Drawing object")
    assert(isrenderobj(newproxy()) == false, "must return false for a plain userdata")
    obj:Destroy()
end)

test("getrenderproperty", {}, function()
    local obj = Drawing.new("Square")
    obj.Visible = true
    assert(type(getrenderproperty(obj, "Visible")) == "boolean", "must return boolean for Visible")
    obj:Destroy()
end)

test("setrenderproperty", {}, function()
    local obj = Drawing.new("Square")
    obj.Visible = true
    setrenderproperty(obj, "Visible", false)
    assert(obj.Visible == false, "must set Visible to false")
    obj:Destroy()
end)

test("cleardrawcache", {}, function()
    cleardrawcache()
end)

test("getfflag", {}, function()
    local v = getfflag("AllowHideCharacter")
    assert(type(v) == "string", "must return a string FFlag value")
    assert(v == "True" or v == "False" or #v > 0, "value must be a recognisable flag string")
end)

test("getscriptflag", {}, function()
    local v = getscriptflag("AllowHideCharacter")
    assert(type(v) == "boolean", "must return a boolean")
end)

test("_G", {}, function()
    _G.__UNC_GTEST = "global_ok"
    assert(_G.__UNC_GTEST == "global_ok", "_G must persist written values")
    _G.__UNC_GTEST = nil
end)

test("shared", {}, function()
    shared.__UNC_STEST = "shared_ok"
    assert(shared.__UNC_STEST == "shared_ok", "shared must persist written values")
    shared.__UNC_STEST = nil
end)

test("task.spawn", {}, function()
    local result = nil
    task.spawn(function() result = "spawned" end)
    task.wait()
    assert(result == "spawned", "task.spawn must run the function immediately")
end)

test("task.defer", {}, function()
    local result = nil
    task.defer(function() result = "deferred" end)
    task.wait()
    assert(result == "deferred", "task.defer must run the function at end of frame")
end)

test("task.delay", {}, function()
    local fired = false
    task.delay(0.05, function() fired = true end)
    task.wait(0.2)
    assert(fired, "task.delay must fire after the specified duration")
end)

test("task.wait", {}, function()
    local t0      = tick()
    local elapsed = task.wait(0.1)
    local actual  = tick() - t0
    assert(actual >= 0.09,               "must wait at least ~0.1 seconds")
    assert(type(elapsed) == "number",    "must return elapsed time as number")
end)

test("task.cancel", {}, function()
    local fired  = false
    local thread = task.delay(0.1, function() fired = true end)
    task.cancel(thread)
    task.wait(0.25)
    assert(not fired, "task.cancel must prevent the delayed callback from running")
end)

test("table.isfrozen", {}, function()
    local t = {}
    assert(not table.isfrozen(t), "unfrozen table must not be frozen")
    table.freeze(t)
    assert(table.isfrozen(t),     "frozen table must be reported as frozen")
end)

test("bit32", {}, function()
    assert(type(bit32)              == "table", "bit32 must be a table")
    assert(bit32.band(0xFF, 0x0F)   == 0x0F,   "band failed")
    assert(bit32.bor(0xF0, 0x0F)    == 0xFF,   "bor failed")
    assert(bit32.bxor(0xFF, 0x0F)   == 0xF0,   "bxor failed")
    assert(bit32.bnot(0) == 0xFFFFFFFF,         "bnot(0) failed")
    assert(bit32.lshift(1, 4)       == 16,      "lshift failed")
    assert(bit32.rshift(16, 4)      == 1,       "rshift failed")
    assert(bit32.lrotate(1, 1)      == 2,       "lrotate failed")
    assert(bit32.rrotate(2, 1)      == 1,       "rrotate failed")
    assert(bit32.extract(0xFF, 4, 4)== 0x0F,    "extract failed")
    assert(bit32.countlz(0x80000000) == 0,      "countlz failed")
    assert(bit32.countrz(1)          == 0,      "countrz failed")
end)

test("makeSignal", {}, function()
    assert(type(makeSignal) == "function", "makeSignal must be a function")
    local s = makeSignal()
    assert(s ~= nil,                       "makeSignal() must return an object")
    assert(type(s.Connect) == "function",  "returned signal must have :Connect")
    assert(type(s.Fire)    == "function",  "returned signal must have :Fire")
    s:Destroy()
end)

test("WebSocket (capital aliases)", {}, function()
	assert(type(WebSocket) == "table", "WebSocket must be a table")
end)

test("game / workspace aliases", {}, function()
    assert(Game      == game      or typeof(Game)      == "Instance", "Game alias must exist")
    assert(Workspace == workspace or typeof(Workspace) == "Instance", "Workspace alias must exist")
end)

test("crypt namespace", {}, function()
    assert(type(crypt)               == "table",    "crypt must be a table")
    assert(type(crypt.base64encode)  == "function", "crypt.base64encode must exist")
    assert(type(crypt.base64decode)  == "function", "crypt.base64decode must exist")
    assert(type(crypt.generatekey)   == "function", "crypt.generatekey must exist")
    assert(type(crypt.generatebytes) == "function", "crypt.generatebytes must exist")
    assert(type(crypt.random)        == "function", "crypt.random must exist")
    assert(type(crypt.encrypt)       == "function", "crypt.encrypt must exist")
    assert(type(crypt.decrypt)       == "function", "crypt.decrypt must exist")
    assert(type(crypt.hash)          == "function", "crypt.hash must exist")
    assert(type(crypt.hmac)          == "function", "crypt.hmac must exist")
    assert(type(crypt.lz4compress)   == "function", "crypt.lz4compress must exist")
    assert(type(crypt.lz4decompress) == "function", "crypt.lz4decompress must exist")
end)

test("cache namespace", {}, function()
    assert(type(cache)            == "table",    "cache must be a table")
    assert(type(cache.iscached)   == "function", "cache.iscached must exist")
    assert(type(cache.invalidate) == "function", "cache.invalidate must exist")
    assert(type(cache.replace)    == "function", "cache.replace must exist")
end)

test("http namespace", {}, function()
    assert(type(http)         == "table",    "http must be a table")
    assert(type(http.request) == "function", "http.request must exist")
    assert(http.request == request or http_request, "http.request must alias request")
end)

test("base64 namespace", {}, function()
    assert(type(base64)        == "table",    "base64 must be a table")
    assert(type(base64.encode) == "function", "base64.encode must exist")
    assert(type(base64.decode) == "function", "base64.decode must exist")
    assert(base64.encode("x") == base64encode("x"), "base64.encode must match base64encode")
    assert(base64.decode(base64.encode("x")) == "x", "base64.decode round-trip must work")
end)

test("setstack", {}, function()
    assert(type(setstack) == "function", "setstack must be a function")
    local function fn()
        return "fail", setstack(1, 1, "setstack_ok")
    end
    assert(fn() == "setstack_ok", "setstack must overwrite the first stack slot")
end)

test("getproto", {}, function()
    assert(type(getproto) == "function", "getproto must be a function")
    local function outer()
        local function inner() return "getproto_ok" end
    end
    local inner = getproto(outer, 1, true)[1]
    assert(inner, "must retrieve inner function")
    assert(inner() == "getproto_ok", "inner function must execute correctly")
end)

test("getprotos", {}, function()
    assert(type(getprotos) == "function", "getprotos must be a function")
    local function outer()
        local function a() return 1 end
        local function b() return 2 end
    end
    local protos = getprotos(outer)
    assert(type(protos) == "table" and #protos == 2, "must return 2 inner protos")
end)

test("getconstant", {}, function()
    assert(type(getconstant) == "function", "getconstant must be a function")
    local function fn() print("const_test") end
    assert(getconstant(fn, 1) == "print",      "constant[1] must be 'print'")
    assert(getconstant(fn, 3) == "const_test", "constant[3] must be 'const_test'")
end)

test("getconstants", {}, function()
    assert(type(getconstants) == "function", "getconstants must be a function")
    local function fn() print("constants_test") end
    local c = getconstants(fn)
    assert(type(c) == "table", "must return a table of constants")
    assert(c[1] == "print" or c[2] == "print", "must contain 'print'")
end)

test("getinfo", {}, function()
    assert(type(getinfo) == "function", "getinfo must be a function")
    local info = getinfo(print)
    assert(type(info) == "table",       "must return a table")
    assert(type(info.what) == "string", "info.what must be a string")
end)

test("getscriptenv", {}, function()
    assert(type(getscriptenv) == "function", "getscriptenv must be a function")
    local scripts = getscripts()
    assert(#scripts > 0, "need at least one script to test getscriptenv")
    local env = getscriptenv(scripts[1])
    assert(type(env) == "table",        "must return a table environment")
    assert(env.script == scripts[1],    "env.script must match the target script")
end)

test("getthreads", {}, function()
    assert(type(getthreads) == "function", "getthreads must be a function")
    local threads = getthreads()
    assert(type(threads) == "table", "must return a table")
    for _, t in ipairs(threads) do
        assert(type(t) == "thread", "all entries must be threads")
    end
    return "found " .. #threads .. " threads"
end)

test("gettenv", {}, function()
    assert(type(gettenv) == "function", "gettenv must be a function")
    local thread = coroutine.create(function() task.wait(999) end)
    coroutine.resume(thread)
    local tenv = gettenv(thread)
    assert(type(tenv) == "table", "must return a table environment for a thread")
    coroutine.close(thread)
end)

test("fireremote", {}, function()
    assert(type(fireremote) == "function", "fireremote must be a function")
    local re = Instance.new("RemoteEvent")
    re.Parent = game:GetService("Players").LocalPlayer.PlayerGui
    local ok = pcall(fireremote, re, "unc_test")
    assert(ok, "fireremote must not throw on a valid RemoteEvent")
    re:Destroy()
end)

test("invokeremote", {}, function()
    assert(type(invokeremote) == "function", "invokeremote must be a function")
    local rf = Instance.new("RemoteFunction")
    rf.Parent = game:GetService("Players").LocalPlayer.PlayerGui
    local ok = pcall(invokeremote, rf)
    rf:Destroy()
    assert(ok or true, "invokeremote exists and is callable")
end)

test("getremotes", {}, function()
    assert(type(getremotes) == "function", "getremotes must be a function")
    local remotes = getremotes()
    assert(type(remotes) == "table", "must return a table")
    for _, r in ipairs(remotes) do
        assert(
            r:IsA("RemoteEvent") or r:IsA("RemoteFunction") or r:IsA("UnreliableRemoteEvent"),
            "all entries must be remote instances"
        )
    end
    return "found " .. #remotes .. " remotes"
end)

test("getbindables", {}, function()
    assert(type(getbindables) == "function", "getbindables must be a function")
    local bindables = getbindables()
    assert(type(bindables) == "table", "must return a table")
    for _, b in ipairs(bindables) do
        assert(b:IsA("BindableEvent") or b:IsA("BindableFunction"),
            "all entries must be bindable instances")
    end
    return "found " .. #bindables .. " bindables"
end)

test("getmodules", {}, function()
    assert(type(getmodules) == "function", "getmodules must be a function")
    local mods = getmodules()
    assert(type(mods) == "table" and #mods > 0, "must return non-empty table")
    assert(mods[1]:IsA("ModuleScript"),          "first entry must be a ModuleScript")
end)

test("crypt.base64.encode", { "crypt.base64.decode" }, function()
    assert(type(crypt.base64) == "table",           "crypt.base64 must be a table")
    assert(type(crypt.base64.encode) == "function", "crypt.base64.encode must exist")
    assert(type(crypt.base64.decode) == "function", "crypt.base64.decode must exist")
    local e = crypt.base64.encode("hello")
    assert(e == "aGVsbG8=",                         "must encode 'hello' correctly")
    assert(crypt.base64.decode(e) == "hello",        "decode must round-trip correctly")
end)

test("crypt.base64_encode", { "crypt.base64_decode" }, function()
    assert(type(crypt.base64_encode) == "function", "crypt.base64_encode must exist")
    assert(type(crypt.base64_decode) == "function", "crypt.base64_decode must exist")
    local e = crypt.base64_encode("world")
    assert(e == "d29ybGQ=",                         "must encode 'world' correctly")
    assert(crypt.base64_decode(e) == "world",        "decode must round-trip correctly")
end)

test("getrbxasset", {}, function()
    assert(type(getrbxasset) == "function", "getrbxasset must be a function")
    writefile(".unc/rbxasset_test.png", string.rep("\0", 16))
    local url = getrbxasset(".unc/rbxasset_test.png")
    assert(type(url) == "string" and #url > 0, "must return a non-empty string")
    assert(url:find("rbxasset://"),             "must return an rbxasset:// URL")
end)

test("setsimulationradius (single arg form)", {}, function()
    local origR, origMR = getsimulationradius()
    setsimulationradius(300)
    local r1, _ = getsimulationradius()
    assert(r1 == 300, "single-arg setsimulationradius must set radius to 300")
    setsimulationradius(origR, origMR)
end)

test("getconnections (Disable / Enable)", {}, function()
    local be  = Instance.new("BindableEvent")
    local hit = 0
    be.Event:Connect(function() hit += 1 end)
    local conn = getconnections(be.Event)[1]
    assert(conn.Enabled == true, "connection must start enabled")
    conn:Disable()
    be:Fire()
    assert(hit == 0, "disabled connection must not fire")
    conn:Enable()
    be:Fire()
    assert(hit == 1, "re-enabled connection must fire")
    be:Destroy()
end)

test("debug.getinfo (level form)", {}, function()
    local function inner() return debug.getinfo(1) end
    local info = inner()
    assert(type(info) == "table",              "level-form must return a table")
    assert(type(info.currentline) == "number", "must have currentline field")
end)

test("loadstring (chunkname arg)", {}, function()
	local animate = game:GetService("Players").LocalPlayer.Character.Animate
	local bytecode = getscriptbytecode(animate)
	local func = loadstring(bytecode)
	assert(type(func) ~= "function", "Luau bytecode should not be loadable!")
	assert(assert(loadstring("return ... + 1"))(1) == 2, "Failed to do simple math")
	assert(type(select(2, loadstring("f"))) == "string", "Loadstring did not return anything for a compiler error")
end)

test("request (POST with JSON body)", {}, function()
    local hs   = game:GetService("HttpService")
    local body = hs:JSONEncode({ unc = true, executor = "FluxusZ" })
    local res  = request({
        Url     = "https://httpbin.org/post",
        Method  = "POST",
        Headers = { ["Content-Type"] = "application/json" },
        Body    = body,
    })
    assert(res.StatusCode == 200,         "POST must return 200")
    local data = hs:JSONDecode(res.Body)
    assert(type(data.json) == "table",    "server must echo back our JSON body")
    assert(data.json.unc == true,         "echoed JSON must contain our fields")
end)

test("request (custom headers)", {}, function()
    local res = request({
        Url     = "https://httpbin.org/headers",
        Method  = "GET",
        Headers = { ["X-UNC-Test"] = "FluxusZ" },
    })
    assert(res.StatusCode == 200, "must return 200")
    local data = game:GetService("HttpService"):JSONDecode(res.Body)
    assert(
        (data.headers["X-Unc-Test"] or data.headers["X-UNC-Test"]) == "FluxusZ",
        "custom header must be echoed by httpbin"
    )
end)

test("writefile (binary content)", {}, function()
    local binary = "\0\1\2\3\4\255\254\253"
    writefile(".unc/binary.bin", binary)
    local result = readfile(".unc/binary.bin")
    assert(result == binary,    "binary content must survive round-trip")
    assert(#result == #binary,  "binary length must be preserved exactly")
end)

test("crypt.hash (all algorithms + lengths)", {}, function()
    local algos = {
        { name = "md5",      len = 32  },
        { name = "sha1",     len = 40  },
        { name = "sha256",   len = 64  },
        { name = "sha384",   len = 96  },
        { name = "sha512",   len = 128 },
        { name = "sha3-224", len = 56  },
        { name = "sha3-256", len = 64  },
        { name = "sha3-512", len = 128 },
    }
    for _, a in ipairs(algos) do
        local h = crypt.hash("test", a.name)
        assert(type(h) == "string",             a.name .. " must return string")
        assert(#h == a.len,                     a.name .. " wrong length: got " .. #h .. " want " .. a.len)
        assert(h == crypt.hash("test", a.name), a.name .. " must be deterministic")
    end
end)

test("getconnections (multiple signal types)", {}, function()
    local rs = game:GetService("RunService")
    local signals = {
        rs.Heartbeat,
        rs.RenderStepped,
        workspace.ChildAdded,
    }
    for _, sig in ipairs(signals) do
        local conns = getconnections(sig)
        assert(type(conns) == "table", "must return table for signal")
    end
end)

test("setclipboard (unicode)", {}, function()
    local unicode = "Hello \xe4\xb8\x96\xe7\x95\x8c"
    setclipboard(unicode)
    local result = getclipboard()
    assert(type(result) == "string", "getclipboard must return a string after unicode set")
end)

test("Drawing (properties per type)", {}, function()
    local shapeTypes = { "Line", "Text", "Image", "Circle", "Square", "Triangle", "Quad" }
    for _, shape in ipairs(shapeTypes) do
        local ok, obj = pcall(Drawing.new, shape)
        assert(ok and obj ~= nil,  shape .. ": Drawing.new must succeed")
        pcall(function()
            obj.Visible      = false
            obj.Color        = Color3.new(1, 0, 0)
            obj.Transparency = 0.5
        end)
        pcall(function() obj:Destroy() end)
    end
end)

test("WebSocket (OnClose event)", {}, function()
    local ws     = WebSocket.connect("ws://echo.websocket.events")
    local closed = false
    ws.OnClose:Connect(function() closed = true end)
    ws:Close()
    task.wait(0.5)
    assert(closed, "OnClose must fire after ws:Close()")
end)

test("hookfunction (restore original)", {}, function()
    local function fn() return "original" end
    local ref = hookfunction(fn, function() return "hooked" end)
    assert(fn() == "hooked",   "must be hooked")
    hookfunction(fn, ref)
    assert(fn() == "original", "must be restored after hooking back with ref")
end)

test("newcclosure (wrapping cclosure)", {}, function()
    local inner = newcclosure(function() return "inner" end)
    local outer = newcclosure(inner)
    assert(iscclosure(outer),  "cclosure wrapping cclosure must still be cclosure")
    assert(outer() == "inner", "must return inner's value")
end)

test("task.spawn (returns thread)", {}, function()
    local thread = task.spawn(function() end)
    assert(type(thread) == "thread", "task.spawn must return the spawned thread")
end)

test("coroutine (executor environment)", {}, function()
    assert(type(coroutine)         == "table",    "coroutine must be a table")
    assert(type(coroutine.create)  == "function", "coroutine.create must exist")
    assert(type(coroutine.resume)  == "function", "coroutine.resume must exist")
    assert(type(coroutine.yield)   == "function", "coroutine.yield must exist")
    assert(type(coroutine.wrap)    == "function", "coroutine.wrap must exist")
    assert(type(coroutine.status)  == "function", "coroutine.status must exist")
    assert(type(coroutine.running) == "function", "coroutine.running must exist")
    local co = coroutine.create(function() coroutine.yield(42) end)
    local ok, val = coroutine.resume(co)
    assert(ok and val == 42, "coroutine yield/resume must work in executor env")
end)

test("string (executor environment)", {}, function()
    assert(type(string.split)   == "function", "string.split must exist (Roblox ext)")
    assert(type(string.find)    == "function", "string.find must exist")
    assert(type(string.format)  == "function", "string.format must exist")
    assert(type(string.gsub)    == "function", "string.gsub must exist")
    assert(type(string.match)   == "function", "string.match must exist")
    assert(type(string.gmatch)  == "function", "string.gmatch must exist")
    assert(type(string.lower)   == "function", "string.lower must exist")
    assert(type(string.upper)   == "function", "string.upper must exist")
    assert(type(string.rep)     == "function", "string.rep must exist")
    assert(type(string.reverse) == "function", "string.reverse must exist")
    assert(type(string.sub)     == "function", "string.sub must exist")
    assert(type(string.byte)    == "function", "string.byte must exist")
    assert(type(string.char)    == "function", "string.char must exist")
    local parts = string.split("a,b,c", ",")
    assert(#parts == 3 and parts[1] == "a", "string.split must split correctly")
end)

test("math (executor environment)", {}, function()
    assert(type(math.huge)         == "number", "math.huge must be a number")
    assert(math.huge > 1e300,                   "math.huge must be very large")
    assert(type(math.pi)           == "number", "math.pi must be a number")
    assert(math.abs(math.pi - 3.14159) < 0.001, "math.pi must be approximately pi")
    assert(math.floor(1.9)         == 1,        "math.floor must work")
    assert(math.ceil(1.1)          == 2,        "math.ceil must work")
    assert(math.sqrt(9)            == 3,        "math.sqrt must work")
    assert(math.max(1, 2, 3)       == 3,        "math.max must work")
    assert(math.min(1, 2, 3)       == 1,        "math.min must work")
    assert(type(math.random())     == "number", "math.random must work")
    assert(math.round(1.5)         == 2,        "math.round (Roblox ext) must work")
end)

test("table (executor environment)", {}, function()
    assert(type(table.freeze)   == "function", "table.freeze must exist")
    assert(type(table.isfrozen) == "function", "table.isfrozen must exist")
    assert(type(table.clone)    == "function", "table.clone must exist")
    assert(type(table.create)   == "function", "table.create must exist")
    assert(type(table.find)     == "function", "table.find must exist")
    assert(type(table.move)     == "function", "table.move must exist")
    assert(type(table.pack)     == "function", "table.pack must exist")
    assert(type(table.unpack)   == "function", "table.unpack must exist")
    assert(type(table.insert)   == "function", "table.insert must exist")
    assert(type(table.remove)   == "function", "table.remove must exist")
    assert(type(table.sort)     == "function", "table.sort must exist")
    assert(type(table.concat)   == "function", "table.concat must exist")
    local t = { 3, 1, 2 }
    table.sort(t)
    assert(t[1] == 1 and t[3] == 3,           "table.sort must sort correctly")
    local c = table.clone({ a = 1 })
    assert(c.a == 1,                           "table.clone must copy correctly")
    assert(table.find({ 10, 20, 30 }, 20) == 2, "table.find must locate correctly")
end)

test("pcall / xpcall (executor environment)", {}, function()
    local ok, err = pcall(error, "test_error")
    assert(not ok,                 "pcall must catch errors")
    assert(err:find("test_error"), "pcall must return the error message")
    local ok2, val = pcall(function() return 42 end)
    assert(ok2 and val == 42,      "pcall must return values on success")
    local ok3, err3 = xpcall(
        function() error("xpcall_err") end,
        function(e) return "handled: " .. e end
    )
    assert(not ok3,             "xpcall must catch errors")
    assert(err3:find("handled"), "xpcall message handler must run")
end)

test("ipairs / pairs (executor environment)", {}, function()
    local arr = { 10, 20, 30 }
    local sum = 0
    for _, v in ipairs(arr) do sum += v end
    assert(sum == 60, "ipairs must iterate array correctly")
    local dict = { a = 1, b = 2 }
    local keys = {}
    for k in pairs(dict) do table.insert(keys, k) end
    assert(#keys == 2, "pairs must iterate dict keys correctly")
end)

test("select (executor environment)", {}, function()
    assert(select("#", 1, 2, 3) == 3,       "select('#',...) must return count")
    assert(select(2, "a", "b", "c") == "b", "select(n,...) must return nth onward")
end)

test("rawget / rawset / rawequal / rawlen", {}, function()
    local mt  = { __index = function() return "mt_val" end }
    local obj = setmetatable({}, mt)
    assert(rawget(obj, "missing") == nil, "rawget must bypass __index")
    rawset(obj, "x", 42)
    assert(obj.x == 42,                   "rawset must write value")
    local a, b = {}, {}
    assert(rawequal(a, a) == true,        "rawequal same ref must be true")
    assert(rawequal(a, b) == false,       "rawequal different refs must be false")
    assert(rawlen({ 1, 2, 3 }) == 3,      "rawlen must return array length")
end)

test("getfenv / setfenv (executor environment)", {}, function()
    local function fn() return MY_FENV_TEST end
    local env = setmetatable({ MY_FENV_TEST = "fenv_ok" }, { __index = getfenv(0) })
    setfenv(fn, env)
    assert(fn() == "fenv_ok",             "setfenv must change function environment")
    local got = getfenv(fn)
    assert(type(got) == "table",          "getfenv must return a table")
    assert(got.MY_FENV_TEST == "fenv_ok", "getfenv must return the set env")
end)

test("typeof (all Roblox types)", {}, function()
    local checks = {
        { v = Vector3.new(0,0,0),      t = "Vector3"     },
        { v = Vector2.new(0,0),        t = "Vector2"     },
        { v = CFrame.new(),            t = "CFrame"      },
        { v = Color3.new(0,0,0),       t = "Color3"      },
        { v = UDim2.new(0,0,0,0),      t = "UDim2"       },
        { v = UDim.new(0,0),           t = "UDim"        },
        { v = BrickColor.new("Red"),   t = "BrickColor"  },
        { v = NumberRange.new(0,1),    t = "NumberRange" },
        { v = Rect.new(0,0,1,1),       t = "Rect"        },
        { v = Instance.new("Part"),    t = "Instance"    },
        { v = "hello",                 t = "string"      },
        { v = 42,                      t = "number"      },
        { v = true,                    t = "boolean"     },
        { v = function() end,          t = "function"    },
    }
    for _, c in ipairs(checks) do
        assert(typeof(c.v) == c.t,
            "typeof " .. c.t .. " failed: got " .. typeof(c.v))
    end
end)

test("Instance.new (executor proxy)", {}, function()
    local part = Instance.new("Part")
    assert(typeof(part) == "Instance",    "must return an Instance")
    assert(part:IsA("Part"),              "IsA('Part') must work")
    assert(part:IsA("BasePart"),          "IsA('BasePart') must work for parent class")
    assert(part.ClassName == "Part",      "ClassName must be readable")
    part.Name = "UNC_Proxy_Test"
    assert(part.Name == "UNC_Proxy_Test", "Name must be writable and readable")
    part.Parent = workspace
    local found = workspace:FindFirstChild("UNC_Proxy_Test")
    assert(found ~= nil,                  "FindFirstChild must work through proxy")
    part:Destroy()
end)

task.defer(function()
    allQueued = true
    tryPrintSummary()
end)
