//////////////////////////////////////////////////////////////////////
//                                                                  //
//  CluelessPlus - an noai-AI                                       //
//                                                                  //
//////////////////////////////////////////////////////////////////////
// 
// CluelessPlus is based on original Clueless which was written in 
// the beginning of 2008, when NoAI API was announced.
//
// In contrast to original Clueless, CluelessPlus make use of the
// library pathfinder, so it can play on maps with build on slope
// enabled. Building of stations has been changed so that it try
// many locations in a town using the old algorithm, but without 
// executing any construction. Then afterwards it builds the station
// at the best found location. Clueless original built *lots* of
// stations all over the town and then removed all but the one it 
// wanted to keep. 
//
// Author: Zuu (Leif Linse), user Zuu @ tt-forums.net
// Purpose: To play around with the noai framework.
//               - Not to make the next big thing.
// Copyright: Leif Linse - 2008-2011
// License: GNU GPL - version 2


import("util.superlib", "SuperLib", 9);

Log <- SuperLib.Log;
Helper <- SuperLib.Helper;
Money <- SuperLib.Money;

Tile <- SuperLib.Tile;
Direction <- SuperLib.Direction;

Engine <- SuperLib.Engine;
Vehicle <- SuperLib.Vehicle;

Station <- SuperLib.Station;
Airport <- SuperLib.Airport;
Industry <- SuperLib.Industry;

Order <- SuperLib.Order;
OrderList <- SuperLib.OrderList;

RoadBuilder <- SuperLib.RoadBuilder;

import("queue.fibonacci_heap", "FibonacciHeap", 2);

require("pairfinder.nut"); 
require("sortedlist.nut");
require("clue_helper.nut");
require("stationstatistics.nut");
require("strategy.nut");

require("return_values.nut");


STATION_SAVE_VERSION <- "0";

//////////////////////////////////////////////////////////////////////
//                                                                  //
//  CLASS: Connection - a transport connection                      //
//                                                                  //
//////////////////////////////////////////////////////////////////////

// My aim is that this class should be as general as possible and allow 2> towns, or even cargo transport
class Connection
{
	clueless_instance = null;

	cargo_type = null;

	// date built
	date_built = null;
	last_vehicle_manage = null;

	// used towns and industries (arrays)
	town     = null;
	industry = null;

	// links to infrastructure and vehicles (arrays)
	station  = null; // station tile
	depot    = null;

	// nodes from PairFinder. Some day perhaps town + industry could be removed as they are in the node class (arrays of Node)
	node = null;

	last_station_manage = null;
	last_repair_route = null;
	station_statistics = null; // array of pointers to StationStatistics objects for each station
	max_station_usage = null;
	max_station_tile_usage = null;

	long_time_mean_income = 0;
	
	last_bus_buy = null;
	last_bus_sell = null;

	desired_engine = null;


	static STATE_BUILDING = 0;
	static STATE_FAILED = 1;
	static STATE_ACTIVE = 2;
	static STATE_CLOSED_DOWN = 10;
	static STATE_CLOSING_DOWN = 11;
	static STATE_SUSPENDED = 20;

	state = null;
	state_change_date = null;
	
	constructor(clueless_instance) {
		this.clueless_instance = clueless_instance;
		this.cargo_type = null;
		this.date_built = null;
		this.last_vehicle_manage = null;
		this.town     = [];
		this.industry = [];
		this.node     = [];
		this.station  = [null, null];
		this.depot    = [null, null];
		this.last_station_manage = null;
		this.last_repair_route = null;
		this.station_statistics = [];
		this.max_station_usage = 0;      // overall usage of the station with highest overall usage
		this.max_station_tile_usage = 0; // usage of the tile with highest usage
		this.long_time_mean_income = 0;
		this.state_change_date = 0;
		this.SetState(Connection.STATE_BUILDING);
		this.last_bus_buy = null;
		this.last_bus_sell = null;
		this.desired_engine = null;
	}

	function GetName();

	function SetState(newState);

	function ReActivateConnection();
	function SuspendConnection();
	function CloseConnection();

	function IsTownOnly();
	function GetTotalPoputaltion();
	function GetTotalDistance(); // only implemented for 2 towns
	function ManageState()
	function ManageStations()
	function ManageVehicles();
	function SendVehicleForSelling(vehicle_id);

	function FindEngineModelToBuy();
	function BuyVehicles(num_vehicles, engine_id);
	function NumVehiclesToBuy(connection);

	function GetVehicles();
	function GetBrokenVehicles(); // Gets broken vehicles that stops at any of the stations

	// Change order functions
	function FullLoadAtStations(enable_full_load);
	function StopInDepots(stop_in_depots);

	function SkipAllVehiclesToClosestDepot();

	function RepairRoadConnection();

	// Engine type management
	function FindNewDesiredEngineType();
	function MassUpgradeVehicles();

	static function IsVehicleToldToUpgrade(vehicle_id);
	static function GetVehicleUpgradeToEngine(vehicle_id);
}

function Connection::GetName()
{
	// Quick version if the connection is okay.
	if(node.len() == 2 && node[0] != null && node[1] != null)
		return node[0].GetName() + " - " + node[1].GetName();

	// If one or more node is broken:
	return "[broken connection]";
}

function Connection::SetState(newState)
{
	this.state = newState;
	this.state_change_date = AIDate.GetCurrentDate();
}

function Connection::ReActivateConnection()
{
	Log.Info("ReActivateConnection " + node[0].GetName() + " - " + node[1].GetName(), Log.LVL_INFO);

	// Change the depot orders to service at depots and start all vehicles

	local vehicle_list = this.GetVehicles();
	if(vehicle_list.IsEmpty())
	{
		Log.Warning("ReActivateConnection fails because connection " + node[0].GetName() + " - " + node[1].GetName() + " do not have any vehicles.", Log.LVL_INFO);
		return false;
	}

	// Change the depot orders to service at depots (but don't stop in depot)
	local veh_id = vehicle_list.Begin();
	for(local i_order = 0; i_order < AIOrder.GetOrderCount(veh_id); ++i_order)
	{
		if(AIOrder.IsGotoDepotOrder(veh_id, i_order))
		{
			// Always go to depot if breakdowns are "normal", otherwise only go if needed
			local service_flag = AIGameSettings.GetValue("vehicle_breakdowns") == 2? 0 : AIOrder.AIOF_SERVICE_IF_NEEDED;

			AIOrder.SetOrderFlags(veh_id, i_order, AIOrder.AIOF_NON_STOP_INTERMEDIATE | service_flag);
		}
	}

	// Start all vehicles that are stoped in depot
	foreach(vehicle_id, _ in vehicle_list)
	{
		if(AIVehicle.GetState(vehicle_id) == AIVehicle.VS_IN_DEPOT)
		{
			ClueHelper.StoreInVehicleName(vehicle_id, "active");
			AIVehicle.StartStopVehicle(vehicle_id);
		}
	}

	this.SetState(Connection.STATE_ACTIVE);

	return true;
}

function Connection::SuspendConnection()
{
	Log.Info("SuspendConnection " + node[0].GetName() + " - " + node[1].GetName(), Log.LVL_INFO);

	local vehicle_list = this.GetVehicles();
	if(vehicle_list.IsEmpty())
	{
		Log.Warning("SuspendConnection fails because connection " + node[0].GetName() + " - " + node[1].GetName() + " do not have any vehicles.", Log.LVL_INFO);
		return false;
	}

	if(!this.StopInDepots(true))
		return false;

	foreach(vehicle_id, _ in vehicle_list)
	{
		// Store state in vehicle so they won't be sold
		ClueHelper.StoreInVehicleName(vehicle_id, "suspended");
	}

	// Make sure vehicles that load at stations skip to depot instead of potentially forever waiting for full load
	SkipAllVehiclesToClosestDepot();

	this.SetState(Connection.STATE_SUSPENDED);

	return true;
}

function Connection::CloseConnection()
{
	Log.Info("CloseConnection " + node[0].GetName() + " - " + node[1].GetName(), Log.LVL_INFO);

	if(this.state == Connection.STATE_CLOSING_DOWN || this.state == Connection.STATE_CLOSED_DOWN || this.state == Connection.STATE_FAILED)
	{
		Log.Warning("CloseConnection fails because the current state ( " + this.state + " ) of the connection does not allow initiating the closing down process.");
		return false;
	}

	// Send all vehicles to depot for selling and set state STATE_CLOSING_DOWN
	this.SetState(Connection.STATE_CLOSING_DOWN);

	local vehicle_list = this.GetVehicles();
	if(vehicle_list.IsEmpty())
	{
		return true;
	}

	// Change orders so that vehicles will stay at the depots when they go there. 
	// By doing like this instead of calling SendVehicleForSelling for all vehicles, they will keep the stations in the orders
	// so that it is possible to query the stations to see if all vehicles has been sold or not.
	if(!this.StopInDepots(true))
		return false;

	foreach(vehicle_id, _ in vehicle_list)
	{
		// Store state in vehicles
		ClueHelper.StoreInVehicleName(vehicle_id, "close conn");
	}

	// Make sure vehicles that load at stations skip to depot instead of potentially forever waiting for full load
	SkipAllVehiclesToClosestDepot();

	return true;
}

function Connection::IsTownOnly()
{
	foreach(n in this.node)
	{
		// Return false if there is a non-town node
		if(!n.IsTown()) return false;
	}

	// otherwise true
	return true;
}

function Connection::GetTotalPoputaltion()
{
	local val = null;
	local pop = 0;
	foreach(val in town)
	{
		if(val != null)
		{
			pop += this.AITown().GetPopulation(val);
		}
	}
	return pop;
}
function Connection::GetTotalDistance() 
{
	if(node.len() != 2)
		return 0;

	return AIMap.DistanceManhattan( this.node[0].GetLocation(), this.node[1].GetLocation() );
}
function Connection::FindEngineModelToBuy()
{
	return Strategy.FindEngineModelToBuy(this.cargo_type, AIVehicle.VT_ROAD);
}
function Connection::BuyVehicles(num_vehicles, engine_id)
{
	if(station.len() != 2)
	{
		Log.Warning("BuyVehicles: wrong number of stations", Log.LVL_INFO);
		return false;
	}

	if(depot.len() != 2)
	{
		Log.Warning("BuyVehicles: wrong number of depots", Log.LVL_INFO);
		return false;
	}

	local min_reliability = 85;
	local new_bus;
	local i;
	local exec = AIExecMode();

	local share_orders_with = -1;

	if(engine_id == null || !AIEngine.IsBuildable(engine_id))
	{
		Log.Warning("BuyVehicles: failed to find a bus/truck to build", Log.LVL_INFO);
		return false;
	}

	Log.Info("BuyVehicles: engine name: " + AIEngine.GetName(engine_id), Log.LVL_SUB_DECISIONS);

	local new_buses = [];
	
	// Buy buses
	for(i = 0; i < num_vehicles; ++i)
	{
		new_bus = AIVehicle.BuildVehicle(depot[i%2], engine_id);
		if(AIVehicle.IsValidVehicle(new_bus))
		{
			if(AIVehicle.RefitVehicle(new_bus, this.cargo_type))
			{
				Log.Info("I built a bus/truck", Log.LVL_DEBUG);
				new_buses.append(new_bus);
			}
			else
			{
				Log.Warning("Failed to refit vehicle because " + AIError.GetLastErrorString(), Log.LVL_INFO);

				// Sell the vehicle as we couldn't refit it
				AIVehicle.SellVehicle(new_bus);
				new_bus = -1;
			}

			// Store current state in vehicle name
			if(this.state == Connection.STATE_SUSPENDED)
				ClueHelper.StoreInVehicleName(new_bus, "suspended");
			else if(this.state == Connection.STATE_ACTIVE)
				ClueHelper.StoreInVehicleName(new_bus, "active");
			else if(this.state == Connection.STATE_CLOSING_DOWN)  // There is not really a reason to buy vehicles in this state!
				ClueHelper.StoreInVehicleName(new_bus, "close conn");
			else if(this.state == Connection.STATE_BUILDING) 
			{ }
			else if(this.state == null) // build state
				ClueHelper.StoreInVehicleName(new_bus, "active");
			else
			{
				Log.Warning("Built vehicle while in state " + this.state, Log.LVL_INFO);
			}

		}

		if(!AIVehicle.IsValidVehicle(new_bus)) // if failed to buy last vehicle
		{
			if(i == 0)
			{
				local dep = depot[i%2];
				local x = AIMap.GetTileX(dep);
				local y = AIMap.GetTileY(dep);

				Log.Info("Build vehicle error string: " + AIError.GetLastErrorString(), Log.LVL_INFO);

				Log.Warning("Depot is " + dep + ", location: " + x + ", " + y, Log.LVL_INFO);

				if(!AIMap.IsValidTile(dep))
					Log.Warning("Depot is invalid tile!", Log.LVL_INFO);

				if(!AIRoad.IsRoadDepotTile(dep))
					Log.Warning("No depot!", Log.LVL_INFO);

				if(!AIEngine.IsValidEngine(engine_id))
					Log.Warning("Invalid engine!", Log.LVL_INFO);

				if(!AIEngine.IsBuildable(engine_id))
					Log.Warning("Engine not buildable!", Log.LVL_INFO);

				Log.Warning("Failed to buy bus/truck", Log.LVL_INFO);
				return false; // if no bus have been built, return false
			}
			else
			{
				num_vehicles = i;
				break;
			}
		}

		// See if there is existing vehicles to share orders with 
		// (vehicles not in depot could have been destroyed by a train or an UFO so don't rely
		// on old information -> check every time that share_orders_with is a valid vehicle)
		if(share_orders_with == -1 || !AIVehicle.IsValidVehicle(share_orders_with))
		{
			local existing_vehicles = GetVehicles();
			
			local num_old_vehicles = existing_vehicles.Count();
			if(!existing_vehicles.IsEmpty())
				share_orders_with = existing_vehicles.Begin();
		}

		// Share orders of existing vehicle or assign new orders
		if(AIVehicle.IsValidVehicle(share_orders_with))
		{
			AIOrder.ShareOrders(new_bus, share_orders_with);
		}
		else
		{
			// Always go to depot if breakdowns are "normal", otherwise only go if needed
			local service_flag = AIGameSettings.GetValue("vehicle_breakdowns") == 2? 0 : AIOrder.AIOF_SERVICE_IF_NEEDED;

			AIOrder.AppendOrder(new_bus, depot[0], service_flag);
			AIOrder.AppendOrder(new_bus, station[0], AIOrder.AIOF_NON_STOP_INTERMEDIATE); 
			AIOrder.AppendOrder(new_bus, depot[1], service_flag);  
			AIOrder.AppendOrder(new_bus, station[1], AIOrder.AIOF_NON_STOP_INTERMEDIATE);

			share_orders_with = new_bus;
		}
	}

	
	for(i = 0; i < new_buses.len(); ++i)
	{
		if(i%2 == 0)
			AIOrder.SkipToOrder(new_buses[i], 1);
		else
			AIOrder.SkipToOrder(new_buses[i], 3);

	}
	
	for(i = 0; i < new_buses.len(); ++i)
	{
		if(i%2 == 1)
			AIController.Sleep(20);

		// Don't start new vehicles if connection is suspended
		if(this.state != Connection.STATE_SUSPENDED)
			AIVehicle.StartStopVehicle(new_buses[i]);
		else
			Log.Info("Don't start new vehicle (" + AIVehicle.GetName(new_buses[i]) + " because connection is suspended", Log.LVL_SUB_DECISIONS);
	}

	this.last_bus_buy = AIDate.GetCurrentDate();

	Log.Info("Built bus => return true", Log.LVL_DEBUG);
	return true;
}
function Connection::NumVehiclesToBuy(engine_id)
{
	local distance = GetTotalDistance().tofloat();
	local speed = AIEngine.GetMaxSpeed(engine_id);
	local travel_time = 5 + Engine.GetFullSpeedTraveltime(engine_id, distance);
	local capacity = AIEngine.GetCapacity(engine_id);

	Log.Info("NumVehiclesToBuy(): distance: " + distance, Log.LVL_SUB_DECISIONS);
	Log.Info("NumVehiclesToBuy(): travel time: " + travel_time, Log.LVL_SUB_DECISIONS);
	Log.Info("NumVehiclesToBuy(): capacity:  " + capacity + " cargo_type: " + cargo_type + " engine_id: " + engine_id, Log.LVL_SUB_DECISIONS);

	if(this.IsTownOnly())
	{
		// Town only connections
		local population = GetTotalPoputaltion().tofloat();

		Log.Info("NumVehiclesToBuy(): total town population:  " + population, Log.LVL_SUB_DECISIONS);

		local num_bus = 1 + max(0, (Helper.Min(1400, population - 200) / capacity / 15).tointeger());
		local extra = distance/capacity/3;
		num_bus += extra;
		Log.Info("NumVehiclesToBuy(): extra:  " + extra, Log.LVL_SUB_DECISIONS);

		num_bus = num_bus.tointeger();

		Log.Info("NumVehiclesToBuy(): Buy " + num_bus + " vehicles", Log.LVL_SUB_DECISIONS);
		return num_bus;
	}
	else
	{
		// All other connections
		local max_cargo_available = Helper.Max(this.node[0].GetCargoAvailability(), this.node[1].GetCargoAvailability());
		Log.Info("NumVehiclesToBuy(): cargo availability: " + max_cargo_available, Log.LVL_SUB_DECISIONS);

		// * 70 / 100 => assume 90% station rating
		local tor_month_to_days = 30;
		local tor_production = max_cargo_available * 70 / 100 * (travel_time * 2) / tor_month_to_days;
		local num_veh = 2 + (tor_production / capacity).tointeger();

		// Old num_veh code:
		//local num_veh = (travel_time * capacity / 83).tointeger();

		Log.Info("NumVehiclesToBuy(): Buy " + num_veh + " vehicles", Log.LVL_SUB_DECISIONS);
		return num_veh;
	}
}

