
class Timer {

	start = null;
	total = null;

	label = null;

	constructor(label = "")
	{
		this.label = label;
		this.start = null;
		this.total = 0;
	}

	function Reset()
	{
		this.total = 0;
		this.start = null;
	}

	function PrintTotal()
	{
		if(this.start != null)
		{
			// Get time until now
			this.Stop();
			this.Start();
		}

		Log.Info("timer " + this.label + ": " + (this.total / 74), Log.LVL_DEBUG);
	}

	function Start()
	{
		if(this.start == null)
			this.start = AIController.GetTick();
	}

	function Stop()
	{
		this.total += AIController.GetTick() - this.start;
		this.start = null;
	}
}
