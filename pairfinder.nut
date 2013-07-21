
/*
 * When computing produced - transported, this
 * factor gets multiplied with transported and
 * then divided by 100. 
 *
 * A value > 100 means that the AI will be 
 * discouraged to compete on resources with
 * other AIs
 */
TRANSPORTED_FACTOR_PERCENT <- 150;


class PairFinder {

	all_nodes = null;
	vehicle_type_cargos = null; // table with TM_* as key => list of cargos that VT accepts
	any_tm_cargoes = null; // => list of cargos than any VT can take
	air_cargo_max_range = null; // => list of max air range per cargo

	constructor()
	{
		all_nodes = [];
		vehicle_type_cargos = null;
	}

	function GetTransportModes(); // a list of transport modes that are allowed to use
	function UpdateVehicleCargoCapability(); // update member variables for which cargoes each vehicle type can transport

	function AddNodesSorted(desperateness, connection_list);

	// Helper functions to AddNodesSorted
	function AddTownNodes(desperateness, connection_list, node_heap, bonus_cargos);
	function AddIndustryNodes(desperateness, connection_list, node_heap, bonus_cargos);

	// returns {
	//   pair -> [source node, dest node]
	//   transport_mode -> TM_*
	// }
	function FindTwoNodesToConnect(maxDistance, desperateness, connection_list);

	static function TownDistanceIdealityValuator(town_id, node_tile);
	static function IndustryDistanceIdealityValuator(industry_id, node_tile);

	static function SquirrelListComperator_PairScore(pair1, pair2);

	static function IsPairNearExistingNetwork(node1, node2, connection_list);
	static function ExistingNetworkAreaPreCache(connection_list, desperateness);
}

function PairFinder::GetTransportModes()
{
	// transport modes to try for each pair
	local try_tm = [];
	local use_air = Vehicle.GetVehiclesLeft(AIVehicle.VT_AIR) >= MIN_VEHICLES_TO_BUILD_NEW;
	local use_road = Vehicle.GetVehiclesLeft(AIVehicle.VT_ROAD) >= MIN_VEHICLES_TO_BUILD_NEW;
	local use_air_only = !use_road && use_air;
	if(use_air)
		try_tm.append(TM_AIR);
	if(use_road)
		try_tm.append(TM_ROAD);

	return try_tm;
}
function PairFinder::UpdateVehicleCargoCapability()
{
	local tm_list = this.GetTransportModes();
	this.vehicle_type_cargos = {};
	this.any_tm_cargoes = AIList();
	foreach(tm in tm_list)
	{
		// Get a list of all cargoes that can be transported with current transport mode
		local available_cargos = AICargoList();
		available_cargos.Valuate(Engine.DoesEngineExistForCargo, TransportModeToVehicleType(tm), true, true, false);
		available_cargos.KeepValue(1);
		this.vehicle_type_cargos.rawset(tm, available_cargos);

		// Add cargoes to list of cargoes for which there is at least one transport mode that can transport them
		this.any_tm_cargoes.AddList(available_cargos);

		if(tm == TM_AIR)
		{
			// Get the aircraft range of the suggested planning engine for each cargo
			this.air_cargo_max_range = AIList();
			foreach(cargo, _ in available_cargos)
			{
				local engine = Strategy.FindEngineModelToPlanFor(cargo, AIVehicle.VT_AIR, false, true, -1);
				local max_range = AIEngine.GetMaximumOrderDistance(engine);
				Log.Info("Max range for " + AICargo.GetCargoLabel(cargo) + " is " + max_range + " using " + AIEngine.GetName(engine), Log.LVL_DEBUG);

				// Check that we can afford two airports + engine for this cargo
				local airport_type = Strategy.GetAffordedAirportTypeForNewConnection(max_range, cargo);


				if(airport_type != null)
				{
					this.air_cargo_max_range.AddItem(cargo, max_range);
				}
				else
				{
					this.air_cargo_max_range.AddItem(cargo, -1);
					Log.Info(".. but 2 airports + 1 aircraft can't be afforded", Log.LVL_DEBUG);
				}
			}
		}
	}
}
function PairFinder::AddNodesSorted(desperateness, connection_list)
{
	//// Get settings ////
	/*
	 * 0 = Towns only
	 * 1 = Industries only
	 * 2 = Both towns and industries
	 *
	 * -1 = not set
	 *
	 * See info.nut
	 */
	local allowed_connection_types = AIController.GetSetting("connection_types");

	// Default to only towns if a non-supported value is detected
	// => backward compatibility
	if(allowed_connection_types != 0 &&
		allowed_connection_types != 1 &&
		allowed_connection_types != 2)
	{
		allowed_connection_types = 0;
	}

	Log.Info("allowed connection types: " + allowed_connection_types, Log.LVL_DEBUG);

	// Some cargos may have a bonus
	// Only give a bonus if we have a profit so that the bonus doesn't
	// cause the AI to get a first route with too low profit.
	local my_company = AICompany.ResolveCompanyID(AICompany.COMPANY_SELF);
	local profit = AICompany.GetQuarterlyIncome(my_company, AICompany.CURRENT_QUARTER) - AICompany.GetQuarterlyExpenses(my_company, AICompany.CURRENT_QUARTER);
	local cargo_bonus = AIList();
	if (profit > 2000 && AICompany.GetQuarterlyCompanyValue(my_company, AICompany.CURRENT_QUARTER) > 1000) {
		local cargo_goal = g_no_car_goal.GetGoalCargoArray();
		if (cargo_goal != null) {
			foreach(cargo in cargo_goal) {
				local to_transport = max(0, cargo.goal - cargo.transported);
				local bonus = -1 * to_transport * 1000 / cargo.goal
				cargo_bonus.AddItem(cargo.cargo, bonus);
			}
		}
	}
	

	//// Add Nodes to Fibonacci Heap ////
	local node_heap = FibonacciHeap();

	if(allowed_connection_types == 0 || allowed_connection_types == 2)
	{
		Log.Info("connect towns", Log.LVL_DEBUG);
		AddTownNodes(desperateness, connection_list, node_heap, cargo_bonus);
	}
	if(allowed_connection_types == 1 || allowed_connection_types == 2)
	{
		// Temporarily code to require road for industry nodes for this release as the ongoing work to support aircraft
		// at industries is not good enough yet
		local use_road = Vehicle.GetVehiclesLeft(AIVehicle.VT_ROAD) >= MIN_VEHICLES_TO_BUILD_NEW;
		if(use_road)
		{
			Log.Info("connect industries", Log.LVL_DEBUG);
			AddIndustryNodes(desperateness, connection_list, node_heap, cargo_bonus);
		}
	}

	//// Move nodes to Squirrel List ////
	all_nodes.clear();

	while(node_heap.Count() > 0)
	{
		local node = node_heap.Pop();
		all_nodes.append(node);
	}
}

