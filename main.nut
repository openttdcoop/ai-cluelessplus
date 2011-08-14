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

// Import SuperLib
import("util.superlib", "SuperLib", 11);

Result <- SuperLib.Result;
Log <- SuperLib.Log;
Helper <- SuperLib.Helper;
ScoreList <- SuperLib.ScoreList;
Money <- SuperLib.Money;

Tile <- SuperLib.Tile;
Direction <- SuperLib.Direction;

Engine <- SuperLib.Engine;
Vehicle <- SuperLib.Vehicle;

Station <- SuperLib.Station;
Airport <- SuperLib.Airport;
Industry <- SuperLib.Industry;
Town <- SuperLib.Town;

Order <- SuperLib.Order;
OrderList <- SuperLib.OrderList;

Road <- SuperLib.Road;
RoadBuilder <- SuperLib.RoadBuilder;

// Import other libraries
import("queue.fibonacci_heap", "FibonacciHeap", 2);

// Import all CluelessPlus files
require("pairfinder.nut"); 
require("clue_helper.nut");
require("stationstatistics.nut");
require("strategy.nut");
require("transport_mode_stats.nut");
require("connection.nut");
require("timer.nut");


STATION_SAVE_VERSION <- "0";
STATION_SAVE_AIRCRAFT_DUMP <- "Air Service";
MIN_VEHICLES_TO_BUILD_NEW <- 5; // minimum number of vehicles left in order to allow building new connections for a given transport mode

// Airport where aircrafts are "dumped" while airports are upgraded
g_aircraft_dump_airport_small <- null;
g_aircraft_dump_airport_large <- null;

g_num_connection_airport_upgrade <- 0;

//////////////////////////////////////////////////////////////////////

g_timers <- { 
		manage_vehicles = Timer("manage vehicles"),
		manage_stations = Timer("manage stations"),
		manage_state = Timer("manage state"),
		all_manage = Timer("all manage"),
		build_check = Timer("build check"),
		state_build = Timer("state build"),
		build_pathfinding = Timer("build - pathfinding"),
		build_buildroad = Timer("build - buildroad"),
		build_infra_connect = Timer("build - infra connect"),
		build_buy_vehicles = Timer("build - vehicles"),
		build_stations = Timer("build - stations"),
		build_performance = Timer("build - calc performance"),
		build_abort = Timer("abort building connection"),
		repair_connection = Timer("repair connection"),
		rail_crossings = Timer("rail crossings"),
		scan_depots = Timer("scan depots"),
		pairfinding = Timer("pair finding"),
		connect_pair = Timer("connect pair"),
		handle_events = Timer("handle events"),
		manage_loan = Timer("manage loan"),
		all = Timer("all"),
	};

// table_name is eg. build_check which is a key in the g_timers table
function TimerStart(table_name)
{
	if(AIController.GetSetting("enable_timers") == 1)
	{
		g_timers.rawget(table_name).Start();
	}
}

function TimerStop(table_name)
{
	if(AIController.GetSetting("enable_timers") == 1)
	{
		g_timers.rawget(table_name).Stop();
	}
}


//////////////////////////////////////////////////////////////////////

function GetAvailableTransportModes(min_vehicles_left = 1)
{
	local tm_list = [];
	if(Vehicle.GetVehiclesLeft(AIVehicle.VT_AIR) >= min_vehicles_left)
		tm_list.append(TM_AIR);
	if(Vehicle.GetVehiclesLeft(AIVehicle.VT_ROAD) >= min_vehicles_left)
		tm_list.append(TM_ROAD);

	return tm_list;
}

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
	local order_dest = Order.GetCurrentOrderDestination(vehicleId);
	switch(AIVehicle.GetVehicleType(vehicleId))
	{
		case AIVehicle.VT_ROAD:
			return AIRoad.IsRoadDepotTile(order_dest);

		case AIVehicle.VT_AIR:
			return AIAirport.IsHangarTile(order_dest);

		case AIVehicle.VT_RAIL:
			return AIRail.IsRailDepotTile(order_dest);

		case AIVehicle.VT_WATER:
			return AIMarine.IsWaterDepotTile(order_dest);
	}

	Log.Error("Invalid vehicle type of vehicle " + AIVehicle.GetName(vehicleId) + " (IsVehicleGoingToADepot)", Log.LVL_INFO);
	return false;
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

function AnyVehicleTypeBuildable()
{
	local vt_available = false;
	foreach(vt in [AIVehicle.VT_ROAD, AIVehicle.VT_AIR])
	{
		vt_available = vt_available || Vehicle.GetVehicleLimit(vt);
	}

	return vt_available;
}

// if avoid_small_airports is true, the result will only contain small airports
// if there are no large ones.
function GetAirportTypeList_AllowedAndBuildable(avoid_small_airports = false)
{
	local airport_type_list = Airport.GetAirportTypeList(); // Todo: refine airport type selection
	airport_type_list.Valuate(AIAirport.IsValidAirportType); // can airport be built?
	airport_type_list.KeepValue(1);
	//airport_type_list.Valuate(AIAirport.GetNumHangars); // for some reason this don't remove the heliport
	//airport_type_list.RemoveValue(0);
	airport_type_list.RemoveItem(AIAirport.AT_HELIPORT);
	airport_type_list.RemoveItem(AIAirport.AT_HELISTATION);
	airport_type_list.RemoveItem(AIAirport.AT_HELIDEPOT);
	airport_type_list.RemoveItem(AIAirport.AT_INTERCON); // the intercon has worse performance than international and is larger

	if(avoid_small_airports)
	{
		local skip_small = false;
		foreach(ap_type in airport_type_list)
		{
			if(!Airport.IsSmallAirportType(ap_type))
			{
				skip_small = true;
				break;
			}
		}
		if(skip_small)
		{
			airport_type_list.Valuate(Airport.IsSmallAirportType);
			airport_type_list.KeepValue(0);
		}
	}

	airport_type_list.Valuate(Helper.ItemValuator);
	return airport_type_list;
}