function Connection::ManageState()
{
	Log.Info("Manage connection state - state: " + this.state + " - " + node[0].GetName() + " - " + node[1].GetName(), Log.LVL_SUB_DECISIONS);

	// Check if there is at least one working transport direction. Working in this case is that
	// one end produces the cargo and another end accpts it.
	if(this.state != Connection.STATE_CLOSING_DOWN && this.state != Connection.STATE_SUSPENDED && this.state != Connection.STATE_CLOSED_DOWN)
	{
		local accept0 = Station.IsCargoAccepted(this.station_statistics[0].station_id, this.node[0].cargo_id);
		local accept1 = Station.IsCargoAccepted(this.station_statistics[1].station_id, this.node[1].cargo_id);
		local has_prod_accept_pair = (this.node[0].IsCargoProduced() && accept1) ||
				(this.node[1].IsCargoProduced() && accept0);

		// TODO: Read OpenTTD Source and see if SkipToOrder works if vehicles already at order 0 and we want to skip to that order so they leave the station

		if(!has_prod_accept_pair)
		{
			// One industry has closed down or town station has lost accept/produce status
			// -> CloseConnection

			Log.Info("Connection do no longer has at least one producer-accepter pair -> close connection", Log.LVL_DEBUG);
			this.CloseConnection();
			return;
		}

		// Check if any of the (industry) nodes has disappeared. That is if the industry is gone or has moved elsewhere. 
		if(this.node[0].HasNodeDissapeared() || this.node[1].HasNodeDissapeared())
		{
			Log.Info("One or more of the nodes (town/industry) of connection has disappeared -> close connection", Log.LVL_DEBUG);
			this.CloseConnection();
			return;
		}
	}

	// Go through the possible states
	if(this.state == Connection.STATE_ACTIVE)
	{
		if(this.GetVehicles().IsEmpty())
		{
			// Close connection if it does not have any vehicles
			this.CloseConnection();
		}
		else

		// Production checks
		if(!this.IsTownOnly())
		{
			// Check if one of the producing industries has zero production
			local zero_raw_production = false;
			local zero_secondary_production = false;
			local max_production = 0;

			foreach(node in this.node)
			{
				local node_production = node.GetLastMonthProduction();
				if(node.IsIndustry() && 
						node.IsCargoProduced() && 
						node_production < 1)
				{
					if(AIIndustryType.IsRawIndustry(AIIndustry.GetIndustryType(node.industry_id)))
						zero_raw_production = true;
					else
						zero_secondary_production = true;
				}

				// Keep track of the max production
				if(node_production > max_production)
					max_production = node_production;
			}

			// If there is a secondary industry with zero production, start by suspending
			// the connection and see if it will start producing again. The vehicles of
			// this connection could be blocking the trucks with raw materials.

			if(max_production > 0)
			{
				if(zero_secondary_production || zero_secondary_production)
				{
					// Dual way connection where one node has zero production

					// Update full-load orders
					// The function will only full load at the end with highest production so that will solve the issue
					this.FullLoadAtStations(true);
				}
			}
			else
			{
				// Single or double way connection with all nodes at zero production

				if(zero_secondary_production)
				{
					// One of the producing nodes is a non-raw node -> suspend connection for a while
					// and hope that the industry will start produce cargo again

					// However, if the stations are not much in use, it is better to keep the connection
					// active to not cause bad station ratings.
					if(this.max_station_usage > 135 || this.max_station_tile_usage > 180)
					{
						this.SuspendConnection();
					}
				}
				else if(zero_raw_production)
				{
					// Only raw industries -> No hope for increased production again
					this.CloseConnection();
				}
			}
		}

		if(this.node[0].HasNodeDissapeared() || this.node[1].HasNodeDissapeared())
		{
			Log.Info("A node has dissapeared from connection " + this.GetName() + " => close it down", Log.LVL_INFO);
			this.CloseConnection();
			return;
		}
	}
	else if(this.state == Connection.STATE_SUSPENDED)
	{
		local now = AIDate.GetCurrentDate();
		local suspended_time = now - this.state_change_date;

		Log.Info("Connection has been suspended for " + suspended_time + " days");

		// Check if the connection has been suspended for at least 35 days
		if(suspended_time > 35)
		{
			// Check if the connection should be re-activated or closed down
			foreach(node in this.node)
			{
				if(node.GetLastMonthProduction() > 0)
				{

					this.ReActivateConnection();
					break;
				}
			}

			// If the connection was not re-activated within 90 days, close it down
			if(this.state == Connection.STATE_SUSPENDED && suspended_time > 90)
			{
				this.CloseConnection();
			}
		}
	}
	else if(this.state == Connection.STATE_CLOSING_DOWN)
	{
		local vehicle_list = this.GetVehicles();

		// Sell vehicles in depot
		foreach(vehicle_id, _ in vehicle_list)
		{
			if(AIVehicle.GetState(vehicle_id) == AIVehicle.VS_IN_DEPOT)
			{
				AIVehicle.SellVehicle(vehicle_id);
			}
		}

		// Refresh the vehicle list
		vehicle_list = this.GetVehicles();
		if(vehicle_list.IsEmpty())
		{
			// All vehicles has been sold

			local front_tiles = AIList();

			// Demolish stations
			foreach(station_tile in this.station)
			{
				Helper.SetSign(station_tile, "close conn");

				local station_id = AIStation.GetStationID(station_tile);

				// Remember the front tiles for later road removal 
				front_tiles.AddList(Station.GetRoadFrontTiles(station_id));

				// Demolish station
				Station.DemolishStation(station_id);
			}

			// Demolish depots
			foreach(depot in this.depot)
			{
				Helper.SetSign(depot, "close conn");
				local front = AIRoad.GetRoadDepotFrontTile(depot);

				// Remember the front tile for later road removal
				front_tiles.AddItem(front, 0);

				// Demolish depot
				if(AIRoad.IsRoadDepotTile(depot) && !AITile.DemolishTile(depot))
				{
					if(AIError.GetLastError() == AIError.ERR_VEHICLE_IN_THE_WAY)
					{
						local sell_failed = false;
						local vehicles_in_depot = Vehicle.GetVehiclesAtTile(depot);
						foreach(veh_in_depot, _ in vehicles_in_depot)
						{
							if(!AIVehicle.IsStoppedInDepot(veh_in_depot))
							{
								// The vehicle is not stoped in depot
								// -> Try to stop it and see if it is now stopped in the depot
								AIVehicle.StartStopVehicle(veh_in_depot);
								if(!AIVehicle.IsStoppedInDepot(veh_in_depot))
								{
									// The vehicle is stoped, but not in the depot
									// -> Start it again
									AIVehicle.StartStopVehicle(veh_in_depot);
									sell_failed = true;
									continue;
								}
							}

							AIVehicle.SellVehicle(veh_in_depot);
						}

						if(sell_failed)
						{
							Log.Warning("Error while removing depot for closing down connection: There was a vehicle in the way half way on the way in or out of the depot -> could not sell it", Log.LVL_INFO);
							Log.Info("-> abort closing connection for now", Log.LVL_INFO);
							// Abort closing down for a while
							return;
						}

						// Now the depot should be empty of vehicles
						if(!AITile.DemolishTile(depot))
						{
							Log.Warning("Error: Failed to demolish depot even after having tried to sell vehicles that are in the way", Log.LVL_INFO);
							Log.Info("-> abort closing connection for now", Log.LVL_INFO);
							return;
						}
					}
					else
					{
						Log.Warning("Could not demolish depot because of " + AIError.GetLastErrorString());
						Log.Info("-> abort closing connection for now", Log.LVL_INFO);
						return;
					}
				}
				AIRoad.RemoveRoad(front, depot);
			}

			// debug signs
			foreach(tile, _ in front_tiles)
			{
				Helper.SetSign(tile, "front");
			}

			// Remove road from all front tiles
			foreach(tile, _ in front_tiles)
			{
				RoadBuilder.RemoveRoadUpToRoadCrossing(tile);
			}

			Log.Info("Change state to STATE_CLOSED_DOWN");
			this.SetState(Connection.STATE_CLOSED_DOWN);
		}
	}
}

function Connection::ManageStations()
{
	if(this.state != Connection.STATE_ACTIVE)
		return;

	// Don't manage too often
	local now = AIDate.GetCurrentDate();
	if(this.last_station_manage != null && now - this.last_station_manage < 5)
		return;
	this.last_station_manage = now;

	Log.Info("Manage Stations: " + this.GetName(), Log.LVL_INFO);

	// Update station statistics
	local max_station_usage = 0;
	local max_station_tile_usage = 0;

	for(local i = 0; i < this.station.len(); ++i)
	{
		local station_tile = this.station[i];
		local station_statistics = this.station_statistics[i];

		// Close connection if one of the stations are invalid
		if(!AIStation.IsValidStation(AIStation.GetStationID(station_tile)))
		{
			Log.Warning("An invalid station was detected -> Close connection", Log.LVL_INFO);
			CloseConnection();
			return;
		}

		station_statistics.ReadStatisticsData();

		local usage = Helper.Max(station_statistics.usage.bus.percent_usage, station_statistics.usage.truck.percent_usage);
		local max_tile_usage = Helper.Max(station_statistics.usage.bus.percent_usage_max_tile, station_statistics.usage.truck.percent_usage_max_tile);

		if(usage > max_station_usage)
			max_station_usage = usage;

		if(max_tile_usage > max_station_tile_usage)
			max_station_tile_usage = max_tile_usage;
	}

	this.max_station_usage = max_station_usage;
	this.max_station_tile_usage = max_station_tile_usage;

	// Check that all station parts are connected to road
	for(local town_i = 0; town_i < 2; town_i++)
	{
		local station_id = AIStation.GetStationID(this.station[town_i]);
		local existing_stop_tiles = AITileList_StationType(station_id, AIStation.STATION_BUS_STOP);
		existing_stop_tiles.AddList(AITileList_StationType(station_id, AIStation.STATION_TRUCK_STOP));
		local num_remaining_stop_tiles = existing_stop_tiles.Count();

		foreach(stop_tile, _ in existing_stop_tiles)
		{
			local front_tile = AIRoad.GetRoadStationFrontTile(stop_tile);
			if(!AIRoad.AreRoadTilesConnected(stop_tile, front_tile))
			{
				Log.Warning("Found part of bus station " + AIStation.GetName(station_id) + " that is not connected to road. Trying to fix it.. ", Log.LVL_INFO);
				local i = 0;
				while(!AIRoad.BuildRoad(front_tile, stop_tile))
				{
					// Try a few times to build the road if a vehicle is in the way
					if(i++ == 10) break;

					local last_error = AIError.GetLastError();
					if(last_error != AIError.ERR_VEHICLE_IN_THE_WAY && last_error != AIError.ERR_NOT_ENOUGH_CASH)
					{
						// Can't connect the station -> remove it
						if(num_remaining_stop_tiles > 1) // Don't remove the last station tile. If we would want to do that the entire connection has to be closed down which is not supported.
						{
							Helper.SetSign(stop_tile, "no rd acc");
							Helper.SetSign(stop_tile, "no road access");
							AITile.DemolishTile(stop_tile);
							num_remaining_stop_tiles--;

							if(this.station[town_i] == stop_tile)
							{
								// Repair the station variable (it should be a tile of the station, but the tile it contains no longer contains a stop)
								this.station[town_i] = AIBaseStation.GetLocation(station_id);
							}
						}
					}

					AIController.Sleep(5);
				}

			}
		}

	}


	// Check if the stations are allowed to expand, and then check if there is a need for expansion.
	local max_num_bus_stops_per_station = AIController.GetSetting("max_num_bus_stops");
	if(max_num_bus_stops_per_station > 1)
	{
		local percent_usage = [Helper.Max(station_statistics[0].usage.bus.percent_usage, station_statistics[0].usage.truck.percent_usage),
				Helper.Max(station_statistics[1].usage.bus.percent_usage, station_statistics[1].usage.truck.percent_usage) ];

		Log.Info("Checking if connection " + node[0].GetName() + " - " + node[1].GetName() + " needs more bus stops", Log.LVL_SUB_DECISIONS);
		Log.Info("bus usage: " + percent_usage[0] + ", " + percent_usage[0], Log.LVL_SUB_DECISIONS);
		Log.Info("pax waiting: " + station_statistics[0].cargo_waiting + ", " + station_statistics[1].cargo_waiting, Log.LVL_SUB_DECISIONS);

		// look for connections that need additional bus stops added
		if( (percent_usage[0] > 150 && station_statistics[0].cargo_waiting > 150) ||
			(percent_usage[0] > 250) ||
			(percent_usage[1] > 150 && station_statistics[1].cargo_waiting > 150) ||
			(percent_usage[1] > 250) )
		{
			for(local town_i = 0; town_i < 2; town_i++)
			{
				Log.Info("town/industry: " + node[town_i].GetName(), Log.LVL_DEBUG);

				// more bus stops needed
				local station_id = AIStation.GetStationID(this.station[town_i]);

				local station_type = AIStation.STATION_BUS_STOP;
				if(AIRoad.GetRoadVehicleTypeForCargo(this.cargo_type) == AIRoad.ROADVEHTYPE_TRUCK)
					station_type = AIStation.STATION_TRUCK_STOP;

				local existing_stop_tiles = AITileList_StationType(station_id, AIStation.STATION_BUS_STOP);
				existing_stop_tiles.AddList(AITileList_StationType(station_id, AIStation.STATION_TRUCK_STOP));

				// Don't add more than 4 bus stops
				if(existing_stop_tiles.Count() >= max_num_bus_stops_per_station)
				{
					Log.Info("To many bus stations already for town/industry " + node[town_i].GetName(), Log.LVL_DEBUG);
					continue;
				}

				Log.Info("Grow station for town/industry " + node[town_i].GetName(), Log.LVL_INFO);

				// Try to first grow in parallel and then if it fails for some other reason than out of money,
				// fall back to the classic grow function
				local grown_parallel_ret = this.clueless_instance.GrowStationParallel(station_id, station_type);
				local grown = IsSuccess(grown_parallel_ret);
				if(!grown && grown_parallel_ret != RETURN_NOT_ENOUGH_MONEY)
					grown = IsSuccess(this.clueless_instance.GrowStation(station_id, station_type));

				if(grown)
				{
					Log.Info("Station has been grown with one bus stop", Log.LVL_INFO);

					if(IsSuccess(grown_parallel_ret))
						Log.Info("Growing was done in parallel", Log.LVL_INFO);

					// Change the usage so that it is percent of new capacity, so that the AI don't quickly add another bus stop before the
					// statistics adopt to the new capacity.
					local old_size = existing_stop_tiles.Count();
					local new_size = old_size + 1;
					local new_usage = (percent_usage[town_i] * old_size) / new_size;
					Log.Info("old usage = " + percent_usage[town_i] + "  new usage = " + new_usage, Log.LVL_SUB_DECISIONS);

					if(station_type == AIStation.STATION_BUS_STOP)
					{
						this.station_statistics[town_i].usage.bus.percent_usage = new_usage;
					}
					if(station_type == AIStation.STATION_TRUCK_STOP)
					{
						this.station_statistics[town_i].usage.truck.percent_usage = new_usage;
					}

					this.station_statistics[town_i].ReadStatisticsData();
				}

			}
		}
	}

	// Check if we should buy a statue in the town
	for(local town_i = 0; town_i < 2; town_i++)
	{
		local tile = this.station[town_i];
		local town = AITile.GetClosestTown(tile);
		local prod = this.node[town_i].GetCargoAvailability(); // don't build statues in town if we only deliver cargo there

		if(prod > 0 && !AITown.HasStatue(town))
		{
			local statue_cost = -1;
			{
				local tm = AITestMode();
				local am = AIAccounting();

				if(AITown.PerformTownAction(town, AITown.TOWN_ACTION_BUILD_STATUE))
					statue_cost = am.GetCosts();
			}

			if(AICompany.GetBankBalance(AICompany.COMPANY_SELF) > statue_cost * 10)
			{
				// Build statue if we have 10 times the money it costs
				AITown.PerformTownAction(town, AITown.TOWN_ACTION_BUILD_STATUE);
			}
		}
	}

}

