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
// Copyright: Leif Linse - 2008-2010
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
