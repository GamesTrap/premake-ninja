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
local modDeps = {}

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

local function ConvertToNinjaPath(path)
	return path
end

local function ModuleLocations_PathForGenerator(path)
	return ConvertToNinjaPath(path)
end

local function ModuleLocations_BMILocationForModule(modFiles, logicalName)
	local m = modFiles[logicalName]
	if m then
		return m.BMIPath
	end

	return nil
end

local function ModuleLocations_BMIGeneratorPathForModule(modFiles, moduleLocations, logicalName)
	local bmiLoc = ModuleLocations_BMILocationForModule(modFiles, logicalName)
	if bmiLoc then
		return ModuleLocations_PathForGenerator(bmiLoc)
	end

	return bmiLoc
end

local function Usages_AddReference(usages, logicalName, loc, lookupMethod)
	if usages.Reference[logicalName] then
		local r = usages.Reference[logicalName]

		if r.Path == loc and r.Method == lookupMethod then
			return true
		end

		printError("Disagreement of the location of the '" .. logicalName .. "' module. Location A: '" ..
		           r.Path .. "' via " .. r.Method .. "; Location B: '" .. loc .. "' via " .. lookupMethod .. ".")
		return false
	end

	usages.Reference[logicalName] =
	{
		Path = "",
		Method = LookupMethod.ByName
	}
	local ref = usages.Reference[logicalName]
	ref.Path = loc
	ref.Method = lookupMethod
end

local function moduleUsageSeed(modFiles, moduleLocations, objects, usages)
	local internalUsages = {}
	local unresolved = {}

	for _, object in pairs(objects) do
		--Add references for each of the provided modules.
		for _1, provide in pairs(object.Provides) do
			local bmiLoc = ModuleLocations_BMIGeneratorPathForModule(modFiles, moduleLocations, provide.LogicalName)
			if bmiLoc then
				Usages_AddReference(usages, provide.LogicalName, bmiLoc, LookupMethod.ByName)
			end
		end

		--For each requires, pull in what is required.
		for _1, require in pairs(object.Requires) do
			--Find the required name in the current target.
			local bmiLoc = ModuleLocations_BMIGeneratorPathForModule(modFiles, moduleLocations, require.LogicalName)

			--Find transitive usages.
			local transitiveUsages = usages.Usage[require.LogicalName]

			for _2, provide in pairs(object.Provides) do
				if not usages.Usage[provide.LogicalName] then
					usages.Usage[provide.LogicalName] = {}
				end
				local thisUsages = usages.Usage[provide.LogicalName]

				--Add the direct usage.
				thisUsages[require.LogicalName] = 1

				if not transitiveUsages or internalUsages[require.LogicalName] then
					--Mark that we need to update transitive usages later.
					if bmiLoc then
						if not internalUsages[provide.LogicalName] then
							internalUsages[provide.LogicalName] = {}
						end
						internalUsages[provide.LogicalName][require.LogicalName] = 1
					end
				else
					--Add the transitive usage.
					for tu, _3 in pairs(transitiveUsages) do
						thisUsages[tu] = 1
					end
				end
			end

			if bmiLoc then
				Usages_AddReference(usages, require.LogicalName, bmiLoc, require.Method)
			end
		end
	end

	--While we have internal usages to manage.
	while next(internalUsages) do
		local startingSize = #internalUsages

		--For each internal usage.
		for f, s in pairs(internalUsages) do
			local thisUsages = usages.Usage[f]

			for f1, s2 in pairs(s) do
				--Check if this required module uses other internal modules; defer if so.
				if internalUsages[f1] then
					goto continueUse
				end

				local transitiveUsages = usages.Usage[f1]
				if transitiveUsages then
					for transitiveUsage, _ in pairs(transitiveUsages) do
						thisUsages[transitiveUsage] = 1
					end
				end

				s[f1] = nil

				::continueUse::
			end

			--Erase the entry if it doesn't have any remaining usages.
			if #s == 0 then
				internalUsages[f] = nil
			end
		end

		--Check that at least one usage was resolved.
		if startingSize == #internalUsages then
			--Nothing could be resolved this loop; we have a cycle, so record the cycle and exit.
			for f, s in pairs(internalUsages) do
				if not table.contains(unresolved, f) then
					table.insert(unresolved, f)
				end
			end
			break
		end
	end

	return unresolved
end

