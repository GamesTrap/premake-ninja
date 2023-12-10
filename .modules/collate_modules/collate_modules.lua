--
-- Name:        premake-ninja/.modules/collate_modules/collate_modules.lua
-- Purpose:     Define the collate_modules action.
-- Author:      Jan "GamesTrap" Schürkamp
-- Created:     2023/12/10
-- Copyright:   (c) 2023 Jan "GamesTrap" Schürkamp
--

local p = premake

premake.modules.collate_modules = {}
local collate_modules = p.modules.collate_modules

local modmapfmt = _OPTIONS["modmapfmt"]
local dd = _OPTIONS["dd"]
local ddis = {}

local function printError(msg)
	term.setTextColor(term.errorColor)
	print(msg)
	term.setTextColor(nil)
end

local function printDebug(msg)
	term.setTextColor(term.magenta)
	print(msg)
	term.setTextColor(nil)
end

local function validateInput()
	if not _OPTIONS["ddi"] then
		printError("collate_modules requires value for --ddi=")
		return false
	end

	if not dd then
		printError("collate_modules requires value for --dd=")
		return false
	end

	return true
end

local function getModuleMapExtension(modmapFormat)
	if not modmapFormat then
		return ".bmi"
	end

	if(modmapFormat == "clang") then
		return ".pcm"
	elseif (modmapFormat == "gcc") then
		return ".gcm"
	elseif(modmapFormat == "msvc") then
		return ".ifc"
	else
		printError("collate_modules does not understand the " .. modmapFormat .. " module map format!")
		os.exit()
	end
end

local function generateNinjaDynDepFile()
	local fileStr = "ninja_dyndep_version = 1.0\n"

	return fileStr
end

local function decodeDDIs(ddis)
	local decodedDDIs = {}

	for k, v in pairs(ddis) do
		local result, error = json.decode(io.readfile(v))
		if not result or error then
			printError("Failed to decode \"" .. v .. "\" (" .. error .. ")")
			os.exit()
		end

		-- printDebug("Successfully decoded \"" .. v .. "\"")
		table.insert(decodedDDIs, result)
	end

	return decodedDDIs
end

local function mapDDIs(ddis)
	local modFiles = {}
	local targetModules = {}

	local moduleExt = getModuleMapExtension(modmapfmt)

	for _, ddi in pairs(ddis) do
		if ddi["rules"] and ddi["rules"][1] and ddi["rules"][1]["provides"] and ddi["rules"][1]["provides"][1] and
		   ddi["rules"][1]["primary-output"] then
			local ddiProvides = ddi["rules"][1]["provides"][1]
			local ddiPrimaryOutput = ddi["rules"][1]["primary-output"]
			local logicalName = ddiProvides["logical-name"]

			local mod = nil

			if ddiProvides["compiled-module-path"] then
				--The scanner provided the path to the module file.
				mod = ddiProvides["compiled-module-path"]
			else
				--Assume the module file path matches the logical module name.
				local safeLogicalName = logicalName --TODO Needs fixing for header units
				safeLogicalName = string.gsub(safeLogicalName, ":", "-")
				local moduleDir = path.getdirectory(ddiPrimaryOutput)
				mod = moduleDir .. safeLogicalName .. moduleExt
			end

			modFiles[logicalName] = {["BMIPath"] = mod, ["IsPrivate"] = false} --Always visible within our own target.

			targetModules[logicalName] = {["bmi"] = mod, ["is-private"] = false}

			-- for k,v in pairs(ddiProvides) do
			-- 	for k1,v1 in pairs(v) do
			-- 		printDebug("Key " .. k1)
			-- 		printDebug("Value " .. v1)
			-- 	end
			-- end
			-- printDebug("Primary-output: " .. ddiPrimaryOutput)
		end
	end

	return modFiles, targetModules
end

function collate_modules.CollateModules()
	if not validateInput() then
		os.exit()
	end

	local ddis = string.explode(_OPTIONS["ddi"], " ")

	-- printDebug("modmapfmt: " .. modmapfmt)
	-- printDebug("dd: " .. dd)
	-- for _,v in pairs(ddis) do
	-- 	printDebug(v)
	-- end
	-- for k, v in pairs(_ARGS) do
	-- 	printDebug("Key: " .. k)
	-- 	printDebug("Value: " .. v)
	-- end

	local decodedDDIs = decodeDDIs(ddis)
	local modFiles, targetModules = mapDDIs(decodedDDIs)

	local NinjaDynDepFile = generateNinjaDynDepFile()
	printDebug(NinjaDynDepFile)
	io.writefile(dd, NinjaDynDepFile)
end

include("_preload.lua")

return collate_modules
