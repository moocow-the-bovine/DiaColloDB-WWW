#!/usr/bin/perl -w
##-*- Mode: CPerl; coding: utf-8; -*-

use lib qw(./lib);

use CGI qw(:standard :cgi-lib);
use DDC::Client::Distributed;
use DDC::Format::Text;
use DDC::Format::Kwic;
use DDC::Format::Template;
use DDC::Format::JSON;
use DDC::Format::YAML;
use DDC::Format::Raw;
use DTA::CAB::Client::HTTP;
use URI;
use URI::Escape qw(uri_escape_utf8);
use HTTP::Status;
use Encode qw(encode decode encode_utf8 decode_utf8);
use JSON;
use File::Basename qw(basename dirname);
use Cwd qw(abs_path);
use Date::Parse qw(str2time); ##-- for str2time()
use Time::HiRes qw(gettimeofday tv_interval);
use POSIX qw(strftime);
use utf8;
use strict;

our $VERSION = '0.60';
our $prog    = basename($0);
our $progdir = abs_path(dirname($prog));
BEGIN {
  #binmode(STDIN, ':utf8');
  #binmode(STDOUT,':utf8');
  binmode(STDERR,':utf8');
}

##-- timing
our ($t0);
BEGIN {
  $t0 = [gettimeofday];
}

##-- BEGIN dstar config
our %dstar = (server_host=>'127.0.0.1', server_port=>'52000', corpus=>'corpus',
	      stringifyComments=>1, stringifyUser=>1, stringifyPeer=>1, stringifyRoles=>1);
if (-r "$progdir/dstar.rc") {
  do "$progdir/dstar.rc" or die("$prog: failed to load '$progdir/dstar.rc': $@");
}
##-- END dstar config

##======================================================================
## globals ; override these locally in "local.rc"

our $allow_alternate_server = 1; ##-- allow user to pass in 'ddc' or 'server' parameter for server contact info?
our $allow_debug = 1;            ##-- honor the 'debug' parameter?
our $dropFields = [qw(lts con)]; ##-- ignore these token-level index fields
our $charset = 'utf-8'; 	 ##-- this is all we support for now

## %ddc_client_opts : options for DDC::Client::Distributed
our %ddc_client_opts= (
		       #connect=>{PeerAddr=>$dstar{server_host},PeerPort=>$dstar{server_port}}, ##-- set below, after local.rc has been loaded
		       start=>0, ##-- ddc 'start' param starts at 0; cgi param starts at 1...
		       limit=>10,
		       #timeout=>60, ##-- original timeout: 1min
		       timeout=>300, ##-- conservative timeout: 5min
		       hint=>'',
		       encoding=>$charset,
		       parseMeta=>1,
		       parseContext=>1,
		       expandFields=>1,
		       keepRaw => 0,
		       dropFields=>$dropFields,
		       fieldSeparator=>"\x{1f}",
		       tokenSeparator=>"\x{1e}",
		      );

## %fmt_opts : options for DDC::Format
our %fmt_opts = (
		 columns => 80,
		 level   => 0,
		 vars    => {
			     ##-- variables for template formatting
			     #root_timestamp_file => "$0",
			     VERSION => $VERSION,
			    },
		);

my $filebase = "dstar".strftime("%Y%m%d%H%M%S",localtime(time));

##-- %fmt : ($fmtName => {type=>$fmtType, ext=>$ext, class=>$fmtClass, opts=>\%opts}
my %ttopts = (config => {%{DDC::Format::Template->new->{config}}, ENCODING=>'utf8'} );
my %fmt_json = (type=>'application/json', class=>'DDC::Format::JSON',
		headers=>{
			  '-Content-Disposition'=>"inline; filename=\"$filebase.json\"",
			  #'-Access-Control-Allow-Origin' => '*', ##-- mantis #40432 (disabled 2021-05-17)
			 });