local function Ninja_WriteBuild(ninjaBuild)
	local result = ""

	--Make sure there is a rule.
	if ninjaBuild.Rule == "" then
		printError("No rule for Ninja_WriteBuild! called with comment: " .. ninjaBuild.Comment)
		os.exit(1)
	end

	--Make sure there is at least one output file.
	if #ninjaBuild.Outputs == 0 then
		printError("No output files for Ninja_WriteBuild! called with comment: " .. ninjaBuild.Comment)
		os.exit(1)
	end
	local buildStr = ""

	if ninjaBuild.Comment ~= "" then
		result = result .. ninjaBuild.Comment .. "\n"
	end

	--Write output files.
	buildStr = buildStr .. "build"

	--Write explicit outputs
	for _, output in pairs(ninjaBuild.Outputs) do
		buildStr = buildStr .. " " .. output
		-- if ComputingUnknownDependencies then
		-- 	--TODO
		-- end
	end

	--Write implicit outputs
	if #ninjaBuild.ImplicitOuts > 0 then
		--Assume Ninja is new enough to support implicit outputs.
		--Callers should not populate this field otherwise.
		buildStr = buildStr .. " |"
		for _, implicitOut in pairs(ninjaBuild.ImplicitOuts) do
			buildStr = buildStr .. " " .. implicitOut
			-- if ComputingUnknownDependencies then
			-- 	--TODO
			-- end
		end
	end

	--Repeat some outputs, but expressed as absolute paths.
	--This helps Ninja handle absolute paths found in a depfile.
	--FIXME: Unfortunately this causes Ninja to stat the file twice.
	--We could avoid this if Ninja Issue #1251 were fixed.
	if #ninjaBuild.WorkDirOuts > 0 then
		if SupportsImplicitOuts() and #ninjaBuild.ImplicitOuts == 0 then
			--Make them implicit outputs if supported by this version of Ninja.
			buildStr = buildStr .. " |"
		end

		for _, workDirOut in pairs(ninjaBuild.WorkDirOuts) do
			buildStr = buildStr .. " " .. workDirOut
		end
	end

	--Write the rule.
	buildStr = buildStr .. ": " .. ninjaBuild.Rule

	local arguments = ""

	--TODO: Better formatting for when there are multiple input/output files.

	--Write explicit dependencies.
	for _, explicitDep in pairs(ninjaBuild.ExplicitDeps) do
		arguments = arguments .. " " .. explicitDep
	end

	--Write implicit dependencies.
	if #ninjaBuild.ImplicitDeps > 0 then
		arguments = arguments .. " |"
		for _, implicitDep in pairs(ninjaBuild.ImplicitDeps) do
			arguments = arguments .. " " .. implicitDep
		end
	end

	--Write oder-only dependencies.
	if #ninjaBuild.OrderOnlyDeps > 0 then
		arguments = arguments .. " ||"
		for _, orderOnlyDep in pairs(ninjaBuild.OrderOnlyDeps) do
			arguments = arguments .. " " .. orderOnlyDep
		end
	end

	arguments = arguments .. "\n"

	--Write the variables bound to this build statement.
	local assignments = ""
	for variable, value in pairs(ninjaBuild.Variables) do
		assignments = assignments .. "    " .. variable .. " = " .. value .. "\n"
	end

	--Check if a response file rule should be used
	local useResponseFile = false
	--TODO

	return buildStr .. arguments .. assignments .. "\n"
end

local function GetTransitiveUsages(modFiles, locs, required, usages)
	local transitiveUsageDirects = {}
	local transitiveUsageNames = {}

	local allUsages = {}

	for _, r in pairs(required) do
		local bmiLoc = ModuleLocations_BMIGeneratorPathForModule(modFiles, locs, r.LogicalName)
		if bmiLoc then
			table.insert(allUsages, {LogicalName = r.LogicalName, Location = bmiLoc, Method = r.Method})
			if not table.contains(transitiveUsageDirects, r.LogicalName) then
				table.insert(transitiveUsageDirects, r.LogicalName)
			end

			--Insert transitive usages.
			local transitiveUsages = usages.Usage[r.LogicalName]
			if transitiveUsages then
				for _1, tu in pairs(transitiveUsages) do
					if not table.contains(transitiveUsageNames, tu) then
						table.insert(transitiveUsageNames, tu)
					end
				end
			end
		end
	end

	for _, transitiveName in pairs(transitiveUsageNames) do
		if not table.contains(transitiveUsageDirects, transitiveName) then
			local moduleRef = usages.Reference[transitiveName]
			if moduleRef then
				table.insert(allUsages, {LogicalName = transitiveName, Location = moduleRef.Path, Method = moduleRef.Method})
			end
		end
	end

	return allUsages
end

