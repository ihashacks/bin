#!/usr/bin/mawk
BEGIN \
{
	NetService = "/inet/tcp/0/localhost/631";
	print "name" |& NetService;
	while ((NetService |& getline) > 0)
		print $0;
	close(NetService);
}
