//////////////////////////////////////////////////////////////////////
//                                                                  //
//  CluelessPlus - an noai-AI                                       //
//                                                                  //
//////////////////////////////////////////////////////////////////////
// 
// Clueless need some help from you in order to function. First, and
// most important he would be happy if you turn off build-on-slope in 
// the patch-settings. This is because he can only build roads from 
// center to center (of tiles).
// 
// Also he prefers flat, smooth maps with low sea-level. The map should
// have low amount of towns and no industries. Industries are big and 
// scary. Clueless don't know how to build around them.
//
// He haven't interacted that much with players so be kind to him.  
// Don't build nasty railways that block his way. He don't know how
// to cross them yet.
//
// 2009-07-27: Note that the text above was written for Clueless -
// the original. CluelessPlus uses the library path finder that 
// is much better at path finding. 
//
// Author: Zuu (Leif Linse), user Zuu @ tt-forums.net
// Purpose: To play around with the noai framework.
//               - Not to make the next big thing.
//
// License: GNU GPL - version 2

//////////////////////////////////////////////////////////////////////
//                                                                  //
//  CLASS: FCluelessPlusPlusAI - registration of the ai             //
//                                                                  //
//////////////////////////////////////////////////////////////////////
class FCluelessPlusPlusAI extends AIInfo {
	function GetAuthor()      { return "Zuu"; }
	function GetName()        { return "CluelessPlus"; }
	function GetShortName()   { return "CLUP"; } // CLUP is the non SVN short name. CLUS is used by the SVN development edition
	function GetDescription() { return "CluelessPlus connects towns and industries using road and air transport. CluelessPlus tries to do its job without causing major jams for other transport companies using jam detection mechanisms."; }
	function GetAPIVersion()  { return "1.1"; }
	function GetVersion()     { return 32; }
	function MinVersionToLoad() { return 1; }
	function GetDate()        { return "2011-12-10"; }
	function GetUrl()         { return "http://junctioneer.net/o-ai/CLUP"; }
	function UseAsRandomAI()  { return true; }
	function CreateInstance() { return "CluelessPlus"; }

	function GetSettings() {
		AddSetting({name = "use_rvs", description = "Enable road vehicles", easy_value = 1, medium_value = 1, hard_value = 1, custom_value = 1, flags = AICONFIG_BOOLEAN | AICONFIG_INGAME});
		AddSetting({name = "use_planes", description = "Enable aircrafts", easy_value = 1, medium_value = 1, hard_value = 1, custom_value = 1, flags = AICONFIG_BOOLEAN | AICONFIG_INGAME});
		//AddSetting({name = "use_trains", description = "Enable trains", easy_value = 1, medium_value = 1, hard_value = 1, custom_value = 1, flags = AICONFIG_BOOLEAN | AICONFIG_INGAME});
		//AddSetting({name = "use_ships", description = "Enable ships", easy_value = 1, medium_value = 1, hard_value = 1, custom_value = 1, flags = AICONFIG_BOOLEAN | AICONFIG_INGAME});

		AddSetting({name = "slow_ai", description = "Think and build slower", easy_value = 1, medium_value = 0, hard_value = 0, custom_value = 0, flags = AICONFIG_BOOLEAN | AICONFIG_INGAME});
		AddSetting({name = "expand_local", description = "Build new connections nearby existing ones (simple growing boundary box)", easy_value = 1, medium_value = 1, hard_value = 0, custom_value = 0, flags = AICONFIG_BOOLEAN | AICONFIG_INGAME});
		AddSetting({name = "allow_competition", description = "Allow competition against existing transport links", easy_value = 0, medium_value = 0, hard_value = 1, custom_value = 1, flags = AICONFIG_BOOLEAN | AICONFIG_INGAME});
		AddSetting({name = "connection_types", description = "", easy_value = 0, medium_value = 2, hard_value = 2, custom_value = 2, min_value = 0, max_value = 2, flags = AICONFIG_INGAME});
		AddSetting({name = "max_num_bus_stops", description = "Maximum number of road stops per station to build" easy_value = 1, medium_value = 2, hard_value = 4, custom_value = 4, flags = AICONFIG_INGAME, min_value = 1, max_value = 16});
		AddSetting({name = "enable_magic_dtrs", description = "Allow usage of drive-trough road stops terminated with a depot", easy_value = 0, medium_value = 1, hard_value = 1, custom_value = 1, flags = AICONFIG_BOOLEAN | AICONFIG_INGAME});
		AddSetting({name = "log_level", description = "Debug: Log level (higher = print more)", easy_value = 1, medium_value = 1, hard_value = 1, custom_value = 1, flags = AICONFIG_INGAME, min_value = 1, max_value = 3});
		AddSetting({name = "debug_signs", description = "Debug: Build debug signs", easy_value = 0, medium_value = 0, hard_value = 0, custom_value = 0, flags = AICONFIG_BOOLEAN | AICONFIG_INGAME});
		AddSetting({name = "enable_timers", description = "Debug: Clock AI performance (can't be changed in-game)", easy_value = 0, medium_value = 0, hard_value = 0, custom_value = 0, flags = AICONFIG_BOOLEAN });

		AddLabels("connection_types", {_0 = "Connect towns only", _1 = "Connect industries only", _2 = "Connect both towns and industries" } );
	}
}

/* Tell the core we are an AI */
RegisterAI(FCluelessPlusPlusAI());

