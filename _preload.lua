--
-- Name:        premake-ninja/_preload.lua
-- Purpose:     Define the ninja action.
-- Author:      Dmitry Ivanov
-- Modified by: Jan "GamesTrap" Schürkamp
-- Created:     2015/07/04
-- Updated:     2025/11/11
-- Copyright:   (c) 2015 Dmitry Ivanov, (c) 2023-2025 Jan "GamesTrap" Schürkamp
--

local p = premake

newoption
{
	trigger = "experimental-enable-cxx-modules",
	description = "Enable C++20 Modules support. This adds code scanning and collation step to the Ninja build."
}

newoption
{
	trigger = "experimental-modules-scan-all",
	description = "Enable scanning for all C++ translation units. By default only files ending with .cxx, .cxxm, .ixx, .cppm, .c++m, .ccm and .mpp are scanned."
}

newaction
{
	-- Metadata for the command line and help system
	trigger			= "ninja",
	shortname		= "ninja",
	description		= "Ninja is a small build system with a focus on speed",

	-- The capabilities of this action
	valid_kinds		= {"ConsoleApp", "WindowedApp", "SharedLib", "StaticLib", "None"}, -- Not supported: Makefile, Packaging, SharedItems, Utility
	valid_languages	= {"C", "C++"},
	valid_tools		= {cc = { "gcc", "clang", "msc" }},

	toolset = iif(os.target() == "windows", "msc-v143", --msc-v143 = Microsoft Visual Studio 2022
			  iif(os.target() == "macosx", "clang", "gcc")),

	-- Workspace and project generation logic
	onWorkspace = function(wks)
		p.eol("\r\n")
		p.indent("  ")
		p.generate(wks, "build.ninja", p.modules.ninja.generateWorkspace)
	end,
	onProject = function(prj)
		p.eol("\r\n")
		p.indent("  ")
		p.modules.ninja.generateProject(prj)
	end,
	onBranch = function(prj)
		p.eol("\r\n")
		p.indent("  ")
		p.modules.ninja.generateProject(prj)
	end,
	onCleanSolution = function(sln)
		-- TODO
	end,
	onCleanProject = function(prj)
		-- TODO
	end,
	onCleanTarget = function(prj)
		-- TODO
	end,
}

--
-- Decide when the full module should be loaded.
--

return function(cfg)
	return (_ACTION == "ninja")
end
