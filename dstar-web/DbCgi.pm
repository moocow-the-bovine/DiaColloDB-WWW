##-*- Mode: CPerl; coding: utf-8; -*-
package DbCgi;

use CGI qw(:standard :cgi-lib);
use URI;
use URI::Escape qw(uri_escape_utf8);
use HTTP::Status;
use Encode qw(); #qw(encode decode encode_utf8 decode_utf8);
use File::Basename qw(basename dirname);
use Cwd qw(getcwd abs_path);
use LWP::UserAgent;
use DBI qw(:sql_types);
use DBI::Const::GetInfoType;
use Template;
use JSON qw();
use Time::HiRes qw();
use utf8;
use Carp;
use strict;
our $VERSION = 0.17;

our $prog    = basename($0);
BEGIN {
  #binmode(STDIN, ':utf8');
  #binmode(STDOUT,':utf8');
  binmode(STDERR,':utf8');
}

*isa = \&UNIVERSAL::isa;
*can = \&UNIVERSAL::can;

##======================================================================
## globals

##======================================================================
## constructors etc.

## $cdb = $that->new(%args)
sub new {
  my $that = shift;
  my $cdb = bless({
		   ##-- db stuff
		   db_dsn  => undef,   ##-- REQUIRED
		   db_user => undef,   ##-- REQUIRED
		   db_pass => undef,   ##-- REQUIRED
		   db_opts => {},      ##-- additional options for DBI->connect()
		   tab_default => 'TAB_DEFAULT',  ##-- recommended
		   id_default => 'ID',            ##-- default column name returned by $cdb->primary_key()
		   dbh => undef,
		   ##
		   ##-- basic stuff
		   prog => basename($0),
		   ##
		   ##-- underlying CGI module
		   cgipkg => 'CGI',
		   ##
		   ##-- CGI params
		   defaults => {},
		   vars     => undef,
		   charset  => 'utf-8',
		   nodecode => {},  ##-- vars not to decode
		   ##
		   ##-- CGI environment stuff : see getenv() method
		   remote_addr => undef,
		   remote_user => undef,
		   request_method => undef,
		   request_uri => undef,
		   request_query => undef,
		   http_referer => undef,
		   http_host    => undef,
		   server_addr  => undef,
		   server_port  => undef,
		   ##
		   ##-- template toolkit stuff
		   ttk_package => (ref($that)||$that),
		   ttk_vars    => {},                   ##-- template vars
		   ttk_config  => {ENCODING=>'utf8'},	##-- options for Template->new()
		   ttk_process => {binmode=>':utf8'},	##-- options for Template->process()
		   ttk_dir     => abs_path(dirname($0)),
		   ttk_key     => undef, ##-- template basename
		   ##
		   ##-- debug
		   trace_sql   => 0,
		   ##
		   ##-- user args
		   @_,
		  }, ref($that)||$that);

  ##-- default dsn
  if (!$cdb->{db_dsn}) {
    $cdb->{db_dsn} = "dbi:SQLite:dbname=".dirname($prog).'/'.basename($prog);
    $cdb->{db_dsn} =~ s/\.[^\.]*$/\.sqlite/;
  }

  ##-- CGI package
  if ($cdb->{cgipkg}) {
    eval "use $cdb->{cgipkg} qw(:standard :cgi-lib);";
    confess(__PACKAGE__, "::new(): could not use cgipjg $cdb->{cgipkg}: $@") if ($@);
  }

  ##-- environment defaults
  $cdb->_getenv();

  return $cdb;
}

## @keys = $cdb->_param()
## $val  = $cdb->_param($name)
sub _param {
  my $cdb = shift;
  return $cdb->cgi('param',@_);
}

## $cdb = $cdb->_reset()
##  + resets CGI environment
sub _reset {
  my $cdb = shift;
  delete @$cdb{(qw(vars),
		qw(remote_addr remote_user),
		qw(request_method request_uri request_query),
		qw(http_referer http_host server_addr server_port),
	       )};
  return $cdb;
}

## $cdb = $cdb->_getenv()
sub _getenv {
  my $cdb = shift;
  $cdb->{remote_addr} = ($ENV{REMOTE_ADDR}||'0.0.0.0');
  $cdb->{remote_user} = ($ENV{REMOTE_USER} || getpwuid($>));
  $cdb->{request_method} = ($ENV{REQUEST_METHOD}||'GET');
  $cdb->{request_uri} = ($ENV{REQUEST_URI} || $0);
  $cdb->{request_query} = $ENV{QUERY_STRING};
  $cdb->{http_referer} = $ENV{HTTP_REFERER};
  $cdb->{http_host} = $ENV{HTTP_HOST};
  $cdb->{server_addr} = $ENV{SERVER_ADDR};
  $cdb->{server_port} = $ENV{SERVER_PORT};
  return $cdb;
}


