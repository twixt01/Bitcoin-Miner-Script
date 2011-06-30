#!/bin/bash
############################################################
##### SETTINGS                                          ####
############################################################

## Url of our control file - should contain the pool address in http://user:pass@host:port format
CTRL_URL="http://sample.com/p.txt";

MINER_ID="GPU0";  # IMPORTANT, If you have more than 1 gpu/miner, increment this accordinly
ATICONFIG_ADAPTER_ID=0;  # Same, this is requierd to fetch the LOAD & TEMP

## Settings/commandline for the phoenix miner
PHOENIX_OPTIONS="-q 2 -k phatk VECTORS BFI_INT FASTLOOP=false AGGRESSION=12 DEVICE=5";

## Minimum Load and Maximum Temp 
MIN_LOAD=30; # if load drops below this, we'll restart miner
MAX_TEMP=85; # if temps go above this, we'll kill the miner

ENABLE_EMAIL=0;	# 1=enabled, anything else will disable it
FROM="user@host.com";
TO="user@host.com";
SMTP_SERVER="10.1.0.58:25";

# Logging
ENABLE_LOG=1;  # 1=enabled, anything else will disable it
LOG="/tmp/Log-$MINER_ID.log"


############################################################
##### YOU SHOULD NOT HAVE TO MODIFY ANYTHING BELOW THIS ####
############################################################

#UNIQID="$MINER_ID-"`date +%Y%M%d%H%M%S`
UNIQID="$MINER_ID-MINER"

log()
{
	### ARGS:
	###		$1 - message to log
	if [ "$ENABLE_LOG" -eq "1" ]
	then
		echo "$1" >> $LOG
	fi
	echo "$1"
}
sendMail()
{
	### ARGS:
	###		$1 - subject
	###		$2 - mesage
	if [ "$ENABLE_EMAIL" -eq "1" ]
	then
		sendemail -f "$FROM" -t "$TO" -u "$1" -m "$2" -s "$SMTP_SERVER"
	fi
}

sendMail "$UNIQID Script Started" "$UNIQID Server Running"

killPID()
{
	PID=$(($1+0))
	RESULT=0;
	log "KillPID: $PID"
	if [ "$PID" -gt 0 ]
	then
		sudo kill -9 $PID
		RESULT=$?
		log "trying to kill -9 $PID result:$RESULT"
	else
		log "killPID failed, invalid PID '$PID' specified"
	fi
	
	return $RESULT
}
killOldMiners()
{
	log "Killing old miner instance..."
	PID=`screen -list | grep $UNIQID | cut -f1 -d'.' | sed 's/\W//g'`;
	killPID $PID
}

isMinerRunning()
{
	screen -wipe > /dev/null
	PID=`screen -list | grep $UNIQID | cut -f1 -d'.' | sed 's/\W//g'`;
	PID=$((PID+0))
	if [ "$PID" -gt 0 ]
	then
		return 1; #its running
	else
		return 0; #its not running
	fi 
}

CURRENT="";
RECHECK=0;
# kill any running instances
killOldMiners
while true; do
	SERVER=`sudo wget -qO- "$CTRL_URL"`
	RESULT=$?
	PROCEED=0;

	if [ "$RESULT" -eq "0" ]

	then
#need to fix this if statement!
		#if [ $SERVER == *http* ]
		#then
	echo http correct
			PROCEED=1;
		#fi

	fi

	if [ "$PROCEED" -eq "1" ]
	then
echo starting
		# we are good to go
		########################################################################
		isMinerRunning $UNIQID;
		R=$?
		if [ "$R" -eq "0" ]
		then
			# MINER NOT RUNNING
			log "Miner is not running, starting"
			log "Launching screen: screen -dmS $UNIQID ./phoenix.py -u $SERVER $PHOENIX_OPTIONS"
						
			 screen -dmS $UNIQID ./phoenix.py -u $SERVER $PHOENIX_OPTIONS
			
			sendMail "$MINER_ID not running, starting $UNIQID" "Miner was not running, started..."
			CURRENT="$SERVER"
			RECHECK=1
		else
			# miner is running
			# lets see if a new server is available
			if [ "$CURRENT" != "$SERVER" ]
			then
				PID=`screen -list | grep $UNIQID | cut -f1 -d'.' | sed 's/\W//g'`;
				killPID $PID
				RESULT=$?
				log "Server address change detected, killing current miner..., result: $RESULT"
				RECHECK=1
			else
				RECHECK=0
				TEMP=`env DISPLAY=:0 aticonfig --odgt --adapter=$ATICONFIG_ADAPTER_ID | grep Temperature | awk '{gsub(/%/,"",$4); print $5}' | cut -d '.' -f1`
				LOAD=`env DISPLAY=:0 aticonfig --odgc --adapter=$ATICONFIG_ADAPTER_ID | grep 'GPU load' | awk '{gsub(/%/,"",$4); print $4}'`
				if [ "$TEMP" -gt "$MAX_TEMP" ]
				then
					log "The GPU's Temp ($TEMP) is greater than $MAX_TEMP, killing miner!";
					PID=`screen -list | grep $UNIQID | cut -f1 -d'.' | sed 's/\W//g'`;
					killPID $PID
					RESULT=$?
					sendMail "$MINER_ID overheating, $TEMP > $MAX_TEMP" "Miner killed as it was overheating, it should automatically restart at next check. \n\nResult of KILL -9 $PID was $RESULT (should be 0)"
					RECHECK=0
				fi
				if [ "$LOAD" -lt "$MIN_LOAD" ]
				then
					sleep 15
					LOAD=`env DISPLAY=:0 aticonfig --odgc --adapter=$ATICONFIG_ADAPTER_ID | grep 'GPU load' | awk '{gsub(/%/,"",$4); print $4}'`
					log "After sleeping 15 seconds, the load is $LOAD"
					if [ "$LOAD" -lt "$MIN_LOAD" ]
					then
						log "The GPU's Load ($LOAD) is still less than $MIN_LOAD, killing miner!";
						PID=`screen -list | grep $UNIQID | cut -f1 -d'.' | sed 's/\W//g'`;
						killPID $PID
						RESULT=$?
						sendMail "$MINER_ID Load was $LOAD < $MIN_LOAD" "Miner killed as it was under the specified load threshhold, it should automatically restart shortly. \n\nResult of KILL -9 $PID was $RESULT (should be 0)"
						RECHECK=1
					fi
				fi
			fi
		fi
	else
		# failed to fetch the control web page
		log "Failed to get the web page at $CTRL_URL please make sure it is correct!"
		sendMail "Failed to load control page: $CTRL_URL" "Please check to make sure that your miners can wget $CTRL_URL"
	fi

	
	if [ "$RECHECK" -eq "1" ]
	then
		log "RECHECK requested, sleeping 10 seconds" 
		sleep 10
	else
		sleep 300
	fi
done
