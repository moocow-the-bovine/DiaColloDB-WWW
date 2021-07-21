NAME
    README for ddc-dstar/corpus/web

SYNOPSIS
     ##-- ... display summary of known targets
     $ make help

     ##-- .... (re-) initialize local configuration files(s)
     $ make init

     ##-- ... install generated apache site configuration to /etc/apache2 (WEB_SITE_INSTALL_DIR)
     $ sudo make install

     ##-- ... install if required, and register with apache
     $ make register

     ##-- ... remove most generated files (including indices)
     $ make clean

DESCRIPTION
    This directory provides a generic web-based interface for use with D*
    corpora. The D* corpus management tools are maintained in SVN under
    "svn+ssh://svn.dwds.de/home/svn/dev/ddc-dstar/trunk/", and are mirrored
    daily to the READ-ONLY ZDL gitea repository
    <https://git.zdl.org/svn-mirror/ddc-dstar/src/branch/master/>.

  Requirements
    See "README_deps" <http://kaskade.dwds.de/dstar/doc/README_deps.html>
    rsp. the SVN sub-project
    "svn+ssh://svn.dwds.de/home/svn/dev/ddc-dstar/deps" rsp. its read-only
    gitea mirror <https://git.zdl.org/svn-mirror/dstar-deps/>.

  Web Directory Structure
   Subdirectories
    The "corpus/web/"
    <https://git.zdl.org/svn-mirror/ddc-dstar/src/branch/master/corpus/web/>
    directory contains the following subdirectories:

    config/
        (OBSOLETE) Corpus-dependent configuration directory - now in
        "$(WEB_RCDIR
        <http://kaskade.dwds.de/dstar/doc/README_config.html#WEB_RCDIR>)",
        usually "$(DSTAR_ROOT
        <http://kaskade.dwds.de/dstar/doc/README_config.html#DSTAR_ROOT>)/co
        nfig/web".

        You can store corpus-dependent web overrides in the Template Toolkit
        file "config/$(CORPUS
        <http://kaskade.dwds.de/dstar/doc/README_config.html#CORPUS>).ttk",
        which will be read by all local templates. Such corpus-dependent
        templates can and should be checked into the dstar version control
        system, assuming they are valid for all instances of a given corpus.
        Perl-level overrides can be stored in "config/$(CORPUS
        <http://kaskade.dwds.de/dstar/doc/README_config.html#CORPUS>).rc"
        and will be included in the local "dstar.rc" file by the "init-rc"
        target.

        In earlier versions of the dstar system, the "corpus/web/config"
        directory was situated directly under "$(CORPUS
        <http://kaskade.dwds.de/dstar/doc/README_config.html#CORPUS>)/web/".
        As of SVN revision 13975 (2015-03-02), "corpus/web/config/" is just
        a symbolic link to "$(WEB_RCDIR
        <http://kaskade.dwds.de/dstar/doc/README_config.html#WEB_RCDIR>)",
        by default "$(DSTAR_ROOT
        <http://kaskade.dwds.de/dstar/doc/README_config.html#DSTAR_ROOT>)/co
        nfig/web/".

    "diacollo/"
    <https://git.zdl.org/svn-mirror/ddc-dstar/src/branch/master/corpus/web/d
    iacollo/>
        (Optional) generic web-interface
        <https://metacpan.org/release/DiaColloDB-WWW> to the DiaColloDB
        <https://metacpan.org/release/DiaColloDB> diachronic collocation
        database for the current corpus. Only used if an index is available
        and the value of the make variable "$(WEB_DIACOLLO_ENABLED
        <http://kaskade.dwds.de/dstar/doc/README_config.html#WEB_DIACOLLO_EN
        ABLED>)" is neither empty nor ""no"".

    "highslide/"
    <https://git.zdl.org/svn-mirror/ddc-dstar/src/branch/master/corpus/web/h
    ighslide/>
        Static "highslide.js" snapshot used for transitory popups.

    "images/"
    <https://git.zdl.org/svn-mirror/ddc-dstar/src/branch/master/corpus/web/i
    mages/>
        Logos and icons for dstar corpora. You can check small corpus-local
        logos and icons into this directory if you wish.

    lexdb/
    <https://git.zdl.org/svn-mirror/ddc-dstar/src/branch/master/corpus/web/l
    exdb/>
        (Optional) generic web-interface to the simple sqlite corpus lexical
        database for the current corpus. Only used if a lexdb database is
        available and the value of the make variable "$(WEB_LEXDB_ENABLED
        <http://kaskade.dwds.de/dstar/doc/README_config.html#WEB_LEXDB_ENABL
        ED>)" is neither empty nor ""no"".

    "semcloud/"
    <https://git.zdl.org/svn-mirror/ddc-dstar/src/branch/master/corpus/web/s
    emcloud/>
        Distributional semantic index and web-service wrappers for the
        current corpus. Only used if such an index was built and installed
        at corpus compilation time and the value of the make variable
        "$(WEB_SEMCLOUD_ENABLED
        <http://kaskade.dwds.de/dstar/doc/README_config.html#WEB_SEMCLOUD_EN
        ABLED>)" is neither empty nor ""no"".

    "stats/"
    <https://git.zdl.org/svn-mirror/ddc-dstar/src/branch/master/corpus/web/s
    tats/>
        (Optional) directory containing various assorted pre-compiled corpus
        statistics. Only populated if the corresponding statistics were
        built at corpus compilation time. Prior to 2020-03, such statistics
        were regularly updated by a cron-job running "$(DSTAR_ROOT
        <http://kaskade.dwds.de/dstar/doc/README_config.html#DSTAR_ROOT>)/we
        broot/www-stats/dstar-stats-update.perl". See "Corpus Statistics"
        for a list of the compiled statistics.

   Configuration Files
    The following configuration files are either generated by "make init" or
    optional manual overrides. Please do not check any of these
    configuration files into version control.

    dstar.rc
        Low-level perl file generated by "make init" and sourced by all CGI
        scripts to set default values for DDC server, corpus name, and base
        URL. Also includes any local code from "config/$(CORPUS
        <http://kaskade.dwds.de/dstar/doc/README_config.html#CORPUS>).rc" if
        present.

    local.rc
        OPTIONAL low-level perl file which can be used to set local
        overrides of the variables in "dstar.rc"

    siterc.vars
        Simple "make" variable assignments used for generating "site.rc", 1
        variable per line, lines of the form "*VAR*=*VALUE*". Also used by
        "config.perl".

    site.rc
        Apache configuration file generated by "make init" via "siterc.ttk"
        <https://git.zdl.org/svn-mirror/ddc-dstar/src/branch/master/corpus/w
        eb/siterc.ttk>, and installed into
        "/etc/apache2/sites-(available|enabled)" by "make install" (implied
        by "make register"). Changes to corpus configuration variables which
        affect the apache site configuration (in particular those involving
        access restrictions such as "WEB_DIACOLLO_ENABLE"
        <http://kaskade.dwds.de/dstar/doc/README_config.html#WEB_DIACOLLO_EN
        ABLE>, "WEB_DIACOLLO_PUBLIC"
        <http://kaskade.dwds.de/dstar/doc/README_config.html#WEB_DIACOLLO_PU
        BLIC>, "WEB_SITE_ALLOW"
        <http://kaskade.dwds.de/dstar/doc/README_config.html#WEB_SITE_ALLOW>
        , "WEB_SITE_PUBLIC"
        <http://kaskade.dwds.de/dstar/doc/README_config.html#WEB_SITE_PUBLIC
        >, "WEB_SITE_AUTH_FILE"
        <http://kaskade.dwds.de/dstar/doc/README_config.html#WEB_SITE_AUTH_F
        ILE>, "WEB_SITE_AUTH_EXTERNAL"
        <http://kaskade.dwds.de/dstar/doc/README_config.html#WEB_SITE_AUTH_E
        XTERNAL>, etc.) require re-initialization ("make init") and
        re-registration ("dstar-register-web.sh") of the working copy on
        "WEBHOST", in order to ensure that the apache configuration updated
        and reloaded.

    corpus.ttk
        As mentioned above, corpus-local configuration can be tuned by
        creating and/or editing the file "config/$(CORPUS
        <http://kaskade.dwds.de/dstar/doc/README_config.html#CORPUS>).ttk"
        to override or set default values for Template Toolkit variables
        used by the web templates. If "config/$(CORPUS
        <http://kaskade.dwds.de/dstar/doc/README_config.html#CORPUS>).ttk"
        is present, then the directory initialization rules invoked by "make
        init" will create the file "corpus.ttk" as a symlink pointing to
        "config/$(CORPUS
        <http://kaskade.dwds.de/dstar/doc/README_config.html#CORPUS>).ttk".
        Otherwise, "corpus.ttk" will be auto-generated as an empty file.

        See "common.ttk" for a list of common variables which can be set
        here.

    custom.ttk
        OPTIONAL Template Toolkit customization file loaded AFTER
        "corpus.ttk" and the main content of "common.ttk" which can be used
        to set instance-specific overrides.

    osd.xml
    <https://git.zdl.org/svn-mirror/ddc-dstar/src/branch/master/corpus/web/o
    sd.xml>
        OpenSearch description document for the web wrapper instance
        generated by "make init".

   CGI Scripts
    The web wrapper directory contains the following CGI scripts:

    config.perl
        Wrapper for "dstar.perl" which returns read-only configuration
        variable dumps in JSON format. The configuration variables to be
        dumped can be selected by the "fmt" parameter, which accepts the
        following values:

         all    : full dump (default)
         auth   : authorization make variables
         env    : environment variables
         site   : WEB_* make variables (siterc.vars)
         stash  : Template::Toolkit stash

        Note that in order to minimize the potential for abuse, HTTP access
        to "config.perl" should typically be much more restrictive than
        general web-wrapper access, and are controlled by the D*
        configuration variables of the form "WEB_SITE_CONFIG_*"
        <http://kaskade.dwds.de/dstar/docurl/README_config.html#WEB_SITE_CON
        FIG_ALLOW>.

    ddc-cgi.perl
        "Thin" ddc wrapper, adapted from
        "svn+ssh://svn.code.sf.net/p/ddc-concordance/code/ddc-perl/trunk/ddc
        -cgi.perl". Automated clients should access this script rather than
        "dstar.perl" whenever possible, in order to minimize computation
        overhead and maintain maximal compatibility with the ddc-internal
        json format. Accepts the following parameters:

         q      # user query or request [required]
         mode   # query mode (json,html,table,text,req); default=json
         start  # first hit-number to return, starting from 1; default=1
         limit  # maximal number of hits to return; default=10
         hint   # navigation hint for ddc >= v2.1.9
         server # (DEBUG) alternate ddc server as HOST:PORT

    details.perl
        Symlink to "dstar.perl" which displays human-readable server status
        and corpus information.

    dhist-plot.perl
        Low-level time-series histogram acquisition and plotting script,
        really just an "svn:externals" alias for
        "svn+ssh://svn.dwds.de/home/svn/dev/ddc-dstar-timeseries/trunk/ts-pl
        ot.perl" (mirrored daily to
        <https://git.zdl.org/svn-mirror/ddc-dstar-timeseries>). Accepts the
        following parameters:

         ##-- time-series histogram options
         query          # target query (aliases: query qu q lemma lem l) [required]
         unit           # date-slice unit (aliases: unit u); known values: y=years(default), m=months, d=days
         offset         # date-slice offset in selected UNITs (aliases: offset off)
         slice          # date-slice interval size (integer); aliases=qw(sliceby slice sl s); default=10
                        # + notation {SIZE}("+"|"-"){OFFSET} also sets default "offset" value
                        # + notation {SIZE}(("+"|"-"){OFFSET})?{UNIT} also sets default "unit" value
         norm           # normalization mode (abs date class date+class corpus); aliases=qw(normalize norm n); default=abs
         logproj        # do log-linear projection? (aliases: logproject logp lp); default=0
         logavg         # do log-linear smoothing? (aliases: logavg loga la lognorm logn log ln); default=0
         window         # moving-average smoothing window width (slices) (aliases: window win w); default=0
         wbase          # inverse-distance smoothing base (aliases: wbase wb W); default=0
         totals         # plot totals? (aliases: totals tot T); default=0
         single         # plot single-curve only (true) or each genre separatately (false)? (aliases: single sing sg); default=0
         grand          # include grand-average curve (implied by single=1)? (aliases: grand gr g); default=0
         gaps           # allow gaps for missing (zero) values? (aliases: gaps gap); default=0
         prune          # inverse confidence level for outlier detection (0: no pruning, .05: 95% confidence level; aliases: prune pr); default=0 (may change)
         pformat        # target plot format (aliases: pformat pfmt pf format fmt f); default=png
                        # - known values: null json text gnuplot png svg eps ps pdf epsmono psmono pdfmono

         ##-- gnuplot-only options
         xlabel         # x-axis label (default="date"; set to "none" to supppress)
         ylabel         # y-axis label (default="": auto; set to "none" to suppress)
         xrange         # gnuplot x-range (aliases: xrange xr); default=*:*
         yrange         # gnuplot y-range (aliases: yrange yr); default=0:*
         logscale       # log-scale base for gnuplot axes (aliases: logscale lscale ls logy ly); default=0 (no log-scaling)
         title          # gnuplot title; default='' (auto-generated; 'none' to suppress title)
         size           # gnuplot size (w,h) (aliases: psize psiz psz size siz sz); default=640,480
         key            # gnuplot legend? (aliases: key legend leg); default='' (gnuplot default; "off" or "none" to suppress)
         smooth         # gnuplot smoothing (values: none bezier csplines); default=none
         style          # gnuplot style (values: lines points linespoints); default=l
         grid           # gnuplot grid? default=0
         bare           # gnuplot condensed format (line width)? default=0 (large plot)

         ##-- json-only options
         pretty         # pretty-print json output?; default=0

    dstar.perl
        Top-level wrapper script for processing user queries. Accepts (among
        others) the following parameters:

         q      # user-specified ddc query; required
         start  # first hit-number to return (starting from 1); default=1
         limit  # maximal number of hits to return; default=10
         hint   # navigation hint for ddc >= v2.1.9
         export # Boolean; sets http content-disposition=attachment if true
         fmt    # output format; default=kwic (but depends on how dstar.perl was called); known values:
                #   index        : top-level corpus landing page (HTML)
                #   osd          : OpenSearch description file for corpus (XML)
                #   details      : human-readable corpus details (HTML)
                #   ddc          : (raw) raw query response data from ddc_daemon (usually raw JSON)
                #   html         : (web) corpus query results (HTML, full hits)
                #   kwic         : corpus query results (HTML, Keyword-In-Context)
                #   text         : (txt) corpus query results (UTF-8 text, full hits)
                #   text-kwic    : corpus query results (UTF-8 text, KWIC)
                #   csv          : comma-separated table (for spreadsheet import, full hits)
                #   csv-kwic     : comma-separated table (for spreadsheet import, KWIC)
                #   tsv          : TAB-separated table (for spreadsheet import, full hits)
                #   tsv-kwic     : TAB-separated table (for spreadsheet import, KWIC)
                #   json         : corpus query results (verbose JSON)
                #   json1        : corpus query results (verbose JSON, pretty)
                #   json2        : corpus query results (verbose JSON, prettier)
                #   yaml         : (yml) corpus query results (YAML)
                #   rss          : corpus query results (rss+xml)
                #   atom         : corpus query results (atom+xml)
                #   tcf          : corpus query results (tcf+xml)
                #   hist-html    : (hist, ts, ts-html) time-series histogram query results (HTML)
                #   hist-plot    : (plot, ts-plot) time-series histogram plot data (from dhist-plot.perl)
                #   hist-help    : time-series histogram help (HTML)
                #   expand-html  : (expand) term expansion GUI (HTML)
                #   expand-json  : term expansion (JSON)
                #   expand-text  : term expansion (UTF-8 text)
         server # (DEBUG) alternate ddc server as HOST:PORT

    help-hist.perl
        Symlink to "dstar.perl" which displays a human-readable help page
        for the time-series histogram interface.

    hist.perl
        Symlink to "dstar.perl" providing a top-level time-series histogram
        interface by setting a default "fmt=hist-html".

    lizard.perl
        Symlink to "dstar.perl" providing a top-level term expansion
        interface by setting a default "fmt=expand-html".

    diacollo/index.perl
        Top-level DiaColloDB::WWW
        <https://metacpan.org/release/DiaColloDB-WWW> user interface for
        DiaColloDB <https://metacpan.org/release/DiaColloDB>. Accepts the
        following parameters:

         query     # target LEMMA(s) or /REGEX/ or DDC query (aliases: query q lemmata lemmas lemma lem l; REQUIRED)
         date      # target DATE(s) or /REGEX/ or MIN:MAX (aliases: dates date d; default=all)
         slice     # target date-slice or 0 for global profile (aliases: dslice slice ds sl s; default=10)
         bquery    # diff target query (aliases: bquery bq blemmata blemmas blemma blem bl; default=$QUERY)
         bdate     # diff target date  (aliases: bdates bdate bd; default=$DATE)
         bslice    # diff target slice (aliases: bdslice bslice bds bsl bs; default=$SLICE)
         groupby   # aggregation attribute list with optional restrictions (aliases: groupby group gr gb g; default=l,p)
         score     # score function (aliases: score sc sf; default=ld); known values:
                   #  f     : frequency
                   #  fm    : frequency per million
                   #  lf    : log frequency
                   #  lfm   : log frequency per million
                   #  mi1   : pointwise mutual information (raw)
                   #  mi3   : cubic pointwise mutual information
                   #  milf  : pointwise mutual information * log frequency product (alias: mi)
                   #  ll    : 1-sided log likelihood a la Evert (2008)
                   #  ld    : log Dice coefficient a la Rychly (2008)
         kbest     # number of items per date-slice (aliases: kbest kb k; default=10)
         cutoff    # score cutoff per date-slice (aliases: cutoff cut co; not for "diff" profiles)
         diff      # low-level diff operation (aliases: diffop diff D; default=adiff); known values:
                   #  diff  : raw difference (pre-trimmed, asymmetric)
                   #  adiff : selects by absolute difference, returns raw difference (pre-trimmed, symmetric)
                   #  sum   : score sum (symmetric)
                   #  min   : minimum score (pre-trimmed, symmetric)
                   #  max   : maximum score (symmetric)
                   #  avg   : average score (symmetric)
                   #  havg  : adjusted harmonic average (symmetric)
                   #  gavg  : adjusted geometric average (symmetric)
                   #  lavg  : adjusted log average (symmetric)
         global    # whether to apply trimming paramters (kbest,cutoff) globally or slice-locally (default=0)
         onepass   # whether to use old, fast, incorrect 1-pass frequency acquisition? (default=0; aliases: 1pass 1p)
         debug     # debug mode? (aliases: debug dbg; default=0)
         profile   # profile-type (aliases: profile prof prf pr p; default=2); known values:
                   #  colloc        (aliases: cof c f12 2)
                   #  unigrams      (aliases: ug u f1 1)
                   #  tdf           (aliases: tdm)
                   #  ddc           (aliases: DDC)
                   #  diff-colloc   (aliases: diff-cof diff-c diff-f12 diff-2 d2)
                   #  diff-unigrams (aliases: diff-ug diff-u diff-f1 diff-1 d1)
                   #  diff-tdf      (aliases: diff-tdm dtdm dtdf)
                   #  diff-ddc      (aliases: diff-DDC dDDC dddc)
         format    # output format (aliases: format fmt f; default=html); known values:
                   #  txt           (aliases: text txt t tsv csv)
                   #  json          (aliases: json js j)
                   #  html          (aliases: html htm)
                   #  storable      (aliases: storable sto bin)
                   #  gmotion       (aliases: gmotion gm)
                   #  hichart       (aliases: highcharts highchart hichart chart hi hc)
                   #  bubble        (aliases: bubbles bubble bub b)
                   #  cloud         (aliases: cloud cld cl c)

    diacollo/profile.perl
        Low-level script for DiaColloDB queries, returns DiaColloDB data.
        Accepts the same parameters as "diacollo/index.perl".

    lexdb/view.perl
        Top-level user interface for LexDB viewing. Accepts the following
        parameters:

         select       # SQLite SELECT clause (default=w,p,l,f)
         from         # SQLite FROM clause (default=lex)
         where        # SQLite WHERE clause (default="")
         groupby      # SQLite GROUP BY clause (default="")
         orderby      # SQLite ORDER BY clause (default="")
         offset       # SQLite LIMIT clause offset (default=0)
         limit        # SQLite LIMIT clause limit (default=10)

    lexdb/export.perl
        Low-level wrapper for LexDB data export. Accepts the same parameters
        as "lexdb/view.perl", and also:

         fmt          # output format, one of (json text); default=text

    lexdb/suggest.perl
        Low-level wrapper for DDC query auto-completion via LexDB. Accepts
        the following parameters:

         a            # attribute to query (aliases: a index attr; default: guess from query)
         q            # user query or term (aliases: q term)
         case         # use letter-case for suggestion search? (default: guess)
         offset       # offset of first result hit (default=0)
         limit        # number of suggestions to return (default=10)
         f            # result format (default="json"); known formats:
                      #  gs    : google suggestion JSON (for jquery-ui)
                      #  os    : OpenSearch suggestion JSON
                      #  json  : flat JSON suggestion list
                      #  text  : flat raw suggestion text
                      #  csv   : TAB-separated list of frequencies and suggestions

    semcloud/index.perl
        Top-level entry point for distributional semantic index GUI (if
        available).

    semcloud/pages.perl
         Alias: semcloud/docs.perl

        GUI for k-nearest-neighbor pages. Sets default target axis
        "to=pages"; all other parameters as for "semq.perl".

    semcloud/books.perl
         Alias: semcloud/cats.perl

        GUI for k-nearest-neighbor books (files). Sets default target axis
        to "to=books"; all other parameters as for "semq.perl".

    semcloud/terms.perl
         Alias: semcloud/terms.perl

        GUI for k-nearest-neighbor terms (files). Sets default target axis
        to "to=terms"; all other parameters as for "semq.perl".

    semcloud/semq.perl
         Alias: semcloud/semq.fcgi

        Guts for k-nearest-neighbor distributional semantic index search.
        Accepts the following parameters:

         q     # query string (required): CONTENT_LEMMA | page=REGEX | book=REGEX ...
         to    # target axis (terms | pages | books); default=books
         k     # number of nearest items to return; default=50
         b     # base for Maxwell-Boltzmann distance-to-probability conversion; default=2
         beta  # inverse temperature for Maxwell-Boltzmann distance-to-probability conversion; default=-1
         color # target color space (color | mono); default=color

   Index data
    The following index data files may (or may not) be published to this
    directory by invoking "make publish"
    <http://kaskade.dwds.de/dstar/doc/HOWTO.html#Remote-Publish> in a corpus
    build directory:

     dhist.db                 # fast static Berkeley-DB for "trivial" dhist-plot.perl queries
     dhist.db.ver             # dhist.db build version
     dhist-cache.json         # cache for dhist-plot.perl (1-year resolution)
     dhist-cache.json_m       # cache for dhist-plot.perl (1-month resolution, if supported)
     dhist-cache.json_y       # cache for dhist-plot.perl (1-day resolution, if supported)
 
     diacollo/data/           # DiaColloDB index data directory
 
     lexdb/lexdb.sqlite       # LexDB database
     lexdb/version.txt        # LexDB build version
 
     semcloud/dc-pages-map.d/ # DTA-style DocClassify model for semcloud

   Cache files
    The following dynamic cache files are used, and should be (re-)generated
    at the latest by a call to "make init" in the "corpus/web"
    <https://git.zdl.org/svn-mirror/ddc-dstar/src/branch/master/corpus/web/>
    checkout directory:

     dhist-cache.json    # cache for dhist-plot.perl (1-year resolution)
     dhist-cache.json_m  # cache for dhist-plot.perl (1-month resolution, if supported)
     dhist-cache.json_y  # cache for dhist-plot.perl (1-day resolution, if supported)
     gpversion.txt       # output of `gnuplot --version` for dhist-plot.perl
     osd.xml             # generated OpenSearch description document

    The "dhist-cache.json*" cache files should typically be generated at
    index compilation time and published
    <http://kaskade.dwds.de/dstar/doc/HOWTO.html#Remote-Publish> together
    with the corpus index data. Earlier versions of the dstar web-wrappers
    updated these cache files on-demand in response to user queries. The
    on-demand cache generation behavior can be enabled by setting the make
    variable "WEB_CACHE_STATIC
    <http://kaskade.dwds.de/dstar/doc/README_config.html#WEB_CACHE_STATIC>=n
    o" (assuming appropriate values for "WEB_CACHE_GROUP"
    <http://kaskade.dwds.de/dstar/doc/README_config.html#WEB_CACHE_GROUP>
    and "WEB_CACHE_PERMS"
    <http://kaskade.dwds.de/dstar/doc/README_config.html#WEB_CACHE_PERMS>),
    and re-initializing the "corpus/web"
    <https://git.zdl.org/svn-mirror/ddc-dstar/src/branch/master/corpus/web/>
    checkout via "make init".

   Corpus Statistics
    A number corpus statistics files may be available in the "stats/"
    subdirectory. Exactly which files are available for a given corpus is
    determined by the compile-time "STATS*" variables, e.g. "STATS_ENABLED"
    <http://kaskade.dwds.de/dstar/doc/README_config.html#STATS_ENABLED>,
    "STATS_VARIANT"
    <http://kaskade.dwds.de/dstar/doc/README_config.html#STATS_VARIANT>,
    "STATS_QUERIES"
    <http://kaskade.dwds.de/dstar/doc/README_config.html#STATS_QUERIES>,
    "STATS_LEXDB_QUERIES"
    <http://kaskade.dwds.de/dstar/doc/README_config.html#STATS_LEXDB_QUERIES
    >, "STATS_EXTRA"
    <http://kaskade.dwds.de/dstar/doc/README_config.html#STATS_EXTRA>, etc.
    Unless explicitly noted as "optional", all statistics files listed in
    this section should be available for all dstar corpora.

    Additionally, compatibility symlinks (or sometimes copies) of some
    DDC-query statistics files may be included, depnding on the value of
    "STATS_SYMLINKS"
    <http://kaskade.dwds.de/dstar/doc/README_config.html#STATS_SYMLINKS>.
    Compatibility symlinks typically have file basenames of the form
    "count___*.txt" derived from the underlying DDC query. Use of
    compatibility symlinks is *deprecated* as of 2021-03-09.

    ddc.files.all.txt
         DDC query: count(* #in file)
         Symlink  : count____in_file_.txt

    ddc.files.by-decade.txt
         DDC query: count(* #in file) #by[date/10]
         Symlink  : count____in_file___by_date_10_.txt

    ddc.files.by-decade+genre.txt
         DDC query: count(* #in file) #by[date/10,textClass~s/:.*//]
         Symlink  : count____in_file___by_date_10_textClass_s_______.txt

    ddc.files.by-decade+genre+pos.txt
         DDC query: count(* #in file) #by[date/10,textClass~s/:.*//,]
         Symlink  : count____in_file___by_date_10_textClass_s________.txt

    ddc.files.by-decade+pos.txt
         DDC query: count(* #in file) #by[date/10,]
         Symlink  : count____in_file___by_date_10__.txt

    ddc.files.by-genre.txt
         DDC query: count(* #in file) #by[textClass~s/:.*//]
         Symlink  : count____in_file___by_textClass_s_______.txt

    ddc.files.by-genre+pos.txt
         DDC query: count(* #in file) #by[textClass~s/:.*//,]
         Symlink  : count____in_file___by_textClass_s________.txt

    ddc.files.by-pos.txt
         DDC query: count(* #in file) #by[]
         Symlink  : count____in_file___by__.txt

    ddc.files.by-urldomain.txt
         DDC query: count(* #in file) #by[url~s/^(?:https?:\/\/)(?:www\.)?([^\/]+).*/$1/]

        OPTIONAL, enabled by default if "STATS_VARIANT
        <http://kaskade.dwds.de/dstar/doc/README_config.html#STATS_VARIANT>
        = web". This list can potentially grow quite large (*O(N_docs)*),
        and may not be very useful in its raw form. It is nonetheless
        required for correct computation of "extra.urldomains.n.txt" and
        "extra.urldomains.top-20.txt", in particular when superordinate
        metacorpora are involved (see mantis #52445
        <https://mantis.dwds.de/mantis/view.php?id=52445>).

    ddc.sentences.all.txt
         DDC query: count(* #in s)
         Symlink  : count____in_s_.txt

    ddc.sentences.by-decade.txt
         DDC query: count(* #in s) #by[date/10]
         Symlink  : count____in_s___by_date_10_.txt

    ddc.sentences.by-decade+genre.txt
         DDC query: count(* #in s) #by[date/10,textClass~s/:.*//]
         Symlink  : count____in_s___by_date_10_textClass_s_______.txt

    ddc.sentences.by-decade+genre+pos.txt
         DDC query: count(* #in s) #by[date/10,textClass~s/:.*//,]
         Symlink  : count____in_s___by_date_10_textClass_s________.txt

    ddc.sentences.by-decade+pos.txt
         DDC query: count(* #in s) #by[date/10,]
         Symlink  : count____in_s___by_date_10__.txt

    ddc.sentences.by-genre.txt
         DDC query: count(* #in s) #by[textClass~s/:.*//]
         Symlink  : count____in_s___by_textClass_s_______.txt

    ddc.sentences.by-genre+pos.txt
         DDC query: count(* #in s) #by[textClass~s/:.*//,]
         Symlink  : count____in_s___by_textClass_s________.txt

    ddc.sentences.by-pos.txt
         DDC query: count(* #in s) #by[]
         Symlink  : count____in_s___by__.txt

    ddc.tokens.all.txt
         DDC query: count(* #sep)
         Symlink  : count____sep_.txt

    ddc.tokens.by-decade.txt
         DDC query: count(* #sep) #by[date/10]
         Symlink  : count____sep___by_date_10_.txt

    ddc.tokens.by-decade+genre.txt
         DDC query: count(* #sep) #by[date/10,textClass~s/:.*//]
         Symlink  : count____sep___by_date_10_textClass_s_______.txt

    ddc.tokens.by-decade+genre+pos.txt
         DDC query: count(* #sep) #by[date/10,textClass~s/:.*//,]
         Symlink  : count____sep___by_date_10_textClass_s________.txt

    ddc.tokens.by-decade+pos.txt
         DDC query: count(* #sep) #by[date/10,]
         Symlink  : count____sep___by_date_10__.txt

    ddc.tokens.by-genre.txt
         DDC query: count(* #sep) #by[textClass~s/:.*//]
         Symlink  : count____sep___by_textClass_s_______.txt

    ddc.tokens.by-genre+pos.txt
         DDC query: count(* #sep) #by[textClass~s/:.*//,]
         Symlink  : count____sep___by_textClass_s________.txt

    ddc.tokens.by-pos.txt
         DDC query: count(* #sep) #by[]
         Symlink  : count____sep___by__.txt

    extra.urldomains.n.txt
         Shell command: wc -l < ddc.files.by-urldomain.txt

        OPTIONAL, requires "ddc.files.by-urldomain.txt", enabled by default
        if "STATS_VARIANT
        <http://kaskade.dwds.de/dstar/doc/README_config.html#STATS_VARIANT>
        = web". See mantis #52445
        <https://mantis.dwds.de/mantis/view.php?id=52445>.

    extra.urldomains.top-20.txt
         Shell command: sort -nr -k1 ddc.files.by-urldomain.txt | head -n20

        OPTIONAL, requires "ddc.files.by-urldomain.txt", enabled by default
        if "STATS_VARIANT
        <http://kaskade.dwds.de/dstar/doc/README_config.html#STATS_VARIANT>
        = web". See mantis #52445
        <https://mantis.dwds.de/mantis/view.php?id=52445>.

    indexed.stamp
         Shell command: /bin/ls -1 ../ddc_index/*/*._con | xargs -n1 date +'%FT%TZ' -ur | sort | tail -n1

        File modification time ("mtime") of youngest physical subcorpus
        contributing to "stats/" DDC queries. Should be identical to the
        "indexed" attribute returned by a DDC "info" request
        <https://kaskade.dwds.de/~moocow/software/ddc/ddc_proto.html#info>
        to the appropriate "ddc_daemon" process, as also reported by
        "details.perl#basic".

    lexdb.wordlike.txt
         LexDB SQL query: SELECT sum(f) FROM w WHERE w REGEXP '^[[:alnum:]]+(?:-[[:alnum:]]+)*$'

        Should approximate the total number of "word-like" tokens in the
        corpus. Only present if a "lexdb" database was compiled.

   Templates
    The "*.ttk" files in the corpus/web directory are Template Toolkit
    <http://www.template-toolkit.org/> template files instantiated by the
    "dstar.perl" script.

   Other files
    In addition to the the aforemention files and directories, the
    corpus/web directory contains the following files:

     dstar.css      # local css stylesheet
     dstar.js       # local javascript hacks
     jquery*.js     # local copy of jQuery API; see http://jquery.com/
     jquery-ui*     # local copy of jQuery-UI API; see http://jqueryui.com/
     purl.js        # local copy or purl URL-parser; see https://github.com/allmarkedup/purl
     Makefile       # (DEVEL) Makefile for initialization and installation rules
     README.*       # (DEVEL) this REAMDE file in various formats

  Aliases and Rewrites
    If the apache "mod_rewrite" module is availble, the following rewrite
    rules should be enanbled in "site.rc" for each URL directory alias "".""
    in the D* make variable "WEB_SITE_ALIAS" (ususally "/dstar/*CORPUS*
    <http://kaskade.dwds.de/dstar/doc/README_config.html#CORPUS>/"):

    "./query" => "ddc-cgi.perl"
    "./search" => "dstar.perl"
    "./lizard" => "lizard.perl"
    "./hist" => "hist.perl"
    "./tcf" => "tcf.perl"
    "./status" => "ddc-cgi.perl""?mode=req&q=status"
    "./vstatus" => "ddc-cgi.perl""?mode=req&q=vstatus"
    "./info" => "ddc-cgi.perl""?mode=req&q=info"
    "./details" => "details.perl"
    "./config" => "config.perl"
    "./config-(all|auth|env|site|stash)" => "config.perl""?fmt=$1"
    "./diacollo/profile" => "diacollo/profile.perl"
    "./lexdb/view" => "lexdb/view.perl"
    "./lexdb/export" => "lexdb/export.perl"
    "./lexdb/suggest" => "lexdb/suggest.perl"
    "./semcloud/(cats|books|docs|pages|terms)" => semcloud/$1.perl (~
    "semcloud/semq.perl?to=$1")
    "./semcloud/(query|semq)" => "semcloud/semq.perl"
    "./doc" => "//odo.dwds.de/~moocow/software/ddc/"
    "./privacy" => "../privacy"
    "./imprint" => "../imprint"

SEE ALSO
    See also the top-level ddc-dstar README
    <http://kaskade.dwds.de/dstar/doc/README.html> file in SVN under
    "svn+ssh://svn.dwds.de/home/svn/dev/ddc-dstar/trunk/doc/README.txt" and
    the references mentioned there.

AUTHOR
    Bryan Jurish <jurish@bbaw.de> created these web wrappers by adapting the
    relevant portions of the OpenSearch wrapper API used for the Deutsches
    Textarchiv (dta).