function FilterCargoList(cargo_list, desperateness)
{
	// In NoCarGoal games, only use non-goal cargos if we are desperate (or all goals
	// have been completed)
	if(g_no_car_goal.IsNoCarGoalGame() && desperateness <= 1)
	{
		local filter_completed = g_no_car_goal.GetNUncompletedGoals() > 0;
		g_no_car_goal.FilterCargoList(cargo_list, filter_completed);
	}
}

function PairFinder::AddTownNodes(desperateness, connection_list, node_heap, bonus_cargos)
{
	local town_list = AITownList();
	local allow_competition = AIController.GetSetting("allow_competition");
	foreach(town_id, _ in town_list)
	{
		// Ignore towns with too low rating
		if(!Town.TownRatingAllowStationBuilding(town_id))
			continue;

		// Add nodes for all cargos which can be produced/accepted by towns
		local produced_cargo_list = Helper.GetTownProducedCargoList();
		local accepted_cargo_list = Helper.GetTownAcceptedCargoList();

		// Only consider cargos if there is an engine available to transport it
		produced_cargo_list.KeepList(this.any_tm_cargoes);
		accepted_cargo_list.KeepList(this.any_tm_cargoes);
/*		produced_cargo_list.Valuate(Engine.DoesEngineExistForCargo, AIVehicle.VT_ROAD, true, true, false);
		produced_cargo_list.KeepValue(1);
		accepted_cargo_list.Valuate(Engine.DoesEngineExistForCargo, AIVehicle.VT_ROAD, true, true, false);
		accepted_cargo_list.KeepValue(1);
*/

		local cargo_list = AIList();

		cargo_list.AddList(produced_cargo_list);
		cargo_list.AddList(accepted_cargo_list);

		// Filter list with respect to Goals
		FilterCargoList(cargo_list, desperateness);

		foreach(cargo_id, _ in cargo_list)
		{
			// Skip if the cargo is already transported from the town and competition is not allowed
			if(!allow_competition && AITown.GetLastMonthTransported(town_id, cargo_id) != 0)
				continue;

			local node = Node(town_id, -1, cargo_id);

			// Only actually append the node if it accepts/produces the cargo - dummy nodes do not make anyone happy
			if (node.IsCargoAccepted() || node.IsCargoProduced())
			{
				local bonus = 0;
				if (bonus_cargos.HasItem(cargo_id)) bonus = bonus_cargos.GetValue(cargo_id);
				node_heap.Insert(node, -1 * node.GetCargoValueAvailability() + bonus);
			}
		}

	}
}