our %fmt =
  (
   ##-- top-level pseudo-formats
   'index' => {type=>'text/html', class=>'DDC::Format::Template', opts=>{src=>'index.ttk',%ttopts}, noexport=>1},
   'osd'   => {type=>'text/xml',  class=>'DDC::Format::Template', opts=>{src=>'osd.ttk',%ttopts}},
   'siterc' => {type=>'text/plain', class=>'DDC::Format::Template', opts=>{src=>'siterc.ttk',%ttopts}, noexport=>1},
   'details' => {type=>'text/html', class=>'DDC::Format::Template', opts=>{src=>'details.ttk',%ttopts}},
   ##
   ##-- search result formats
   ddc  => {class=>'redirect', url=>'ddc-cgi.perl', vars=>[qw(q mode start limit)], params=>{raw=>1}},
   html => {type=>'text/html', class=>'DDC::Format::Template', opts=>{src=>'html.ttk',%ttopts}},
   kwic => {type=>'text/html', class=>'DDC::Format::Template', opts=>{src=>'kwic.ttk',%ttopts}, ext=>'kwic.html'},
   text => {type=>'text/plain', class=>'DDC::Format::Text', headers=>{'-Content-Disposition'=>"inline; filename=\"$filebase.txt\""}, ext=>'txt'},
   'text-kwic' => {type=>'text/plain', class=>'DDC::Format::Kwic', headers=>{'-Content-Disposition'=>"inline; filename=\"$filebase.txt\""}, ext=>'txt'},
   json => {%fmt_json},
   json1 => {%fmt_json, opts=>{level=>1}, ext=>'json'},
   json2 => {%fmt_json, opts=>{level=>2}, ext=>'json'},
   yaml => {type=>'text/x-yaml', class=>'DDC::Format::YAML', headers=>{'-Content-Disposition'=>"inline; filename=\"$filebase.yml\""}, ext=>'yml'},
   rss  => {type=>'application/rss+xml', class=>'DDC::Format::Template', opts=>{src=>'rss.ttk',%ttopts}, headers=>{'-Content-Disposition'=>"inline; filename=\"$filebase.rss\""}},
   atom => {type=>'application/atom+xml', class=>'DDC::Format::Template', opts=>{src=>'atom.ttk',%ttopts}, headers=>{'-Content-Disposition'=>"inline; filename=\"$filebase.atom\""}},
   tcf => {type=>'text/tcf+xml', class=>'DDC::Format::Template', opts=>{src=>'tcf.ttk',%ttopts}, headers=>{'-Content-Disposition'=>"inline; filename=\"$filebase.tcf\""}},
   csv => {type=>'text/csv', class=>'DDC::Format::Template', opts=>{src=>'csv.ttk',%ttopts}, headers=>{'-Content-Disposition'=>"inline; filename=\"$filebase.csv\""}, ext=>'csv'},
   tsv => {type=>'text/tab-separated-values', class=>'DDC::Format::Template', opts=>{src=>'csv.ttk',%ttopts}, headers=>{'-Content-Disposition'=>"inline; filename=\"$filebase.tsv\""}, ext=>'tsv'},
   ##
   ##-- time-series (histogram) formats
   'hist-html' => {type=>'text/html', class=>'DDC::Format::Template', opts=>{src=>'hist.ttk',%ttopts},  noexport=>1},
   'hist-plot' => {class=>'redirect', url=>'dhist-plot.perl', noexport=>1},
   'hist-help' => {type=>'text/html', class=>'DDC::Format::Template', opts=>{src=>'help-hist.ttk',%ttopts}, noexport=>1},
   ##
   ##-- term expansion (lizard) formats
   'expand-html' => {type=>'text/html', class=>'DDC::Format::Template',        opts=>{src=>'expand-html.ttk',%ttopts}, noexport=>1},
   'expand-json' => {type=>'application/json', class=>'DDC::Format::Template', opts=>{src=>'expand-json.ttk',%ttopts}, noexport=>1},
   'expand-text' => {type=>'text/plain', class=>'DDC::Format::Template',       opts=>{src=>'expand-text.ttk',%ttopts}, noexport=>1},
   ##
   ##-- configuration dump fomats (siterc.vars etc.)
   'config' => {type=>'application/json', class=>'DDC::Format::Template',  opts=>{src=>'config.ttk',%ttopts}, noexport=>1},
  );
$fmt{raw} = $fmt{ddc};
$fmt{txt} = $fmt{text};
$fmt{yml} = $fmt{yaml};
$fmt{web} = $fmt{html};
$fmt{expand} = $fmt{'expand-html'};
$fmt{"config-$_"} = $fmt{'config'}
  foreach (qw(all env site auth stash));
$fmt{hist} = $fmt{ts} = $fmt{'ts-html'} = $fmt{'hist-html'};
$fmt{"help-hist"} = $fmt{"hist-help"};
$fmt{plot} = $fmt{'ts-plot'} = $fmt{'hist-plot'};
$fmt{'csv-kwic'} = $fmt{'csv'};
$fmt{'tsv-kwic'} = $fmt{'tsv'};

##-- %flags : ($flagsAlias => $flags_regex, ...), for deprecated dta-style 'flags' (formerly 'corpus') parameter
our (%flags);

