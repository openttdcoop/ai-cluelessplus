
class Town
{
	static function GetTownCargoList();

	static town_cargo_list = null;
}

// Returns an AIList of cargos that towns produce & accept
function GetTownCargoList()
{
	if (town_cargo_list == null)
	{
		town_cargo_list = AIList();
		town_cargo_list.AddItem(Helper.GetPAXCargo(), 0);
	}

	return town_cargo_list;
}