function PairFinder::AddIndustryNodes(desperateness, connection_list, node_heap, bonus_cargos)
{
	local industry_list = AIIndustryList();
	local cargo_list = AICargoList();

	// Only consider cargos if there is an engine available to transport it
	cargo_list.KeepList(this.any_tm_cargoes);
/*	cargo_list.Valuate(Engine.DoesEngineExistForCargo, AIVehicle.VT_ROAD, true, true, false);
	cargo_list.KeepValue(1);*/

	// Filter list with respect to Goals
	FilterCargoList(cargo_list, desperateness);

	Log.Info("cargo_list size: " + cargo_list.Count(), Log.LVL_DEBUG);

	if (cargo_list.IsEmpty()) return;

	local t_start = 0;
	local t_end = 0;

	local num_industries_added = 0;
	local MAX_NUM_INDUSTRIES = 1000;
	local industry_list_length = industry_list.Count();
	local add_all = industry_list_length <= MAX_NUM_INDUSTRIES;
	local i_industry = -1;

	Log.Info("industry_list size: " + industry_list_length, Log.LVL_DEBUG);
	Log.Info("add all: " + add_all, Log.LVL_DEBUG);

	local allow_competition = AIController.GetSetting("allow_competition");
	Log.Info("allow competition: " + allow_competition, Log.LVL_DEBUG);

	foreach(industry_id, _ in industry_list)
	{
		// Ignore industries in towns with too low rating
		if(!Town.TownRatingAllowStationBuilding(AITile.GetClosestTown(AIIndustry.GetLocation(industry_id))))
			continue;

		if(!add_all)
		{
			++i_industry;

			local add = AIBase.Chance(MAX_NUM_INDUSTRIES, industry_list_length);

			// Check if the amount needed is less than or equal to the amount of industries left in the list
			if(MAX_NUM_INDUSTRIES - num_industries_added <= industry_list_length - i_industry)
				add_all = true; // if so, just add all the remaining industries

			if(!add)
				continue;
		}

		foreach(cargo_id, _ in cargo_list)
		{
			if (AIIndustry.IsCargoAccepted(industry_id, cargo_id) == AIIndustry.CAS_ACCEPTED || // is the cargo accepted
				(
					AIIndustry.GetLastMonthProduction(industry_id, cargo_id) > 0 // or cargo is it produced
					&&
					(allow_competition || AIIndustry.GetLastMonthTransported(industry_id, cargo_id) == 0) // and competition is allowed or there is no transportation
				) )
			{
				local node = Node(-1, industry_id, cargo_id);
				local bonus = 0;
				if (bonus_cargos.HasItem(cargo_id)) bonus = bonus_cargos.GetValue(cargo_id);
				node_heap.Insert(node, -1 * node.GetCargoValueAvailability() + bonus);
			}
		}
	}
}

function PairFinder::CanAffordAirConnection()
{
	foreach(cargo, range in this.air_cargo_max_range)
	{
		if(range != -1)
		{
			Log.Info("Pairfinder: Can afford air connection for " + AICargo.GetCargoLabel(cargo), Log.LVL_DEBUG);
			return true;
		}
	}

	Log.Info("Pairfinder: Can't afford air connections", Log.LVL_INFO);
	return false; 
}

