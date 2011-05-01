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


import("pathfinder.road", "RPF", 3);
require("wayfinder.nut");

class MyRoadPF extends RPF {}

function MyRoadPF::InitializePath(sources, goals)
{
	::RPF.InitializePath(sources, goals);
}

function MyRoadPF::_Cost(path, new_tile, new_direction, self)
{
	local cost = ::RPF._Cost(path, new_tile, new_direction, self);

	// Penalty for crossing railways without bridge
	if(AITile.HasTransportType(new_tile, AITile.TRANSPORT_RAIL)) cost += 800;

	// Try to build around drive through stops
	if(AIRoad.IsDriveThroughRoadStationTile(new_tile)) cost += 1000;

	if(path != null)
	{
		// Path is null on first node
		local prev_tile = path.GetTile();

		// If it is possible to reach the current tile from next tile but not in the other direction, then it is a one-way road
		// in the wrong direction.
		if(AIRoad.AreRoadTilesConnected(new_tile, prev_tile) && !AIRoad.AreRoadTilesConnected(prev_tile, new_tile))
		{
			// Don't try to use one-way roads from the back
			Log.Info("One-way road detected", Log.LVL_DEBUG);
			cost += 10000;
		}
	}

	return cost;
}

function MyRoadPF::_Neighbours(path, cur_node, self)
{
	local tiles = ::RPF._Neighbours(path, cur_node, self);

	local offsets = [AIMap.GetTileIndex(0, 1), AIMap.GetTileIndex(0, -1),
					 AIMap.GetTileIndex(1, 0), AIMap.GetTileIndex(-1, 0)];
	/* Check all tiles adjacent to the current tile. */
	foreach(offset in offsets) 
	{
		//local next_tile = cur_node + offset;
		local cur_height = AITile.GetMaxHeight(cur_node);
		if(AITile.GetSlope(cur_node) != AITile.SLOPE_FLAT) continue;

		local bridge_length = 2;
		local i_tile = cur_node + offset;
		
		while(AITile.HasTransportType(i_tile, AITile.TRANSPORT_RAIL) || AITile.IsWaterTile(i_tile)) // try to bridge over rail or flat water (rivers/canals)
		{
			i_tile += offset;
			bridge_length++;
		}

		if(bridge_length <= 2) continue; // Nothing to bridge over
		if(!Tile.IsStraight(cur_node, i_tile)) continue; // Detect map warp-arounds

		local bridge_list = AIBridgeList_Length(bridge_length);
		if(bridge_list.IsEmpty() || !AIBridge.BuildBridge(AIVehicle.VT_ROAD, bridge_list.Begin(), cur_node, i_tile)) {
			continue; // not possible to build bridge here
		}
		
		// Found possible bridge over rail
		tiles.push([i_tile, 0xFF]);
	}

	return tiles;
}

class RoadBuilder {

	pf_loops_used = null;
	build_loops_used = null;

	constructor() {
		this.pf_loops_used = 0;
		this.build_loops_used = 0;
	}
	

	// If repair_existing == true, then it should as much as possible avoid building road next to existing to get a tiny bit less penalty

	static CONNECT_SUCCEEDED = 0;
	static CONNECT_FAILED_OTHER = 1;
	static CONNECT_FAILED_TIME_OUT = 2;
	static CONNECT_FAILED_NO_PATH_FOUND = 3;
	static CONNECT_FAILED_OUT_OF_TRIES = 4;

	function ConnectTiles(tile1, tile2, repair_existing = false, max_loops = 4000, call_count = 1);

	// Call this function after ConnectTiles have returned to see how many loops that were used.
	// The values are accumulated since the instance was created in case ConnectTiles is called
	// multiple times or has to make recursive calls.
	function GetPFLoopsUsed();
	function GetBuildLoopsUsed();

	/* Returns a table which always contain a key 'succeeded' that is true or false depeding
	 * on if the function succeeded or not.
	 *
	 * If succeeded is true then the table also contains
	 * - bridge_start = <tile>
	 * - bridge_end = <tile>
	 *
	 * If succeeded is false then the table also contains
	 * - permanently = <boolean>
	 */
	static function ConvertRailCrossingToBridge(rail_tile, prev_tile);
	//static function RemoveRoad(from_tile, to_tile);

	static function RemoveRoadUpToRoadCrossing(start_tile);
}


