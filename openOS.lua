local table_unpack, computer_pullSignal, table_insert, ssub, table_concat, component, error, xpcall, assert, shutdown, checkArg, pairs, type, unpack, traceback = table.unpack, computer.pullSignal, table.insert, string.sub, table.concat, component, error, xpcall, assert, computer.shutdown, checkArg, pairs, type, table.unpack, debug.traceback

-------------------------------------------------------functions

local function getDeviceLevel(address)
    return tonumber(computer.getDeviceInfo()[address].width) or false
end

local function getComponent(ctype)
    local maxlevel = 0
    local deviceaddress = nil
    local finded = false

    while true do
        finded = false
        for address, ltype in component.list(ctype) do
            if ctype == ltype then
                local level = getDeviceLevel(address)
                if not level then
                    deviceaddress = address
                elseif level > maxlevel then
                    maxlevel = level
                    deviceaddress = address
                    finded = true
                    break
                end
            end
        end
        if not finded then
            return component.proxy(deviceaddress or "")
        end
    end
end

local internet = getComponent("internet")
local componentBeep = getComponent("beep")

-------------------------------------------------------functions

local function delay(time)
    local inTime = computer.uptime()
    while computer.uptime() - inTime < time do
        computer.pullSignal(0)
    end
end

local function optimizeBeep(freq, del, bloked)
    if componentBeep then
        componentBeep.beep({[freq] = del})
        if bloked then delay(del) end
    else
        computer.beep(freq, del)
    end
end

local soundAllow = true
local function sound(num)
    if bootState or not soundAllow then return false end
    if num == 0 then
        optimizeBeep(1600, 0.05, true)
        optimizeBeep(1400, 0.05, true)
        optimizeBeep(1400, 0.05, true)
        optimizeBeep(1600, 0.05)
    elseif num == 1 then
        optimizeBeep(1000, 0.2)
    elseif num == 2 then
        optimizeBeep(1333, 0.05, true)
        optimizeBeep(1333, 0.05)
    elseif num == 3 then
        optimizeBeep(2000, 0.01)
    end
    return true
end

