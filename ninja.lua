--
-- Name:        premake-ninja/ninja.lua
-- Purpose:     Define the ninja action.
-- Author:      Dmitry Ivanov
-- Modified by: Jan "GamesTrap" Schürkamp
-- Created:     2015/07/04
-- Updated:     2025/11/11
-- Copyright:   (c) 2015 Dmitry Ivanov, (c) 2023-2025 Jan "GamesTrap" Schürkamp
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

ninja.handlers = {}

local function registerHandler(kind, c_cpp_compilationRules, target_rules)
	ninja.handlers[kind] = {c_cpp_compilationRules = c_cpp_compilationRules, target_rules = target_rules}
end

local function getKey(cfg)
	local name = name or cfg.project.name

	if cfg.platform then
		return string.format('%s_%s_%s', name, cfg.buildcfg, cfg.platform)
	end

	return string.format('%s_%s', name, cfg.buildcfg)
end

local function list(value)
	if #value > 0 then
		return " " .. table.concat(value, " ")
	else
		return ""
	end
end

local function escape(value)
	value = value:gsub("%$", "$$") -- TODO maybe there is better way
	value = value:gsub(":", "$:")
	value = value:gsub("\n", "$\n")
	value = value:gsub(" ", "$ ")
	return value
end

local build_cache = {}

local function addBuild(cfg, out, implicit_outputs, command, inputs, implicit_inputs, dependencies, vars)
	implicit_outputs = list(table.translate(implicit_outputs, escape))
	if #implicit_outputs > 0 then
		implicit_outputs = " |" .. implicit_outputs
	else
		implicit_outputs = ""
	end

	inputs = list(table.translate(inputs, escape))

	implicit_inputs = list(table.translate(implicit_inputs, escape))
	if #implicit_inputs > 0 then
		implicit_inputs = " |" .. implicit_inputs
	else
		implicit_inputs = ""
	end

	dependencies = list(table.translate(dependencies, escape))
	if #dependencies > 0 then
		dependencies = " ||" .. dependencies
	else
		dependencies = ""
	end
	build_line = "build " .. escape(out) .. implicit_outputs .. ": " .. command .. inputs .. implicit_inputs .. dependencies

	local cached = build_cache[out]
	if cached ~= nil then
		if build_line == cached.build_line and table.equals(vars or {}, cached.vars or {}) then
			-- custom_command/copy rules are identical for each configuration (contrary to other rules)
			-- So we can compare extra parameter
			if command == "custom_command" or command == "copy" then
				p.outln("# INFO: Rule ignored, same as " .. cached.cfg_key)
			else
				local cfg_key = cfg and getKey(cfg) or "Global scope"
				p.warn(cached.cfg_key .. " and " .. cfg_key .. " both generate (differently?) " .. out .. ". Ignoring " .. cfg_key)
				p.outln("# WARNING: Rule ignored, using the one from .." .. cached.cfg_key)
			end
		else
			local cfg_key = cfg and getKey(cfg) or "Global scope"
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
	build_cache[out] =
	{
		cfg_key = cfg and getKey(cfg) or "Global scope",
		build_line = build_line,
		vars = vars
	}
end

local function emitRule(name, cmds, description, opts)
	opts = opts or {}
	p.outln("rule " .. name)
	p.outln("  command = " .. table.concat(cmds, " &&$\n            "))
	p.outln("  description = " .. description)
	for key, value in pairs(opts) do
		p.outln("  " .. key .. " = " .. value)
	end
	p.outln("")
end

local function emitFlags(name, value)
	p.outln(name .. " =" .. value)
end

local function quote(value)
	value = value:gsub("\\", "\\\\")
	value = value:gsub("'", "\\'")
	value = value:gsub('"', '\\"')

	return '"' .. value .. '"'
end

-- In some cases we write file names in rule commands directly
-- so we need to propely escape them
local function shellEscape(value)
	if type(value) == "table" then
		return table.translate(value, shellEscape)
	end

	if value:find(" ") or value:find('"') or value:find('(', 1, true) or value:find(')') or value:find('|') or value:find('&') then
		return quote(value)
	end

	return value
end

local function canGenerate(prj)
	return p.action.supports(prj.kind) and prj.kind ~= p.NONE
end

-- return name of build file for configuration
local function projectCfgFilename(cfg, relative)
	if relative ~= nil then
		relative = project.getrelative(cfg.workspace, cfg.location) .. "/"
	else
		relative = ""
	end
	return relative .. getKey(cfg, cfg.project.filename) .. ".ninja"
end

