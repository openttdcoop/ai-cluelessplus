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
// Copyright: Leif Linse - 2008-2010
// License: GNU GPL - version 2


import("util.superlib", "SuperLib", 3);

Log <- SuperLib.Log;
Helper <- SuperLib.Helper;
Money <- SuperLib.Money;

Tile <- SuperLib.Tile;
Direction <- SuperLib.Direction;

Engine <- SuperLib.Engine;
Vehicle <- SuperLib.Vehicle;

Station <- SuperLib.Station;
Industry <- SuperLib.Industry;

//Order <- SuperLib.Order;
//OrderList <- SuperLib.OrderList;

require("pairfinder.nut"); 
require("sortedlist.nut");
require("roadbuilder.nut"); 
require("clue_helper.nut");
require("stationstatistics.nut");



//////////////////////////////////////////////////////////////////////
//                                                                  //
//  CLASS: TownFinder                                               //
//                                                                  //
//////////////////////////////////////////////////////////////////////
class TownFinder
{
	// each item in search list is an array of these stuff:
	// [0] => town ID
	// [1] => town population
	search_list = [];

	conf_min_distance = 20;
	conf_min_population = 150;

	constructor() {
		search_list = [];
	}

	function SelectSearchList();
	function FindTwoTownsToConnectByRoad(maxDistance);
	function SelectSearchList_CompareTownByPopulation(a, b);
	function FindTwoTownsToConnectByRoad_CompareTownPairsByScore(a, b);
}

// Creates a sorted list of all towns (best first), and then shrink it to top 50.
// The top 50-list is then stored list in this.search_list.
function TownFinder::SelectSearchList(connection_list)
{
	local town_list = AITownList();
	local list = [];
	local population;

	for(local town_id = town_list.Begin(); town_list.HasNext(); town_id = town_list.Next())
	{
		if(!AITown.IsValidTown(town_id) || ClueHelper.IsTownInConnectionList(connection_list, town_id))
		{
			//AILog.Info("Town no " + town_id + " is not a valid town or already connected, skip it");	
		}
		else
		{
			population = AITown.GetPopulation(town_id);
			if(population >= this.conf_min_population)
			{
				list.append([town_id, population]);
				//AILog.Info("appended town to list " + town_id);
			}
		}
	}
	list.sort(this.SelectSearchList_CompareTownByPopulation);
	list.reverse();

	if(list.len() > 50)
	{
		list.resize(50);
	}

	foreach(val in list)
	{
		//AILog.Info(val[0] + " (" + AITown.GetName(val[0]) + ") => " + val[1]);
	}

	this.search_list = list;
}

function TownFinder::SelectSearchList_CompareTownByPopulation(a, b)
{
	if(a[1] > b[1]) 
		return 1
	else if(a[1] < b[1]) 
		return -1
	return 0;
}

function TownFinder::FindTwoTownsToConnectByRoad(maxDistance)
{
	//AILog.Info("TownFinder::FindTwoTownsToConnectByRoad()");
	local dist_weight = 1.5;
	local pop_weight  = 1.0;
	local desert_snow_weight = 200.0;

	local list_pairs = ScoreList();
	local i = 0;
	local j = 0;

	//AILog.Info(this.search_list.len());
	for(i = 0; i < this.search_list.len(); i++)
	{
		for(j = i+1; j < this.search_list.len(); j++)
		{
			if(i != j)
			{
				local town1_location = AITown.GetLocation(this.search_list[i][0]);
				local town2_location = AITown.GetLocation(this.search_list[j][0]);

				local distance = ClueHelper.TownDistance(this.search_list[i][0], this.search_list[j][0]);
				local total_population = this.search_list[i][1] + this.search_list[j][1];

				// count the number of towns that are on snow/desert and thus will not grow unless another player supply it with required goods
				local desert_snow_count = 0;
				if(AITile.IsSnowTile(town1_location) || AITile.IsDesertTile(town1_location))
					desert_snow_count++;
				if(AITile.IsSnowTile(town2_location) || AITile.IsDesertTile(town2_location))
					desert_snow_count++;

				// give a bonus to pairs that are balanced in population or where either both or none of them are on desert/snow
				local differity = Helper.Abs(this.search_list[i][1] - this.search_list[j][1]);
				if(desert_snow_count == 1)
					differity += 400;
				local equity = 700 / (differity + 1); // add 1 to make sure we never divide by zero

				// calculate total score
				local t = ClueHelper.StepFunction(distance - maxDistance);
				local score = total_population * pop_weight + 
						distance * (1 - ClueHelper.StepFunction(distance - maxDistance))  * dist_weight +
						(2 - desert_snow_count) * desert_snow_weight +
						equity;
				if( distance > maxDistance || distance < this.conf_min_distance || total_population < this.conf_min_population )
				{
					score = 0;
				}
				else
				{
					list_pairs.Push([this.search_list[i][0], this.search_list[j][0], score, distance, total_population], score);
				}
				//AILog.Info("For city " + AITown.GetName(this.search_list[i][0]) + " and " + AITown.GetName(this.search_list[j][0]) + " the score is: " + score + ". The distance is: " + distance + " and the total population is: " + total_population);
			}
		}
	}

	local best_town_pair = list_pairs.PopMax();

	if(best_town_pair == null)
		return null;

	//AILog.Info("Best cities are: " + best_town_pair[0] + " and " + best_town_pair[1] + " with the score: " + best_town_pair[2]);
	return [ best_town_pair[0], best_town_pair[1] ];
}

