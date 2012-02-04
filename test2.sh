cd /export/ftp-pub.cos.ru

 find . -type f -xdev | while read F; do echo $( ls -lai "$F" | awk '{print $6"\t"$1"\t"}'; md5sum "$F" ) & done > /tmp/fpub.md5

cat fpub.md5 | while read SZ IN CS NM; do echo -e "$CS $IN\t$SZ"; done | sort | uniq -c | perl -e 'my $pCS=""; $pIN=""; $pSZ=""; $pN=""; while (<>) { chomp; ($_SP, $N, $CS, $IN, $SZ) = split /\s+/,$_,5; if ( $pCS eq $CS ) { print "$pN\t$CS\t$SZ\t$pIN\t+$N x $IN\n"; }; $pCS=$CS; $pN=$N; $pIN=$IN; $pSZ=$SZ; }'> FPUB.md5.sort 

cat fpub.md5 | while read SZ IN CS NM; do echo -e "$CS $IN\t$SZ\t$NM"; done | sort > FPUB.md5