function RoadBuilder::ConnectTiles(tile1, tile2, repair_existing = false, max_loops = 4000, call_count = 1) 
{
	Log.Info("Connecting tiles - try no: " + call_count, Log.LVL_SUB_DECISIONS);

	local pathfinder = MyRoadPF();
	//local pathfinder = WayFinder();

	local play_slow = AIController.GetSetting("slow_ai");

	Helper.SetSign(tile1, "from" + call_count);
	Helper.SetSign(tile2, "to" + call_count);

	pathfinder.InitializePath([tile1], [tile2]);
	pathfinder.cost.no_existing_road = repair_existing? 300 : 60; // default = 40
	pathfinder.cost.tile = 80; // default = 100
	pathfinder.cost.max_bridge_length = 15; // default = 10

	// Set maximum cost as some constant plus a factor times the cost of the optimal path to avoid to long detours
	// factor = 5/2 aka 2,5
	pathfinder.cost.max_cost = 7000 + (pathfinder.cost.tile * AIMap.DistanceManhattan(tile1, tile2) * 5) / 2 + pathfinder.cost.turn;

	local path = false;
	local i = 0;
	local STEP_SIZE = 100;
	while (path == false) {
		path = pathfinder.FindPath(STEP_SIZE);
		AIController.Sleep(1);

		if(play_slow == 1)
			AIController.Sleep(5);

		i += STEP_SIZE;
		this.pf_loops_used += STEP_SIZE;

		if (max_loops != -1 && i > max_loops)
		{
			Log.Info("Finding path took to long -> abort", Log.LVL_SUB_DECISIONS);
			return RoadBuilder.CONNECT_FAILED_TIME_OUT;
		}
	}

	Log.Info("PF loops used:" + i, Log.LVL_DEBUG);

	if(path == null) {
		Log.Warning("Failed to find path", Log.LVL_INFO);
		return RoadBuilder.CONNECT_FAILED_NO_PATH_FOUND;
	}
	Log.Info("Path found, now start building!", Log.LVL_INFO);

	//AISign.BuildSign(path.GetTile(), "Start building");

	while (path != null) {
		local par = path.GetParent();
		//Helper.SetSign(path.GetTile(), "tile");
		if (par != null) {
			local last_node = path.GetTile();
			//Helper.SetSign(par.GetTile(), "par");
			if (AIMap.DistanceManhattan(path.GetTile(), par.GetTile()) == 1 ) {
				if (AIRoad.AreRoadTilesConnected(path.GetTile(), par.GetTile())) {
					// there is already a road here, don't do anything
					//Helper.SetSign(par.GetTile(), "conn");

					if (AITile.HasTransportType(par.GetTile(), AITile.TRANSPORT_RAIL))
					{
						// Found a rail track crossing the road, try to bridge it
						Helper.SetSign(par.GetTile(), "rail!");

						local bridge_result = RoadBuilder.ConvertRailCrossingToBridge(par.GetTile(), path.GetTile());
						if (bridge_result.succeeded == true)
						{
							// TODO update par/path
							local new_par = par;
							while (new_par != null && new_par.GetTile() != bridge_result.bridge_start && new_par.GetTile() != bridge_result.bridge_end)
							{
								new_par = new_par.GetParent();
							}
							
							if (new_par == null)
							{
								Log.Warning("Tried to convert rail crossing to bridge but somehow got lost from the found path.", Log.LVL_INFO);
							}
							par = new_par;
						}
						else
						{
							Log.Info("Failed to bridge railway crossing", Log.LVL_INFO);
						}
					}

				} else {

					/* Look for longest straight road and build it as one build command */
					local straight_begin = path;
					local straight_end = par;

					if(play_slow != 1) // build piece by piece in slow-mode
					{
						local prev = straight_end.GetParent();
						while(prev != null && 
								Tile.IsStraight(straight_begin.GetTile(), prev.GetTile()) &&
								AIMap.DistanceManhattan(straight_end.GetTile(), prev.GetTile()) == 1)
						{
							straight_end = prev;
							prev = straight_end.GetParent();
						}

						/* update the looping vars. (path is set to par in the end of the main loop) */
						par = straight_end;
					}

					//AISign.BuildSign(path.GetTile(), "path");
					//AISign.BuildSign(par.GetTile(), "par");

					if (!AIRoad.BuildRoad(straight_begin.GetTile(), straight_end.GetTile())) {
						/* An error occured while building a piece of road. TODO: handle it. 
						 * Note that is can also be the case that the road was already build. */

						Helper.SetSign(straight_begin.GetTile(), "fail from");
						Helper.SetSign(straight_end.GetTile(), "fail to");
						Log.Warning("Build straight failed", Log.LVL_SUB_DECISIONS);


						// Try PF again
						if (call_count > 4 || 
								RoadBuilder.ConnectTiles(tile1, path.GetTile(), false, Helper.Max(max_loops, 4000), call_count+1) != RoadBuilder.CONNECT_SUCCEEDED)
						{
							Log.Warning("After several tries the road construction could still not be completed", Log.LVL_INFO);
							return RoadBuilder.CONNECT_FAILED_OUT_OF_TRIES;
						}
						else
						{
							return RoadBuilder.CONNECT_SUCCEEDED;
						}
					}

					if(play_slow == 1)
						AIController.Sleep(10);
				}
			} else {
				if (AIBridge.IsBridgeTile(path.GetTile())) {
					/* A bridge exists */

					Helper.SetSign(path.GetTile(), "bridge exists", false);

					// Check if it is a bridge with low speed
					local bridge_type_id = AIBridge.GetBridgeID(path.GetTile())
					local bridge_max_speed = AIBridge.GetMaxSpeed(bridge_type_id);

					if(bridge_max_speed < 100) // low speed bridge
					{
						Helper.SetSign(path.GetTile(), "exists slow", false);

						local other_end_tile = AIBridge.GetOtherBridgeEnd(path.GetTile());
						local bridge_length = AIMap.DistanceManhattan( path.GetTile(), other_end_tile ) + 1;
						local bridge_list = AIBridgeList_Length(bridge_length);

						bridge_list.Valuate(AIBridge.GetMaxSpeed);
						bridge_list.KeepAboveValue(bridge_max_speed);

						if(!bridge_list.IsEmpty())
						{
							Helper.SetSign(path.GetTile(), "exists upgrade", false);
							// There is a faster bridge

							// Pick a random faster bridge than the current one
							bridge_list.Valuate(AIBase.RandItem);
							bridge_list.Sort(AIAbstractList.SORT_BY_VALUE, AIAbstractList.SORT_ASCENDING);

							Log.Info("Try to upgrade slow existing bridge", Log.LVL_SUB_DECISIONS);

							// Upgrade the bridge
							AIBridge.BuildBridge( AIVehicle.VT_ROAD, bridge_list.Begin(), path.GetTile(), other_end_tile );

							Log.Info("Upgrade err: " + AIError.GetLastErrorString() );
						}
					}

				} else if(AITunnel.IsTunnelTile(path.GetTile())) {
					/* A tunnel exists */
					
					// All tunnels have equal speed so nothing to do
				} else {
					/* Build a bridge or tunnel. */

					/* If it was a road tile, demolish it first. Do this to work around expended roadbits. */
					if (AIRoad.IsRoadTile(path.GetTile()) && 
							!AIRoad.IsRoadStationTile(path.GetTile()) &&
							!AIRoad.IsRoadDepotTile(path.GetTile())) {
						AITile.DemolishTile(path.GetTile());
					}
					if (AITunnel.GetOtherTunnelEnd(path.GetTile()) == par.GetTile()) {
						if (!AITunnel.BuildTunnel(AIVehicle.VT_ROAD, path.GetTile())) {
							/* An error occured while building a tunnel. TODO: handle it. */
							Log.Info("Build tunnel error: " + AIError.GetLastErrorString(), Log.LVL_INFO);
						}
					} else {
						local bridge_list = AIBridgeList_Length(AIMap.DistanceManhattan(path.GetTile(), par.GetTile()) +1);
						bridge_list.Valuate(AIBridge.GetMaxSpeed);
						if (!AIBridge.BuildBridge(AIVehicle.VT_ROAD, bridge_list.Begin(), path.GetTile(), par.GetTile())) {
							/* An error occured while building a bridge. TODO: handle it. */
							Log.Info("Build bridge error: " + AIError.GetLastErrorString(), Log.LVL_INFO);
						}
					}

					if(play_slow == 1)
						AIController.Sleep(50); // Sleep a bit after tunnels
				}
			}
		}
		path = par;
		this.build_loops_used += 1;
	}

	Log.Info("Build loops used:" + this.build_loops_used, Log.LVL_DEBUG);
	//AISign.BuildSign(tile1, "Done");

	// Remove the from/to signs now that the road was successfully built
	Helper.SetSign(tile1, "");
	Helper.SetSign(tile2, "");

	return RoadBuilder.CONNECT_SUCCEEDED;
}

