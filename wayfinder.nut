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


class WFLink
{
	from = null;
	to = null;
	has_obstacle = false;

	tiles = null;

	constructor(from, to, hasObstacle)
	{
		this.from = from;
		this.to = to;
		this.has_obstacle = hasObstacle;

		this.tiles = [];
	}
}


////  CLASS: WayFinder  ////

class WayFinder
{
	from = null;
	to = null;

	from_x = null;
	from_y = null;
	to_x = null;
	to_y = null;

	pf_state = null;
	PF_STATE_FIND_OBSTACLES = null;
	PF_STATE_FIND_PATH = null;

	transport_mode = null;
	TM_RAIL = null;
	TM_ROAD = null;

	obstacles = null;
	link_list = null;
	scan_area = null;
	scan_area_from_tile = null;
	scan_area_to_tile = null;

	num_optimal_path_tiles = null;
	num_obstacle_tiles = null;

	find_obstacles_data = null;

	constructor(transportMode)
	{
		this.from = -1;
		this.to = -1;

		this.PF_STATE_FIND_OBSTACLES = "find obstacles";
		this.PF_STATE_FIND_PATH = "find path";
		this.pf_state = PF_STATE_FIND_OBSTACLES;

		this.TM_ROAD = "road";
		this.TM_RAIL = "rail";
		this.transport_mode = transportMode;

		this.obstacles = [];
		this.link_list = [];
		this.scan_area = null;
		this.scan_area_from_tile = -1;
		this.scan_area_to_tile = -1;

		this.num_optimal_path_tiles = 0;
		this.num_obstacle_tiles = 0;

		this.find_obstacles_data = null; // for storing a table with data used in PF_STATE_FIND_OBSTACLES
	}

	function InitializePath(from, to);
	function FindPath(ticks);
}

function WayFinder::InitializePath(from, to)
{
	Helper.ClearAllSigns();

	// set from/to
	this.from = from[0];
	this.to = to[0];

	// Create scan_area tile rect
	from_x = AIMap.GetTileX(this.from);
	to_x = AIMap.GetTileX(this.to);
	from_y = AIMap.GetTileY(this.from);
	to_y = AIMap.GetTileY(this.to);

	local x_min = Helper.Min(from_x, to_x);
	local y_min = Helper.Min(from_y, to_y);
	local x_max = Helper.Max(from_x, to_x);
	local y_max = Helper.Max(from_y, to_y);


	// increase the rect by 10 in each direction, but not beyond the map edge
	local enlarge_by = 10;
	x_min = Helper.Clamp(x_min - enlarge_by, 0, AIMap.GetMapSizeX() - 1);
	x_max = Helper.Clamp(x_max + enlarge_by, 0, AIMap.GetMapSizeX() - 1);
	y_min = Helper.Clamp(y_min - enlarge_by, 0, AIMap.GetMapSizeY() - 1);
	y_max = Helper.Clamp(y_max + enlarge_by, 0, AIMap.GetMapSizeY() - 1);

	AILog.Info("x_min = "  + x_min);
	AILog.Info("x_max = "  + x_max);
	AILog.Info("y_min = "  + y_min);
	AILog.Info("y_max = "  + y_max);

	scan_area_from_tile = AIMap.GetTileIndex(x_min, y_min);
	scan_area_to_tile = AIMap.GetTileIndex(x_max, y_max);
	scan_area = AITileList();
	scan_area.AddRectangle(scan_area_from_tile, scan_area_to_tile);

	// set pf_state
	pf_state = PF_STATE_FIND_OBSTACLES;

	// debug output
	Helper.SetSign(this.from, "From");
	Helper.SetSign(this.to,   "To");

	Helper.SetSign(AIMap.GetTileIndex(x_min, y_min), "<>");
	Helper.SetSign(AIMap.GetTileIndex(x_max, y_min), "<>");
	Helper.SetSign(AIMap.GetTileIndex(x_min, y_max), "<>");
	Helper.SetSign(AIMap.GetTileIndex(x_max, y_max), "<>");

	AILog.Info("WayFinder initialized");
}

function IsObstacleTile(tile)
{
	// Rail or road tiles are not seen as obstacles as they can usually be bridged/tunneled
	return !AITile.IsBuildable(tile) && !AIRoad.IsRoadTile(tile) && !AIRail.IsRailTile(tile);
}

