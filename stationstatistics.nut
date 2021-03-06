//////////////////////////////////////////////////////////////////////
//                                                                  //
//  CluelessPlus - an noai-AI                                       //
//                                                                  //
//////////////////////////////////////////////////////////////////////
// 
// Author: Zuu (Leif Linse), user Zuu @ tt-forums.net
// Purpose: To play around with the noai framework.
//               - Not to make the next big thing.
// Copyright: Leif Linse - 2009-2011
// License: GNU GPL - version 2


//////////////////////////////////////////////////////
//                                                  //
//   CLASS: StationStatistics                       //
//                                                  //
//////////////////////////////////////////////////////

class StationStatistics {
	station_id = null;
	cargo_id = null;

	cargo_waiting = null;
	rating = null;

	usage = null;

	constructor(station_id, cargo_id)
	{
		this.station_id = station_id;
		this.cargo_id = cargo_id;

		cargo_waiting = -1;
		rating = -1;
		usage = { bus =    {station_type = AIStation.STATION_BUS_STOP,   mode = AIVehicle.VT_ROAD, percent_usage = -1, percent_usage_max_tile = -1}, 
				truck =    {station_type = AIStation.STATION_TRUCK_STOP, mode = AIVehicle.VT_ROAD, percent_usage = -1, percent_usage_max_tile = -1},
				aircraft = {station_type = AIStation.STATION_AIRPORT,    mode = AIVehicle.VT_AIR,  percent_usage = -1, percent_usage_max_tile = -1},
				train =    {station_type = AIStation.STATION_TRAIN,      mode = AIVehicle.VT_RAIL, percent_usage = -1, percent_usage_max_tile = -1} };
	}

	static function VehicleIsWithinTileList(vehicle_id, tile_list);
};

function StationStatistics::VehicleIsWithinTileList(vehicle_id, tile_list)
{
	return tile_list.HasItem(AIVehicle.GetLocation(vehicle_id));
}

function StationStatistics::ReadStatisticsData()
{
	//AILog.Info("ReadStatisticsData for station " + AIStation.GetName(this.station_id) + " - " + AICargo.GetCargoLabel(this.cargo_id) + " " + this.cargo_id);

	local alpha = 4; // weight of old value (new value will have weight 1)


	local currently_waiting = AIStation.GetCargoWaiting(this.station_id, this.cargo_id);
	if(this.cargo_waiting == -1)
		this.cargo_waiting = currently_waiting;
	else
		this.cargo_waiting = (this.cargo_waiting * alpha + currently_waiting) / (alpha + 1);

	//AILog.Info("cargo_waiting = " + this.cargo_waiting);

	local current_rating = AIStation.GetCargoRating(this.station_id, this.cargo_id);
	if(this.rating == -1)
		this.rating = current_rating;
	else
		this.rating = (this.rating * alpha + current_rating) / (alpha + 1);

	//AILog.Info("rating = " + this.rating);

	// Get an estimate on the vehicle load of the station, by counting the number of vehicles on station tiles
	foreach(_, transp_mode_usage in this.usage)
	{
		if(AIStation.HasStationType(this.station_id, transp_mode_usage.station_type))
		{

			if(transp_mode_usage.station_type == AIStation.STATION_AIRPORT)
			{
				local hangar_num = Airport.GetNumNonStopedAircraftsInAirportDepot(this.station_id);
				local holding_num = Airport.GetNumAircraftsInAirportQueue(this.station_id);
				local new_percent_usage = (holding_num + hangar_num)* 100;
				if(transp_mode_usage.percent_usage == -1)
					transp_mode_usage.percent_usage = new_percent_usage;
				else
					transp_mode_usage.percent_usage = (transp_mode_usage.percent_usage * alpha + new_percent_usage) / (alpha + 1);

				Helper.SetSign(AIStation.GetLocation(station_id) + 2, "hold: " + holding_num + " han: " + hangar_num);
				Helper.SetSign(AIStation.GetLocation(station_id) + 3, "queue: " + (new_percent_usage / 100));
			}
			else
			{
				local station_tile_list = AITileList_StationType(this.station_id, transp_mode_usage.station_type);
				local station_vehicle_list = AIVehicleList_Station(this.station_id);
				station_vehicle_list.Valuate(AIVehicle.GetVehicleType);
				station_vehicle_list.KeepValue(transp_mode_usage.mode);

				local num_vehicles_on_station = 0;
				local max_num_vehicles_per_tile = 0;

				foreach(tile, _ in station_tile_list)
				{
					local num_vehicles_on_this_tile = 0;
					foreach(vehicle, _ in station_vehicle_list)
					{
						if(AIVehicle.GetLocation(vehicle) == tile)
						{
							num_vehicles_on_this_tile++;
						}
					}

					num_vehicles_on_station += num_vehicles_on_this_tile;
					if(num_vehicles_on_this_tile > max_num_vehicles_per_tile)
						max_num_vehicles_per_tile = num_vehicles_on_this_tile;
				}

				local new_percent_usage = num_vehicles_on_station * 100 / station_tile_list.Count();
				local new_percent_usage_max_tile = max_num_vehicles_per_tile * 100;

				if(transp_mode_usage.percent_usage == -1)
					transp_mode_usage.percent_usage = new_percent_usage;
				else
					transp_mode_usage.percent_usage = (transp_mode_usage.percent_usage * alpha + new_percent_usage) / (alpha + 1);

				if(transp_mode_usage.percent_usage_max_tile == -1)
					transp_mode_usage.percent_usage_max_tile = new_percent_usage_max_tile;
				else
					transp_mode_usage.percent_usage_max_tile = (transp_mode_usage.percent_usage_max_tile * alpha + new_percent_usage_max_tile) / (alpha + 1);
			}
		}
		else
		{
			transp_mode_usage.percent_usage = -1;
			transp_mode_usage.percent_usage_max_tile = -1;
		}
	}

	//AILog.Info("bus usage = " + this.usage.bus.percent_usage);

	Helper.SetSign(AIBaseStation.GetLocation(station_id), "w" + cargo_waiting + 
			" r" + rating + 
			" u" + Helper.Max(usage.bus.percent_usage, usage.truck.percent_usage) + 
			" um" + Helper.Max(usage.bus.percent_usage_max_tile, usage.truck.percent_usage_max_tile) +
			" a" + usage.aircraft.percent_usage);
}
