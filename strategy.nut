
class Strategy {

	static function UpdateNewConnectionEngineList(engine_list);

	static function FindEngineModelToPlanFor(cargo_id, vehicle_type, small_aircraft_only, allow_articulated_rvs);
	static function FindEngineModelToBuy(cargo_id, vehicle_type, small_aircraft_only, allow_articulated_rvs);

	static function EngineBuyScore(engine_id);
}

function Strategy::FindEngineModelToPlanFor(cargo_id, vehicle_type, small_aircraft_only, allow_articulated_rvs)
{
	// find a bus model to buy
	local bus_list = AIEngineList(vehicle_type);

	// Get engines that can be refited to the wanted cargo
	bus_list.Valuate(AIEngine.CanRefitCargo, cargo_id)
	bus_list.KeepValue(1); 

	// Exclude articulated vehicles + trams
	if (vehicle_type == AIVehicle.VT_ROAD)
	{
		if(!allow_articulated_rvs)
		{
			bus_list.Valuate(AIEngine.IsArticulated)
			bus_list.KeepValue(0); 
		}

		// Exclude trams
		bus_list.Valuate(AIEngine.GetRoadType);
		bus_list.KeepValue(AIRoad.ROADTYPE_ROAD);
	}

	if (vehicle_type == AIVehicle.VT_AIR)
	{
		bus_list.Valuate(AIEngine.GetPlaneType);
		bus_list.RemoveValue(AIAirport.PT_HELICOPTER); // helicopters are good at jamming up airports, so avoid them
		if(small_aircraft_only)
		{
			// Exclude large aircrafts
			bus_list.KeepValue(AIAirport.PT_SMALL_PLANE);
		}

		// Exclude aircrafts that don't have an buildable airport type
		bus_list.Valuate(Helper.ItemValuator);
		foreach(plane, _ in bus_list)
		{
			if(!Airport.AreThereAirportsForPlaneType(AIEngine.GetPlaneType(plane)))
			{
				bus_list.RemoveValue(plane);
			}
		}
	}

	// Exclude engines that can't be built
	bus_list.Valuate(AIEngine.IsBuildable);
	bus_list.KeepValue(1); 

	// Buy the vehicle with highest score
	bus_list.Valuate(Strategy.EngineBuyScore);
	bus_list.KeepTop(1);

	return bus_list.IsEmpty()? -1 : bus_list.Begin();
}

function Strategy::FindEngineModelToBuy(cargo_id, vehicle_type, small_aircraft_only, allow_articulated_rvs)
{
	return Strategy.FindEngineModelToPlanFor(cargo_id, vehicle_type, small_aircraft_only, allow_articulated_rvs);
}

function Strategy::EngineBuyScore(engine_id)
{
	// Use the product of speed and capacity
	return AIEngine.GetMaxSpeed(engine_id) * AIEngine.GetCapacity(engine_id);
}

function Strategy::UpdateNewConnectionEngineList(engine_list, cargo)
{
	local engine_list = AIList();
	if(Vehicle.GetVehiclesLeft(AIVehicle.VT_ROAD) > 0)
		engine_list.AppendList(AIEngineList(AIVehicle.VT_ROAD));
	if(Vehicle.GetVehiclesLeft(AIVehicle.VT_AIR) > 0)
		engine_list.AppendList(AIEngineList(AIVehicle.VT_AIR));
	/*if(Vehicle.GetVehiclesLeft(AIVehicle.VT_RAIL) > 0)
		engine_list.AppendList(AIEngineList(AIVehicle.VT_RAIL));
	if(Vehicle.GetVehiclesLeft(AIVehicle.VT_WATER) > 0)
		engine_list.AppendList(AIEngineList(AIVehicle.VT_WATER));*/

	// Pre-compute which airport to use for large/small airplanes instead of doing this for each
	// engine
	local airport_type_list = GetAirportTypeList_AllowedAndBuildable(true);
	local large_plane_ap_type = airport_type_list.Begin();
	airport_type_list = GetAirportTypeList_AllowedAndBuildable(false);
	local small_plane_ap_type = airport_type_list.Begin();

	// Get ideal transport distance of each engine
	engine_list.Valuate(IdealTransportDistance, cargo, small_plane_ap_type, large_plane_ap_type);
	engine_list.Sort(AIList.SORT_BY_VALUE, AIList.SORT_ASCENDING);
	
	// Separate engines into fractions
	local groups = SeparateEnginesIntoGroups(engine_list, [20, 70, 150, 300, 800, 9999]); // last limit is threated as infinity
	foreach(group in groups)
	{
		group.list.Valuate(EngineBuyScore);
		group.KeepTop(1);
	}

}

function Strategy::SeparateEnginesIntoGroups(list, borders)
{
	list.Sort(AIList.SORT_BY_VALUE, AIList.SORT_ASCENDING);

	local groups = [];
	local prev = 0;
	foreach(limit in borders)
	{
		groups.append( { min = prev,
				max = limit,
				items = AIList() });

		prev = limit;
	}

	local limit_i = 0;
	foreach(engine, value in list)
	{
		while(limit_i < groups.len() - 2 && value >= groups[limit_i].max)
		{
			++limit_i;
		}

		groups[limit_i].list.AddItem(engine, value);
	}
}

function Strategy::IdealTransportDistance(engine, cargo, small_plane_ap_type, large_plane_ap_type)
{
	local ap_type = -1;
	if(AIEngine.GetVehicleType(engine) == AIVehicle.VT_AIR)
	{
		if(AIEngine.GetPlaneType(engine) == AIAircraft.PT_BIG_PLANE)
			ap_type = large_plane_ap_type;
		else
			ap_type = small_plane_ap_type;
	}

	return Engine.GetIdealTransportDistance(engine, cargo, ap_type);
}