## \%vars = $cdb->vars()
##   + gets CGI variables, instantiating $cdb->{defaults} if present
sub vars {
  my $cdb = shift;
  return $cdb->{vars} if (defined($cdb->{vars}));
  my $vars = $cdb->cgi('param') ? { %{$cdb->cgi('Vars')} } : {};

  if (($cdb->{cgipkg}//'CGI') ne 'CGI' || defined($vars->{POSTDATA})) {
    ##-- parse params from query string; required e.g. for CGI::Fast or non-form POST requests (which set POSTDATA)
    my $uri  = URI->new($cdb->{request_uri});
    my %urif = $uri->query_form();
    @$vars{keys %urif} = values %urif;
  }

  foreach (grep {!exists($vars->{$_}) && defined($cdb->{defaults}{$_})} keys %{$cdb->{defaults}||{}}) {
    ##-- defaults
    $vars->{$_} = $cdb->{defaults}{$_}
  }
  my ($tmp);
  foreach (keys %$vars) {
    ##-- decode (annoying temporary variable hack hopefully ensures that utf8 flag is set!)
    $tmp = $vars->{$_};
    $tmp =~ s/\x{0}/ /g;
    if ($cdb->{charset} && !utf8::is_utf8($tmp) && !exists($cdb->{nodecode}{$_})) {
      $tmp = Encode::decode($cdb->{charset},$tmp);
      #$cdb->trace("decode var '$_':\n+ OLD=$vars->{$_}\n+ NEW=$tmp\n");
      $vars->{$_} = $tmp;
    }
  }
  return $cdb->{vars} = $vars;
}

##======================================================================
## config loading

## $cdb = $cdb->load_config($filename)
##  + clobers %$cdb keys from JSON filename
sub load_config {
  my ($cdb,$file) = @_;
  open(RC,"<:raw",$file)
    or confess("load_config(): failed for '$file': $!");
  local $/ = undef;
  my $buf = <RC>;
  close RC
    or confess("load_config(): close failed for '$file': $!");
  my $data = JSON::from_json($buf,{utf8=>1,relaxed=>1})
    or confess("load_config(): from_json() failed for config data from '$file': $!");
  @$cdb{keys %$data} = values %$data;
  return $cdb;
}

##======================================================================
## DB Stuff: Basic

## undef = $cdb->trace(@msg)
sub trace {
  return if (!$_[0] || (ref($_[0]) && !$_[0]{trace_sql}));
  print STDERR $prog, ": ", ((ref($_[0])||$_[0]), ": ", @_[1..$#_]);
}

sub trace1 { return trace(@_,"\n"); }

## $dbh = $cdb->dbh()
##  + returns database handle; implicitly calls $cdb->dbconnect() if not already connected
sub dbh {
  my $cdb = shift;
  return $cdb->{dbh} if (defined($cdb->{dbh}));
  return $cdb->dbconnect();
}

## $dbh = $cdb->dbconnect()
##  + (re-)connect to database; sets $cdb->{dbh}
sub dbconnect {
  my $cdb = shift;
  #print STDERR __PACKAGE__, "::dbconnect(): dsn=$cdb->{db_dsn}; CWD=", getcwd(), "\n";
  my $dbh = $cdb->{dbh} = DBI->connect(@$cdb{qw(db_dsn db_user db_pass)}, {AutoCommit=>1,RaiseError=>1, %{$cdb->{db_opts}||{}}})
    or die (ref($cdb)."::dbconnect(): could not connect to $cdb->{db_dsn}: $!");
  return $dbh;
}

## undef = $cdb->dbdisconnect
##  + disconnect from database and deletes $cdb->{dbh}
sub dbdisconnect {
  my $cdb = shift;
  $cdb->{dbh}->disconnect if (UNIVERSAL::can($cdb->{dbh},'disconnect'));
  delete $cdb->{dbh};
}

## $sth = $cdb->prepare($sqlstr)
##  + prepares sql
sub prepare {
  my ($cdb,$sql) = @_;
  $cdb->trace("prepare(): $sql\n");
  my $sth = $cdb->dbh->prepare($sql)
    or confess(__PACKAGE__, "::prepare() failed for {$sql}: ", $cdb->dbh->errstr);
  $sth->{Callbacks}{execute} = sub {
    $cdb->trace1("execute(): query={$sql} ; params=".(@_>1 ? ('['.join(',',map {$cdb->escapeSQL($_)} @_[1..$#_]).']') : '[]'));
    return; ##-- callback must return nothing
  } if ($cdb->{trace_sql});
  return $sth;
}

## $sth = $cdb->execsql($sqlstr)
## $sth = $cdb->execsql($sqlstr,\@params)
##  + executes sql with optional bind-paramaters \@params
*execSQL = \&execsql;
sub execsql {
  my ($cdb,$sql,$params) = @_;
  $cdb->trace("execsql(): $sql\n");

  my $sth = $cdb->dbh->prepare($sql)
    or confess(__PACKAGE__, "::execsql(): prepare() failed for {$sql}: ", $cdb->dbh->errstr);
  my $rv  = $sth->execute($params ? @$params : qw())
    or confess(__PACKAGE__, "::execsql(): execute() failed for {$sql}: ", $sth->errstr);
  return $sth;
}

## \%info = $cdb->db_info()
##  $info = $cdb->db_info($info_type_str)
##   + get db info (wrapper for $dbh->get_info())
sub db_info {
  my $cdb = shift;
  if (!@_) {
    my $dbh = $cdb->dbh;
    return {map {($_=>$dbh->get_info($GetInfoType{$_}))} keys %GetInfoType};
  }
  return $cdb->dbh->get_info($GetInfoType{$_[0]});
}

## @tables = $cdb->tables()
## @tables = $cdb->tables($schema)
##  + return an array of array-refs ([SCHEMA,TABLE],...) for all tables in database (1st form)
##    or an array of table names (TABLE,...) in SCHEMA (second form)
sub tables {
  my ($cdb,$schema) = @_;
  my $dbh   = $cdb->dbh;
  my $qchar = $dbh->get_info($GetInfoType{SQL_IDENTIFIER_QUOTE_CHAR});
  my @tables = (
		map {[split(/\./,$_,2)]}    ##-- ['SCHEMA','TABLE']
		map {s/\Q${qchar}\E//g; $_} ##-- ('SCHEMA.TABLE')
		$cdb->dbh->tables(),        ##-- ('"SCHEMA"."TABLE"', ...)
	       );
  return @tables if (!$schema);
  return map {$_->[1]} grep {$_->[0] eq $schema} @tables;
}

## @keys = $cdb->primary_keys(                   $table)
## @keys = $cdb->primary_keys(          $schema, $table)
## @keys = $cdb->primary_keys($catalog, $schema, $table)
##  + get primary key(s) for $table as stored in db
sub primary_keys {
  my $cdb = shift;
  return $cdb->dbh->primary_key(@_[0..2])          if (@_ >= 3);
  return $cdb->dbh->primary_key(undef,@_[0,1])     if (@_ >= 2);
  confess(__PACKAGE__, "::primary_key(): no table specified!") if (!$_[0]);
  return ($cdb->dbh->primary_key(undef,undef,$_[0]));
}

## $key = $cdb->primary_key(                   $table)
## $key = $cdb->primary_key(          $schema, $table)
## $key = $cdb->primary_key($catalog, $schema, $table)
##  + get __first__ primary key for $table, or $cdb->{id_default} if not defined
sub primary_key {
  my $cdb = shift;
  my $key = ($cdb->primary_keys(@_))[0];
  return defined($key) ? $key : $cdb->{id_default};
}

## \%name2info = $cdb->table_info(                           $type)
## \%name2info = $cdb->table_info(                   $table, $type)
## \%name2info = $cdb->table_info(          $schema, $table, $type)
## \%name2info = $cdb->table_info($catalog, $schema, $table, $type)
##  + get table information for table(s) as hashref over TABLE_NAME
sub table_info {
  my $cdb = shift;
  my ($sth);
  if    (@_ >= 4) { $sth=$cdb->dbh->table_info(@_[0..3]); }
  elsif (@_ >= 3) { $sth=$cdb->dbh->table_info(undef,@_[0..2]); }
  elsif (@_ >= 2) { $sth=$cdb->dbh->table_info(undef,undef,@_[0..1]); }
  elsif (@_ >= 1) { $sth=$cdb->dbh->table_info(undef,undef,undef,$_[0]); }
  else {
    #confess(__PACKAGE__, "::column_info(): no table specified!") if (!$_[0]);
    $sth=$cdb->dbh->table_info(undef,undef,undef,undef);
  }
  die(__PACKAGE__, "::table_info(): DBI returned NULL statement handle") if (!$sth);
  return $sth->fetchall_hashref('TABLE_NAME');
}

## \%name2info = $cdb->column_info(                   $table)
## \%name2info = $cdb->column_info(          $schema, $table)
## \%name2info = $cdb->column_info($catalog, $schema, $table)
##  + get column information for table as hashref over COLUMN_NAME; see DBI::column_info()
sub column_info {
  my $cdb = shift;
  my ($sth);
  if    (@_ >= 3) { $sth=$cdb->dbh->column_info(@_[0..2],undef); }
  elsif (@_ >= 2) { $sth=$cdb->dbh->column_info(undef,@_[0,1],undef); }
  else {
    confess(__PACKAGE__, "::column_info(): no table specified!") if (!$_[0]);
    return {} if ($_[0] =~ /[\s\(\),]/); ##-- probably an embedded query
    $sth=$cdb->dbh->column_info(undef,undef,$_[0],undef);
  }
  die(__PACKAGE__, "::column_info(): DBI returned NULL statement handle") if (!$sth);
  return $sth->fetchall_hashref('COLUMN_NAME');
}

## @colnames = $cdb->columns(                   $table)
## @colnames = $cdb->columns(          $schema, $table)
## @colnames = $cdb->columns($catalog, $schema, $table)
##  + get column names for $catalog.$schema.$table in db-storage order
sub columns {
  my $cdb  = shift;
  return map {$_->{COLUMN_NAME}} sort {$a->{ORDINAL_POSITION}<=>$b->{ORDINAL_POSITION}} values %{$cdb->column_info(@_)};
}

## \%TABLE_INFO = $cdb->TABLE_INFO()
##  + override table info
sub TABLE_INFO { return (ref($_[0]) ? $_[0]{TABLE_INFO} : undef)||{}; }

## \%COLUMN_INFO = $cdb->COLUMN_INFO()
##  + override table info
sub COLUMN_INFO { return (ref($_[0]) ? $_[0]{COLUMN_INFO} : undef)||{}; }


##======================================================================
## DB Stuff: column parsing

## \%colspecs = $cdb->colspecs($table,@colnames)
## \%colspecs = $cdb->colspecs($table)
##  + returns hash-ref \%colspecs = { $colName=>\%colSpec, ... } and \%colSpec =
##    {
##     type0=>$type0,	##-- sql declaration, like $cdb->column_info($table)->{$colName}{TYPE_NAME}
##     type=>$type,	##-- data type: qw(bool int float blob enum text), default='text'
##     keyvals=>\@keyvals, ##-- [$key,$value] pairs for 'enum' types
##     cmt=>$cmt,	##-- column comment
##     ro=>$bool,	##-- read-only?
##     id=>$bool	##-- id-column?
##     ref=>$tabname,   ##-- ref target?
###   }
sub colspecs {
  my ($cdb,$table,@colnames) = @_;
  my $TINFO = $cdb->TABLE_INFO();
  my $CINFO = $cdb->COLUMN_INFO();
  @colnames = $cdb->columns($table) if (!@colnames);
  my $cinfo = $cdb->column_info($table);
  my $idcol = $cdb->primary_key($table);
  my $specs = {};
  my ($cname,$c,$ctype0,$ctype,@keyvals);
  my $tsql = $cdb->table_info($table,undef)->{$table}{sqlite_sql};
  foreach $cname (@colnames) {
    $ctype0 = $cinfo->{$cname}{TYPE_NAME};
    $c      = $specs->{$cname} = {type0=>$ctype0};

    ##-- decode
    $cname  = Encode::decode_utf8($cname) if (!utf8::is_utf8($cname));
    $ctype0 = Encode::decode_utf8($ctype0) if (!utf8::is_utf8($ctype0));

    ##-- check for datatype
    if    ($ctype0 =~ /(?:bool|tinyint)/i)					 { $ctype = 'bool'; }
    elsif ($ctype0 =~ /int/i) 							 { $ctype = 'int'; }
    elsif ($ctype0 =~ /(?:text|char|string)/i) 					 { $ctype = 'text'; }
    elsif ($ctype0 =~ /(?:blob|clob|bin)/i) 					 { $ctype = 'blob'; }
    elsif ($ctype0 =~ /(?:float|numeric)/i) 					 { $ctype = 'float'; }
    else 									 { $ctype = 'text'; }

    ##-- check for enums
    if ($ctype0 =~ /\benum[\(\{\[]([^\)\}\]]+)[\)\}\]]/i) {
      @keyvals = map {[split(/[=:]+/,$_,2)]} split(/[\;\,\s]+/,$1);
      $_->[1] = $_->[0] foreach (grep {!defined($_->[1])} @keyvals);
      $c->{keyvals} = [@keyvals];
      $ctype = 'enum';
    }
    $c->{type} = $ctype;

    ##-- check for readonly
    $c->{id}=1 if ($cname eq $idcol);
    $c->{ro}=1 if ($cname eq $idcol || $ctype0 =~ /\b(?:readonly|ro|autoincrement|auto)\b/i);

    ##-- check for refs
    $c->{ref}=$1 if ($ctype0 =~ /\bref\(([^\)]*)\)/i);

    ##-- get comments
    if    ($ctype0 =~ /\bcomment\s*\'((?:[^\']|\'\')*)\'/) { $c->{cmt}=$1; }
    elsif ($ctype0 =~ m{/\*(.*?)\*/}) { $c->{cmt}=$1; }
    elsif ($tsql =~ m{^\s*\Q$cname\E\b.*/\*\-*\s*(.*?)\s*\-*\*/}m) { $c->{cmt} = $1; }

    ##-- respect local overrides
    @$c{keys %{$CINFO->{$cname}}} = values %{$CINFO->{$cname}} if ($CINFO->{$cname});
    @$c{keys %{$CINFO->{"$table.$cname"}}} = values %{$CINFO->{"$table.$cname"}} if ($table && $CINFO->{"$table.$cname"});

    $c->{cdoc} = $c->{cmt} if (!$c->{cdoc});
    if (!$c->{cdoc} && $c->{id}) {
      $c->{cdoc} = 'primary key';
    }
    elsif (!$c->{'ref'} && $c->{cdoc} && $c->{cdoc} =~ m{\bref\(([^\)]*)\)}) {
      $c->{'ref'} = $1;
      $c->{'ro'}  = $1;
    }
    elsif (!$c->{'ref'} && !$c->{cdoc} && exists($TINFO->{$cname})) {
      $c->{'ref'} = $cname;
      $c->{ro}    = 1;
      $c->{cdoc}  = $c->{cmt} = "ref($cname)";
    }
  }
  return $specs;
}

## \%dbinfo = $cdb->dbinfo()
##  + high-level sub
##  + gets database info %dbinfo = (tables=>{$tabName=>\%tabInfo,...}, columns=>{$colName=>\%colInfo,...})
##  + adds %tabInfo keys qw(tdoc cols colnames)
sub dbinfo {
  my $cdb = shift;
  my $TINFO = $cdb->TABLE_INFO();
  my $tinfo = $cdb->table_info();
  my $cinfo = {};
  my ($tname,$t, $cname,$c);
  delete @$tinfo{grep {$_ =~ /^sqlite_/ } keys %$tinfo};
  while (($tname,$t)=each(%$tinfo)) {
    delete @$t{grep {$_ ne 'TABLE_TYPE'} keys %$t};
    @$t{keys %{$TINFO->{$tname}}} = values %{$TINFO->{$tname}} if ($TINFO->{$tname});
    $t->{cols}     = $cdb->colspecs($tname);
    $t->{colnames} = [$cdb->columns($tname)];
    $t->{tdoc}     = lc($t->{TABLE_TYPE}).": $tname" if (!$t->{tdoc});

    while (($cname,$c)=each(%{$t->{cols}})) {
      $cinfo->{$cname}=$c if (!$cinfo->{$cname});
    }
  }
  return {tables=>$tinfo,columns=>$cinfo};
}

##======================================================================
## DB Stuff: Data Retrieval

## $row_arrayref = $cdb->fetch1row_arrayref($sql)
## $row_arrayref = $cdb->fetch1row_arrayref($sql,\@params)
##  + get a single row from the database as an ARRAY-ref
*fetch1row = \&fetch1row_arrayref;
sub fetch1row_arrayref {
  my $cdb = shift;
  my $sth = $cdb->execsql(@_);
  return $sth->fetchrow_arrayref();
}

## @row_array = $cdb->fetch1row_array($sql)
## @row_array = $cdb->fetch1row_array($sql,\@params)
##  + get a single row from the database as an array
sub fetch1row_array {
  my $cdb = shift;
  my $row = $cdb->fetch1row_arrayref(@_);
  return defined($row) ? @$row : qw();
}

## $row_hashref = $cdb->fetch1row_hashref($sql,\@params)
##  + get a single row from the database as a hash-ref
sub fetch1row_hashref {
  my $cdb = shift;
  my $sth = $cdb->execsql(@_);
  return $sth->fetchrow_hashref();
}

## \%data = $cdb->getall(%select_sql_args, hashrows=>$bool)
## \%data = $cdb->getall(\%select_sql_args_or_hashrows)
##  + returns db-data for $cdb->select_sql(%select_sql_args) as $data =
##    {
##     args  => \%args,        ##-- options passed
##     sql   => $sql,          ##-- generated sql
##     names => \@colnames,    ##-- array of column names
##     rows  => \@rows,        ##-- array of rows (ARRAY-refs)
##     hrows => \@rows,        ##-- array of rows (HASH-refs); only if 'hashrows' option is specified and true
##     nrows => $nrows,        ##-- number of rows as returned by $sth->rows()
##    }
##  + if 'hashrows' is specified and true
sub getall {
  my $cdb  = shift;
  my $args = @_==1 && isa($_[0],'HASH') ? $_[0] : {@_};
  my $sql = $cdb->select_sql($args);
  my $sth = $cdb->execsql($sql);
  my $data  = {
	       args => $args,
	       sql => $sql,
	       names => $sth->{NAME},
	       nrows => $sth->rows,
	       rows  => [],
	      };
  my ($row);
  while (defined($row=$sth->fetchrow_arrayref)) {
    push(@{$data->{rows}},[map {defined($_) && !utf8::is_utf8($_) ? Encode::decode_utf8($_) : $_} @$row]);
  }
  $sth->finish;
  $data->{hrows} = $cdb->hashrows(@$data{qw(names rows)}) if ($args->{hashrows} || !exists($args->{hashrows}));
  return $data;
}

## \%data = $cdb->get1row(%select_sql_args, hashrows=>$bool)
## \%data = $cdb->get1row(\%select_sql_args_or_hashrows)
##  + just like $cdb->getall(...), but die()s if not exactly 1 row is returned
sub get1row {
  my $cdb = shift;
  my $args = @_==1 && isa($_[0],'HASH') ? $_[0] : {@_};
  $args->{limit} = 2;
  my $data = $cdb->getall($args);
  die(__PACKAGE__ . "::get1row(): no rows returned for {$args->{sql}}")
    if (!$data || !@{$data->{rows}});
  die(__PACKAGE__ . "::get1row(): multiple rows returned for {$args->{sql}}")
    if (@{$data->{rows}} > 1);
  return $data;
}

## \@hashrows = $cdb->hashrows(\@array_row_colnames,\@array_rows)
##  + returns ARRAY-ref of HASH-refs for each row of @array_rows rows, keyed by \@array_row_colnames
sub hashrows {
  my ($cdb,$anames,$arows) = @_;
  my $hrows = [];
  my ($arow);
  foreach $arow (@$arows) {
    push(@$hrows,{map {($anames->[$_]=>$arow->[$_])} (0..$#$anames)});
  }
  return $hrows;
}

##======================================================================
## DB Stuff: SQL Generation

## $limit_str = $cdb->limit_sql($offset_or_undef, $limit_or_undef)
##  + returns an "OFFSET x LIMIT y" for the given arguments
##  + may be overridden db-specifically for child classes
sub limit_sql {
  my ($cdb,$off,$lim) = @_;
  no warnings 'uninitialized';
  return '' if (!$off && $lim eq '');
  return ' LIMIT '.($off||'0').",$lim";
}

## $id_sql = $cdb->id_sql($table,$idval)
##  + returns a WHERE clause for PRIMARY_KEY($table) = $idval
sub id_sql {
  my ($cdb,$tab,$val) = @_;
  return $cdb->primary_key($tab)."=".$val;
}

## $sql = $cdb->select_sql(\%opts)
## $sql = $cdb->select_sql( %opts)
##  + returns SQL string for querying database
##  + %opts:
##      sql     => $raw_sql_str, ##-- override
##      select  => \@cols,       ##-- ... or raw sql string (NOT parsed)
##      from    => \@tables,     ##-- ... or raw sql string (parsed)
##      where   => \@conds,      ##-- AND-joined list, or raw sql string (NOT parsed)
##      $col    => $string,      ##-- ... other column-name keys are used for 'where' clause if not already present
##      ".$col" => $expr,        ##-- ... other dot-column keys are used for 'where' clause
##      oderby  => $spec,
##      groupby => $spec,
##      offset  => $offset,
##      limit   => $limit,
sub select_sql {
  my $cdb  = shift;
  my $opts = @_==1 && isa($_[0],'HASH') ? shift : {@_};
  return $opts->{sql} if ($opts->{sql});

  ##-- select
  $opts->{select} = '*' if (!$opts->{select});
  $opts->{select} = [$opts->{select}] if (!isa($opts->{select},'ARRAY'));

  ##-- from
  $opts->{from}   = $cdb->{tab_default} if (!$opts->{from});
  $opts->{from}   = [split(/[\,]+/,$opts->{from})] if (!isa($opts->{from},'ARRAY'));

  ##-- where: basic
  $opts->{where}=[$opts->{where}||qw()] if (!isa($opts->{where},'ARRAY'));
  if (defined($opts->{id})) {
    push(@{$opts->{where}}, $cdb->id_sql($opts->{from}[0],$opts->{id}));
    #delete($opts->{id});
  }
  ##
  ##-- where: adopt CGI parameters
  my $colh = { map {%{$cdb->column_info($_)}} @{$opts->{from}} };
  my %where = qw();
  foreach (keys %$colh) {
    $where{$_}    = $opts->{$_}    if (!exists($where{$_})    && exists($opts->{$_}));
    $where{".$_"} = $opts->{".$_"} if (!exists($where{".$_"}) && exists($opts->{".$_"}));
  }
  ##
  ##-- where: auto-escape, converting ".$col" parameters if not otherwise present
  foreach (keys %$colh) {
    $where{$_} = $cdb->escapeSQL($where{$_}) if ( exists($where{$_}));
    $where{$_} = $where{".$_"}               if (!exists($where{$_}) && exists($where{".$_"}));
    delete($where{".$_"});
  }
  ##
  ##-- where: append
  push(@{$opts->{where}}, map {"$_=$where{$_}"} keys %where);

  my $sql = ("SELECT ".join(',', @{$opts->{select}})
	     ." FROM ".join(',', @{$opts->{from}})
	     .(@{$opts->{where}}
	       ? (" WHERE ".(isa($opts->{where},'ARRAY') ? join(' AND ', map {"($_)"} @{$opts->{where}}) : $opts->{where}))
	       : ''));
  $sql .= " GROUP BY $opts->{groupby}" if ($opts->{groupby} && $sql !~ /\bgroup\s+by\b/is);
  $sql .= " ORDER BY $opts->{orderby}" if ($opts->{orderby} && $sql !~ /\border\s+by\b/is);
  if ($opts->{limit} && $sql !~ /\blimit\s+\d+\s*,\s*\d+/is) {
    $sql .= $opts->{limit} =~ /(\d*)\,(\d*)/ ? $cdb->limit_sql($1,$2) : $cdb->limit_sql(@$opts{qw(offset limit)});
  }
  return $opts->{sql}=$sql;
}

## $sql = $cdb->insert_sql(\%opts)
## $sql = $cdb->insert_sql( %opts)
##  + returns SQL string for inserting values into database
##  + %opts:
##      sql     => $raw_sql_str, ##-- override
##      into    => $table,       ##-- ... or raw sql string (single table only)
##      set     => \%col2val,    ##-- set these columns (values are auto-escaped unless $col begins with '.') [alias:'values']
##      $col    => $string,      ##-- ... other column-name keys are used for 'set' clause if not already present
##      ".$col" => $expr,        ##-- ... other dot-column keys are used for 'set' clause
sub insert_sql {
  my $cdb  = shift;
  my $opts = @_==1 && isa($_[0],'HASH') ? shift : {@_};
  return $opts->{sql} if ($opts->{sql});

  ##-- table
  my $table = $opts->{into}||$cdb->{tab_default};
  my $colh = $cdb->column_info($table);
  confess(__PACKAGE__, "::insert_sql(): cannot insert into non-existent table '$table'") if (!$colh || !%$colh);

  ##-- set: adopt CGI parameters
  $opts->{set} = $opts->{values} if (!$opts->{set});
  $opts->{set} = {split(/\s*=\s*/,($opts->{set}||''),2)} if (!isa($opts->{set},'HASH'));
  foreach (keys %$colh) {
    $opts->{set}{$_}    = $opts->{$_}    if (!exists($opts->{set}{$_})    && exists($opts->{$_}));
    $opts->{set}{".$_"} = $opts->{".$_"} if (!exists($opts->{set}{".$_"}) && exists($opts->{".$_"}));
  }

  ##-- set: auto-escape, converting ".$col" parameters if not otherwise present
  foreach (keys %$colh) {
    $opts->{set}{$_} = $cdb->escapeSQL($opts->{set}{$_}) if ( exists($opts->{set}{$_}));
    $opts->{set}{$_} = $opts->{set}{".$_"}               if (!exists($opts->{set}{$_}) && exists($opts->{set}{".$_"}));
    delete($opts->{set}{".$_"});
  }

  my $sql = ("INSERT INTO $table"
	     ."(".join(',', keys %{$opts->{set}}).")"
	     ." VALUES (".join(',', values %{$opts->{set}}).")"
	    );
  return $opts->{sql}=$sql;
}

## $sql = $cdb->update_sql(\%opts)
## $sql = $cdb->update_sql( %opts)
##  + returns SQL string for updating values in database
##  + %opts:
##      sql     => $raw_sql_str, ##-- override
##      update  => $table,       ##-- single table only [alias: 'table']
##      set     => \%col2val,    ##-- set these columns (values are auto-escaped unless $col begins with '.') [alias: 'values']
##      $col    => $string,      ##-- ... other column-name keys are used for 'set' clause if not already present
##      ".$col" => $expr,        ##-- ... other dot-column keys are used for 'set' clause; clobbers ($col=>$str)
##      where   => \@conds,      ##-- AND-joined
##      id      => $idval,       ##-- ... like "WHERE id=$idval"
sub update_sql {
  my $cdb  = shift;
  my $opts = @_==1 && isa($_[0],'HASH') ? shift : {@_};
  return $opts->{sql} if ($opts->{sql});

  ##-- table
  my $table = $opts->{update}||$opts->{table}||$cdb->{tab_default};
  my $colh = $cdb->column_info($table);
  confess(__PACKAGE__, "::update_sql(): cannot update non-existent table '$table'") if (!$colh || !%$colh);

  ##-- where
  $opts->{where}=[$opts->{where}||qw()] if (!isa($opts->{where},'ARRAY'));
  push(@{$opts->{where}}, $cdb->id_sql($table,$opts->{id})) if (defined($opts->{id}));
  ##
  ##-- set: adopt CGI parameters
  $opts->{set} = $opts->{values} if (!$opts->{set});
  $opts->{set} = {split(/\s*=\s*/,($opts->{set}||''),2)} if (!isa($opts->{set},'HASH'));
  foreach (keys %$colh) {
    $opts->{set}{$_}    = $opts->{$_}    if (!exists($opts->{set}{$_})    && exists($opts->{$_}));
    $opts->{set}{".$_"} = $opts->{".$_"} if (!exists($opts->{set}{".$_"}) && exists($opts->{".$_"}));
  }
  ##
  ##-- set: auto-escape, converting ".$col" parameters present
  foreach (keys %$colh) {
    $opts->{set}{$_} = $cdb->escapeSQL($opts->{set}{$_}) if (exists($opts->{set}{$_}));
    $opts->{set}{$_} = $opts->{set}{".$_"}               if (exists($opts->{set}{".$_"}));
    #delete($opts->{set}{".$_"});
  }
  ##
  ##-- where: sanity check
  confess(__PACKAGE__."::update_sql(): cowardly refusing to update whole table '$table'")
    if (!@{$opts->{where}});
  ##
  ##-- set: sanity check(s)
  delete($opts->{set}{$cdb->primary_key($table)});
  return '' if (!%{$opts->{set}});

  ##-- generate sql string
  my $sql = ("UPDATE $table"
	     ." SET ".join(', ', map {"$_=$opts->{set}{$_}"} grep {$_ !~ /^\./} keys %{$opts->{set}})
	     .(@{$opts->{where}}
	       ? (" WHERE ".join(' AND ', map {"($_)"} @{$opts->{where}}))
	       : '')
	    );
  return $opts->{sql}=$sql;
}

## $sql = $cdb->delete_sql(\%opts)
## $sql = $cdb->delete_sql( %opts)
##  + returns SQL string for deleting values from the database
##  + %opts:
##      sql     => $raw_sql_str, ##-- override
##      from    => \@tables,     ##-- ... or raw sql string (parsed) [alias: 'from']
##      where   => \@conds,      ##-- AND-joined
##      $col    => $string,      ##-- ... other column-name keys are used for 'where' clause if not already present
##      ".$col" => $expr,        ##-- ... other dot-column keys are used for 'where' clause
sub delete_sql {
  my $cdb  = shift;
  my $opts = @_==1 && isa($_[0],'HASH') ? shift : {@_};
  return $opts->{sql} if ($opts->{sql});

  ##-- table
  my $table = $opts->{from}||$cdb->{tab_default};
  my $colh = $cdb->column_info($table);
  confess(__PACKAGE__, "::delete_sql(): cannot delete from non-existent table '$table'") if (!$colh || !%$colh);

  ##-- where: basic
  $opts->{where}=[$opts->{where}||qw()] if (!isa($opts->{where},'ARRAY'));
  if (defined($opts->{id})) {
    push(@{$opts->{where}}, $cdb->id_sql($table,$opts->{id}));
    #delete($opts->{id});
  }
  ##
  ##-- where: adopt CGI parameters
  my %where = qw();
  foreach (keys %$colh) {
    $where{$_}    = $opts->{$_}    if (!exists($where{$_})    && exists($opts->{$_}));
    $where{".$_"} = $opts->{".$_"} if (!exists($where{".$_"}) && exists($opts->{".$_"}));
  }
  ##
  ##-- where: auto-escape, converting ".$col" parameters if not otherwise present
  foreach (keys %$colh) {
    $where{$_} = $cdb->escapeSQL($where{$_}) if ( exists($where{$_}));
    $where{$_} = $where{".$_"}               if (!exists($where{$_}) && exists($where{".$_"}));
    delete($where{".$_"});
  }
  ##
  ##-- where: append
  push(@{$opts->{where}}, map {"$_=$where{$_}"} keys %where);
  ##
  ##-- where: sanity check
  confess(__PACKAGE__."::delete_sql(): cowardly refusing to truncate whole table '$table'")
    if (!@{$opts->{where}});

  my $sql = ("DELETE FROM $table"
	     .(@{$opts->{where}}
	       ? (" WHERE ".join(' AND ', map {"($_)"} @{$opts->{where}}))
	       : '')
	    );
  return $opts->{sql}=$sql;
}

## $sqlstr = $cdb->escapeSQL($str)
## $sqlstr = $cdb->escapeSQL($str,$sql_type)
##  + returns SQL-escaped version of $str
sub escapeSQL {
  my ($cdb,$str,$type) = @_;
  return $cdb->dbh->quote($str,$type);
}

##======================================================================
## common sql wrappers

## $sth = $cdb->dbInsert(\%insert_sql_args,\@params)
sub dbInsert {
  my ($cdb,$opts,$params) = @_;
  my $sql = $cdb->insert_sql($opts);
  return $cdb->execsql($sql,$params);
}

## $sth = $cdb->dbUpdate(\%update_sql_args,\@params)
sub dbUpdate {
  my ($cdb,$opts,$params) = @_;
  my $sql = $cdb->update_sql($opts);
  return $cdb->execsql($sql,$params);
}

## $sth = $cdb->dbDelete(\%delete_sql_args,\@params)
sub dbDelete {
  my ($cdb,$opts,$params) = @_;
  my $sql = $cdb->delete_sql($opts);
  return $cdb->execsql($sql,$params);
}

## $sth = $cdb->dbSelect(\%select_sql_args,\@params)
sub dbSelect {
  my ($cdb,$opts,$params) = @_;
  my $sql = $cdb->select_sql($opts);
  return $cdb->execsql($sql,$params);
}



##======================================================================
## Template Toolkit stuff

## $key = $cdb->ttk_key($key)
## $key = $cdb->ttk_key()
##  + returns current template key
##  + default is basename($cdb->{prog}) without final extension
sub ttk_key {
  my ($cdb,$key) = @_;
  ($key=basename($cdb->{prog})) =~ s/\.[^\.]*\z// if (!$key);
  return $key;
}

## $file = $cdb->ttk_file()
## $file = $cdb->ttk_file($key)
##  + returns template filename for template key (basename) $key
##  + $key defaults to $cdb->{prog} without final extension
sub ttk_file {
  my ($cdb,$key) = @_;
  (my $dir = $cdb->{ttk_dir} || '.') =~ s/\/+\z//;
  return abs_path($dir)."/".$cdb->ttk_key($key).".ttk";
}

## $t = $cdb->ttk_template(\%templateConfigArgs)
##  + returns a new Template object with default args set
sub ttk_template {
  my ($cdb,$targs) = @_;
  my $t = Template->new(
			INTERPOLATE=>1,
			PRE_CHOMP=>0,
			POST_CHOMP=>1,
			EVAL_PERL=>1,
			ABSOLUTE=>1,
			RELATIVE=>1,
			%{$cdb->{ttk_config}||{}},
			%{$targs||{}},
		       );
  return $t;
}

## $data = $cdb->ttk_process($srcFile, \%templateVars, \%templateConfigArgs)
##  + process a template $srcFile, returns generated $data
sub ttk_process {
  my ($cdb,$src,$tvars,$targs) = @_;
  my $out = '';
  my $t = $cdb->ttk_template($targs);
  $t->process($src,
	      {package=>$cdb->{ttk_package}, version=>$VERSION, ENV=>{%ENV}, %{$cdb->{ttk_vars}||{}}, cdb=>$cdb, %{$tvars||{}}},
	      \$out,
	      ($cdb->{ttk_process}||{}),
	     )
    or confess(__PACKAGE__, "::ttk_process(): template error: ".$t->error);
  return $out;
}

##======================================================================
## CGI stuff: generic

## @error = $cdb->htmlerror($status,@message)
##  + returns a print()-able HTML error
sub htmlerror {
  my ($cdb,$status,@msg) = @_;
  $status = 500 if (!defined($status)); ##-- RC_INTERNAL_SERVER_ERROR
  my $title = 'Error: '.$status.' '.status_message($status);
  charset($cdb->{charset});
  my $msg = join((defined($,) ? $, : ''), @msg);
  $msg =~ s/\beval\s*\'(?:\\.|[^\'])*\'/eval '...'/sg; ##-- suppress long eval '...' messsages
  return
    (header(-status=>$status),
     start_html($title),
     h1($title),
     pre("\n",escapeHTML($msg),"\n"),
     end_html,
    );
}

## @whatever = $cdb->cgi($method, @args)
##  + call a method from the CGI package $cdb->{cgipkg}->can($method)
sub cgi {
  my ($cdb,$method)=splice(@_,0,2);
  CGI::charset($cdb->{charset}) if ($cdb->{charset});
  my ($sub);
  if (ref($method)) {
    return $method->(@_);
  }
  elsif ($sub=$cdb->{cgipkg}->can($method)) {
    return $sub->(@_);
  }
  elsif ($sub=CGI->can($method)) {
    return $sub->(@_);
  }
  confess(__PACKAGE__."::cgi(): unknown method '$method' for cgipkg='$cdb->{cgipkg}'");
}

## undef = $cdb->cgi_main()
## undef = $cdb->cgi_main($ttk_key)
##  + wraps a template-instantiation for $ttk_key, by default basename($0)
sub cgi_main {
  my ($cdb,$key) = @_;
  my (@content);
  eval {
    @content = $cdb->ttk_process($cdb->ttk_file($key), $cdb->vars);
  };
  @content = $cdb->htmlerror(undef, $@) if ($@);
  @content = $cdb->htmlerror(undef, "template '$key' returned no content") if (!@content || !defined($content[0]));
  if ($cdb->{charset}) {
    charset($cdb->{charset});
    binmode(\*STDOUT, ":encoding($cdb->{charset})");
  }
  print @content;
}

## undef = $cdb->fcgi_main()
## undef = $cdb->fcgi_main($ttk_key)
##  + wraps a template-instantiation for $ttk_key, by default basename($0)
sub fcgi_main {
  my ($cdb,$key) = @_;
  require CGI::Fast;
  CGI::Fast->import(':standard');
  $cdb->{cgipkg} = 'CGI::Fast';
  while (CGI::Fast->new()) {
    $cdb->_getenv();
    $cdb->cgi_main($key);
    $cdb->_reset();
  }
}

##======================================================================
## Template stuff: useful aliases

sub dbDsn { return $_[0]{db_dsn}; }
sub dbUser { return $_[0]{db_user}; }

sub remoteAddr { return $_[0]{remote_addr}; }
sub remoteUser { return $_[0]{remote_user}; }
sub requestMethod { return $_[0]{request_method}; }
sub requestUri { return $_[0]{request_uri}; }
sub requestQuery { return $_[0]{request_query}; }
sub httpReferer { return $_[0]{http_referer}; }
sub httpHost { return $_[0]{http_host}; }
sub serverAddr { return $_[0]{server_addr}; }
sub serverPort {
  return $_[0]{server_port} if ($_[0]{server_port});
  my $host = $_[0]->httpHost;
  return $1 if ($host && $host =~ /:([0-9]+)$/);
  return $ENV{HTTPS} ? 443 : 80; ##-- guess port from scheme
}


## $uri    = $cdb->uri()
## $uri    = $cdb->uri($uri)
sub uri {
  return URI->new($_[1]) if (defined $_[1]);
  my $cdb = shift;
  my $host = $cdb->httpHost // '';
  my $port = $cdb->serverPort;
  my $scheme = ($ENV{HTTPS} ? 'https' : 'http'); ##-- guess scheme from HTTP environment variable
  return URI->new(
		  #($host ? "//$host" : "file://")
		  ($host ? "${scheme}://$host" : "file://")
		  .( ($host && $host =~ /:[0-9]+$/) || $port==($scheme eq 'https' ? 443 : 80) ? '' : ":$port" )
		  .$cdb->requestUri
		 );
}

## $scheme = $cdb->uriScheme($uri?)
## $opaque = $cdb->uriOpaque($uri?)
## $path   = $cdb->uriPath($uri?)
## $frag   = $cdb->uriFragment($uri?)
## $canon  = $cdb->uriCanonical($uri?)
## $abs    = $cdb->uriAbs($uri?);
sub uriScheme { $_[0]->uri($_[1])->scheme; }
sub uriPath { $_[0]->uri($_[1])->path; }
sub uriFragment { $_[0]->uri($_[1])->fragment; }
sub uriCanonical { $_[0]->uri($_[1])->canonical->as_string; }
sub uriAbs { $_[0]->uri($_[1])->abs->as_string; }

## $dir = $cdb->uriDir($uri?)
sub uriDir {
  my $uri = $_[0]->uri($_[1])->as_string;
  $uri =~ s{[?#].*$}{};
  $uri =~ s{/+[^/]*$}{};
  return $uri;
}

## $auth   = $cdb->uriAuthority($uri?)
## $pquery = $cdb->uriPathQuery($uri?)
## \@segs   = $cdb->uriPathSegments($uri?)
## $query  = $cdb->uriQuery($uri?)
## \%form  = $cdb->uriQueryForm($uri?)
## \@kws    = $cdb->uriQueryKeywords($uri?)
sub uriAuthoriry { $_[0]->uri($_[1])->authority; }
sub uriPathQuery { $_[0]->uri($_[1])->path_query; }
sub uriPathSegments { [$_[0]->uri($_[1])->path_segments]; }
sub uriQuery { $_[0]->uri($_[1])->query; }
sub uriQueryForm { {$_[0]->uri($_[1])->query_form}; }
sub uriQueryKeywords { [$_[0]->uri($_[1])->query_keywords]; }

## $userinfo = $cdb->uriUserInfo($uri?)
## $host     = $cdb->uriHost($uri?)
## $port     = $cdb->uriPort($uri?)
sub userinfo { $_[0]->uri($_[1])->userinfo; }
sub uriHost { $_[0]->uri($_[1])->host; }
sub uriPort { $_[0]->uri($_[1])->port; }

## $uristr = quri($base, \%form)
sub quri {
  shift if (isa($_[0],__PACKAGE__));
  my ($base,$form)=@_;
  my $uri=URI->new($base);
  $uri->query_form($uri->query_form, map {utf8::is_utf8($_) ? Encode::encode_utf8($_) : $_} %{$form||{}});
  return $uri->as_string;
}

## $urisub = uuri($base, \%form)
## $uristr = $urisub->(\%form)
sub uuri {
  shift if (isa($_[0],__PACKAGE__));
  my $qbase = quri(@_);
  return sub { quri($qbase,@_); };
}

## $sqstring = sqstring($str)
sub sqstring {
  shift if (isa($_[0],__PACKAGE__));
  (my $s=shift) =~ s/([\\\'])/\\$1/g; "'$s'"
}

## $quoted = escapeSQLx($str)
sub escapeSQLx {
  shift if (isa($_[0],__PACKAGE__));
  no warnings 'uninitialized';
  return $_[0] if (DBI::looks_like_number($_[0]));
  (my $s = shift) =~ s/\'/\'\'/g;
  return "'$s'"
}

## $quoted = escapeSQLs($str)
sub escapeSQLs {
  shift if (isa($_[0],__PACKAGE__));
  no warnings 'uninitialized';
  (my $s = shift) =~ s/\'/\'\'/g;
  return "'$s'"
}

## $str = sprintf_(...)
sub sprintf_ {
  shift if (isa($_[0],__PACKAGE__));
  return CORE::sprintf($_[0],@_[1..$#_]);
}

## $nrows = $cdb->nrows(%select_sql_args)
sub nrows {
  my $cdb = shift;
  my $sql = $cdb->select_sql(@_,select=>'1',orderby=>undef,offset=>undef,limit=>undef);
  return $cdb->get1row(sql=>"select count(*) from ($sql);")->{rows}[0][0];
}

## $mtime = $cdb->mtime($filename_or_dsn)
sub mtime {
  my $cdb = shift;
  my $file = shift || $cdb->{db_dsn};
  $file =~ s/^.*?=([\w\.\-\/]+).*$/$1/ if ($file =~ /^dbi:/); ##-- trim dsns
  $file = abs_path($file);
  return 0 if (!-e $file);
  my @stat = stat($file);
  return $stat[9];
}

## $str = $cdb->timestamp()
##  + gets localtime timestamp
sub timestamp {
  my $cdb = shift;
  return POSIX::strftime('%Y-%m-%d %H:%M:%S', localtime());
}

## $json_str = PACKAGE->to_json($data)
## $json_str = PACKAGE::to_json($data)
## $json_str = PACKAGE->to_json($data,\%opts)
## $json_str = PACKAGE::to_json($data,\%opts)
sub to_json {
  shift if (isa($_[0],__PACKAGE__));
  return JSON::to_json($_[0]) if (@_==1);
  return JSON::to_json($_[0],$_[1]);
}

## $json_str = PACKAGE->from_json($data)
## $json_str = PACKAGE::from_json($data)
sub from_json {
  shift if (isa($_[0],__PACKAGE__));
  return JSON::from_json(@_);
}

## \@timeofday = PACKAGE->gettimeofday()
## \@timeofday = PACKAGE::gettimeofday()
sub gettimeofday {
  shift if (isa($_[0],__PACKAGE__));
  return [Time::HiRes::gettimeofday()];
}

## $secs = PACKAGE->tv_interval($t0,$t1)
## $secs = PACKAGE::tv_interval($t0,$t1)
sub tv_interval {
  shift if (isa($_[0],__PACKAGE__));
  return Time::HiRes::tv_interval(@_);
}

## \@timeofday = PACKAGE->t_start()
## \@timeofday = PACKAGE->t_start()
##  + sets package variable $t_started
our $t_started = [Time::HiRes::gettimeofday];
sub t_start {
  shift if (isa($_[0],__PACKAGE__));
  $t_started = [Time::HiRes::gettimeofday];
}

## $secs = PACKAGE->t_elapsed()
## $secs = PACKAGE->t_elapsed($t1)
## $secs = PACKAGE->t_elapsed($t0,$t1)
## $secs = PACKAGE::t_elapsed()
## $secs = PACKAGE::t_elapsed($t1)
## $secs = PACKAGE::t_elapsed($t0,$t1)
sub t_elapsed {
  shift if (isa($_[0],__PACKAGE__));
  my ($t0,$t1) = @_;
  return tv_interval($t_started,[Time::HiRes::gettimeofday]) if (!@_);
  return tv_interval($t_started,$_[0]) if (@_==1);
  return tv_interval($_[0],$_[1]);
}

## $enc = PACKAGE->encode_utf8($str, $force=0)
## $enc = PACKAGE::encode_utf8($str, $force=0)
##  + encodes only if $force is true or if not already flagged as a byte-string
sub encode_utf8 {
  shift if (isa($_[0],__PACKAGE__));
  return $_[0] if (!$_[1] && !utf8::is_utf8($_[0]));
  return Encode::encode_utf8($_[0]);
}

## $enc = PACKAGE->decode_utf8($str, $force=0)
## $enc = PACKAGE::decode_utf8($str, $force=0)
##  + decodes only if $force is true or if not flagged as a byte-string
sub decode_utf8 {
  shift if (isa($_[0],__PACKAGE__));
  return $_[0] if (!$_[1] && utf8::is_utf8($_[0]));
  return Encode::decode_utf8($_[0]);
}

1; ##-- be happy

__END__
##========================================================================
## POD DOCUMENTATION, auto-generated by podextract.perl + edited
=pod

=cut

##========================================================================
## NAME
=pod

=head1 NAME

DbCgi - Generic template-based CGI RDBMS wrapper module

=cut

##========================================================================
## SYNOPSIS
=pod

=head1 SYNOPSIS

 ##========================================================================
 ## PRELIMINARIES
 use DbCgi;
 
 ##========================================================================
 ## constructors etc.
 
 $cdb = $CLASS_OR_OBJECT->new(%args);
 \%vars = $cdb->vars();
 
 ##========================================================================
 ## DB Stuff: Basic
 
 $dbh = $cdb->dbh();
 $dbh = $cdb->dbconnect();
 undef = $cdb->dbdisconnect;
 $sth = $cdb->execsql($sqlstr);
 
 \%info = $cdb->db_info();
 
 @tables = $cdb->tables();
 @keys   = $cdb->primary_keys($table);
 $key    = $cdb->primary_key($table);
 
 \%name2info = $cdb->column_info($table);
 @colnames   = $cdb->columns($table);
 
 ##========================================================================
 ## DB Stuff: Data Retrieval
 
 $row_arrayref = $cdb->fetch1row_arrayref($sql);
 @row_array    = $cdb->fetch1row_array($sql);
 $row_hashref  = $cdb->fetch1row_hashref($sql,\@params);
 
 \%data = $cdb->getall(%select_sql_args, hashrows=>$bool);
 \%data = $cdb->get1row(%select_sql_args, hashrows=>$bool);
 
 \@hashrows = $cdb->hashrows(\@array_row_colnames,\@array_rows);
 
 ##========================================================================
 ## DB Stuff: SQL Generation
 
 $id_sql = $cdb->id_sql($table,$idval);
 $sql = $cdb->select_sql(\%opts);
 $sql = $cdb->insert_sql(\%opts);
 $sql = $cdb->update_sql(\%opts);
 $sql = $cdb->delete_sql(\%opts);
 $sqlstr = $cdb->escapeSQL($str);
 
 ##========================================================================
 ## Template Toolkit stuff
 
 $key  = $cdb->ttk_key($key);
 $file = $cdb->ttk_file();
 $t    = $cdb->ttk_template(\%templateConfigArgs);
 $data = $cdb->ttk_process($srcFile, \%templateVars, \%templateConfigArgs);
 
 ##========================================================================
 ## CGI stuff: generic
 
 @error   = $cdb->htmlerror($status,@message);
 @content = $cdb->cgi($method, @args);
 undef    = $cdb->cgi_main();
 undef    = $cdb->fcgi_main();
 

=cut

##========================================================================
## DESCRIPTION
=pod

=head1 DESCRIPTION

The DbCgi module provides utilities for building template-based RDBMS wrappers as
CGI scripts.  Each elementary operation (e.g. view, edit, insert, update, delete, export)
is implemented as a trivial wrapper script which does nothing more than create a
DbCgi object and instantiate a Template-Toolkit template.  In most cases, the script can
be a simple symbolic link to the F<dbcgi.perl> script distributed with this module, assuming
the template sets the appropriate object parameters before any database methods are invoked.
See L<cgi_main> and/or L<fcgi_main> for details.

=cut

##----------------------------------------------------------------
## DESCRIPTION: DbCgi: constructors etc.
=pod

=head2 Constructors etc.

=over 4

=item new

 $cdb = $CLASS_OR_OBJECT->new(%args);

Create and return a new DbCgi object.  Recognized arguments together with their defaults are:

 ##-- db stuff
 db_dsn  => undef,   ##-- REQUIRED; see DBI::connect()
 db_user => undef,   ##-- REQUIRED
 db_pass => undef,   ##-- REQUIRED
 db_opts => {},      ##-- additional options for DBI->connect()
 tab_default => 'TAB_DEFAULT',  ##-- recommended
 id_default => 'ID',            ##-- default column name returned by $cdb->primary_key()
 dbh => undef,                  ##-- low-level database handle (see DBI manpage)
 ##
 ##-- basic stuff
 prog => basename($0),          ##-- used as basename for current operation template
 ##
 ##-- CGI params
 defaults => {},                ##-- defaults for CGI variables
 vars     => undef,             ##-- CGI variables; see CGI::Vars()
 charset  => 'utf8',            ##-- default charset
 ##
 ##-- CGI environment stuff
 remote_addr    => ($ENV{REMOTE_ADDR}||'0.0.0.0'),
 remote_user    => ($ENV{REMOTE_USER}||getpwuid($>)),
 request_method => ($ENV{REQUEST_METHOD}||'GET'),
 request_uri    => $ENV{REQUEST_URI},
 request_query  => $ENV{QUERY_STRING},
 http_referer   => $ENV{HTTP_REFERER}, ##-- sic
 ##
 ##-- template toolkit stuff
 ttk_package => (ref($that)||$that),
 ttk_vars    => {},                   ##-- template vars
 ttk_dir     => abs_path(dirname($0)),
 ttk_key     => undef, ##-- template basename

=item vars

 \%vars = $cdb->vars();

Gets CGI variables, instantiating $cdb-E<gt>{defaults} if present. Calls imported CGI::Vars()

=back

=cut

##----------------------------------------------------------------
## DESCRIPTION: DbCgi: DB Stuff: Basic
=pod

=head2 DB Stuff: Basic

=over 4

=item dbh

 $dbh = $cdb->dbh();

returns database handle; implicitly calls $cdb-E<gt>dbconnect() if not already connected

=item dbconnect

 $dbh = $cdb->dbconnect();

(re-)connect to database; sets $cdb-E<gt>{dbh}

=item dbdisconnect

 undef = $cdb->dbdisconnect;

disconnect from database and deletes $cdb-E<gt>{dbh}

=item execsql

 $sth = $cdb->execsql($sqlstr);
 $sth = $cdb->execsql($sqlstr,\@params);

executes sql with optional bind-paramaters \@params; returns DBI statement handle.

=item db_info

 \%info = $cdb->db_info();
  $info = $cdb->db_info($info_type_str);


get db info.  $info_type_str is the string form of some generic database property
known to DBI. See also DBI::get_info(), DBI::Const::GetInfoType.

=item tables

 @tables = $cdb->tables();
 @tables = $cdb->tables($schema);

Return an array of array-refs ([SCHEMA,TABLE],...) for all tables in database (1st form),
or an array of table names (TABLE,...) in SCHEMA (second form).

=item primary_keys

 @keys = $cdb->primary_keys(                   $table);
 @keys = $cdb->primary_keys(          $schema, $table);
 @keys = $cdb->primary_keys($catalog, $schema, $table);

get primary key(s) for $table as stored in db.
See also DBI::primary_key().

=item primary_key

 @keys = $cdb->primary_key(                   $table);
 @keys = $cdb->primary_key(          $schema, $table);
 @keys = $cdb->primary_key($catalog, $schema, $table);

Get B<first> primary key for $table, or $cdb-E<gt>{id_default} if not defined.
This is really just a convenience wrapper which is B<only> safe to use if you
know that $table a single unique primary key.

=item column_info

 \%name2info = $cdb->column_info(                   $table);
 \%name2info = $cdb->column_info(          $schema, $table);
 \%name2info = $cdb->column_info($catalog, $schema, $table);

get column information for table as hashref keyed by COLUMN_NAME.
Values are hashrefs as returned by DBI::column_info(), which see.

=item columns

 @colnames = $cdb->columns(                   $table);
 @colnames = $cdb->columns(          $schema, $table);
 @colnames = $cdb->columns($catalog, $schema, $table);

get column names for C<$catalog.$schema.$table> in db-storage order

=back

=cut

##----------------------------------------------------------------
## DESCRIPTION: DbCgi: DB Stuff: Data Retrieval
=pod

=head2 DB Stuff: Data Retrieval

=over 4

=item fetch1row_arrayref

 $row_arrayref = $cdb->fetch1row_arrayref($sql);
 $row_arrayref = $cdb->fetch1row_arrayref($sql,\@params)

get a single row from the database as an ARRAY-ref.

=item fetch1row_array

 @row_array = $cdb->fetch1row_array($sql);
 @row_array = $cdb->fetch1row_array($sql,\@params)

get a single row from the database as an array.

=item fetch1row_hashref

 $row_hashref = $cdb->fetch1row_hashref($sql,\@params);

get a single row from the database as a HASH-ref.

=item getall

 \%data = $cdb->getall(%select_sql_args, hashrows=>$bool);
 \%data = $cdb->getall(\%select_sql_args_or_hashrows).

Returns db-data for $cdb-E<gt>select_sql(%select_sql_args) as $data =

 {
  names => \@colnames,    ##-- array of column names
  rows  => \@rows,        ##-- array of rows (ARRAY-refs)
  hrows => \@rows,        ##-- array of rows (HASH-refs); only if 'hashrows' option is specified and true
  nrows => $nrows,        ##-- number of rows as returned by $sth->rows()
 }

=item get1row

 \%data = $cdb->get1row(%select_sql_args, hashrows=>$bool);
 \%data = $cdb->get1row(\%select_sql_args_or_hashrows)

just like $cdb-E<gt>getall(...), but die()s if not exactly 1 row is returned.

=item hashrows

 \@hashrows = $cdb->hashrows(\@array_row_colnames,\@array_rows);

returns ARRAY-ref of HASH-refs for each row of @array_rows rows, keyed by \@array_row_colnames.

=back

=cut

##----------------------------------------------------------------
## DESCRIPTION: DbCgi: DB Stuff: SQL Generation
=pod

=head2 DB Stuff: SQL Generation

=over 4

=item id_sql

 $id_sql = $cdb->idsql($table,$idval);

Returns a WHERE clause for C<PRIMARY_KEY($table) = $idval>.

=item select_sql

 $sql = $cdb->select_sql(\%opts);
 $sql = $cdb->select_sql( %opts)

Returns an SQL string appropriate for querying the database. Known %opts =

 sql     => $raw_sql_str, ##-- override
 select  => \@cols,       ##-- ... or raw sql string (parsed)
 from    => \@tables,     ##-- ... or raw sql string (parsed)
 where   => \@conds,      ##-- AND-joined list, or raw sql string (NOT parsed)
 $col    => $string,      ##-- ... other column-name keys are used for 'where' clause if not already present
 ".$col" => $expr,        ##-- ... other dot-column keys are used for 'where' clause
 oderby  => $spec,
 groupby => $spec,
 offset  => $offset,
 limit   => $limit,

=item insert_sql

 $sql = $cdb->insert_sql(\%opts);
 $sql = $cdb->insert_sql( %opts)

Returns SQL string appropriate for inserting values into the database.
Known %opts =

 sql     => $raw_sql_str, ##-- override
 into    => $table,       ##-- ... or raw sql string (single table only)
 set     => \%col2val,    ##-- set these columns (values are auto-escaped unless $col begins with '.') [alias:'values']
 $col    => $string,      ##-- ... other column-name keys are used for 'set' clause if not already present
 ".$col" => $expr,        ##-- ... other dot-column keys are used for 'set' clause

=item update_sql

 $sql = $cdb->update_sql(\%opts);
 $sql = $cdb->update_sql( %opts)

Returns SQL string appropriate for updating values in the database.
Known %opts = 

 sql     => $raw_sql_str, ##-- override
 update  => $table,       ##-- single table only [alias: 'table']
 set     => \%col2val,    ##-- set these columns (values are auto-escaped unless $col begins with '.') [alias: 'values']
 $col    => $string,      ##-- ... other column-name keys are used for 'set' clause if not already present
 ".$col" => $expr,        ##-- ... other dot-column keys are used for 'set' clause; clobbers ($col=>$str)
 where   => \@conds,      ##-- AND-joined
 id      => $idval,       ##-- ... like "WHERE id=$idval"

=item delete_sql

 $sql = $cdb->delete_sql(\%opts);
 $sql = $cdb->delete_sql( %opts)

Returns SQL string appropriate for deleting values from the database.
Known %opts =

 sql     => $raw_sql_str, ##-- override
 from    => \@tables,     ##-- ... or raw sql string (parsed) [alias: 'from']
 where   => \@conds,      ##-- AND-joined
 $col    => $string,      ##-- ... other column-name keys are used for 'where' clause if not already present
 ".$col" => $expr,        ##-- ... other dot-column keys are used for 'where' clause

=item escapeSQL

 $sqlstr = $cdb->escapeSQL($str);
 $sqlstr = $cdb->escapeSQL($str,$sql_type)

Returns SQL-escaped version of $str.  Really just a wrapper for C<$cdb-E<gt>dbh-E<gt>quote($str,$sql_type)>.

=back

=cut

##----------------------------------------------------------------
## DESCRIPTION: DbCgi: Template Toolkit stuff
=pod

=head2 Template Toolkit stuff

=over 4

=item ttk_key

 $key = $cdb->ttk_key($key);
 $key = $cdb->ttk_key()

Returns current template key;
default is basename($cdb-E<gt>{prog}) without final extension.

=item ttk_file

 $file = $cdb->ttk_file();
 $file = $cdb->ttk_file($key)

Returns template filename for template key (basename) $key,
which defaults to $cdb-E<gt>{prog} without final extension.

=item ttk_template

 $t = $cdb->ttk_template(\%templateConfigArgs);

Returns a new Template object with default configuration arguments set.

=item ttk_process

 $data = $cdb->ttk_process($srcFile, \%templateVars, \%templateConfigArgs);

Process a template $srcFile, returns generated $data.

=back

=cut

##----------------------------------------------------------------
## DESCRIPTION: DbCgi: CGI stuff: generic
=pod

=head2 CGI stuff: generic

=over 4

=item htmlerror

 @error = $cdb->htmlerror($status,@message);

Returns a print()-able HTML error.

=item cgi

 @whatever = $cdb->cgi($method, @args);

Call a method from the CGI package CGI-E<gt>can($method).

=item cgi_main

 undef = $cdb->cgi_main();
 undef = $cdb->cgi_main($ttk_key);

Wraps a template-instantiation for $cdb-E<gt>ttk_key($ttk_key).
This is basically just a wrapper for:

 print $cdb->ttk_process($cdb->ttk_file($ttk_key), $cdb->vars);

... with some additional wrapper code to catch and report errors using
the htmlerror() method.

=item fcgi_main

 undef = $cdb->fcgi_main();
 undef = $cdb->fcgi_main($ttk_key);

Like L<cgi_main> using the CGI::Fast module.

=back

=cut

##========================================================================
## END POD DOCUMENTATION, auto-generated by podextract.perl
=pod



=cut

##======================================================================
## Footer
##======================================================================
=pod

=head1 AUTHOR

Bryan Jurish E<lt>jurish@bbaw.deE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2011 by Bryan Jurish

This package is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.10.1 or,
at your option, any later version of Perl 5 you may have available.

=head1 SEE ALSO

L<DBI(3perl)|DBI>,
L<CGI(3perl)|CGI>,
L<Template(3perl)|Template>,
L<perl(1)|perl>,
...


=cut
