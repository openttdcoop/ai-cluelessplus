
RETURN_SUCCESS <- 0;
RETURN_FAIL <- 1;
RETURN_NOT_ENOUGH_MONEY <- 2;
RETURN_TIME_OUT <- 3;

function IsSuccess(return_val)
{
	return return_val == RETURN_SUCCESS;
}

function IsFail(return_val)
{
	return return_val != RETURN_SUCCESS;
}