function RoadBuilder::GetPFLoopsUsed()
{
	return this.pf_loops_used;
}

function RoadBuilder::GetBuildLoopsUsed()
{
	return this.build_loops_used;
}

function RoadBuilder::GetVehicleLocations()
{
	local veh_list = AIVehicleList();

	// Get a list of tile locations of our vehicles
	veh_list.Valuate(AIVehicle.GetLocation);
	local veh_locations = Helper.CopyListSwapValuesAndItems(veh_list);

	return veh_locations;
}

function RoadBuilder::GetNonCrashedVehicleLocations()
{
	local veh_list = AIVehicleList();
	veh_list.Valuate(AIVehicle.GetState);
	veh_list.RemoveValue(AIVehicle.VS_CRASHED);
	veh_list.RemoveValue(AIVehicle.VS_INVALID);

	// Get a list of tile locations of our vehicles
	veh_list.Valuate(AIVehicle.GetLocation);
	local veh_locations = Helper.CopyListSwapValuesAndItems(veh_list);

	return veh_locations;
}

function RoadBuilder::GetCrashedVehicleLocations()
{
	local veh_list = AIVehicleList();
	veh_list.Valuate(AIVehicle.GetState);
	veh_list.KeepValue(AIVehicle.VS_CRASHED);

	// Get a list of tile locations of our vehicles
	veh_list.Valuate(AIVehicle.GetLocation);
	local veh_locations = Helper.CopyListSwapValuesAndItems(veh_list);

	return veh_locations;
}