function TownFinder::FindTwoTownsToConnectByRoad_CompareTownPairsByScore(a, b)
{
	if(a[2] > b[2]) 
		return 1
	else if(a[2] < b[2]) 
		return -1
	return 0;
}

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
	station_statistics = null; // array of pointers to StationStatistics objects for each station
	max_station_usage = null;

	long_time_mean_income = 0;
	
	last_bus_buy = null;
	last_bus_sell = null;


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
		cargo_type = null;
		date_built = null;
		last_vehicle_manage = null;
		town     = [];
		industry = [];
		node     = [];
		station  = [null, null];
		depot    = [null, null];
		last_station_manage = null;
		station_statistics = [];
		max_station_usage = 0;
		long_time_mean_income = 0;
		state_change_date = 0;
		this.SetState(Connection.STATE_BUILDING);
		last_bus_buy = null;
		last_bus_sell = null;
	}

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

	// Change order functions
	function FullLoadAtStations(enable_full_load);
	function StopInDepots(stop_in_depots);

	function SkipAllVehiclesToClosestDepot();

	function RepairRoadConnection();
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
			AIOrder.SetOrderFlags(veh_id, i_order, AIOrder.AIOF_NON_STOP_INTERMEDIATE | AIOrder.AIOF_SERVICE_IF_NEEDED);
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

	// Send all vehicles to depot for selling and set state STATE_CLOSING_DOWN
	this.SetState(Connection.STATE_CLOSING_DOWN);

	local vehicle_list = this.GetVehicles();
	if(vehicle_list.IsEmpty())
	{
		Log.Warning("CloseConnection fails because connection " + node[0].GetName() + " - " + node[1].GetName() + " do not have any vehicles.", Log.LVL_INFO);
		return false;
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
function Connection::EngineBuyScore(engine)
{
	// Use the product of speed and capacity
	return AIEngine.GetMaxSpeed(engine) * AIEngine.GetCapacity(engine);
}
function Connection::FindEngineModelToBuy()
{
	// find a bus model to buy
	local bus_list = AIEngineList(AIVehicle.VT_ROAD);

	// Get engines that can be refited to the wanted cargo
	bus_list.Valuate(AIEngine.CanRefitCargo, this.cargo_type)
	bus_list.KeepValue(1); 

	// Exclude articulated vehicles
	bus_list.Valuate(AIEngine.IsArticulated)
	bus_list.KeepValue(0); 

	// Exclude trams
	bus_list.Valuate(AIEngine.GetRoadType);
	bus_list.KeepValue(AIRoad.ROADTYPE_ROAD);

	// Exclude engines that can't be built
	bus_list.Valuate(AIEngine.IsBuildable)
	bus_list.KeepValue(1); 

	// Buy the vehicle with highest score
	bus_list.Valuate(Connection.EngineBuyScore)
	bus_list.KeepTop(1);

	return bus_list.IsEmpty()? -1 : bus_list.Begin();
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

				Log.Warning("Failed to build bus/truck", Log.LVL_INFO);
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
			AIOrder.AppendOrder(new_bus, depot[0], AIOrder.AIOF_SERVICE_IF_NEEDED);
			AIOrder.AppendOrder(new_bus, station[0], AIOrder.AIOF_NON_STOP_INTERMEDIATE); 
			AIOrder.AppendOrder(new_bus, depot[1], AIOrder.AIOF_SERVICE_IF_NEEDED);  
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

		AIVehicle.StartStopVehicle(new_buses[i]);
	}

	this.last_bus_buy = AIDate.GetCurrentDate();

	Log.Info("Built bus => return true", Log.LVL_DEBUG);
	return true;
}
function Connection::NumVehiclesToBuy(engine_id)
{
	local distance = GetTotalDistance().tofloat();
	local speed = AIEngine.GetMaxSpeed(engine_id);
	local travel_time = Engine.GetFullSpeedTraveltime(engine_id, distance);
	local capacity = AIEngine.GetCapacity(engine_id);

	if(this.IsTownOnly())
	{
		// Town only connections
		local population = GetTotalPoputaltion().tofloat();

		Log.Info("NumVehiclesToBuy(): distance between towns: " + distance, Log.LVL_SUB_DECISIONS);
		Log.Info("NumVehiclesToBuy(): total town population:  " + population, Log.LVL_SUB_DECISIONS);
		Log.Info("NumVehiclesToBuy(): capacity:  " + capacity + " cargo_type: " + cargo_type + " engine_id: " + engine_id, Log.LVL_SUB_DECISIONS);

		local num_bus = 1 + max(0, ((population - 200) / capacity / 15).tointeger());
		local extra = distance/capacity/3;
		num_bus += extra;
		Log.Info("NumVehiclesToBuy(): extra:  " + extra, Log.LVL_SUB_DECISIONS);

		num_bus = num_bus.tointeger();

		Log.Info("Buy " + num_bus + " vehicles", Log.LVL_SUB_DECISIONS);
		return num_bus;
	}
	else
	{
		// All other connections
		local max_cargo_available = Helper.Max(this.node[0].GetCargoAvailability(), this.node[1].GetCargoAvailability());
		local num_veh = (capacity * travel_time / 83).tointeger();

		Log.Info("Buy " + num_veh + " vehicles", Log.LVL_SUB_DECISIONS);
		return num_veh;
	}
}

