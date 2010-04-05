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


import("pathfinder.road", "RPF", 3);
require("wayfinder.nut");

class MyRoadPF extends RPF {}

function MyRoadPF::_Cost(path, new_tile, new_direction, self)
{
	local cost = ::RPF._Cost(path, new_tile, new_direction, self);

	if(AITile.HasTransportType(new_tile, AITile.TRANSPORT_RAIL)) cost += 500;

	if(path != null)
	{
		// Path is null on first node
		local prev_tile = path.GetTile();

		// If it is possible to reach the current tile from next tile but not in the other direction, then it is a one-way road
		// in the wrong direction.
		if(AIRoad.AreRoadTilesConnected(new_tile, prev_tile) && !AIRoad.AreRoadTilesConnected(prev_tile, new_tile))
		{
			// Don't try to use one-way roads from the back
			AILog.Info("One-way road detected");
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

	constructor() {
	}
	

	// If repair_existing == true, then it should as much as possible avoid building road next to existing to get a tiny bit less penalty
	static function ConnectTiles(tile1, tile2, call_count, repair_existing = false);

	static function ConvertRailCrossingToBridge(rail_tile, prev_tile);
	static function RemoveRoad(from_tile, to_tile);
}


function RoadBuilder::ConnectTiles(tile1, tile2, call_count, repair_existing = false) 
{

	AILog.Info("Connecting tiles - try no: " + call_count);

	local pathfinder = MyRoadPF();
	//local pathfinder = WayFinder();

	local play_slow = AIController.GetSetting("slow_ai");

	Helper.SetSign(tile1, "from");
	Helper.SetSign(tile2, "to");

	pathfinder.InitializePath([tile1], [tile2]);
	pathfinder.cost.no_existing_road = repair_existing? 300 : 60; // default = 40
	pathfinder.cost.tile = 80; // default = 100

	local path = false;
	while (path == false) {
		path = pathfinder.FindPath(100);
		AIController.Sleep(1);

		if(play_slow == 1)
			AIController.Sleep(5);
	}

	if(path == null) {
		AILog.Info("Failed to find path");
		return false;
	}
	AILog.Info("Path found, now start building!");

	//AISign.BuildSign(path.GetTile(), "Start building");

	while (path != null) {
		local par = path.GetParent();
		Helper.SetSign(path.GetTile(), "tile");
		if (par != null) {
			local last_node = path.GetTile();
			Helper.SetSign(par.GetTile(), "par");
			if (AIMap.DistanceManhattan(path.GetTile(), par.GetTile()) == 1 ) {
				if (AIRoad.AreRoadTilesConnected(path.GetTile(), par.GetTile())) {
					// there is already a road here, don't do anything
					Helper.SetSign(par.GetTile(), "conn");

					if (AITile.HasTransportType(par.GetTile(), AITile.TRANSPORT_RAIL))
					{
						// Found a rail track crossing the road, try to bridge it
						Helper.SetSign(par.GetTile(), "rail!");

						local bridge = RoadBuilder.ConvertRailCrossingToBridge(par.GetTile(), path.GetTile());
						if (bridge != null)
						{
							// TODO update par/path
							local new_par = par;
							while (new_par != null && new_par.GetTile() != bridge[1] && new_par.GetTile() != bridge[0])
							{
								new_par = new_par.GetParent();
							}
							
							if (new_par == null)
							{
								AILog.Warning("Tried to convert rail crossing to bridge but somehow got lost from the found path.");
							}
							par = new_par;
						}
						else
						{
							AILog.Info("Failed to bridge railway crossing");
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

						// Try PF again
						if (call_count > 4 || 
								!RoadBuilder.ConnectTiles(tile1, path.GetTile(), call_count+1))
						{
							AILog.Info("After several tries the road construction could still not be completed");
							return false;
						}
						else
						{
							return true;
						}
					}

					if(play_slow == 1)
						AIController.Sleep(20);
				}
			} else {
				/* Build a bridge or tunnel. */
				if (!AIBridge.IsBridgeTile(path.GetTile()) && !AITunnel.IsTunnelTile(path.GetTile())) {

					/* If it was a road tile, demolish it first. Do this to work around expended roadbits. */
					if (AIRoad.IsRoadTile(path.GetTile()) && 
							!AIRoad.IsRoadStationTile(path.GetTile()) &&
							!AIRoad.IsRoadDepotTile(path.GetTile())) {
						AITile.DemolishTile(path.GetTile());
					}
					if (AITunnel.GetOtherTunnelEnd(path.GetTile()) == par.GetTile()) {
						if (!AITunnel.BuildTunnel(AIVehicle.VT_ROAD, path.GetTile())) {
							/* An error occured while building a tunnel. TODO: handle it. */
							AILog.Info("Build tunnel error: " + AIError.GetLastErrorString());
						}
					} else {
						local bridge_list = AIBridgeList_Length(AIMap.DistanceManhattan(path.GetTile(), par.GetTile()) +1);
						bridge_list.Valuate(AIBridge.GetMaxSpeed);
						if (!AIBridge.BuildBridge(AIVehicle.VT_ROAD, bridge_list.Begin(), path.GetTile(), par.GetTile())) {
							/* An error occured while building a bridge. TODO: handle it. */
							AILog.Info("Build bridge error: " + AIError.GetLastErrorString());
						}
					}

					if(play_slow == 1)
						AIController.Sleep(50); // Sleep a bit after tunnels
				}
			}
		}
		path = par;
	}

	//AISign.BuildSign(tile1, "Done");

	return true;
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


// returns [bridge_start_tile, bridge_end_tile] or null
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
		AILog.Info("Fail 1");
		return null;
	}

	// If after moving 10 times, there is still a rail-tile, abort
	if (AITile.HasTransportType(tile_after, AITile.TRANSPORT_RAIL) ||
			AIBridge.IsBridgeTile(tile_after) ||
			AITunnel.IsTunnelTile(tile_after))
	{
		AILog.Info("Fail 2");
		return null;
	}


	/* Now tile_before and tile_after are the tiles where the bridge would begin/end */

	// Check that we own those tiles. NoAI 1.0 do not have any constants for checking if a owner is a company or
	// not. -1 seems to indicate that it is not a company. ( = town )
	local tile_after_owner = AITile.GetOwner(tile_after);
	local tile_before_owner = AITile.GetOwner(tile_before);
	if ( (tile_before_owner != -1 && !AICompany.IsMine(tile_before_owner)) || 
			(tile_after_owner != -1 && !AICompany.IsMine(tile_after_owner)) )
	{
		AILog.Info("Not my road - owned by " + tile_before_owner + ": " + AICompany.GetName(tile_before_owner) + " and " + tile_after_owner + ":" + AICompany.GetName(tile_after_owner));
		AILog.Info("Fail 3");
		return null;
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
			AILog.Info("Fail 4");
			return null;
		}
	}

	/* Check that we don't have a crashed vehicle on the track */

	/*{
		// Get a list of all (our) crashed vehicles
		local veh_list = AIVehicleList();
		veh_list.Valuate(AIVehicle.GetState);
		veh_list.KeepValue(AIVehicle.VS_CRASHED);

		// Get a list of tile locations that has crashed vehicles
		veh_list.Valuate(AIVehicle.GetLocation);
		local crash_locations = Helper.CopyListSwapValuesAndItems(veh_list);

		// Make a list of all tiles that will have the road removed
		local tile_list = AITileList();
		tile_list.AddRectangle(tile_before, tile_after);

		// Keep road tiles that has a crashed vehicle on them
		tile_list.KeepList(crash_locations);

		if(!tile_list.IsEmpty())
		{
			// One of the crash sites are at the road/rail tiles of this rail crossing
			AILog.Info("A crashed vehicle is still on the rail -> so don't try yet to replace the road");
			AILog.Info("Fail 4.5");
			return null;
		}
	}*/

	

	/* Now we know that we can demolish the road on tile_before and tile_after without destroying any road intersections */
	
	local tunnel = false;
	local bridge = false;

	//local after_dn_slope = Tile.IsDownSlope(tile_after, forward_dir);
	local after_dn_slope = Tile.IsUpSlope(tile_after, backward_dir);
	local before_dn_slope = Tile.IsDownSlope(tile_before, backward_dir);
	local same_height = AITile.GetMaxHeight(tile_after) == AITile.GetMaxHeight(tile_before);

	AILog.Info("after_dn_slope = " + after_dn_slope + " | before_dn_slope = " + before_dn_slope + " | same_height = " + same_height);

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
					(Tile.IsBuildOnSlope_FlatInDirection(tile_before, forward_dir) && Tile.IsBuildOnSlope_FlatInDirection(tile_after, forward_dir));
		}
		else if (AITile.GetMaxHeight(tile_before) == AITile.GetMaxHeight(tile_after) + 1) // tile before is one higher
		{
			// _______
			//        \____________
			//         rail

			bridge = Tile.IsBuildOnSlope_UpSlope(tile_before, backward_dir) && Tile.IsBuildOnSlope_FlatInDirection(tile_after, forward_dir);

		}
		else if (AITile.GetMaxHeight(tile_before) + 1 == AITile.GetMaxHeight(tile_after)) // tile after is one higher
		{
			//              _______
			// ____________/
			//         rail

			bridge = Tile.IsBuildOnSlope_FlatInDirection(tile_before, forward_dir) && Tile.IsBuildOnSlope_UpSlope(tile_after, forward_dir);
		}
		else // more than one level of height difference
		{
		}
	}

	if (!tunnel && !bridge)
	{
		// Can neither make tunnel or build bridge
		AILog.Info("Fail 5");
		return null;
	}

	local bridge_length = AIMap.DistanceManhattan(tile_before, tile_after) + 1;
	local bridge_list = AIBridgeList_Length(bridge_length);
	if (bridge)
	{
		if (bridge_list.IsEmpty())
		{
			AILog.Info("Fail 6");
			return null; // There is no bridge for this length
		}
	}

	/* Now we know it is possible to bridge/tunnel the rail from tile_before to tile_after */
	
	// Make sure we can afford the construction
	AICompany.SetLoanAmount(AICompany.GetMaxLoanAmount());
	if (AICompany.GetBankBalance(AICompany.COMPANY_SELF) < 20000)
	{
		AILog.Info("Found railway crossing that can be replaced, but bail out because of low founds.");
		AILog.Info("Fail 7");
		return null;
	}

	/* Now lets get started removing the old road! */

	{
		// Since it is a railway crossing it is a good idea to remove the entire road in one go.

		/* However in OpenTTD 1.0 removing road will not fail if removing rail at rail crossings
		 * fails. So therefore, remove road one by one and always make sure the road actually got
		 * removed before moving forward so that there is a way out for vehicles.
		 */

		local i = 0;
		local tile1 = tile_before;
		local tile2 = Direction.GetAdjacentTileInDirection(tile1, forward_dir);
		while(i < 40)
		{
//			Helper.ClearAllSigns();
//			Helper.SetSign(tile1, "tile1");
//			Helper.SetSign(tile2, "tile2");

			// Reduce the risk of vehicle movements after checking their locations by getting a fresh
			// oopcodes quota
			AIController.Sleep(1);

			// Get a list of all (our) non-crashed vehicles
			local veh_locations = RoadBuilder.GetNonCrashedVehicleLocations();

			// Keep vehicle locations that match tile1 or tile2
			local tile_list = AITileList();
			tile_list.AddRectangle(tile1, tile2);
			veh_locations.KeepList(tile_list);

			if(veh_locations.HasItem(tile1))
			{
				// There is a non-crashed vehicle in the first of two tiles to remove -> wait so it does not get stuck
				AILog.Info("Detected own vehicle in the way -> delay removing road");
				AIController.Sleep(5);
				i++;

				// Check again before trying to remove the road
				continue;
			}

			while(i < 40 && (!AIRoad.RemoveRoadFull(tile1, tile2) 
					|| AITile.HasTransportType(tile1, AITile.TRANSPORT_ROAD)// make sure the road actually got removed
					|| AITile.HasTransportType(tile2, AITile.TRANSPORT_ROAD)))//if they contain a self owned vehicle
			{
				if(veh_locations.IsEmpty())
				{
					AILog.Info("Removing road failed, but the road tile doesn't have any of our own buses so skip removing it");
					break;
				}
					

				local last_error = AIError.GetLastError();
				if(last_error == AIError.ERR_VEHICLE_IN_THE_WAY || last_error == AIError.ERR_NOT_ENOUGH_CASH)
				{
					AILog.Info("Couldn't remove road over rail because of vehicle in the way or low cash -> wait and try again");
					AIController.Sleep(5);
				}
				else
				{
					AILog.Info("Couldn't remove road because " + AIError.GetLastErrorString());
					break;
				}
				i++;
			}

			// End _after_ the road has been removed up to tile_after
			if(tile2 == tile_after)
				break;

			// Next tile pair
			tile1 = tile2;
			tile2 = Direction.GetAdjacentTileInDirection(tile1, forward_dir);
		}

		// Do not just check that tile2 has reached the end -> check that all tiles from tile_before to tile_after do not have
		// transport mode road.
		local remove_failed = false;
		for(local tile = tile_before; tile != tile_after; tile = Direction.GetAdjacentTileInDirection(tile, forward_dir))
		{
			if(AITile.HasTransportType(tile, AITile.TRANSPORT_ROAD))
			{
				// Get a list of all (our) non-crashed vehicles
				local veh_locations = RoadBuilder.GetNonCrashedVehicleLocations();

				// Check if there are any non-crashed vehicles on the current tile
				veh_locations.KeepValue(tile);

			foreach(veh, _ in veh_locations)
			{
				Helper.SetSign(veh - 1, "veh");
			}
				if(!veh_locations.IsEmpty()) // Only fail to remove road, if the road bit has a non-crashed (own) vehicle on it
				{
					remove_failed = true;
					break;
				}
			}
		}

		if(remove_failed)
		{
			AILog.Info("Tried to remove road over rail for a while, but failed");

			AIRoad.BuildRoadFull(tile_before, tile_after);
			AIRoad.BuildRoadFull(tile_after, tile_before);

			AILog.Info("Fail 8");
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
		AILog.Warning("Failed to build " + what + " to cross rail because " + AIError.GetLastErrorString() + ". Now try to build road to repair the road.");
		if(AIRoad.BuildRoadFull(tile_before, tile_after))
		{
			AILog.Error("Failed to repair road crossing over rail by building road because " + AIError.GetLastErrorString());
		}

		AILog.Info("Fail 9");
		return null;
	}

	return [tile_before, tile_after];
}

function RoadBuilder::RemoveRoad(from_tile, to_tile)
{
	local forward_dir = Tile.GetDirectionToTile(from_tile, to_tile);
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
