#!/bin/bash

TODAY="$(date +%s)"

# as installed manually
AWS='/usr/local/bin/aws'
# as installed via a package manager
AWS2='/usr/bin/aws'

JQ='/usr/bin/jq'

function usage() {
	echo -e "$0 [-p profile_name] [-r region]"
	echo -e "\t-p profile_name: the aws profile name, default is 'default'. if specified, this should be specified first."
	echo -e "\t-r region-1,region-2: the region/regions you only wish to check and clean."
	exit 1
}

if [ ! -x "$JQ" ]
then
	echo "$JQ is not installed. (apt-get|yum) install jq"
	exit 1
fi

if [ ! -x "$AWS" ]
then
	if [ ! -x "$AWS2" ]
	then
		echo "AWS cli is not installed. visit: http://aws.amazon.com/cli/"
		exit 1
	else
		AWS="$AWS2"
	fi
fi

while getopts "hp:r:" opt
do
	case $opt in
		h)
			usage
		;;
		p)
			PROFILE="--profile $OPTARG"
		;;
		r)
			REGIONS="$OPTARG"
		;;
		*)
			echo "this option '-$OPTARG' is not supported"
			usage
		;;
	esac
done


LOCAL_REGION=$(wget http://169.254.169.254/latest/meta-data/placement/availability-zone -q -O - | sed 's/.$//')

if [ -z "$REGIONS" ]
then
	REGIONS=$($AWS $PROFILE --output json --region $LOCAL_REGION ec2 describe-regions | $JQ '.Regions[].RegionName' | sed 's/"//g')
else
	REGIONS=$(echo $REGIONS | sed 's/,/ /g')
fi


for REGION in $REGIONS
do
	for SNAPSHOTID in $($AWS $PROFILE --output json --region $REGION ec2 describe-snapshots --filters "Name=tag-key,Values=Expire" | $JQ '.Snapshots[].SnapshotId' | sed 's/"//g')
	do
		EXPIRE=$($AWS $PROFILE --output json --region $REGION ec2 describe-snapshots --filters "Name=snapshot-id,Values=$SNAPSHOTID" | $JQ '.Snapshots[].Tags[]' | grep -A1 -B2 'Expire' | $JQ '.Value' | sed 's/"//g')
		EXPIRE=$(date --date="$EXPIRE" +%s)

		if [ "$EXPIRE" -le "$TODAY" ]
		then
			RETURN=$($AWS $PROFILE --output json --region $REGION ec2 delete-snapshot --snapshot-id "$SNAPSHOTID" | $JQ '.return' | sed 's/"//g')
			if [ "$RETURN" != "true" ]
			then
				echo "Cannot delete snapshot $SNAPSHOTID"
			fi
		fi
	done
done