local function ModuleMapContentClang(modFiles, locs, object, usages)
	local mm = ""

	--Clang's command line only supports a single output.
	--If more than one is expected, we cannot make a useful module map file.
	if #object.Provides > 1 then
		return ""
	end

	--A series of flags which tell the compiler where to look for modules.

	for _, provide in pairs(object.Provides) do
		local bmiLoc = ModuleLocations_BMIGeneratorPathForModule(modFiles, locs, provide.LogicalName)
		if bmiLoc then
			--Force the TU to be considered a C++ module source file regardless of extension.
			mm = mm .. "-x c++-module\n"

			mm = mm .. "-fmodule-output=" .. bmiLoc .. "\n"
			break
		end
	end

	local allUsages = GetTransitiveUsages(modFiles, locs, object.Requires, usages)
	for _, usage in pairs(allUsages) do
		mm = mm .. "-fmodule-file=" .. usage.LogicalName .. "=" .. usage.Location .. "\n"
	end

	return mm
end

local function ModuleMapContentGCC(modFiles, locs, object, usages)
	local mm = ""

	--Documented in GCC's documentation.
	--The format is a series of lines with a module name and the associated
	--filename separated by spaces. The first line may use '$root' as the module
	--name to specify a "repository root".
	--That is used to anchor any relative paths present in the file
	--(Premake-Ninja should never generate any).

	--Write the root directory to use for module paths.
	mm = mm .. "$root " .. locs.RootDirectory .. "\n"

	for _, provide in pairs(object.Provides) do
		local bmiLoc = ModuleLocations_BMIGeneratorPathForModule(modFiles, locs, provide.LogicalName)
		if bmiLoc then
			mm = mm .. provide.LogicalName .. " " .. bmiLoc .. "\n"
		end
	end
	for _, require in pairs(object.Requires) do
		local bmiLoc = ModuleLocations_BMIGeneratorPathForModule(modFiles, locs, require.LogicalName)
		if bmiLoc then
			mm = mm .. require.LogicalName .. " " .. bmiLoc .. "\n"
		end
	end

	return mm
end

local function ModuleMapContentMSVC(modFiles, locs, object, usages)
	local mm = ""

	--A response file of '-reference NAME=PATH' arguments.

	--MSVC's command line only supports a single output.
	--If more than one is expected, we cannot make a useful module map file.
	if #object.Provides > 1 then
		return ""
	end

	local function flagForMethod(method)
		if method == LookupMethod.ByName then
			return "-reference"
		elseif method == LookupMethod.IncludeAngle then
			return "-headerUnit:angle"
		elseif method == LookupMethod.IncludeQuote then
			return "-headerUnit:quote"
		else
			printError("Unsupported lookup method")
			os.exit(1)
		end
	end

	for _, provide in pairs(object.Provides) do
		if provide.IsInterface then
			mm = mm .. "-interface\n"
		else
			mm = mm .. "-internalPartition\n"
		end

		local bmiLoc = ModuleLocations_BMIGeneratorPathForModule(modFiles, locs, provide.LogicalName)
		if bmiLoc then
			mm = mm .. "-ifcOutput " .. bmiLoc .. "\n"
		end
	end

	local allUsages = GetTransitiveUsages(modFiles, locs, object.Requires, usages)
	for _, usage in pairs(allUsages) do
		local flag = flagForMethod(usage.Method)

		mm = mm .. flag .. " " .. usage.LogicalName .. "=" .. usage.Location .. "\n"
	end

	return mm
end

local function ModuleMapContent(modmapfmt, modFiles, locs, object, usages)
	if modmapfmt == "clang" then
		return ModuleMapContentClang(modFiles, locs, object, usages)
	elseif modmapfmt == "gcc" then
		return ModuleMapContentGCC(modFiles, locs, object, usages)
	elseif modmapfmt == "msvc" then
		return ModuleMapContentMSVC(modFiles, locs, object, usages)
	end

	printError("Unknown modmapfmt: " .. modmapfmt)
	os.exit(1)
end

local function LoadModuleDependencies(modDeps, modFiles, usages)
	if _OPTIONS["deps"] == nil or _OPTIONS["deps"] == "" then
		return
	end

	for i = 1, #modDeps do
		local modDepFile = modDeps[i]

		local modDep = io.readfile(modDepFile)
		if not modDep or modDep == "" then
			printError("Failed to open \"" .. modDepFile .. "\" for module information")
			os.exit(1)
		end

		local modDepData, error = json.decode(modDep)
		if not modDepData or error then
			printError("Failed to parse \"" .. modDepFile .. "\" (" .. error .. ")")
			os.exit(1)
		end

		if modDepData == nil then
			return
		end

		local targetModules = modDepData["modules"]
		if targetModules then
			for moduleName, moduleData in pairs(targetModules) do
				local bmiPath = moduleData["bmi"]
				local isPrivate = moduleData["is-private"]
				modFiles[moduleName] = { BMIPath = bmiPath, IsPrivate = isPrivate }
			end
		end

		local targetModulesReferences = modDepData["references"]
		if targetModulesReferences then
			for moduleName, moduleData in pairs(targetModulesReferences) do
				local moduleReference =
				{
					Path = "",
					Method = LookupMethod.ByName
				}

				local referencePath = moduleData["path"]
				if referencePath then
					moduleReference.Path = referencePath
				end

				local referenceMethod = moduleData["lookup-method"]
				if referenceMethod then
					if referenceMethod == "by-name" or referenceMethod == "include-angle" or referenceMethod == "include-quote" then
						moduleReference.Method = referenceMethod
					else
						printError("Unknown lookup method \"" .. referenceMethod .. "\"")
						os.exit(1)
					end
				end

				usages.Reference[moduleName] = moduleReference
			end
		end

		local targetModulesUsage = modDepData["usages"]
		if targetModulesUsage then
			for moduleName, modules in pairs(targetModulesUsage) do
				for i = 1, #modules do
					if not usages.Usage[moduleName] then
						usages.Usage[moduleName] = {}
					end

					table.insert(usages.Usage[moduleName], modules[i])
				end
			end
		end
	end
