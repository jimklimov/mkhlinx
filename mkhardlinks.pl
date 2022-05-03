#!/usr/bin/perl -w

print "Gonna start!\n";

### This script deduplicates file archives by finding same files
### and hardlinking them. (C) 2007-2010 by Jim Klimov, COS&HT

### Controlled by Env.Vars, see comments below:
### MKH_BASEDIR   MKH_CONSIDER_METADATA   MKH_DEBUG  MKH_TEMPFILE
### DIFF

### Predefine MKH_DEBUG=anything to skip actual removal and linking

###    !!!     IT IS NOT INTENDED FOR HOME DIRECTORIES      !!!
### and other files which are expected to change separately in future.
### It is for Distros, photo archives, etc.

### NOTE: The MKH_BASEDIR and all its subdirs MUST BE in the same
### filesystem or dataset, so that hardlinks are possible.
###      NO SPECIAL CHECKS ARE DONE DURING FILE REMOVAL!
### Find command does use '-mount' to only find names in one filesystem,
### and '-type f' to not follow symlinks, but things can happen...

### If envvars are not defined, Perl vars will be empty and initialized below
my $MKH_BASEDIR = "";
if (defined($ENV{MKH_BASEDIR})) {	
	$MKH_BASEDIR	= "$ENV{MKH_BASEDIR}"; }
my $MKH_CONSIDER_METADATA = "";
if (defined($ENV{MKH_CONSIDER_METADATA})) {
	$MKH_CONSIDER_METADATA	= "$ENV{MKH_CONSIDER_METADATA}"; }
my $MKH_DEBUG = "";
if (defined($ENV{MKH_DEBUG})) {
	$MKH_DEBUG	= "$ENV{MKH_DEBUG}"; }
my $MKH_TEMPFILE = "";
if (defined($ENV{MKH_TEMPFILE})) {
	$MKH_TEMPFILE	= "$ENV{MKH_TEMPFILE}"; }
my $DIFF = "";
if (defined($ENV{DIFF})) {	$DIFF	= "$ENV{DIFF}"; }
my $CKSUM_BIN = "";
if (defined($ENV{CKSUM})) {	$CKSUM_BIN	= "$ENV{CKSUM}"; }

### MKH_CONSIDER_METADATA values:
###	no		skip metadata check (allow any files with same contents
###			merge into one filesystem inode)
###	owner		check if UID/GID/POSIX access rights fields differ
###	all		also check if date fields differ
###	owner-acl	try to check UID/GID/POSIX and UFS/ZFS/NFSv4 ACLs
###	all-acl		try to check UID/GID/POSIX/DATE and UFS/ZFS/NFSv4 ACLs
if ( "$MKH_CONSIDER_METADATA" eq "" ) {
    $MKH_CONSIDER_METADATA = "owner";
}

### Dir under which we do the work
if ( "$MKH_BASEDIR" eq "" ) {
    $MKH_BASEDIR = "/export/ftp";
    # $MKH_BASEDIR = "/u01/s01/dvd/s0/Solaris_10/Product";
}

### gdiff is much faster on Solaris (4x on sfv240 test), if available
if ( "$DIFF" eq "" ) {
    $DIFF='gdiff -q';
}

### Sanity check - does the requested command exist?
system ("$DIFF '$0' '$0'") == 0 or $DIFF='';
if ( "$DIFF" eq "" ) {
    $DIFF='diff';
}

if ( "$CKSUM_BIN" eq "" ) {
    $CKSUM_BIN = "cksum";
    # $CKSUM_BIN = "md5sum";
}

if ( "$MKH_DEBUG" eq "" ) {
#    $MKH_DEBUG = "no";
    $MKH_DEBUG = "yes";
}

if ( "$MKH_TEMPFILE" eq "" ) {
    $MKH_TEMPFILE = "/tmp/mkhardlinks-dedup-$$.tmp";
}

###########################
### File "stat" and "test" docs:
###   http://perldoc.perl.org/functions/stat.html
###   http://www.itworld.com/nls_unix_fileattributes_060309
###   http://www.devshed.com/c/a/Perl/File-Tests-in-Perl/
#### These funcs can become obsolete if tempfile format changes
### (i.e. includes this data as output by "find -ls"
sub getInode {
    ###### ls -lani "$1" | awk '{print $1}'
    ### Actually returns "DEVNUM:INODE"
    my $filename = shift;
#    return "(stat($filename))[1]";

    ($dev,$ino,$mode,$nlink,$uid,$gid,$rdev,$size,$atime,$mtime,$ctime,$blksize,$blocks) = stat($filename);
    return "$dev:$ino";
}

