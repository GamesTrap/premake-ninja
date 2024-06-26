--
-- Name:        premake-ninja/ninja.lua
-- Purpose:     Define the ninja action.
-- Author:      Dmitry Ivanov
-- Created:     2015/07/04
-- Copyright:   (c) 2015 Dmitry Ivanov, (c) 2023 Jan "GamesTrap" Schürkamp
--

local p = premake
local tree = p.tree
local project = p.project
local config = p.config
local fileconfig = p.fileconfig

-- Some toolset fixes/helper
p.tools.clang.objectextension = ".o"
p.tools.gcc.objectextension = ".o"
p.tools.msc.objectextension = ".obj"

p.tools.clang.tools.rc = p.tools.clang.tools.rc or "windres"

p.tools.msc.gettoolname = function(cfg, name)
	local map = {cc = "cl", cxx = "cl", ar = "lib", rc = "rc"}
	return map[name]
end

-- Ninja module
premake.modules.ninja = {}
local ninja = p.modules.ninja

local function get_key(cfg)
	if cfg.platform then
		return cfg.project.name .. "_" .. cfg.buildcfg .. "_" .. cfg.platform
	else
		return cfg.project.name .. "_" .. cfg.buildcfg
	end
end

local build_cache = {}

local function add_build(cfg, out, implicit_outputs, command, inputs, implicit_inputs, dependencies, vars)
	implicit_outputs = ninja.list(table.translate(implicit_outputs, ninja.esc))
	if #implicit_outputs > 0 then
		implicit_outputs = " |" .. implicit_outputs
	else
		implicit_outputs = ""
	end

	inputs = ninja.list(table.translate(inputs, ninja.esc))

	implicit_inputs = ninja.list(table.translate(implicit_inputs, ninja.esc))
	if #implicit_inputs > 0 then
		implicit_inputs = " |" .. implicit_inputs
	else
		implicit_inputs = ""
	end

	dependencies = ninja.list(table.translate(dependencies, ninja.esc))
	if #dependencies > 0 then
		dependencies = " ||" .. dependencies
	else
		dependencies = ""
	end
	build_line = "build " .. ninja.esc(out) .. implicit_outputs .. ": " .. command .. inputs .. implicit_inputs .. dependencies

	local cached = build_cache[out]
	if cached ~= nil then
		if build_line == cached.build_line
			and table.equals(vars or {}, cached.vars or {})
		then
			-- custom_command rule is identical for each configuration (contrary to other rules)
			-- So we can compare extra parameter
			if string.startswith(cached.command, "custom_command") then
				p.outln("# INFO: Rule ignored, same as " .. cached.cfg_key)
			else
				local cfg_key = get_key(cfg)
				p.warn(cached.cfg_key .. " and " .. cfg_key .. " both generate (differently?) " .. out .. ". Ignoring " .. cfg_key)
				p.outln("# WARNING: Rule ignored, using the one from " .. cached.cfg_key)
			end
		else
			local cfg_key = get_key(cfg)
			p.warn(cached.cfg_key .. " and " .. cfg_key .. " both generate differently " .. out .. ". Ignoring " .. cfg_key)
			p.outln("# ERROR: Rule ignored, using the one from " .. cached.cfg_key)
		end
		p.outln("# " .. build_line)
		for i, var in ipairs(vars or {}) do
			p.outln("#   " .. var)
		end
		return
	end
	p.outln(build_line)
	for i, var in ipairs(vars or {}) do
		p.outln("  " .. var)
	end
	build_cache[out] = {
		cfg_key = get_key(cfg),
		build_line = build_line,
		vars = vars
	}
end

function ninja.esc(value)
	value = value:gsub("%$", "$$") -- TODO maybe there is better way
	value = value:gsub(":", "$:")
	value = value:gsub("\n", "$\n")
	value = value:gsub(" ", "$ ")
	return value
end

function ninja.quote(value)
	value = value:gsub("\\", "\\\\")
	value = value:gsub("'", "\\'")
	value = value:gsub("\"", "\\\"")

	return "\"" .. value .. "\""
end

-- in some cases we write file names in rule commands directly
-- so we need to propely escape them
function ninja.shesc(value)
	if type(value) == "table" then
		local result = {}
		local n = #value
		for i = 1, n do
			table.insert(result, ninja.shesc(value[i]))
		end
		return result
	end

	if value:find(" ") then
		return ninja.quote(value)
	end
	return value
end

-- generate solution that will call ninja for projects
function ninja.generateWorkspace(wks)
	local oldGetDefaultSeparator = path.getDefaultSeparator
	path.getDefaultSeparator = function() return "/" end

	p.outln("# solution build file")
	p.outln("# generated with premake ninja")
	p.outln("")

	p.outln("# build projects")
	local cfgs = {} -- key is concatenated name or variant name, value is string of outputs names
	local key = ""
	local cfg_first = nil
	local cfg_first_lib = nil

	for prj in p.workspace.eachproject(wks) do
		if p.action.supports(prj.kind) and prj.kind ~= p.NONE then
			for cfg in p.project.eachconfig(prj) do
				key = get_key(cfg)

				if not cfgs[cfg.buildcfg] then cfgs[cfg.buildcfg] = {} end
				table.insert(cfgs[cfg.buildcfg], key)

				-- set first configuration name
				if (cfg_first_lib == nil) and (cfg.kind == p.STATICLIB or cfg.kind == p.SHAREDLIB) then
					cfg_first_lib = key
				end
				if (cfg_first == nil and (wks.startproject == nil or prj.name == wks.startproject)) then
					cfg_first = key
				end

				-- include other ninja file
				p.outln("subninja " .. ninja.esc(ninja.projectCfgFilename(cfg, true)))
			end
		end
	end

	if cfg_first == nil then cfg_first = cfg_first_lib end

	p.outln("")

	p.outln("# targets")
	for cfg, outputs in pairs(cfgs) do
		p.outln("build " .. ninja.esc(cfg) .. ": phony" .. ninja.list(table.translate(outputs, ninja.esc)))
	end
	p.outln("")

	p.outln("# default target")
	p.outln("default " .. ninja.esc(cfg_first))
	p.outln("")

	path.getDefaultSeparator = oldGetDefaultSeparator
