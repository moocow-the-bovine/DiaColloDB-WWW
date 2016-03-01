#!/usr/bin/perl -w

use lib qw(. ./blib/lib ./blib/arch lib lib/blib/lib lib/blib/arch);
use DiaColloDB::WWW;
use DiaColloDB::WWW::CGI;
use Getopt::Long qw(:config no_ignore_case);
use Cwd qw(abs_path);
use File::Basename qw(basename);
use File::ShareDir qw(:ALL);
use File::Copy qw(copy);
use File::Copy::Recursive qw(dircopy);
use File::chmod::Recursive;
use File::Path qw(make_path remove_tree);
use Pod::Usage;
use strict;

##----------------------------------------------------------------------
## Globals
##----------------------------------------------------------------------

##-- program vars
our $prog  = basename($0);
our ($help,$version);

our %log = (level=>'TRACE', rootLevel=>'FATAL');
our $force = 0;
our $wwwdir = undef;

my %rcfiles = (
	       'dstar.rc' => dist_file("DiaColloDB-WWW",'rc/dstar.rc'),
	       'local.rc' => dist_file("DiaColloDB-WWW",'rc/local.rc'),
	       'dstar/corpus.ttk' => dist_file("DiaColloDB-WWW",'rc/corpus.ttk'),
	       'dstar/custom.ttk' => dist_file("DiaColloDB-WWW",'rc/custom.ttk'),
	      );
my $want_siterc = 1;
my %site = (
	    'alias' => undef,
	   );

##----------------------------------------------------------------------
## Command-line processing
##----------------------------------------------------------------------
GetOptions(##-- general
	   'help|h' => \$help,
	   'version|V' => \$version,
	   #'verbose|v=i' => \$verbose,

	   ##-- generation
	   'dstar-rc|dstar|drc|rc|d=s' => \$rcfiles{'dstar.rc'},
	   'local-rc|local|lrc|l=s' => \$rcfiles{'local.rc'},
	   'corpus-ttk|corpus|c=s' => \$rcfiles{'dstar/corpus.ttk'},
	   'custom-ttk|custom|C=s'  => \$rcfiles{'dstar/custom.ttk'},
	   'site-rc|siterc|site!' => \$want_siterc,
	   'site-alias|alias|a=s' => \$site{alias},

	   ##-- logging
	   'log-level|level|ll=s' => sub { $log{level} = uc($_[1]); },
	   'log-option|logopt|lo=s' => \%log,

	   ##-- I/O
	   'force|f!' => \$force,
	   'output|out|o=s' => \$wwwdir,
	  );

pod2usage({-exitval=>0,-verbose=>0}) if ($help);
if ($version) {
  print STDERR "$prog version $DiaColloDB::WWW::VERSION by Bryan Jurish\n";
  exit 0 if ($version);
}
pod2usage({-exitval=>0,-verbose=>0,-msg=>"no DBDIR specified!"}) if (@ARGV < 1);


##----------------------------------------------------------------------
## MAIN
##----------------------------------------------------------------------

##-- setup logger
DiaColloDB::Logger->ensureLog(%log);
my $logger = 'DiaColloDB::WWW';

##-- command-line arguments
my $dbdir = shift;
$dbdir    =~ s{/$}{};
$wwwdir //= "$dbdir.www";
$wwwdir   =~ s{/$}{};


##-- get source directory via File::ShareDir
my $srcdir = File::ShareDir::dist_dir('DiaColloDB-WWW');
$srcdir   =~ s{/$}{};
my $docdir = "$srcdir/htdocs";
-d $docdir
  or $logger->logdie("no source directory '$docdir' found");

##-- ensure output directory exists
$logger->logdie("output directory '$wwwdir' exists, use --force option to overwrite") if (-e $wwwdir && !$force);
-d $wwwdir
  or make_path($wwwdir)
  or $logger->logdie("failed to create output directory '$wwwdir': $!");

##-- copy wrappers
$logger->info("copying wrappers from $docdir to $wwwdir");
{
  no warnings 'once';
  $File::Copy::Recursive::RmTrgFil = 2;
}
dircopy($docdir,$wwwdir)
  or $logger->logdie("failed to copy $docdir to $wwwdir: $!");

##-- copy configuration files
$logger->info("copying configuration file(s)");
foreach (sort keys %rcfiles) {
  !$rcfiles{$_}
    or copy($rcfiles{$_},"$wwwdir/$_")
    or $logger->logdie("failed to copy $rcfiles{$_} to $wwwdir/$_: $!");
}

##-- set permissions
$logger->info("setting permissions on $wwwdir");
chmod_recursive('u+w',$wwwdir)
  or $logger->logdie("failed to update permissions on $wwwdir: $!");

