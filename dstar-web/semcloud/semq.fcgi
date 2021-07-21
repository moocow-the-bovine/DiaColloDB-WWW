#!/usr/bin/perl -w
##-*- Mode: CPerl; coding: utf-8; -*-

use lib '.';
use DbCgi;
use utf8;
use strict;
#use CGI '-debug';

#use lib qw(/home/moocow/local/pdl/lib/perl5 /home/moocow/local/pdl/lib/perl);
#use lib qw(/home/moocow/work/diss/perl/MUDL);
use DocClassify;
use PDL;

BEGIN {
  #binmode(STDIN, ':utf8');
  #binmode(STDOUT,':utf8');
  binmode(STDERR,':utf8');
}

DocClassify::Logger->ensureLog();

my $cdb = DbCgi->new();
$cdb->fcgi_main();