end

function ninja.list(value)
	if #value > 0 then
		return " " .. table.concat(value, " ")
	else
		return ""
	end
end

local function shouldcompileasc(filecfg)
	if filecfg.compileas and filecfg.compileas ~= "Default" then
		return p.languages.isc(filecfg.compileas)
	end
	return path.iscfile(filecfg.abspath)
end

local function shouldcompileascpp(filecfg)
	if filecfg.compileas and filecfg.compileas ~= "Default" then
		return p.languages.iscpp(filecfg.compileas)
	end
	return path.iscppfile(filecfg.abspath)
end

local function getFileDependencies(cfg)
	local dependencies = {}
	if #cfg.prebuildcommands > 0 or cfg.prebuildmessage then
		dependencies = {"prebuild_" .. get_key(cfg)}
	end
	for i = 1, #cfg.dependson do
		table.insert(dependencies, cfg.dependson[i] .. "_" .. cfg.buildcfg)
	end
	return dependencies
end

ninja.MSVCCDialects =
{
	["C11"] = "/std:c11",
	["C17"] = "/std:c17"
}

ninja.MSVCCPPDialects =
{
	["C++14"] = "/std:c++14",
	["C++17"] = "/std:c++17",
	["C++20"] = "/std:c++20",
	["C++latest"] = "/std:c++latest"
}

local function getcflags(toolset, cfg, filecfg)
	local buildopt = ninja.list(filecfg.buildoptions)
	local cppflags = ninja.list(toolset.getcppflags(filecfg))
	local cflags = ninja.list(toolset.getcflags(filecfg)) --Note MSVC is missing the correct cdialect

	local MSVCcdialect = ""
	if toolset == p.tools.msc and ninja.MSVCCPPDialects[cfg.cppdialect] ~= nil then
		MSVCcdialect = " " .. ninja.MSVCCDialects[cfg.cdialect] .. " "
	end

	local defines = ninja.list(table.join(toolset.getdefines(filecfg.defines, filecfg), toolset.getundefines(filecfg.undefines)))
	-- Ninja requires that all files are relative to the build dir
		local tmpCfgProjectDir = cfg.project.location
		cfg.project.location = cfg.workspace.location
		local includes = ninja.list(toolset.getincludedirs(cfg, filecfg.includedirs, filecfg.externalincludedirs, filecfg.frameworkdirs, filecfg.includedirsafter))
		local forceincludes = ninja.list(toolset.getforceincludes(cfg))
		cfg.project.location = tmpCfgProjectDir

	return buildopt .. cppflags .. cflags .. MSVCcdialect .. defines .. includes .. forceincludes
end

local function getcxxflags(toolset, cfg, filecfg)
	local buildopt = ninja.list(filecfg.buildoptions)
	local cppflags = ninja.list(toolset.getcppflags(filecfg))
	local cxxflags = ninja.list(toolset.getcxxflags(filecfg)) --Note MSVC is missing the correct cppdialect

	local MSVCcppdialect = ""
	if toolset == p.tools.msc and ninja.MSVCCPPDialects[cfg.cppdialect] ~= nul then
		MSVCcppdialect = " " .. ninja.MSVCCPPDialects[cfg.cppdialect] .. " "
	end

	local defines = ninja.list(table.join(toolset.getdefines(filecfg.defines, filecfg), toolset.getundefines(filecfg.undefines)))
	-- Ninja requires that all files are relative to the build dir
		local tmpCfgProjectDir = cfg.project.location
		cfg.project.location = cfg.workspace.location
		local includes = ninja.list(toolset.getincludedirs(cfg, filecfg.includedirs, filecfg.externalincludedirs, filecfg.frameworkdirs, filecfg.includedirsafter))
		local forceincludes = ninja.list(toolset.getforceincludes(cfg))
		cfg.project.location = tmpCfgProjectDir
	return buildopt .. cppflags .. cxxflags .. MSVCcppdialect .. defines .. includes .. forceincludes
end

local function getldflags(toolset, cfg)
	-- Ninja requires that all files are relative to the build dir
		local tmpCfgProjectDir = cfg.project.location
		cfg.project.location = cfg.workspace.location
		local libdirs = toolset.getLibraryDirectories(cfg);
		cfg.project.location = tmpCfgProjectDir

	local ldflags = ninja.list(table.join(libdirs, toolset.getldflags(cfg), cfg.linkoptions))
	if cfg.runpathdirs then
		ldflags = ldflags .. ninja.list(table.join(toolset.getrunpathdirs(cfg, table.join(cfg.runpathdirs, p.config.getsiblingtargetdirs(cfg)))))
	end

	if toolset == p.tools.msc and cfg.entrypoint ~= nil then
		ldflags = ldflags .. " /ENTRY:" .. cfg.entrypoint
	end

	-- experimental feature, change install_name of shared libs
	--if (toolset == p.tools.clang) and (cfg.kind == p.SHAREDLIB) and ninja.endsWith(cfg.buildtarget.name, ".dylib") then
	--	ldflags = ldflags .. " -install_name " .. cfg.buildtarget.name
	--end
	return ldflags
end

