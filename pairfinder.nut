
class PairFinder {

	town_nodes = null;
	industry_nodes = null;

	constructor()
	{
		town_nodes = [];
		industry_nodes = [];
	}

	function AddNodes(connection_list);
	function AddTownNodes(connection_list);
	function AddIndustryNodes(connection_list);

	// returns [source node, dest node]
	function FindTwoNodesToConnect(maxDistance, desperateness, connection_list);

	static function TownDistanceIdealityValuator(town_id, node_tile);
	static function IndustryDistanceIdealityValuator(industry_id, node_tile);

	static function SquirrelListComperator_PairScore(pair1, pair2);
}

function PairFinder::AddNodes(connection_list)
{
	town_nodes.clear();
	industry_nodes.clear();

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

	if(allowed_connection_types == 0 || allowed_connection_types == 2)
	{
		Log.Info("connect towns", Log.LVL_DEBUG);
		AddTownNodes(connection_list);
	}
	if(allowed_connection_types == 1 || allowed_connection_types == 2)
	{
		Log.Info("connect industries", Log.LVL_DEBUG);
		AddIndustryNodes(connection_list);
	}
}

function PairFinder::AddTownNodes(connection_list)
{
	local town_list = AITownList();
	foreach(town_id, _ in town_list)
	{
		// Add nodes for all cargos which can be produced/accepted by towns
		local produced_cargo_list = Helper.GetTownProducedCargoList();
		local accepted_cargo_list = Helper.GetTownAcceptedCargoList();

		// Only consider cargos if there is an engine available to transport it
		produced_cargo_list.Valuate(Engine.DoesEngineExistForCargo, AIVehicle.VT_ROAD, true, true, false);
		produced_cargo_list.KeepValue(1);
		accepted_cargo_list.Valuate(Engine.DoesEngineExistForCargo, AIVehicle.VT_ROAD, true, true, false);
		accepted_cargo_list.KeepValue(1);

		local cargo_list = AIList();

		cargo_list.AddList(produced_cargo_list);
		cargo_list.AddList(accepted_cargo_list);

		foreach(cargo_id, _ in cargo_list)
		{
			local node = Node(town_id, -1, cargo_id);

			// Only actually append the node if it accepts/produces the cargo - dummy nodes do not make anyone happy
			if (node.IsCargoAccepted() || node.IsCargoProduced())
			{
				town_nodes.append(node);
			}
		}

/*		local cargo_list = AICargoList();

		// Only consider cargos if there is an engine available to transport it
		cargo_list.Valuate(Engine.DoesEngineExistForCargo, AIVehicle.VT_ROAD, true, true, false);

		foreach(cargo_id, _ in cargo_list)
		{
			if (AITown.GetLastMonthProduction(town_id, cargo_id) > 0) // && 
					//!ClueHelper.IsTownInConnectionList(connection_list, town_id, cargo_id))
			{
				town_nodes.append(Node(town_id, -1, cargo_id));
			}
		}
*/
	}
}

function PairFinder::AddIndustryNodes(connection_list)
{
	local industry_list = AIIndustryList();
	foreach(industry_id, _ in industry_list)
	{
		local cargo_list = AICargoList();

		// Only consider cargos if there is an engine available to transport it
		cargo_list.Valuate(Engine.DoesEngineExistForCargo, AIVehicle.VT_ROAD, true, true, false);

		foreach(cargo_id, _ in cargo_list)
		{
			if (/*!ClueHelper.IsIndustryInConnectionList(connection_list, industry_id, cargo_id) && */
				(AIIndustry.GetLastMonthProduction(industry_id, cargo_id) > 0 || // cargo is produced
				AIIndustry.IsCargoAccepted(industry_id, cargo_id)))              // or is accepted
			{
				industry_nodes.append(Node(-1, industry_id, cargo_id));
			}
		}
	}
}