-- Generate solution that will call ninja for projects
function ninja.generateWorkspace(wks)
	local oldGetDefaultSeparator = path.getDefaultSeparator
	path.getDefaultSeparator = function()
		return "/"
	end

	p.outln("# solution build file")
	p.outln("# generated with premake ninja")
	p.outln("")

	p.outln("# build projects")
	local cfgs = {} -- key is concatenated name or variant name, value is string of outputs names
	local key = ""
	local cfg_first = nil
	local cfg_first_lib = nil
	local subninjas = {}

	for prj in p.workspace.eachproject(wks) do
		if canGenerate(prj) then
			for cfg in p.project.eachconfig(prj) do
				key = getKey(cfg)

				if not cfgs[cfg.buildcfg] then
					cfgs[cfg.buildcfg] = {}
				end
				table.insert(cfgs[cfg.buildcfg], key)

				-- set first configuration name
				if wks.defaultplatform == nil then
					if (cfg_first == nil) and (cfg.kind == p.CONSOLEAPP or cfg.kind == p.WINDOWEDAPP) then
						cfg_first = key
					end
				end
				if (cfg_first_lib == nil) and (cfg.kind == p.STATICLIB or cfg.kind == p.SHAREDLIB) then
					cfg_first_lib = key
				end
				if prj.name == wks.startproject then
					if wks.defaultplatform == nil then
						cfg_first = key
					elseif cfg.platform == wks.defaultplatform then
						if cfg_first == nil then
							cfg_first = key
						end
					end
				end

				-- include other ninja file
				table.insert(subninjas, escape(projectCfgFilename(cfg, true)))
				p.outln("subninja " .. escape(projectCfgFilename(cfg, true)))
			end
		end
	end

	if cfg_first == nil then
		cfg_first = cfg_first_lib
	end

	p.outln("")

	p.outln("# targets")
	for cfg, outputs in spairs(cfgs) do
		p.outln("build " .. escape(cfg) .. ": phony" .. list(table.translate(outputs, escape)))
	end
	p.outln("")

	if wks.editorintegration then
		-- we need to filter out the 'file' argument, since we already output the script separately
		local args = {}
		for _, arg in ipairs(_ARGV) do
			if not (arg:startswith('--file') or arg:startswith('/file')) then
				table.insert(args, arg)
			end
		end
		table.sort(args)

		p.outln("# Rule")
		emitRule('premake', {shellEscape(p.workspace.getrelative(wks, _PREMAKE_COMMAND)) .. ' --file=$in ' .. table.concat(shellEscape(args), ' ')}, 'run premake', {generator = 'true', restat = 'true'})
		addBuild(nil, 'build.ninja', subninjas, 'premake', {p.workspace.getrelative(wks, _MAIN_SCRIPT_DIR)}, {}, {}, {})
		p.outln('')
	end

	if cfg_first then
		p.outln("# default target")
		p.outln("default " .. escape(cfg_first))
		p.outln("")
	end

	path.getDefaultSeparator = oldGetDefaultSeparator
end

local function shouldCompileAsC(filecfg)
	if filecfg.compileas and filecfg.compileas ~= "Default" then
		return p.languages.isc(filecfg.compileas)
	end
	return path.iscfile(filecfg.abspath)
end

local function shouldCompileAsCpp(filecfg)
	if filecfg.compileas and filecfg.compileas ~= "Default" then
		return p.languages.iscpp(filecfg.compileas)
	end
	return path.iscppfile(filecfg.abspath)
end

local function getFileDependencies(cfg)
	local dependencies = {}
	if #cfg.prebuildcommands > 0 or cfg.prebuildmessage then
		dependencies = {"prebuild_" .. getKey(cfg)}
	end
	for i = 1, #cfg.dependson do
		local dependpostfix = ''
		if cfg.platform then
			dependpostfix = '_' .. cfg.platform
		end

		table.insert(dependencies, cfg.dependson[i] .. "_" .. cfg.buildcfg .. dependpostfix)
	end
	return dependencies
end

local function getCFlags(toolset, cfg, filecfg)
	p.escaper(shellEscape)

	local buildopt = list(filecfg.buildoptions)
	local cppflags = list(toolset.getcppflags(filecfg))
	local cflags = list(toolset.getcflags(filecfg))
	local defines = list(table.join(toolset.getdefines(filecfg.defines, filecfg), toolset.getundefines(filecfg.undefines)))
	local includes = list(toolset.getincludedirs(cfg, filecfg.includedirs, filecfg.externalincludedirs, filecfg.frameworkdirs, filecfg.includedirsafter))
	local forceincludes = list(toolset.getforceincludes(cfg))
	p.escaper(nil)

	return buildopt .. cppflags .. cflags .. defines .. includes .. forceincludes