##-- link in 'data' directory
my $dbdir_abs = abs_path($dbdir);
$logger->info("linking $wwwdir/data to $dbdir_abs");
!-e "$wwwdir/data"
  or unlink("$wwwdir/data")
  or $logger->logdie("failed to unlink stale $wwwdir/data: $!");
symlink($dbdir_abs,"$wwwdir/data")
  or $logger->logdie("failed to create symlink $wwwdir/data -> $dbdir_abs: $!");

##-- create site.rc
if ($want_siterc) {
  $logger->info("creating $wwwdir/site.rc");
  $site{alias}  //= "/".basename($wwwdir);
  $site{wwwdir}   = abs_path($wwwdir)."/";
  my $dbcgi = DiaColloDB::WWW::CGI->new;
  my $data  = $dbcgi->ttk_process(dist_file("DiaColloDB-WWW", "rc/siterc.ttk"), {site=>\%site,prog=>$prog,version=>$DiaColloDB::WWW::VERSION});
  CORE::open(my $fh, ">:raw", "$wwwdir/site.rc")
    or $logger->logdie("$0: open failed for $wwwdir/site.rc: $!");
  $fh->print($data);
  CORE::close($fh);
  print STDERR "$prog: $_\n"
    foreach ("==================================================",
	     "created apache configuration file $wwwdir/site.rc",
	     "",
	     "remember to add $wwwdir/site.rc to your apache",
	     "site configuration and re-load the server config!",
	     "=================================================="
	    );
} else {
  $logger->info("NOT creating apache site configuration $wwwdir/site.rc (disabled by user request)");
}


__END__

###############################################################
## pods
###############################################################

=pod

=head1 NAME

dcdb-www-create.perl - instantiate apache www wrappers for a DiaColloDB index

=head1 SYNOPSIS

 dcdb-www-create.perl [OPTIONS] DBDIR

 General Options:
   -help                 # this help message
   -version              # display program version and exit

 Customization Options:
   -dstar-rc RCFILE      # instantiates WWWDIR/dstar.rc (default:none)
   -local-rc RCFILE      # instantiates WWWDIR/local.rc (default:none)
   -corpus-ttk TTKFILE   # instantiates WWWDIR/dstar/corpus.ttk (default:none)
   -custom-ttk TTKFILE   # instantiates WWWDIR/dstar/custom.ttk (default:none)
   -[no]site-rc          # do/don't create apache configuration in WWWDIR/site.rc (default:do)
   -site-alias ALIAS     # server path alias for WWWDIR/site.rc (default=/WWWDIR)

 Output Options:
   -[no]force            # do/don't force-overwrite existing WWWDIR (default=don't)
   -output WWWDIR        # create wrapper directory WWWDIR (default=DBDIR.www)

 Caveats:
   + you will need to update and reload your apache server configuration after
     adding or changing any site-wide aliases!

=cut

###############################################################
## OPTIONS
###############################################################
=pod

=head1 OPTIONS

=cut

###############################################################
# General Options
###############################################################
=pod

=head2 General Options

=over 4

=item -help

Display a brief help message and exit.

=item -version

Display version information and exit.

=item -verbose LEVEL

Set verbosity level to LEVEL.  Default=1.

=back

=cut


###############################################################
# Customization Options
###############################################################
=pod

=head2 Customization Options

=over 4

=item -dstar-rc RCFILE

Install a user-specified C<RCFILE> as F<WWWDIR/dstar.rc>
(perl format, base configuration).

=item -local-rc RCFILE

Install a user-specified C<RCFILE> as F<WWWDIR/local.rc>
(perl format, overrides).

=item -corpus-ttk TTKFILE

Install a user-specified C<TTKFILE> as F<WWWDIR/dstar/corpus.ttk>
(Template Toolkit format, base configuration).

=item -custom-ttk TTKFILE

Install a user-specified C<TTKFILE> as F<WWWDIR/dstar/custom.ttk>
(Template Toolkit format, overrides).

=item -site-rc , -nosite-rc

Do/don't create an apache site configuration stub in F<WWWDIR/site.rc>.
Default=do.

=item -site-alias ALIAS

Server path alias for F<WWWDIR/site.rc>,
Default=F</WWWDIR> (basename only).

=back

=cut

###############################################################
# I/O Options
###############################################################
=pod

=head2 I/O Options

=over 4

=item -[no]force

Do/don't force-overwrite an existing output directory (default=don't).

=item -output WWWDIR

Specify wrapper output directory F<WWWDIR>.
Default=F<DBDIR.www>.

=back

=cut


###############################################################
# Bugs and Limitations
###############################################################
=pod

=head1 BUGS AND LIMITATIONS

Probably many.

=cut


###############################################################
# Footer
###############################################################
=pod

=head1 ACKNOWLEDGEMENTS

Perl by Larry Wall.

=head1 AUTHOR

Bryan Jurish E<lt>moocow@cpan.orgE<gt>

=head1 SEE ALSO

perl(1).

=cut
