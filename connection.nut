
//////////////////////////////////////////////////////////////////////
//                                                                  //
//  CLASS: Connection - a transport connection                      //
//                                                                  //
//////////////////////////////////////////////////////////////////////

// My aim is that this class should be as general as possible and allow 2> towns, or even cargo transport
//
// As of 2011-07-25: The class handles any cargo type, but >2 towns/industries is quite likely that it doesn't work without some work
class Connection
{
	clueless_instance = null;

	transport_mode = null;
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
	last_airport_upgrade_fail = null;

	desired_engine = null;
	airport_upgrade_list = null; // list of airports (stations) to upgrade
	airport_upgrade_failed = false; // set to true during upgrade if any airport failed
	airport_upgrade_start = null; // when did the upgrade start?


	static STATE_BUILDING = 0;
	static STATE_FAILED = 1;
	static STATE_ACTIVE = 2;
	static STATE_CLOSED_DOWN = 10;
	static STATE_CLOSING_DOWN = 11;
	static STATE_SUSPENDED = 20;
	static STATE_AIRPORT_UPGRADE = 30;

	state = null;
	state_change_date = null;
	
	constructor(clueless_instance) {
		this.clueless_instance = clueless_instance;
		this.transport_mode = TM_INVALID;
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
		this.last_airport_upgrade_fail = null;
		this.desired_engine = null;
		this.airport_upgrade_list = null;
		this.airport_upgrade_failed = null;
		this.airport_upgrade_start = null;
	}

	function GetName();

	function SetState(newState);

	function ReActivateConnection();
	function SuspendConnection();
	function CloseConnection();

	function IsTownOnly();
	function HasSmallAirport();
	function GetSmallAirportCount();
	function HasMagicDTRSStops();
	function GetTotalPoputaltion();
	function GetTotalDistance(); // only implemented for 2 towns
	function ManageState()
	function ManageStations()
	function ManageVehicles();
	function SendVehicleForSelling(vehicle_id);
	function GetMinMaxRatingWaiting();

	function ManageAirports();
	function CheckForAirportUpgrade();
	function TryUpgradeAirports();

	function FindEngineModelToBuy();
	function BuyVehicles(num_vehicles, engine_id);
	function NumVehiclesToBuy(connection);
	function GetDepotServiceFlag();

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
		return node[0].GetName() + " - " + node[1].GetName() + " (" + TransportModeToString(transport_mode) + ")";

	// If one or more node is broken:
	return "[broken connection]";
}

function Connection::SetState(newState)
{
	this.state = newState;
	this.state_change_date = AIDate.GetCurrentDate();

	if(this.station != null)
	{
		foreach(stn in this.station)
		{
			if(stn != null)
				Helper.SetSign(Tile.GetTileRelative(AIStation.GetLocation(AIStation.GetStationID(stn)), 1, 1), "state:" + this.state);
		}
	}
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
			local service_flag = this.GetDepotServiceFlag();

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

function Connection::HasSmallAirport()
{
	if(this.transport_mode != TM_AIR)
		return false;

	foreach(station_tile in this.station)
	{
		if(station_tile == null) continue;

		if(Airport.IsSmallAirport(AIStation.GetStationID(station_tile)))
			return true;
	}

	return false;
}

function Connection::GetSmallAirportCount()
{
	if(this.transport_mode != TM_AIR)
		return 0;

	local count = 0;
	foreach(station_tile in this.station)
	{
		if(station_tile == null) continue;

		if(Airport.IsSmallAirport(AIStation.GetStationID(station_tile)))
			++count;
	}

	return count;
}

function Connection::HasMagicDTRSStops()
{
	if(this.transport_mode != TM_ROAD)
		return false;

	foreach(station_tile in this.station)
	{
		if(AIRoad.IsDriveThroughRoadStationTile(station_tile))
			return true;
	}

	return false;
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
	local has_small_airport = this.HasSmallAirport();
	local allow_articulated_rvs = this.HasMagicDTRSStops();
	return Strategy.FindEngineModelToBuy(this.cargo_type, TransportModeToVehicleType(this.transport_mode), has_small_airport, allow_articulated_rvs);
}
function Connection::BuyVehicles(num_vehicles, engine_id)
{

	if(station.len() != 2 || this.station[0] == null || this.station[1] == null)
	{
		Log.Warning("BuyVehicles: wrong number of stations", Log.LVL_INFO);
		return false;
	}

	if(depot.len() != 2 || this.depot[0] == null || this.depot[1] == null)
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
				Log.Info("I built a vehicle", Log.LVL_DEBUG);
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
		AIController.Sleep(1);
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
			local service_flag = (this.transport_mode == TM_ROAD || this.transport_mode == TM_RAIL? AIOrder.AIOF_NON_STOP_INTERMEDIATE : 0) | this.GetDepotServiceFlag();
			local station_flag = this.transport_mode == TM_ROAD || this.transport_mode == TM_RAIL? AIOrder.AIOF_NON_STOP_INTERMEDIATE : AIOrder.AIOF_NONE;

			AIOrder.AppendOrder(new_bus, depot[0], service_flag);
			AIOrder.AppendOrder(new_bus, station[0], station_flag); 
			AIOrder.AppendOrder(new_bus, depot[1], service_flag);  
			AIOrder.AppendOrder(new_bus, station[1], station_flag);

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

function Connection::GetDepotServiceFlag()
{
	if(AIGameSettings.GetValue("vehicle_breakdowns") != 2 || // if breakdowns is enabled
			HasMagicDTRSStops()) 
	{
		return 0; //  Always visit the depots
	}
	else
	{
		return AIOrder.AIOF_SERVICE_IF_NEEDED;
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
					local check = false;
					switch(this.transport_mode)
					{
						case TM_ROAD:
							check = this.max_station_usage > 135 || this.max_station_tile_usage > 180;
							break;

						case TM_RAIL:
							check = this.max_station_usage > 135; // tweak
							break;

						default:
							check = false;
					}

					if(check)
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
				if(station_tile == null) continue;

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
				if(depot == null) continue;

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
				Road.RemoveRoadUpToRoadCrossing(tile);
			}

			Log.Info("Change state to STATE_CLOSED_DOWN");
			this.SetState(Connection.STATE_CLOSED_DOWN);
		}
	}
	else if(this.state == Connection.STATE_AIRPORT_UPGRADE)
	{
		// Try to get further in the upgrade process
		Log.Info("Manage state - try to continue upgrading the airports", Log.LVL_SUB_DECISIONS);
		this.TryUpgradeAirports();
	}
}

