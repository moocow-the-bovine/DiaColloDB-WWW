    README for DiaColloDB::WWW

ABSTRACT
    DiaColloDB::WWW - www wrapper scripts and utitilties for DiaColloDB
    diachronic collocation database

REQUIREMENTS
    CGI Available from CPAN.

    Cwd Available from CPAN.

    DiaColloDB
        For low-level index access, available from CPAN.

    Encode
        Available from CPAN.

    ExtUtils::MakeMaker
        Available from CPAN.

    File::Copy::Recursive
        Available from CPAN.

    File::MimeInfo
        Available from CPAN.

    File::ShareDir
        Available from CPAN.

    File::ShareDir::Install
        Available from CPAN.

    File::chmod::Recursive
        Available from CPAN.

    HTTP::Daemon
        Available from CPAN.

    HTTP::Message
        Available from CPAN.

    POSIX
        Available from CPAN.

    Socket
        Available from CPAN.

    Template
        Available from CPAN.

    Time::HiRes
        Available from CPAN.

    URI Available from CPAN.

    URI::Escape
        Available from CPAN.

    (an existing DiaColloDB index to query)
        See dcdb-create.perl(1) from the DiaColloDB distribution for
        details.

DESCRIPTION
    The DiaColloDB::WWW package provides a set of Perl modules and wrapper
    scripts implementing a simple webservice API for DiaColloDB indices,
    including a simple user interface and online visualization.

INSTALLATION
    Issue the following commands to the shell:

     bash$ cd DiaColloDB-WWW-0.01 # (or wherever you unpacked this distribution)
     bash$ perl Makefile.PL       # check requirements, etc.
     bash$ make                   # build the module
     bash$ make test              # (optional): test module before installing
     bash$ make install           # install the module on your system

USAGE
    Assuming you have a raw text corpus you'd like to access via this
    module, the following steps will be required:

  Corpus Annotation and Conversion
    Your corpus must be tokenized and annotated with whatever word-level
    attributes and/or document-level metadata you wish to be able to query;
    in particular document date is required. See "SUBCLASSES" in
    DiaColloDB::Document for a list of currently supported corpus formats.

  DiaCollo Index Creation
    You will need to compile a DiaColloDB index for your corpus. This can be
    accomplished using the dcdb-create.perl(1) script from the DiaColloDB
    distribution.

  WWW Wrappers
    The proper domain of this distribution is to mediate between a
    high-level user interface running in a web browser and the DiaColloDB
    index API itself. Utilities are provided for accomplishing this task in
    the following two ways:

   ... as a Standalone Server
    Once you have a DiaCollo index, you can access it by running the
    standalone server script dcdb-www-server.perl(1) included in this
    distribution.

   ... or via an External HTTP Server
    Alternately, you can use the dcdb-www-create.perl(1) script from this
    distribution to bootstrap a wrapper directory for use with an external
    webserver such as apache <http://httpd.apache.org/>. You will need to
    manually configure your webserver for the directory thus created.

    In either case, additional configuration will be necessary if you wish
    to have access to the corpus KWIC-link function, which requires a
    running DDC Server <http://sourceforge.net/projects/ddc-concordance/>
    and corresponding web wrappers for corpus searching.

SEE ALSO
    *   The user help page for the DiaColloDB::WWW wrappers at
        <http://kaskade.dwds.de/diacollo/help.perl>.

    *   The CLARIN-D DiaCollo Showcase at
        <http://clarin-d.de/de/kollokationsanalyse-in-diachroner-perspektive
        > contains a brief example-driven tutorial on using the
        DiaColloDB::WWW wrappers (in German).

    *   The DiaColloDB::WWW and DiaColloDB documentation.

AUTHOR
    Bryan Jurish <moocow@cpan.org>

