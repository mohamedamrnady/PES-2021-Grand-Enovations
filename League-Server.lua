--League-Server by GRAND(Gerlamp) and Mohamed Amr Nady
--Research: SMc81, .andre92
--Special thank's: crabshank

local m = {}
-- Constants
local contentPath = ".\\content\\season-server\\"
local startAddress = 0x00007FF4D0000000
local endAddress = 0x00007FF4DFFFFFFF
local hexPat = '0x%x+'
local BlankDate = ("\xff\xff\xff\xff\x37\x00\x00\x00\x03\x00\x00\x00\xff\xff\xff\xff")
local genericSchedule = {
    [18] = {
        --League Starts Jan
        "1/17",
        "1/24",
        "2/14",
        "2/21",
        "2/28",
        "3/7",
        "3/21",
        "3/28",
        "4/11",
        "4/18",
        "4/25",
        "5/2",
        "5/9",
        "5/23",
        "6/20",
        "6/24",
        "7/20",
        "7/26",
        "8/1",
        "8/8",
        "8/22",
        "8/29",
        "9/12",
        "9/19",
        "9/26",
        "10/3",
        "10/17",
        "10/24",
        "11/12",
        "11/18",
        "11/28",
        "12/5",
        "12/12",
        "12/23",
    }, -- 34 matches
    [20] = {
        --Turkey
        "8/12",
        "8/19",
        "8/27",
        "9/2",
        "9/17",
        "9/24",
        "9/30",
        "10/7",
        "10/22",
        "10/29",
        "11/5",
        "11/11",
        "11/26",
        "12/2",
        "12/8",
        "12/14",
        "12/18",
        "12/22",
        "12/26",
        "1/14",
        "1/21",
        "1/24",
        "1/28",
        "2/4",
        "2/11",
        "2/18",
        "2/25",
        "3/3",
        "3/10",
        "3/17",
        "4/3",
        "4/7",
        "4/14",
        "4/21",
        "4/28",
        "5/5",
        "5/12",
        "5/19",
    }, -- 38 matches
    [22] = { "8/22",
        "8/23",
        "8/24",
        "8/25",
        "8/26",
        "8/27",
        "8/28",
        "8/29",
        "8/30",
        "8/31",
        "9/1",
        "9/2",
        "9/3",
        "9/4",
        "9/5",
        "9/6",
        "9/7",
        "9/8",
        "9/9",
        "9/10",
        "9/11",
        "9/12",
        "9/13",
        "9/14",
        "9/15",
        "9/16",
        "9/17",
        "9/18",
        "9/19",
        "9/20",
        "9/21",
        "9/22",
        "9/23",
        "9/24",
        "9/25",
        "9/26",
        "9/27",
        "9/28",
        "9/29",
        "9/30",
        "10/1",
        "10/2",
    }, -- 42 matches
}
-- Variables
local compsMap
local mlteamnow = {}
local CalendarAddresses = {}
local Schedule = {}
local gamesSchedule = {}
local matchdays = {}
local teamIDsToHex = {}
local teamNamestoIDs = {}
local fixtureNumber = {}
local gameweekNumber = {}
local fromDates = {}
local toDates = {}
local isNight = {}
local matchStartTime = {}
local homeTeams = {}
local awayTeams = {}
local fixtureNumberInterval = 0
-- Config
local isDebugging = true
-- local changeDate = false


function m.dispose()
    mlteamnow = {}
    CalendarAddresses = {}
    Schedule = {}
    gamesSchedule = {}
    matchdays = {}
    teamIDsToHex = {}
    teamNamestoIDs = {}
    fixtureNumber = {}
    gameweekNumber = {}
    fromDates = {}
    toDates = {}
    isNight = {}
    matchStartTime = {}
    homeTeams = {}
    awayTeams = {}
end

local function get_rlm_lib(ctx)
    return ctx.real_life_mode or _empty
end