end

function collate_modules.CollateModules()
	if not validateInput() then
		os.exit(1)
	end

	local moduleDir = path.getdirectory(dd)

	local ddis = iif(#_OPTIONS["ddi"] > 0, string.explode(_OPTIONS["ddi"], " "), {})

	local modDeps = iif(#_OPTIONS["deps"] > 0, string.explode(_OPTIONS["deps"], " "), {})

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

	local modFiles = {}
	local targetModules = {}

	LoadModuleDependencies(modDeps, modFiles, usages)

	--Map from module name to module file path, if known.
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

	local moduleLocations = { RootDirectory = "." }

	--Insert information about the current target's modules.
	if modmapfmt then
		local cycleModules = moduleUsageSeed(modFiles, moduleLocations, objects, usages)
		if #cycleModules ~= 0 then
			printError("Circular dependency detected in the C++ module import graph. See modules named: \"" .. table.concat(cycleModules, "\", \"") .. "\"")
			os.exit(1)
		end
	end

	--Create modmap and dyndep files

	local dynDepStr = "ninja_dyndep_version = 1.0\n"

	local ninjaBuild =
	{
		Comment = "",
		Rule = "dyndep",
		Outputs = {},
		ImplicitOuts = {},
		WorkDirOuts = {},
		ExplicitDeps = {},
		ImplicitDeps = {},
		OrderOnlyDeps = {},
		Variables = {},
		RspFile = ""
	}
	table.insert(ninjaBuild.Outputs, "")
	for _, object in pairs(objects) do
		ninjaBuild.Outputs[1] = object.PrimaryOutput
		ninjaBuild.ImplicitOuts = {}
		for _1, provide in pairs(object.Provides) do
			local implicitOut = modFiles[provide.LogicalName].BMIPath
			--Ignore the 'provides' when the BMI is the output.
			if implicitOut ~= ninjaBuild.Outputs[1] then
				table.insert(ninjaBuild.ImplicitOuts, implicitOut)
			end
		end
		ninjaBuild.ImplicitDeps = {}
		for _1, require in pairs(object.Requires) do
			local mit = modFiles[require.LogicalName]
			if mit then
				table.insert(ninjaBuild.ImplicitDeps, mit.BMIPath)
			end
		end
		ninjaBuild.Variables = {}
		if #object.Provides > 0 then
			ninjaBuild.Variables["restat"] = "1"
		end

		if modmapfmt then
			local mm = ModuleMapContent(modmapfmt, modFiles, moduleLocations, object, usages)
			io.writefile(object.PrimaryOutput .. ".modmap", mm)
		end

		dynDepStr = dynDepStr .. Ninja_WriteBuild(ninjaBuild)
	end

	io.writefile(dd, dynDepStr)

	--Create CXXModules.json

	local targetModsFilepath = path.join(path.getdirectory(dd), "CXXModules.json")
	local targetModuleInfo = {}
	targetModuleInfo["modules"] = targetModules

	targetModuleInfo["usages"] = {}
	local targetUsages = targetModuleInfo["usages"]
	for moduleName, moduleUsages in pairs(usages.Usage) do
		targetUsages[moduleName] = {}
		local modUsage = targetUsages[moduleName]
		for modules, _ in pairs(moduleUsages) do
			table.insert(modUsage, modules)
		end
	end

	targetModuleInfo["references"] = {}
	local targetReferences = targetModuleInfo["references"]
	for moduleName, reference in pairs(usages.Reference) do
		targetReferences[moduleName] = {}
		local modRef = targetReferences[moduleName]
		modRef["path"] = reference.Path
		modRef["lookup-method"] = reference.Method
	end

	io.writefile(targetModsFilepath, json.encode(targetModuleInfo))
end

include("_preload.lua")

return collate_modules