local function split(str, sep)
    local parts, count = {}, 1
    local i = 1
    while true do
        if i > #str then break end
        local char = ssub(str, i, #sep + (i - 1))
        if not parts[count] then parts[count] = "" end
        if char == sep then
            count = count + 1
            i = i + #sep
        else
            parts[count] = parts[count] .. ssub(str, i, i)
            i = i + 1
        end
    end
    if ssub(str, #str - (#sep - 1), #str) == sep then table_insert(parts, "") end
    return parts
end

-------------------------------------------------------graphics init

local gpu = component.proxy(computer.getBootGpu())
local screen = computer.getBootScreen()
local keyboard = component.invoke(screen, "getKeyboards")[1]
local rx, ry, depth = gpu.getResolution()
depth = gpu.getDepth()

-------------------------------------------------------functions

local function isColor()
    return depth ~= 1
end

local function optimizeColor(color, simpleColor, bf)
    if not simpleColor then simpleColor = color end
    if depth ~= 1 then
        if depth == 4 then
            return simpleColor
        else
            return color
        end
    else
        return (bf and 0xFFFFFF) or 0
    end
end

-------------------------------------------------------graphics

local function invert()
    gpu.setForeground(gpu.setBackground(gpu.getForeground()))
end

local function fill()
    gpu.fill(1, 1, rx, ry, " ")
end

local function setColor(back, fore)
    gpu.setBackground(back or 0xFFFFFF)
    gpu.setForeground(fore or 0)
end

local function clear(back, fore)
    setColor(back, fore)
    fill()
end

local function setText(text, posY)
    gpu.set(math.ceil((rx / 2) - (unicode.len(text) / 2)), posY, text)
end

local function menu(label, strs, num)
    local select = num or 1
    local posY = ((ry // 2) - (#strs // 2) - 1)
    if posY < 0 then posY = 0 end
    while true do
        clear()
        local startpos = (select // ry) * ry
        local dy = posY
        if startpos == 0 then
            if not isColor() then invert() end
            setText(label, 1 + dy)
            if not isColor() then invert() end
        else
            dy = 0
        end
        setColor(nil, optimizeColor(0x888888, 0xAAAAAA, false))
        for i = 1, #strs do
            local pos = (i + 1 + dy) - startpos
            if pos >= 1 and pos <= ry then
                if keyboard and select == i then invert() end
                setText(strs[i], pos)
                if keyboard and select == i then invert() end
            end
        end
        ::noReDraw::
        local isEvent = false
        local eventName, uuid, posX, code, button = computer.pullSignal()
        if eventName == "key_down" and uuid == keyboard then
            if code == 200 and select > 1 then
                select = select - 1
                isEvent = true
            end
            if code == 208 and select < #strs then
                select = select + 1
                isEvent = true
            end
            if code == 28 then
                sound(3)
                return select
            end
        elseif eventName == "touch" and uuid == screen and button == 0 then
            code = (code + startpos) - dy
            code = code - 1
            if code >= 1 and code <= #strs then
                local text = strs[code]
                local start, textEnd = math.ceil((rx / 2) - (unicode.len(text) / 2))
                textEnd = start + (unicode.len(text) - 1)
                if posX >= start and posX <= textEnd then
                    sound(3)
                    return code
                end
            end
        elseif eventName == "scroll" and uuid == screen then
            if button == 1 and select > 1 then
                select = select - 1
                isEvent = true
            end
            if button == -1 and select < #strs then
                select = select + 1
                isEvent = true
            end
        end
        if not isEvent then
            goto noReDraw
        else
            sound(3)
        end
    end
end

local function menuPro(label, strs, utiles, args, num)
    strs[#strs + 1] = "back" --да я знаю что так нельзя, что таблица ссылачьный тип, бла бла бла даже слышать не хочу
    local num = num or 1
    while true do
        local localLabel = label
        if type(label) == "function" then localLabel = label() end
        num = menu(localLabel, strs, num)
        if num == #strs then return end
        local arg = {}
        if args and args[num] then arg = args[num] end
        utiles[num](table.unpack(arg))
    end
end

local function yesno(label, simple, state)
    if simple then
        return menu(label, {"no", "yes"}, (state and 2) or 1) == 2
    else
        return menu(label, {"no", "no", "yes", "no"}, (state and 3) or 1) == 3
    end
end

local function isControl()
    return screen and (keyboard or (math.floor(computer.getDeviceInfo()[screen].width) ~= 1))
end

local function waitFoTouch(posY)
    gpu.set(1, posY, "press enter or touch to continue...")
    while true do
        local eventName, uuid, _, code = computer.pullSignal()
        if eventName == "key_down" and uuid == keyboard then
            if code == 28 then
                break
            end
        elseif eventName == "touch" and uuid == screen then
            break
        end
    end
    sound(3)
end

local function status(str, delayTime)
    if not screen then return end
    clear()
    setText(str, ry // 2)
    if delayTime then delay(delayTime) end
end

local function splash(str)
    if not screen then return end
    if not isControl() then status(str, 1) return end
    clear()
    gpu.set(1, 1, str)
    waitFoTouch(2)
end

local function input(posX, posY, crypto)
    if not keyboard then
        splash("keyboard is not found, touch to cancel input")
        return ""
    end
    local buffer = ""
    while true do
        gpu.set(posX, posY, "_")
        local eventName, uuid, char, code = computer.pullSignal()
        if eventName == "key_down" and uuid == keyboard then
            if code == 28 then
                sound(3)
                return buffer
            elseif code == 14 then
                if unicode.len(buffer) > 0 then
                    buffer = unicode.sub(buffer, 1, unicode.len(buffer) - 1)
                    gpu.set(posX, posY, " ")
                    posX = posX - 1
                    gpu.set(posX, posY, " ")
                    sound(3)
                end
            elseif char ~= 0 then
                buffer = buffer .. unicode.char(char)
                gpu.set(posX, posY, (crypto and "*") or unicode.char(char))
                posX = posX + 1
                sound(3)
            end
        elseif eventName == "clipboard" and uuid == keyboard then
            buffer = buffer .. char
            gpu.set(posX, posY, char)
            posX = posX + unicode.len(char)
            if unicode.sub(char, unicode.len(char), unicode.len(char)) == "\n" then
                sound(3)
                return unicode.sub(buffer, 1, unicode.len(buffer) - 1)
            end
        elseif eventName == "touch" and uuid == screen then
            if #buffer == 0 then return "" end
        end
    end
end

local function inputZone(text, crypto)
    clear()
    gpu.set(1, 1, text..": ")
    return input(unicode.len(text) + 3, 1, crypto)
end

local function garbage_collect()
    status("garbage collection")
    for i = 1, 5 do computer.pullSignal(0.1) end
end

-------------------------------------------------------functions

local function miniStr(uuid)
    if not uuid then return nil end
    return uuid:sub(1, 6)
end

local function getFile(fs, path)
    local file, err = fs.open(path)
    if not file then return nil, err end
    local buffer = ""
    while true do
        local read = fs.read(file, math.huge)
        if not read then break end
        buffer = buffer .. read
    end
    fs.close(file)
    return buffer
end

local function segments(path)
    local parts = {}
    for part in path:gmatch("[^\\/]+") do
        local current, up = part:find("^%.?%.$")
        if current then
            if up == 2 then
                table.remove(parts)
            end
        else
            table.insert(parts, part)
        end
    end
    return parts
end

local function filesystem_path(path)
    local parts = segments(path)
    local result = table.concat(parts, "/", 1, #parts - 1) .. "/"
    if unicode.sub(path, 1, 1) == "/" and unicode.sub(result, 1, 1) ~= "/" then
        return "/" .. result
    else
        return result
    end
end

local function saveFile(fs, path, data)
    fs.makeDirectory(filesystem_path(path))
    local file, err = fs.open(path, "w")
    if not file then return nil, err end
    fs.write(file, data)
    fs.close(file)
    return true
end

local function isBootFs(address)
    local proxy = component.proxy(address)
    return proxy.exists("/init.lua") or proxy.exists("/OS.lua")
end

local function fsName(address)
    return table_concat({miniStr(address), component.proxy(address).getLabel()}, ":")
end

local function selectfs(label, uuid, clearAllow, bottableOnly, isClear)
    local data = {n = {}, a = {}}
    for address in component.list("filesystem") do
        if not bottableOnly or isBootFs(address) then
            data.n[#data.n + 1] = fsName(address)
            data.a[#data.a + 1] = address
        end
    end
    if clearAllow then data.n[#data.n + 1] = "clear" end
    data.n[#data.n + 1] = "back"
    local num = 1
    if not isClear then
        if type(uuid) == "number" then
            num = uuid
        elseif type(uuid) == "string" then
            for i = 1, #data.a do 
                if data.a[i] == uuid then
                    num = i
                    break
                end
            end
        end
    else
        num = #data.n - 1
    end
    local select = menu(label, data.n, num)
    local address = data.a[select]
    if not address then
        if select == #data.n then
            return nil
        elseif select == (#data.n - 1) then
            return false
        end
    end
    return address
end

--[[
local function originalResolution()
    if screen then
        rx, ry = gpu.maxResolution()
        gpu.setResolution(rx, ry)
    end
end
]]

local function getInternetFile(url)
    if not internet then return nil, "internet card is not found" end
    local handle, data, result, reason = internet.request(url), ""
    if handle then
        while true do
            result, reason = handle.read(mathHuge)	
            if result then
                data = data .. result
            else
                handle.close()
                
                if reason then
                    return nil, reason
                else
                    return data
                end
            end
        end
    else
        return nil, "unvalid address"
    end
end

local function checkInternet(noSplash)
    if not internet then 
        if not noSplash then splash("internet card is not found") end
        return true
    end
end

local function checkPassword(text)
    local data = getDataPart(8)
    if data == "" then return true end
    local userInput = inputZone("password" .. ((text and (" to " .. text)) or ""), true)
    if userInput == "" then return nil end
    return data == userInput
end

local function endAt(...)
    local buff = ""
    for i, data in ipairs(split(...)) do
        buff = data
    end
    return buff
end

local function miniUrl(url)
    return split(split(url, "//")[2], "/")[1] .. ":" .. endAt(url, "/")
end

local function fileName(str)
    return endAt(str, "/"):match("[^.%.]+")
end

-------------------------------------------------------main

local function install(address, url)
    local filelist = getInternetFile(url .. "/filelist.txt")
    filelist = split(filelist, "\n")

    for i, filePath in ipairs(filelist) do
        local fileUrl = url .. filePath
        local file, err = getInternetFile(fileUrl)
        if file then
            status("saving file: " .. filePath)
            local ok, err = saveFile(component.proxy(address), filePath, file)
            if ok then
                status("saved file: " .. filePath)
            else
                status("error to save file: " .. (err or "unkown"))
            end
        else
            status("error to get file: " .. (err or "unkown"))
        end
    end
end

while true do
    local selected = selectfs("select fs to install")
    if not selected then return end

    local fs = component.proxy(selected)
    if fs.isReadOnly() then
        splash("filesystem is readonly")
    else
        local modes = {"openOS classic", "openOS modified", "mod only(no os)", "back"}
        local num = menu("select distribution", modes)
        if num ~= 4 and yesno("install " .. modes[num] .. " to " .. fsName(selected) .. "?") then
            if yesno("format?") then fs.remove("/") end
            if num == 1 then
                install(selected, "https://raw.githubusercontent.com/igorkll/openOS/main")
            elseif num == 2 then
                install(selected, "https://raw.githubusercontent.com/igorkll/openOS/main")
                install(selected, "https://raw.githubusercontent.com/igorkll/openOSpath/main")
            elseif num == 3 then
                install(selected, "https://raw.githubusercontent.com/igorkll/openOSpath/main")
            end
        end
    end
end