sub getACL {
    ### TODO: Want a better method like STAT than calling
    ### external processes to get ZFS ACLs
    my $filename = shift;
    my $acl = "`ls -lanidV $filename | tail +2`";

    if ( $? == 0 ) {
	chomp $acl;
	return "$acl";
    } else {
	return "";
    }
}

sub getMeta {
    if ( "$MKH_CONSIDER_METADATA" eq "no" ) {
	return "";
    }

    my $filename = shift;
    ($dev,$ino,$mode,$nlink,$uid,$gid,$rdev,$size,$atime,$mtime,$ctime,$blksize,$blocks) = stat($filename);

    if ( 	"$MKH_CONSIDER_METADATA" eq "owner" ) {
	###### ls -lanid "$1" | awk '{print $2" "$4" "$5 }'
	return "$mode $uid $gid";
    } elsif (	"$MKH_CONSIDER_METADATA" eq "all" ) {
	###### ls -lanid "$1" | awk '{print $2" "$4" "$5" "$7" "$8" "$9 }'
	return "$mode $uid $gid $mtime";
    } elsif (	"$MKH_CONSIDER_METADATA" eq "owner-acl" ) {
	###### ls -lani "$1" | awk '{print $2" "$4" "$5 }'
	###### ls -lanidV "$1" | tail +2
	return "$mode $uid $gid\n" . &getACL("$filename");
    } elsif (	"$MKH_CONSIDER_METADATA" eq "all-acl" ) {
	###### ls -lanid "$1" | awk '{print $2" "$4" "$5" "$7" "$8" "$9 }'
	###### ls -lanidV "$1" | tail +2
	return "$mode $uid $gid $mtime\n" . &getACL("$filename");
    } else {
	return "";
    }
}
###########################

### Signal processing docs:
###    http://affy.blogspot.com/p5be/ch13.htm
###    http://perl.active-venture.com/pod/perlipc-signal.html
$flagBreak = 0;
sub breakAction() {
    my $signame = shift;

    $flagBreak ++;
    if ( $flagBreak == 1 ) {
	print "(SIG=$signame) The script is currently busy with a sensitive operation. Will abort when it's done.\n";
    }
}

sub breakCheck() {
    if ( $flagBreak != 0 ) {
	print "Break-requested flag is set ($flagBreak), exiting.\n";
	eval {
	    print LOG &getDate().": Break-requested flag is set ($flagBreak), exiting.\n";
	    close LOG;
	};
	exit 0;
    }
}

sub breakDisable() {
#    $SIG{'INT'} = 'IGNORE';
    $SIG{'INT'} = 'breakAction';
    $SIG{'QUIT'} = 'breakAction';
    $SIG{'HUP'} = 'breakAction';
    $SIG{'ABRT'} = 'breakAction';
#    $SIG{'BREAK'} = 'breakAction';
    $SIG{'TERM'} = 'breakAction';
}

sub breakEnable() {
    breakCheck;
    $SIG{'INT'} = 'DEFAULT';
    $SIG{'QUIT'} = 'DEFAULT';
    $SIG{'HUP'} = 'DEFAULT';
    $SIG{'ABRT'} = 'DEFAULT';
#    $SIG{'BREAK'} = 'DEFAULT';
    $SIG{'TERM'} = 'DEFAULT';
}

###########################

sub getDate() {
    $date = `date`;
    chomp $date;
    return $date;
}

sub printLog {
    print "@_";
    eval { print LOG "@_"; };
}

sub printErrLog {
    print STDERR "ERROR: @_";
    eval { print LOG "ERROR: @_"; };
}

sub printMergeLog {
    print "MERGE: @_";
    eval { print LOG "MERGE: @_"; };
}

### Final sanity check
system ( "$DIFF '$0' '$0'" ) == 0 or die "Can't use diff command '$DIFF'!\n";

chdir ("$MKH_BASEDIR") or die "Can't cd to '$MKH_BASEDIR'!\n";

print "Gonna work!\n";

$DIAGS_HEADER = "Starting ".&getDate()." with settings:\n" .
    "	MKH_BASEDIR	= $MKH_BASEDIR\n" .
    "	MKH_TEMPFILE	= $MKH_TEMPFILE";

if ( -s "$MKH_TEMPFILE" ) { $DIAGS_HEADER .= " (exists)"; }

