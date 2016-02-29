#!/usr/bin/perl -w
##-*- Mode: CPerl; coding: utf-8; -*-

use lib qw(. lib dclib dclib/blib/lib dclib/blib/arch);
use DiaColloDB::WWW::CGI;
use utf8;
use strict;
#use CGI '-debug';
BEGIN {
  #binmode(STDIN, ':utf8');
  #binmode(STDOUT,':utf8');
  binmode(STDERR,':utf8');
}

my $dbcgi = DiaColloDB::WWW::CGI->new();
$dbcgi->cgi_main();