local function date_to_totaldays(month, day)
    local days_in_each_month = { 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 }
    if month > 0 and month <= 12 and day > 0 and day <= 31 then
        if day > days_in_each_month[month] then
            log("Incorrect Date: day should be smaller")
            return nil
        end
        local totaldays = day
        for i = 1, month - 1 do
            totaldays = totaldays + days_in_each_month[i]
        end
        return totaldays
    else
        log("Incorrect Date: be realistic plz")
        return nil
    end
end

local function teamHextoID(teamHex)
    function getBits(num)
        local x = {}
        while num > 0 do
            rest = num % 2
            table.insert(x, 1, rest)
            num = (num - rest) / 2
        end
        return table.concat(x) or x
    end

    function binToNum(binary)
        local bin, sum = tostring(binary):reverse(), 0
        for i = 1, #bin do
            num = bin:sub(i, i) == "1" and 1 or 0
            sum = sum + num * 2 ^ (i - 1)
        end
        return sum
    end

    return binToNum(getBits(memory.unpack("u32", teamHex)):sub(1, -15))
end

local function gamedayToTeamIDs(matchday)
    local t = {}
    for n = 1, 10 do
        local gameAddress = matchday[n]
        local homeHex = memory.read(gameAddress + 20, 4)
        local awayHex = memory.read(gameAddress + 24, 4)
        t[teamHextoID(homeHex)] = homeHex
        t[teamHextoID(awayHex)] = awayHex
    end
    return t
end