$DIAGS_HEADER .=
    "\n	MKH_CONSIDER_METADATA	= $MKH_CONSIDER_METADATA\n" .
    "	MKH_DEBUG	= $MKH_DEBUG\n" .
    "	DIFF		= $DIFF\n" .
    "	CKSUM		= $CKSUM_BIN\n" ;
$DIAGS_HEADER .= "\nFree space now:\n" . `df -k "$MKH_BASEDIR"` . "\n";

print $DIAGS_HEADER;
open (LOG, ">> $MKH_TEMPFILE.diaglog") or die "Can't log to '$MKH_TEMPFILE.diaglog'!\n";

print LOG $DIAGS_HEADER;

#trap "exit 0"  1 2 3 15
#breakDisable;

print "Sleeping 5 sec if you want to abort...\n";
sleep 5;
#sleep 1;

breakEnable;

### TODO: Perhaps provide some parallelism for multiCPU machines?
### TODO: Perhaps skip some work for files already with hardlinks?
if ( ! -s "$MKH_TEMPFILE" ) {
    printLog ( "=== ".&getDate().": Creating MKH_TEMPFILE = '$MKH_TEMPFILE'...\n" );
    printLog ( "find . -mount -type f -exec $CKSUM_BIN '{}' \\; > '" . $MKH_TEMPFILE ."'" );
#    system ( "pwd" );
#    system ( "find . -mount -type f > '" . $MKH_TEMPFILE ."'" );
    system ( "find . -mount -type f -exec $CKSUM_BIN '{}' \\; > '" . $MKH_TEMPFILE ."'" );
    printLog ( "--- ".&getDate().": done ($?)\n" );

#die;
}

$NUM_LINES = `wc -l "$MKH_TEMPFILE"`;
chomp $NUM_LINES;
$NUM_LINES =~ s/^\s+(\d+)\s+.*$/$1/g;

printLog ( "=== ".&getDate().": Parsing MKH_TEMPFILE... (total of $NUM_LINES lines originally)\n" );

### TODO: hide sorting in perl, maybe cache whole file as an array

$COUNT_MERGED	= 0;
$COUNT_MERGEDSZ	= 0;
$COUNT_SKIPPED	= 0;

$COUNT_LINES	= 0;

###### sort -n "$MKH_TEMPFILE" | awk '{ print $1" "$2 }' | uniq -c | sort -n | grep -v ' 1 ' | {
######  while read COUNT CKSUM SIZE; do
### This selects lines with unique CKSUM and SIZE couples, which have been hit more than once
open (SORT, "sort -n '$MKH_TEMPFILE' | awk '{ print " . '$1" "$2' . " }' | uniq -c | sort -n | grep -v ' 1 ' |") or die "Can't sort results!\n";

