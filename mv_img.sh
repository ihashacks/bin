#!/bin/bash

#set -x

count=1130
while [ 1 ]; do
	for i in `ls image*.jpg` ; do
		echo "$i to Image\ $count\.jpg"
		mv $i Image\ $count\.jpg
		let count=count+1;
	done
done
