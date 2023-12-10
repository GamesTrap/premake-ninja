--
-- Name:        premake-ninja/.modules/collate_modules/_preload.lua
-- Purpose:     Define the collate_modules action.
-- Author:      Jan "GamesTrap" Schürkamp
-- Created:     2023/12/10
-- Copyright:   (c) 2023 Jan "GamesTrap" Schürkamp
--

local p = premake

newoption
{
	trigger = "modmapfmt",
	description = "",
	allowed =
	{
		{ "clang", "Clang" },
		{ "gcc", "GCC" },
		{ "msvc", "MSVC" },
	}
}

newoption
{
	trigger = "dd",
	description = "",
}

newoption
{
	trigger = "ddi",
	description = "",
}

newaction
{
	-- Metadata for the command line and help system
	trigger			= "collate_modules",
	shortname		= "collate_modules",
	description		= "collate_modules is a small utility to generate modmap files from ddi",

	execute = function()
		p.modules.collate_modules.CollateModules()
	end
}

return p.modules.collate_modules
