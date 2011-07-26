
TM_ROAD <- 0;
TM_AIR <- 1;
TM_RAIL <- 2;
TM_WATER <- 3;

TM_INVALID <- 99;

/* list of all transport modes */
g_tm_list <- [TM_ROAD, TM_AIR, TM_RAIL, TM_WATER];

// see also g_tm_stats that is created after TMStat class is defined

function TransportModeToVehicleType(tm)
{
	switch(tm)
	{
		case TM_ROAD:
			return AIVehicle.VT_ROAD;
		case TM_AIR:
			return AIVehicle.VT_AIR;
		case TM_RAIL:
			return AIVehicle.VT_RAIL;
		case TM_WATER:
			return AIVehicle.VT_WATER;
	}

	return null;
}

function TransportModeToString(tm)
{
	switch(tm)
	{
		case TM_ROAD:
			return "road";

		case TM_AIR:
			return "air";

		case TM_RAIL:
			return "rail";

		case TM_WATER:
			return "water";

		case TM_INVALID:
		default:
			return "invalid";
	}
}

/* stats for a specific transport mode */
class TMStat {

	transport_mode = null;
	construct_performance = null;
	min_construct_distance = null;
	ideal_construct_distance = null;
	max_construct_distance = null;
	max_construct_distance_deviation = null;

	constructor(transport_mode)
	{
		this.transport_mode = transport_mode;
		this.construct_performance = 0;

		this.CalcMaxConstructDistance(0);
		switch(this.transport_mode)
		{
			case TM_ROAD:
				this.min_construct_distance = 30;
				this.ideal_construct_distance = 80;
				this.max_construct_distance_deviation = 70;
				break;

			case TM_AIR:
				this.min_construct_distance = 100;
				this.ideal_construct_distance = 300;
				this.max_construct_distance_deviation = 120;
				break;

			case TM_RAIL:
			case TM_WATER:
				this.min_construct_distance = 20;
				this.ideal_construct_distance = 80;
				this.max_construct_distance_deviation = 70;
				break;
		}
	}
	
	function CalcMaxConstructDistance(desperateness);
}

function TMStat::CalcMaxConstructDistance(desperateness)
{
	local a = Helper.Clamp(this.construct_performance, -20, 100); // bonus distance based on performance history
	switch(this.transport_mode)
	{
		case TM_ROAD:
			max_construct_distance = 100 + a + 20 * desperateness;
			break;

		case TM_AIR:
			max_construct_distance = 800 + a * 5 + 200 * desperateness; // needs tweaking
			break;

		case TM_RAIL:
			max_construct_distance = 100 + a + 20 * desperateness; // needs tweaking
			break;

		case TM_WATER:
			max_construct_distance = 100 + a + 20 * desperateness; // needs tweaking
			break;
	}
}

/* container that contains the stats for all transport modes */
g_tm_stats <- [];
g_tm_stats.append(TMStat(TM_ROAD));
g_tm_stats.append(TMStat(TM_AIR));
g_tm_stats.append(TMStat(TM_RAIL));
g_tm_stats.append(TMStat(TM_WATER));