function Connection::ManageStations()
{
	if(this.state != Connection.STATE_ACTIVE)
		return;

	if(this.station[0] == null || this.station[1] == null)
	{
		this.CloseConnection();
		return;
	}

	// Don't manage too often
	local now = AIDate.GetCurrentDate();
	if(this.last_station_manage != null && now - this.last_station_manage < 5)
		return;
	this.last_station_manage = now;

	Log.Info("Manage Stations: " + this.GetName(), Log.LVL_INFO);

	// Update station statistics
	if(this.transport_mode != TM_WATER)
	{
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

			local usage = null;
			local max_tile_usage = null;

			switch(this.transport_mode)
			{
				case TM_ROAD:
					usage = Helper.Max(station_statistics.usage.bus.percent_usage, station_statistics.usage.truck.percent_usage);
					max_tile_usage = Helper.Max(station_statistics.usage.bus.percent_usage_max_tile, station_statistics.usage.truck.percent_usage_max_tile);
					break;

				case TM_AIR:
					usage = station_statistics.usage.aircraft.percent_usage;
					break;

				case TM_RAIL:
					usage = station_statistics.usage.train.percent_usage;
					break;
			}

			if(usage > max_station_usage)
				max_station_usage = usage;

			if(this.transport_mode == TM_ROAD && max_tile_usage > max_station_tile_usage)
				max_station_tile_usage = max_tile_usage;
		}

		this.max_station_usage = max_station_usage;
		this.max_station_tile_usage = max_station_tile_usage;
	}

	// road specific station management
	if(this.transport_mode == TM_AIR)
	{
		this.ManageAirports();
		if(this.station[0] == null || this.station[1] == null) return; // may happen if airport upgrade fails with a broken connection
	}
	else if(this.transport_mode == TM_ROAD)
	{
		// Check that all station parts are connected to road
		for(local town_i = 0; town_i < 2; town_i++)
		{
			local station_id = AIStation.GetStationID(this.station[town_i]);
			local existing_stop_tiles = AITileList_StationType(station_id, AIStation.STATION_BUS_STOP);
			existing_stop_tiles.AddList(AITileList_StationType(station_id, AIStation.STATION_TRUCK_STOP));
			local num_remaining_stop_tiles = existing_stop_tiles.Count();

			foreach(stop_tile, _ in existing_stop_tiles)
			{
				local front_tile = Road.GetRoadStationFrontTile(stop_tile);
				local is_dtrs = AIRoad.IsDriveThroughRoadStationTile(stop_tile);
				if(is_dtrs)
				{
					if(AIMap.DistanceManhattan(stop_tile, front_tile) != 1)
					{
						// This DTRS station tile is not adjacent to the front tile
						continue;
					}

					if(AIRoad.IsRoadDepotTile(front_tile))
					{
						Log.Warning("Found a front tile of a DTRS that is a road depot!", Log.LVL_INFO);
						continue; // don't demolish our own depot!
					}
				}
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
								Helper.SetSign(stop_tile, "no road access");
								if(!is_dtrs) // never demolish DTRS station parts
								{
									AITile.DemolishTile(stop_tile);
									num_remaining_stop_tiles--;
								}

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
		if(max_num_bus_stops_per_station > 1 && !this.HasMagicDTRSStops()) // expanding of MagicDTRS has not been implemented
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
					local grown_parallel_ret = Road.GrowStationParallel(station_id, station_type);
					local grown = Result.IsSuccess(grown_parallel_ret);
					if(!grown && grown_parallel_ret != Result.NOT_ENOUGH_MONEY)
						grown = Result.IsSuccess(Road.GrowStation(station_id, station_type));

					if(grown)
					{
						Log.Info("Station has been grown with one bus stop", Log.LVL_INFO);

						if(Result.IsSuccess(grown_parallel_ret))
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
	} // end of road station management

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

function Connection::ManageAirports()
{
	this.CheckForAirportUpgrade();
}

function Connection::CheckForAirportUpgrade()
{
	if( (g_num_connection_airport_upgrade != 0 || g_num_connection_airport_upgrade < this.clueless_instance.connection_list.len() / 2) && // don't upgrade too many at the same time
			(last_airport_upgrade_fail == null || last_airport_upgrade_fail + 365 < AIDate.GetCurrentDate())) // fail at maximum once a year
	{
		Log.Info("ManageAirports", Log.LVL_DEBUG);

		// Does all towns forbid station-building?
		local all_forbid = true;
		foreach(node in this.node)
		{
			if(Town.TownRatingAllowStationBuilding(node.GetClosestTown()))
				all_forbid = false;
		}

		if(all_forbid)
			return;

		// Check if upgrading of airport is needed
		local upgrade_need = 0;

		local tmp = this.GetMinMaxRatingWaiting();
		local min_rating = tmp.min_rating;
		local max_rating = tmp.max_rating;
		local max_waiting = tmp.max_waiting;

		local small_count = this.GetSmallAirportCount();
		local has_small = small_count > 0;

		upgrade_need += max_waiting / 10 + (has_small? 50 : 0);

		foreach(station_stat in station_statistics)
		{
			upgrade_need += station_stat.usage.aircraft.percent_usage;
		}

		// If there is not enough need from capacity point of view, check if the upgrade
		// can be motivated by allowing upgrade to a significantly better aircraft.
		if(upgrade_need <= 200 && has_small)
		{
			// Get best engine, also including large aircrafts
			local articulated_rvs = false;
			local best_engine = Strategy.FindEngineModelToBuy(this.cargo_type, TransportModeToVehicleType(this.transport_mode), false, articulated_rvs); 
			if(AIEngine.GetPlaneType(best_engine) == AIAirport.PT_BIG_PLANE)
			{
				// best engine is a large aircraft

				// check if it is significantly better than the current aircraft
				local veh_list = this.GetVehicles();
				if(!veh_list.IsEmpty())
				{
					local curr_engine = AIVehicle.GetEngineType(veh_list.Begin());
					local curr_score = Strategy.EngineBuyScore(curr_engine);
					local best_score = Strategy.EngineBuyScore(best_engine);
					Log.Info("ce" + curr_engine + " cs " + curr_score + " bs " + best_score + " be " + best_engine);

					if(best_score > curr_score * 1.5) // higher treshold than when mass-upgrading vehicles
					{
						// Upgrade as there is a significantly better engine available
						if(AICompany.GetBankBalance(AICompany.COMPANY_SELF) > AICompany.GetMaxLoanAmount() * 15 / 10) // if rich, upgrade quick
							upgrade_need += 1000;
						else
							// else, give a smaller bonus to reduce the risk of trying to upgrade all 
							// connections at the same time. (20 in bonus if both are small and 50 
							// in bonus if only one airport is missing before the connection get all
							// airports large
							upgrade_need += 20 + (small_count == 1? 30 : 0); 
					}
				}
			}
		}

		Log.Info("Upgrade need for " + this.GetName() + " is " + upgrade_need, Log.LVL_SUB_DECISIONS);
		foreach(stn in this.station)
		{
			if(stn != null)
				Helper.SetSign(Tile.GetTileRelative(AIStation.GetLocation(AIStation.GetStationID(stn)), 0, 2), "un:" + upgrade_need);
		}

		if(upgrade_need > 200)
		{
			Log.Info("Look for airport upgrades for connection " + this.GetName(), Log.LVL_INFO);
			// Want to upgrade airports

			// Check if there is anything to upgrade to
			local airport_type_list = GetAirportTypeList_AllowedAndBuildable();
			if(!has_small)
			{
				// Don't allow "upgrading" to a small airport, if all airports are large.
				airport_type_list.Valuate(Airport.IsSmallAirportType);
				airport_type_list.KeepValue(0);
			}

			airport_type_list.Valuate(AIAirport.GetPrice);
			airport_type_list.KeepBelowValue(AICompany.GetBankBalance(AICompany.COMPANY_SELF) - (2 + (small_count == 1? -1 : 0) + g_num_connection_airport_upgrade * 2) * 3); // can afford airport?  (last * 3 is to be extra sure to have the money also when aircrafts have been moved away to the dump airport)

			airport_type_list.Valuate(Helper.ItemValuator); // sort by item again
			if(airport_type_list.IsEmpty())
			{
				Log.Warning("There are no airports to upgrade to for " + this.GetName(), Log.LVL_SUB_DECISIONS);
				return;
			}

			local upgrade_list = [];
			local i = 0;
			foreach(station_tile in this.station)
			{
				if(station_tile == null) {
					++i;
					continue;
				}

				local town_id = this.node[i].GetClosestTown();
				if(!Town.TownRatingAllowStationBuilding(town_id)) // Skip towns with too low town rating
				{
					Log.Info("Town has too low town rating " + AITown.GetName(this.node[i].GetClosestTown()), Log.LVL_INFO);
					++i;
					continue;
				}

				local curr_ap_type = AIAirport.GetAirportType(station_tile);
				local curr_noise_contrib = AIAirport.GetNoiseLevelIncrease(station_tile, curr_ap_type);
				local noise_budget = AITown.GetAllowedNoise(town_id) + curr_noise_contrib;
				local better_list = [];
				foreach(ap_type in airport_type_list)
				{
					if(ap_type == curr_ap_type)
						continue;

					// Noise constraints?
					local budget_overrun = GetNoiseBudgetOverrun();
					if(AIAirport.GetNoiseLevelIncrease(station_tile, ap_type) - budget_overrun > noise_budget) 
					{
						Log.Info("Airport type to noisy for " + this.node[i].GetName(), Log.LVL_INFO);
						continue;
					}

					if(IsAirportTypeBetterThan(ap_type, curr_ap_type))
					{
						better_list.append(ap_type);
					}
				}

				if(better_list.len() > 0)
				{
					// upgrade
					local upgrade = { airport_tile = station_tile,
							node = this.node[i],
							index = i,
							from_type = curr_ap_type,
							to_type_list = better_list // give a list of all airports that are better than current (as the best one might be to large/noisy to build
						};

					upgrade_list.append(upgrade);
				}
				else
				{
					Log.Info("No better airport type was found for " + this.node[i].GetName(), Log.LVL_INFO);
				}

				++i;
			}

			if(upgrade_list.len() > 0)
			{
				// one or more airport want to be upgraded
				Log.Info("One or more airports will be upgraded for connection " + this.GetName(), Log.LVL_INFO);
				this.airport_upgrade_list = upgrade_list;

				// Initialize upgrading member vars
				this.airport_upgrade_list = upgrade_list;
				this.airport_upgrade_failed = false;
				this.airport_upgrade_start = AIDate.GetCurrentDate();
				++g_num_connection_airport_upgrade;

				// store airport upgrading state
				this.SetState(Connection.STATE_AIRPORT_UPGRADE);
				local veh_list = this.GetVehicles();
				foreach(veh, _ in veh_list)
				{
					ClueHelper.StoreInVehicleName(veh, "ap upgrade");
				}

				// start upgrading (will not complete it though, if it has to wait on vehicles)
				this.TryUpgradeAirports();
			}
		}
	}
}

function Connection::TryUpgradeAirports()
{
	// Check state
	if(this.state != Connection.STATE_AIRPORT_UPGRADE)
	{
		return false;
	}

	if(this.station[0] == null || this.station[1] == null)
		return false;

	// Abort upgrading if there are no upgrade instructions (eg. when loading a game with a connection in upgrade state)
	if(this.airport_upgrade_list == null || this.airport_upgrade_list.len() == 0)
	{
		this.StopAirportUpgrading();
		return;
	}

	Log.Info("Try to upgrade airports of connection " + this.GetName(), Log.LVL_INFO);

	// Get an airport where we can dump the aircrafts while upgrading airports
	local dump_airport = GetAircraftDumpAirport(!this.HasSmallAirport());
	if(dump_airport == null)
	{
		Log.Warning("Failed to get airport where aircrafts could be sent while upgrading", Log.LVL_INFO);
		this.last_airport_upgrade_fail = AIDate.GetCurrentDate();
		this.StopAirportUpgrading();
		return;
	}

	// Make sure all aircrafts are marked to remember that a upgrade is in process if a save/load gets in the way
	local veh_list = this.GetVehicles();
	foreach(veh, _ in veh_list)
	{
		if(ClueHelper.ReadStrFromVehicleName(veh) != "ap upgrade")
		{
			ClueHelper.StoreInVehicleName(veh, "ap upgrade");
		}
	}

	// Check if vehicles need to be sent to the dump airport
	if(!veh_list.IsEmpty())
	{
		// Add order to go to the dump airport at the end of order list (if it does not already exist)
		local vehicle_id = veh_list.Begin();
		Log.Info("Modifying order of: " + AIVehicle.GetName(vehicle_id), Log.LVL_DEBUG);
		if(!HasVehicleGoToAircraftDumpOrder(vehicle_id))
		{
			AIOrder.AppendOrder(vehicle_id, Airport.GetHangarTile(dump_airport), AIOrder.AIOF_STOP_IN_DEPOT);
		}
		else
			Log.Info("aircraft " + AIVehicle.GetName(vehicle_id) + " already has dump order", Log.LVL_DEBUG);

		// Send all aircrafts to dump airport
		foreach(veh, _ in veh_list)
		{
			Log.Info("skip order of " + AIVehicle.GetName(veh), Log.LVL_DEBUG);
			AIOrder.SkipToOrder(veh, AIOrder.GetOrderCount(veh) - 1);
		}
	}
	else
	{
		Log.Warning("Connection has no vehicles", Log.LVL_DEBUG);
	}


	// Go through upgrade list and see if any airport can be upgraded
	local done_airports = [];
	for(local i = 0; i < this.airport_upgrade_list.len(); ++i)
	{
		local upgrade = this.airport_upgrade_list[i];
		local station_id = AIStation.GetStationID(upgrade.airport_tile);

		// Check if there are aircrafts in the way
		{
			local tm = AITestMode();
			if(Airport.GetNumAircraftsInAirportQueue(station_id, false) > 0 ||  // wait for empty holding queue
					!AITile.DemolishTile(upgrade.airport_tile))       // wait until airport is clear of airplanes
			{
				continue; // skip upgrading this airport for now
			}
		}

		// Airport is ready to be upgraded
		Log.Info("Do upgrade airport", Log.LVL_DEBUG);

		// Make sure the new airport accept/produce the wanted cargo
		local accept_cargo = -1;
		local produce_cargo = -1;
		if(upgrade.node.IsCargoAccepted())
			accept_cargo = upgrade.node.cargo_id;
		if(upgrade.node.IsCargoProduced())
			produce_cargo = upgrade.node.cargo_id;

		local station_id = AIStation.GetStationID(upgrade.airport_tile);
		local result = Airport.UpgradeAirportInTown(upgrade.node.GetClosestTown(), station_id, upgrade.to_type_list, accept_cargo, produce_cargo);
		if(Result.IsSuccess(result))
		{
			// Update station tile
			local new_station_tile = AIStation.GetLocation(station_id);
			local new_hangar_tile = Airport.GetHangarTile(station_id);
			this.station[upgrade.index] = new_station_tile;
			this.depot[upgrade.index] = new_hangar_tile;

			done_airports.append(i);
			Log.Info("Airport has been upgraded", Log.LVL_INFO);
		}
		else 
		{
			this.airport_upgrade_failed = true;
			this.last_airport_upgrade_fail = AIDate.GetCurrentDate();

			if(result == Result.REBUILD_FAILED)
			{
				this.station[upgrade.index] = null;
				this.depot[upgrade.index] = null;

				// old airport was removed, but couldn't be rebuilt => close connection
				Log.Error("Tried to upgrade airport, but something went wrong after the old airport was removed and", Log.LVL_INFO);
				Log.Error("a new airport of the old type couldn't be built. The connection will be closed down.", Log.LVL_INFO);
				this.CloseConnection();
				return;
			}
			else if(result == Result.MONEY_TOO_LOW)
			{
				Log.Info("Tried to upgrade airport, money was too low => stop upgrading", Log.LVL_INFO);
				this.StopAirportUpgrading();
				return;
			}
			else if(result == Result.TOWN_RATING_TOO_LOW)
			{
				Log.Info("Tried to upgrade airport, town rating was too low => don't try this airport more", Log.LVL_INFO);
				done_airports.append(i);
			}
			else if(result == Result.TOWN_NOISE_ACCEPTANCE_TOO_LOW)
			{
				Log.Info("Tried to upgrade airport, town noise acceptance was too low => don't try this airport more", Log.LVL_INFO);
				done_airports.append(i);
			}
			else
			{
				Log.Info("Tried to upgrade airport, but failed due to other error", Log.LVL_INFO);
			}
		}
	}

	// How much have been done?
	if(done_airports.len() > 0) // at least one airport is done
	{
		if(done_airports.len() == this.airport_upgrade_list.len()) // all airports are done
		{
			this.airport_upgrade_list = null;

			// Set state back to active
			this.StopAirportUpgrading();
		}
		else
		{
			// at least one airport has been upgraded, but not all.

			// remove the done airports from this.airport_upgrade_list so that it will not be upgraded again
			for(local i = done_airports.len() -1; i >= 0; --i)
			{
				local remove_idx = done_airports[i];
				this.airport_upgrade_list.remove(remove_idx);
			}
		}
	}

	// Stop upgrading if it has took too long
	if(this.airport_upgrade_list != null && this.airport_upgrade_start != null && this.airport_upgrade_start + 365 < AIDate.GetCurrentDate()) 
	{
		// have tried to upgrade for more than a year
		this.StopAirportUpgrading();
	}
}

function Connection::StopAirportUpgrading()
{
	if(this.state != Connection.STATE_AIRPORT_UPGRADE)
		return;

	// Re-enable aircrafts
	local veh_list = this.GetVehicles();
	foreach(vehicle_id, _ in veh_list)
	{
		// Remove the order to go to the dump airport
		//
		// all vehicles *should* share orders, but check all just in case
		Log.Info("Modifying (2) order of: " + AIVehicle.GetName(vehicle_id), Log.LVL_DEBUG);
		for(local i = 0; i < AIOrder.GetOrderCount(vehicle_id); ++i)
		{
			if(IsGoToAircraftDumpOrder(vehicle_id, i))
			{
				AIOrder.RemoveOrder(vehicle_id, i);
				--i;
			}
		}

		// randomize orders to distribute airplanes a bit
		if(AIVehicle.IsStoppedInDepot(vehicle_id))
		{
			Log.Info("skip order of " + AIVehicle.GetName(vehicle_id), Log.LVL_DEBUG);
			AIOrder.SkipToOrder(vehicle_id, AIBase.RandRange(AIOrder.GetOrderCount(vehicle_id)));
		}

		if(AIVehicle.IsStoppedInDepot(vehicle_id))
			AIVehicle.StartStopVehicle(vehicle_id);

		ClueHelper.StoreInVehicleName(vehicle_id, "active");
	}

	Log.Info("done ", Log.LVL_DEBUG);

	if(this.state == STATE_AIRPORT_UPGRADE) --g_num_connection_airport_upgrade;
	this.SetState(STATE_ACTIVE);

	// Take adventage of the new airport (especially in case of upgrading from small to large)
	this.FindNewDesiredEngineType();
	this.MassUpgradeVehicles();

	this.airport_upgrade_list = null;
	this.airport_upgrade_failed = false;
	this.airport_upgrade_start = null;
}


function Connection::ManageVehicles()
{
	// Don't manage vehicles for failed connections.
	if(this.state != Connection.STATE_ACTIVE)
		return;

	Log.Info("Connection::ManageVehicles called for connection: " + this.GetName(), Log.LVL_DEBUG);

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
		if(this.station[0] != null)
			Helper.SetSign(Tile.GetTileRelative(this.station[0], 3, 2), "manage");
		if(this.station[1] != null)
			Helper.SetSign(Tile.GetTileRelative(this.station[1], 3, 2), "manage");


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

		local tmp = this.GetMinMaxRatingWaiting();
		local min_rating = tmp.min_rating;
		local max_rating = tmp.max_rating;
		local max_waiting = tmp.max_waiting;

		Log.Info("connection income: " + income, Log.LVL_INFO);
		Log.Info("connection mean income: " + mean_income, Log.LVL_INFO);
		Log.Info("connection long time mean income: " + long_time_mean_income, Log.LVL_INFO);
		Log.Info("connection max station usage: " + this.max_station_usage, Log.LVL_INFO);
		Log.Info("connection max station tile usage: " + this.max_station_tile_usage, Log.LVL_INFO);

		// Try to repair road connections from time to time
		if(this.transport_mode == TM_ROAD)
		{
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
				g_timers.repair_connection.Start();
				if(RepairRoadConnection())
					this.long_time_mean_income = this.long_time_mean_income * 7 / 10; // Fake a reduction of long time mean in order to prevent or make management hell less likely to happen.
				this.last_repair_route = AIDate.GetCurrentDate();
				g_timers.repair_connection.Stop();
			}
		}

		this.long_time_mean_income = (this.long_time_mean_income * 9 + income) / 10;

		// Unless the vehicle list is empty, only buy/sell if we have not bought/sold anything the last 30 days.
		local recently_sold = last_bus_sell != null && last_bus_sell + 30 > now;
		local recently_bought = last_bus_buy != null && last_bus_buy + 30 > now;
		if( veh_list.Count() == 0 ||
				(!recently_sold && !recently_bought) )
		{
			// Sell check
			local sell_check = false;
			local too_high_usage = false;
			switch(this.transport_mode)
			{
				case TM_ROAD:
					too_high_usage = this.max_station_usage > 195 || this.max_station_tile_usage > 220;
					sell_check = income < 0 || too_high_usage || max_waiting < 10;
					break;

				case TM_AIR:
					too_high_usage = this.max_station_usage > 220;
					sell_check = income < 0 || too_high_usage || max_waiting < 20;
					break;

				case TM_RAIL:
					too_high_usage = this.max_station_usage > 200;
					sell_check = income < 0 || too_high_usage || max_waiting < 20;
					break;

				case TM_WATER:
					too_high_usage = false;
					sell_check = income < 0 || max_waiting < 20;
			}

			local sell_min_rating = veh_list.Count() <= 2? 50 : 25; // limit with 2 vehicles is 50, otherwise 25 in rating

			sell_check = sell_check && veh_list.Count() > 1 && min_rating > sell_min_rating;

			if(sell_check)
			{
				local num_to_sell = Helper.Max(1, veh_list.Count() / 8);
				
				if(income < 0)
				{
					local engine_type_id = AIVehicle.GetEngineType(veh_list.Begin());
					local running_cost = AIEngine.GetRunningCost(engine_type_id);
					num_to_sell = Helper.Min(veh_list.Count() - 1, (-income) / running_cost + 1);
				}
				else if(too_high_usage)
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
				local capacity_left = false;
				local waiting_limit = 0;
				local buy_size = 0;
				switch(this.transport_mode)
				{
					case TM_ROAD:
						capacity_left = this.max_station_usage < 170 && this.max_station_tile_usage < 200;
						waiting_limit = 40  + veh_list.Count() * 3;
						buy_size = 100;
						break;

					case TM_AIR:
						capacity_left = this.max_station_usage < 160;
						waiting_limit = 60 + veh_list.Count() * 8; // todo: tweak
						buy_size = 300;
						break;

					case TM_RAIL:
						capacity_left = this.max_station_usage < 200;
						waiting_limit = 40 + veh_list.Count() * 8; // todo: tweak
						buy_size = 300;
						break;

					case TM_WATER:
						capacity_left = true;
						waiting_limit = 40 + veh_list.Count() * 8; // todo: tweak
						buy_size = 400;
						break;
				}

				local buy_rating_limit = veh_list.Count() <= 2? 50 : 20;
				if(veh_list.Count() == 0 || 
					(capacity_left &&
					 (max_waiting > waiting_limit || min_rating < buy_rating_limit)) )
				{
					// Buy a new vehicle
					Log.Info("Manage vehicles: decided to Buy a new bus", Log.LVL_INFO);
					local engine = this.FindEngineModelToBuy();
					local num = 1 + (max_waiting - waiting_limit) / buy_size; // if buy reason is low rating, only one vehicle is bought
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

		local very_high_usage = false;
		switch(this.transport_mode)
		{
			case TM_ROAD:
				very_high_usage = this.max_station_usage >= 220 || this.max_station_tile_usage >= 235; // make sure these values are higher than for sell_check.
				Log.Info("max usage: " + this.max_station_usage + " max tile: " + this.max_station_tile_usage, Log.LVL_INFO);
				break;

			case TM_AIR:
				very_high_usage = this.max_station_usage > 400;
				break;

			case TM_RAIL:
				very_high_usage = this.max_station_usage > 300; // tweak
				break;
		}

		Log.Info("min_rating = " + min_rating + " max_rating = " + max_rating + " max_waiting = " + max_waiting + " very_high_usage = " + very_high_usage, Log.LVL_INFO);
		if(very_high_usage)
			FullLoadAtStations(false);
		else if(this.IsTownOnly())
		{
			if(this.transport_mode == TM_ROAD)
				FullLoadAtStations((min_rating < 55 || max_rating < 75) && max_waiting < 55);
			else
				FullLoadAtStations((min_rating < 55 || max_rating < 75) && max_waiting < 150);
		}
		else
			FullLoadAtStations(true);

		// Unset manage signs
		if(this.station[0] != null)
			Helper.SetSign(Tile.GetTileRelative(this.station[0], 3, 2), "");
		if(this.station[1] != null)
			Helper.SetSign(Tile.GetTileRelative(this.station[1], 3, 2), "");
	}
	else
	{
		Log.Info("Connection::ManageVehicles: to early to manage", Log.LVL_SUB_DECISIONS);
	}	
}

function Connection::GetMinMaxRatingWaiting()
{
	local min_rating = 100;
	local max_rating = 0;
	local max_waiting = 0;
	local station_tile = null;
	foreach(station_tile in this.station)
	{
		if(station_tile == null) continue;
		
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

	return { min_rating = min_rating,
		max_rating = max_rating,
		max_waiting = max_waiting };
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
	if(station[0] != null && station[1] != null)
	{
		local veh0 = AIVehicleList_Station(AIStation.GetStationID(station[0]));
		local veh1 = AIVehicleList_Station(AIStation.GetStationID(station[1]));

		veh0.KeepList(veh1);
		local intersect = veh0;

		return intersect;
	}
	else if(AIStation.IsValidStation(station_statistics[0].station_id) && AIStation.IsValidStation(station_statistics[1].station_id))
	{
		// A station might just have disappeared, but has its station sign left
		local veh0 = AIVehicleList_Station(station_statistics[0].station_id);
		local veh1 = AIVehicleList_Station(station_statistics[1].station_id);

		veh0.KeepList(veh1);
		local intersect = veh0;

		return intersect;
	}
	else if(station[0] != null)
	{
		return AIVehicleList_Station(AIStation.GetStationID(station[0]));
	}
	else if(station[1] != null)
	{
		return AIVehicleList_Station(AIStation.GetStationID(station[1]));
	}
	else
	{
		return AIList();
	}
}

function Connection::GetBrokenVehicles()
{
	local veh0 = null;
	local veh1 = null;
	if(station[0] != null && station[1] != null)
	{
		veh0 = AIVehicleList_Station(AIStation.GetStationID(station[0]));
		veh1 = AIVehicleList_Station(AIStation.GetStationID(station[1]));
	}
	else if(AIStation.IsValidStation(station_statistics[0].station_id) && AIStation.IsValidStation(station_statistics[1].station_id))
	{
		// A station might just have disappeared, but has its station sign left
		veh0 = AIVehicleList_Station(station_statistics[0].station_id);
		veh1 = AIVehicleList_Station(station_statistics[1].station_id);
	}

	local union = AIList();
	if(veh0 != null) union.AddList(veh0);
	if(veh1 != null) union.AddList(veh1);

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
				local service_flag = this.GetDepotServiceFlag();

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
	if(station[0] == null || station[1] == null) return false;

	Log.Info("Repairing connection", Log.LVL_INFO);
	local front1 = Road.GetRoadStationFrontTile(station[0]);
	local front2 = Road.GetRoadStationFrontTile(station[1]);

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
	local small_airport = this.HasSmallAirport();
	local articulated_rvs = this.HasMagicDTRSStops();
	local best_engine = Strategy.FindEngineModelToBuy(this.cargo_type, TransportModeToVehicleType(this.transport_mode), small_airport, articulated_rvs); 
	
	Log.Info(this.GetName() + " have small airport = " + small_airport, Log.LVL_DEBUG);

	if(this.desired_engine != null)
		Log.Info(Strategy.EngineBuyScore(best_engine) + " | " + (Strategy.EngineBuyScore(this.desired_engine) * 1.15), Log.LVL_SUB_DECISIONS);

	// Change desired engine only if the best one is X % better than the old one or the old one
	// is no longer buildable.
	if(this.desired_engine == null || !AIEngine.IsBuildable(this.desired_engine) ||
			Strategy.EngineBuyScore(best_engine) > Strategy.EngineBuyScore(this.desired_engine) * 1.15)
	{
		if(this.desired_engine != null)
			Log.Info("Connection " + this.GetName() + " has changed desired engine from " + AIEngine.GetName(this.desired_engine) + " to " + AIEngine.GetName(best_engine), Log.LVL_SUB_DECISIONS);
		else
			Log.Info("Connection " + this.GetName() + " has changed desired engine from " + "[no engine]" + " to " + AIEngine.GetName(best_engine), Log.LVL_SUB_DECISIONS);
		this.desired_engine = best_engine;
	}
}

function Connection::MassUpgradeVehicles()
{
	// Require to be in state ACTIVE or SUSPENDED in order to mass-upgrade
	// vehicles
	if(this.state != Connection.STATE_ACTIVE && this.state != Connection.STATE_SUSPENDED)
		return;

	Log.Info("Check if connection " + node[0].GetName() + " - " + node[1].GetName() + " has any vehicles to mass-upgrade to " + AIEngine.GetName(this.desired_engine), Log.LVL_SUB_DECISIONS);

	// Make a list of vehicles of this connection that are not
	// of the desired vehicle type
	local vehicle_list = this.GetVehicles();
	local all_veh_count = vehicle_list.Count();
	vehicle_list.Valuate(AIVehicle.GetEngineType);
	vehicle_list.RemoveValue(this.desired_engine);
	local wrong_type_count = vehicle_list.Count();

	Log.Info("all: " + all_veh_count + " wrong: " + wrong_type_count, Log.LVL_DEBUG);

	// No need to do anything if there are no vehicles of wrong type
	if(wrong_type_count == 0)
	{
		Log.Info("All vehicles already of desired engine type", Log.LVL_DEBUG);
		return;
	}

	Log.Info(wrong_type_count + " vehicles could be mass-upgraded", Log.LVL_DEBUG);

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
		{
			Log.Info("Can't afford to mass-upgrade any vehicles", Log.LVL_DEBUG);
			return;
		}
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