function WayFinder::FindObstacles_NextTile(next_tile, debug_sign_label)
{
	// Move prev + curr tile forward
	find_obstacles_data.prev_tile = find_obstacles_data.curr_tile;
	find_obstacles_data.curr_tile = next_tile;

	// Display debug sign
	Helper.SetSign( find_obstacles_data.curr_tile, debug_sign_label );

	// Has the obstacle state (existence of an obstacle at tile) of current tile changed since last tile?
	local is_obstacle = IsObstacleTile(find_obstacles_data.curr_tile);
	if(is_obstacle != find_obstacles_data.in_obstacle)
	{
		// Yes - end current link and start a new one

		local new_link = WFLink(null, null, is_obstacle);
		if(find_obstacles_data.in_obstacle)
		{
			// Exiting obstacle -> put link connection point at current tile (just after obstacle)
			find_obstacles_data.curr_link.to = find_obstacles_data.curr_tile;
			find_obstacles_data.curr_link.tiles.append(find_obstacles_data.curr_tile);
			new_link.from = find_obstacles_data.curr_tile;
		}
		else
		{
			// Entering an obstacle -> put link connection point before current tile (just before obstacle)
			find_obstacles_data.curr_link.to = find_obstacles_data.prev_tile;
			new_link.from = find_obstacles_data.prev_tile;
			new_link.tiles.append(find_obstacles_data.prev_tile);
		}

		new_link.tiles.append(find_obstacles_data.curr_tile);
		link_list.append(find_obstacles_data.curr_link);
		find_obstacles_data.curr_link = new_link;
		find_obstacles_data.in_obstacle = is_obstacle;
	}
	else
	{
		// No obstacle state change -> Just continue on current link by adding curr_tile to list of all tiles in that link
		find_obstacles_data.curr_link.tiles.append(find_obstacles_data.curr_tile);
	}

	// Count number of tiles + obstacle tiles
	find_obstacles_data.num_tiles++;
	if(is_obstacle) find_obstacles_data.num_obstacle_tiles++;
	if(is_obstacle) Helper.SetSign( find_obstacles_data.curr_tile, "o" );
}

function WayFinder::FindPath(ticks)
{
	local start_tick = AIController.GetTick();

	while(ticks == -1 || start_tick + ticks > AIController.GetTick())
	{
		if(pf_state == PF_STATE_FIND_OBSTACLES)
		{
			// Walk through the optimal path
			if(find_obstacles_data == null)
			{
				// Init data structure for this PF state
				find_obstacles_data = { 
					dir_x = from_x < to_x? 1 : -1,
					dir_y = from_y < to_y? 1 : -1,
					x = from_x,
					y = from_y,
					prev_tile = -1, 
					curr_tile = AIMap.GetTileIndex(from_x, from_y),
					in_obstacle = null,
					curr_link = null,
					num_tiles = 0,
					num_obstacle_tiles = 0};

				find_obstacles_data.in_obstacle = IsObstacleTile(find_obstacles_data.curr_tile);
				find_obstacles_data.curr_link = WFLink(find_obstacles_data.curr_tile, null, find_obstacles_data.in_obstacle);


				// Add start tile to tile list of first link
				find_obstacles_data.curr_link.tiles.append(find_obstacles_data.curr_link.from);
			}

			// Get the optimal path (only consider obstacles on the optimal path)
			//local optimal_path_tiles = AITileList();

			// shorter data table pointer name
			local data = find_obstacles_data;

			while(data.x != to_x)
			{
				data.x += data.dir_x;
				FindObstacles_NextTile(AIMap.GetTileIndex(data.x, data.y), "x");

				// Rail can go diagonal
				if(this.transport_mode == TM_RAIL && data.y != to_y)
				{
					data.y += data.dir_y;
					FindObstacles_NextTile(AIMap.GetTileIndex(data.x, data.y), "y2");
				}
			}

			while(data.y != to_y)
			{
				data.y += data.dir_y;
				FindObstacles_NextTile(AIMap.GetTileIndex(data.x, data.y), "y");
			}

			// Add last tile and terminate last link
			FindObstacles_NextTile(AIMap.GetTileIndex(data.x, data.y), ".");
			data.curr_link.to = data.curr_tile;
			link_list.append(data.curr_link);
			data.curr_link = null;

			AILog.Info("Num tiles " + data.num_tiles);
			AILog.Info("Num obstacle tiles " + data.num_obstacle_tiles);
			AILog.Info("Num links " + link_list.len());

			/*
			// Check which optimal path tiles that have an obstacle
			local obstacle_tiles = AITileList();
			obstacle_tiles.AddList(optimal_path_tiles);
			obstacle_tiles.Valuate(IsObstacleTile);
			obstacle_tiles.KeepValue(0);
			*/

			foreach(link in this.link_list)
			{
				AILog.Info("Link start: " + Tile.GetTileString(link.from));
				AILog.Info("Link to: " + Tile.GetTileString(link.to));
				AILog.Info("Link has_obstacle: " + link.has_obstacle);

				local obstacle_observed = false;
				foreach(tile in link.tiles)
				{
					Helper.SetSign(tile, ".");
					if(IsObstacleTile(tile))
					{
						obstacle_observed = true;
						//break;
					}
				}

				Helper.SetSign(link.from, "f");
				Helper.SetSign(link.to, "t");

				AILog.Info("Link obstacle_observed: " + link.has_obstacle);
				AILog.Info("----------------------------------------------");
			}


			pf_state = PF_STATE_FIND_PATH;
			find_obstacles_data = null; // allow the memory used for this pf_state to be freed.


		}
		else if(pf_state == PF_STATE_FIND_PATH)
		{

		}

	}

	return true;
}
