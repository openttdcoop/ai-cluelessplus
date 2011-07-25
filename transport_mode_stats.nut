
TM_ROAD <- 'road';
TM_AIR <- 'air';
TM_RAIL <- 'rail';
TM_MARINE <- 'marine';


/* container that contains the stats for all transport modes */
g_tm_stats <- {TM_ROAD = TMStat(TM_ROAD),
	TM_AIR = TMStat(TM_AIR),
	TM_RAIL = TMStat(TM_RAIL),
	TM_MARINE = TMStat(TM_MARINE), };

/* list of all transport modes */
g_tm_list = [TM_ROAD, TM_AIR, TM_RAIL, TM_MARINE];

/* stats for a specific transport mode */
class TMStat {

	transport_mode = null;
	construct_performance = null;
	max_construct_distance = null;

	constructor(transport_mode)
	{
		this.transport_mode = transport_mode;
		this.construct_performance = 0;
		this.CalcMaxConstructDistance(0);
	}
	
	function CalcMaxConstructDistance(desperateness)
	{
		local a = Helper.Clamp(this.construct_performance, -20, 100); // bonus distance based on performance history
		switch(this.transport_mode)
		{
			case TransportModeStats.TM_ROAD:
				max_construct_distance = 100 + a + 20 * desperateness;
				break;

			case TransportModeStats.TM_AIR:
				max_construct_distance = 300 + a * 5 + 20 * desperateness; // needs tweaking
				break;

			case TransportModeStats.TM_RAIL:
				max_construct_distance = 100 + a + 20 * desperateness; // needs tweaking
				break;

			case TransportModeStats.TM_MARINE:
				max_construct_distance = 100 + a + 20 * desperateness; // needs tweaking
				break;
		}
	}

}