function IsAirportTypeBetterThan(ap_type, other_ap_type)
{
	return ap_type > other_ap_type;
}

function IsAircraftDumpStation(station_id)
{
	local save_str = ClueHelper.ReadStrFromStationName(station_id);
	local space = save_str.find(" ");
	local save_version = -1;
	local node_save_str = null;
	if(space == null)
		return false;
	save_version = save_str.slice(0, space);
	node_save_str = save_str.slice(space + 1);
	return node_save_str == STATION_SAVE_AIRCRAFT_DUMP;
}

function IsGoToAircraftDumpOrder(vehicle_id, order_id)
{
	local dest = AIOrder.GetOrderDestination(vehicle_id, order_id);
	local station_id = AIStation.GetStationID(dest);
	return IsAircraftDumpStation(station_id);
}

function HasVehicleGoToAircraftDumpOrder(vehicle_id)
{
	for(local i = 0; i < AIOrder.GetOrderCount(vehicle_id); ++i)
	{
		if(IsGoToAircraftDumpOrder(vehicle_id, i))
			return true;
	}

	return false;
}

function GetNoiseBudgetOverrun()
{
	return AIGameSettings.GetValue("station_noise_level") == 1? 2 : 0; // allow airports to go at maximum 2 over noise budget, to allow for new airports to be placed further away. 
}


/*
 * Will return a station id of an airport that has no other purpose
 * than holding aircrafts while upgrading other airports
 *
 * need_large_airport = true or false
 */
function GetAircraftDumpAirport(need_large_airport)
{
	// if have large, give large
	if(g_aircraft_dump_airport_large != null && AIStation.IsValidStation(g_aircraft_dump_airport_large))
		return g_aircraft_dump_airport_large;

	// if have small and small is enough, give small
	if(!need_large_airport && g_aircraft_dump_airport_small != null && AIStation.IsValidStation(g_aircraft_dump_airport_small))
		return g_aircraft_dump_airport_small;


	// we don't have a dump airport
	local avoid_small = need_large_airport;
	local airport_type_list = GetAirportTypeList_AllowedAndBuildable(avoid_small);

	// Use a small airport if possible (no large is needed and a small is available)
	if(!need_large_airport)
	{
		airport_type_list.Valuate(Airport.IsSmallAirportType);
		if(Helper.GetListMinValue(airport_type_list) == 0) // have small airport?
		{
			airport_type_list.KeepValue(0); // keep only small airports
		}
	}

	// pick cheapest airport that is fulfills the requirements
	airport_type_list.Valuate(AIAirport.GetPrice); 
	airport_type_list.Sort(AIList.SORT_BY_VALUE, AIList.SORT_ASCENDING);

	local selected_type = airport_type_list.Begin();

	// Build airport in HQ-town if possible, else in the smallest town
	local hq_tile = AICompany.GetCompanyHQ(AICompany.COMPANY_SELF);
	local town = null;
	local town_list = AITownList();
	if(AIMap.IsValidTile(hq_tile))
	{
		town = AITile.GetClosestTown(hq_tile);
	}
	else
	{
		town_list.Valuate(AITown.GetPopulation);
		town_list.Sort(AIList.SORT_BY_VALUE, AIList.SORT_ASCENDING);

		town = town_list.Begin();
		town_list.RemoveTop(1);
	}

	local no_cargo = -1;
	local ap_tile = Airport.BuildAirportInTown(town, selected_type, no_cargo, no_cargo);
	if(ap_tile == null)
	{
		// Fall back to iterating town list if HQ / smallest town failed
		foreach(town in town_list)
		{
			ap_tile = Airport.BuildAirportInTown(town, selected_type, no_cargo, no_cargo);
			if(ap_tile != null)
				break;

			if(AIError.GetLastError() == AIError.ERR_NOT_ENOUGH_CASH)
				break;
		}
	}

	if(ap_tile != null)
	{
		local station_id = AIStation.GetStationID(ap_tile);
		if(Airport.IsSmallAirportType(selected_type))
			g_aircraft_dump_airport_small = station_id;
		else
			g_aircraft_dump_airport_large = station_id;

		ClueHelper.StoreInStationName(station_id, STATION_SAVE_VERSION + " " + STATION_SAVE_AIRCRAFT_DUMP);

		return station_id;
	}

	return null;
}