function Connection::ManageVehicles()
{
	// Don't manage vehicles for failed connections.
	if(this.state != Connection.STATE_ACTIVE)
		return;

	Log.Info("Connection::ManageVehicles called for connection: " + 
			AIStation.GetName(AIStation.GetStationID(this.station[0])) + " - " + 
			AIStation.GetName(AIStation.GetStationID(this.station[1])), Log.LVL_DEBUG);

	//AISign.BuildSign(this.station[0], "manage");
	//AISign.BuildSign(this.station[1], "manage");

	// Sell vehicles that has one of the stations as order, but has at
	// least one invalid order
	local broken_vehicles = GetBrokenVehicles();
	if(!broken_vehicles.IsEmpty())
	{
		foreach(veh, _ in broken_vehicles)
		{
			Log.Info("Send vehicle " + AIVehicle.GetName(veh) + " for selling because the connection found that it is broken", Log.LVL_SUB_DECISIONS);
			SendVehicleForSelling(veh);
		}
	}

	local now = AIDate.GetCurrentDate();
	local days_since_built = now - date_built;
	if( ((last_vehicle_manage == null && days_since_built > 75) || // first manage after a bit more than two months
			(last_vehicle_manage != null && last_vehicle_manage + AIDate.GetDate(0, 3, 0) < now )) &&  // and then every 3 months
			AIDate.GetMonth(now) > 2)  // but don't make any management on the first two months of the year
	{
		last_vehicle_manage = now;

		Log.Info("Connection::ManageVehicles time to manage vehicles for connection " + this.node[0].GetName() + " - " + this.node[1].GetName(), Log.LVL_INFO);
		Helper.SetSign(this.station[0] + 1, "manage");
		Helper.SetSign(this.station[1] + 1, "manage");


		// Sometimes look for new vehicles to upgrade to
		if(AIBase.RandRange(5) < 1 || 
				this.desired_engine == null ||
				!AIEngine.IsBuildable(this.desired_engine)) // Always find new desired engine type if the previous one is no longer buildable
		{
			this.FindNewDesiredEngineType();
			this.MassUpgradeVehicles();
		}


		AICompany.SetLoanAmount(AICompany.GetMaxLoanAmount());
		// wait one year before first manage, and then every year

		local income = 0;
		local num_income = 0;
		local veh_list = AIList();

		local connection_vehicles = GetVehicles();
		local veh = null;
		foreach(veh, _ in connection_vehicles)
		{
			// If the vehicle is to old => sell it. Otherwise if the vehicle is kept, include it in the income checking.
			if(AIVehicle.GetAge(veh) > AIVehicle.GetMaxAge(veh) - 365 * 2)
			{
				AIVehicle.SetName(veh, "old -> sell");
				SendVehicleForSelling(veh);
			}
			else 
			{
				// Check if the vehicle has been told to upgrade, but is not going to a depot
				if(Connection.IsVehicleToldToUpgrade(veh) && !IsVehicleGoingToADepot(veh))
				{
					AIVehicle.SendVehicleToDepot(veh);
				}

				if(AIVehicle.GetAge(veh) > 90) // Only include vehicles older than 90 days in the income stats
				{
					income += AIVehicle.GetProfitThisYear(veh);
					num_income++;
				}
				veh_list.AddItem(veh, veh);
			}
		}
		local mean_income = 0;
		if(num_income != 0)
			mean_income = income / num_income;

		local min_rating = 100;
		local max_rating = 0;
		local max_waiting = 0;
		local station_tile = null;
		foreach(station_tile in this.station)
		{
			local station_id = AIStation.GetStationID(station_tile);
			local rate = AIStation.GetCargoRating(station_id, cargo_type);
			local waiting = AIStation.GetCargoWaiting(station_id, cargo_type);
			if(rate < min_rating)
				min_rating = rate;
			if(rate > max_rating)
				max_rating = rate;
			if(waiting > max_waiting)
				max_waiting = waiting;
		}

		Log.Info("connection income: " + income, Log.LVL_INFO);
		Log.Info("connection mean income: " + mean_income, Log.LVL_INFO);
		Log.Info("connection long time mean income: " + long_time_mean_income, Log.LVL_INFO);
		Log.Info("connection max station usage: " + this.max_station_usage, Log.LVL_INFO);
		Log.Info("connection max station tile usage: " + this.max_station_tile_usage, Log.LVL_INFO);


		local recently_repaired = this.last_repair_route != null && 
			this.last_repair_route + 30 * 3 > AIDate.GetCurrentDate(); // repaired in the last 3 months
		if(!recently_repaired &&
			(
				mean_income < 30 ||
				(long_time_mean_income > 0 && income < (long_time_mean_income / 2)) ||
						(long_time_mean_income <= 0 && income < (long_time_mean_income * 2) / 3))
			)
		{
			// Repair the connection if it is broken
			if(RepairRoadConnection())
				this.long_time_mean_income = this.long_time_mean_income * 7 / 10; // Fake a reduction of long time mean in order to prevent or make management hell less likely to happen.
			this.last_repair_route = AIDate.GetCurrentDate();
		}

		this.long_time_mean_income = (this.long_time_mean_income * 9 + income) / 10;

		// Unless the vehicle list is empty, only buy/sell if we have not bought/sold anything the last 30 days.
		local recently_sold = last_bus_sell != null && last_bus_sell + 30 > now;
		local recently_bought = last_bus_buy != null && last_bus_buy + 30 > now;
		if( veh_list.Count() == 0 ||
				(!recently_sold && !recently_bought) )
		{
			// Sell check
			if( (income < 0 || this.max_station_usage > 200 || this.max_station_tile_usage > 230 || max_waiting < 10) && veh_list.Count() > 1)
			{
				local num_to_sell = Helper.Max(1, veh_list.Count() / 8);
				
				if(income < 0)
				{
					local engine_type_id = AIVehicle.GetEngineType(veh_list.Begin());
					local running_cost = AIEngine.GetRunningCost(engine_type_id);
					num_to_sell = Helper.Min(veh_list.Count() - 1, (-income) / running_cost + 1);
				}
				else if(this.max_station_usage > 200 || this.max_station_tile_usage > 230)
				{
					num_to_sell = Helper.Max(1, veh_list.Count() / 6);
				}


				Log.Info("Manage vehicles decided to Sell " + num_to_sell + " buses/trucks", Log.LVL_INFO);
				for(local i = 0; i < num_to_sell; i++)
				{	
					local veh_to_sell = null;

					// sell one vehicle

					// For some particular reason buses are not sent to depot. Also for some particular reason the depots are not added to order list.

					veh_list.Valuate(AIVehicle.GetAgeLeft)
					veh_list.Sort(AIAbstractList.SORT_BY_VALUE, true); // Vehicle with least amount of time left first
					veh_to_sell = veh_list.Begin();
					if(!AIVehicle.IsValidVehicle(veh_to_sell))
					{
						Log.Error("Can't sell bad vehicle", Log.LVL_INFO);
						return;
					}

					SendVehicleForSelling(veh_to_sell);

					// Remove the sold vehicle from the list of vehicles in the connection
					veh_list.Valuate(Helper.ItemValuator);
					veh_list.RemoveValue(veh_to_sell);
				}
			}
			else 
			{
				if(veh_list.Count() == 0 || 
					(this.max_station_usage < 170 && this.max_station_tile_usage < 200 &&
					 max_waiting > 40 + veh_list.Count() * 3) )
				{
					// Buy a new vehicle
					Log.Info("Manage vehicles: decided to Buy a new bus", Log.LVL_INFO);
					local engine = FindEngineModelToBuy();
					local num = 1 + (max_waiting-100) / 100;
					if(num < 1)
						num = 1;
					num = Helper.Min(num, 5); // Don't buy more than 5 at a time
					BuyVehicles(num, engine);
				}
			}
		}
		else
		{
			Log.Info("Don't buy/sell vehicles yet", Log.LVL_INFO);
		}

		Log.Info("min_rating = " + min_rating + " max_rating = " + max_rating + " max_waiting = " + max_waiting, Log.LVL_INFO);
		if(this.IsTownOnly())
			FullLoadAtStations(min_rating < 40 && max_rating < 65 && max_waiting < 70);
		else
			FullLoadAtStations(true);

		// Unset manage signs
		Helper.SetSign(this.station[0] + 1, "");
		Helper.SetSign(this.station[1] + 1, "");
	}
	else
	{
		Log.Info("Connection::ManageVehicles: to early to manage", Log.LVL_SUB_DECISIONS);
	}	
}

function Connection::SendVehicleForSelling(vehicle_id)
{
	if(!AIVehicle.IsValidVehicle(vehicle_id))
		return;

	Log.Info("Send vehicle " + AIVehicle.GetName(vehicle_id) + " for selling", Log.LVL_INFO);

	ClueHelper.StoreInVehicleName(vehicle_id, "sell");

	// Unshare & clear orders
	AIOrder.UnshareOrders(vehicle_id);
	while(AIOrder.GetOrderCount(vehicle_id) > 0)
	{
		AIOrder.RemoveOrder(vehicle_id, 0);
	}

	// Check if it is already in a depot
	if(AIVehicle.IsStoppedInDepot(vehicle_id))
		return;

	if(AIRoad.IsRoadDepotTile(depot[0])) 
	{
		// Send vehicle to specific depot so it don't get lost
		if(AIOrder.AppendOrder(vehicle_id, depot[0], AIOrder.AIOF_STOP_IN_DEPOT))
		{
			// Add an extra order so we can skip between the orders to fully make sure vehicles leave
			// stations they previously were full loading at.
			AIOrder.AppendOrder(vehicle_id, depot[0], AIOrder.AIOF_STOP_IN_DEPOT);

			// so that vehicles that load stuff departures
			AIOrder.SkipToOrder(vehicle_id, 1); 
			AIOrder.SkipToOrder(vehicle_id, 0); 

			// Remove the second now unneccesary order
			AIOrder.RemoveOrder(vehicle_id, 1);
		}
	}
	else
	{
		// depot[0] has been destroyed
		AIVehicle.SendVehicleToDepot(vehicle_id);
	}

	// Turn around road vehicles that stand still, possible in queues.
	if(AIVehicle.GetVehicleType(vehicle_id) == AIVehicle.VT_ROAD)
	{
		if(AIVehicle.GetCurrentSpeed(vehicle_id) == 0)
		{
			Log.Info("Turn aronud vehicle that was sent for selling since speed is zero and it might be stuck in a queue.", Log.LVL_DEBUG);
			Helper.SetSign(AIVehicle.GetLocation(vehicle_id), "turn");
			AIVehicle.ReverseVehicle(vehicle_id);
		}
	}

	this.last_bus_sell = AIDate.GetCurrentDate();
}

function Connection::GetVehicles()
{
	// Return the intersection of the vehicles that stop on station 0 and station 1.
	local veh0 = AIVehicleList_Station(AIStation.GetStationID(station[0]));
	local veh1 = AIVehicleList_Station(AIStation.GetStationID(station[1]));

	veh0.KeepList(veh1);
	local intersect = veh0;

	return intersect;
}

function Connection::GetBrokenVehicles()
{
	local veh0 = AIVehicleList_Station(AIStation.GetStationID(station[0]));
	local veh1 = AIVehicleList_Station(AIStation.GetStationID(station[1]));

	veh0.AddList(veh1);
	local union = veh0;

	union.Valuate(HasVehicleInvalidOrders);
	union.KeepValue(1);

	return union;
}

function Connection::FullLoadAtStations(enable_full_load)
{
	local allow_full_load = [];
	local town_only = this.IsTownOnly();

	if(!enable_full_load)
	{
		foreach(node in this.node)
		{
			allow_full_load.append(false);
		}
	}
	else if(town_only)
	{
		foreach(node in this.node)
		{
			allow_full_load.append(true);
		}
	}
	else
	{
		// Only full load at the industry with highest production

		// Find out which node has the highest production
		local max_prod_node = null;
		local max_prod_value = -1;
		foreach(node in this.node)
		{
			if(node.IsCargoProduced())
			{
				local prod = node.GetLastMonthProduction();
				if(prod > max_prod_value)
				{
					max_prod_value = prod;
					max_prod_node = node;
				}
			}
		}

		foreach(node in this.node)
		{
			// Append true only for the node with highest production
			allow_full_load.append(node == max_prod_node);
		}
	}

	Log.Info("Full load = " + enable_full_load + " for connection " + node[0].GetName() + " - " + node[1].GetName(), Log.LVL_SUB_DECISIONS);
	local connection_vehicles = GetVehicles();
	if(connection_vehicles.Count() > 0)
	{
		local veh = connection_vehicles.Begin();
		local node_id = -1;
		for(local i = 0; i < AIOrder.GetOrderCount(veh); i++)
		{
			if(AIOrder.IsGotoStationOrder(veh, i))
			{
				++node_id;

				if(node_id >= allow_full_load.len())
				{
					Log.Error("Vehicle " + AIVehicle.GetName(veh) + " has more stations than the connection got nodes in Connection::FullLoadAtStations", Log.LVL_INFO);
					break;
				}

				local flags = AIOrder.GetOrderFlags(veh, i);
				if(allow_full_load[node_id])
				{
					flags = flags | AIOrder.AIOF_FULL_LOAD; // add the full load flag
				}
				else
				{
					if((flags & AIOrder.AIOF_FULL_LOAD) != 0) // if full load flag exists since befare
					{
						flags = flags & ~AIOrder.AIOF_FULL_LOAD; // remove the full load flag

						// Make sure vehicles at the station leave the station (otherwise they will keep full-loading until cargo arrives (which could be waiting infinitely long in worst case))
						local order_dest_tile = AIOrder.GetOrderDestination(veh, i);
						local order_dest_station_id = AIStation.GetStationID(order_dest_tile);
						local vehicle_list = Station.GetListOfVehiclesAtStation(order_dest_station_id);

						foreach(at_station_veh, _ in vehicle_list)
						{
							// Force vehicles at station to skip to next order
							AIOrder.SkipToOrder(at_station_veh, i + 1);
						}
					}
				}
				if(!AIOrder.SetOrderFlags(veh, i, flags))
				{
					Log.Warning("Couldn't add/remove full load flags because: " + AIError.GetLastErrorString(), Log.LVL_INFO);
				}
			}
		}
	}
}

function Connection::StopInDepots(stop_in_depots)
{
	// Change the depot orders to be stay in depot
	local vehicle_list = this.GetVehicles();

	if(vehicle_list.IsEmpty())
		return false;

	local veh_id = vehicle_list.Begin();
	for(local i_order = 0; i_order < AIOrder.GetOrderCount(veh_id); ++i_order)
	{
		if(AIOrder.IsGotoDepotOrder(veh_id, i_order))
		{
			if(stop_in_depots)
				AIOrder.SetOrderFlags(veh_id, i_order, AIOrder.AIOF_NON_STOP_INTERMEDIATE | AIOrder.AIOF_STOP_IN_DEPOT);
			else
			{
				// Always go to depot if breakdowns are "normal", otherwise only go if needed
				local service_flag = AIGameSettings.GetValue("vehicle_breakdowns") == 2? 0 : AIOrder.AIOF_SERVICE_IF_NEEDED;

				AIOrder.SetOrderFlags(veh_id, i_order, AIOrder.AIOF_NON_STOP_INTERMEDIATE | service_flag);
			}
		}
	}

	return true;
}

function Connection::SkipAllVehiclesToClosestDepot()
{
	// Get a list of all depots and their order id
	local depot_list = AIList();
	local vehicle_list = this.GetVehicles();

	if(!vehicle_list)
		return false;

	local veh_id = vehicle_list.Begin();
	for(local i_order = 0; i_order < AIOrder.GetOrderCount(veh_id); ++i_order)
	{
		if(AIOrder.IsGotoDepotOrder(veh_id, i_order))
		{
			depot_list.AddItem(AIOrder.GetOrderDestination(veh_id, i_order), i_order);
		}
	}

	if(depot_list.IsEmpty())
	{
		Log.Warning("SkipAllVehiclesToClosestDepot fails because connection " + node[0].GetName() + " - " + node[1].GetName() + " do not have any depots.", Log.LVL_INFO);
		return false;
	}

	// Skip all vehicles to the closest depot
	foreach(vehicle_id, _ in vehicle_list)
	{
		local veh_tile = AIVehicle.GetLocation(vehicle_id);

		// Find the closest depot relative to the vehicle
		local closest_depot_distance = -1;
		local closest_depot_order_id = -1;

		foreach(depot_tile, order_i in depot_list)
		{
			local dist = AIMap.DistanceManhattan(veh_tile, depot_tile);

			if (closest_depot_distance == -1 || dist < closest_depot_distance)
			{
				closest_depot_distance = dist;
				closest_depot_order_id = order_i;
			}
		}

		// Skip vehicle to closest depot
		AIOrder.SkipToOrder(vehicle_id, closest_depot_order_id);
	}

	return true;
}

function Connection::RepairRoadConnection()
{
	Log.Info("Repairing connection", Log.LVL_INFO);
	local front1 = AIRoad.GetRoadStationFrontTile(station[0]);
	local front2 = AIRoad.GetRoadStationFrontTile(station[1]);

	AICompany.SetLoanAmount(AICompany.GetMaxLoanAmount());
	local road_builder = RoadBuilder();
	if(AIController.GetSetting("slow_ai")) road_builder.EnableSlowAI();
	local repair = true;
	road_builder.Init(front1, front2, repair, 50000);
	local connect_result = road_builder.ConnectTiles() == RoadBuilder.CONNECT_SUCCEEDED;
	if(connect_result)
	{
		road_builder.Init(front2, front1, repair, 50000);
		connect_result = road_builder.ConnectTiles() == RoadBuilder.CONNECT_SUCCEEDED; // also make sure the connection works in the reverse direction
	}	

	if(!connect_result)
	{
		// retry but without higher penalty for constructing new road
		Log.Warning("Failed to repair route -> try again but without high penalty for building new road", Log.LVL_INFO);
		repair = false;
		road_builder.Init(front1, front2, repair, 100000);
		connect_result = road_builder.ConnectTiles() == RoadBuilder.CONNECT_SUCCEEDED;
		if(connect_result)
		{
			road_builder.Init(front2, front1, repair, 100000);
			connect_result = road_builder.ConnectTiles() == RoadBuilder.CONNECT_SUCCEEDED; // also make sure the connection works in the reverse direction
		}
	}

	if(!connect_result)
	{
		Log.Error("Failed to repair broken route", Log.LVL_INFO);
	}

	clueless_instance.ManageLoan();

	return connect_result;
}

function Connection::FindNewDesiredEngineType()
{
	local best_engine = Strategy.FindEngineModelToBuy(this.cargo_type, AIVehicle.VT_ROAD);

	// Change desired engine only if the best one is X % better than the old one or the old one
	// is no longer buildable.
	if(this.desired_engine == null || !AIEngine.IsBuildable(this.desired_engine) ||
			Strategy.EngineBuyScore(best_engine) > Strategy.EngineBuyScore(this.desired_engine) * 1.15)
	{
		this.desired_engine = best_engine;
	}
}