end

local function getCXXFlags(toolset, cfg, filecfg)
	p.escaper(shellEscape)
	local buildopt = list(filecfg.buildoptions)
	local cppflags = list(toolset.getcppflags(filecfg))
	local cxxflags = list(toolset.getcxxflags(filecfg))
	local defines = list(table.join(toolset.getdefines(filecfg.defines, filecfg), toolset.getundefines(filecfg.undefines)))
	local includes = list(toolset.getincludedirs(cfg, filecfg.includedirs, filecfg.externalincludedirs, filecfg.frameworkdirs, filecfg.includedirsafter))
	local forceincludes = list(toolset.getforceincludes(cfg))
	p.escaper(nil)

	return buildopt .. cppflags .. cxxflags .. defines .. includes .. forceincludes
end

local function getLDFlags(toolset, cfg)
	local ldflags = list(table.join(toolset.getLibraryDirectories(cfg), toolset.getrunpathdirs(cfg, table.join(cfg.runpathdirs, config.getsiblingtargetdirs(cfg))), toolset.getldflags(cfg), cfg.linkoptions))

	if cfg.entrypoint ~= nil and toolset == p.tools.msc then
		ldflags = ldflags .. " /ENTRY:" .. cfg.entrypoint
	end

	-- experimental feature, change install_name of shared libs
	--if toolset == p.tools.clang and cfg.kind == p.SHAREDLIB and cfg.buildtarget.name:endsWith(".dylib") then
	--	ldflags = ldflags .. " -install_name " .. cfg.buildtarget.name
	--end

	return ldflags
end

local function getResFlags(toolset, cfg, filecfg)
	p.escaper(shellEscape)
	local defines = list(toolset.getdefines(table.join(filecfg.defines, filecfg.resdefines), filecfg))
	local includes = list(toolset.getincludedirs(cfg, table.join(filecfg.externalincludedirs, filecfg.includedirsafter, filecfg.includedirs, filecfg.resincludedirs), {}, {}, {}))
	local options = list(cfg.resoptions)
	p.escaper(nil)

	return defines .. includes .. options
end

local strMagic = "([%^%$%(%)%%%.%[%]%*%+%-%?])" -- UTF-8 replacement for "(%W)"

-- Replace is plain text version of string.gsub()
local function stringReplace(strTxt, strOld, strNew, intNum)
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

