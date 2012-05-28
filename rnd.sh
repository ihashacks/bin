#!/bin/bash

number=0
FLOOR=31
RANGE=37
while [ "$number" -le $FLOOR ]
do
		number=$RANDOM
		let "number %= $RANGE"
done
echo "Random number between $FLOOR and $RANGE: $number"
echo