function Connection::MassUpgradeVehicles()
{
	// Require to be in state ACTIVE or SUSPENDED in order to mass-upgrade
	// vehicles
	if(this.state != Connection.STATE_ACTIVE && this.state != Connection.STATE_SUSPENDED)
		return;

	Log.Info("Check if connection " + node[0].GetName() + " - " + node[1].GetName() + " has any vehicles to mass-upgrade", Log.LVL_SUB_DECISIONS);

	// Make a list of vehicles of this connection that are not
	// of the desired vehicle type
	local vehicle_list = this.GetVehicles();
	local all_veh_count = vehicle_list.Count();
	vehicle_list.Valuate(AIVehicle.GetEngineType);
	vehicle_list.RemoveValue(this.desired_engine);
	local wrong_type_count = vehicle_list.Count();

	// No need to do anything if there are no vehicles of wrong type
	if(wrong_type_count == 0)
		return;

	// Make sure we can afford the upgrade
	local veh_margin = 2;
	if(AICompany.GetBankBalance(AICompany.COMPANY_SELF) < AIEngine.GetPrice(this.desired_engine) * (wrong_type_count + veh_margin))
	{
		// Does not have enough money to upgrade all (+ 2 extra vehicles)
		local bank_balance = AICompany.GetBankBalance(AICompany.COMPANY_SELF);
		vehicle_list.Valuate(AIVehicle.GetCurrentValue);
		local tot_value = Helper.ListValueSum(vehicle_list);
		local tot_cost = AIEngine.GetPrice(this.desired_engine) * (wrong_type_count + veh_margin);

		while(wrong_type_count > 0 && bank_balance < (tot_cost - tot_value))
		{
			// Reduce the upgrade list with the lowest valuable old vehicle ( => higher probability that the upgrade can be performed on many vehicles)
			vehicle_list.Sort(AIAbstractList.SORT_BY_VALUE, true); // lowest value first
			tot_value -= vehicle_list.GetValue(vehicle_list.Begin());
			tot_cost -= AIEngine.GetPrice(this.desired_engine);
			vehicle_list.RemoveTop(1);
			wrong_type_count--;
		}

		if(wrong_type_count <= 0)
			return;
	}


	// When upgrading vehicles, the old vehicle will be sold and a new one with zero income statistics will be created.
	// If no action is taken, this will lead to the AI thinking that the connection might be broken as the mean income will dip.
	// That could lead to spending huge amount of time on trying to repair all connections that has just been upgraded causing
	// ongoing upgrades to take even more time => large real income dips.

	// Keep long time income proportional to amount of vehicles that will not be upgraded.
	this.long_time_mean_income = (all_veh_count - wrong_type_count) * this.long_time_mean_income / all_veh_count;
	// Reduce the income even a bit more to also account for the period of time when there will be less vehicles available to produce income.
	this.long_time_mean_income = this.long_time_mean_income * 70 / 100;

	Log.Info("Mass-upgrade vehicles on connection: " + node[0].GetName() + " - " + node[1].GetName(), Log.LVL_SUB_DECISIONS);
	foreach(vehicle_id, _ in vehicle_list)
	{
		local state = AIVehicle.GetState(vehicle_id);
		if(state != AIVehicle.VS_IN_DEPOT)
		{
			// If in active mode, store "upgrade" in the vehicle name. (in suspended mode we don't want to overwrite "suspended" in vehicle names.
			// however, they will eventually reach the depot and before un-suspending a connection there is a good moment to mass-upgrade.
			if(this.state != Connection.STATE_SUSPENDED)
				ClueHelper.StoreInVehicleName(vehicle_id, "upgrade " + this.desired_engine);

			if(!IsVehicleGoingToADepot(vehicle_id)) // make sure to not cancel to-depot orders
			{
				AIVehicle.SendVehicleToDepot(vehicle_id);
			}
		}
		else
		{
			// Vehicle is in depot
			AIVehicle.SellVehicle(vehicle_id);
			this.BuyVehicles(1, this.desired_engine);
		}
	}
}

/* static */ function Connection::IsVehicleToldToUpgrade(vehicle_id)
{
	local str = ClueHelper.ReadStrFromVehicleName(vehicle_id);
	local u_len = "upgrade".len();
	if(str.len() < u_len) return false; // Reduces the number of catched errors as those cause big red messages in the log
	try
	{
		return str.slice(0, u_len) == "upgrade";
	}
	catch(e)
	{
		// Slice can raise an error if str is too short
		return false;
	}
}

/* static */ function Connection::GetVehicleUpgradeToEngine(vehicle_id)
{
	local str = ClueHelper.ReadStrFromVehicleName(vehicle_id);
	if(str.slice(0, "upgrade".len()) != "upgrade")
		return -1;

	return str.slice("upgrade ".len()).tointeger();
}

//////////////////////////////////////////////////////////////////////

function GetVehiclesWithoutOrders()
{
	local empty_orders = AIVehicleList();
	empty_orders.Valuate(AIOrder.GetOrderCount);
	empty_orders.KeepValue(0);
	return empty_orders;
}

function HasVehicleInvalidOrders(vehicleId)
{
	for(local i = 0; i < AIOrder.GetOrderCount(vehicleId); ++i)
	{
		if( (AIOrder.rawin("IsVoidOrder") && AIOrder.IsVoidOrder(vehicleId, i)) /* ||
				AIOrder.GetOrderFlags(vehicleId, i) == 0*/) // <-- for backward compatibility <-- The backward compatibility code caused problems with new OpenTTD versions.
			return true;
	}

	return false;
}

function IsVehicleGoingToADepot(vehicleId)
{
	return AIRoad.IsRoadDepotTile(Order.GetCurrentOrderDestination(vehicleId));
}

function GetVehiclesWithInvalidOrders()
{
	local invalid_orders = AIVehicleList();
	invalid_orders.Valuate(HasVehicleInvalidOrders);
	invalid_orders.KeepValue(1);
	return invalid_orders;
}

function GetVehiclesWithUpgradeStatus()
{
	local list = AIVehicleList();
	list.Valuate(Connection.IsVehicleToldToUpgrade);
	list.KeepValue(1);
	return list;
}

function GetCargoFromStation(station_id)
{
	local save_str = ClueHelper.ReadStrFromStationName(station_id);
	local space = save_str.find(" ");
	local save_version = -1;
	local node_save_str = null;
	if(space == null)
		return -1;
	save_version = save_str.slice(0, space);
	node_save_str = save_str.slice(space + 1);
	local node = Node.CreateFromSaveString(node_save_str);
	return node == null? -1 : node.cargo_id;
}

//////////////////////////////////////////////////////////////////////
//                                                                  //
//  CLASS: CluelessPlus - the AI main class                         //
//                                                                  //
//////////////////////////////////////////////////////////////////////
class CluelessPlus extends AIController {
	stop     = false;

	loaded_from_save = false;

	pair_finder = null;
	connection_list = [];

	detected_rail_crossings = null;

	state_build = false;
	state_ai_name = null;
	state_desperateness = 0;
	state_connect_performance = 0;

	conf_ai_name = null
	conf_min_balance = 0;



	// All variables should be initiated with their values below!:  (the assigned values above is only there because Squirrel demands it)
	constructor() {
		stop = false;
		loaded_from_save = false;
		pair_finder = PairFinder();
		connection_list = [];

		detected_rail_crossings = AIList();

		state_build = false;
		state_ai_name = null;
		state_desperateness = 0;
		state_connect_performance = 0;

		conf_ai_name = ["Clueless", "Cluemore", "Not so Clueless", "Average IQ", 
				"Almost smart", "Smart", "Even more smart", "Almost intelligent", 
				"Intelligent", "Even more intelligent", "Expert", "Better than expert", 
				"Geek", "Master of universe", "Logistic king", "Ultimate logistics"];
		conf_min_balance = 20000;

	}

	// WARNING: the arguments of the following functions might be wrong. Look at the implementation for the exact arguments. 
	// Squirrel don't complain if the arguments of the definitions and implementation don't match. 
	// Squirrel basically don't look at the definitions below:
	function Start();
	function Stop();
	function HandleEvents();
	function SendLostVehicleForSelling(vehicle_id);
	function CheckDepotsForStopedVehicles();
	function ConnectPair();

	function Save();
	function Load(version, data);
	function ReadConnectionsFromMap(); // Instead of storing data in the save game, the connections are made out from groups of vehicles that share orders.

	function SetCompanyName(nameArray);

	function ManageLoan();
	function RoundLoanDown(loanAmount); // Helper
	function GetMaxMoney();

	function BuildServiceInTown();
	function BuildStopInTown(town, road_veh_type, accept_cargo = -1, produce_cargo = -1);
	function BuildStopForIndustry(industry_id, cargo_id);
	function BuyNewConnectionVehicles(connection); 
	// if tile is not a road-tile it will search for closest road-tile and then start searching for a location to place it from there.
	function BuildBusStopNextToRoad(tile, min_loops, max_loops); 
	function BuildTruckStopNextToRoad(tile, min_loops, max_loops); 
	function BuildDepotNextToRoad(tile, min_loops, max_loops); 
	function BuildNextToRoad(tile, what, min_loops, max_loops);  // 'what' can be any of: "BUS_STOP", "TRUCK_STOP", "DEPOT". ('what' should be a string)
	function GrowStation(station_id, station_type);
	function GrowStationParallel(station_id, station_type);

	function PlaceHQ(nearby_tile);

	function FindClosestRoadTile(tile, max_loops);

	function FindRoadExtensionTile(road_tile, target_tile, min_loops, max_loops); // road_tile = start search here
	                                                                              // target_tile = when searching for a place to extend existing road, we want to get as close as possible to target_tile
																				  // min_loops = search at least for this amount of loops even if one possible extension place is found (return best found)
																				  // max_loops = maximum search loops before forced return
	function FindRoadExtensionTile_SortByDistanceToTarget(a, b); // Helper
}

function CluelessPlus::Start()
{
	this.Sleep(1);

	AIRoad.SetCurrentRoadType(AIRoad.ROADTYPE_ROAD);

	AILog.Info(""); // Call AILog directly in order to not include date in this message

	if(AIController.GetSetting("slow_ai") == 1)
	{
		Log.Info("I'm a slow AI, so sometimes I will take a nap and rest a bit so that I don't get exhausted.", Log.LVL_INFO);
		Log.Info("", Log.LVL_INFO);
		AIController.Sleep(50);
	}

	// Company Name
	if(this.loaded_from_save)
	{
		this.state_ai_name = AICompany.GetName(AICompany.COMPANY_SELF);
	}
	else
	{
		this.state_ai_name = this.SetCompanyName(this.conf_ai_name);
	}

	// Rebuild the connections structure if loading a save game
	if(this.loaded_from_save)
	{
		Log.Info("Map loaded => Read connections from the map ...", Log.LVL_INFO);
		ReadConnectionsFromMap();
		Log.Info("All connections have been read from the map", Log.LVL_INFO);
	}

	if(AIGameSettings.IsDisabledVehicleType(AIVehicle.VT_ROAD) || AIGameSettings.GetValue("max_roadveh") == 0)
	{
		Log.Error("Road transport mode is disabled for AIs. This AI is road-only.", Log.LVL_INFO);
		Log.Info("Enable road transport mode in advanced settings if you want that this AI should build something", Log.LVL_INFO);
		Log.Info("", Log.LVL_INFO);
	}
	
	state_build = false;
	local last_manage_time = AIDate.GetCurrentDate();
	local not_build_info_printed = false;

	local i = 0;
	while(!this.stop)
	{
		i++;
		this.Sleep(1);

		HandleEvents();

		// Sometimes...
		if(i%10 == 1)
		{
			// ... manage our loan
			ManageLoan();

/*
			// Get a list of available buses, so we don't construct if there are no buses
			local engine_list = AIEngineList(AIVehicle.VT_ROAD);
			engine_list.Valuate(AIEngine.GetCargoType)
			local cargo_type = Helper.GetPAXCargo();
			engine_list.KeepValue(cargo_type); 
			engine_list.Valuate(AIEngine.IsArticulated)
			engine_list.KeepValue(0); 
*/

			// Also only manage our vehicles if we have any.
			local bus_list = AIVehicleList();

			// ... check if we can afford to build some stuff (or we don't have anything -> need to build to either suceed or go bankrupt and restart)
			//   AND road vehicles are not disabled
			//   AND at least 5 more buses/trucks can be built before reaching the limit (a 1 bus/truck connection will not become good)
			if((this.GetMaxMoney() > 95000 || AIStationList(AIStation.STATION_ANY).IsEmpty() ) &&
					!AIGameSettings.IsDisabledVehicleType(AIVehicle.VT_ROAD) &&
					AIGameSettings.GetValue("max_roadveh") > bus_list.Count() + 5)
			{
				state_build = true;
				not_build_info_printed = false;
			}
			else
			{
				if(!not_build_info_printed)
				{
					not_build_info_printed = true;
					Log.Info("Not enough money to construct (will check every now and then, but only this message is printed to not spam the log)", Log.LVL_INFO);
				}
			}

			if(!bus_list.IsEmpty() && !AIGameSettings.IsDisabledVehicleType(AIVehicle.VT_ROAD))
			{
				this.CheckDepotsForStopedVehicles();

				// check if we should manage the connections
				local now = AIDate.GetCurrentDate();
				if(now - last_manage_time > AIDate.GetDate(0, 1, 0))
				{
					Log.Info("Time to manage connections", Log.LVL_DEBUG);
					last_manage_time = now;
					local connection = null;
					// Remember the indexes in connection_list for connections to remove
					local remove_connection_idx_list = []; 
					local i = -1;
					foreach(connection in connection_list)
					{
						++i;

						// Detect failed or closed down connections
						if(connection.state == Connection.STATE_FAILED || connection.state == connection.STATE_CLOSED_DOWN)
						{
							continue;
						}

						// But also connections which has invalid array lengths
						if(connection.station.len() != 2 || connection.depot.len() != 2 || connection.town.len() != 2)
						{
							Log.Warning("Connection::ManageVehicles: Wrong number of bus stations or depots. " + 
									connection.station.len() + " stations and " + connection.depot.len() + " depots", Log.LVL_INFO);
							connection.state = Connection.STATE_FAILED;
							continue;
						}

						if(connection.state == Connection.STATE_CLOSED_DOWN)
						{
							// Mark fully closed down connections for removal
							remove_connection_idx_list.append(i);
						}
						else
						{
							connection.ManageState();
							connection.ManageStations();
							connection.ManageVehicles();

							this.CheckDepotsForStopedVehicles(); // Sell / upgrade vehicles even while managing connections - good when there are a huge amount of connections
						}
					}

					// Remove all connections that was marked for removal
					foreach(remove_idx in remove_connection_idx_list)
					{
						connection_list.remove(remove_idx);
					}

					// Check for rail crossings that couldn't be fixed just after a crash event
					this.detected_rail_crossings.Valuate(Helper.ItemValuator);
					foreach(crash_tile, _ in this.detected_rail_crossings)
					{
						Log.Info("Trying to fix a railway crossing that had an accident before", Log.LVL_INFO);
						Helper.SetSign(crash_tile, "crash_tile");
						local neighbours = Tile.GetNeighbours4MainDir(crash_tile);
						neighbours.Valuate(AIRoad.AreRoadTilesConnected, crash_tile);
						neighbours.KeepValue(1);
						
						local road_tile_next_to_crossing = neighbours.Begin();

						if(neighbours.IsEmpty() ||
								!AIMap.IsValidTile(road_tile_next_to_crossing) ||
								!AITile.HasTransportType(crash_tile, AITile.TRANSPORT_ROAD) ||
								!AITile.HasTransportType(road_tile_next_to_crossing, AITile.TRANSPORT_ROAD))
						{
							this.detected_rail_crossings.RemoveValue(crash_tile);
						}

						local bridge_result = RoadBuilder.ConvertRailCrossingToBridge(crash_tile, road_tile_next_to_crossing);
						if(bridge_result.succeeded == true || bridge_result.permanently == true)
						{
							// Succeded to build rail crossing or failed permanently -> don't try again
							this.detected_rail_crossings.RemoveValue(crash_tile);
						}
					}
					
					
				}
			}
		}	

		if(state_build)
		{
			// Simulate the time it takes to look for a connection
			if(AIController.GetSetting("slow_ai"))
				AIController.Sleep(1000); // a bit more than a month

			local ret = this.ConnectPair();
			state_build = false;

			if(ret && !AIMap.IsValidTile(AICompany.GetCompanyHQ(AICompany.COMPANY_SELF)))
			{
				Log.Info("Place HQ", Log.LVL_INFO);
				// Place the HQ close to the first station

				// connection[0] would be failed if first connection fails but the second succeds
				// so we must find the first one that did not fail
				foreach(connection in connection_list)
				{
					if(connection.state == Connection.STATE_ACTIVE)
					{
						for(local i = 0; i != connection.node.len(); i++)
						{
							// Only place the HQ in towns
							if(connection.node[i].IsTown())
							{
								PlaceHQ(connection.station[i]);
								break;
							}
						}
					}

					// Placing the HQ once is enough :-)
					if(AIMap.IsValidTile(AICompany.GetCompanyHQ(AICompany.COMPANY_SELF)))
						break;
				}
			}
			else
			{
				Log.Warning("Could not find two towns/industries to connect", Log.LVL_INFO);
			}
		}

		// Pay back unused money
		ManageLoan();
	}
}
function CluelessPlus::Stop()
{
	Log.Info("CluelessPlus::Stop()", Log.LVL_INFO);
	this.stop = true;
}

function CluelessPlus::Save()
{
	// Store an empty table to please the NoAI API.

	// CluelessPlus loading reads everything from the map.
	local table = {};
	return table;
}

