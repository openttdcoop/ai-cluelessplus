//////////////////////////////////////////////////////////////////////
//                                                                  //
//  CluelessPlus - an noai-AI                                       //
//                                                                  //
//////////////////////////////////////////////////////////////////////
// 
// Author: Zuu (Leif Linse), user Zuu @ tt-forums.net
// Purpose: To play around with the noai framework.
//               - Not to make the next big thing.
//
// Copyright: Leif Linse - 2008-2011
// License: GNU GPL - version 2


//////////////////////////////////////////////////////////////////////
//                                                                  //
//  CLASS: ScoreList                                                //
//                                                                  //
//////////////////////////////////////////////////////////////////////
class ScoreList
{
	list = null;

	sort_max = true;
	sorted = false;

	constructor() {
		list = [];
		sort_max = true;
		sorted = false;
	}

	function Push(value, score);
	function PopMax();
	function PopMin();

	function CompareMin(a, b); // min first
	function CompareMax(a, b); // max first

	// Calles a valuator functions that returns
	// a score for each item
	function ScoreValuate(class_instance, valuator, ...);
}

function ScoreList::Push(value, score)
{
	list.append([value, score]);
	sorted = false;
}
function ScoreList::PopMax()
{
	if(list.len() <= 0)
	{
		return null;
	}
	if(!sorted || sort_max)
	{
		list.sort(this.CompareMin);
	}

	return list.pop()[0];
}
function ScoreList::PopMin()
{
	if(list.len() <= 0)
	{
		return null;
	}
	if(!sorted || !sort_max)
	{
		list.sort(this.CompareMax);
	}

	return list.pop()[0];
}
function ScoreList::CompareMin(a, b)
{
	if(a[1] > b[1]) 
		return 1
	else if(a[1] < b[1]) 
		return -1
	return 0;
}
function ScoreList::CompareMax(a, b)
{
	if(a[1] > b[1]) 
		return -1
	else if(a[1] < b[1]) 
		return 1
	return 0;
}

function ScoreList::ScoreValuate(class_instance, valuator, ...)
{
	assert(typeof(valuator) == "function");

	local args = [class_instance, null];

	for(local c = 0; c < vargc; c++) {
		args.append(vargv[c]);
	}

	foreach(value_score_pair in list) 
	{
		args[1] = value_score_pair[0];
		local score = valuator.acall(args);

		if (typeof(score) == "bool") 
		{
			score = score ? 1 : 0;
		}
	   	else if (typeof(score) != "integer")
		{
			throw("Invalid return type from valuator");
		}

		// Update the score
		value_score_pair[1] = score;
	}

	this.sorted = false;
}
