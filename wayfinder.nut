//////////////////////////////////////////////////////////////////////
//                                                                  //
//  CluelessPlus - an noai-AI                                       //
//                                                                  //
//////////////////////////////////////////////////////////////////////
// 
// Author: Zuu (Leif Linse), user Zuu @ tt-forums.net
// Purpose: To play around with the noai framework.
//               - Not to make the next big thing.
// Copyright: Leif Linse - 2008-2010
// License: GNU GPL - version 2

// WayFinder is an unfinished attempt to create a path finder that tries
// to identify obstacles and then tries to find a way inbetween the 
// obstacles.

////  CLASS: WayFinder  ////

/*class WFPathNode
{
	parent = null;
	tile = null;

	constructor(tile, parent)
	{
		this.tile = tile;
		this.parent = parent;
	}

	function GetParent();
	function GetTile();
}

function WFPathNode::GetParent()
{
	return parent;
}

function WFPathNode::GetTile()
{
	return tile;
}*/

////  CLASS: WayFinder  ////

class WayFinder
{
	from = null;
	to = null;

	mode = null;
	MODE_FIND_OBSTACLES = null;
	MODE_FIND_PATH = null;

	obstacles = null;
	scan_area = null;
	scan_area_from_tile = null;
	scan_area_to_tile = null;

	constructor()
	{
		from = -1;
		to = -1;

		MODE_FIND_OBSTACLES = "find obstacles";
		MODE_FIND_PATH = "find path";
		mode = MODE_FIND_OBSTACLES;

		obstacles = [];
		scan_area = null;
		scan_area_from_tile = -1;
		scan_area_to_tile = -1;
	}

	function InitializePath(from, to);
	function FindPath(ticks);
}

function WayFinder::InitializePath(from, to)
{
	// set from/to
	this.from = from[0];
	this.to = to[0];

	// Create scan_area tile rect
	local x1 = AIMap.GetTileX(this.from);
	local x2 = AIMap.GetTileX(this.to);
	local y1 = AIMap.GetTileY(this.from);
	local y2 = AIMap.GetTileY(this.to);

	local x_min = Helper.Min(x1, x2);
	local y_min = Helper.Min(y1, y2);
	local x_max = Helper.Max(x1, x2);
	local y_max = Helper.Max(y1, y2);


	// increase the rect by 10 in each direction, but not beyond the map edge
	local enlarge_by = 10;
	x_min = Helper.Clamp(x_min - enlarge_by, 0, AIMap.GetMapSizeX() - 1);
	x_max = Helper.Clamp(x_max + enlarge_by, 0, AIMap.GetMapSizeX() - 1);
	y_min = Helper.Clamp(y_min - enlarge_by, 0, AIMap.GetMapSizeY() - 1);
	y_max = Helper.Clamp(y_max + enlarge_by, 0, AIMap.GetMapSizeY() - 1);

	scan_area_from_tile = AIMap.GetTileIndex(x_min, y_min);
	scan_area_to_tile = AIMap.GetTileIndex(x_max, y_max);
	scan_area = AITileList();
	scan_area.AddRectangle(scan_area_from_tile, scan_area_to_tile);

	// set mode
	mode = MODE_FIND_OBSTACLES;

	// debug output
	Helper.SetSign(this.from, "From");
	Helper.SetSign(this.to,   "To");

	Helper.SetSign(AIMap.GetTileIndex(x_min, y_min), "<>");
	Helper.SetSign(AIMap.GetTileIndex(x_max, y_min), "<>");
	Helper.SetSign(AIMap.GetTileIndex(x_min, y_max), "<>");
	Helper.SetSign(AIMap.GetTileIndex(x_max, y_max), "<>");

	AILog.Info("WayFinder initialized");
}

function WayFinder::FindPath(ticks)
{
	if(mode == MODE_FIND_OBSTACLES)
	{
		local obstacle_tiles = AIList();
		local water_tiles = AIList();
		water_tiles.AddList(scan_area);

		water_tiles.Valuate(AITile.IsWaterTile);
		water_tiles.KeepValue(1);
		obstacle_tiles.AddList(water_tiles);
		
		
		
	}
	else if(mode == MODE_FIND_PATH)
	{
	}


	return false;
}