function CluelessPlus::Load(version, data)
{
	// CluelessPlus does not support save/load, so kill ourself if 
	// a user tries to load a savegame with CluelessPlus as AI.
	this.loaded_from_save = true;
	Log.Info("Loading..", Log.LVL_INFO);
	Log.Info("Previously saved with AI version " + version, Log.LVL_INFO);
}

function CluelessPlus::HandleEvents()
{
	if(AIEventController.IsEventWaiting())
	{
		local ev = AIEventController.GetNextEvent();

		if(ev == null)
			return;

		local ev_type = ev.GetEventType();

		if(ev_type == AIEvent.AI_ET_VEHICLE_LOST)
		{
			local lost_event = AIEventVehicleLost.Convert(ev);
			local lost_veh = lost_event.GetVehicleID();

			Log.Info("Vehicle lost event detected - lost vehicle: " + AIVehicle.GetName(lost_veh), Log.LVL_INFO);

			// This is not a pointer to the regular connection object. Instead a new object
			// is created with enough data to use RepairRoadConnection.
			local connection = ReadConnectionFromVehicle(lost_veh);
			
			if(connection != null && connection.station.len() >= 2 && connection.state == Connection.STATE_ACTIVE)
			{
				Log.Info("Try to connect the stations again", Log.LVL_SUB_DECISIONS);

				if(!connection.RepairRoadConnection())
					this.SendLostVehicleForSelling(lost_veh);

				// TODO:
				// If a vehicle is stuck somewhere but the connection succeeds to repair every time without letting the vehicles out,
				// they will never be sent for selling nor will any depot be constructed nearby in order to sell the vehicles and
				// reduce the cost + vehicle usage. (except for if the connection decide to sell the vehicles in the vehicle management
				// procedure)
				//
				// If many vehicles are lost, they can possible also cause a management hell.
			}
			else
			{
				this.SendLostVehicleForSelling(lost_veh);
			}
			
		}
		else if(ev_type == AIEvent.AI_ET_VEHICLE_CRASHED)
		{
			local crash_event = AIEventVehicleCrashed.Convert(ev);
			local crash_reason = crash_event.GetCrashReason();
			local vehicle_id = crash_event.GetVehicleID();
			local crash_tile = crash_event.GetCrashSite();
			if(crash_reason == AIEventVehicleCrashed.CRASH_RV_LEVEL_CROSSING)
			{
				Log.Info("Vehicle " + AIVehicle.GetName(vehicle_id) + " crashed at level crossing", Log.LVL_INFO);
				
				local neighbours = Tile.GetNeighbours4MainDir(crash_tile);
				neighbours.Valuate(AIRoad.AreRoadTilesConnected, crash_tile);
				neighbours.KeepValue(1);
				
				local road_tile_next_to_crossing = neighbours.Begin();

				if(!neighbours.IsEmpty() &&
						AIMap.IsValidTile(road_tile_next_to_crossing) &&
						AITile.HasTransportType(crash_tile, AITile.TRANSPORT_ROAD) &&
						AITile.HasTransportType(road_tile_next_to_crossing, AITile.TRANSPORT_ROAD))
				{
					local bridge_result = RoadBuilder.ConvertRailCrossingToBridge(crash_tile, road_tile_next_to_crossing);

					if(bridge_result.succeeded == false && bridge_result.permanently == false)
					{
						// couldn't fix it right now, so put in in a wait list as there were no permanent problems (only vehicles in the way or lack of funds)
						this.detected_rail_crossings.AddItem(crash_tile, road_tile_next_to_crossing);
					}
				}
			}
		}
		else if(ev_type == AIEvent.AI_ET_INDUSTRY_CLOSE)
		{
			local close_event = AIEventIndustryClose.Convert(ev);
			local close_industry = close_event.GetIndustryID();

			local close_tile = AIIndustry.GetLocation(close_industry);
			local close_tile_is_valid = AIMap.IsValidTile(close_tile);

			foreach(connection in connection_list)
			{
				// Close connections that use this industry
				local match = false;
				foreach(node in connection.node)
				{
					// Ignore town nodes
					if(node.IsTown())
						continue;

					if(close_tile_is_valid)
					{
						if(node.industry_id == close_industry && node.node_location != close_industry)
						{
							// The node has the close_industry id, but not the right location => we know the close_industry id has been 
							// reused by another industry located elsewhere => we know the node is dead.
							match = true;
						}
						else
						{
							// The close industry location is valid, but it could either be that the industry at this node is still existing
							// or that it has been closed and reused for a new industry elsewhere.
							// -> we don't know if close_tile is for the new or old industry

							if(node.industry_id == close_industry)
							{
								if(AIDate.GetCurrentDate() - connection.date_built > 365)
								{
									// The connection is older than 365 days, so assume this can not be a new connection that was built after
									// the event was triggered, the industry closed and a new one opened used the same id.
									match = true;
								}
								else
								{
									// The connection is either a new connection that has reused the industry id or the industry will soon be closed

									// -> do nothing, rely on the detection of broken nodes
								}
							}
						}
					}
					else
					{
						// The close_industry is not a valid industry => if there is a match for this industry id, the node is dead
						if(node.industry_id == close_industry)
							match = true;
					}
				}
				if(match)
				{
					connection.CloseConnection();
				}
			}
		} // event industry close
	}
}

function CluelessPlus::SendLostVehicleForSelling(vehicle_id)
{
	if(!AIOrder.IsGotoDepotOrder(vehicle_id, AIOrder.ORDER_CURRENT))
	{
		// Unshare & clear orders
		AIOrder.UnshareOrders(vehicle_id);
		while(AIOrder.GetOrderCount(vehicle_id) > 0)
		{
			AIOrder.RemoveOrder(vehicle_id, 0);
		}

		ClueHelper.StoreInVehicleName(vehicle_id, "sell");

		if(!AIVehicle.IsStoppedInDepot(vehicle_id))
			AIVehicle.SendVehicleToDepot(vehicle_id);
	}
}

function CluelessPlus::CheckDepotsForStopedVehicles()
{
	local bus_list = AIVehicleList();
	if(!bus_list.IsEmpty() && !AIGameSettings.IsDisabledVehicleType(AIVehicle.VT_ROAD))
	{
		Log.Info("Look for buses to sell / send to depot for selling", Log.LVL_SUB_DECISIONS);

		// check if there are any vehicles to sell
		local to_sell_in_depot = AIVehicleList();
		to_sell_in_depot.Valuate(AIVehicle.IsStoppedInDepot);
		to_sell_in_depot.KeepValue(1);
		Log.Info("num vehicles stopped in depot: " + to_sell_in_depot.Count(), Log.LVL_SUB_DECISIONS);
		foreach(i, _ in to_sell_in_depot)
		{
			local veh_state = ClueHelper.ReadStrFromVehicleName(i);

			// Don't sell suspended / active vehicles
			if(veh_state == "suspended" || veh_state == "active")
				continue;
			
			// Don't sell vehicles that has been told to upgrade
			if(Connection.IsVehicleToldToUpgrade(i))
			{
				Log.Info("Vehicle " + i + " " + ": " + AIVehicle.GetName(i) + " has been told to upgrade", Log.LVL_DEBUG);
				local depot = AIVehicle.GetLocation(i);
				local engine = Connection.GetVehicleUpgradeToEngine(i);
				if(!AIEngine.IsBuildable(engine))
				{
					Log.Warning("Vehicle got upgrade order to a engine type (" + engine + ") that is not buildable", Log.LVL_INFO);
				}
				else
				{
					// The engine is buildable 
					local stn_list = AIStationList_Vehicle(i);
					if(stn_list.IsEmpty())
						continue;
					local cargo = GetCargoFromStation(stn_list.Begin());
					if(cargo == -1)
						continue;
					Log.Info("Upgrade vehicle " + i + ": " + AIVehicle.GetName(i) + " (state: " + veh_state + ")", Log.LVL_SUB_DECISIONS);

					if( AIVehicleList().Count() < AIGameSettings.GetValue("max_roadveh") )
					{
						// There is enough vehicle slots to build new vehicle first, and then sell.
						local veh = AIVehicle.BuildVehicle(depot, engine);
						if(AIVehicle.IsValidVehicle(veh))
						{
							if(AIVehicle.RefitVehicle(veh, cargo))
							{
								// Upgrade succeeded
								AIOrder.ShareOrders(veh, i);
								ClueHelper.StoreInVehicleName(veh, "active");
								AIVehicle.StartStopVehicle(veh);
								AIVehicle.SellVehicle(i);
								continue;
							}

							// Refit failed -> sell new vehicle
							Log.Warning("Refit of vehicle " + AIVehicle.GetName(veh) + " to cargo " + AICargo.GetCargoLabel(cargo) + " failed", Log.LVL_INFO);
							AIVehicle.SellVehicle(veh);
						}
					}
					else
					{
						// Already using max num vehicles -> must sell first. A bit more risky but with max num vehicles it should probably not bankrupt the company on a failure.

						// In order to make order sharing work, we need to find a vehicle that vehicle i shares orders with.
						local shared_orders_group = AIVehicleList_SharedOrders(i);
						shared_orders_group.Valuate(Helper.ItemValuator);
						shared_orders_group.RemoveValue(i);

						if(!shared_orders_group.IsEmpty())
						{
							// In order to upgrade when vehicle count = max, the vehicle to upgrade must share orders with at least one vehicle. (as order copying via memory has not been implemented and we don't have a reference to the connection here)
							Log.Warning("Upgrading vehicle while at max vehicle count => this is slightly more risky than when vehicle count is < max.", Log.LVL_INFO);

							AIVehicle.SellVehicle(i);
							local veh = AIVehicle.BuildVehicle(depot, engine);
							if(AIVehicle.IsValidVehicle(veh))
							{
								if(AIVehicle.RefitVehicle(veh, cargo))
								{
									// Upgrade succeeded
									AIOrder.ShareOrders(veh, shared_orders_group.Begin());
									ClueHelper.StoreInVehicleName(veh, "active");
									AIVehicle.StartStopVehicle(veh);
									continue;
								}

								// Refit failed -> sell new vehicle
								Log.Warning("Refit of vehicle " + AIVehicle.GetName(veh) + " to cargo " + AICargo.GetCargoLabel(cargo) + " failed", Log.LVL_INFO);
								AIVehicle.SellVehicle(veh);
							}

							continue; // Already sold vehicle i, so there is no return to previous state.
						}
					}

				}


				Log.Warning("Buying of new vehicle failed -> return vehicle to active state", Log.LVL_INFO);
				Log.Info("depot: " + Tile.GetTileString(depot), Log.LVL_INFO);
				Log.Info("engine: " + engine + " = " + AIEngine.GetName(engine), Log.LVL_INFO);
				ClueHelper.StoreInVehicleName(i, "active");
				AIVehicle.StartStopVehicle(i);

				continue;
			}


			Log.Info("Sell vehicle " + i + ": " + AIVehicle.GetName(i) + " (state: " + veh_state + ")", Log.LVL_SUB_DECISIONS);
			if(!AIVehicle.SellVehicle(i)) // sell
				Log.Info("Failed to sell vehicle " + AIVehicle.GetName(i) + " in depot - Error string: " + AIError.GetLastErrorString(), Log.LVL_INFO);
		}

		// check if there are any vehicles without orders that don't tries to find a depot
		// the new selling code adds a depot order, but there may exist vehicles without orders roaming around for other reasons
		local to_send_to_depot = GetVehiclesWithoutOrders();
		local invalid_orders_vehicles = GetVehiclesWithInvalidOrders();
		local upgrade_status_vehicles = GetVehiclesWithUpgradeStatus();
		Log.Info("num vehicles without orders: " + to_send_to_depot.Count(), Log.LVL_DEBUG);
		to_send_to_depot.AddList(invalid_orders_vehicles);
		to_send_to_depot.AddList(upgrade_status_vehicles);
		Log.Info("num vehicles with invalid orders: " + invalid_orders_vehicles.Count(), Log.LVL_DEBUG);
		Log.Info("num vehicles with upgrade status: " + upgrade_status_vehicles.Count(), Log.LVL_DEBUG);

		to_send_to_depot.Valuate(AIOrder.IsGotoDepotOrder, AIOrder.ORDER_CURRENT);
		to_send_to_depot.KeepValue(0);
		to_send_to_depot.Valuate(AIVehicle.IsStoppedInDepot);
		to_send_to_depot.KeepValue(0);

		Log.Info("  num vehicles that does not go to depot: " + to_send_to_depot.Count(), Log.LVL_DEBUG);
		foreach(i, _ in to_send_to_depot)
		{
			Log.Info("Send broken vehicle '" + AIVehicle.GetName(i) + "' to depot", Log.LVL_SUB_DECISIONS);
			AIVehicle.SendVehicleToDepot(i); // send to depot
		}
	}
}

function CluelessPlus::ConnectPair()
{
	// scan for two pairs to connect
	local a = Helper.Clamp(state_connect_performance, -20, 100); // bonus distance based on performance history
	local max_distance = 100 + a + 20 * state_desperateness;
	local pair = this.pair_finder.FindTwoNodesToConnect(max_distance, state_desperateness, connection_list);

	if(!pair)
	{
		state_desperateness++; // be more desperate (accept worse solutions) the more times we fail
		Log.Warning("No pair found -> fail", Log.LVL_INFO);
		return false;
	}

	if( (!pair[0].IsTown() && !pair[0].IsIndustry()) ||
			(!pair[1].IsTown() && !pair[1].IsIndustry()))
	{
		Log.Error("Pair has non-town, non-industry node!", Log.LVL_INFO);
		return false; 
	}

	// A pair was found

	// Store the cargo type
	local connection = Connection(this);
	connection.cargo_type = pair[0].cargo_id;
	connection.state = Connection.STATE_BUILDING;


	local failed = false;
	Log.Info("Connect " + pair[0].GetName() + " with " + pair[1].GetName(), Log.LVL_INFO);

	// We don't want to worry about budgeting exactly how much money that is needed, get as much money as possible.
	// We can always pay back later. 
	AICompany.SetLoanAmount(AICompany.GetMaxLoanAmount());


	// Build bus/truck-stops + depots
	local road_stop = [];
	local depot = [];

	foreach(node in pair)
	{
		local station_tile = null;
		local depot_tile = null;
		if (node.IsTown())
		{
			local road_veh_type = AIRoad.GetRoadVehicleTypeForCargo(node.cargo_id);

			// Make sure the station accept/produce the wanted cargo
			local accept_cargo = -1;
			local produce_cargo = -1;
			if(node.IsCargoAccepted())
				accept_cargo = node.cargo_id;
			if(node.IsCargoProduced())
				produce_cargo = node.cargo_id;

			station_tile = BuildStopInTown(node.town_id, road_veh_type, accept_cargo, produce_cargo);

			if (station_tile != null)
				depot_tile = BuildDepotNextToRoad(AIRoad.GetRoadStationFrontTile(station_tile), 0, 100);
			else
				Log.Warning("failed to build bus/truck stop in town " + AITown.GetName(node.town_id), Log.LVL_INFO);
		}
		else
		{
			station_tile = BuildStopForIndustry(node.industry_id, node.cargo_id);
			if (!AIStation.IsValidStation(AIStation.GetStationID(station_tile))) // for compatibility with the old code, turn -1 into null
				station_tile = null;
			
			if (station_tile != null)
				depot_tile = BuildDepotNextToRoad(AIRoad.GetRoadStationFrontTile(station_tile), 0, 100); // TODO, for industries there is only a road stump so chances are high that this fails
		}

		// Append null if the station tile is invalid
		road_stop.append(station_tile);
		depot.append(depot_tile);
	}


	// Check that we built all buildings
	if(road_stop[0] == null || road_stop[1] == null || depot[0] == null || depot[1] == null)
	{
		Log.Info("failed = true", Log.LVL_INFO);
		failed = true;
	}
	else
	{
		Log.Info("assign name to " + AIStation.GetName(AIStation.GetStationID(road_stop[0])), Log.LVL_DEBUG);
		ClueHelper.StoreInStationName(AIStation.GetStationID(road_stop[0]), STATION_SAVE_VERSION + " " + pair[0].SaveToString());

		Log.Info("assign name to " + AIStation.GetName(AIStation.GetStationID(road_stop[1])), Log.LVL_DEBUG);
		ClueHelper.StoreInStationName(AIStation.GetStationID(road_stop[1]), STATION_SAVE_VERSION + " " + pair[1].SaveToString());
	}

	// save town, industry, station and depot in connection data-structure.
	local i = 0;
	connection.station = [];
	connection.industry = [];
	connection.town = [];
	connection.depot = [];
	connection.station_statistics = [];
	connection.node = [];
	foreach(node in pair)
	{
		connection.town.append( node.IsTown()? node.town_id : -1 );
		connection.industry.append( node.IsIndustry()? node.industry_id : -1 );
		connection.station.append(road_stop[i]);
		connection.depot.append(depot[i]);
		connection.node.append(node);

		if(!failed)
		{
			connection.station_statistics.append(StationStatistics(AIStation.GetStationID(connection.station[i]), connection.cargo_type));
		}

		i++;
	}

	local connected = false;
	local road_builder = RoadBuilder();
	if(AIController.GetSetting("slow_ai")) road_builder.EnableSlowAI();
	Log.Info("bus/truck-stops built", Log.LVL_INFO);
	if(!failed)
	{
		connected = true; // true until first failure

		for(local i = 0; i < 2; i++)
		{
			local station_front_tile = AIRoad.GetRoadStationFrontTile(connection.station[i]);
			local depot_front_tile = AIRoad.GetRoadDepotFrontTile(connection.depot[i]);

			//Helper.SetSign(station_front_tile, "stn front");
			//Helper.SetSign(depot_front_tile, "depot front");

			if(station_front_tile != depot_front_tile)
			{
				local repair = false;
				local max_loops = 5000;
				if(connected)
				{
					road_builder.Init(depot_front_tile, station_front_tile, repair, max_loops); // -> start construct it from the station
					connected = road_builder.ConnectTiles() == RoadBuilder.CONNECT_SUCCEEDED;
				}
			}

			if(!connected)
				break;
		}

		// Don't waste money on a road if connecting stops with depots failed
		if(connected)
		{
			local from = AIRoad.GetRoadStationFrontTile(road_stop[0]);
			local to = AIRoad.GetRoadStationFrontTile(road_stop[1]);
			local repair = false;

			// First try 100 loops from the source, if path finding do not fail 
			// nor succeed - just times out, try from the other end. This way 
			// if it is impossible to reach one of the ends, that is quickly
			// detected and we don't risk to spend *a lot* of time trying to find
			// an impossible path
			road_builder.Init(from, to, repair, 500);
			local con_ret = road_builder.ConnectTiles();
			if(con_ret == RoadBuilder.CONNECT_FAILED_TIME_OUT) // no error was found path finding a litle bit from one end
			{
				road_builder.Init(to, from, repair, 100000);
				con_ret = road_builder.ConnectTiles();
			}

			connected = con_ret == RoadBuilder.CONNECT_SUCCEEDED;
		}
	}


	// Only buy buses if we actually did connect the two cities.
	if(connected && !failed)
	{	
		Log.Info("connected by road", Log.LVL_INFO);
		// BuyNewConnectionVehicles save the IDs of the bough buses in the connection data-structure
		BuyNewConnectionVehicles(connection); 
		connection.FullLoadAtStations(true); // TODO
		Log.Info("bough buses", Log.LVL_INFO);

		connection.state = Connection.STATE_ACTIVE;	// construction did not fail -> active connection
	}
	else
	{
		Log.Warning("failed to connect by road", Log.LVL_INFO);

		for(local i = 0; i < 2; i++)
		{
			local front_tiles = AIList();

			if(connection.depot[i])
			{
				local front = AIRoad.GetRoadDepotFrontTile(connection.depot[i]);
				AITile.DemolishTile(connection.depot[i]);
				AIRoad.RemoveRoad(front, connection.depot[i]);

				front_tiles.AddItem(front, 0);

			}

			if(connection.station[i])
			{
				local station_id = AIStation.GetStationID(connection.station[i]);
				front_tiles.AddList(Station.GetRoadFrontTiles(station_id));
				Station.DemolishStation(station_id);
			}

			// Go through all front tiles and remove the road up to the end/intersection
			foreach(front_tile, _ in front_tiles)
			{
				RoadBuilder.RemoveRoadUpToRoadCrossing(front_tile);
			}
		}

		connection.state = Connection.STATE_FAILED;			// store that this connection faild so we don't waste our money on buying buses for it.
		state_desperateness++;
	}

	// Store the connection so we don't build it again.
	connection.date_built = AIDate.GetCurrentDate();
	connection_list.append(connection); 

	// Calculate build performance
	if(!failed && connected)
	{
		local pf_loops_used = road_builder.GetPFLoopsUsed();
		local build_loops_used = road_builder.GetBuildLoopsUsed();
		local from = AIRoad.GetRoadStationFrontTile(road_stop[0]);
		local to = AIRoad.GetRoadStationFrontTile(road_stop[1]);
		local distance = AIMap.DistanceManhattan(from, to);

		Log.Info("pf loops used:    " + pf_loops_used, Log.LVL_INFO);
		Log.Info("build loops used: " + build_loops_used, Log.LVL_INFO);
		Log.Info("over distance:    " + distance, Log.LVL_INFO);

		local pf_performance = pf_loops_used / distance;
		local build_performance = build_loops_used / distance;
		local performance = distance * 7000 / (pf_loops_used + build_loops_used) - 62; // The constants are magic numbers that has been found by collecting data from several connections and tweaking the formula to give good results

		// Allow the long term performance to be in the interval -30 to 110 (when used it is clamped to -20 to 100)
		state_connect_performance = Helper.Clamp((state_connect_performance * 2 + performance) / 3, -30, 110);
		Log.Info("Connect performance of this connection: " + performance, Log.LVL_INFO);
		Log.Info("Long term performance rating:           " + state_connect_performance, Log.LVL_INFO);
	}

	// If we succeed to build the connection, revert to zero desperateness
	if(!failed && connected)
		state_desperateness = 0;

	return !failed && connected;
}

