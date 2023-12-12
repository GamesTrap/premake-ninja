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

local VersionStr = "version"
local RulesStr = "rules"
local WorkDirectoryStr = "work-directory"
local PrimaryOutputStr = "primary-output"
local OutputsStr = "outputs"
local ProvidesStr = "provides"
local LogicalNameStr = "logical-name"
local CompiledModulePathStr = "compiled-module-path"
local UniqueOnSourcePathStr = "unique-on-source-path"
local SourcePathStr = "source-path"
local IsInterfaceStr = "is-interface"
local RequiresStr = "requires"
local LookupMethodStr = "lookup-method"

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

LookupMethod =
{
	ByName = "by-name",
	IncludeAngle = "include-angle",
	IncludeQuote = "include-quote"
}

-- SourceReqInfo =
-- {
-- 	LogicalName = "",
-- 	SourcePath = "",
-- 	CompiledModulePath = "",
-- 	UseSourcePath = false,
-- 	IsInterface = true,
-- 	Method = LookupMethod.ByName
-- }

-- ScanDepInfo =
-- {
-- 	PrimaryOutput = "",
-- 	ExtraOutputs = {},
-- 	Provides = {},
-- 	Requires = {}
-- }

-- ModuleReference =
-- {
-- 	Path = "",
-- 	Method = LookupMethod.ByName
-- }

-- ModuleUsage =
-- {
-- 	Usage = {},
-- 	Reference = {}
-- }

-- AvailableModuleInfo =
-- {
-- 	BMIPath = "",
-- 	IsPrivate = false
-- }