##-- default format
my ($prog_fmt);
if    ($fmt{$prog}) { $prog_fmt = $prog; }
elsif ($prog =~ /^(.*?)\.perl$/i && $fmt{$1}) { $prog_fmt = $1; }
elsif ($prog =~ /\b(?:lizard|expand)\b/) { $prog_fmt ='expand-html'; }
elsif ($prog =~ /\b(?:hist|ts)\b/) { $prog_fmt = 'hist-html'; }
elsif ($prog =~ /\b(?:tcf)\b/) { $prog_fmt = 'tcf'; }
elsif ($prog =~ /\b(?:config)\b/) { $prog_fmt = 'config'; }

##-- %defaults: cgi paramter defaults
our %defaults =
  (
   #'q'    => 'NOQUERY',
   #'q' => encode_utf8("\x{f6}de"), ##-- utf8 bytes
   #'q' => "\xf6de", ##-- latin1 bytes

   'start' => 1, ##-- ddc 'start' param starts at 0; cgi param starts at 1...
   'limit' => 10,
   'fmt'   => ($prog_fmt // 'kwic'),
   'hint'  => '',
   #'export' => '',
   ##
   wf => ($dstar{text_attr} // 'w'), ##-- token text field
   ##
   #'pretty'=> 0,
   #'debug' => 0,
   ##
   #ctx => 8, ##-- kwic context-width (see common.ttk)
   ##
   ##-- lizard defaults
   'x' => 'Token',
   ##
   ##-- DEBUG
   #q => '@seyn with $page=68 #has[dtaid,16168]',
   #q => '$u=@Heilk with $page=24 #has[dtaid,16489] #cntxt 1',
   #q => "\x{f6}de",
  );

##----------------------------------------------------------------------
## local config
my $rcfile = "$progdir/local.rc";
if (-r $rcfile) {
  do $rcfile or die "$prog: could not load local config file '$rcfile': $@";
}

##======================================================================
## subs: generic

*htmlesc = \&escapeHTML;

## $escaped_br = escapeHTMLbr($str)
##  + escapes HTML and inserts <br/> for line-breaks
sub escapeHTMLbr {
  my $str = escapeHTML($_[0]);
  $str =~ s{\r?\n}{<br/>}g;
  return $str;
}

## $escaped = escapeXML($str)
sub escapeXML {
  my $str = shift;

  ##-- XML escapes (should be handled elsewhere)
  $str =~ s/\&/\&amp;/sg;
  $str =~ s/\'/\&apos;/sg;
  $str =~ s/\"/\&quot;/sg;
  $str =~ s/\</\&lt;/sg;
  $str =~ s/\>/\&gt;/sg;

  return $str;
}

## $escaped = escapeDDC($str)
##  + returns escaped DDC string
sub escapeDDC {
  my $s = shift;
  return $s if ($s !~ m/\W/);
  $s =~ s/([\'\\])/\\$1/g;
  return "'$s'";
}

## $prevhint = hint_prev($hint, $pagesize)
sub hint_prev {
  my ($hint,$pagesize) = @_;
  $hint = '' if (!defined($hint));
  $hint =~ s/\s.*$//;
  $hint =~ s{([0-9]+)}{$1 > $pagesize ? ($1-$pagesize) : 0}ge;
  return $hint;
}

##======================================================================
## cgi parameters

##-- DEBUG
sub showq {
  return;
  my ($lab,$q) = @_;
  printf STDERR
    ("$0: $lab: q=$q \[utf8:%d,valid:%d,check:%d]\n",
     (utf8::is_utf8($q) ? 1 : 0),
     (utf8::valid($q) ? 1 : 0),
     (Encode::is_utf8($q,1) ? 1 : 0),
    );
}

##-- get params
my $vars = {};
if (param()) {
  $vars = { Vars() }; ##-- copy tied Vars()-hash, otherwise utf8 flag gets handled wrong!
}
if (defined($vars->{POSTDATA}) && !$vars->{'q'}) {
  ##-- read query from POSTDATA pseudo-parameter if otherwise unspecified
  $vars->{'q'} = $vars->{POSTDATA};
  ##
  ##-- ... and explicitly parse params from query string; required for CGI::Fast or non-form POST requests (which set POSTDATA)
  my $uri  = URI->new( $ENV{REQUEST_URI} || self_url() );
  my %urif = $uri->query_form();
  @$vars{keys %urif} = values %urif;
}
showq('init', $vars->{q}//'');

charset($charset); ##-- initialize charset AFTER calling Vars(), otherwise fallback utf8::upgrade() won't work

##-- instantiate defaults
$vars->{$_} = $defaults{$_} foreach (grep {!exists($vars->{$_})} keys %defaults);
$vars->{$_} = $defaults{$_} foreach (grep {!defined($vars->{$_}) || $vars->{$_} !~ /^[\-\+]?[0-9]+$/} qw(start limit));
$vars->{$_} = $defaults{$_} foreach (grep {!defined($vars->{$_}) || $vars->{$_} eq ''} qw(fmt));
showq('default', $vars->{q});

##-- sanitize vars
foreach (keys %$vars) {
  next if (!defined($vars->{$_}));
  my $tmp = $vars->{$_};
  $tmp =~ s/\x{0}//g;
  eval {
    ##-- try to decode utf8 params e.g. "%C3%B6de" for "öde"
    $tmp = decode_utf8($tmp,1) if (!utf8::is_utf8($tmp) && utf8::valid($tmp));
  };
  if ($@) {
    ##-- decoding failed; treat as bytes (e.g. "%F6de" for "öde")
    utf8::upgrade($tmp);
    undef $@;
  }
  $vars->{$_} = $tmp;
}
our $fmt = $vars->{fmt} = lc($vars->{fmt});
#$vars->{pretty} = 1 if (exists($vars->{pretty}) && $vars->{pretty} eq '');
#$vars->{debug}  = 1 if (exists($vars->{debug}) && $vars->{debug} eq '');
$vars->{pretty} = 1 if (!$vars->{pretty} && $allow_debug && $vars->{debug});
$vars->{server} //= $vars->{ddc}; ##-- backwards-compatible alias

showq('sanitized', $vars->{q});

##======================================================================
## check for redirects

##-- tweak format, check for empty queries
$fmt =~ s/^lizard/expand/;
$fmt = "expand-$fmt"   if ($fmt !~ /^expand/      && $prog =~ /^(?:lizard|expand)/);
$fmt = "hist-$fmt"     if ($fmt !~ /^(?:hist|ts)/ && $prog =~ /^(?:hist|ts\b)/);
$fmt = "tcf"           if ($fmt !~ /^tcf/         && $prog =~ /^(?:tcf)\b/);
$fmt = "config-$fmt"   if ($fmt !~ /^config/      && $prog =~ /^(?:config)\b/);
$fmt = 'index'         if (!$vars->{q} && $fmt !~ /^(?:expand|hist|ts\b|osd|siterc|details|tcf|help|config)/);
$vars->{fmt} = $fmt;
our $fmth = $fmt{$fmt};

##-- check for redirect queries
if ($fmth && ($fmth->{class}//'') eq 'redirect') {
  my %params = (
		($fmth->{vars}   ? (map {($_=>$vars->{$_})} @{$fmth->{vars}}) : %$vars),
		%{$fmth->{params}//{}},
	       );
  print redirect(-status=>303,
		 -uri=>($fmth->{url}
			."?"
			.join("&",
			      map {$params{$_} ? ("$_=".uri_escape_utf8($params{$_})) : qw()}
			      keys %params
			     )
		       ),
		);
 exit 0;
}

##======================================================================
## subs: wrapper guts

## $open = openTag("<tag>", %attrs)
sub openTag {
  my ($tag,%attrs) = @_;
  return ''   if (!$tag);
  return $tag if (!%attrs);
  $tag =~ s/>\s*\z//s;
  foreach (keys %attrs) {
    $tag .= " $_=\"".htmlesc($attrs{$_})."\"" if (defined($attrs{$_}));
  }
  return $tag . ">";
}

## $str = ctxWrapTokens(\@token_refs_or_strings, %opts)
##  + wraps tokens as "\x{02}$TOKEN_TEXT\x{03}" (no match) or "\x{04}$TOKEN_TEXT\x{03}" (match)
##  + %opts: wf=>$wf
sub ctxWrapTokens {
  my ($words,%opts) = @_;
  my $wf = $opts{wf} // $vars->{wf} // 'w';
  my $str = join('',
		 map {
		   (
		    (ref($_) && exists($_->{ws}) && ($_->{ws}//'') ne '' && !$_->{ws} ? '' : ' ')
		    .(ref($_) && $_->{hl_} ? "\x{02}" : "\x{04}")
		    .(ref($_) ? $_->{$wf} : $_)
		    ."\x{03}")
		  } @$words
		)."\n";
  $str =~ s/^ //;
  return $str;
}

## $str = ctxUntokenize($wrappedTokenString)
## $str = ctxUntokenize($wrappedTokenString)
sub ctxUntokenize {
  my $str = shift;

  ##-- punctuation heuristics
  my $wl  = qr/[\x{02}\x{04}]/;
  my $wr  = qr/\x{03}/;
  my $ql  = qr/[\(\[\{\x{2018}\x{201c}\x{2039}\x{201a}\x{201e}]/;
  my $qr  = qr/[\)\]\}\x{2019}\x{201d}\x{203a}]/;
  my $nqr = qr/[^\)\]\}\x{2019}\x{201d}\x{203a}]/;
  my $qq  = qr/[\"\`\'\x{ab}\x{bb}]/;
  my $nqq = qr/[^\"\`\'\x{ab}\x{bb}]/;
  my $pr  = qr/[\,\.\!\?\:\;\%]|[\x{2019}\x{201d}\x{203a}][snm]/;
  $str =~ s|(\s${wl}${qq}+${wr})\s(${nqq}*)\s(${wl}${qq}+${wr}\s)|$1$2$3|sg;
  $str =~ s|(\s${wl}${ql}${wr})\s|$1|sg;
  $str =~ s|\s(${wl}${qr}${wr}\s)|$1|sg;
  $str =~ s|\s(${wl}${pr}${wr}\s)|$1|sg;

  ##-- html escapes (should be handled elsewhere)
  #$str =~ s/\&/\&amp;/sg;
  #$str =~ s/\'/\&#39;/sg;
  #$str =~ s/\"/\&quot;/sg;
  #$str =~ s/\</\&lt;/sg;
  #$str =~ s/\>/\&gt;/sg;

  return $str;
}

## $str = ctxUnwrapTokens($wrappedTokenStr)
sub ctxUnwrapTokens {
  my $str = shift;

  ##-- remove separators
  $str =~ s/[\x{02}-\x{04}]//g;

  return $str;
}

## $str = ctxString(\@token_refs_or_strings,%opts)
##  + %opts
##     untokenize => $bool, ##-- default=1
##     unwrap=> $bool,      ##-- default=0
##     wf => $wf
sub ctxString {
  my ($words,%opts) = @_;
  my $str = ctxWrapTokens($words,%opts);
  $str = ctxUntokenize($str) if ($opts{untokenize}//1);
  $str = ctxUnwrapTokens($str) if ($opts{unwrap}//0);
  return $str =~ /^\s*$/ ? '' : $str;
}

## $str = contextString($hit, $matchOpen,$matchClose, \%opts)
##  + context string generator
##  + %opts include:
##    (
##     span       => [$wOpen,$wClose],
##     titleAttrs => \@attrs,
##     matchid    => [$matchIdOpen,$matchIdClose]
##     escape     => $how, ##-- 'html', 'xml', or false (default='html')
##    )
sub contextString {
  my ($hit,$open,$close,$opts) = @_;

  $open  = '' if (!defined($open));
  $close = '' if (!defined($close));
  $opts  = {} if (!defined($opts));
  my $span  = $opts->{span} // ['',''];
  my $wf    = $vars->{wf} || 'w';
  my $ctx   = $hit->{ctx_};
  $wf = $hit->{meta_}{indices_}[0] if (($ctx->[1][0]{$wf}||'') eq ''); ##-- hack for '#within file' queries

  ##-- escape sub
  my $escapeHow = defined($opts->{escape}) ? lc($opts->{escape}) : 'html';
  my $escapeSub = ($escapeHow eq 'html' ? \&escapeHTML
		   : ($escapeHow eq 'xml' ? \&escapeXML
		      : sub { $_[0] }));

  ##-- generate context strings: with 'ws' field
  ## + we need to check for empty hit token 'ws' field in order to catch '#in file' queries
  my $has_ws   = ((grep {$_ eq 'ws'} @{$hit->{meta_}{indices_}}) && !(grep {!ref($_) || ($_->{ws}//'') eq ''} @{$ctx->[1]}));
  my $deep_ctx = UNIVERSAL::isa($ctx->[0][0],'HASH') || UNIVERSAL::isa($ctx->[2][0],'HASH');
  my $str = (ctxString($ctx->[0], wf=>$wf,  untokenize=>!($deep_ctx && $has_ws))
	     .ctxString($ctx->[1], wf=>$wf, untokenize=>!$has_ws)
	     .ctxString($ctx->[2], wf=>$wf, untokenize=>!($deep_ctx && $has_ws))
	    );
  
  ##-- highlighting
  my $i=0;
  my $ostr='';
  my @tokens = map {@$_} @$ctx;
  my ($w,$wtxt,$wstart,$tag0,$tag1,$title);
  while ($str =~ m|\G([^\x{02}-\x{04}]*)([\x{02}\x{04}])([^\x{03}]*)\x{03}|sg) {
    $ostr  .= $1;
    $wstart = $2;
    $wtxt   = $3;
    if ($wstart eq "\x{02}") {
      ($tag0,$tag1) = ($open,$close);
    } else {
      ($tag0,$tag1) = @$span;
    }
    $w = $tokens[$i++];
    if ($opts->{titleAttrs}) {
      $title = join(', ', map {$_."=".(ref($w) && defined($w->{$_}) ? $w->{$_} : '-')} @{$opts->{titleAttrs}});
      $ostr .= openTag($tag0, title=>$escapeSub->($title));
    } elsif (defined($tag0)) {
      $ostr .= $tag0;
    }
    $ostr .= $escapeSub->($wtxt).($tag1||'');
    if (ref($w) && $w->{hl_} && $opts->{matchid}) {
      $ostr .= $opts->{matchid}[0] . $w->{hl_} . $opts->{matchid}[1];
    }
  }
  $ostr .= $escapeSub->($1) if ($str =~ m/([^\x{03}]*)$/);

  return $ostr;
}


##======================================================================
## MAIN

our ($content, $qbase);
eval {
  my ($hits,%fvars);

  ##-- ensure valid format
  die("$prog: unknown format '$fmt'") if (!$fmth);

  ##-- sanity checks: cowardly refuse to serve up apache site config
  die("site-rc generation disabled from web\n")
    if ($fmt eq 'siterc' && getpwuid($<) eq 'www-data');
  die("configuration dump disabled via $prog\n")
    if ($fmt =~ /^config/ && $prog !~ /^config/);

  ##-- setup ddc client
  $ddc_client_opts{connect} = {PeerAddr=>$dstar{server_host}, PeerPort=>$dstar{server_port}};
  if ($allow_alternate_server && defined($vars->{server})) {
    my ($host,$port) = split(/:/,$vars->{server},2);
    $ddc_client_opts{connect}{PeerAddr}=$host if ($host);
    $ddc_client_opts{connect}{PeerPort}=$port if ($port);
  }
  my $dclient = DDC::Client::Distributed->new(%ddc_client_opts)
    or die("$prog: could not create DDC client");

  if ($fmt =~ /^expand/) {
    ##----------------------------------------------------------------------
    ## Get DDC expansions (adapted from dtaos lizard.perl)
    ##  + $qxl = [$word1, $word2, ...]
    ##  + $qx  = join(' ', @$qxl)
    ##  + $qxh = { $word => {n=>$n, w=>$word, wx=>escapeHTML($w), ux=>uriEscape($w), ...} }
    my ($q,$qxl,$qx,$qxh);
    if (defined($q=$vars->{'q'})) {
      if (defined($qx=$vars->{'qx'})) {
	$qxl = [split(' ', $qx)];
      } else {
	##-- sanitize query string
	$q =~ s/^(?:\$\w+=)?\@?\{(.*)\}\s*/$1/;

	my $terms = [grep {$_ !~ /^\#/} split(/[\s\,\;]/,$q)];
	foreach (@$terms) {
	  s/(?:^\"|\"$)//g;
	  s/\$[^\=]+=//;
	  s/^\@//;
	  s/^\'(.*)\'$/$1/;
	}
	@$terms = grep {defined($_) && $_ ne ''} @$terms;
	$q      = join(' ',@$terms);

	$dclient->open()
	  or die("$prog: could not connect to DDC server on $dclient->{connect}{PeerAddr}:$dclient->{connect}{PeerPort}: $!");

	my $chain   = $vars->{x} // 'Token';
	my $buf     = $dclient->expand_terms($vars->{'x'}, $terms);
	utf8::decode($buf) if (!utf8::is_utf8($buf));
	my ($status,$data) = split(/\n/,$buf,2);
	my ($rc,$n) = split(' ',$status);
	die("$prog: could not expand term '$q': $data") if ($rc != 0);
	$qxl = [grep {defined($_) && $_ ne ''} split(/[\t\n]/, $data)];
	$qx  = $vars->{qx} = join(' ', grep {defined($_) && $_ ne ''} @$qxl);
      }
    }

    ##-- sanitize qxl, build qxh
    my ($w);
    $qxh = { map {($_=>{w=>$_})} @$qxl };
    @$qxl   = sort keys %$qxh;
    foreach (0..$#$qxl) {
      $w = $qxl->[$_];
      $qxh->{$w} = {n=>$_, w=>$w, wx=>escapeHTML($w), ux=>uri_escape_utf8(escapeDDC($w))};
    }

    %fvars = (
	      'q'    => $q,
	      'x'    => $vars->{x},
	      'qx'   => $vars->{qx},
	      'qxl'  => $qxl,
	      'qxh'  => $qxh,
	     );
  }
  elsif ($fmt !~ m/^(?:index|osd|siterc|config.*|details|help\-hist)$/) {
    ##----------------------------------------------------------------------
    ## Get DDC hits (if applicable)

    ## $query  : raw query as passed by user
    ## $cquery : tweaked query (with internal tweaks, e.g. for auto-generated random seed)
    my ($query,$cquery);

    ##-- prepare & send query
    $query  = $vars->{'q'} // '';

    ##-- query hacks: visible: dta: w2->u (backwards-compatible)
    if ($vars->{wf} eq 'u') { $query =~ s/\$w2=/\$u=/g; }

    ##-- query hacks: visible: random
    if ($query =~ m/\s(\#rand(?:om)?)/i) { ##-- negative lookahead outputs bogus "#rand[y]om[x]" for input "#random[x]"
      my $rend = $+[0];
      if (substr($query,$rend) !~ /^\s*\[/) {
	my $seed = time() % 100; ##-- 100 seeds should be enough for auto-generation
	substr($query,$rend,0,"[$seed]");
      }
    }

    ##-- query hacks: visible: dta: flags
    $vars->{flags} ||= $vars->{corpus};
    if (%flags && $vars->{flags} && $query !~ / \#has\[(?:flags|corpus),/) {
      foreach my $flag (grep {$_ ne 'all'} split(' ', $vars->{flags})) {
	if (exists($flags{$flag})) {
	  $query .= " #has[flags,/$flags{$flag}/]";
	}
	elsif ($flag eq 'none') {
	  $query .= ' #has[flags,/^$/]';
	}
	else {
	  $query .= " #has[flags,/\\b$flag\\b/]"; ##-- expect literal regex for un-registered flags
	}
      }
    }

    ##-- query hacks: invisible
    $cquery = $query; ##-- query as passed to client (with internal hacks)

    ##-- query hacks: invisible: #offset, #limit
    while ($cquery =~ s{\s\#(?:start|off(?:set)?)\s+([0-9]+)\b}{ }i) {
      $vars->{start} = $1;
    }
    while ($cquery =~ s{\s\#(?:limit)(?:\s+|\[\s*)([\+\-]?[0-9]+)\b\]?}{ }i) {
      $vars->{limit} = $1;
    }
    $dclient->{start} = ($vars->{start} > 0 ? ($vars->{start}-1) : 0);
    $dclient->{limit} = $vars->{limit};
    $dclient->{hint}  = $vars->{hint} if (!$dstar{ignore_user_hints});

    ##-- query hacks: invisible: comments (~ zwei.dwds.de lib/DWDS/DDC/Query.pm)
    my $ccmts='';
    if ($dstar{stringifyComments}) {
      $ccmts = (($dstar{stringifyRoles} ? "\n#:~dstar" : '')
		.($dstar{stringifyUser} || $dstar{stringifyPeer}
		  ? ("\n#:<"
		     .($dstar{stringifyUser} ? ($ENV{REMOTE_USER} || "anonymous") : '?')
		     .'@'
		     .($dstar{stringifyPeer} ? ($ENV{REMOTE_HOST} || $ENV{REMOTE_ADDR} || '?') : '-'))
		  : '')
		."\n");
    }

    ##-- hit retrieval guts
    if ($cquery ne '' && $fmt ne 'hist') {
      $dclient->open()
	or die("$prog: could not connect to DDC server $dclient->{connect}{PeerAddr} port $dclient->{connect}{PeerPort}: $!");
      my $buf  = $dclient->queryRaw($cquery.$ccmts)
	or die("$prog: queryRaw ($cquery) failed: $!");

      ##-- cooked mode: do some parsing
      $hits = $dclient->parseData($buf)
	or die("$prog: parseData() failed: $!");

      ##-- check for errors
      die("DDC server error ($hits->{istatus_} $hits->{nstatus_}): $hits->{error_}\n")
	if ($hits->{error_});

      ##-- mark matches for each hit
      foreach (@{$hits->{hits_}//[]}) {
	$_->{matches} = [grep {$_->{hl_}} @{$_->{ctx_}[1]}];
      }
    }

    ##-- format sanity check
    if (@{$hits->{counts_}//[]} && !@{$hits->{hits_}//[]} && $fmt =~ /^(?:atom|rss|tcf)/) {
      die("$prog: count() queries are not currently supported for the '$fmt' output format");
    }

    ##-- setup format options
    %fvars = (
	      query  => $query,
	      cquery => $cquery,
	      ccmts  => $ccmts,
	      startIndex   => $dclient->{start}+1, ##-- ddc 'start' param starts at 0; cgi param starts at 1...
	      itemsPerPage => $dclient->{limit},
	      hint_cur     => $dclient->{hint},
	      hint_next    => $hits->{hint_},
	      hint_self    => hint_prev($hits->{hint_},   $dclient->{limit}),
	      hint_prev    => hint_prev($hits->{hint_}, 2*$dclient->{limit}),
	     );
  }

  ##-- munge dstar location defaults
  $dstar{www_host} = $ENV{HTTP_HOST} if ($ENV{HTTP_HOST});
  if ($ENV{REQUEST_URI}) {
    my $path = URI->new($ENV{REQUEST_URI})->path();
    $dstar{www_path} = $path =~ m{/$} ? $path : dirname($path);
  }
  $dstar{www_url}  = "//$dstar{www_host}$dstar{www_path}" if ($ENV{HTTP_HOST} || $ENV{REQUEST_URI});

  ##-- setup format
  %{$fmt_opts{vars}} = (%{$fmt_opts{vars}},
			%fvars,
			client => $dclient,
			defaults => \%defaults,
			dstar => \%dstar,
			encode_utf8 => \&encode_utf8,
			decode_utf8 => \&decode_utf8,
			'escapeHTML' => \&escapeHTML,
			'escapeHTMLbr' => \&escapeHTMLbr,
			'escapeXML' => \&escapeXML,
			'escapeDDC' => \&escapeDDC,
			'to_json'   => sub { return @_==1 ? JSON::to_json($_[0]) : JSON::to_json($_[0],$_[1]) },
			sprintf => sub { return CORE::sprintf($_[0],@_[1..$#_]); },
			'strftime' => sub { POSIX::strftime(map {UNIVERSAL::isa($_,'ARRAY') ? @$_ : $_} @_) },
			'str2time' => sub { Date::Parse::str2time(@_) },
			contextString => \&contextString,
			cgi    => $vars,
			ENV    => \%ENV,
			HTTP_HOST => $ENV{HTTP_HOST},
			##-- timing
			t0 => $t0,
		       );

  my $fmt_class = $fmth->{class}
    or die("$prog: unknown format '$fmt'");
  my $fmt_obj = $fmt_class->new(%fmt_opts, start=>$dclient->{start}, encoding=>$charset, level=>$vars->{pretty}, %{$fmt{$fmt}{opts}||{}})
    or die("$prog: could not create formatter object of class $fmt_class: $!");

  ##-- dump formatted data
  $content .= $fmt_obj->toString($hits)
    or die("$prog: could not format hits");
  $content = encode($charset, $content) if ($charset && utf8::is_utf8($content));
};

##----------------------------------------------------------------------
## ... something went wahooni shaped ...
if ($@) {
  my $msg = "$@";
  if ($fmt =~ /^(?:osd|siterc)$/) {
    ##-- offline mode: just die
    die "$msg";
  }
  print
    (header(-status=>RC_INTERNAL_SERVER_ERROR),
     start_html('Error'),
     h1('Error'),
     pre(htmlesc($msg)),
     end_html);
  exit 1;
}

##----------------------------------------------------------------------
## dump content
my $type    = $fmth->{type} || 'application/octet-stream';
my %headers = %{$fmth->{headers}||{}};
if ($allow_debug && $vars->{debug} && $fmt ne 'index') {
  if   ($type =~ /\bxml\b/) { $type = 'text/xml'; }
  else { $type = 'text/plain'; }
  delete $headers{'-Content-Disposition'};
}
elsif ($vars->{export} && !$fmth->{noexport}) {
  #my $xfile = $vars->{'q'} // 'dstar';
  #$xfile =~ s/[^\w\s]//g;
  #$xfile =~ s/\s+/_/g;
  #$xfile .= ".".($fmth->{ext} // $fmt);
  ##~
  my $xfile = $filebase . "." . ($fmth->{ext} // $fmt);
  $headers{'-Content-Disposition'} = "attachment; filename=\"$xfile\"";
  $type = 'application/octet-stream' if ($type eq 'text/plain');
  $type =~ s{^text/}{application/};
}
print header(-type=>$type,
	     -charset=>$charset,
	     %headers
	    ), $content;