function CluelessPlus::GrowStation(station_id, station_type)
{
	Log.Info("GrowStation: Non-parallel grow function called", Log.LVL_DEBUG);

	if(!AIStation.IsValidStation(station_id))
	{
		Log.Error("GrowStation: Can't grow invalid station", Log.LVL_INFO);
		return RETURN_FAIL;
	}

	local existing_stop_tiles = AITileList_StationType(station_id, station_type);
	local grow_max_distance = Helper.Clamp(7, 0, AIGameSettings.GetValue("station_spread") - 1);

	Helper.SetSign(Direction.GetAdjacentTileInDirection(AIBaseStation.GetLocation(station_id), Direction.DIR_E), "<- grow");

	// AIRoad.BuildStation wants another type of enum constant to decide if bus/truck should be built
	local road_veh_type = 0;
	if(station_type == AIStation.STATION_BUS_STOP)
		road_veh_type = AIRoad.ROADVEHTYPE_BUS;
	else if(station_type == AIStation.STATION_TRUCK_STOP)
		road_veh_type = AIRoad.ROADVEHTYPE_TRUCK;
	else
		KABOOOOOOOM_UNSUPPORTED_STATION_TYPE = 0;

	local potential_tiles = AITileList();

	foreach(stop_tile, _ in existing_stop_tiles)
	{
		potential_tiles.AddList(Tile.MakeTileRectAroundTile(stop_tile, grow_max_distance));
	}

	potential_tiles.Valuate(AIRoad.IsRoadStationTile);
	potential_tiles.KeepValue(0);

	potential_tiles.Valuate(AIRoad.IsRoadDepotTile);
	potential_tiles.KeepValue(0);

	potential_tiles.Valuate(AIRoad.IsRoadStationTile);
	potential_tiles.KeepValue(0);

	//potential_tiles.Valuate(AIRoad.IsRoadTile);
	//potential_tiles.KeepValue(0);

	potential_tiles.Valuate(AIRoad.GetNeighbourRoadCount);
	potential_tiles.KeepAboveValue(0);
	//potential_tiles.RemoveValue(4);

	potential_tiles.Valuate(AIMap.DistanceManhattan, AIRoad.GetRoadStationFrontTile(existing_stop_tiles.Begin()) );
	potential_tiles.Sort(AIAbstractList.SORT_BY_VALUE, true); // lowest value first

	foreach(try_tile, _ in potential_tiles)
	{
		local neighbours = Tile.GetNeighbours4MainDir(try_tile);

		neighbours.Valuate(AIRoad.IsRoadTile);
		neighbours.KeepValue(1);

		local road_builder = RoadBuilder();
		if(AIController.GetSetting("slow_ai")) road_builder.EnableSlowAI();

		foreach(road_tile, _ in neighbours)
		{
			if( (AIRoad.AreRoadTilesConnected(try_tile, road_tile) || ClueHelper.CanConnectToRoad(road_tile, try_tile)) &&
					AITile.GetMaxHeight(try_tile) == AITile.GetMaxHeight(road_tile) )
			{
				if(AIRoad.BuildRoadStation(try_tile, road_tile, road_veh_type, station_id))
				{
					// Make sure the new station part is connected with one of the existing parts (which is in turn should be
					// connected with all other existing parts)
					local repair = false;
					road_builder.Init(try_tile, AIRoad.GetRoadStationFrontTile(existing_stop_tiles.Begin()), repair, 10000);
					if(road_builder.ConnectTiles() != RoadBuilder.CONNECT_SUCCEEDED)
					{
						AIRoad.RemoveRoadStation(try_tile);
						continue;
					}

					local i = 0;
					while(!AIRoad.AreRoadTilesConnected(try_tile, road_tile) && !AIRoad.BuildRoad(try_tile, road_tile))
					{
						// Try a few times to build the road if a vehicle is in the way
						if(i++ == 10) return RETURN_TIME_OUT;

						local last_error = AIError.GetLastError();
						if(last_error != AIError.ERR_VEHICLE_IN_THE_WAY) return false;

						AIController.Sleep(5);
					}

					return RETURN_SUCCESS;
				}
			}
		}
	}
	
	return RETURN_FAIL;
}

function CluelessPlus::GrowStationParallel(station_id, station_type)
{
	if(!AIStation.IsValidStation(station_id))
	{
		Log.Error("GrowStationParallel: Can't grow invalid station", Log.LVL_INFO);
		return RETURN_FAIL;
	}

	Helper.ClearAllSigns();

	local road_veh_type = 0;
	if(station_type == AIStation.STATION_BUS_STOP)
		road_veh_type = AIRoad.ROADVEHTYPE_BUS;
	else if(station_type == AIStation.STATION_TRUCK_STOP)
		road_veh_type = AIRoad.ROADVEHTYPE_TRUCK;
	else
		KABOOOOOOOM_UNSUPPORTED_STATION_TYPE = 0;

	local existing_stop_tiles = AITileList_StationType(station_id, station_type);

	local tot_wait_days = 0;
	local MAX_TOT_WAIT_DAYS = 30;
	
	foreach(stop_tile, _ in existing_stop_tiles)
	{
		local is_drive_through = AIRoad.IsDriveThroughRoadStationTile(stop_tile);
		local front_tile = AIRoad.GetRoadStationFrontTile(stop_tile);

		// Get the direction that the entry points at from the road stop
		local entry_dir = Direction.GetDirectionToAdjacentTile(stop_tile, front_tile);

		// Try to walk in sideways in both directions
		local walk_dirs = [Direction.TurnDirClockwise45Deg(entry_dir, 2), Direction.TurnDirClockwise45Deg(entry_dir, 6)];
		foreach(walk_dir in walk_dirs)
		{
			Log.Info( AIError.GetLastErrorString() );

			local parallel_stop_tile = Direction.GetAdjacentTileInDirection(stop_tile, walk_dir);
			local parallel_front_tile = Direction.GetAdjacentTileInDirection(front_tile, walk_dir);

			local opposite_walk_dir = Direction.TurnDirClockwise45Deg(walk_dir, 4);
			local dir_from_front_to_station = Direction.TurnDirClockwise45Deg(entry_dir, 4);

			local parallel_back_tile = Direction.GetAdjacentTileInDirection(parallel_stop_tile, dir_from_front_to_station);

			// cache if we own the parallel front tile or not as it is checked at at least 3 places.
			local own_parallel_front_tile = AICompany.IsMine(AITile.GetOwner(parallel_front_tile));

			Helper.SetSign(parallel_stop_tile, "par stop");

			// Check that we don't have built anything on the parallel stop tile
			if(!AICompany.IsMine(AITile.GetOwner(parallel_stop_tile)) &&

					// Check that the parallel front tile doesn't contain anything that we own. (with the exception that road is allowed)
					!(own_parallel_front_tile && !AIRoad.IsRoadTile(parallel_front_tile)) &&

					// Does slopes allow construction
					Tile.IsBuildOnSlope_FlatForTerminusInDirection(front_tile, walk_dir) && // from front tile to parallel front tile
					Tile.IsBuildOnSlope_FlatForTerminusInDirection(parallel_front_tile, opposite_walk_dir) && // from parallel front tile to front tile
					Tile.IsBuildOnSlope_FlatForTerminusInDirection(parallel_front_tile, dir_from_front_to_station) && // from parallel front tile to parallel station tile
					Tile.IsBuildOnSlope_FlatForTerminusInDirection(parallel_stop_tile, entry_dir) && // from parallel station tile to parallel front tile
					// Is the max heigh equal to allow construction
					AITile.GetMaxHeight(front_tile) == AITile.GetMaxHeight(parallel_front_tile) && 
					AITile.GetMaxHeight(front_tile) == AITile.GetMaxHeight(parallel_stop_tile)
					)
				
			{
				Log.Info("Landscape allow grow in parallel", Log.LVL_DEBUG);

				// Get the number of connections from the parallel stop tile to its adjacent tiles
				local num_stop_tile_connections = 0;
				if(AIRoad.AreRoadTilesConnected(parallel_stop_tile, parallel_back_tile))  num_stop_tile_connections++;
				if(AIRoad.AreRoadTilesConnected(parallel_stop_tile, parallel_front_tile)) num_stop_tile_connections++;
				if(AIRoad.AreRoadTilesConnected(parallel_stop_tile, Direction.GetAdjacentTileInDirection(parallel_stop_tile, walk_dir))) num_stop_tile_connections++;

				Log.Info("Num stop tile connections: " + num_stop_tile_connections, Log.LVL_DEBUG);

				// If the parallel tile has more than one connection to adjacent tiles, then it is possible
				// that an opponent is using the road tile as part of his/her/its route. Since we don't want
				// to annoy our opponents by unfair play, don't use this parallel tile
				if(num_stop_tile_connections > 1)
				{
					Log.Info("Parallel stop tile is (by road) connected to > 1 other tile => bail out (otherwise we could destroy someones road)", Log.LVL_DEBUG);
					continue;
				}

				// Check if no buildings / unremovable / vehicles are in the way
				local build = false;
				{
					local tm = AITestMode();
					local am = AIAccounting();
					build = AITile.DemolishTile(parallel_stop_tile) && 
							(
								// road can already exists or can be built
								// OR 
								// parallel front is not my property but can be demolished.
								(
									(AIRoad.AreRoadTilesConnected(front_tile, parallel_front_tile) || AIRoad.BuildRoad(front_tile, parallel_front_tile)) &&
									(AIRoad.AreRoadTilesConnected(parallel_stop_tile, parallel_front_tile) || AIRoad.BuildRoad(parallel_stop_tile, parallel_front_tile))
									|| (!own_parallel_front_tile && AITile.DemolishTile(parallel_front_tile))
								) 
							);

					// Wait up to 10 days untill we have enough money to demolish + construct
					local start = AIDate.GetCurrentDate();
					while(am.GetCosts() * 2 > AICompany.GetBankBalance(AICompany.COMPANY_SELF))
					{
						local now = AIDate.GetCurrentDate();
						local wait_time = now - start;
						if(wait_time > 10 || tot_wait_days + wait_time > MAX_TOT_WAIT_DAYS)
						{
							return RETURN_NOT_ENOUGH_MONEY;
						}
					}
					
				}

				if(build)
				{
					if(!AIRoad.AreRoadTilesConnected(front_tile, parallel_front_tile))
					{	
						// Wait untill there are no vehicles at front_tile
						local tm = AITestMode();
						local start = AIDate.GetCurrentDate();
						local fail = false;
						while(!AITile.DemolishTile(front_tile) && AIError.GetLastError() == AIError.ERR_VEHICLE_IN_THE_WAY)
						{ 
							// Keep track of the time
							local now = AIDate.GetCurrentDate();
							local wait_time = now - start;

							// Stop if waited more than allowed in total
							if(tot_wait_days + wait_time > MAX_TOT_WAIT_DAYS) 
							{
								return RETURN_TIME_OUT;
							}

							// Wait maximum 10 days
							if(wait_time > 10)
							{
								fail = true;
								break;
							}

							AIController.Sleep(5);
						}

						tot_wait_days += AIDate.GetCurrentDate() - start;

						if(fail)
						{
							Log.Info("Failed to grow to a specific parallel tile because the front_tile had vehicles in the way for too long time.", Log.LVL_DEBUG);
							continue;
						}
					}

					// Force clearing of the parallel_stop_tile if it has some road on it since it could have a single road connection to another 
					// road tile which would make it impossible to build a road stop on it after having built a road from the parallel_front_tile.
					if( (!AITile.IsBuildable(parallel_stop_tile) || AIRoad.IsRoadTile(parallel_stop_tile))  && !AITile.DemolishTile(parallel_stop_tile))
					{
						Log.Info("Failed to grow to a specific parallel tile because the parallel_stop_tile couldn't be cleared", Log.LVL_DEBUG);
						continue;
					}

					// Clear the parallel front tile if it is needed
					// Forbid clearing the tile if we own it
					if(!AIRoad.AreRoadTilesConnected(front_tile, parallel_front_tile) && !AIRoad.BuildRoad(front_tile, parallel_front_tile) && (own_parallel_front_tile || !AITile.DemolishTile(parallel_front_tile)))
					{
						Log.Info("Failed to grow to a specific parallel tile because the parallel_front_tile couln't be cleared", Log.LVL_DEBUG);
						continue;
					}

					if(!AIRoad.AreRoadTilesConnected(front_tile, parallel_front_tile) && !AIRoad.BuildRoad(front_tile, parallel_front_tile))
					{
						Log.Info("Failed to grow to a specific parallel tile because couldn't connect front_tile and parallel_front_tile", Log.LVL_DEBUG);
						continue;
					}

					if(!AIRoad.AreRoadTilesConnected(parallel_stop_tile, parallel_front_tile) && !AIRoad.BuildRoad(parallel_stop_tile, parallel_front_tile))
					{
						Log.Info("Failed to grow to a specific parallel tile because couldn't connect the parallel_stop_tile with the parallel_front_tile", Log.LVL_DEBUG);
						continue;
					}

					if(!AIRoad.BuildRoadStation(parallel_stop_tile, parallel_front_tile, road_veh_type, station_id))
					{
						Log.Info("Failed to grow to a specific parallel tile because the road station couldn't be built at parallel_stop_tile", Log.LVL_DEBUG);
						continue;
					}

					Log.Info("Growing to a specific parallel tile succeeded", Log.LVL_DEBUG);

					// Succeeded to grow station
					return RETURN_SUCCESS;
				}
			}
		}
		Log.Info( AIError.GetLastErrorString() );
	}

	return RETURN_FAIL;
}

