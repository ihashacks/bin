#!/bin/bash
#
#	Written 20040623 by Brandon Pierce <brandon@ihashacks.com>
#	
#	Checks network for samba shares and reports the results via email.
#

IPRANGE=192.168.1.0/24
SMBSCAN=/usr/local/bin/sambascan2.sh
WORKDIR=/tmp/sambascan
LOGRECIP=ids@domain.com

# keep move last week's results to .old, and delete the week before that.
echo "Rotating old logs from: $WORKDIR"
# remove logs older than 60 days
find $WORKDIR/*.log -ctime +60 | xargs /bin/rm -f {}
#rm $WORKDIR/*.old
for i in `ls /tmp/sambascan/*.gz` ; do \
		mv $i $i.old ; \
done

# run the scan
echo "Scanning $IPRANGE"
$SMBSCAN $IPRANGE > $WORKDIR/`date +%Y%m%d`.log 2>&1

# Format the output for everything found, and send it away
for i in `ls /tmp/sambascan/*.gz` ; do \
		 echo -e -n "\nShares found for " ; \
		 echo -n $i | \
		 sed -e 's/\/tmp\/sambascan\///; s/^[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}-//; s/\.txt\.gz//' ; \
		 echo : ; \
		 zcat $i | \
		 sed -e 's/^[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}:/\t/' ; \
done | \
Mail -s "Sambascan2 results for `date "+%b %d, %Y"`" $LOGRECIP
echo "Scan complete, mailing results to $LOGRECIP"
/bin/rm -f /tmp/sambascan/latest.log
ln -sf /tmp/sambascan/`date +%Y%m%d`.log /tmp/sambascan/latest.log