local function prebuildRule(cfg)
	if #cfg.prebuildcommands > 0 or cfg.prebuildmessage then
		local commands = {}
		if cfg.prebuildmessage then
			commands = {os.translateCommandsAndPaths("{ECHO} " .. cfg.prebuildmessage, cfg.workspace.basedir, cfg.workspace.location)}
		end
		commands = table.join(commands, os.translateCommandsAndPaths(pretranslatePaths(cfg.prebuildcommands, cfg), cfg.workspace.basedir, cfg.workspace.location))
		if (#commands > 1) then
			if p.tools.canonical(cfg.toolset) == p.tools.msc then
				commands = 'cmd /c ' .. quote(table.implode(commands,"",""," && "))
			else
				commands = 'sh -c ' .. quote(table.implode(commands,"","",";"))
			end
		else
			commands = commands[1]
		end

		emitRule('run_prebuild', {commands}, 'prebuild')
	end
end

local function prelinkRule(cfg)
	if #cfg.prelinkcommands > 0 or cfg.prelinkmessage then
		local commands = {}
		if cfg.prelinkmessage then
			commands = {os.translateCommandsAndPaths("{ECHO} " .. cfg.prelinkmessage, cfg.workspace.basedir, cfg.workspace.location)}
		end
		commands = table.join(commands, os.translateCommandsAndPaths(pretranslatePaths(cfg.prelinkcommands, cfg), cfg.workspace.basedir, cfg.workspace.location))
		if (#commands > 1) then
			if p.tools.canonical(cfg.toolset) == p.tools.msc then
				commands = 'cmd /c ' .. quote(table.implode(commands,"",""," && "))
			else
				commands = 'sh -c ' .. quote(table.implode(commands,"","",";"))
			end
		else
			commands = commands[1]
		end

		emitRule('run_prelink', {commands}, 'prelink')
	end
end

local function postbuildRule(cfg)
	if #cfg.postbuildcommands > 0 or cfg.postbuildmessage then
		local commands = {}
		if cfg.postbuildmessage then
			commands = {os.translateCommandsAndPaths("{ECHO} " .. cfg.postbuildmessage, cfg.workspace.basedir, cfg.workspace.location)}
		end

		local oldGetDefaultSeparator = path.getDefaultSeparator
		if p.tools.canonical(cfg.toolset) == p.tools.msc then
			path.getDefaultSeparator = function()
				return '\\'
			end
		end
		commands = table.join(commands, os.translateCommandsAndPaths(pretranslatePaths(cfg.postbuildcommands, cfg), cfg.workspace.basedir, cfg.workspace.location))
		path.getDefaultSeparator = oldGetDefaultSeparator

		if (#commands > 1) then
			if p.tools.canonical(cfg.toolset) == p.tools.msc then
				commands = 'cmd /c ' .. quote(table.implode(commands,"",""," && "))
			else
				commands = 'sh -c ' .. quote(table.implode(commands,"","",";"))
			end
		else
			commands = commands[1]
		end

		emitRule('run_postbuild', {commands}, 'postbuild')
	end
end

local function c_cpp_compilationRules(cfg, toolset, pch)
	---------------------------------------------------- figure out toolset executables
	local cc = toolset.gettoolname(cfg, "cc")
	local cxx = toolset.gettoolname(cfg, "cxx")
	local ar = toolset.gettoolname(cfg, "ar")
	local link = toolset.gettoolname(cfg, iif(cfg.language == "C", "cc", "cxx"))
	local rc = toolset.gettoolname(cfg, "rc")

	-- all paths need to be relative to the workspace output location,
	-- and not relative to the project output location.
	-- override the toolset getrelative function to achieve this

	local getrelative = p.tools.getrelative
	p.tools.getrelative = function(cfg, value)
		return p.workspace.getrelative(cfg.workspace, value)
	end

	local all_cflags = getCFlags(toolset, cfg, cfg)
	local all_cxxflags = getCXXFlags(toolset, cfg, cfg)
	local all_ldflags = getLDFlags(toolset, cfg)
	local all_resflags = getResFlags(toolset, cfg, cfg)

	if toolset == p.tools.msc then
		local force_include_pch = ""
		if pch then
			force_include_pch = " /Yu" .. shellEscape(path.getname(pch.input)) .. " /Fp" .. shellEscape(pch.pch)
		end

		emitFlags('CFLAGS', all_cflags)
		emitRule('cc', {cc .. ' $CFLAGS' .. force_include_pch .. ' /nologo /showIncludes -c /Tc$in /Fo$out'}, 'cc $out', {deps = 'msvc'})

		emitFlags('CXXFLAGS', all_cxxflags)
		emitRule('cxx', {cxx .. ' $CXXFLAGS' .. force_include_pch .. ' /nologo /showIncludes -c /Tp$in /Fo$out'}, 'cxx $out', {deps = 'msvc'})

		if pch then
			emitRule('build_pch', {iif(cfg.language == "C", cc .. " $CFLAGS", cxx .. " $CXXFLAGS") .. ' /Yc' .. shellEscape(path.getname(pch.input)) .. ' /Fp' .. shellEscape(pch.pch) .. ' /nologo /showIncludes -c /Tp$in /Fo$out'}, 'build_pch $out', {deps = 'msvc'})
		end

		emitRule('cxx_module', {cxx .. ' $CXXFLAGS' .. force_include_pch .. ' /nologo /showIncludes @$DYNDEP_MODULE_MAP_FILE /FS -c /Tp$in /Fo$out'}, 'cxx_module $out', {deps = 'msvc'})

		emitFlags('RESFLAGS', all_resflags)
		emitRule('rc', {rc .. ' /nologo /fo$out $in $RESFLAGS'}, 'rc $out')

		if cfg.kind == p.STATICLIB then
			emitRule('ar', {ar .. ' $in /nologo -OUT:$out'}, 'ar $out')
		else
			emitRule('link', {link .. ' $in ' .. list(shellEscape(pretranslatePaths(toolset.getlinks(cfg, true), cfg))) .. ' /link ' .. all_ldflags .. ' /nologo /out:$out'}, 'link $out')
		end
	elseif toolset == p.tools.clang or toolset == p.tools.gcc then
		local force_include_pch = ""
		if pch then
			force_include_pch = " -include " .. shellEscape(pch.placeholder)
		end

		emitFlags('CFLAGS', all_cflags)
		emitRule('cc', {cc .. ' $CFLAGS' .. force_include_pch .. ' -x c -MF $out.d -c -o $out $in'}, 'cc $out', {depfile = '$out.d', deps = 'gcc'})

		emitFlags('CXXFLAGS', all_cxxflags)
		emitRule('cxx', {cxx .. ' $CXXFLAGS' .. force_include_pch .. ' -x c++ -MF $out.d -c -o $out $in'}, 'cxx $out', {depfile = '$out.d', deps = 'gcc'})

		if pch then
			emitRule('build_pch', {iif(cfg.language == "C", cc .. ' $CFLAGS -x c-header', cxx .. ' $CXXFLAGS -x c++-header') .. ' -MF $out.d -c -o $out $in'}, 'build_pch $out', {depfile = '$out.d', deps = 'gcc'})
		end

		if toolset == p.tools.gcc then
			emitRule('cxx_module', {cxx .. ' $CXXFLAGS -fmodules-ts -fmodule-mapper=$DYNDEP_MODULE_MAP_FILE -fdeps-format=p1689r5 -x c++' .. force_include_pch .. ' -MT $out -MF $out.d -c -o $out $in'}, 'cxx_module $out', {depfile = '$out.d', deps = 'gcc'})
		elseif toolset == p.tools.clang then
			emitRule('cxx_module', {cxx .. ' $CXXFLAGS' .. force_include_pch .. ' -MT $out -MF $out.d @$DYNDEP_MODULE_MAP_FILE -c -o $out $in'}, 'cxx_module $out', {depfile = '$out.d', deps = 'gcc'})
		end

		emitFlags('RESFLAGS', all_resflags)
		if rc then
			emitRule('rc', {rc .. ' -i $in -o $out $RESFLAGS'}, 'rc $out')
		end

		if cfg.kind == p.STATICLIB then
			emitRule('ar', {ar .. ' rcs $out $in'}, 'ar $out')
		else
			local groups = iif(cfg.linkgroups == premake.ON, {'-Wl,--start-group ', ' -Wl,--end-group'}, {'', ''})
			emitRule('link', {link .. ' -o $out ' .. groups[1] .. '$in' .. list(shellEscape(pretranslatePaths(toolset.getlinks(cfg, true, true), cfg))) .. all_ldflags .. groups[2]}, 'link $out')
		end
	end

	p.tools.getrelative = getrelative
end

local function customCommandRule()
	emitRule('custom_command', {'$CUSTOM_COMMAND'}, '$CUSTOM_DESCRIPTION')
end

local function copyRule()
	emitRule('copy', {os.translateCommands('{COPYFILE} $in $out')}, 'copy $in $out')
end

local function collectGeneratedFiles(prj, cfg)
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

local function pchBuild(cfg, pch, toolset)
	local pch_dependency = {}
	if pch then
		if toolset == p.tools.msc then
			pch_dependency = { pch.pch }
			addBuild(cfg, pch.outObj, {pch.pch}, "build_pch", {pch.inputSrc}, {}, {}, {})
		else
			pch_dependency = {pch.gch}
			addBuild(cfg, pch.gch, {}, "build_pch", {pch.input}, {}, {}, {})
		end
	end

	return pch_dependency
end

local function customCommandBuild(prj, cfg, filecfg, filename, file_dependencies)
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
			commands = 'cmd /c ' .. quote(table.implode(commands,"",""," && "))
		else
			commands = 'sh -c ' .. quote(table.implode(commands,"","",";"))
		end
	else
		commands = commands[1]
	end

	addBuild(cfg, output, outputs, "custom_command", {filename}, project.getrelative(prj.workspace, filecfg.buildinputs), file_dependencies, {"CUSTOM_COMMAND = " .. commands, "CUSTOM_DESCRIPTION = custom build " .. shellEscape(output)})
end

local function isCXXModuleFile(file)
	if _OPTIONS["experimental-modules-scan-all"] then
		return true
	end

	local fileEnding = path.getextension(file)

	if fileEnding == ".cxx" or fileEnding == ".cxxm" or fileEnding == ".ixx" or
	   fileEnding == ".cppm" or fileEnding == ".c++m" or fileEnding == ".ccm" or
	   fileEnding == ".mpp" then
		return true
	end

	return false
end

local function compileFileBuild(cfg, filecfg, toolset, pch_dependency, regular_file_dependencies, objfiles, extrafiles)
	local obj_file = filecfg.objname .. (toolset.objectextension or '.o')
	local obj_dir = project.getrelative(cfg.workspace, cfg.objdir)
	local filepath = project.getrelative(cfg.workspace, filecfg.abspath)
	local has_custom_settings = fileconfig.hasFileSettings(filecfg)

	if filecfg.buildaction == 'None' then
		return
	elseif filecfg.buildaction == 'Copy' then
		local target = project.getrelative(cfg.workspace, path.join(cfg.targetdir, filecfg.name))
		addBuild(cfg, target, {}, 'copy', {filepath}, {}, {}, {})
		extrafiles[#extrafiles + 1] = target
	elseif shouldCompileAsC(filecfg) then
		local objfilename = obj_dir .. '/' .. obj_file
		objfiles[#objfiles + 1] = objfilename
		local vars = {}
		if has_custom_settings then
			vars = {'CFLAGS = $CFLAGS ' .. getCFlags(toolset, cfg, filecfg)}
		end
		addBuild(cfg, objfilename, {}, 'cc', {filepath}, pch_dependency, regular_file_dependencies, vars)
	elseif shouldCompileAsCpp(filecfg) then
		local objfilename = obj_dir .. '/' .. obj_file
		objfiles[#objfiles + 1] = objfilename
		local vars = {}
		if has_custom_settings then
			vars = { 'CXXFLAGS = $CXXFLAGS ' .. getCXXFlags(toolset, cfg, filecfg)}
		end

		if _OPTIONS["experimental-enable-cxx-modules"] and isCXXModuleFile(filecfg.name) then
			local regFileDeps = table.arraycopy(regular_file_dependencies)

			local dynDepModMapFile = objfilename .. ".modmap"
			local dynDepFile = path.join(obj_dir, "CXX.dd")
			table.insert(vars, "DYNDEP_MODULE_MAP_FILE = " .. dynDepModMapFile)
			table.insert(vars, "dyndep = " .. dynDepFile)
			table.insert(regFileDeps, dynDepFile)
			table.insert(regFileDeps, dynDepModMapFile)

			addBuild(cfg, objfilename, {}, 'cxx_module', {filepath}, pch_dependency, regFileDeps, vars)
		else
			addBuild(cfg, objfilename, {}, 'cxx', {filepath}, pch_dependency, regular_file_dependencies, vars)
		end
	elseif path.isresourcefile(filecfg.abspath) then
		local objfilename = obj_dir .. '/' .. filecfg.basename .. '.res'
		objfiles[#objfiles + 1] = objfilename
		local resflags = {}
		if has_custom_settings then
			resflags = {'RESFLAGS = $RESFLAGS ' .. getResFlags(toolset, cfg, filecfg)}
		end
		local rc = toolset.gettoolname(cfg, 'rc')
		if rc then
			addBuild(cfg, objfilename, {}, 'rc', {filepath}, {}, {}, resflags)
		else
			p.warnOnce(filepath, string.format('Ignored resource: "%s"', filepath))
		end
	end
end

local function filesBuild(prj, cfg, toolset, pch_dependency, regular_file_dependencies, file_dependencies)
	local objfiles = {}
	local extrafiles = {}
	local obj_dir = project.getrelative(cfg.workspace, cfg.objdir)

	tree.traverse(project.getsourcetree(prj), {
		onleaf = function(node, depth)
			local filecfg = fileconfig.getconfig(node, cfg)
			if not filecfg or filecfg.flags.ExcludeFromBuild then
				return
			end

			-- Compiling PCH is handled via build_pch build rule
			if cfg.pchsource and cfg.pchsource == node.abspath then
				if toolset == p.tools.msc then -- MSVC emits an object file for the PCH, while GCC and Clang dont
					local objfilename = obj_dir .. "/" .. path.getname(node.path) .. (toolset.objectextension or ".o")
					objfiles[#objfiles + 1] = objfilename
				end

				return
			end

			local rule = p.global.getRuleForFile(node.name, prj.rules)
			local filepath = project.getrelative(cfg.workspace, node.abspath)

			if fileconfig.hasCustomBuildRule(filecfg) then
				customCommandBuild(prj, cfg, filecfg, filepath, file_dependencies)
			elseif rule then
				local environ = table.shallowcopy(filecfg.environ)

				if rule.propertydefinition then
					p.rule.prepareEnvironment(rule, environ, cfg)
					p.rule.prepareEnvironment(rule, environ, filecfg)
				end
				local rulecfg = p.context.extent(rule, environ)
				customCommandBuild(prj, cfg, rulecfg, filepath, file_dependencies)
			else
				compileFileBuild(cfg, filecfg, toolset, pch_dependency, regular_file_dependencies, objfiles, extrafiles)
			end
		end,
	}, false, 1)
	p.outln("")

	return objfiles, extrafiles
end

local function generatedFilesBuild(cfg, generated_files, key)
	local final_dependency = {}
	if #generated_files > 0 then
		p.outln("# generated files")
		addBuild(cfg, "generated_files_" .. key, {}, "phony", generated_files, {}, {}, {})
		final_dependency = {"generated_files_" .. key}
	end
	return final_dependency
end

-- return name of output binary relative to build folder
local function outputFilename(cfg)
	return project.getrelative(cfg.workspace, cfg.buildtarget.directory) .. "/" .. cfg.buildtarget.name
end

local function getCXXModuleScannerName(toolset, toolsetVersion, cfg)
	if toolset == p.tools.clang then
		local scannerName = "clang-scan-deps"

		if toolsetVersion then
			scannerName = scannerName .. "-" .. toolsetVersion
		end

		return scannerNamer
	elseif toolset == p.tools.gcc or toolset == p.tools.msc then
		return toolset.gettoolname(cfg, "cxx")
	end

	return nil
end

local function cxxModuleScanRule(cfg, toolset)
	local cmd = ""

	local scannerName = getCXXModuleScannerName(toolset, toolsetVersion, cfg)

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

	local deps = {}
	if toolset == p.tools.msc then
		deps = {deps = 'msvc'}
	else
		deps = {depfile = '$DEP_FILE', deps = 'gcc'}
	end
	emitRule("__module_scan", {cmd}, 'Scanning $in for C++ dependencies', deps)
end

local collateModuleScript = nil

local function cxxModuleCollateRule(cfg, toolset)
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

	emitRule('__module_collate', {cmd}, 'Generating C++ dyndep file $out', {rspfile = '$out.rsp', rspfile_content = '$in'})
end

local function scanCXXModuleFileBuild(cfg, filecfg, toolset, modulefiles)
	local obj_dir = project.getrelative(cfg.workspace, cfg.objdir)
	local filepath = project.getrelative(cfg.workspace, filecfg.abspath)

	local outputFilebase = obj_dir .. "/" .. filecfg.name
	local dyndepfilename = outputFilebase .. toolset.objectextension .. ".ddi"
	modulefiles[#modulefiles + 1] = dyndepfilename

	local vars = {}
	table.insert(vars, "DEP_FILE = " .. outputFilebase .. toolset.objectextension .. ".ddi.d")
	table.insert(vars, "DYNDEP_INTERMEDIATE_FILE = " .. dyndepfilename)
	table.insert(vars, "OBJ_FILE = " .. outputFilebase .. toolset.objectextension)
	table.insert(vars, "PREPROCESSED_OUTPUT_FILE = " .. outputFilebase .. toolset.objectextension .. ".ddi.i")

	addBuild(cfg, dyndepfilename, {}, "__module_scan", {filepath}, {}, {}, vars)
end

local function filesScanCXXModules(prj, cfg, toolset)
	local modulefiles = {}
	tree.traverse(project.getsourcetree(prj), {
		onleaf = function(node, depth)
			if not isCXXModuleFile(node.name) then
				return
			end

			local filecfg = fileconfig.getconfig(node, cfg)
			if not filecfg or filecfg.flags.ExcludeFromBuild then
				return
			end

			scanCXXModuleFileBuild(cfg, filecfg, toolset, modulefiles)
		end,
	}, false, 1)
	p.outln("")

	return modulefiles
end

-- generate project + config build file
local function generateProjectCfg(cfg)
	local oldGetDefaultSeparator = path.getDefaultSeparator
	path.getDefaultSeparator = function()
		return '/'
	end

	local prj = cfg.project
	local key = getKey(cfg)
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

	-- premake-ninja relies on scoped rules and dyndep
	p.outln("ninja_required_version = 1.11.1")
	p.outln("")

	local isCOrCPP = cfg.language == p.C or cfg.language == p.CPP

	---------------------------------------------------- figure out settings
	local pch = nil
	if isCOrCPP then
		pch = p.tools.gcc.getpch(cfg)
		if pch then
			pch = {
				input = project.getrelative(cfg.workspace, path.join(cfg.location, pch)),
				inputSrc = project.getrelative(cfg.workspace, path.join(cfg.location, cfg.pchsource)),
				placeholder = project.getrelative(cfg.workspace, path.join(cfg.objdir, path.getname(pch))),
				gch = project.getrelative(cfg.workspace, path.join(cfg.objdir, path.getname(pch) .. ".gch")),
				pch = project.getrelative(cfg.workspace, path.join(cfg.objdir, path.getname(pch) .. ".pch")),
				outObj = path.join(project.getrelative(cfg.workspace, cfg.objdir), path.getname(project.getrelative(cfg.workspace, path.join(cfg.location, cfg.pchsource))) .. (toolset.objectextension or p.tools.msc.objectextension))
			}
		end
	end

	---------------------------------------------------- write rules
	p.outln("# core rules for " .. cfg.name)

	prebuildRule(cfg)
	prelinkRule(cfg)
	postbuildRule(cfg)

	if isCOrCPP then
		c_cpp_compilationRules(cfg, toolset, pch)

		if _OPTIONS["experimental-enable-cxx-modules"] then
			cxxModuleScanRule(cfg, toolset)
			cxxModuleCollateRule(cfg, toolset)

			---------------------------------------------------- scan all module files
			p.outln("# scan modules")
			local modulefiles = filesScanCXXModules(prj, cfg, toolset)

			if modulefiles then
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

				addBuild(cfg, outputFile, implicitOutputs, "__module_collate", modulefiles, implicit_inputs, dependencies, vars)
				p.outln("")
			end
		end
	else
		local handler = ninja.handlers[cfg.language]
		if not handler then
			p.error('Expected registered ninja handler action for target ' .. cfg.language)
		end
		handler.compilationRules(cfg, toolset)
	end

	copyRule()
	customCommandRule()

	---------------------------------------------------- build all files

	p.outln("# build files")

	local pch_dependency = isCOrCPP and pchBuild(cfg, pch, toolset) or {}

	local generated_files = collectGeneratedFiles(prj, cfg)

	local file_dependencies = getFileDependencies(cfg)
	local regular_file_dependencies = table.join(iif(#generated_files > 0, {"generated_files_" .. key}, {}), file_dependencies)

	local obj_dir = project.getrelative(cfg.workspace, cfg.objdir)
	local objfiles, extrafiles = filesBuild(prj, cfg, toolset, pch_dependency, regular_file_dependencies, file_dependencies)
	local final_dependency = generatedFilesBuild(cfg, generated_files, key)

	---------------------------------------------------- build final target
	if #cfg.prebuildcommands > 0 or cfg.prebuildmessage then
		p.outln("# prebuild")
		addBuild(cfg, "prebuild_" .. getKey(cfg), {}, "run_prebuild", {}, {}, {}, {})
	end
	local prelink_dependency = {}
	if #cfg.prelinkcommands > 0 or cfg.prelinkmessage then
		p.outln("# prelink")
		addBuild(cfg, "prelink_" .. getKey(cfg), {}, "run_prelink", {}, objfiles, final_dependency, {})
		prelink_dependency = { "prelink_" .. getKey(cfg) }
	end
	if #cfg.postbuildcommands > 0 or cfg.postbuildmessage then
		p.outln("# postbuild")
		addBuild(cfg, "postbuild_" .. getKey(cfg), {}, "run_postbuild",  {}, {outputFilename(cfg)}, {}, {})
	end

	if isCOrCPP then
		-- we don't pass getlinks(cfg) through dependencies
		-- because system libraries are often not in PATH so ninja can't find them
		local libs = table.translate(config.getlinks(cfg, "siblings", "fullpath"), function (p)
			return project.getrelative(cfg.workspace, path.join(cfg.project.location, p))
		end)
		local cfg_output = outputFilename(cfg)
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

		local deps = table.join(final_dependency, extrafiles, prelink_dependency)
		addBuild(cfg, cfg_output, extra_outputs, command_rule, table.join(objfiles, libs), {}, deps, {})
		outputs = {cfg_output}
	else
		local handler = ninja.handlers[cfg.language]
		if not handler then
			p.error('Expected registered ninja handler action for target ' .. cfg.language)
		end
		outputs = handler.targetRules(cfg, toolset)
	end

	p.outln("")
	if #cfg.postbuildcommands > 0 or cfg.postbuildmessage then
		addBuild(cfg, key, {}, "phony", {"postbuild_" .. getKey(cfg)}, {}, {}, {})
	else
		addBuild(cfg, key, {}, "phony", outputs, {}, {}, {})
	end
	p.outln("")

	path.getDefaultSeparator = oldGetDefaultSeparator
end

-- generate all build files for every project configuration
function ninja.generateProject(prj)
	if not canGenerate(prj) then
		return
	end
	for cfg in project.eachconfig(prj) do
		p.generate(cfg, projectCfgFilename(cfg), generateProjectCfg)
	end
end

include("_preload.lua")

return ninja