local function ScanDepFormatP1689Parse(ddiFilePath)
	local scanDepInfo =
	{
		PrimaryOutput = "",
		ExtraOutputs = {},
		Provides = {},
		Requires = {}
	}

	--Load ddi JSON
	local decodedDDI, error = json.decode(io.readfile(ddiFilePath))
	if not decodedDDI or error then
		printError("Failed to parse \"" .. ddiFilePath .. "\" (" .. error .. ")")
		return nil
	end

	local version = iif(decodedDDI[VersionStr], decodedDDI[VersionStr], nil)
	if version ~= nil and version > 1 then
		printError("Failed to parse \"" .. ddiFilePath .. "\": version " .. tostring(version))
		return nil
	end

	local rules = iif(decodedDDI[RulesStr], decodedDDI[RulesStr], nil)
	if rules and type(rules) == "table" then
		if #rules ~= 1 then
			printError("Failed to parse \"" .. ddiFilePath .. "\": expected 1 source entry")
			return nil
		end

		for _, rule in pairs(rules) do
			local workDir = rule[WorkDirectoryStr]
			if workDir and type(workDir) ~= "string" then
				printError("Failed to parse \"" .. ddiFilePath .. "\": work-directory is not a string")
				return nil
			end

			if rule[PrimaryOutputStr] then
				scanDepInfo.PrimaryOutput = rule[PrimaryOutputStr]
				if not scanDepInfo.PrimaryOutput then
					printError("Failed to parse \"" .. ddiFilePath .. "\": invalid filename")
					return nil
				end
			end

			if rule[OutputsStr] then
				local outputs = rule[OutputsStr]
				if outputs and type(outputs) == "table" then
					for _1, output in pairs(outputs) do
						if not output then
							printError("Failed to parse \"" .. ddiFilePath .. "\": invalid filename")
							return nil
						end
						table.insert(scanDepInfo.ExtraOutputs, output)
					end
				end
			end

			if rule[ProvidesStr] then
				local provides = rule[ProvidesStr]
				if type(provides) ~= "table" then
					printError("Failed to parse \"" .. ddiFilePath .. "\": provides is not an array")
					return nil
				end

				for _1, provide in pairs(provides) do
					local provideInfo =
					{
						LogicalName = "",
						SourcePath = "",
						CompiledModulePath = "",
						UseSourcePath = false,
						IsInterface = true,
						Method = LookupMethod.ByName
					}

					provideInfo.LogicalName = provide[LogicalNameStr]
					if not provideInfo.LogicalName then
						printError("Failed to parse \"" .. ddiFilePath .. "\": invalid blob")
						return nil
					end

					if provide[CompiledModulePathStr] then
						provideInfo.CompiledModulePath = provide[CompiledModulePathStr]
					end

					if provide[UniqueOnSourcePathStr] then
						local uniqueOnSourcePath = provide[UniqueOnSourcePathStr]
						if type(uniqueOnSourcePath) ~= "boolean" then
							printError("Failed to parse \"" .. ddiFilePath .. "\": unique-on-source-path is not a boolean")
							return nil
						end
						provideInfo.UseSourcePath = uniqueOnSourcePath
					else
						provideInfo.UseSourcePath = false
					end

					if provide[SourcePathStr] then
						provideInfo.SourcePath = provide[SourcePathStr]
					elseif provideInfo.UseSourcePath == true then
						printError("Failed to parse \"" .. ddiFilePath .. "\": source-path is missing")
						return nil
					end

					if provide[IsInterfaceStr] then
						local isInterface = provide[IsInterfaceStr]
						if type(isInterface) ~= "boolean" then
							printError("Failed to parse \"" .. ddiFilePath .. "\": is-interface is not a boolean")
							return nil
						end
						provideInfo.IsInterface = isInterface
					else
						provideInfo.IsInterface = true
					end

					table.insert(scanDepInfo.Provides, provideInfo)
				end
			end

			if rule[RequiresStr] then
				local requires = rule[RequiresStr]
				if type(requires) ~= "table" then
					printError("Failed to parse \"" .. ddiFilePath .. "\": requires is not an array")
					return nil
				end

				for _1, require in pairs(requires) do
					local requireInfo =
					{
						LogicalName = "",
						SourcePath = "",
						CompiledModulePath = "",
						UseSourcePath = false,
						IsInterface = true,
						Method = LookupMethod.ByName
					}

					requireInfo.LogicalName = require[LogicalNameStr]
					if not requireInfo.LogicalName then
						printError("Failed to parse \"" .. ddiFilePath .. "\": invalid blobl")
						return nil
					end

					if require[CompiledModulePathStr] then
						requireInfo.CompiledModulePath = require[CompiledModulePathStr]
					end

					if require[UniqueOnSourcePathStr] then
						local uniqueOnSourcePath = require[UniqueOnSourcePathStr]
						if type(uniqueOnSourcePath) ~= "boolean" then
							printError("Failed to parse \"" .. ddiFilePath .. "\": unique-on-source-path is not a boolean")
							return nil
						end
						requireInfo.UseSourcePath = uniqueOnSourcePath
					else
						requireInfo.UseSourcePath = false
					end

					if require[SourcePathStr] then
						requireInfo.SourcePath = require[SourcePathStr]
					elseif requireInfo.UseSourcePath then
						printError("Failed to parse \"" .. ddiFilePath .. "\": source-path is missing")
						return nil
					end

					if require[LookupMethodStr] then
						local lookupMethod = require[LookupMethodStr]
						if type(lookupMethod) ~= "string" then
							printError("Failed to parse \"" .. ddiFilePath .. "\": lookup-method is not a string")
							return nil
						end

						if lookupMethod == "by-name" then
							requireInfo.Method = LookupMethod.ByName
						elseif lookupMethod == "include-angle" then
							requireInfo.Method = LookupMethod.IncludeAngle
						elseif lookupMethod == "include-quote" then
							requireInfo.Method = LookupMethod.IncludeQuote
						else
							printError("Failed to parse \"" .. ddiFilePath .. "\": lookup-method is not valid: " .. lookupMethod)
							return nil
						end
					elseif requireInfo.UseSourcePath then
						requireInfo.Method = LookupMethod.ByName
					end

					table.insert(scanDepInfo.Requires, requireInfo)
				end
			end
		end
	end

	return scanDepInfo
end

