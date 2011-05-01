
class Strategy {


	static function FindEngineModelToPlanFor(cargo_id, vehicle_type);
	static function FindEngineModelToBuy(cargo_id, vehicle_type);

	static function EngineBuyScore(engine_id);
}

function Strategy::FindEngineModelToPlanFor(cargo_id, vehicle_type)
{
	// find a bus model to buy
	local bus_list = AIEngineList(vehicle_type);

	// Get engines that can be refited to the wanted cargo
	bus_list.Valuate(AIEngine.CanRefitCargo, cargo_id)
	bus_list.KeepValue(1); 

	// Exclude articulated vehicles
	if (vehicle_type == AIVehicle.VT_ROAD)
	{
		bus_list.Valuate(AIEngine.IsArticulated)
		bus_list.KeepValue(0); 

		// Exclude trams
		bus_list.Valuate(AIEngine.GetRoadType);
		bus_list.KeepValue(AIRoad.ROADTYPE_ROAD);
	}

	if (vehicle_type == AIVehicle.VT_AIR)
	{
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
	bus_list.Valuate(AIEngine.IsBuildable)
	bus_list.KeepValue(1); 

	// Buy the vehicle with highest score
	bus_list.Valuate(Strategy.EngineBuyScore)
	bus_list.KeepTop(1);

	return bus_list.IsEmpty()? -1 : bus_list.Begin();
}

function Strategy::FindEngineModelToBuy(cargo_id, vehicle_type)
{
	return Strategy.FindEngineModelToPlanFor(cargo_id, vehicle_type);
}

function Strategy::EngineBuyScore(engine_id)
{
	// Use the product of speed and capacity
	return AIEngine.GetMaxSpeed(engine_id) * AIEngine.GetCapacity(engine_id);
}