function RoadBuilder::ConvertRailCrossingToBridge(rail_tile, prev_tile)
{
	local forward_dir = Direction.GetDirectionToAdjacentTile(prev_tile, rail_tile);
	local backward_dir = Direction.TurnDirClockwise45Deg(forward_dir, 4);

	local tile_after = Direction.GetAdjacentTileInDirection(rail_tile, forward_dir);
	local tile_before = Direction.GetAdjacentTileInDirection(rail_tile, backward_dir);

	// Check if the tile before rail is a rail-tile. If so, go to prev tile for a maximum of 10 times
	local i = 0;
	while (AITile.HasTransportType(tile_before, AITile.TRANSPORT_RAIL) && i < 10)
	{
		tile_before = Direction.GetAdjacentTileInDirection(tile_before, backward_dir);
		i++;
	}

	// Check if the tile after rail is a rail-tile. If so, go to next tile for a maximum of 10 times (in total with going backwards)
	while (AITile.HasTransportType(tile_after, AITile.TRANSPORT_RAIL) && i < 10)
	{
		tile_after = Direction.GetAdjacentTileInDirection(tile_after, forward_dir);
		i++;
	}

	Helper.SetSign(tile_after, "after");
	Helper.SetSign(tile_before, "before");

	// rail-before shouldn't be a rail tile as we came from it, but if it is then it is a multi-rail that
	// previously failed to be bridged
	if (AITile.HasTransportType(tile_before, AITile.TRANSPORT_RAIL) ||
			AIBridge.IsBridgeTile(tile_before) ||
			AITunnel.IsTunnelTile(tile_before))
	{
		Log.Info("Fail 1", Log.LVL_INFO);
		return { succeeded = false, permanently = true };
	}

	// If after moving 10 times, there is still a rail-tile, abort
	if (AITile.HasTransportType(tile_after, AITile.TRANSPORT_RAIL) ||
			AIBridge.IsBridgeTile(tile_after) ||
			AITunnel.IsTunnelTile(tile_after))
	{
		Log.Info("Fail 2", Log.LVL_INFO);
		return { succeeded = false, permanently = true };
	}


	/* Now tile_before and tile_after are the tiles where the bridge would begin/end */

	// Check that we own those tiles. NoAI 1.0 do not have any constants for checking if a owner is a company or
	// not. -1 seems to indicate that it is not a company. ( = town )
	local tile_after_owner = AITile.GetOwner(tile_after);
	local tile_before_owner = AITile.GetOwner(tile_before);
	if ( (tile_before_owner != -1 && !AICompany.IsMine(tile_before_owner)) || 
			(tile_after_owner != -1 && !AICompany.IsMine(tile_after_owner)) )
	{
		Log.Info("Not my road - owned by " + tile_before_owner + ": " + AICompany.GetName(tile_before_owner) + " and " + tile_after_owner + ":" + AICompany.GetName(tile_after_owner), Log.LVL_INFO);
		Log.Info("Fail 3", Log.LVL_INFO);
		return { succeeded = false, permanently = true };
	}

	// Check that those tiles do not have 90-deg turns, T-crossings or 4-way crossings
	local left_dir = Direction.TurnDirAntiClockwise45Deg(forward_dir, 2);
	local right_dir = Direction.TurnDirClockwise45Deg(forward_dir, 2);

	local bridge_ends = [tile_before, tile_after];
	foreach(end_tile in bridge_ends)
	{
		local left_tile = Direction.GetAdjacentTileInDirection(end_tile, left_dir);
		local right_tile = Direction.GetAdjacentTileInDirection(end_tile, right_dir);

		if (AIRoad.AreRoadTilesConnected(end_tile, left_tile) || AIRoad.AreRoadTilesConnected(end_tile, right_tile))
		{
			Log.Info("Fail 4", Log.LVL_INFO);
			return { succeeded = false, permanently = true };
		}
	}

	/* Now we know that we can demolish the road on tile_before and tile_after without destroying any road intersections */
	
	/* Check the landscape if it allows for a tunnel or a bridge */ 

	local tunnel = false;
	local bridge = false;

	//local after_dn_slope = Tile.IsDownSlope(tile_after, forward_dir);
	local after_dn_slope = Tile.IsUpSlope(tile_after, backward_dir);
	local before_dn_slope = Tile.IsDownSlope(tile_before, backward_dir);
	local same_height = AITile.GetMaxHeight(tile_after) == AITile.GetMaxHeight(tile_before);

	Log.Info("after_dn_slope = " + after_dn_slope + " | before_dn_slope = " + before_dn_slope + " | same_height = " + same_height, Log.LVL_INFO);

	if (Tile.IsDownSlope(tile_after, forward_dir) && Tile.IsDownSlope(tile_before, backward_dir) &&
		AITile.GetMaxHeight(tile_after) == AITile.GetMaxHeight(tile_before)) // Make sure the tunnel entrances are at the same height
	{
		// The rail is on a hill with down slopes at both sides -> can tunnel under the railway.
		tunnel = true;
	}
	else
	{
		if (AITile.GetMaxHeight(tile_before) == AITile.GetMaxHeight(tile_after)) // equal (max) height
		{
			// either 
			// _______      _______
			//        \____/
			//         rail
			//
			// or flat 
			// ____________________
			//         rail
			bridge = (Tile.IsBuildOnSlope_UpSlope(tile_before, backward_dir) && Tile.IsBuildOnSlope_UpSlope(tile_after, forward_dir)) ||
					(Tile.IsBuildOnSlope_FlatForBridgeInDirection(tile_before, forward_dir) && Tile.IsBuildOnSlope_FlatForBridgeInDirection(tile_after, forward_dir));
		}
		else if (AITile.GetMaxHeight(tile_before) == AITile.GetMaxHeight(tile_after) + 1) // tile before is one higher
		{
			// _______
			//        \____________
			//         rail

			bridge = Tile.IsBuildOnSlope_UpSlope(tile_before, backward_dir) && Tile.IsBuildOnSlope_FlatForBridgeInDirection(tile_after, forward_dir);

		}
		else if (AITile.GetMaxHeight(tile_before) + 1 == AITile.GetMaxHeight(tile_after)) // tile after is one higher
		{
			//              _______
			// ____________/
			//         rail

			bridge = Tile.IsBuildOnSlope_FlatForBridgeInDirection(tile_before, forward_dir) && Tile.IsBuildOnSlope_UpSlope(tile_after, forward_dir);
		}
		else // more than one level of height difference
		{
		}
	}

	if (!tunnel && !bridge)
	{
		// Can neither make tunnel or build bridge
		Log.Info("Fail 5", Log.LVL_INFO);
		return { succeeded = false, permanently = true };
	}

	local bridge_length = AIMap.DistanceManhattan(tile_before, tile_after) + 1;
	local bridge_list = AIBridgeList_Length(bridge_length);
	if (bridge)
	{
		if (bridge_list.IsEmpty())
		{
			Log.Info("Fail 6", Log.LVL_INFO);
			return { succeeded = false, permanently = true };
		}
	}

	/* Check that there isn't a bridge that crosses the tile_before or tile_after */

	if (Tile.GetBridgeAboveStart(tile_before, backward_dir) != -1 || // check for bridge that goes above parallel with the road 
			Tile.GetBridgeAboveStart(tile_before, Direction.TurnDirClockwise45Deg(backward_dir, 2)) != -1 || // check for bridge over the tile before rail orthogonal to the road dir
			Tile.GetBridgeAboveStart(tile_after, Direction.TurnDirClockwise45Deg(backward_dir, 2)) != -1)    // check for bridge over the tile after rail orthogonal to the road dir
	{
		Log.Info("There is a nearby bridge that blocks the new bridge", Log.LVL_INFO);
		Log.Info("Fail 6.5", Log.LVL_INFO);
		return { succeeded = false, permanently = true };
	}

	/* Now we know it is possible to bridge/tunnel the rail from tile_before to tile_after */
	
	// Make sure we can afford the construction
	AICompany.SetLoanAmount(AICompany.GetMaxLoanAmount());
	if (AICompany.GetBankBalance(AICompany.COMPANY_SELF) < 20000)
	{
		Log.Info("Found railway crossing that can be replaced, but bail out because of low founds.", Log.LVL_INFO);
		Log.Info("Fail 7", Log.LVL_INFO);
		return { succeeded = false, permanently = false };
	}

	/* Now lets get started removing the old road! */

	{
		// Since it is a railway crossing it is a good idea to remove the entire road in one go.

		/* However in OpenTTD 1.0 removing road will not fail if removing rail at rail crossings
		 * fails. So therefore, remove road one by one and always make sure the road actually got
		 * removed before moving forward so that there is a way out for vehicles.
		 */

		Helper.ClearAllSigns();

		local i = 0;
		local forigin_veh_in_the_way_counter = 0;
		local tile1 = tile_before;
		local tile2 = Direction.GetAdjacentTileInDirection(tile1, forward_dir);
		local up_to_and_tile1 = AITileList();
		up_to_and_tile1.AddTile(tile1);
		local prev_tile = -1; // the tile before tile1 ( == -1 the first round )

		local MAX_I = 20 + 10 * bridge_length;

		while(i < MAX_I)
		{
			// Reduce the risk of vehicle movements after checking their locations by getting a fresh
			// oopcodes quota
			AIController.Sleep(1);

			// Get a list of all (our) non-crashed vehicles
			local veh_locations = RoadBuilder.GetNonCrashedVehicleLocations();

			// Check that no vehicle will become stuck on tile1 or any previous tile because they could have moved to a previous tile during processing/sleep time.
			// Both because previous tiles could have a crashed vehicle so that the road couln't be removed but also because when the vehicles are at the very end
			// of a tile and turns back they are actually on the other tile.
			veh_locations.KeepList(up_to_and_tile1);
			if(!veh_locations.IsEmpty())
			{
				// There is a non-crashed vehicle in the first of two tiles to remove -> wait so it does not get stuck
				Log.Info("Detected own vehicle in the way -> delay removing road", Log.LVL_INFO);
				AIController.Sleep(5);
				i++;

				// Check again before trying to remove the road
				continue;
			}

			Log.Info("Tile is clear -> remove road", Log.LVL_INFO);
			//Helper.SetSign(tile1, "clear");

			// Try to remove from tile 1 to tile 2 since tile 1 is clear from own non-crashed vehicles
			local result = AIRoad.RemoveRoadFull(tile1, tile2);
			local last_error = AIError.GetLastError();

			local go_to_next_tile = false;

			// If there were a vehicle in the way
			if(!result && last_error == AIError.ERR_NOT_ENOUGH_CASH)
			{
				Log.Info("Not enough cach -> wait a little bit", Log.LVL_INFO);
				AIController.Sleep(5);
				i++;
				continue;
			}
			else if( (tile2 == tile_after) && (!result || AITile.HasTransportType(tile2, AITile.TRANSPORT_ROAD)) ) // if failed to remove road at tile_after
			{
				// Special care need to be taken when tile2 is the last tile.
				// Then we can't just move on and check the next iteration when
				// it becomes tile1 if it is ok to skip it or not. In fact
				// we can never skip tile_after as the bridge need to come down
				// there.
				if(last_error == AIError.ERR_VEHICLE_IN_THE_WAY)
				{
					Log.Info("Failed to remove last tile because vehicle in the way", Log.LVL_INFO)
					i++;
					AIController.Sleep(5);
					continue;
				}
				else if(last_error = AIError.ERR_UNKNOWN)
				{
					Log.Info("Couldn't remove last road bit because of unknown error - strange -> wait and try again", Log.LVL_INFO);
					i++;
					AIController.Sleep(5);
					continue;
				}
				else
				{
					Log.Info("Couldn't remove last road bit because of unhandled error: " + AIError.GetLastErrorString() + " -> abort", Log.LVL_INFO);
					break;
				}
			}
			else if( (!result && last_error == AIError.ERR_VEHICLE_IN_THE_WAY) || result && AITile.HasTransportType(tile1, AITile.TRANSPORT_ROAD) )
			{	
				Log.Info("Road was not removed, possible because a vehicle in the way", Log.LVL_INFO);

				if(tile1 == tile_before)
				{
					// We can never skip to remove road from the tile before the railway crossing(s)
					// as the bridge will start here
					Log.Info("Since this is the tile before the railway crossing the road MUST be removed -> wait and hope the vehicles go away", Log.LVL_INFO);
					i++;
					AIController.Sleep(5);
					continue;
				}

				// If the vehicle that is in the way is a crashed vehicle then move on
				// if not, it is possible a competitor vehicle which could be kind to
				// save from being trapped.
				local own_vehicle_locations = RoadBuilder.GetVehicleLocations();
				own_vehicle_locations.Valuate(Helper.ItemValuator);
				own_vehicle_locations.KeepValue(tile1);
				if(own_vehicle_locations.IsEmpty() && forigin_veh_in_the_way_counter < 5)
				{
					// The vehicle in the way is not one of our own crashed vehicles
					Log.Info("Detected vehicle in the way that is not our own. Wait a bit to see if it moves == non-crashed.", Log.LVL_INFO);
					forigin_veh_in_the_way_counter++;
					i++
					AIController.Sleep(5);
					continue;
				}

				Log.Info("Road was not removed, most likely because a crashed vehicle in the way -> move on", Log.LVL_INFO);

				go_to_next_tile = true;
			}
			else if(!result)
			{
				if (last_error == AIError.ERR_UNKNOWN)
				{
					Log.Info("Couldn't remove road because of unknown error - strange -> wait and try again", Log.LVL_INFO);
					Helper.SetSign(tile1, "strange");
					i++;
					AIController.Sleep(5);
					continue;
				}
				else
				{
					Log.Info("Couldn't remove road because " + AIError.GetLastErrorString(), Log.LVL_INFO);
					break;
				}
			}
			else
			{
				// Road was removed
				go_to_next_tile = true;
			}

			if(go_to_next_tile)
			{
				// End _after_ the road has been removed up to tile_after
				if(tile2 == tile_after)
				{
					Log.Info("Road has been removed up to tile_after -> stop", Log.LVL_INFO);
					break;
				}

				// Next tile pair
				prev_tile = tile1;
				tile1 = tile2;
				tile2 = Direction.GetAdjacentTileInDirection(tile1, forward_dir);
				up_to_and_tile1.AddTile(tile1);
			}
		}

		Helper.ClearAllSigns();
		
		// Do not just check that tile2 has reached the end -> check that all tiles from tile_before to tile_after do not have
		// transport mode road.
		local remove_failed = false;
		local tile_after_after = Direction.GetAdjacentTileInDirection(tile_after, forward_dir);
		for(local tile = tile_before; tile != tile_after_after; tile = Direction.GetAdjacentTileInDirection(tile, forward_dir))
		{
			//Helper.SetSign(tile, "test");
			if(AITile.HasTransportType(tile, AITile.TRANSPORT_ROAD))
			{
				if(tile == tile_before || tile == tile_after)
				{
					// Don't check the end tiles for crashed vehicles as they are not rail tiles
					// Checking them could give false positives from vehicles turning around at the tiles adjacent to the end tiles at the outside of the tiles to be removed.
					remove_failed = true;
					//Helper.SetSign(tile, "fail");
					break;
				}
				else
				{
					//Helper.SetSign(tile, "road");

					// Get a list of all (our) non-crashed vehicles
					local veh_locations = RoadBuilder.GetNonCrashedVehicleLocations();
					veh_locations.Valuate(Helper.ItemValuator);

					// Check if there are any non-crashed vehicles on the current tile
					veh_locations.KeepValue(tile);

					if(!veh_locations.IsEmpty()) // Only fail to remove road, if the road bit has a non-crashed (own) vehicle on it
					{
						Log.Info("One of our own vehicles got stuck while removing the road. -> removing failed", Log.LVL_INFO);
						remove_failed = true;
						//Helper.SetSign(tile, "fail");
						break;
					}
				}
			}
		}

		if(remove_failed)
		{
			Log.Info("Tried to remove road over rail for a while, but failed", Log.LVL_INFO);

			AIRoad.BuildRoadFull(tile_before, tile_after);
			AIRoad.BuildRoadFull(tile_after, tile_before);

			Log.Info("Fail 8", Log.LVL_INFO);
		}
	}

	/* Now lets get started building bridge / tunnel! */

	local build_failed = false;	

	if (tunnel)
	{
		if(!AITunnel.BuildTunnel(AIVehicle.VT_ROAD, tile_before))
			build_failed = true;
	}
	else if (bridge)
	{
		bridge_list.Valuate(AIBridge.GetMaxSpeed);
		if (!AIBridge.BuildBridge(AIVehicle.VT_ROAD, bridge_list.Begin(), tile_before, tile_after))
			build_failed = true;
	}

	if (build_failed)
	{
		local what = tunnel == true? "tunnel" : "bridge";
		Log.Warning("Failed to build " + what + " to cross rail because " + AIError.GetLastErrorString() + ". Now try to build road to repair the road.", Log.LVL_INFO);
		if(AIRoad.BuildRoadFull(tile_before, tile_after))
		{
			Log.Error("Failed to repair road crossing over rail by building road because " + AIError.GetLastErrorString(), Log.LVL_INFO);
		}

		Log.Info("Fail 9", Log.LVL_INFO);
		return { succeeded = false, permanently = false };
	}

	return { succeeded = true, bridge_start = tile_before, bridge_end = tile_after };
}