function PairFinder::FindTwoNodesToConnect(desperateness, connection_list)
{
	// Rebuild cargo/vehicle availability
	this.UpdateVehicleCargoCapability();

	// Rebuild the list of nodes
	this.AddNodesSorted(desperateness, connection_list);
	Log.Info("a total of " + all_nodes.len() + " nodes has been added", Log.LVL_SUB_DECISIONS);
	Log.Info("all nodes has been sorted by cargo value availability", Log.LVL_DEBUG);

	Log.Info("desperateness: " + desperateness, Log.LVL_DEBUG);

	if(all_nodes.len() == 0)
	{
		Log.Info("No locations to transport between was found. This can happen if there are no buses/lories available or if there is nothing more to connect.", Log.LVL_SUB_DECISIONS);
		return null;
	}

	// transport modes to try for each pair
	local try_tm = [];
	local use_air = Vehicle.GetVehiclesLeft(AIVehicle.VT_AIR) >= MIN_VEHICLES_TO_BUILD_NEW && this.CanAffordAirConnection();
	local use_road = Vehicle.GetVehiclesLeft(AIVehicle.VT_ROAD) >= MIN_VEHICLES_TO_BUILD_NEW;
	local use_air_only = !use_road && use_air;
	if(use_air)
		try_tm.append(TM_AIR);
	if(use_road)
		try_tm.append(TM_ROAD);

	Log.Info("Pairfinder: Use air = " + use_air, Log.LVL_INFO);
	Log.Info("Pairfinder: Use road = " + use_road, Log.LVL_INFO);

	if(try_tm.len() == 0)
	{
		Log.Warning("Pairfinder: No transport mode possible", Log.LVL_INFO);
		return null;
	}

	// Get min noise needed for aircraft
	local airport_noise = 0;
	if(use_air)
	{
		local airport_type_list = GetAirportTypeList_AllowedAndBuildable();
		airport_type_list.Valuate(Airport.GetAirportTypeNoiseLevel);
		airport_type_list.Sort(AIList.SORT_BY_VALUE, AIList.SORT_ASCENDING);
		airport_noise = airport_type_list.GetValue(airport_type_list.Begin());
	}

	local aircraft_cargos = AICargoList();
	aircraft_cargos.Valuate(Engine.DoesEngineExistForCargo, AIVehicle.VT_AIR);
	aircraft_cargos.KeepValue(1);

	// Get the ideal length

	// TODO: Get ideal distance per cargo type for each vehicle type
	/*{
		local cargo_id = 0;
		local engine_id = Strategy.FindEngineModelToPlanFor(cargo_id, AIVehicle.VT_ROAD);
		local ideal_pax_distance = Engine.GetIdealTransportDistance(engine_id, cargo_id, -1);

		//Log.Info("Plan for engine " + AIEngine.GetName(engine_id) + " which has an ideal transport distance of " + ideal_pax_distance);
	}*/

	local top_source_nodes = [];

	local i = -1;
	foreach(node in all_nodes)
	{
		if(!node.IsCargoProduced())
			continue;

		// Only accept nodes as sources if they are not in use for the given cargo
		if(!Node.IsNodeInConnectionList(connection_list, node))
		{
			++i;
			top_source_nodes.append(node);
			Log.Info("top node: " + node.GetName(), Log.LVL_SUB_DECISIONS);
			if (i >= 8 * (1 + desperateness)) break;
		}
	}

	local global_best_pairs = FibonacciHeap();

	// Get the setting if the AI should expand new connections local to existing ones or simply look at the entire map.
	local setting_expand_local = AIController.GetSetting("expand_local");
	local existing_network_area_cached = null;
	if(setting_expand_local)
	{
		existing_network_area_cached = PairFinder.ExistingNetworkAreaPreCache(connection_list, desperateness);
	}

	// Give a bonus to cargos that help achieving a goal
	local bonus_cargos = AIList();
	if(g_no_car_goal.IsNoCarGoalGame()) {
		bonus_cargos = AICargoList();
		FilterCargoList(bonus_cargos, 0);
	}

	// Find a good pair using one of the top-producing nodes
	foreach(source_node in top_source_nodes)
	{
		local max_ideality_distance = 50; // accept max 50 tiles more/less than ideal distance

		Log.Info("Source " + source_node.GetName(), Log.LVL_DEBUG);

		// Look for nearby nodes that accept this cargo
		local local_best_pairs = FibonacciHeap();
		local i = -1;
		foreach(dest_node in all_nodes)
		{
			++i;
			if(dest_node.cargo_id != source_node.cargo_id) // only consider the node of the right cargo type of a given node
			{
				continue;
			}

			// In NoCarGoal games, only use non-goal cargos if we are desperate (or all goals
			// have been completed)
			if(g_no_car_goal.IsNoCarGoalGame() && desperateness <= 1 &&
					g_no_car_goal.GetNUncompletedGoals() > 0 &&
					!g_no_car_goal.IsGoalCargo(dest_node.cargo_id, true))
			{
				continue;
			}

			// Make sure to not connect the same node with itself
			if((dest_node.town_id != -1 && dest_node.town_id == source_node.town_id) ||
					(dest_node.industry_id != -1 && dest_node.industry_id == source_node.industry_id))
			{
				continue;
			}

			// If expand_local is enabled, reject all pairs that are not near the existing network.
			// This uses a simple boundary box model that should execute fairly fast. (essentially 2 API calls and 4 comparisons)
			if(setting_expand_local == 1 && !PairFinder.IsPairNearExistingNetwork(source_node, dest_node, existing_network_area_cached))
				continue;

			// Check that there exist no connection already between these two nodes
			local existing_connection = Node.FindNodePairInConnectionList(connection_list, source_node, dest_node);
			if(existing_connection != null)
			{
				// An existing non-failed or failed connection exist
				continue;
			}

			// If the dest offers cargo, then make sure we don't transport from the destination as well.
			if(dest_node.IsCargoProduced() && Node.IsNodeInConnectionList(connection_list, dest_node))
			{
				continue;
			}

			if(!dest_node.IsCargoAccepted())
				continue;

			// The selection of TM simply tries different TMs until a one that can handle the pair
			// is found. Later either the order of tests or some other way it should be randomized or improved
			local transport_mode = TM_INVALID;

			local dist = AIMap.DistanceManhattan(dest_node.GetLocation(), source_node.GetLocation());
			local possible_tms = [];
			foreach(tm in try_tm)
			{
				if(tm == TM_AIR)
				{
					// Don't use aircraft if there is no aircraft that
					// takes the given cargo
					if(!aircraft_cargos.HasItem(source_node.cargo_id))
						continue;

					// Don't consider connections that are longer than max range - 20 tiles 
					// to allow for some bad luck based on station placement.
					local order_dist = AIOrder.GetOrderDistance(AIVehicle.VT_AIR, dest_node.GetLocation(), source_node.GetLocation());
					local max_engine_range = this.air_cargo_max_range.GetValue(source_node.cargo_id);
					if(max_engine_range == -1) // -1 is PairFinder flag for cargos where 2 * airport + engine can't be afforded
						continue;
					if(max_engine_range != 0 && order_dist > max_engine_range - 20) // 0 is NoAI/OpenTTD flag for engines without limit
						continue;

					local budget_overrun = GetNoiseBudgetOverrun();
					local dest_airport_noise = airport_noise;
					local source_airport_noise = airport_noise;
				   	if (dest_node.IsIndustry())
					{
						local dist = AIMap.DistanceManhattan(dest_node.GetLocation(), AITown.GetLocation(dest_node.GetClosestTown()))
						dest_airport_noise /= max(1, (dist / 4));
					}
					if(source_node.IsIndustry())
					{
						local dist = AIMap.DistanceManhattan(source_node.GetLocation(), AITown.GetLocation(source_node.GetClosestTown()))
						source_airport_noise /= max(1, (dist / 4));
					}

					// check that connections allow airport noise
					if(AITown.GetAllowedNoise(source_node.GetClosestTown()) + budget_overrun < dest_airport_noise 
							|| AITown.GetAllowedNoise(dest_node.GetClosestTown()) + budget_overrun < source_airport_noise)
						continue;
				}

				local dist_deviation = Helper.Abs(g_tm_stats[tm].ideal_construct_distance - dist); // 0 = correct dist and then increasing for how many tiles wrong the distance is

				if (dist > g_tm_stats[tm].max_construct_distance * max(2, desperateness * 2) / 2)
					continue;

				if (dist_deviation > g_tm_stats[tm].max_construct_distance_deviation * max(2, desperateness * 2) / 2)
					continue;

				if (dist < g_tm_stats[tm].min_construct_distance * 2 / max(2, desperateness * 2 - 1))
					continue;

				// The pair can be connected using transport_mode
				possible_tms.append(tm);
			}

			// Couldn't find any transport mode?
			if(possible_tms.len() == 0)
				continue;

			// pick random transport mode
			transport_mode = possible_tms[AIBase.RandRange(possible_tms.len())];
			
			// Make sure picked transport mode is valid
			if(transport_mode == TM_INVALID)
				continue;

			local score = 0;

			// Penalty if the source industry can't increase production
			local no_prod_increase_penalty = 0;
			if(!AIIndustryType.ProductionCanIncrease( AIIndustry.GetIndustryType(source_node.industry_id) ))
			{
				no_prod_increase_penalty = 4000;
			}

			local prod_value = source_node.GetCargoValueAvailability();

			// Can the same cargo be transported the other way around?
			if(dest_node.GetCargoValueAvailability() > 0 && source_node.IsCargoAccepted())
			{
				local extra_value = dest_node.GetCargoValueAvailability();

				// Also give penalty if the "dest" can't increase in case it produces cargo
				if(AIIndustryType.ProductionCanIncrease( AIIndustry.GetIndustryType(dest_node.industry_id) ))
				{
					// Scale the penalty depending on how big the extra value is compared to the production by the main source.
					no_prod_increase_penalty += (4000 * (extra_value.tofloat() / prod_value.tofloat()) ).tointeger();
				}

				prod_value += extra_value;
			}

			// Check if the destination is already supplyed with cargo => bonus score
			local bonus = 0;
			if(dest_node.IsIndustry() && 
					ClueHelper.IsIndustryInConnectionList(connection_list, dest_node.industry_id, -1)) // -1 = any cargo
			{
				// Add a small bonus if we already supply the industry with some goods = has existing station
				bonus += 200;

				// Add a bigger bonus if the industry also produces some cargo (that can be transported)
				if(AICargoList_IndustryProducing(dest_node.industry_id))
					bonus += 2000;
			}

			// Give a significant bonus to cargos that help achieving a goal.
			if (bonus_cargos.HasItem(source_node.cargo_id)) {
				bonus += 3000;
			}

			// Make a combined score of the production value and distance deviation
			local dist_deviation = Helper.Abs(g_tm_stats[transport_mode].ideal_construct_distance - dist); // 0 = correct dist and then increasing for how many tiles wrong the distance is
			score = prod_value + (70 - dist_deviation) * 2 + bonus;

//			if(transport_mode == TM_AIR)
//				score += 1000; // at 2000, several air-links are built, but they aren't as good as the road links from an economical point of view.

			local_best_pairs.Insert([source_node, dest_node, score, transport_mode], -score);
		}

		// Copy the 5 best "local best" pairs to the "global best" list
		for(local j = 0; j < 5 && local_best_pairs.Count() > 0; ++j)
		{
			local pair = local_best_pairs.Pop();
			local score = pair[2] + AIBase.RandRange(pair[2] / 3); // Randomize the scores a bit
			global_best_pairs.Insert(pair, -score); 
		}
	}

	Log.Info("there is " + global_best_pairs.Count() + " 'global best pairs'", Log.LVL_SUB_DECISIONS);

	// Get the best pair of the best
	local best_pair = global_best_pairs.Pop();
	if(best_pair == null)
	{
		// Failed to find a connection => remove a failed connection

		// Remove out dated failed connections
		Node.RemoveOldFailedConnections(connection_list, /* min age: */ 5 * 365, /* min num: */ 1);
	
		return null;
	}

	Log.Info("top-list: ", Log.LVL_DEBUG);
	Log.Info(best_pair[0].GetName() + " - " + best_pair[1].GetName() + " using " + TransportModeToString(best_pair[3]) + " => score: " + best_pair[2], Log.LVL_DEBUG);
	while(global_best_pairs.Count() > 0)
	{
		local pair = global_best_pairs.Pop();
		Log.Info(pair[0].GetName() + " - " + pair[1].GetName() + " using " + TransportModeToString(pair[3]) + " => score: " + pair[2], Log.LVL_DEBUG);
	}

	Log.Info("best pair score: " + best_pair[2] + " (" + best_pair[0].GetName() + " - " + best_pair[1].GetName() + ")", Log.LVL_SUB_DECISIONS);

	return {
		pair = [best_pair[0], best_pair[1]], // [source node, dest node]
		transport_mode = best_pair[3],
	};
}