function CargoOfVehicleValuator(vehicle_id)
{
	local engine_id = AIVehicle.GetEngineType(vehicle_id);
	return AIEngine.GetCargoType(engine_id);
}

function CluelessPlus::ReadConnectionsFromMap()
{
	// Get all road vehicles that carries passengers => buses
	local uncategorized_vehicles = AIVehicleList();
	uncategorized_vehicles.Valuate(AIVehicle.GetVehicleType);
	uncategorized_vehicles.KeepValue(AIVehicle.VT_ROAD);
	//uncategorized_vehicles.Valuate(CargoOfVehicleValuator);
	//uncategorized_vehicles.KeepValue(Helper.GetPAXCargo());

	local unused_bus_stations = AIStationList(AIStation.STATION_BUS_STOP);
	local unused_truck_stations = AIStationList(AIStation.STATION_TRUCK_STOP);
	local unused_stations = AIList();
	unused_stations.AddList(unused_bus_stations);
	unused_stations.AddList(unused_truck_stations);
	unused_stations.Valuate(Helper.ItemValuator);

	while(uncategorized_vehicles.Count() > 0)
	{
		local veh_id = uncategorized_vehicles.Begin();
		local group = AIVehicleList_SharedOrders(veh_id);

		// remove the vehicles that belongs to the found group from the list of uncategorised vehicles
		uncategorized_vehicles.RemoveList(group);

		// Construct the connection object and read everything needed for the connection from the map.
		Log.Info("Found connection with " + group.Count() + " vehicles", Log.LVL_INFO);
		local connection = ReadConnectionFromVehicle(veh_id);

		// Ignore vehicles with != 2 stations
		if(connection == null || connection.station.len() != 2)
		{
			Log.Warning("Couldn't create connection object for this connection", Log.LVL_INFO);
			continue;
		}

		connection_list.append(connection);

		Log.Info("Connection " + connection.GetName() + " added to connection list", Log.LVL_INFO);

		foreach(station_tile in connection.station)
		{
			// remove station from unused stations list
			local station_id = AIStation.GetStationID(station_tile);
			unused_stations.RemoveValue(station_id);
		}
	}

	// Destroy all unused stations so they don't cost money
	foreach(station_id, _ in unused_stations)
	{
		Log.Warning("Station " + AIStation.GetName(station_id) + " is unused and will be removed", Log.LVL_INFO);

		Station.DemolishStation(station_id);
	}
}

function CluelessPlus::ReadConnectionFromVehicle(vehId)
{
	local connection = Connection(this);
	connection.cargo_type = Vehicle.GetVehicleCargoType(vehId);

	connection.station = [];
	connection.depot = [];
	for(local i_order = 0; i_order < AIOrder.GetOrderCount(vehId); ++i_order)
	{
		if(AIOrder.IsGotoStationOrder(vehId, i_order))
		{
			local station_id = AIStation.GetStationID(AIOrder.GetOrderDestination(vehId, i_order));
			Log.Info("Added station: " + AIStation.GetName(station_id), Log.LVL_INFO);
			connection.station.append(AIOrder.GetOrderDestination(vehId, i_order));
			connection.station_statistics.append(StationStatistics(station_id, connection.cargo_type));
		}

		if(AIOrder.IsGotoDepotOrder(vehId, i_order))
		{
			connection.depot.append(AIOrder.GetOrderDestination(vehId, i_order));
		}
	}

	// fail if less than two stations were found
	if(connection.station.len() != 2)
	{
		Log.Warning("Connection has != 2 stations -> fail", Log.LVL_INFO);
		return null;
	}

	local station_tile = null;
	connection.town = [];
	connection.industry = [];
	connection.node = [];
	foreach(station_tile in connection.station)
	{
		local station_id = AIStation.GetStationID(station_tile);

		local save_str = ClueHelper.ReadStrFromStationName(station_id);
		local space = save_str.find(" ");
		local save_version = -1;
		local node_save_str = null;
		if(space != null)
		{
			save_version = save_str.slice(0, space);
			node_save_str = save_str.slice(space + 1);

			// Convert save version to integer
			try
			{
				save_version = save_version.tointeger();
			}
			catch(e)
			{
				AILog.Warning("catched exception");
				save_version = -1;
			}
		}

		Log.Info("station save version: " + save_version, Log.LVL_INFO);
		Log.Info("station save str: " + node_save_str, Log.LVL_INFO);

		local node = null;
		if(node_save_str != null && save_version >= 0)
		{
			node = Node.CreateFromSaveString(node_save_str);
		}

		if(node == null)
		{
			Log.Info("Node is null -> game has old pre version 19 station names", Log.LVL_INFO);

			// Old CluelessPlus and/or loading from other AI
			local town_id = AITile.GetClosestTown(station_tile);
			local industry_id = -1;
			local cargo_id = Helper.GetPAXCargo(); //AIEngine.GetCargoType(AIVehicle.GetVehicleType(vehId));
			
			if(AIEngine.GetCargoType(AIVehicle.GetEngineType(vehId)) != cargo_id)
			{
				Log.Info("connection with non-pax detected", Log.LVL_INFO);
				return null; // The vehicle transports non-pax
			}

			local stop_tiles_for_veh = AITileList_StationType(station_id, Station.GetStationTypeOfVehicle(vehId));
			if(stop_tiles_for_veh.IsEmpty())
			{
				Log.Warning("No bus stops at station " + AIError.GetLastErrorString(), Log.LVL_INFO);
				return null; // There is no bus stops at the station
			}

			node = Node(town_id, industry_id, cargo_id);

			// Update the station name to be compatible with the current storage method
			ClueHelper.StoreInStationName(station_id, STATION_SAVE_VERSION + " " + node.SaveToString());
		}

		connection.town.append(node.town_id);
		connection.industry.append(node.industry_id);
		connection.node.append(node);

		//Helper.SetSign(node.GetLocation(), node.SaveToString());
	}

	local group = AIVehicleList_SharedOrders(vehId);
	group.Valuate(AIVehicle.GetAge);
	group.Sort(AIAbstractList.SORT_BY_VALUE, false); // oldest first
	local estimated_construction_date = AIDate.GetCurrentDate() - AIVehicle.GetAge(group.Begin());
	
	connection.date_built = estimated_construction_date;
	connection.state = Connection.STATE_ACTIVE;
	
	// read connection state from vehicles
	local active_count = 0;
	local suspended_count = 0;
	local close_conn_count = 0;
	local sell_count = 0;
	foreach(veh_id, _ in group)
	{
		local state = ClueHelper.ReadStrFromVehicleName(veh_id);

		if(state == "active")
			active_count++;
		else if(state == "suspended")
			suspended_count++;
		else if(state == "close conn")
			close_conn_count++;
		else if(state == "sell")
			sell_count++;
		else
			continue;

		Log.Info("Vehicle has state: " + state, Log.LVL_DEBUG);
	}

	// For now just detect closing down and suspended named vehicles
	if(close_conn_count > 0) {
		connection.state = Connection.STATE_CLOSING_DOWN;
	} else if(suspended_count > 0) {
		connection.state = Connection.STATE_SUSPENDED;
	} else { //if(sell_count != group.Count())
		connection.state = Connection.STATE_ACTIVE;
	}

	// Detect broken connections
	if(connection.depot.len() != 2 || connection.station.len() != 2 || connection.town.len() != 2)
		connection.state = Connection.STATE_FAILED;

	Helper.SetSign(connection.station[0], "state: " + connection.state);
	Helper.SetSign(connection.station[1], "state: " + connection.state);

	// Sleep a while if we are a slow AI
	if(AIController.GetSetting("slow_ai") == 1)
		AIController.Sleep(50);

	return connection;
}

// RETURN: new name
function CluelessPlus::SetCompanyName(nameArray)
{
	AICompany.SetPresidentName("Dr. Clue");

	local i = 0;
	//AILog.Info("i, before loop = " + i);
	while(i < nameArray.len() && !AICompany.SetName(nameArray[i]))
	{
		Log.Info("i++ = " + i, Log.LVL_DEBUG);
		i = i + 1;
	}
	//AILog.Info("company name done");
	//AILog.Info("i, after loop = " + i);
	return nameArray[i];
}

function CluelessPlus::ManageLoan()
{
	// local constants. ( I've not found how to declare constants in Squirrel yet :( )
	local balance = AICompany.GetBankBalance(AICompany.COMPANY_SELF);
	local loan = AICompany.GetLoanAmount();
	local max_balance = this.conf_min_balance + 2 * AICompany.GetLoanInterval(); // Attention: max_balance is the maximum balance we accept before paying back loan.


	if( balance < this.conf_min_balance ) // bigger loan
	{
		//AILog.Info("ManageLoan: Want to loan more");
		//AILog.Info("Company: " + AICompany.GetCompanyName());

		local new_loan = loan + (this.conf_min_balance - balance) + AICompany.GetLoanInterval();
		if(new_loan < AICompany.GetMaxLoanAmount())
			new_loan = AICompany.GetMaxLoanAmount();

		new_loan = RoundLoanDown(new_loan);
		if(!AICompany.SetLoanAmount(new_loan))
		{
			//AILog.Info(this.state_ai_name + " Failed to increase loan amount");
		}
	}
	
	else if( balance > max_balance && loan > 0) // smaller loan
	{
		//AILog.Info("ManageLoan: Want to pay back");
		//AILog.Info("Company: " + AICompany.GetCompanyName());
		//AILog.Info("balance: " + balance);
		//AILog.Info("loan: " + loan);
		//AILog.Info("max_balance: " + max_balance);

		local pay_back = balance - max_balance;
		local new_loan = RoundLoanDown(loan - pay_back);

		//AILog.Info("pay_back: " + pay_back);
		//AILog.Info("new_loan: " + new_loan);
		
		if(!AICompany.SetLoanAmount(new_loan))
		{
			//AILog.Info(this.state_ai_name + " Failed to decrease loan amount");
		}
			
		//AILog.Info("Successfully paid back loan");
	}
}

function CluelessPlus::RoundLoanDown(loanAmount)
{
	return loanAmount - loanAmount % AICompany.GetLoanInterval();
}
function CluelessPlus::GetMaxMoney()
{
	local balance = AICompany.GetBankBalance(AICompany.COMPANY_SELF);
	local loan = AICompany.GetLoanAmount();

	local max_possible_balance = balance + (AICompany.GetMaxLoanAmount() - loan);

	return max_possible_balance;
}

function CluelessPlus::BuildStopInTown(town, road_veh_type, accept_cargo = -1, produce_cargo = -1) // this function is ugly and should ideally be removed
{
	Log.Info("CluelessPlus::BuildStopInTown(" + AITown.GetName(town) + ")", Log.LVL_INFO);

	if(AITown.IsValidTown(town))
		Log.Info("Town is valid", Log.LVL_DEBUG);
	else
		Log.Warning("Town is NOT valid", Log.LVL_INFO);
	
	local location = AITown.GetLocation(town);

	if(!AIMap.IsValidTile(location))
	{
		Log.Error("Invalid location!", Log.LVL_INFO);
		return false;
	}

	local what = "";

	if(road_veh_type == AIRoad.ROADVEHTYPE_BUS)
		what = "BUS_STOP";
	if(road_veh_type == AIRoad.ROADVEHTYPE_TRUCK)
		what = "TRUCK_STOP";

	return BuildNextToRoad(location, what, accept_cargo, produce_cargo, 50, 100 + AITown.GetPopulation(town) / 70, 1);

/*
	local tiles = AITileList();
	tiles.AddRectangle(location - AIMap.GetTileIndex(15, 15), location + AIMap.GetTileIndex(15, 15));
	tiles.Valuate(GetNeighbourRoadCount);
	tiles.KeepAboveValue(0);
	tiles.Valuate(IsWithinTownInfluence, town);
	tiles.KeepValue(true); 
	tiles.Valuate(*/
}

function CluelessPlus::BuildStopForIndustry(industry_id, cargo_id)
{
	local road_veh_type = AIRoad.GetRoadVehicleTypeForCargo(cargo_id);
	
	local radius = 3;
	local accept_tile_list = AITileList_IndustryAccepting(industry_id, radius);
	local produce_tile_list = AITileList_IndustryProducing(industry_id, radius);

	local tile_list = AITileList();

	if (!accept_tile_list.IsEmpty() && !produce_tile_list.IsEmpty())
	{
		// Intersection between accept & produce tiles
		tile_list.AddList(accept_tile_list);
		tile_list.KeepList(produce_tile_list);
	}
	else
	{
		// The industry only accepts or produces cargo
		// so intersection would yeild an empty tile list.
		// Instead make a union
		tile_list.AddList(accept_tile_list);
		tile_list.AddList(produce_tile_list);
	}


	// tile_list now contains all tiles around the industry that accept + produce cargo (hopefully all cargos of the industry, but that isn't documented in the API)
	
	tile_list.Valuate(AITile.IsWaterTile);
	tile_list.KeepValue(0);
	
	tile_list.Valuate(AITile.IsBuildable);
	tile_list.KeepValue(1);

	tile_list.Valuate(Tile.IsBuildOnSlope_Flat); // this is a bit more strict than necessary _FlatInDirection(tile, ANY_DIR) would have been enough
	tile_list.KeepValue(1);

	// Randomize the station location
	tile_list.Valuate(AIBase.RandItem);

	//tile_list.Valuate(AIMap.DistanceManhattan, AIIndustry.GetLocation(industry_id));
	tile_list.Sort(AIAbstractList.SORT_BY_VALUE, AIAbstractList.SORT_DESCENDING); // place the station as far away as possible from the industry location (in practice -> to the south of the industry)

	// Randomize which direction to try first when constructing to not get a strong bias towards building
	// stations in one particular direction. It is however, enough to randomize once per industry. 
	// (no need to randomize once per tile)
	local dir_list = Direction.GetMainDirsInRandomOrder();

	// Loop through the remaining tiles and see where we can put down a stop and a road infront of it
	foreach(tile, _ in tile_list)
	{
//		Helper.SetSign(tile, "ind stn");

		// Go through all dirs and try to build in all directions until one succeeds
		foreach(dir, _ in dir_list)
		{
			
			local front_tile = Direction.GetAdjacentTileInDirection(tile, dir);

			if(!Tile.IsBuildOnSlope_FlatForTerminusInDirection(front_tile, Direction.OppositeDir(dir))) // Check that the front tile can be connected to tile without using any DoCommands.
				continue;

			Helper.SetSign(tile, "front stn");

			// First test build to see if there is a failure and only if it works build it in reality
			{
				local tm = AITestMode();

				if(!AIRoad.BuildRoadStation(tile, front_tile, road_veh_type, AIStation.STATION_NEW) &&
						AIRoad.BuildRoad(tile, front_tile))
					continue;
			}
			
			// Build it for real
			local ret = AIRoad.BuildRoadStation(tile, front_tile, road_veh_type, AIStation.STATION_NEW) &&
					AIRoad.BuildRoad(tile, front_tile);

			if (ret)
				return tile;

			// There was a problem to construct some part -> demolish tile + front_tile so that we don't leave anything around
			AITile.DemolishTile(tile);
			AITile.DemolishTile(front_tile);
		}
	}

	return -1;
}

// Build*NextToRoad functions:
// 1. Checks if 'tile' is road
// 2. If not: it locates nearby road using FindClosestRoadTile
// 3. From the starting-point on the road network, search for a suitable 
//    location to build the building. 
//    - it prefers to build the building near the starting-point
function CluelessPlus::BuildBusStopNextToRoad(tile, min_loops, max_loops)
{
	return BuildNextToRoad(tile, "BUS_STOP", -1, -1, min_loops, max_loops, 1);
}
function CluelessPlus::BuildTruckStopNextToRoad(tile, min_loops, max_loops)
{
	return BuildNextToRoad(tile, "TRUCK_STOP", -1, -1, min_loops, max_loops, 1);
}
function CluelessPlus::BuildDepotNextToRoad(tile, min_loops, max_loops)
{
	return BuildNextToRoad(tile, "DEPOT", -1, -1, min_loops, max_loops, 1);
}

// Score valuator to be uesd with the found_locations ScoreList in BuildNextToRoad
function CluelessPlus::GetTileAcceptancePlusProduction_TimesMinusOne(pair, accept_cargo, produce_cargo)
{
	local station_tile = pair[0];
	//local front_tile = pair[1]; // not used

	local acceptance = -1;
	local production = -1;

	if(accept_cargo != -1)
		acceptance = AITile.GetCargoAcceptance(station_tile, accept_cargo, 1, 1, 3);

	if(produce_cargo != -1)
		production = AITile.GetCargoProduction(station_tile, accept_cargo, 1, 1, 3);

	// Get base score
	local score = (acceptance + production);

	// Add a random component up to a third of the acceptance/production sum
	score = score + AIBase.RandRange(score / 3); 

	// Multiply by -1
	score = score * -1;

	return score;
}