function PairFinder::FindTwoNodesToConnect(maxDistance, desperateness, connection_list)
{
	// Rebuild the list of nodes
	this.AddNodes(connection_list);

	// Get the best producing nodes. Town or industry doesn't matter.
	local all_nodes = [];

	all_nodes.extend(town_nodes);
	all_nodes.extend(industry_nodes);
	all_nodes.sort(Node.SquirrelListComperator_CargoValueAvailability);

	if(all_nodes.len() == 0)
	{
		Log.Info("No locations to transport between was found. This can happen if there are no buses/lories available or if there is nothing more to connect.", Log.LVL_SUB_DECISIONS);
		return null;
	}

	local top_source_nodes = [];

	local i = -1;
	foreach(node in all_nodes)
	{
		// Only accept nodes as sources if they are not in use for the given cargo
		if(!Node.IsNodeInConnectionList(connection_list, node))
		{
			++i;
			top_source_nodes.append(node);
			Log.Info("top node: " + node.GetName(), Log.LVL_SUB_DECISIONS);
			if (i >= 8 * (1 + desperateness)) break;
		}
	}

	local best_pairs = [];

	// Find a good pair using one of the top-producing nodes
	local score_list = AIList();
	foreach(source_node in top_source_nodes)
	{
		local max_ideality_distance = 50; // accept max 50 tiles more/less than ideal distance

		Log.Info("Source " + source_node.GetName(), Log.LVL_DEBUG);

		// Look for nearby nodes that accept this cargo
		score_list.Clear();
		local i = -1;
		foreach(dest_node in all_nodes)
		{
			++i;
			if(dest_node.cargo_id != source_node.cargo_id) // only consider the node of the right cargo type of a given node
			{
				continue;
			}

			// Make sure to not connect the same node with itself
			if((dest_node.town_id != -1 && dest_node.town_id == source_node.town_id) ||
					(dest_node.industry_id != -1 && dest_node.industry_id == source_node.industry_id))
			{
				continue;
			}

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

			local score = 0;

			local dist = AIMap.DistanceManhattan(dest_node.GetLocation(), source_node.GetLocation());
			local dist_deviation = Helper.Abs(80 - dist); // 0 = correct dist and then increasing for how many tiles wrong the distance is

			if (dist > maxDistance)
				continue;

			if (dist_deviation > 70)
				continue;

			if (dist < 20)
				continue;

			if(!dest_node.IsCargoAccepted())
				continue;

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

				prod_value += extra_value
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

			// Make a combined score of the production value and distance deviation
			score = prod_value + (70 - dist_deviation) * 2 + bonus;

			score_list.AddItem(i, score);
		}

		// Sort the scores with highest score first
		score_list.Sort(AIAbstractList.SORT_BY_VALUE, AIAbstractList.SORT_DESCENDING);

		// Add the 5 best pairs from the current source to the list of found pairs
		score_list.KeepTop(5);
		foreach(idx, score in score_list)
		{
			local dest_node = all_nodes[idx];
			best_pairs.append([source_node, dest_node, score]);
		}
	}

	Log.Info("there is " + best_pairs.len() + " found pairs", Log.LVL_SUB_DECISIONS);

	// Get the best pair of the best
	best_pairs.sort(PairFinder.SquirrelListComperator_PairScore);

	if(best_pairs.len() == 0)
		return null;

	Log.Info("best pair score: " + best_pairs[0][2], Log.LVL_SUB_DECISIONS);

	return [best_pairs[0][0], best_pairs[0][1]]; // return [source node, dest node]
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
	cargo_id = null;

	constructor(townId, industryId, cargoId)
	{
		this.town_id = townId;
		this.industry_id = industryId;
		this.cargo_id = cargoId;
	}

	function SaveToString();
	static function CreateFromSaveString(save_str);

	// Compares town/industry id + cargo_id
	function IsEqualTo(node);

	function IsTown();
	function IsIndustry();
	function GetName();
	function GetLocation();
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
}

function Node::IsEqualTo(node)
{
	// The idea is that if both nodes has invalid town or industry their value shouldn't
	// be compared. It is enough to check one of them for validity though. 
	return (AITown.IsValidTown(this.town_id) && this.town_id == node.town_id) ||
		(AIIndustry.IsValidIndustry(this.industry_id) && this.industry_id == node.industry_id);
}

function Node::IsTown()
{
	return AITown.IsValidTown(this.town_id);
}

function Node::IsIndustry()
{
	return AIIndustry.IsValidIndustry(this.industry_id);
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

	return api.GetLastMonthProduction(self_id, this.cargo_id) - api.GetLastMonthTransported(self_id, this.cargo_id);
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

	return (api.GetLastMonthProduction(self_id, this.cargo_id) - api.GetLastMonthTransported(self_id, this.cargo_id)) * 
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
		return AIIndustry.IsCargoAccepted(this.industry_id, this.cargo_id);
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

/*
class Industry {

	constructor() {
	}

	function FindTwoIndustriesToConnectByRoad(maxDistance);
}*/
