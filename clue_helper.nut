//////////////////////////////////////////////////////////////////////
//                                                                  //
//  CluelessPlus - an noai-AI                                       //
//                                                                  //
//////////////////////////////////////////////////////////////////////
// 
// Author: Zuu (Leif Linse), user Zuu @ tt-forums.net
// Purpose: To play around with the noai framework.
//               - Not to make the next big thing.
// Copyright: Leif Linse - 2008-2011
// License: GNU GPL - version 2

// This class contain helper functions that has not been merged into 
// the common Helper class for both CluelessPlus and PAXLink
class ClueHelper {

	static function StepFunction(t);
	static function TileLocationString(tile);

	static function IsTownInConnectionList(connection_list, check_town, cargo_id = -1); // cargo_id = -1 -> any cargo is enough
	static function IsIndustryInConnectionList(connection_list, check_industry, cargo_id = -1);
}

function ClueHelper::StepFunction(t)
{
	if(t>=0)
		return 1;

	return 0;
}

function ClueHelper::TileLocationString(tile)
{
	return "(" + AIMap.GetTileX(tile) + ", " + AIMap.GetTileY(tile) + ")";
}

function ClueHelper::IsTownInConnectionList(connection_list, check_town, cargo_id = -1)
{
	foreach(val in connection_list)
	{
		foreach(town in val.town)
		{
			if(town == check_town && (cargo_id == -1 || val.cargo_type == cargo_id))
			{
				return true;
			}
		}
	}
	return false;
}

function ClueHelper::IsIndustryInConnectionList(connection_list, check_industry, cargo_id = -1)
{
	foreach(val in connection_list)
	{
		foreach(industry in val.industry)
		{
			if(industry == check_industry && (cargo_id == -1 || val.cargo_type == cargo_id))
			{
				Log.Info(AIIndustry.GetName(check_industry) + " is not used by any connection for cargo_id == " + cargo_id, Log.LVL_DEBUG);
				return true;
			}
		}
	}
	return false;
}