function CluelessPlus::BuildNextToRoad(tile, what, accept_cargo, produce_cargo, min_loops, max_loops, try_number)
{
	local start_tile = tile;

	local green_list = AIList();
	local red_list = [];

	local found_locations = ScoreList();

	local i = 0;
	local ix, iy;
	local curr_x, curr_y;
	local curr_tile;
	local curr_distance;
	local adjacent_x, adjacent_y;
	local adjacent_tile;

	local adjacent_dir_list = Direction.GetMainDirsInRandomOrder();

	if(!AIMap.IsValidTile(start_tile))
	{
		Log.Error("Invalid start_tile!", Log.LVL_INFO);
		return null;
	}

	if(!AIRoad.IsRoadTile(start_tile))
	{
		start_tile = FindClosestRoadTile(start_tile, 4);
		if(!start_tile)
		{
			Log.Error("failed to find road tile as start_tile was not a road tile!", Log.LVL_INFO);
			return null;
		}
	}

	curr_tile = start_tile;
	curr_distance = 0;

	while( i++ < max_loops )
	{
		/*{
			local exec = AIExecMode(); 
			AISign.BuildSign(curr_tile, i+"/"+AIMap.DistanceSquare(curr_tile, start_tile));
		}*/
		local testmode = AITestMode();
		curr_x = AIMap.GetTileX(curr_tile);
		curr_y = AIMap.GetTileY(curr_tile);

		// if we are on a bridge end, add the tile next to other end to green list if it's not in red_list and is accessible from bridge.
		if(AIBridge.IsBridgeTile(curr_tile) || AITunnel.IsTunnelTile(curr_tile))
		{
			local exec = AIExecMode();	

			//AISign.BuildSign(curr_tile, "bridge end");
			local other_end = null;
			if(AIBridge.IsBridgeTile(curr_tile))
			{
				other_end = AIBridge.GetOtherBridgeEnd(curr_tile);
			}
			else 
			{
				other_end = AITunnel.GetOtherTunnelEnd(curr_tile);
			}
			//AISign.BuildSign(other_end, "other end");

			// Get tile next to bridge/tunnel on the other end
			local next_to_other_end = null;
			local x = AIMap.GetTileX(curr_tile) - AIMap.GetTileX(other_end);
			local y = AIMap.GetTileY(curr_tile) - AIMap.GetTileY(other_end);
			local bridge_tunnel_length = Helper.Max(abs(x), abs(y));
			
			if(x != 0)
				x = x / abs(x);
			if(y != 0)
				y = y / abs(y);
			next_to_other_end = other_end - AIMap.GetTileIndex(x, y);
			//AISign.BuildSign(next_to_other_end, "next to other end");
			
			// Add the tile next_to_other_end to green list if it is not in red list and is accessible from the bridge
			if( ClueHelper.ArrayFind(red_list, next_to_other_end) == null )
			{
				//local test = AITestMode(); // < let's add a road bit at the other end if there is no so we can use that for building next to if needed.
				if(AIRoad.AreRoadTilesConnected(other_end, next_to_other_end) || AIRoad.BuildRoad(other_end, next_to_other_end))
				{
					local walk_distance = curr_distance + bridge_tunnel_length;
					green_list.AddItem(next_to_other_end, walk_distance + AIMap.DistanceManhattan(next_to_other_end, start_tile));
				}
			}
			
		}
		else
		{
			// scan adjacent tiles
			foreach(adjacent_dir, _ in adjacent_dir_list)
			{
				adjacent_tile = Direction.GetAdjacentTileInDirection(curr_tile, adjacent_dir);

				if(!AIMap.IsValidTile(adjacent_tile))
				{
					Log.Warning("Adjacent tile is not valid", Log.LVL_DEBUG);
					continue;
				}

				if(accept_cargo != -1)
				{
					// Make sure the station will accept the given cargo
					local acceptance = AITile.GetCargoAcceptance(adjacent_tile, accept_cargo, 1, 1, 3);
					if(acceptance < 8)
						continue;
				}
				if(produce_cargo != -1)
				{
					// Make sure the station will receive the given produced cargo
					local production = AITile.GetCargoProduction(adjacent_tile, produce_cargo, 1, 1, 3);
					if(production < 8)
						continue;
				}

				if(AIRoad.AreRoadTilesConnected(curr_tile, adjacent_tile))
				{
					if( ClueHelper.ArrayFind(red_list, adjacent_tile) == null )
					{
						local exec = AIExecMode();	
						green_list.AddItem(adjacent_tile, curr_distance + 1 + AIMap.DistanceManhattan(adjacent_tile, start_tile));
						//AISign.BuildSign(adjacent_tile, i+":"+AIMap.DistanceSquare(adjacent_tile, start_tile));
					}
				}
				else if(AIRoad.BuildRoad(adjacent_tile, curr_tile))
				{
					/*{
						local exec = AIExecMode(); 
						AISign.BuildSign(adjacent_tile, i+"|"+AIMap.DistanceSquare(adjacent_tile, start_tile));
					}*/

					local ret;
					

					if(what == "BUS_STOP")
					{
						ret = AIRoad.BuildRoadStation(adjacent_tile, curr_tile, AIRoad.ROADVEHTYPE_BUS, AIStation.STATION_NEW);
					}
					else if(what == "TRUCK_STOP")
					{
						ret = AIRoad.BuildRoadStation(adjacent_tile, curr_tile, AIRoad.ROADVEHTYPE_TRUCK, AIStation.STATION_NEW);
					}
					else if(what == "DEPOT")
					{
						ret = AIRoad.BuildRoadDepot(adjacent_tile, curr_tile)
					}
					else
					{
						Log.Info("ERROR: Invalid value of argument 'what' to function BuildNextToRoad(tile, what)", Log.LVL_INFO);
						AIRoad.RemoveRoad(adjacent_tile, curr_tile);
						return null;
					}

					if(ret)
					{
						found_locations.Push([adjacent_tile, curr_tile], AIMap.DistanceSquare(adjacent_tile, start_tile));
					}
				}
				else
				{
					//local exec = AIExecMode();	
					//AISign.BuildSign(adjacent_tile, "x");
				}

				if(i%10 == 0)
				{
					this.Sleep(1);
				}
			}
		}

		// if found at least one location and we have looped at least min_loops. => don't search more
		if(found_locations.list.len() > 0 && i >= min_loops)
		{
			break;
		}

		red_list.append(curr_tile);

		if(green_list.IsEmpty())
		{
			Log.Warning("Green list empty in BuildNextToRoad function.", Log.LVL_INFO);
			break;
		}

		// select best tile from green_list
		green_list.Sort(AIAbstractList.SORT_BY_VALUE, true); // lowest distance first
		curr_tile = green_list.Begin();
		curr_distance = green_list.GetValue(curr_tile) - AIMap.DistanceManhattan(curr_tile, start_tile); // The distance score include the distance to city center as well, so remove it to get the walk distance only as the base for aggregating distance.
		
		green_list.Valuate(Helper.ItemValuator);
		green_list.RemoveValue(curr_tile);

		if(!AIMap.IsValidTile(curr_tile)) 
		{
			Log.Warning("Green list contained invalid tile.", Log.LVL_INFO);
			break;
		}
	}

	// if there is a accept/produce cargo use that to score the locations
	if(accept_cargo != -1 || produce_cargo != -1)
	{
		// Valuate the list with (acceptance + production of cargoes) * -1
		//
		// By multiplying by -1, PopMin below will pick the best producing/accepting tile first
		found_locations.ScoreValuate(this, GetTileAcceptancePlusProduction_TimesMinusOne, accept_cargo, produce_cargo);
	}

	// get best built building
	local best_location = found_locations.PopMin();
	if(best_location == null) // return null, if no location at all was found.
	{
		Log.Info("BuildNextToRoad: failed to build: " + what, Log.LVL_INFO);
		return null;
	}

	// Build best station
	local road_tile = best_location[1];
	local station_tile = best_location[0];
	
	local ret = false;

	if(!AIRoad.BuildRoad(road_tile, station_tile)) return null;
	if(what == "BUS_STOP")
	{
		ret = AIRoad.BuildRoadStation(station_tile, road_tile, AIRoad.ROADVEHTYPE_BUS, AIStation.STATION_NEW);
	}
	else if(what == "TRUCK_STOP")
	{
		ret = AIRoad.BuildRoadStation(station_tile, road_tile, AIRoad.ROADVEHTYPE_TRUCK, AIStation.STATION_NEW);
	}
	else if(what == "DEPOT")
	{
		ret = AIRoad.BuildRoadDepot(station_tile, road_tile)
	}
	else
	{
		Log.Error("ERROR: Invalid value of argument 'what' to function BuildNextToRoad(tile, what) at constructing on the best tile", Log.LVL_INFO);
		return null;
	}

	if(!ret)
	{
		// someone built something on the tile so now it's not possible to build there. :( 
		// make another try a few times and then give up
		if(try_number <= 5)
		{
			Log.Info("BuildNextToRoad retries by calling itself", Log.LVL_INFO);
			return BuildNextToRoad(tile, what, -1, -1 min_loops, max_loops, try_number+1);
		}
		else
			return null;
	}

	if(AIController.GetSetting("slow_ai") == 1)
		this.Sleep(80);
	else
		this.Sleep(5);

	//Helper.ClearAllSigns();
	
	// return the location of the built station
	return station_tile;
	
}

function CluelessPlus::FindClosestRoadTile(tile, max_radius)
{
	if(!tile || !AIMap.IsValidTile(tile))
		return null;

	if(AIRoad.IsRoadTile(tile))
		return tile;
	
	local r; // current radius

	local start_x = AIMap.GetTileX(tile);
	local start_y = AIMap.GetTileY(tile);

	local x0, x1, y0, y1;
	local ix, iy;
	local test_tile;

	for(r = 1; r < max_radius; ++r)
	{
		y0 = start_y - r;
		y1 = start_y + r;
		for(ix = start_x - r; ix <= start_x + r; ++ix)
		{
			test_tile = AIMap.GetTileIndex(ix, y0)
			if(test_tile != null && AIRoad.IsRoadTile(test_tile))
				return test_tile;

			test_tile = AIMap.GetTileIndex(ix, y1)
			if(test_tile != null && AIRoad.IsRoadTile(test_tile))
				return test_tile;
		}

		x0 = start_x - r;
		x1 = start_x + r;
		for(iy = start_y - r + 1; iy <= start_y + r - 1; ++iy)
		{
			test_tile = AIMap.GetTileIndex(x0, iy)
			if(test_tile != null && AIRoad.IsRoadTile(test_tile))
				return test_tile;

			test_tile = AIMap.GetTileIndex(x1, iy)
			if(test_tile != null && AIRoad.IsRoadTile(test_tile))
				return test_tile;

		}
	}

	return null;
}

function CluelessPlus::FindRoadExtensionTile(road_tile, target_tile, min_loops, max_loops)
{
	// road_tile belong to a road-network of one or more tiles.
	// This function aims to find a tile in this network from which the network can be extended.
	// It stops the search when either:
	// * the whole network have been scanned
	// * it have looped for min_loops times AND have found at least one solution
	// * it have looped for max_loops times
	//
	// Returns the best solution-tile.


	if(road_tile == null || !AIRoad.IsRoadTile(road_tile) || target_tile == null || !AIMap.IsValidTile(target_tile))
		return null;


	local start = road_tile;

	local green_list = ScoreList()
	local red_list = [];

	// each item is a tile, and the score is the MH distance to the target tile
	local extend_list = FibonacciHeap();

	local i = 0;
	local ix, iy;
	local curr_x, curr_y;
	local curr_tile;
	local adjacent_x, adjacent_y;
	local adjacent_tile;

	local adjacent_loop = [ [-1,0], [1,0], [0,-1], [0,1] ];

	curr_tile = start;

	while( i++ < max_loops )
	{
		curr_x = AIMap.GetTileX(curr_tile);
		curr_y = AIMap.GetTileY(curr_tile);

		//AISign.BuildSign(curr_tile, "i:" + i)
		
		// scan adjacent tiles

		foreach(adjacent_offset in adjacent_loop)
		{
			adjacent_x = curr_x + adjacent_offset[0];
			adjacent_y = curr_y + adjacent_offset[1];

			adjacent_tile = AIMap.GetTileIndex(adjacent_x, adjacent_y);

			if(AIRoad.AreRoadTilesConnected(curr_tile, adjacent_tile))
			{
				// special case: we have reached the target-tile.
				if(adjacent_tile == target_tile)
				{
					return adjacent_tile;
				}

				// add tile to green_list if it is not in red_list
				if( ClueHelper.ArrayFind(red_list, adjacent_tile) == null )
				{
					green_list.Push(adjacent_tile, AIMap.DistanceManhattan(adjacent_tile, target_tile));
				}
			}
			else 
			{
				//AILog.Info("CluelessPlus::FindRoadExtensionTile: found one solution");
				// Perhaps the road can be extended here. 
				// Test if it is possible to do so.
				local test_mode = AITestMode();
				if(AIRoad.BuildRoad(curr_tile, adjacent_tile))
				{
					//AILog.Info("Possible to build road");
					extend_list.Insert(curr_tile, AIMap.DistanceManhattan(curr_tile, target_tile));
				}
			}

			if(AIController.GetSetting("slow_ai") == 1)
				this.Sleep(5);
			else
				this.Sleep(1);
		}

		// stop loop if at least one solution found and i > min_loops
		if(extend_list.Count() > 0 && i > min_loops)
		{
			break;
		}

		red_list.append(curr_tile);

		// select best tile from green_list
		curr_tile = green_list.PopMin();

		if(!curr_tile || !AIMap.IsValidTile(curr_tile)) // if green_list was empty
		{
			break;
		}
	}

	if(extend_list.Count() == 0)
	{
		Log.Info("CluelessPlus::FindRoadExtensionTile: found zero solutions", Log.LVL_INFO);
		return null;
	}
	else
	{
		return extend_list.Pop();
	}
}
function CluelessPlus::FindRoadExtensionTile_SortByDistanceToTarget(a, b)
{
	if(a[1] > b[1]) 
		return 1
	else if(a[1] < b[1]) 
		return -1
	return 0;
}

function CluelessPlus::BuyNewConnectionVehicles(connection)
{
	local engine = connection.FindEngineModelToBuy();
	local num = connection.NumVehiclesToBuy(engine);

	Log.Info("buy engine " + engine, Log.LVL_INFO);

	connection.BuyVehicles(num, engine);

	return connection;
}

function IsHQLocationNearbyRoad(hq_location)
{
	local adjacent_tiles = AITileList();
	
	// Add the 4x4 rectangle around the HQ as well as the HQ-rect inself
	adjacent_tiles.AddRectangle( Tile.GetTileRelative(hq_location, -1, -1), Tile.GetTileRelative(hq_location, 2, 2) );

	// Remove the 4 corners
	adjacent_tiles.RemoveTile( Tile.GetTileRelative(hq_location, -1, -1) );
	adjacent_tiles.RemoveTile( Tile.GetTileRelative(hq_location, -1, 2) );
	adjacent_tiles.RemoveTile( Tile.GetTileRelative(hq_location, 2, -1) );
	adjacent_tiles.RemoveTile( Tile.GetTileRelative(hq_location, 2, 2) );

	// Remove the HQ rect itself
	adjacent_tiles.RemoveRectangle( hq_location, Tile.GetTileRelative(hq_location, 1, 1) );

	adjacent_tiles.Valuate(AIRoad.IsRoadTile);
	adjacent_tiles.KeepValue(1);

	return adjacent_tiles.Count() > 0;
}

function CluelessPlus::PlaceHQ(nearby_tile)
{
	Log.Info("Trying to build the HQ close to " + ClueHelper.TileLocationString(nearby_tile), Log.LVL_INFO);

	local tiles = Tile.MakeTileRectAroundTile(nearby_tile, 40);
	tiles.Valuate(IsHQLocationNearbyRoad);
	tiles.KeepValue(1);

	tiles.Valuate(AIMap.DistanceManhattan, nearby_tile);
	tiles.Sort(AIAbstractList.SORT_BY_VALUE, true); // lowest distance first

	local possible_tiles = AIList();
	possible_tiles.Sort(AIAbstractList.SORT_BY_VALUE, true); // lowest cost first

	// Go through the tiles starting from closest to nearby_tile and check if HQ can be built there
	foreach(hq_tile, _ in tiles)
	{
		{{
			local test = AITestMode();
			local cost = AIAccounting();
			
			if(!AICompany.BuildCompanyHQ(hq_tile))
				continue;

			// Add tiles that can be built on with their cost as value
			// In addition to cost add the distance to nearby_tile so
			// that if tow locations are equally cheap, it chooses the 
			// closest one. The weighting inbetween cost and distance is
			// such that it will not place it very far away just to not 
			// remove any trees, but still include cost in the selection
			possible_tiles.AddItem(hq_tile, cost.GetCosts() + 3 * tiles.GetValue(hq_tile) );
		}}

		// Stop when 10 possible locations have been found
		if(possible_tiles.Count() > 30)
			break;
	}

	if(possible_tiles.Count() == 0)
	{
		Log.Warning("Couldn't find a place close to " + ClueHelper.TileLocationString(nearby_tile) + " to build the HQ", Log.LVL_INFO);
		return;
	}

	
	// Since there might have been changes since the checking of 10 possible tiles was made to the terrain,
	// try until we succeed, starting with the cheapest alternative.
	foreach(hq_tile, _ in possible_tiles)
	{
		if(AICompany.BuildCompanyHQ(hq_tile))
		{
			Log.Info("The HQ was built, so that our clueless paper pushers have somewhere to sit. ;-)", Log.LVL_INFO);

			if(AIController.GetSetting("slow_ai") == 1)
			{
				Log.Info("The AI is so happy with the new HQ that it can't think about anything else for a while..", Log.LVL_INFO);
				AIController.Sleep(200);
				Log.Info("Oh, there is business to do also! :-)", Log.LVL_INFO);
				AIController.Sleep(2);
				Log.Info("Oh well ... ", Log.LVL_INFO);
				AIController.Sleep(20);
			}

			return;
		}
	}

	Log.Warning("Found " + possible_tiles.Count() + " number of places to build the HQ, but when trying to execute the construction all found locations failed.", Log.LVL_INFO);
}
