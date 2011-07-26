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

	static function TownDistance(town1, town2);
	static function StepFunction(t);
	static function TileLocationString(tile);

	static function IsTownInConnectionList(connection_list, check_town, cargo_id = -1); // cargo_id = -1 -> any cargo is enough
	static function IsIndustryInConnectionList(connection_list, check_industry, cargo_id = -1);



	// Creates a string such as 0001
	static function IntToStrFill(int_val, num_digits);

	static function EncodeIntegerInStr(int_val, str_len);
	static function DecodeIntegerFromStr(str);

	// The string str, has to be short enough that there is room to add some extra random data at the end so that an unique name is created
	static function StoreInStationName(station_id, str);
	static function ReadStrFromStationName(station_id);

	// Similar but for vehicle names
	static function StoreInVehicleName(vehicle_id, str);
	static function ReadStrFromVehicleName(vehicle_id);

	// Generic store/read
	static function StoreInObjectName(obj_id, obj_api_class, str);
	static function ReadStrFromObjectName(obj_id, obj_api_class);

	// Why not have a bit fun and use a base that create smilies when you have a 2-digit value. :-)
	static ENCODE_CHARS = ":)D|(/spOo3SP><{}[]$012456789abcdefghijklmnqrtuvwxyzABCEFGHIJKLMNQRTUVWXYZ?&;#=@!\\%";
	//static ENCODE_CHARS = "0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ{}[]$?&<>;/()|#:=@!\\%";
}