/*

// It seems like this function do not work

function RoadBuilder::RemoveRoad(from_tile, to_tile)
{
	local forward_dir = Direction.GetDirectionToTile(from_tile, to_tile);
	if (!Direction.IsMainDir(forward_dir))
	{
		return false;
	}

	local after_end = Direction.GetAdjacentTileInDirection(to_tile, forward_dir);
	local prev_tile = from_tile;
	for(local curr_tile = from_tile;
			curr_tile != after_end;
			curr_tile = Direction.GetAdjacentTileInDirection(curr_tile, forward_dir))
	{
		if (!curr_tile == prev_tile)
		{
			local i = 0;
			while(i < 20 && !AIRoad.RemoveRoad(prev_tile, curr_tile))
			{
				local last_error = AIError.GetLastError();
				if(last_error == AIError.ERR_VEHICLE_IN_THE_WAY || last_error == AIError.ERR_NOT_ENOUGH_CASH)
				{
					AIController.Sleep(5);
				}
				else
				{
					break;
				}
				i++;
			}

			if(AIRoad.AreRoadTilesConnected(prev_tile, curr_tile))
			{
				// Todo: rebuild the road
				return false;
			}
		}
	}
}
*/

// TODO: Handle bridges/tunnels (perhaps leave long ones)
// TODO: Manage to cross railways
function RoadBuilder::RemoveRoadUpToRoadCrossing(start_tile)
{
	//if (!AITile.HasTransportType(start_tile, AITile.TRANSPORT_ROAD))
	if (!AIRoad.IsRoadTile(start_tile) || AIRoad.IsDriveThroughRoadStationTile(start_tile))
	{
		Log.Info("RemoveRoadUpToRoadCrossing fails because start tile do not have road", Log.LVL_DEBUG);
		return false;
	}

	local curr_tile = start_tile;
	local next_tile = 0;

	//while(AITile.HasTransportType(curr_tile, AITile.TRANSPORT_ROAD))
	while(AICompany.IsMine(AITile.GetOwner(curr_tile)) &&
			(
				// Is road or bridge/tunnel
				(AIRoad.IsRoadTile(curr_tile) && !AIRoad.IsDriveThroughRoadStationTile(curr_tile)) ||
				AITile.HasTransportType(curr_tile, AITile.TRANSPORT_ROAD) ||
				AIBridge.IsBridgeTile(curr_tile) || AITunnel.IsTunnelTile(curr_tile)
			))
	{
		// Check for bridge/tunnel
		local has_bridge_tunnel = false;
		local bridge_tunnel_other_end = -1;
		if(AIBridge.IsBridgeTile(curr_tile))
		{
			has_bridge_tunnel = true;
			bridge_tunnel_other_end = AIBridge.GetOtherBridgeEnd(curr_tile);
		}
		else if(AITunnel.IsTunnelTile(curr_tile))
		{
			has_bridge_tunnel = true;
			bridge_tunnel_other_end = AITunnel.GetOtherTunnelEnd(curr_tile);
		}

		if(has_bridge_tunnel) // has bridge or tunnel -> go to other end
		{
			Helper.SetSign(curr_tile, "bridge|tunnel");
			local dir = Direction.GetDirectionToTile(curr_tile, bridge_tunnel_other_end);
			local length = AIMap.DistanceManhattan(curr_tile, bridge_tunnel_other_end) + 1;

			// Go to the tile after the bridge
			curr_tile = bridge_tunnel_other_end; 
			next_tile = Direction.GetAdjacentTileInDirection(curr_tile, dir); // next tile after bridge

			// Remove bridges/tunnels shorter than length 8
			if(length < 8)
			{
				AITile.DemolishTile(curr_tile);
			}
			Helper.SetSign(curr_tile, "curr");
			Helper.SetSign(next_tile, "next");
		}
		else
		{
			Helper.SetSign(curr_tile, "curr");

			// Curr tile is neither a bridge nor a tunnel
			// Find next tile
			local neighbours = Tile.GetNeighbours4MainDir(curr_tile);
			neighbours.Valuate(AIRoad.AreRoadTilesConnected, curr_tile);
			neighbours.KeepValue(1);

			// > 1 neighbours -> curr_tile is a road crossing tile
			if(neighbours.Count() > 1)
			{
				Log.Info("RemoveRoadUpToRoadCrossing stops because road crossing found", Log.LVL_DEBUG);
				break;
			}

			if(neighbours.Count() == 0)
			{
				// This should really only happen if the start tile contains a road bit that is not connected with anything
				Log.Info("RemoveRoadUpToRoadCrossing stops because no connected neighbours found", Log.LVL_DEBUG);
				break;
			}

			// Set next tile
			next_tile = neighbours.Begin();
		}

		// Remove road from curr_tile
		if(!AIRoad.RemoveRoad(curr_tile, next_tile)) 
		{
			// Abort if road removal fails
			Log.Info("RemoveRoadUpToRoadCrossing: Remove road failed", Log.LVL_INFO);
			break;
		}

		// In case the road tile has partial connections to neighbour tiles remove them
		local neighbours = Tile.GetNeighbours4MainDir(curr_tile);
		foreach(tile, _ in neighbours)
		{
			// Just try once; no wait for vehicles to move away.
			AIRoad.RemoveRoad(curr_tile, tile);
		}

		// If next tile is rail, then we need to go to the next tile after that, since there won't be
		// a road stump at the rail.
		if(AITile.HasTransportType(next_tile, AITile.TRANSPORT_RAIL))
		{
			local dir = Direction.GetDirectionToTile(curr_tile, next_tile);

			Log.Info("RemoveRoadUpToRoadCrossing: rail move " + Direction.GetDirString(dir), Log.LVL_INFO);
			next_tile = Direction.GetAdjacentTileInDirection(next_tile, dir);

			Helper.SetSign(next_tile, "new next");
		}

		// Go to next tile
		curr_tile = next_tile;

	}

	Helper.SetSign(curr_tile, "end");

	Log.Info("RemoveRoadUpToRoadCrossing done", Log.LVL_DEBUG);

	return true;
}