/*
 * Compute the bounding box of the current network in order to speedup the
 * IsPairNearExistingNetwork function that is called once for every pair that
 * make it to the top N pairs.
 */
/* static */ function PairFinder::ExistingNetworkAreaPreCache(connection_list, desperateness)
{
	if(connection_list == null || connection_list.len() == 0)
		return null;

	local min_x = 100000;
	local min_y = 100000;
	local max_x = 0;
	local max_y = 0;

	foreach(conn in connection_list)
	{
		local loc_list = [conn.node[0].GetLocation(), conn.node[1].GetLocation()];

		foreach(loc in loc_list)
		{
			local x = AIMap.GetTileX(loc);
			local y = AIMap.GetTileY(loc);
		
			if(x < min_x)
				min_x = x;
			if(x > max_x)
				max_x = x;	
			if(y < min_y)
				min_y = y;
			if(y > max_y)
				max_y = y;
		}
	}

	local allowed_distance = desperateness > 1 ? desperateness * 20 : desperateness * 5;

	min_x -= allowed_distance;
	min_y -= allowed_distance;
	max_x += allowed_distance;
	max_y += allowed_distance;

	local network_boundary = {
		min_x = min_x, 
		min_y = min_y, 
		max_x = max_x, 
		max_y = max_y
	};

	Helper.SetSign( AIMap.GetTileIndex(min_x, min_y), "min xy" );
	Helper.SetSign( AIMap.GetTileIndex(max_x, max_y), "max xy" );

	return {
		boundary = network_boundary, 
		connection_list = connection_list
	};
}