while ( $LINE_SORT = <SORT> ) {
	# sleep 1;

	chomp $LINE_SORT;
	$LINE_SORT =~ s/^\s+([\d].*[^\s])\s*$/$1/;
	# print "=== '$LINE_SORT'\n";
	my ( $COUNT, $CKSUM, $SIZE ) = split /\s+/, $LINE_SORT;
	$COUNT_LINES++;
	print "LINE_SORT: ($COUNT_LINES/$NUM_LINES)	'$COUNT' '$CKSUM' '$SIZE'\n";
	$FIRSTFILE = "";

	### TODO: hide greping in perl, maybe cache whole file as an array
	open (GREP_CKSUM, "grep -w '$CKSUM' '$MKH_TEMPFILE' | ") or die "Can't grep for cksum data!\n";

	### TODO: we need a way to differentiate two strands of files with same
	### checksums and sizes. Currently we only merge files which have same
	### contents as the one FIRSTFILE.
	### IDEA: Build an array of "firstfiles" from rejected names, and
	### iterate through this block until they were all checked?

	while ( $LINE_GREP = <GREP_CKSUM> ) {
	###### grep -w "$CKSUM" "$MKH_TEMPFILE" | while 
	######  read CS SZ FILE; do
		chomp $LINE_GREP;
		#$LINE_GREP =~ s/^\s+([\d].*[^\s])\s*$/$1/;
		#( $CS, $SZ, $FILE ) = split /\s+/, $LINE_GREP;

		if ( $LINE_GREP =~ /^([\d]*)\s([\d]*)\s(.*)$/ ) {
		    $CS = "$1";
		    $SZ = "$2";
		    $FILE = "$3";
		} else {
		    print "ERROR: unparseable line:\n";
		    print "	LINE_GREP='$LINE_GREP'\n";
		    next;
		}

		if ( ! -f "$FILE" ) {
		    print "ERROR: not a file '$FILE'\n";
		    print "	LINE_GREP='$LINE_GREP'\n";
		    next;
		}

		if ( "$FIRSTFILE" eq "" ) {
		    ### TODO: work around differing files
		    ### (includes metadata check) with same
		    ### checksums.
		    ### So far we're only comparing with first found filename
			$FIRSTFILE	= "$FILE";
			$FIRSTINODE	= &getInode("$FILE");
			$FIRSTMETA	= &getMeta("$FILE");
			print "BASE: ($FIRSTINODE) $FILE\n";
		} else {
			### Files FIRSTFILE and FILE have same checksum
			$MERGE = "yes";

                        ### Check file sizes, can differ a lot with same weak checksum
                        if ( "$MERGE" eq "yes" &&
                    	     "$SZ" ne "$SIZE" ) {
                                $MERGE = "different sizes";
                        }

                        ### Check for null file sizes, they take no space anyway
                        ### But may be placeholders for some changes soon...
                        if ( "$MERGE" eq "yes" &&
                    	     "$SZ" eq "0" ) {
                                $MERGE = "null sized file";
                        }

                        ### What if "checksum" string was found in wrong column?
                        if ( "$MERGE" eq "yes" &&
                    	     "$CS" ne "$CKSUM" ) {
                                $MERGE = "different checksums";
                        }

			### Check inode numbers
			if ( "$MERGE" eq "yes" ) {
			    $CURRINODE = &getInode("$FILE");
			    if ( "$FIRSTINODE" eq "$CURRINODE" ) {
				$MERGE = "same inode $CURRINODE";
			    }
			}

			### Check owners and access rights (maybe dates)
			if ( "$MERGE" eq "yes" ) {
			    $CURRMETA = &getMeta ("$FILE");
			    if ( "$FIRSTMETA" ne "$CURRMETA" ) {
				$MERGE = "different metadata ('$FIRSTMETA' != '$CURRMETA')";
			    }
			}

			### Check if their contents differ
			if ( "$MERGE" eq "yes" ) {
			    $diff_out = `$DIFF "$FIRSTFILE" "$FILE" 2>&1`;
			    if ( $? != 0 || "$diff_out" ne "" ) {
				$MERGE = "different contents or diff error";
			    }
			}

			if ( "$MERGE" eq "yes" ) {
			    ### Unbreakable file mangling (don't want occasional
			    ### Ctrl+C to delete a file with no trace)
			    breakDisable;

			    if ( "$MKH_DEBUG" eq "no" ) {
				printMergeLog "'$SZ' bytes:	rm -f '$FILE' && ln '$FIRSTFILE' '$FILE'\n";
				if ( rename ( "$FILE", "$FILE.tmp.$$") ) {
			    	    if ( link ( "$FIRSTFILE", "$FILE" ) ) {
					unlink( "$FILE.tmp.$$" ) or printErrLog STDERR "Can't unlink original '$FILE.tmp.$$' after hardlinking!\n";
					$COUNT_MERGED++;
					$COUNT_MERGEDSZ += $SZ;
				    } else {
					rename ( "$FILE.tmp.$$", "$FILE" ) or printErrLog "Can't re-link '$FILE.tmp.$$' after unsuccessful hardlinking attempt!\n";
				    }
				}
			    } else {
				printMergeLog "DEBUG: '$SZ' bytes:	### rm -f '$FILE' && ln '$FIRSTFILE' '$FILE'\n";
				$COUNT_MERGED++;
				$COUNT_MERGEDSZ += $SZ;
			    }

			    breakEnable;
			} else {
			    printErrLog ( "SKIP: '$FILE' not merged with '$FIRSTFILE'\n" .
				"      (reason: $MERGE)\n" ); 
			    $COUNT_SKIPPED++;
			}
		} #// if FIRST or another file with same CKSUM
	} #// while grep CKSUM
	close GREP_CKSUM;
} #// while sort

close SORT;

printLog ( "--- ".&getDate().": done\n" );

printLog ( "===========
Results:
    Files skipped:	$COUNT_SKIPPED
    Files merged:	$COUNT_MERGED
    Space saved:	$COUNT_MERGEDSZ

" . `df -k "$MKH_BASEDIR"` );

close LOG;
exit 0;
