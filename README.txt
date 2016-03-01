    README for DiaColloDB::WWW

ABSTRACT
    DiaColloDB::WWW - www wrapper scripts and utitilties for DiaColloDB
    diachronic collocation database

REQUIREMENTS
    DiaColloDB
        For low-level index access, available from CPAN.

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

AUTHOR
    Bryan Jurish <moocow@cpan.org>