/* static */ function PairFinder::IsPairNearExistingNetwork(node1, node2, pre_cached_existing_network)
{
	if(node1 == null || node2 == null)
		return false;

	// If this is the first connection, it will be reported as it is within an existing
	// network area so that all locations are valid for the first connection.
	if(pre_cached_existing_network == null)
		return true;

	local loc_list = [node1.GetLocation(), node2.GetLocation()];
	local boundary = pre_cached_existing_network.boundary;
	
	local inside = false;
	foreach(loc in loc_list)
	{
		local x = AIMap.GetTileX(loc);
		local y = AIMap.GetTileY(loc);

		if(x >= boundary.min_x && x <= boundary.max_x &&
				y >= boundary.min_y && y <= boundary.max_y)
			inside = true;
	}
		
	// It is enough that one of the two nodes is inside or nearby the boundary box of the current network.
	return inside;
}

/* static */ function PairFinder::TownDistanceIdealityValuator(town_id, node_tile)
{
	return Helper.Abs(300 - AIMap.GetDistanceManhattan(AITown.GetLocation(town_id), node_tile));
}

/* static */ function PairFinder::IndustryDistanceIdealityValuator(industry_id, node_tile)
{
	return Helper.Abs(300 - AIMap.GetDistanceManhattan(AIIndustry.GetLocation(town_id), node_tile));
}

/* static */ function PairFinder::SquirrelListComperator_PairScore(pair1, pair2)
{
	if (pair1[2] < pair2[2])
		return 1;
	if (pair1[2] > pair2[2])
		return -1;
	return 0;
}

class Node {
	town_id = null;
	industry_id = null;
	node_location = null; // for detecting moved industries (close down + reused id)
	cargo_id = null;

	constructor(townId, industryId, cargoId)
	{
		this.town_id = townId;
		this.industry_id = industryId;
		this.cargo_id = cargoId;

		// Store the original location of industry/town in this.node_location
		if(AIIndustry.IsValidIndustry(industryId))
			this.node_location = AIIndustry.GetLocation(industryId);
		else if(AITown.IsValidTown(townId))
			this.node_location = AITown.GetLocation(townId);
		else
			this.node_location = -1;
	}

	function SaveToString();
	static function CreateFromSaveString(save_str);

	// Compares town/industry id + cargo_id
	function IsEqualTo(node);

	// If no id is given (id == null), then the functions check if the node is any town/industry. Else it checks if it is a specific town id or industry id.
	function IsTown(town_id = null);
	function IsIndustry(industry_id = null);

	function HasNodeDissapeared();

	function GetName();
	function GetLocation();
	function GetClosestTown();
	/*function GetDistanceManhattan(tile);*/

	// Checks the LastMonthProduction + Transported
	function GetLastMonthProduction();
	function GetCargoAvailability();
	function GetCargoValueAvailability();
	
	// Checks if cargo is accepted or produced at all
	function IsCargoAccepted(); // boolean
	function IsCargoProduced(); // boolean

	static function SquirrelListComperator_CargoValueAvailability(node1, node2);

	static function IsNodeInConnectionList(connection_list, node);
	static function FindNodePairInConnectionList(connection_list, node1, node2); // returns the matching connection object or null

	static function RemoveOldFailedConnections(connection_list, min_age, min_num); // remove old failed connections so that a new attempt can be made
}