function CheckIfDumpStationsAreUnused()
{
	if(g_num_connection_airport_upgrade > 0) return;

	// Don't remove unused dump stations if we are rich
	if(AICompany.GetBankBalance(AICompany.COMPANY_SELF) > AICompany.GetMaxLoanAmount() * 1.5) return;

	if(g_aircraft_dump_airport_small != null && AIVehicleList_Station(g_aircraft_dump_airport_small).IsEmpty())
	{
		// Remove unused dump station
		if(AITile.DemolishTile(Airport.GetAirportTile(g_aircraft_dump_airport_small)))
		{
			g_aircraft_dump_airport_small = null;
		}
	}

	if(g_aircraft_dump_airport_large != null && AIVehicleList_Station(g_aircraft_dump_airport_large).IsEmpty())
	{
		// Remove unused dump station
		if(AITile.DemolishTile(Airport.GetAirportTile(g_aircraft_dump_airport_large)))
		{
			g_aircraft_dump_airport_large = null;
		}
	}
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
	function GetNewPairMoneyLimitPerTransportMode();
	function GetNewPairMoneyLimit();
	function ConnectPair(budget);

	function Save();
	function Load(version, data);
	function ReadConnectionsFromMap(); // Instead of storing data in the save game, the connections are made out from groups of vehicles that share orders.

	function SetCompanyName(nameArray);

	function ManageLoan();
	function RoundLoanDown(loanAmount); // Helper
	function GetMaxMoney();

	function BuyNewConnectionVehicles(connection); 
	function BuildHQ();
	// if tile is not a road-tile it will search for closest road-tile and then start searching for a location to place it from there.
	function PlaceHQ(nearby_tile);

	function FindRoadExtensionTile(road_tile, target_tile, min_loops, max_loops); // road_tile = start search here
	                                                                              // target_tile = when searching for a place to extend existing road, we want to get as close as possible to target_tile
																				  // min_loops = search at least for this amount of loops even if one possible extension place is found (return best found)
																				  // max_loops = maximum search loops before forced return
	function FindRoadExtensionTile_SortByDistanceToTarget(a, b); // Helper
}

