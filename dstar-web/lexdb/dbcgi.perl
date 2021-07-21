#!/usr/bin/perl -w
##-*- Mode: CPerl; coding: utf-8; -*-

use lib qw(. lib);
use DbCgi;
use File::Basename qw(basename);
use Cwd qw(abs_path);
use utf8;
use strict;
#use CGI '-debug';
BEGIN {
  #binmode(STDIN, ':utf8');
  #binmode(STDOUT,':utf8');
  binmode(STDERR,':utf8');
}

##----------------------------------------------------------------------
## local config

our $prog    = basename($0);
our $progdir = abs_path(".");

##-- BEGIN dstar config
our %dstar = qw(); #(foo=>'bar');
if (-r "$progdir/../dstar.rc") {
  do "$progdir/../dstar.rc" or die("$prog: failed to load '$progdir/../dstar.rc': $@");
}
##-- END dstar config

##-- BEGIN dstar local
my $rcfile = "$progdir/../local.rc";
if (-r $rcfile) {
  do $rcfile or die "$prog: could not load local config file '$rcfile': $@";
}
##-- END dstar local config

##----------------------------------------------------------------------
## dbcgi guts

my $cdb = DbCgi->new(ttk_vars=>{dstar=>\%dstar});
$cdb->cgi_main();