local function getresflags(toolset, cfg, filecfg)
	local defines = ninja.list(toolset.getdefines(table.join(filecfg.defines, filecfg.resdefines), filecfg))
	-- Ninja requires that all files are relative to the build dir
		local tmpCfgProjectDir = cfg.project.location
		cfg.project.location = cfg.workspace.location
		local includes = ninja.list(toolset.getincludedirs(cfg, table.join(filecfg.externalincludedirs, filecfg.includedirsafter, filecfg.includedirs, filecfg.resincludedirs), {}, {}, {}))
		cfg.project.location = tmpCfgProjectDir
	local options = ninja.list(cfg.resoptions)

	return defines .. includes .. options
end

local function prebuild_rule(cfg)
	if #cfg.prebuildcommands > 0 or cfg.prebuildmessage then
		local commands = {}
		if cfg.prebuildmessage then
			commands = {os.translateCommandsAndPaths("{ECHO} " .. cfg.prebuildmessage, cfg.workspace.basedir, cfg.workspace.location)}
		end
		commands = table.join(commands, os.translateCommandsAndPaths(pretranslatePaths(cfg.prebuildcommands, cfg), cfg.workspace.basedir, cfg.workspace.location))
		if (#commands > 1) then
			if p.tools.canonical(cfg.toolset) == p.tools.msc then
				commands = 'cmd /c ' .. ninja.quote(table.implode(commands,"",""," && "))
			else
				commands = 'sh -c ' .. ninja.quote(table.implode(commands,"","",";"))
			end
		else
			commands = commands[1]
		end
		p.outln("rule run_prebuild")
		p.outln("  command = " .. commands)
		p.outln("  description = prebuild")
		p.outln("")
	end
end

local function prelink_rule(cfg)
	if #cfg.prelinkcommands > 0 or cfg.prelinkmessage then
		local commands = {}
		if cfg.prelinkmessage then
			commands = {os.translateCommandsAndPaths("{ECHO} " .. cfg.prelinkmessage, cfg.workspace.basedir, cfg.workspace.location)}
		end
		commands = table.join(commands, os.translateCommandsAndPaths(pretranslatePaths(cfg.prelinkcommands, cfg), cfg.workspace.basedir, cfg.workspace.location))
		if (#commands > 1) then
			if p.tools.canonical(cfg.toolset) == p.tools.msc then
				commands = 'cmd /c ' .. ninja.quote(table.implode(commands,"",""," && "))
			else
				commands = 'sh -c ' .. ninja.quote(table.implode(commands,"","",";"))
			end
		else
			commands = commands[1]
		end
		p.outln("rule run_prelink")
		p.outln("  command = " .. commands)
		p.outln("  description = prelink")
		p.outln("")
	end
end

local function stringReplace(str, match, replacement)
	local function regexEscape(str)
		return str:gsub("[%(%)%.%%%+%-%*%?%[%^%$%]]", "%%%1")
	end

	return str:gsub(regexEscape(match), replacement:gsub("%%", "%%%%"))
end

local strMagic = "([%^%$%(%)%%%.%[%]%*%+%-%?])" -- UTF-8 replacement for "(%W)"

-- Hide magic pattern symbols  ^ $ ( ) % . [ ] * + - ?
local function stringPlain(strTxt)
	-- Prefix every magic pattern character with a % escape character,
	-- where %% is the % escape, and %1 is the original character capture.
	strTxt = tostring(strTxt or ""):gsub(strMagic,"%%%1")
	return strTxt
end

-- replace is plain text version of string.gsub()
local function stringReplace(strTxt,strOld,strNew,intNum)
	strOld = tostring(strOld or ""):gsub(strMagic,"%%%1")  -- Hide magic pattern symbols
	return tostring(strTxt or ""):gsub(strOld,function() return strNew end,tonumber(intNum))  -- Hide % capture symbols
end

local function pretranslatePaths(cmds, cfg)
	for i = 1, #cmds do
		local cmdCopy = cmds[i]

		for v in string.gmatch(cmds[i], "%.%./[%w-._/\\]+") do
			local correctedPath = path.getabsolute(v, cfg.project.location)
			correctedPath = path.getrelative(cfg.workspace.location, correctedPath)

			cmdCopy = stringReplace(cmdCopy, v, correctedPath, 1) --Replace path with path based on build dir
		end

		cmds[i] = cmdCopy
	end

	return cmds
end

local function postbuild_rule(cfg)
	if #cfg.postbuildcommands > 0 or cfg.postbuildmessage then
		local commands = {}
		if cfg.postbuildmessage then
			commands = {os.translateCommandsAndPaths("{ECHO} " .. cfg.postbuildmessage, cfg.workspace.basedir, cfg.workspace.location)}
		end
		commands = table.join(commands, os.translateCommandsAndPaths(pretranslatePaths(cfg.postbuildcommands, cfg), cfg.workspace.basedir, cfg.workspace.location))
		if (#commands > 1) then
			if p.tools.canonical(cfg.toolset) == p.tools.msc then
				commands = 'cmd /c ' .. ninja.quote(table.implode(commands,"",""," && "))
			else
				commands = 'sh -c ' .. ninja.quote(table.implode(commands,"","",";"))
			end
		else
			commands = commands[1]
		end
		p.outln("rule run_postbuild")
		p.outln("  command = " .. commands)
		p.outln("  description = postbuild")
		p.outln("")
	end
end

local function compilation_rules(cfg, toolset, pch)
	---------------------------------------------------- figure out toolset executables
	local cc = toolset.gettoolname(cfg, "cc")
	local cxx = toolset.gettoolname(cfg, "cxx")
	local ar = toolset.gettoolname(cfg, "ar")
	local link = toolset.gettoolname(cfg, iif(cfg.language == "C", "cc", "cxx"))
	local rc = toolset.gettoolname(cfg, "rc")

	local all_cflags = getcflags(toolset, cfg, cfg)
	local all_cxxflags = getcxxflags(toolset, cfg, cfg)
	local all_ldflags = getldflags(toolset, cfg)
	local all_resflags = getresflags(toolset, cfg, cfg)

	if toolset == p.tools.msc then
		local force_include_pch = ""
		if pch then
			force_include_pch = " /Yu" .. ninja.shesc(path.getname(pch.input)) .. " /Fp" .. ninja.shesc(pch.pch)
			p.outln("rule build_pch")
			p.outln("  command = " .. iif(cfg.language == "C", cc .. all_cflags, cxx .. all_cxxflags) .. " /Yc"  .. ninja.shesc(path.getname(pch.input)) .. " /Fp" .. ninja.shesc(pch.pch) .. " /nologo /showIncludes -c /Tp$in /Fo$out")
			p.outln("  description = build_pch $out")
			p.outln("  deps = msvc")
			p.outln("")
		end

		p.outln("CFLAGS=" .. all_cflags)
		p.outln("rule cc")
		p.outln("  command = " .. cc .. " $CFLAGS" .. force_include_pch .. " /nologo /showIncludes -c /Tc$in /Fo$out")
		p.outln("  description = cc $out")
		p.outln("  deps = msvc")
		p.outln("")
		p.outln("CXXFLAGS=" .. all_cxxflags)
		p.outln("rule cxx")
		p.outln("  command = " .. cxx .. " $CXXFLAGS" .. force_include_pch .. " /nologo /showIncludes -c /Tp$in /Fo$out")
		p.outln("  description = cxx $out")
		p.outln("  deps = msvc")
		p.outln("")
		p.outln("rule cxx_module")
		p.outln("  command = " .. cxx .. " $CXXFLAGS" .. force_include_pch .. " /nologo /showIncludes @$DYNDEP_MODULE_MAP_FILE /FS -c /Tp$in /Fo$out")
		p.outln("  description = cxx_module $out")
		p.outln("  deps = msvc")
		p.outln("")
		p.outln("RESFLAGS = " .. all_resflags)
		p.outln("rule rc")
		p.outln("  command = " .. rc .. " /nologo /fo$out $in $RESFLAGS")
		p.outln("  description = rc $out")
		p.outln("")
		if cfg.kind == p.STATICLIB then
			p.outln("rule ar")
			p.outln("  command = " .. ar .. " $in /nologo -OUT:$out")
			p.outln("  description = ar $out")
			p.outln("")
		else
			p.outln("rule link")
			p.outln("  command = " .. link .. " $in" .. ninja.list(ninja.shesc(pretranslatePaths(toolset.getlinks(cfg, true), cfg))) .. " /link" .. all_ldflags .. " /nologo /out:$out")
			p.outln("  description = link $out")
			p.outln("")
		end
	elseif toolset == p.tools.clang or toolset == p.tools.gcc then
		local force_include_pch = ""
		if pch then
			force_include_pch = " -include " .. ninja.shesc(pch.placeholder)
			p.outln("rule build_pch")
			p.outln("  command = " .. iif(cfg.language == "C", cc .. all_cflags .. " -x c-header", cxx .. all_cxxflags .. " -x c++-header")  .. " -MF $out.d -c -o $out $in")
			p.outln("  description = build_pch $out")
			p.outln("  depfile = $out.d")
			p.outln("  deps = gcc")
		end
		p.outln("CFLAGS=" .. all_cflags)
		p.outln("rule cc")
		p.outln("  command = " .. cc .. " $CFLAGS" .. force_include_pch .. " -x c -MF $out.d -c -o $out $in")
		p.outln("  description = cc $out")
		p.outln("  depfile = $out.d")
		p.outln("  deps = gcc")
		p.outln("")
		p.outln("CXXFLAGS=" .. all_cxxflags)
		p.outln("rule cxx")
		p.outln("  command = " .. cxx .. " $CXXFLAGS" .. force_include_pch .. " -x c++ -MF $out.d -c -o $out $in")
		p.outln("  description = cxx $out")
		p.outln("  depfile = $out.d")
		p.outln("  deps = gcc")
		p.outln("")
		p.outln("rule cxx_module")
		if toolset == p.tools.gcc then
			p.outln("  command = " .. cxx .. " $CXXFLAGS " .. "-fmodules-ts -fmodule-mapper=$DYNDEP_MODULE_MAP_FILE -fdeps-format=p1689r5 -x c++ " .. force_include_pch .. " -MT $out -MF $out.d -c -o $out $in")
		else
			p.outln("  command = " .. cxx .. " $CXXFLAGS" .. force_include_pch .. " -MT $out -MF $out.d @$DYNDEP_MODULE_MAP_FILE -c -o $out $in")
		end
		p.outln("  description = cxx_module $out")
		p.outln("  depfile = $out.d")
		p.outln("  deps = gcc")
		p.outln("")
		p.outln("RESFLAGS = " .. all_resflags)
		p.outln("rule rc")
		p.outln("  command = " .. rc .. " -i $in -o $out $RESFLAGS")
		p.outln("  description = rc $out")
		p.outln("")
		if cfg.kind == p.STATICLIB then
			p.outln("rule ar")
			p.outln("  command = " .. ar .. " rcs $out $in")
			p.outln("  description = ar $out")
			p.outln("")
		else
			local groups = iif(cfg.linkgroups == premake.ON, {"-Wl,--start-group ", " -Wl,--end-group"}, {"", ""})
			p.outln("rule link")
			p.outln("  command = " .. link .. " -o $out " .. groups[1] .. "$in" .. ninja.list(ninja.shesc(pretranslatePaths(toolset.getlinks(cfg, true, true), cfg))) .. all_ldflags .. groups[2])
			p.outln("  description = link $out")
			p.outln("")
		end
	end
end

local function custom_command_rule()
	p.outln("rule custom_command")
	p.outln("  command = $CUSTOM_COMMAND")
	p.outln("  description = $CUSTOM_DESCRIPTION")
	p.outln("")
end

local function get_module_scanner_name(toolset, toolsetVersion, cfg)
	local scannerName = nil

	if toolset == p.tools.clang then
		scannerName = "clang-scan-deps"
		if toolsetVersion then
			scannerName = scannerName .. "-" .. toolsetVersion
		end
	elseif toolset == p.tools.gcc or toolset == p.tools.msc then
		scannerName = toolset.gettoolname(cfg, "cxx")
	end

	return scannerName
end

local function module_scan_rule(cfg, toolset)
	local cmd = ""

	local scannerName = get_module_scanner_name(toolset, toolsetVersion, cfg)

	if toolset == p.tools.clang then
		local _, toolsetVersion = p.tools.canonical(cfg.toolset)
		local compilerName = toolset.gettoolname(cfg, "cxx")

		libcppPath, libcppError = os.outputof(compilerName .. " -print-resource-dir")
		if libcppError ~= 0 then
			term.setTextColor(term.errorColor)
			print("Failed to find path to system headers!")
			term.setTextColor(term.warningColor)
			print("Using automatic system header discovery, this may use incorrect paths")
			term.setTextColor(nil)
			libcppPath = ""
		else
			libcppPath = " -resource-dir " .. libcppPath .. " "
		end

		cmd = scannerName .. " -format=p1689 -- " .. compilerName .. libcppPath .. " $CXXFLAGS -x c++ $in -c -o $OBJ_FILE -MT $DYNDEP_INTERMEDIATE_FILE -MD -MF $DEP_FILE > $DYNDEP_INTERMEDIATE_FILE.tmp && mv $DYNDEP_INTERMEDIATE_FILE.tmp $DYNDEP_INTERMEDIATE_FILE"
	elseif toolset == p.tools.gcc then
		cmd = scannerName .. " $CXXFLAGS -E -x c++ $in -MT $DYNDEP_INTERMEDIATE_FILE -MD -MF $DEP_FILE -fmodules-ts -fdeps-file=$DYNDEP_INTERMEDIATE_FILE -fdeps-target=$OBJ_FILE -fdeps-format=p1689r5 -o $PREPROCESSED_OUTPUT_FILE"
	elseif toolset == p.tools.msc then
		cmd = scannerName .. " $CXXFLAGS $in -nologo -TP -showIncludes -scanDependencies $DYNDEP_INTERMEDIATE_FILE -Fo$OBJ_FILE"
	else
		term.setTextColor(term.errorColor)
		print("C++20 Modules are only supported with Clang, GCC and MSC!")
		term.setTextColor(nil)
		os.exit()
	end

	p.outln("rule __module_scan")
	if toolset == p.tools.msc then
		p.outln("  deps = msvc")
	else
		p.outln("  depfile = $DEP_FILE")
	end
	p.outln("  command = " .. cmd)
	p.outln("  description = Scanning $in for C++ dependencies")
	p.outln("")
end

local collateModuleScript = nil

local function module_collate_rule(cfg, toolset)
	if not collateModuleScript then
		local collateModuleScripts = os.matchfiles(_MAIN_SCRIPT_DIR .. "/.modules/**/collate_modules/collate_modules.lua")
		if collateModuleScripts == nil or collateModuleScripts[1] == nil then
			term.setTextColor(term.errorColor)
			print("Unable to find collate_modules.lua script!")
			term.setTextColor(nil)
			os.exit()
		else
			collateModuleScript = collateModuleScripts[1]
		end
	end

	local cmd = _PREMAKE_COMMAND .. " --file=" .. collateModuleScript .. " collate_modules "

	if toolset == p.tools.clang then
		cmd = cmd .. "--modmapfmt=clang "
	elseif toolset == p.tools.gcc then
		cmd = cmd .. "--modmapfmt=gcc "
	elseif toolset == p.tools.msc then
		cmd = cmd .. "--modmapfmt=msvc "
	else
		term.setTextColor(term.errorColor)
		print("C++20 Modules are only supported with Clang, GCC and MSC!")
		term.setTextColor(nil)
		os.exit()
	end

	cmd = cmd .. "--dd=$out --ddi=\"$in\" --deps=$MODULE_DEPS @$out.rsp"

	p.outln("rule __module_collate")
	p.outln("  command = " .. cmd)
	p.outln("  description = Generating C++ dyndep file $out")
	p.outln("  rspfile = $out.rsp")
	p.outln("  rspfile_content = $in")
	p.outln("")
end

local function collect_generated_files(prj, cfg)
	local generated_files = {}
	tree.traverse(project.getsourcetree(prj), {
	onleaf = function(node, depth)
		function append_to_generated_files(filecfg)
			local outputs = project.getrelative(prj.workspace, filecfg.buildoutputs)
			generated_files = table.join(generated_files, outputs)
		end
		local filecfg = fileconfig.getconfig(node, cfg)
		if not filecfg or filecfg.flags.ExcludeFromBuild then
			return
		end
		local rule = p.global.getRuleForFile(node.name, prj.rules)
		if fileconfig.hasCustomBuildRule(filecfg) then
			append_to_generated_files(filecfg)
		elseif rule then
			local environ = table.shallowcopy(filecfg.environ)

			if rule.propertydefinition then
				p.rule.prepareEnvironment(rule, environ, cfg)
				p.rule.prepareEnvironment(rule, environ, filecfg)
			end
			local rulecfg = p.context.extent(rule, environ)
			append_to_generated_files(rulecfg)
		end
	end,
	}, false, 1)
	return generated_files
end

local function is_module_file(file)
	local fileEnding = path.getextension(file)

	if _OPTIONS["experimental-modules-scan-all"] and path.iscppfile(file) then
		return true
	end

	if fileEnding == ".cxx" or fileEnding == ".cxxm" or fileEnding == ".ixx" or
	   fileEnding == ".cppm" or fileEnding == ".c++m" or fileEnding == ".ccm" or
	   fileEnding == ".mpp" then
		return true
	end

	return false
end

local function pch_build(cfg, pch, toolset)
	local pch_dependency = {}
	if pch then
		if toolset == p.tools.msc then
			pch_dependency = { pch.pch }

			local obj_dir = project.getrelative(cfg.workspace, cfg.objdir)
			local pchObj = obj_dir .. "/" .. path.getname(pch.inputSrc) .. (toolset.objectextension or ".o")

			add_build(cfg, pchObj, pch_dependency, "build_pch", {pch.inputSrc}, {}, {}, {})
		else
			pch_dependency = { pch.gch }
			add_build(cfg, pch.gch, {}, "build_pch", {pch.input}, {}, {}, {})
		end
	end
	return pch_dependency
end

local function custom_command_build(prj, cfg, filecfg, filename, file_dependencies)
	local outputs = project.getrelative(prj.workspace, filecfg.buildoutputs)
	local output = outputs[1]
	table.remove(outputs, 1)
	local commands = {}
	if filecfg.buildmessage then
		commands = {os.translateCommandsAndPaths("{ECHO} " .. filecfg.buildmessage, prj.workspace.basedir, prj.workspace.location)}
	end
	commands = table.join(commands, os.translateCommandsAndPaths(pretranslatePaths(filecfg.buildcommands, cfg), prj.workspace.basedir, prj.workspace.location))
	if (#commands > 1) then
		if p.tools.canonical(cfg.toolset) == p.tools.msc then
			commands = 'cmd /c ' .. ninja.quote(table.implode(commands,"",""," && "))
		else
			commands = 'sh -c ' .. ninja.quote(table.implode(commands,"","",";"))
		end
	else
		commands = commands[1]
	end

	add_build(cfg, output, outputs, "custom_command", {filename}, filecfg.buildinputs, file_dependencies,
		{"CUSTOM_COMMAND = " .. commands, "CUSTOM_DESCRIPTION = custom build " .. ninja.shesc(output)})
end

local function compile_file_build(cfg, filecfg, toolset, pch_dependency, regular_file_dependencies, objfiles)
	local obj_dir = project.getrelative(cfg.workspace, cfg.objdir)
	local filepath = project.getrelative(cfg.workspace, filecfg.abspath)
	local has_custom_settings = fileconfig.hasFileSettings(filecfg)

	if shouldcompileasc(filecfg) then
		local objfilename = obj_dir .. "/" .. filecfg.objname .. (toolset.objectextension or ".o")
		objfiles[#objfiles + 1] = objfilename
		local cflags = {}
		if has_custom_settings then
			cflags = {"CFLAGS = $CFLAGS " .. getcflags(toolset, cfg, filecfg)}
		end
		add_build(cfg, objfilename, {}, "cc", {filepath}, pch_dependency, regular_file_dependencies, cflags)
	elseif shouldcompileascpp(filecfg) then
		local objfilename = obj_dir .. "/" .. filecfg.objname .. path.getextension(filecfg.path) .. (toolset.objectextension or ".o")
		objfiles[#objfiles + 1] = objfilename
		local cxxflags = {}
		if has_custom_settings then
			cxxflags = {"CXXFLAGS = $CXXFLAGS " .. getcxxflags(toolset, cfg, filecfg)}
		end

		local rule = "cxx"
		local regFileDeps = table.arraycopy(regular_file_dependencies)
		if _OPTIONS["experimental-enable-cxx-modules"] and is_module_file(filecfg.name) then
			rule = "cxx_module"
			local dynDepModMapFile = objfilename .. ".modmap"
			local dynDepFile = path.join(obj_dir, "CXX.dd")
			table.insert(cxxflags, "DYNDEP_MODULE_MAP_FILE = " .. dynDepModMapFile)
			table.insert(cxxflags, "dyndep = " .. dynDepFile)
			table.insert(regFileDeps, dynDepFile)
			table.insert(regFileDeps, dynDepModMapFile)
		end

		add_build(cfg, objfilename, {}, rule, {filepath}, pch_dependency, regFileDeps, cxxflags)
	elseif path.isresourcefile(filecfg.abspath) then
		local objfilename = obj_dir .. "/" .. filecfg.name .. ".res"
		objfiles[#objfiles + 1] = objfilename
		local resflags = {}
		if has_custom_settings then
			resflags = {"RESFLAGS = $RESFLAGS " .. getresflags(toolset, cfg, filecfg)}
		end
		add_build(cfg, objfilename, {}, "rc", {filepath}, {}, {}, resflags)
	end
end

local function files_build(prj, cfg, toolset, pch_dependency, regular_file_dependencies, file_dependencies)
	local objfiles = {}
	local obj_dir = project.getrelative(cfg.workspace, cfg.objdir)

	tree.traverse(project.getsourcetree(prj), {
	onleaf = function(node, depth)
		local filecfg = fileconfig.getconfig(node, cfg)
		if not filecfg or filecfg.flags.ExcludeFromBuild then
			return
		end

		-- Compiling PCH on MSVC is handled via build_pch build rule
		if toolset == p.tools.msc and cfg.pchsource and cfg.pchsource == node.abspath then
			local objfilename = obj_dir .. "/" .. path.getname(node.path) .. (toolset.objectextension or ".o")
			objfiles[#objfiles + 1] = objfilename
			return
		end

		local rule = p.global.getRuleForFile(node.name, prj.rules)
		local filepath = project.getrelative(cfg.workspace, node.abspath)

		if fileconfig.hasCustomBuildRule(filecfg) then
			custom_command_build(prj, cfg, filecfg, filepath, file_dependencies)
		elseif rule then
			local environ = table.shallowcopy(filecfg.environ)

			if rule.propertydefinition then
				p.rule.prepareEnvironment(rule, environ, cfg)
				p.rule.prepareEnvironment(rule, environ, filecfg)
			end
			local rulecfg = p.context.extent(rule, environ)
			custom_command_build(prj, cfg, rulecfg, filepath, file_dependencies)
		else
			compile_file_build(cfg, filecfg, toolset, pch_dependency, regular_file_dependencies, objfiles)
		end
	end,
	}, false, 1)
	p.outln("")

	return objfiles
end

local function scan_module_file_build(cfg, filecfg, toolset, modulefiles)
	local obj_dir = project.getrelative(cfg.workspace, cfg.objdir)
	local filepath = project.getrelative(cfg.workspace, filecfg.abspath)
	local has_custom_settings = fileconfig.hasFileSettings(filecfg)

	local outputFilebase = obj_dir .. "/" .. filecfg.name
	local dyndepfilename = outputFilebase .. toolset.objectextension .. ".ddi"
	modulefiles[#modulefiles + 1] = dyndepfilename

	local vars = {}
	table.insert(vars, "DEP_FILE = " .. outputFilebase .. toolset.objectextension .. ".ddi.d")
	table.insert(vars, "DYNDEP_INTERMEDIATE_FILE = " .. dyndepfilename)
	table.insert(vars, "OBJ_FILE = " .. outputFilebase .. toolset.objectextension)
	table.insert(vars, "PREPROCESSED_OUTPUT_FILE = " .. outputFilebase .. toolset.objectextension .. ".ddi.i")

	add_build(cfg, dyndepfilename, {}, "__module_scan", {filepath}, {}, {}, vars)
end

local function files_scan_modules(prj, cfg, toolset)
	local modulefiles = {}
	tree.traverse(project.getsourcetree(prj), {
	onleaf = function(node, depth)
		if not is_module_file(node.name) then
			return
		end

		local filecfg = fileconfig.getconfig(node, cfg)
		if not filecfg or filecfg.flags.ExcludeFromBuild then
			return
		end

		scan_module_file_build(cfg, filecfg, toolset, modulefiles)
	end,
	}, false, 1)
	p.outln("")

	return modulefiles
end

local function generated_files_build(cfg, generated_files, key)
	local final_dependency = {}
	if #generated_files > 0 then
		p.outln("# generated files")
		add_build(cfg, "generated_files_" .. key, {}, "phony", generated_files, {}, {}, {})
		final_dependency = {"generated_files_" .. key}
	end
	return final_dependency
end

-- generate project + config build file
function ninja.generateProjectCfg(cfg)
	local prj = cfg.project
	local key = get_key(cfg)
	local toolset, toolset_version = p.tools.canonical(cfg.toolset)

	if not toolset then
		p.error("Unknown toolset " .. cfg.toolset)
	end

  -- Some toolset fixes
	cfg.gccprefix = cfg.gccprefix or ""

	if os.target() == "windows" and cfg.externalwarnings == nil then
		cfg.externalwarnings = "Default"
	end

	if cfg.characterset == nil then
		cfg.characterset = "Default"
	end
	if cfg.entrypoint == nil then
		if cfg.kind == "WindowedApp" then -- Use WinMain()
			cfg.entrypoint = "WinMainCRTStartup"
		elseif cfg.kind == "SharedLib" then -- Use DllMain()
			cfg.entrypoint = "_DllMainCRTStartup"
		elseif cfg.kind == "ConsoleApp" then -- Use main()
			cfg.entrypoint = "mainCRTStartup"
		end
	end

	p.outln("# project build file")
	p.outln("# generated with premake ninja")
	p.outln("")

	-- premake-ninja relies on scoped rules
	-- and they were added in ninja v1.11.1
	p.outln("ninja_required_version = 1.11.1")
	p.outln("")

	---------------------------------------------------- figure out settings
	local pch = p.tools.gcc.getpch(cfg)
	if pch then
		pch = {
			input = project.getrelative(cfg.workspace, path.join(cfg.location, pch)),
			inputSrc = project.getrelative(cfg.workspace, path.join(cfg.location, cfg.pchsource)),
			placeholder = project.getrelative(cfg.workspace, path.join(cfg.objdir, path.getname(pch))),
			gch = project.getrelative(cfg.workspace, path.join(cfg.objdir, path.getname(pch) .. ".gch")),
			pch = project.getrelative(cfg.workspace, path.join(cfg.objdir, path.getname(pch) .. ".pch"))
		}
	end

	---------------------------------------------------- write rules
	p.outln("# core rules for " .. cfg.name)
	prebuild_rule(cfg)
	prelink_rule(cfg)
	postbuild_rule(cfg)
	compilation_rules(cfg, toolset, pch)
	custom_command_rule()
	if _OPTIONS["experimental-enable-cxx-modules"] then
		module_scan_rule(cfg, toolset)
		module_collate_rule(cfg, toolset)
	end

	local modulefiles = nil
	if _OPTIONS["experimental-enable-cxx-modules"] then
	---------------------------------------------------- scan all module files
		p.outln("# scan modules")
		modulefiles = files_scan_modules(prj, cfg, toolset)
	end

	if _OPTIONS["experimental-enable-cxx-modules"] and modulefiles then
		---------------------------------------------------- collate all scanned module files
		p.outln("# collate modules")

		local obj_dir = project.getrelative(cfg.workspace, cfg.objdir)
		local outputFile = obj_dir .. "/CXX.dd"

		local implicitOutputs = {obj_dir .. "/CXXModules.json"}
		for k,v in pairs(modulefiles) do
			table.insert(implicitOutputs, path.replaceextension(v, "modmap"))
		end

		local implicit_inputs = {}
		local vars = {}
		local dependencies = {}
		for _, v in pairs(p.config.getlinks(cfg, "dependencies", "object")) do
			local relDepObjDir = project.getrelative(cfg.workspace, v.objdir)
			table.insert(dependencies, path.join(relDepObjDir, "CXXModules.json"))
		end

		table.insert(vars, "MODULE_DEPS = \"" .. table.implode(dependencies, "", "", " ") .. "\"")

		add_build(cfg, outputFile, implicitOutputs, "__module_collate", modulefiles, implicit_inputs, dependencies, vars)
		p.outln("")
	end

	---------------------------------------------------- build all files

	local pch_dependency = pch_build(cfg, pch, toolset)

	local generated_files = collect_generated_files(prj, cfg)
	local file_dependencies = getFileDependencies(cfg)
	local regular_file_dependencies = table.join(iif(#generated_files > 0, {"generated_files_" .. key}, {}), file_dependencies)

	local obj_dir = project.getrelative(cfg.workspace, cfg.objdir)
	p.outln("# build files")
	local objfiles = files_build(prj, cfg, toolset, pch_dependency, regular_file_dependencies, file_dependencies)
	local final_dependency = generated_files_build(cfg, generated_files, key)

	---------------------------------------------------- build final target
	if #cfg.prebuildcommands > 0 or cfg.prebuildmessage then
		p.outln("# prebuild")
		add_build(cfg, "prebuild_" .. get_key(cfg), {}, "run_prebuild", {}, {}, {}, {})
	end
	local prelink_dependency = {}
	if #cfg.prelinkcommands > 0 or cfg.prelinkmessage then
		p.outln("# prelink")
		add_build(cfg, "prelink_" .. get_key(cfg), {}, "run_prelink", {}, objfiles, final_dependency, {})
		prelink_dependency = { "prelink_" .. get_key(cfg) }
	end
	if #cfg.postbuildcommands > 0 or cfg.postbuildmessage then
		p.outln("# postbuild")
		add_build(cfg, "postbuild_" .. get_key(cfg), {}, "run_postbuild",  {}, {ninja.outputFilename(cfg)}, {}, {})
	end

	-- we don't pass getlinks(cfg) through dependencies
	-- because system libraries are often not in PATH so ninja can't find them
	local libs = table.translate(config.getlinks(cfg, "siblings", "fullpath"), function (p) return project.getrelative(cfg.workspace, path.join(cfg.project.location, p)) end)
	local cfg_output = ninja.outputFilename(cfg)
	local extra_outputs = {}
	local command_rule = ""
	if cfg.kind == p.STATICLIB then
		p.outln("# link static lib")
		command_rule = "ar"
	elseif cfg.kind == p.SHAREDLIB then
		p.outln("# link shared lib")
		command_rule = "link"
		extra_outputs = iif(os.target() == "windows", {path.replaceextension(cfg_output, ".lib"), path.replaceextension(cfg_output, ".exp")}, {})
	elseif (cfg.kind == p.CONSOLEAPP) or (cfg.kind == p.WINDOWEDAPP) then
		p.outln("# link executable")
		command_rule = "link"
	else
		p.error("ninja action doesn't support this kind of target " .. cfg.kind)
	end
	add_build(cfg, cfg_output, extra_outputs, command_rule, table.join(objfiles, libs), {}, table.join(final_dependency, prelink_dependency), {})

	p.outln("")
	if #cfg.postbuildcommands > 0 or cfg.postbuildmessage then
		add_build(cfg, key, {}, "phony", {"postbuild_" .. get_key(cfg)}, {}, {}, {})
	else
		add_build(cfg, key, {}, "phony", {cfg_output}, {}, {}, {})
	end
	p.outln("")
end

-- return name of output binary relative to build folder
function ninja.outputFilename(cfg)
	return project.getrelative(cfg.workspace, cfg.buildtarget.directory) .. "/" .. cfg.buildtarget.name
end

-- return name of build file for configuration
function ninja.projectCfgFilename(cfg, relative)
	if relative ~= nil then
		relative = project.getrelative(cfg.workspace, cfg.location) .. "/"
	else
		relative = ""
	end
	return relative .. "build_" .. get_key(cfg) .. ".ninja"
end

-- check if string starts with string
function ninja.startsWith(str, starts)
	return str:sub(0, starts:len()) == starts
end

-- check if string ends with string
function ninja.endsWith(str, ends)
	return str:sub(-ends:len()) == ends
end

-- generate all build files for every project configuration
function ninja.generateProject(prj)
	if not p.action.supports(prj.kind) or prj.kind == p.NONE then
		return
	end
	for cfg in project.eachconfig(prj) do
		p.generate(cfg, ninja.projectCfgFilename(cfg), ninja.generateProjectCfg)
	end
end

include("_preload.lua")

return ninja