function CluelessPlus::Start()
{
	this.Sleep(1);
	local last_timer_print = AIDate.GetCurrentDate();

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
		Log.Info("", Log.LVL_INFO);
		Log.Info("All connections have been read from the map", Log.LVL_INFO);
		Log.Info("----------------------------------------------------------------------", Log.LVL_INFO);
		Log.Info("", Log.LVL_INFO);
		Log.Info("", Log.LVL_INFO);
	}

	if(!AnyVehicleTypeBuildable())
	{
		Log.Error("All transport modes that are supported by this AI are disabled for AIs (or have vehicle limit = 0).", Log.LVL_INFO);
		Log.Info("Enable road or air transport mode in advanced settings if you want that this AI should build something", Log.LVL_INFO);
		Log.Info("", Log.LVL_INFO);
	}
	
	state_build = false;
	local last_manage_time = AIDate.GetCurrentDate();
	local not_build_info_printed = false;
	local last_yearly_manage = AIDate.GetCurrentDate();

	local i = 0;
	while(!this.stop)
	{
		TimerStart("all");

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

			TimerStart("build_check");

			// Also only manage our vehicles if we have any.
			local vehicle_list = AIVehicleList();

			local allow_build_road = Vehicle.GetVehiclesLeft(AIVehicle.VT_ROAD) >= MIN_VEHICLES_TO_BUILD_NEW;
			local allow_build_air = Vehicle.GetVehiclesLeft(AIVehicle.VT_AIR) >= MIN_VEHICLES_TO_BUILD_NEW;

			local new_pair_money_limit = this.GetNewPairMoneyLimit();

			// ... check if we can afford to build some stuff (or we don't have anything -> need to build to either succeed or go bankrupt and restart)
			//   AND road vehicles are not disabled
			//   AND at least 5 more buses/trucks can be built before reaching the limit (a 1 bus/truck connection will not become good)
			if((this.GetMaxMoney() > new_pair_money_limit || AIStationList(AIStation.STATION_ANY).IsEmpty() ) &&
					AnyVehicleTypeBuildable() &&
					(allow_build_road || allow_build_air) )
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

			TimerStop("build_check");
			TimerStart("all_manage");

			if(!vehicle_list.IsEmpty() && AnyVehicleTypeBuildable())
			{
				TimerStart("scan_depots");
				this.CheckDepotsForStopedVehicles();
				TimerStop("scan_depots");

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
							local old_balance = Money.MaxLoan();

							TimerStart("manage_state");
							connection.ManageState();
							TimerStop("manage_state");

							TimerStart("manage_stations");
							connection.ManageStations();
							TimerStop("manage_stations");

							TimerStart("manage_vehicles");
							connection.ManageVehicles();
							TimerStop("manage_vehicles");

							TimerStart("scan_depots");
							this.CheckDepotsForStopedVehicles(); // Sell / upgrade vehicles even while managing connections - good when there are a huge amount of connections
							TimerStop("scan_depots");

							Money.RestoreLoan(old_balance);
						}
					}

					// Remove all connections that was marked for removal
					foreach(remove_idx in remove_connection_idx_list)
					{
						connection_list.remove(remove_idx);
					}

					// Check for rail crossings that couldn't be fixed just after a crash event
					TimerStart("rail_crossings");
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

						local bridge_result = Road.ConvertRailCrossingToBridge(crash_tile, road_tile_next_to_crossing);
						if(bridge_result.succeeded == true || bridge_result.permanently == true)
						{
							// Succeded to build rail crossing or failed permanently -> don't try again
							this.detected_rail_crossings.RemoveValue(crash_tile);
						}
					}
					TimerStop("rail_crossings");

				}
			}

			TimerStop("all_manage");


			if(state_build)
			{
				TimerStart("state_build");

				// Simulate the time it takes to look for a connection
				if(AIController.GetSetting("slow_ai"))
					AIController.Sleep(1000); // a bit more than a month

				TimerStart("connect_pair");
				local ret = this.ConnectPair(new_pair_money_limit * 15 / 10);
				state_build = false;
				TimerStop("connect_pair");

				if(ret && !AIMap.IsValidTile(AICompany.GetCompanyHQ(AICompany.COMPANY_SELF)))
				{
					this.BuildHQ();
				}
				else
				{
					Log.Warning("Could not find two towns/industries to connect", Log.LVL_INFO);
				}

				TimerStop("state_build");
			}
		}

		// Pay back unused money
		ManageLoan();

		// Yearly management
		if(last_yearly_manage + 365 < AIDate.GetCurrentDate())
		{
			Log.Info("Yearly manage", Log.LVL_INFO);

			// Check if we have any unused aircraft dump stations (that can be removed to save money) 
			//CheckIfDumpStationsAreUnused();

			// wait a year for next yearly manage
			last_yearly_manage = AIDate.GetCurrentDate();
			Log.Info("Yearly manage - done", Log.LVL_INFO);
		}

		TimerStop("all");

		// Show timers + restart once a year
		if(last_timer_print + 365 * 5 < AIDate.GetCurrentDate())
		{
			Log.Info("Timer counts:", Log.LVL_DEBUG);
			foreach(_, timer in g_timers)
			{
				timer.PrintTotal();
				timer.Reset();
			}
			Log.Info("------- Timer counts end -------", Log.LVL_DEBUG);
			last_timer_print = AIDate.GetCurrentDate();
		}
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
	TimerStart("handle_events");
	if(AIEventController.IsEventWaiting())
	{
		local ev = AIEventController.GetNextEvent();

		if(ev == null)
		{
			TimerStop("handle_events");
			return;
		}

		local ev_type = ev.GetEventType();

		if(ev_type == AIEvent.AI_ET_VEHICLE_LOST)
		{
			local lost_event = AIEventVehicleLost.Convert(ev);
			local lost_veh = lost_event.GetVehicleID();

			if(AIVehicle.IsValidVehicle(lost_veh))
			{
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
					local bridge_result = Road.ConvertRailCrossingToBridge(crash_tile, road_tile_next_to_crossing);

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
		} 
		else if(ev_type == AIEvent.AI_ET_COMPANY_IN_TROUBLE)
		{
			local company_in_trouble_event = AIEventCompanyInTrouble.Convert(ev);
			local company = company_in_trouble_event.GetCompanyID();
			if(AICompany.IsMine(company))
			{
				local num = 0;

				local list = AIVehicleList();
				while(list.Count() > 0 || num == 0)
				{
					list.Valuate(Vehicle.GetProfitThisAndLastYear);
					list.Sort(AIList.SORT_BY_VALUE, AIList.SORT_ASCENDING);
					local lowest_profit_vehicle = list.Begin();
					if(num > 0 && list.GetValue(lowest_profit_vehicle) > 0) break; // don't sell vehicles that make profit if we have sold at least one already
					list.RemoveItem(lowest_profit_vehicle);

					// Send vehicle for selling without spending time to find out which connection that it belongs to
					SendLostVehicleForSelling(lowest_profit_vehicle);
				}

				foreach(connection in this.connection_list)
				{
					if(connection.transport_mode == TM_AIR)
					{
						// don't upgrade airports when in economic trouble
						connection.StopAirportUpgrading();
					}
				}

			} // Is mine company

		}
	}

	TimerStop("handle_events");
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
	local vehicle_list = AIVehicleList();
	if(!vehicle_list.IsEmpty() && AnyVehicleTypeBuildable())
	{
		Log.Info("Look for vehicles to sell / send to depot for selling", Log.LVL_SUB_DECISIONS);

		// check if there are any vehicles to sell
		local to_sell_in_depot = AIVehicleList();
		to_sell_in_depot.Valuate(AIVehicle.IsStoppedInDepot);
		to_sell_in_depot.KeepValue(1);
		Log.Info("num vehicles stopped in depot: " + to_sell_in_depot.Count(), Log.LVL_SUB_DECISIONS);
		foreach(i, _ in to_sell_in_depot)
		{
			local veh_state = ClueHelper.ReadStrFromVehicleName(i);

			// Don't sell suspended / active vehicles, or vehicles waiting for airport upgrade
			if(veh_state == "suspended" || veh_state == "active" || veh_state == "ap upgrade")
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

					if(Vehicle.GetVehiclesLeft(AIVehicle.GetVehicleType(i)) > 0)
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

		Log.Info("  num vehicles that does not go to depot: " + to_send_to_depot.Count(), Log.LVL_DEBUG);
		foreach(i, _ in to_send_to_depot)
		{
			Log.Info("Send broken vehicle '" + AIVehicle.GetName(i) + "' to depot", Log.LVL_SUB_DECISIONS);
			SendLostVehicleForSelling(i);
		}
	}
}

function CluelessPlus::GetNewPairMoneyLimit()
{
	local limits = this.GetNewPairMoneyLimitPerTransportMode();
	local min_limit = null;
	foreach(item in limits)
	{
		if(min_limit == null || item.limit < min_limit)
			min_limit = item.limit;
	}

	if(min_limit == null) min_limit = 95000;
	min_limit = Helper.Max(95000, min_limit); // require at least 95000 even if some transport mode is cheaper

	return min_limit;
}

function CluelessPlus::GetNewPairMoneyLimitPerTransportMode()
{
	local tm_list = GetAvailableTransportModes(MIN_VEHICLES_TO_BUILD_NEW);

	// Make sure there are at least one transport mode
	if(tm_list.len() == 0)
		return 95000;

	local tm_money_limits = [];
	foreach(tm in tm_list)
	{
		local item = { tm = tm, limit = 95000 };	

		if(tm == TM_AIR)
		{
			local airport_type_list = GetAirportTypeList_AllowedAndBuildable();

			airport_type_list.Valuate(AIAirport.GetPrice);
			airport_type_list.Sort(AIList.SORT_BY_VALUE, AIList.SORT_DESCENDING);
			local ap_type = airport_type_list.Begin();
			local airport_cost = airport_type_list.GetValue(ap_type) * 2;

			local engine = Strategy.FindEngineModelToPlanFor(Helper.GetPAXCargo(), AIVehicle.VT_AIR, Airport.IsSmallAirport(ap_type), false);
			local engine_cost = AIEngine.GetPrice(engine);

			item.limit = (airport_cost + engine_cost) * 12 / 10; // 20 % margin
		}

		tm_money_limits.append(item);
	}

	return tm_money_limits;
}

function CluelessPlus::ConnectPair(budget)
{
	// scan for two pairs to connect

	// Calculate max distance for each transport mode
	foreach(tm in g_tm_list)
	{
		g_tm_stats[tm].CalcMaxConstructDistance(state_desperateness);
	}

	TimerStart("pairfinding");
	local result = this.pair_finder.FindTwoNodesToConnect(state_desperateness, connection_list);
	local pair = result != null? result.pair : null;
	TimerStop("pairfinding");

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

	local connection = Connection(this);

	connection.cargo_type = pair[0].cargo_id; // Store the cargo type
	connection.transport_mode = result.transport_mode; // Store transport mode
	connection.state = Connection.STATE_BUILDING;

	connection.station = [];
	connection.industry = [];
	connection.town = [];
	connection.depot = [];
	connection.station_statistics = [];
	connection.node = [];

	local failed = false;
	Log.Info("Connect " + pair[0].GetName() + " with " + pair[1].GetName(), Log.LVL_INFO);

	// save town, industry, and node in connection data-structure.
	foreach(node in pair)
	{
		connection.town.append( node.IsTown()? node.town_id : -1 );
		connection.industry.append( node.IsIndustry()? node.industry_id : -1 );
		connection.node.append(node);
	}

	// We don't want to worry about budgeting exactly how much money that is needed, get as much money as possible.
	// We can always pay back later. 
	local old_balance = Money.MaxLoan();
	local budget_money_left = budget;


	//// Start building ////

	// Build bus/truck-stops + depots (or equivalent for other transport modes)
	if(!this.ConstructStationAndDepots(pair, connection))
	{
		connection.date_built = AIDate.GetCurrentDate();
		connection.state = Connection.STATE_FAILED;			// store that this connection faild so we don't waste our money on buying buses for it.
		connection_list.append(connection); 
		this.state_desperateness++;
		Money.RestoreLoan(old_balance);
		return false;
	}

	// reduce budget by money spent on stations
	budget_money_left -= old_balance - AICompany.GetBankBalance(AICompany.COMPANY_SELF);
	Money.MakeMaximumPayback();
	Money.MakeSureToHaveAmount(budget_money_left / 2); // reduce loan to some reasonable amount for pathfinding to not fail due to low money, but not too high
	local balance_before_infra_build = AICompany.GetBankBalance(AICompany.COMPANY_SELF);

	Log.Info("Built stations + depots", Log.LVL_INFO);

	// Create StationStatistics instances for stations
	if(!failed)
	{
		local i = 0;
		foreach(node in pair)
		{
			connection.station_statistics.append(StationStatistics(AIStation.GetStationID(connection.station[i]), connection.cargo_type));
			i++;
		}
	}

	// Connect stations with road/rail/buyos

	TimerStart("build_infra_connect");

	local connected = false;
	local road_builder = null; // keep the builder alive also after building completed, so that performance can be computed
	local rail_builder = null;
	switch(connection.transport_mode)
	{
		case TM_ROAD:
			{
				road_builder = RoadBuilder();
				if(AIController.GetSetting("slow_ai")) road_builder.EnableSlowAI();
				Log.Info("bus/truck-stops built", Log.LVL_INFO);
				if(!failed)
				{
					connected = true; // true until first failure

					for(local i = 0; i < 2; i++)
					{
						local station_front_tile = Road.GetRoadStationFrontTile(connection.station[i]);
						local depot_front_tile = AIRoad.GetRoadDepotFrontTile(connection.depot[i]);

						//Helper.SetSign(station_front_tile, "stn front");
						//Helper.SetSign(depot_front_tile, "depot front");

						if(station_front_tile != depot_front_tile)
						{
							local repair = false;
							local max_loops = 5000;
							if(connected)
							{
								TimerStart("build_pathfinding");
								road_builder.Init(depot_front_tile, station_front_tile, repair, max_loops); // -> start construct it from the station
								road_builder.DoPathfinding();
								TimerStop("build_pathfinding");

								TimerStart("build_buildroad");
								connected = road_builder.ConnectTiles() == RoadBuilder.CONNECT_SUCCEEDED;
								TimerStop("build_buildroad");
							}
						}

						if(!connected)
							break;
					}

					// Don't waste money on a road if connecting stops with depots failed
					if(connected)
					{
						local from = Road.GetRoadStationFrontTile(connection.station[0]);
						local to = Road.GetRoadStationFrontTile(connection.station[1]);
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
			}
			break;

		case TM_AIR:
			connected = true; // no infrastructure is needed
			break;

		case TM_RAIL:
		case TM_WATER:
			NOT_IMPLEMENTED();
			return false;
	}
	TimerStop("build_infra_connect");

	budget_money_left -= balance_before_infra_build - AICompany.GetBankBalance(AICompany.COMPANY_SELF);
	Money.MaxLoan(); // no more budgeting - get all money!

	// Only buy buses if we actually did connect the two cities.
	if(connected && !failed)
	{	
		TimerStart("build_buy_vehicles");
		Log.Info("stations are now connected with infrastructure", Log.LVL_INFO);
		// BuyNewConnectionVehicles save the IDs of the bough buses in the connection data-structure
		BuyNewConnectionVehicles(connection); 
		connection.FullLoadAtStations(true); // TODO
		Log.Info("bough buses", Log.LVL_INFO);

		connection.state = Connection.STATE_ACTIVE;	// construction did not fail -> active connection
		TimerStop("build_buy_vehicles");
	}
	else
	{
		Log.Warning("failed to connect stations with road/rail etc.", Log.LVL_INFO);
		TimerStart("build_abort");

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
				Road.RemoveRoadUpToRoadCrossing(front_tile);
			}
		}

		connection.state = Connection.STATE_FAILED;			// store that this connection faild so we don't waste our money on buying buses for it.
		state_desperateness++;
		TimerStop("build_abort");
	}

	// Store the connection so we don't build it again.
	connection.date_built = AIDate.GetCurrentDate();
	connection_list.append(connection); 

	// Calculate build performance
	if(!failed && connected)
	{
		TimerStart("build_performance");
		local performance = 0;
		switch(connection.transport_mode)
		{
			case TM_ROAD:
				{
					local pf_loops_used = road_builder.GetPFLoopsUsed();
					local build_loops_used = road_builder.GetBuildLoopsUsed();
					local from = Road.GetRoadStationFrontTile(connection.station[0]);
					local to = Road.GetRoadStationFrontTile(connection.station[1]);
					local distance = AIMap.DistanceManhattan(from, to);

					Log.Info("pf loops used:    " + pf_loops_used, Log.LVL_INFO);
					Log.Info("build loops used: " + build_loops_used, Log.LVL_INFO);
					Log.Info("over distance:    " + distance, Log.LVL_INFO);

					local pf_performance = pf_loops_used / distance;
					local build_performance = build_loops_used / distance;
					performance = distance * 7000 / (pf_loops_used + build_loops_used) - 62; // The constants are magic numbers that has been found by collecting data from several connections and tweaking the formula to give good results
				}
				break;

			case TM_AIR:
				{
					//local from = connection.station[0];
					//local to = connection.station[1];
					performance = 10; // include cost/time used to build airports
				}
				break;

			case TM_RAIL:
			case TM_WATER:
				performance = 10;
				break;
		}

		local tm = connection.transport_mode;

		// Allow the long term performance to be in the interval -30 to 110 (when used it is clamped to -20 to 100)
		g_tm_stats[tm].construct_performance = Helper.Clamp((g_tm_stats[tm].construct_performance * 2 + performance) / 3, -30, 110);
		Log.Info("Connect performance of this connection: " + performance, Log.LVL_INFO);
		Log.Info("Long term performance rating:           " + g_tm_stats[tm].construct_performance, Log.LVL_INFO);


		// we succeed to build the connection => revert to zero desperateness
		state_desperateness = 0;

		TimerStop("build_performance");
	}

	Money.RestoreLoan(old_balance);

	return !failed && connected;
}

function CluelessPlus::BuildHQ()
{
	// Check if HQ already has been built
	if(AIMap.IsValidTile(AICompany.GetCompanyHQ(AICompany.COMPANY_SELF)))
		return;

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

function CluelessPlus::ConstructStationAndDepots(pair, connection)
{
	if(connection.transport_mode == null)
		return false;

	// If transport mode is air, get airport type to build
	local airport_type = null;
	local use_magic_dtrs = null;

	if(connection.transport_mode == TM_AIR)
	{
		// Select an airport that can be afforded after reserving* money for one aircraft   * = no actual reservation is made. Only accounting for the engine is done.

		local large_engine = Strategy.FindEngineModelToPlanFor(connection.cargo_type, AIVehicle.VT_AIR, false, false);
		local large_engine_cost = AIEngine.GetPrice(large_engine);

		// can afford large airport + large airplane?
		local airport_type_list = GetAirportTypeList_AllowedAndBuildable(false);
		airport_type_list.Valuate(AIAirport.GetPrice);
		airport_type_list.KeepBelowValue(AICompany.GetBankBalance(AICompany.COMPANY_SELF) - large_engine_cost * 12 / 10);

		if(airport_type_list.IsEmpty())
		{
			// couldn't afford large airport + large engine.
			// try small airport

			local small_engine = Strategy.FindEngineModelToPlanFor(connection.cargo_type, AIVehicle.VT_AIR, true, false);
			local small_engine_cost = AIEngine.GetPrice(small_engine);

			airport_type_list = GetAirportTypeList_AllowedAndBuildable(true);
			airport_type_list.Valuate(AIAirport.GetPrice);
			airport_type_list.KeepBelowValue(AICompany.GetBankBalance(AICompany.COMPANY_SELF) - small_engine_cost * 12 / 10);
		}

		airport_type_list.Sort(AIList.SORT_BY_ITEM, AIList.SORT_DESCENDING);
		airport_type = airport_type_list.Begin(); // take last airport type that can be afforded

		if(airport_type == null)
		{
			Log.Warning("Tried to connect pair by air, but there is not enough money to afford an airport + engine", Log.LVL_INFO);
			return false;
		}
	}
	else if(connection.transport_mode == TM_ROAD)
	{
		// Decide if we should use DTRS or not
		local magic_dtrs_allowed = AIController.GetSetting("enable_magic_dtrs");
		if(magic_dtrs_allowed)
		{
			// See if the desired engine is articulated or not
			local rv_engine = Strategy.FindEngineModelToPlanFor(connection.cargo_type, AIVehicle.VT_ROAD, false, magic_dtrs_allowed);

			// Use the magic DTRS only when we get an articulated engine
			use_magic_dtrs = AIEngine.IsArticulated(rv_engine) ||
				AIBase.RandRange(6) < 1; // or at one time in 6, use dtrs anyway just for some randomization (and higher chance of finding bugs :-D )
		}
		else
		{
			use_magic_dtrs = false;
		}
	}

	foreach(node in pair)
	{
		local station_tile = null;
		local depot_tile = null;
		if (node.IsTown())
		{
			// Make sure the station accept/produce the wanted cargo
			local accept_cargo = -1;
			local produce_cargo = -1;
			if(node.IsCargoAccepted())
				accept_cargo = node.cargo_id;
			if(node.IsCargoProduced())
				produce_cargo = node.cargo_id;

			switch(connection.transport_mode)
			{
				case TM_ROAD:
					{
						local road_veh_type = AIRoad.GetRoadVehicleTypeForCargo(node.cargo_id);
						local stop_length = 2;

						if(use_magic_dtrs)
						{
							local result = Road.BuildMagicDTRSInTown(node.town_id, road_veh_type, stop_length, accept_cargo, produce_cargo);
							if(result.result)
							{
								station_tile = AIStation.GetLocation(result.station_id);
								depot_tile = result.depot_tile;
							}
						}
						else
						{
							station_tile = Road.BuildStopInTown(node.town_id, road_veh_type, accept_cargo, produce_cargo);

							if (station_tile != null)
								depot_tile = Road.BuildDepotNextToRoad(Road.GetRoadStationFrontTile(station_tile), 0, 100);
							else
								Log.Warning("failed to build bus/truck stop in town " + AITown.GetName(node.town_id), Log.LVL_INFO);
						}
					}
					break;

				case TM_AIR:
					Log.Info("ap type: " + airport_type + " ac " + accept_cargo + " pc " + produce_cargo, Log.LVL_INFO);
					station_tile = Airport.BuildAirportInTown(node.town_id, airport_type, accept_cargo, produce_cargo);

					if (station_tile == null)
						Log.Warning("failed to build airport in town " + AITown.GetName(node.town_id), Log.LVL_INFO);
					else
					{
						Log.Warning("Built airport in town: " + AITown.GetName(node.town_id), Log.LVL_SUB_DECISIONS);
						depot_tile = Airport.GetHangarTile(AIStation.GetStationID(station_tile));
					}
					break;

				default:
					return false;
			}
		}
		else
		{
			switch(connection.transport_mode)
			{
				case TM_ROAD:
					station_tile = Road.BuildStopForIndustry(node.industry_id, node.cargo_id);
					if (!AIStation.IsValidStation(AIStation.GetStationID(station_tile))) // for compatibility with the old code, turn -1 into null
						station_tile = null;
					
					if (station_tile != null)
						depot_tile = Road.BuildDepotNextToRoad(Road.GetRoadStationFrontTile(station_tile), 0, 100); // TODO, for industries there is only a road stump so chances are high that this fails
					break;

				case TM_AIR:
					station_tile = Airport.BuildAirportForIndustry(airport_type, node.industry_id, node.cargo_id);

					if (station_tile == null)
						Log.Warning("failed to build airport in town " + AITown.GetName(node.town_id), Log.LVL_INFO);
					else
						depot_tile = Airport.GetHangarTile(AIStation.GetStationID(station_tile));
					break;

				default:
					return false;
			}
			
		}

		// Append null if the station tile is invalid
		connection.station.append(station_tile);
		connection.depot.append(depot_tile);
	}

	// Check that we built all buildings
	local fail = false;
	foreach(station in connection.station)
	{
		if(station == null || !AIMap.IsValidTile(station))
		{
			Log.Info("failed to build stations = true", Log.LVL_INFO);
			fail = true;
		}
	}
	foreach(depot in connection.depot)
	{
		if(depot == null || !AIMap.IsValidTile(depot))
		{
			Log.Info("failed to build depots = true", Log.LVL_INFO);
			fail = true;
		}
	}

	// Remove stations/depots that were built, if not all succeeded
	if(fail)
	{
		foreach(station in connection.station)
		{
			if(station != null && AIMap.IsValidTile(station))
			{
				local station_id = AIStation.GetStationID(station);
				Station.DemolishStation(station_id);
			}
		}
		foreach(depot in connection.depot)
		{
			if(depot != null && AIMap.IsValidTile(depot))
			{
				AITile.DemolishTile(depot);
			}
		}

		Log.Info("Demolished failed stn + depot", Log.LVL_DEBUG);

		return false;
	}



	// Store node info in station names
	local i = 0;
	foreach(station_tile in connection.station)
	{
		Log.Info("assign name to " + AIStation.GetName(AIStation.GetStationID(station_tile)), Log.LVL_DEBUG);
		ClueHelper.StoreInStationName(AIStation.GetStationID(station_tile), STATION_SAVE_VERSION + " " + pair[i].SaveToString());
		++i;
	}

	return true;
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
	//uncategorized_vehicles.Valuate(AIVehicle.GetVehicleType);
	//uncategorized_vehicles.KeepValue(AIVehicle.VT_ROAD);
	//uncategorized_vehicles.Valuate(CargoOfVehicleValuator);
	//uncategorized_vehicles.KeepValue(Helper.GetPAXCargo());

	local unused_stations = AIStationList(AIStation.STATION_ANY);
	unused_stations.Valuate(Helper.ItemValuator);

	// Are there any special stations?
	foreach(station_id, _ in unused_stations)
	{
		if(IsAircraftDumpStation(station_id))
		{
			Log.Info("Found aircraft dump station: " + AIStation.GetName(station_id), Log.LVL_INFO);
			local ap_tile = Airport.GetAirportTile(station_id);
			if(ap_tile != null && AIMap.IsValidTile(ap_tile)) // verify that the station has an airport
			{
				if(Airport.IsSmallAirport(ap_tile))
					g_aircraft_dump_airport_small = station_id;
				else
					g_aircraft_dump_airport_large = station_id;

				Log.Info("is small airport = " + Airport.IsSmallAirport(ap_tile), Log.LVL_DEBUG);

				unused_stations.RemoveItem(station_id);
			}
		}
	}

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
			SendLostVehicleForSelling(veh_id);
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

	Log.Info("Num unused stations: " + unused_stations.Count(), Log.LVL_DEBUG);

	// Destroy all unused stations so they don't cost money
	foreach(station_id, _ in unused_stations)
	{
		// Don't remove the airport dump stations
		if(IsAircraftDumpStation(station_id))
		{
			continue;
		}

		Log.Warning("Station " + AIStation.GetName(station_id) + " is unused and will be removed", Log.LVL_INFO);

		Station.DemolishStation(station_id);
	}
}

function CluelessPlus::ReadConnectionFromVehicle(vehId)
{
	local connection = Connection(this);
	connection.cargo_type = Vehicle.GetVehicleCargoType(vehId);

	local station_type = Engine.GetRequiredStationType(AIVehicle.GetEngineType(vehId));
	if(station_type == null) return null;
	switch(AIVehicle.GetVehicleType(vehId))
	{
		case AIVehicle.VT_ROAD:
			connection.transport_mode = TM_ROAD;
			break;

		case AIVehicle.VT_AIR:
			connection.transport_mode = TM_AIR;
			break;

		case AIVehicle.VT_RAIL:
			connection.transport_mode = TM_RAIL;
			break;

		case AIVehicle.VT_WATER:
			connection.transport_mode = TM_WATER;
			break;
	}

	connection.station = [];
	connection.depot = [];
	for(local i_order = 0; i_order < AIOrder.GetOrderCount(vehId); ++i_order)
	{
		if(AIOrder.IsGotoStationOrder(vehId, i_order))
		{
			local station_id = AIStation.GetStationID(AIOrder.GetOrderDestination(vehId, i_order));
			local stn_tile_list = AITileList_StationType(station_id, station_type); // Resolve a station tile with the right transport mode.
			local station_tile = stn_tile_list.Begin();

			if(stn_tile_list.Count() == 0)
			{
				Log.Error("Couldn't find station tile of the right station type for station " + AIStation.GetName(station_id) + ". Engine: " + AIEngine.GetName(AIVehicle.GetEngineType(vehId)) + ". Transport Mode: " + connection.transport_mode + ".", Log.LVL_INFO);
				continue;
				
			}

			Log.Info("Added station: " + AIStation.GetName(station_id), Log.LVL_SUB_DECISIONS);
			connection.station.append(station_tile);
			connection.station_statistics.append(StationStatistics(station_id, connection.cargo_type));
		}

		if(AIOrder.IsGotoDepotOrder(vehId, i_order))
		{
			local order_dest = AIOrder.GetOrderDestination(vehId, i_order);
			
			// Ignore the aircraft dump airport if it's hangar is in the orders
			if(AIAirport.IsAirportTile(order_dest))
			{
				local station_id = AIStation.GetStationID(order_dest);
				if(IsAircraftDumpStation(station_id))
					continue;
			}

			connection.depot.append(order_dest);
		}
	}

	// fail if less than two stations were found
	if(connection.station.len() != 2)
	{
		Log.Warning("Connection has != 2 stations -> fail | tm: " + TransportModeToString(connection.transport_mode) + " veh: " + AIVehicle.GetName(vehId), Log.LVL_INFO);
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

		Log.Info("station save version: " + save_version, Log.LVL_DEBUG);
		Log.Info("station save str: " + node_save_str, Log.LVL_SUB_DECISIONS);

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
	local ap_upgrade_count = 0;
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
		else if(state == "ap upgrade")
			ap_upgrade_count++;
		else if(state == "sell")
			sell_count++;
		else
			continue;

		Log.Info("Vehicle has state: " + state, Log.LVL_DEBUG);
	}

	// For now just detect closing down, suspended and airport upgrade named vehicles
	if(close_conn_count > 0) {
		connection.state = Connection.STATE_CLOSING_DOWN;
	} else if(suspended_count > 0) {
		connection.state = Connection.STATE_SUSPENDED;
	} else if(ap_upgrade_count > 0) {
		connection.state = Connection.STATE_AIRPORT_UPGRADE;
	} else { //if(sell_count != group.Count())
		connection.state = Connection.STATE_ACTIVE;
	}

	Log.Info("Connection state before fail-check: " + connection.state, Log.LVL_DEBUG);

	// Detect broken connections
	if(connection.depot.len() != 2 || connection.station.len() != 2 || connection.town.len() != 2)
		connection.state = Connection.STATE_FAILED;

	if(connection.state == Connection.STATE_AIRPORT_UPGRADE)
	{
		// update variable that keeps track of how many connections that upgrade airports
		++g_num_connection_airport_upgrade
	}

	Log.Info("Connection state after fail-check: " + connection.state, Log.LVL_DEBUG);

	// show loaded state in debug sign
	foreach(stn in connection.station)
	{
		Helper.SetSign(Tile.GetTileRelative(AIStation.GetLocation(AIStation.GetStationID(stn)), 1, 1), "state:" + connection.state);
	}

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
	TimerStart("manage_loan");

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

	TimerStop("manage_loan");
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
				if( Helper.ArrayFind(red_list, adjacent_tile) == null )
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