function ClueHelper::TownDistance(town1, town2)
{
	return AIMap.DistanceManhattan(AITown.GetLocation(town1), AITown.GetLocation(town2));
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

function ClueHelper::SetSign(tile, message, force = false)
{
	if(AIController.GetSetting("debug_signs") != 1 && force == false)
		return;

	local found = false;
	local sign_list = AISignList();
	foreach(i, _ in sign_list)
	{
		if(AISign.GetLocation(i) == tile)
		{
			if(found)
				AISign.RemoveSign(i);
			else
			{
				if(message == "")
					AISign.RemoveSign(i);
				else
					AISign.SetName(i, message);
				found = true;
			}
		}
	}

	if(!found)
		AISign.BuildSign(tile, message);
}

// Places a sign on tile sign_tile and waits until the sign gets removed
function ClueHelper::BreakPoint(sign_tile)
{
	if(AIController.GetSetting("debug_signs") != 1)
		return;

	if(Helper.HasSign("no_break"))
		return;

	AILog.Warning("Break point reached. -> Remove the \"break\" sign to continue.");
	local sign = AISign.BuildSign(sign_tile, "break");
	while(AISign.IsValidSign(sign)) { AIController.Sleep(1); }
}

function ClueHelper::HasSign(text)
{
	local sign_list = AISignList();
	foreach(i, _ in sign_list)
	{
		if(AISign.GetName(i) == text)
		{
			return true;
		}
	}
	return false;
}
function ClueHelper::ClearAllSigns()
{
	local sign_list = AISignList();
	for(local i = sign_list.Begin(); sign_list.HasNext(); i = sign_list.Next())
	{
		AISign.RemoveSign(i);
	}
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

function ClueHelper::GetPAXCargo()
{
	local cargo_list = AICargoList();
	cargo_list.Valuate(AICargo.HasCargoClass, AICargo.CC_PASSENGERS);
	cargo_list.KeepValue(1);
	cargo_list.Valuate(AICargo.GetTownEffect);
	cargo_list.KeepValue(AICargo.TE_PASSENGERS);

	if(!AICargo.IsValidCargo(cargo_list.Begin()))
	{
		AILog.Error("PAX Cargo do not exist");
	}

	//AILog.Info("PAX Cargo is: " + AICargo.GetCargoLabel(cargo_list.Begin()));

	return cargo_list.Begin();
}

function ClueHelper::MakeTileRectAroundTile(center_tile, radius)
{
	local tile_x = AIMap.GetTileX(center_tile);
	local tile_y = AIMap.GetTileY(center_tile);

	AILog.Info("TileRectAroundTile: tile " + tile_x + ", " + tile_y);

	local x_min = Helper.Clamp(tile_x - radius, 1, AIMap.GetMapSizeX() - 2);
	local x_max = Helper.Clamp(tile_x + radius, 1, AIMap.GetMapSizeX() - 2);
	local y_min = Helper.Clamp(tile_y - radius, 1, AIMap.GetMapSizeY() - 2);
	local y_max = Helper.Clamp(tile_y + radius, 1, AIMap.GetMapSizeY() - 2);

	AILog.Info("TileRectAroundTile: x_min: " + x_min);
	AILog.Info("TileRectAroundTile: x_max: " + x_max);
	AILog.Info("TileRectAroundTile: y_min: " + y_min);
	AILog.Info("TileRectAroundTile: y_max: " + y_max);

	local list = AITileList();
	list.AddRectangle( AIMap.GetTileIndex(x_min, y_min), AIMap.GetTileIndex(x_max, y_max) );

	return list;
}

function ClueHelper::ItemValuator(item)
{
	return item;
}

function ClueHelper::CopyListSwapValuesAndItems(old_list)
{
	local new_list = AIList();
	for(local i = old_list.Begin(); old_list.HasNext(); i = old_list.Next())
	{
		local value = old_list.GetValue(i);
		new_list.AddItem(value, i);
	}

	return new_list;
}

function ClueHelper::GetListMinValue(ai_list)
{
	ai_list.Sort(AIAbstractList.SORT_BY_VALUE, true); // highest last
	return ai_list.GetValue(ai_list.Begin());
}

function ClueHelper::GetListMaxValue(ai_list)
{
	ai_list.Sort(AIAbstractList.SORT_BY_VALUE, false); // highest first
	return ai_list.GetValue(ai_list.Begin());
}

function ClueHelper::Clamp(value, min, max)
{
	if(value < min)
		value = min;
	else if(value > max)
		value = max;

	return value;
}

function ClueHelper::Min(a, b)
{
	return a < b? a : b;
}
function ClueHelper::Max(a, b)
{
	return a > b? a : b;
}

function ClueHelper::Abs(a)
{
	return a >= 0? a : -a;
}

function ClueHelper::IntToStrFill(int_val, num_digits)
{
	local str = int_val.tostring();

	while(str.len() < num_digits)
	{
		str = "0" + str;
	}

	return str;
}

function ClueHelper::EncodeIntegerInStr(int_val, str_len)
{
	// First convert the integer value into the new base
	local i = int_val;
	local base = ClueHelper.ENCODE_CHARS.len();

	local str = "";

	while(i >= base)
	{
		local div = (i / base).tointeger();
		local reminder = i - div * base;

		str = ClueHelper.ENCODE_CHARS[reminder].tochar() + str;

		i = div;
	}

	str = ClueHelper.ENCODE_CHARS[i].tochar() + str;

	// second append zeros at the beginning ot fill up the entire str_len

	while(str.len() < str_len)
	{
		str = ClueHelper.ENCODE_CHARS[0].tochar() + str;
	}

	return str;
}

function ClueHelper::DecodeIntegerFromStr(str)
{
	local base10_val = 0;

	for(local i = 0; i < str.len(); ++i)
	{
		local c = str[i];
		local enc_base_val = ClueHelper.ENCODE_CHARS.find(c);

		base10_val += (str.len() - i) * enc_base_val;
	}

	return base10_val;
}

function ClueHelper::StoreInStationName(station_id, str)
{
	return ClueHelper.StoreInObjectName(station_id, AIBaseStation, str);
}

function ClueHelper::ReadStrFromStationName(station_id)
{
	return ClueHelper.ReadStrFromObjectName(station_id, AIBaseStation);
}

function ClueHelper::StoreInVehicleName(vehicle_id, str)
{
	return ClueHelper.StoreInObjectName(vehicle_id, AIVehicle, str);
}

function ClueHelper::ReadStrFromVehicleName(vehicle_id)
{
	return ClueHelper.ReadStrFromObjectName(vehicle_id, AIVehicle);
}

function ClueHelper::StoreInObjectName(obj_id, obj_api_class, str)
{
	local i = 1;
	local obj_name = str + " " + ClueHelper.EncodeIntegerInStr(i, 2);

	while(!obj_api_class.SetName(obj_id, obj_name))
	{
		Log.Info(AIError.GetLastErrorString(), Log.LVL_DEBUG)
		i++;
		obj_name = str + " " + ClueHelper.EncodeIntegerInStr(i, 2);

		if(i > 9000)
		{
			AILog.Error("Failed to give name to object 9000 times");
			return false;
		}
	}

	return true;
}

function ClueHelper::ReadStrFromObjectName(obj_id, obj_api_class)
{
	local name = obj_api_class.GetName(obj_id);
	
	local str = name.slice(0, name.len() - 3);
	return str;
}