function Node::IsEqualTo(node)
{
	// The idea is that if both nodes has invalid town or industry their value shouldn't
	// be compared. It is enough to check one of them for validity though. 
	return (AITown.IsValidTown(this.town_id) && this.town_id == node.town_id) ||
		(AIIndustry.IsValidIndustry(this.industry_id) && this.industry_id == node.industry_id);
}

function Node::IsTown(town_id = null)
{
	return AITown.IsValidTown(this.town_id) && (town_id == null || this.town_id == town_id);
}

function Node::IsIndustry(industry_id = null)
{
	return AIIndustry.IsValidIndustry(this.industry_id) && (industry_id == null || this.industry_id == industry_id);
}

function Node::HasNodeDissapeared()
{
	// Return true if
	// - neither industry nor town
	// - or if the industry id exists, but at another location than the original location
	return !IsTown() && (!IsIndustry() || AIIndustry.GetLocation(this.industry_id) != this.node_location);
}

function Node::GetName()
{
	if(IsTown())
		return AITown.GetName(this.town_id) + " - " + AICargo.GetCargoLabel(this.cargo_id);
	if(IsIndustry())
		return AIIndustry.GetName(this.industry_id) + " - " + AICargo.GetCargoLabel(this.cargo_id);

	return "<is neither a town nor an industry>";
}

function Node::GetLocation()
{
	if(IsTown())
		return AITown.GetLocation(this.town_id);
	if(IsIndustry())
		return AIIndustry.GetLocation(this.industry_id);

	return -1;
}

function Node::GetClosestTown()
{
	if(IsTown())
		return this.town_id;
	
	if(IsIndustry())
		return AITile.GetClosestTown(AIIndustry.GetLocation(this.industry_id));

	return -1;
}

/*function Node::GetDistanceManhattan(tile)
{
	local self_loc = this.GetLocation();

	return AIMap.DistanceManhattan(self_loc, tile);
}*/

function Node::GetLastMonthProduction()
{
	local api = null;
	local self_id = -1;
	if(this.IsTown())
	{
		api = AITown;
		self_id = town_id;
	}
	else if(this.IsIndustry())
	{
		api = AIIndustry;
		self_id = industry_id;
	}
	else
	{
		return 0;
	}

	return api.GetLastMonthProduction(self_id, this.cargo_id);
}

function Node::GetCargoAvailability()
{
	local api = null;
	local self_id = -1;
	if(this.IsTown())
	{
		api = AITown;
		self_id = town_id;
	}
	else if(this.IsIndustry())
	{
		api = AIIndustry;
		self_id = industry_id;
	}
	else
	{
		return 0;
	}

	return api.GetLastMonthProduction(self_id, this.cargo_id) - (api.GetLastMonthTransported(self_id, this.cargo_id) * TRANSPORTED_FACTOR_PERCENT) / 100;
}

// returns [value, cargo_id] for the cargo with higest value availability
function Node::GetCargoValueAvailability()
{
	local api = null;
	local self_id = -1;

	if(this.IsTown())
	{
		api = AITown;
		self_id = town_id;
	}
	else if(this.IsIndustry())
	{
		api = AIIndustry;
		self_id = industry_id;
	}
	else
	{
		return 0;
	}

	return (api.GetLastMonthProduction(self_id, this.cargo_id) - (api.GetLastMonthTransported(self_id, this.cargo_id) * TRANSPORTED_FACTOR_PERCENT) / 100) * 
			AICargo.GetCargoIncome(this.cargo_id, 150, 20); // assume 150 tiles and 20 days in transit
}

/* static */ function Node::SquirrelListComperator_CargoValueAvailability(node1, node2)
{
	local a = node1.GetCargoValueAvailability();
	local b = node2.GetCargoValueAvailability();

	if (a < b)
		return 1;
	if (a > b)
		return -1;
	return 0;
}

function Node::IsCargoAccepted()
{
	if(this.IsTown())
	{
		// Hack: Use a list of cargos that towns accept eg PAX, MAIL, GOODS
		// and reduce any other cargo so that we don't by mistake accept a cargo because of an industry
		local town_cargos = Helper.GetTownAcceptedCargoList();
		if(!town_cargos.HasItem(this.cargo_id))
			return false;

		// Second, check that the town in question actually accept the cargo
		local town_location = AITown.GetLocation(this.town_id);
		local acceptance = AITile.GetCargoAcceptance(town_location, this.cargo_id, 1, 1, 10);

		return acceptance >= 8;
	}
	else if(this.IsIndustry())
	{
		return AIIndustry.IsCargoAccepted(this.industry_id, this.cargo_id) != AIIndustry.CAS_NOT_ACCEPTED;
	}
	else
	{
		return false;
	}
}

function Node::IsCargoProduced()
{
	if (this.IsTown())
		return AITile.GetCargoProduction(this.GetLocation(), this.cargo_id, 1, 1, 5) > 0; // check a radius of 5 tiles for production

	return Industry.IsCargoProduced(this.industry_id, this.cargo_id);
}