local function getAddressWithVariableBytes(addrBeginning, variableByteLength, addrEndning, variableStartAddress)
    local addr = memory.safe_search(addrEndning, variableStartAddress, endAddress)
    if memory.read(addr - #addrBeginning - variableByteLength, #addrBeginning) == addrBeginning then
        return addr - variableByteLength - #addrBeginning
    else
        return getAddressWithVariableBytes(addrBeginning, variableByteLength, addrEndning, addr + #addrEndning)
    end
end

local function getGamesOfLeagueUsingMemory(currentleagueid, matchdaytotal)
    local variableBytesLength = 20
    local addrEndning = "\x00\x00\x00\x00\x00\x00\x00\x00\xFF\xFF"
    local returnValueOffset = -2

    local t = {}
    for i = 1, matchdaytotal do
        local all_found = false
        local variableStartAddress = startAddress
        local addrBeginning = "\x00\x00" .. currentleagueid .. memory.pack("u8", i - 1) .. "\x20"
        log(string.format("searching matchday %d", i))
        t[i] = {}
        while all_found == false and variableStartAddress <= endAddress do
            local addr = memory.safe_search(addrBeginning, variableStartAddress, endAddress)
            if addr then
                if memory.read(addr + #addrBeginning + variableBytesLength, #addrEndning) == addrEndning then
                    log("address matches criteria, inserting...")
                    table.insert(t[i], addr + returnValueOffset)
                else
                    log("address doesn't matches criteria, skipping...")
                end
                variableStartAddress = tonumber(string.match(tostring(addr), hexPat)) + 1
            else
                all_found = true
                log(string.format("found %d address in matchday %d", #t[i], i))
            end
        end
    end
    return t
end

local function getGamesOfCompUsingLoop(currentleagueid, yearnow, total_matchdays, total_games_per_matchday)
    local t = {}
    local addr
    for matchday = 1, total_matchdays do
        t[matchday] = {}
        for game = 1, total_games_per_matchday do
            if matchday == 1 and game == 1 then
                addr = memory.safe_search("\x00\x00" .. currentleagueid .. "\x00\x20" .. yearnow, startAddress,
                    endAddress) - 2
                if addr then
                    fixtureNumberInterval = memory.unpack("u16", memory.read(addr, 2))
                    table.insert(t[1], addr)
                else
                    error("matchday 1 game 1 wasn't found, aborting...")
                    return {}
                end
            else
                addr = t[1][1]
                    + 596 * (game - 1)
                    + 596 * (matchday - 1) * total_games_per_matchday
                table.insert(t[matchday], addr)
            end
            if isDebugging then
                log(string.format("matchdays: MatchDay %d Game %d : %s", matchday, game,
                    memory.hex(memory.read(addr, 28))))
            end
        end
    end
    return t
end

local function getSchedule(currentleagueid, total_matchdays, total_games_per_matchday)
    local t = {}
    local addr
    for matchday = 1, total_matchdays do
        t[matchday] = {}
        for game = 1, total_games_per_matchday do
            if matchday == 1 and game == 1 then
                addr = getAddressWithVariableBytes(currentleagueid .. "\x00\x00", 11, "\xff" .. currentleagueid,
                    startAddress)
                if addr then
                    table.insert(t[1], addr - 6)
                else
                    error("matchday 1 game 1 wasn't found, aborting...")
                    return {}
                end
            else
                addr = t[1][1]
                    + 32 * (game - 1)
                    + 520 * (matchday - 1)
                table.insert(t[matchday], addr)
            end
            if isDebugging then
                log(string.format("gamesSchedule: MatchDay %d Game %d : %s", matchday, game,
                    memory.hex(memory.read(addr, 28))))
            end
        end
    end
    return t
end

-- local function getAllAddressesWithVariableBytes(addrBeginning, variableByteLength, addrEndning, variableStartAddress,
--                                                 returnValueOffset)
--     local t = {}
--     local all_found = false
--     while all_found == false and variableStartAddress <= endAddress do
--         local addr = memory.safe_search(addrBeginning, variableStartAddress, endAddress)
--         if addr == nil then
--             all_found = true
--             log(string.format("found %d address", #t))
--         else
--             local ad = tonumber(string.match(tostring(addr), hexPat))
--             if type(ad) == 'number' then
--                 log("found address")
--                 if memory.read(addr + #addrBeginning + variableByteLength, #addrEndning) == addrEndning then
--                     log("address matches criteria, inserting...")
--                     log(memory.hex(memory.read(ad + returnValueOffset, #addrBeginning)))
--                     table.insert(t, ad + returnValueOffset)
--                     -- else
--                     --     log(memory.hex(addr))
--                 end
--                 variableStartAddress = ad + #addrBeginning
--             end
--         end
--     end
--     return t
-- end

local function readMatchdays(dir)
    local fixture = {}
    local gameweek = {}
    local datesfrom = {}
    local datesto = {}
    local nightBools = {}
    local timeStrings = {}
    local home = {}
    local away = {}
    local f = io.open(dir)
    log(dir)
    if f then
        for line in f:lines() do
            if not string.match(line, ";") then
                local fixtureno, compno, fromdate, todate, night, time, homeN, awayN = line:match(
                    "([^,]+),([^,]+),([^,]+),([^,]+),([^,]+),([^,]+),([^,]+),([^,]+)")
                if fixtureno and compno and fromdate and todate and night and time and homeN and awayN then
                    table.insert(fixture, tonumber(fixtureno))
                    table.insert(gameweek, tonumber(compno))
                    table.insert(datesfrom, fromdate)
                    table.insert(datesto, todate)
                    table.insert(nightBools, tonumber(night))
                    table.insert(timeStrings, tonumber(time))
                    table.insert(home, homeN)
                    table.insert(away, awayN)
                    log(string.format("Fix. %s in Gameweek %s On %s At %s o'clock: %s VS %s",
                        fixtureno, compno,
                        todate, time, homeN, awayN))
                else
                    error("error reading matchdays")
                end
            end
        end
    end
    return fixture, gameweek, datesfrom, datesto, nightBools, timeStrings, home, away
end

local function readTeamsMap(dir)
    local t = {}
    local f = io.open(dir)
    log(dir)
    if f then
        for line in f:lines() do
            if not string.match(line, ";") then
                local id, name = line:match("([^,]+),([^,]+)")
                if id and name then
                    t[name] = tonumber(id) or id
                    log(string.format("Team Name : %s Id : %s", name, id))
                else
                    error("error reading mapteams")
                end
            end
        end
    end
    return t
end

local function readCompsMap()
    local dir = contentPath .. "\\map_competitions.txt"

    local t = {}
    local f = io.open(dir)
    log(dir)
    if f then
        for line in f:lines() do
            if not string.match(line, ";") then
                local name, id = line:match("([^,]+)=([^,]+)")
                if id and name then
                    if not t[id] then
                        local exits = io.open(contentPath .. name .. "\\config.ini")
                        if exits then
                            t[tonumber(id)] = name
                            log(string.format("Comp Name : %s Id : %s", name, id))
                        end
                    end
                else
                    error("error reading mapteams")
                end
            end
        end
    end
    return t
end

local function readLeagueConfig(dir)
    local t = {}
    local f = io.open(dir)
    log(dir)
    if f then
        for line in f:lines() do
            if not string.match(line, ";") then
                local name, value = line:match("([^,]+)=([^,]+)")
                if value and name then
                    t[name] = tonumber(value) or value
                    log(line)
                else
                    error("error reading LeagueConfig")
                end
            end
        end
    end
    return t
end

local function getFolders(path)
    local t = {}
    local command = string.format([[dir "%s" /b /ad]], path)

    for dir in io.popen(command):lines() do
        t[dir] = ""
    end

    return t
end


local function setGenericSchedule(league_config, startingYear, currentTeamIsInLeague, isNewSeason)
    -- from/to: date (month/day)
    -- startingYear: the year the ML starts
    local total_league_teams = league_config["TOTAL_TEAMS"]
    local total_matchdays = total_league_teams * 2 - 2
    local total_games_in_matchday = total_league_teams / 2
    local secondYear = startingYear + 1
    log(string.format("%d teams %d matchdays with %d games", total_league_teams, total_matchdays, total_games_in_matchday))
    for matchday_number = 1, total_matchdays do
        log(string.format("generic matchday %d", matchday_number))
        -- Date configs
        local to = genericSchedule[total_league_teams][matchday_number]
        local mon, day = to:match("(%d+)/(%d+)")
        local to_month, to_day = tonumber(mon), tonumber(day)
        if league_config["STARTS_IN_JAN"] == "false" then
            if to_month <= 6 then
                startingYear = secondYear
                --yearnow.dec = yearnow.dec + 1
                --log(string.format("yearnow for schedule: %d", yearnow.dec))
                log(string.format("yearnow for schedule: %d", startingYear))
            end
        end
        -- if changeDate then
        -- Calendar Writing
        local game_type_hex = "\x02\x00"
        if currentTeamIsInLeague then
            memory.write(CalendarAddresses[date_to_totaldays(to_month, to_day)],
                memory.pack("u16", (total_league_teams / 2) * (matchday_number - 1) + fixtureNumberInterval)) -- C8 00 Matchday ID
            memory.write(CalendarAddresses[date_to_totaldays(to_month, to_day)] + 2,
                league_config["ID"].hex)                                                                      -- 11 00 League ID
            memory.write(CalendarAddresses[date_to_totaldays(to_month, to_day)] + 4,
                memory.pack("u16", matchday_number - 1))                                                      -- 14 00 Matchday № this 21 day
            memory.write(CalendarAddresses[date_to_totaldays(to_month, to_day)] + 6, "\x00")                  -- 00 00 Blank
            memory.write(CalendarAddresses[date_to_totaldays(to_month, to_day)] + 8, game_type_hex)           -- 02 00 Playable day (01 UCL) (03 not Playableday)
            memory.write(CalendarAddresses[date_to_totaldays(to_month, to_day)] + 10, "\x00")                 -- 00 00 Blank
            memory.write(CalendarAddresses[date_to_totaldays(to_month, to_day)] + 12, mlteamnow.hex)          -- Team ID
        end
        -- end
        if isNewSeason then
            for fixture_number = 1, total_games_in_matchday do
                log(string.format("generic game %d in matchday %d", fixture_number, matchday_number))
                -- Writing Process
                local sum = memory.unpack("u8", memory.read(Schedule[date_to_totaldays(to_month, to_day)], 1)) + 1
                local fixNoHex = memory.pack("u16",
                    fixture_number - 1 + (total_league_teams / 2) * (matchday_number - 1) + fixtureNumberInterval)

                -- Matchday Writing

                -- E6 00 (Fixture id)
                -- 00 00 11 00 (Liga id)
                -- 17 (Matchday)
                -- 20 (League type)
                -- E5 07 01 1A (Date 2021/01/26)
                -- 00 00 00 00 (Night Boolean)
                -- 10 00 00 00 (Match time)
                -- 10 C0 2C 00 (Home team)
                -- 04 80 19 00 (Away team)

                local gameAddress = matchdays[matchday_number][fixture_number]
                local matchdaySchedule = gamesSchedule[matchday_number][fixture_number]
                if isDebugging then
                    log(string.format("matchdays: Game %d of MatchDay %d Before: %s", fixture_number, matchday_number,
                        memory.hex(memory.read(gameAddress, 28))))
                    log(string.format("gamesSchedule: Game %d of MatchDay %d Before: %s", fixture_number, matchday_number,
                        memory.hex(memory.read(matchdaySchedule, 18))))
                end
                memory.write(gameAddress + 12, memory.pack("u16", 1))  -- Night Bool
                memory.write(gameAddress + 16, memory.pack("u16", 20)) -- Time
                -- if changeDate then
                memory.write(gameAddress + 8,
                    memory.pack("u16", startingYear) .. memory.pack("u8", to_month) .. memory.pack("u8", to_day))
                -- end
                if isDebugging then
                    log(string.format("matchdays: Game %d of MatchDay %d After: %s", fixture_number, matchday_number,
                        memory.hex(memory.read(gameAddress, 28))))
                    log(string.format("gamesSchedule: Game %d of MatchDay %d After: %s", fixture_number, matchday_number,
                        memory.hex(memory.read(matchdaySchedule, 18))))
                end
                -- Schedule Writing
                memory.write(Schedule[date_to_totaldays(to_month, to_day)], memory.pack("u8", sum))        -- (addr_gamedays_sum)
                -- Write new fixture after previous ones (if there any)
                memory.write(Schedule[date_to_totaldays(to_month, to_day)] - (sum * (-2) + 562), fixNoHex) -- (addr_10gamedays)
                memory.write(Schedule[date_to_totaldays(to_month, to_day)] + 7, "\x00")
            end
        end
    end
end

local function tableIsEmpty(self)
    for _, _ in pairs(self) do
        return false
    end
    return true
end

function m.data_ready(ctx, filename)
    --Main
    local newml = string.match(filename, "common\\demo\\fixdemo\\mode\\cut_data\\mode_meeting_reply_0%d%_pl.fdc")
    local newbl = string.match(filename, "common\\demo\\fixdemo\\mode\\cut_data\\mode_firstday_BL01_1_pl.fdc")
    --local newml = string.match(filename, "common\\demo\\fixdemo\\mode\\cut_data\\mode_meeting_mission_07a_manager.fdc")

    if newml or newbl then
        log("**Writing Started**")
        local rlmLib = get_rlm_lib(ctx)
        local year = rlmLib.hook_year()
        local position = memory.read(year - 3, 1)
        local yearnow = rlmLib.current_season()
        local secondYear = yearnow.dec + 1
        -- startingYear = yearnow.dec
        -- endingYear = yearnow.dec + 1
        local datenow = memory.read(year + 5, 4)
        local currentMonth = memory.unpack("u8", memory.read(year + 7, 1))
        -- local currentleagueid = memory.read(year + 51, 1)

        mlteamnow = rlmLib.current_team_id()
        local currentleagueid = {}
        currentleagueid.dec = ctx.common_lib.compID_to_tournamentID_map
            [ctx.common_lib.leagues_of_teams[mlteamnow.dec][1]]
        currentleagueid.hex = memory.pack("u16", currentleagueid.dec)
        log(string.format("ML Team: %d", mlteamnow.dec))
        log(string.format("League ID: %d", currentleagueid.dec))
        log(string.format("Season: %d", yearnow.dec))

        if not tableIsEmpty(compsMap) then
            local leagues_configs = {}
            for i, compName in pairs(compsMap) do -- Load all league configs to return current league config easily
                leagues_configs[i] = readLeagueConfig(contentPath ..
                    string.format("\\%s\\", compName) .. "config.ini")
                leagues_configs[i]["ID"] = {}
                leagues_configs[i]["ID"].dec = i
                leagues_configs[i]["ID"].hex = memory.pack("u16", i)
            end
            -- local compName = compsMap[currentleagueid.dec]
            for i, compName in pairs(compsMap) do
                local configPath = contentPath ..
                    string.format("\\%s\\", compName)
                local existingYears = getFolders(configPath)
                if tableIsEmpty(CalendarAddresses) then
                    for counter = 1, 365 do
                        if isDebugging then
                            log(string.format("Calendar: Day %d : %s", counter,
                                memory.hex(memory.read(year + counter * 16 + 1, 16))))
                        end
                        table.insert(CalendarAddresses, counter, year + counter * 16 + 1)
                    end
                end
                -- Schedule -- Found in ML Main Menu Bottom Left and Center -- Needs optimization
                if tableIsEmpty(Schedule) then
                    local addr
                    if leagues_configs[currentleagueid.dec]["STARTS_IN_JAN"] == "true" then
                        addr = getAddressWithVariableBytes("\x00\x00\x03\x00\x00\x00", 2, "\x01\x01\x01\x00\x01",
                            startAddress)
                    elseif leagues_configs[currentleagueid.dec]["STARTS_IN_JAN"] == "false" then
                        addr = getAddressWithVariableBytes("\x00\x00\x06\x00\x00\x00", 2, "\x01\x01\x09\x00\xF5",
                            startAddress)
                    end
                    if addr then
                        table.insert(Schedule, 1, addr - 2)
                        for day = 1, 364 do -- day 0 is already there
                            table.insert(Schedule, day + 1, Schedule[1] + 708 * day)
                            if isDebugging then
                                log(string.format("Schedule: Day %d : %s", day + 1,
                                    memory.hex(memory.read(Schedule[1] + 708 * day, 15))))
                            end
                        end
                    else
                        error("schecule was not found, aborting...")
                    end
                end
                local isNewSeason = (currentMonth == 1 and leagues_configs[i]["STARTS_IN_JAN"] == "true") or
                    ((currentMonth == 6 or currentMonth == 8) and leagues_configs[i]["STARTS_IN_JAN"] == "false")
                -- if isNewSeason then
                local total_matchdays
                local total_games_per_matchday
                if leagues_configs[i]["TOTAL_MATCHDAYS"] ~= nil then
                    total_matchdays = leagues_configs[i]["TOTAL_MATCHDAYS"]
                else
                    total_matchdays = leagues_configs[i]["TOTAL_TEAMS"] * 2 - 2
                end
                if leagues_configs[i]["TOTAL_GAMES_PER_MATCHDAY"] ~= nil then
                    total_games_per_matchday = leagues_configs[i]["TOTAL_GAMES_PER_MATCHDAY"]
                else
                    total_games_per_matchday = leagues_configs[i]["TOTAL_TEAMS"] / 2
                end
                if existingYears[tostring(yearnow.dec)] then -- custom edit based on year
                    local mapsPath = configPath .. tostring(yearnow.dec)
                    teamNamestoIDs = readTeamsMap(mapsPath .. "\\map_team.txt")
                    fixtureNumber, gameweekNumber, fromDates, toDates, isNight, matchStartTime, homeTeams, awayTeams =
                        readMatchdays(
                            mapsPath ..
                            "\\map_matchdays.txt")

                    if isNewSeason then
                        matchdays = getGamesOfCompUsingLoop(memory.pack("u16", i), yearnow.hex, total_matchdays,
                            total_games_per_matchday)                                                                 -- Found in ML Main Menu> Team Info> Schedule
                        gamesSchedule = getSchedule(memory.pack("u16", i), total_matchdays, total_games_per_matchday) -- Found in ML Main Menu> Team Info> Schedule> MatchDay ##
                    end
                    teamIDsToHex = gamedayToTeamIDs(matchdays[1])
                    for n = 1, #fixtureNumber do
                        local mon, day = fromDates[n]:match("(%d+)/(%d+)")
                        local from_month, from_day = tonumber(mon), tonumber(day)
                        mon, day = toDates[n]:match("(%d+)/(%d+)")
                        local to_month, to_day = tonumber(mon), tonumber(day)
                        local startingYear = yearnow.dec

                        if leagues_configs[i]["STARTS_IN_JAN"] == "false" then
                            if to_month <= 6 then
                                startingYear = secondYear
                            end
                        end
                        local fixNoHex = memory.pack("u16",
                            fixtureNumber[n] - 1 + (leagues_configs[i]["TOTAL_TEAMS"] / 2) * (gameweekNumber[n] - 1) +
                            fixtureNumberInterval)
                        if isNewSeason then
                            local sum = memory.unpack("u8", memory.read(Schedule[date_to_totaldays(to_month, to_day)], 1)) +
                                1
                            local gameAddress = matchdays[gameweekNumber[n]][fixtureNumber[n]]
                            local matchdaySchedule = gamesSchedule[gameweekNumber[n]][fixtureNumber[n]]
                            if isDebugging then
                                log(string.format("matchdays: Game %d of MatchDay %d Before: %s", fixtureNumber[n],
                                    gameweekNumber[n],
                                    memory.hex(memory.read(gameAddress, 28))))
                                log(string.format("gamesSchedule: Game %d of MatchDay %d Before: %s", fixtureNumber[n],
                                    gameweekNumber[n],
                                    memory.hex(memory.read(matchdaySchedule, 18))))
                            end
                            -- if changeDate then
                            memory.write(gameAddress + 8,
                                memory.pack("u16", startingYear) ..
                                memory.pack("u8", to_month) .. memory.pack("u8", to_day))
                            -- end
                            memory.write(gameAddress + 12, memory.pack("u16", isNight[n]))
                            memory.write(gameAddress + 16, memory.pack("u16", matchStartTime[n]))
                            memory.write(gameAddress + 20,
                                teamIDsToHex[teamNamestoIDs[homeTeams[n]]] .. teamIDsToHex[teamNamestoIDs[awayTeams[n]]])
                            memory.write(matchdaySchedule + 10,
                                teamIDsToHex[teamNamestoIDs[homeTeams[n]]] .. teamIDsToHex[teamNamestoIDs[awayTeams[n]]])

                            if isDebugging then
                                log(string.format("matchdays: Game %d of MatchDay %d After: %s", fixtureNumber[n],
                                    gameweekNumber[n],
                                    memory.hex(memory.read(gameAddress, 28))))
                                log(string.format("gamesSchedule: Game %d of MatchDay %d After: %s", fixtureNumber[n],
                                    gameweekNumber[n],
                                    memory.hex(memory.read(matchdaySchedule, 18))))
                            end
                            -- Schedule Writing
                            -- if changeDate then
                            memory.write(Schedule[date_to_totaldays(to_month, to_day)], memory.pack("u8", sum))
                            -- Write new fixture after previous ones (if there any)
                            memory.write(Schedule[date_to_totaldays(to_month, to_day)] - (sum * (-2) + 562), fixNoHex)
                            -- Remove "from_date" games
                            -- TODO: Decode that section for proper writing
                            memory.write(Schedule[date_to_totaldays(from_month, from_day)] - 560, string.rep("\xff", 560))
                        else
                            log("fixtures should be already set before")
                        end
                        -- Stop or Skip
                        if i == currentleagueid.dec then
                            if mlteamnow.dec == teamNamestoIDs[homeTeams[n]] or mlteamnow.dec == teamNamestoIDs[awayTeams[n]] then
                                -- Stop
                                memory.write(Schedule[date_to_totaldays(to_month, to_day)] + 7, "\x00")
                                -- Calendar Writing
                                -- TODO: Define that for UCL,... (01), domestic league/cup (02), or nothing (03)
                                local game_type_hex = "\x02\x00"

                                memory.write(CalendarAddresses[date_to_totaldays(to_month, to_day)], fixNoHex)        -- C8 00 Matchday ID
                                memory.write(CalendarAddresses[date_to_totaldays(to_month, to_day)] + 2,
                                    leagues_configs[i]["ID"].hex)                                                     -- 11 00 League ID
                                memory.write(CalendarAddresses[date_to_totaldays(to_month, to_day)] + 4,
                                    memory.pack("u16", gameweekNumber[n] - 1))                                        -- 14 00 Matchday № this 21 day
                                memory.write(CalendarAddresses[date_to_totaldays(to_month, to_day)] + 6, "\x00\x00")  -- 00 00 Blank
                                memory.write(CalendarAddresses[date_to_totaldays(to_month, to_day)] + 8,
                                    game_type_hex)                                                                    -- 02 00 Playable day (01 UCL) (03 not Playableday)
                                memory.write(CalendarAddresses[date_to_totaldays(to_month, to_day)] + 10, "\x00\x00") -- 00 00 Blank
                                memory.write(CalendarAddresses[date_to_totaldays(to_month, to_day)] + 12,
                                    mlteamnow.hex)                                                                    -- Team ID
                                memory.write(CalendarAddresses[date_to_totaldays(from_month, from_day)], BlankDate)   -- (from,Blank)
                            else
                                -- Skip
                                -- That might be causing an error that's we didn't experience yet
                                -- Some sort of double writing
                                memory.write(Schedule[date_to_totaldays(to_month, to_day)] + 7, "\xff")
                                -- Calendar Writing
                            end
                        end
                    end
                elseif not existingYears[tostring(yearnow.dec)] and leagues_configs[i]["NEEDS_GENERIC"] == "true" then -- generic schedule for created leagues
                    -- only needs dates set
                    log("applying generic schedule")
                    if isNewSeason then
                        matchdays = getGamesOfCompUsingLoop(memory.pack("u16", i), "\xff\xff", total_matchdays,
                            total_games_per_matchday)
                        gamesSchedule = getSchedule(memory.pack("u16", i), total_matchdays, total_games_per_matchday)
                    end
                    setGenericSchedule(leagues_configs[i], yearnow.dec, i == currentleagueid.dec, isNewSeason)
                else
                    error("current year config is not found and generic is disabled, aborting...")
                end
                -- else
                --     log(string.format("skipping %s, already set before or not supposed to be set yet", compName))
                -- end
                -- else
                --     log("league is not in content folder, nothing has changed")
                --     log("if that should not happen, make sure the league name matches the map")
                --     log("and it has config.ini in it with required parameters")
            end
            m.dispose()
        else
            log("that module is useless")
            log(string.format("since %s is empty or problem in map", contentPath))
            log("disable it for better experience")
        end
    end
end

function m.init(ctx)
    if contentPath:sub(1, 1) == "." then
        contentPath = ctx.sider_dir .. contentPath
    end
    m.dispose()
    compsMap = readCompsMap()
    ctx.register("livecpk_data_ready", m.data_ready)
end

return m