function Connection::ManageState()
{
	Log.Info("Manage connection state - state: " + this.state + " - " + node[0].GetName() + " - " + node[1].GetName(), Log.LVL_INFO);

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

			Log.Info("Connection do no longer has at least one producer-accepter pair -> close it down", Log.LVL_DEBUG);
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
					this.SuspendConnection();
				}
				else if(zero_raw_production)
				{
					// Only raw industries -> No hope for increased production again
					this.CloseConnection();
				}
			}
		}
	}
	else if(this.state == Connection.STATE_SUSPENDED)
	{
		local now = AIDate.GetCurrentDate();
		local suspended_time = now - this.state_change_date;

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
				local station_id = AIStation.GetStationID(station_tile);

				// Remember the front tiles for later road removal 
				front_tiles.AddList(Station.GetRoadFrontTiles(station_id));

				// Demolish station
				Station.DemolishStation(station_id);
			}

			// Demolish depots
			foreach(depot in this.depot)
			{
				local front = AIRoad.GetRoadDepotFrontTile(depot);

				// Remember the front tile for later road removal
				front_tiles.AddItem(front, 0);

				// Demolish depot
				AITile.DemolishTile(depot);
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

	Log.Info("Manage Stations", Log.LVL_INFO);

	// Update station statistics
	local max_usage = 0;

	for(local i = 0; i < this.station.len(); ++i)
	{
		local station_tile = this.station[i];
		local station_statistics = this.station_statistics[i];

		station_statistics.ReadStatisticsData();

		local usage = Helper.Max(station_statistics.usage.bus.percent_usage, station_statistics.usage.truck.percent_usage);
		if(usage > max_usage)
			max_usage = usage;
	}

	this.max_station_usage = max_usage;

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
								this.station[town_id] = AIBaseStation.GetLocation(station_id);
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

		Log.Info("Checking if connection " + node[0].GetName() + " - " + node[1].GetName() + " needs more bus stops", Log.LVL_INFO);
		Log.Info("bus usage: " + percent_usage[0] + ", " + percent_usage[0], Log.LVL_SUB_DECISIONS);
		Log.Info("pax waiting: " + station_statistics[0].cargo_waiting + ", " + station_statistics[1].cargo_waiting, Log.LVL_SUB_DECISIONS);

		// look for connections that need additional bus stops added
		if( (percent_usage[0] > 150 && station_statistics[0].cargo_waiting > 150) ||
			(percent_usage[0] > 250) ||
			(percent_usage[1] > 150 && station_statistics[1].cargo_waiting > 150) ||
			(percent_usage[1] > 250))
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
	
				if(this.clueless_instance.GrowStation(station_id, station_type))
				{
					Log.Info("Station has been grown with one bus stop", Log.LVL_INFO);

					// Change the usage so that it is percent of new capacity, so that the AI don't quickly add another bus stop before the
					// statistics adopt to the new capacity.
					local old_size = existing_stop_tiles.Count();
					local new_size = old_size + 1;
					local new_usage = (percent_usage[town_i] * old_size) / new_size;
					Log.Info("old usage = " + percent_usage[town_i] + "  new usage = " + new_usage, Log.LVL_SUB_DECISIONS);

					if(station_type == AIStation.STATION_BUS_STOP)
						this.station_statistics[town_i].usage.bus.percent_usage = new_usage;
					if(station_type == AIStation.STATION_TRUCK_STOP)
						this.station_statistics[town_i].usage.bus.percent_usage = new_usage;

					this.station_statistics[town_i].ReadStatisticsData();
				}

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

	local now = AIDate.GetCurrentDate();
	if( ((last_vehicle_manage == null && AIDate.GetYear(now) > AIDate.GetYear(date_built)) || 		   // make first manage the year after it was built
			(last_vehicle_manage != null && last_vehicle_manage + AIDate.GetDate(0, 3, 0) < now )) &&  // and then every 3 months
			AIDate.GetMonth(now) > 2)  // but don't make any management on the first two months of the year
	{
		last_vehicle_manage = now;

		Log.Info("Connection::ManageVehicles time to manage vehicles for connection " + this.node[0].GetName() + " - " + this.node[1].GetName(), Log.LVL_INFO);
		Helper.SetSign(this.station[0] + 1, "manage");
		Helper.SetSign(this.station[1] + 1, "manage");

		AICompany.SetLoanAmount(AICompany.GetMaxLoanAmount());
		// wait one year before first manage, and then every year

		local income = 0;
		local num_income = 0;
		local veh_list = AIList();

		local connection_vehicles = GetVehicles();
		local veh = null;
		for(veh = connection_vehicles.Begin(); connection_vehicles.HasNext(); veh = connection_vehicles.Next())
		{
			// If the vehicle is to old => sell it. Otherwise if the vehicle is kept, include it in the income checking.
			if(AIVehicle.GetAge(veh) > AIVehicle.GetMaxAge(veh) - 365 * 2)
			{
				AIVehicle.SetName(veh, "old -> sell");
				SendVehicleForSelling(veh);
			}
			else
			{
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
		Log.Info("connection max usage: " + this.max_station_usage, Log.LVL_INFO);

		if(mean_income < 30 ||
			(long_time_mean_income > 0 && income < (long_time_mean_income / 2)) ||
					(long_time_mean_income <= 0 && income < (long_time_mean_income * 2) / 3))
		{
			// Repair the connection if it is broken
			RepairRoadConnection();
		}

		long_time_mean_income = (long_time_mean_income * 9 + income) / 10;

		// Unless the vehicle list is empty, only buy/sell if we have not bought/sold anything the last 30 days.
		local recently_sold = last_bus_sell != null && last_bus_sell + 30 > now;
		local recently_bought = last_bus_buy != null && last_bus_buy + 30 > now;
		if( veh_list.Count() == 0 ||
				(!recently_sold && !recently_bought) )
		{
			if( (income < 0 || this.max_station_usage > 200 || max_waiting < 10) && veh_list.Count() > 1)
			{
				local num_to_sell = Helper.Max(1, veh_list.Count() / 8);
				
				if(income < 0)
				{
					local engine_type_id = AIVehicle.GetEngineType(veh_list.Begin());
					local running_cost = AIEngine.GetRunningCost(engine_type_id);
					num_to_sell = Helper.Min(veh_list.Count() - 1, (-income) / running_cost + 1);
				}
				else if(this.max_station_usage > 200)
				{
					num_to_sell = Helper.Max(1, veh_list.Count() / 6);
				}


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

					Log.Info("Manage vehicles decided to Sell one bus", Log.LVL_INFO);
					SendVehicleForSelling(veh_to_sell);

					// Remove the sold vehicle from the list of vehicles in the connection
					veh_list.Valuate(Helper.ItemValuator);
					veh_list.RemoveValue(veh_to_sell);
				}
			}
			else 
			{
				if(veh_list.Count() == 0 || 
					(this.max_station_usage < 170 && max_waiting > 40 + veh_list.Count() * 3) )
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
	Log.Info("Send vehicle " + AIVehicle.GetName(vehicle_id) + " for selling", Log.LVL_INFO);

	ClueHelper.StoreInVehicleName(vehicle_id, "sell");

	// Unshare & clear orders
	AIOrder.UnshareOrders(vehicle_id);
	while(AIOrder.GetOrderCount(vehicle_id) > 0)
	{
		AIOrder.RemoveOrder(vehicle_id, 0);
	}

	// Send vehicle to specific depot so it don't get lost
	if(!AIOrder.AppendOrder(vehicle_id, depot[0], AIOrder.AIOF_STOP_IN_DEPOT))
	{
		Log.Error(AIError.GetLastErrorString(), Log.LVL_INFO);
		KABOOOOOM_Failed_to_append_order // crash if sending vehicle to depot fails
	}

	// Add an extra order so we can skip between the orders to fully make sure vehicles leave
	// stations they previously were full loading at.
	AIOrder.AppendOrder(vehicle_id, depot[0], AIOrder.AIOF_STOP_IN_DEPOT);

	// so that vehicles that load stuff departures
	AIOrder.SkipToOrder(vehicle_id, 1); 
	AIOrder.SkipToOrder(vehicle_id, 0); 

	// Remove the second now unneccesary order
	AIOrder.RemoveOrder(vehicle_id, 1);

	// Turn around road vehicles that stand still, possible in queues.
	if(AIVehicle.GetVehicleType(vehicle_id) == AIVehicle.VT_ROAD)
	{
		// max 20% of maximum speed
		if(AIVehicle.GetCurrentSpeed(vehicle_id) < AIEngine.GetMaxSpeed(AIVehicle.GetEngineType(vehicle_id)) * 5 / 4)
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

						foreach(at_station_veh in vehicle_list)
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
				AIOrder.SetOrderFlags(veh_id, i_order, AIOrder.AIOF_NON_STOP_INTERMEDIATE | AIOrder.AIOF_SERVICE_IF_NEEDED);
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
	local repair = true;
	local connect_result = clueless_instance.ConnectByRoad(front1, front2, repair, 50000) == RoadBuilder.CONNECT_SUCCEEDED;
	connect_result = connect_result && clueless_instance.ConnectByRoad(front2, front1, repair, 50000) == RoadBuilder.CONNECT_SUCCEEDED; // also make sure the connection works in the reverse direction

	if(!connect_result)
	{
		// retry but without higher penalty for constructing new road
		Log.Warning("Failed to repair route -> try again but without high penalty for building new road", Log.LVL_INFO);
		repair = false;
		connect_result = clueless_instance.ConnectByRoad(front1, front2, repair, 100000) == RoadBuilder.CONNECT_SUCCEEDED;
		connect_result = connect_result && clueless_instance.ConnectByRoad(front2, front1, repair, 100000) == RoadBuilder.CONNECT_SUCCEEDED; // also make sure the connection works in the reverse direction
	}

	if(!connect_result)
	{
		Log.Error("Failed to repair broken route", Log.LVL_INFO);
	}

	clueless_instance.ManageLoan();

	return connect_result;
}

//////////////////////////////////////////////////////////////////////

function GetVehiclesWithoutOrders()
{
	local empty_orders = AIVehicleList();
	empty_orders.Valuate(AIOrder.GetOrderCount);
	empty_orders.KeepValue(0);
	return empty_orders;
}

//////////////////////////////////////////////////////////////////////
//                                                                  //
//  CLASS: CluelessPlus - the AI main class                         //
//                                                                  //
//////////////////////////////////////////////////////////////////////
class CluelessPlus extends AIController {
	stop     = false;

	loaded_from_save = false;

	town_finder = null;
	pair_finder = null;
	road_builder = null;
	connection_list = [];

	detected_rail_crossings = null;

	state_build = false;
	state_ai_name = null;
	state_desperateness = 0;

	conf_ai_name = null
	conf_min_balance = 0;



	// All variables should be initiated with their values below!:  (the assigned values above is only there because Squirrel demands it)
	constructor() {
		stop = false;
		loaded_from_save = false;
		town_finder = TownFinder();
		pair_finder = PairFinder();
		road_builder = RoadBuilder();
		connection_list = [];

		detected_rail_crossings = AIList();

		state_build = false;
		state_ai_name = null;
		state_desperateness = 0;

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
	function ConnectPair();

	function Save();
	function Load(version, data);
	function ReadConnectionsFromMap(); // Instead of storing data in the save game, the connections are made out from groups of vehicles that share orders.

	function SetCompanyName(nameArray);

	function ManageLoan();
	function RoundLoanDown(loanAmount); // Helper
	function GetMaxMoney();

	function BuildServiceInTown();
	function BuildStopInTown(town);
	function BuildStopForIndustry(industry_id, cargo_id);
	function BuyConnectionVehicles(connection); 
	// if tile is not a road-tile it will search for closest road-tile and then start searching for a location to place it from there.
	function BuildBusStopNextToRoad(tile, min_loops, max_loops); 
	function BuildTruckStopNextToRoad(tile, min_loops, max_loops); 
	function BuildDepotNextToRoad(tile, min_loops, max_loops); 
	function BuildNextToRoad(tile, what, min_loops, max_loops);  // 'what' can be any of: "BUS_STOP", "TRUCK_STOP", "DEPOT". ('what' should be a string)
	function GrowStation(station_id, station_type);

	function PlaceHQ(nearby_tile);

	function FindClosestRoadTile(tile, max_loops);

	function ConnectByRoad(tile1, tile2, repair = false, max_loops = -1);
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

	Log.Info("", Log.LVL_INFO);

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

	if(AIGameSettings.IsDisabledVehicleType(AIVehicle.VT_ROAD))
	{
		Log.Error("Road transport mode is disabled for AIs. This AI is road-only.", Log.LVL_INFO);
		Log.Info("Enable road transport mode in advanced settings if you want that this AI should build something", Log.LVL_INFO);
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

			// ... check if we can afford to build some stuff
			if(this.GetMaxMoney() > 95000 && !AIGameSettings.IsDisabledVehicleType(AIVehicle.VT_ROAD))
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
				Log.Info("Look for buses to sell / send to depot for selling", Log.LVL_SUB_DECISIONS);

				// check if there are any vehicles to sell
				local to_sell_in_depot = AIVehicleList();
				to_sell_in_depot.Valuate(AIVehicle.IsStoppedInDepot);
				to_sell_in_depot.KeepValue(1);
				Log.Info("num vehicles stopped in depot: " + to_sell_in_depot.Count(), Log.LVL_SUB_DECISIONS);
				for(local i = to_sell_in_depot.Begin(); to_sell_in_depot.HasNext(); i = to_sell_in_depot.Next())
				{
					local veh_state = ClueHelper.ReadStrFromVehicleName(i);

					// Don't sell suspended / active vehicles
					if(veh_state == "suspended" || veh_state == "active")
						continue;


					Log.Info("Sell vehicle " + i + ": " + AIVehicle.GetName(i) + " (state: " + veh_state + ")", Log.LVL_SUB_DECISIONS);
					if(!AIVehicle.SellVehicle(i)) // sell
						Log.Info("Failed to sell vehicle " + AIVehicle.GetName(i) + " in depot - Error string: " + AIError.GetLastErrorString(), Log.LVL_INFO);
				}

				// check if there are any vehicles without orders that don't tries to find a depot
				// the new selling code adds a depot order, but there may exist vehicles without orders roaming around for other reasons
				local to_send_to_depot = GetVehiclesWithoutOrders();
				Log.Info("num vehicles without orders: " + to_send_to_depot.Count(), Log.LVL_DEBUG);
				to_send_to_depot.Valuate(AIOrder.IsGotoDepotOrder, AIOrder.ORDER_CURRENT);
				to_send_to_depot.KeepValue(0);
				Log.Info("num vehicles does not go to depot: " + to_send_to_depot.Count(), Log.LVL_DEBUG);
				for(local i = to_send_to_depot.Begin(); to_send_to_depot.HasNext(); i = to_send_to_depot.Next())
				{
					Log.Info("Send vehicle " + AIVehicle.GetName(i) + " to depot", Log.LVL_SUB_DECISIONS);
					//AIVehicle.SendVehicleToDepot(i); // send to depot
				}


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
			foreach(conn in connection_list)
			{
				if(conn.station_statistics.len() == 0)
					continue;
				
				// look for connections that could have mail service added
				// TODO

			}

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
			Log.Info("Vehicle lost event detected", Log.LVL_INFO);
			local lost_event = AIEventVehicleLost.Convert(ev);
			local lost_veh = lost_event.GetVehicleID();

			local connection = ReadConnectionFromVehicle(lost_veh);
			
			if(connection != null && connection.station.len() >= 2 && connection.state == Connection.STATE_ACTIVE)
			{
				Log.Info("Try to connect the stations again", Log.LVL_SUB_DECISIONS);

				if(!connection.RepairRoadConnection())
					SellVehicle(lost_veh);
			}
			else
			{
				SellVehicle(lost_veh);
			}
			
		}
		if(ev_type == AIEvent.AI_ET_VEHICLE_CRASHED)
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
	}
}

function CluelessPlus::ConnectPair()
{
	// scan for two pairs to connect
	local pair = this.pair_finder.FindTwoNodesToConnect(100 + 20 * state_desperateness, state_desperateness, connection_list);

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
			station_tile = BuildStopInTown(node.town_id, road_veh_type);

			if (station_tile != null)
				depot_tile = BuildDepotNextToRoad(station_tile, 0, 100);
			else
				Log.Warning("failed to build bus/truck stop in town " + AITown.GetName(node.town_id), Log.LVL_INFO);
		}
		else
		{
			station_tile = BuildStopForIndustry(node.industry_id, node.cargo_id);
			if (!AIStation.IsValidStation(AIStation.GetStationID(station_tile))) // for compatibility with the old code, turn -1 into null
				station_tile = null;
			
			if (station_tile != null)
				depot_tile = BuildDepotNextToRoad(station_tile, 0, 100); // TODO, for industries there is only a road stump so chances are high that this fails
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
		ClueHelper.StoreInStationName(AIStation.GetStationID(road_stop[0]), pair[0].SaveToString());

		Log.Info("assign name to " + AIStation.GetName(AIStation.GetStationID(road_stop[1])), Log.LVL_DEBUG);
		ClueHelper.StoreInStationName(AIStation.GetStationID(road_stop[1]), pair[1].SaveToString());
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
				connected = connected && ConnectByRoad(depot_front_tile, station_front_tile, repair, 5000) == RoadBuilder.CONNECT_SUCCEEDED; // -> start construct it from the station
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
			local con_ret = ConnectByRoad(from, to, repair, 500);
			if(con_ret == RoadBuilder.CONNECT_FAILED_TIME_OUT) // no error was found path finding a litle bit from one end
				con_ret = ConnectByRoad(to, from, repair, 100000);

			connected = con_ret == RoadBuilder.CONNECT_SUCCEEDED;
		}
	}


	// Only buy buses if we actually did connect the two cities.
	if(connected && !failed)
	{	
		Log.Info("connected by road", Log.LVL_INFO);
		// BuyConnectionVehicles save the IDs of the bough buses in the connection data-structure
		BuyConnectionVehicles(connection); 
		connection.FullLoadAtStations(true); // TODO
		Log.Info("bough buses", Log.LVL_INFO);

		connection.state = Connection.STATE_ACTIVE;	// construction did not fail -> active connection
	}
	else
	{
		Log.Warning("failed to connect by road", Log.LVL_INFO);

		for(local i = 0; i < 2; i++)
		{
			if(connection.depot[i])
			{
				local front = AIRoad.GetRoadDepotFrontTile(connection.depot[i]);
				AITile.DemolishTile(connection.depot[i]);
				AIRoad.RemoveRoad(front, connection.depot[i]);
			}

			if(connection.station[i])
			{
				local station_id = AIStation.GetStationID(connection.station[i]);
				Station.DemolishStation(station_id);
			}
		}

		connection.state = Connection.STATE_FAILED;			// store that this connection faild so we don't waste our money on buying buses for it.
		state_desperateness++;
	}

	// Store the connection so we don't build it again.
	connection.date_built = AIDate.GetCurrentDate();
	connection_list.append(connection); 

	// If we succeed to build the connection, revert to zero desperateness
	if(!failed && connected)
		state_desperateness = 0;

	return !failed && connected;
}

function CluelessPlus::GrowStation(station_id, station_type)
{
	if(!AIStation.IsValidStation(station_id))
	{
		Log.Error("GrowStation: Can't grow invalid station", Log.LVL_INFO);
		return false;
	}

	local existing_stop_tiles = AITileList_StationType(station_id, station_type);
	local grow_max_distance = Helper.Clamp(7, 0, AIGameSettings.GetValue("station_spread") - 1);

	Helper.SetSign(AIBaseStation.GetLocation(station_id) - 1, "grow");

	// AIRoad.BuildStation wants another type of enum constant to decide if bus/truck should be built
	local road_veh_type = 0;
	if(station_type == AIStation.STATION_BUS_STOP)
		road_veh_type = AIRoad.ROADVEHTYPE_BUS;
	else if(station_type == AIStation.STATION_TRUCK_STOP)
		road_veh_type = AIRoad.ROADVEHTYPE_TRUCK;
	else
		KABOOOOOOOM_UNSUPPORTED_STATION_TYPE = 0;

	local potential_tiles = AITileList();

	for(local stop_tile = existing_stop_tiles.Begin(); existing_stop_tiles.HasNext(); stop_tile = existing_stop_tiles.Next())
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

	potential_tiles.Valuate(AIMap.DistanceManhattan, existing_stop_tiles.Begin());
	potential_tiles.Sort(AIAbstractList.SORT_BY_VALUE, true); // lowest value first

	for(local try_tile = potential_tiles.Begin(); potential_tiles.HasNext(); try_tile = potential_tiles.Next())
	{
		local neighbours = Tile.GetNeighbours4MainDir(try_tile);

		neighbours.Valuate(AIRoad.IsRoadTile);
		neighbours.KeepValue(1);

		for(local road_tile = neighbours.Begin(); neighbours.HasNext(); road_tile = neighbours.Next())
		{
			if( (AIRoad.AreRoadTilesConnected(try_tile, road_tile) || ClueHelper.CanConnectToRoad(road_tile, try_tile)) &&
					AITile.GetMaxHeight(try_tile) == AITile.GetMaxHeight(road_tile) )
			{
				if(AIRoad.BuildRoadStation(try_tile, road_tile, road_veh_type, station_id))
				{
					// Make sure the new station part is connected with one of the existing parts (which is in turn should be
					// connected with all other existing parts)
					local repair = false;
					if(this.ConnectByRoad(try_tile, AIRoad.GetRoadStationFrontTile(existing_stop_tiles.Begin()), repair, 10000) != RoadBuilder.CONNECT_SUCCEEDED)
					{
						AIRoad.RemoveRoadStation(try_tile);
						return false;
					}

					local i = 0;
					while(!AIRoad.AreRoadTilesConnected(try_tile, road_tile) && !AIRoad.BuildRoad(try_tile, road_tile))
					{
						// Try a few times to build the road if a vehicle is in the way
						if(i++ == 10) return false;

						local last_error = AIError.GetLastError();
						if(last_error != AIError.ERR_VEHICLE_IN_THE_WAY) return false;

						AIController.Sleep(5);
					}

					return true;
				}
			}
		}
	}
	
	return false;
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

		Log.Info("Connection " + AIStation.GetName(AIStation.GetStationID(connection.station[0])) + " - " + AIStation.GetName(AIStation.GetStationID(connection.station[1])) + " added to connection list", Log.LVL_INFO);

		foreach(station_tile in connection.station)
		{
			// remove station from unused stations list
			local station_id = AIStation.GetStationID(station_tile);
			unused_stations.RemoveValue(station_id);
		}
	}

	// Destroy all unused stations so they don't cost money
	for(local station_id = unused_stations.Begin(); unused_stations.HasNext(); station_id = unused_stations.Next())
	{
		Log.Warning("Station " + AIStation.GetName(station_id) + " is unused and will be removed", Log.LVL_INFO);

		Station.DemolishStation(station_id);
	}
}

function CluelessPlus::ReadConnectionFromVehicle(vehId)
{
	local connection = Connection(this);
	connection.cargo_type = ClueHelper.GetVehicleCargoType(vehId);

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
		Log.Info(AIStation.GetName(station_id) + " " + save_str, Log.LVL_INFO);
		local node = Node.CreateFromSaveString(save_str);

		if(node == null)
		{
			// Old CluelessPlus and/or loading from other AI
			local town_id = AITile.GetClosestTown(station_tile);
			local industry_id = -1;
			local cargo_id = Helper.GetPAXCargo(); //AIEngine.GetCargoType(AIVehicle.GetVehicleType(vehId));
			
			if(AIEngine.GetCargoType(AIVehicle.GetEngineType(vehId)) != cargo_id)
			{
				Log.Info("connection with non-pax detected", Log.LVL_INFO);
				return null; // The vehicle transports non-pax
			}

			local stop_tiles_for_veh = AITileList_StationType(station_id, AIRoad.GetRoadVehicleTypeForCargo(cargo_id));
			if(stop_tiles_for_veh.IsEmpty())
			{
				return null; // There is no bus stops at the station
			}

			node = Node(town_id, industry_id, cargo_id);
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

	// Detect broken connections
	if(connection.depot.len() != 2 || connection.station.len() != 2 || connection.town.len() != 2)
		connection.state = Connection.STATE_FAILED;

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

function CluelessPlus::BuildStopInTown(town, road_veh_type) // this function is ugly and should ideally be removed
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

	return BuildNextToRoad(location, what, 50, 100 + AITown.GetPopulation(town) / 70, 1);

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
	local dir_list = AIList();
	for(local dir = Direction.DIR_FIRST; dir != Direction.DIR_LAST + 1; dir++)
	{
		if(!Direction.IsMainDir(dir))
			continue;

		dir_list.AddItem(dir, 0);
	}
	dir_list.Valuate(AIBase.RandItem);
	dir_list.Sort(AIAbstractList.SORT_BY_VALUE, AIAbstractList.SORT_DESCENDING);

	// Loop through the remaining tiles and see where we can put down a stop and a road infront of it
	foreach(tile, _ in tile_list)
	{
		Helper.SetSign(tile, "ind stn");

		// Go through all dirs and try to build in all directions until one succeeds
		foreach(dir, _ in dir_list)
		{
			local front_tile = Direction.GetAdjacentTileInDirection(tile, dir);

			if(!Tile.IsBuildOnSlope_FlatInDirection(front_tile, dir)) // Only allow the front tile road to be flat
				continue;

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
	return BuildNextToRoad(tile, "BUS_STOP", min_loops, max_loops, 1);
}
function CluelessPlus::BuildTruckStopNextToRoad(tile, min_loops, max_loops)
{
	return BuildNextToRoad(tile, "TRUCK_STOP", min_loops, max_loops, 1);
}
function CluelessPlus::BuildDepotNextToRoad(tile, min_loops, max_loops)
{
	return BuildNextToRoad(tile, "DEPOT", min_loops, max_loops, 1);
}
function CluelessPlus::BuildNextToRoad(tile, what, min_loops, max_loops, try_number)
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

	local adjacent_loop = [ [-1,0], [1,0], [0,-1], [0,1] ];

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

			foreach(adjacent_offset in adjacent_loop)
			{
				adjacent_x = curr_x + adjacent_offset[0];
				adjacent_y = curr_y + adjacent_offset[1];

				adjacent_tile = AIMap.GetTileIndex(adjacent_x, adjacent_y);

				if(!AIMap.IsValidTile(adjacent_tile))
				{
					Log.Warning("Adjacent tile is not valid", Log.LVL_INFO);
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
			return BuildNextToRoad(tile, what, min_loops, max_loops, try_number+1);
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

	// TODO: Use ScoreList instead of a plain array.
	local extend_list = []; // each item is an array: [tile, MH distance to target]

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
					extend_list.append( [ curr_tile, AIMap.DistanceManhattan(curr_tile, target_tile) ] );
				}
			}

			if(AIController.GetSetting("slow_ai") == 1)
				this.Sleep(5);
			else
				this.Sleep(1);
		}

		// stop loop if at least one solution found and i > min_loops
		if(extend_list.len() > 0 && i > min_loops)
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

	if(extend_list.len() == 0)
	{
		Log.Info("CluelessPlus::FindRoadExtensionTile: found zero solutions", Log.LVL_INFO);
		return null;
	}
	else if(extend_list.len() == 1)
		return extend_list[0][0];
	else
	{
		extend_list.sort(FindRoadExtensionTile_SortByDistanceToTarget);
		return extend_list[0][0];
	}

	return null;
}
function CluelessPlus::FindRoadExtensionTile_SortByDistanceToTarget(a, b)
{
	if(a[1] > b[1]) 
		return 1
	else if(a[1] < b[1]) 
		return -1
	return 0;
}

function CluelessPlus::ConnectByRoad(tile1, tile2, repair = false, max_loops = 1000)
{
	return RoadBuilder.ConnectTiles(tile1, tile2, 1, repair, max_loops);

	// As of version 16 of CluelessPlus the old path finder was removed. If anyone is interested in a bad pathfinder then check out this place
	// in the old <= version 15 sources. ;-)
}

function CluelessPlus::BuyConnectionVehicles(connection)
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
	for(local hq_tile = tiles.Begin(); tiles.HasNext(); hq_tile = tiles.Next())
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
	for(local hq_tile = possible_tiles.Begin(); possible_tiles.HasNext(); hq_tile = possible_tiles.Next())
	{
		if(AICompany.BuildCompanyHQ(hq_tile))
		{
			Log.Info("The HQ was built, so that our clueless paper pushers have somewhere to sit. ;-)", Log.LVL_INFO);

			if(AIController.GetSetting("slow_ai") == 1)
			{
				Log.Info("The AI is so happy with the new HQ so it can't think about anything else for a while..", Log.LVL_INFO);
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