function Node::SaveToString()
{
	local id_string = "";
	local what = "";
	local obj_id = "";
	if (this.IsTown())
	{
		what = "T";
		obj_id = this.town_id.tostring();
	}
	else if(this.IsIndustry())
	{
		what = "I";
		obj_id = this.industry_id.tostring();
	}

	id_string = what + obj_id + " " + this.cargo_id;
	return id_string;
}

/* static */ function Node::CreateFromSaveString(save_str)
{
	// format: [IT][0-9]+ [0-9]+

	try // some problems are detected but not all, so at least don't crash if a bad string is given
	{
		local space = save_str.find(" ");
		if(space == null) return null; // fail if there is no space in the string
		local obj_str = save_str.slice(0, space);
		
		local type = obj_str.slice(0, 1); // T or I
		local obj_id = obj_str.slice(1).tointeger();  // town or industry id

		// Create town_id and industry_id variables and assign values
		local town_id = -1;
		local industry_id = -1;
		if(type == "T")
		{
			town_id = obj_id;
		}
		else if(type == "I")
		{
			industry_id = obj_id;
		}
		else
		{
			return null; // fail if unexpected object type was found
		}

		// Get the cargo id
		local cargo_id_str = save_str.slice(space + 1);
		local cargo_id = cargo_id_str.tointeger();

		return Node(town_id, industry_id, cargo_id);
	}
	catch(e)
	{
		return null;
	}
}

/* static */ function Node::IsNodeInConnectionList(connection_list, node)
{
	foreach(connection in connection_list)
	{
		// Don't consider failed or closed down connections
		if(connection.state == Connection.STATE_FAILED || connection.state == Connection.STATE_CLOSED_DOWN)
			continue;

		if(node.IsTown())
		{
			foreach(con_node in connection.node)
			{
				if(con_node.town_id == node.town_id && con_node.cargo_id == node.cargo_id)
				{
					return true;
				}
			}
		}
		else if(node.IsIndustry())
		{
			foreach(con_node in connection.node)
			{
				if(con_node.industry_id == node.industry_id && con_node.cargo_id == node.cargo_id)
				{
					return true;
				}
			}
		}
	}

	return false;
}

/* static */ function Node::FindNodePairInConnectionList(connection_list, node1, node2)
{
	local comp_con = [node1, node2];

	foreach(connection in connection_list)
	{
		if(connection.node.len() != 2)
			KABOOOM_CONNECTION_LENGTH_IS_NOT_TWO();

		local j = 1; // j is (i + 1) % 2
		for(local i = 0; i < 2; i++)
		{
			// Check if the connection in connection list has node1 and node2 in
			// any order ("any order" is what the loop is for)
			if (connection.node[i].IsEqualTo(node1) && 
					connection.node[j].IsEqualTo(node2))
				return connection;

			j++;
			if(j > 1) j = 0;
		}
	}
	return null;
}

function ConnectionBuiltDateSorter(c1, c2)
{
	local c1_date = c1.date_built;
	local c2_date = c2.date_built;

	if(c1_date > c2_date) return 1;
	else if(c1_date < c2_date) return -1;
	return 0;
}

/* static */ function Node::RemoveOldFailedConnections(connection_list, min_age, min_num)
{
	Log.Info("Remove old failed connections.  min age: " + min_age + "  min num: " + min_num, Log.LVL_SUB_DECISIONS);

	// a list of failed connections
	local failed_list = [];

	Log.Info("Failed connections: (before removal)", Log.LVL_DEBUG);
	foreach(connection in connection_list)
	{
		if(connection.node.len() != 2)
			KABOOOM_CONNECTION_LENGTH_IS_NOT_TWO();

		if(connection.state == Connection.STATE_FAILED ||
				connection.state == Connection.STATE_CLOSED_DOWN)
		{
			failed_list.append(connection);
			Log.Info(connection.GetName() + " - built: " + connection.date_built, Log.LVL_DEBUG);
		}
	}

	failed_list.sort(ConnectionBuiltDateSorter);
	local num = 0;
	local day_now = AIDate.GetCurrentDate();
	foreach(connection in failed_list)
	{
		// Is done?
		if(day_now - connection.date_built < min_age && num >= min_num)
			return;

		// No - remove this failed connection from the connection_list
		// and thus make its nodes available again for new connection
		// tries.

		// find index of connection in connection_list and remove it
		foreach(idx, c in connection_list)
		{
			if(c == connection)
			{
				Log.Info("Remove connection " + connection.GetName(), Log.LVL_SUB_DECISIONS);
				connection_list.remove(idx);
				break;
			}
		}
	}

	Log.Info("Failed connections: (after removal)", Log.LVL_DEBUG);
	foreach(connection in connection_list)
	{
		if(connection.state == Connection.STATE_FAILED ||
				connection.state == Connection.STATE_CLOSED_DOWN)
		{
			Log.Info(connection.GetName() + " - built: " + connection.date_built, Log.LVL_DEBUG);
		}
	}
	Log.Info("Failed connections removal DONE", Log.LVL_DEBUG);
}

/*
class Industry {

	constructor() {
	}

	function FindTwoIndustriesToConnectByRoad(maxDistance);
}*/
