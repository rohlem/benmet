#!/usr/bin/env sh

case $1 in
	
	"status")
		if [ -f "./params_out.txt" ]; then
			echo "finished"
		else
			echo "startable"
		fi
		exit 0
	;;
	
	"inputs")
		echo '{"a": "default-value-a", "b": "default-value-b", "c": "default-value-c", "33": 33}'
		exit 0
	;;
	
	"start")
		cat "./params_in.txt"
		cat "./params_in.txt" > "./params_out.txt"
		exit 0
	;;
	
	"cancel")
		echo "nothing to cancel!"
		exit 1
	;;
	
	"continue")
		echo "nothing to continue!"
		exit 1
	;;
esac

echo "unrecognized command!"
exit 1