//////////////////////////////////////////////////////////////////////
//                                                                  //
//  CluelessPlus - an noai-AI                                       //
//                                                                  //
//////////////////////////////////////////////////////////////////////
// 
// CluelessPlus need some help from you in order to function. First, and
// most important he would be happy if you turn off build-on-slope in 
// the patch-settings. This is because he can only build roads from 
// center to center (of tiles).
// 
// Also he prefers flat, smooth maps with low sea-level. The map should
// have low amount of towns and no industries. Industries are big and 
// scary. CluelessPlus don't know how to build around them.
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
	function GetShortName()   { return "CLUP"; }
	function GetDescription() { return "An AI that connects town-pairs with bus-links - new in Plus is that it uses library pathfinder and have better management"; }
	function GetAPIVersion()  { return "1.0"; }
	function GetVersion()     { return 19; }
	function MinVersionToLoad() { return 1; }
	function GetDate()        { return "2010-03-20"; }
	function GetUrl()         { return "http://www.tt-forums.net/viewtopic.php?f=65&t=41462"; }
	function UseAsRandomAI()  { return true; }
	function CreateInstance() { return "CluelessPlus"; }

	function GetSettings() {
		AddSetting({name = "slow_ai", description = "Think and build slower", easy_value = 1, medium_value = 0, hard_value = 0, custom_value = 0, flags = AICONFIG_BOOLEAN | AICONFIG_INGAME});
		AddSetting({name = "connection_types", description = "", easy_value = 0, medium_value = 2, hard_value = 2, custom_value = 2, min_value = 0, max_value = 2, flags = AICONFIG_INGAME});
		AddSetting({name = "max_num_bus_stops", description = "Maximum number of bus/truck stops per station to build" easy_value = 1, medium_value = 2, hard_value = 4, custom_value = 4, flags = AICONFIG_INGAME, min_value = 1, max_value = 16});
		AddSetting({name = "log_level", description = "Log level (higher = print more)", easy_value = 1, medium_value = 1, hard_value = 1, custom_value = 1, flags = AICONFIG_INGAME, min_value = 1, max_value = 3});
		AddSetting({name = "debug_signs", description = "Build debug signs", easy_value = 0, medium_value = 0, hard_value = 0, custom_value = 0, flags = AICONFIG_BOOLEAN | AICONFIG_INGAME});

		AddLabels("connection_types", {_0 = "Connect towns only", _1 = "Connect industries only", _2 = "Connect both towns and industries" } );
	}
}

/* Tell the core we are an AI */
RegisterAI(FCluelessPlusPlusAI());

