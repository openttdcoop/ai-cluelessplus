
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
	function FindTwoNodesToConnect(maxDistance, connection_list);

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

	AILog.Info("allowed connection types: " + allowed_connection_types);

	if(allowed_connection_types == 0 || allowed_connection_types == 2)
	{
		AILog.Info("connect towns");
		AddTownNodes(connection_list);
	}
	if(allowed_connection_types == 1 || allowed_connection_types == 2)
	{
		AILog.Info("connect industries");
		AddIndustryNodes(connection_list);
	}
}

function PairFinder::AddTownNodes(connection_list)
{
	local town_list = AITownList();
	foreach(town_id, _ in town_list)
	{
		local cargo_list = AICargoList();

		// Only consider cargos if there is an engine available to transport it
		cargo_list.Valuate(Engine.DoesEngineExistForCargo, AIVehicle.VT_ROAD, true, true, false);

		foreach(cargo_id, _ in cargo_list)
		{
			if (AITown.GetLastMonthProduction(town_id, cargo_id) > 0 && 
					!ClueHelper.IsTownInConnectionList(connection_list, town_id, cargo_id))
			{
				town_nodes.append(Node(town_id, -1, cargo_id));
			}
		}
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
			if (!ClueHelper.IsIndustryInConnectionList(connection_list, industry_id, cargo_id) &&
				(AIIndustry.GetLastMonthProduction(industry_id, cargo_id) > 0 || // cargo is produced
				AIIndustry.IsCargoAccepted(industry_id, cargo_id)))              // or is accepted
			{
				industry_nodes.append(Node(-1, industry_id, cargo_id));
			}
		}
	}
}

function PairFinder::FindTwoNodesToConnect(maxDistance, connection_list)
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
		AILog.Info("No locations to transport between was found. This can happen if there are no buses/lories available or if there is nothing more to connect.");
		return null;
	}

	local top_source_nodes = [];

	local i = -1;
	foreach(node in all_nodes)
	{
		++i;
		top_source_nodes.append(node);
		AILog.Info("top node: " + node.GetName());
		if (i >= 8) break;
	}

	local best_pairs = [];

	// Find a good pair using one of the top-producing nodes
	local score_list = AIList();
	foreach(source_node in top_source_nodes)
	{
		local max_ideality_distance = 50; // accept max 50 tiles more/less than ideal distance

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


			if((dest_node.town_id != -1 && dest_node.town_id == source_node.town_id) ||
					(dest_node.industry_id != -1 && dest_node.industry_id == source_node.industry_id))
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

			if(!dest_node.IsCargoAccepted())
				continue;

			local prod_value = source_node.GetCargoValueAvailability();

			// Can the same cargo be transported the other way around?
			if(dest_node.GetCargoValueAvailability() > 0 && source_node.IsCargoAccepted())
			{
				prod_value += dest_node.GetCargoValueAvailability();
			}

			// Make a combined score of the production value and distance deviation
			score = prod_value + (70 - dist_deviation) * 2;

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

	AILog.Info("there is " + best_pairs.len() + " found pairs");

	// Get the best pair of the best
	best_pairs.sort(PairFinder.SquirrelListComperator_PairScore);

	if(best_pairs.len() == 0)
		return null;

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

	function IsTown();
	function IsIndustry();
	function GetName();
	function GetLocation();
	/*function GetDistanceManhattan(tile);*/

	// Checks the LastMonthProduction + Transported
	function GetCargoAvailability();
	function GetCargoValueAvailability();
	
	// Checks if cargo is accepted or produced at all
	function IsCargoAccepted(); // boolean
	function IsCargoProduced(); // boolean

	static function SquirrelListComperator_CargoValueAvailability(node1, node2);
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

	id_string = what + obj_id + " " + this.cargo_id.tostring();
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
		local cargo_id = save_str.slice(space + 1);
		cargo_id = cargo_id.tointeger();

		return Node(town_id, industry_id, cargo_id);
	}
	catch(e)
	{
		return null;
	}
}

/*
class Industry {

	constructor() {
	}

	function FindTwoIndustriesToConnectByRoad(maxDistance);
}*/
