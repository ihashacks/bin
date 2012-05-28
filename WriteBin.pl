#
# WriteBin v1.0 | Reed Arvin reedarvin[at]gmail[dot]com
#
# Usage:
# WriteBin.pl <file name>
# WriteBin.pl MyBin.exe.txt
#
########################################################

use strict;

my($strInputFile) = $ARGV[0];
my($intByteCount) = "";
my($strBytes)     = "";

if ($#ARGV ne "0")
{
	print "WriteBin v1.0 | Reed Arvin reedarvin[at]gmail[dot]com\n";
	print "\n";
	print "Usage:\n";
	print "WriteBin.pl <file name>\n";
	print "WriteBin.pl MyBin.exe.txt\n";

	exit;
}

if (open(INPUTFILE, "< $strInputFile"))
{
	open(OUTPUTFILE, "> new_" . substr($strInputFile, 0, (length($strInputFile) - 4)));

	binmode(OUTPUTFILE);

	$intByteCount = 0;

	while (<INPUTFILE>)
	{
		$strBytes = $_;

		chop($strBytes);

		print (OUTPUTFILE pack("H" . length($strBytes), $strBytes));
	}

	close(INPUTFILE);
	close(OUTPUTFILE);
}
else
{
	print "ERROR! Cannot open file $strInputFile\n";
}

# Written by Reed Arvin reedarvin[at]gmail[dot]com