local function getModuleMapExtension(modmapFormat)
	if(modmapFormat == "clang") then
		return ".pcm"
	elseif (modmapFormat == "gcc") then
		return ".gcm"
	elseif(modmapFormat == "msvc") then
		return ".ifc"
	else
		printError("collate_modules does not understand the " .. modmapFormat .. " module map format!")
		os.exit(1)
	end
end

local function fileIsFullPath(name)
	local nameLen = #name

	if os.target() == "windows" then
		--On Windows, the name must be at least two characters long.
		if nameLen < 2 then
			return false
		end
		if name[1] == ":" then
			return true
		end
		if name[2] == "\\" then
			return true
		end
	else
		--On UNIX, the name must be at least one character long.
		if nameLen < 1 then
			return false
		end
	end
	if os.target ~= "windows" then
		if name[1] == "~" then
			return true
		end
	end
	--On UNIX, the name must begin in a '/'.
	--On Windows, if the name begins in a '/', then it is a full network path.
	if name[1] == "/" then
		return true
	end

	return false
end

local function moduleUsageSeed(modFiles, moduleLocations, objects, usages)
	--TODO

	return nil
end

local function generateNinjaDynDepFile()
	local fileStr = "ninja_dyndep_version = 1.0\n"

	return fileStr
end

function collate_modules.CollateModules()
	if not validateInput() then
		os.exit(1)
	end

	local moduleDir = path.getdirectory(dd)

	local ddis = string.explode(_OPTIONS["ddi"], " ")

	local objects = {}
	for _, ddiFilePath in pairs(ddis) do
		local info = ScanDepFormatP1689Parse(ddiFilePath)
		if not info then
			printError("Failed to parse ddi file \"" .. ddiFilePath .. "\"")
			os.exit(1)
		end

		table.insert(objects, info)
	end

	local usages =
	{
		Usage = {},
		Reference = {}
	}

	local moduleExt = getModuleMapExtension(modmapfmt)

	--Map from module name to module file path, if known.
	local modFiles = {}
	local targetModules = {}
	for _, object in pairs(objects) do
		for _1, provide in pairs(object.Provides) do
			local mod = ""

			if provide.CompiledModulePath ~= "" then
				--The scanner provided the path to the module file
				mod = provide.CompiledModulePath
				if not fileIsFullPath(mod) then
					--Treat relative to work directory (top of build tree).
					-- mod = CollapseFullPath(mod, dirTopBld)
					--TODO (Use moduleDir to make path absolute?)
					printError("Scanner provided compiled module relative paths are not supported!")
					os.exit(1)
				end
			else
				--Assume the module file path matches the logical module name.
				local safeLogicalName = provide.LogicalName --TODO Needs fixing for header units
				string.gsub(safeLogicalName, ":", "-")
				mod = path.join(moduleDir, safeLogicalName) .. moduleExt
			end

			modFiles[provide.LogicalName] = { BMIPath = mod, IsPrivate = false } --Always visible within our own target.

			targetModules[provide.LogicalName] = {}
			local moduleInfo = targetModules[provide.LogicalName]
			moduleInfo["bmi"] = mod
			moduleInfo["is-private"] = false
		end
	end

	local moduleLocations = { RootDirectory = "", BMILocationForModule = nil }
	moduleLocations.RootDirectory = "."
	moduleLocations.BMILocationForModule = function(modFiles, logicalName)
		local m = modFiles[logicalName]
		if m then
			return m.BMIPath
		end

		return nil
	end

	--Insert information about the current target's modules.
	if modmapfmt then
		local cycleModules = moduleUsageSeed(modFiles, moduleLocations, objects, usages)
		if cycleModules then
			printError("Circular dependency detected in the C++ module import graph. See modules names: \"" .. table.concat(cycleModules, "\", \"") .. "\"")
			os.exit(1)
		end
	end

	--TODO

	local NinjaDynDepFile = generateNinjaDynDepFile()
	printDebug(NinjaDynDepFile)
	io.writefile(dd, NinjaDynDepFile)
end

include("_preload.lua")

return collate_modules
